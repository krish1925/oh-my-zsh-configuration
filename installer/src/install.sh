#!/bin/zsh
# Zsh Config — installer and uninstaller.
#
#   install.sh        install (this is what "Install Zsh Config.app" runs in Terminal)
#   uninstall.sh      put back the shell setup you had before (a copy lives in ~/.config/zsh/)
#
# Test switches:  ZC_YES=1  never prompt (answers default)   ZC_SKIP_DEPS=1  skip Xcode tools / Homebrew / zsh-setup

SELF=${0:A}
HERE=${SELF:h}
PAYLOAD=$HERE/payload
BKROOT=$HOME/.zsh-config-backup

b=$'\e[1m'; g=$'\e[32m'; y=$'\e[33m'; r=$'\e[31m'; z=$'\e[0m'
step() { print; print -r -- "${b}==> $*${z}" }
ok()   { print -r -- "  ${g}✓${z} $*" }
warn() { print -r -- "  ${y}!${z} $*" }
die()  { print; print -r -- "  ${r}✗ $*${z}"; [[ -n $ZC_YES ]] || { print; read -r "?Press Return to close… " }; exit 1 }
ask()  {   # ask "question" y|n  → 0 = yes
  [[ -n $ZC_YES ]] && { [[ $2 == y ]]; return }
  local a hint='[y/N]'; [[ $2 == y ]] && hint='[Y/n]'
  read -r "a?  $1 $hint "
  a=${a:-$2}; [[ $a == [yY]* ]]
}

# ============================================================== uninstall
uninstall() {
  print -r -- "${b}Zsh Config — uninstall${z}"
  local first
  first=( $BKROOT/[0-9]*(N/) ); first=$first[1]        # oldest backup = your setup from before the first install
  [[ -n $first && -f $first/manifest ]] || die "No backup found in $BKROOT — nothing to restore."
  print; print -r -- "This puts back what you had before (backup: ${first:t}) and moves the Zsh Config files"
  print -r -- "aside into $BKROOT/removed-<time>/ — nothing is deleted."
  print -r -- "Kept untouched: your history, AI memory database, downloaded models, ~/.zshrc.local."
  ask "Continue?" y || { print "Cancelled."; exit 0 }

  local removed=$BKROOT/removed-$(date +%Y%m%d-%H%M%S) kind item cur
  mkdir -p $removed
  while read -r kind item; do
    cur=$HOME/$item
    if [[ -e $cur || -L $cur ]]; then mkdir -p $removed/${item:h}; mv $cur $removed/$item; fi
    if [[ $kind == backup ]]; then mkdir -p ${cur:h}; cp -RP $first/$item $cur; ok "restored ~/$item"
    else ok "removed ~/$item"; fi
  done < $first/manifest
  rm -f $HOME/.zshrc.zwc
  print; print -r -- "Done. Open a new Terminal window."
  [[ -n $ZC_YES ]] || { print; read -r "?Press Return to close… " }
  exit 0
}
[[ ${SELF:t} == uninstall.sh || $1 == --uninstall ]] && uninstall

# ============================================================== install
[[ -d $PAYLOAD ]] || die "Installer files are missing ($PAYLOAD). Re-download the disk image."
VERSION=$(<$PAYLOAD/VERSION)

clear 2>/dev/null
print -r -- "${b}Zsh Config $VERSION${z}"
print -r -- "
A fast, colourful zsh with smart history, click-to-move cursor, a command palette,
and a private AI assistant that runs entirely on this Mac (nothing is sent anywhere).

This installer will:
  • install Apple's command line tools and Homebrew if you don't have them
  • back up your current ~/.zshrc, ~/.p10k.zsh and ~/.config/zsh first
  • install the config, then the tools it uses (eza, bat, fzf, atuin, ripgrep, jq, …)
  • ask before downloading the local AI model (~5.5 GB)

Your existing ~/.zshrc.local, shell history and Ghostty config are never overwritten."

mac=$(sw_vers -productVersion); arch=$(uname -m)
(( ${mac%%.*} >= 13 )) || die "macOS 13 or newer is required (this Mac runs $mac)."
[[ $arch == arm64 ]] || warn "This is an Intel Mac: the shell works, but the local AI features need Apple Silicon."
print
ask "Ready to install?" y || { print "Cancelled — nothing was changed."; exit 0 }

# ---- 1. Xcode command line tools + Homebrew ---------------------------
find_brew() {
  local p; for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x $p ]] && { eval "$($p shellenv)"; return 0 }
  done; return 1
}
if [[ -z $ZC_SKIP_DEPS ]]; then
  step "1/6  Apple command line tools"
  if xcode-select -p &>/dev/null; then ok "already installed"
  else
    print "  A macOS window is about to ask you to install them — click Install and wait (a few minutes)."
    xcode-select --install &>/dev/null
    until xcode-select -p &>/dev/null; do sleep 5; done
    ok "installed"
  fi
  step "2/6  Homebrew"
  if find_brew; then ok "already installed"
  else
    ask "Homebrew (the macOS package manager) is not installed. Install it now? It asks for your password." y ||
      die "Homebrew is required — the config's tools come from it."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew install failed."
    find_brew || die "Homebrew installed but 'brew' was not found."
    ok "installed"
  fi
else
  step "1-2/6  skipped (ZC_SKIP_DEPS)"
fi

# ---- 3. Back up, then install the files -------------------------------
step "3/6  Installing the config"
BK=$BKROOT/$(date +%Y%m%d-%H%M%S)
mkdir -p $BK && : >| $BK/manifest || die "Cannot create $BK"
snap() {   # snap <path relative to ~> — remember what was there before we overwrite it
  local item=$1 src=$HOME/$1
  if [[ -e $src || -L $src ]]; then
    mkdir -p $BK/${item:h} && cp -RP $src $BK/$item && print -r -- "backup $item" >> $BK/manifest
  else
    print -r -- "created $item" >> $BK/manifest
  fi
}
snap .zshrc; snap .p10k.zsh; snap .config/zsh
cp $PAYLOAD/zshrc $HOME/.zshrc                          || die "Could not write ~/.zshrc"
cp $PAYLOAD/p10k.zsh $HOME/.p10k.zsh                    || die "Could not write ~/.p10k.zsh"
mkdir -p $HOME/.config/zsh
# code is replaced; the things you edit or that hold your data (plugin list, AI memory vault) are only created once
rsync -rlp --exclude=/plugins.txt --exclude=/agent/vault/ $PAYLOAD/config-zsh/ $HOME/.config/zsh/ || die "Copy failed"
rsync -rlp --ignore-existing $PAYLOAD/config-zsh/plugins.txt $HOME/.config/zsh/
rsync -rlp --ignore-existing $PAYLOAD/config-zsh/agent/vault/ $HOME/.config/zsh/agent/vault/
cp $SELF $HOME/.config/zsh/uninstall.sh && chmod +x $HOME/.config/zsh/uninstall.sh $HOME/.config/zsh/bin/* 2>/dev/null
rm -f $HOME/.zshrc.zwc $HOME/.config/zsh/*.zwc(N)          # stale compile caches must not shadow the new files
ok "~/.zshrc, ~/.p10k.zsh, ~/.config/zsh"

if [[ ! -e $HOME/.zshrc.local ]]; then
  cat > $HOME/.zshrc.local <<'EOF'
# Your private overrides — the installer never touches this file.
# Anything in the header of ~/.zshrc marked "override in ~/.zshrc.local" goes here. Examples:
#   ZAI_MODEL=mlx-community/Qwen3.5-4B-MLX-4bit   # smaller local model for 8–16 GB Macs
#   ZSH_CD_HINTS=0                                 # no project summary when entering a repo
#   ZSH_NOTIFY_AFTER=30                            # notify when a command runs longer than 30 s
EOF
  ok "created ~/.zshrc.local (yours to edit)"
fi
if [[ ! -e $HOME/.config/ghostty/config ]]; then
  snap .config/ghostty/config
  mkdir -p $HOME/.config/ghostty && cp $PAYLOAD/ghostty-config $HOME/.config/ghostty/config
  ok "Ghostty settings installed"
else
  ok "kept your existing Ghostty config"
fi
print -r -- "  ${b}backup of your old setup:${z} $BK"

# ---- 4-5. Tools --------------------------------------------------------
if [[ -z $ZC_SKIP_DEPS ]]; then
  step "4/6  Core tools"
  for f in antidote uv; do
    brew list --formula $f &>/dev/null && ok "$f present" || { brew install $f && ok "$f installed" || warn "$f failed — run: brew install $f"; }
  done
  print
  if [[ -z $ZC_SKIP_FONT ]] && ask "Install the Meslo Nerd Font (the prompt and file icons need it in Terminal/iTerm; Ghostty has its own)?" y; then
    brew install --cask font-meslo-lg-nerd-font && ok "font installed" || warn "font failed — run: brew install --cask font-meslo-lg-nerd-font"
  fi

  step "5/6  Setting up the shell tools and the local AI"
  print -r -- "  (this runs the config's own  zsh-setup  — it may ask about the model download and Ghostty)"; print
  /bin/zsh -ic zsh-setup || warn "zsh-setup did not finish — open a new terminal and run:  zsh-setup"
else
  step "4-5/6  skipped (ZC_SKIP_DEPS)"
fi

# ---- 6. Optional: raise the GPU memory limit for the big model ---------
step "6/6  Optional"
plist=$HOME/.config/zsh/launchd/local.iogpu-wired-limit.plist
if [[ $arch == arm64 && -f $plist && ! -f /Library/LaunchDaemons/local.iogpu-wired-limit.plist ]] &&
   (( $(sysctl -n hw.memsize) >= 24 * 1024 * 1024 * 1024 )); then
  print -r -- "  The deep model (??? / ????) runs best with a higher GPU memory limit (19 GB). It costs nothing while"
  print -r -- "  unused and is reversible, but needs your password once. Most people can skip this."
  if ask "Raise the GPU memory limit?" n; then
    sudo cp $plist /Library/LaunchDaemons/ && sudo chown root:wheel /Library/LaunchDaemons/local.iogpu-wired-limit.plist &&
      sudo launchctl load /Library/LaunchDaemons/local.iogpu-wired-limit.plist && ok "done" || warn "skipped (failed)"
  fi
else
  ok "nothing to do"
fi

# ---- done --------------------------------------------------------------
print -r -- "
${g}${b}All set.${z}

  ?  <what you want>     the AI writes a command onto your prompt (never runs it)
  ?? <question>          the AI answers, with read-only tools
  zhelp                  cheat sheet          Ctrl+G   command palette
  zsh-doctor             health check

  Undo everything:  zsh ~/.config/zsh/uninstall.sh
"
[[ -n $ZC_YES ]] && exit 0
read -r "?Press Return to start your new shell… "
exec /bin/zsh -l
