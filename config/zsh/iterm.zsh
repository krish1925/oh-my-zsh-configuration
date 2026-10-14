# =====================================================================
#  iterm.zsh — iTerm2 as a first-class terminal for this config
#
#  Everything that talks to iTerm2 is gated on TERM_PROGRAM == iTerm.app, so in Terminal.app or Ghostty this
#  file does nothing at all. The `zs-iterm` command works anywhere.
#
#    marks           every prompt/command/exit status is marked (OSC 133), so in iTerm2:
#                    ⌘⇧↑/⌃⌘↑ jump between commands · ⌘⇧A select last output · click a mark's gutter arrow
#                    → also gives `??` the exact output of the last command (see _zs_tab_output)
#    badge           the corner badge shows the AI mode you are in:  ?  ??  ???  ????
#    cwd / host      OSC 1337 CurrentDir/RemoteHost → new tabs open in the same dir, ⌘-click paths work over ssh
#    screen for ??   _zs_tab_output reads the session by tty (like the Terminal.app path)
#    imgcat / ishot  inline images; `ishot` shows your latest screenshot inline
#    profiles        ZS_ITERM_PROFILES=( '~/work/prod' Prod  'host:staging' Staging ) → auto-switch by dir/ssh host
#    tm              tmux -CC (native panes/tabs over a persistent tmux)
#    zs-iterm        status · install (dynamic profile with triggers) · keys (cheat sheet)
#
#  If iTerm2's own shell integration is installed (ITERM_SHELL_INTEGRATION_INSTALLED) marks are left to it.
# =====================================================================

typeset -gA ZS_ITERM_PROFILES 2>/dev/null   # 'dir-prefix' → profile name, or 'host:name' → profile name
typeset -g _ZS_IT_BADGE='' _ZS_IT_PROFILE=''
typeset -gi _ZS_IT_RAN=0
: ${ZS_ITERM_BADGE:=1}

_zs_it_on() { [[ $TERM_PROGRAM == iTerm.app ]] }
_zs_it_osc() { print -rn -- $'\e]'"$1"$'\a' }                       # one OSC sequence
_zs_it_b64() { print -rn -- "$1" | command base64 | command tr -d '\n' }

# ---- marks + cwd/host (only when iTerm2's own integration isn't doing it) ------------------------------------
_zs_it_precmd() {
  local st=$?
  [[ -n $ITERM_SHELL_INTEGRATION_INSTALLED ]] || {
    (( _ZS_IT_RAN )) && _zs_it_osc "133;D;$st"                        # previous command finished, with its status
    _zs_it_osc "133;A"                                                # a prompt starts here
    _zs_it_osc "1337;RemoteHost=${USER}@${HOST%%.*}"
    _zs_it_osc "1337;CurrentDir=$PWD"
  }
  _ZS_IT_RAN=0
  _zs_it_profile
  return $st
}
_zs_it_preexec() {
  _ZS_IT_RAN=1
  [[ -n $ITERM_SHELL_INTEGRATION_INSTALLED ]] || _zs_it_osc "133;C"    # command output starts here
  [[ $1 == ssh\ * ]] && _zs_it_profile "host:${${(z)1}[-1]##*@}"
}
_zs_it_line_init() { [[ -n $ITERM_SHELL_INTEGRATION_INSTALLED ]] || _zs_it_osc "133;B"; _zs_it_badge; return 0 }   # the prompt ends; your typing begins

# ---- badge: which AI mode is this line in? ---------------------------------------------------------------------
_zs_it_badge() {
  (( ZS_ITERM_BADGE )) || return 0
  local want=''
  case $_ZS_AIMODE in
    cmd) want='?' ;; agent) want='??' ;; deep) want='???' ;; deep_high) want='????' ;;
  esac
  [[ $want == $_ZS_IT_BADGE ]] && return 0                            # only talk to the terminal when it changes
  _ZS_IT_BADGE=$want
  _zs_it_osc "1337;SetBadgeFormat=$(_zs_it_b64 "$want")"
}

# ---- profiles by directory / ssh host ------------------------------------------------------------------------
_zs_it_profile() {   # [host:name] — no argument: decide from $PWD
  (( ${#ZS_ITERM_PROFILES} )) || return 0
  local want='' k
  if [[ -n $1 ]]; then want=$ZS_ITERM_PROFILES[$1]
  else for k in ${(k)ZS_ITERM_PROFILES}; do [[ $k == host:* ]] && continue; [[ $PWD == ${~${k/#\~/$HOME}}* ]] && want=$ZS_ITERM_PROFILES[$k]; done; fi
  [[ $want == $_ZS_IT_PROFILE ]] && return 0
  _ZS_IT_PROFILE=$want
  _zs_it_osc "1337;SetProfile=${want:-Default}"
}

# ---- inline images ---------------------------------------------------------------------------------------------
(( $+commands[imgcat] )) || function imgcat {   # imgcat <file…>   (or:  cat x.png | imgcat)
  emulate -L zsh
  local f
  if (( ! $# )); then _zs_it_osc "1337;File=inline=1:$(command base64 | command tr -d '\n')"; print; return; fi
  for f in "$@"; do
    [[ -r $f ]] || { print -u2 "imgcat: $f: not readable"; continue }
    _zs_it_osc "1337;File=name=$(_zs_it_b64 ${f:t});size=$(command stat -f %z $f);inline=1:$(command base64 < $f | command tr -d '\n')"; print
  done
}
function ishot {   # show the latest screenshot (shot/??shot) inline
  local f=${ZSH_SHOTS:-$ZSH_CACHE/shots}/latest.png
  [[ -r $f ]] && imgcat $f || print -u2 "no screenshot yet — shot, or ??shot <question>"
}

# ---- tmux integration mode -------------------------------------------------------------------------------------
function tm { tmux -CC new-session -A -s ${1:-main} }

# ---- hooks (iTerm2 only) --------------------------------------------------------------------------------------
if _zs_it_on; then
  autoload -Uz add-zsh-hook add-zle-hook-widget
  add-zsh-hook precmd  _zs_it_precmd
  add-zsh-hook preexec _zs_it_preexec
  add-zle-hook-widget line-init _zs_it_line_init
fi

# ---- zs-iterm --------------------------------------------------------------------------------------------------
function zs-iterm {
  emulate -L zsh
  local prof=${ZSH_CONF:-$HOME/.config/zsh}/iterm/zsh-config.dynamic-profile.json
  local dest="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  case ${1:-status} in
    status)
      print -P "%Biterm2%b"
      [[ -d /Applications/iTerm.app ]] && print "  installed:        yes" || print "  installed:        no   (brew install --cask iterm2)"
      print "  this terminal:    ${TERM_PROGRAM:-unknown}"
      _zs_it_on && print "  marks/badge:      active  (badge: ${_ZS_IT_BADGE:-none}, own integration: ${ITERM_SHELL_INTEGRATION_INSTALLED:+yes}${ITERM_SHELL_INTEGRATION_INSTALLED:-no})" \
                || print "  marks/badge:      inactive here (only runs inside iTerm2)"
      [[ -f "$dest/zsh-config.json" ]] && print "  dynamic profile:  installed" || print "  dynamic profile:  not installed → zs-iterm install"
      print "  keys:             zs-iterm keys" ;;
    install)
      [[ -f $prof ]] || { print -u2 "missing $prof"; return 1 }
      command mkdir -p "$dest" && command cp -f $prof "$dest/zsh-config.json" &&
        print "installed → iTerm2 ▸ Settings ▸ Profiles now lists “zsh-config” (triggers, semantic history, badge, unlimited scrollback). Pick it as default if you like." ;;
    keys)
      print -P "%Bnavigation%b   ⌘D split right · ⌘⇧D split below · ⌘⌥ arrows move between panes · ⌘⇧↩ zoom a pane · ⌘T tab
%Bmarks%b        ⌘⇧↑ / ⌘⇧↓ previous/next command · ⌘⇧A select that command's output (then ⌘C) · ⌥⌘/ show marks
%Bsearch%b       ⌘F (regex, all scrollback) · ⌘; autocomplete from scrollback · ⌘⇧H paste history · ⌥⌘B instant replay
%Bpanes%b        ⌘⇧I broadcast input to all panes · ⌥⌘I broadcast to one tab's panes
%Bwindows%b      ⌥Space hotkey window (set in Profiles ▸ Keys) · ⌘⇧S save arrangement · tm = tmux -CC
%Bclicks%b       ⌘-click a path / URL / file:line → opens it (editor set in the profile)
%Bhere%b         ishot · imgcat <file> · ZS_ITERM_PROFILES for per-directory colors" ;;
    *) print "zs-iterm [status|install|keys]" ;;
  esac
}
