# =====================================================================
#  carousel.zsh — a live list of past commands under the prompt while you type
#
#    type ≥2 chars    up to ZSH_CAROUSEL_N matches appear in a column on the
#                     right half under the line: commands that START with what
#                     you typed first, then ones that contain it — ranked like
#                     the gray suggestion and Ctrl+N (ran in this directory ×3,
#                     frequency, recency). Only commands that succeeded.
#    ↑ / ↓            move the highlight (▸). What you typed is NOT changed
#                     while you browse. ↓ past the last visible row scrolls
#                     in the next match (up to ZSH_CAROUSEL_MAX); past the very
#                     last one it wraps to the top; ↑ past the top = no highlight.
#    Enter            highlighted entry → it goes on the line (Enter again runs
#                     it). Nothing highlighted → Enter runs your line as always.
#    ↑ on an empty line / a recalled line → history search, exactly as before
#                     (the list only opens for text you typed).
#
#  PATH MODE — when the word you are typing is a path (starts with / ~ ./ ../ or contains a /, or is an argument of
#  cd/ls/cat/vim/cp/… ) the list becomes the folder's contents (folders first, size for files). In a window ≥ 80
#  columns it is TWO panes, like ranger/yazi: this folder on the left, and on the right an automatic preview of
#  whatever is highlighted — a folder's contents, or the first lines of a text file:
#    ↑ / ↓            move the highlight
#    →                open the highlighted folder (its contents appear) / insert the highlighted file
#    ←                go back one folder
#    Enter            same as → on the highlighted entry (nothing highlighted: runs the line as usual)
#  ← and → only act when a path list is open, a row is highlighted (or there is a single entry), and the cursor is at
#  the end of the line — otherwise they move the cursor / accept the gray suggestion exactly as before.
#    ZSH_CAROUSEL=0   off  (e.g. in ~/.zshrc.local)
#
#  Drawn with zle -M (the message area under the line), never inside the line
#  itself — so it can't interfere with the prompt, autosuggestions, syntax
#  highlighting or the cursor. (Drawing it inside the line via POSTDISPLAY to get
#  a colored highlight was tried 2026-09-27 and wrecked the display — don't.)
#  The cost: zle -M is plain text, no colors.
# =====================================================================

typeset -g  ZSH_CAROUSEL=${ZSH_CAROUSEL:-1}
typeset -gi ZSH_CAROUSEL_N=${ZSH_CAROUSEL_N:-5}        # rows shown at once
typeset -gi ZSH_CAROUSEL_MAX=${ZSH_CAROUSEL_MAX:-50}   # matches fetched — ↓ past the last row scrolls to the next
typeset -g  _zs_car_key=$'\0'
typeset -ga _zs_car_cmds=() _zs_car_meta=()
typeset -gi _zs_car_idx=0 _zs_car_shown=0 _zs_car_top=1   # _zs_car_top: first row of the visible window
# PATH MODE state (see _zs_car_path_ctx): what kind of list this is, the token being typed, and the folder it names
typeset -g  _zs_car_mode=hist _zs_car_raw='' _zs_car_dirpart='' _zs_car_real=''
typeset -gi ZSH_CAROUSEL_PATH_ROWS=${ZSH_CAROUSEL_PATH_ROWS:-8} _zs_car_rows=5   # rows shown: history N, path ZSH_CAROUSEL_PATH_ROWS
typeset -ga _zs_car_isdir=()
# commands whose bare words are file/folder names — after these, a path list opens even without a slash typed
typeset -ga _zs_car_pathcmds=( cd pushd ls ll la l eza lsd tree cat bat less more head tail nvim vim vi nano code open
                               cp mv rm rmdir mkdir touch source ln chmod stat file du wc )

_zs_car_age() {   # minutes → 5m / 3h / 12d
  if   (( $1 < 60 ));   then REPLY="${1}m"
  elif (( $1 < 1440 )); then REPLY="$(( $1 / 60 ))h"
  else                       REPLY="$(( $1 / 1440 ))d"; fi
}

_zs_car_fetch() {   # <typed text> → _zs_car_cmds / _zs_car_meta
  emulate -L zsh
  _zs_car_cmds=() _zs_car_meta=()
  local q=$1 p=${1//\'/\'\'} d=${PWD//\'/\'\'} row
  local -a f rows
  if (( $+functions[_zs_have_db] )) && _zs_have_db; then
    rows=( ${(f)"$(_zs_sql "SELECT command, MAX(cwd = '$d'), COUNT(*),
        CAST((CAST(strftime('%s','now') AS INTEGER) - MAX(timestamp) / 1000000000) / 60 AS INTEGER)
      FROM history
      WHERE (substr(command, 1, ${#q}) = '$p' OR instr(command, '$p') > 0)
        AND command != '$p' AND deleted_at IS NULL AND exit = 0 AND ltrim(command) NOT LIKE 'zagent%'   -- zagent = how ?? runs, not a command you typed
        AND instr(command, char(10)) = 0 AND length(command) < 300
      GROUP BY command
      ORDER BY (substr(command, 1, ${#q}) = '$p') * 5.0 + MAX(cwd = '$d') * 3.0 + MIN(COUNT(*), 20) / 10.0
             - MIN((CAST(strftime('%s','now') AS REAL) - MAX(timestamp) / 1e9) / 86400.0, 90.0) / 30.0 DESC
      LIMIT $ZSH_CAROUSEL_MAX;")"} )
    for row in $rows; do
      f=( "${(@ps:\t:)row}" )
      _zs_car_cmds+=( "$f[1]" )
      _zs_car_age ${f[4]:-0}
      _zs_car_meta+=( "${${f[2]:#0}:+here · }${f[3]}× · $REPLY" )
    done
  else   # no atuin: plain zsh history, most recent first, no ranking
    local -a m=( ${(u)${(M)${(v)history}:#*${(b)q}*}} )
    m=( ${m:#$q} )
    m=( ${${m:#zagent*}:# zagent*} )   # ?? internals, not commands
    _zs_car_cmds=( ${m[1,ZSH_CAROUSEL_MAX]} )
    _zs_car_meta=( ${_zs_car_cmds/*/history} )
  fi
}

# ---------------------------------------------------------------------------------------------------------------
#  path mode
# ---------------------------------------------------------------------------------------------------------------
_zs_car_size() {   # bytes → 1.2K / 3.4M
  local -i b=$1
  if   (( b < 1024 ));       then REPLY="${b}B"
  elif (( b < 1048576 ));    then REPLY=$(( b / 1024.0 )); REPLY="${REPLY[1,3]%.}K"
  elif (( b < 1073741824 )); then REPLY=$(( b / 1048576.0 )); REPLY="${REPLY[1,3]%.}M"
  else                            REPLY=$(( b / 1073741824.0 )); REPLY="${REPLY[1,3]%.}G"; fi
}

# Is the word under the cursor a path? Sets _zs_car_raw (exactly as typed, quotes and all), _zs_car_dirpart (its
# folder part as typed, ending in /) and returns the folder to list in $REPLY, with the filename prefix in $reply[1].
_zs_car_path_ctx() {
  emulate -L zsh
  [[ -z $RBUFFER || $RBUFFER == [[:space:]]* ]] || return 1          # editing in the middle of a word: leave it alone
  [[ $LBUFFER == *$'\n'* || -z $LBUFFER ]] && return 1
  local -a w=( ${(z)LBUFFER} )
  (( $#w )) || return 1
  local raw tok cmd dirpart pfx real
  local -i i cmdpos=1
  [[ $LBUFFER == *[[:space:]] && $LBUFFER != *'\ ' ]] && raw='' || raw=$w[-1]
  for (( i = 1; i <= $#w; i++ )); do [[ $w[i] == (\;|\||\|\||\&\&|\&) ]] && cmdpos=$(( i + 1 )); done
  while [[ $w[cmdpos] == (sudo|env|command|noglob|time|nocorrect|builtin|exec) ]] && (( cmdpos < $#w )); do (( cmdpos++ )); done
  cmd=$w[cmdpos]
  local q=''
  if [[ $raw == [\'\"]* ]]; then
    q=$raw[1]; tok=${raw[2,-1]}                                      # opened a quote and still inside it (${(Q)} keeps an unterminated quote)
    [[ $tok == *$q ]] && return 1                                    # the quote is already closed: that word is finished
  else tok=${(Q)raw}; fi
  [[ $tok == -* ]] && return 1
  # a path if it looks like one (any word), or a bare word / empty word that follows a command taking file names
  if [[ $tok == (/|\~|./|../)* || $tok == */* ]]; then :
  elif (( $_zs_car_pathcmds[(Ie)$cmd] )) && { [[ -z $raw ]] || (( $#w > cmdpos )); }; then :
  else return 1; fi
  if   [[ $tok == '~' ]];    then dirpart='~/'; pfx=''
  elif [[ $tok == */* ]];    then dirpart=${tok%/*}/; pfx=${tok##*/}
  else                            dirpart='';  pfx=$tok; fi
  real=${dirpart/#\~/$HOME}; [[ -z $real ]] && real=$PWD/
  [[ $real == /* ]] || real=$PWD/$real
  [[ -d $real ]] || return 1
  _zs_car_raw=$raw _zs_car_dirpart=$dirpart
  typeset -g _zs_car_quote=$q
  [[ $cmd == (cd|pushd) ]] && typeset -gi _zs_car_dironly=1 || typeset -gi _zs_car_dironly=0
  reply=( "$pfx" ); REPLY=$real
  return 0
}

_zs_car_path_fetch() {   # <folder> <prefix> → _zs_car_cmds/_meta/_isdir ; 1 when nothing matches
  emulate -L zsh
  local d=${1%/} pfx=$2 e base lp=${(L)2} ci=1 r
  local -a dirs files st
  [[ $pfx == *[[:upper:]]* ]] && ci=0                                # smartcase: an uppercase letter makes it exact
  _zs_car_cmds=() _zs_car_meta=() _zs_car_isdir=()
  dirs=(  $d/*(N-/D[1,3000]) )
  (( _zs_car_dironly )) || files=( $d/*(N^-/D[1,3000]) )
  for e in $dirs $files; do
    base=${e:t}
    [[ $base == .* && $pfx != .* ]] && continue
    if (( ci )); then [[ ${(L)base} == "$lp"* ]] || continue; else [[ $base == "$pfx"* ]] || continue; fi   # quoted: a * or [ in the prefix is literal
    if [[ -d $e ]]; then _zs_car_cmds+=( "$base/" ); _zs_car_meta+=( dir ); _zs_car_isdir+=( 1 )
    else
      zstat -A st +size $e 2>/dev/null; _zs_car_size ${st[1]:-0}
      _zs_car_cmds+=( "$base" ); _zs_car_meta+=( $REPLY ); _zs_car_isdir+=( 0 )
    fi
    (( $#_zs_car_cmds >= 200 )) && break
  done
  (( $#_zs_car_cmds )) || { [[ -z $pfx ]] && return 2; return 1; }    # 2 = an existing but EMPTY folder (still worth showing: ← goes back)
  # the word is already a complete FILE name and nothing else continues it: a list of one is just noise
  (( $#_zs_car_cmds == 1 && ! _zs_car_isdir[1] )) && [[ $_zs_car_cmds[1] == $pfx ]] && { _zs_car_cmds=(); return 1 }
  return 0
}

_zs_car_parent() {   # <folder part as typed, ends in /> → the folder one level up, same style
  emulate -L zsh
  local p=${1%/}
  case $1 in
    '')               print -rn -- ../ ;;
    /)                print -rn -- / ;;
    '~/')             print -rn -- "${HOME:h}/" ;;
    ./)               print -rn -- ../ ;;
    ../|*/../)        print -rn -- "${1}../" ;;
    *)  if [[ $p == */* ]]; then p=${p%/*}; [[ -z $p ]] && p=/; [[ $p == / ]] && print -rn -- / || print -rn -- "$p/"
        else print -rn -- ./; fi ;;
  esac
}

# put a path into the line in place of the word being typed, quoted the way it was started
_zs_car_path_put() {   # <full path as typed, e.g. ~/my dir/src/>
  emulate -L zsh
  local newtok=$1 q=$_zs_car_quote out
  if [[ -n $q ]]; then out=$q$newtok
  elif [[ $newtok == \~* ]]; then out="~${(q)newtok#\~}"
  else out=${(q)newtok}; fi
  LBUFFER=${LBUFFER:0:$(( ${#LBUFFER} - ${#_zs_car_raw} ))}$out
  CURSOR=$#BUFFER
}

# → or Enter on a highlighted row: open the folder (list its contents) / insert the file
_zs_car_path_open() {   # [index] — defaults to the highlighted row, or the only row
  emulate -L zsh
  local -i n=${1:-$_zs_car_idx}
  (( n )) || { (( $#_zs_car_cmds == 1 )) && n=1; }
  (( n )) || return 1
  local name=$_zs_car_cmds[n]
  _zs_car_path_put "${_zs_car_dirpart}${name}"
  if (( _zs_car_isdir[n] )); then
    _zs_car_key=$BUFFER; _zs_car_refresh                             # folder: show what is inside
  else
    [[ -n $_zs_car_quote ]] && LBUFFER+=$_zs_car_quote               # file: close the quote it was opened with
    _zs_car_key=$BUFFER; _zs_car_clear                               # done with the list
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------------------------
#  choose the list for the current line, draw it
# ---------------------------------------------------------------------------------------------------------------
# what to show in the right pane for the highlighted entry → reply=( lines ), at most $1 of them
_zs_car_preview() {   # <max lines> <full path>
  emulate -L zsh
  local max=$1 p=$2 e base
  local -a dirs files out
  reply=()
  if [[ -d $p ]]; then
    dirs=( ${p%/}/*(N-/D) ); files=( ${p%/}/*(N^-/D) )
    for e in $dirs; do base=${e:t}; [[ $base == .* ]] && continue; out+=( "$base/" ); done
    for e in $files; do base=${e:t}; [[ $base == .* ]] && continue; out+=( "$base" ); done
    (( $#out )) || out=( "(empty folder)" )
    (( $#out > max )) && out=( ${out[1,max-1]} "… ${$(( $#out - max + 1 ))} more" )
    reply=( "${out[@]}" )
  elif [[ -f $p ]]; then
    local -a st; zstat -A st +size $p 2>/dev/null
    if (( ${st[1]:-0} > 2000000 )); then reply=( "(large file)" )
    elif command grep -qI . $p 2>/dev/null; then
      reply=( "${(@f)$(command head -n $max $p 2>/dev/null | command expand -t 4)}" )
    else reply=( "(binary file)" ); fi
  else reply=( "" ); fi
}

# path mode, wide window: [ this folder | preview of the highlighted entry ], flush right
_zs_car_render_two() {
  emulate -L zsh
  local out='' name meta mark lpart rpart hdr sel=''
  local -a reply
  local -i region lw rw i k rows=$_zs_car_rows total=$#_zs_car_cmds last
  (( region = COLUMNS * 2 / 3 )); (( region < 72 )) && region=72; (( region > COLUMNS - 2 )) && region=$(( COLUMNS - 2 ))
  (( lw = region * 45 / 100 )); (( rw = region - lw - 3 ))
  local pad=${(l:COLUMNS - region - 1:: :)}
  (( last = _zs_car_top + rows - 1 )); (( last > total )) && last=total
  local where=${_zs_car_dirpart:-./}; (( ${#where} > lw )) && where="…${where[-$(( lw - 1 )),-1]}"
  local pos="$total"; (( _zs_car_idx )) && pos="$_zs_car_idx/$total"
  local more=''; (( last < total )) && more=' ↓'
  local -i mw=0; for meta in ${_zs_car_meta[_zs_car_top,last]}; do (( ${#meta} > mw )) && mw=${#meta}; done
  local -i room=$(( lw - mw - 4 )); (( room < 6 )) && room=6
  local -a right=()
  if (( _zs_car_idx )); then
    sel=$_zs_car_cmds[_zs_car_idx]
    _zs_car_preview $rows "${_zs_car_real%/}/${sel}"; right=( "${reply[@]}" )
    hdr="${(r:lw:)where}  ${pos}${more}"
  else
    right=( "↓ to pick an entry; → opens it," "← goes back a folder." )
    hdr="${(r:lw:)where}  ${pos}${more}"
  fi
  out+="${pad}${hdr}"$'\n'
  local emptymsg='(empty folder)'
  if (( total == 0 )); then out+="${pad}${(r:lw:)emptymsg} │ ← back"$'\n'; fi
  for (( i = _zs_car_top, k = 1; i <= last; i++, k++ )); do
    name=$_zs_car_cmds[i]; meta=$_zs_car_meta[i]
    (( ${#name} > room )) && name="${name[1,room-1]}…"
    if (( i == _zs_car_idx )); then mark='▸'; else mark=' '; fi
    lpart="${mark} ${(r:room:)name} ${(l:mw:)meta}"
    rpart=${right[k]//$'\t'/  }; (( ${#rpart} > rw )) && rpart="${rpart[1,rw-1]}…"
    out+="${pad}${(r:lw:)lpart} │ ${rpart}"$'\n'
  done
  # the preview can be taller than the list (a folder with more entries than rows shown)
  for (( ; k <= rows && k <= $#right; k++ )); do
    rpart=${right[k]}; (( ${#rpart} > rw )) && rpart="${rpart[1,rw-1]}…"
    out+="${pad}${(r:lw:: :)}   │ ${rpart}"$'\n'
  done
  zle -M -- "${out%$'\n'}"
  _zs_car_shown=1
}

_zs_car_render() {   # a column on the right half; rows left-aligned inside it, so ▸ only moves up/down
  emulate -L zsh
  if [[ $_zs_car_mode == path ]] && (( COLUMNS >= 80 )); then _zs_car_render_two; return; fi
  local out='' pad cmd meta mark hdr
  local -i colw mw room i
  (( colw = COLUMNS / 2 ))
  (( colw < 44 )) && colw=$(( COLUMNS - 2 ))          # narrow window: one full-width column
  pad=${(l:COLUMNS - colw - 1:: :)}
  local -i total=$#_zs_car_cmds last
  (( last = _zs_car_top + _zs_car_rows - 1 ))
  (( last > total )) && last=total
  for meta in ${_zs_car_meta[_zs_car_top,last]}; do (( ${#meta} > mw )) && mw=${#meta}; done
  (( room = colw - mw - 5 ))
  (( room < 8 )) && room=8
  local pos="$total match$( (( total == 1 )) || print -rn es)"
  (( _zs_car_idx )) && pos="$_zs_car_idx/$total"
  local more=''; (( last < total )) && more=' ↓more'
  if [[ $_zs_car_mode == path ]]; then
    local where=${_zs_car_dirpart:-./}; (( ${#where} > 26 )) && where="…${where[-25,-1]}"
    if (( total )); then hdr="${where} ${pos}${more} · ↑↓ · ← back · → open"
    else hdr="${where} empty folder · ← back"; fi
  else
    hdr="history ${pos}${more} · ↑↓ select · Enter take"
  fi
  out+="${pad}${hdr}"$'\n'
  for (( i = _zs_car_top; i <= last; i++ )); do
    cmd=$_zs_car_cmds[i]; meta=$_zs_car_meta[i]
    (( ${#cmd} > room )) && cmd="${cmd[1,room-1]}…"
    if (( i == _zs_car_idx )); then mark='▸'; else mark=' '; fi
    out+="${pad}${mark} ${(r:room:)cmd}  ${(l:mw:)meta}"$'\n'
  done
  zle -M -- "${out%$'\n'}"
  _zs_car_shown=1
}

_zs_car_clear() {
  _zs_car_cmds=() _zs_car_meta=() _zs_car_isdir=() _zs_car_idx=0 _zs_car_top=1
  (( _zs_car_shown )) && { zle -M ''; _zs_car_shown=0 }
  return 0
}

_zs_car_refresh() {   # pick history or path list for the CURRENT line, fetch it, draw it (or clear)
  local -a reply; local REPLY
  _zs_car_idx=0 _zs_car_top=1
  if _zs_car_path_ctx; then
    local real=$REPLY pfx=$reply[1]
    _zs_car_path_fetch $real $pfx; local -i prc=$?
    if (( prc == 0 || prc == 2 )); then _zs_car_mode=path _zs_car_real=$real _zs_car_rows=$ZSH_CAROUSEL_PATH_ROWS; _zs_car_render; return 0; fi
  fi
  _zs_car_mode=hist _zs_car_rows=$ZSH_CAROUSEL_N
  if (( ${#BUFFER} < 2 )) || [[ $BUFFER == ' '* || $BUFFER == *$'\n'* || $BUFFER == '?'* ]]; then _zs_car_clear; return 0; fi
  _zs_car_fetch "$BUFFER"
  if (( $#_zs_car_cmds )); then _zs_car_render; else _zs_car_clear; fi
  return 0
}

_zs_car_redraw() {   # zle-line-pre-redraw: recompute only when the TYPED text changed
  (( ZSH_CAROUSEL )) || return 0
  [[ -n $_ZS_AIMODE ]] && return 0                  # AI modes own the line
  (( PENDING || KEYS_QUEUED_COUNT )) && return 0    # paste / fast typing: catch up on the last key
  [[ $BUFFER == $_zs_car_key ]] && return 0         # browsing the list, cursor moves, messages: leave them
  _zs_car_key=$BUFFER _zs_car_idx=0 _zs_car_top=1
  # only for text you typed — a line recalled with ↑ (history search) or pasted
  # must not open the list, or the next ↑ would browse the list instead of history
  case $LASTWIDGET in
    (*history*|_zs_up|_zs_down|*paste*|*autosuggest-accept*) _zs_car_clear; return 0 ;;
  esac
  _zs_car_refresh
  return 0
}

# ↑/↓ while the list is showing: move the highlight. Never touches what you typed.
# Returns 1 when the list isn't showing, so _zs_up/_zs_down fall through to history.
_zs_car_nav() {   # <+1|-1>
  (( ZSH_CAROUSEL )) && [[ -z $_ZS_AIMODE ]] || return 1
  if [[ $BUFFER != $_zs_car_key ]]; then   # typed faster than the last redraw: refresh first
    _zs_car_key=$BUFFER
    _zs_car_refresh
  fi
  (( _zs_car_shown && $#_zs_car_cmds )) || return 1
  local -i n=$#_zs_car_cmds
  (( _zs_car_idx = (_zs_car_idx + $1 + n + 1) % (n + 1) ))   # 0 = nothing highlighted; wraps around the FULL list
  if (( _zs_car_idx == 0 )); then _zs_car_top=1                                      # back to the top
  elif (( _zs_car_idx < _zs_car_top )); then _zs_car_top=$_zs_car_idx                   # scrolled up past the window
  elif (( _zs_car_idx > _zs_car_top + _zs_car_rows - 1 )); then (( _zs_car_top = _zs_car_idx - _zs_car_rows + 1 )); fi   # scrolled down
  _zs_car_render
  return 0
}

# Enter with an entry highlighted: history → put the command on the line; path → open folder / insert file.
# Returns 1 with nothing highlighted, so Enter behaves exactly as before.
_zs_car_take() {
  (( _zs_car_idx && _zs_car_shown )) || return 1
  if [[ $_zs_car_mode == path ]]; then _zs_car_path_open; return 0; fi
  BUFFER=$_zs_car_cmds[_zs_car_idx]; CURSOR=$#BUFFER
  _zs_car_key=$BUFFER
  _zs_car_clear
  return 0
}

# ← / →: only while a PATH list is open and the cursor is at the end; everything else is the normal key
_zs_car_path_active() {
  (( ZSH_CAROUSEL && _zs_car_shown )) && [[ $_zs_car_mode == path && -z $_ZS_AIMODE ]] &&
    [[ $BUFFER == $_zs_car_key ]] && (( CURSOR == $#BUFFER ))
}
_zs_car_right() {
  if _zs_car_path_active && { (( _zs_car_idx )) || (( $#_zs_car_cmds == 1 )); }; then _zs_car_path_open
  else zle forward-char; fi
  return 0
}
_zs_car_left() {
  if _zs_car_path_active; then
    local up; up=$(_zs_car_parent $_zs_car_dirpart)
    _zs_car_path_put $up
    _zs_car_key=$BUFFER; _zs_car_refresh
  else zle backward-char; fi
  return 0
}

_zs_car_init()   { _zs_car_key=$'\0' _zs_car_idx=0 _zs_car_shown=0 _zs_car_top=1 _zs_car_mode=hist; _zs_car_cmds=() _zs_car_meta=() _zs_car_isdir=(); return 0 }
_zs_car_finish() { _zs_car_clear }   # never leave the list behind in scrollback

zle -N _zs_car_right
zle -N _zs_car_left
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init       _zs_car_init
add-zle-hook-widget line-pre-redraw _zs_car_redraw
add-zle-hook-widget line-finish     _zs_car_finish
bindkey -M emacs '^[[C' _zs_car_right '^[OC' _zs_car_right '^[[D' _zs_car_left '^[OD' _zs_car_left
