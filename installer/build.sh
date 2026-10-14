#!/bin/zsh
# Build "Zsh Config" disk image from the live config in ~/.config/zsh, ~/.zshrc, ~/.p10k.zsh.
#   ./build.sh [version]        → dist/Zsh-Config-<version>.dmg
# Re-run any time the config changes. Fails (no DMG kept) if the leak scan finds personal data.
setopt ERR_EXIT PIPE_FAIL NO_UNSET
HERE=${0:A:h}
VERSION=${1:-$(date +%Y.%m.%d)}
APPNAME="Install Zsh Config.app"
VOL="Zsh Config"
B=$HERE/.build; STAGE=$B/stage; DMGDIR=$B/dmg; DIST=$HERE/dist
APP=$STAGE/$APPNAME; RES=$APP/Contents/Resources; P=$RES/payload
CONF=$HOME/.config/zsh

rm -rf $B; mkdir -p $STAGE $DMGDIR $DIST $APP/Contents/MacOS $P/config-zsh

# ---- personal-data scan: files AND file names ---------------------------------------------
leak_scan() {   # <dir> → prints hits, returns 1 if any
  local dir=$1 pat hits
  pat="kpatel|krish|patel|gmail|/Users/[A-Za-z]|$(hostname -s)|$(id -un)|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{30,}|xox[bp]-|hf_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY"
  # names are checked relative to $dir: the absolute build path itself contains the username
  hits=$( { grep -rIiE -- $pat $dir 2>/dev/null; (cd $dir && find . -print | grep -iE -- $pat | sed 's/^/FILENAME: /'); } | grep -v '/Users/YOU' || true)
  [[ -z $hits ]] && return 0
  print -r -- "$hits" | cut -c1-200; return 1
}

# ---- payload -------------------------------------------------------------------------------
print "==> assembling payload from $CONF"
rsync -rlp \
  --exclude='*.zwc' --exclude='__pycache__/' --exclude='.DS_Store' --exclude='*.pyc' \
  --exclude='/agent/tests/' --exclude='/agent/bench/' --exclude='/agent/evals/' \
  --exclude='/agent/*PLAN*.md' --exclude='/agent/*REVIEW*.md' --exclude='/agent/BACKLOG.md' \
  --exclude='/RELIABILITY.md' --exclude='/agent/vault/' --exclude='/uninstall.sh' \
  $CONF/ $P/config-zsh/

# AI-memory vault: written from clean templates, never copied — whatever you have remembered stays on your Mac
V=$P/config-zsh/agent/vault; mkdir -p $V/inbox $V/archive $V/notes
cat > $V/SOUL.md <<'EOF'
You are ??, a terse terminal copilot on the user's Mac. Plain text, no markdown.
Prefer checking with tools over guessing. Say "I don't know" rather than invent.
Commands go through propose_command; you never run anything for real.
EOF
cat > $V/USER.md <<'EOF'
# About the user
<!-- edited via /remember --me, or by hand. Cap: 1200 chars (see MEMORY.md's comment for
     the same refuse-not-truncate behavior). New facts about the same subject replace the
     old line instead of piling up. -->
EOF
cat > $V/MEMORY.md <<'EOF'
<!-- Facts written via /remember (inside ?? mode) or ai-memory. Cap: 2000 chars, enforced
     on write (a fact that would push this over the cap is refused, not silently truncated).
     No automatic supersession/dedup yet — if you replace a fact, delete the old line by hand.
     The model never writes here directly. -->
EOF
cat > $V/MOC.md <<'EOF'
<!-- Map of Content: an index of vault/notes/*.md. Only THIS FILE (titles + one line each)
     goes into every ?? system prompt; note BODIES are read on demand via the read_note tool.
     Cap: 600 chars. Add a line here when you add a note. -->
EOF
touch $V/inbox/.keep $V/archive/.keep $V/notes/.keep

cp $HOME/.zshrc $P/zshrc
sed -i '' 's/ · kpatel · M4 Pro 24GB · / · /' $P/zshrc                     # header line
sed -i '' '/^# Added by Antigravity CLI installer$/,$d' $P/zshrc            # a tool's PATH line with a hardcoded home dir
cp $HOME/.p10k.zsh $P/p10k.zsh
cp $HOME/.config/ghostty/config $P/ghostty-config
print -r -- $VERSION > $P/VERSION

# any hardcoded home directory or first name left in docs/comments → neutral wording (files touched are listed)
for f in ${(f)"$(grep -rIlE "/Users/kpatel|Krish" $P || true)"}; do
  print "   sanitized: ${f#$P/}"
  sed -i '' -e 's#/Users/kpatel#/Users/YOU#g' -e "s/Krish[’']s/the user's/g" $f
done

print "==> leak scan (payload)"
leak_scan $P || { print -u2 "\nLEAK SCAN FAILED — nothing built."; exit 1 }
print "   clean"

# dev-only paths referenced by shipped code?  (informational)
print "==> references from shipped code to files that were left out:"
grep -rnE 'agent/(tests|evals|bench)|RELIABILITY\.md|[A-Z_]+_PLAN\.md|BACKLOG\.md' $P/config-zsh --include='*.zsh' --include='*.py' 2>/dev/null | cut -c1-170 || true

# ---- the app bundle -----------------------------------------------------------------------
cp $HERE/src/install.sh $HERE/src/install.command $RES/
cp $HERE/src/launcher.sh $APP/Contents/MacOS/ZshConfig
chmod +x $RES/install.sh $RES/install.command $APP/Contents/MacOS/ZshConfig $P/config-zsh/bin/* 2>/dev/null || true
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Install Zsh Config</string>
  <key>CFBundleDisplayName</key><string>Install Zsh Config</string>
  <key>CFBundleIdentifier</key><string>local.zshconfig.installer</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>ZshConfig</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF

print "==> icon"
if python3 $HERE/src/icon.py $B/icon.png; then
  IS=$B/AppIcon.iconset; mkdir -p $IS
  for s in 16 32 128 256 512; do
    sips -z $s $s $B/icon.png --out $IS/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) $B/icon.png --out $IS/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $IS -o $RES/AppIcon.icns && print "   ok"
else
  print "   (icon generation failed — building without one)"
fi

xattr -cr $STAGE                                    # no download-origin or Finder metadata riding along
codesign --force --deep -s - $APP 2>&1 | sed 's/^/   /'   # ad-hoc: intact-seal only, not notarized

# ---- disk image ---------------------------------------------------------------------------
print "==> disk image"
cp -R $APP $DMGDIR/
cp $HERE/src/README.txt "$DMGDIR/Read Me First.txt"
RW=$B/rw.dmg; OUT=$DIST/Zsh-Config-$VERSION.dmg
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -volname $VOL -srcfolder $DMGDIR -fs HFS+ -format UDRW -ov $RW >/dev/null
hdiutil attach $RW -readwrite -noverify -noautoopen -mountpoint "/Volumes/$VOL" >/dev/null
# window layout is cosmetic and needs Finder scripting permission — best effort, 30 s cap
perl -e 'alarm 30; exec @ARGV' osascript <<EOF >/dev/null 2>&1 || print "   (Finder layout skipped — icons use the default arrangement)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 760, 460}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set position of item "$APPNAME" of container window to {160, 150}
    set position of item "Read Me First.txt" of container window to {400, 150}
    close
    delay 1
  end tell
end tell
EOF
rm -rf "/Volumes/$VOL/.fseventsd" "/Volumes/$VOL/.Trashes" 2>/dev/null || true
sync
hdiutil detach "/Volumes/$VOL" -quiet
rm -f $OUT
hdiutil convert $RW -format UDZO -imagekey zlib-level=9 -o $OUT >/dev/null
print "   $OUT  ($(du -h $OUT | cut -f1))"

# ---- verify the FINISHED image, not the staging folder -----------------------------------
print "==> verifying the image"
MNT=$B/mnt; mkdir -p $MNT
hdiutil attach $OUT -readonly -nobrowse -noautoopen -mountpoint $MNT >/dev/null
trap 'hdiutil detach $MNT -quiet 2>/dev/null || true' EXIT
codesign --verify --deep --strict "$MNT/$APPNAME" && print "   code signature intact"
leak_scan $MNT || { print -u2 "LEAK SCAN FAILED on the finished image"; rm -f $OUT; exit 1 }
print "   image contents: no personal data"

T=$(mktemp -d)                                      # throwaway HOME: your real files are never touched
print -r -- "# my old zshrc" > $T/.zshrc
print "   install into a scratch HOME ($T):"
HOME=$T ZC_YES=1 ZC_SKIP_DEPS=1 /bin/zsh "$MNT/$APPNAME/Contents/Resources/install.sh" 2>&1 | sed 's/^/     /'
[[ -f $T/.config/zsh/ai.zsh && -f $T/.p10k.zsh && -f $T/.zshrc.local && -f $T/.config/zsh/agent/vault/SOUL.md ]] || { print -u2 "install left files missing"; exit 1 }
grep -q "my old zshrc" $T/.zsh-config-backup/*/.zshrc                       && print "   old ~/.zshrc was backed up"
HOME=$T zsh -n $T/.zshrc                                                     && print "   ~/.zshrc parses"
for f in $T/.config/zsh/*.zsh; do zsh -n $f || { print -u2 "syntax error: $f"; exit 1 }; done && print "   all modules parse"
python3 -m py_compile $T/.config/zsh/agent/*.py $T/.config/zsh/agent/servers/*.py && print "   agent code compiles"
print "   interactive shell on the installed copy (plugins download on first start; up to 4 min):"
LOADOUT=$(HOME=$T perl -e 'alarm 240; exec @ARGV' /bin/zsh -i -c 'for f in zsh-setup zsh-doctor ai-winnow ai-decide ai-memory _zdec _zdec_swapped _zs_triage _zai_privacy_gate _zai_danger2 _zdw_ensure; do (( $+functions[$f] )) || print "MISSING $f"; done; print LOADED; ai-winnow status; zsh-doctor 2>&1 | grep -E "decider|division|error"' 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
print -r -- "$LOADOUT" | grep -E 'LOADED|MISSING|down|decider' | sed 's/^/     /'
[[ $LOADOUT == *LOADED* && $LOADOUT != *MISSING* && $LOADOUT == *decider* && $LOADOUT != *"division by zero"* ]] || { print -u2 "installed copy did not load cleanly:"; print -r -- "$LOADOUT" | tail -15 >&2; exit 1 }
print "   the decision commands exist and fall back cleanly with no Winnow installed"
print "   uninstall from the scratch HOME:"
HOME=$T ZC_YES=1 /bin/zsh $T/.config/zsh/uninstall.sh 2>&1 | sed 's/^/     /'
[[ "$(<$T/.zshrc)" == "# my old zshrc" && ! -e $T/.config/zsh && ! -e $T/.p10k.zsh ]] && print "   uninstall restored the original state"
rm -rf $T

print "\nDONE → $OUT"
