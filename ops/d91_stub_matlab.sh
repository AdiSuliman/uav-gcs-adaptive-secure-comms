#!/usr/bin/env bash
# Stand-in for matlab.exe in the takeover tests: matlab [options] -batch "<command>" in a worktree.
# run_stage(...) prints run_stage's stage markers; control files in $STUB_CTL:
#   fail_<stage> or fail_<worktree>_<stage>   that stage fails once (MATLAB exit 1)
#   slow_<stage> or slow_<worktree>_<stage>   seconds the stage takes (default STUB_DELAY)
#   fail_whos                                 the next whos(...) fails once
# Every call and stage goes to $STUB_CTL/calls.log ("<ns> <worktree> <event> <what>"; options
# other than -batch as "<ns> <worktree> opts <options>"); two calls in one worktree at once are
# logged as CONCURRENT. start_<Windows PID> holds the start time (read by d91_stub_sys.sh).
C=${STUB_CTL:?}
cmd=""; opts=()
while [ $# -gt 0 ]; do
  if [ "$1" = -batch ]; then cmd=${2:-}; shift 2; else opts+=("$1"); shift; fi
done
w=$(basename "$PWD")
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
