# =====================================================================
#  habits.zsh — the learning layer
#
#  Everything here reads data you already produce (atuin's SQLite history:
#  command, cwd, exit code, session, timestamp). Nothing leaves the machine.
#
#  Live, per keystroke (async, never blocks typing):
#    sequence  "after `git add …` you run `git commit …`"   pure zsh, no fork
#    smart     ranks by: ran in THIS directory ×3, frequency, recency
#  On demand:
#    habits            mine what you keep typing → one-key abbreviations
#    habits seq        commands you always run back-to-back → one shortcut
#    habits typos      commands you keep mistyping → auto-correct aliases
#    habits here       what you usually run in this directory   (Ctrl+X h)
#    habits report     usage statistics          habits ai → LLM reads them
#  Weekly (background): re-scan, and tell you once when there is something new.
# =====================================================================

(( $+functions[_zs_locked] )) || source ${${(%):-%x}:A:h}/lib.zsh 2>/dev/null   # locking + atomic writes (lib.zsh), found next to this file
typeset -g _ZS_ATUIN_DB=${ATUIN_DB_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/atuin/history.db}

_zs_sql() { sqlite3 -readonly -separator $'\t' $_ZS_ATUIN_DB "$1" 2>/dev/null }
_zs_have_db() { [[ -r $_ZS_ATUIN_DB ]] && (( $+commands[sqlite3] )) }
# atuin stores nanoseconds
_zs_since() { print -r -- "(CAST(strftime('%s','now') AS INTEGER) - ${1:-120} * 86400) * 1000000000" }

# ---- live suggestions -------------------------------------------------
# Like upstream match_prev_cmd, but (a) matches on the first two words of the
# previous command so `git add src/x.py` still predicts `git commit …`, and
# (b) stays silent without real sequence evidence, letting `smart` decide.
_zsh_autosuggest_strategy_sequence() {
  emulate -L zsh; setopt extendedglob
  local prefix="${1//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"
  local pattern="$prefix*"
  local -a keys pw hw
  keys=( ${(k)history[(R)$~pattern]} )
  (( $#keys )) || return
  pw=( ${(z)history[$((HISTCMD-1))]} )
  (( $#pw )) || return
  local want="${pw[1]} ${pw[2]}" k
  for k in ${keys[1,150]}; do
    (( k > 1 )) || break
    hw=( ${(z)history[$((k-1))]} )
    [[ ${history[$k]} == (#s)[[:space:]]#zagent* ]] && continue   # ?? internals, not commands
    if [[ "${hw[1]} ${hw[2]}" == "$want" ]]; then
      typeset -g suggestion=$history[$k]
      return
    fi
  done
}

# One read-only SQLite query per keystroke, inside autosuggestions' async worker.
# score = 3·(ever succeeded in this directory) + min(uses,20)/10 − min(age_days,90)/30
_zsh_autosuggest_strategy_smart() {
  emulate -L zsh
  (( ZSH_SMART_SUGGEST )) && (( ${#1} >= 2 )) && _zs_have_db || return
  local p=${1//\'/\'\'} d=${PWD//\'/\'\'} out
  out=$(sqlite3 -readonly $_ZS_ATUIN_DB "SELECT command FROM history
    WHERE substr(command, 1, ${#1}) = '$p' AND length(command) > ${#1} AND length(command) < 200
      AND deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0 AND instr(command, char(10)) = 0
    GROUP BY command
    ORDER BY MAX(cwd = '$d') * 3.0 + MIN(COUNT(*), 20) / 10.0
           - MIN((CAST(strftime('%s','now') AS REAL) - MAX(timestamp) / 1e9) / 86400.0, 90.0) / 30.0 DESC
    LIMIT 1;" 2>/dev/null)
  [[ -n $out ]] && typeset -g suggestion=$out
}

# ---- this directory ------------------------------------------------------
_zs_here_top() {   # top N commands here, joined — used by the cd hint
  _zs_have_db || return
  local d=${PWD//\'/\'\'}
  local -a rows
  rows=( ${(f)"$(_zs_sql "SELECT command FROM history
    WHERE cwd = '$d' AND deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0 AND length(command) < 48 AND instr(command, char(10)) = 0
    GROUP BY command HAVING COUNT(*) >= 2 ORDER BY COUNT(*) DESC, MAX(timestamp) DESC LIMIT ${1:-3};")"} )
  print -r -- ${(j: · :)rows}
}
_zs_here_pick() {
  _zs_have_db || { print -u2 "needs atuin + sqlite3 (run zsh-setup)"; return 1 }
  local d=${PWD//\'/\'\'}
  _zs_sql "SELECT printf('%4dx  ', COUNT(*)) || command FROM history
    WHERE cwd = '$d' AND deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0 AND instr(command, char(10)) = 0
    GROUP BY command ORDER BY COUNT(*) DESC, MAX(timestamp) DESC LIMIT 100;" |
    fzf --height=50% --no-sort --prompt='here ❯ ' --header="what you usually run in ${PWD/#$HOME/~}"
}
_zs_here_widget() {
  local sel
  sel=$(_zs_here_pick)
  if [[ -n $sel ]]; then BUFFER=${sel#*x  }; CURSOR=${#BUFFER}; fi
  zle reset-prompt
}

# ---- mining ------------------------------------------------------------------
_zs_hist_dump() {   # successful single-line commands, one per line
  if _zs_have_db; then
    _zs_sql "SELECT command FROM history WHERE deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0
             AND instr(command, char(10)) = 0 AND timestamp > $(_zs_since ${1:-120});"
  else
    fc -ln 1 2>/dev/null        # no atuin: plain zsh history (no exit codes, no time window)
  fi
}

# → score<TAB>count<TAB>command, best first.  score ≈ keystrokes you would have saved.
# Counts every 2/3/4-word prefix plus long full lines, then drops a prefix when a
# longer form explains ≥80% of it (so `git commit -m` wins over `git commit`).
_zs_habits_candidates() {
  _zs_hist_dump ${1:-120} | awk -v min=${2:-6} -v minlen=8 '
    {
      line = $0
      sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
      n = split(line, w, /[ \t]+/)
      if (n < 2) next
      if (w[1] == "cd" || w[1] == "z" || w[1] == "zi" || w[1] == "ai" || w[1] == "habits" || w[1] == "?" || w[1] == "??") next
      p = w[1]
      for (i = 2; i <= n && i <= 4; i++) { p = p " " w[i]; c[p]++ }
      if (n > 4) { c[line]++; anc[line] = p }
    }
    END {
      for (k in c) {
        if (c[k] < min) continue
        parent = k; sub(/ [^ ]+$/, "", parent)
        if (parent != k && (parent in c) && c[k] >= 0.8 * c[parent]) drop[parent] = 1
        if ((k in anc) && c[k] >= 0.8 * c[anc[k]]) drop[anc[k]] = 1
      }
      for (k in c) {
        if (c[k] < min || (k in drop) || length(k) < minlen) continue
        t = k; q1 = gsub(/"/, "&", t); t = k; q2 = gsub(/\047/, "&", t)
        if (q1 % 2 || q2 % 2) continue
        if (k ~ /[|;&<>`$(){}\\]$/) continue
        printf "%d\t%d\t%s\n", c[k] * (length(k) - 3), c[k], k
      }
    }' | sort -t$'\t' -k1,1nr | head -n 60
}

_zs_abbr_file() { REPLY=${ABBR_USER_ABBREVIATIONS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh-abbr/user-abbreviations} }
_zs_abbr_exists() {   # is <name> already an abbreviation?
  _zs_abbr_file
  [[ -r $REPLY ]] && grep -Eq "^abbr (-[a-zA-Z-]+ )*\"?$1\"?=" $REPLY
}
_zs_known() {         # is <command> already covered by an abbreviation or alias?
  (( ${${(v)aliases}[(Ie)$1]} )) && return 0
  _zs_abbr_file
  [[ -r $REPLY ]] && grep -qF -- "$1" $REPLY
}
_zs_name_clash() {   # would <name> shadow something?
  (( $+commands[$1] || $+aliases[$1] || $+functions[$1] || $+builtins[$1] )) && return 0
  (( ${reswords[(Ie)$1]} || ${+_zs_taken[$1]} )) && return 0
  _zs_abbr_exists $1
}
# command → REPLY: short unique name built from word initials
#   git push origin main → gpom     docker compose up -d → dcud     uv run pytest → urp
_zs_abbr_name() {
  emulate -L zsh; setopt extendedglob
  local w name='' base
  local -i i=2
  for w in ${(z)1}; do
    w=${w##-##}; w=${w:t}
    [[ $w == [[:alpha:]]* ]] && name+=${(L)w[1]}
  done
  (( ${#name} >= 2 )) || name=${(L)${1%% *}[1,3]}
  base=${name[1,5]}; name=$base
  while _zs_name_clash $name; do name=$base$i; (( i++ )); done
  REPLY=$name
}
# learned.zsh is SOURCED at every shell start, so a torn or duplicated line there breaks or slows every
# terminal. One line per alias name (re-learning replaces it), written whole under a lock.
_zs_learn_alias() {   # <name> <expansion>
  emulate -L zsh
  _zs_locked $ZSH_CONF/learned.zsh _zs_learn_alias_locked "$1" "$2"
}
_zs_learn_alias_locked() {
  emulate -L zsh
  local name=$1 l; local -a reply out
  _zs_read_lines $ZSH_CONF/learned.zsh
  for l in "${reply[@]}"; do [[ $l == "alias ${(q)name}="* ]] || out+=( "$l" ); done
  out+=( "alias ${(q)name}=${(qq)2}" )
  _zs_write_lines $ZSH_CONF/learned.zsh "${out[@]}"
}
_zs_learn() {   # <name> <expansion> → abbreviation (expands visibly as you type); alias as fallback
  if (( $+functions[abbr] )) && abbr add "$1=$2" >/dev/null 2>&1; then
    print -P -- "  %F{$ZC[exe]}+%f %B$1%b → ${2//\%/%%}"
  else
    _zs_learn_alias "$1" "$2" || { print -u2 "could not save the alias (busy)"; return 1 }
    alias -- "$1=$2"
    print -P -- "  %F{$ZC[exe]}+%f %B$1%b → ${2//\%/%%}   %F{$ZC[dim]}(alias, in learned.zsh)%f"
  fi
}
_zs_fzf_multi() {   # stdin: display<TAB>…hidden fields… → selected lines
  fzf --multi --delimiter=$'\t' --with-nth=1 --no-sort --height=70% --bind=ctrl-a:select-all \
      --prompt="$1 ❯ " --header="$2"$'\n''TAB mark · ENTER create · Ctrl+A all · ESC cancel'
}

_zs_habits_shortcuts() {
  emulate -L zsh
  local score n cmd disp pick
  local -a rows picks f
  local -A _zs_taken
  _zs_habits_candidates 120 6 | while IFS=$'\t' read -r score n cmd; do
    [[ -n $cmd ]] || continue
    _zs_known "$cmd" && continue
    _zs_abbr_name "$cmd"; _zs_taken[$REPLY]=1
    printf -v disp '%-7s → %-44s %4d×  ~%d keys' "$REPLY" "$cmd" "$n" "$score"
    rows+=( "$disp"$'\t'"$REPLY"$'\t'"$cmd" )
  done
  if (( ! $#rows )); then
    print "nothing to learn yet — needs a command typed ≥6× in 120 days that has no shortcut."
    _zs_have_db || print "tip: with atuin (zsh-setup) this also uses exit codes, directories and sessions."
    return 0
  fi
  picks=( ${(f)"$(print -rl -- $rows | _zs_fzf_multi habits 'shortcut → what you keep typing   (uses · keystrokes saveable)')"} )
  for pick in $picks; do
    f=( "${(@ps:\t:)pick}" )
    _zs_learn "$f[2]" "$f[3]"
  done
  (( $#picks )) && print -P -- "%F{$ZC[dim]}type the shortcut + space to expand · rename: abbr rename <old> <new> · remove: abbr erase <name>%f"
  zf_rm -f $ZSH_CACHE/tip 2>/dev/null
  return 0
}

_zs_habits_sequences() {
  emulate -L zsh
  _zs_have_db || { print -u2 "sequences need atuin's database (run zsh-setup)"; return 1 }
  local n a b disp pick
  local -a rows picks f
  local -A _zs_taken
  _zs_sql "WITH o AS (
      SELECT command AS a, exit AS ea,
             LEAD(command) OVER (PARTITION BY session ORDER BY timestamp) AS b,
             LEAD(exit)    OVER (PARTITION BY session ORDER BY timestamp) AS eb
      FROM history
      WHERE deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND instr(command, char(10)) = 0 AND timestamp > $(_zs_since 120))
    SELECT COUNT(*) AS n, a, b FROM o
    WHERE b IS NOT NULL AND a <> b AND ea = 0 AND eb = 0
      AND length(a) BETWEEN 4 AND 60 AND length(b) BETWEEN 4 AND 60
    GROUP BY a, b HAVING n >= 4 ORDER BY n DESC LIMIT 25;" |
  while IFS=$'\t' read -r n a b; do
    [[ -n $b ]] || continue
    _zs_known "$a && $b" && continue
    _zs_abbr_name "$a $b"; _zs_taken[$REPLY]=1
    printf -v disp '%-7s → %s  &&  %s   (%d×)' "$REPLY" "$a" "$b" "$n"
    rows+=( "$disp"$'\t'"$REPLY"$'\t'"$a && $b" )
  done
  (( $#rows )) || { print "no repeated back-to-back pairs found yet."; return 0 }
  picks=( ${(f)"$(print -rl -- $rows | _zs_fzf_multi sequences 'pairs you run back-to-back → one shortcut that runs both')"} )
  for pick in $picks; do
    f=( "${(@ps:\t:)pick}" )
    _zs_learn "$f[2]" "$f[3]"
  done
  return 0
}

_zs_habits_typos() {
  emulate -L zsh; setopt extendedglob
  _zs_have_db || { print -u2 "typo mining needs atuin's database (exit codes)"; return 1 }
  local n w fix disp pick
  local -a rows picks f near
  _zs_sql "SELECT COUNT(*) AS n, substr(command, 1, instr(command || ' ', ' ') - 1) AS w
           FROM history WHERE exit = 127 AND deleted_at IS NULL
           GROUP BY w HAVING n >= 3 ORDER BY n DESC LIMIT 40;" |
  while IFS=$'\t' read -r n w; do
    [[ $w == [[:alnum:]_.-]## ]] && (( ${#w} >= 3 )) || continue
    (( $+commands[$w] || $+aliases[$w] || $+functions[$w] )) && continue
    near=( ${(k)commands[(I)(#a1)$w]} ${(k)aliases[(I)(#a1)$w]} )
    (( $#near )) || continue
    fix=${near[1]}
    printf -v disp '%-12s → %-12s (%d× command-not-found)' "$w" "$fix" "$n"
    rows+=( "$disp"$'\t'"$w"$'\t'"$fix" )
  done
  (( $#rows )) || { print "no recurring typos — nice."; return 0 }
  picks=( ${(f)"$(print -rl -- $rows | _zs_fzf_multi typos 'typo → what you meant   (creates an alias)')"} )
  for pick in $picks; do
    f=( "${(@ps:\t:)pick}" )
    _zs_learn_alias "$f[2]" "$f[3]" || { print -u2 "could not save the alias (busy)"; continue }
    alias -- "$f[2]=$f[3]"
    print -r -- "  + $f[2] → $f[3]"
  done
  return 0
}

_zs_habits_report() {
  emulate -L zsh
  print "== most used (120 days) =="
  _zs_hist_dump 120 | awk '{ print $1 }' | sort | uniq -c | sort -rn | head -n 15
  if _zs_have_db; then
    print "\n== fail most often =="
    _zs_sql "SELECT COUNT(*) AS n, substr(command, 1, instr(command || ' ', ' ') - 1) AS w FROM history
             WHERE exit NOT IN (0, 130) AND deleted_at IS NULL AND timestamp > $(_zs_since 120)
             GROUP BY w ORDER BY n DESC LIMIT 8;"
    print "\n== busiest directories =="
    _zs_sql "SELECT COUNT(*) AS n, cwd FROM history WHERE deleted_at IS NULL AND timestamp > $(_zs_since 120)
             GROUP BY cwd ORDER BY n DESC LIMIT 8;"
    print "\n== back-to-back pairs =="
    _zs_sql "WITH o AS (SELECT command AS a, LEAD(command) OVER (PARTITION BY session ORDER BY timestamp) AS b
               FROM history WHERE deleted_at IS NULL AND instr(command, char(10)) = 0 AND timestamp > $(_zs_since 120))
             SELECT COUNT(*) AS n, a || '  ->  ' || b FROM o
             WHERE b IS NOT NULL AND a <> b AND length(a) < 60 AND length(b) < 60
             GROUP BY a, b HAVING n >= 4 ORDER BY n DESC LIMIT 8;"
  fi
  print "\n== typed often, no shortcut (uses / command) =="
  _zs_habits_candidates 120 6 | head -n 12 | awk -F'\t' '{ printf "%5d  %s\n", $2, $3 }'
}

function habits {
  case ${1:-} in
    ''|shortcuts)  _zs_habits_shortcuts ;;
    seq|sequences) _zs_habits_sequences ;;
    typos)         _zs_habits_typos ;;
    here)          local s; s=$(_zs_here_pick) && print -z -- ${s#*x  } ;;
    report)        _zs_habits_report ;;
    ai)            _zs_habits_report | ai "These are my shell usage statistics. Propose up to 6 concrete improvements: abbreviations, small zsh functions that merge repeated sequences, or a better tool for something I do the slow way. Give the exact definition for each. Skip anything generic." ;;
    *) print "habits              frequent commands → abbreviations
habits seq          back-to-back pairs → one shortcut
habits typos        recurring command-not-found → aliases
habits here         what you usually run in this directory (Ctrl+X h)
habits report       usage statistics        habits ai   let the local LLM read them" ;;
  esac
}

# weekly, from _zs_maintenance: leave a one-line tip when there is something worth learning
_zs_habits_scan() {
  emulate -L zsh
  local score n cmd
  local -i cnt=0 keys=0
  _zs_habits_candidates 120 10 | while IFS=$'\t' read -r score n cmd; do
    [[ -n $cmd ]] || continue
    _zs_known "$cmd" && continue
    (( cnt++, keys += score ))
  done
  (( cnt >= 2 )) && print -r -- "habits: $cnt things you keep typing could be shortcuts (~$keys keystrokes in 4 months) → run: habits" >| $ZSH_CACHE/tip
  return 0
}


# ---- the selector: see the alternatives, not just the top guess ----------------
# Inline autosuggestions show ONE prediction. This shows the ranked list behind
# it, from the same scoring the `smart` strategy uses, and lets you pick.
#   Ctrl+N          with an empty line  → what you usually run in this directory
#                   with a prefix typed → every command that continues it, ranked
#   right arrow / Ctrl+Space            → still just accepts the inline one
_zs_suggest_candidates() {
  emulate -L zsh
  local p=${1//\'/\'\'} d=${PWD//\'/\'\'}
  if _zs_have_db; then
    # same weights as _zsh_autosuggest_strategy_smart, shown with why it ranked
    _zs_sql "SELECT printf('%-5s %-4s ', CASE WHEN MAX(cwd = '$d') = 1 THEN 'here' ELSE '' END,
                    COUNT(*) || 'x') || command
             FROM history
             WHERE substr(command, 1, ${#1}) = '$p' AND deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0
               AND instr(command, char(10)) = 0 AND length(command) < 300
             GROUP BY command
             ORDER BY MAX(cwd = '$d') * 3.0 + MIN(COUNT(*), 20) / 10.0
                    - MIN((CAST(strftime('%s','now') AS REAL) - MAX(timestamp) / 1e9) / 86400.0, 90.0) / 30.0 DESC
             LIMIT 200;"
  else
    local -a m=( ${(u)history[(R)${1}*]} )
    print -rl -- ${m[1,200]}
  fi
}
_zs_suggest_widget() {
  emulate -L zsh
  local prefix=$LBUFFER sel
  sel=$(_zs_suggest_candidates "$prefix" | fzf --no-sort --height=50% --query="" \
        --prompt='suggest ❯ ' --delimiter='  +' \
        --header="${prefix:+continuing: $prefix}${prefix:-what you usually run in ${PWD/#$HOME/~}}   ENTER insert · Ctrl+Y copy" \
        --preview-window=hidden)
  if [[ -n $sel ]]; then
    _zs_have_db && sel=${sel##(here|)[[:space:]]#<->x[[:space:]]#}
    BUFFER=$sel; CURSOR=${#BUFFER}
  fi
  zle reset-prompt
}

# ---- hs: find a command by describing it ----------------------------------------
#   hs that ffmpeg crop command from last spring
#   hs how did I deploy the lambda          (Ctrl+X s: describe on the line, then press it)
# The local model turns the description into literal fragments the command
# probably contains (+ a time window); SQLite ranks your successful commands by
# how many fragments they match; fzf picks; the command lands on your prompt.
# Cheaper than embeddings, and it needs nothing but the model you already run.
_zs_hs_plan() {   # <description> → JSON {"terms":[…],"days_ago_min":n,"days_ago_max":n}
  local out
  if (( $+functions[_zai_ensure] )) && _zai_ensure 2>/dev/null; then
    out=$(ZAI_STATUS='searching history' _zai_request "You help search a zsh history database. Given a description of a command the user ran before, output ONLY compact JSON: {\"terms\":[...],\"days_ago_min\":N|null,\"days_ago_max\":N|null}. terms: 3-8 short LITERAL substrings that would appear in that command line (program names, flags like -vf or crop=, file extensions, subcommands), most specific first, lowercase. Include likely variants (e.g. both 'docker compose' and 'docker-compose'). Today is $(date +%F). Convert relative dates to a days-ago window, generously (\"last spring\" → a wide range); null when no time is mentioned." "$1" 160 0.1 2>/dev/null)
    out=${${out#*\{}%\}*}; out="{$out}"
    jq -e '.terms | length > 0' <<< $out >/dev/null 2>&1 && { print -r -- $out; return }
  fi
  # no model: plain words, minus filler
  local -a w=( ${(L)=1} )
  w=( ${w:#(the|a|an|that|this|command|from|last|i|my|how|did|to|of|for|with|run|ran|used|what|was|in|on)} )
  jq -nc --args '{terms: $ARGS.positional, days_ago_min: null, days_ago_max: null}' $w
}
function hs {
  emulate -L zsh
  _zs_have_db || { print -u2 "hs needs atuin's database (zsh-setup)"; return 1 }
  [[ -n $* ]] || { print "usage: hs <describe the command you ran>"; return 1 }
  local plan sel score='' where='' t q
  local -a terms
  plan=$(_zs_hs_plan "$*")
  terms=( ${(f)"$(jq -r '.terms[]' <<< $plan 2>/dev/null)"} )
  (( $#terms )) || { print -u2 "hs: could not make search terms"; return 1 }
  for t in ${terms[1,8]}; do
    q=${${t//\'/\'\'}//\%/}
    [[ -n $q ]] || continue
    score+="${score:+ + }(instr(lower(command), lower('$q')) > 0)"
  done
  local -i dmin=$(jq -r '.days_ago_min // 0' <<< $plan 2>/dev/null) dmax=$(jq -r '.days_ago_max // 0' <<< $plan 2>/dev/null)
  (( dmax > 0 && dmax >= dmin )) && where="AND timestamp BETWEEN (CAST(strftime('%s','now') AS INTEGER) - $(( dmax + 14 )) * 86400) * 1000000000 AND (CAST(strftime('%s','now') AS INTEGER) - $(( dmin > 14 ? dmin - 14 : 0 )) * 86400) * 1000000000"
  print -P -- "%F{$ZC[dim]}looking for: ${(j:, :)terms//\%/%%}${where:+  (time window applied)}%f"
  sel=$(_zs_sql "SELECT ($score) AS s, COUNT(*), strftime('%Y-%m-%d', MAX(timestamp) / 1000000000, 'unixepoch'), command
                 FROM history WHERE deleted_at IS NULL AND ltrim(command) NOT LIKE 'zagent%' AND exit = 0 $where
                 GROUP BY command HAVING s > 0
                 ORDER BY s DESC, MAX(timestamp) DESC LIMIT 300;" |
        awk -F'\t' '{ printf "%s  %3dx  %s\t%s\n", $3, $2, substr($4, 1, 160), $4 }' |
        fzf --delimiter=$'\t' --with-nth=1 --no-sort --height=60% --prompt='hs ❯ ' \
            --header="best matches first · ENTER puts it on your prompt" \
            --preview 'print -r -- {2}' --preview-window=down:4:wrap)
  [[ -n $sel ]] && print -z -- "${sel#*$'\t'}"
}
alias hs='noglob hs'
_zs_hs_widget() {   # Ctrl+X s: the text on the line is the description
  [[ -n ${BUFFER//[[:space:]]/} ]] || { zle -M "describe the command first, then Ctrl+X s"; return }
  local q=$BUFFER
  BUFFER=" hs ${(q)q}"; zle accept-line
}
