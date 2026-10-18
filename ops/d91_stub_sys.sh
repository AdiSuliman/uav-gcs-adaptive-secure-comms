#!/usr/bin/env bash
# Stand-in for the takeover's PowerShell queries in its tests; state in $V7T_SYS_DIR:
#   boot, cpu, headroom              one number each
#   matlab                           MATLAB processes, one "pid|exited 0/1|command line" per line
#   procs/<pid>                      command line of a process (else: a live stub MATLAB of the tests by
#                                    Windows PID; no other process of this machine is ever seen)
#   state/<pid>                      live, exited or other (default none)
D=${V7T_SYS_DIR:?}
case $1 in
  cmdline)
    if [ -f "$D/procs/$2" ]; then cat "$D/procs/$2"
    else
      for p in /proc/[0-9]*; do
        [ "$(cat "$p/winpid" 2>/dev/null)" = "$2" ] || continue
        c=$(tr '\0' ' ' < "$p/cmdline"); grep -q d91_stub_matlab <<< "$c" && echo "$c"
        break
      done
    fi;;
  state)    cat "$D/state/$2" 2>/dev/null || echo none;;
  matlab)   cat "$D/matlab" 2>/dev/null;;
  cpu)      cat "$D/cpu" 2>/dev/null || echo 5;;
  boot)     cat "$D/boot";;
  headroom) cat "$D/headroom" 2>/dev/null || echo 60;;
  *) exit 1;;
esac
