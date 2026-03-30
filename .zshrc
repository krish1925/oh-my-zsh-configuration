#!/usr/bin/env zsh
# =====================================================
# OPTIMIZED ZSH CONFIGURATION — kpatel M4 Pro 24GB
# Ghostty + OMZ + Powerlevel10k + kollzsh
# Target: <200ms startup · 100% local · Catppuccin Mocha
# Last updated: March 2026
# =====================================================

# ===== PERFORMANCE SETTINGS (MUST BE FIRST) =====

DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"
ZSH_DISABLE_COMPFIX=true
ZLE_RPROMPT_INDENT=0

# ===== TERMINAL-SPECIFIC SETTINGS =====
if [[ -n "${TERM_PROGRAM}" ]]; then
  case "${TERM_PROGRAM}" in
    "vscode")      POWERLEVEL9K_INSTANT_PROMPT=off ;;
    "iTerm.app")   POWERLEVEL9K_TERM_SHELL_INTEGRATION=true ;;
    "ghostty")     ;;  # Ghostty handles shell integration via config
  esac
fi

# Path to Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# ===== INSTANT PROMPT (MUST BE EARLY) =====
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===== THEME =====
ZSH_THEME="powerlevel10k/powerlevel10k"

# Powerlevel10k performance optimizations
POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS=0.1
POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=4096
POWERLEVEL9K_VCS_STAGED_MAX_NUM=10
POWERLEVEL9K_VCS_UNSTAGED_MAX_NUM=10
POWERLEVEL9K_DISABLE_HOT_RELOAD=true
POWERLEVEL9K_VCS_BACKENDS=(git)
POWERLEVEL9K_TRANSIENT_PROMPT=always

# ===== OH MY ZSH SETTINGS =====
CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"
zstyle ':omz:update' mode disabled
DISABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
ZSH_COMPDUMP="$ZSH_CACHE_DIR/.zcompdump"

# ===== HISTORY =====
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
HIST_STAMPS="yyyy-mm-dd"
LISTMAX=0

setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY

# ===== ZSH AUTOSUGGESTIONS CONFIG (before plugins load) =====
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
ZSH_AUTOSUGGEST_USE_ASYNC=1                  # FIX: was missing, caused blocking suggestions

# ===== ZSH SYNTAX HIGHLIGHTING CONFIG (before plugins load) =====
# NOTE: fast-syntax-highlighting replaces zsh-syntax-highlighting
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
ZSH_HIGHLIGHT_MAXLENGTH=512

# ===== PLUGIN LIST =====
# Order is critical — deviations cause subtle breakage
plugins=(
  git                          # Lightweight, useful aliases
  colored-man-pages            # Free, built-in OMZ
  sudo                         # ESC ESC prepends sudo
  fzf-tab                      # MUST be before autosuggestions
  zsh-autosuggestions          # Fish-like inline suggestions
  zsh-autopair                 # Auto-close brackets/parens/quotes
  you-should-use               # Reminds you of existing aliases
  forgit                       # fzf-powered interactive git
  kollzsh                      # Ctrl+O → local LLM completions
  zsh-autoswitch-virtualenv    # Auto-activate .venv on cd
  zsh-completions              # 100+ extra completions (mlx-lm, uv, etc.)
  history-substring-search     # Up-arrow = mid-string history search
  fast-syntax-highlighting     # MUST be last (replaces zsh-syntax-highlighting)
)

# ===== OPTIMIZED COMPINIT (ONCE DAILY) =====
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
autoload -Uz bashcompinit && bashcompinit

# ===== SOURCE OH MY ZSH =====
source $ZSH/oh-my-zsh.sh

# Remove annoying safety aliases from OMZ
unalias rm cp mv 2>/dev/null

# ===== POST-PLUGIN CONFIGURATION =====

# --- fzf-tab ---
# Preview dirs with eza, git with delta; switch groups with < >
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --tree --color=always $realpath'
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'

# --- history-substring-search (rebind AFTER OMZ sources) ---
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=green,fg=black,bold'
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=red,fg=white,bold'

# --- you-should-use ---
export YSU_MESSAGE_POSITION='after'
export YSU_MODE=ALL

# --- zsh-autoswitch-virtualenv ---
export AUTOSWITCH_MESSAGE_FORMAT='🐍 %venv_name (%py_version)'

# --- forgit (disable default aliases to avoid collisions with existing ones) ---
export FORGIT_NO_ALIASES=true
alias gifa='forgit::add'
alias gifl='forgit::log'
alias gifd='forgit::diff'
alias gifco='forgit::checkout::file'
alias gifss='forgit::stash::show'
alias gifcb='forgit::checkout::branch'
alias gifcm='forgit::checkout::commit'
alias gifri='forgit::rebase'
alias gifrb='forgit::rebase'
alias gifcp='forgit::cherry-pick'
alias gifcln='forgit::clean'
alias gifix='forgit::fixup'

# --- kollzsh (Ctrl+O → local LLM shell completions via Ollama) ---
KOLLZSH_MODEL='qwen2.5-coder:1.5b'
KOLLZSH_HOTKEY='^o'
KOLLZSH_COMMAND_COUNT=5
KOLLZSH_URL='http://localhost:11434'
KOLLZSH_KEEP_ALIVE='30m'

# ===== PATH CONFIGURATION =====
typeset -U path
path=(
  /Users/kpatel/.codeium/windsurf/bin
  /opt/homebrew/opt/openjdk/bin
  /opt/homebrew/bin
  /usr/local/bin
  $HOME/.local/bin
  $HOME/bin
  $PWD
  $path
)
export PATH

# ===== ENVIRONMENT VARIABLES =====
export LANG=en_US.UTF-8
export EDITOR='nvim'
export VISUAL="$EDITOR"

# Emacs — always terminal mode by default, never spawn GUI window
alias emacs='command emacs -nw'
alias em='emacs'
alias e='emacs'
export LESS='-R -F -g -i -J -M -W -x4'
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export PYTORCH_ENABLE_MPS_FALLBACK=1

# LS Colors
export CLICOLOR=1
export LSCOLORS=exfxcxdxbxegedabagacad
export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# ===== EZA (LS REPLACEMENT) =====
if command -v eza > /dev/null; then
  alias ls='eza --color=always --icons=always --group-directories-first'
  alias ll='eza -l --header --icons=always --git --group-directories-first --time-style=relative'
  alias la='eza -la --header --icons=always --git --group-directories-first'
  alias lt='eza --tree --level=2 --icons=always --group-directories-first'
  alias lta='eza --tree --level=2 --icons=always --group-directories-first -a'
  alias ltree='eza --tree --icons=always --group-directories-first'

  # Time-based
  alias llm='eza -la --icons=always --git --sort=modified --reverse'
  alias llo='eza -la --icons=always --git --sort=oldest'
  alias llc='eza -la --icons=always --git --sort=created'

  # Size-based
  alias lsize='eza -la --icons=always --git --sort=size --reverse'
  alias lsmall='eza -la --icons=always --git --sort=size'

  # Type-specific
  alias ldirs='eza -lD --icons=always'
  alias lfiles='eza -lf --icons=always --git'
  alias lexec='eza -l --icons=always | grep "^-..x"'

  # Git-aware
  alias lgit='eza -la --icons=always --git --git-ignore'
  alias lmod='eza -la --icons=always --git --modified'
else
  alias ls='ls --color=auto'
  alias ll='ls -alFh'
  alias la='ls -A'
  alias lt='ls -alt'
  alias lsize='ls -lhSr'
fi

# ===== BAT (CAT REPLACEMENT) =====
if command -v bat > /dev/null; then
  export BAT_THEME="Catppuccin-mocha"
  export BAT_STYLE="numbers,changes,header,grid"

  alias cat='bat --paging=never'
  alias catt='bat --paging=always'
  alias catp='bat --plain'
  alias catl='bat --language'
  alias batdiff='git diff --name-only --relative --diff-filter=d | xargs bat --diff'

  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT="-c"

  help() {
    "$@" --help 2>&1 | bat --plain --language=help
  }
fi

# ===== ZOXIDE (SMART CD) =====
if command -v zoxide > /dev/null; then
  eval "$(zoxide init zsh)"
  # FIX: removed alias cd='z' — conflicts with custom cd() function below
  alias cdi='zi'         # Interactive zoxide
  alias cdb='z -'        # Go back
  alias cdl='zoxide query -l'
  alias cdr='zoxide remove'
fi

# ===== RIPGREP =====
if command -v rg > /dev/null; then
  # FIX: removed cat > ~/.ripgreprc block — run once manually, not on every shell open
  # One-time setup: mkdir -p ~/.config/ripgrep && cat > ~/.ripgreprc <<'EOF' ... EOF
  export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

  alias rg='rg --smart-case'
  alias rga='rg --hidden --no-ignore'
  alias rgf='rg --files-with-matches'
  alias rgl='rg --files-without-match'
  alias rgc='rg --count'
  alias rgi='rg --ignore-case'
  alias rgpy='rg --type=py'
  alias rgjs='rg --type=js'
  alias rgrs='rg --type=rust'

  rge() {
    local file line
    read -r file line <<< $(rg --line-number --no-heading --color=always "$@" |
      fzf --ansi --delimiter ':' --preview 'bat --color=always {1} --highlight-line {2}' |
      awk -F: '{print $1, $2}')
    [[ -n "$file" ]] && ${EDITOR:-nvim} "+$line" "$file"
  }
fi

# ===== FZF =====
if command -v fzf > /dev/null; then
  source <(fzf --zsh) 2>/dev/null || [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

  if command -v fd > /dev/null; then
    export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"
    _fzf_compgen_path() { fd --hidden --exclude .git . "$1"; }
    _fzf_compgen_dir() { fd --type=d --hidden --exclude .git . "$1"; }
  fi

  # Catppuccin Mocha colors
  export FZF_DEFAULT_OPTS="
    --height=80% --layout=reverse --border --info=inline
    --color=fg:#cdd6f4,bg:#1e1e2e,hl:#f38ba8
    --color=fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8
    --color=info:#cba6f7,prompt:#94e2d5,pointer:#f5e0dc
    --color=marker:#f5e0dc,spinner:#f5e0dc,header:#f38ba8
  "

  if command -v bat > /dev/null; then
    export FZF_CTRL_T_OPTS="
      --walker-skip .git,node_modules,target,.venv
      --preview 'bat -n --color=always --line-range :500 {}'
      --bind 'ctrl-/:change-preview-window(down|hidden|)'
    "
  fi

  if command -v eza > /dev/null; then
    export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
  elif command -v tree > /dev/null; then
    export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -200'"
  fi

  export FZF_CTRL_R_OPTS="
    --preview 'echo {}' --preview-window up:3:hidden:wrap
    --bind 'ctrl-/:toggle-preview'
    --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
    --header 'CTRL-Y to copy to clipboard'
  "

  _fzf_comprun() {
    local command=$1; shift
    case "$command" in
      cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" 2>/dev/null || fzf "$@" ;;
      export|unset) fzf --preview "eval 'echo \${}'" "$@" ;;
      *)            fzf --preview 'bat -n --color=always --line-range :500 {}' "$@" 2>/dev/null || fzf "$@" ;;
    esac
  }

  # macOS: bind Option+C (ç) to fzf-cd-widget
  bindkey "ç" fzf-cd-widget
fi

# ===== FD (FIND REPLACEMENT) =====
if command -v fd > /dev/null; then
  alias find='fd'
  alias fdf='fd --type f'
  alias fdd='fd --type d'
  alias fdx='fd --type x'
  alias fdh='fd --hidden'
  alias fda='fd --hidden --no-ignore'

  fde() {
    local file
    file=$(fd --type f | fzf --preview 'bat --color=always {}')
    [[ -n "$file" ]] && ${EDITOR:-nvim} "$file"
  }
fi

# ===== DELTA (GIT DIFF) =====
if command -v delta > /dev/null; then
  git config --global core.pager delta
  git config --global interactive.diffFilter 'delta --color-only'
  git config --global delta.navigate true
  git config --global delta.light false
  git config --global delta.side-by-side true
  git config --global delta.line-numbers true

  alias gd='git diff | delta'
  alias gds='git diff --staged | delta'
  alias gshow='git show | delta'
fi

# ===== DUST (DU REPLACEMENT) =====
if command -v dust > /dev/null; then
  alias du='dust'
  alias dua='dust -d 1'
  alias dus='dust -r'
  alias dux='dust -X .git -X node_modules -X .venv'
fi

# ===== PROCS (PS REPLACEMENT) =====
if command -v procs > /dev/null; then
  alias ps='procs'
  alias psa='procs --sortd cpu'
  alias psm='procs --sortd mem'
  alias pst='procs --tree'
  alias psw='procs --watch'
  alias psg='procs --search'
fi

# ===== BOTTOM (TOP/HTOP REPLACEMENT) =====
if command -v btm > /dev/null; then
  alias top='btm'
  alias htop='btm'
  alias btm='btm --color default-light'
  alias btmc='btm --basic'
fi

# ===== TEALDEER (TLDR) =====
if command -v tldr > /dev/null; then
  alias tldr='tldr --color=always'
  alias tldru='tldr --update'
  t() { tldr "$@" | bat -l markdown; }
fi

# ===== TOKEI (CODE STATS) =====
if command -v tokei > /dev/null; then
  alias stats='tokei'
  alias statsa='tokei --sort lines'
  alias statsf='tokei --files'
  alias statst='tokei --type'
fi

# ===== HYPERFINE (BENCHMARKING) =====
if command -v hyperfine > /dev/null; then
  alias bench='hyperfine --warmup 3'
  alias benchs='hyperfine --shell=zsh'
  alias bench-zsh='hyperfine "zsh -i -c exit"'
fi

# ===== SD (SED REPLACEMENT) =====
if command -v sd > /dev/null; then
  alias sed='sd'
  replace()     { sd "$1" "$2" "$3"; }
  replace-all() { fd -t f -x sd "$1" "$2"; }
fi

# ===== XH (HTTP CLIENT) =====
if command -v xh > /dev/null; then
  alias http='xh'
  alias https='xh --https'
  alias httpj='xh --json'
  alias httpd='xh --download'
  get()  { xh GET "$@"; }
  post() { xh POST "$@"; }
fi

# ===== GITUI (GIT TUI) =====
if command -v gitui > /dev/null; then
  alias gu='gitui'
  alias gitu='gitui'
fi

# ===== BROOT =====
if command -v broot > /dev/null; then
  alias br='broot'
  alias brt='broot --sizes'
  source ~/.config/broot/launcher/bash/br 2>/dev/null
fi

# ===== CHOOSE (CUT/AWK REPLACEMENT) =====
if command -v choose > /dev/null; then
  alias cut='choose'
  field() { choose "$1"; }
fi

# ===== WATCHEXEC (FILE WATCHER) =====
if command -v watchexec > /dev/null; then
  alias watch='watchexec'
  watchrun() { watchexec -c -r "$@"; }
  watchpy()  { watchexec -e py -c -r "$@"; }
fi

# ===== FNM (FAST NODE MANAGER) =====
# FIX: removed duplicate fnm init that was at line ~968 — one block only
if command -v fnm > /dev/null; then
  eval "$(fnm env --use-on-cd)"
  alias node-install='fnm install'
  alias node-use='fnm use'
  alias node-list='fnm list'
fi

# ===== GREX (REGEX GENERATOR) =====
if command -v grex > /dev/null; then
  regex() { grex "$@"; }
fi

# ===== SILICON (CODE SCREENSHOTS) =====
if command -v silicon > /dev/null; then
  screenshot() { silicon --theme "Catppuccin-mocha" --output "$1.png" "$1"; }
fi

# ===== BANDWHICH (NETWORK MONITOR) =====
if command -v bandwhich > /dev/null; then
  alias netmon='sudo bandwhich'
fi

# ===== ZSH OPTIONS =====
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt CDABLE_VARS

setopt EXTENDED_GLOB
setopt GLOB_DOTS
setopt NO_NOMATCH
setopt NUMERIC_GLOB_SORT

setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt AUTO_MENU
setopt LIST_PACKED

setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt NO_FLOW_CONTROL
setopt MULTIOS
setopt RM_STAR_SILENT

unsetopt CORRECT
unsetopt CORRECT_ALL

# ===== COMPLETION STYLING =====
zstyle ':completion:*' completer _extensions _complete _approximate
zstyle ':completion:*' matcher-list \
  'm:{[:lower:][:upper:]-_}={[:upper:][:lower:]_-}' \
  'r:|[._-]=* r:|=*' \
  'l:|=* r:|=*'
zstyle ':completion:*' list-suffixes
zstyle ':completion:*' expand prefix suffix
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' menu no  # fzf-tab handles the menu

# ===== NAVIGATION ALIASES =====
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# ===== ESSENTIAL ALIASES =====
alias mkdir='mkdir -pv'
alias h='history'
alias j='jobs -l'
alias which='type -a'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%T"'
alias nowdate='date +"%Y-%m-%d"'
alias week='date +%V'

# ===== GIT ALIASES =====
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gl='git log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
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

# ===== SYSTEM ALIASES =====
alias df='df -H'

# ===== USEFUL FUNCTIONS =====

# Unalias anything that would conflict with custom cd
unalias z 2>/dev/null
unalias cd 2>/dev/null

# FIX: removed alias cd='z' (was line 194) — conflicts with this function
# Smarter cd: if target is a file, cd to its directory; otherwise use zoxide
cd() {
  if [[ -f "$1" ]]; then
    builtin cd "$(dirname "$1")"
  elif command -v z > /dev/null; then
    z "$@" 2>/dev/null || builtin cd "$@"
  else
    builtin cd "$@"
  fi
}

# Make directory and cd into it
mkcd() {
  [[ -z "$1" ]] && { echo "Usage: mkcd <directory>" >&2; return 1; }
  if [[ -d "$1" ]]; then
    echo "Directory exists, changing to it..."
    cd "$1"
  else
    mkdir -p "$1" && cd "$1" && echo "Created and changed to: $(pwd)"
  fi
}

# Enhanced directory picker with fzf
fcd() {
  if ! command -v fzf > /dev/null; then echo "fzf not installed" >&2; return 1; fi
  local dir
  if command -v fd > /dev/null; then
    dir=$(fd --type d ${1:-.} 2>/dev/null | fzf \
      --preview 'eza --tree --color=always {} | head -200' \
      --preview-window=right:50% \
      --header="Navigate to directory") && cd "$dir"
  else
    dir=$(find ${1:-.} -type d 2>/dev/null | fzf --header="Navigate to directory") && cd "$dir"
  fi
}

# Enhanced git branch switcher with preview
fbr() {
  if ! command -v fzf > /dev/null; then echo "fzf not installed" >&2; return 1; fi
  git rev-parse HEAD > /dev/null 2>&1 || { echo "Not in git repo" >&2; return 1; }
  local branches branch
  branches=$(git branch --all --color=always --sort=-committerdate | grep -v HEAD)
  branch=$(echo "$branches" |
    fzf --ansi --preview 'git log -n 10 --color=always --oneline --graph $(sed "s/.* //" <<< {})' \
    --preview-window=right:60% |
    sed "s/.* //" | sed "s#remotes/[^/]*/##")
  [[ -n "$branch" ]] && git checkout "$branch"
}

# Smart commit with analysis
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
  if ! command -v fzf > /dev/null; then echo "fzf not installed" >&2; return 1; fi
  local selected
  selected=$(fc -rl 1 | fzf --tac --no-sort \
    --preview 'echo {}' \
    --preview-window up:3:hidden:wrap \
    --bind 'ctrl-/:toggle-preview' \
    --header="Search history") &&
  print -z "$(echo "$selected" | sed 's/^ *[0-9]* *//')"
}

# Git log search
unalias glog 2>/dev/null
glog() {
  if ! command -v fzf > /dev/null; then echo "fzf not installed" >&2; return 1; fi
  git log --oneline --color=always |
    fzf --ansi --preview 'git show --color=always {1}' \
    --preview-window=right:60% \
    --bind 'enter:execute(git show {1})'
}

# Quick notes
note() {
  local notes_dir="$HOME/notes"
  [[ ! -d "$notes_dir" ]] && mkdir -p "$notes_dir"
  if [[ -n "$1" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$notes_dir/quick-notes.md"
    echo "Note saved!"
  else
    ${EDITOR:-nvim} "$notes_dir/quick-notes.md"
  fi
}

# Extract any archive
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"    ;;
      *.tar.gz)    tar xzf "$1"    ;;
      *.bz2)       bunzip2 "$1"    ;;
      *.rar)       unrar e "$1"    ;;
      *.gz)        gunzip "$1"     ;;
      *.tar)       tar xf "$1"     ;;
      *.tbz2)      tar xjf "$1"    ;;
      *.tgz)       tar xzf "$1"    ;;
      *.zip)       unzip "$1"      ;;
      *.Z)         uncompress "$1" ;;
      *.7z)        7z x "$1"       ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Yazi: cd to selected directory on exit
if command -v yazi > /dev/null; then
  function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
fi

# ===== RUST-POWERED COMBO FUNCTIONS =====

# Smart search and edit
search-edit() {
  local file line
  read -r file line <<< $(
    rg --line-number --no-heading --color=always "$@" |
    fzf --ansi \
      --delimiter ':' \
      --preview 'bat --color=always {1} --highlight-line {2}' \
      --preview-window '+{2}/2' |
    awk -F: '{print $1, $2}'
  )
  [[ -n "$file" ]] && ${EDITOR:-nvim} "+$line" "$file"
}
alias se='search-edit'

# Find file and preview
find-preview() {
  fd --type f "$@" |
    fzf --preview 'bat --color=always {}' \
        --bind 'enter:execute(${EDITOR:-nvim} {})'
}
alias fp='find-preview'

# Git log with preview
git-log-preview() {
  git log --oneline --color=always --decorate |
    fzf --ansi \
      --preview 'git show --color=always {1} | delta' \
      --bind 'enter:execute(git show {1} | delta | less -R)'
}
alias glp='git-log-preview'

# Process killer
kill-process() {
  procs |
    fzf --header-lines=1 \
        --preview 'echo {}' \
        --preview-window down:3:wrap |
    awk '{print $1}' |
    xargs -r kill -9
}
alias kp='kill-process'

# Directory size analysis
dir-analysis() {
  dust -d 3 -r "${1:-.}" |
    fzf --ansi --preview 'eza --tree --level=2 --color=always $(echo {} | awk "{print \$NF}")'
}
alias da='dir-analysis'

# Code statistics
code-stats() {
  tokei --sort lines "${1:-.}" | bat -l yaml
}
alias cs='code-stats'

# Benchmark comparison
compare-commands() {
  hyperfine --warmup 3 "$@" | bat -l markdown
}
alias cmp='compare-commands'

# Network connections
net-connections() {
  procs | rg -i 'tcp|udp' | fzf --header-lines=1
}
alias nc='net-connections'

# Git file history
git-file-history() {
  git log --follow --oneline --color=always -- "$1" |
    fzf --ansi \
      --preview "git show --color=always {1}:$1 | bat --color=always" \
      --bind 'enter:execute(git show {1}:'"$1"' | bat | less -R)'
}
alias gfh='git-file-history'

# Search in history and execute
history-exec() {
  local cmd
  cmd=$(fc -rl 1 |
    fzf --tac --no-sort \
      --preview 'echo {}' \
      --bind 'enter:accept' |
    sed 's/^ *[0-9]* *//')
  [[ -n "$cmd" ]] && eval "$cmd"
}
alias he='history-exec'

# Find large files
find-large() {
  fd --type f -x dust -s {} |
    sort -rh |
    head -n "${1:-20}" |
    bat -l tsv
}
alias fl='find-large'

# Find recent files with preview
find-recent() {
  fd --type f --changed-within "${1:-7d}" |
    fzf --preview 'bat --color=always {}' \
        --bind 'enter:execute(${EDITOR:-nvim} {})'
}
alias fr='find-recent'

# Interactive git add
git-add-interactive() {
  git status --short |
    fzf --multi \
      --preview 'git diff --color=always {2} | delta' \
      --bind 'ctrl-a:select-all' |
    awk '{print $2}' |
    xargs -r git add
}
alias gai='git-add-interactive'

# FIX: renamed from 'ps' alias — was colliding with alias ps='procs'
# project-stats() is now accessible as pstat
project-stats() {
  echo "📊 Project Statistics\n"
  echo "Code Lines:"
  tokei --sort lines
  echo "\n📁 Disk Usage:"
  dust -d 1
  echo "\n🗂️  File Types:"
  fd --type f | choose -f '.' -1 | sort | uniq -c | sort -rn | head -10
}
alias pstat='project-stats'

# Benchmark all tools
benchmark-tools() {
  echo "🏎️  Performance Comparison\n"
  echo "=== LS vs EZA ==="
  hyperfine --warmup 3 'ls -la /usr/bin' 'eza -la /usr/bin'
  echo "\n=== FIND vs FD ==="
  hyperfine --warmup 3 'find . -name "*.py"' 'fd -e py'
  echo "\n=== GREP vs RIPGREP ==="
  hyperfine --warmup 3 'grep -r "import" .' 'rg "import"'
  echo "\n=== CAT vs BAT ==="
  hyperfine --warmup 3 'cat ~/.zshrc' 'bat --paging=never ~/.zshrc'
}

# ===== KEY BINDINGS =====
bindkey -e  # Emacs mode

# Word navigation
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '\e\e[D'  backward-word
bindkey '\e\e[C'  forward-word

# Home / End / Delete
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# Word delete
bindkey '^[d'  kill-word
bindkey '^[^?' backward-kill-word

# Edit command in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Accept autosuggestion
bindkey '^ ' autosuggest-accept   # Ctrl+Space

# ===== PYTHON DEVELOPMENT =====
alias py='python'

auto_venv() {
  if [[ -f "venv/bin/activate" ]]; then
    echo "🌱 Virtual environment detected, activating..."
    source venv/bin/activate
  elif [[ -f ".venv/bin/activate" ]]; then
    echo "🌱 Virtual environment detected, activating..."
    source .venv/bin/activate
  fi
}

command_not_found_handler() {
  local cmd="$1"
  if [[ "$cmd" == *.py ]]; then
    if [[ -f "$cmd" ]]; then
      echo "🐍 Auto-executing: $cmd"
      python "$cmd" "${@:2}"; return $?
    elif [[ -f "${cmd}.py" ]]; then
      echo "🐍 Auto-executing: ${cmd}.py"
      python "${cmd}.py" "${@:2}"; return $?
    fi
  elif [[ -f "${cmd}.py" ]]; then
    echo "🐍 Auto-executing: ${cmd}.py"
    python "${cmd}.py" "${@:2}"; return $?
  fi
  echo "zsh: command not found: $cmd" >&2
  return 127
}

# ===== MISE (UNIVERSAL VERSION MANAGER) =====
# Uncomment if you prefer mise over fnm/uv:
# if command -v mise > /dev/null; then eval "$(mise activate zsh)"; fi

# ===== UV COMPLETIONS =====
if command -v uv > /dev/null; then
  eval "$(uv generate-shell-completion zsh)" 2>/dev/null
fi

# ===== ATUIN (MODERN SHELL HISTORY) =====
# FIX: McFly block removed entirely — Atuin takes sole ownership of Ctrl+R
# Atuin config at ~/.config/atuin/config.toml:
#   [behavior]
#   filter_mode_shell_up_arrow = "directory"
#   filter_mode = "global"
#   search_mode = "fuzzy"
#   [sync]
#   records = false
if command -v atuin > /dev/null; then
  eval "$(atuin init zsh)"
fi

# ===== LAZY-LOADED TOOLS =====

# Lazy-load nvm
if [[ -d "$HOME/.nvm" ]]; then
  export NVM_DIR="$HOME/.nvm"
  lazy_load_nvm() {
    unset -f nvm node npm npx pnpm yarn
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  }
  nvm()  { lazy_load_nvm; nvm "$@"; }
  node() { lazy_load_nvm; node "$@"; }
  npm()  { lazy_load_nvm; npm "$@"; }
  npx()  { lazy_load_nvm; npx "$@"; }
fi

# Lazy-load conda
if [[ -d "/opt/homebrew/Caskroom/miniconda/base" ]]; then
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
fi

# ===== FINAL CUSTOMIZATIONS =====
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Load p10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Override p10k gap settings after loading config
if [[ -n $POWERLEVEL9K_VERSION ]]; then
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  p10k reload 2>/dev/null
fi

# ===== GHOSTTY CURSOR FIX =====
# Restores block cursor after Powerlevel10k overrides it to a beam
# Must be last — after p10k loads
if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
  _fix_cursor() { echo -ne '\e[2 q'; }
  precmd_functions+=(_fix_cursor)
  zle-line-init() { echo -ne '\e[2 q'; }
  zle -N zle-line-init
fi

# ===== ADDITIONAL PATHS =====
export PATH="/Users/kpatel/.antigravity/antigravity/bin:$PATH"

# ===== CLAUDE SCREENSHOT TOOL =====
alias claude-screenshot='/Users/kpatel/.claude_screenshot/launch_stealth.sh'

# ===== OPENCLAW COMPLETION =====
source "/Users/kpatel/.openclaw/completions/openclaw.zsh"

# ===== BACKGROUND: COMPILE ZCOMPDUMP =====
{
  zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
  if [[ -s "$zcompdump" && (! -s "${zcompdump}.zwc" || "$zcompdump" -nt "${zcompdump}.zwc") ]]; then
    zcompile "$zcompdump"
  fi
} &!

# Welcome message
if [[ -o interactive ]]; then
  echo "✨ Welcome back, $(whoami)! Today is $(date '+%A, %B %d')"
fi
