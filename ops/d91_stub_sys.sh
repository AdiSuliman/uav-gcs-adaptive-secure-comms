#!/usr/bin/env bash
# Stand-in for the takeover's PowerShell queries in its tests; state in $V7T_SYS_DIR:
#   boot, cpu, headroom              one number each
#   matlab                           MATLAB processes, one "pid|exited 0/1|command line" per line
#   scripts                          bash processes of the old scripts, one "pid|created|command line" per line
#   scripts_once                     more such lines, listed by one scan only (a short-lived fork)
#   procs/<pid>                      command line of a process (else: a live stub MATLAB of the tests,
#                                    or a live process of this sandbox, by Windows PID; else 'none')
#   created/<pid>                    creation time of a procs/<pid> process
#   children/<pid>                   MATLAB children of a process (default 'none')
#   state/<pid>                      live, exited or other (default none)
#   exec_delay                       seconds after its start during which a stub MATLAB still shows the
#                                    command line of the takeover's subshell (exec not done yet)
#   fail_<query>, fail_<query>_<pid> that query fails (no output) while the file exists
#   hang_<query>, hang_<query>_<pid> that query hangs (the takeover's query timeout ends it); its PID goes to hung
# As the real queries: cmdline and created print 'none' for a missing process, mlchild 'none' for
# no MATLAB child, and scripts and matlab end with a line 'end'.
D=${V7T_SYS_DIR:?}
{ [ -f "$D/fail_$1" ] || { [ -n "${2:-}" ] && [ -f "$D/fail_$1_$2" ]; }; } && exit 0
{ [ -f "$D/hang_$1" ] || { [ -n "${2:-}" ] && [ -f "$D/hang_$1_$2" ]; }; } && { echo $$ >> "$D/hung"; exec sleep 1000; }
proc_of() {   # MSYS /proc entry of the process of this sandbox with Windows PID $1
  local p
  for p in /proc/[0-9]*; do
    [ "$(cat "$p/winpid" 2>/dev/null)" = "$1" ] || continue
    tr '\0' '\n' 2>/dev/null < "$p/environ" | grep -qx "V7T_SYS_DIR=$D" && { echo "$p"; return 0; }
    return 1
  done
  return 1
}
is_stub_ml() { tr '\0' ' ' < "$1/cmdline" 2>/dev/null | grep -q d91_stub_matlab; }
started() { cat "${STUB_CTL:-/nonexistent}/start_$1" 2>/dev/null; }
case $1 in
  cmdline)
    if [ -f "$D/procs/$2" ]; then cat "$D/procs/$2"
    elif p=$(proc_of "$2"); then
      t=$(started "$2")
      if is_stub_ml "$p" && [ -f "$D/exec_delay" ] && [ -n "$t" ] && [ $(( $(date +%s) - t )) -lt "$(cat "$D/exec_delay")" ]; then
        echo '"C:\Program Files\Git\usr\bin\bash.exe" "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh" 24172 49732'
      else
        tr '\0' ' ' < "$p/cmdline"
      fi
    else echo none; fi;;
  created)
    if [ -f "$D/procs/$2" ]; then cat "$D/created/$2" 2>/dev/null
    elif p=$(proc_of "$2"); then
      if is_stub_ml "$p" && [ -n "$(started "$2")" ]; then started "$2"
      else echo $(( $(awk '/^btime/{print $2}' /proc/stat) + $(awk '{print $22}' "$p/stat") / 1000 )); fi
    else echo none; fi;;
  mlchild)
    if [ -f "$D/children/$2" ]; then cat "$D/children/$2"
    elif p=$(proc_of "$2") && is_stub_ml "$p"; then echo "$2"
    else echo none; fi;;
  state)    cat "$D/state/$2" 2>/dev/null || echo none;;
  matlab)   sed -e '$a\' "$D/matlab" 2>/dev/null; echo end;;
  scripts)  sed -e '$a\' "$D/scripts" 2>/dev/null
            [ -f "$D/scripts_once" ] && { sed -e '$a\' "$D/scripts_once"; rm -f "$D/scripts_once"; }
            echo end;;
  cpu)      cat "$D/cpu" 2>/dev/null || echo 5;;
  boot)     cat "$D/boot";;
  headroom) cat "$D/headroom" 2>/dev/null || echo 60;;
  *) exit 1;;
esac
