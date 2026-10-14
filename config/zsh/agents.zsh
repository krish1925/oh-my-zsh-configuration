# =====================================================================
#  agents.zsh — background Claude Code jobs that stay on
#
#    aj <task>        detached `claude -p` job in its OWN git worktree + branch,
#                     so three agents can't damage your tree or each other
#    aj --here <task> run in the current directory instead (edits your files)
#    ajs              pick a job: preview result/diff · Enter cd's into it
#                       Ctrl+D diff · Ctrl+L log · Ctrl+K kill · Ctrl+A apply
#    aj-apply <id>    apply a job's changes to your checkout (git apply --3way)
#    aj-clean [-f]    remove worktrees of finished jobs (-f: even with changes)
#    prompt           ⚙2 running · ✓1 finished, not looked at · ✗1 failed
#
#  Circuit breakers: --max-turns $ZAJ_TURNS and --max-budget-usd $ZAJ_BUDGET.
#  Permissions: acceptEdits — file edits are allowed; any shell command that
#  would need approval is denied (nobody is there to approve it in -p mode),
#  except the read-only ones in ZAJ_ALLOW. A job therefore never sits blocked
#  on a prompt: it finishes, and the prompt segment tells you.
# =====================================================================

(( $+functions[_zs_locked] )) || source ${${(%):-%x}:A:h}/lib.zsh 2>/dev/null   # locking + atomic writes (lib.zsh), found next to this file
typeset -g ZAJ_DIR=$ZSH_DATA/ai-jobs
: ${ZAJ_TURNS:=30}
: ${ZAJ_BUDGET:=2}
: ${ZAJ_MODE:=acceptEdits}
(( ${+ZAJ_ALLOW} )) || typeset -ga ZAJ_ALLOW=(
  'Bash(git status:*)' 'Bash(git diff:*)' 'Bash(git log:*)' 'Bash(git show:*)'
  'Bash(ls:*)' 'Bash(rg:*)' 'Bash(fd:*)'
)

_zaj_ids() { reply=( $ZAJ_DIR/*(N/On:t) ) }   # newest first
_zaj_state() {   # <dir> → REPLY: running|done|failed|died|applied
  local d=$1 s=''
  [[ -r $d/status ]] && s=$(<$d/status)
  if [[ $s == running && -r $d/pid ]] && ! kill -0 $(<$d/pid) 2>/dev/null; then
    [[ -r $d/status ]] && s=$(<$d/status)     # it may have just finished
    [[ $s == running ]] && s=died
  fi
  REPLY=${s:-died}
}

function aj {
  emulate -L zsh
  (( $+commands[claude] )) || { print -u2 "aj: claude CLI not found"; return 1 }
  local here=''
  [[ $1 == --here ]] && { here=1; shift }
  local task="$*" id="${EPOCHSECONDS}-${sysparams[pid]}-$(( ++_ZS_TMP_SEQ ))" root='' wt dir   # two `aj` in the same second used to collide
  [[ -n $task ]] || { print "usage: aj <task>      aj --here <task>      (ajs to see jobs)"; return 1 }
  (( $+functions[_zai_privacy_gate] )) && { _zai_privacy_gate "this task (claude -p runs in the cloud)" "$task" || { print -u2 "aj: not started"; return 1 } }
  dir=$ZAJ_DIR/$id
  if [[ -z $here ]]; then
    root=$(git rev-parse --show-toplevel 2>/dev/null) ||
      { print -u2 "aj: not in a git repo — use  aj --here <task>  to let it edit $PWD directly"; return 1 }
    wt=${root:h}/.aj-${root:t}-$id
    git -C $root worktree add -q -b aj/$id $wt HEAD || return 1
    git -C $root diff --quiet HEAD 2>/dev/null ||
      print -P "%F{$ZC[warn]}note:%f the job starts from HEAD — your uncommitted changes are not in its worktree"
  else
    wt=$PWD
  fi
  command mkdir -p $dir
  print -r -- $task >| $dir/task
  print -r -- $wt   >| $dir/cwd
  print -r -- $root >| $dir/root
  print running     >| $dir/status
  (
    cd $wt || { print failed >| $dir/status; exit 1 }
    claude -p "$task" --output-format json \
      --max-turns $ZAJ_TURNS --max-budget-usd $ZAJ_BUDGET \
      --permission-mode $ZAJ_MODE --allowedTools $ZAJ_ALLOW \
      --append-system-prompt "You are running unattended as a background job. Nobody can answer questions or approve commands. Make the change, keep it focused, and finish with a short summary of what you changed and anything left for a human." \
      </dev/null >| $dir/out.json 2>| $dir/err.log &
    print -r -- $! >| $dir/pid
    wait $!
    rc=$?; st=done
    (( rc == 0 )) && [[ $(jq -r '.is_error // false' $dir/out.json 2>/dev/null) != true ]] || st=failed
    print -r -- $st >| $dir/status
    cost=$(jq -r '.total_cost_usd // empty' $dir/out.json 2>/dev/null)
    if [[ $st == done ]]; then title="aj ✓ done"; else title="aj ✗ failed"; fi
    (( $+functions[_zs_notify] )) && _zs_notify "$title" "${task[1,80]}${cost:+ · \$$(printf %.2f $cost)} — ajs"
  ) >/dev/null 2>&1 &!
  print -r -- "aj $id → ${wt/#$HOME/~}   (ajs to follow)"
}

_zaj_line() {   # <id> → one fzf row
  local id=$1 d=$ZAJ_DIR/$1 task icon age
  _zaj_state $d
  case $REPLY in
    running) icon='⚙' ;; done) icon='✓' ;; applied) icon='⇲' ;; *) icon='✗' ;;
  esac
  local -i m=$(( (EPOCHSECONDS - ${id%%-*}) / 60 ))
  if (( m < 60 )); then age="${m}m"; elif (( m < 1440 )); then age="$(( m / 60 ))h"; else age="$(( m / 1440 ))d"; fi
  task=$(<$d/task)
  printf '%s %-7s %4s  %s\t%s\n' $icon $REPLY $age "${${task//$'\n'/ }[1,90]}" $id
}
_zaj_preview() {   # <id>
  local d=$ZAJ_DIR/$1 wt
  wt=$(<$d/cwd)
  _zaj_state $d
  print -r -- "status: $REPLY    dir: ${wt/#$HOME/~}"
  [[ -s $d/out.json ]] && jq -r '"turns: \(.num_turns // "?")   cost: $\(.total_cost_usd // 0 | . * 100 | round / 100)   \(.duration_ms // 0 | ./1000 | floor)s"' $d/out.json 2>/dev/null
  print -r -- "task:   $(<$d/task)"
  print
  if [[ -s $d/out.json ]]; then jq -r '.result // .error // empty' $d/out.json 2>/dev/null
  elif [[ -s $d/err.log ]]; then tail -n 20 $d/err.log
  else print "(still working…)"; fi
  if [[ -d $wt/.git || -f $wt/.git ]]; then
    print; print -- '── changes ──'
    git -C $wt status --short 2>/dev/null | head -30
    git -C $wt diff --stat --color=always 2>/dev/null | tail -n 12
  fi
}
function ajs {
  emulate -L zsh
  local -a reply; _zaj_ids
  (( $#reply )) || { print "no jobs yet — aj <task>"; return 0 }
  local id sel key
  local out
  out=$(for id in $reply; do _zaj_line $id; done |
    fzf --delimiter=$'\t' --with-nth=1 --no-sort --height=80% --prompt='jobs ❯ ' \
        --expect=ctrl-d,ctrl-l,ctrl-k,ctrl-a \
        --header='ENTER cd into it · Ctrl+D diff · Ctrl+L log · Ctrl+K kill · Ctrl+A apply to your checkout' \
        --preview "zsh -fc 'source ${(q)ZSH_CONF}/agents.zsh 2>/dev/null; ZAJ_DIR=${(q)ZAJ_DIR}; _zaj_preview {2}'" \
        --preview-window=right:60%:wrap)
  [[ -n $out ]] || return 0
  key=${out%%$'\n'*}; sel=${out#*$'\n'}; id=${sel##*$'\t'}
  [[ -n $id && -d $ZAJ_DIR/$id ]] || return 0
  local d=$ZAJ_DIR/$id wt=$(<$ZAJ_DIR/$id/cwd)
  : >| $d/seen
  case $key in
    ctrl-d) git -C $wt add -N . 2>/dev/null; git -C $wt diff ;;
    ctrl-l) ${PAGER:-less} $d/err.log $d/out.json ;;
    ctrl-k) # a finished job's PID may have been reused by an unrelated process — only kill a live `claude`
            local -i jpid=0; [[ -r $d/pid ]] && jpid=$(<$d/pid)
            if [[ $(<$d/status) == running ]] && _zs_pid_is $jpid claude; then
              kill $jpid 2>/dev/null && print failed >| $d/status && print "killed $id"
            else print "job $id is not running" ; fi ;;
    ctrl-a) aj-apply $id ;;
    *)      builtin cd -- $wt && print -P "%F{$ZC[dim]}in job $id — git diff to review · aj-apply $id to bring it home · cd - to go back%f" ;;
  esac
}
function aj-apply {   # bring a job's changes (committed or not) into the repo it came from
  emulate -L zsh
  local id=${1:?usage: aj-apply <id>} d=$ZAJ_DIR/$1 wt root base
  [[ -d $d ]] || { print -u2 "no job $id"; return 1 }
  wt=$(<$d/cwd); root=$(<$d/root)
  [[ -n $root ]] || { print -u2 "job ran with --here; its changes are already in $wt"; return 1 }
  base=$(git -C $root rev-parse HEAD) || return 1
  git -C $wt add -A >/dev/null 2>&1
  local patch=$d/changes.patch
  git -C $wt diff --cached --binary $(git -C $wt merge-base HEAD $base) >| $patch
  [[ -s $patch ]] || { print "job $id made no changes"; return 0 }
  if git -C $root apply --3way --index $patch; then
    print applied >| $d/status; : >| $d/seen
    print -P "%F{$ZC[exe]}applied%f $(git -C $root diff --cached --shortstat) → review with: git diff --cached"
  else
    print -u2 "conflicts — resolve them in $root (the patch is at $patch)"; return 1
  fi
}
function aj-clean {
  emulate -L zsh
  local force='' id d wt root
  [[ $1 == -f ]] && force=1
  local -a reply; _zaj_ids
  local -i n=0
  for id in $reply; do
    d=$ZAJ_DIR/$id; _zaj_state $d
    [[ $REPLY == running ]] && continue
    wt=$(<$d/cwd); root=$(<$d/root)
    if [[ -n $root && -d $wt ]]; then
      if [[ -z $force && $REPLY != applied && -n $(git -C $wt status --porcelain 2>/dev/null) ]]; then
        print -r -- "kept $id — unapplied changes (aj-apply $id, or aj-clean -f to discard)"; continue
      fi
      git -C $root worktree remove --force $wt 2>/dev/null
      git -C $root branch -D aj/$id >/dev/null 2>&1
    fi
    command rm -rf -- $d; (( n++ ))
  done
  git worktree prune 2>/dev/null
  print "removed $n job(s)"
}

# ---- p10k segment:  ⚙ running · ✓ finished-unseen · ✗ failed-unseen -----------
# Pure zsh (no forks): runs on every prompt.
function prompt_aj() {
  local d
  local -i run=0 fin=0 bad=0
  for d in $ZAJ_DIR/*(N/); do
    [[ -e $d/seen ]] && continue
    _zaj_state $d
    case $REPLY in running) (( run++ )) ;; done|applied) (( fin++ )) ;; *) (( bad++ )) ;; esac
  done
  (( run + fin + bad )) || return
  local t=''
  (( run )) && t+="⚙$run "
  (( fin )) && t+="✓$fin "
  (( bad )) && t+="✗$bad "
  local -i fg=117
  (( bad )) && fg=204
  p10k segment -f $fg -t "${t% }"
}
