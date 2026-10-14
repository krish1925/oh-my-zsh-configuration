#!/bin/bash
# "Install Zsh Config.app" — opens Terminal and runs the installer there.
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
/usr/bin/xattr -dr com.apple.quarantine "$RES" 2>/dev/null   # files from a downloaded image would otherwise trigger a second Gatekeeper prompt
chmod +x "$RES/install.command" "$RES/install.sh" 2>/dev/null
exec /usr/bin/open -a Terminal "$RES/install.command"
