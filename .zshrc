#!/usr/bin/env zsh
# =====================================================
# ENHANCED ZSH CONFIGURATION
# Optimized for performance, functionality, and maintainability
# =====================================================

# ===== PERFORMANCE SETTINGS (MUST BE FIRST) =====
# These settings significantly improve startup time
DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"
ZLE_RPROMPT_INDENT=0

if [[ -n "${TERM_PROGRAM}" ]]; then
  case "${TERM_PROGRAM}" in
    "vscode") POWERLEVEL9K_INSTANT_PROMPT=off ;;
    "iTerm.app") POWERLEVEL9K_TERM_SHELL_INTEGRATION=true ;;
  esac
fi

# Path to your Oh My Zsh installation
export ZSH="$HOME/.oh-my-zsh"

# ===== INSTANT PROMPT (MUST BE EARLY) =====
# Enable Powerlevel10k instant prompt - must be before any console output
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===== THEME CONFIGURATION =====
ZSH_THEME="powerlevel10k/powerlevel10k"

# Powerlevel10k performance settings
POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS=0.1
POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=4096
POWERLEVEL9K_VCS_STAGED_MAX_NUM=10
POWERLEVEL9K_VCS_UNSTAGED_MAX_NUM=10

# If you have font issues, uncomment this line:
# POWERLEVEL9K_MODE='compatible'
# Disable gap filler to prevent width issues


# ===== OH MY ZSH SETTINGS =====
# Case-insensitive completion
CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"

# Auto-update behavior
zstyle ':omz:update' mode disabled  # We disabled auto-update for performance

# Enable command auto-correction
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# ===== OPTIMIZED HISTORY CONFIGURATION =====
HISTFILE="$HOME/.zsh_history"
HISTSIZE=1000000
SAVEHIST=1000000
HIST_STAMPS="yyyy-mm-dd"

# Robust history settings
setopt EXTENDED_HISTORY          # Save timestamp and duration
setopt INC_APPEND_HISTORY        # Write immediately
setopt SHARE_HISTORY             # Share between sessions
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicates first
setopt HIST_IGNORE_DUPS          # Don't record immediate duplicates
setopt HIST_IGNORE_ALL_DUPS      # Delete old recorded duplicates
setopt HIST_FIND_NO_DUPS         # Don't show duplicates in search
setopt HIST_IGNORE_SPACE         # Don't record commands starting with space
setopt HIST_SAVE_NO_DUPS         # Don't write duplicates
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks
setopt HIST_VERIFY               # Don't execute immediately on expansion

# ===== PLUGIN CONFIGURATION =====
# Note: zsh-syntax-highlighting must be last!
plugins=(
  git                    # Git aliases and functions
  z                      # Jump to frecent directories
  fzf                    # Fuzzy finder integration
  docker                 # Docker completion
  kubectl                # Kubernetes completion
  pip                    # Python pip completion
  npm                    # npm completion
  sudo                   # Press ESC twice to add sudo
  copypath               # Copy current path to clipboard
  copyfile               # Copy file contents to clipboard
  dirhistory             # Navigate directory history with ALT-LEFT/RIGHT
  jsontools              # JSON pretty printing
  macos                  # macOS specific utilities
  web-search             # Search web from terminal
  colored-man-pages      # Colorful man pages
  command-not-found      # Suggest package to install
  extract                # Extract any archive with `extract`
  history-substring-search # Search history with up/down arrows
  zsh-autosuggestions    # Fish-like autosuggestions
  zsh-syntax-highlighting # MUST BE LAST - Fish-like syntax highlighting
)

# ===== ZSH AUTOSUGGESTIONS OPTIMIZATION =====
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#3a3a3a"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
ZSH_AUTOSUGGEST_COMPLETION_IGNORE="git *"

# Source Oh My Zsh
source $ZSH/oh-my-zsh.sh

# ===== SMART COMPLETION CONFIGURATION =====
# Optimized completion loading
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

autoload -Uz bashcompinit && bashcompinit

# Enhanced completion options
setopt COMPLETE_IN_WORD    # Complete from both ends
setopt ALWAYS_TO_END       # Move cursor to end
setopt PATH_DIRS           # Perform path search on commands with /
setopt AUTO_MENU           # Show completion menu on successive tab
setopt AUTO_LIST           # Automatically list choices
setopt AUTO_PARAM_SLASH    # Add trailing slash for directories
setopt EXTENDED_GLOB       # Extended globbing
setopt NO_CASE_GLOB        # Case insensitive globbing
setopt NUMERIC_GLOB_SORT   # Sort filenames numerically
setopt NO_BEEP             # No beep on error
setopt MENU_COMPLETE       # Auto highlight first element

# Advanced completion styling
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/completion-cache"

# Better kill completion
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# SSH/SCP/RSYNC host completion
zstyle ':completion:*:(ssh|scp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:(ssh|scp|rsync):*' group-order users files all-files hosts-domain hosts-host hosts-ipaddr

# ===== PATH CONFIGURATION =====
# Deduplicate PATH entries
typeset -U path
path=(
  /Users/kpatel/.codeium/windsurf/bin
  /opt/homebrew/opt/openjdk/bin
  /opt/homebrew/bin
  /usr/local/bin
  $HOME/.local/bin
  $HOME/bin
  $path
)
export PATH

# ===== ENVIRONMENT VARIABLES =====
export LANG=en_US.UTF-8
export EDITOR='nvim'
export VISUAL="$EDITOR"
export LESS='-R -F -g -i -J -M -W -x4'
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export PYTORCH_ENABLE_MPS_FALLBACK=1

# ===== LS COLORS =====
# Enable colors for ls
export CLICOLOR=1
# Set custom colors for different file types
export LSCOLORS=exfxcxdxbxegedabagacad

# ===== FZF CONFIGURATION =====
# Better fzf defaults with preview support
export FZF_DEFAULT_OPTS='
  --height 40% --layout=reverse --border
  --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9
  --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9
  --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6
  --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4
  --bind="ctrl-/:toggle-preview"
  --bind="ctrl-u:preview-half-page-up"
  --bind="ctrl-d:preview-half-page-down"'

# Use fd for better performance if available
if command -v fd > /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

  # Preview with bat if available
  if command -v bat > /dev/null; then
    export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}'"
    export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -200'"
  fi
fi

# ===== SMART DIRECTORY NAVIGATION =====
setopt AUTO_CD              # Auto cd without typing cd
setopt AUTO_PUSHD           # Push current directory on stack
setopt PUSHD_IGNORE_DUPS    # No duplicates in stack
setopt PUSHD_SILENT         # No directory stack after pushd/popd
setopt CDABLE_VARS          # Change directory to a path in variable

# Disable spelling correction
unsetopt correct
unsetopt correct_all

# ===== ENHANCED ALIASES =====
# Better ls
alias ls='ls --color=auto'
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alt'
alias ltr='ls -altr'
alias lsize='ls -lhSr'  # Sort by size

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -pv'

# Shortcuts
alias h='history'
alias j='jobs -l'
alias which='type -a'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%T"'
alias nowdate='date +"%Y-%m-%d"'
alias week='date +%V'

# Enhanced Git aliases
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gl='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
alias gd='git diff'
alias gds='git diff --staged'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch -vv'
alias gf='git fetch --all --prune'
alias gm='git merge'
alias gcp='git cherry-pick'
alias grb='git rebase'
alias gst='git stash'
alias gstp='git stash pop'
alias gprune='git remote prune origin'

# System info
alias df='df -H'
alias du='du -ch'
alias top='htop 2>/dev/null || top'
alias free='free -h'

# ===== ENHANCED FUNCTIONS =====

# Smarter cd: if target is a file, cd to its directory
cd() {
  if [[ -f "$1" ]]; then
    builtin cd "$(dirname "$1")"
  else
    builtin cd "$@"
  fi
}

# Make directory and cd into it with error handling
mkcd() {
  [[ -z "$1" ]] && { echo "Usage: mkcd <directory>" >&2; return 1; }

  if [[ -d "$1" ]]; then
    echo "Directory exists, changing to it..."
    cd "$1"
  else
    mkdir -p "$1" && cd "$1" && echo "Created and changed to: $(pwd)"
  fi
}

# Enhanced directory picker with preview
fcd() {
  local dir
  dir=$(fd --type d ${1:-.} 2>/dev/null | fzf \
    --preview 'tree -C -L 2 {} | head -200' \
    --preview-window=right:50% \
    --header="Navigate to directory") && cd "$dir"
}

# Enhanced git branch switcher with preview
fbr() {
  git rev-parse HEAD > /dev/null 2>&1 || { echo "Not in git repo" >&2; return 1; }

  local branches branch
  branches=$(git branch --all --color=always --sort=-committerdate | grep -v HEAD)
  branch=$(echo "$branches" |
    fzf --ansi --preview 'git log -n 10 --color=always --oneline --graph $(sed "s/.* //" <<< {})' \
    --preview-window=right:60% |
    sed "s/.* //" | sed "s#remotes/[^/]*/##")

  [[ -n "$branch" ]] && git checkout "$branch"
}

# Smart commit with analysis (unalias first to avoid conflict)
unalias gcmsg 2>/dev/null
gcmsg() {
  git diff --cached --quiet && { echo "No staged changes"; return 1; }

  local files_changed=$(git diff --cached --name-only | wc -l | tr -d ' ')
  local stats=$(git diff --cached --stat 2>/dev/null | tail -1)
  local insertions=$(echo "$stats" | grep -o '[0-9]* insertion' | awk '{print $1}')
  local deletions=$(echo "$stats" | grep -o '[0-9]* deletion' | awk '{print $1}')

  echo "Changes: $files_changed files, +${insertions:-0}/-${deletions:-0} lines"

  local msg
  if [[ $files_changed -eq 1 ]]; then
    local filename=$(git diff --cached --name-only | head -1)
    msg="Update $(basename "$filename")"
  else
    msg="Update $files_changed files"
  fi

  echo "Suggested: $msg"
  read "user_msg?Enter message (or press Enter for suggestion): "
  git commit -m "${user_msg:-$msg}"
}

# Enhanced history search with fzf
hist() {
  local selected
  selected=$(fc -rl 1 | fzf --tac --no-sort \
    --preview 'echo {}' \
    --preview-window up:3:hidden:wrap \
    --bind 'ctrl-/:toggle-preview' \
    --header="Search history") &&
  print -z "$(echo "$selected" | sed 's/^ *[0-9]* *//')"
}

# Git log search
unalias glog 2>/dev/null # <-- FIX: Remove alias from git plugin to avoid conflict
glog() {
  git log --oneline --color=always |
    fzf --ansi --preview 'git show --color=always {1}' \
    --preview-window=right:60% \
    --bind 'enter:execute(git show {1})'
}

# Directory bookmarks
export BOOKMARKS_DIR="$HOME/.local/share/zsh/bookmarks"
[[ ! -d "$BOOKMARKS_DIR" ]] && mkdir -p "$BOOKMARKS_DIR"

bookmark() {
  local name="${1:-$(basename "$PWD")}"
  ln -sf "$PWD" "$BOOKMARKS_DIR/$name"
  echo "Bookmarked $PWD as '$name'"
}

jump() {
  local bookmark
  if [[ -n "$1" ]]; then
    [[ -L "$BOOKMARKS_DIR/$1" ]] && cd "$(readlink "$BOOKMARKS_DIR/$1")" || echo "Bookmark not found"
  else
    bookmark=$(find "$BOOKMARKS_DIR" -type l -printf '%f\n' 2>/dev/null | fzf --header="Jump to bookmark") &&
    cd "$(readlink "$BOOKMARKS_DIR/$bookmark")"
  fi
}

# Quick notes function
note() {
  local notes_dir="$HOME/notes"
  [[ ! -d "$notes_dir" ]] && mkdir -p "$notes_dir"

  if [[ -n "$1" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$notes_dir/quick-notes.md"
    echo "Note saved!"
  else
    ${EDITOR:-vim} "$notes_dir/quick-notes.md"
  fi
}

# Extract any archive
extract() {
  if [ -f "$1" ]; then # <-- FIX: Quoted variable
    case "$1" in # <-- FIX: Quoted variable
      *.tar.bz2)   tar xjf "$1"     ;;
      *.tar.gz)    tar xzf "$1"     ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar e "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xf "$1"      ;;
      *.tbz2)      tar xjf "$1"     ;;
      *.tgz)       tar xzf "$1"     ;;
      *.zip)       unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *)     echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}


# History maintenance
hist-backup() {
  local backup_dir="$HOME/.local/share/zsh/history-backups"
  [[ ! -d "$backup_dir" ]] && mkdir -p "$backup_dir"
  cp "$HISTFILE" "$backup_dir/zsh_history.$(date +%Y%m%d_%H%M%S)"
  echo "History backed up"
}

hist-clean() {
  local temp_hist="$HISTFILE.tmp"
  tac "$HISTFILE" | awk '!seen[$0]++' | tac > "$temp_hist" &&
  mv "$temp_hist" "$HISTFILE"
  echo "History cleaned and deduplicated"
}

# ===== KEY BINDINGS =====
# History search with arrows
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Ctrl+R for fzf history
bindkey '^R' hist

# Accept autosuggestion
bindkey '^ ' autosuggest-accept      # Ctrl+Space
bindkey '^[[F' autosuggest-accept    # End key

# Alt+Enter to accept and execute
bindkey '^[^M' autosuggest-execute

# Home/End navigation
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

# Delete key
bindkey '^[[3~' delete-char

# ===== LAZY LOADING SECTION =====
# Load these only when needed for faster startup

# Conda lazy initialization (moved after instant prompt)
conda() {
  unset -f conda
  __conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
  if [ $? -eq 0 ]; then
    eval "$__conda_setup"
  else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
      . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
      export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
  fi
  unset __conda_setup
  conda "$@"
}

# NVM lazy loading
nvm() {
  unset -f nvm
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  nvm "$@"
}

# Load fzf last (after instant prompt)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# ===== FINAL CUSTOMIZATIONS =====
# Load machine-specific settings if they exist
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Load p10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Override p10k gap settings AFTER loading the config
typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=''
typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''

# Force reload p10k with new settings
if [[ -n $POWERLEVEL9K_VERSION ]]; then
  p10k reload
fi

# Welcome message (keep it simple for performance)
if [[ -o interactive ]]; then
  echo "Welcome back, $(whoami)! Today is $(date '+%A, %B %d')"
fi