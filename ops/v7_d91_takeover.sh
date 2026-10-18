#!/usr/bin/env bash
# v7 takeover of the d86 launcher's remaining duties, after Adi has ended the launcher's main bash
# and the profile 3 fix script. Three tracks and a final phase; every dependency is read from the
# log markers in uav-gcs-logs/v7_d86/ (the launcher's '##### PART' and '##### STAGE <s> done'
# format), never from process ids.
#
#   bash v7_d91_takeover.sh <launcher PID> <p3 fix PID>          run (resumable: run it again
#                                                                after a reboot or a crash)
#   bash v7_d91_takeover.sh <launcher PID> <p3 fix PID> status   state of every track; changes nothing
#
# Profile 1 (uav-gcs-v7): its chain keeps running to RPT in the launcher's own subshell; the track
#   only reads p1.log. A chain that ends with rc != 0 or is cut by a reboot raises
#   ALERT_p1_failed / ALERT_p1_cut and runs nothing until Adi writes v7_d86/p1_resume.go (newer
#   than p1.log); then the chain goes on from its first unfinished stage under a new part.
# Profile 3 (uav-gcs-v7-p3): C1p to RPT once profile 1's current part is past SURV3; before that,
#   while waiting, the B-stage rerun listed in v7_d86/p3_brerun.go (A0 first; once per version of
#   the file; never after P3's C1p has started).
# Profile 2 (uav-gcs-v7-p2): once profile 1's chain has ended with rc=0 past RPT, branch v7-p2 from
#   v7-dev (profile.json n_rx 2, fresh data/ and results/, pushed; the commit goes to
#   code_commit.txt); A0-B2F, B3n, B3m, the stages of v7_d86/p2_set4.stages if present, B3, B3a, B4,
#   OOD, B4s; then C1p to RPT once profile 3's current part is past SURV3.
# Final: when all three tracks are over, on an idle machine (no live MATLAB running pipeline
#   stages, exited processes not counted; CPU below CPU_IDLE % on two polls IDLE_POLL apart; at
#   most IDLE_MAX_S), LAT, KPI, DASH, WEAK, RPT and the console bundle of every finished profile.
#
# Control files in v7_d86/ (written by Adi or the agent):
#   p1_resume.go, p3_resume.go, p2_resume.go   go on after a failed or cut chain (must be newer
#                                              than the profile's log; renamed to .used_<time>)
#   p3_brerun.go       stage list of P3's B-stage rerun, e.g. "B2F B3 B3a B4 OOD B4s"
#   p2_set4.stages     extra stages of profile 2 after B3m, e.g. "B3q B3r"
#   p3_c1p.hold, p2_c1p.hold     hold the profile before C1p
#   p3_c1p.force, p2_c1p.force   start C1p without the other profile's SURV3 and past a failed rerun
#   p1.abandon, p3.abandon, p2.abandon         end that track; the final phase skips the profile
# Alerts: v7_d86/ALERT_<topic>.txt (delete after handling) and this script's log.
#
# Safety: refuses unless cygpath -w "$TEMP" is TEMP_WIN (the parallel turn file lives there),
# while either given PID still runs its script, or while another takeover's heartbeat
# (v7_d86/takeover.lock) is fresh. Touches v7_d86/run.lock and takeover.lock at least every HB_S
# seconds for its whole life, so the launcher's resume always refuses. One MATLAB per profile
# worktree at a time; never touches the parallel turn file.
#
# Start detached (PowerShell), the same way as the launcher (same TEMP):
#   $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
# V7T_* environment variables point it at a test copy; a real run leaves them unset.

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
STALE_S=${V7T_STALE_S:-1200}               # [s] heartbeat age beyond which no takeover is alive
QUIET_S=${V7T_QUIET_S:-120}                # [s] a part written by an ended script: quiet this long
SILENT_S=${V7T_SILENT_S:-21600}            # [s] profile 1's log silent this long: alert
IDLE_MAX_S=${V7T_IDLE_MAX_S:-14400}        # [s] longest wait for an idle machine before LAT
IDLE_POLL=${V7T_IDLE_POLL:-600}            # [s] between the two idle polls
CPU_IDLE=${V7T_CPU_IDLE:-15}               # [%]
NEED_GB=${V7T_NEED_GB:-45}                 # [GB] free commit before a chain's MATLAB starts
HEADROOM_ALERT_S=${V7T_HEADROOM_ALERT_S:-3600}
COPY_RE=${V7T_COPY_RE:-'B3m|B3q|B3r'}      # stages run in worktree copies, not counted as busy
R="$L/v7_d86"
LOCK="$R/takeover.lock"
GO3="$R/p3_brerun.go"
TRAILER="Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_EDITOR=true

AB=(A0 A4v A5 A6 B1 B2 B2F B3n B3 B3a B4 OOD B4s)
AB2_HEAD=(A0 A4v A5 A6 B1 B2 B2F B3n B3m)
AB2_TAIL=(B3 B3a B4 OOD B4s)
HV=(C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT)
FIN=(LAT KPI DASH WEAK RPT BUNDLE)
GGEN_RE='^params\.mat$|^models/[^/]*\.slx$|^results/'
declare -A RAISED=()

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
wt()  { case $1 in p1) echo "$V7";; p3) echo "$P3";; p2) echo "$P2";; esac; }
br()  { case $1 in p1) echo v7-dev;; p3) echo v7-p3;; p2) echo v7-p2;; esac; }
dep() { case $1 in p3) echo p1;; p2) echo p3;; esac; }   # whose SURV3 this profile's C1p waits for
mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
hb()  { touch -c "$R/run.lock" "$LOCK" 2>/dev/null; }   # never recreates the takeover lock after its removal
nap() {   # sleep $1 seconds with heartbeats
  local end=$(( $(date +%s) + $1 )) now
  while hb; now=$(date +%s); [ "$now" -lt "$end" ]; do
    sleep $(( end - now < HB_S ? end - now : HB_S ))
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
in_list() { local x=$1; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }

# Machine queries: PowerShell, or the stand-in V7T_SYS
sysq() {
  local q
  if [ -n "$SYS" ]; then "$SYS" "$@"; return; fi
  case $1 in
    cmdline|state) [[ "${2:-}" =~ ^[0-9]+$ ]] || return 0;;
  esac
  case $1 in
    cmdline)  q="(Get-CimInstance Win32_Process -Filter \"ProcessId=$2\").CommandLine";;
    state)    q="\$p = Get-Process -Id $2 -ErrorAction SilentlyContinue; if (-not \$p) {'none'} elseif (\$p.HasExited) {'exited'} elseif (\$p.Path -like '*win64*') {'live'} else {'other'}";;
    matlab)   q="Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Where-Object { \$_.CommandLine -like '*win64*' } | ForEach-Object { \$p = Get-Process -Id \$_.ProcessId -ErrorAction SilentlyContinue; \$x = if (-not \$p -or \$p.HasExited) {1} else {0}; '{0}|{1}|{2}' -f \$_.ProcessId, \$x, \$_.CommandLine }";;
    cpu)      q="(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average";;
    boot)     q="([DateTimeOffset](Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToUnixTimeSeconds()";;
    headroom) q="[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory / 1MB)";;
    *) return 1;;
  esac
  powershell.exe -NoProfile -Command "$q" 2>/dev/null | tr -d '\r'
}
stage_live() {   # live MATLAB sessions running pipeline stages (smoke runs and worktree copies not counted)
  sysq matlab | awk -F'|' '$2 == 0' | grep 'run_stage(' | grep -v "run_stage(.smoke" | grep -Ev "$COPY_RE" | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ *$//'
}
n_live_matlab() { sysq matlab | awk -F'|' '$2 == 0' | wc -l | tr -d ' '; }
cpu_int() { local c; c=$(sysq cpu); c=${c%%.*}; c=$(tr -dc '0-9' <<< "$c"); echo "${c:-100}"; }

# Log markers. A part runs from its '##### PART <stamp> <mode> SRC <sha> FROM <i> <stage> A0 <0|1>
# [AB <list>] [RERUN <list> GO <id>] #####' header to the next header.
cur_part() {
  local f="$R/$1.log" n
  [ -f "$f" ] || return 0
  n=$(grep -n '^##### PART ' "$f" | tail -1 | cut -d: -f1)
  [ -n "$n" ] && tail -n +"$n" "$f"
}
section_at() { tail -n +"$2" "$1" | awk 'NR > 1 && /^##### PART /{exit} {print}'; }
hdr_field() { sed -n "s/.* $2 \([^ ]*\) .*/\1/p" <<< "$1"; }
part_mode() { cur_part "$1" | head -1 | awk '{print $4}'; }
part_stamp() { cur_part "$1" | head -1 | awk '{print $3}'; }
ab_of() {   # B stages of the profile; profile 2's from its latest part header
  local h
  if [ "$1" = p2 ]; then
    h=$(grep '^##### PART .* AB ' "$R/p2.log" 2>/dev/null | tail -1)
    h=$(hdr_field "$h" AB)
    if [ -n "$h" ]; then echo "${h//,/ }"; else echo "${P2AB_NEW:-${AB2_HEAD[*]} ${AB2_TAIL[*]}}"; fi
    return
  fi
  echo "${AB[*]}"
}
list_of() {   # all stages of the profile, as its current part counts them
  local h ab
  h=$(cur_part "$1" | head -1); ab=$(hdr_field "$h" AB)
  if [ -n "$ab" ]; then ab=${ab//,/ }; else ab=$(ab_of "$1"); fi
  echo "$ab ${HV[*]} ${FIN[*]}"
}
idx_of() { local i=0 x; for x in $(list_of "$1"); do [ "$x" = "$2" ] && { echo "$i"; return; }; i=$((i + 1)); done; echo -1; }
# index of the profile's first unfinished stage: the part's start, advanced over the
# '##### STAGE <s> done' markers that follow the list in order; a rerun part leaves it at C1p
next_idx() {
  local part hdr r a0 i=0 seq F
  part=$(cur_part "$1")
  [ -n "$part" ] || { echo 0; return; }
  read -ra F <<< "$(list_of "$1")"
  hdr=$(head -1 <<< "$part")
  if [ -n "$(hdr_field "$hdr" RERUN)" ]; then idx_of "$1" C1p; return; fi
  r=$(sed -n 's/.* FROM \([0-9]*\) [^ ]* A0 [01] .*/\1/p' <<< "$hdr")
  a0=$(sed -n 's/.* FROM [0-9]* [^ ]* A0 \([01]\) .*/\1/p' <<< "$hdr")
  [ -n "$r" ] || { echo 0; return; }
  mapfile -t seq < <(grep -o '##### STAGE [A-Za-z0-9]* done' <<< "$part" | cut -d' ' -f3)
  if [ "$a0" = 1 ]; then
    [ "${seq[0]:-}" = A0 ] || { echo "$r"; return; }
    i=1
  fi
  while [ "$r" -lt "${#F[@]}" ] && [ "$i" -lt "${#seq[@]}" ] && [ "${seq[$i]}" = "${F[$r]}" ]; do
    r=$((r + 1)); i=$((i + 1))
  done
  echo "$r"
}
end_rc()     { cur_part "$1" | grep -o '^##### chain ended rc=[0-9]*' | tail -1 | sed 's/.*rc=//'; }
open_stage() { cur_part "$1" | grep '^##### STAGE [A-Za-z0-9]* ' | tail -1 | awk '$4 != "done" {print $3}'; }
past_surv3() { [ "$(next_idx "$1")" -gt "$(idx_of "$1" SURV3)" ]; }
complete() {   # past RPT, and the chain's MATLAB over (its end marker, or a final-phase part)
  local nlat from
  nlat=$(idx_of "$1" LAT)
  [ "$(next_idx "$1")" -ge "$nlat" ] || return 1
  [ "$(end_rc "$1")" = 0 ] && return 0
  from=$(cur_part "$1" | head -1 | sed -n 's/.* FROM \([0-9]*\) .*/\1/p')
  [ "${from:-0}" -ge "$nlat" ]
}
part_idle() {   # nothing writes the profile's current part any more
  local g=$1 part f="$R/$1.log"
  part=$(cur_part "$g")
  [ -n "$part" ] || return 0
  grep -q '^##### \(chain\|rerun\) ended' <<< "$part" && return 0
  [[ $(part_mode "$g") == takeover* ]] && return 0
  [ "$(mtime "$f")" -lt "$BOOT" ] && return 0
  [ "$g" = p1 ] && return 1
  [ -z "$(open_stage "$g")" ] && [ $(( $(date +%s) - $(mtime "$f") )) -ge "$QUIET_S" ]
}

stage_cmd() { local q; q=$(printf ",'%s'" "$@"); echo "run_stage(${q#,})"; }
part_header() {   # profile $1, list index $2, A0 first $3, mode $4, extra header fields $5
  local g=$1 r=$2 F extra=${5:-} sha
  read -ra F <<< "$(list_of "$g")"
  [ "$g" = p2 ] && extra=" AB $(ab_of p2 | tr ' ' ',')$extra"
  sha=$(git -C "$(wt "$g")" rev-parse HEAD 2>/dev/null)
  echo "##### PART $(date +%Y%m%d_%H%M%S) $4 SRC ${sha:-unknown} FROM $r ${F[$r]:-end} A0 $3$extra #####" >> "$R/$g.log"
}
commit_note() { echo "$1 $(br "$1") $(git -C "$(wt "$1")" rev-parse HEAD) $(date '+%Y-%m-%d %H:%M:%S %z') takeover: $2" >> "$R/code_commit.txt"; }

# MATLAB -batch "$2" in profile $1's worktree, output appended to its log; heartbeat while it runs
ml_guard() {   # a MATLAB this takeover started earlier in the worktree, still alive: wait
  local g=$1 pf="$R/takeover_ml_$1.pid" op
  while [ -f "$pf" ]; do
    op=$(tr -dc '0-9' < "$pf")
    [ -n "$op" ] && [ "$(mtime "$pf")" -ge "$BOOT" ] || break
    grep -qi matlab <<< "$(sysq cmdline "$op")" || break
    alert "ml_alive_$g" "A MATLAB started earlier in $(wt "$g") (Windows PID $op) is still alive; no new MATLAB starts there until it exits."
    nap "$POLL"
  done
  rm -f "$pf"
}
run_ml() {
  local g=$1 cmd=$2 w mp rc pf="$R/takeover_ml_$1.pid"
  w=$(wt "$g")
  ml_guard "$g"
  ( cd "$w" && exec "$MATLAB" -batch "$cmd" ) >> "$R/$g.log" 2>&1 &
  mp=$!
  sleep 1; cat "/proc/$mp/winpid" > "$pf" 2>/dev/null
  while kill -0 "$mp" 2>/dev/null; do hb; sleep "$STEP"; done
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
headroom_wait() {   # free commit of at least NEED_GB before a chain's MATLAB starts
  local g=$1 h t0 said=0
  t0=$(date +%s)
  while h=$(sysq headroom | tr -dc '0-9'); [ "${h:-0}" -lt "$NEED_GB" ]; do
    [ "$said" = 1 ] || { say "$g: free commit ${h:-?} GB < $NEED_GB GB; waiting"; said=1; }
    [ $(( $(date +%s) - t0 )) -lt "$HEADROOM_ALERT_S" ] || alert "headroom_${g}_$t0" "$g has waited $(( ($(date +%s) - t0) / 60 )) min for $NEED_GB GB of free commit (now ${h:-?} GB)."
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
  local f="$R/$2"
  [ -f "$f" ] || return 1
  if [ "$(mtime "$f")" -le "$(mtime "$R/$1.log")" ]; then
    alert "stale_$2" "$f is older than $1.log, so it predates the event; write it again to go on."
    return 1
  fi
  mv "$f" "$f.used_$(date +%Y%m%d_%H%M%S)" && say "$1: $2 taken"
}

# Profile 1: watch; run only on p1_resume.go after a failed or cut chain
p1_run() {   # from its first unfinished stage to RPT in one MATLAB (A0 first inside the B stages)
  local r nab nch a0=0 F list rc
  ml_guard p1
  read -ra F <<< "$(list_of p1)"
  r=$(next_idx p1); nab=$(idx_of p1 C1p); nch=$(idx_of p1 LAT)
  if [ "$r" -ge "$nch" ]; then
    echo "##### chain ended rc=0 (its stages were done before an interruption) $(date) #####" >> "$R/p1.log"
    return 0
  fi
  [ "$r" -gt 0 ] && [ "$r" -lt "$nab" ] && a0=1
  code_wait p1; headroom_wait p1
  part_header p1 "$r" "$a0" takeover
  commit_note p1 "resume from ${F[$r]}"
  [ "$r" -le "$nab" ] && pools_check p1
  list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${F[@]:r:nch-r}")
  say "p1: stages ${F[$r]} to RPT started (A0 first: $a0)"
  run_ml p1 "$(stage_cmd "${list[@]}")"; rc=$?
  echo "##### chain ended rc=$rc $(date) #####" >> "$R/p1.log"
  say "p1: chain ended rc=$rc"
}
track_p1() {
  local rc r F
  while :; do
    [ -f "$R/p1.abandon" ] && { say "p1: track ended (p1.abandon)"; return 0; }
    complete p1 && { say "p1: chain finished"; return 0; }
    rc=$(end_rc p1)
    if [ -n "$rc" ] || part_idle p1; then
      read -ra F <<< "$(list_of p1)"; r=$(next_idx p1)
      if [ -n "$rc" ]; then
        alert "p1_failed_$(part_stamp p1)" "Profile 1's chain ended with rc=$rc before ${F[$r]:-end} (see $R/p1.log). Profile 3 does not start C1p before profile 1 is past SURV3, and profile 2 does not start. After the cause is understood and fixed: write $R/p1_resume.go to go on from ${F[$r]:-end} (or p1.abandon to give profile 1 up; then p3_c1p.force lets profile 3 go on)."
      else
        alert "p1_cut_$(part_stamp p1)" "Profile 1's chain stopped without an end marker (a reboot) before ${F[$r]:-end}. Write $R/p1_resume.go to go on from ${F[$r]:-end} (C1p keeps its per-cell checkpoints)."
      fi
      take_go p1 p1_resume.go && { p1_run; continue; }
    elif [ $(( $(date +%s) - $(mtime "$R/p1.log") )) -gt "$SILENT_S" ]; then
      alert "p1_silent_$(mtime "$R/p1.log")" "p1.log has not changed for $(( SILENT_S / 3600 )) h; check that profile 1's MATLAB still runs."
    fi
    nap "$POLL"
  done
}

# Profile 3's B-stage rerun (p3_brerun.go)
map_keys() { grep -o "'[A-Z][A-Za-z0-9]*', '[A-Za-z_0-9]*'" "$1/code/run_stage.m" 2>/dev/null | cut -d"'" -f2 | sort -u; }
go_list() { local x out=(); for x in $(tr -s ', \t\r\n' '     ' < "$GO3"); do [ "$x" = A0 ] || in_list "$x" "${out[@]}" || out+=("$x"); done; echo "${out[*]}"; }
go_id() { echo "$(go_list) $(mtime "$GO3")" | md5sum | cut -c1-12; }
go_section() { local n; n=$(grep -n "^##### PART .* GO $1 " "$R/p3.log" 2>/dev/null | tail -1 | cut -d: -f1); [ -n "$n" ] && section_at "$R/p3.log" "$n"; }
go_state() {   # none, done, pending, failed, ignored, blocked (the latest rerun not ended well), invalid:<stage>
  local list x keys sec rc n
  if [ -f "$GO3" ]; then
    list=$(go_list); [ -n "$list" ] || { echo "invalid:empty"; return; }
    keys=$(map_keys "$P3")
    for x in $list; do
      if ! grep -qx "$x" <<< "$keys" || in_list "$x" smoke "${HV[@]}" "${FIN[@]}"; then echo "invalid:$x"; return; fi
    done
    sec=$(go_section "$(go_id)")
    rc=$(grep -o '^##### rerun ended rc=[0-9]*' <<< "$sec" | tail -1 | sed 's/.*rc=//')
    [ "$rc" = 0 ] && { echo done; return; }
    grep -q '^##### STAGE C1p (' "$R/p3.log" && { echo ignored; return; }
    [ -n "$rc" ] && { echo failed; return; }
    echo pending; return
  fi
  n=$(grep -n '^##### PART .* RERUN ' "$R/p3.log" 2>/dev/null | tail -1 | cut -d: -f1)
  [ -n "$n" ] || { echo none; return; }
  rc=$(section_at "$R/p3.log" "$n" | grep -o '^##### rerun ended rc=[0-9]*' | tail -1 | sed 's/.*rc=//')
  if [ "$rc" = 0 ]; then echo none; else echo blocked; fi
}
rerun_left() {   # stages of request $1 still to run (an interrupted part goes on after its done markers)
  local sec list seq i=1 j=0
  sec=$(go_section "$1")
  [ -n "$sec" ] || { go_list; return; }
  read -ra list <<< "$(hdr_field "$(head -1 <<< "$sec")" RERUN | tr ',' ' ')"
  mapfile -t seq < <(grep -o '##### STAGE [A-Za-z0-9]* done' <<< "$sec" | cut -d' ' -f3)
  [ "${seq[0]:-}" = A0 ] || { echo "${list[*]}"; return; }
  while [ "$j" -lt "${#list[@]}" ] && [ "$i" -lt "${#seq[@]}" ] && [ "${seq[$i]}" = "${list[$j]}" ]; do
    i=$((i + 1)); j=$((j + 1))
  done
  echo "${list[@]:j}"
}
run_rerun() {
  local id list r x F rc
  id=$(go_id)
  read -ra list <<< "$(rerun_left "$id")"
  if [ "${#list[@]}" = 0 ]; then
    echo "##### rerun ended rc=0 GO $id (its stages were done before an interruption) $(date) #####" >> "$R/p3.log"
    return 0
  fi
  code_wait p3; headroom_wait p3
  read -ra F <<< "$(list_of p3)"
  r=$(( $(idx_of p3 C1p) - 1 ))
  for x in "${!F[@]}"; do in_list "${F[$x]}" "${list[@]}" && { r=$x; break; }; done
  part_header p3 "$r" 1 takeover-rerun " RERUN $(IFS=,; echo "${list[*]}") GO $id"
  commit_note p3 "B-stage rerun ${list[*]} (request $id)"
  say "p3: B-stage rerun A0 ${list[*]} started (request $id)"
  run_ml p3 "$(stage_cmd A0 "${list[@]}")"; rc=$?
  echo "##### rerun ended rc=$rc GO $id $(date) #####" >> "$R/p3.log"
  say "p3: B-stage rerun ended rc=$rc"
}

# Profiles 3 and 2: B stages, then C1p to RPT once the other profile is past SURV3
run_ab() {   # B stages from list index $2 (A0 first inside them); end marker only on a failure
  local g=$1 r=$2 nab a0=0 F list rc
  read -ra F <<< "$(list_of "$g")"; nab=$(idx_of "$g" C1p)
  [ "$r" -gt 0 ] && a0=1
  code_wait "$g"; headroom_wait "$g"
  part_header "$g" "$r" "$a0" takeover
  commit_note "$g" "B stages from ${F[$r]}"
  list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${F[@]:r:nab-r}")
  say "$g: stages ${list[*]} started"
  run_ml "$g" "$(stage_cmd "${list[@]}")"; rc=$?
  [ "$rc" = 0 ] || echo "##### chain ended rc=$rc $(date) #####" >> "$R/$g.log"
  say "$g: B stages ended rc=$rc"
  return "$rc"
}
pre_c1p() {   # 0 when C1p may start; 1 after a rerun ran or the track was given up
  local g=$1 d st blk said=""
  d=$(dep "$g")
  while :; do
    [ -f "$R/$g.abandon" ] && return 1
    blk=""
    if [ "$g" = p3 ]; then
      st=$(go_state)
      case $st in
        pending) run_rerun; return 1;;
        failed)  blk="B-stage rerun failed"
                 alert "p3_rerun_failed_$(go_id)" "P3's B-stage rerun (p3_brerun.go) failed (see $R/p3.log); C1p does not start. Fix it, then write p3_brerun.go again (a new version reruns its whole list), or write p3_c1p.force to start C1p as it is.";;
        blocked) blk="last B-stage rerun not ended well"
                 alert p3_rerun_blocked "P3's last B-stage rerun did not end well and p3_brerun.go is gone; C1p does not start. Write p3_brerun.go again, or p3_c1p.force to start C1p as it is.";;
        ignored) alert "p3_go_ignored_$(go_id)" "p3_brerun.go was written after P3's C1p had started; it is ignored.";;
        invalid:*) blk="p3_brerun.go invalid"
                 alert "p3_rerun_invalid_$(mtime "$GO3")" "p3_brerun.go names '${st#invalid:}', which is not a B stage of $P3/code/run_stage.m; C1p does not start until the file is fixed or removed.";;
      esac
    fi
    [ -f "$R/${g}_c1p.hold" ] && blk="${blk:+$blk; }${g}_c1p.hold"
    if [ -f "$R/${g}_c1p.force" ]; then
      [ -f "$R/${g}_c1p.hold" ] || { say "$g: C1p starts on ${g}_c1p.force"; return 0; }
    elif [ -z "$blk" ] && past_surv3 "$d"; then
      return 0
    fi
    if [ "$said" != "$blk" ]; then
      say "$g: C1p waits for $d's SURV3${blk:+ and: $blk}"; said=$blk
    fi
    nap "$POLL"
  done
}
run_c() {   # C1p onward from list index $2 to RPT; the chain's end marker
  local g=$1 r=$2 nab nch F rc d
  read -ra F <<< "$(list_of "$g")"; nab=$(idx_of "$g" C1p); nch=$(idx_of "$g" LAT); d=$(dep "$g")
  if [ "$r" -ge "$nch" ]; then
    echo "##### chain ended rc=0 (its stages were done before an interruption) $(date) #####" >> "$R/$g.log"
    return 0
  fi
  code_wait "$g"; headroom_wait "$g"
  part_header "$g" "$r" 0 takeover
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
  local g=$1 rc r nab F
  while :; do
    [ -f "$R/$g.abandon" ] && { say "$g: track ended ($g.abandon)"; return 0; }
    complete "$g" && { say "$g: chain finished"; return 0; }
    ml_guard "$g"
    rc=$(end_rc "$g")
    read -ra F <<< "$(list_of "$g")"; r=$(next_idx "$g"); nab=$(idx_of "$g" C1p)
    if [ -n "$rc" ]; then
      alert "${g}_failed_$(part_stamp "$g")" "Profile ${g#p}'s chain ended with rc=$rc before ${F[$r]:-end} (see $R/$g.log). After the cause is fixed: write $R/${g}_resume.go to go on from ${F[$r]:-end}, or $g.abandon."
      take_go "$g" "${g}_resume.go" || { nap "$POLL"; continue; }
    elif ! part_idle "$g"; then
      if [ -n "$(open_stage "$g")" ]; then
        alert "${g}_open_$(part_stamp "$g")" "$g.log's current part (mode $(part_mode "$g")) has stage $(open_stage "$g") open and its script is gone. If its MATLAB still runs, wait; if it has died, write $R/${g}_resume.go."
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
  local ml s
  [ -d "$P2" ] && grep -q '^p2 v7-p2 ' "$R/code_commit.txt" 2>/dev/null && return 0
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
  local f="$R/p2_set4.stages" x keys extra=()
  if [ -f "$f" ]; then
    keys=$(map_keys "$P2")
    for x in $(tr -s ', \t\r\n' '     ' < "$f"); do
      if ! grep -qx "$x" <<< "$keys" || in_list "$x" smoke A0 "${AB2_HEAD[@]}" "${AB2_TAIL[@]}" "${HV[@]}" "${FIN[@]}"; then
        alert "p2_set4_invalid_$(mtime "$f")" "p2_set4.stages names '$x', which is not a new stage of $P2/code/run_stage.m; profile 2 waits until the file is fixed or removed."
        return 1
      fi
      in_list "$x" "${extra[@]}" || extra+=("$x")
    done
  fi
  P2AB_NEW="${AB2_HEAD[*]}${extra[*]:+ ${extra[*]}} ${AB2_TAIL[*]}"
}
track_p2() {
  local said=0
  until complete p1 || [ -f "$R/p1.abandon" ] || [ -n "$(cur_part p2)" ]; do
    [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
    [ "$said" = 1 ] || { say "p2: waits for profile 1's chain to end with rc=0"; said=1; }
    nap "$POLL"
  done
  [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
  until p2_prepare; do
    [ -f "$R/p2.abandon" ] && { say "p2: track ended (p2.abandon)"; return 0; }
    alert p2_prep "Profile 2's worktree $P2 could not be prepared (see $R/merge_$(basename "$P2").log and the takeover log); retried every $POLL s."
    nap "$POLL"
  done
  if [ -z "$(cur_part p2)" ]; then
    until p2_ab_new; do nap "$POLL"; done
    say "p2: stages $P2AB_NEW"
  fi
  track_run p2
}

# Machine state at the end; the parallel turn's holder
IDLE_END=""
wait_idle() {   # no live pipeline MATLAB and CPU < CPU_IDLE on two polls IDLE_POLL apart; at most IDLE_MAX_S
  local now
  [ -n "$IDLE_END" ] || IDLE_END=$(( $(date +%s) + IDLE_MAX_S ))
  while :; do
    if [ -z "$(stage_live)" ] && [ "$(cpu_int)" -lt "$CPU_IDLE" ]; then
      nap "$IDLE_POLL"
      [ -z "$(stage_live)" ] && [ "$(cpu_int)" -lt "$CPU_IDLE" ] && return 0
    fi
    now=$(date +%s)
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
    live) ;;
    *) [ "$TURN_SAID" = "$op" ] || { say "parallel turn file names PID $op, no live MATLAB ($st): the next take takes it over"; TURN_SAID=$op; };;
  esac
}
final_phase() {
  local g r F nlat nfull idle ld
  for g in p1 p3 p2; do
    [ -f "$R/$g.abandon" ] && { say "$g given up: no LAT"; continue; }
    [ -d "$(wt "$g")" ] && [ -f "$R/$g.log" ] || continue
    complete "$g" || { say "$g did not finish (stage $(list_of "$g" | cut -d' ' -f$(( $(next_idx "$g") + 1 )))): no LAT"; continue; }
    r=$(next_idx "$g"); read -ra F <<< "$(list_of "$g")"; nlat=$(idx_of "$g" LAT); nfull=${#F[@]}
    [ "$r" -lt "$nfull" ] || continue
    part_header "$g" "$r" 0 takeover-final
    if [ "$r" -lt $((nfull - 1)) ]; then
      if wait_idle; then idle="idle"; else idle="not idle after $(( IDLE_MAX_S / 60 )) min"; fi
      ld="machine before LAT: CPU $(cpu_int) %, live pipeline MATLAB sessions: $(stage_live | wc -w | tr -d ' '), live MATLAB processes in all: $(n_live_matlab) ($idle)"
      echo "$ld $(date)" >> "$R/$g.log"; say "$g: $ld"
      commit_note "$g" "final ${F[$r]} to RPT"
      run_ml "$g" "$(stage_cmd "${F[@]:r:nfull-1-r}")"
    fi
    if [ "$(next_idx "$g")" -gt $((nlat + 1)) ]; then
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
  local g r F f
  for g in p1 p3 p2; do
    [ -f "$R/$g.log" ] || { echo "$g: no log"; continue; }
    read -ra F <<< "$(list_of "$g")"; r=$(next_idx "$g")
    echo "$g: $(cur_part "$g" | head -1)"
    echo "    next ${F[$r]:-end} (index $r); end marker rc=$(end_rc "$g"); open stage: $(open_stage "$g"); past SURV3: $(past_surv3 "$g" && echo yes || echo no); finished: $(complete "$g" && echo yes || echo no); idle part: $(part_idle "$g" && echo yes || echo no)"
  done
  echo "p3 rerun request: $(go_state)"
  for f in "$R"/*.go "$R"/*.hold "$R"/*.force "$R"/*.abandon "$R"/p2_set4.stages "$R"/ALERT_*.txt; do
    [ -f "$f" ] && echo "file $(basename "$f") ($(date -d @"$(mtime "$f")" '+%F %T'))"
  done
  for f in "$R/run.lock" "$LOCK"; do [ -f "$f" ] && echo "$(basename "$f") age $(( $(date +%s) - $(mtime "$f") )) s"; done
  echo "launcher $LPID: $(sysq cmdline "$LPID" | cut -c1-120)"
  echo "p3 fix $FPID: $(sysq cmdline "$FPID" | cut -c1-120)"
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
BOOT=$(sysq boot | tr -dc '0-9'); BOOT=${BOOT:-0}
if [ "$MODE" = status ]; then status; exit 0; fi
c=$(sysq cmdline "$LPID"); grep -q 'v7_d86_launch' <<< "$c" && { say "the launcher (PID $LPID) still runs: $c; not started"; exit 1; }
c=$(sysq cmdline "$FPID"); grep -q 'v7_d87_p3fix' <<< "$c" && { say "the p3 fix script (PID $FPID) still runs: $c; not started"; exit 1; }
if [ -f "$LOCK" ]; then
  lt=$(mtime "$LOCK"); age=$(( $(date +%s) - lt ))
  if [ "$age" -lt "$STALE_S" ] && [ "$lt" -ge "$BOOT" ]; then
    say "a takeover (PID $(head -1 "$LOCK")) was alive $age s ago; not started (after a crash without a reboot, wait until $LOCK is $((STALE_S / 60)) min old)"
    exit 1
  fi
fi
[ -f "$MATLAB" ] || { say "MATLAB not found at $MATLAB; not started"; exit 1; }
[ -f "$R/code_commit.txt" ] || { say "$R/code_commit.txt missing; not started"; exit 1; }
for g in p1 p3 p2; do
  w=$(wt "$g")
  [ "$g" = p2 ] && [ ! -d "$w" ] && continue
  [ -d "$w" ] || { say "worktree $w missing; not started"; exit 1; }
  b=$(git -C "$w" symbolic-ref --short -q HEAD)
  [ "$b" = "$(br "$g")" ] || { say "$w is on '$b', not $(br "$g"); not started"; exit 1; }
done
{ cat "/proc/$$/winpid" 2>/dev/null || echo "$$"; date '+%Y-%m-%d %H:%M:%S'; } > "$LOCK"
[ -f "$R/run.lock" ] || echo "$(cat "/proc/$$/winpid" 2>/dev/null || echo "$$")" > "$R/run.lock"
trap 'rm -f "$LOCK"' EXIT
hb
( while kill -0 $$ 2>/dev/null; do hb; sleep "$HB_S"; done ) &   # heartbeat while this script lives (the tracks beat in their own waits too)
say "v7 takeover started (boot $(date -d @"$BOOT" '+%F %T'), TEMP $tw, poll $POLL s)"
for g in p1 p3 p2; do
  [ -f "$R/$g.log" ] && say "$g: next $(list_of "$g" | cut -d' ' -f$(( $(next_idx "$g") + 1 ))) (index $(next_idx "$g")); $(cur_part "$g" | head -1)"
done

# Tracks
track_p1 & T1=$!
track_run p3 & T3=$!
track_p2 & T2=$!
alive() { local p; for p in "$T1" "$T3" "$T2"; do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }
while alive; do turn_check; nap "$POLL"; done
wait "$T1" "$T3" "$T2"
say "tracks ended"
final_phase
say "v7 done"
