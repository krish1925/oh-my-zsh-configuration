# =====================================================================
#  supershell.zsh — the line editor behaves like a text editor
#
#  CLICK TO PLACE THE CURSOR
#    Ghostty      plain click, built in (cursor-click-to-move, see ghostty config)
#    Terminal.app Option+click, built in — or `zmouse auto` for a plain click
#    zmouse auto  plain click moves the cursor while you are typing a command;
#                 with an empty prompt the mouse is the terminal's again
#                 (select / scroll output). Click the gray suggestion to take
#                 it up to that point.
#    zmouse on    always while the prompt is active   ·  zmouse off
#                 Persist with ZSH_MOUSE=auto in ~/.zshrc.local.
#                 While it is active, the terminal needs a modifier to select
#                 text: Shift+drag in Ghostty/iTerm; Terminal.app: ⌘R toggles
#                 "Allow Mouse Reporting".
#
#  SELECT LIKE AN EDITOR
#    Shift+←/→          extend a selection (Shift+Alt = by word, Shift+Home/End)
#    typing             replaces the selection   ·  Backspace/Delete removes it
#    Alt+W              copy selection to the macOS clipboard
#    Ctrl+W             cut selection to the clipboard (no selection: delete word)
#    Ctrl+X c           copy the whole line to the clipboard
#
#  MORE
#    Up/Down            move between lines in a multi-line command; history
#                       search only from the first/last line
#    Ctrl+Z             empty line: resume the suspended job (fg). Otherwise
#                       park the line, run something else, get it back.
#    watcher            a command that ran ≥ ZSH_WATCH_AFTER s while you were in
#                       another app → macOS notification; if it failed and the
#                       local model is up, the notification says why.
#    ciw [run-id]       watch GitHub Actions in the background, same treatment
# =====================================================================

(( $+functions[_zs_locked] )) || source ${${(%):-%x}:A:h}/lib.zsh 2>/dev/null   # locking + atomic writes (lib.zsh), found next to this file
: ${ZSH_MOUSE:=off}             # off | auto | on
: ${ZSH_WATCH:=1}               # notify about long commands finished while you were away
: ${ZSH_WATCH_AFTER:=60}        # seconds
: ${ZSH_WATCH_CAPTURE:=0}       # Terminal.app: read the tab's last output for the summary
                                #   (first use asks for Automation permission once)

# ---- helpers ------------------------------------------------------------------
_zs_notify() {   # <title> <message> — argv, so quotes in the message cannot break out
  osascript -e 'on run a' -e 'display notification (item 2 of a) with title (item 1 of a)' -e 'end run' \
    -- "$1" "${2[1,220]}" >/dev/null 2>&1
}
_zs_frontmost() {   # → REPLY: display name of the frontmost app (no AppleScript, ~5 ms)
  REPLY=${${${(M)${(f)"$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null)"}:#*=*}#*=\"}%\"}
}
_zs_term_is_front() {
  _zs_frontmost
  case $TERM_PROGRAM in
    Apple_Terminal) [[ $REPLY == Terminal ]] ;;
    ghostty)        [[ $REPLY == Ghostty ]] ;;
    iTerm.app)      [[ $REPLY == iTerm2 ]] ;;
    WarpTerminal)   [[ $REPLY == Warp ]] ;;
    vscode)         [[ $REPLY == (Code|Cursor|Windsurf)* ]] ;;
    *)              [[ -z $REPLY ]] ;;   # unknown terminal: assume focused, stay quiet
  esac
}

# =====================================================================
#  1. MOUSE: click to move the cursor
# =====================================================================
# SGR 1006 mouse reporting, enabled only while ZLE is reading a line and turned
# off before any command runs (preexec + line-finish), so programs never see it.
# On a click we move the cursor to the start of the buffer, ask the terminal
# where that is (DSR 6n), lay the buffer out the way ZLE does (wide chars,
# wrapping at $COLUMNS, embedded newlines) and pick the character under the
# pointer.
typeset -gi _ZS_MOUSE_STATE=0 _ZS_MOUSE_PAUSED=0

_zs_mouse_emit() {   # <0|1>
  if (( $1 )); then print -n '\e[?1000h\e[?1006h' >/dev/tty
  else print -n '\e[?1006l\e[?1000l' >/dev/tty; fi
  _ZS_MOUSE_STATE=$1
}
_zs_mouse_want() {
  case $ZSH_MOUSE in
    on)   (( ! _ZS_MOUSE_PAUSED )) ;;
    auto) (( ! _ZS_MOUSE_PAUSED && ${#BUFFER} )) ;;
    *)    return 1 ;;
  esac
}
_zs_mouse_redraw() {   # zle-line-pre-redraw: follow the buffer (auto mode) cheaply
  [[ $ZSH_MOUSE == off ]] && { (( _ZS_MOUSE_STATE )) && _zs_mouse_emit 0; return 0 }
  [[ $LASTWIDGET != _zs_mouse_widget ]] && _ZS_MOUSE_PAUSED=0   # any key un-pauses
  if _zs_mouse_want; then
    # re-emit even when we think it is on: fzf & co. switch it off behind our back
    _zs_mouse_emit 1
  elif (( _ZS_MOUSE_STATE )); then
    _zs_mouse_emit 0
  fi
}
_zs_mouse_init()   { _ZS_MOUSE_PAUSED=0; _zs_mouse_want && _zs_mouse_emit 1; return 0 }
_zs_mouse_finish() { (( _ZS_MOUSE_STATE )) && _zs_mouse_emit 0; return 0 }

# Read the rest of a mouse report after the bound prefix.
#   SGR:  \e[<b;x;yM   (press)  …m (release)       X10:  \e[M + 3 bytes
_zs_mouse_read() {   # → reply=(button x y pressed)
  local c s=''
  if [[ $KEYS == *'<' ]]; then
    while read -t 0.2 -k 1 c; do
      [[ $c == [Mm] ]] && break
      s+=$c; (( ${#s} > 24 )) && return 1
    done
    local -a f=( ${(s:;:)s} )
    (( $#f == 3 )) || return 1
    reply=( $f[1] $f[2] $f[3] 0 )
    [[ $c == M ]] && reply[4]=1
  else
    local b x y
    read -t 0.2 -k 1 b && read -t 0.2 -k 1 x && read -t 0.2 -k 1 y || return 1
    b=$(( #b - 32 )); x=$(( #x - 32 )); y=$(( #y - 32 ))
    reply=( $b $x $y $(( (b & 3) != 3 )) )
    (( (b & 3) == 3 )) && reply[1]=0
  fi
  return 0
}
_zs_cursor_pos() {   # → reply=(row col) of the terminal cursor, 1-based
  local r='' c
  print -n '\e[6n' >/dev/tty
  # anything else queued (the button-release report) is skipped
  while read -t 0.5 -k 1 c; do
    r+=$c
    [[ $c == R && $r == *$'\e['<->';'<->R ]] && break
    (( ${#r} > 64 )) && return 1
  done
  [[ $r =~ $'\e\\[([0-9]+);([0-9]+)R$' ]] || return 1
  reply=( $match[1] $match[2] )
}
_zs_mouse_widget() {
  emulate -L zsh; setopt extendedglob
  local -a reply
  _zs_mouse_read || return 0
  local -i b=$reply[1] x=$reply[2] y=$reply[3] pressed=$reply[4]
  (( pressed )) || return 0                                  # ignore releases
  if (( b & 64 )); then                                      # wheel: give the mouse back
    _ZS_MOUSE_PAUSED=1; _zs_mouse_emit 0                     # until the next keypress
    zle -M "scrolling — mouse returned to the terminal until you type"
    return 0
  fi
  (( (b & ~28) == 0 )) || return 0                           # left button only (any modifiers)

  local -i keep=$CURSOR r0 c0
  CURSOR=0; zle -R
  if ! _zs_cursor_pos; then CURSOR=$keep; zle -R; return 0; fi
  r0=$reply[1] c0=$reply[2]
  if (( y < r0 )); then CURSOR=$keep; return 0; fi           # clicked above the prompt line

  # lay out BUFFER + POSTDISPLAY (autosuggestion) and find the pointer
  local text=$BUFFER$POSTDISPLAY ch
  local -i n=${#BUFFER} total=${#text} r=r0 col=c0 i w best=-1 last=-1
  for (( i = 0; i <= total; i++ )); do
    if (( r == y )); then
      last=i
      (( col <= x )) && best=i
    elif (( r > y )); then
      break
    fi
    (( i == total )) && break
    ch=${text[i+1]}
    if [[ $ch == $'\n' ]]; then
      (( r++, col = 1 )); continue
    fi
    if [[ $ch == [[:cntrl:]] ]]; then w=2; else w=${(m)#ch}; (( w < 1 )) && w=1; fi
    (( col + w - 1 > COLUMNS )) && (( r++, col = 1 ))       # wide char would not fit
    (( col += w ))
    (( col > COLUMNS )) && (( r++, col = 1 ))
  done
  (( best < 0 )) && best=$last                               # left of the text on that row
  if (( best < 0 )); then                                    # below everything → end
    CURSOR=$n
  elif (( best > n )); then                                  # inside the gray suggestion
    BUFFER+=${POSTDISPLAY[1,best-n]}; CURSOR=${#BUFFER}
  else
    CURSOR=$best
  fi
  zle -R
}
function zmouse {
  case ${1:-status} in
    on|auto|off) typeset -g ZSH_MOUSE=$1
                 [[ $1 == off ]] && _zs_mouse_emit 0
                 print -r -- "mouse: $1${${1:#off}:+   (click in the command to move the cursor)}" ;;
    toggle)      if [[ $ZSH_MOUSE == off ]]; then zmouse auto; else zmouse off; fi ;;
    status)      print -r -- "mouse: $ZSH_MOUSE    (zmouse auto | on | off — persist: ZSH_MOUSE=auto in ~/.zshrc.local)" ;;
    *)           print "zmouse auto|on|off|toggle" ;;
  esac
}

# =====================================================================
#  2. SHIFT-SELECT: an editor-style selection inside the command line
# =====================================================================
# Modelled on jirutka/zsh-shift-select: while a selection exists we switch to a
# private keymap in which printable keys replace it, Delete/Backspace remove it,
# and anything else drops the selection and is replayed in the normal keymap.
_zs_sel_start() { (( REGION_ACTIVE )) || { MARK=$CURSOR; REGION_ACTIVE=1 }; zle -K zs-select }
_zs_sel_end()   { zle deactivate-region 2>/dev/null; REGION_ACTIVE=0; zle -K main }
_zs_sel_left()      { _zs_sel_start; zle .backward-char }
_zs_sel_right()     { _zs_sel_start; zle .forward-char }
_zs_sel_wleft()     { _zs_sel_start; zle .backward-word }
_zs_sel_wright()    { _zs_sel_start; zle .forward-word }
_zs_sel_home()      { _zs_sel_start; zle .beginning-of-line }
_zs_sel_end_line()  { _zs_sel_start; zle .end-of-line }
_zs_sel_all()       { MARK=0; CURSOR=${#BUFFER}; REGION_ACTIVE=1; zle -K zs-select }
_zs_sel_text()      { local -i a=$(( MARK < CURSOR ? MARK : CURSOR )) z=$(( MARK < CURSOR ? CURSOR : MARK )); REPLY=${BUFFER[a+1,z]} }
_zs_sel_replay()    { _zs_sel_end; zle -U -- "$KEYS" }
_zs_sel_replace()   { zle .kill-region; _zs_sel_end; zle -U -- "$KEYS" }
_zs_sel_delete()    { zle .kill-region; _zs_sel_end }
_zs_sel_copy()      { _zs_sel_text; print -rn -- "$REPLY" | pbcopy; _zs_sel_end; zle -M "copied ${#REPLY} chars" }
_zs_sel_cut()       { _zs_sel_text; print -rn -- "$REPLY" | pbcopy; zle .kill-region; _zs_sel_end; zle -M "cut ${#REPLY} chars" }
_zs_copy_line() { print -rn -- "$BUFFER" | pbcopy; zle -M "copied the command line" }

() {
  local w
  for w in _zs_sel_{left,right,wleft,wright,home,end_line,all,replay,replace,delete,copy,cut} \
           _zs_copy_line _zs_mouse_widget; do
    zle -N $w
  done
  bindkey -N zs-select
  bindkey -M zs-select -R '^@'-'^?' _zs_sel_replay        # anything → drop selection, replay
  bindkey -M zs-select -R ' '-'~'   _zs_sel_replace       # printable → replaces the selection
  bindkey -M zs-select '^?' _zs_sel_delete '^H' _zs_sel_delete '^[[3~' _zs_sel_delete
  bindkey -M zs-select '^[w' _zs_sel_copy '^W' _zs_sel_cut
  # the same shift-motions extend the selection in both keymaps.
  # Terminal.app / xterm / Ghostty send different codes for the modifier combos.
  local k km
  for km in main zs-select; do
    for k in '^[[1;2D';            do bindkey -M $km $k _zs_sel_left;     done
    for k in '^[[1;2C';            do bindkey -M $km $k _zs_sel_right;    done
    for k in '^[[1;4D' '^[[1;10D' '^[[1;6D' '^[^[[1;2D'; do bindkey -M $km $k _zs_sel_wleft;  done
    for k in '^[[1;4C' '^[[1;10C' '^[[1;6C' '^[^[[1;2C'; do bindkey -M $km $k _zs_sel_wright; done
    for k in '^[[1;2H';            do bindkey -M $km $k _zs_sel_home;     done
    for k in '^[[1;2F';            do bindkey -M $km $k _zs_sel_end_line; done
  done
  bindkey -M zs-select '^[[<' _zs_mouse_widget '^[[M' _zs_mouse_widget
  # mouse reports
  bindkey -M emacs '^[[<' _zs_mouse_widget
  bindkey -M emacs '^[[M' _zs_mouse_widget
}

# =====================================================================
#  3. SMALL THINGS THAT ADD UP
# =====================================================================
_zs_up() {     # multi-line command: move a line; otherwise history substring search
  (( $+functions[_zs_car_nav] )) && _zs_car_nav -1 && return 0   # carousel list showing: browse it
  if [[ $LBUFFER == *$'\n'* ]]; then zle .up-line
  elif (( $+widgets[history-substring-search-up] )); then zle history-substring-search-up
  else zle .up-line-or-history; fi
  [[ -n $_ZS_AIMODE && -n $BUFFER ]] && _ZS_AIPEND=1     # AI modes: a recalled line is a command
  return 0
}
_zs_down() {
  (( $+functions[_zs_car_nav] )) && _zs_car_nav 1 && return 0   # carousel list showing: browse it
  if [[ $RBUFFER == *$'\n'* ]]; then zle .down-line
  elif (( $+widgets[history-substring-search-down] )); then zle history-substring-search-down
  else zle .down-line-or-history; fi
  [[ -n $_ZS_AIMODE && -n $BUFFER ]] && _ZS_AIPEND=1
  return 0
}
_zs_ctrl_z() {  # the Ctrl+Z round trip: suspend with Ctrl+Z, come back with Ctrl+Z
  if [[ -z $BUFFER ]]; then
    if (( ${#jobstates} )); then BUFFER=' fg'; zle .accept-line
    else zle -M "no suspended jobs"; fi
  else
    zle push-input; zle -M "line parked — it comes back after the next command"
  fi
}
zle -N _zs_up; zle -N _zs_down; zle -N _zs_ctrl_z
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(_zs_up _zs_down)

# =====================================================================
#  4. WATCHER: long commands that finish while you are elsewhere
# =====================================================================
typeset -g _ZS_WATCH_NOTE=$ZSH_CACHE/watch-note
_zs_tab_output() {   # last few KB of THIS tab/session (found by tty): Terminal.app or iTerm2
  if [[ $TERM_PROGRAM == iTerm.app && -n $TTY ]]; then
    osascript -e 'on run a' -e 'tell application "iTerm2"' \
      -e 'repeat with w in windows' -e 'repeat with t in tabs of w' -e 'repeat with s in sessions of t' \
      -e 'if tty of s is (item 1 of a) then return text of s' \
      -e 'end repeat' -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'end run' -- "$TTY" 2>/dev/null | tail -c 6000
    return
  fi
  [[ $TERM_PROGRAM == Apple_Terminal && -n $TTY ]] || return 1
  osascript -e 'on run a' -e 'tell application "Terminal"' \
    -e 'repeat with w in windows' -e 'repeat with t in tabs of w' \
    -e 'if tty of t is (item 1 of a) then return history of t' \
    -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'end run' -- "$TTY" 2>/dev/null | tail -c 6000
}
_zs_watch_report() {   # runs detached: <cmd> <status> <seconds>
  emulate -L zsh
  local cmd=$1 st=$2 secs=$3 why='' out=''
  local head="${cmd[1,50]}"
  if (( st == 0 )); then
    _zs_notify "✓ done in ${secs}s" "$head"; return 0
  fi
  if (( $+functions[_zai_up] )) && _zai_up; then
    (( ZSH_WATCH_CAPTURE )) && out=$(_zs_tab_output | _zai_redact)
    why=$(ZAI_STATUS=watch _zai_request "A long-running shell command failed while the user was away. In ONE short sentence (max 18 words), say the most likely reason. If there is no output, reason from the command and exit status." \
      "Command: $(print -r -- $cmd | _zai_redact)
Exit status: $st
Output tail:
${out:-(not captured)}" 60 0.1 2>/dev/null)
  fi
  _zs_notify "✗ exit $st after ${secs}s" "${why:-$head}"
  print -r -- "${why:+$why   }(${head}, exit $st · wtf for details)" >> $_ZS_WATCH_NOTE      # append: two jobs finishing together both get shown
}
_zs_watch_note() {    # every prompt: show a summary that arrived while you were away
  [[ -s $_ZS_WATCH_NOTE ]] || return 0
  # claim the notes by renaming the file: rename is atomic, so exactly one terminal shows them, and a note
  # written a moment later starts a fresh file (the old read-then-delete destroyed notes that arrived in between)
  local claim=$_ZS_WATCH_NOTE.claim.${sysparams[pid]}
  zf_mv -f $_ZS_WATCH_NOTE $claim 2>/dev/null || return 0
  print -P -- "%F{$ZC[warn]}◆ watcher:%f ${$(<$claim)//\%/%%}"
  zf_rm -f $claim
}
_zs_watch_check() {   # <status> <seconds> — called from _zs_precmd after a real command
  (( ZSH_WATCH && $2 >= ZSH_WATCH_AFTER && $1 != 130 )) || return 0
  case ${${(z)_ZS_LAST_CMD}[1]} in
    (nvim|vim|vi|emacs|less|man|ssh|top|btm|htop|lazygit|lg|gitui|yazi|y|claude|ai|tmux|watch|fg) return 0 ;;
  esac
  _zs_term_is_front && return 0
  ( _zs_watch_report "$_ZS_LAST_CMD" $1 ${2%.*} ) &!
  return 0
}

function ciw {   # ciw [run-id] — watch a GitHub Actions run in the background
  emulate -L zsh
  (( $+commands[gh] )) || { print -u2 "ciw: needs gh"; return 1 }
  local id=$1 br
  if [[ -z $id ]]; then
    br=$(git branch --show-current 2>/dev/null)
    id=$(gh run list ${br:+--branch $br} -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
  fi
  [[ -n $id ]] || { print -u2 "ciw: no runs found${br:+ for $br}"; return 1 }
  local repo=${$(git rev-parse --show-toplevel 2>/dev/null):t}
  print -r -- "watching run $id${repo:+ ($repo)} — you get a notification when it finishes"
  (
    gh run watch $id --exit-status --interval 20 >/dev/null 2>&1
    local -i rc=$?
    if (( rc == 0 )); then _zs_notify "✓ CI passed${repo:+ · $repo}" "run $id"; exit 0; fi
    local logs why=''
    logs=$(gh run view $id --log-failed 2>/dev/null | tail -c 9000 | _zai_redact)
    if [[ -n $logs ]] && (( $+functions[_zai_up] )) && _zai_up; then
      why=$(ZAI_STATUS=ci _zai_request "A CI run failed. From the failed-step log, give the root cause in ONE sentence (max 20 words), naming the failing test/step when visible." "$logs" 70 0.1 2>/dev/null)
    fi
    _zs_notify "✗ CI failed${repo:+ · $repo}" "${why:-run $id — gh run view $id --log-failed}"
    print -r -- "CI run $id failed: ${why:-see gh run view $id --log-failed}" >> $_ZS_WATCH_NOTE
  ) &!
}

# =====================================================================
#  hooks
# =====================================================================
autoload -Uz add-zsh-hook add-zle-hook-widget
add-zle-hook-widget line-init       _zs_mouse_init
add-zle-hook-widget line-pre-redraw _zs_mouse_redraw
add-zle-hook-widget line-finish     _zs_mouse_finish
add-zsh-hook preexec _zs_mouse_finish          # belt and braces: commands never get mouse reports
add-zsh-hook zshexit _zs_mouse_finish
