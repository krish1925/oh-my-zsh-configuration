# =====================================================================
#  lib.zsh — the few primitives everything else builds on
#
#  Several shells, background jobs and the agent all touch the same small files
#  (memory, bookmarks, session, caches) and the same model servers. Before this
#  file each place did its own `read → modify → print >| file` and its own
#  `kill $(<pidfile)`, which is how you lose an edit, corrupt a config, or kill a
#  process that merely inherited a dead server's PID. Three rules, all here:
#
#    _zs_locked      one writer at a time (kernel flock: released automatically
#                    when the holder exits or is killed — no stale lock files)
#    _zs_write_atomic  a file is replaced whole or not at all (temp + rename)
#    _zs_pid_is      only ever signal a PID after checking what it actually is
# =====================================================================

zmodload zsh/system 2>/dev/null
typeset -gi _ZS_TMP_SEQ=0
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload -F zsh/files b:zf_rm b:zf_mv b:zf_mkdir 2>/dev/null

# _zs_locked [-t secs] <lockpath> <command…>
#   Runs <command…> holding an exclusive lock on <lockpath>.lock; returns its status.
#   Waits up to secs (default 20; 0 = try once). Returns 75 if the lock stayed busy —
#   CALLERS MUST CHECK: a skipped write must be reported, never silent. (zsh's timed lock
#   polls instead of queueing; measured: 8 simultaneous writers never miss, ~30 can starve.)
#   Always released — even if the command fails or the shell is interrupted.
_zs_locked() {
  local -i t=20
  [[ $1 == -t ]] && { t=$2; shift 2 }
  local lk=$1.lock fd; shift
  [[ -d ${lk:h} ]] || zf_mkdir -p ${lk:h} 2>/dev/null
  : >> $lk 2>/dev/null || return 74
  zsystem flock -t $t -f fd $lk 2>/dev/null || return 75
  { "$@" } always { exec {fd}>&- }
}

# _zs_write_atomic <dest>      stdin → dest, all or nothing
#   Temp file in the SAME directory + rename: a concurrent reader sees the old file or
#   the new one, never half of one; a crash mid-write leaves the old file untouched.
#   Follows a symlinked dest (dotfile repos) and keeps its permission bits.
_zs_write_atomic() {
  emulate -L zsh
  local dest=${1:A} tmp
  local -a st
  # $$ and $RANDOM are the PARENT's in every forked subshell/background job (measured: identical
  # across 30 concurrent writers → they overwrote each other's temp file). sysparams[pid] is the real PID.
  tmp=$dest.tmp.${sysparams[pid]}.$(( ++_ZS_TMP_SEQ ))
  command cat >| $tmp || { zf_rm -f $tmp; return 1 }
  if [[ -e $dest ]] && zstat -A st +mode $dest 2>/dev/null; then
    command chmod $(( [##8] st[1] & 8#7777 )) $tmp 2>/dev/null
  fi
  zf_mv -f $tmp $dest || { zf_rm -f $tmp; return 1 }
}

# _zs_write_lines <dest> [line…]   the lines (blank ones included), atomically. No lines = empty file.
_zs_write_lines() {
  emulate -L zsh
  local dest=$1; shift
  if (( $# )); then print -rl -- "$@" | _zs_write_atomic $dest
  else : | _zs_write_atomic $dest; fi
}

# _zs_read_lines <file> → reply=( one element per line, blank lines kept; empty/missing file → () )
_zs_read_lines() {
  emulate -L zsh
  [[ -s $1 ]] || { reply=(); return 0 }
  reply=( "${(@f)$(<$1)}" )
}

# _zs_pid_is <pid> <substring…>   true only if the process is alive AND its command line
#   contains every substring. This is the guard before any `kill`: a PID from a file
#   (or a leftover from a crash) may now belong to an unrelated process.
_zs_pid_is() {
  emulate -L zsh
  local -i pid=${1:-0}; shift
  (( pid > 1 )) && kill -0 $pid 2>/dev/null || return 1
  local cmd s
  cmd=$(command ps -ww -o command= -p $pid 2>/dev/null) || return 1
  for s in "$@"; do [[ $cmd == *${s}* ]] || return 1; done
  return 0
}

# _zs_stop_pids <grace_secs> <pid…>   SIGTERM, wait for them to be GONE (memory is only
#   released when the process has exited), then SIGKILL whatever is left. Returns 0 when all gone.
_zs_stop_pids() {
  emulate -L zsh
  local -i grace=$1 i any; shift
  local -a pids=( $@ ) left
  local p
  (( $#pids )) || return 0
  kill $pids 2>/dev/null
  for (( i = 0; i < grace * 10; i++ )); do
    left=(); for p in $pids; do kill -0 $p 2>/dev/null && left+=$p; done
    (( $#left )) || return 0
    sleep 0.1
  done
  kill -9 $left 2>/dev/null
  for (( i = 0; i < 20; i++ )); do
    any=0; for p in $left; do kill -0 $p 2>/dev/null && any=1; done
    (( any )) || return 0
    sleep 0.1
  done
  return 1
}
