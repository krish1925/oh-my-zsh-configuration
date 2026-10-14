# Global screenshot hotkey — Shortcuts.app setup

This is a one-time, manual setup in macOS Shortcuts.app (GUI steps, can't be scripted).
Everything it calls (`zshot`) is already installed and tested.

## Setup (about 2 minutes)

1. Open **Shortcuts.app** (built into macOS, in Applications).
2. Click **+** to create a new shortcut. Name it something like **"Screenshot for ??"**.
3. Search the action library for **"Run Shell Script"** and drag it into the shortcut.
4. In the action:
   - Shell: `/bin/zsh`
   - Input: **Nothing** (clear the default "Shortcut Input")
   - Paste this as the script:
     ```sh
     /Users/YOU/.config/zsh/bin/zshot region
     /usr/bin/osascript -e 'display notification "Ask: ?? what is this" with title "screenshot ready"'
     ```
5. Click the shortcut's settings (the **ⓘ** icon in the top-right of the editor).
6. Check **"Use as Quick Action"** → **"Add Keyboard Shortcut"**, then press the key
   combo you want, e.g. **⌃⌥⌘S** (Control+Option+Command+S — unlikely to collide with
   anything else).
7. Close the editor. Press your hotkey from anywhere (Finder, a browser, any app).

## What happens when you press it

- The screen dims slightly and your cursor becomes a crosshair — drag to select a region
  (same as ⌘⇧4). Press **Esc** to cancel.
- A notification appears: "screenshot ready".
- Switch to your terminal and ask **any** `??` question within 2 minutes (`ZAH_PENDING_MAX_S`,
  default 120s) — the next `??` picks up the pending screenshot automatically, whatever you
  type. `??` prints `↳ using your screenshot from Ns ago` when it does. Wait longer than 2
  minutes and it expires (`??` says so and drops it) — take a fresh one instead.

## First-time permission prompt

The **first time** you run this shortcut, macOS will ask **Shortcuts.app** for **Screen
Recording** permission (System Settings → Privacy & Security → Screen Recording). Grant
it and re-run the shortcut once — the first attempt after granting permission sometimes
needs a retry. This is a one-time prompt.

If you *also* run `shot`/`??shot` directly from your terminal (Terminal.app or Ghostty),
that app gets its own separate Screen Recording prompt the first time, since macOS grants
this permission per-app, not system-wide.

## Variants

- **Window instead of region**: change `zshot region` to `zshot window` — click a window
  instead of dragging a box.
- **Full screen**: `zshot full` — no interaction, captures immediately.
- **Skip the notification**: delete the `osascript` line if you find it noisy.
- **skhd instead of Shortcuts**: if you already use `skhd` (`brew install skhd`) for other
  hotkeys, add one line to `~/.skhdrc`:
  ```
  ctrl + alt + cmd - s : /Users/YOU/.config/zsh/bin/zshot region
  ```
  then `skhd --start-service`. This needs Accessibility permission for `skhd` instead of
  Screen Recording for Shortcuts — grant it in System Settings → Privacy & Security →
  Accessibility.

## Troubleshooting

- **Nothing happens when you press the hotkey**: check System Settings → Keyboard →
  Keyboard Shortcuts → Services (or App Shortcuts) — another app may already own that
  combo. Pick a different one in step 6.
- **"zshot: cannot create ..."**: rare, means `$HOME/.cache` isn't writable. Check
  `ls -la ~/.cache`.
- **The screenshot never gets picked up by `??`**: it expires after `ZAH_SHOT_MAX_AGE_MIN`
  (default 10 minutes) — take a fresh one if it's been a while, or just use `??shot`
  directly instead of the hotkey + typing `??` separately.
