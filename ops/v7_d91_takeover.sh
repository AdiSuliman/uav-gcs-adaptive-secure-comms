#!/usr/bin/env bash
# v7 takeover of the d86 launcher's remaining duties, after Adi has ended the launcher's main bash
# and the profile 3 fix script. Three tracks and a final phase; every dependency is read from the
# log markers in uav-gcs-logs/v7_d86/ (the launcher's '##### PART' and '##### STAGE <s> done'
# format), never from process ids.
#
#   bash v7_d91_takeover.sh <launcher PID> <p3 fix PID>          run (resumable: run it again
#                                                                after a reboot or a crash)
#   bash v7_d91_takeover.sh <launcher PID> <p3 fix PID> status   state of every track; changes nothing
#   V7T_ALLOW_PIDS='43428 43972'   profile 1's live chain subshells of the launcher (see Safety)
#
# Profile 1 (uav-gcs-v7): its chain keeps running to RPT in the launcher's own subshell; the track
#   only reads p1.log. A chain that ends with rc != 0, is cut by a reboot, or whose subshells
#   (V7T_ALLOW_PIDS) are gone without an end marker raises ALERT_p1_failed / ALERT_p1_cut and runs
#   nothing until Adi writes v7_d86/p1_resume.go (newer than p1.log); then the chain goes on from
#   its first unfinished stage under a new part (C1p or C1c not while P3's B-stage rerun runs).
# Profile 3 (uav-gcs-v7-p3): C1p to RPT once profile 1's current part is past SURV3; before that,
#   while waiting, the B-stage rerun listed in v7_d86/p3_brerun.go (A0 first; once per version of
#   the file; never after P3's C1p has started; only while profile 1 has no C1p/C1c running, with
#   RERUN_NEED_GB of free commit, on one computational thread).
# Profile 2 (uav-gcs-v7-p2): once profile 1's chain has ended with rc=0 past RPT, or on
#   v7_d86/p2_start.go, branch v7-p2 from v7-dev (profile.json n_rx 2, fresh data/ and results/,
#   pushed; the commit goes to code_commit.txt); A0-B2F, B3n, B3m, the stages of
#   v7_d86/p2_set4.stages if present, B3, B3a, B4, OOD, B4s; then C1p to RPT once profile 3's
#   current part is past SURV3.
# Final: when all three tracks have ended on purpose, on an idle machine (no live MATLAB running
#   pipeline stages, exited processes and the worktree copies' exact commands not counted; CPU
#   below CPU_IDLE % on two polls IDLE_POLL apart; at most IDLE_MAX_S), LAT, KPI, DASH, WEAK, RPT
#   and the console bundle of every finished profile. Skipped when a track died.
#
# Control files in v7_d86/ (written by Adi or the agent):
#   p1_resume.go, p3_resume.go, p2_resume.go   go on after a failed or cut chain (must be newer
#                                              than the profile's log; renamed to .used_<time>)
#   p2_start.go        start profile 2 before profile 1's chain has finished
#   p3_brerun.go       stage list of P3's B-stage rerun, e.g. "B2F B3 B3a B4 B4s"
#   p2_set4.stages     extra stages of profile 2 after B3m, e.g. "B3q"
#   p3_rerun.accept    after a failed rerun: go on with P3's B stages as they are (C1p still
#                      waits for profile 1's SURV3)
#   p3_c1p.hold, p2_c1p.hold     hold the profile before C1p
#   p3_c1p.force, p2_c1p.force   skip only the wait for the other profile's SURV3; counted only
#                                once that profile is given up (its .abandon file) and its chain
#                                has stopped; p2_c1p.force also needs profile 1 past SURV3,
#                                finished, or given up with its chain stopped
#   p1.abandon, p3.abandon, p2.abandon         end that track; the final phase skips the profile
# Alerts: v7_d86/ALERT_<topic>.txt (delete after handling) and this script's log.
#
# Safety: refuses unless cygpath -w "$TEMP" is TEMP_WIN (the parallel turn file lives there),
# unless the boot time can be read, while either given PID still runs its script, while any bash
# runs an old run script (SCRIPT_RE) other than the V7T_ALLOW_PIDS subshells (an allowed PID
# counts only for a process created within ALLOW_WIN_S after the start of profile 1's current
# launcher part, in this boot), or while another takeover holds v7_d86/takeover.lock (its main
# bash still runs this script, or its heartbeat is under 3 HB_S old). At its start it renames
# code_commit.txt's 'SRC <sha>' line to 'SRC_RETIRED_BY_D91 <sha>' (backup
# code_commit_before_d91_<time>.txt, SHA kept in retired_src.txt), so the launcher's resume
# refuses from then on, also after a reboot, and renames every old run script (OLD_SCRIPTS) to
# <name>.retired_by_d91 (a running bash keeps its open file; the launcher's chain subshells only
# finish the function they have already parsed). While running it alerts on a bash that runs an
# old script and starts no MATLAB until it is gone. Every value read from a log or a process
# query is unknown unless well formed, and unknown never acts: the track waits and reads again
# (ALERT_unknown_* after UNKNOWN_ALERT_S). PowerShell queries end after Q_TIMEOUT_S. Touches
# v7_d86/run.lock and takeover.lock at least every HB_S seconds; each track writes its beat file
# at every heartbeat and its end file when it ends on purpose; the main loop raises
# ALERT_takeover_track_<g>_stalled / _died; when its main bash is gone, each track stops at its
# next heartbeat (ALERT_takeover_main_gone; a running MATLAB keeps its PID file). One MATLAB per
# profile worktree at a time; never touches the parallel turn file.
#
# Stop: end every bash that runs this script and has no MATLAB child, all with taskkill /F and none
# with /T (v7_d91_takeover.md).
#
# Start detached (PowerShell), the same way as the launcher (same TEMP):
#   $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "V7T_ALLOW_PIDS=''43428 43972'' bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
# Other V7T_* environment variables point it at a test copy; a real run leaves them unset.

LPID=${1:-}
FPID=${2:-}
MODE=${3:-run}
V7=${V7T_P1:-"/c/Users/Adi Suliman/uav-gcs-v7"}
P3=${V7T_P3:-"/c/Users/Adi Suliman/uav-gcs-v7-p3"}
P2=${V7T_P2:-"/c/Users/Adi Suliman/uav-gcs-v7-p2"}
REPO=${V7T_REPO:-"/c/Users/Adi Suliman/uav-gcs-adaptive-secure-comms"}
L=${V7T_LOGS:-"/c/Users/Adi Suliman/uav-gcs-logs"}
MATLAB=${V7T_MATLAB:-"/c/Program Files/MATLAB/R2026a/bin/matlab.exe"}
SYS=${V7T_SYS:-}                           # stand-in for the PowerShell queries (tests)
TEMP_WIN=${V7T_TEMP_WIN:-'C:\Users\ADISUL~1\AppData\Local\Temp'}
POLL=${V7T_POLL:-300}                      # [s] between checks of the logs and control files
STEP=${V7T_STEP:-10}                       # [s] between checks of a running MATLAB
HB_S=${V7T_HB_S:-30}                       # [s] longest gap between heartbeats
STALE_S=${V7T_STALE_S:-1200}               # [s] a lock without a PID counts as stale after this
QUIET_S=${V7T_QUIET_S:-120}                # [s] a part written by an ended script: quiet this long
SILENT_S=${V7T_SILENT_S:-21600}            # [s] profile 1's log silent this long: alert
IDLE_MAX_S=${V7T_IDLE_MAX_S:-14400}        # [s] longest wait for an idle machine before LAT
IDLE_POLL=${V7T_IDLE_POLL:-600}            # [s] between the two idle polls
CPU_IDLE=${V7T_CPU_IDLE:-15}               # [%]
NEED_GB=${V7T_NEED_GB:-45}                 # [GB] free commit before a chain's MATLAB starts
RERUN_NEED_GB=${V7T_RERUN_NEED_GB:-65}     # [GB] before P3's B-stage rerun: OOD's 36 GB peak + P1's pool gather + margin
HEADROOM_ALERT_S=${V7T_HEADROOM_ALERT_S:-3600}
ML_PID_WAIT_S=${V7T_ML_PID_WAIT_S:-60}     # [s] wait for a started MATLAB's Windows PID; then retried this often
BOOT_RETRY_S=${V7T_BOOT_RETRY_S:-5}        # [s] between start-time queries
QRETRY_S=${V7T_QRETRY_S:-30}               # [s] before an unknown value is read again
Q_TIMEOUT_S=${V7T_Q_TIMEOUT_S:-120}        # [s] a process query not answered by then is ended (unknown)
UNKNOWN_ALERT_S=${V7T_UNKNOWN_ALERT_S:-3600}  # [s] the same value unknown this long: alert
STALL_S=${V7T_STALL_S:-$(( 2 * POLL + 600 ))} # [s] a track's beat this old: alert
ALLOW_PIDS=${V7T_ALLOW_PIDS:-}             # profile 1's live chain subshells of the launcher
ALLOW_WIN_S=${V7T_ALLOW_WIN_S:-900}        # [s] an allowed subshell is created this soon after its part's start
# exact -batch commands of the worktree copies (B3m builds, fourth test set), not counted as busy
IFS='|' read -ra COPY_CMDS <<< "${V7T_COPY_CMDS:-run_stage('A0','B3m')|run_stage('A0','B3q')|run_stage('A0','B3r')|set4_build}"
R="$L/v7_d86"
LOCK="$R/takeover.lock"
GATE="$R/takeover_gate.d"                  # one track at a time between a check and its part header
GO3="$R/p3_brerun.go"
OLD_SCRIPTS=(v7_d86_launch.sh v7_d87_p3fix.sh v7_d87_redo.sh v7_d87_resume.ps1 v7_d83_launch.sh v7_fix_resume.sh)
SCRIPT_RE='(v7_d8(6_launch|7_p3fix|7_redo|3_launch)|v7_fix_resume)'   # old bash run scripts (without .sh)
TRAILER="Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_EDITOR=true

AB=(A0 A4v A5 A6 B1 B2 B2F B3n B3 B3a B4 OOD B4s)
AB2_HEAD=(A0 A4v A5 A6 B1 B2 B2F B3n B3m)
AB2_TAIL=(B3 B3a B4 OOD B4s)
HV=(C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT)
FIN=(LAT KPI DASH WEAK RPT BUNDLE)
NTAIL=$(( ${#HV[@]} + ${#FIN[@]} ))
GGEN_RE='^params\.mat$|^models/[^/]*\.slx$|^results/'
declare -A RAISED=() UNK=() TPID=()

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
wt()  { case $1 in p1) echo "$V7";; p3) echo "$P3";; p2) echo "$P2";; esac; }
br()  { case $1 in p1) echo v7-dev;; p3) echo v7-p3;; p2) echo v7-p2;; esac; }
dep() { case $1 in p3) echo p1;; p2) echo p3;; esac; }   # whose SURV3 this profile's C1p waits for
isnum() { [[ ${1:-} =~ ^[0-9]+$ ]]; }
mtime() {   # modification time [s]: 0 for a missing file; nothing and status 1 when unreadable
  [ -e "$1" ] || { echo 0; return 0; }
  local t; t=$(stat -c %Y "$1" 2>/dev/null); isnum "$t" && echo "$t"
}
split_lines() { local - IFS=$'\n'; set -f; eval "$1=(\$2)"; }   # array $1: the lines of $2 (no fork, no globbing)
main_gone() {   # a track whose takeover main bash is gone: stop here (a running MATLAB keeps its PID file)
  alert takeover_main_gone "The takeover's main bash (MSYS PID $MAIN) is gone; each track stopped at its next heartbeat and starts nothing more. A MATLAB it started runs on, and its PID stays in $R/takeover_ml_<profile>.pid. Start the takeover again with the same launch command; it waits for that MATLAB."
  exit 0
}
hb() {   # heartbeat; never recreates the takeover lock after its removal; a track's beat file (no fork)
  if [ -n "${TRACK:-}" ]; then
    kill -0 "$MAIN" 2>/dev/null || main_gone
    { printf '%s\n' "$EPOCHSECONDS" > "$R/takeover_beat_$TRACK"; } 2>/dev/null
  fi
  touch "$R/run.lock" 2>/dev/null; touch -c "$LOCK" 2>/dev/null
}
nap() {   # sleep $1 seconds with heartbeats
  local end=$(( EPOCHSECONDS + $1 ))
  while hb; [ "$EPOCHSECONDS" -lt "$end" ]; do
    sleep $(( end - EPOCHSECONDS < HB_S ? end - EPOCHSECONDS : HB_S ))
  done
}
run_hb() { "$@" & local p=$!; while kill -0 "$p" 2>/dev/null; do hb; sleep 1; done; wait "$p"; }
alert() {   # once per topic and process: v7_d86/ALERT_<topic>.txt and the log
  local f="$R/ALERT_$1.txt"
  [ -n "${RAISED[$1]:-}" ] && return 0
  RAISED[$1]=1
  [ -f "$f" ] && return 0
  printf '%s\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$2" > "$f"
  say "ALERT $1: $2"
}
unknown_wait() {   # value $1 could not be read ($2): logged once, an alert after UNKNOWN_ALERT_S; a short wait
  local k=$1
  [ -n "${UNK[$k]:-}" ] || { UNK[$k]=$EPOCHSECONDS; say "$2 (read again every $QRETRY_S s)"; }
  [ $(( EPOCHSECONDS - UNK[$k] )) -lt "$UNKNOWN_ALERT_S" ] || \
    alert "unknown_${k}_${UNK[$k]}" "$2, for $(( (EPOCHSECONDS - UNK[$k]) / 60 )) min; nothing starts on it meanwhile. Check that file, free memory and the number of processes; the takeover goes on by itself once it reads."
  nap "$QRETRY_S"
}
known() { unset "UNK[$1]"; }
in_list() { local x=$1; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }

# Machine queries: PowerShell, or the stand-in V7T_SYS, each ended after Q_TIMEOUT_S. Empty output
# means the query failed (unknown): cmdline and created print 'none' for a missing process,
# mlchild 'none' for no MATLAB child, and scripts and matlab end their list with a line 'end'.
q_run() {   # "$@" with its output; nothing and status 1 when it has not ended within Q_TIMEOUT_S (its process tree ended)
  local out
  out=$(
    "$@" 2>/dev/null & p=$!; t0=$EPOCHSECONDS; i=0
    while kill -0 "$p" 2>/dev/null; do
      if [ $(( EPOCHSECONDS - t0 )) -ge "$Q_TIMEOUT_S" ]; then
        read -r wp < "/proc/$p/winpid" 2>/dev/null && taskkill //PID "$wp" //T //F >/dev/null 2>&1
        kill -9 "$p" 2>/dev/null; exit 124
      fi
      if [ "$i" -lt 20 ]; then sleep 0.1; else sleep 1; fi; i=$((i + 1))
    done
    wait "$p"; exit 0
  ) || return 1
  [ -z "$out" ] || printf '%s\n' "$out"
}
sysq() {
  local q
  if [ -n "$SYS" ]; then q_run "$SYS" "$@"; return; fi
  case $1 in
    cmdline|state|created|mlchild) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo none; return 0; };;
  esac
  case $1 in
    cmdline)  q="\$p = Get-CimInstance Win32_Process -Filter \"ProcessId=$2\"; if (-not \$p) {'none'} elseif (\$p.CommandLine) {\$p.CommandLine} else {'(no command line)'}";;
    created)  q="\$p = Get-CimInstance Win32_Process -Filter \"ProcessId=$2\"; if (\$p) { ([DateTimeOffset]\$p.CreationDate).ToUnixTimeSeconds() } else {'none'}";;
    mlchild)  q="\$c = @(Get-CimInstance Win32_Process -Filter \"ParentProcessId=$2\" | Where-Object { \$_.Name -like 'matlab*' }); if (\$c.Count) { \$c | ForEach-Object { \$_.ProcessId } } else {'none'}";;
    scripts)  q="Get-CimInstance Win32_Process -Filter \"Name='bash.exe'\" | Where-Object { \$_.CommandLine -like ('*v7_d8' + '*') -or \$_.CommandLine -like ('*v7_fix' + '_resume*') } | ForEach-Object { '{0}|{1}|{2}' -f \$_.ProcessId, ([DateTimeOffset]\$_.CreationDate).ToUnixTimeSeconds(), \$_.CommandLine }; 'end'";;
    state)    q="\$p = Get-Process -Id $2 -ErrorAction SilentlyContinue; if (-not \$p) {'none'} elseif (\$p.HasExited) {'exited'} elseif (\$p.Path -like '*win64*') {'live'} else {'other'}";;
    matlab)   q="Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Where-Object { \$_.CommandLine -like '*win64*' } | ForEach-Object { \$p = Get-Process -Id \$_.ProcessId -ErrorAction SilentlyContinue; \$x = if (-not \$p -or \$p.HasExited) {1} else {0}; '{0}|{1}|{2}' -f \$_.ProcessId, \$x, \$_.CommandLine }; 'end'";;
    cpu)      q="(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average";;
    boot)     q="([DateTimeOffset](Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToUnixTimeSeconds()";;
    headroom) q="[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory / 1MB)";;
    *) return 1;;
  esac
  q_run powershell.exe -NoProfile -Command "\$ErrorActionPreference = 'Stop'; $q" | tr -d '\r'
}
q_known() {   # sysq, up to 5 tries until it answers
  local i out
  for i in 1 2 3 4 5; do
    out=$(sysq "$@"); [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    sleep "$BOOT_RETRY_S"
  done
  return 1
}
listq() {   # list query $1 (scripts, matlab) without its 'end' line; status 2 when the query failed
  local out
  out=$(sysq "$1")
  [[ $out == end || $out == *$'\n'end ]] || return 2
  out=${out%end}; printf '%s' "${out%$'\n'}"
}
stage_live() {   # live MATLAB sessions running pipeline stages (smoke runs and worktree copies not counted); '?' when unknown
  local out x pid ex cmd b ids=() M
  out=$(listq matlab) || { echo '?'; return; }
  split_lines M "$out"
  for x in "${M[@]}"; do
    pid=${x%%|*}; x=${x#*|}; ex=${x%%|*}; cmd=${x#*|}
    [ "$ex" = 0 ] || continue
    b=$cmd
    [[ $cmd =~ \"-batch\"\ \"([^\"]*)\" ]] && b=${BASH_REMATCH[1]}
    [[ $b == *'run_stage('* ]] || continue
    [[ $b == *'run_stage('?smoke* ]] && continue
    in_list "$b" "${COPY_CMDS[@]}" && continue
    ids+=("$pid")
  done
  echo "${ids[*]}"
}
n_live_matlab() { listq matlab | awk -F'|' '$2 == 0' | wc -l | tr -d ' '; }
cpu_int() { local c; c=$(sysq cpu); c=${c%%.*}; c=${c//[!0-9]/}; echo "${c:-100}"; }

# Log markers. A part runs from its '##### PART <stamp> <mode> SRC <sha> FROM <i> <stage> A0 <0|1>
# [AB <list>] [RERUN <list> GO <id>] #####' header to the next header. Every reader below gives
# nothing and status 1 when the log exists but does not read as such (unknown).
grep_end() { grep "$@"; [ $? -le 1 ] && echo '#END'; }   # grep, then '#END' once it has read its input
tgrep_end() {   # the same over text $1 (grep options and pattern after it)
  local t=$1; shift
  printf '%s\n' "$t" | grep "$@"
  [ "${PIPESTATUS[1]}" -le 1 ] && echo '#END'
}
ge_ok() {   # grep_end output $2 complete: the lines before '#END' into variable $1
  [[ $2 == '#END' || $2 == *$'\n#END' ]] || return 1
  local _b=${2%'#END'}
  printf -v "$1" '%s' "${_b%$'\n'}"
}
hdr_ok() {   # $1 a well-formed part header; its fields into H_STAMP, H_MODE, H_FROM, H_A0
  [[ $1 =~ ^'##### PART '([0-9]{8}_[0-9]{6})' '([A-Za-z-]+)' SRC '[^\ ]+' FROM '([0-9]+)' '[^\ ]+' A0 '([01])(' '.*)?' #####'$ ]] || return 1
  H_STAMP=${BASH_REMATCH[1]}; H_MODE=${BASH_REMATCH[2]}; H_FROM=${BASH_REMATCH[3]}; H_A0=${BASH_REMATCH[4]}
}
cur_part() {   # the profile's log from its last '##### PART' line
  local f="$R/$1.log" n
  n=$(grep -n '^##### PART ' "$f" 2>/dev/null | tail -1 | cut -d: -f1)
  isnum "$n" && tail -n +"$n" "$f"
}
part_head() { local h; h=$(cur_part "$1" | head -1); hdr_ok "$h" && echo "$h"; }
part_mode() { local h; h=$(part_head "$1") && hdr_ok "$h" && echo "$H_MODE"; }
section_at() {   # file $1 from header line $2 to the next header
  local s
  s=$(tail -n +"$2" "$1" | awk 'NR > 1 && /^##### PART /{exit} {print}')
  [[ $s == '##### PART '* ]] && printf '%s\n' "$s"
}
ab_of() {   # B stages of the profile; profile 2's from its latest part header
  local x
  [ "$1" = p2 ] || { echo "${AB[*]}"; return 0; }
  [ -e "$R/p2.log" ] || { echo "${P2AB_NEW:-${AB2_HEAD[*]} ${AB2_TAIL[*]}}"; return 0; }
  x=$(grep_end '^##### PART .* AB [^ ]* ' "$R/p2.log") && ge_ok x "$x" || return 1
  x=${x##*$'\n'}
  [[ $x =~ \ AB\ ([^\ ]+)\  ]] || return 1
  x=${BASH_REMATCH[1]//,/ }
  [[ "$x " == "${AB2_HEAD[*]} "* && " $x" == *" ${AB2_TAIL[*]}" ]] && echo "$x"
}
list_of() { local ab; ab=$(ab_of "$1") && echo "$ab ${HV[*]} ${FIN[*]}"; }   # all stages of the profile
load_list() {   # F: all stages of profile $1, complete (A0 first, the C and final stages last)
  local s; s=$(list_of "$1") || return 1
  F=($s)
  [ "${F[0]:-}" = A0 ] && [ "${#F[@]}" -gt "$NTAIL" ] && [ "${F[*]: -NTAIL}" = "${HV[*]} ${FIN[*]}" ] || return 1
  case $1 in p1|p3) [ "${#F[@]}" = $(( ${#AB[@]} + NTAIL )) ];; esac
}
idx_of() { local F i; load_list "$1" || return 1; for i in "${!F[@]}"; do [ "${F[$i]}" = "$2" ] && { echo "$i"; return 0; }; done; return 1; }
# index of the profile's first unfinished stage (0 without a log): the part's start, advanced over
# the '##### STAGE <s> done' markers that follow the list in order; a rerun part leaves it at C1p
next_idx() {
  local g=$1 part h x r i=0 F seq
  [ -e "$R/$g.log" ] || { echo 0; return 0; }
  load_list "$g" || return 1
  part=$(cur_part "$g") || return 1
  h=${part%%$'\n'*}
  hdr_ok "$h" || return 1
  [[ $h =~ \ RERUN\ [^\ ] ]] && { idx_of "$g" C1p; return; }
  r=$H_FROM
  x=$(tgrep_end "$part" -o '##### STAGE [A-Za-z0-9]* done') && ge_ok x "$x" || return 1
  seq=($x)   # four words per marker, the stage third
  if [ "$H_A0" = 1 ]; then
    [ "${seq[2]:-}" = A0 ] || { echo "$r"; return 0; }
    i=1
  fi
  while [ "$r" -lt "${#F[@]}" ] && [ $(( 4 * i + 2 )) -lt "${#seq[@]}" ] && [ "${seq[4 * i + 2]}" = "${F[$r]}" ]; do
    r=$((r + 1)); i=$((i + 1))
  done
  echo "$r"
}
end_rc() {   # rc of the chain's end marker in the current part, 'none' without one
  local part x
  [ -e "$R/$1.log" ] || { echo none; return 0; }
  part=$(cur_part "$1") && hdr_ok "${part%%$'\n'*}" || return 1
  x=$(tgrep_end "$part" -o '^##### chain ended rc=[0-9]*') && ge_ok x "$x" || return 1
  [ -n "$x" ] || { echo none; return 0; }
  x=${x##*=}; isnum "$x" && echo "$x"
}
open_stage() {   # the part's last stage when it has no done marker (nothing when none)
  local part x
  [ -e "$R/$1.log" ] || return 0
  part=$(cur_part "$1") && hdr_ok "${part%%$'\n'*}" || return 1
  x=$(tgrep_end "$part" '^##### STAGE [A-Za-z0-9]* ') && ge_ok x "$x" || return 1
  [ -n "$x" ] || return 0
  x=${x##*$'\n'}
  [[ $x =~ ^'##### STAGE '([A-Za-z0-9]*)' '([^\ ]*) ]] || return 1
  [ "${BASH_REMATCH[2]}" = done ] || echo "${BASH_REMATCH[1]}"
}
past_surv3() { local r s; r=$(next_idx "$1") && s=$(idx_of "$1" SURV3) && [ "$r" -gt "$s" ]; }   # false when unknown
complete() {   # 0 past RPT with the chain's MATLAB over (its end marker, or a final-phase part); 1 not; 2 unknown
  local nlat r rc h
  nlat=$(idx_of "$1" LAT) && r=$(next_idx "$1") && rc=$(end_rc "$1") || return 2
  [ "$r" -ge "$nlat" ] || return 1
  [ "$rc" = 0 ] && return 0
  h=$(part_head "$1") && hdr_ok "$h" || return 2
  [ "$H_FROM" -ge "$nlat" ]
}
part_idle() {   # 0 nothing writes the profile's current part any more; 1 something may; 2 unknown
  local g=$1 f="$R/$1.log" part x m op
  [ -e "$f" ] || return 0
  part=$(cur_part "$g") || return 2
  hdr_ok "${part%%$'\n'*}" || return 2
  x=$(tgrep_end "$part" -c '^##### \(chain\|rerun\) ended') && ge_ok x "$x" && isnum "$x" || return 2
  [ "$x" -gt 0 ] && return 0
  [[ $H_MODE == takeover* ]] && return 0
  m=$(mtime "$f") || return 2
  [ "$m" -lt "$BOOT" ] && return 0
  [ "$g" = p1 ] && return 1
  op=$(open_stage "$g") || return 2
  [ -z "$op" ] && [ $(( EPOCHSECONDS - m )) -ge "$QUIET_S" ] && return 0
  return 1
}
p1_heavy() {   # profile 1's chain between C1p and the end of C1c (pool build, gather, clean pools); true when unknown
  local r a b rc m
  [ -f "$R/p1.abandon" ] && return 1
  rc=$(end_rc p1) || return 0
  [ "$rc" = none ] || return 1
  m=$(mtime "$R/p1.log") || return 0
  [ "$m" -ge "$BOOT" ] || return 1
  r=$(next_idx p1) && a=$(idx_of p1 C1p) && b=$(idx_of p1 C1c) || return 0
  [ "$r" -ge "$a" ] && [ "$r" -le "$b" ]
}

# The old run scripts
stamp_epoch() { local s=$1; date -d "${s:0:8} ${s:9:2}:${s:11:2}:${s:13:2}" +%s 2>/dev/null; }
runs_script() {   # command line $1 is a bash that runs a script named $2 (ERE, without .sh), not one that only mentions it
  local pg lc sc
  pg='^("[^"]*[/\\]bash(\.exe)?"|([^" ]*[/\\])?bash(\.exe)?)[[:space:]]+'
  lc="(-l?c[[:space:]]+\"([A-Za-z_][A-Za-z0-9_]*=('[^']*'|[^ '\"]*)[[:space:]]+)*bash[[:space:]]+)?"
  sc="(['\"]([^'\"]*[/\\\\])?|([^'\" ]*[/\\\\])?)$2\\.sh(['\"[:space:]]|\$)"
  [[ $1 =~ $pg$lc$sc ]]
}
foreign_scripts() {   # bash processes running an old run script, allowed subshells left out; status 2 when unknown
  local out x pid ct cmd se="" h S
  out=$(listq scripts) || return 2
  if [ -e "$R/p1.log" ]; then
    h=$(part_head p1) && hdr_ok "$h" || return 2
    if [[ $H_MODE != takeover* ]]; then se=$(stamp_epoch "$H_STAMP"); isnum "$se" || return 2; fi
  fi
  split_lines S "$out"
  for x in "${S[@]}"; do
    pid=${x%%|*}; x=${x#*|}; ct=${x%%|*}; cmd=${x#*|}
    [ -n "$pid" ] && runs_script "$cmd" "$SCRIPT_RE" || continue
    if in_list "$pid" $ALLOW_PIDS && runs_script "$cmd" v7_d86_launch && [ -n "$se" ] && \
       isnum "$ct" && [ "$se" -ge "$BOOT" ] && [ "$ct" -ge "$se" ] && [ "$ct" -le $(( se + ALLOW_WIN_S )) ]; then
      continue
    fi
    echo "$pid|$ct|$cmd"
  done
}
foreign_seen_twice() {   # foreign_scripts, only processes found on two scans BOOT_RETRY_S apart (a fork lives for milliseconds); status 2 when unknown
  local a b x y A B
  local -A k=()
  a=$(foreign_scripts) || return 2
  [ -n "$a" ] || return 0
  sleep "$BOOT_RETRY_S"
  b=$(foreign_scripts) || return 2
  split_lines A "$a"; split_lines B "$b"
  for x in "${A[@]}"; do y=${x#*|}; k[${x%%|*}_${y%%|*}]=1; done   # key: PID and creation time
  for x in "${B[@]}"; do y=${x#*|}; [ -n "${k[${x%%|*}_${y%%|*}]:-}" ] && echo "$x"; done
  return 0
}
scripts_alert() {
  local x pid ct S
  split_lines S "$1"
  for x in "${S[@]}"; do
    pid=${x%%|*}; ct=${x#*|}; ct=${ct%%|*}
    alert "old_script_${pid}_$ct" "Bash PID $pid runs an old run script outside V7T_ALLOW_PIDS: ${x#*|*|}. No MATLAB starts until it is gone; end it (taskkill /PID $pid /F, no /T) once sure it is not one of profile 1's chain subshells."
  done
}
scripts_wait() {   # no MATLAB starts while such a script runs, or while the scan cannot be read
  local f
  while :; do
    if f=$(foreign_seen_twice); then
      known scan
      [ -z "$f" ] && return 0
      scripts_alert "$f"; nap "$POLL"
    else
      unknown_wait scan "the process scan for old scripts failed; no MATLAB starts until it reads"
    fi
  done
}
allowed_alive() {   # alive, none or unknown: is one of V7T_ALLOW_PIDS still a bash running the launcher
  local p c st=none
  for p in $ALLOW_PIDS; do
    c=$(sysq cmdline "$p")
    if [ -z "$c" ]; then st=unknown
    elif [ "$c" != none ] && runs_script "$c" v7_d86_launch; then echo alive; return
    fi
  done
  echo "$st"
}
p1_chain_gone() {   # profile 1's launcher chain: its subshells gone and none has a MATLAB child (explicit answers only)
  local p
  [ -n "$ALLOW_PIDS" ] && [ "$(allowed_alive)" = none ] || return 1
  for p in $ALLOW_PIDS; do [ "$(sysq mlchild "$p")" = none ] || return 1; done
}
retire_file() {   # file $1 renamed to <name>.retired_by_d91
  local f=$1 t
  [ -f "$f" ] || return 0
  t="$f.retired_by_d91"; [ -e "$t" ] && t="$t.$(date +%Y%m%d_%H%M%S)"
  if mv "$f" "$t"; then say "$(basename "$f") renamed to $(basename "$t") (old run script); it cannot be run any more"
  else alert "retire_$(basename "$f")" "$f could not be renamed to $(basename "$t"); retried every $POLL s. Never run it."; return 1; fi
}
retire_old() { local s; for s in "${OLD_SCRIPTS[@]}"; do retire_file "$L/$s"; done; }   # every old run script; failures retried
retire_launcher() {   # code_commit.txt's SRC line renamed: v7_d86_launch.sh's resume reads '^SRC ' and refuses
  local f="$R/code_commit.txt" sha s
  sha=$(sed -n 's/^SRC //p' "$f")
  if [ -n "$sha" ]; then
    s=$(date +%Y%m%d_%H%M%S)
    cp -p "$f" "$R/code_commit_before_d91_$s.txt" || return 1
    echo "retired SRC $sha at $(date '+%Y-%m-%d %H:%M:%S %z') by v7_d91_takeover.sh (backup code_commit_before_d91_$s.txt): the run's code until the takeover; v7_d86_launch.sh resume refuses from here on" >> "$R/retired_src.txt" || return 1
    sed -i 's/^SRC \(.*\)$/SRC_RETIRED_BY_D91 \1/' "$f" || return 1
    say "code_commit.txt: SRC $sha retired (the launcher's resume refuses)"
  fi
  [ -z "$(sed -n 's/^SRC //p' "$f")" ] && grep -q '^SRC_RETIRED_BY_D91 ' "$f"
}

stage_cmd() { local q; q=$(printf ",'%s'" "$@"); echo "run_stage(${q#,})"; }
part_header() {   # profile $1, list index $2, A0 first $3, mode $4, extra header fields $5; status 1 when unreadable
  local g=$1 r=$2 F extra=${5:-} sha ab
  hb
  load_list "$g" || return 1
  if [ "$g" = p2 ]; then ab=$(ab_of p2) || return 1; extra=" AB ${ab// /,}$extra"; fi
  sha=$(git -C "$(wt "$g")" rev-parse HEAD 2>/dev/null)
  echo "##### PART $(date +%Y%m%d_%H%M%S) $4 SRC ${sha:-unknown} FROM $r ${F[$r]:-end} A0 $3$extra #####" >> "$R/$g.log"
}
same_r() { local r; r=$(next_idx "$1") && [ "$r" = "$2" ]; }   # first unfinished stage still $2, read again before a part header
commit_note() { echo "$1 $(br "$1") $(git -C "$(wt "$1")" rev-parse HEAD) $(date '+%Y-%m-%d %H:%M:%S %z') takeover: $2" >> "$R/code_commit.txt"; }

# MATLAB -batch "$2" in profile $1's worktree, output appended to its log; heartbeat while it runs
ml_state() {   # alive, gone or unknown: the process recorded in profile $1's MATLAB PID file
  local pf="$R/takeover_ml_$1.pid" op="" l2="" w2="" c ch ct m
  [ -f "$pf" ] || { echo gone; return; }
  { read -r op; read -r l2; } < "$pf" 2>/dev/null
  op=${op//[!0-9]/}
  [ -n "$op" ] || { echo unknown; return; }
  m=$(mtime "$pf") || { echo unknown; return; }
  [ "$m" -ge "$BOOT" ] || { echo gone; return; }
  if [[ $l2 =~ ^msys\ ([0-9]+)$ ]]; then   # the subshell still known to MSYS: its Windows process now (after the exec)
    read -r w2 < "/proc/${BASH_REMATCH[1]}/winpid" 2>/dev/null; isnum "$w2" && op=$w2
  fi
  c=$(sysq cmdline "$op")
  if [ -z "$c" ]; then echo unknown
  elif { [ "$c" = none ] && [[ $l2 == msys* ]]; } || [[ $c == *v7_d91_takeover* ]]; then
    # a takeover subshell around its exec, or its stub gone: alive while it has a MATLAB child
    # (Windows keeps ParentProcessId after the parent exits) or predates this takeover (it may still exec)
    ch=$(sysq mlchild "$op")
    if [ -n "$ch" ] && [ "$ch" != none ]; then echo alive
    elif [ -z "$ch" ]; then echo unknown
    elif [ "$c" = none ]; then echo gone
    else
      ct=$(sysq created "$op")
      if isnum "$ct" && [ "$ct" -lt "$START_T" ]; then echo alive
      elif [ -z "$ct" ]; then echo unknown
      else echo gone; fi
    fi
  elif [ "$c" = none ]; then echo gone
  elif [[ ${c,,} == *matlab* ]]; then echo alive
  else echo gone; fi
}
ml_guard() {   # a MATLAB this takeover started earlier in the worktree, still alive or unknown: wait
  local g=$1 pf="$R/takeover_ml_$1.pid" st
  while [ -f "$pf" ]; do
    st=$(ml_state "$g")
    case $st in
      gone) break;;
      alive) known "ml_$g"
             alert "ml_alive_$g" "A MATLAB started earlier in $(wt "$g") (Windows PID $(head -1 "$pf")) is still alive; no new MATLAB starts there until it exits."
             nap "$POLL";;
      *) unknown_wait "ml_$g" "$g: the process query for PID $(head -1 "$pf") failed; no MATLAB starts there until it reads";;
    esac
  done
  known "ml_$g"
  rm -f "$pf"
}
ml_pid_try() {   # PID file $2 names MATLAB once subshell $1 shows it (exec done); status 1 before
  local wp c
  read -r wp < "/proc/$1/winpid" 2>/dev/null && isnum "$wp" || return 1
  c=$(sysq cmdline "$wp")
  [ -n "$c" ] && [ "$c" != none ] && [[ ${c,,} == *matlab* ]] || return 1
  printf '%s\n' "$wp" > "$2"
}
run_ml() {   # profile $1, command $2, further MATLAB options after them
  local g=$1 cmd=$2 w mp wp rc t0 pend=1 next=0 pf="$R/takeover_ml_$1.pid"
  shift 2
  w=$(wt "$g")
  ml_guard "$g"
  scripts_wait
  hb
  ( cd "$w" && exec "$MATLAB" "$@" -batch "$cmd" ) >> "$R/$g.log" 2>&1 &
  mp=$!
  wp=$mp; read -r wp < "/proc/$mp/winpid" 2>/dev/null
  printf '%s\nmsys %s\n' "$wp" "$mp" > "$pf"   # the subshell until MATLAB shows
  t0=$EPOCHSECONDS
  while kill -0 "$mp" 2>/dev/null; do
    if [ "$pend" = 1 ] && [ "$EPOCHSECONDS" -ge "$next" ]; then   # MATLAB's PID once the exec shows, also after the wait
      if ml_pid_try "$mp" "$pf"; then pend=0
      elif [ $(( EPOCHSECONDS - t0 )) -ge "$ML_PID_WAIT_S" ]; then
        read -r wp < "/proc/$mp/winpid" 2>/dev/null && isnum "$wp" && printf '%s\nmsys %s\n' "$wp" "$mp" > "$pf"
        alert "ml_pid_${g}_$t0" "MATLAB started in $w did not show as a matlab process within $ML_PID_WAIT_S s (Windows PID $wp, MSYS PID $mp); its PID file holds the subshell's PID, which a restarted takeover treats as alive while it has a MATLAB child. Checked again every $ML_PID_WAIT_S s; the file names MATLAB once it shows."
        next=$(( EPOCHSECONDS + ML_PID_WAIT_S ))
      fi
    fi
    hb
    if [ "$pend" = 1 ] && [ $(( EPOCHSECONDS - t0 )) -lt "$ML_PID_WAIT_S" ]; then sleep 1; else sleep "$STEP"; fi
  done
  wait "$mp"; rc=$?
  rm -f "$pf"
  return "$rc"
}
code_wait() {   # the worktree on its branch, no merge in progress, its code committed
  local g=$1 w b cur why
  w=$(wt "$g"); b=$(br "$g")
  while :; do
    why=""
    cur=$(git -C "$w" symbolic-ref --short -q HEAD)
    [ "$cur" = "$b" ] || why="it is on '$cur', not $b"
    git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null && why="a merge is in progress"
    [ -z "$(git -C "$w" status --porcelain --untracked-files=no -- code startup.m 2>/dev/null)" ] || why="it has uncommitted code changes"
    [ -z "$why" ] && return 0
    alert "code_$g" "$w: $why; no MATLAB starts there until this is fixed."
    nap "$POLL"
  done
}
headroom_wait() {   # free commit of at least $2 GB (default NEED_GB) before a chain's MATLAB starts
  local g=$1 need=${2:-$NEED_GB} h t0 said=0
  t0=$EPOCHSECONDS
  while h=$(sysq headroom | tr -dc '0-9'); [ "${h:-0}" -lt "$need" ]; do
    [ "$said" = 1 ] || { say "$g: free commit ${h:-?} GB < $need GB; waiting"; said=1; }
    [ $(( EPOCHSECONDS - t0 )) -lt "$HEADROOM_ALERT_S" ] || alert "headroom_${g}_$t0" "$g has waited $(( (EPOCHSECONDS - t0) / 60 )) min for $need GB of free commit (now ${h:-?} GB)."
    nap "$POLL"
  done
  [ "$said" = 1 ] && say "$g: free commit $h GB"
  return 0
}
pools_check() {   # an unreadable policy_pools.mat (cut short by a crash) moved aside; C1p's cell checkpoints stay
  local g=$1 w f s
  w=$(wt "$g"); f="$w/data/policy_pools.mat"
  [ -f "$f" ] || return 0
  if run_ml "$g" "whos('-file','data/policy_pools.mat')"; then
    say "$g: data/policy_pools.mat readable, kept"
  else
    s=$(date +%Y%m%d_%H%M%S)
    mv "$f" "$w/data/policy_pools_partial_$s.mat" && say "$g: unreadable data/policy_pools.mat moved to policy_pools_partial_$s.mat"
  fi
}
take_go() {   # control file $2 for profile $1, newer than the profile's log: renamed and taken
  local f="$R/$2" a b
  [ -f "$f" ] || return 1
  a=$(mtime "$f") && b=$(mtime "$R/$1.log") || return 1
  if [ "$a" -le "$b" ]; then
    alert "stale_$2" "$f is older than $1.log, so it predates the event; write it again to go on."
    return 1
  fi
  mv "$f" "$f.used_$(date +%Y%m%d_%H%M%S)" && say "$1: $2 taken"
}
chain_dead() {   # profile $1 runs no chain: its track has ended, no MATLAB of the takeover is recorded there,
                 # and profile 1's launcher chain is over (end marker, a reboot since, or its subshells gone with no MATLAB child)
  local rc m
  [ -f "$R/takeover_end_$1" ] && [ "$(ml_state "$1")" = gone ] || return 1
  [ "$1" = p1 ] || return 0
  rc=$(end_rc p1) || return 1
  [ "$rc" = none ] || return 0
  [[ $(part_mode p1) == takeover* ]] && return 0
  m=$(mtime "$R/p1.log") || return 1
  [ "$m" -lt "$BOOT" ] && return 0
  p1_chain_gone
}
p1_clear() { past_surv3 p1 || complete p1 || { [ -f "$R/p1.abandon" ] && chain_dead p1; }; }   # profile 1 not before its SURV3

# Profile 1: watch; run only on p1_resume.go after a failed or cut chain
gate_enter() {
  local t0=$EPOCHSECONDS
  until mkdir "$GATE" 2>/dev/null; do
    hb
    [ $(( EPOCHSECONDS - t0 )) -lt "$UNKNOWN_ALERT_S" ] || alert "gate_$t0" "$GATE has been held for $(( (EPOCHSECONDS - t0) / 60 )) min; its holder may have died inside it. Stop the takeover and start it again (the start clears it)."
    sleep 1
  done
}
gate_leave() { rmdir "$GATE" 2>/dev/null; }
p3_rerun_open() {   # P3's current part is a B-stage rerun of this boot without its end marker; true when unknown
  local h m part x
  [ -e "$R/p3.log" ] || return 1
  h=$(part_head p3) && hdr_ok "$h" || return 0
  [ "$H_MODE" = takeover-rerun ] || return 1
  m=$(mtime "$R/p3.log") || return 0
  [ "$m" -ge "$BOOT" ] || return 1
  part=$(cur_part p3) || return 0
  x=$(tgrep_end "$part" -c '^##### rerun ended') && ge_ok x "$x" && isnum "$x" || return 0
  [ "$x" = 0 ]
}
p1_cut_now() {   # profile 1's launcher part: no end marker, its chain subshells gone, the log quiet; false when unknown
  local h rc m
  h=$(part_head p1) && hdr_ok "$h" || return 1
  [[ $H_MODE != takeover* ]] || return 1
  rc=$(end_rc p1) && [ "$rc" = none ] || return 1
  m=$(mtime "$R/p1.log") && [ $(( EPOCHSECONDS - m )) -ge "$QUIET_S" ] || return 1
  p1_chain_gone
}
p1_run() {   # from its first unfinished stage to RPT in one MATLAB (A0 first inside the B stages)
  local r x nab nch nc1 a0 F list rc said=0
  ml_guard p1
  until load_list p1 && r=$(next_idx p1) && nab=$(idx_of p1 C1p) && nch=$(idx_of p1 LAT) && nc1=$(idx_of p1 C1c); do
    unknown_wait p1log "p1: p1.log could not be read before the resume"
  done
  known p1log
  while :; do   # C1p and C1c never beside P3's B-stage rerun (the rerun checks the same under the gate)
    if [ "$r" -ge "$nch" ]; then
      echo "##### chain ended rc=0 (its stages were done before an interruption) $(date) #####" >> "$R/p1.log"
      return 0
    fi
    a0=0; [ "$r" -gt 0 ] && [ "$r" -lt "$nab" ] && a0=1
    code_wait p1; headroom_wait p1
    gate_enter
    if [ "$r" -le "$nc1" ] && p3_rerun_open; then
      gate_leave
      [ "$said" = 1 ] || { say "p1: resume from ${F[$r]} waits until profile 3's B-stage rerun has ended"; said=1; }
      nap "$POLL"; continue
    fi
    if ! x=$(next_idx p1) || [ "$x" != "$r" ] || ! part_header p1 "$r" "$a0" takeover; then
      gate_leave
      isnum "$x" && [ "$x" != "$r" ] && { say "p1: first unfinished stage now index $x, not $r; read again"; r=$x; continue; }
      unknown_wait p1log "p1: p1.log could not be read before the resume's part header"; continue
    fi
    gate_leave; break
  done
  known p1log
  commit_note p1 "resume from ${F[$r]}"
  [ "$r" -le "$nab" ] && pools_check p1
  list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${F[@]:r:nch-r}")
  say "p1: stages ${F[$r]} to RPT started (A0 first: $a0)"
  run_ml p1 "$(stage_cmd "${list[@]}")"; rc=$?
  echo "##### chain ended rc=$rc $(date) #####" >> "$R/p1.log"
  say "p1: chain ended rc=$rc"
}
track_p1() {
  local rc r F pi m
  while :; do
    [ -f "$R/p1.abandon" ] && { say "p1: track ended (p1.abandon)"; return 0; }
    complete p1 && { say "p1: chain finished"; return 0; }
    part_idle p1; pi=$?
    if [ "$pi" = 2 ] || ! rc=$(end_rc p1) || ! load_list p1 || ! r=$(next_idx p1); then
      unknown_wait p1log "p1: p1.log could not be read; nothing is decided on it"; continue
    fi
    known p1log
    if [ "$rc" != none ] || [ "$pi" = 0 ] || p1_cut_now; then
      complete p1 && continue   # its end marker written since the check above
      if [ "$rc" != none ]; then
        alert "p1_failed_$H_STAMP" "Profile 1's chain ended with rc=$rc before ${F[$r]:-end} (see $R/p1.log). Profile 3 does not start C1p before profile 1 is past SURV3, and profile 2 does not start (p2_start.go starts it anyway). After the cause is understood and fixed, and after checking that no MATLAB of profile 1 still runs in $V7: write $R/p1_resume.go to go on from ${F[$r]:-end}. Or write p1.abandon to give profile 1 up; then p3_c1p.force lets profile 3's C1p start without profile 1's SURV3 (it skips only that wait)."
      else
        alert "p1_cut_$H_STAMP" "Profile 1's chain stopped without an end marker before ${F[$r]:-end}: a reboot, or its chain subshells (V7T_ALLOW_PIDS '${ALLOW_PIDS:-none}') are gone with no MATLAB child left. First check that no MATLAB of profile 1 still runs in $V7 (Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Select-Object ProcessId,ParentProcessId,CommandLine); a second one would write the same files. Then write $R/p1_resume.go to go on from ${F[$r]:-end} (C1p keeps its per-cell checkpoints)."
      fi
      take_go p1 p1_resume.go && { p1_run; continue; }
    elif m=$(mtime "$R/p1.log") && [ $(( EPOCHSECONDS - m )) -gt "$SILENT_S" ]; then
      alert "p1_silent_$m" "p1.log has not changed for $(( SILENT_S / 3600 )) h; check that profile 1's MATLAB still runs and uses CPU. Alive and busy: nothing to do. Gone: ALERT_p1_cut or ALERT_p1_failed follows. Hanging (alive, no CPU for hours): end that MATLAB with taskkill /PID <pid> /F (no /T); its chain then ends with rc != 0 and ALERT_p1_failed follows."
    fi
    nap "$POLL"
  done
}

# Profile 3's B-stage rerun (p3_brerun.go); each reader gives status 1 when unknown
map_keys() {
  local x; x=$(grep_end -o "'[A-Z][A-Za-z0-9]*', '[A-Za-z_0-9]*'" "$1/code/run_stage.m") && ge_ok x "$x" && [ -n "$x" ] || return 1
  printf '%s\n' "$x" | cut -d"'" -f2 | sort -u
}
go_list() { local s x out=(); s=$(tr -s ', \t\r\n' '     ' < "$GO3") || return 1; for x in $s; do [ "$x" = A0 ] || in_list "$x" "${out[@]}" || out+=("$x"); done; echo "${out[*]}"; }
go_id() { local l m x; l=$(go_list) && m=$(mtime "$GO3") || return 1; x=$(echo "$l $m" | md5sum | cut -c1-12); [[ $x =~ ^[0-9a-f]{12}$ ]] && echo "$x"; }
go_section() {   # p3.log from the last part header of request $1 to the next header; nothing when none
  local x n
  [ -e "$R/p3.log" ] || return 0
  x=$(grep_end -n "^##### PART .* GO $1 " "$R/p3.log") && ge_ok x "$x" || return 1
  [ -n "$x" ] || return 0
  x=${x##*$'\n'}; n=${x%%:*}; isnum "$n" || return 1
  section_at "$R/p3.log" "$n"
}
sec_end() {   # '<rc> <accepted count>' of the rerun in section $1 ('-' for no end line)
  local x a
  x=$(tgrep_end "$1" -o '^##### rerun ended rc=[0-9]*') && ge_ok x "$x" || return 1
  a=$(tgrep_end "$1" -c '^##### rerun accepted ') && ge_ok a "$a" && isnum "$a" || return 1
  if [ -n "$x" ]; then x=${x##*=}; isnum "$x" || return 1; else x=-; fi
  echo "$x $a"
}
go_state() {   # none, done, pending, failed, ignored, blocked (the latest rerun not ended well), invalid:<stage>
  local list x keys K sec e rc acc n s
  if [ -f "$GO3" ]; then
    list=$(go_list) || return 1
    [ -n "$list" ] || { echo "invalid:empty"; return 0; }
    keys=$(map_keys "$P3") || return 1
    split_lines K "$keys"
    for x in $list; do
      if ! in_list "$x" "${K[@]}" || in_list "$x" smoke "${HV[@]}" "${FIN[@]}"; then echo "invalid:$x"; return 0; fi
    done
    x=$(go_id) && sec=$(go_section "$x") && e=$(sec_end "$sec") || return 1
    rc=${e% *}; acc=${e#* }
    [ "$rc" = 0 ] && { echo done; return 0; }
    [ "$rc" != - ] && [ "$acc" -gt 0 ] && { echo done; return 0; }
    grep -q '^##### STAGE C1p (' "$R/p3.log"; s=$?
    [ "$s" -le 1 ] || return 1
    [ "$s" = 0 ] && { echo ignored; return 0; }
    [ "$rc" != - ] && { echo failed; return 0; }
    echo pending; return 0
  fi
  [ -e "$R/p3.log" ] || { echo none; return 0; }
  x=$(grep_end -n '^##### PART .* RERUN ' "$R/p3.log") && ge_ok x "$x" || return 1
  [ -n "$x" ] || { echo none; return 0; }
  x=${x##*$'\n'}; n=${x%%:*}; isnum "$n" || return 1
  sec=$(section_at "$R/p3.log" "$n") && e=$(sec_end "$sec") || return 1
  rc=${e% *}; acc=${e#* }
  if [ "$rc" = 0 ] || [ "$acc" -gt 0 ]; then echo none; else echo blocked; fi
}
last_go_id() {
  local x; x=$(grep_end '^##### PART .* RERUN ' "$R/p3.log") && ge_ok x "$x" && [ -n "$x" ] || return 1
  x=${x##*$'\n'}; [[ $x =~ \ GO\ ([^\ ]+) ]] && echo "${BASH_REMATCH[1]}"
}
rerun_left() {   # stages of request $1 still to run (an interrupted part goes on after its done markers)
  local sec list seq x i=1 j=0
  sec=$(go_section "$1") || return 1
  [ -n "$sec" ] || { go_list; return; }
  [[ ${sec%%$'\n'*} =~ \ RERUN\ ([^\ ]+) ]] || return 1
  list=(${BASH_REMATCH[1]//,/ })
  x=$(tgrep_end "$sec" -o '##### STAGE [A-Za-z0-9]* done') && ge_ok x "$x" || return 1
  seq=($x)
  [ "${seq[2]:-}" = A0 ] || { echo "${list[*]}"; return 0; }
  while [ "$j" -lt "${#list[@]}" ] && [ $(( 4 * i + 2 )) -lt "${#seq[@]}" ] && [ "${seq[4 * i + 2]}" = "${list[$j]}" ]; do
    i=$((i + 1)); j=$((j + 1))
  done
  echo "${list[@]:j}"
}
run_rerun() {
  local id s list r x F nc rc
  if ! id=$(go_id) || ! s=$(rerun_left "$id") || ! load_list p3 || ! nc=$(idx_of p3 C1p); then
    unknown_wait rerun "p3: p3_brerun.go or p3.log could not be read; the rerun waits"; return 0
  fi
  known rerun
  list=($s)
  if [ "${#list[@]}" = 0 ]; then
    echo "##### rerun ended rc=0 GO $id (its stages were done before an interruption) $(date) #####" >> "$R/p3.log"
    return 0
  fi
  code_wait p3; headroom_wait p3 "$RERUN_NEED_GB"
  r=$(( nc - 1 ))
  for x in "${!F[@]}"; do in_list "${F[$x]}" "${list[@]}" && { r=$x; break; }; done
  gate_enter
  if p1_heavy; then   # profile 1 entered C1p or C1c during the waits above
    gate_leave; say "p3: B-stage rerun deferred: profile 1 is between C1p and the end of C1c"
    return 0
  fi
  if ! x=$(go_id) || [ "$x" != "$id" ] || ! part_header p3 "$r" 1 takeover-rerun " RERUN $(IFS=,; echo "${list[*]}") GO $id"; then
    gate_leave; say "p3: p3_brerun.go changed or could not be read before the rerun's part header; read again"
    nap "$QRETRY_S"; return 0
  fi
  gate_leave
  commit_note p3 "B-stage rerun ${list[*]} (request $id)"
  say "p3: B-stage rerun A0 ${list[*]} started (request $id)"
  run_ml p3 "$(stage_cmd A0 "${list[@]}")" -singleCompThread; rc=$?
  echo "##### rerun ended rc=$rc GO $id $(date) #####" >> "$R/p3.log"
  say "p3: B-stage rerun ended rc=$rc"
}

# Profiles 3 and 2: B stages, then C1p to RPT once the other profile is past SURV3
run_ab() {   # B stages from list index $2 (A0 first inside them); end marker only on a failure
  local g=$1 r=$2 nab a0=0 F list rc
  load_list "$g" && nab=$(idx_of "$g" C1p) || return 1
  [ "$r" -gt 0 ] && a0=1
  code_wait "$g"; headroom_wait "$g"
  same_r "$g" "$r" && part_header "$g" "$r" "$a0" takeover || { say "$g: $g.log changed or could not be read before the part header; read again"; return 1; }
  commit_note "$g" "B stages from ${F[$r]}"
  list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${F[@]:r:nab-r}")
  say "$g: stages ${list[*]} started"
  run_ml "$g" "$(stage_cmd "${list[@]}")"; rc=$?
  [ "$rc" = 0 ] || echo "##### chain ended rc=$rc $(date) #####" >> "$R/$g.log"
  say "$g: B stages ended rc=$rc"
  return "$rc"
}
pre_c1p() {   # 0 when C1p may start; 1 after a rerun ran or the track was given up
  local g=$1 d st blk why rc3 said="" id fo msg
  d=$(dep "$g"); fo="$R/${g}_c1p.force"
  while :; do
    [ -f "$R/$g.abandon" ] && return 1
    blk=""; why=""
    if [ "$g" = p3 ]; then
      if ! st=$(go_state); then unknown_wait go3 "p3: p3.log or p3_brerun.go could not be read; C1p and the rerun wait"; continue; fi
      known go3
      case $st in
        pending) if ! p1_heavy; then run_rerun; return 1; fi
                 [ "$said" = rerun_wait ] || { say "p3: B-stage rerun waits until profile 1 is past C1c"; said=rerun_wait; }
                 nap "$POLL"; continue;;
        failed|blocked)
                 if [ "$st" = failed ]; then id=$(go_id); else id=$(last_go_id); fi || { unknown_wait go3 "p3: the rerun's request id could not be read"; continue; }
                 if take_go p3 p3_rerun.accept; then
                   echo "##### rerun accepted GO $id (p3_rerun.accept: C1p goes on with the B stages as they are) $(date) #####" >> "$R/p3.log"
                   say "p3: B-stage rerun $id accepted as it ended (p3_rerun.accept); C1p still waits for p1's SURV3"
                   continue
                 fi
                 if [ "$st" = failed ]; then
                   blk="B-stage rerun failed"
                   alert "p3_rerun_failed_$id" "P3's B-stage rerun (p3_brerun.go) failed (see $R/p3.log); C1p does not start. Fix it, then write p3_brerun.go again (a new version reruns its whole list), or write $R/p3_rerun.accept to go on with the B stages as they are. Either way C1p still waits for profile 1's SURV3. p3_c1p.force does not clear this; it skips only that SURV3 wait, and only once profile 1 is given up and its chain has stopped."
                 else
                   blk="last B-stage rerun not ended well"
                   alert p3_rerun_blocked "P3's last B-stage rerun (request $id) did not end well and p3_brerun.go is gone; C1p does not start. Write p3_brerun.go again, or $R/p3_rerun.accept to go on with the B stages as they are. Either way C1p still waits for profile 1's SURV3. p3_c1p.force does not clear this; it skips only that SURV3 wait, and only once profile 1 is given up and its chain has stopped."
                 fi;;
        ignored) alert "p3_go_ignored_$(go_id)" "p3_brerun.go was written after P3's C1p had started; it is ignored.";;
        invalid:*) blk="p3_brerun.go invalid"
                 alert "p3_rerun_invalid_$(mtime "$GO3")" "p3_brerun.go names '${st#invalid:}', which is not a B stage of $P3/code/run_stage.m; C1p does not start until the file is fixed or removed.";;
      esac
    fi
    if [ "$g" = p2 ] && ! past_surv3 p3; then
      if [ -f "$R/p3.abandon" ]; then
        chain_dead p3 && alert p2_c1p_p3_abandon "Profile 3 is given up (p3.abandon) and its chain has stopped before its SURV3, so profile 2's C1p does not start by itself. Write $R/p2_c1p.force to start it. That file skips only the wait for profile 3's SURV3: profile 2's C1p still waits until profile 1 is past SURV3, has finished, or is given up with its chain stopped."
      elif rc3=$(end_rc p3) && [ "$rc3" != none ] && [ "$rc3" != 0 ]; then
        alert "p2_c1p_p3_failed_$(part_head p3 | awk '{print $3}')" "Profile 3's chain ended with rc=$rc3 before its SURV3, so profile 2's C1p waits. Resume profile 3 (p3_resume.go); or give it up (p3.abandon) and write $R/p2_c1p.force, which skips only the wait for profile 3's SURV3 and counts only once profile 3 is given up and its chain has stopped, so that two C1p never run at once."
      fi
    fi
    [ -f "$R/${g}_c1p.hold" ] && blk="${blk:+$blk; }${g}_c1p.hold"
    [ -z "$blk" ] && past_surv3 "$d" && return 0
    if [ -f "$fo" ]; then   # skips only the wait for the other profile's SURV3, once that profile is given up and its chain stopped
      if [ ! -f "$R/$d.abandon" ]; then
        alert "${g}_force_ignored_$(mtime "$fo")" "$fo exists, but profile ${d#p} is not given up ($d.abandon), so it is ignored: it would start profile ${g#p}'s C1p beside profile ${d#p}'s chain. The file skips only the wait for profile ${d#p}'s SURV3 and counts only once that profile is given up and its chain has stopped. Remove it, or write $R/$d.abandon."
      elif ! chain_dead "$d"; then
        why="${g}_c1p.force waits until profile ${d#p}'s chain has stopped"
      elif [ "$g" = p2 ] && ! p1_clear; then
        why="p2_c1p.force waits until profile 1 is past SURV3, has finished, or is given up with its chain stopped"
      elif [ -z "$blk" ]; then
        say "$g: C1p starts on ${g}_c1p.force (profile ${d#p} given up and its chain stopped; its SURV3 not awaited)"; return 0
      fi
    fi
    msg="${blk:+ and: $blk}${why:+; $why}"
    [ "$said" = "#$msg" ] || { say "$g: C1p waits for $d's SURV3$msg"; said="#$msg"; }
    nap "$POLL"
  done
}
run_c() {   # C1p onward from list index $2 to RPT; the chain's end marker
  local g=$1 r=$2 nab nch F rc d
  load_list "$g" && nab=$(idx_of "$g" C1p) && nch=$(idx_of "$g" LAT) || return 1
  d=$(dep "$g")
  if [ "$r" -ge "$nch" ]; then
    echo "##### chain ended rc=0 (its stages were done before an interruption) $(date) #####" >> "$R/$g.log"
    return 0
  fi
  code_wait "$g"; headroom_wait "$g"
  same_r "$g" "$r" && part_header "$g" "$r" 0 takeover || { say "$g: $g.log changed or could not be read before the part header; read again"; return 1; }
  commit_note "$g" "stages ${F[$r]} to RPT"
  if [ "$r" -le "$nab" ]; then
    pools_check "$g"
    if past_surv3 "$d"; then echo "$g: C1p onward after $d's SURV3 $(date)" >> "$R/$g.log"
    else echo "$g: C1p onward on ${g}_c1p.force $(date)" >> "$R/$g.log"; fi
  fi
  say "$g: stages ${F[$r]} to RPT started"
  run_ml "$g" "$(stage_cmd "${F[@]:r:nch-r}")"; rc=$?
  echo "##### chain ended rc=$rc $(date) #####" >> "$R/$g.log"
  say "$g: chain ended rc=$rc"
}
track_run() {
  local g=$1 rc r nab F op pi
  while :; do
    [ -f "$R/$g.abandon" ] && { say "$g: track ended ($g.abandon)"; return 0; }
    complete "$g" && { say "$g: chain finished"; return 0; }
    ml_guard "$g"
    part_idle "$g"; pi=$?
    if [ "$pi" = 2 ] || ! rc=$(end_rc "$g") || ! load_list "$g" || ! r=$(next_idx "$g") || \
       ! nab=$(idx_of "$g" C1p) || ! op=$(open_stage "$g"); then
      unknown_wait "${g}log" "$g: $g.log could not be read; nothing is decided on it"; continue
    fi
    known "${g}log"
    if [ "$rc" != none ]; then
      alert "${g}_failed_$(part_head "$g" | awk '{print $3}')" "Profile ${g#p}'s chain ended with rc=$rc before ${F[$r]:-end} (see $R/$g.log). After the cause is fixed: write $R/${g}_resume.go to go on from ${F[$r]:-end}, or $g.abandon."
      take_go "$g" "${g}_resume.go" || { nap "$POLL"; continue; }
    elif [ "$pi" = 1 ]; then
      if [ -n "$op" ]; then
        alert "${g}_open_$(part_head "$g" | awk '{print $3}')" "$g.log's current part (mode $(part_mode "$g")) has stage $op open and its script is gone. If its MATLAB still runs, wait; if it has died, write $R/${g}_resume.go."
        take_go "$g" "${g}_resume.go" || { nap "$POLL"; continue; }
      else
        nap "$POLL"; continue
      fi
    fi
    if [ "$r" -lt "$nab" ]; then
      run_ab "$g" "$r"
    elif [ "$r" -eq "$nab" ]; then
      pre_c1p "$g" && run_c "$g" "$r"
    else
      run_c "$g" "$r"
    fi
  done
}

# Profile 2: its worktree once profile 1 has finished
merge_gen() {   # merge $2 into worktree $1; conflicts allowed only in generated files (incoming side)
  local w=$1 c=$2 m=$3 log U f bad
  log="$R/merge_$(basename "$w").log"
  git -C "$w" merge-base --is-ancestor "$c" HEAD && { echo "$c already merged $(date)" >> "$log"; return 0; }
  git -C "$w" merge --no-ff -m "$m" -m "$TRAILER" "$c" >> "$log" 2>&1 && return 0
  U=$(git -C "$w" -c core.quotepath=off diff --name-only --diff-filter=U)
  bad=$(grep -Ev "$GGEN_RE" <<< "$U" | sed '/^$/d')
  if [ -z "$U" ] || [ -n "$bad" ]; then
    git -C "$w" merge --abort >> "$log" 2>&1
    say "merge of $c into $(basename "$w") aborted: ${bad:-failed without a conflict} (see $log)"
    return 1
  fi
  while IFS= read -r f; do
    if git -C "$w" cat-file -e "MERGE_HEAD:$f" 2>/dev/null; then
      git -C "$w" checkout --theirs -- "$f" && git -C "$w" add -f -- "$f"
    else
      git -C "$w" rm -q -f -- "$f"
    fi || { git -C "$w" merge --abort >> "$log" 2>&1; say "merge of $c into $(basename "$w") aborted at $f"; return 1; }
  done <<< "$U"
  git -C "$w" commit -q -m "$m" -m "$TRAILER" >> "$log" 2>&1 || { git -C "$w" merge --abort >> "$log" 2>&1; return 1; }
  echo "merged $c; generated files from the incoming side: $(tr '\n' ' ' <<< "$U") $(date)" >> "$log"
}
p2_prepare() {   # branch v7-p2 from v7-dev, two antennas, fresh data/ and results/, pushed
  local ml s q
  [ -e "$R/p2.log" ] && return 0   # its first part header comes after the preparation
  if [ -d "$P2" ]; then
    grep -q '^p2 v7-p2 ' "$R/code_commit.txt"; q=$?
    [ "$q" = 0 ] && return 0
    [ "$q" = 1 ] || return 1
  fi
  ml="$R/merge_$(basename "$P2").log"; s=$(date +%Y%m%d_%H%M%S)
  if [ ! -d "$P2" ]; then
    if git -C "$REPO" show-ref --verify -q refs/heads/v7-p2; then
      run_hb git -C "$REPO" worktree add "$P2" v7-p2 >> "$ml" 2>&1 || return 1
      merge_gen "$P2" v7-dev "Merge v7-dev into v7-p2: v7 code for profile 2" || return 1
    else
      run_hb git -C "$REPO" worktree add -b v7-p2 "$P2" v7-dev >> "$ml" 2>&1 || return 1
    fi
  fi
  [ "$(git -C "$P2" symbolic-ref --short -q HEAD)" = v7-p2 ] || return 1
  if ! grep -q '"n_rx":2' "$P2/profile.json" 2>/dev/null; then
    printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
    git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" -m "$TRAILER" || return 1
  fi
  mkdir -p "$P2/archive/tracked_$s"
  [ -d "$P2/results" ] && mv "$P2/results" "$P2/archive/tracked_$s/results"
  mkdir -p "$P2/results" "$P2/data"
  echo "p2 v7-p2 $(git -C "$P2" rev-parse HEAD) $(date '+%Y-%m-%d %H:%M:%S %z') takeover: branched from v7-dev $(git -C "$REPO" rev-parse v7-dev)" >> "$R/code_commit.txt"
  run_hb timeout 120 git -C "$P2" push -q -u origin v7-p2 || say "push of v7-p2 failed; the run goes on"
  say "p2: worktree $P2 on v7-p2 $(git -C "$P2" rev-parse --short HEAD)"
}
p2_ab_new() {   # profile 2's B stages, with the stages of p2_set4.stages after B3m
  local f="$R/p2_set4.stages" x s keys K extra=()
  if [ -f "$f" ]; then
    keys=$(map_keys "$P2") && s=$(tr -s ', \t\r\n' '     ' < "$f") || { unknown_wait set4 "p2: p2_set4.stages or $P2/code/run_stage.m could not be read"; return 1; }
    known set4
    split_lines K "$keys"
    for x in $s; do
      if [ "$x" = B3r ]; then   # the fourth set's single reading: by hand after the go/no-go and OOD (d91_set4.md step 7)
        alert "p2_set4_invalid_$(mtime "$f")" "p2_set4.stages names B3r, the fourth test set's single reading. It never runs in the chain: OOD re-saves the detector after it. Run it by hand after the go/no-go (d91_set4.md step 7); list only B3q. Profile 2 waits until the file is fixed or removed."
        nap "$POLL"; return 1
      fi
      if ! in_list "$x" "${K[@]}" || in_list "$x" smoke A0 "${AB2_HEAD[@]}" "${AB2_TAIL[@]}" "${HV[@]}" "${FIN[@]}"; then
        alert "p2_set4_invalid_$(mtime "$f")" "p2_set4.stages names '$x', which is not a new stage of $P2/code/run_stage.m; profile 2 waits until the file is fixed or removed."
        nap "$POLL"; return 1
      fi
      in_list "$x" "${extra[@]}" || extra+=("$x")
    done
  fi
  P2AB_NEW="${AB2_HEAD[*]}${extra[*]:+ ${extra[*]}} ${AB2_TAIL[*]}"
}
track_p2() {
  local said=0
  until complete p1 || [ -e "$R/p2.log" ]; do
    [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
    take_go p2 p2_start.go && { say "p2: starts on p2_start.go before profile 1's chain has finished"; break; }
    [ -f "$R/p1.abandon" ] && alert p2_wait_p1_abandon "Profile 1 is given up (p1.abandon), so profile 2 does not start by itself; write $R/p2_start.go to start it."
    [ "$said" = 1 ] || { say "p2: waits for profile 1's chain to end with rc=0"; said=1; }
    nap "$POLL"
  done
  [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
  until p2_prepare; do
    [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
    alert p2_prep "Profile 2's worktree $P2 could not be prepared (see $R/merge_$(basename "$P2").log and the takeover log); retried every $POLL s."
    nap "$POLL"
  done
  if [ ! -e "$R/p2.log" ]; then
    until p2_ab_new; do :; done
    say "p2: stages $P2AB_NEW"
  fi
  track_run p2
}

# Machine state at the end; the parallel turn's holder
IDLE_END=""
wait_idle() {   # no live pipeline MATLAB and CPU < CPU_IDLE on two polls IDLE_POLL apart; at most IDLE_MAX_S
  local now
  [ -n "$IDLE_END" ] || IDLE_END=$(( EPOCHSECONDS + IDLE_MAX_S ))
  while :; do
    if [ -z "$(stage_live)" ] && [ "$(cpu_int)" -lt "$CPU_IDLE" ]; then
      nap "$IDLE_POLL"
      [ -z "$(stage_live)" ] && [ "$(cpu_int)" -lt "$CPU_IDLE" ] && return 0
    fi
    now=$EPOCHSECONDS
    [ "$now" -lt "$IDLE_END" ] || return 1
    nap $(( IDLE_END - now < IDLE_POLL ? IDLE_END - now : IDLE_POLL ))
  done
}
TURN_SAID=""
turn_check() {   # read only: a turn file whose holder has exited blocks every 'take'
  local tf="$T/uav_gcs_parallel_turn.txt" op st
  [ -f "$tf" ] || return 0
  op=$(tr -dc '0-9' < "$tf"); [ -n "$op" ] || return 0
  st=$(sysq state "$op")
  case $st in
    exited) alert "turn_holder_$op" "The parallel turn file $(cygpath -w "$tf") names MATLAB $op, which has exited but whose process object lingers; parallel_turn still counts it as the holder, so every 'take' waits. Adi: end its leftover child processes (e.g. MATLABWebUI.exe with parent $op) so the process goes away, or, once sure no live MATLAB holds the turn, move the turn file aside.";;
    live|'') ;;
    *) [ "$TURN_SAID" = "$op" ] || { say "parallel turn file names PID $op, no live MATLAB ($st): the next take takes it over"; TURN_SAID=$op; };;
  esac
}
final_phase() {
  local g r F nlat nfull idle ld c
  for g in p1 p3 p2; do
    [ -f "$R/$g.abandon" ] && { say "$g given up: no LAT"; continue; }
    [ -d "$(wt "$g")" ] && [ -f "$R/$g.log" ] || continue
    while complete "$g"; c=$?; [ "$c" = 2 ] || ! load_list "$g" || ! r=$(next_idx "$g") || ! nlat=$(idx_of "$g" LAT); do
      unknown_wait "${g}final" "$g: $g.log could not be read before the final phase"
    done
    known "${g}final"
    [ "$c" = 0 ] || { say "$g did not finish (stage ${F[$r]:-end}): no LAT"; continue; }
    nfull=${#F[@]}
    [ "$r" -lt "$nfull" ] || continue
    part_header "$g" "$r" 0 takeover-final || { say "$g: its stage list could not be read for the final part; no LAT"; continue; }
    if [ "$r" -lt $((nfull - 1)) ]; then
      if wait_idle; then idle="idle"; else idle="not idle after $(( IDLE_MAX_S / 60 )) min"; fi
      ld="machine before LAT: CPU $(cpu_int) %, live pipeline MATLAB sessions: $(stage_live | wc -w | tr -d ' '), live MATLAB processes in all: $(n_live_matlab) ($idle)"
      echo "$ld $(date)" >> "$R/$g.log"; say "$g: $ld"
      commit_note "$g" "final ${F[$r]} to RPT"
      run_ml "$g" "$(stage_cmd "${F[@]:r:nfull-1-r}")"
    fi
    until r=$(next_idx "$g"); do unknown_wait "${g}final" "$g: $g.log could not be read after the final stages"; done
    if [ "$r" -gt $((nlat + 1)) ]; then
      if run_ml "$g" "startup; export_gui_bundle('$(cygpath -m "$V7")/profiles')"; then
        echo "##### STAGE BUNDLE done #####" >> "$R/$g.log"; say "$g: console bundle exported"
      else
        say "$g: console bundle export failed (see $R/$g.log)"
      fi
    else
      say "$g: LAT or KPI failed (see $R/$g.log); no console bundle"
    fi
  done
}

status() {
  local g r F f h rc op pi s
  for g in p1 p3 p2; do
    [ -f "$R/$g.log" ] || { echo "$g: no log"; continue; }
    if ! load_list "$g" || ! r=$(next_idx "$g") || ! h=$(part_head "$g") || ! rc=$(end_rc "$g") || ! op=$(open_stage "$g"); then
      echo "$g: log could not be read (unknown)"; continue
    fi
    part_idle "$g"; pi=$?
    echo "$g: $h"
    echo "    next ${F[$r]:-end} (index $r); end marker rc=$rc; open stage: $op; past SURV3: $(past_surv3 "$g" && echo yes || echo no); finished: $(complete "$g" && echo yes || echo no); idle part: $(case $pi in 0) echo yes;; 1) echo no;; *) echo unknown;; esac)"
  done
  echo "p3 rerun request: $(go_state || echo unknown)"
  for f in "$R"/*.go "$R"/*.accept "$R"/*.hold "$R"/*.force "$R"/*.abandon "$R"/p2_set4.stages "$R"/ALERT_*.txt "$R"/takeover_beat_* "$R"/takeover_end_*; do
    [ -f "$f" ] && echo "file $(basename "$f") ($(date -d @"$(mtime "$f")" '+%F %T'))"
  done
  for f in "$R/run.lock" "$LOCK"; do [ -f "$f" ] && echo "$(basename "$f") age $(( EPOCHSECONDS - $(mtime "$f") )) s"; done
  echo "launcher $LPID: $(sysq cmdline "$LPID" | cut -c1-120)"
  echo "p3 fix $FPID: $(sysq cmdline "$FPID" | cut -c1-120)"
  echo "old scripts outside V7T_ALLOW_PIDS ('$ALLOW_PIDS'): $(if s=$(foreign_scripts); then cut -d'|' -f1 <<< "$s" | tr '\n' ' '; else echo '(scan failed)'; fi)"
  echo "allowed launcher subshells: $(allowed_alive); old scripts not yet renamed: $(for f in "${OLD_SCRIPTS[@]}"; do [ -f "$L/$f" ] && printf '%s ' "$f"; done)"
  echo "code_commit.txt: $(grep -m1 '^SRC' "$R/code_commit.txt" 2>/dev/null | cut -c1-60)"
  [ -f "$T/uav_gcs_parallel_turn.txt" ] && echo "parallel turn: PID $(tr -dc '0-9' < "$T/uav_gcs_parallel_turn.txt") ($(sysq state "$(tr -dc '0-9' < "$T/uav_gcs_parallel_turn.txt")"))"
  echo "free commit $(sysq headroom) GB; live pipeline MATLAB: $(stage_live)"
}

usage() { echo "usage: bash v7_d91_takeover.sh <launcher PID> <p3 fix PID> [status]"; }

# Checks (nothing is changed before they pass)
case "$MODE" in run|status) ;; *) usage; exit 1;; esac
[[ "$LPID" =~ ^[0-9]+$ ]] && [[ "$FPID" =~ ^[0-9]+$ ]] || { usage; exit 1; }
[ -d "$R" ] || { say "$R missing; not started"; exit 1; }
tw=$(cygpath -w "${TEMP:-/nonexistent}" 2>/dev/null)
[ "$tw" = "$TEMP_WIN" ] || { say "TEMP is '$tw', not $TEMP_WIN (the parallel turn file would split); not started"; exit 1; }
T=$(cygpath -u "$TEMP")
START_T=$EPOCHSECONDS
BOOT=""
for i in 1 2 3 4 5; do
  BOOT=$(sysq boot | tr -dc '0-9')
  [[ "$BOOT" =~ ^[0-9]{9,}$ ]] && [ "$BOOT" -le "$START_T" ] && break
  BOOT=""; sleep "$BOOT_RETRY_S"
done
[ -n "$BOOT" ] || { say "the boot time could not be read (5 tries); not started (a reboot could not be told from a running chain)"; exit 1; }
if [ "$MODE" = status ]; then status; exit 0; fi
MAIN=$$
for x in "$LPID launcher v7_d86_launch" "$FPID p3_fix_script v7_d87_p3fix"; do
  read -r p n s <<< "$x"
  c=$(q_known cmdline "$p") || { say "the command line of PID $p could not be read (5 tries); not started"; exit 1; }
  [ "$c" != none ] && runs_script "$c" "$s" && { say "the ${n//_/ } (PID $p) still runs: $c; not started"; exit 1; }
done
for i in 1 2 3 4 5; do c=$(foreign_seen_twice) && break; c="?"; sleep "$BOOT_RETRY_S"; done
[ "$c" != "?" ] || { say "the process scan for old scripts could not be read (5 tries); not started"; exit 1; }
[ -z "$c" ] || { say "bash processes run old run scripts outside V7T_ALLOW_PIDS ('$ALLOW_PIDS', each created within $ALLOW_WIN_S s after p1's launcher part in this boot): $(tr '\n' ';' <<< "$c") not started"; exit 1; }
[ -f "$MATLAB" ] || { say "MATLAB not found at $MATLAB; not started"; exit 1; }
[ -f "$R/code_commit.txt" ] || { say "$R/code_commit.txt missing; not started"; exit 1; }
for g in p1 p3 p2; do
  w=$(wt "$g")
  [ "$g" = p2 ] && [ ! -d "$w" ] && continue
  [ -d "$w" ] || { say "worktree $w missing; not started"; exit 1; }
  b=$(git -C "$w" symbolic-ref --short -q HEAD)
  [ "$b" = "$(br "$g")" ] || { say "$w is on '$b', not $(br "$g"); not started"; exit 1; }
done
lock_take() {   # takeover.lock created atomically (mkdir section, noclobber); a live takeover's lock refuses
  local d="$LOCK.d" lt age lp="" c m me=""
  if ! mkdir "$d" 2>/dev/null; then
    { m=$(mtime "$d") && [ $(( EPOCHSECONDS - m )) -ge 60 ] && rmdir "$d" 2>/dev/null && mkdir "$d" 2>/dev/null; } || \
      { say "another takeover is starting at this moment ($d); not started"; return 1; }
  fi
  if [ -f "$LOCK" ]; then
    lt=$(mtime "$LOCK") || { say "$LOCK could not be read; not started"; rmdir "$d"; return 1; }
    age=$(( EPOCHSECONDS - lt ))
    read -r lp < "$LOCK" 2>/dev/null; lp=${lp//[!0-9]/}
    if [ "$lt" -ge "$BOOT" ] && [ -n "$lp" ]; then   # never stale while its PID still runs a takeover
      c=$(q_known cmdline "$lp") || { say "the command line of PID $lp in $LOCK could not be read (5 tries); not started"; rmdir "$d"; return 1; }
      read -r me < "/proc/$$/winpid" 2>/dev/null
      if [[ $c == *v7_d91_takeover* ]] && [ "$lp" != "$me" ]; then
        say "a takeover (PID $lp) is alive (heartbeat $age s ago); not started. Stop it first (v7_d91_takeover.md, Stopping the takeover)."
        [ "$age" -lt "$STALE_S" ] || alert "takeover_lock_held_$lt" "A start found $LOCK held by takeover PID $lp, whose heartbeat is $(( age / 60 )) min old while it still runs: it may hang. Check its log; stop it (v7_d91_takeover.md) and start it again."
        rmdir "$d"; return 1
      fi
      if [ "$age" -lt $(( 3 * HB_S )) ]; then
        say "a takeover (PID $lp) was alive $age s ago; not started (wait $(( 3 * HB_S )) s after its main bash is gone)"
        rmdir "$d"; return 1
      fi
    elif [ "$lt" -ge "$BOOT" ] && [ "$age" -lt "$STALE_S" ]; then
      say "$LOCK names no PID and is $age s old; not started (until it is $((STALE_S / 60)) min old)"
      rmdir "$d"; return 1
    fi
    rm -f "$LOCK"
  fi
  if ! ( set -C; { cat "/proc/$$/winpid" 2>/dev/null || echo "$$"; date '+%Y-%m-%d %H:%M:%S'; } > "$LOCK" ) 2>/dev/null; then
    say "$LOCK appeared meanwhile; not started"; rmdir "$d"; return 1
  fi
  rmdir "$d"
}
lock_take || exit 1
alive() { local g; for g in p1 p3 p2; do [ -n "${TPID[$g]:-}" ] && kill -0 "${TPID[$g]}" 2>/dev/null && return 0; done; return 1; }
trap 'alive || rm -f "$LOCK"' EXIT   # a live track keeps the lock until it goes stale
retire_launcher || { say "the SRC line of $R/code_commit.txt could not be retired; not started"; exit 1; }
rmdir "$GATE" 2>/dev/null   # left by a takeover that died inside it
rm -f "$R"/takeover_beat_* "$R"/takeover_end_*
[ -f "$R/run.lock" ] || echo "$(cat "/proc/$$/winpid" 2>/dev/null || echo "$$")" > "$R/run.lock"
hb
( while kill -0 $$ 2>/dev/null; do hb; sleep "$HB_S"; done ) &   # heartbeat while this script lives (the tracks beat in their own waits too)
retire_old
say "v7 takeover started (boot $(date -d @"$BOOT" '+%F %T'), TEMP $tw, poll $POLL s, allowed launcher subshells: ${ALLOW_PIDS:-none})"
for g in p1 p3 p2; do
  [ -f "$R/$g.log" ] || continue
  if load_list "$g" && r=$(next_idx "$g") && h=$(part_head "$g"); then say "$g: next ${F[$r]:-end} (index $r); $h"
  else say "$g: $g.log could not be read yet"; fi
done

# Tracks: each beats in its waits and writes its end file when it ends on purpose
start_track() {
  printf '%s\n' "$EPOCHSECONDS" > "$R/takeover_beat_$1"
  { TRACK=$1; hb; "${@:2}"; printf '%s\n' "$EPOCHSECONDS" > "$R/takeover_end_$TRACK"; } &
  TPID[$1]=$!
}
start_track p1 track_p1
start_track p3 track_run p3
start_track p2 track_p2
for g in p1 p3 p2; do wp=""; read -r wp < "/proc/${TPID[$g]}/winpid" 2>/dev/null; echo "$g ${TPID[$g]} ${wp:-?}"; done > "$R/takeover_tracks.txt"
DIED=""
watch_tracks() {   # a track whose beat is old: alert; one gone without its end file: alert, and listed in DIED
  local g t
  for g in p1 p3 p2; do
    if kill -0 "${TPID[$g]}" 2>/dev/null; then
      t=""; read -r t < "$R/takeover_beat_$g" 2>/dev/null
      isnum "$t" && [ $(( EPOCHSECONDS - t )) -ge "$STALL_S" ] && \
        alert "takeover_track_${g}_stalled_$t" "The takeover's $g track has not beaten for $(( (EPOCHSECONDS - t) / 60 )) min (MSYS PID ${TPID[$g]}, $R/takeover_beat_$g): it may hang in a process query, a git command or a fork. Check free memory and the number of processes. If it does not beat again, stop the takeover (v7_d91_takeover.md) and start it again with the same launch command."
    elif [ ! -f "$R/takeover_end_$g" ] && ! in_list "$g" $DIED; then
      DIED="${DIED:+$DIED }$g"
      alert "takeover_track_${g}_died" "The takeover's $g track ended without its end file (a failed fork or a stray taskkill); profile ${g#p} is not followed any more, and the final phase will be skipped. The other tracks go on. Stop the takeover (v7_d91_takeover.md) and start it again with the same launch command: the restart resumes profile ${g#p} from its log."
    fi
  done
}
while alive; do
  turn_check
  if c=$(foreign_seen_twice) && [ -n "$c" ]; then scripts_alert "$c"; fi
  retire_old
  watch_tracks
  nap "$POLL"
done
wait "${TPID[p1]}" "${TPID[p3]}" "${TPID[p2]}"
watch_tracks
if [ -n "$DIED" ]; then
  say "tracks ended; final phase skipped: track $DIED died (ALERT_takeover_track_*_died); start the takeover again with the same launch command"
  exit 1
fi
say "tracks ended"
final_phase
say "v7 done"
