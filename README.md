# Death end re;Quest Resolution Patcher

An unofficial patch for the Steam version of Death end re;Quest (the first game).

- **Menu fix:** On a 2560x1440 monitor, the game shows 2560x1440 as available
  but won't let you select it. This is an off-by-one bug in the menu code,
  and the patch corrects it.
- **4K supersampling (optional):** The game normally renders at 1080p and
  stretches the picture unless you own a 4K monitor. This unlocks its
  3840x2160 render mode on smaller monitors and scales it down to fit,
  which sharpens characters, text, and UI considerably.

The patcher is a single PowerShell script. It contains no game code, checks
every byte before changing it, keeps a backup, and can undo itself.

Tested on one machine: 2560x1440, Full Screen mode. Not affiliated with
Idea Factory or Compile Heart.

The reverse engineering and the patcher script were done with Claude
Fable 5.2 (Anthropic); testing in the game was done by hand.
