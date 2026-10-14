# iTerm2 triggers worth adding (Settings ▸ Profiles ▸ zsh-config ▸ Advanced ▸ Triggers ▸ Edit)

Triggers can't be shipped in the dynamic profile file reliably across iTerm2 versions, so add these by hand once.
Each is regex → action. Tick "Use interpolated strings" only if noted.

| Regex | Action | Why |
|---|---|---|
| `\b(error|fail(ed|ure)?|traceback|panic|fatal)\b` | Highlight Text (red) | spot failures in long output |
| `^(BUILD SUCCESSFUL\|✓ .* passed\|All tests passed)` | Post Notification: `Build done` | long builds while you're in another app |
| `Enter passphrase\|\[sudo\] password` | Prompt to Enter Password… | (needs a saved password; skip if unsure) |
| `(https?://\S+)` | Make Hyperlink | ⌘-click any URL |
| `^\s*File "(.+)", line (\d+)` | Make Hyperlink → `\1:\2` | jump to Python traceback lines (needs ⌘-click "best editor" in the profile) |
| `^(zagent\|\?\?)` | Set Mark | every `??` question becomes a jumpable mark (⌘⇧↑) |

Marks from shell integration (command boundaries) already exist — `zs-iterm status` tells you whether they're active.
