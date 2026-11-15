@echo off
setlocal
title Death end re;Quest resolution patcher

rem Put this file and Patch-DerqResolutionMenu.ps1 together in
rem the game's resource\bin folder (next to Application.exe)
rem then double-click this file. Close the game first.

set "SCRIPT=%~dp0Patch-DerqResolutionMenu.ps1"

if not exist "%SCRIPT%" (
    echo Could not find Patch-DerqResolutionMenu.ps1 next to this file.
    echo Both files need to be in the same folder as Application.exe.
    echo.
    pause
    exit /b 1
)

rem Anything typed after the file name is passed straight through, for example:
rem   Patch-DerqResolutionMenu.bat -Supersample -Label "4K SSAA"
if not "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
    goto done
)

echo.
echo   1  Menu fix + supersampling  (4K render on this monitor)
echo   2  Menu fix only
echo   3  Restore the original file
echo   4  Quit
echo.
choice /c 1234 /n /m "Pick 1, 2, 3 or 4: "

if errorlevel 4 exit /b 0
if errorlevel 3 goto restore
if errorlevel 2 goto menuonly

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Supersample
goto done

:menuonly
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
goto done

:restore
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Restore
goto done

:done
echo.
pause
endlocal
