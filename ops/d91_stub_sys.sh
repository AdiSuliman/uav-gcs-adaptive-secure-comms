#!/usr/bin/env bash
# Stand-in for the takeover's PowerShell queries in its tests; state in $V7T_SYS_DIR:
#   boot, cpu, headroom              one number each
#   matlab                           MATLAB processes, one "pid|exited 0/1|command line" per line
#   scripts                          bash processes of the old scripts, one "pid|created|command line" per line
#   procs/<pid>                      command line of a process (else: a live stub MATLAB of the tests by
#                                    Windows PID; no other process of this machine is ever seen)
#   created/<pid>                    creation time of a procs/<pid> process
#   state/<pid>                      live, exited or other (default none)
#   exec_delay                       seconds after its start during which a stub MATLAB still shows the
#                                    command line of the takeover's subshell (exec not done yet)
D=${V7T_SYS_DIR:?}
stub_ml() {   # MSYS /proc entry of the live stub MATLAB with Windows PID $1
  local p
  for p in /proc/[0-9]*; do
    [ "$(cat "$p/winpid" 2>/dev/null)" = "$1" ] || continue
    tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q d91_stub_matlab && { echo "$p"; return 0; }
    return 1
  done
  return 1
}
started() { cat "${STUB_CTL:-/nonexistent}/start_$1" 2>/dev/null; }
case $1 in
  cmdline)
    if [ -f "$D/procs/$2" ]; then cat "$D/procs/$2"
    elif p=$(stub_ml "$2"); then
      t=$(started "$2")
      if [ -f "$D/exec_delay" ] && [ -n "$t" ] && [ $(( $(date +%s) - t )) -lt "$(cat "$D/exec_delay")" ]; then
        echo '"C:\Program Files\Git\usr\bin\bash.exe" "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh" 24172 49732'
      else
        tr '\0' ' ' < "$p/cmdline"
      fi
    fi;;
  created)
    if [ -f "$D/procs/$2" ]; then cat "$D/created/$2" 2>/dev/null
    elif stub_ml "$2" >/dev/null; then started "$2"; fi;;
  mlchild)  stub_ml "$2" >/dev/null && echo "$2";;
  state)    cat "$D/state/$2" 2>/dev/null || echo none;;
  matlab)   cat "$D/matlab" 2>/dev/null;;
  scripts)  cat "$D/scripts" 2>/dev/null;;
  cpu)      cat "$D/cpu" 2>/dev/null || echo 5;;
  boot)     cat "$D/boot";;
  headroom) cat "$D/headroom" 2>/dev/null || echo 60;;
  *) exit 1;;
esac
