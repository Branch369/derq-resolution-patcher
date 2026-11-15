<#
.SYNOPSIS
    Unofficial resolution patcher for Death end re;Quest (GOG, the first game).
    1. Fixes the Options > Screen resolution menu so 2560x1440 can be selected
       on a 2560x1440 monitor.
    2. Optional (-Supersample): lets a monitor smaller than 4K use the game's
       3840x2160 render mode, scaled down to the monitor (supersampling).

.DESCRIPTION
    This script edits Application.exe in place. It contains no game code, only
    file offsets and the bytes to put there. It checks every byte before it
    replaces it, keeps a backup named Application.exe.bak next to the game file,
    and changes nothing if the file is not the build it expects.

    SUPPORTED BUILD
    Application.exe with SHA-256
    C526DD98FBA0F43B9FAE7FE9F88EAC506355DCFFA82408072DC721A6443DF221
    (the GOG build this was developed against, November 2026). On any other
    build the byte checks fail and the script stops without writing.

    The Steam release has not been tested. Its Application.exe may be a
    different file, in which case the script will report a mismatch and leave
    it alone. If it happens to be byte-compatible at the patched locations, the
    script will say so and patch it.

    BACKGROUND: HOW THE GAME PICKS RESOLUTIONS
    The game has a fixed list of 13 resolutions, numbered 0 to 12:

         0  640x360      5  1280x720     10  2560x1440
         1  720x405      6  1360x765     11  3840x2160
         2  800x450      7  1366x768     12  4K Native
         3  1024x576     8  1600x900
         4  1152x648     9  1920x1080

    It works out which entry matches your monitor (call it the native index)
    and allows entries up to that one. It renders at 1920x1080 for every entry
    except 12, which renders at 3840x2160. Entries 10 and 11 are a 1080p render
    stretched to a bigger window.

    THE MENU FIX (always applied)
    The code that draws the menu marks 2560x1440 as available when the native
    index is 10 or higher. The code that moves the selection asks for 11 or
    higher. On a 1440p monitor the native index is exactly 10, so the entry is
    drawn as available and then cannot be reached with the keyboard or clicked
    with the mouse. Two small patches make both follow the drawing code's rule.
    Entries the monitor cannot show stay blocked.

    SUPERSAMPLING (-Supersample)
    Entry 12 is the only way to get a render above 1080p, and the game refuses
    it unless the monitor is 4K. It also takes the window size from the same
    list, so simply forcing entry 12 on a smaller monitor would open a
    3840x2160 window that hangs off the screen.

    This option changes three things:
      - Entries 11 and 12 get your monitor's size as their window size.
        Entry 12 still renders at 3840x2160; that part is not touched.
      - The two routines that find the native index are told to prefer the
        highest matching entry. With the change above they pick entry 12, so
        the game unlocks it by its own rules.
      - Entry 12 is renamed in the menu, from "4K Native" to "4K SSAA"
        (or whatever you pass with -Label).

    Result: pick "4K SSAA" and the game renders at 3840x2160 and scales the
    picture down to your monitor. Entry 11, "3840x2160", becomes a duplicate of
    your native size, so it cannot open an oversized window.

    WHAT HAS AND HAS NOT BEEN TESTED
    Confirmed in the game on one machine: the GOG release on a 2560x1440
    monitor in Full Screen mode, menu fix and supersampling both working. Windowed and Borderless
    modes, other monitor sizes, and multi-monitor setups have not been tried.

    THINGS TO KNOW
      - Rendering at 3840x2160 is four times the pixels of 1080p. Expect a
        matching drop in frame rate.
      - The game only draws 16:9. On an ultrawide or 16:10 monitor the picture
        will be stretched, as it already is in the unpatched game.
      - With -Supersample and no saved settings, the game starts in entry 12.
      - GOG Galaxy's "Verify / Repair" and game updates put the original
        Application.exe back. Run the script again afterwards.
      - Not affiliated with or endorsed by Idea Factory or Compile Heart.
        Use at your own risk.

.PARAMETER Path
    Full path to Application.exe. If omitted, the script looks for
    Application.exe in its own folder, so the easy route is to put this script
    in the game's resource\bin folder and run it there.

.PARAMETER Supersample
    Also apply the supersampling changes described above.

.PARAMETER Width
    Width of your monitor in real pixels, for -Supersample. If Width and Height
    are omitted, the script reads the primary monitor. Pass both if the game
    runs on a different monitor.

.PARAMETER Height
    Height of your monitor in real pixels, for -Supersample. See Width.

.PARAMETER Label
    Menu name for entry 12 when -Supersample is used. Default "4K SSAA".
    The game stores the name in a 16-byte slot, so it can be at most 15 plain
    ASCII characters. "4K Supersample" fits, but fills its menu box edge to edge.

.PARAMETER Restore
    Copy Application.exe.bak back over Application.exe, undoing everything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Patch-DerqResolutionMenu.ps1

    Applies the menu fix only.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Patch-DerqResolutionMenu.ps1 -Supersample

    Applies the menu fix and supersampling for the primary monitor.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Patch-DerqResolutionMenu.ps1 -Supersample -Width 2560 -Height 1440 -Label "4K Supersample"

    Same, with the monitor size and menu name given by hand.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Patch-DerqResolutionMenu.ps1 -Restore

    Puts the original file back.

.NOTES
    Running the script again is safe. It reports what is already applied and
    only writes what is missing. To change the monitor size or the menu name,
    run it again with the new values.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Supersample,
    [int]$Width,
    [int]$Height,
    [string]$Label = '4K SSAA',
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = 5

# SHA-256 of the untouched Application.exe this patch was made from.
$OriginalSha256 = 'C526DD98FBA0F43B9FAE7FE9F88EAC506355DCFFA82408072DC721A6443DF221'

# ---------------------------------------------------------------------------------
# Patch data
#
# Offset is a position in the file on disk. VA is the same place as a debugger or
# disassembler shows it (image base 0x140000000), given so the patches can be
# checked independently. "Native index" below is the 32-bit value at VA 0x140F5850C:
# the list entry the game matched to the monitor.
#
# Old is what must be in the file before patching, New is what replaces it. Old and
# New always have the same length, so nothing in the file moves.
# ---------------------------------------------------------------------------------

$MenuPatches = @(
    @{
        # VA 0x1407C6C84, in the handler for the Right key on the second menu row.
        # Decides whether the selection may leave 1920x1080 for the third row.
        #   was:  cmp eax, 0Bh     ; native index < 11 -> stay
        #   now:  cmp eax, 0Ah     ; native index < 10 -> stay
        Name   = 'Menu, keyboard: Right from 1920x1080 reaches 2560x1440'
        Offset = 0x7C6084
        Old    = '83 F8 0B'
        New    = '83 F8 0A'
    },
    @{
        # VA 0x1407C6BB1, in the mouse-click handler for the third menu row.
        # ebp = entry clicked (0 = 2560x1440, 1 = 3840x2160, 2 = 4K Native),
        # r15d = entry selected before the click, ebx = result.
        #   was:  mov ebx, r15d
        #         cmp dword [native index], 0Bh
        #         cmovge ebx, ebp            ; any entry, but only at 11 or higher
        #         xor ecx, ecx / call ... / jmp ...
        #   now:  mov ebx, r15d
        #         cmp ebp, 1
        #         sbb eax, eax
        #         add eax, 0Bh               ; eax = 10 for entry 0, 11 for the others
        #         cmp dword [native index], eax
        #         cmovge ebx, ebp            ; same thresholds the drawing code uses
        #         jmp short +2               ; to an identical xor / call / jmp that
        #                                    ; already follows, which frees the bytes
        Name   = 'Menu, mouse: click on the third row follows the availability rule'
        Offset = 0x7C5FB1
        Old    = '41 8B DF 83 3D 51 19 79 00 0B 0F 4D DD 33 C9 E8 4B BD CB FF EB 1A'
        New    = '41 8B DF 83 FD 01 19 C0 83 C0 0B 39 05 4A 19 79 00 0F 4D DD EB 02'
    }
)

# The game finds the native index in two near-identical routines, one run at startup
# and one run from the window procedure. Each has two loops over the list: for a
# desktop narrower than 3840 it scans upward and keeps the first of equal matches,
# otherwise it scans downward and keeps the last. Removing the branch makes it always
# scan downward, so when entries 10, 11 and 12 all have the monitor's size it settles
# on 12. A real 4K monitor already took the downward path, so nothing changes there.
$SupersamplePatches = @(
    @{
        # VA 0x140484FAA    was: jl +5Fh    now: nop, nop
        Name   = 'Supersample: startup monitor match prefers the highest entry'
        Offset = 0x4843AA
        Old    = '7C 5F'
        New    = '90 90'
    },
    @{
        # VA 0x1404854AA    was: jl +5Fh    now: nop, nop
        Name   = 'Supersample: running monitor match prefers the highest entry'
        Offset = 0x4848AA
        Old    = '7C 5F'
        New    = '90 90'
    }
)

# Resolution list entries 11 and 12 (VA 0x140F58778; the list starts at 0x140F58720).
# Stored as width, height, width, height, each a 32-bit little-endian number.
# The game uses these for the window size only. The 3840x2160 render size of entry 12
# is hard-coded elsewhere and is keyed on the entry number, so it survives this change.
$TableOffset   = 0xF56978
$TableOriginal = '00 0F 00 00 70 08 00 00 00 0F 00 00 70 08 00 00'   # 3840, 2160, 3840, 2160

# Menu name of entry 12 (VA 0x140C3AA78): ASCII text followed by zero bytes, in a
# 16-byte slot. The next string starts right after it, hence the 15-character limit.
$LabelOffset   = 0xC39478
$LabelSlotSize = 16

# ---------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------

function ConvertTo-ByteArray([string]$Hex) {
    # '83 F8 0B' -> byte[] (0x83, 0xF8, 0x0B)
    $parts = $Hex.Trim() -split '\s+'
    $bytes = New-Object byte[] $parts.Length
    for ($i = 0; $i -lt $parts.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($parts[$i], 16)
    }
    return ,$bytes
}

function Test-BytesAt([byte[]]$Data, [int]$Offset, [byte[]]$Expected) {
    # True if $Data contains exactly $Expected at $Offset.
    if ($Offset + $Expected.Length -gt $Data.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Data[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

function Get-LabelAt([byte[]]$Data, [int]$Offset, [int]$Size) {
    # Returns the text in the slot, or $null if the slot is not
    # "printable ASCII, then only zero bytes" (which would mean a different build).
    $text = ''
    $ended = $false
    for ($i = 0; $i -lt $Size; $i++) {
        $b = $Data[$Offset + $i]
        if ($ended) {
            if ($b -ne 0) { return $null }
        }
        elseif ($b -eq 0) {
            $ended = $true
        }
        elseif ($b -ge 0x20 -and $b -le 0x7E) {
            $text += [char]$b
        }
        else {
            return $null
        }
    }
    if (-not $ended -or $text.Length -eq 0) { return $null }
    return $text
}

function Get-PrimaryMonitorSize {
    # Size of the primary monitor in real pixels. Without the DPI-awareness call,
    # Windows reports a scaled-down size to this process whenever display scaling
    # is above 100%, and the patch would be written with the wrong numbers.
    $source = @'
using System;
using System.Runtime.InteropServices;
public static class DerqScreenProbe {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
'@
    if (-not ('DerqScreenProbe' -as [type])) {
        Add-Type -TypeDefinition $source
    }
    [void][DerqScreenProbe]::SetProcessDPIAware()
    $w = [DerqScreenProbe]::GetSystemMetrics(0)   # SM_CXSCREEN
    $h = [DerqScreenProbe]::GetSystemMetrics(1)   # SM_CYSCREEN
    return @($w, $h)
}

# ---------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------

Write-Host "Death end re;Quest resolution patcher, version $ScriptVersion"

# --- locate the game file ---------------------------------------------------------
if (-not $Path) {
    $Path = Join-Path $PSScriptRoot 'Application.exe'
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Host "Could not find the game file at: $Path" -ForegroundColor Red
    Write-Host 'Put this script in the resource\bin folder inside the game folder, next to Application.exe,'
    Write-Host 'or pass the location with -Path "C:\...\Application.exe".'
    exit 1
}
$Path   = (Resolve-Path -LiteralPath $Path).Path
$Backup = "$Path.bak"

# --- restore ------------------------------------------------------------------------
if ($Restore) {
    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
        Write-Host "No backup found at: $Backup" -ForegroundColor Red
        Write-Host 'GOG Galaxy can also put the original back: Manage installation > Verify / Repair.'
        exit 1
    }
    Copy-Item -LiteralPath $Backup -Destination $Path -Force
    Write-Host 'Original file restored from backup.' -ForegroundColor Green
    exit 0
}

# --- inspect ------------------------------------------------------------------------
# The hash is informational. What decides whether a patch is applied is the bytes at
# its offset, which lets the script run again on a file it has already patched.
$hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
Write-Host "File:    $Path"
Write-Host "SHA-256: $hash"
if ($hash -eq $OriginalSha256) {
    Write-Host 'This is the untouched build the patch was made from.'
}
else {
    Write-Host 'Not the untouched build (already patched, or a different build). Checking the specific bytes...'
}

[byte[]]$data = [System.IO.File]::ReadAllBytes($Path)

$wanted = @() + $MenuPatches
if ($Supersample) { $wanted += $SupersamplePatches }

# Everything is checked first and collected in $todo. Nothing is written until every
# check has passed, so a mismatch can never leave the file half patched.
$todo = @()
foreach ($p in $wanted) {
    $old = ConvertTo-ByteArray $p.Old
    $new = ConvertTo-ByteArray $p.New
    if ($old.Length -ne $new.Length) {
        throw "Internal error: patch '$($p.Name)' changes the length."
    }
    if (Test-BytesAt $data $p.Offset $new) {
        Write-Host "  already applied: $($p.Name)"
    }
    elseif (Test-BytesAt $data $p.Offset $old) {
        Write-Host "  will apply:      $($p.Name)"
        $todo += @{ Offset = $p.Offset; New = $new }
    }
    else {
        Write-Host "  MISMATCH:        $($p.Name)" -ForegroundColor Red
        Write-Host ('The bytes at offset 0x{0:X} are not what this patch expects.' -f $p.Offset) -ForegroundColor Red
        Write-Host 'Nothing was changed. This is probably a different build of the game.' -ForegroundColor Red
        exit 1
    }
}

# --- supersampling: list entries and menu name ----------------------------------------
# The list entries are accepted in two states: the original 3840x2160 pair, or a pair
# of identical sizes written by an earlier run (so the monitor size can be changed).
$curW1 = [BitConverter]::ToUInt32($data, $TableOffset)
$curH1 = [BitConverter]::ToUInt32($data, $TableOffset + 4)
$curW2 = [BitConverter]::ToUInt32($data, $TableOffset + 8)
$curH2 = [BitConverter]::ToUInt32($data, $TableOffset + 12)
$tableIsOriginal = Test-BytesAt $data $TableOffset (ConvertTo-ByteArray $TableOriginal)
$tableLooksSane  = ($curW1 -eq $curW2) -and ($curH1 -eq $curH2) -and
                   ($curW1 -ge 640) -and ($curW1 -le 3840) -and ($curH1 -ge 360) -and ($curH1 -le 2160)

if ($Supersample) {
    if (-not $tableLooksSane) {
        Write-Host '  MISMATCH:        Supersample: resolution list entries 11 and 12' -ForegroundColor Red
        Write-Host 'Nothing was changed. This is probably a different build of the game.' -ForegroundColor Red
        exit 1
    }
    if (-not $Width -or -not $Height) {
        try {
            $size   = Get-PrimaryMonitorSize
            $Width  = $size[0]
            $Height = $size[1]
            Write-Host "Primary monitor detected: ${Width}x${Height}"
        }
        catch {
            Write-Host 'Could not read the monitor size. Pass it with -Width and -Height.' -ForegroundColor Red
            exit 1
        }
    }
    if ($Width -lt 640 -or $Height -lt 360) {
        Write-Host "Monitor size ${Width}x${Height} does not look right. Pass -Width and -Height." -ForegroundColor Red
        exit 1
    }
    if ($Width -ge 3840) {
        # The game already offers entry 12 here, and the 4K render would not be scaled down.
        Write-Host 'This monitor is already 4K wide or more, so "4K Native" works without the supersampling change.' -ForegroundColor Yellow
        Write-Host 'Run the script without -Supersample. Nothing was changed.'
        exit 0
    }
    $ratio = $Width * 9 - $Height * 16
    if ($ratio -ne 0) {
        Write-Host "Note: ${Width}x${Height} is not 16:9. The game only draws 16:9, so the picture will be stretched." -ForegroundColor Yellow
    }

    $wb = [BitConverter]::GetBytes([uint32]$Width)
    $hb = [BitConverter]::GetBytes([uint32]$Height)
    [byte[]]$tableNew = $wb + $hb + $wb + $hb

    if (Test-BytesAt $data $TableOffset $tableNew) {
        Write-Host "  already applied: Supersample: entries 11 and 12 use a ${Width}x${Height} window"
    }
    else {
        Write-Host "  will apply:      Supersample: entries 11 and 12 use a ${Width}x${Height} window (was ${curW1}x${curH1})"
        $todo += @{ Offset = $TableOffset; New = $tableNew }
    }

    # Menu name of entry 12.
    if ($Label -notmatch '^[\x20-\x7E]{1,15}$') {
        Write-Host "The label '$Label' will not fit. Use 1 to 15 plain ASCII characters." -ForegroundColor Red
        Write-Host 'Nothing was changed.'
        exit 1
    }
    $currentLabel = Get-LabelAt $data $LabelOffset $LabelSlotSize
    if ($null -eq $currentLabel) {
        Write-Host '  MISMATCH:        Supersample: menu name of entry 12' -ForegroundColor Red
        Write-Host 'Nothing was changed. This is probably a different build of the game.' -ForegroundColor Red
        exit 1
    }
    if ($currentLabel -ceq $Label) {
        Write-Host "  already applied: Supersample: entry 12 is named '$Label'"
    }
    else {
        # Zero-filled slot with the new text at the start, so the text stays terminated.
        $labelNew = New-Object byte[] $LabelSlotSize
        $labelText = [System.Text.Encoding]::ASCII.GetBytes($Label)
        [Array]::Copy($labelText, 0, $labelNew, 0, $labelText.Length)
        Write-Host "  will apply:      Supersample: entry 12 renamed '$currentLabel' -> '$Label'"
        $todo += @{ Offset = $LabelOffset; New = $labelNew }
    }
}
else {
    if (-not $tableIsOriginal) {
        Write-Host "  note: supersampling is already in this file (${curW1}x${curH1}). Left as it is; use -Restore to remove it."
    }
    if ($PSBoundParameters.ContainsKey('Label') -or $PSBoundParameters.ContainsKey('Width') -or $PSBoundParameters.ContainsKey('Height')) {
        Write-Host '  note: -Label, -Width and -Height only take effect together with -Supersample.' -ForegroundColor Yellow
    }
}

if ($todo.Count -eq 0) {
    Write-Host 'Everything requested is already applied. Nothing to do.' -ForegroundColor Green
    exit 0
}

# --- back up, then write --------------------------------------------------------------
# An existing backup is never overwritten: it is the copy closest to the original.
if (Test-Path -LiteralPath $Backup) {
    Write-Host "Keeping the existing backup: $Backup"
}
else {
    if ($hash -ne $OriginalSha256) {
        Write-Host 'Note: the backup being made now is of an already modified file.' -ForegroundColor Yellow
    }
    Copy-Item -LiteralPath $Path -Destination $Backup
    Write-Host "Backup written: $Backup"
}

foreach ($t in $todo) {
    [Array]::Copy($t.New, 0, $data, $t.Offset, $t.New.Length)
}

try {
    [System.IO.File]::WriteAllBytes($Path, $data)
}
catch {
    Write-Host "Could not write the file: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Close the game first. If the game lives under Program Files, run this from an elevated PowerShell.'
    exit 1
}

$newHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
Write-Host "New SHA-256: $newHash"
Write-Host ''
Write-Host 'Patched.' -ForegroundColor Green
if ($Supersample) {
    Write-Host "In the game: Options > Screen resolution, pick '$Label', then Apply."
    Write-Host 'If the picture or the mouse is off, pick another entry, or run this script with -Restore.'
}
else {
    Write-Host 'In the game: Options > Screen resolution, highlight 1920x1080, press Right.'
}
Write-Host 'To undo everything: run this script again with -Restore.'
