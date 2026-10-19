#!/usr/bin/env bash
# Stand-in for matlab.exe in the takeover tests: matlab [options] -batch "<command>" in a worktree.
# run_stage(...) prints run_stage's stage markers; control files in $STUB_CTL:
#   fail_<stage> or fail_<worktree>_<stage>   that stage fails once (MATLAB exit 1)
#   slow_<stage> or slow_<worktree>_<stage>   seconds the stage takes (default STUB_DELAY)
#   hold_<stage> or hold_<worktree>_<stage>   that stage then waits until the file is removed
#   fail_whos                                 the next whos(...) fails once
#   win64 or win64_<worktree>                 this process is the bin\matlab.exe launcher: it starts a child
#                                             (--win64, as win64\MATLAB.exe) that does the work and waits for
#                                             it; the child writes ppid_<its Windows PID> (the launcher's) and
#                                             win64_pid_<worktree> (its MSYS and Windows PIDs)
# Every call and stage goes to $STUB_CTL/calls.log ("<ns> <worktree> <event> <what>"; options
# other than -batch as "<ns> <worktree> opts <options>"); two calls in one worktree at once are
# logged as CONCURRENT. start_<Windows PID> holds the start time (read by d91_stub_sys.sh).
C=${STUB_CTL:?}
w=$(basename "$PWD")
if [ "${1:-}" = --win64 ]; then   # the child under the launcher
  shift
  wp=$(cat /proc/$$/winpid 2>/dev/null)
  cat "/proc/$PPID/winpid" > "$C/ppid_$wp" 2>/dev/null
  echo "$$ $wp" > "$C/win64_pid_$w"
elif [ -f "$C/win64" ] || [ -f "$C/win64_$w" ]; then   # the launcher
  date +%s > "$C/start_$(cat /proc/$$/winpid 2>/dev/null || echo $$)"
  bash "$0" --win64 "$@" & c=$!
  wait "$c"; exit $?
fi
cmd=""; opts=()
while [ $# -gt 0 ]; do
  if [ "$1" = -batch ]; then cmd=${2:-}; shift 2; else opts+=("$1"); shift; fi
done
ns() { date +%s%N; }
log() { echo "$(ns) $w $*" >> "$C/calls.log"; }
date +%s > "$C/start_$(cat /proc/$$/winpid 2>/dev/null || echo $$)"
log call "$cmd"
[ "${#opts[@]}" = 0 ] || log opts "${opts[*]}"
mkdir "$C/busy_$w" 2>/dev/null || { log CONCURRENT "$cmd"; exit 3; }
trap 'rmdir "$C/busy_$w" 2>/dev/null' EXIT
pick() { for f in "$C/$1_${w}_$2" "$C/$1_$2"; do [ -f "$f" ] && { echo "$f"; return; }; done; }
case $cmd in
  run_stage\(*)
    for s in $(sed "s/^run_stage(//; s/)$//; s/'//g; s/,/ /g" <<< "$cmd"); do
      echo
      echo "##### STAGE $s (stub) $(date) #####"
      log start "$s"
      d=$(pick slow "$s"); sleep "$( [ -n "$d" ] && cat "$d" || echo "${STUB_DELAY:-0.05}")"
      h=$(pick hold "$s"); while [ -n "$h" ] && [ -f "$h" ]; do sleep 0.2; done
      f=$(pick fail "$s")
      if [ -n "$f" ]; then rm -f "$f"; echo "Error using $s (stub failure)"; log fail "$s"; exit 1; fi
      echo "##### STAGE $s done in 0.0 min #####"
      log done "$s"
    done;;
  whos*)
    if [ -f "$C/fail_whos" ]; then rm -f "$C/fail_whos"; echo "Error: cannot read file (stub)"; log fail whos; exit 1; fi
    echo "stub whos";;
  *export_gui_bundle*) echo "stub console bundle";;
  *) echo "stub: $cmd";;
esac
exit 0
