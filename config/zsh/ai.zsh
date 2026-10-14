# =====================================================================
#  ai.zsh — local-first AI for the shell
#
#  Backend: ANY OpenAI-compatible endpoint. Default = mlx_lm.server on this
#  Mac, started on first use, kept warm, shut down after ZAI_IDLE_MIN idle
#  minutes. (v3's kollzsh loaded the model from disk on every keypress.)
#
#    ? <request>      Enter → command lands on your prompt. NEVER auto-runs.
#    ?+ <change>      refine the last ? result ("?+ only .py files")
#    ?? <question>    Enter → the HEAVY model (MiMo 9B, multimodal) as an agent with
#                     read-only tools: this Mac (memory, processes, apps, disk,
#                     battery, network), this repo, a code sandbox, + the web.
#                     Follow-ups for 10 min. ??new starts over · ??? = thinking on
#                     It never runs anything real: a command it proposes lands on
#                     your prompt and you press Enter. (run_python/run_shell are the
#                     one exception — fully network-free, throwaway sandboxes.)
#    ??shot <q>       screenshot (drag a region) + ask, one step — "??shot what is this"
#    shot             shot [full|window|region] → screenshot ($ZSH_SHOTS/latest.png)
#    ai-equip         pick ??'s vision model: ai-equip mimo | qwen4b | <hf-repo>
#                     (smoke-tested before it's switched, never just trusted)
#  Privacy: API keys / tokens / passwords in your history are replaced by
#  [redacted] before they are sent (_zai_redact), and everything is redacted
#  when ZAI_URL is not localhost.
#    Ctrl+O           same as "? " for whatever is on the line
#    Ctrl+X e         explain the command on the line (line comes back after)
#    Ctrl+X f         put a corrected version of the last failed command on the line
#    wtf              why did the last command fail? (+ fix on the next prompt)
#    wtf -r           …re-run it to capture the real error text first
#    <cmd> | ai "…"   pipe anything in:  git diff | ai "risky changes?"
#    aic              commit message from the staged diff (opens in $EDITOR)
#    ai-server        start | stop | restart | status | log
#
#  Switch backend in ~/.zshrc.local:
#    ZAI_MODEL=mlx-community/<other-repo>            # any MLX text model
#    ZAI_URL=http://localhost:11434/v1               # Ollama
#    ZAI_URL=http://localhost:1234/v1                # LM Studio
#    ZAI_URL=https://…/v1  ZAI_KEY=sk-…              # cloud — NOTE: cwd, file
#        names and your last few commands are sent as context
#  Use an *instruct* (non-thinking) model: reasoning models stream their
#  <think> block and make "? " slow.
# =====================================================================

: ${ZAI_URL:=http://127.0.0.1:8377/v1}                       # own port: never collides with an mlx server you run yourself on 8080
: ${ZAI_MODEL:=mlx-community/Qwen3.5-9B-MLX-4bit}   # ~5.5 GB · current generation
# Chosen Sept 2026 for a 24 GB M4 Pro. Qwen3.5-9B is the current small-model
# generation (Qwen2.5-Coder, the earlier default here, is a late-2024 model).
# The deciding detail: on Qwen3.5 the 0.8B/2B/4B/9B sizes ship with reasoning
# DISABLED by default, so there is no <think> latency tax — while Qwen3.5's
# thinking mode is widely reported to loop and burn context, which would have
# made a thinking-by-default model unusable behind `? `.
#
# Switch any time with:  ai-model            (lists, tests and sets the default)
# Other good picks for 24 GB — see `ai-model` for the current table:
#   mlx-community/Qwen3.5-4B-MLX-4bit        ~2.5 GB  half the RAM, still current-gen
#   lmstudio-community/gpt-oss-20b-MLX-8bit  ~12 GB   best quality-per-GB in 2026 tests
#   mlx-community/Qwen3-4B-Instruct-2507-4bit ~2.3 GB previous default, known-good
# Not recommended here: Qwen3.6-27B / 35B-A3B (16-20 GB leaves too little for
# the rest of your machine), and any "nl2bash/nl2sh" fine-tune (0.8-1.5B,
# Linux-only flags, and they only do text->command, not wtf/explain/review).
#
# CAVEAT worth knowing: Qwen3.5 is natively multimodal, and some mlx-community
# repos for it are packaged for mlx-vlm rather than mlx-lm. If the server log
# shows a model-loading error, run `ai-model` and pick another — it test-loads
# each candidate before committing.
(( $+functions[_zs_locked] )) || source ${${(%):-%x}:A:h}/lib.zsh   # next to this file — not via $ZSH_CONF, which tests and tools repoint
: ${ZSH_CACHE:=$HOME/.cache/zsh}
: ${ZSH_CONF:=$HOME/.config/zsh}
: ${ZSH_DATA:=$HOME/.local/share/zsh}
: ${ZAI_KEY:=}
: ${ZAI_AUTOSTART:=1}
: ${ZAI_IDLE_MIN:=45}        # free the RAM after this many idle minutes (0 = keep forever)
: ${ZAI_TIMEOUT:=120}
typeset -g _ZAI_STAMP=$ZSH_CACHE/ai-last-use _ZAI_PIDF=$ZSH_CACHE/ai-server.pid _ZAI_LOG=$ZSH_CACHE/ai-server.log
typeset -g _ZAI_OS=''
zmodload -F zsh/files b:zf_rm b:zf_mkdir 2>/dev/null || true

# ---- backend -------------------------------------------------------------
_zai_headers() {   # → reply (array)
  reply=(-H 'Content-Type: application/json')
  [[ -n $ZAI_KEY ]] && reply+=(-H "Authorization: Bearer $ZAI_KEY")
  return 0
}
_zai_up()       { local -a reply; _zai_headers; curl -sf -m 2 -o /dev/null $reply "$ZAI_URL/models" }
_zai_is_local() { [[ $ZAI_URL == http://(127.0.0.1|localhost)[:/]* ]] }

# ---- secrets never leave in context -----------------------------------------
# `export OPENAI_API_KEY=sk-…` followed by `wtf` used to ship the key to whatever
# ZAI_URL points at. Everything that goes into a prompt passes through here:
# always for _zai_context (your history), and for the whole message whenever
# ZAI_URL is not on this machine. Also used by the MCP server and the watcher.
typeset -g _ZAI_REDACT_PL='
  s/\bsk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_-]{16,}/[redacted]/g;
  s/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,})/[redacted]/g;
  s/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/[redacted]/g;
  s/\bxox[abprs]-[A-Za-z0-9-]{10,}/[redacted]/g;
  s/\bAIza[0-9A-Za-z_-]{30,}/[redacted]/g;
  s/\b(?:hf|npm|pypi|dop_v1)_[A-Za-z0-9_-]{20,}/[redacted]/g;
  s/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[redacted-jwt]/g;
  s/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|\z)/[redacted-private-key]/gs;
  s/(\b(?:Bearer|Basic|Token)\s+)[^\s"\x27]+/$1\[redacted]/gi;
  s/(\b[A-Za-z0-9_]*(?:password|passwd|passphrase|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|credentials?)s?(?:[_-]?key)?\s*[=:]\s*)("[^"]*"|\x27[^\x27]*\x27|[^\s&;|]+)/$1\[redacted]/gi;
  s/(--?(?:password|passwd|token|secret|api-key|key)[= ])(\S+)/$1\[redacted]/gi;
  s#(://[^/\s:@]+:)[^@\s/]+@#$1\[redacted]@#g;
'
_zai_redact() {   # stdin → stdout, secrets replaced by [redacted]
  perl -0777 -pe "$_ZAI_REDACT_PL" 2>/dev/null || command cat
}
_zai_maybe_redact() {   # <text> → REPLY; redacts only when the endpoint is remote
  if _zai_is_local; then REPLY=$1; else REPLY=$(print -r -- "$1" | _zai_redact); fi
}

# ---- reasoning models: never let <think> reach the prompt or the screen ------
# Closed blocks, a block cut off by max_tokens (no </think>), and the variant
# where the chat template already opened <think> so only </think> appears.
_zai_strip_think() {   # <text> → REPLY
  emulate -L zsh; setopt extendedglob
  local s=$1
  s=${s//\<think\>*\<\/think\>/}
  [[ $s == *'</think>'* ]] && s=${s##*\<\/think\>}
  [[ $s == *'<think>'* ]]  && s=${s%%\<think\>*}
  REPLY=${s##[[:space:]]##}
}
# streaming version: holds back only a possible partial "<think" tag, so output
# is still immediate; drops everything inside <think>, closed or not.
typeset -g _ZAI_THINK_PL='
  $| = 1; my ($b, $in) = ("", 0); my ($o, $c) = ("<think>", "</think>");
  while (sysread(STDIN, my $x, 4096)) {
    $b .= $x;
    while (1) {
      if ($in) {
        my $i = index($b, $c);
        if ($i < 0) { $b = substr($b, -8) if length($b) > 8; last }
        $b = substr($b, $i + length $c); $b =~ s/^\s+//; $in = 0; next;
      }
      my $i = index($b, $o);
      if ($i >= 0) { print substr($b, 0, $i); $b = substr($b, $i + length $o); $in = 1; next }
      my $k = 0;
      for my $n (reverse 1 .. length($o) - 1) { if (length($b) >= $n && substr($b, -$n) eq substr($o, 0, $n)) { $k = $n; last } }
      print substr($b, 0, length($b) - $k); $b = $k ? substr($b, -$k) : ""; last;
    }
  }
  print $b unless $in;
'

# ---- server lifecycle -----------------------------------------------------------------
# Four rules, each one a bug that used to be here:
#   1. One launcher at a time per server. Two terminals both saw "down" and both launched; the
#      loser overwrote the pidfile with a dead PID and the real server became untracked.
#   2. Never signal a PID from a file without checking what it is. PIDs are recycled — the idle
#      reaper could have killed an unrelated program that inherited a dead server's number, and
#      `ai-server stop` killed whatever listened on the port, even if it wasn't ours.
#   3. Stop means "wait until it is gone". Its GPU memory is only released when the process exits,
#      and `zagent --deep` loads the 27B immediately after stopping the other models.
#   4. The idle reaper never kills a server that is answering a request, and stops watching once
#      the server is stopped or replaced.
_zai_port() { REPLY=${${ZAI_URL#*://*:}%%/*}; [[ $REPLY == <-> ]] || REPLY=8377 }

_zai_server_pids() {   # → reply=( PIDs of OUR server for $ZAI_URL ), each verified against its command line
  emulate -L zsh
  local port p; _zai_port; port=$REPLY
  local -a cand
  reply=()
  [[ -r $_ZAI_PIDF ]] && cand+=( ${(f)"$(<$_ZAI_PIDF)"} )
  _zai_is_local && cand+=( ${(f)"$(lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)"} )   # a uvx wrapper's real child
  for p in ${(u)cand}; do
    _zs_pid_is $p mlx_ "--port $port" && reply+=$p
  done
  return 0
}

_zai_server_stop() {   # graceful, and returns only once the process is gone (or 1 if it would not die)
  emulate -L zsh
  local -a reply; _zai_server_pids
  local -i rc=0
  (( $#reply )) && { _zs_stop_pids 20 $reply || rc=1 }
  (( rc )) || zf_rm -f $_ZAI_PIDF
  return rc
}

_zai_spawn_reaper() {   # <pid> <port> — detached; after ZAI_IDLE_MIN idle minutes, stop the server (carefully)
  (( ZAI_IDLE_MIN > 0 )) || return 0
  nohup zsh -fc '
    zmodload zsh/datetime; zmodload -F zsh/stat b:zstat
    pid=$1 port=$2 stamp=$3 pidf=$4 idle=$5 tick=$6
    while sleep $tick; do
      kill -0 $pid 2>/dev/null || exit 0                                 # already gone
      cur=""; [[ -r $pidf ]] && read -r cur < $pidf
      [[ $cur == $pid ]] || exit 0                                       # stopped, or a newer server took over
      cmd=$(ps -ww -o command= -p $pid 2>/dev/null)
      [[ $cmd == *mlx_*"--port $port"* ]] || exit 0                      # PID recycled: never touch it
      zstat -A m +mtime $stamp 2>/dev/null || exit 0
      (( EPOCHSECONDS - m[1] > idle )) || continue
      [[ -n $(lsof -nP -iTCP:$port -sTCP:ESTABLISHED -t 2>/dev/null) ]] && continue   # answering a request right now
      kill $pid; exit 0
    done' _ $1 $2 $_ZAI_STAMP $_ZAI_PIDF $(( ZAI_IDLE_MIN * 60 )) ${ZAI_REAPER_TICK:-120} >/dev/null 2>&1 &!
}

_zai_server_launch() {   # <server command…> — runs under the launch lock: at most one shell starts a given server
  emulate -L zsh
  local port; _zai_port; port=$REPLY
  local -a reply
  _zai_up && return 0                                          # already answering
  _zai_server_pids; (( $#reply )) && return 0                  # another terminal launched it; it is still loading
  if _zai_is_local && [[ -n $(lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null) ]]; then
    print -u2 "ai: port $port is already used by another program — not starting a model server there"
    return 1
  fi
  print -r -- "--- $(date '+%F %T') starting $ZAI_MODEL on :$port" >> $_ZAI_LOG
  nohup "$@" --model $ZAI_MODEL --host 127.0.0.1 --port $port ${_ZAI_EXTRA_ARGS[@]} >> $_ZAI_LOG 2>&1 &!   # unquoted on purpose: unset → no args (quoted → one "" arg, which mlx_lm.server rejects)
  local -i pid=$!
  print -r -- $pid | _zs_write_atomic $_ZAI_PIDF
  : >| $_ZAI_STAMP
  _zai_spawn_reaper $pid $port
  return 0
}

_zai_server_start() {
  emulate -L zsh
  local -a cmd
  if (( ${_ZAI_VLM:-0} )); then                    # heavy model: text + vision, one server
    if   (( $+commands[mlx_vlm.server] )); then cmd=(mlx_vlm.server)
    elif (( $+commands[uvx] ));            then cmd=(uvx --from mlx-vlm mlx_vlm.server)
    else
      print -u2 "ai: mlx-vlm is not installed → uv tool install mlx-vlm"
      return 1
    fi
  elif (( $+commands[mlx_lm.server] )); then cmd=(mlx_lm.server)
  elif (( $+commands[uvx] ));           then cmd=(uvx --from mlx-lm mlx_lm.server)
  else
    print -u2 "ai: mlx-lm is not installed → uv tool install mlx-lm   (or point ZAI_URL at Ollama / LM Studio)"
    return 1
  fi
  _zs_locked -t 60 $_ZAI_PIDF _zai_server_launch $cmd
  local -i rc=$?
  (( rc == 75 )) && print -u2 "ai: another terminal has been starting this server for over a minute — try again, or: ai-server log"
  return rc
}

# Progress UI. The v4.0 mistake was silence: the first run downloads several GB
# with nothing on screen, which is indistinguishable from a hang.
typeset -g _ZAI_SPIN_PID=''
_zai_status() { [[ -t 2 ]] && print -u2 -Pn "\r\e[2K%F{$ZC[dim]}$1%f" }
_zai_status_done() { [[ -t 2 ]] && print -u2 -n "\r\e[2K" }
_zai_spin_start() {   # dots while we wait; killed by _zai_spin_stop
  [[ -t 2 ]] || return 0
  local msg=$1
  { local -i i=0
    local -a f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 $$ 2>/dev/null; do          # $$ = the parent shell: if it is gone (Ctrl+C, closed tab) so are we
      print -u2 -Pn "\r\e[2K%F{$ZC[acc]}${f[i % 10 + 1]}%f %F{$ZC[dim]}${msg}%f"
      (( i++ )); sleep 0.1
    done } &!
  _ZAI_SPIN_PID=$!
}
_zai_spin_stop() {
  [[ -n $_ZAI_SPIN_PID ]] && { kill $_ZAI_SPIN_PID 2>/dev/null; _ZAI_SPIN_PID='' }
  _zai_status_done
}
_zai_model_cached() {   # is the model already on disk? decides what we tell the user
  [[ -d $ZAI_MODEL ]] && return 0
  local repo=${ZAI_MODEL//\//--}
  [[ -d ${HF_HOME:-$HOME/.cache/huggingface}/hub/models--$repo ]]
}

_zai_ensure() {   # make sure something answers at ZAI_URL; talks while it waits
  _zai_up && return 0
  if ! _zai_is_local || (( ! ZAI_AUTOSTART )); then
    print -u2 "ai: nothing answering at $ZAI_URL"; return 1
  fi
  # memory: the deep 27B doesn't share 24GB with the others — launching one of them stops it first
  [[ $ZAI_URL == ${ZAH_DEEP_URL:-x} || $ZAI_URL == ${ZAH_DEEP_RELAY_URL:-x} ]] || (( ! $+functions[_zah_deep_evict] )) || _zah_deep_evict
  (( $+functions[_zdw_yield] )) && _zdw_yield          # the decision model steps aside if both would not fit
  local first=''
  _zai_model_cached || first=1
  if [[ -n $first ]]; then
    print -u2 -P "%F{$ZC[warn]}first run:%f downloading $ZAI_MODEL — several GB, this happens once."
    print -u2 -P "%F{$ZC[dim]}progress: ai-server log   ·   Ctrl+C is safe, the download resumes   ·   other models: ai-model%f"
  fi
  _zai_server_start || return 1
  local -i i
  local -i limit=${first:+3600}      # first run: up to an hour for the download
  (( limit )) || limit=90            # afterwards: load from disk, ~5-20 s
  _zai_spin_start "${first:+downloading + }loading ${ZAI_MODEL:t} …"
  {
    local -a reply
    local -i pid
    for (( i = 0; i < limit * 2; i++ )); do
      if _zai_up; then (( i > 6 )) && { _zai_spin_stop; print -u2 -P "%F{$ZC[exe]}model ready%f (stays warm ${ZAI_IDLE_MIN}m)" }; return 0; fi
      # cheap liveness check each round; the full identity check only when that fails
      pid=0; [[ -r $_ZAI_PIDF ]] && pid=$(<$_ZAI_PIDF)
      if ! (( pid )) || ! kill -0 $pid 2>/dev/null; then
        _zai_server_pids
        if (( ! $#reply )); then
          _zai_spin_stop
          print -u2 -P "%F{$ZC[err]}ai: the model server exited.%f last lines:"
          tail -n 12 $_ZAI_LOG >&2
          return 1
        fi
      fi
      sleep 0.5
    done
    _zai_spin_stop
    print -u2 "ai: gave up waiting. Check: ai-server log"
    return 1
  } always {
    _zai_spin_stop                    # Ctrl+C mid-wait must not leave the spinner running
  }
}

function ai-server {
  [[ $1 == heavy ]] && { shift; _zah_with ai-server "$@"; return }   # ai-server heavy start|stop|status|log
  case ${1:-status} in
    start)   _zai_ensure && print -r -- "up: $ZAI_MODEL at $ZAI_URL" ;;
    stop)    # only OUR server (verified by its command line, never by PID alone or by "whatever listens on the port"),
             # and only returns once it has actually exited — its memory is free by then
             local -a reply; _zai_server_pids
             if (( ! $#reply )); then zf_rm -f $_ZAI_PIDF; print "not running"
             elif _zs_locked -t 40 $_ZAI_PIDF _zai_server_stop; then print "stopped"
             else print -u2 "ai: could not stop the server (pids: $reply) — try: kill -9 $reply"; return 1; fi ;;
    restart) ai-server stop && ai-server start ;;
    log)     tail -n ${2:-40} -f $_ZAI_LOG ;;
    status)  if _zai_up; then print -r -- "up    $ZAI_URL   model: $ZAI_MODEL   idle-shutdown: ${ZAI_IDLE_MIN}m"
             else print -r -- "down  $ZAI_URL   (autostart=$ZAI_AUTOSTART — starts on first use)"; fi ;;
    *)       print "usage: ai-server start|stop|restart|status|log [lines]" ;;
  esac
}

# _zai_body <stream:true|false> <system> <user> <max_tokens> <temperature> → JSON on stdout
#   $ZAI_HISTORY (optional): file with one {"role","content"} object per line,
#   inserted between the system prompt and the new user turn (?? follow-ups).
_zai_body() {
  # chat_template_kwargs.enable_thinking=false is the documented hard switch for
  # the Qwen3/3.5/3.6 family. Servers that don't know the field ignore it, and
  # _zai_strip_think / _ZAI_THINK_PL drop any <think> block that slips through.
  local hist='[]'
  [[ -n $ZAI_HISTORY && -s $ZAI_HISTORY ]] && hist=$(jq -sc '.' $ZAI_HISTORY 2>/dev/null || print '[]')
  jq -n --arg m "$ZAI_MODEL" --arg s "$2" --arg u "$3" --argjson st $1 --argjson n $4 --argjson t $5 \
        --argjson h "$hist" \
    '{model:$m, stream:$st, max_tokens:$n, temperature:$t,
      chat_template_kwargs:{enable_thinking:false},
      messages:([{role:"system",content:$s}] + $h + [{role:"user",content:$u}])}'
}
# _zai_request <system> <user> [max_tokens] [temperature] → completion text
_zai_request() {
  emulate -L zsh
  (( $+commands[jq] )) || { print -u2 "ai: jq is required → brew install jq"; return 1 }
  : >| $_ZAI_STAMP
  local -a reply; _zai_headers
  local resp out user
  _zai_maybe_redact "$2"; user=$REPLY
  _zai_spin_start "${ZAI_STATUS:-thinking}…"
  resp=$(_zai_body false "$1" "$user" ${3:-256} ${4:-0.2} |
         curl -sS -m $ZAI_TIMEOUT $reply --data-binary @- "$ZAI_URL/chat/completions")
  local -i rc=$?
  _zai_spin_stop
  (( rc == 0 )) || return 1
  out=$(print -r -- $resp | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  _zai_strip_think "$out"; out=$REPLY
  [[ -n ${out//[[:space:]]/} ]] || { print -u2 -r -- "ai: empty reply — ${resp[1,200]}"; return 1 }
  print -r -- $out
}
# F7 (DECIDER_FEATURES_PLAN.md): a check before text leaves this Mac for a cloud service. Two layers, both ADDITIVE and
# both only ever ASK — never silently block, never silently allow:
#   1. deterministic: does the redactor (_zai_redact) change anything? Then the text contains something secret-shaped.
#   2. the decision model, only if it is already up: clean | secret | personal data | company-confidential (swap-checked).
# Returns 0 = fine to send (or you said yes), 1 = you said no or there was no terminal to ask on (fail closed).
_zai_privacy_gate() {   # <what is being sent> <text>
  emulate -L zsh
  local what=$1 text=$2 why='' red th
  red=$(print -rn -- "$text" | _zai_redact 2>/dev/null)
  [[ $red != $text ]] && why="something that looks like a secret or credential"
  if [[ -z $why && ${ZDEC:-1} != 0 && ${ZDEC_PRIVACY:-1} != 0 ]] && _zdw_up 2>/dev/null; then
    th=$(_zdec_threshold privacy)
    if [[ -n $th ]]; then
      local -a reply; local state; state=$(jq -nc --arg p "${text[1,4000]}" '{payload: $p}')
      if _zdec_swapped privacy $state && [[ -n $reply[1] && $reply[1] != clean ]] && (( reply[2] >= th )); then
        case $reply[1] in
          contains_secret)             why="an actual secret or credential" ;;
          contains_personal_data)      why="personal data about real people" ;;
          contains_employer_internal)  why="confidential company material" ;;
        esac
      fi
    fi
  fi
  [[ -z $why ]] && return 0
  print -u2 -P "%F{$ZC[warn]}⚠  $what appears to contain $why — it is about to go to a cloud service.%f"
  [[ -t 0 ]] || { print -u2 "   no terminal to confirm on — not sending."; return 1 }
  local a; read -q "a?   send it anyway? [y/N] "; print
  [[ $a == y ]]
}

# ---- deciders: typed decisions from a local Winnow server (DECIDER_PLAN.md) ------------------
# The server (winnow-inference, POST /v1/systemone) owns the prompt format, letter labels, logits and softmax.
# This client only builds the typed request from agent/decide_spec.json, calls it, and reads typed JSON back —
# no prompts, no letters, no exp/log here (agent/decide.py is the Python twin; decide_parity.zsh compares them).
#   _zdec <task> <state-json> [options-json|""] [rev]  → 0 + reply=(label margin ms "" probs-json) on success
#                                                       → 1 + reply=("" 0 ms REASON) on any fallback
#   REASON: disabled|unfitted|server_down|timeout|bad_response|error. Callers treat every fallback as "do what you
#   did before". Never starts a model (D3), never touches the idle timer (D14).
#   ZDEC=0 off · ZDEC_RAW=1 ignore "unfitted" (eval/parity only) · ZDEC_DEBUG=1 print each decision
#   bad_response is a bug: the raw reply is saved to $ZSH_CACHE/decide-debug/ and the path is printed to stderr.
_zdec() {
  emulate -L zsh
  zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null
  reply=('' 0 0 disabled)
  [[ ${ZDEC:-1} == 0 ]] && return 1
  (( $+commands[jq] )) || { print -u2 "zdec: jq is required → brew install jq"; reply[4]=error; return 1 }
  local task=$1 state=$2 opts=${3:-null} rev=${4:-0}
  [[ $4 == rev ]] && rev=1
  [[ $4 == both ]] && rev=2          # both option orders as TWO questions in ONE request (the swap check, ~half the latency)
  local spec=${ZDEC_SPEC:-${ZSH_CONF:-$HOME/.config/zsh}/agent/decide_spec.json}
  local dbg=${ZSH_CACHE:-$HOME/.cache/zsh}/decide-debug
  local -F t0=$EPOCHREALTIME
  local cfg body url resp rc reason=''
  cfg=$(jq -c --arg t $task '.tasks[$t] as $k | {th: ($k.thresholds | if has("delta") then .delta else .accept_margin end), be: .backend}' $spec) ||
    { print -u2 "zdec: cannot read task $task from $spec"; reply[4]=error; return 1 }
  if [[ -z $ZDEC_RAW && $(jq -r '.th == null' <<< $cfg) == true ]]; then reply[4]=unfitted; return 1; fi
  body=$(jq -c --arg t $task --argjson state $state --argjson opts $opts --arg rev $rev '
      .tasks[$t] as $k | .backend as $b
      | (if $opts != null then $opts else $k.options end) as $o
      | ($o | to_entries | reverse | from_entries) as $rr
      | {model: $b.model, state: $state,
         questions: (if $rev == "2" then {q: {type: $k.type, instructions: $k.instructions, criteria: $o},
                                          r: {type: $k.type, instructions: $k.instructions, criteria: $rr}}
                     else {q: {type: $k.type, instructions: $k.instructions, criteria: (if $rev == "1" then $rr else $o end)}} end),
         winnow: {temperature: $b.temperature, diagnostics: false}}' $spec) ||
    { print -u2 "zdec: could not build the request for $task"; reply[4]=error; return 1 }
  url=${ZDEC_URL:-$(jq -r '.be.url' <<< $cfg)}
  resp=$(curl -s --connect-timeout $(jq -r '.be.connect_timeout_s' <<< $cfg) --max-time $(jq -r '.be.timeout_s' <<< $cfg) \
         -H 'Content-Type: application/json' ${ZDEC_KEY:+-H "Authorization: Bearer $ZDEC_KEY"} --data-binary $body "${url%/}/v1/systemone")
  rc=$?
  case $rc in
    0)  ;;
    7)  reason=server_down ;;
    28) reason=timeout ;;
    *)  reason=error ;;
  esac
  local out=''
  if [[ -z $reason ]]; then
    local prog='.answers.q | select(.type == "choice")
                  | [.choice, ((.probabilities | [.[]] | sort | reverse) as $p | $p[0] - ($p[1] // 0)), (.probabilities | tojson)] | @tsv'
    if (( rev == 2 )); then       # → label_q margin_q label_r margin_r probs_q
      prog='.answers | select(.q.type == "choice" and .r.type == "choice")
            | def m: (.probabilities | [.[]] | sort | reverse) as $p | $p[0] - ($p[1] // 0);
              [.q.choice, (.q | m), .r.choice, (.r | m), (.q.probabilities | tojson)] | @tsv'
    fi
    out=$(jq -er $prog <<< $resp) || {
      command mkdir -p $dbg; local f=$dbg/${EPOCHSECONDS}-$task-parse.txt; print -r -- $resp >| $f
      print -u2 "zdec: unexpected reply from the decision server; raw reply saved to $f"; reason=bad_response
    }
  elif [[ $reason == error ]]; then
    command mkdir -p $dbg; local f=$dbg/${EPOCHSECONDS}-$task-curl$rc.txt; print -r -- $resp >| $f
    print -u2 "zdec: request failed (curl exit $rc); saved to $f"
  fi
  local -i ms=$(( (EPOCHREALTIME - t0) * 1000 ))
  local -a f; f=( "${(@s:	:)out}" )
  if [[ -n $reason ]]; then reply=('' 0 $ms $reason)
  elif (( rev == 2 )); then
    local -F m=$f[2]; (( f[4] < m )) && m=$f[4]
    if [[ $f[1] == $f[3] ]]; then reply=( $f[1] $m $ms '' 1 $f[5] ); else reply=( '' $m $ms '' 0 $f[5] ); fi
  else reply=( $f[1] $f[2] $ms '' $f[3] ); fi
  [[ -z $reason ]] && : >| $_ZDW_STAMP          # Winnow's OWN idle timer only (D14 is about the mlx servers)
  _zdec_log $task ab $state "${reply[@]}"
  [[ -n ${ZDEC_DEBUG:-} ]] && print -u2 -r -- "zdec $task → ${reply[1]:-—} margin=${reply[2]} ${reply[3]}ms ${reply[4]}"
  [[ -z $reason ]]
}

# _zdec_swapped <task> <state-json> [options-json] → both option orders must agree (D5), asked as ONE request.
#   reply=(label margin ms reason swap_ok probs); label is empty when they disagree (swap_ok=0): "uncertain", not a decision.
_zdec_swapped() { _zdec $1 $2 ${3:-null} both }

# _zdec_threshold <task> → prints the fitted primary threshold, or nothing when the task is unfitted (feature off)
_zdec_threshold() {
  jq -r --arg t $1 '.tasks[$t].thresholds | (if has("delta") then .delta else .accept_margin end) // empty' \
    ${ZDEC_SPEC:-${ZSH_CONF:-$HOME/.config/zsh}/agent/decide_spec.json}
}

# one JSONL line per decision (D15): redacted ≤300-char preview, far below PIPE_BUF·… so an O_APPEND write is atomic
_zdec_log() {   # task variant state-json label margin ms reason [probs]
  emulate -L zsh
  local cache=${ZSH_CACHE:-$HOME/.cache/zsh} prev
  prev=${3[1,300]}
  (( $+functions[_zai_redact] )) && prev=$(print -r -- $prev | _zai_redact 2>/dev/null)
  [[ -d $cache ]] || command mkdir -p $cache
  jq -nc --arg t $1 --arg v $2 --arg c "$4" --argjson m ${5:-0} --argjson ms ${6:-0} --arg r "$7" \
        --arg sha "$(print -rn -- $3 | shasum -a 256 | cut -c1-12)" --arg p "${prev[1,300]}" \
    '{t: now|floor, task: $t, variant: $v, chosen: (if $c == "" then null else $c end), margin: ($m*1000|round/1000),
      swap_ok: null, ms: $ms, fallback_reason: (if $r == "" then null else $r end), input_sha: $sha, input_preview: $p}' \
    >> $cache/decide.jsonl 2>/dev/null
}

# ---- Winnow decision server: on-demand lifecycle (DECIDER_FEATURES_PLAN.md Phase 0d) ---------------
# Never resident by default. Same rules as the mlx servers above: one launcher at a time, PIDs verified by command
# line before any signal, stop waits until the process is gone, the idle reaper never kills a server that is
# answering a request. Winnow is a native llama.cpp build (scripts/serve.py execve()s it, so the PID we launch IS the
# server). Two call policies: `explicit` features (ai-memory tidy, zfilter…) may start it; `opportunistic` ones (wtf,
# /remember, ?) use it only if it is already up — nothing on an interactive path ever waits for a model load.
#   ZDW_MODE=swap|coexist    swap: starting Winnow may stop the fast model (:8377) to make room. coexist: never stops anything
: ${ZDW_HOME:=${ZSH_DATA:-$HOME/.local/share/zsh}/winnow}        # holds winnow-inference/ and model/gguf/
: ${ZDW_MODEL_FILE:=Winnow-E4B-Q8_0.gguf}
: ${ZDW_PORT:=8091} ${ZDW_IDLE_MIN:=10} ${ZDW_CONTEXT:=4096} ${ZDW_PARALLEL:=4} ${ZDW_MARGIN_GB:=1.0}
: ${ZDW_MODE:=swap}
: ${ZDW_FAST_PORT:=8377} ${ZDW_MLX_PORTS:=8377 8378 8379 8380}     # the mlx servers Winnow shares the GPU with (tests override)
typeset -g _ZDW_PIDF=$ZSH_CACHE/ai-winnow.pid _ZDW_LOG=$ZSH_CACHE/ai-winnow.log _ZDW_STAMP=$ZSH_CACHE/ai-winnow-last-use

_zdw_up()  { curl -sf -m 1 -o /dev/null http://127.0.0.1:$ZDW_PORT/health }
_zdw_pids() {   # → reply=( PIDs of OUR winnow-server on $ZDW_PORT ), each verified against its command line
  emulate -L zsh
  local p; local -a cand
  reply=()
  [[ -r $_ZDW_PIDF ]] && cand+=( ${(f)"$(<$_ZDW_PIDF)"} )
  cand+=( ${(f)"$(lsof -nP -iTCP:$ZDW_PORT -sTCP:LISTEN -t 2>/dev/null)"} )
  for p in ${(u)cand}; do _zs_pid_is $p winnow-server "--port $ZDW_PORT" && reply+=$p; done
  return 0
}
_zdw_stop() {   # returns only once the process is gone (its GPU memory is released when it exits)
  emulate -L zsh
  local -a reply; _zdw_pids
  if (( $#reply )); then _zs_stop_pids 20 $reply || return 1; fi
  zf_rm -f $_ZDW_PIDF
}
_zdw_gb_of() {   # <pid…> → REPLY: their summed RSS in GB (unified memory: weights count as RSS — measured 7.82 vs 7.90 backend)
  emulate -L zsh
  local p; local -F gb=0; local -a kb
  for p in "$@"; do kb=( ${(f)"$(command ps -o rss= -p $p 2>/dev/null)"} ); (( gb += ${kb[1]:-0} / 1048576.0 )); done
  REPLY=$gb
}
_zdw_others_gb() {   # → REPLY: GB held by the mlx model servers (:8377 fast · :8378 MiMo · :8379 27B · :8380 reader)
  emulate -L zsh
  local p port; local -a pids
  for port in ${=ZDW_MLX_PORTS}; do
    for p in ${(f)"$(lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)"}; do _zs_pid_is $p mlx_ "--port $port" && pids+=$p; done
  done
  _zdw_gb_of $pids
}
_zdw_need_gb() {   # → REPLY: what Winnow will hold: weights + ~0.5 GB context/scratch (measured 7.46 GiB weights → 7.9 GiB)
  emulate -L zsh
  local -a sz
  (( $+builtins[zstat] )) && zstat -A sz +size $ZDW_HOME/model/gguf/$ZDW_MODEL_FILE 2>/dev/null
  if (( $#sz )); then REPLY=$(( sz[1] / 1073741824.0 + 0.5 )); else REPLY=8.5; fi
}
_zdw_make_room() {   # 0 = there is room now (possibly after stopping the fast model in swap mode), 1 = refuse
  emulate -L zsh
  local REPLY; local -F limit need others
  _zah_gpu_budget_gb; limit=$REPLY
  _zdw_need_gb; need=$REPLY
  _zdw_others_gb; others=$REPLY
  local -F short=$(( need + others + ZDW_MARGIN_GB - limit ))
  (( short <= 0 )) && return 0
  if [[ $ZDW_MODE == swap && -n $(lsof -nP -iTCP:$ZDW_FAST_PORT -sTCP:LISTEN -t 2>/dev/null) ]]; then
    local -F fast; local -a pids=( ${(f)"$(lsof -nP -iTCP:$ZDW_FAST_PORT -sTCP:LISTEN -t 2>/dev/null)"} )
    _zdw_gb_of $pids; fast=$REPLY
    if (( short <= fast )); then
      print -u2 -P "%F{$ZC[dim]}stopping the fast model to make room for the decision model…%f"
      ( ZAI_URL=http://127.0.0.1:$ZDW_FAST_PORT/v1; ai-server stop >/dev/null 2>&1 )
      return 0
    fi
  fi
  printf 'ai-winnow: not enough GPU memory: needs %.1f GB + %.1f GB already loaded + %.1f GB margin > %.1f GB limit.\n' \
    $need $others $ZDW_MARGIN_GB $limit >&2
  print -u2 "  stop a model first (ai-server stop · ai-server heavy stop), or raise the limit: ai-deep limit"
  return 1
}
_zdw_spawn_reaper() {   # <pid> — detached; after ZDW_IDLE_MIN idle minutes stop the server (carefully)
  (( ZDW_IDLE_MIN > 0 )) || return 0
  nohup zsh -fc '
    zmodload zsh/datetime; zmodload -F zsh/stat b:zstat
    pid=$1 port=$2 stamp=$3 pidf=$4 idle=$5 tick=$6
    while sleep $tick; do
      kill -0 $pid 2>/dev/null || exit 0
      cur=""; [[ -r $pidf ]] && read -r cur < $pidf
      [[ $cur == $pid ]] || exit 0
      cmd=$(ps -ww -o command= -p $pid 2>/dev/null)
      [[ $cmd == *winnow-server*"--port $port"* ]] || exit 0
      zstat -A m +mtime $stamp 2>/dev/null || exit 0
      (( EPOCHSECONDS - m[1] > idle )) || continue
      [[ -n $(lsof -nP -iTCP:$port -sTCP:ESTABLISHED -t 2>/dev/null) ]] && continue
      kill $pid; exit 0
    done' _ $1 $ZDW_PORT $_ZDW_STAMP $_ZDW_PIDF ${ZDW_IDLE_SECS:-$(( ZDW_IDLE_MIN * 60 ))} ${ZDW_REAPER_TICK:-30} >/dev/null 2>&1 &!
}
_zdw_launch() {   # runs under the launch lock: at most one shell starts it
  emulate -L zsh
  local -a reply
  _zdw_up && return 0
  _zdw_pids; (( $#reply )) && return 0                       # another terminal is loading it
  if [[ -n $(lsof -nP -iTCP:$ZDW_PORT -sTCP:LISTEN -t 2>/dev/null) ]]; then
    print -u2 "ai-winnow: port $ZDW_PORT is used by another program — not starting"; return 1
  fi
  print -r -- "--- $(date '+%F %T') starting $ZDW_MODEL_FILE on :$ZDW_PORT" >> $_ZDW_LOG
  ( cd $ZDW_HOME/winnow-inference && exec nohup python3 scripts/serve.py --profile apple-silicon \
      --model $ZDW_HOME/model/gguf/$ZDW_MODEL_FILE --alias Winnow-E4B --text-only --context $ZDW_CONTEXT \
      --decision-parallel $ZDW_PARALLEL --port $ZDW_PORT >> $_ZDW_LOG 2>&1 ) &!
  local -i pid=$!
  print -r -- $pid | _zs_write_atomic $_ZDW_PIDF
  : >| $_ZDW_STAMP
  _zdw_spawn_reaper $pid
}
# _zdw_ensure explicit|opportunistic → 0 when Winnow answers. opportunistic never starts anything.
_zdw_ensure() {
  emulate -L zsh
  _zdw_up && return 0
  [[ $1 == explicit && ${ZDEC:-1} != 0 ]] || return 1
  [[ -x $ZDW_HOME/winnow-inference/.build/bin/winnow-server ]] ||
    { print -u2 "ai-winnow: the server is not built ($ZDW_HOME/winnow-inference) — see agent/DECIDER_PLAN.md STATUS"; return 1 }
  [[ -f $ZDW_HOME/model/gguf/$ZDW_MODEL_FILE ]] || { print -u2 "ai-winnow: model file missing: $ZDW_HOME/model/gguf/$ZDW_MODEL_FILE"; return 1 }
  _zdw_make_room || return 1
  local REPLY; _zdw_need_gb
  print -u2 -P "%F{$ZC[dim]}starting the decision model (~${REPLY[1,3]} GB, a few seconds; stops itself after ${ZDW_IDLE_MIN} idle min)…%f"
  _zs_locked -t 60 $_ZDW_PIDF _zdw_launch || return 1
  local -i i pid
  for (( i = 0; i < 180; i++ )); do
    _zdw_up && return 0
    pid=0; [[ -r $_ZDW_PIDF ]] && pid=$(<$_ZDW_PIDF)
    (( pid )) && kill -0 $pid 2>/dev/null || { print -u2 "ai-winnow: the server exited — last lines:"; tail -n 8 $_ZDW_LOG >&2; return 1 }
    sleep 0.5
  done
  print -u2 "ai-winnow: gave up waiting — ai-winnow log"; return 1
}
# called by _zai_ensure before an mlx server starts: if both would not fit, the decision model steps aside
_zdw_yield() {
  emulate -L zsh
  _zdw_up || return 0
  local -a reply; _zdw_pids; (( $#reply )) || return 0
  local REPLY; local -F limit others win need
  _zah_gpu_budget_gb; limit=$REPLY
  _zdw_others_gb; others=$REPLY
  _zdw_gb_of $reply; win=$REPLY
  _zah_model_gb $ZAI_MODEL 2>/dev/null; need=$REPLY; (( need > 0 )) || need=8
  (( others + win + need + ZDW_MARGIN_GB > limit )) || return 0
  print -u2 -P "%F{$ZC[dim]}stopping the decision model to make room…%f"
  _zdw_stop
}
function ai-winnow {
  emulate -L zsh
  case ${1:-status} in
    start)  _zdw_ensure explicit && print "up: $ZDW_MODEL_FILE on :$ZDW_PORT (idle stop ${ZDW_IDLE_MIN}m, mode $ZDW_MODE)" ;;
    stop)   local -a reply; _zdw_pids
            if (( ! $#reply )); then zf_rm -f $_ZDW_PIDF; print "not running"
            elif _zs_locked -t 40 $_ZDW_PIDF _zdw_stop; then print "stopped"
            else print -u2 "ai-winnow: could not stop it (pids: $reply)"; return 1; fi ;;
    log)    tail -n ${2:-40} -f $_ZDW_LOG ;;
    budget) local REPLY; local -F limit need others
            _zah_gpu_budget_gb; limit=$REPLY; _zdw_need_gb; need=$REPLY; _zdw_others_gb; others=$REPLY
            printf 'limit %.1f GB · other models loaded %.1f GB · winnow needs %.1f GB · margin %.1f GB → %s\n' \
              $limit $others $need $ZDW_MARGIN_GB $(( need + others + ZDW_MARGIN_GB <= limit )) ;;
    status) if _zdw_up; then print "up    :$ZDW_PORT  $ZDW_MODEL_FILE  idle-stop ${ZDW_IDLE_MIN}m  mode $ZDW_MODE"
            else print "down  (starts only for explicit features: ai-winnow start · ai-memory tidy)"; fi ;;
    *)      print "usage: ai-winnow start|stop|status|budget|log" ;;
  esac
}

# ai-decide [stats|tail [N]|clear] — what the deciders have been doing
function ai-decide {
  emulate -L zsh
  local f=${ZSH_CACHE:-$HOME/.cache/zsh}/decide.jsonl
  [[ -s $f ]] || { print "no decisions logged yet ($f)"; return 0 }
  case ${1:-stats} in
    stats) jq -rs 'group_by(.task) | .[] | "\(.[0].task)  n=\(length)  fallbacks=\(map(select(.fallback_reason != null)) | length)  p50=\(map(.ms) | sort | .[length/2|floor])ms  low-margin(<8)=\(map(select(.margin < 8 and .fallback_reason == null)) | length)"' $f ;;
    tail)  tail -n ${2:-15} $f | jq -r '"\(.t|strftime("%H:%M:%S"))  \(.task)/\(.variant)  \(.chosen // "—")  m=\(.margin)  \(.ms)ms  \(.fallback_reason // "")  \(.input_preview[0:70])"' ;;
    clear) : >| $f; print "cleared" ;;
    *)     print "ai-decide [stats|tail [N]|clear]" ;;
  esac
}

# _zai_stream <system> <user> [max_tokens] → tokens as they arrive
#   $ZAI_CAPTURE (optional): also write the visible answer to this file
_zai_stream() {
  emulate -L zsh
  local _first user
  (( $+commands[jq] )) || { print -u2 "ai: jq is required → brew install jq"; return 1 }
  : >| $_ZAI_STAMP
  local -a reply; _zai_headers
  _zai_maybe_redact "$2"; user=$REPLY
  _zai_spin_start "${ZAI_STATUS:-thinking}…"
  { _zai_body true "$1" "$user" ${3:-800} 0.3 |
    curl -sS -N -m 300 $reply --data-binary @- "$ZAI_URL/chat/completions" |
    { IFS= read -r _first; _zai_spin_stop; print -r -- "$_first"; command cat } } |
    awk '/^data: ?\{/ { sub(/^data: ?/, ""); print; fflush() }' |
    jq --unbuffered -rj '.choices[0].delta.content // empty' 2>/dev/null |
    perl -e "$_ZAI_THINK_PL" |
    if [[ -n $ZAI_CAPTURE ]]; then tee $ZAI_CAPTURE; else command cat; fi
  print
}

# ---- ?? sessions: follow-ups work ("?? now make it recursive") ----------------
# The last ZAI_SESSION_TURNS exchanges are replayed while the session file is
# younger than ZAI_SESSION_MIN minutes; after that (or ??new) it starts fresh.
: ${ZAI_SESSION_MIN:=10}
: ${ZAI_SESSION_TURNS:=4}
typeset -g _ZAI_SESSION=$ZSH_CACHE/ai-session.jsonl
_zai_session_live() {
  local -a m
  [[ -s $_ZAI_SESSION ]] && zstat -A m +mtime $_ZAI_SESSION 2>/dev/null &&
    (( EPOCHSECONDS - m[1] < ZAI_SESSION_MIN * 60 ))
}
_zai_session_add() {   # <user> <assistant> — append + trim as ONE locked, atomic step (was: append, then truncate-rewrite, which lost concurrent turns)
  emulate -L zsh
  [[ -n ${2//[[:space:]]/} ]] || return 0
  _zs_locked $_ZAI_SESSION _zai_session_add_locked "$1" "$2" ||
    print -u2 "ai: could not save this turn to the follow-up session (busy) — the answer above is unaffected"
  return 0
}
_zai_session_add_locked() {
  emulate -L zsh
  local -a reply lines
  _zs_read_lines $_ZAI_SESSION; lines=( "${reply[@]}" )
  lines+=( "$(jq -nc --arg c "${1[1,4000]}" '{role:"user",content:$c}')"
           "$(jq -nc --arg c "${2[1,4000]}" '{role:"assistant",content:$c}')" )
  (( $#lines > ZAI_SESSION_TURNS * 2 )) && lines=( ${lines[-$(( ZAI_SESSION_TURNS * 2 )),-1]} )
  _zs_write_lines $_ZAI_SESSION "${lines[@]}"
}
function ai-session {
  case ${1:-show} in
    new|reset) zf_rm -f $_ZAI_SESSION $ZSH_CACHE/agent-session.jsonl; print "new ?? session" ;;
    show) if _zai_session_live; then jq -r '"\(.role): \(.content[0:160])"' $_ZAI_SESSION
          else print "no live session (follow-ups last ${ZAI_SESSION_MIN}m)"; fi ;;
    *) print "ai-session [show|new]" ;;
  esac
}

# ---- /remember + the vault: facts and persona only YOU can write into ??'s context -------
# The model can never write these files (no tool exposes it) — only /remember (inside a ??
# mode) or editing directly do. See agent/MEMORY_VISION_PLAN.md §3c for the layout:
#   SOUL.md (persona) · USER.md (about you) · MEMORY.md (durable facts) · MOC.md (notes index)
# All four are injected as a capped, budget-enforced block on every ?? call (agent.py's
# build_context()) — editing them here is the ONLY way they change.
# ai-memory tidy: write the deduplicated lines only if the file is still what the user reviewed (run under its lock)
_zah_tidy_apply() {   # <file> <content the user saw> <new lines…>   → 0 written · 3 file changed since · other = write failed
  local tf=$1 before=$2; shift 2
  [[ $(<$tf) == $before ]] || return 3
  _zs_write_lines $tf "$@"
}
# F4, explicit mode: review the whole vault with the decision model (newest fact first, against the older ones) and
# propose removing lines a newer fact replaces or repeats. In/out: _ZAH_TIDY_KEEP (lines). Out: _ZAH_TIDY_ARCH (archive
# rows). It STARTS the decision model if needed (and says so), and stops it again if it started it. Proposals only:
# the caller shows the diff and writes nothing without a "y".
_zah_tidy_smart() {   # <file>
  emulate -L zsh
  local file=$1 th1 th2; th1=$(_zdec_threshold memory_list); th2=$(_zdec_threshold memory_rel)
  if [[ ${ZDEC:-1} == 0 || ${ZDEC_MEMORY:-1} == 0 || -z $th1 || -z $th2 ]]; then
    print -u2 "  (smart pass off: the decision thresholds are not fitted, or ZDEC=0)"; return 0
  fi
  local -a idx=() olderidx out reply; local -i i j k m started=0 total; local REPLY new t
  for (( i = 1; i <= $#_ZAH_TIDY_KEEP; i++ )); do [[ $_ZAH_TIDY_KEEP[i] == '- '* ]] && idx+=$i; done
  (( $#idx >= 2 )) || return 0
  if ! _zdw_up; then
    started=1
    _zdw_ensure explicit || { print -u2 "  smart pass skipped (the decision model is unavailable)"; return 0 }
  fi
  local -A gone
  total=$#idx
  for (( k = $#idx; k >= 2; k-- )); do
    i=$idx[k]; (( ${+gone[$i]} )) && continue
    print -u2 -n "\r  checking facts… $(( total - k + 1 ))/$total"
    olderidx=(); for (( m = 1; m < k; m++ )); do (( ${+gone[$idx[m]]} )) || olderidx+=$idx[m]; done
    (( $#olderidx )) || continue
    (( $#olderidx > 25 )) && olderidx=( ${olderidx[-25,-1]} )
    typeset -ga _ZAH_TEXTS=(); for j in $olderidx; do t=${_ZAH_TIDY_KEEP[j]#- }; _ZAH_TEXTS+=${t%  (*)}; done
    new=${_ZAH_TIDY_KEEP[i]#- }; new=${new%  (*)}
    REPLY=0; _zah_smart_candidate "$new" || continue
    (( REPLY >= 1 )) || continue
    _zah_smart_pair "$_ZAH_TEXTS[REPLY]" "$new" || continue
    if [[ $reply[1] == (replaces|repeats) ]] && (( reply[5] == 1 && reply[2] >= th2 )); then
      j=$olderidx[REPLY]; gone[$j]=1
      _ZAH_TIDY_ARCH+=( "${file:t}"$'\t'"$_ZAH_TIDY_KEEP[j]"$'\t'"$_ZAH_TIDY_KEEP[i]"$'\t'"$(date +%F)"$'\tactive' )
    fi
  done
  print -u2 ""
  out=(); for (( i = 1; i <= $#_ZAH_TIDY_KEEP; i++ )); do (( ${+gone[$i]} )) || out+=( "$_ZAH_TIDY_KEEP[i]" ); done
  _ZAH_TIDY_KEEP=( "${out[@]}" )
  (( started )) && _zdw_stop
  return 0
}
typeset -g _ZAH_VAULT=${ZSH_CONF:-$HOME/.config/zsh}/agent/vault
typeset -g _ZAH_MEMORY=$_ZAH_VAULT/MEMORY.md   # kept for anything that still references it directly
function ai-memory {
  local f=$_ZAH_VAULT/MEMORY.md
  case ${1:-} in
    soul)    f=$_ZAH_VAULT/SOUL.md ;;
    user|me) f=$_ZAH_VAULT/USER.md ;;
    moc)     f=$_ZAH_VAULT/MOC.md ;;
    vault)   zf_mkdir -p $_ZAH_VAULT; ${EDITOR:-nvim} $_ZAH_VAULT; return ;;
    # T2 episodic store (§3e) — separate from the vault files above, so it's dispatched
    # straight to memdb.py's own CLI rather than falling into the `local f=...` file-edit path.
    undo)    _zah_undo; return ;;
    forget)  shift; python3 ${ZSH_CONF:-$HOME/.config/zsh}/agent/memdb.py forget "$@"; return ;;
    stats)   python3 ${ZSH_CONF:-$HOME/.config/zsh}/agent/memdb.py stats; return ;;
    # §3c/§10: deterministic dedup first (no model call); then, if the decision model is fitted, the smart pass above. MEMORY.md is small (2000-char cap,
    # ~20-30 facts) and user-authored, so a model rewrite risks silently changing a fact a
    # diff-skimming reviewer would miss; exact/near-duplicate removal doesn't have that risk.
    tidy)    emulate -L zsh
             local tf=$_ZAH_VAULT/MEMORY.md
             [[ -s $tf ]] || { print "nothing to tidy ($tf empty)"; return }
             local -a lines; lines=("${(@f)$(<$tf)}")
             local -A seen; local -a keep; local -i i
             for ((i = $#lines; i >= 1; i--)); do            # walk backwards: keep the LAST
               local l=$lines[i]                              # (most recent) copy of a repeated
               if [[ $l == '- '* ]]; then                      # fact, matching /remember's own
                 local norm=${(L)${l#- }}; norm=${norm%  (*)}  # supersession behavior
                 (( ${+seen[$norm]} )) && continue
                 seen[$norm]=1
               fi
               keep=("$l" $keep)
             done
             typeset -ga _ZAH_TIDY_KEEP _ZAH_TIDY_ARCH; _ZAH_TIDY_KEEP=( "${keep[@]}" ); _ZAH_TIDY_ARCH=()
             _zah_tidy_smart $tf; keep=( "${_ZAH_TIDY_KEEP[@]}" )       # F4: also propose facts a newer one replaces/repeats
             if (( $#keep == $#lines )); then print "no duplicate or outdated facts in ${tf:t}"; return; fi
             local before=$(<$tf) tmp=$(mktemp)
             print -rl -- "${keep[@]}" >| $tmp
             print "$(( $#lines - $#keep )) line(s) would be removed from ${tf:t}:"
             command diff -u $tf $tmp | tail -n +3
             zf_rm -f $tmp
             read -q '?apply? [y/N] ' || { print; return }
             print
             # Not held under the lock while you read the diff — instead re-checked at the moment of writing:
             # if a /remember landed in between, refuse rather than overwrite it with a stale tidy.
             _zs_locked $tf _zah_tidy_apply $tf "$before" "${keep[@]}"; local -i trc=$?
             case $trc in
               0) print "tidied $tf"
                  if (( $#_ZAH_TIDY_ARCH )); then       # what the smart pass removed is kept, and `ai-memory undo` can bring it back
                    command mkdir -p $_ZAH_VAULT/archive; print -rl -- "${_ZAH_TIDY_ARCH[@]}" >> $_ZAH_VAULT/archive/superseded.tsv
                    print "  ${#_ZAH_TIDY_ARCH} replaced/repeated fact(s) archived — ai-memory undo restores the last one"
                  fi ;;
               3) print -u2 "${tf:t} changed while you were reviewing (a /remember?) — nothing was written; run tidy again" ;;
               *) print -u2 "could not write ${tf:t} (busy) — nothing was written" ;;
             esac
             return ;;
    show|clear|'') ;;
    *)       print "ai-memory [show|clear|soul|user|moc|vault|undo|forget <query>|stats|tidy]   (no args: edit MEMORY.md in \$EDITOR)   or inside ??: /remember <fact>"; return ;;
  esac
  case ${1:-} in
    show)   [[ -s $f ]] && command cat $f || print "nothing there yet — /remember <fact> inside ?? mode, or: ai-memory"
            return ;;
    clear)  _zs_locked $f _zs_write_lines $f && print "cleared $f" || print -u2 "could not clear $f (busy)"; return ;;
  esac
  zf_mkdir -p ${f:h}; [[ -f $f ]] || : >| $f
  ${EDITOR:-nvim} $f
}

# /remember, as one transaction (run under the file's lock via _zs_locked). The old inline version read the
# file, rewrote it with `print -rl -- $lines` (which DROPS blank lines — your headings' spacing), or appended
# with `>>` (which glues the fact onto the last line if the file lacked a trailing newline), and two tabs
# remembering at once lost one of them. Result message → $_ZAH_REM_MSG.
_zah_remember() {   # <file> <char cap> <fact> [replace|repeat <exact old line>]   (optional pair = F4's decision)
  emulate -L zsh
  local rfile=$1 rcap=$2 fact=$3 sact=$4 sold=$5
  local line="- ${fact}  ($(date +%F))" subj=${(L)fact} old='' ltext lsubj
  local -a reply lines
  local -i i replaced=0 newsize smart=0
  if [[ $subj == *' is '* ]]; then subj=${subj%% is *}
  elif [[ $subj == *' = '* ]]; then subj=${subj%% = *}; fi
  _zs_read_lines $rfile; lines=( "${reply[@]}" )
  for ((i = 1; i <= $#lines; i++)); do
    [[ $lines[i] == '- '* ]] || continue
    ltext=${lines[i]#- }; ltext=${ltext%  (*)}
    lsubj=${(L)ltext}
    if [[ $lsubj == *' is '* ]]; then lsubj=${lsubj%% is *}
    elif [[ $lsubj == *' = '* ]]; then lsubj=${lsubj%% = *}; fi
    if [[ -n $subj && $lsubj == $subj ]]; then old=$lines[i]; lines[i]=$line; replaced=1; break; fi
  done
  # F4: a decision made OUTSIDE the lock from a snapshot. It is applied only if the old line is still there verbatim
  # (compare-and-swap); otherwise the fact is simply appended, exactly as before.
  if (( ! replaced )) && [[ -n $sact && -n $sold ]]; then
    local -i idx=${lines[(ie)$sold]}
    if (( idx <= $#lines )); then
      local soldtext=${sold#- }; soldtext=${soldtext%  (*)}
      if [[ $sact == repeat ]]; then _ZAH_REM_MSG="already remembered: \"$soldtext\""; return 0; fi
      old=$lines[idx]; lines[idx]=$line; replaced=1; smart=1
    fi
  fi
  (( replaced )) || lines+=( "$line" )
  newsize=${#${(F)lines}}
  if (( newsize > rcap )); then
    local tip="ai-memory ${${rfile:t}:l:r} to edit it by hand"
    [[ $rfile == */MEMORY.md ]] && tip="ai-memory tidy to remove duplicates, or $tip"
    _ZAH_REM_MSG="vault full (${rfile:t}) — $tip"; return 1
  fi
  _zs_write_lines $rfile "${lines[@]}" || { _ZAH_REM_MSG="could not write ${rfile:t}"; return 1 }
  if (( smart )); then
    local arch=${rfile:h}/archive/superseded.tsv
    command mkdir -p ${arch:h}
    print -r -- "${rfile:t}"$'\t'"$old"$'\t'"$line"$'\t'"$(date +%F)"$'\tactive' >> $arch
    local oldtext=${old#- }; oldtext=${oldtext%  (*)}
    _ZAH_REM_MSG="replaced: \"$oldtext\" — ai-memory undo puts it back"
  elif (( replaced )); then
    local oldtext=${old#- }; oldtext=${oldtext%  (*)}
    _ZAH_REM_MSG="replaced old fact (${oldtext}) — ai-memory ${${rfile:t}:l:r} to review"
  else
    _ZAH_REM_MSG="remembered — ai-memory ${${rfile:t}:l:r} to review"
  fi
}

# F4 (DECIDER_FEATURES_PLAN.md): does a new fact replace / repeat an existing one? Opportunistic — runs only when the
# decision model is ALREADY up, and only for tasks whose thresholds are fitted; every other case = today's behaviour.
# Sets _ZAH_SMART_ACTION (replace|repeat|''), _ZAH_SMART_OLD (the exact old line), _ZAH_SMART_NOTE (a hint).
_zah_smart_texts() {   # <file> → reply=( fact lines ) and _ZAH_TEXTS=( their texts ); newest 25
  emulate -L zsh
  local -a reply lines; local l
  _zs_read_lines $1; lines=( "${reply[@]}" )
  reply=( ${(M)lines:#- *} )
  (( $#reply > 25 )) && reply=( ${reply[-25,-1]} )
  typeset -ga _ZAH_TEXTS=()
  for l in $reply; do l=${l#- }; _ZAH_TEXTS+=( ${l%  (*)} ); done
  typeset -ga _ZAH_FACTLINES; _ZAH_FACTLINES=( "${reply[@]}" )
}
_zah_smart_pair() {   # <old text> <new fact> → 0 + reply=(label margin ms '' swap_ok) when the relation is decided
  emulate -L zsh
  local state; state=$(jq -nc --arg o "$1" --arg n "$2" '{old_fact: $o, new_fact: $n}')
  _zdec_swapped memory_rel $state
}
_zah_smart_candidate() {   # <new fact> → REPLY = index into _ZAH_TEXTS of the fact it is about (0 = none/uncertain)
  emulate -L zsh
  local -a reply
  local th; th=$(_zdec_threshold memory_list); REPLY=0
  [[ -n $th && $#_ZAH_TEXTS -gt 0 ]] || return 1
  local opts state
  opts=$(jq -nc '$ARGS.positional | to_entries | map({key: "fact_\(.key + 1)", value: .value}) | from_entries
                 | . + {none: "no listed fact is about the same subject"}' --args "${_ZAH_TEXTS[@]}") || return 1
  state=$(jq -nc --arg f "$1" '{new_fact: $f}')
  _zdec memory_list $state $opts 0 || return 1
  [[ $reply[1] == fact_<-> ]] && (( reply[2] >= th )) || return 0
  REPLY=${reply[1]#fact_}
}
_zah_smart_resolve() {   # <file> <fact>
  emulate -L zsh
  typeset -g _ZAH_SMART_ACTION='' _ZAH_SMART_OLD='' _ZAH_SMART_NOTE=''
  [[ ${ZDEC:-1} == 0 || ${ZDEC_MEMORY:-1} == 0 ]] && return 0
  _zdw_up || return 0
  local th; th=$(_zdec_threshold memory_rel); [[ -n $th ]] || return 0
  _zah_smart_texts $1; (( $#_ZAH_TEXTS )) || return 0
  local REPLY; local -a reply
  _zah_smart_candidate "$2" || return 0
  local -i n=$REPLY; (( n >= 1 )) || return 0
  _zah_smart_pair "$_ZAH_TEXTS[n]" "$2" || return 0
  [[ $reply[1] == (replaces|repeats) ]] || return 0
  if (( reply[5] == 1 && reply[2] >= th )); then
    _ZAH_SMART_ACTION=${${reply[1]/replaces/replace}/repeats/repeat}; _ZAH_SMART_OLD=$_ZAH_FACTLINES[n]
  else
    _ZAH_SMART_NOTE="may relate to \"${_ZAH_TEXTS[n][1,60]}\" — ai-memory tidy to review"
  fi
}

# ai-memory undo — put back the newest replaced line. The NEW fact stays (both may be true); the old line goes back next to it.
_zah_undo_apply() {   # <file> <old line> <new line> <archive> <row index>       (under the file's lock)
  emulate -L zsh
  local f=$1 old=$2 new=$3 arch=$4; local -i ri=$5
  local -a reply lines rows; _zs_read_lines $f; lines=( "${reply[@]}" )
  local -i idx=${lines[(ie)$new]} cap=2000
  [[ ${f:t} == USER.md ]] && cap=1200
  (( idx <= $#lines )) || { _ZAH_REM_MSG="the replacing line is no longer in ${f:t} — edit by hand: ai-memory"; return 2 }
  if (( ${lines[(ie)$old]} > $#lines )); then
    lines=( "${(@)lines[1,idx-1]}" "$old" "${(@)lines[idx,-1]}" )
    (( ${#${(F)lines}} <= cap )) || { _ZAH_REM_MSG="vault full (${f:t}) — nothing restored"; return 1 }
    _zs_write_lines $f "${lines[@]}" || return 1
  fi
  _zs_read_lines $arch; rows=( "${reply[@]}" )
  rows[ri]=${rows[ri]%active}restored
  _zs_write_lines $arch "${rows[@]}"
}
_zah_undo() {
  emulate -L zsh
  local arch=$_ZAH_VAULT/archive/superseded.tsv
  local -a reply rows; local -i i
  _zs_read_lines $arch; rows=( "${reply[@]}" )
  for (( i = $#rows; i >= 1; i-- )); do [[ ${rows[i]##*$'\t'} == active ]] && break; done
  (( i >= 1 )) || { print "nothing to undo"; return 1 }
  local -a c; c=( "${(@ps:\t:)rows[i]}" )
  typeset -g _ZAH_REM_MSG=''
  _zs_locked $_ZAH_VAULT/$c[1] _zah_undo_apply $_ZAH_VAULT/$c[1] "$c[2]" "$c[3]" $arch $i; local -i rc=$?
  if (( rc == 0 )); then print -r -- "restored: ${${c[2]#- }%  (*)}   (the newer fact stays)"
  else print -u2 -r -- "${_ZAH_REM_MSG:-undo failed (${c[1]} busy?)}"; return 1; fi
}

# ---- ~/.zshrc.local: set one variable without touching anything else in the file -------------
# Replaces any existing `VAR=` / `export VAR=` line and keeps every other line — comments and blank lines
# included — byte for byte. Locked and atomic: this file holds your own settings, and the old rewrite
# (`print -rl -- $lines >| file`) dropped blank lines and could leave it truncated if interrupted.
_zs_local_set() {   # <VAR> <value>
  emulate -L zsh
  local lf=${ZS_LOCAL:-$HOME/.zshrc.local}
  _zs_locked $lf _zs_local_set_locked $lf "$1" "$2" || { print -u2 "could not update $lf (busy)"; return 1 }
}
_zs_local_set_locked() {
  emulate -L zsh; setopt extendedglob
  local lf=$1 var=$2 val=$3 l
  local -a reply out
  _zs_read_lines $lf
  for l in "${reply[@]}"; do
    [[ $l == (#s)[[:space:]]#(export[[:space:]]##)#${var}=* ]] && continue
    out+=( "$l" )
  done
  out+=( "$var=${(q)val}" )
  _zs_write_lines $lf "${out[@]}"
}

# ---- ai-access: see/revoke the 7-day directory grants ?? got via request_directory_access ----
# Granting only ever happens through a real y/N inside ?? — there is deliberately no `grant` here.
function ai-access {
  case ${1:-list} in
    list)        python3 ${ZSH_CONF:-$HOME/.config/zsh}/agent/dirgrants.py list ;;
    revoke)      shift; python3 ${ZSH_CONF:-$HOME/.config/zsh}/agent/dirgrants.py revoke "$@" ;;
    revoke-all)  python3 ${ZSH_CONF:-$HOME/.config/zsh}/agent/dirgrants.py revoke-all ;;
    *)           print "ai-access [list|revoke <path>|revoke-all]   (grants come only from a y/N inside ??, and expire after 7 days)" ;;
  esac
}

# ---- /escalate: hand the ?? conversation to OpenCode when the 9B is out of its depth ----
# OpenCode's own permission prompts ("ask") are the execution gate here — never pass
# --auto. This writes a markdown brief (agent.py --handoff, no model call) and opens
# OpenCode's interactive TUI on it; you approve every edit/command it wants to make.
#   NOTE (measured): the local 9B model through OpenCode's "build" agent is slow —
#   its large tool-laden system prompt costs a lot of prefill on this model, and
#   mlx_vlm.server (like mlx_lm.server) only serves one request at a time. Set ZAH_ESCALATE_MODEL to a
#   provider/model you already have configured in OpenCode (cloud or otherwise) for
#   a much better experience; the local one is there mainly so /escalate always has
#   *something* to hand off to, offline.
: ${ZAH_ESCALATE_MODEL:=}
function ai-escalate {
  emulate -L zsh
  (( $+commands[opencode] )) || { print -u2 "ai-escalate: opencode not found (needs the opencode CLI)"; return 1 }
  local f=${ZSH_CACHE:-$HOME/.cache/zsh}/agent-handoff.md
  ZSH_CACHE=${ZSH_CACHE:-$HOME/.cache/zsh} ZAH_URL=$ZAH_URL uv run --quiet --script ${ZSH_CONF:-$HOME/.config/zsh}/agent/agent.py --handoff $f "$@" || return 1
  local -a m
  if [[ -n $ZAH_ESCALATE_MODEL ]]; then
    m=(-m $ZAH_ESCALATE_MODEL)
  else
    local REPLY; _zah_prepare 2>/dev/null && m=(-m "mlx-local/$REPLY")
  fi
  # local models (the default) never leave this Mac; only a cloud ZAH_ESCALATE_MODEL is gated
  if [[ -n $ZAH_ESCALATE_MODEL && $ZAH_ESCALATE_MODEL != mlx-local/* ]]; then
    _zai_privacy_gate "the escalation brief (model: $ZAH_ESCALATE_MODEL)" "$(<$f)" || { print -u2 "ai-escalate: not sent"; return 1 }
  fi
  print -P "%F{$ZC[dim]}handing off to OpenCode (plan agent — it asks before editing or running anything)…%f"
  opencode $m --agent plan --prompt "$(<$f)"
}

# ---- the heavy model: ?? is an agent ---------------------------------------------------
# MiMo-V2.6-Distill-Qwen-9B (Qwen3.5-9B fine-tuned on agent data), mixed 4/6-bit.
# Measured on this M4 Pro: ~24.6 tok/s decode, 5.9 GB peak. Its own server on
# :8378 so the fast model behind ? / wtf / explain stays warm and unaffected.
# Thinking is OFF for ?? (answers in seconds); ??? turns it on.
#   agent:    ~/.config/zsh/agent/agent.py   (read-only MCP tools: mac + web)
#   security: ~/.config/zsh/agent/guard.py   (prompt-injection scaffold)
#   audit:    $ZSH_CACHE/agent-audit.jsonl   (every tool call, block and proposal)
: ${ZAH_MODEL:=DJLougen/MiMo-V2.6-Distill-Qwen-9B-MLX-mixed-4-6}
: ${ZAH_URL:=http://127.0.0.1:8378/v1}
: ${ZAH_IDLE_MIN:=20}          # the 9B model frees its ~6 GB after this many idle minutes
# mlx_lm guesses the tool-call parser from the chat template and looks for
# "<tool_call>\n<function="; MiMo's template has no newline there, so it picks
# the JSON parser and silently DROPS every tool call. Fix without touching the
# HF cache: a local model dir of symlinks + a tokenizer_config.json that names
# the right parser. Rebuilt automatically when the snapshot changes.
_zah_prepare() {   # _zah_prepare [model-repo, default $ZAH_MODEL] → REPLY: what to pass as --model
  emulate -L zsh; setopt extendedglob
  local model=${1:-$ZAH_MODEL}
  REPLY=$model
  [[ -d $model ]] && return 0                                  # already a local path
  local -a snap=( ${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${model//\//--}/snapshots/*(N/om[1]) )
  if (( ! $#snap )); then
    print -u2 -P "%F{$ZC[warn]}first run:%f downloading $model (once)…"
    uvx --from 'huggingface_hub[hf_xet]' hf download $model >&2 || return 1
    snap=( ${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${model//\//--}/snapshots/*(N/om[1]) )
    (( $#snap )) || return 1
  fi
  local dir=${ZSH_DATA:-$HOME/.local/share/zsh}/models/${model:t} f
  if [[ ! -s $dir/.snapshot || $(<$dir/.snapshot) != $snap[1] ]]; then
    zf_rm -rf $dir 2>/dev/null; zf_mkdir -p $dir
    for f in $snap[1]/*(N); do [[ ${f:t} == tokenizer_config.json ]] || ln -s $f $dir/${f:t}; done
    jq '. + {tool_parser_type: "qwen3_coder"}' $snap[1]/tokenizer_config.json >| $dir/tokenizer_config.json || return 1
    print -r -- $snap[1] >| $dir/.snapshot
  fi
  REPLY=$dir
}
_zah_with() {   # run "$@" with the ai-server machinery pointed at the heavy model
  local REPLY; _zah_prepare || return 1
  local ZAI_URL=$ZAH_URL ZAI_MODEL=$REPLY ZAI_IDLE_MIN=$ZAH_IDLE_MIN ZAI_KEY=${ZAH_KEY:-}
  local _ZAI_PIDF=$ZSH_CACHE/ai-heavy.pid _ZAI_LOG=$ZSH_CACHE/ai-heavy.log _ZAI_STAMP=$ZSH_CACHE/ai-heavy-last-use
  # mlx_vlm.server, not mlx_lm.server: the heavy model handles text AND images from one
  # process (verified: same weights, tool calls still parse via a per-request "tool_parser"
  # override — see agent.py). Measured cost: ~1.1 GB more resident than text-only mlx_lm,
  # even for a plain text question, because the vision tower stays loaded. Accepted because
  # it's only while ?? is actively warm (ZAH_IDLE_MIN still unloads it), and one server beats
  # maintaining two (mlx_lm for text, mlx_vlm for images) with separate tool-parsing quirks.
  local _ZAI_VLM=1
  # Prefix cache: without it every ?? step re-read its whole 5-10k-token prompt at
  # ~240 tok/s (20-40s per step, measured 2026-09-27: cached_tokens=0 on every request).
  # MiMo is hybrid (Gated DeltaNet) like the 27B, so reuse needs recurrent-state
  # checkpoints: every 1024 tokens, keep 8. MiMo + the fast model leave room for 2GB.
  APC_ENABLED=1 APC_CHECKPOINT_INTERVAL_TOKENS=${ZAH_APC_INTERVAL:-1024} APC_CHECKPOINT_ENTRIES=${ZAH_APC_ENTRIES:-8} \
    APC_MEMORY_MAX_GB=${ZAH_APC_MEM_GB:-2} APC_DISK_MAX_GB=${ZAH_APC_DISK_GB:-4} "$@"
}

# ---- the deep model: ??? engages Qwen3.8-27B (3-bit) for hard multi-step questions -------
# See agent/DEEP_MODEL_PLAN.md. One heavy model fits in 24GB at a time: starting this one
# stops both the :8378 (MiMo) and :8377 (fast) servers first; they restart lazily on your
# next ?? / ? / ai. ZAH_DEEP_MODEL is unset by default — set it once you've picked a build
# (Step A of the plan), e.g. a ready 3-bit MLX conversion of Qwen3.8-27B.
: ${ZAH_DEEP_MODEL:=lukaskremla/Qwen3.8-27B-3bit-MLX}   # 2-bit builds tested 2026-09-27: broken (loops, wrong answers)
: ${ZAH_DEEP_MTP:=lukaskremla/Qwen3.8-27B-MTP-3bit-MLX}   # or "bundled" (repo's own mtp/ dir); empty = off
: ${ZAH_DEEP_URL:=http://127.0.0.1:8379/v1}
: ${ZAH_DEEP_IDLE_MIN:=10}
: ${ZAH_DEEP_SESSION_TURNS:=2}   # bounds how much prior conversation gets re-prefilled → bounds peak memory
: ${ZAH_DEEP_EFFORT:=low}               # ??? default. medium spent 250-400 thinking tokens (~30-40s at ~10 tok/s) even on
                                        # "what is my name"; ???? (high) is there for questions that need it
: ${ZAH_DEEP_HIGH_EFFORT:=high}         # ???? uses this instead
: ${ZAH_DEEP_MAX_TOKENS:=4096}
: ${ZAH_DEEP_DEADLINE:=600}
: ${ZAH_DEEP_KV_BITS:=8}                 # 8-bit uniform KV to fit safely within the 16GB default ceiling
: ${ZAH_DEEP_MAX_KV_SIZE:=12288}   # crashed the GPU (Metal OOM) at 24576 under real multi-turn load —
                                    # continuous_batching pre-allocates the KV pool up to this size regardless
                                    # of actual use, and the default 16GB Metal ceiling has no margin for it
: ${ZAH_DEEP_PREFILL_STEP:=512}     # smaller prefill chunks need less scratch memory per step
# The reader: a small model reads every large tool result / recall / terminal dump for the 27B and
# hands it a digest (agent.py relay_via_fast_model), so the 27B's slow prefill (~100 tok/s here) goes
# on decisions only. Starting it beside the 27B under the default 16GB GPU limit crashed and rebooted
# the Mac (2026-09-27), so it only starts when _zah_reader_fits says the arithmetic works (needs the
# raised limit: ai-deep limit); otherwise ??? uses agent.py's in-process keyword filter, which is free.
: ${ZAH_DEEP_RELAY_MODEL:=mlx-community/Qwen3-4B-Instruct-2507-4bit}
: ${ZAH_DEEP_RELAY_URL:=http://127.0.0.1:8380/v1}
_zah_relay_with() {   # run "$@" with the ai-server machinery pointed at the deep mode's reader model
  local ZAI_URL=$ZAH_DEEP_RELAY_URL ZAI_MODEL=$ZAH_DEEP_RELAY_MODEL ZAI_IDLE_MIN=$ZAH_DEEP_IDLE_MIN ZAI_KEY=
  local _ZAI_PIDF=$ZSH_CACHE/ai-relay.pid _ZAI_LOG=$ZSH_CACHE/ai-relay.log _ZAI_STAMP=$ZSH_CACHE/ai-relay-last-use
  local _ZAI_VLM=0
  local -a _ZAI_EXTRA_ARGS=()
  "$@"
}
# The deep 27B, MiMo and the fast/reader models do NOT fit in 24GB together. Two rules keep them apart:
#   * starting any of the others first stops the 27B (and its reader) — _zah_deep_evict, called from _zai_ensure
#   * the reader may join the 27B only if the arithmetic works against the GPU working-set limit
#     (weights + KV + margin < limit). "Free RAM" is the wrong measure: it read 4.8GB the moment before
#     the reader took the machine to 60MB free.
_zah_model_gb() {   # <repo id or dir> → REPLY: GB of weight files ("0" when the model isn't on disk)
  emulate -L zsh; setopt extendedglob
  local m=$1 d x
  local -a f sz
  for d in $m $ZSH_DATA/models/${m:t} ${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${m//\//--}/snapshots/*(N/om[1]); do
    [[ -d $d ]] || continue
    f=( $d/*.safetensors(N) ); (( $#f )) && break
  done
  local -F total=0
  for x in $f; do zstat -A sz +size $x 2>/dev/null && (( total += sz[1] )); done
  REPLY=$(( total / 1000000000.0 ))
}
_zah_gpu_budget_gb() {   # → REPLY: the GPU working-set limit in GB (iogpu.wired_limit_mb, or macOS's default of 2/3 of RAM)
  emulate -L zsh
  local -i mb=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null)
  if (( mb > 0 )); then REPLY=$(( mb / 1024.0 ))
  else REPLY=$(( $(sysctl -n hw.memsize 2>/dev/null) / 1073741824.0 * 2 / 3 )); fi
}
_zah_reader_fits() {   # → 0 if 27B + reader + KV + margin fit the GPU limit; REPLY = the numbers
  emulate -L zsh
  local -F deep rdr budget need
  _zah_model_gb $ZAH_DEEP_MODEL; deep=$REPLY
  _zah_model_gb $ZAH_DEEP_RELAY_MODEL; rdr=$REPLY
  _zah_gpu_budget_gb; budget=$REPLY
  need=$(( deep + rdr + ${ZAH_DEEP_KV_GB:-2.5} + 0.5 ))
  REPLY=$(printf '%.1f + %.1f GB weights + KV/margin = %.1f GB needed, %.1f GB GPU limit' $deep $rdr $need $budget)
  (( deep > 0 && rdr > 0 && need <= budget ))
}
_zah_deep_evict() {   # stop the 27B and its reader if running (memory); returns when they are gone
  emulate -L zsh
  local -a reply
  ( ZAI_URL=$ZAH_DEEP_URL; _ZAI_PIDF=$ZSH_CACHE/ai-deep.pid; _zai_server_pids; (( $#reply )) ) ||
    ( ZAI_URL=$ZAH_DEEP_RELAY_URL; _ZAI_PIDF=$ZSH_CACHE/ai-relay.pid; _zai_server_pids; (( $#reply )) ) || return 0
  print -u2 -P "%F{$ZC[dim]}stopping the deep model to make room…%f"
  _zah_relay_with ai-server stop >/dev/null 2>&1
  _zah_deep_with ai-server stop >/dev/null 2>&1
  return 0
}
_zah_deep_with() {   # run "$@" with the ai-server machinery pointed at the deep model
  [[ -n $ZAH_DEEP_MODEL ]] || { print -u2 "???: ZAH_DEEP_MODEL is unset — pick a 3-bit Qwen3.8-27B build first, see agent/DEEP_MODEL_PLAN.md"; return 1 }
  local REPLY; _zah_prepare $ZAH_DEEP_MODEL || return 1
  local ZAI_URL=$ZAH_DEEP_URL ZAI_MODEL=$REPLY ZAI_IDLE_MIN=$ZAH_DEEP_IDLE_MIN ZAI_KEY=${ZAH_KEY:-}
  local _ZAI_PIDF=$ZSH_CACHE/ai-deep.pid _ZAI_LOG=$ZSH_CACHE/ai-deep.log _ZAI_STAMP=$ZSH_CACHE/ai-deep-last-use
  local _ZAI_VLM=1
  local -a _ZAI_EXTRA_ARGS=(--max-kv-size $ZAH_DEEP_MAX_KV_SIZE --prefill-step-size $ZAH_DEEP_PREFILL_STEP)
  if [[ -n $ZAH_DEEP_MTP ]]; then
    local mtpdir
    if [[ $ZAH_DEEP_MTP == bundled ]]; then mtpdir=$ZAI_MODEL/mtp; [[ -d $mtpdir ]] || mtpdir=''
    else _zah_prepare $ZAH_DEEP_MTP; mtpdir=$REPLY; fi
    [[ -n $mtpdir ]] && _ZAI_EXTRA_ARGS+=(--draft-model $mtpdir --draft-kind mtp)
  else
    _ZAI_EXTRA_ARGS+=(--thinking-budget 6000)
  fi
  [[ -n $ZAH_DEEP_KV_BITS ]] && _ZAI_EXTRA_ARGS+=(--kv-bits $ZAH_DEEP_KV_BITS)
  # Prefix cache: Qwen3.8 is hybrid (Gated DeltaNet), so a cached prefix can only resume at a saved
  # recurrent-state checkpoint. Defaults (every 2048 tokens, keep 2) only kept one checkpoint near the
  # END of the last prompt — past where the next question diverges — so every question re-read ~6-8k
  # tokens at ~100 tok/s. Checkpoint every 1024 and keep 8 (~75-150MB each) so one lands inside the
  # static system+tools prefix. Measured: see agent/DEEP_MODEL_PLAN.md §7.
  APC_ENABLED=1 APC_CHECKPOINT_INTERVAL_TOKENS=${ZAH_DEEP_APC_INTERVAL:-1024} APC_CHECKPOINT_ENTRIES=${ZAH_DEEP_APC_ENTRIES:-8} \
    APC_MEMORY_MAX_GB=${ZAH_DEEP_APC_MEM_GB:-1} "$@"   # <1GB is free with the 27B loaded; the SSD tier holds the rest
}
function ai-deep {   # ai-deep [status|stop|log [n]|limit]  — manual control of the deep model's server
  if [[ ${1:-} == limit ]]; then
    local cur=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null)
    print -r -- "iogpu.wired_limit_mb: ${cur:-0}  (0 = macOS default, ~16GB on this machine)"
    if [[ -f /Library/LaunchDaemons/local.iogpu-wired-limit.plist ]]; then
      print -r -- "LaunchDaemon: installed"
    else
      local conf=${ZSH_CONF:-$HOME/.config/zsh}
      print -r -- "LaunchDaemon: not installed. To raise the limit at every boot (needs sudo once):"
      print -r -- "  sudo cp $conf/launchd/local.iogpu-wired-limit.plist /Library/LaunchDaemons/"
      print -r -- "  sudo chown root:wheel /Library/LaunchDaemons/local.iogpu-wired-limit.plist"
      print -r -- "  sudo launchctl load /Library/LaunchDaemons/local.iogpu-wired-limit.plist"
    fi
    return 0
  fi
  [[ ${1:-} == stop ]] && _zah_relay_with ai-server stop >/dev/null
  _zah_deep_with ai-server "$@"
}
: ${ZSH_AGENT_SCREEN:=1}   # 0 disables sending recent terminal-screen text to ??/zagent
function zagent {   # the run is _zagent_run; this wrapper only guarantees its temp files never outlive it (Ctrl+C used to leak them)
  local prop=$ZSH_CACHE/agent-proposal.${sysparams[pid]}.$(( ++_ZS_TMP_SEQ )) ctx=$ZSH_CACHE/agent-context.${sysparams[pid]}.$_ZS_TMP_SEQ
  { _zagent_run "$@" } always { zf_rm -f $prop $ctx }
}
function _zagent_run {
  emulate -L zsh
  (( $+commands[uv] )) || { print -u2 "??: needs uv (brew install uv)"; return 1 }
  local cmd w
  local -a warns
  local -i deep=0
  local effort=$ZAH_DEEP_EFFORT stamp=$ZSH_CACHE/ai-heavy-last-use
  local -a pass_args
  while (( $# )); do
    case $1 in
      --deep)
        [[ -n $ZAH_DEEP_MODEL ]] || { print -u2 "???: ZAH_DEEP_MODEL is unset — pick a 3-bit Qwen3.8-27B build first, see agent/DEEP_MODEL_PLAN.md"; return 1 }
        deep=1; shift ;;
      --effort)
        effort=$2; shift 2 ;;
      *)
        pass_args+=( "$1" ); shift ;;
    esac
  done
  if (( deep )); then
    stamp=$ZSH_CACHE/ai-deep-last-use
    if [[ $(pmset -g batt 2>/dev/null) == *"Battery Power"* ]] && [[ $(pmset -g 2>/dev/null) == *"powermode 1"* ]]; then
      print -u2 -P "%F{$ZC[warn]}warning:%f on battery in Low Power mode — GPU is throttled"
    fi
    ai-server stop >/dev/null 2>&1            # fast model, :8377 — one big model at a time on 24GB
    _zah_with ai-server stop >/dev/null 2>&1  # heavy MiMo, :8378
    local ZAI_SESSION_TURNS=$ZAH_DEEP_SESSION_TURNS
    _zah_deep_with _zai_ensure || return 1
    local relay_mode=extract
    if _zah_relay_with _zai_up; then relay_mode=model          # already running
    elif _zah_reader_fits; then
      _zah_relay_with _zai_ensure && relay_mode=model
    else
      print -u2 -P "%F{$ZC[dim]}???: reader model would not fit (${REPLY}) — using the keyword filter. Raising the GPU limit (ai-deep limit) makes room.%f"
    fi
    [[ $relay_mode == model ]] && : >| $ZSH_CACHE/ai-relay-last-use
  else
    _zah_with _zai_ensure || return 1
  fi
  : >| $stamp
  local REPLY
  if (( deep )); then _zah_prepare $ZAH_DEEP_MODEL || return 1
  else _zah_prepare || return 1
  fi
  {
    print -r -- "last_command: ${_ZS_LAST_CMD}"
    print -r -- "exit_status: ${_ZS_LAST_STATUS}"
    print -r -- "cwd: ${PWD/#$HOME/~}"
    if (( ${ZSH_AGENT_SCREEN:-1} )) && (( $+functions[_zs_tab_output] )); then
      local screen=$(_zs_tab_output 2>/dev/null | tail -n $(( deep ? 25 : 60 )))   # every line costs prefill time on the 27B
      if [[ -n $screen ]]; then
        print -r -- "--- terminal (last lines) ---"
        print -r -- "$screen"
      fi
    fi
  } >| $ctx 2>/dev/null
  local conf=${ZSH_CONF:-$HOME/.config/zsh}
  if (( deep )); then
    ZAH_URL=$ZAH_DEEP_URL ZAH_MODEL=$REPLY ZAH_KEY=${ZAH_KEY:-} ZSH_CACHE=$ZSH_CACHE \
    ZAH_PROFILE=deep ZAH_REASONING_EFFORT=$effort ZAH_MAX_TOKENS=$ZAH_DEEP_MAX_TOKENS ZAH_DEADLINE=$ZAH_DEEP_DEADLINE ZAH_RELAY=1 ZAH_RELAY_MODE=$relay_mode ZAH_RELAY_URL=$ZAH_DEEP_RELAY_URL ZAH_RELAY_MODEL=$ZAH_DEEP_RELAY_MODEL \
    ZAH_MAX_KV_SIZE=$ZAH_DEEP_MAX_KV_SIZE \
    ZAI_SESSION_MIN=$ZAI_SESSION_MIN ZAI_SESSION_TURNS=$ZAI_SESSION_TURNS \
      uv run --quiet --script $conf/agent/agent.py --think --proposal $prop --context $ctx "${pass_args[@]}"
  else
    ZAH_URL=$ZAH_URL ZAH_MODEL=$REPLY ZAH_KEY=${ZAH_KEY:-} ZSH_CACHE=$ZSH_CACHE ZAH_RELAY_URL=$ZAI_URL ZAH_RELAY_MODEL=$ZAI_MODEL \
    ZAH_MAX_KV_SIZE=32768 \
    ZAI_SESSION_MIN=$ZAI_SESSION_MIN ZAI_SESSION_TURNS=$ZAI_SESSION_TURNS \
      uv run --quiet --script $conf/agent/agent.py --proposal $prop --context $ctx "${pass_args[@]}"
  fi
  local -i rc=$?
  : >| $stamp
  if [[ -s $prop ]]; then
    cmd=$(jq -r '.command' $prop)
    warns=( ${(f)"$(jq -r '.warnings[]' $prop)"} )
    _zai_dangerous "$cmd" && warns+=( "potentially destructive" ) || { local REPLY; _zai_danger2 "$cmd" && warns+=( "$REPLY" ) }
    print -P -- "%F{$ZC[exe]}→ on your prompt%f (Enter runs it · Ctrl+U clears):  ${cmd//\%/%%}"
    for w in $warns; do print -P -- "%F{$ZC[err]}!! ${w//\%/%%}%f"; done
    print -z -- "$cmd"
    typeset -g _ZS_AIPEND_NEXT=$cmd       # AI modes: Enter runs it instead of asking again
    typeset -g _ZS_AIPROP=$cmd            # _zs_precmd watches for this running next → feeds the result back
  fi
  return rc
}

# ---- screen vision: shot → screenshot, zagent-shot → capture + ask in one step -------------
# The heavy model (?? / zagent) is multimodal — see _zah_with's _ZAI_VLM note above — so a
# screenshot goes straight into the SAME conversation, no separate description step.
typeset -g ZSH_SHOTS=$ZSH_CACHE/shots
function shot {   # shot [full|window|region] → screenshot path, also $ZSH_SHOTS/latest.png
  ${ZSH_CONF:-$HOME/.config/zsh}/bin/zshot "$@"
}
function zagent-shot {   # zagent-shot [--deep] [--effort <val>] [full|window|region] <question>  (default mode: region)
  emulate -L zsh
  local mode=region
  local -a zargs
  while (( $# )); do
    case $1 in
      full|window|region) mode=$1; shift ;;
      --deep)             zargs+=( --deep ); shift ;;
      --effort)           zargs+=( --effort "$2" ); shift 2 ;;
      --new)              zargs+=( --new ); shift ;;
      --think)            zargs+=( --think ); shift ;;
      *)                  break ;;
    esac
  done
  # NOT `local path`: `path` is zsh's special array tied to $PATH — shadowing it here wiped
  # PATH for the rest of this function's scope, breaking the nested zagent call below in a
  # way that only showed up as a mystifying "needs uv" from inside a shell that clearly HAD
  # uv on PATH. Found by testing, not by inspection — a good reminder to avoid `path` as a
  # variable name in zsh generally.
  local shotpath; shotpath=$(shot $mode) || return 1
  print -P "%F{$ZC[dim]}captured: ${shotpath/#$HOME/~}%f"
  zagent "${zargs[@]}" --image $shotpath "$@"
}

# ---- /equip: pick the vision model, tested not trusted ---------------------------------
# mimo reuses the weights ?? already has (no download); qwen4b is the lighter, less-proven
# alternative (better architecture on paper, but new enough to have little mlx-vlm mileage —
# hence "tested, not trusted": it only becomes the default if it actually passes the
# smoke test below, same bar mimo itself had to clear in this project's own step-0 testing).
function ai-equip {   # ai-equip [mimo|qwen4b|<hf-repo>]  — no arg: show current + usage
  emulate -L zsh
  (( $+commands[mlx_vlm.generate] )) || { print -u2 "ai-equip: needs mlx-vlm → uv tool install mlx-vlm"; return 1 }
  if [[ -z $1 ]]; then
    print "current: $ZAH_MODEL"
    print "usage: ai-equip mimo | qwen4b | <hf-repo>"
    return 0
  fi
  local repo
  case $1 in
    mimo)   repo=DJLougen/MiMo-V2.6-Distill-Qwen-9B-MLX-mixed-4-6 ;;
    qwen4b) repo=mlx-community/Qwen3.5-4B-MLX-4bit ;;   # unverified as an mlx-vlm repo — the smoke test below is what decides, not this label
    *)      repo=$1 ;;
  esac

  print -P "%F{$ZC[dim]}smoke-testing $repo — a solid-red image must come back \"red\"…%f"
  local png; png=$(mktemp -t ai-equip-XXXX).png
  python3 -c "
import zlib, struct
w = h = 64
row = b'\x00' + b'\xff\x00\x00' * w
raw = row * h
chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
open('$png', 'wb').write(
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(raw))
    + chunk(b'IEND', b'')
)
" 2>/dev/null
  local out
  out=$(mlx_vlm.generate --model $repo --image $png --prompt "What single color is this? One word." \
        --max-tokens 10 --thinking-mode disabled 2>&1 | tail -5)
  zf_rm -f $png
  if [[ ${out:l} != *red* ]]; then
    print -P "%F{$ZC[err]}ai-equip: $repo failed the image test%f — kept %B$ZAH_MODEL%b"
    print -P "%F{$ZC[dim]}output was: ${out[1,200]//\%/%%}%f"
    return 1
  fi
  print -P "%F{$ZC[exe]}passed%f — $repo can see"
  _zah_with ai-server stop >/dev/null 2>&1   # the running server is keyed to the old model

  _zs_local_set ZAH_MODEL $repo || return 1
  print -P "%F{$ZC[exe]}?? now uses%f $repo   (recorded in ~/.zshrc.local — starts fresh on the next ?? / ??shot)"
}

# ---- context: what the model gets to see -----------------------------------------
_zai_context() {
  emulate -L zsh
  [[ -n $_ZAI_OS ]] || typeset -g _ZAI_OS="macOS $(sw_vers -productVersion 2>/dev/null) $(uname -m)"
  local -a tools files stack
  local t branch=''
  for t in fd rg bat eza jq sd dust procs xh gh git docker kubectl aws uv python3 node npm brew ffmpeg magick sqlite3 curl rsync; do
    (( $+commands[$t] )) && tools+=$t
  done
  files=( *(N[1,40]) )
  [[ -f pyproject.toml || -f requirements.txt ]] && stack+=python
  [[ -f uv.lock ]]      && stack+=uv
  [[ -f package.json ]] && stack+=node
  [[ -f Cargo.toml ]]   && stack+=rust
  [[ -f Dockerfile || -f compose.yaml || -f docker-compose.yml ]] && stack+=docker
  [[ -f template.yaml || -f serverless.yml || -f cdk.json ]] && stack+=aws
  [[ -r .git/HEAD ]]    && branch=${$(<.git/HEAD)#ref: refs/heads/}
  # recent commands: keep 6, but truncate huge one-liners (those giant
  # `python manage.py shell -c "..."` from your history were 982 lines / 46k
  # tokens and made wtf time out after 300s). Show at most 120 chars per line
  # and 1200 chars total.
  local recent
  recent="$(fc -ln -6 2>/dev/null | cut -c1-120 | head -c 1200 | _zai_redact)"
  print -r -- "OS: $_ZAI_OS · shell: zsh
 cwd: ${PWD/#$HOME/~}${branch:+ (git branch: $branch)}
 project: ${stack:-unknown}
 files here: ${files[*]:-none}
 installed tools: ${tools[*]}
 recent commands:
 ${recent:-none}"
}

_zai_clean_cmd() {   # strip markdown fences / backticks / "$ " that small models like to add
  emulate -L zsh; setopt extendedglob
  local s=$1
  s=${s//\`\`\`[a-z]#/}
  s=${${s##[[:space:]]##}%%[[:space:]]##}
  s=${s#\$ }
  [[ $s == \`*\` ]] && s=${${s#\`}%\`}
  print -r -- $s
}
_zai_dangerous() {
  local re='(^|[;&|[:space:]])(sudo|rm[[:space:]]+-[a-zA-Z]*[rRf]|mkfs|dd[[:space:]]+(if|of)=|diskutil[[:space:]]+erase|killall|shutdown|reboot)|>[[:space:]]*/dev/(r?disk|sd)|ch(mod|own)[[:space:]]+-R|git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f|push[[:space:]].*(--force|-f([[:space:]]|$)))|[Dd][Rr][Oo][Pp][[:space:]]+(TABLE|table|DATABASE|database)|\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh([[:space:]]|$)|:\(\)[[:space:]]*\{'
  [[ $1 =~ $re ]]
}
# F11 (DECIDER_FEATURES_PLAN.md): a second opinion for commands the regex above does NOT match (`find -delete`,
# `git checkout -- .`, `defaults delete`, `curl … | bash -s`, `git stash drop`…). It can only ADD a warning — never remove
# or soften _zai_dangerous — and it is opportunistic: only when the decision model is already up and its threshold is
# fitted. Sets REPLY to the message and returns 0 when it flags the command. ~0.5 s, so call it only after _zai_dangerous.
_zai_danger2() {   # <command>
  emulate -L zsh
  [[ ${ZDEC:-1} == 0 || ${ZDEC_DANGER:-1} == 0 ]] && return 1
  _zdw_up 2>/dev/null || return 1
  local th; th=$(_zdec_threshold danger); [[ -n $th ]] || return 1
  local -a reply; local state
  state=$(jq -nc --arg c "$1" --arg d "${PWD/#$HOME/~}" --argjson g "$( [[ -n $(git rev-parse --git-dir 2>/dev/null) ]] && print true || print false )" \
            '{command: $c, cwd: $d, in_git_repo: $g}')
  _zdec danger $state || return 1
  (( reply[2] >= th )) || return 1
  case $reply[1] in
    destructive)  REPLY="this may be destructive or hard to undo (decision-model check) — read every word first" ;;
    remote_exec)  REPLY="this downloads code from the network and runs it (decision-model check) — read it first" ;;
    *)            return 1 ;;
  esac
}

_zai_nl2cmd() {   # <request> [previous-command] → one command
  local out prev=''
  [[ -n $2 ]] && prev="
Previous command (the request below modifies it — keep what it does unless told otherwise): $2"
  out=$(_zai_request "You are a command-line expert on macOS with zsh. Convert the request into ONE shell command (pipes and && are fine). Output ONLY the command: a single line, no markdown, no backticks, no commentary. Use BSD/macOS flag syntax, not GNU. Prefer the installed modern tools from the context when they fit. Use real file names from the context; use <placeholders> only when a value is unknown. If the request is not a shell task, output: echo 'not a shell task'" \
"$(_zai_context)
$prev
Request: $1" 220 0.1) || return 1
  _zai_clean_cmd "$out"
}

# ---- line-editor integration ----------------------------------------------------------
typeset -g _ZAI_LAST_Q='' _ZAI_LAST_OUT=''
_zai_fill() {   # natural language → BUFFER.   <request> [refine: 1]
  local q=$1 cmd err base=''
  if [[ -z ${q//[[:space:]]/} ]]; then
    zle -M "describe what you want, e.g.   ? find files over 100MB changed this week"; return 1
  fi
  if [[ -n $2 ]]; then
    [[ -n $_ZAI_LAST_OUT ]] || { zle -M "?+ refines the last ? result — there is none in this shell yet"; return 1 }
    base=$_ZAI_LAST_OUT
  fi
  zle -M "thinking…  ($ZAI_MODEL)"; zle -R
  if ! err=$(_zai_ensure 2>&1); then zle -M "${err:-ai: backend unavailable}"; return 1; fi
  cmd=$(_zai_nl2cmd "$q" "$base" 2>/dev/null)
  if [[ -z $cmd ]]; then zle -M "ai: no answer — check: ai-server log"; return 1; fi
  print -s -- "?${2:++} $q"          # the question stays in history (Up brings it back)
  _ZAI_LAST_Q=$q _ZAI_LAST_OUT=$cmd
  BUFFER=$cmd; CURSOR=${#BUFFER}
  local REPLY
  if _zai_dangerous "$cmd"; then zle -M "!! potentially destructive — read it first.   Ctrl+X e explains · Ctrl+_ undoes"
  elif _zai_danger2 "$cmd"; then zle -M "!! $REPLY.   Ctrl+X e explains · Ctrl+_ undoes"
  else zle -M "Enter runs · ?+ <change> refines it · Ctrl+X e explains · Ctrl+_ undoes"; fi
}
_zai_cmd_widget() { _zai_fill "${${BUFFER##\?# }## }" }

_zai_accept_line() {
  (( $+functions[_zs_car_take] )) && _zs_car_take && return 0   # Enter on a highlighted carousel entry
  if [[ -n $_ZS_AIMODE ]]; then _zs_aimode_accept; else _zai_accept_plain; fi
}
_zai_accept_plain() {
  setopt local_options extended_glob
  local trimmed=${${BUFFER##[[:space:]]#}%%[[:space:]]#}
  if [[ $trimmed == '????' ]]; then
    _zs_aimode_enter deep_high; return
  elif [[ $trimmed == '???' ]]; then
    _zs_aimode_enter deep; return
  elif [[ $trimmed == '??' ]]; then
    _zs_aimode_enter agent; return
  elif [[ $trimmed == '?' ]]; then
    _zs_aimode_enter cmd; return
  fi

  # ?? / ??? / ???? → agent models + tools
  if [[ $BUFFER == '????new'(|' '*) ]]; then
    BUFFER="zagent --deep --effort ${ZAH_DEEP_HIGH_EFFORT:-high} --new ${(qq)${${BUFFER#\?\?\?\?new}# }}"
  elif [[ $BUFFER == '???new'(|' '*) ]]; then
    BUFFER="zagent --deep --new ${(qq)${${BUFFER#\?\?\?new}# }}"
  elif [[ $BUFFER == '??new'(|' '*) ]]; then
    BUFFER="zagent --new ${(qq)${${BUFFER#\?\?new}# }}"
  elif [[ $BUFFER == '????shot'(|' '*) ]]; then
    local _shotrest=${${BUFFER#\?\?\?\?shot}# } _shotmode=''
    case ${_shotrest%% *} in full|window|region) _shotmode=${_shotrest%% *}; _shotrest=${_shotrest#* } ;; esac
    BUFFER="zagent-shot --deep --effort ${ZAH_DEEP_HIGH_EFFORT:-high} ${_shotmode:+$_shotmode }${(qq)_shotrest}"
  elif [[ $BUFFER == '???shot'(|' '*) ]]; then
    local _shotrest=${${BUFFER#\?\?\?shot}# } _shotmode=''
    case ${_shotrest%% *} in full|window|region) _shotmode=${_shotrest%% *}; _shotrest=${_shotrest#* } ;; esac
    BUFFER="zagent-shot --deep ${_shotmode:+$_shotmode }${(qq)_shotrest}"
  elif [[ $BUFFER == '??shot'(|' '*) ]]; then
    # ??shot [full|window|region] <question>  → capture then ask, one step.
    # Mode word (if any) is parsed here, not left in the quoted question, so
    # a question containing *, `, $() etc. can't be misread as shell syntax.
    local _shotrest=${${BUFFER#\?\?shot}# } _shotmode=''
    case ${_shotrest%% *} in full|window|region) _shotmode=${_shotrest%% *}; _shotrest=${_shotrest#* } ;; esac
    BUFFER="zagent-shot ${_shotmode:+$_shotmode }${(qq)_shotrest}"
  elif [[ $BUFFER == '???? '* ]]; then
    # deep model (Qwen3.8-27B 3-bit), high reasoning effort — see agent/DEEP_MODEL_PLAN.md
    BUFFER="zagent --deep --effort ${ZAH_DEEP_HIGH_EFFORT:-high} ${(qq)${BUFFER#\?\?\?\? }}"
  elif [[ $BUFFER == '??? '* ]]; then
    # deep model, medium reasoning effort (its own default is xhigh — too slow on a laptop)
    BUFFER="zagent --deep ${(qq)${BUFFER#\?\?\? }}"
  elif [[ $BUFFER == '?? '* ]]; then
    BUFFER="zagent ${(qq)${BUFFER#\?\? }}"
  elif [[ $BUFFER == '?+ '* ]]; then
    _zai_fill "${BUFFER#\?+ }" 1; return
  elif [[ $BUFFER == '? '* ]]; then
    _zai_fill "${BUFFER#\? }"; return
  elif [[ $BUFFER == *$'\n'* ]]; then
    # Pasted multiple commands (e.g. 3 lines from clipboard) — stock
    # accept-line only runs the first line and drops the rest. Push the
    # remaining lines back onto the editing stack so they run sequentially.
    # print -z is LIFO, so push in reverse to preserve order.
    local -a lines
    lines=( ${(f)BUFFER} )
    BUFFER=${lines[1]}
    zle .accept-line
    local i
    for (( i = $#lines; i >= 2; i-- )); do
      [[ -n ${lines[i]//[[:space:]]/} ]] && print -z -- "${lines[i]}"
    done
    return
  fi
  zle .accept-line
}
zle -N accept-line _zai_accept_line    # defined before the deferred plugins, so they wrap *this*

_zai_explain_widget() {
  [[ -n ${BUFFER//[[:space:]]/} ]] || { zle -M "type a command first, then Ctrl+X e"; return }
  local cmd=$BUFFER
  zle push-line                        # your line is restored at the next prompt
  BUFFER=" explain ${(qq)cmd}"         # leading space → kept out of history
  zle accept-line
}
_zai_fix_widget() {
  [[ -n $_ZS_LAST_CMD ]] || { zle -M "no previous command"; return }
  local err cmd
  zle -M "fixing: $_ZS_LAST_CMD"; zle -R
  if ! err=$(_zai_ensure 2>&1); then zle -M "${err:-ai: backend unavailable}"; return 1; fi
  cmd=$(_zai_request "The user's previous zsh command on macOS failed. Output ONLY the corrected command on one line — no markdown, no commentary. Fix typos, wrong flags (BSD, not GNU), bad quoting, missing sudo/paths. If the right fix is unknowable, output the most likely one." \
"$(_zai_context)

Failed command: $_ZS_LAST_CMD
Exit status: $_ZS_LAST_STATUS" 200 0.1 2>/dev/null)
  cmd=$(_zai_clean_cmd "$cmd")
  [[ -n $cmd ]] || { zle -M "ai: no suggestion"; return 1 }
  BUFFER=$cmd; CURSOR=${#BUFFER}
  # same gate as ? and wtf — this is the path you hit while already annoyed
  local REPLY
  if _zai_dangerous "$cmd"; then zle -M "!! suggested fix is DESTRUCTIVE — read every word before Enter.   Ctrl+X e explains · Ctrl+_ undoes"
  elif _zai_danger2 "$cmd"; then zle -M "!! suggested fix: $REPLY.   Ctrl+X e explains · Ctrl+_ undoes"
  else zle -M "suggested fix — review, then Enter"; fi
}

# ---- commands ------------------------------------------------------------------------------
function ai {   # temp file cleanup guaranteed by this wrapper (see zagent)
  local cap=$ZSH_CACHE/ai-answer.${sysparams[pid]}.$(( ++_ZS_TMP_SEQ ))
  { _ai_run "$@" } always { zf_rm -f $cap }
}
function _ai_run {
  emulate -L zsh
  local input='' user fresh=''

  [[ $1 == (-n|--new) ]] && { fresh=1; shift }
  local prompt="$*"
  [[ -n $fresh ]] && zf_rm -f $_ZAI_SESSION
  [[ -t 0 ]] || input=$(head -c ${ZAI_MAX_INPUT:-24000})
  if [[ -z $prompt && -z $input ]]; then
    [[ -n $fresh ]] && { print "new ?? session"; return 0 }
    print "usage:  ai <question>      <command> | ai <instruction>      (or on the prompt:  ?? <question>)
        ai --new …  /  ??new …   start over instead of following up (sessions last ${ZAI_SESSION_MIN}m)"
    return 1
  fi
  _zai_ensure || return 1
  local ZAI_STATUS='thinking' ZAI_HISTORY=''
  if _zai_session_live; then
    ZAI_HISTORY=$_ZAI_SESSION
    ZAI_STATUS="thinking (follow-up · ??new to reset)"
  fi
  user=$prompt
  [[ -n $input ]] && user="${prompt:-Summarize this.}

--- input ---
$input"
  ZAI_CAPTURE=$cap _zai_stream "You are a senior engineer answering inside a terminal. Be direct and concise: plain text, short paragraphs, commands on their own lines, no headings, no filler. The user is on macOS with zsh. Earlier turns of this conversation, if any, are context for follow-up questions." "$user" ${ZAI_MAX_TOKENS:-900}
  [[ -s $cap ]] && { _zai_maybe_redact "$user"; _zai_session_add "$REPLY" "$(<$cap)" }
  zf_rm -f $cap
  return 0
}
alias ai='noglob ai'       # so  ai what does *.py[cod] match?  is not globbed

function explain {
  emulate -L zsh
  local cmd="$*"
  [[ -n $cmd ]] || cmd=$(fc -ln -1)
  _zai_ensure || return 1
  print -P -- "%F{$ZC[dim]}${cmd//\%/%%}%f"
  local ZAI_STATUS='reading the command'
  _zai_stream "Explain shell commands for an experienced engineer. First line: what it does overall. Then one short line per part: 'token — meaning'. Call out anything destructive, slow or surprising. Plain text only, no markdown." "$cmd" 450
}

function wtf {   # temp file cleanup guaranteed by this wrapper (see zagent)
  local tmp=$ZSH_CACHE/wtf.${sysparams[pid]}.$(( ++_ZS_TMP_SEQ ))
  { _wtf_run "$@" } always { zf_rm -f $tmp }
}
# ---- wtf fast path: deterministic failure triage (DECIDER_FEATURES_PLAN.md F1) ---------------------------------
# _zs_triage <cmd> <status> <output> → 0 and reply=( class fix note ) when a rule matches, else 1. NO model, no fork
# beyond `node -v`. `fix` is a read-only diagnostic or the single command the evidence names — never sudo, never
# rm/chmod. An empty fix means "the class is clear, there is no safe one-liner". Env facts come from
# _zs_triage_env (pinned by tests with ZS_TRI_FIXED=1).
typeset -gA _ZS_TRI_ENV
_zs_triage_env() {
  [[ -n $ZS_TRI_FIXED ]] && return 0
  local d=$PWD nv='' f pm=npm
  _ZS_TRI_ENV=( venv_active ${${VIRTUAL_ENV:+1}:-0} has_venv 0 has_pyproject 0 has_package_json 0 nvmrc_major '' node_major ''
                have_uv $(( $+commands[uv] )) have_fnm $(( $+commands[fnm] )) have_gh $(( $+commands[gh] )) pm npm local_mods '' )
  [[ -f .venv/bin/activate ]] && _ZS_TRI_ENV[has_venv]=1
  [[ -f pyproject.toml ]] && _ZS_TRI_ENV[has_pyproject]=1
  if [[ -f package.json ]]; then
    _ZS_TRI_ENV[has_package_json]=1
    [[ -f pnpm-lock.yaml ]] && pm=pnpm; [[ -f yarn.lock ]] && pm=yarn; [[ -f bun.lockb || -f bun.lock ]] && pm=bun
    _ZS_TRI_ENV[pm]=$pm
  fi
  local -a lm=( *.py(N:r) *(N/:t) src/*.py(N:r) src/*(N/:t) ); _ZS_TRI_ENV[local_mods]="${(j: :)lm[1,200]}"   # your own top-level modules/packages
  local -i i
  for (( i = 0; i < 4; i++ )); do
    for f in $d/.nvmrc $d/.node-version; do
      [[ -r $f ]] && { nv=${${(f)"$(<$f)"}[1]#v}; break 2 }
    done
    [[ $d == / ]] && break; d=${d:h}
  done
  if [[ $nv == [0-9]* ]]; then
    _ZS_TRI_ENV[nvmrc_major]=${nv%%.*}
    (( $+commands[node] )) && _ZS_TRI_ENV[node_major]=${${$(node -v 2>/dev/null)#v}%%.*}
  fi
}
typeset -gA _ZS_PYPKG=( yaml pyyaml cv2 opencv-python PIL pillow sklearn scikit-learn bs4 beautifulsoup4 dotenv python-dotenv
  dateutil python-dateutil jwt pyjwt git gitpython serial pyserial attr attrs Crypto pycryptodome magic python-magic )
_zs_triage() {
  emulate -L zsh; setopt extendedglob
  local cmd=$1 st=$2 out=$3 w=${${(z)1}[1]} port='' mod='' p=''
  reply=()
  _zs_triage_env
  local -A E; E=( "${(@kv)_ZS_TRI_ENV}" )
  # busy port
  if [[ $out == *(EADDRINUSE|ddress already in use|"port is already in use"|ort [0-9]##" is already in use"|ort [0-9]##" was already in use"|ort [0-9]##" is in use"|"already running on port"|"port is already allocated"|"Is port "[0-9]##" in use")* ]]; then
    local l    # read the port ONLY from the lines that report the conflict (not stack frames or timestamps), and take the LAST :N on a line
    for l in ${(f)out}; do
      [[ $l == *(EADDRINUSE|ddress already in use|"port is already in use"|ort [0-9]##" is"|ort [0-9]##" was"|"already running on port"|"already allocated"|"Is port ")* ]] || continue
      if   [[ $l =~ 'Bind for [0-9.:]*:([0-9]{2,5})' ]]; then port=$match[1]
      elif [[ $l =~ '[Pp]ort ([0-9]{2,5})' ]]; then port=$match[1]
      elif [[ $l =~ '.*:([0-9]{2,5})([^0-9]|$)' ]]; then port=$match[1]; fi
      [[ -n $port ]] && break
    done
    [[ -z $port && $cmd =~ '([0-9]{4,5})' ]] && port=$match[1]
    if [[ -n $port ]]; then reply=( port_in_use "lsof -nP -iTCP:$port -sTCP:LISTEN" "port $port is already taken — this shows who holds it" )
    else reply=( port_in_use "lsof -nP -iTCP -sTCP:LISTEN" "a port is already taken — this lists what is listening" ); fi
    return 0
  fi
  # python: import fails
  if [[ $out =~ "No module named ['\"]?([A-Za-z0-9_.-]+)" ]]; then
    local full=${match[1]}; mod=${full%%.*}
    [[ " $E[local_mods] " == *" $mod "* ]] && return 1          # your own package: an import/path bug, not a missing install
    # part of the standard library (of a NEWER python than the one that ran): installing "tomllib" is wrong — use another interpreter
    if (( $+commands[python3] )) && [[ " $(python3 -c 'import sys; print(*sys.stdlib_module_names)' 2>/dev/null) " == *" $mod "* ]]; then return 1; fi
    # namespace packages: the import name says nothing about which distribution provides it — never guess one
    if [[ $mod == (google|azure|backports|zope|jaraco|ruamel|sphinxcontrib|mpl_toolkits|opentelemetry) && $full == *.* ]]; then
      reply=( missing_dep "" "'$full' is part of a namespace package — the import name does not say which distribution provides it (search PyPI for it)" ); return 0
    fi
    mod=${_ZS_PYPKG[$mod]:-$mod}
    if   (( E[has_venv] && ! E[venv_active] )); then reply=( wrong_venv "source .venv/bin/activate" "this folder has a .venv that is not active, so '$mod' is not visible" )
    elif (( E[has_pyproject] && E[have_uv] )); then reply=( missing_dep "uv add $mod" "'$mod' is not installed in this project" )
    elif (( E[have_uv] )); then reply=( missing_dep "uv venv && source .venv/bin/activate && uv pip install $mod" "no virtualenv here — this makes one and installs '$mod'" )
    else reply=( missing_dep "" "'$mod' is not installed and there is no uv or venv here to install it into" ); fi
    return 0
  fi
  # node: module missing (non-relative)
  if (( E[has_package_json] )) && [[ $out =~ "Cannot find (module|package) '([^'./][^']*)'" ]]; then
    reply=( missing_dep "${E[pm]:-npm} install" "node_modules is missing '${match[2]}'" ); return 0
  fi
  # A test run prints error names as DATA ("✓ retries after ECONNREFUSED", an assertion about 'Permission denied'): never
  # diagnose the environment from it. Only the rules above (imports, ports) are specific enough to survive that.
  [[ $out == *(" PASS "|" FAIL "|"✓"|"✕"|"Tests:"|" passed"|"FAILED tests/"|"failed, "[0-9]## passed)* ]] && return 1
  # ssh key rejected / credentials rejected
  if [[ $out == *"Permission denied (publickey"* ]]; then
    reply=( auth_expired "ssh -T git@github.com" "the SSH key was rejected — this tests it against GitHub" ); return 0
  fi
  if [[ $out == *(uthentication failed|ould not read Username|401 Unauthorized|HTTP 401|ad credentials|equires authentication|E401)* ]]; then
    case $w in
      gh|git)          if (( E[have_gh] )); then reply=( auth_expired "gh auth login" "GitHub no longer accepts the saved credentials" )
                       else reply=( auth_expired "" "the saved credentials were rejected — refresh the token or use an SSH key (gh is not installed here)" ); fi ;;
      npm|pnpm|yarn)   reply=( auth_expired "npm login" "the registry rejected the credentials" ) ;;
    esac
    (( $#reply )) && return 0
  fi
  if [[ $w == (docker|podman) && $out == *("authentication required"|"requested access to the resource is denied")* ]]; then
    reply=( auth_expired "$w login" "the registry does not accept your credentials" ); return 0
  fi
  # permission denied on a path: show it, never "fix" it with sudo/chmod
  if [[ $out == *([Pp]ermission denied|EACCES)* ]]; then
    if   [[ $out =~ "(open|scandir|mkdir|unlink|rename|access|copyfile) '([^']+)'" ]]; then p=$match[2]
    elif [[ $out =~ "Permission denied: '([^']+)'" ]]; then p=$match[1]
    elif [[ $out =~ '[Pp]ermission denied: ([^ ]+)' ]]; then p=$match[1]
    elif [[ $out =~ '([^: ]+): [Pp]ermission denied' ]]; then p=$match[1]; fi
    if [[ -n $p ]]; then
      reply=( permission "ls -ld ${(q)p}" "no permission on $p — this shows its owner and mode (change it deliberately; no sudo suggested)" ); return 0
    fi
  fi
  if [[ $out == *"Operation not permitted"* ]]; then
    reply=( permission "" "macOS blocked this (a protected path or a missing privacy permission) — sudo will not help; check System Settings → Privacy & Security" ); return 0
  fi
  # wrong node for the project
  if [[ $w == (node|npm|npx|pnpm|yarn|corepack|tsx|ts-node|vite|next|bun) && -n $E[nvmrc_major] && -n $E[node_major] &&
        $E[nvmrc_major] != $E[node_major] && $E[have_fnm] == 1 && ( -z $out || $out == *(ngine|ersion|yntaxError|nexpected token|equires|ERR_)* ) ]]; then
    reply=( wrong_node "fnm use" "this project wants node $E[nvmrc_major] and you are on $E[node_major]" ); return 0
  fi
  # network / service
  if [[ $out == *(ould not resolve host|emporary failure in name resolution|ENOTFOUND|Network is unreachable|nodename nor servname|ETIMEDOUT|onnection timed out|"Operation timed out"|SSL_ERROR_SYSCALL|"SSL connect error")* ]]; then
    reply=( network "ping -c 1 1.1.1.1" "the network or DNS is unreachable — this checks basic connectivity" ); return 0
  fi
  if [[ $out == *(ECONNREFUSED|onnection refused|"Couldn't connect to server"|"Cannot connect to the Docker daemon"|"Can't connect to local MySQL server"|"Can't connect to local server")* ||
        ( $w == curl && $st == 7 ) ]]; then
    if [[ $out == *"Docker daemon"* ]]; then
      reply=( service_down "" "the Docker daemon is not running — start Docker Desktop (or your engine: colima start, orb start)" ); return 0
    fi
    # lsof only helps when the service is on THIS machine
    if [[ $out == *(localhost|127.0.0.1|"::1"|0.0.0.0|"local MySQL"|"local server")* || ( -z $out && $cmd == *(localhost|127.0.0.1)* ) ]]; then
      local l    # the port comes from the line that reports the refusal, never from a stack frame further down
      for l in ${(f)out}; do
        [[ $l == *(ECONNREFUSED|onnection refused|"Couldn't connect")* ]] || continue
        if   [[ $l =~ 'port ([0-9]{2,5})' ]]; then port=$match[1]
        elif [[ $l =~ '.*:([0-9]{2,5})([^0-9]|$)' ]]; then port=$match[1]; fi
        [[ -n $port ]] && break
      done
      [[ -z $port && $cmd =~ '(localhost|127.0.0.1):([0-9]{2,5})' ]] && port=$match[2]
      if [[ -n $port ]]; then
        reply=( service_down "lsof -nP -iTCP:$port -sTCP:LISTEN" "nothing accepted the connection on port $port — is the service running? this shows what listens there" )
      else reply=( service_down "" "the local service is not accepting connections" ); fi
    else reply=( service_down "" "the remote service refused the connection — it is down, or a firewall/port is wrong" ); fi
    return 0
  fi
  return 1
}
function _wtf_run {
  emulate -L zsh; setopt extendedglob
  local cmd=$_ZS_LAST_CMD out='' fix
  local st=$_ZS_LAST_STATUS
  if [[ ! -t 0 ]]; then                                  # some-cmd 2>&1 | wtf
    out=$(tail -c 8000); st='(see output)'
    cmd=${cmd%%[[:space:]]#\|[[:space:]]#wtf*}
  elif [[ $1 == -r ]]; then
    print -r -- "re-run to capture its output:  $cmd"
    read -q '?proceed? [y/N] ' || { print; return 1 }; print
    out=$(eval "$cmd" 2>&1); st=$?
    (( ${#out} > 8000 )) && out=${out[-8000,-1]}
  fi
  [[ -n $cmd || -n $out ]] || { print "nothing to diagnose yet"; return 1 }
  # exit 0 means success — not a failure to diagnose (common when user runs
  # `alias | grep ali` which succeeds, then `wtf` out of habit)
  if [[ $st == 0 ]]; then
    print -P -- "%F{$ZC[exe]}last command succeeded (exit 0): ${cmd//\%/%%}%f — nothing to fix"
    # still show output if piped, but don't call AI
    [[ -n $out ]] && print -r -- "$out"
    return 0
  fi
  # exit 127 = command not found — handle locally without AI (instant, no 5min wait)
  # Reuse the same logic as command_not_found_handler for suggestions.
  if [[ $st == 127 ]]; then
    local bad=${cmd%% *}
    # only the first word matters for typos like `lsl` → `ls`
    if [[ -n $bad ]]; then
      local -a near
      near=( ${(k)commands[(I)(#a1)$bad]} ${(k)aliases[(I)(#a1)$bad]} ${(k)functions[(I)(#a1)$bad]} )
      near=( ${${(u)near}:#_*} )
      (( $#near )) && near=( ${near[1,6]} )
      print -P -- "%F{$ZC[err]}command not found: $bad%f"
      if (( $#near )); then
        print -P -- "did you mean: ${(j:  :)near}"
        print -P -- "FIX: $near[1]"
        print -z -- "$near[1]"
      else
        print -P -- "no close match — try: ? <what you were trying to do>"
        print -P -- "FIX: none"
      fi
      return 0
    fi
  fi
  local -a reply
  if _zs_triage "$cmd" "$st" "$out"; then         # F1: rules first — instant, no model, no wait
    print -P -- "%F{$ZC[dim]}failed: ${cmd//\%/%%}   (exit $st)%f"
    print -P -- "%B${reply[1]//_/ }%b — ${reply[3]//\%/%%}"
    if [[ -n $reply[2] ]]; then print -r -- "FIX: $reply[2]"; print -z -- "$reply[2]"; fi
    return 0
  fi
  print -P -- "%F{$ZC[dim]}failed: ${cmd//\%/%%}   (exit $st)%f"
  _zai_ensure || return 1
  local ZAI_STATUS='diagnosing'
  _zai_stream "A zsh command failed on macOS. In at most 8 lines: the most likely cause first, then how to fix it. If the output is missing, reason from the command and exit status and say what you are assuming. End with exactly one line 'FIX: <corrected command>' — or 'FIX: none' when no single command fixes it. Plain text." \
"$(_zai_context)

Command: $cmd
Exit status: $st
Output:
${out:-(not captured — use: wtf -r   or   <cmd> 2>&1 | wtf)}" 500 | tee $tmp
  fix=${${(M)${(f)"$(<$tmp)"}:#FIX: *}[-1]#FIX: }
  zf_rm -f $tmp
  if [[ -n $fix && $fix != none* ]]; then
    fix=$(_zai_clean_cmd "$fix")
    if _zai_dangerous "$fix"; then print -P -- "%F{$ZC[err]}!! that fix is destructive — read it before pressing Enter%f"
    else local REPLY; _zai_danger2 "$fix" && print -P -- "%F{$ZC[err]}!! that fix ${REPLY#this }%f"; fi
    print -z -- "$fix"                      # the fix is waiting on your next prompt
  fi
  return 0
}

function aic {   # AI commit message from the staged diff; you always get the editor
  emulate -L zsh
  git rev-parse --git-dir >/dev/null 2>&1 || { print -u2 "not a git repo"; return 1 }
  git diff --cached --quiet && { print "nothing staged — git add first (gai = interactive)"; return 1 }
  local msg diff
  diff="$(git diff --cached --stat | tail -n 25)

$(git diff --cached -U2 | head -c 14000)"
  if _zai_ensure; then
    local ZAI_STATUS='writing the commit message'
    msg=$(_zai_request "Write a git commit message for this staged diff. Conventional Commits: 'type(scope): summary', imperative, ≤72 chars. If it helps, add a blank line and up to 3 short '- ' bullets about WHY. Output only the message." "$diff" 220 0.3 2>/dev/null)
  fi
  if [[ -z $msg ]]; then               # backend down → v3's heuristic
    local -a files=( ${(f)"$(git diff --cached --name-only)"} )
    if (( $#files == 1 )); then msg="Update ${files[1]:t}"; else msg="Update $#files files"; fi
  fi
  git commit -e -m "$msg"
}
alias gcmsg='aic'
function aireview { git diff ${1:---cached} | ai "Review this diff like a careful senior engineer: real bugs, edge cases, security, things that will break in production. Skip style nits. Cite file and line." }


# =====================================================================
#  ai-model — see what is available, test it, make it the default.
#  Writes ZAI_MODEL into ~/.zshrc.local, which this config never overwrites.
# =====================================================================
typeset -ga ZAI_CANDIDATES=(
  "mlx-community/Qwen3.5-9B-MLX-4bit|~5.5 GB|current gen, thinking off by default, strong all-round"
  "mlx-community/Qwen3.5-4B-MLX-4bit|~2.5 GB|same generation, half the RAM, noticeably quicker"
  "mlx-community/Qwen3-4B-Instruct-2507-4bit|~2.3 GB|previous default here, known-good with mlx-lm"
  "lmstudio-community/gpt-oss-20b-MLX-8bit|~12 GB|best quality-per-GB in 2026 local tests; slower to load"
  "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit|~4.3 GB|2024 model; still fine at pure code, dated elsewhere"
)
_zai_hf_size() {   # bytes already on disk for a repo, or empty
  local d=${HF_HOME:-$HOME/.cache/huggingface}/hub/models--${1//\//--}
  [[ -d $d ]] && du -sh $d 2>/dev/null | cut -f1
}
function ai-model {
  emulate -L zsh
  local entry repo size note cached sel
  local -a rows
  case ${1:-} in
    -h|--help) print "ai-model            pick from the list, test it, set as default
ai-model <hf-repo>  test and set that specific model
ai-model --current  show what is in use"; return 0 ;;
    --current) print -r -- "$ZAI_MODEL"; _zai_up && print "server: up" || print "server: down"; return 0 ;;
    '') for entry in $ZAI_CANDIDATES; do
          repo=${entry%%|*}; size=${${entry#*|}%%|*}; note=${entry##*|}
          cached=$(_zai_hf_size $repo)
          rows+=( "$(printf '%-46s %-8s %-10s %s' $repo $size "${cached:+on disk}" $note)"$'\t'"$repo" )
        done
        sel=$(print -rl -- $rows | fzf --delimiter=$'\t' --with-nth=1 --no-sort --height=40% \
              --prompt='model ❯ ' --header='ENTER downloads if needed, test-loads, then sets the default')
        [[ -n $sel ]] || return 0
        repo=${sel##*$'\t'} ;;
    *) repo=$1 ;;
  esac

  print -P "%F{$ZC[dim]}stopping current server…%f"; ai-server stop >/dev/null 2>&1
  local old=$ZAI_MODEL
  ZAI_MODEL=$repo
  [[ -n $(_zai_hf_size $repo) ]] || print -P "%F{$ZC[warn]}not on disk — downloading, this can take a while%f"
  if ! _zai_ensure; then
    print -P "%F{$ZC[err]}$repo did not come up.%f Most likely it is packaged for mlx-vlm rather than mlx-lm."
    print -P "reverting to %B$old%b"
    ZAI_MODEL=$old; ai-server stop >/dev/null 2>&1
    return 1
  fi
  print -P "%F{$ZC[dim]}test prompt…%f"
  local out
  out=$(ZAI_STATUS='testing' _zai_request "Output ONLY a shell command, nothing else." "list files larger than 100MB under the current directory" 80 0.1)
  if [[ -z $out ]]; then
    print -P "%F{$ZC[err]}loaded but produced nothing.%f reverting to %B$old%b"; ZAI_MODEL=$old; return 1
  fi
  print -P "  %F{$ZC[exe]}reply:%f ${out//\%/%%}"
  # persist in ~/.zshrc.local
  _zs_local_set ZAI_MODEL $repo || return 1
  print -P "%F{$ZC[exe]}default set%f → $repo   (recorded in ~/.zshrc.local)"
}

# =====================================================================
#  AI MODES — stop typing ? every time
#
#    ?   then Tab    command mode: every line you type is a request → a command
#                    lands on your prompt (label turns "run ›"), Enter runs it
#    ??  then Tab    agent mode: every line is a question for ?? (MiMo + tools)
#    ??? then Tab    deep agent mode: Qwen3.8-27B 3-bit reasoning model + tools
#    ???? then Tab   deep+ agent mode: 27B model with high reasoning effort
#    Esc             back to the normal shell          (Ctrl+D on an empty line too)
#    Tab (empty)     cycle between the modes (cmd → agent → deep → deep+ → cmd)
#  inside a mode:
#    !<cmd>          run a shell command as-is          e.g.  !git status
#    + <change>      command mode: refine the last command (like ?+)
#    /new            agent mode: forget the conversation
#    /think          toggle thinking (slower, deeper; deep modes always reason)
#    /deep [/deep+]  switch to deep / deep+ agent mode
#    /agent /cmd     switch to agent / cmd mode
#    /exit           same as Esc
#    Up/Down         recall history; a recalled line runs as a command
# =====================================================================
typeset -g _ZS_AIMODE='' _ZS_AIPEND_NEXT='' _ZS_AIMODE_HL=''
typeset -gi _ZS_AIPEND=0 _ZS_AITHINK=0

_zs_aimode_enter() {   # <cmd|agent|deep|deep_high>
  [[ -z $_ZS_AIMODE ]] && _ZS_AIMODE_HL=${ZSH_HIGHLIGHT_MAXLENGTH:-10000}
  typeset -g _ZS_AIMODE=$1
  typeset -g _ZSH_AUTOSUGGEST_DISABLED=1          # zsh-autosuggestions' own off switch
  setopt IGNORE_EOF                                # so Ctrl+D reaches our widget instead of closing the shell
  BUFFER=''; POSTDISPLAY=''; _ZS_AIPEND=0
  case $1 in
    deep_high)
      zle -M "deep+ agent mode (high reasoning effort) · 27B model · !cmd runs a command · /new · Esc exits" ;;
    deep)
      zle -M "deep agent mode · 27B reasoning model · tools: this Mac + web · !cmd runs a command · /new · Esc exits" ;;
    agent)
      zle -M "agent mode · ask anything (tools: this Mac + web) · !cmd runs a command · /new /think · Esc exits" ;;
    *)
      zle -M "command mode · describe what you want → a command appears · + <change> refines · !cmd runs as-is · Esc exits" ;;
  esac
  _zs_aimode_redraw
}
_zs_aimode_exit() {
  [[ -n $_ZS_AIMODE ]] || return 0
  _ZS_AIMODE='' _ZS_AIPEND=0
  unset _ZSH_AUTOSUGGEST_DISABLED
  unsetopt IGNORE_EOF
  ZSH_HIGHLIGHT_MAXLENGTH=${_ZS_AIMODE_HL:-10000}
  PREDISPLAY=''; POSTDISPLAY=''; region_highlight=()
  zle -M "back to the shell"
}
_zs_aimode_label() {   # → REPLY, reply=(color)
  local shotmark=''
  # a shot picked with /shot or ??shot (session-local), OR one from the hotkey/`shot` that
  # hasn't been consumed by a question yet (the file, agent.py enforces the actual age limit)
  { [[ -n $_ZS_AIMODE_IMAGE ]] || [[ -e ${ZSH_SHOTS:-$ZSH_CACHE/shots}/pending ]] } && shotmark='📷 '
  if (( _ZS_AIPEND )); then REPLY='run › '; reply=( $ZC[exe] )
  elif [[ $_ZS_AIMODE == deep_high ]]; then REPLY="???? deep+ ${shotmark}› "; reply=( $ZC[acc] )
  elif [[ $_ZS_AIMODE == deep ]]; then REPLY="??? deep ${shotmark}› "; reply=( $ZC[acc] )
  elif [[ $_ZS_AIMODE == agent ]]; then REPLY="?? agent${${_ZS_AITHINK:#0}:++think} ${shotmark}› "; reply=( $ZC[acc] )
  else REPLY='? cmd › '; reply=( $ZC[warn] ); fi
}
_zs_aimode_redraw() {   # zle-line-pre-redraw: label, placeholder, colors
  [[ -n $_ZS_AIMODE ]] || return 0
  [[ -z $BUFFER ]] && _ZS_AIPEND=0                 # emptied the line → back to asking
  local -a reply; local REPLY
  _zs_aimode_label
  PREDISPLAY=$REPLY
  region_highlight=( "P0 ${#PREDISPLAY} fg=${reply[1]},bold" )
  if (( _ZS_AIPEND )); then
    ZSH_HIGHLIGHT_MAXLENGTH=${_ZS_AIMODE_HL:-10000}  # a real command: normal highlighting
    POSTDISPLAY=''
  else
    ZSH_HIGHLIGHT_MAXLENGTH=0                        # plain English: no red "unknown command"
    if [[ -z $BUFFER ]]; then
      if [[ $_ZS_AIMODE == deep_high ]]; then POSTDISPLAY='ask anything (deep 27B model, high effort)…  (Esc exits · Tab cycles mode)'
      elif [[ $_ZS_AIMODE == deep ]]; then POSTDISPLAY='ask anything (deep 27B model)…  (Esc exits · Tab cycles mode)'
      elif [[ $_ZS_AIMODE == agent ]]; then POSTDISPLAY='ask anything…  (Esc exits · Tab cycles mode)'
      else POSTDISPLAY='describe what you want to do…  (Esc exits · Tab cycles mode)'; fi
      region_highlight+=( "P${#PREDISPLAY} $(( ${#PREDISPLAY} + ${#POSTDISPLAY} )) fg=${ZC[dim]}" )
    else
      POSTDISPLAY=''
      region_highlight+=( "P${#PREDISPLAY} $(( ${#PREDISPLAY} + ${#BUFFER} )) fg=${ZC[text]}" )
    fi
  fi
}
_zs_aimode_init() {    # zle-line-init: a proposal pushed by ?? arrives as a command to run
  [[ -n $_ZS_AIMODE ]] || return 0
  if [[ -n $_ZS_AIPEND_NEXT && $BUFFER == $_ZS_AIPEND_NEXT ]]; then _ZS_AIPEND=1; fi
  _ZS_AIPEND_NEXT=''
  _zs_aimode_redraw
}
_zs_aimode_do_shot() {   # <mode> <question-or-empty> — capture, then either send now or prefill
  emulate -L zsh
  local mode=$1 q=$2 p
  p=$(shot $mode 2>/dev/null)
  if [[ -z $p ]]; then BUFFER=''; zle -M "shot: cancelled"; return 1; fi
  print -P "%F{$ZC[dim]}captured: ${p/#$HOME/~}%f"
  if [[ -n ${q//[[:space:]]/} ]]; then                 # a question came with it → ask right away
    if [[ $_ZS_AIMODE == deep_high ]]; then
      print -s -- "???? $q"
      BUFFER=" zagent --deep --effort ${ZAH_DEEP_HIGH_EFFORT:-high} --image ${(qq)p} ${(qq)q}"
    elif [[ $_ZS_AIMODE == deep ]]; then
      print -s -- "??? $q"
      BUFFER=" zagent --deep --image ${(qq)p} ${(qq)q}"
    else
      print -s -- "?? $q"
      BUFFER=" zagent ${${_ZS_AITHINK:#0}:+--think }--image ${(qq)p} ${(qq)q}"
    fi
    POSTDISPLAY=''; PREDISPLAY=''
    zle .accept-line
  else                                                  # bare → stash it, let the user type/edit the question
    typeset -g _ZS_AIMODE_IMAGE=$p
    BUFFER='what is this?'; CURSOR=${#BUFFER}
    zle -M "captured — edit the question or press Enter"
  fi
  return 0
}
_zs_aimode_accept() {
  local q=$BUFFER
  if [[ -z ${q//[[:space:]]/} ]]; then POSTDISPLAY=''; zle .accept-line; return; fi
  if (( _ZS_AIPEND )); then                        # the proposed/recalled command: run it
    _ZS_AIPEND=0; POSTDISPLAY=''; _zai_accept_plain; return
  fi
  case $q in
    '!'*)             BUFFER=${q#!}; _zai_accept_plain; return ;;
    /exit|/quit)      BUFFER=''; _zs_aimode_exit; return ;;
    /cmd)             _zs_aimode_enter cmd; return ;;
    /agent)           _zs_aimode_enter agent; return ;;
    /deep|/deep\ *)   if [[ $q == '/deep high'* || $q == '/deep+'* ]]; then
                        _zs_aimode_enter deep_high
                      else
                        _zs_aimode_enter deep
                      fi; return ;;
    /deep+)           _zs_aimode_enter deep_high; return ;;
    /think)           if [[ $_ZS_AIMODE == deep* ]]; then
                        BUFFER=''
                        local eff="medium"
                        [[ $_ZS_AIMODE == deep_high ]] && eff="high"
                        zle -M "deep mode always reasons (effort: $eff · use /deep+ or /deep to switch)"; return
                      fi
                      (( _ZS_AITHINK = ! _ZS_AITHINK )); BUFFER=''
                      zle -M "thinking ${${_ZS_AITHINK:#0}:+on (slower, deeper)}${${_ZS_AITHINK:#1}:+off}"; return ;;
    /new)             BUFFER=''
                      zf_rm -f ${ZSH_CACHE:-$HOME/.cache/zsh}/agent-session.jsonl ${_ZAI_SESSION:-${ZSH_CACHE:-$HOME/.cache/zsh}/ai-session.jsonl}
                      zle -M "new conversation"; return ;;
    /escalate|/escalate\ *)
                      BUFFER=" ai-escalate ${(qq)${${q#/escalate}# }}"; POSTDISPLAY=''; PREDISPLAY=''
                      zle .accept-line; return ;;
    /remember\ *|/remember)
                      local fact=${q#/remember}; fact=${fact# }; BUFFER=''
                      local rfile=${_ZAH_VAULT:-${ZSH_CONF:-$HOME/.config/zsh}/agent/vault}/MEMORY.md rcap=2000
                      if [[ $fact == '--me '* ]]; then fact=${fact#--me }; rfile=${_ZAH_VAULT:-${ZSH_CONF:-$HOME/.config/zsh}/agent/vault}/USER.md; rcap=1200; fi
                      if [[ -z ${fact//[[:space:]]/} ]]; then
                        zle -M "usage: /remember <fact>   or  /remember --me <fact about you>"
                      else
                        zf_mkdir -p ${rfile:h}; [[ -f $rfile ]] || : >| $rfile
                        typeset -g _ZAH_REM_MSG=''
                        if _zdw_up 2>/dev/null; then zle -M "checking memory…"; zle -R; fi
                        _zah_smart_resolve $rfile "$fact"
                        _zs_locked $rfile _zah_remember $rfile $rcap "$fact" "$_ZAH_SMART_ACTION" "$_ZAH_SMART_OLD"
                        (( $? == 74 || $? == 75 )) && _ZAH_REM_MSG="could not save (${rfile:t} is busy) — try again"   # 1 = a normal refusal that already set its own message
                        [[ -n $_ZAH_SMART_NOTE && -z $_ZAH_SMART_ACTION ]] && _ZAH_REM_MSG+=" · $_ZAH_SMART_NOTE"
                        zle -M "$_ZAH_REM_MSG"
                      fi
                      return ;;
    /shot|/shot\ *|'??shot'|'??shot '*|'???shot'|'???shot '*|'????shot'|'????shot '*)
                      local srest=$q
                      srest=${srest#\?\?\?\?shot}
                      srest=${srest#\?\?\?shot}
                      srest=${srest#\?\?shot}
                      srest=${srest#/shot}
                      srest=${srest# }
                      local smode=region
                      case ${srest%% *} in full|window|region) smode=${srest%% *}; srest=${srest#${srest%% *}}; srest=${srest# } ;; esac
                      _zs_aimode_do_shot $smode "$srest"
                      return ;;
    /unshot)          BUFFER=''; unset _ZS_AIMODE_IMAGE; zf_rm -f ${ZSH_SHOTS:-$ZSH_CACHE/shots}/pending 2>/dev/null
                      zle -M "cleared the pending screenshot"; return ;;
    /equip|/equip\ *) BUFFER=" ai-equip ${${q#/equip}# }"; POSTDISPLAY=''; PREDISPLAY=''
                      zle .accept-line; return ;;
    /*)               zle -M "unknown: $q   (try /new /think /cmd /agent /deep /deep+ /remember /escalate /shot /unshot /equip /exit, ??shot/???shot, or !cmd)"; return ;;
  esac
  if [[ $_ZS_AIMODE == cmd ]]; then
    if [[ $q == '+ '* ]]; then _zai_fill "${q#+ }" 1; else _zai_fill "$q"; fi && _ZS_AIPEND=1
    _zs_aimode_redraw
  elif [[ $_ZS_AIMODE == deep_high ]]; then
    print -s -- "???? $q"
    local -a imgflag
    if [[ -n $_ZS_AIMODE_IMAGE ]]; then imgflag=(--image ${(qq)_ZS_AIMODE_IMAGE}); unset _ZS_AIMODE_IMAGE; fi
    BUFFER=" zagent --deep --effort ${ZAH_DEEP_HIGH_EFFORT:-high}${imgflag:+ $imgflag} ${(qq)q}"
    POSTDISPLAY=''; PREDISPLAY=''
    zle .accept-line
  elif [[ $_ZS_AIMODE == deep ]]; then
    print -s -- "??? $q"
    local -a imgflag
    if [[ -n $_ZS_AIMODE_IMAGE ]]; then imgflag=(--image ${(qq)_ZS_AIMODE_IMAGE}); unset _ZS_AIMODE_IMAGE; fi
    BUFFER=" zagent --deep${imgflag:+ $imgflag} ${(qq)q}"
    POSTDISPLAY=''; PREDISPLAY=''
    zle .accept-line
  else
    print -s -- "?? $q"                            # history shows the question
    local -a imgflag
    if [[ -n $_ZS_AIMODE_IMAGE ]]; then imgflag=(--image ${(qq)_ZS_AIMODE_IMAGE}); unset _ZS_AIMODE_IMAGE; fi
    BUFFER=" zagent ${${_ZS_AITHINK:#0}:+--think }${imgflag:+$imgflag }${(qq)q}"
    POSTDISPLAY=''; PREDISPLAY=''
    zle .accept-line
  fi
}
_zs_aimode_tab() {
  setopt local_options extended_glob
  local trimmed=${${BUFFER##[[:space:]]#}%%[[:space:]]#}
  if   [[ $trimmed == '????' ]]; then _zs_aimode_enter deep_high
  elif [[ $trimmed == '???' ]];  then _zs_aimode_enter deep
  elif [[ $trimmed == '??' ]];   then _zs_aimode_enter agent
  elif [[ $trimmed == '?' ]];    then _zs_aimode_enter cmd
  elif [[ -n $_ZS_AIMODE && -z $trimmed ]]; then
    case $_ZS_AIMODE in
      cmd)       _zs_aimode_enter agent ;;
      agent)     _zs_aimode_enter deep ;;
      deep)      _zs_aimode_enter deep_high ;;
      deep_high) _zs_aimode_enter cmd ;;
      *)         _zs_aimode_enter agent ;;
    esac
  else
    zle ${_ZS_TAB_ORIG:-expand-or-complete}
  fi
}
_zs_aimode_esc() { [[ -n $_ZS_AIMODE ]] && { BUFFER=''; _zs_aimode_exit } }
_zs_aimode_ctrl_d() {
  if [[ -n $_ZS_AIMODE && -z $BUFFER ]]; then _zs_aimode_exit   # never close the shell from a mode
  else zle delete-char-or-list; fi
}
zle -N _zs_aimode_tab; zle -N _zs_aimode_esc; zle -N _zs_aimode_ctrl_d
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init       _zs_aimode_init
add-zle-hook-widget line-pre-redraw _zs_aimode_redraw
