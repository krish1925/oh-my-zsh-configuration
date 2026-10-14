# =====================================================================
#  tools.zsh — swiss-army knife. You do not need to remember any of it:
#    Ctrl+G   fuzzy palette over everything below + your aliases + abbreviations
#    zhelp    the same list, printed by category
# =====================================================================

# name → "category|what it does".  Feeds zhelp and the palette.
(( $+functions[_zs_locked] )) || source ${${(%):-%x}:A:h}/lib.zsh 2>/dev/null   # locking + atomic writes (lib.zsh), found next to this file
typeset -gA ZS_HELP=(
  '? <request>'   'ai|describe a task → command appears on your prompt (never auto-runs)'
  '?? <question>' 'ai|heavy model (MiMo 9B) + read-only tools: this Mac, this repo, the web, a sandbox'
  '??? <q>'       'ai|deep reasoning model (Qwen3.8-27B) + tools (medium effort)'
  '???? <q>'      'ai|deep reasoning model with high reasoning effort'
  '/remember <f>' 'ai|inside ?? mode: save a fact only you can write, recalled in every future ??'
  ai-memory       'ai|show / edit / clear what ?? remembers ($EDITOR)'
  ai-escalate     'ai|hand the ?? conversation to OpenCode (interactive, asks before every action)'
  '??shot <q>'    'ai|screenshot (drag a region) + ask, one step: ??shot what is this error'
  '???shot <q>'   'ai|screenshot + ask the 27B deep model in one step'
  shot            'ai|shot [full|window|region] → screenshot, also $ZSH_SHOTS/latest.png'
  '/shot'         'ai|inside ?? mode: capture, then pre-fills "what is this?" to edit/send'
  ai-equip        'ai|pick the vision model for ??: ai-equip mimo | qwen4b | <hf-repo>'
  '? + Tab'       'ai|COMMAND MODE: every line is a request → command (run ›). Esc exits, !cmd runs raw'
  '?? + Tab'      'ai|AGENT MODE: every line goes to ?? · /new /think · Tab on empty line cycles mode'
  '??? + Tab'     'ai|DEEP AGENT MODE: 27B model · Tab on empty line cycles mode · Esc exits'
  '???? + Tab'    'ai|DEEP+ AGENT MODE: 27B model (high effort) · Esc exits'
  ai              'ai|ai <question>  or  <cmd> | ai <instruction>'
  wtf             'ai|why did the last command fail? (wtf -r re-runs to capture output)'
  explain         'ai|explain a command part by part (Ctrl+X e for the current line)'
  aic             'ai|commit message from the staged diff, opens in your editor'
  aireview        'ai|review staged diff (or: aireview HEAD~3) for real bugs'
  ai-server       'ai|start | stop | restart | status | log of the local model'
  ai-winnow       'ai|decision model (optional, 8 GB): start | stop | status | budget | log — powers /remember replace, danger + privacy checks'
  ai-decide       'ai|what the decision model has been doing: stats | tail | clear'
  'ai-memory undo' 'ai|put back the fact /remember or tidy replaced (the newer fact stays)'
  ai-model        'ai|list/test/switch the local model (ai-model --current)'
  'Ctrl+N'        'learn|ranked suggestion picker (empty line = usual here)'
  habits          'learn|frequent commands → one-key abbreviations (seq · typos · here · report · ai)'
  mark            'nav|bookmark this directory: mark api → cd ~api'
  marks           'nav|pick a bookmark and jump'
  unmark          'nav|remove a bookmark'
  proj            'nav|jump to any git repo under your project roots'
  fcd             'nav|fuzzy cd below the current directory'
  up              'nav|up 3 → cd ../../..'
  mkcd            'nav|mkdir -p and cd into it'
  y               'nav|yazi file manager; exits into the directory you were in'
  se              'find|ripgrep → fzf → open at the matching line:  se "TODO"'
  fp              'find|find file with preview → open in editor'
  fr              'find|files changed recently (fr 2d) → open'
  extract         'files|unpack any archive'
  bak             'files|timestamped backup copy of a file'
  del             'files|move to Trash instead of rm'
  json            'files|explore JSON (file or stdin)'
  copy            'clip|copy a file clean — no line numbers, no color (copy <file>)'
  catp            'clip|view without line numbers, when you want to select normally'
  cpwd            'clip|copy current path'
  copylast        'clip|copy the last command'
  fbr             'git|fuzzy branch switcher with log preview'
  glog            'git|browse commits with diff preview'
  gai             'git|interactive staging with diff preview'
  gclean          'git|delete local branches already merged'
  lg              'git|lazygit'
  kp              'sys|pick processes and kill them'
  port            'net|who is listening:  port 3000'
  killport        'net|kill whatever listens on a port'
  myip            'net|local and public IP'
  serve           'net|static file server here:  serve 8000'
  netcon          'net|live network connections'
  dsh             'docker|shell into a running container'
  dlog            'docker|follow logs of a container'
  kctx            'k8s|switch kubectl context'
  kns             'k8s|switch namespace'
  klog            'k8s|follow logs of a pod'
  awsp            'aws|switch AWS_PROFILE'
  venv            'python|create (uv) + activate .venv'
  pyclean         'python|remove __pycache__ / .pytest_cache / *.pyc'
  note            'misc|note buy milk  → ~/notes/quick-notes.md   (note = open)'
  cheat           'misc|tldr → cheat.sh → AI, whichever answers first'
  calc            'misc|calc 2**32 / 1e6   (zsh math, no quoting needed)'
  epoch           'misc|epoch → now; epoch 1726000000 → date'
  genpass         'misc|random password → clipboard only (auto-clears after 45s)'
  pstat           'misc|lines of code, disk usage, file types of this project'
  zsh-setup       'shell|one-time machine bootstrap (brew tools, atuin, model)'
  zsh-doctor      'shell|health check: startup time, tools, AI, history DB'
  zsh-colors      'shell|preview the palette and diagnose ls/eza colors'
  zup             'shell|update tools, plugins, caches — then reload'
  zhelp           'shell|this list'
  '?+ <change>'   'ai|refine the last ? command: ?+ only python files'
  '??new <q>'     'ai|start a fresh ?? conversation (?? follows up for 10 min)'
  ai-session      'ai|show / reset the ?? follow-up memory'
  hs              'find|find a past command by describing it: hs ffmpeg crop from spring'
  aj              'agents|background Claude Code job in its own git worktree: aj fix the flaky test'
  ajs             'agents|jobs: preview result + diff, Enter cd, Ctrl+A apply, Ctrl+K kill'
  aj-apply        'agents|apply a job’s changes to your checkout (git apply --3way)'
  aj-clean        'agents|remove finished job worktrees (-f discards unapplied changes)'
  zmouse          'edit|click-to-move cursor: zmouse auto / on / off'
  zs-iterm        'shell|iTerm2: status · install profile · keys · tm = tmux -CC · ishot / imgcat'
  ciw             'sys|watch GitHub Actions in the background; failure reason in a notification'
)

function zhelp {
  emulate -L zsh
  local c k v
  for c in ai agents edit learn nav find files clip git sys net docker k8s aws python misc shell; do
    print -P -- "\n%B%F{$ZC[dir]}${(U)c}%f%b"
    for k in ${(ok)ZS_HELP}; do
      v=$ZS_HELP[$k]
      [[ ${v%%|*} == $c ]] && printf '  %-15s %s\n' "$k" "${v#*|}"
    done
  done
  print -P -- "\n%B%F{$ZC[dir]}KEYS%f%b
  Ctrl+G   palette            Ctrl+R   history (atuin)     Up/Down  history by prefix
  Ctrl+O   AI: line → command Ctrl+X e explain line        Ctrl+X f fix last failure
  Ctrl+X h usual here         Ctrl+T   files               Opt+C    cd below
  Ctrl+N   pick from all ranked suggestions (empty line = usual in this dir)
  Ctrl+Space accept suggestion   Esc Esc  sudo             Ctrl+X Ctrl+E  edit in nvim
  ↑/↓      walk the live list under the line (history; or a folder's files when you type a path: → open · ← back)
  Tab = fzf completion  ·  in any fzf: Ctrl+/ preview, Ctrl+Y copy

%B%F{$ZC[dir]}EDITING LIKE AN EDITOR%f%b   (supershell.zsh)
  click          move the cursor (Ghostty: built in · Terminal.app: Option+click, or zmouse auto)
  Shift+←/→      select (Shift+Alt by word · Shift+Home/End)   type = replace · ⌫ = delete
  Alt+W / Ctrl+W copy / cut the selection to the clipboard       Ctrl+X ^A select all
  Ctrl+X c       copy the whole line                             Ctrl+X s  hs: find by description
  Ctrl+Z         empty line: fg · otherwise park the line        Up/Down   move lines in multi-line cmds"
}

_zs_palette_lines() {
  emulate -L zsh
  local k v line
  for k in ${(ok)ZS_HELP}; do
    v=$ZS_HELP[$k]
    printf '%-16s %-7s %s\t%s\n' "$k" "${v%%|*}" "${v#*|}" "${k%% *}"
  done
  if (( $+functions[abbr] )); then
    abbr list 2>/dev/null | while IFS= read -r line; do
      k=${${line%%=*}//\"/}; v=${${line#*=}//\"/}
      [[ -n $k ]] && printf '%-16s %-7s %s\t%s\n' "$k" abbr "$v" "$k"
    done
  fi
  for k in ${(ok)aliases}; do
    printf '%-16s %-7s %s\t%s\n' "$k" alias "${aliases[$k]}" "$k"
  done
}
_zs_palette_widget() {
  local sel
  sel=$(_zs_palette_lines | fzf --delimiter=$'\t' --with-nth=1 --height=70% --prompt='palette ❯ ' \
        --header='everything this shell can do — Enter puts it on your prompt')
  if [[ -n $sel ]]; then
    LBUFFER+="${sel##*$'\t'} "
  fi
  zle reset-prompt
}

# ---- navigation ---------------------------------------------------------------
function mkcd { [[ -n $1 ]] || { print -u2 "usage: mkcd <dir>"; return 1 }; command mkdir -p -- "$1" && builtin cd -- "$1" }
(( $+commands[up] )) || function up { local -i n=${1:-1}; local p=''; repeat $n do p+=../; done; builtin cd -- $p }
function fcd {
  local dir
  dir=$(fd --type d ${1:-.} 2>/dev/null | fzf --preview 'eza --tree --level=2 --color=always {} | head -200') && cd "$dir"
}
function proj {
  emulate -L zsh
  local -a roots=( ${=ZS_PROJECT_ROOTS:-$HOME/Documents $HOME/Desktop $HOME/code $HOME/projects $HOME/dev $HOME/src} )
  roots=( ${^roots}(N-/) )
  (( $#roots )) || { print -u2 "set ZS_PROJECT_ROOTS='dir1 dir2' in ~/.zshrc.local"; return 1 }
  local d
  d=$(fd -H -t d -d 5 '^\.git$' $roots 2>/dev/null | sed -e 's#/\.git/*$##' |
      fzf --query="$*" --select-1 --prompt='repo ❯ ' \
          --preview 'git -C {} log --oneline -8 --color=always 2>/dev/null; echo; eza -la --color=always --icons=always {} | head -40') &&
    cd "$d"
}
# bookmarks = zsh named directories: `mark api` → `cd ~api`, `~api/src`, shown as ~api in the prompt
typeset -g _ZS_MARKS=$ZSH_DATA/bookmarks
() {
  local n p
  [[ -r $_ZS_MARKS ]] || return 0
  while IFS=$'\t' read -r n p; do [[ -n $n && -d $p ]] && hash -d -- "$n=$p"; done < $_ZS_MARKS
}
(( $+commands[mark] )) || function mark {
  local n=${1:-${PWD:t}}
  [[ $n == [[:alnum:]_-]## ]] || { print -u2 "bookmark names: letters, digits, _ and -"; return 1 }
  _zs_locked $_ZS_MARKS _zs_mark_set "$n" "$PWD" || { print -u2 "could not save the bookmark (busy)"; return 1 }
  hash -d -- "$n=$PWD"; print -r -- "~$n → $PWD"
}
# replace-or-add one bookmark, locked + atomic: `mark` in two tabs used to lose one (each did unmark → rewrite → append)
_zs_mark_set() {   # <name> <dir>
  emulate -L zsh
  local l; local -a reply out
  _zs_read_lines $_ZS_MARKS
  for l in "${reply[@]}"; do [[ $l == "$1"$'\t'* ]] || out+=( "$l" ); done
  out+=( "$1"$'\t'"$2" )
  _zs_write_lines $_ZS_MARKS "${out[@]}"
}
_zs_mark_drop() {   # <name>  — matched LITERALLY: `unmark '*'` used to be a glob that deleted every bookmark
  emulate -L zsh
  local l; local -a reply out
  _zs_read_lines $_ZS_MARKS
  for l in "${reply[@]}"; do [[ $l == "$1"$'\t'* ]] || out+=( "$l" ); done
  _zs_write_lines $_ZS_MARKS "${out[@]}"
}
function unmark {
  [[ -n $1 && -r $_ZS_MARKS ]] || return 1
  _zs_locked $_ZS_MARKS _zs_mark_drop "$1" || { print -u2 "could not update bookmarks (busy)"; return 1 }
  unhash -d -- $1 2>/dev/null; return 0
}
function marks {
  [[ -s $_ZS_MARKS ]] || { print "no bookmarks yet — mark <name> in a directory"; return 0 }
  local sel
  sel=$(fzf --delimiter=$'\t' --prompt='bookmark ❯ ' --preview 'eza -la --color=always --icons=always {2} | head -40' < $_ZS_MARKS) &&
    cd "${sel#*$'\t'}"
}
if (( $+commands[yazi] )); then
  function y {
    local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
    yazi "$@" --cwd-file="$tmp"
    cwd=$(<$tmp); [[ -n $cwd && $cwd != $PWD ]] && builtin cd -- "$cwd"
    command rm -f -- "$tmp"
  }
fi

# ---- find / files ----------------------------------------------------------------
function search-edit {
  local hit
  hit=$(rg --line-number --no-heading --color=always "$@" |
        fzf --ansi --delimiter=: --preview 'bat --color=always {1} --highlight-line {2}' --preview-window '+{2}/2') || return
  local -a f=( "${(@s.:.)hit}" )
  ${EDITOR:-nvim} "+$f[2]" "$f[1]"
}
function find-preview { local f; f=$(fd --type f "$@" | fzf --preview 'bat --color=always {}') && ${EDITOR:-nvim} "$f" }
function find-recent  { local f; f=$(fd --type f --changed-within "${1:-7d}" | fzf --preview 'bat --color=always {}') && ${EDITOR:-nvim} "$f" }
alias se='search-edit' fp='find-preview' fr='find-recent'

function extract {
  [[ -f $1 ]] || { print -u2 "'$1' is not a file"; return 1 }
  case ${1:l} in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;      *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.xz|*.txz)   tar xJf "$1" ;;      *.tar.zst)      tar --zstd -xf "$1" ;;
    *.tar)            tar xf "$1" ;;       *.bz2)          bunzip2 "$1" ;;
    *.gz)             gunzip "$1" ;;       *.xz)           unxz "$1" ;;
    *.zst)            unzstd "$1" ;;       *.zip|*.jar|*.whl) unzip "$1" ;;
    *.rar)            unrar x "$1" ;;      *.7z)           7z x "$1" ;;
    *.z)              uncompress "$1" ;;
    *) print -u2 "don't know how to extract '$1'"; return 1 ;;
  esac
}
function bak { [[ -e $1 ]] || return 1; local dst="$1.$(date +%Y%m%d-%H%M%S).bak"; command cp -a -- "$1" "$dst" && print -r -- "→ $dst" }
function del {   # recoverable rm
  (( $# )) || { print -u2 "usage: del <files…>"; return 1 }
  if [[ -x /usr/bin/trash ]]; then /usr/bin/trash "$@"
  elif (( $+commands[trash] )); then command trash "$@"
  else command mv -i -- "$@" ~/.Trash/; fi
}
(( $+commands[json] )) || function json {
  if (( $+commands[jless] )) && [[ -n $1 ]]; then jless "$@"
  elif [[ -n $1 ]]; then jq -C . "$@" | less -R
  else jq -C . | less -R; fi
}

# ---- clipboard ------------------------------------------------------------------------
(( $+commands[copy] )) || function copy { if [[ -n $1 ]]; then pbcopy < "$1"; else pbcopy; fi }
function cpwd     { print -rn -- $PWD | pbcopy; print -r -- "copied: $PWD" }
function copylast { fc -ln -1 | pbcopy; print "copied last command" }

# ---- git ---------------------------------------------------------------------------------
function fbr {
  git rev-parse HEAD >/dev/null 2>&1 || { print -u2 "not in a git repo"; return 1 }
  local b
  b=$(git branch --all --color=always --sort=-committerdate | command grep -v HEAD |
      fzf --ansi --preview 'git log -n 12 --color=always --oneline --graph $(sed "s/.* //" <<< {})' --preview-window=right:60% |
      sed -e 's/.* //' -e 's#remotes/[^/]*/##')
  [[ -n $b ]] && git checkout "$b"
}
function glog {
  git log --oneline --color=always --decorate |
    fzf --ansi --no-sort --preview 'git show --color=always {1}' --preview-window=right:60% \
        --bind 'enter:execute(git show --color=always {1} | less -R)'
}
function git-add-interactive {
  git status --short | fzf --multi --preview 'git diff --color=always -- {2}' --bind 'ctrl-a:select-all' |
    awk '{ print $2 }' | xargs git add
}
alias gai='git-add-interactive'
function gclean {
  local main=${$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)#origin/}
  git branch --merged ${main:-main} | command grep -vE "^\*|^[[:space:]]*(${main:-main}|master|develop)$" | xargs git branch -d
}

# ---- system / network ----------------------------------------------------------------------
function kill-process {
  local -a pids
  pids=( $( { procs 2>/dev/null || ps -axo pid,user,%cpu,%mem,command } | fzf --multi --header-lines=1 | awk '{ print $1 }') )
  (( $#pids )) && kill ${1:--TERM} $pids
}
alias kp='kill-process'
function netcon { lsof -nP -i | fzf --header-lines=1 }
(( $+commands[port] )) || function port {
  [[ -n $1 ]] || { lsof -nP -iTCP -sTCP:LISTEN; return }
  lsof -nP -iTCP:$1 -sTCP:LISTEN
}
function killport { local -a p=( $(lsof -ti tcp:$1 -sTCP:LISTEN 2>/dev/null) ); (( $#p )) && kill -9 $p && print "killed $p" || print "nothing on :$1" }
function myip { print -r -- "local   $(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"; print -r -- "public  $(curl -fsS -m 4 https://api.ipify.org 2>/dev/null)" }
(( $+commands[serve] )) || function serve {
  if (( $+commands[miniserve] )); then miniserve --port ${1:-8000} .; else python3 -m http.server ${1:-8000}; fi
}

# ---- docker / kubernetes / aws — only defined when the CLI exists --------------------------
if (( $+commands[docker] )); then
  alias dk='docker' dc='docker compose' dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
  _zs_dpick() { docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | fzf --prompt="$1 ❯ " | cut -f1 }
  function dsh  { local c; c=$(_zs_dpick shell) && docker exec -it $c sh -c 'command -v bash >/dev/null && exec bash || exec sh' }
  function dlog { local c; c=$(_zs_dpick logs)  && docker logs -f --tail ${1:-200} $c }
fi
if (( $+commands[kubectl] )); then
  alias k='kubectl' kg='kubectl get' kd='kubectl describe'
  function kctx { local c; c=$(kubectl config get-contexts -o name | fzf --prompt='context ❯ ') && kubectl config use-context $c }
  function kns  { local n; n=$(kubectl get ns -o name | sed 's#namespace/##' | fzf --prompt='namespace ❯ ') && kubectl config set-context --current --namespace=$n }
  function klog { local p; p=$(kubectl get pods -o name | fzf --prompt='pod ❯ ' --preview 'kubectl describe {} | head -60') && kubectl logs -f --tail=${1:-200} $p }
fi
(( $+commands[aws] )) && function awsp {
  local p; p=$(aws configure list-profiles 2>/dev/null | fzf --prompt='AWS profile ❯ ') && export AWS_PROFILE=$p && print -r -- "AWS_PROFILE=$p"
}

# ---- python -----------------------------------------------------------------------------------
function venv {
  local -a pyv; [[ -n $1 ]] && pyv=(--python $1)          # venv 3.12
  if [[ ! -d .venv ]]; then
    if (( $+commands[uv] )); then uv venv $pyv || return; else python3 -m venv .venv || return; fi
  fi
  source .venv/bin/activate
}
function pyclean {
  fd -H -I -t d '^(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache)$' -X rm -rf
  fd -H -I -e pyc -X rm -f
}

# ---- misc ---------------------------------------------------------------------------------------
function note {
  local dir=$HOME/notes; command mkdir -p $dir
  if (( $# )); then print -r -- "$(date '+%F %T'): $*" >> $dir/quick-notes.md; print "saved"
  else ${EDITOR:-nvim} $dir/quick-notes.md; fi
}
function cheat {
  [[ -n $1 ]] || { print -u2 "usage: cheat <command>"; return 1 }
  if (( $+commands[tldr] )) && tldr "$@" 2>/dev/null; then return; fi
  curl -fsS -m 5 "https://cheat.sh/${(j:+:)@}" 2>/dev/null && return
  (( $+functions[ai] )) && ai "Show the 6 most useful real-world examples of: $*"
}
zmodload zsh/mathfunc 2>/dev/null
function _zs_calc { print -- $(( $* )) }
alias calc='noglob _zs_calc'
function epoch { if [[ -n $1 ]]; then date -r ${1[1,10]} '+%F %T %Z'; else print $EPOCHSECONDS; fi }
function genpass {   # genpass [len] — straight to the clipboard, never on screen / in scrollback
  emulate -L zsh
  local -i n=${1:-24}
  local pw
  pw=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^*_+=-' < /dev/urandom | head -c $n)
  print -rn -- $pw | pbcopy
  print -r -- "copied a $n-char password · clipboard clears in 45s if unchanged"
  ( sleep 45; [[ $(pbpaste) == "$pw" ]] && print -n "" | pbcopy ) &!
}
function project-stats {
  (( $+commands[tokei] )) && { print "== code =="; tokei --sort lines }
  (( $+commands[dust] ))  && { print "\n== disk =="; dust -d 1 }
  print "\n== file types =="
  fd --type f | awk -F. 'NF > 1 { print $NF }' | sort | uniq -c | sort -rn | head -n 10
}
alias pstat='project-stats'
function patterns { habits report }      # v3 name

# =====================================================================
#  SETUP · DOCTOR · UPDATE · MAINTENANCE
# =====================================================================
typeset -ga ZS_BREW_TOOLS=(antidote fzf fd ripgrep bat eza zoxide atuin git-delta carapace jq dust procs
  bottom sd xh gitui lazygit tealdeer tokei hyperfine yazi broot fnm uv glow gping just jless)

_zs_comp() {   # <name> <generator…> → $ZSH_CACHE/completions/_name, only if the generator produced something
  # unique temp name (two shells generating at once shared one fixed name) and OUTSIDE the completions
  # directory (compinit would otherwise pick a half-written `_name.tmp` up as a completion function)
  local f=$ZSH_CACHE/completions/_$1 tmp=$ZSH_CACHE/.comp-$1.tmp.${sysparams[pid]}; shift
  "$@" >| $tmp 2>/dev/null && [[ -s $tmp ]] && zf_mv -f $tmp $f || zf_rm -f $tmp
}
_zs_gen_completions() {    # native completions as fpath files: autoloaded on first Tab, zero startup cost
  (( $+commands[uv] ))    && { _zs_comp uv uv generate-shell-completion zsh; _zs_comp uvx uvx --generate-shell-completion zsh }
  (( $+commands[just] ))  && _zs_comp just just --completions zsh
  (( $+commands[atuin] )) && _zs_comp atuin atuin gen-completions --shell zsh
  zf_rm -f $ZSH_CACHE/zcompdump $ZSH_CACHE/zcompdump.zwc      # next shell rebuilds the dump once
  return 0
}

_zs_atuin_ai_off_toml() {
  print -l -- '[ai]' '# written by zsh-setup: `?` is handled by ~/.config/zsh/ai.zsh' 'enabled = false' 'send_cwd = false'
}

function zsh-setup {
  emulate -L zsh
  (( $+commands[brew] )) || { print -u2 "Homebrew first: https://brew.sh"; return 1 }
  print -P "%B1/7 tools%b"
  local -a have=( ${(f)"$(brew list --formula -1 2>/dev/null)"} ) missing
  missing=( ${ZS_BREW_TOOLS:|have} )
  if (( $#missing )); then brew install $missing; else print "  all ${#ZS_BREW_TOOLS} present"; fi
  rehash

  print -P "%B2/7 git + delta%b (written once, not on every shell start)"
  git config --global core.pager delta
  git config --global interactive.diffFilter 'delta --color-only'
  git config --global delta.navigate true
  git config --global delta.line-numbers true
  git config --global delta.side-by-side true
  git config --global merge.conflictstyle zdiff3

  print -P "%B3/7 ripgrep%b"
  [[ -f ~/.ripgreprc ]] || print -l -- --smart-case --hidden '--glob=!.git/*' '--glob=!node_modules/*' '--glob=!.venv/*' > ~/.ripgreprc

  print -P "%B4/7 atuin%b (history DB = what the learning layer reads)"
  local acfg=${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml
  if [[ ! -f $acfg ]] && (( $+commands[atuin] )); then
    command mkdir -p ${acfg:h}
    autoload -Uz is-at-least
    local av=${${(z)"$(atuin --version 2>/dev/null)"}[2]}
    {
      print -l -- '# written by zsh-setup' 'filter_mode = "global"' 'filter_mode_shell_up_arrow = "directory"' \
        'enter_accept = false' 'style = "compact"' 'inline_height = 24' 'show_preview = true' 'auto_sync = false' 'update_check = false'
      if is-at-least 18.13 ${av:-0}; then    # hot in-memory index (nucleo) — 18.13+
        print -l -- 'search_mode = "daemon-fuzzy"' '' '[daemon]' 'enabled = true' 'autostart = true'
      else
        print -l -- 'search_mode = "fuzzy"'
      fi
      _zs_atuin_ai_off_toml
    } > $acfg
    print "  wrote $acfg"
  else
    print "  kept your existing $acfg"
  fi
  # ? belongs to ai.zsh. Atuin 18.13+ has its own AI on ? (opt-in via `atuin
  # setup`); keep it off in the config too, not just via init --disable-ai,
  # so a later `atuin setup` can't start a fight over the key.
  if [[ -f $acfg ]] && ! command grep -q '^\[ai\]' $acfg; then
    { print; _zs_atuin_ai_off_toml } >> $acfg
    print "  atuin AI disabled in $acfg (? is ai.zsh's)"
  fi
  [[ -r $_ZS_ATUIN_DB ]] || atuin import auto

  print -P "%B5/7 completions%b"; _zs_gen_completions

  print -P "%B6/7 starter abbreviations%b"
  if (( $+functions[abbr] )); then
    local a
    for a in 'gcm=git commit -m' 'gpo=git push origin' 'uvr=uv run' 'uvs=uv sync' 'uva=uv add' \
             'mlxs=mlx_lm.server --model' 'dcu=docker compose up -d' 'dcd=docker compose down'; do
      abbr add "$a" >/dev/null 2>&1
    done
  fi

  print -P "%B7/7 local AI%b  ($ZAI_MODEL)"
  (( $+commands[mlx_lm.server] )) || uv tool install mlx-lm
  if read -q "?  download + start the model now (~5.5 GB, runs only on this Mac)? [y/N] "; then
    print; ai-server start
  else
    print "\n  skipped — it starts by itself the first time you use  ? …"
  fi

  if [[ $TERM_PROGRAM != ghostty ]] && ! [[ -d /Applications/Ghostty.app ]]; then
    print -P "\n%BGhostty%b is not installed — it gives plain click-to-move-cursor at the prompt,"
    print -P "  which Terminal.app can only do with Option+click (or: zmouse auto)."
    if read -q "?  brew install --cask ghostty now? [y/N] "; then print; brew install --cask ghostty; else print; fi
  fi
  print -P "\n%BGhostty%b — ~/.config/ghostty/config already has:"
  print -l -- '  cursor-click-to-move = true             # click anywhere in the command to put the cursor there' \
              '  copy-on-select = clipboard              # selecting text copies it to the system clipboard' \
              '  minimum-contrast = 1.6                  # lifts any fg too dark for a translucent bg' \
              '  selection-invert-fg-bg = true           # readable selection over a wallpaper' \
              '  shell-integration-features = no-cursor  # keeps your block cursor' \
              '  macos-option-as-alt = left              # real Alt+B / Alt+F / Alt+C' \
              '  Ctrl+Alt+drag = rectangular selection   # copy code WITHOUT cat’s line-number gutter'
  print -P "\ndone → %Bexec zsh%b, then:  zsh-colors   (check the palette)   ·   ? show the 10 biggest files here"
}

function zsh-doctor {
  emulate -L zsh
  local ok="%F{$ZC[exe]}ok%f  " no="%F{$ZC[err]}--%f  " t
  print -P "%Bshell%b    zsh $ZSH_VERSION · ${TERM_PROGRAM:-?} · config $ZSH_CONF"
  if [[ -s $ZSH_DATA/startup.log ]]; then
    local -a ms=( ${${(f)"$(<$ZSH_DATA/startup.log)"}##* } ); (( $#ms > 30 )) && ms=( ${ms[-30,-1]} )   # a slice longer than the array is EMPTY in zsh
    local -i sum=0 max=0 m
    for m in $ms; do (( sum += m, m > max && (max = m) )); done
    print -P "%Bstartup%b  avg $(( sum / $#ms )) ms · worst $max ms over last $#ms shells  (budget ${ZSH_SLOW_MS} ms · to-first-prompt is lower: instant prompt)"
    (( sum / $#ms > ZSH_SLOW_MS )) && print "         slow → ZPROFILE=1 zsh -i -c exit   shows what costs the time"
  fi
  print -P "%Bplugins%b  $( [[ -s $ZSH_CACHE/plugins.zsh ]] && print "$ok static bundle present" || print "$no no bundle — brew install antidote; exec zsh")"
  print -P "%Bhistory%b  $( if _zs_have_db; then print "$ok atuin DB: $(_zs_sql 'SELECT COUNT(*) FROM history;') commands — smart suggestions + habits active"; else print "$no no atuin DB → zsh-setup (falls back to plain history)"; fi)"
  print -P "%Bai%b       $( if _zai_up; then print "$ok $ZAI_MODEL @ $ZAI_URL"; else print "$no not running (starts on first use) · $ZAI_URL"; fi)"
  if (( $+functions[_zdw_up] )); then       # the decision model (DECIDER_FEATURES_PLAN.md)
    local dstate dfit='' dt; local -a dfitted
    for dt in memory_rel memory_list route deep_hint danger; do [[ -n $(_zdec_threshold $dt 2>/dev/null) ]] && dfitted+=$dt; done
    dfit="fitted: ${(j:, :)dfitted:-none}"
    if _zdw_up; then dstate="$ok up (:$ZDW_PORT, ${ZDW_MODEL_FILE%.gguf}, idle-stop ${ZDW_IDLE_MIN}m)"
    elif [[ -x $ZDW_HOME/winnow-inference/.build/bin/winnow-server && -f $ZDW_HOME/model/gguf/$ZDW_MODEL_FILE ]]; then dstate="$ok installed, off until an explicit feature starts it (ai-winnow start)"
    else dstate="$no not installed (optional) — see agent/DECIDER_PLAN.md STATUS"; fi
    local dlog=${ZSH_CACHE}/decide.jsonl dstats=''
    [[ -s $dlog ]] && dstats=" · last 24h: $(jq -rs --argjson t $(( EPOCHSECONDS - 86400 )) '[.[] | select(.t >= $t)] | "\(length) decisions, \(map(select(.fallback_reason != null)) | length) fallbacks"' $dlog 2>/dev/null)"
    print -P "%Bdecider%b  $dstate · mode $ZDW_MODE · $dfit$dstats"
  fi
  if (( $+commands[bat] )); then
    print -P "%Bbat%b      $( bat --list-themes 2>/dev/null | command grep -qxF -- "$BAT_THEME" && print "$ok theme '$BAT_THEME'" || print "$no theme '$BAT_THEME' unknown → brew upgrade bat (≥0.25 ships Catppuccin)")"
  fi
  print -Pn "%Btools%b    "
  for t in $ZS_BREW_TOOLS sqlite3 mlx_lm.server; do
    case $t in ripgrep) t=rg ;; git-delta) t=delta ;; bottom) t=btm ;; tealdeer) t=tldr ;; antidote) continue ;; esac
    (( $+commands[$t] )) && print -Pn "%F{$ZC[exe]}$t%f " || print -Pn "%F{$ZC[err]}$t✗%f "
  done
  print
}

function zup {
  emulate -L zsh
  local -a have=( ${(f)"$(brew list --formula -1 2>/dev/null)"} ) mine
  mine=( ${ZS_BREW_TOOLS:*have} )                      # only the tools this config uses, not your whole brew
  print -P "%Bbrew%b";    brew update -q && (( $#mine )) && brew upgrade $mine
  print -P "%Bplugins%b"; antidote update; zf_rm -f $ZSH_CACHE/plugins.zsh $ZSH_CACHE/plugins.zsh.zwc
  print -P "%Bmlx-lm%b";  (( $+commands[uv] )) && uv tool upgrade mlx-lm 2>/dev/null
  print -P "%Bcaches%b";  zf_rm -f $ZSH_CACHE/init-*.zsh(N) $ZSH_CACHE/init-*.zwc(N); _zs_gen_completions
  (( $+commands[tldr] )) && tldr --update >/dev/null 2>&1
  exec zsh
}

# Runs detached at most once a week (triggered from .zshrc). No network except tldr
# pages (+ plugin updates if you opt in). Writes ONE line to $ZSH_CACHE/tip at most.
_zs_maintenance() {
  emulate -L zsh
  _zs_gen_completions
  (( $+commands[tldr] )) && tldr --update
  if (( ZSH_AUTO_UPDATE_PLUGINS )) && [[ -r $ZS_ANTIDOTE ]]; then
    source $ZS_ANTIDOTE && antidote update && zf_rm -f $ZSH_CACHE/plugins.zsh
  fi
  local log=$ZSH_DATA/startup.log
  if [[ -s $log ]]; then                      # keep the log small; watch for startup regressions
    local -a lines=( ${(f)"$(<$log)"} )
    (( $#lines > 400 )) && _zs_write_lines $log ${lines[-300,-1]}     # atomic: a shell starting now appends to a whole file
    local -a ms=( ${lines##* } ); (( $#ms > 40 )) && ms=( ${ms[-40,-1]} )
    local -i sum=0 m; for m in $ms; do (( sum += m )); done
    if (( $#ms >= 10 && sum / $#ms > ZSH_SLOW_MS )); then
      print -r -- "shell startup is averaging $(( sum / $#ms )) ms (budget $ZSH_SLOW_MS) → run: zsh-doctor" >| $ZSH_CACHE/tip
      return 0
    fi
  fi
  (( $+functions[_zs_habits_scan] )) && _zs_habits_scan
  return 0
}
