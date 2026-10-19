#!/usr/bin/env bash
# Tests of v7_d91_takeover.sh on sandbox copies of the logs and worktrees, with a stub MATLAB
# (d91_stub_matlab.sh) and stub machine queries (d91_stub_sys.sh). Nothing outside the sandbox is
# written: p1.log, p3.log and code_commit.txt are copied once from the live logs as the starting
# state (profile 1 inside C1p, profile 3 idle at C1p after the fix script), and every V7T_*
# variable points the takeover into the sandbox.
#
#   bash d91_takeover_test.sh [sandbox dir] [scenario ...]
# Scenarios: rename status normal p1crash rerun rerunver accept rerungate reboot oldlaunch p1gone
# p1wait p1orphan orphan mainkill slowexec win64 webui mlquery zombie turn unknown unread nolog mlstub watchdog
# mainstall overwrite forcegate c1phold p2gate refuse (default: all). oldlaunch runs a copy of v7_d86_launch.sh (as old_launcher_copy.sh, so that no
# process scan takes it for the launcher) in the sandbox, with its PowerShell queries replaced by a
# function and every V7L_* variable in the sandbox.
HERE=$(cd "$(dirname "$0")" && pwd)
TK="$HERE/v7_d91_takeover.sh"
SB=${1:-"/c/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/d91_takeover_test"}
shift 2>/dev/null
SCEN=("$@"); [ "${#SCEN[@]}" -gt 0 ] || SCEN=(rename status normal p1crash rerun rerunver accept rerungate reboot oldlaunch p1gone p1wait p1orphan orphan mainkill slowexec win64 webui mlquery zombie turn unknown unread nolog mlstub watchdog mainstall overwrite forcegate c1phold p2gate refuse)
OLD_SCRIPTS=(v7_d86_launch.sh v7_d87_p3fix.sh v7_d87_redo.sh v7_d87_resume.ps1 v7_d83_launch.sh v7_fix_resume.sh
             v7_d87_b3m.sh v7_wait_c1p_then_fix.sh v7_guard_c1p_fail.sh)
LIVE_LOGS="/c/Users/Adi Suliman/uav-gcs-logs"
LIVE_REPO="/c/Users/Adi Suliman/uav-gcs-adaptive-secure-comms"
case "$(cygpath -m "$SB")" in
  *uav-gcs-logs*|*uav-gcs-v7*|*uav-gcs-b3m*) echo "sandbox $SB points at a live folder; refused"; exit 1;;
esac
PASS=0; FAIL=0; FAILS=()
ok()  { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad() { FAIL=$((FAIL + 1)); FAILS+=("$CUR: $*"); echo "  FAIL $*"; }
check() { local m=$1; shift; if "$@"; then ok "$m"; else bad "$m"; fi; }
has()   { grep -q -- "$2" "$1" 2>/dev/null; }
until_t() {   # until_t <seconds> <command...>: poll the condition (deadline times SLOW_X for a loaded machine)
  local end=$(( $(date +%s) + $1 * ${SLOW_X:-3} )); shift
  until "$@"; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 0.3; done
}
children() { local d pp; for d in /proc/[0-9]*; do read -r pp 2>/dev/null < "$d/ppid" && [ "$pp" = "$1" ] && echo "${d#/proc/}"; done; }
kill_tree() {   # the process and its descendants (stopped first, so none is reparented on the way)
  local p=$1 c
  kill -STOP "$p" 2>/dev/null
  for c in $(children "$p"); do kill_tree "$c"; done
  kill -9 "$p" 2>/dev/null
}
sandbox_left() {   # takeover and stub processes of the current sandbox still alive
  local d
  for d in /proc/[0-9]*; do
    tr '\0' '\n' 2>/dev/null < "$d/environ" | grep -qx "V7T_LOGS=$S/logs" || continue
    tr '\0' ' ' 2>/dev/null < "$d/cmdline" | grep -q 'v7_d91_takeover\|d91_stub' && echo "${d#/proc/}"
  done
}
tk_procs() {   # takeover bash processes of the current sandbox
  local d
  for d in /proc/[0-9]*; do
    tr '\0' '\n' 2>/dev/null < "$d/environ" | grep -qx "V7T_LOGS=$S/logs" || continue
    tr '\0' ' ' 2>/dev/null < "$d/cmdline" | grep -q 'v7_d91_takeover' && echo "${d#/proc/}"
  done
}
no_tk() { [ -z "$(tk_procs)" ]; }
hung_left() { local p; for p in $(cat "$S/sys/hung" 2>/dev/null); do kill -0 "$p" 2>/dev/null && echo "$p"; done; }   # hanging stub queries still alive
ns_of() { grep " $2 $3 $4\$" "$1/ctl/calls.log" 2>/dev/null | head -1 | cut -d' ' -f1; }   # first "<worktree> <event> <stage>"
alerted() { ls "$RD"/ALERT_"$1"*.txt >/dev/null 2>&1; }
lt() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; }

# Starting state, copied once
mkdir -p "$SB/source" || exit 1
for f in p1.log p3.log code_commit.txt; do cp -p "$LIVE_LOGS/v7_d86/$f" "$SB/source/$f" || exit 1; done
f="$LIVE_LOGS/v7_d86_launch.sh"; [ -f "$f" ] || f="$f.retired_by_d91"   # renamed by a live takeover
cp -p "$f" "$SB/source/old_launcher_copy.sh" || exit 1
P1_STAMP=$(grep '^##### PART ' "$SB/source/p1.log" | tail -1 | awk '{print $3}')
P1_SE=$(date -d "${P1_STAMP:0:8} ${P1_STAMP:9:2}:${P1_STAMP:11:2}:${P1_STAMP:13:2}" +%s)   # start of profile 1's launcher part
LCMD='"C:\Program Files\Git\usr\bin\bash.exe" "/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.sh" 9b5c9f1beec4bef1ceadaa18068239c36d82c77a resume'
git -C "$LIVE_REPO" show 9b5c9f1:code/run_stage.m | \
  sed "s/'B3m', 'build_fresh_test2', /'B3m', 'build_fresh_test2', 'B3q', 'build_fresh_test3', 'B3r', 'read_fresh_test3', /" > "$SB/source/run_stage.m"
grep -q "'B3q', 'build_fresh_test3'" "$SB/source/run_stage.m" || { echo "run_stage.m stand-in not built"; exit 1; }

setup() {   # fresh sandbox $SB/$1: logs, git repository with v7-dev and v7-p3 worktrees, origin, stubs
  CUR=$1; S="$SB/$1"; RD="$S/logs/v7_d86"
  echo "== $1"
  rm -rf "$S"; mkdir -p "$RD" "$S/temp" "$S/sys/procs" "$S/sys/created" "$S/sys/children" "$S/sys/kids" "$S/sys/state" "$S/ctl"
  cp -p "$SB/source/p1.log" "$SB/source/p3.log" "$SB/source/code_commit.txt" "$RD/"
  for f in "${OLD_SCRIPTS[@]}"; do echo "# stand-in of the old run script $f" > "$S/logs/$f"; done
  echo $(( $(date +%s) - 86400 )) > "$S/sys/boot"; echo 5 > "$S/sys/cpu"; echo 70 > "$S/sys/headroom"; : > "$S/sys/matlab"
  : > "$S/sys/scripts"
  : > "$S/ctl/calls.log"
  ( set -e
    git init -q -b main "$S/repo"; cd "$S/repo"; git config core.autocrlf false
    mkdir code; cp "$SB/source/run_stage.m" code/; echo "% startup" > startup.m; echo "test" > README.md
    git add -A; git commit -q -m base
    git branch v7-dev; git checkout -q -b v7-p3
    echo '{"profile":"profile 3: four antennas","n_rx":4}' > profile.json; git add profile.json; git commit -q -m p3
    git checkout -q main
    git init -q --bare "$S/origin.git"; git -C "$S/origin.git" config core.longpaths true; git remote add origin "$S/origin.git"; git push -q origin v7-dev v7-p3
    git worktree add -q "$S/uav-gcs-v7" v7-dev; git worktree add -q "$S/uav-gcs-v7-p3" v7-p3 ) || { bad "sandbox repository"; return 1; }
  export V7T_P1="$S/uav-gcs-v7" V7T_P3="$S/uav-gcs-v7-p3" V7T_P2="$S/uav-gcs-v7-p2" V7T_REPO="$S/repo" V7T_LOGS="$S/logs"
  export V7T_MATLAB="$HERE/d91_stub_matlab.sh" V7T_SYS="$HERE/d91_stub_sys.sh" V7T_SYS_DIR="$S/sys" STUB_CTL="$S/ctl"
  export TEMP; TEMP=$(cygpath -w "$S/temp"); export V7T_TEMP_WIN="$TEMP"
  export V7T_POLL=1 V7T_STEP=0.2 V7T_HB_S=1 V7T_QUIET_S=2 V7T_IDLE_POLL=1 V7T_IDLE_MAX_S=30 V7T_STALE_S=30 \
         V7T_SILENT_S=100000 V7T_HEADROOM_ALERT_S=5 V7T_BOOT_RETRY_S=0.1 V7T_QRETRY_S=1 V7T_ML_PID_WAIT_S=60 STUB_DELAY=0.05 \
         V7T_Q_TIMEOUT_S=30 V7T_UNKNOWN_ALERT_S=3600 V7T_STALL_S=60
  unset V7T_ALLOW_PIDS
  [ "$V7T_LOGS" != "$LIVE_LOGS" ] && [ "$V7T_P1" != "/c/Users/Adi Suliman/uav-gcs-v7" ] || { echo "not a sandbox; stopped"; exit 1; }
}
tk_start() { bash "${TKRUN:-$TK}" 24172 49732 >> "$S/takeover.log" 2>&1 & TKP=$!; disown "$TKP"; }   # TKRUN: a copy of the script
tk_wait()  { until_t "${1:-240}" bash -c "! kill -0 $TKP 2>/dev/null"; }
tk_kill()  {
  local p
  kill_tree "$TKP"; sleep 0.5
  p=$(sandbox_left | tr '\n' ' '); [ -z "$p" ] || { bad "processes left after the kill: $p"; kill -9 $p 2>/dev/null; }
}
reboot()   {   # every process of the run gone, a boot time after every file
  [ -n "${FAKE:-}" ] && kill_tree "$FAKE"; FAKE=""; tk_kill
  sleep 0.5; rm -rf "$S/ctl"/busy_*
  echo $(( $(date +%s) + 1 )) > "$S/sys/boot"; sleep 2
}
# Profile 1's chain as the launcher's subshell writes it: C1p (open in the copied log) to RPT.
# FAIL_AT: the chain ends rc=1 inside that stage; HOLD_AT: list of stages it waits before, each
# for ctl/p1_release_<stage>; ctl/p1_<stage>_at: when the stage was done
p1_fake() {
  local log="$RD/p1.log" s
  ( echo "##### STAGE C1p done in 1.0 min #####" >> "$log"; date +%s%N > "$S/ctl/p1_C1p_at"
    for s in C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT; do
      if [[ " ${HOLD_AT:-} " == *" $s "* ]]; then until [ -f "$S/ctl/p1_release_$s" ]; do sleep 0.2; done; fi
      echo "##### STAGE $s (fake) $(date) #####" >> "$log"; sleep "${D:-0.2}"
      if [ "$s" = "${FAIL_AT:-}" ]; then echo "Error (fake)" >> "$log"; echo "##### chain ended rc=1 $(date) #####" >> "$log"; exit 0; fi
      echo "##### STAGE $s done in 0.0 min #####" >> "$log"
      date +%s%N > "$S/ctl/p1_${s}_at"
      [ "$s" = SURV3 ] && date +%s%N > "$S/ctl/p1_surv3_at"
    done
    date +%s%N > "$S/ctl/p1_end_at"
    echo "##### chain ended rc=0 $(date) #####" >> "$log" ) &
  FAKE=$!; disown "$FAKE"
}
final_ok() {   # profile $1 finished: a final part with LAT to RPT and the bundle
  local part
  part=$(awk '/^##### PART /{p=""} {p = p $0 "\n"} END {printf "%s", p}' "$RD/$1.log")
  grep -q '^##### PART .* takeover-final ' <<< "$part" && grep -q 'STAGE RPT done' <<< "$part" && \
    grep -q 'STAGE LAT done' <<< "$part" && grep -q '^##### STAGE BUNDLE done' <<< "$part"
}

t_status() {
  setup status || return
  local before after out
  before=$(cd "$S" && find logs -type f -exec md5sum {} + | sort)
  out=$(bash "$TK" 24172 49732 status 2>&1)
  after=$(cd "$S" && find logs -type f -exec md5sum {} + | sort)
  echo "$out" | sed 's/^/     | /'
  check "status changes no file" [ "$before" = "$after" ]
  check "status: p1 at C1p (index 13) in the launcher's part" grep -q 'next C1p (index 13)' <<< "$(grep -A1 '^p1:' <<< "$out")"
  check "status: p3 at C1p (index 13), its part idle" grep -q 'next C1p (index 13).*idle part: yes' <<< "$(grep -A1 '^p3:' <<< "$out")"
  check "status: p1's part not idle (its chain runs)" grep -q 'idle part: no' <<< "$(grep -A1 '^p1:' <<< "$out")"
  check "status: no takeover.lock written" [ ! -f "$RD/takeover.lock" ]
}

t_normal() {
  setup normal || return
  echo "B3q" > "$RD/p2_set4.stages"
  touch -d '-1 hour' "$RD/run.lock"
  tk_start
  until_t 30 test -f "$RD/takeover.lock"
  check "takeover.lock written" [ -f "$RD/takeover.lock" ]
  until_t 40 bash -c "[ \$(( \$(date +%s) - \$(stat -c %Y '$RD/run.lock') )) -lt 5 ]"
  ( while kill -0 "$TKP" 2>/dev/null; do echo $(( $(date +%s) - $(stat -c %Y "$RD/run.lock") )) >> "$S/hb_ages"; sleep 0.5; done ) &
  sleep 3
  check "p3 waits: no MATLAB before profile 1's SURV3" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  D=0.3 p1_fake
  tk_wait 240 || bad "takeover did not end in time"
  local a b
  check "v7 done" has "$S/takeover.log" 'v7 done'
  check "p3: C part header in the launcher's format" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 13 C1p A0 0 #####$' "$RD/p3.log"
  a=$(cat "$S/ctl/p1_surv3_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's SURV3" lt "$a" "$b"
  check "p2: worktree on v7-p2" [ "$(git -C "$S/uav-gcs-v7-p2" symbolic-ref --short HEAD 2>/dev/null)" = v7-p2 ]
  check "p2: profile.json n_rx 2 committed" bash -c "git -C '$S/uav-gcs-v7-p2' show HEAD:profile.json | grep -q '\"n_rx\":2'"
  check "p2: v7-p2 pushed" git -C "$S/origin.git" show-ref -q --verify refs/heads/v7-p2
  check "p2: commit in code_commit.txt" grep -q '^p2 v7-p2 [0-9a-f]* ' "$RD/code_commit.txt"
  check "p2: B stages with B3m and the set-4 build" grep -q ' AB A0,A4v,A5,A6,B1,B2,B2F,B3n,B3m,B3q,B3,B3a,B4,OOD,B4s ' "$RD/p2.log"
  a=$(cat "$S/ctl/p1_end_at"); b=$(ns_of "$S" uav-gcs-v7-p2 start A0)
  check "p2 starts after profile 1's chain ended" lt "$a" "$b"
  a=$(ns_of "$S" uav-gcs-v7-p3 done SURV3); b=$(ns_of "$S" uav-gcs-v7-p2 start C1p)
  check "p2's C1p after p3's SURV3" lt "$a" "$b"
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "final: idle machine" grep -q 'machine before LAT: .*(idle)' "$RD/p1.log"
  check "status: every profile at the end" bash -c "[ \$(bash '$TK' 24172 49732 status | grep -c 'next end') = 3 ]"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  a=$(sort -n "$S/hb_ages" | tail -1)
  check "run.lock heartbeat (every 1 s in the test; oldest seen ${a:-?} s, at most 15 under the live run's load)" [ "${a:-99}" -le 15 ]
  check "takeover.lock removed at the end" [ ! -f "$RD/takeover.lock" ]
  check "no alert" bash -c "! ls '$RD'/ALERT_*.txt >/dev/null 2>&1"
  check "code_commit.txt: SRC line retired, nothing else changed in it" bash -c "diff <(sed 's/^SRC_RETIRED_BY_D91 /SRC /' '$RD/code_commit.txt' | grep -v ' takeover: ') '$SB/source/code_commit.txt'"
  check "code_commit.txt backup and retired SHA kept" bash -c "cmp -s '$RD'/code_commit_before_d91_*.txt '$SB/source/code_commit.txt' && grep -q \"^retired SRC \$(sed -n 's/^SRC //p' '$SB/source/code_commit.txt') \" '$RD/retired_src.txt'"
  check "no MATLAB option but the rerun's" bash -c "! grep -q ' opts ' '$S/ctl/calls.log'"
  for f in "${OLD_SCRIPTS[@]}"; do
    check "$f renamed at the start, logged before 'v7 takeover started'" bash -c "[ ! -e '$S/logs/$f' ] && [ -f '$S/logs/$f.retired_by_d91' ] && \
      [ \$(grep -n '$f renamed to $f.retired_by_d91 (old run script)' '$S/takeover.log' | head -1 | cut -d: -f1) -lt \$(grep -n 'v7 takeover started' '$S/takeover.log' | head -1 | cut -d: -f1) ]"
  done
  check "the tracks' end files written, PIDs recorded" bash -c "ls '$RD'/takeover_end_p1 '$RD'/takeover_end_p3 '$RD'/takeover_end_p2 >/dev/null && [ \$(grep -c '^p[123] [0-9]' '$RD/takeover_tracks.txt') = 3 ]"
}

t_p1crash() {
  setup p1crash || return
  echo "B3z" > "$RD/p2_set4.stages"
  tk_start; sleep 2
  FAIL_AT=C1c D=0.2 p1_fake
  until_t 40 alerted p1_failed; check "alert on profile 1's failure" alerted p1_failed
  sleep 3
  check "p3 does not start C1p" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  check "p2 not started" [ ! -d "$S/uav-gcs-v7-p2" ]
  check "no MATLAB for profile 1 without a go file" bash -c "! grep -q 'uav-gcs-v7 call' '$S/ctl/calls.log'"
  touch -d '-10 min' "$RD/p1_resume.go"
  until_t 40 alerted stale_p1_resume.go; check "alert on the old go file" alerted stale_p1_resume.go
  check "an old go file is not taken" [ -f "$RD/p1_resume.go" ]
  rm -f "$RD/p1_resume.go"; sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 40 grep -q 'takeover SRC [0-9a-f]* FROM 14 C1c A0 0 ' "$RD/p1.log"
  check "profile 1 goes on from C1c under a new part" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 14 C1c A0 0 #####$' "$RD/p1.log"
  check "the go file is renamed" bash -c "ls '$RD'/p1_resume.go.used_* >/dev/null 2>&1 && [ ! -f '$RD/p1_resume.go' ]"
  until_t 40 grep -q "uav-gcs-v7 call run_stage('C1c','SURV','SURV3'" "$S/ctl/calls.log"
  check "profile 1's MATLAB: C1c to RPT" grep -q "uav-gcs-v7 call run_stage('C1c','SURV','SURV3'" "$S/ctl/calls.log"
  until_t 30 alerted p2_set4_invalid; check "alert on a wrong set-4 stage" alerted p2_set4_invalid
  check "p2 waits on it" bash -c "! grep -q 'uav-gcs-v7-p2 call' '$S/ctl/calls.log'"
  sleep 1.1; echo "B3q B3r" > "$RD/p2_set4.stages"
  until_t 30 bash -c "grep -lq 'names B3r' '$RD'/ALERT_p2_set4_invalid_*.txt"
  check "B3r refused in the chain (the reading runs by hand after the go/no-go)" bash -c "grep -lq 'names B3r' '$RD'/ALERT_p2_set4_invalid_*.txt && ! grep -q 'uav-gcs-v7-p2 call' '$S/ctl/calls.log'"
  rm -f "$RD/p2_set4.stages"
  tk_wait 240 || bad "takeover did not end in time"
  local a b
  a=$(ns_of "$S" uav-gcs-v7 done SURV3); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's resumed SURV3" lt "$a" "$b"
  check "p2: B stages without set 4" grep -q ' AB A0,A4v,A5,A6,B1,B2,B2F,B3n,B3m,B3,B3a,B4,OOD,B4s ' "$RD/p2.log"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_rerun() {
  setup rerun || return
  tk_start; HOLD_AT=SURV D=0.2 p1_fake; sleep 3
  echo "B2F C1p" > "$RD/p3_brerun.go"
  until_t 40 alerted p3_rerun_invalid; check "alert on a C stage in the go file" alerted p3_rerun_invalid
  check "nothing run on it" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  local x
  for x in B3m B3q B3r; do   # stages of run_stage.m, but test-set stages
    sleep 1.1; echo "B2F $x" > "$RD/p3_brerun.go"
    until_t 40 bash -c "grep -lq \"names '$x', a test-set stage\" '$RD'/ALERT_p3_rerun_invalid_*.txt"
    check "$x in the go file: refused, the alert naming d91_set4.md step 4" bash -c "grep -h \"names '$x', a test-set stage\" '$RD'/ALERT_p3_rerun_invalid_*.txt | grep -q 'd91_set4.md step 4'"
  done
  check "nothing run on the test-set stages" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  touch "$S/ctl/fail_uav-gcs-v7-p3_B4"; sleep 1.1
  echo "B2F B3 B3a B4 OOD B4s" > "$RD/p3_brerun.go"
  until_t 40 grep -q '^##### rerun ended rc=1' "$RD/p3.log"
  check "rerun part: A0 first, its list and request id" grep -q '^##### PART [0-9_]* takeover-rerun SRC [0-9a-f]* FROM 6 B2F A0 1 RERUN B2F,B3,B3a,B4,OOD,B4s GO [0-9a-f]* #####$' "$RD/p3.log"
  check "rerun MATLAB call" grep -q "uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B3a','B4','OOD','B4s')" "$S/ctl/calls.log"
  check "rerun failure recorded" grep -q '^##### rerun ended rc=1' "$RD/p3.log"
  until_t 40 alerted p3_rerun_failed; check "alert on the failed rerun" alerted p3_rerun_failed
  touch "$S/ctl/p1_release_SURV"; until_t 40 test -f "$S/ctl/p1_surv3_at"; sleep 4
  check "after a failed rerun C1p does not start" bash -c "! grep -q 'FROM 13 C1p' '$RD/p3.log'"
  sleep 1.1; touch "$RD/p3_brerun.go"
  until_t 40 grep -q '^##### rerun ended rc=0' "$RD/p3.log"
  check "a new version of the go file reruns its whole list" [ "$(grep -c "uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B3a','B4','OOD','B4s')" "$S/ctl/calls.log")" = 2 ]
  touch "$S/ctl/fail_uav-gcs-v7-p3_C1p"
  until_t 40 alerted p3_failed; check "alert on P3's failed C1p" alerted p3_failed
  check "C part after the rerun" bash -c "[ \$(grep -n 'rerun ended rc=0' '$RD/p3.log' | tail -1 | cut -d: -f1) -lt \$(grep -n 'FROM 13 C1p A0 0' '$RD/p3.log' | tail -1 | cut -d: -f1) ]"
  sleep 1.1; echo "B3" > "$RD/p3_brerun.go"; sleep 1.1; echo go > "$RD/p3_resume.go"
  until_t 40 alerted p3_go_ignored; check "a go file after C1p started is ignored" alerted p3_go_ignored
  tk_wait 240 || bad "takeover did not end in time"
  check "no rerun after C1p started" [ "$(grep -c 'takeover-rerun' "$RD/p3.log")" = 2 ]
  check "p3 resumed C1p after its failure" [ "$(grep -c 'FROM 13 C1p A0 0' "$RD/p3.log")" = 2 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_rerungate() {   # P3's rerun: not while profile 1 is in C1p..C1c, its own memory gate, one thread
  setup rerungate || return
  local a b
  echo "B2F B3 B3a B4 B4s" > "$RD/p3_brerun.go"
  tk_start; until_t 30 test -f "$RD/takeover.lock"
  until_t 60 grep -q 'p3: B-stage rerun waits until profile 1 is past C1c' "$S/takeover.log"
  check "the wait is logged" grep -q 'p3: B-stage rerun waits until profile 1 is past C1c' "$S/takeover.log"
  sleep 5
  check "no rerun while profile 1's C1p is open" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  echo 50 > "$S/sys/headroom"
  HOLD_AT="C1c SURV" D=0.2 p1_fake
  until_t 40 test -f "$S/ctl/p1_C1p_at"; sleep 15
  check "no rerun after C1p, before C1c" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  touch "$S/ctl/p1_release_C1c"
  until_t 40 grep -q 'p3: free commit 50 GB < 65 GB; waiting' "$S/takeover.log"
  check "after C1c: the rerun waits for 65 GB (50 free; the chains' gate is 45)" grep -q 'p3: free commit 50 GB < 65 GB; waiting' "$S/takeover.log"
  check "no rerun below its memory gate" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  echo 70 > "$S/sys/headroom"
  until_t 40 grep -q '^##### rerun ended rc=0' "$RD/p3.log"
  a=$(cat "$S/ctl/p1_C1c_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start A0)
  check "the rerun starts after profile 1's C1c" lt "$a" "$b"
  check "rerun MATLAB call" grep -q "uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B3a','B4','B4s')" "$S/ctl/calls.log"
  check "the rerun alone runs on one computational thread" bash -c "[ \"\$(grep ' opts ' '$S/ctl/calls.log' | cut -d' ' -f2-)\" = 'uav-gcs-v7-p3 opts -singleCompThread' ]"
  touch "$S/ctl/p1_release_SURV"
  tk_wait 240 || bad "takeover did not end in time"
  a=$(cat "$S/ctl/p1_surv3_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's SURV3" lt "$a" "$b"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"

  setup rerungate2 || return   # profile 1 given up while its launcher chain is between C1p and C1c
  local t
  echo "B2F B3" > "$RD/p3_brerun.go"
  tk_start; FAIL_AT=C1c HOLD_AT=C1c D=0.2 p1_fake
  until_t 40 test -f "$S/ctl/p1_C1p_at"
  until_t 60 grep -q 'p3: B-stage rerun waits until profile 1 is past C1c' "$S/takeover.log"
  touch "$RD/p1.abandon"
  until_t 60 grep -q 'p1: track ended (p1.abandon)' "$S/takeover.log"; sleep 15   # many polls (1 s each)
  check "p1.abandon while its chain is between C1p and C1c: no rerun" bash -c "grep -q 'p1: track ended (p1.abandon)' '$S/takeover.log' && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  t=$(date +%s%N); touch "$S/ctl/p1_release_C1c"
  until_t 60 grep -q 'uav-gcs-v7-p3 start A0' "$S/ctl/calls.log"
  b=$(ns_of "$S" uav-gcs-v7-p3 start A0)
  check "the rerun once profile 1's chain has ended" bash -c "[ -n '$b' ] && [ '$t' -lt '$b' ] && grep -q '^##### chain ended rc=1' '$RD/p1.log'"
  tk_kill
}

t_reboot() {
  setup reboot || return
  mkdir -p "$S/uav-gcs-v7-p3/data"; echo partial > "$S/uav-gcs-v7-p3/data/policy_pools.mat"
  tk_start; HOLD_AT=SURV D=0.2 p1_fake; until_t 30 test -f "$RD/takeover.lock"; sleep 2
  local out
  out=$(timeout 150 bash "$TK" 24172 49732 2>&1); echo "$out" | sed 's/^/     | /'
  check "a second takeover refuses while the first is alive" grep -q 'is alive .* not started' <<< "$out"
  reboot
  tk_start
  until_t 40 alerted p1_cut; check "alert: profile 1 cut by the reboot" alerted p1_cut
  check "the takeover started again after the reboot" [ "$(grep -c 'v7 takeover started' "$S/takeover.log")" = 2 ]
  sleep 2
  check "p3 still waits" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  echo 20 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 30 grep -q 'p1: chain ended rc=0' "$S/takeover.log"
  check "profile 1 resumed from SURV" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 15 SURV A0 0 #####$' "$RD/p1.log"
  until_t 30 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  check "p3's readable pools kept before C1p" grep -q 'p3: data/policy_pools.mat readable, kept' "$S/takeover.log"
  sleep 1
  touch "$S/ctl/fail_whos"
  reboot
  tk_start
  tk_wait 240 || bad "takeover did not end in time"
  check "p3 went on at C1p under a second C part" [ "$(grep -c 'FROM 13 C1p A0 0' "$RD/p3.log")" = 2 ]
  check "unreadable pools moved aside on the resume" bash -c "ls '$S/uav-gcs-v7-p3/data'/policy_pools_partial_*.mat >/dev/null 2>&1"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

lpowershell() { case "$*" in *LastBootUpTime*) cat "$V7T_SYS_DIR/boot";; esac; }
launcher() {   # the launcher's copy in the sandbox, in the background (LP), output to $1
  local out=$1; shift
  [ "$V7T_LOGS" = "$S/logs" ] && [ "$V7T_P1" = "$S/uav-gcs-v7" ] || { echo "not a sandbox; stopped"; exit 1; }
  ( powershell.exe() { lpowershell "$@"; }
    export -f powershell.exe lpowershell
    export V7L_P1="$V7T_P1" V7L_P3="$V7T_P3" V7L_P2="$V7T_P2" V7L_LOGS="$V7T_LOGS" V7L_MATLAB="$V7T_MATLAB" \
           V7L_TEMP="$S/temp" V7L_POLL=1 V7L_STEP=0.2
    exec bash "$SB/source/old_launcher_copy.sh" "$@" ) > "$out" 2>&1 &
  LP=$!
}
t_oldlaunch() {   # the old launcher's resume after a reboot refuses on the retired SRC; old scripts alert
  local sha out rc n1 n3
  setup olctl || return
  sha=$(git -C "$S/uav-gcs-v7" rev-parse HEAD)
  sed -i "s/^SRC .*/SRC $sha/" "$RD/code_commit.txt"
  launcher "$S/launcher.out" "$sha" resume
  until_t 60 grep -q 'resume: code equal to\|not resumed\|not started' "$S/launcher.out"
  disown "$LP" 2>/dev/null; kill_tree "$LP"; sleep 0.5
  sed 's/^/     | /' "$S/launcher.out" | head -5
  check "control: with its SRC line intact the launcher's resume passes after a reboot" grep -q "resume: code equal to $sha" "$S/launcher.out"

  setup oldlaunch || return
  sha=$(git -C "$S/uav-gcs-v7" rev-parse HEAD)
  sed -i "s/^SRC .*/SRC $sha/" "$RD/code_commit.txt"
  echo $(( P1_SE - 3600 )) > "$S/sys/boot"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 8))|$LCMD" > "$S/sys/scripts"
  export V7T_ALLOW_PIDS="43428 43972"
  tk_start; until_t 30 grep -q 'v7 takeover started' "$S/takeover.log"
  check "starts beside profile 1's allowed chain subshells" grep -q 'v7 takeover started.*allowed launcher subshells: 43428 43972' "$S/takeover.log"
  check "SRC line retired" bash -c "grep -qx 'SRC_RETIRED_BY_D91 $sha' '$RD/code_commit.txt' && ! grep -q '^SRC ' '$RD/code_commit.txt'"
  check "backup keeps the SRC line; the SHA recorded" bash -c "grep -qx 'SRC $sha' '$RD'/code_commit_before_d91_*.txt && grep -q '^retired SRC $sha ' '$RD/retired_src.txt'"
  echo "51111|$(date +%s)|$LCMD" >> "$S/sys/scripts"
  until_t 40 alerted old_script_51111; check "alert: a launcher under a new PID while the takeover runs" alerted old_script_51111
  check "no alert for the allowed subshells" bash -c "! ls '$RD'/ALERT_old_script_434*.txt '$RD'/ALERT_old_script_439*.txt >/dev/null 2>&1"
  reboot; : > "$S/sys/scripts"
  n1=$(grep -c '^##### PART' "$RD/p1.log"); n3=$(grep -c '^##### PART' "$RD/p3.log")
  launcher "$S/launcher.out" "$sha" resume
  until_t 60 bash -c "! kill -0 $LP 2>/dev/null" || { bad "the launcher's resume still runs"; kill_tree "$LP"; }
  wait "$LP"; rc=$?
  sed 's/^/     | /' "$S/launcher.out" | head -5
  check "after the reboot the launcher's resume refuses on the retired SRC (exit $rc)" bash -c "[ $rc = 1 ] && grep -q 'the run was launched on , not $sha; not resumed' '$S/launcher.out'"
  check "it wrote no part" [ "$(grep -c '^##### PART' "$RD/p1.log") $(grep -c '^##### PART' "$RD/p3.log")" = "$n1 $n3" ]
  echo "43428|$(date +%s)|$LCMD" > "$S/sys/scripts"
  out=$(timeout 150 bash "$TK" 24172 49732 2>&1); echo "$out" | sed 's/^/     | /'
  check "an allowed PID reused after the reboot: refused" grep -q 'outside V7T_ALLOW_PIDS.*43428|.*not started' <<< "$out"
  : > "$S/sys/scripts"
  tk_start; until_t 30 bash -c "[ \$(grep -c 'v7 takeover started' '$S/takeover.log') = 2 ]"
  check "the takeover starts again" [ "$(grep -c 'v7 takeover started' "$S/takeover.log")" = 2 ]
  until_t 40 test -f "$RD/run.lock"; check "run.lock back (the refused launcher removed it)" test -f "$RD/run.lock"
  check "SRC stays retired, one backup" bash -c "[ \$(ls '$RD'/code_commit_before_d91_*.txt | wc -l) = 1 ] && grep -qx 'SRC_RETIRED_BY_D91 $sha' '$RD/code_commit.txt'"
  tk_kill
  unset V7T_ALLOW_PIDS
}

t_zombie() {
  setup zombie || return
  local s t_free b
  { echo "##### STAGE C1p done in 1.0 min #####"
    for s in C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT; do echo "##### STAGE $s (x) #####"; echo "##### STAGE $s done in 0.0 min #####"; done
    echo "##### chain ended rc=0 $(date) #####"; } >> "$RD/p1.log"
  { echo "##### PART 20261023_100000 takeover SRC abc FROM 13 C1p A0 0 #####"
    for s in C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT; do echo "##### STAGE $s (x) #####"; echo "##### STAGE $s done in 0.0 min #####"; done
  } >> "$RD/p3.log"
  touch "$RD/p2.abandon"
  local M='"C:\Program Files\MATLAB\R2026a\bin\win64\MATLAB.exe" "-batch"'
  printf '%s\n' "32824|1|$M \"run('C:/x/run_chunk.m')\"" "55555|1|$M \"run_stage('C1p')\"" \
    "77777|0|$M \"run_stage('smoke','C1p')\"" "77778|0|$M \"run_stage('A0','B3m')\"" "77779|0|$M \"run_stage('A0','B3q')\"" \
    "77780|0|\"C:\Program Files\MATLAB\R2026a\bin\win64\MATLAB.exe\" \"-singleCompThread\" \"-batch\" \"set4_build\" " \
    "66666|0|$M \"run_stage('KPI')\"" \
    "88888|0|$M \"run_stage('A0','A4v','A5','A6','B1','B2','B2F','B3n','B3m','B3q','B3r','B3','B3a','B4','OOD','B4s')\"" > "$S/sys/matlab"
  echo 50 > "$S/sys/cpu"
  tk_start; sleep 4
  check "a live pipeline MATLAB holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  grep -v 66666 "$S/sys/matlab" > "$S/sys/m2"; mv "$S/sys/m2" "$S/sys/matlab"; echo 5 > "$S/sys/cpu"; sleep 3
  check "profile 2's own chain (with B3m, B3q, B3r) holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  grep -v 88888 "$S/sys/matlab" > "$S/sys/m2"; mv "$S/sys/m2" "$S/sys/matlab"; echo 50 > "$S/sys/cpu"; sleep 3
  check "CPU at 50 % holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  touch "$S/sys/fail_matlab"; echo 5 > "$S/sys/cpu"; sleep 3
  check "a failed MATLAB query holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  t_free=$(date +%s%N); rm -f "$S/sys/fail_matlab"
  tk_wait 120 || bad "takeover did not end in time"
  b=$(ns_of "$S" uav-gcs-v7 start LAT)
  check "LAT once idle (zombie, exited stage session, smoke and the copies' exact commands not counted)" lt "$t_free" "$b"
  check "machine line: idle, no pipeline session, four other live sessions" grep -q 'live pipeline MATLAB sessions: 0, live MATLAB processes in all: 4 (idle)' "$RD/p1.log"
  check "profile 2 given up: no LAT" has "$S/takeover.log" 'p2 given up: no LAT'
  for g in p1 p3; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "p3 stopped after RPT before its end marker: marker written, no MATLAB" bash -c "grep -q 'chain ended rc=0 (its stages were done before an interruption)' '$RD/p3.log' && ! grep -q 'uav-gcs-v7-p3 call run_stage()' '$S/ctl/calls.log'"
}

t_orphan() {   # the takeover's bash processes killed while its MATLAB runs on: no second MATLAB there
  setup orphan || return
  export V7T_STALE_S=5
  echo 150 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  local d p
  for d in /proc/[0-9]*; do
    tr '\0' '\n' 2>/dev/null < "$d/environ" | grep -qx "V7T_LOGS=$S/logs" || continue
    tr '\0' ' ' 2>/dev/null < "$d/cmdline" | grep -q 'v7_d91_takeover' && p+=" ${d#/proc/}"
  done
  kill -9 $p 2>/dev/null; sleep 7
  check "its MATLAB still runs after the kill" test -d "$S/ctl/busy_uav-gcs-v7-p3"
  tk_start
  until_t 120 alerted ml_alive_p3; check "alert: an earlier MATLAB still runs in the worktree" alerted ml_alive_p3
  tk_wait 240 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "its end marker written after the orphan finished" grep -q 'chain ended rc=0 (its stages were done before an interruption)' "$RD/p3.log"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  export V7T_STALE_S=30
}

t_slowexec() {   # MATLAB's exec lags behind the fork: the PID file waits for it, or holds the subshell's PID
  setup slowexec || return
  local pf="$RD/takeover_ml_p3.pid" p op t d
  echo 3 > "$S/sys/exec_delay"; echo 20 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  check "PID file written at the fork: the subshell's PIDs before the exec shows" bash -c "[ \$(wc -l < '$pf') = 2 ] && grep -q '^msys [0-9]' '$pf'"
  until_t 20 bash -c "[ \"\$(wc -l < '$pf' 2>/dev/null)\" = 1 ]"
  op=$(head -1 "$pf" 2>/dev/null); t=$(cat "$S/ctl/start_$op" 2>/dev/null)
  check "exec 3 s late: the PID file then names the MATLAB, rewritten after the exec" bash -c "[ -n '$t' ] && [ \$(stat -c %Y '$pf') -ge \$(( ${t:-0} + 3 )) ] && [ \$(wc -l < '$pf') = 1 ]"
  check "no PID alert" bash -c "! ls '$RD'/ALERT_ml_pid_*.txt >/dev/null 2>&1"
  tk_wait 240 || bad "takeover did not end in time"
  check "v7 done" has "$S/takeover.log" 'v7 done'

  setup slowexec2 || return
  pf="$RD/takeover_ml_p3.pid"
  export V7T_ML_PID_WAIT_S=3 V7T_STALE_S=5
  echo 1000 > "$S/sys/exec_delay"; echo 150 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 40 alerted ml_pid_p3; check "exec not seen within the wait: alert" alerted ml_pid_p3
  check "the PID file holds the subshell's Windows and MSYS PIDs" bash -c "[ \$(wc -l < '$pf') = 2 ] && grep -q '^msys [0-9]' '$pf'"
  p=""
  for d in /proc/[0-9]*; do
    tr '\0' '\n' 2>/dev/null < "$d/environ" | grep -qx "V7T_LOGS=$S/logs" || continue
    tr '\0' ' ' 2>/dev/null < "$d/cmdline" | grep -q 'v7_d91_takeover' && p+=" ${d#/proc/}"
  done
  kill -9 $p 2>/dev/null; sleep 7
  check "its MATLAB still runs after the kill" test -d "$S/ctl/busy_uav-gcs-v7-p3"
  tk_start
  until_t 120 alerted ml_alive_p3; check "the restarted takeover treats the subshell's PID as alive" alerted ml_alive_p3
  tk_wait 240 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  export V7T_ML_PID_WAIT_S=60

  setup slowexec3 || return   # the track killed between the fork and the exec
  pf="$RD/takeover_ml_p3.pid"
  echo 60 > "$S/sys/exec_delay"; echo 150 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  check "inside the exec window the PID file holds the subshell" bash -c "[ \$(wc -l < '$pf') = 2 ]"
  kill -9 $(tk_procs) 2>/dev/null; sleep 5
  check "its MATLAB still runs after the kill" test -d "$S/ctl/busy_uav-gcs-v7-p3"
  tk_start
  until_t 120 alerted ml_alive_p3; check "the restarted takeover waits for the subshell's MATLAB" alerted ml_alive_p3
  tk_wait 240 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  export V7T_STALE_S=30

  setup slowexec4 || return   # the exec shows only after the wait: the PID file then names MATLAB
  pf="$RD/takeover_ml_p3.pid"
  export V7T_ML_PID_WAIT_S=2
  echo 7 > "$S/sys/exec_delay"; echo 40 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 30 alerted ml_pid_p3; check "exec not seen within the wait: alert" alerted ml_pid_p3
  until_t 30 bash -c "[ \"\$(wc -l < '$pf' 2>/dev/null)\" = 1 ]"
  op=$(head -1 "$pf" 2>/dev/null)
  check "checked on after the wait: the PID file names the MATLAB once the exec shows" bash -c "[ \$(wc -l < '$pf') = 1 ] && [ -f '$S/ctl/start_$op' ]"
  tk_kill
  export V7T_ML_PID_WAIT_S=60
}

t_turn() {
  setup turn || return
  export V7T_SILENT_S=3
  local n
  n=$(grep -n '^##### STAGE B4s (' "$RD/p3.log" | tail -1 | cut -d: -f1)
  head -n $((n + 2)) "$RD/p3.log" > "$RD/p3.cut"; mv "$RD/p3.cut" "$RD/p3.log"; touch -d '-5 min' "$RD/p3.log"
  printf 32824 > "$S/temp/uav_gcs_parallel_turn.txt"; touch -d '-1 hour' "$S/temp/uav_gcs_parallel_turn.txt"
  echo exited > "$S/sys/state/32824"
  local m0 t0
  m0=$(md5sum < "$S/temp/uav_gcs_parallel_turn.txt"); t0=$(stat -c %Y "$S/temp/uav_gcs_parallel_turn.txt")
  tk_start
  until_t 40 alerted turn_holder_32824; check "alert: the turn holder has exited" alerted turn_holder_32824
  check "turn file untouched" [ "$(md5sum < "$S/temp/uav_gcs_parallel_turn.txt")" = "$m0" ] && [ "$(stat -c %Y "$S/temp/uav_gcs_parallel_turn.txt")" = "$t0" ]
  until_t 40 alerted p1_silent; check "alert: profile 1's log silent" alerted p1_silent
  until_t 40 alerted p3_open; check "alert: p3's part has a stage open" alerted p3_open
  check "nothing run in p3 while its stage is open" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  sleep 1.1; echo go > "$RD/p3_resume.go"
  until_t 40 grep -q "uav-gcs-v7-p3 call run_stage('A0','B4s')" "$S/ctl/calls.log"
  check "p3 goes on at B4s with A0 first" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 12 B4s A0 1 #####$' "$RD/p3.log"
  printf 99999 > "$S/temp/uav_gcs_parallel_turn.txt"
  until_t 40 grep -q 'names PID 99999, no live MATLAB (none)' "$S/takeover.log"
  check "a holder that is gone: logged, no alert" bash -c "grep -q 'names PID 99999, no live MATLAB' '$S/takeover.log' && [ ! -f '$RD/ALERT_turn_holder_99999.txt' ]"
  tk_kill
  export V7T_SILENT_S=100000
}

t_p2gate() {   # profile 2 starts only on a finished profile 1 or p2_start.go; its C1p alerts when P3 cannot reach SURV3
  setup p2gate || return
  echo "##### chain ended rc=1 $(date) #####" >> "$RD/p1.log"   # the launcher's chain has failed: given up, it runs nothing
  touch "$RD/p1.abandon" "$RD/p3_c1p.force" "$S/ctl/fail_uav-gcs-v7-p3_C1p"
  tk_start
  until_t 40 alerted p2_wait_p1_abandon
  check "profile 1 given up: alert naming p2_start.go" grep -q 'p2_start.go' "$RD/ALERT_p2_wait_p1_abandon.txt"
  until_t 40 alerted p3_failed; check "p3's chain fails in C1p" alerted p3_failed
  sleep 2
  check "profile 2 not started without p2_start.go" [ ! -d "$S/uav-gcs-v7-p2" ]
  echo go > "$RD/p2_start.go"
  until_t 60 grep -q 'uav-gcs-v7-p2 done B4s' "$S/ctl/calls.log"
  check "profile 2's B stages on p2_start.go" grep -q 'uav-gcs-v7-p2 done B4s' "$S/ctl/calls.log"
  check "p2_start.go taken" bash -c "ls '$RD'/p2_start.go.used_* >/dev/null 2>&1 && [ ! -f '$RD/p2_start.go' ]"
  until_t 40 alerted p2_c1p_p3_failed
  check "p3 failed before SURV3: alert naming p2_c1p.force" bash -c "grep -q 'p2_c1p.force' '$RD'/ALERT_p2_c1p_p3_failed_*.txt"
  check "that alert says what the force file skips" bash -c "grep -q 'skips only the wait for profile 3.s SURV3' '$RD'/ALERT_p2_c1p_p3_failed_*.txt"
  touch "$RD/p2_c1p.force"
  until_t 40 alerted p2_force_ignored; check "p2_c1p.force while profile 3 is not given up: ignored, with an alert" alerted p2_force_ignored
  sleep 2; check "no C1p on it" bash -c "! grep -q 'uav-gcs-v7-p2 start C1p' '$S/ctl/calls.log'"
  rm -f "$RD/p2_c1p.force"
  touch "$RD/p3.abandon"
  until_t 40 alerted p2_c1p_p3_abandon
  check "p3 given up before SURV3, its chain stopped: alert naming p2_c1p.force and what it still waits for" bash -c "grep -q 'p2_c1p.force' '$RD/ALERT_p2_c1p_p3_abandon.txt' && grep -q 'still waits until profile 1' '$RD/ALERT_p2_c1p_p3_abandon.txt'"
  check "profile 2's C1p waits" bash -c "! grep -q 'uav-gcs-v7-p2 start C1p' '$S/ctl/calls.log'"
  touch "$RD/p2_c1p.force"
  tk_wait 240 || bad "takeover did not end in time"
  check "profile 2's C1p on p2_c1p.force" grep -q 'uav-gcs-v7-p2 start C1p' "$S/ctl/calls.log"
  check "p2: final part LAT..RPT and the bundle" final_ok p2
  check "profiles 1 and 3 given up: no LAT" bash -c "grep -q 'p1 given up: no LAT' '$S/takeover.log' && grep -q 'p3 given up: no LAT' '$S/takeover.log'"
  check "v7 done" has "$S/takeover.log" 'v7 done'
}

t_refuse() {
  setup refuse || return
  local out
  out=$(TEMP='C:\Windows\Temp' bash "$TK" 24172 49732 2>&1); check "TEMP elsewhere: refused" grep -q 'not started' <<< "$out"
  echo '"C:\Program Files\Git\usr\bin\bash.exe" "/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.sh" 9b5c9f1beec4bef1ceadaa18068239c36d82c77a resume' > "$S/sys/procs/24172"
  out=$(bash "$TK" 24172 49732 2>&1); check "launcher alive: refused" grep -q 'launcher (PID 24172) still runs.*not started' <<< "$out"
  echo 'C:\Windows\notepad.exe' > "$S/sys/procs/24172"
  echo '"C:\Program Files\Git\usr\bin\bash.exe" "/c/Users/Adi Suliman/uav-gcs-logs/v7_d87_p3fix.sh"' > "$S/sys/procs/49732"
  out=$(bash "$TK" 24172 49732 2>&1); check "p3 fix alive: refused" grep -q 'p3 fix script (PID 49732) still runs.*not started' <<< "$out"
  check "no lock after a refusal" [ ! -f "$RD/takeover.lock" ]
  rm -f "$S/sys/procs/49732"
  tk_start; until_t 30 grep -q "v7 takeover started" "$S/takeover.log"
  check "a reused PID does not block the start" grep -q 'v7 takeover started' "$S/takeover.log"
  tk_kill
  out=$(bash "$TK" 24172 2>&1); check "missing PID: usage" grep -q usage <<< "$out"
  rm -f "$RD/takeover.lock"; cp -p "$SB/source/code_commit.txt" "$RD/code_commit.txt"
  for b in "" "x" "$(( $(date +%s) + 86400 ))"; do
    printf '%s' "$b" > "$S/sys/boot"
    out=$(bash "$TK" 24172 49732 2>&1); check "boot time '$b': refused" grep -q 'boot time could not be read.*not started' <<< "$out"
  done
  check "no lock and SRC untouched after the refusals" bash -c "[ ! -f '$RD/takeover.lock' ] && cmp -s '$RD/code_commit.txt' '$SB/source/code_commit.txt'"
  echo $(( P1_SE - 3600 )) > "$S/sys/boot"
  export V7T_ALLOW_PIDS="43428 43972"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 8))|$LCMD" \
    "39928|$((P1_SE - 1))|\"C:\Program Files\Git\bin\bash.exe\" -lc \"bash '/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.sh' 9b5c9f1 resume\"" > "$S/sys/scripts"
  out=$(bash "$TK" 24172 49732 2>&1); echo "$out" | sed 's/^/     | /'
  check "a launcher wrapper outside the allow-list: refused" bash -c "grep -q 'outside V7T_ALLOW_PIDS.*39928|.*not started' <<< \"\$1\" && ! grep -q '43428|' <<< \"\$1\"" _ "$out"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 5000))|$LCMD" > "$S/sys/scripts"
  out=$(bash "$TK" 24172 49732 2>&1); check "an allowed PID created long after its part (reused): refused" grep -q 'outside V7T_ALLOW_PIDS.*43972|.*not started' <<< "$out"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "49999|$((P1_SE + 8))|\"C:\Program Files\Git\usr\bin\bash.exe\" \"/c/Users/Adi Suliman/uav-gcs-logs/v7_d87_p3fix.sh\"" > "$S/sys/scripts"
  out=$(bash "$TK" 24172 49732 2>&1); check "a p3 fix script under another PID: refused" grep -q 'outside V7T_ALLOW_PIDS.*49999|.*not started' <<< "$out"
  check "still no lock, SRC untouched" bash -c "[ ! -f '$RD/takeover.lock' ] && cmp -s '$RD/code_commit.txt' '$SB/source/code_commit.txt'"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 8))|$LCMD" \
    "31748|$((P1_SE + 9))|\"C:\Program Files\Git\bin\bash.exe\" -c -l \"grep -n v7_d86_launch.sh /c/x\"" \
    "29888|$((P1_SE + 9))|\"C:\Program Files\Git\usr\bin\bash.exe\" -c \"sleep 25; : v7_d86_launch.sh\"" \
    "48108|$((P1_SE + 9))|/usr/bin/bash -c \"cat '/c/Users/Adi Suliman/uav-gcs-logs/v7_d87_p3fix.sh'\"" > "$S/sys/scripts"
  echo "47724|$((P1_SE + 9))|$LCMD" > "$S/sys/scripts_once"
  : > "$S/takeover.log"; tk_start; until_t 30 grep -q "v7 takeover started" "$S/takeover.log"
  check "a launcher fork seen by one scan only: not counted" test ! -f "$S/sys/scripts_once"
  check "the allowed subshells and bash commands that only mention the scripts: started" grep -q 'v7 takeover started' "$S/takeover.log"
  sleep 3
  check "no alert on the allowed subshells or the mentions" bash -c "! ls '$RD'/ALERT_old_script_*.txt >/dev/null 2>&1"
  tk_kill
  unset V7T_ALLOW_PIDS
  : > "$S/sys/scripts"; sleep 4
  local A B p
  bash "$TK" 24172 49732 > "$S/two_a.log" 2>&1 & A=$!
  bash "$TK" 24172 49732 > "$S/two_b.log" 2>&1 & B=$!
  disown "$A" "$B"
  until_t 60 bash -c "grep -q 'started' '$S/two_a.log' && grep -q 'started' '$S/two_b.log'"
  cat "$S/two_a.log" "$S/two_b.log" | grep 'started' | sed 's/^/     | /'
  check "two starts at once: exactly one runs, the other refuses" bash -c "[ \$(cat '$S/two_a.log' '$S/two_b.log' | grep -c 'v7 takeover started') = 1 ] && [ \$(cat '$S/two_a.log' '$S/two_b.log' | grep -c 'not started') = 1 ]"
  kill_tree "$A"; kill_tree "$B"; sleep 0.5
  p=$(sandbox_left | tr '\n' ' '); [ -z "$p" ] || kill -9 $p 2>/dev/null
}

t_accept() {   # a failed rerun answered with p3_rerun.accept: C1p still waits for profile 1's SURV3
  setup accept || return
  local a b
  tk_start; HOLD_AT=SURV3 D=0.2 p1_fake
  until_t 40 test -f "$S/ctl/p1_C1c_at"
  touch "$S/ctl/fail_uav-gcs-v7-p3_B3"; echo "B2F B3 B4" > "$RD/p3_brerun.go"
  until_t 120 alerted p3_rerun_failed; check "alert on the failed rerun (profile 1 in SURV)" alerted p3_rerun_failed
  check "it names p3_rerun.accept, and that C1p still waits for SURV3" bash -c "grep -q 'p3_rerun.accept to go on with the B stages as they are. Either way C1p still waits for profile 1.s SURV3' '$RD'/ALERT_p3_rerun_failed_*.txt"
  touch "$RD/p3_c1p.force"
  until_t 40 alerted p3_force_ignored; check "p3_c1p.force while profile 1 is not given up: ignored, with an alert" alerted p3_force_ignored
  rm -f "$RD/p3_c1p.force"; sleep 1.1
  echo ok > "$RD/p3_rerun.accept"
  until_t 40 grep -q '^##### rerun accepted GO ' "$RD/p3.log"
  check "the failed rerun accepted in p3.log" grep -q '^##### rerun accepted GO [0-9a-f]* (p3_rerun.accept' "$RD/p3.log"
  check "p3_rerun.accept taken" bash -c "ls '$RD'/p3_rerun.accept.used_* >/dev/null 2>&1 && [ ! -f '$RD/p3_rerun.accept' ]"
  sleep 4
  check "C1p still waits for profile 1's SURV3" bash -c "! grep -q 'uav-gcs-v7-p3 start C1p' '$S/ctl/calls.log'"
  touch "$S/ctl/p1_release_SURV3"
  tk_wait 240 || bad "takeover did not end in time"
  a=$(cat "$S/ctl/p1_surv3_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's SURV3" lt "$a" "$b"
  check "the rerun ran once" [ "$(grep -c 'takeover-rerun' "$RD/p3.log")" = 1 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_p1gone() {   # profile 1's chain subshells gone without an end marker: p1_cut once no MATLAB child is left
  setup p1gone || return
  echo $(( P1_SE - 3600 )) > "$S/sys/boot"
  export V7T_ALLOW_PIDS="43428 43972"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 8))|$LCMD" > "$S/sys/scripts"
  echo "$LCMD" > "$S/sys/procs/43428"; echo "$LCMD" > "$S/sys/procs/43972"; echo 44984 > "$S/sys/children/43972"
  echo "B2F B3" > "$RD/p3_brerun.go"
  tk_start; until_t 30 grep -q 'v7 takeover started' "$S/takeover.log"
  sleep 4
  check "subshells alive: no p1_cut" bash -c "! ls '$RD'/ALERT_p1_cut*.txt >/dev/null 2>&1"
  check "every old run script renamed at the start, v7_d86_launch.sh too while the allowed subshells live" bash -c "for f in ${OLD_SCRIPTS[*]}; do [ ! -e '$S/logs/'\$f ] && [ -f '$S/logs/'\$f.retired_by_d91 ] || exit 1; done"
  rm -f "$S/sys/procs/43428" "$S/sys/procs/43972"; : > "$S/sys/scripts"
  sleep 4
  check "a MATLAB child still listed: no p1_cut" bash -c "! ls '$RD'/ALERT_p1_cut*.txt >/dev/null 2>&1"
  check "no rerun while profile 1 is in C1p" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  rm -f "$S/sys/children/43972"
  until_t 30 alerted p1_cut; check "p1_cut once no MATLAB child is left" alerted p1_cut
  check "the alert asks to check for a MATLAB of profile 1 first" bash -c "grep -q 'no MATLAB of profile 1 still runs' '$RD'/ALERT_p1_cut_*.txt"
  sleep 2
  check "nothing run for profile 1 without a go file" bash -c "! grep -q 'uav-gcs-v7 call' '$S/ctl/calls.log'"
  sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 60 grep -q 'takeover SRC [0-9a-f]* FROM 13 C1p A0 0 ' "$RD/p1.log"
  check "profile 1 goes on from C1p under a takeover part" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 13 C1p A0 0 #####$' "$RD/p1.log"
  tk_wait 240 || bad "takeover did not end in time"
  local a b
  a=$(ns_of "$S" uav-gcs-v7 done C1c); b=$(ns_of "$S" uav-gcs-v7-p3 start A0)
  check "the rerun after the resumed profile 1's C1c" lt "$a" "$b"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  unset V7T_ALLOW_PIDS
}

t_p1wait() {   # a profile 1 resume does not start C1c beside P3's B-stage rerun
  setup p1wait || return
  local a b
  echo 25 > "$S/ctl/slow_uav-gcs-v7-p3_B3"
  tk_start; FAIL_AT=C1c D=0.2 p1_fake
  until_t 40 alerted p1_failed
  check "the p1_failed alert asks to check for a MATLAB of profile 1 first" bash -c "grep -q 'no MATLAB of profile 1 still runs' '$RD'/ALERT_p1_failed_*.txt"
  echo "B2F B3 B4s" > "$RD/p3_brerun.go"
  until_t 40 grep -q 'uav-gcs-v7-p3 start B3' "$S/ctl/calls.log"
  check "the rerun starts while profile 1 has failed" grep -q 'uav-gcs-v7-p3 start B3' "$S/ctl/calls.log"
  sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 30 grep -q "p1: resume from C1c waits until profile 3's B-stage rerun has ended" "$S/takeover.log"
  check "the resume waits for the rerun" grep -q "p1: resume from C1c waits until profile 3's B-stage rerun has ended" "$S/takeover.log"
  tk_wait 240 || bad "takeover did not end in time"
  a=$(ns_of "$S" uav-gcs-v7-p3 done B4s); b=$(ns_of "$S" uav-gcs-v7 start C1c)
  check "profile 1's C1c after the rerun ended" lt "$a" "$b"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_mainkill() {   # only the main bash killed: the tracks stop, its MATLAB runs on, a restart waits for it
  setup mainkill || return
  local t0
  echo 150 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  t0=$(date +%s); kill -TERM "$TKP"
  until_t 10 bash -c "! kill -0 $TKP 2>/dev/null"
  check "main ended by SIGTERM while its tracks live: its EXIT trap keeps takeover.lock" test -f "$RD/takeover.lock"
  until_t 30 alerted takeover_main_gone; check "alert: the main bash is gone" alerted takeover_main_gone
  until_t 30 no_tk; check "every track has stopped" no_tk
  check "its MATLAB runs on" test -d "$S/ctl/busy_uav-gcs-v7-p3"
  check "its PID file kept" test -f "$RD/takeover_ml_p3.pid"
  sleep 4
  tk_start; until_t 90 bash -c "[ \$(grep -c 'v7 takeover started' '$S/takeover.log') = 2 ]"
  check "restart accepted (main bash gone, lock 3 heartbeats old)" bash -c "[ \$(grep -c 'v7 takeover started' '$S/takeover.log') = 2 ] && [ \$(( \$(date +%s) - $t0 )) -lt 120 ]"
  until_t 120 alerted ml_alive_p3; check "the restart waits for that MATLAB" alerted ml_alive_p3
  tk_wait 240 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
}

t_unknown() {   # a failed process query is unknown, never 'gone': no start, no MATLAB start
  setup unknown || return
  local out t0
  export V7T_Q_TIMEOUT_S=2
  touch "$S/sys/hang_cmdline_24172"; t0=$(date +%s)
  out=$(bash "$TK" 24172 49732 2>&1); check "a hanging command-line query: ended after 2 s each, refused after 5 tries" bash -c "grep -q 'command line of PID 24172 could not be read.*not started' <<< \"\$1\" && [ \$(( \$(date +%s) - $t0 )) -lt 40 ]" _ "$out"
  sleep 1; check "the hanging queries were ended (5 recorded)" bash -c "[ \$(wc -l < '$S/sys/hung') = 5 ] && [ -z \"\$1\" ]" _ "$(sandbox_left)$(hung_left)"
  rm -f "$S/sys/hang_cmdline_24172"; export V7T_Q_TIMEOUT_S=30
  touch "$S/sys/fail_scripts"
  out=$(bash "$TK" 24172 49732 2>&1); check "process scan unreadable at the start: refused" grep -q 'process scan for old scripts could not be read.*not started' <<< "$out"
  rm -f "$S/sys/fail_scripts"; touch "$S/sys/fail_cmdline_24172"
  out=$(bash "$TK" 24172 49732 2>&1); check "the launcher's command line unreadable: refused" grep -q 'command line of PID 24172 could not be read.*not started' <<< "$out"
  rm -f "$S/sys/fail_cmdline_24172"
  check "no lock, SRC untouched, scripts kept" bash -c "[ ! -f '$RD/takeover.lock' ] && cmp -s '$RD/code_commit.txt' '$SB/source/code_commit.txt' && [ -f '$S/logs/v7_d87_p3fix.sh' ]"
  echo '"C:\Program Files\MATLAB\R2026a\bin\win64\MATLAB.exe" "-batch" "run_stage('"'"'C1p'"'"')"' > "$S/sys/procs/61111"
  echo 61111 > "$RD/takeover_ml_p3.pid"; touch "$S/sys/fail_cmdline_61111"
  tk_start; D=0.05 p1_fake
  until_t 60 test -f "$S/ctl/p1_end_at"
  until_t 90 grep -q 'p3: the process query for the PIDs in .*(61111 ) failed' "$S/takeover.log"; sleep 3
  check "logged as unknown" grep -q 'p3: the process query for the PIDs in .*(61111 ) failed' "$S/takeover.log"
  check "a recorded MATLAB whose query fails holds p3 back" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  rm -f "$S/sys/fail_cmdline_61111"
  until_t 20 alerted ml_alive_p3; check "then read as alive" alerted ml_alive_p3
  touch "$S/sys/fail_scripts"; rm -f "$S/sys/procs/61111"
  until_t 90 grep -q 'the process scan for old scripts failed; no MATLAB starts until it reads' "$S/takeover.log"; sleep 3
  check "logged" grep -q 'the process scan for old scripts failed; no MATLAB starts until it reads' "$S/takeover.log"
  check "a failed process scan holds MATLAB starts" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  rm -f "$S/sys/fail_scripts"
  tk_wait 240 || bad "takeover did not end in time"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
}

t_rename() {   # a running bash goes on after its script file is renamed, as the launcher's at the takeover's start
  CUR=rename; S="$SB/rename"; echo "== rename"
  rm -rf "$S"; mkdir -p "$S/A" "$S/B"
  cat > "$S/like_launcher.sh" <<'EOF'
#!/usr/bin/env bash
# main reads this file as it goes; chain runs as an async function, as the launcher's chain subshells
O=${1:?}
chain() {
  local i rc=0
  for i in 1 2 3 4 5 6; do
    ( sleep 1 ); rc=$?
    echo "chain step $i $(date +%s)" >> "$O/chain.log"
  done
  echo "##### chain ended rc=$rc $(date) #####" >> "$O/chain.log"
}
chain &
echo "main: chain started" >> "$O/main.log"
sleep 3
echo "main: line after the first sleep" >> "$O/main.log"
sleep 3
echo "main: line after the second sleep" >> "$O/main.log"
wait
echo "main: end" >> "$O/main.log"
EOF
  local ma mb wp
  cp "$S/like_launcher.sh" "$S/A/s.sh"; bash "$S/A/s.sh" "$S/A" & ma=$!
  cp "$S/like_launcher.sh" "$S/B/s.sh"; bash "$S/B/s.sh" "$S/B" & mb=$!
  sleep 1.5
  check "renamed while its bash runs it" mv "$S/A/s.sh" "$S/A/s.sh.retired_by_d91"
  read -r wp < "/proc/$mb/winpid"; taskkill //PID "$wp" //F > /dev/null
  sleep 0.5
  check "renamed after its main bash was ended with taskkill /F" mv "$S/B/s.sh" "$S/B/s.sh.retired_by_d91"
  until_t 30 bash -c "grep -q 'chain ended' '$S/A/chain.log' && grep -q 'chain ended' '$S/B/chain.log' && grep -q 'main: end' '$S/A/main.log'"
  check "running main bash: reads the script's later lines after the rename" bash -c "grep -q 'line after the second sleep' '$S/A/main.log' && grep -q 'main: end' '$S/A/main.log'"
  check "its chain subshell writes its end marker" grep -q '^##### chain ended rc=0' "$S/A/chain.log"
  check "main ended: its chain subshell goes on, forks included, and writes its end marker" bash -c "[ \$(grep -c '^chain step' '$S/B/chain.log') = 6 ] && grep -q '^##### chain ended rc=0' '$S/B/chain.log' && ! grep -q 'first sleep' '$S/B/main.log'"
  wait "$ma" 2>/dev/null
}

t_unread() {   # a log that exists but does not read as a part is unknown: nothing is decided or started on it
  setup unread || return
  export V7T_UNKNOWN_ALERT_S=3
  local G='##### PART 20261018_120000 takeover SRC abc #####' a b n3
  echo "$G" >> "$RD/p3.log"; n3=$(grep -c '^##### PART' "$RD/p3.log")
  tk_start; HOLD_AT=SURV D=0.2 p1_fake
  until_t 40 grep -q 'p3: p3.log could not be read' "$S/takeover.log"
  check "a header without FROM in p3.log: read as unknown, logged" grep -q 'p3: p3.log could not be read' "$S/takeover.log"
  until_t 40 alerted unknown_p3log; check "alert once it stays unknown" alerted unknown_p3log
  until_t 40 test -f "$S/ctl/p1_C1c_at"
  echo "$G" >> "$RD/p1.log"
  touch "$S/ctl/p1_release_SURV"
  until_t 40 test -f "$S/ctl/p1_end_at"; sleep 5
  check "p1.log unknown after its chain ended: no p1 alert, no p2 start" bash -c "! ls '$RD'/ALERT_p1_failed* '$RD'/ALERT_p1_cut* >/dev/null 2>&1 && [ ! -d '$S/uav-gcs-v7-p2' ]"
  until_t 40 alerted unknown_p1log; check "p1.log unknown: alert" alerted unknown_p1log
  check "no MATLAB and no part header while the logs are unknown" bash -c "! grep -q ' call ' '$S/ctl/calls.log' && [ \$(grep -c '^##### PART' '$RD/p3.log') = $n3 ]"
  grep -vxF "$G" "$RD/p1.log" > "$RD/p1.fix"; mv "$RD/p1.fix" "$RD/p1.log"
  until_t 60 grep -q 'uav-gcs-v7-p2 done B4s' "$S/ctl/calls.log"
  check "p1.log readable again: profile 2 starts" grep -q 'uav-gcs-v7-p2 done B4s' "$S/ctl/calls.log"
  sleep 3
  check "p3 still waits while its log is unknown, and so does p2's C1p" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log' && ! grep -q 'uav-gcs-v7-p2 start C1p' '$S/ctl/calls.log'"
  grep -vxF "$G" "$RD/p3.log" > "$RD/p3.fix"; mv "$RD/p3.fix" "$RD/p3.log"
  tk_wait 240 || bad "takeover did not end in time"
  a=$(cat "$S/ctl/p1_surv3_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's SURV3" lt "$a" "$b"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  export V7T_UNKNOWN_ALERT_S=3600
}

t_mlstub() {   # a recorded subshell whose stub is gone while its MATLAB child lives counts as alive
  setup mlstub || return
  printf '%s\nmsys %s\n' 61112 999 > "$RD/takeover_ml_p3.pid"
  echo none > "$S/sys/procs/61112"; echo 61113 > "$S/sys/children/61112"
  tk_start
  until_t 120 alerted ml_alive_p3; check "stub gone, MATLAB child alive: alive, no new MATLAB there" alerted ml_alive_p3
  sleep 2
  check "its PID file kept, nothing started in p3" bash -c "[ -f '$RD/takeover_ml_p3.pid' ] && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  rm -f "$S/sys/children/61112"
  until_t 30 test ! -f "$RD/takeover_ml_p3.pid"
  check "no MATLAB child left: gone, the PID file removed" test ! -f "$RD/takeover_ml_p3.pid"
  tk_kill

  setup mlstub2 || return   # the launcher alone in the PID file, gone, while a live matlab child of it runs (ParentProcessId kept)
  echo 61120 > "$RD/takeover_ml_p3.pid"
  echo none > "$S/sys/procs/61120"; echo 61121 > "$S/sys/children/61120"
  tk_start
  until_t 120 alerted ml_alive_p3; check "the recorded launcher gone, a live matlab child of it: alive" alerted ml_alive_p3
  sleep 2
  check "its PID file kept, nothing started in p3" bash -c "[ -f '$RD/takeover_ml_p3.pid' ] && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  rm -f "$S/sys/children/61120"
  until_t 30 test ! -f "$RD/takeover_ml_p3.pid"
  check "no child left: gone, the PID file removed" test ! -f "$RD/takeover_ml_p3.pid"
  tk_kill

  setup mlstub3 || return   # 'win64 <pid>': the launcher gone, its win64 child alive
  printf '%s\nwin64 %s\n' 61130 61131 > "$RD/takeover_ml_p3.pid"
  echo none > "$S/sys/procs/61130"; echo live > "$S/sys/state/61131"
  tk_start
  until_t 120 alerted ml_alive_p3; check "the launcher gone, its recorded win64 child live: alive" alerted ml_alive_p3
  sleep 2
  check "its PID file kept, nothing started in p3" bash -c "[ -f '$RD/takeover_ml_p3.pid' ] && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  echo exited > "$S/sys/state/61131"   # exited, its process object lingering: not counted
  until_t 30 test ! -f "$RD/takeover_ml_p3.pid"
  check "the win64 child exited: gone, the PID file removed" test ! -f "$RD/takeover_ml_p3.pid"
  tk_kill

  setup mlstub4 || return   # 'win64 <pid>' exited (its process object lingers) with live helper children, as the zombie 32824
  printf '%s\nwin64 %s\n' 61140 61141 > "$RD/takeover_ml_p3.pid"
  echo none > "$S/sys/procs/61140"; echo exited > "$S/sys/state/61141"; mkdir -p "$S/sys/kids"
  printf '%s\n' "61142 MATLABWebUI.exe live" "61143 MATLABWindow.exe live" "61144 MathWorksServiceHost.exe live" "61145 MATLAB.exe live" > "$S/sys/kids/61141"
  tk_start
  until_t 120 alerted ml_alive_p3; check "the exited win64 with a live MATLAB.exe child (a pool worker) beside its helpers: alive" alerted ml_alive_p3
  sleep 2
  check "its PID file kept, nothing started in p3" bash -c "[ -f '$RD/takeover_ml_p3.pid' ] && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  sed -i 's/^61145 MATLAB.exe live$/61145 MATLAB.exe exited/' "$S/sys/kids/61141"   # the worker gone; MATLABWebUI.exe, MATLABWindow.exe live on
  until_t 30 test ! -f "$RD/takeover_ml_p3.pid"
  check "only MATLABWebUI.exe, MATLABWindow.exe and MathWorksServiceHost.exe left: gone, the PID file removed" test ! -f "$RD/takeover_ml_p3.pid"
  D=0.05 p1_fake   # profile 1 past SURV3: p3's C1p may start
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  check "the next MATLAB starts in p3" grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 30 test -f "$S/ctl/p1_end_at"
  tk_kill
}

t_webui() {   # an exited win64 MATLAB whose MATLABWebUI.exe / MATLABWindow.exe children live on frees its worktree; a launcher gone before its PID was taken
  setup webui || return
  local pf="$RD/takeover_ml_p3.pid" n cm cw lp
  touch "$S/ctl/win64" "$S/ctl/webui"   # every MATLAB: launcher and win64 child, which leaves a lingering object with live helpers
  tk_start; D=0.05 p1_fake
  tk_wait 300 || bad "takeover did not end in time"
  n=$(grep -l 'MATLABWebUI.exe live' "$S/sys/kids/"* 2>/dev/null | wc -l)
  check "every win64 MATLAB left an exited process object with live MATLABWebUI.exe and MATLABWindow.exe children ($n)" bash -c "[ $n -ge 3 ] && [ \$(grep -lx exited '$S/sys/state/'* 2>/dev/null | wc -l) -ge $n ]"
  check "no ml_alive alert: those children hold no worktree" bash -c "! ls '$RD'/ALERT_ml_alive_* >/dev/null 2>&1"
  check "p3's C1p part ends with its end marker" bash -c "sed -n '/takeover SRC [0-9a-f]* FROM 13 C1p/,\$p' '$RD/p3.log' | grep -q '^##### chain ended rc=0'"
  check "no PID file left" bash -c "! ls '$RD'/takeover_ml_*.pid >/dev/null 2>&1"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"

  setup mlquit || return   # p3's launcher exits after 3 s, its exec still unseen (exec_delay 6 s): its win64 child runs on
  pf="$RD/takeover_ml_p3.pid"
  touch "$S/ctl/win64_uav-gcs-v7-p3" "$S/ctl/hold_uav-gcs-v7-p3_C1p"; echo 3 > "$S/ctl/win64_quit_uav-gcs-v7-p3"; echo 6 > "$S/sys/exec_delay"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 40 grep -q 'p3: MATLAB exited before its PID was taken' "$S/takeover.log"
  read -r cm cw < "$S/ctl/win64_pid_uav-gcs-v7-p3"; lp=$(cat "$S/ctl/ppid_$cw" 2>/dev/null)
  check "the launcher gone before its PID was taken: the PID file names its last Windows PID, then its win64 child" bash -c "[ -n '$lp' ] && [ \"\$(head -1 '$pf')\" = '$lp' ] && [ \"\$(sed -n 2p '$pf')\" = 'win64 $cw' ]"
  until_t 120 alerted ml_alive_p3
  check "the child runs on: the takeover holds the worktree (alert, PID file kept, no end marker)" bash -c "kill -0 '$cm' && ls '$RD'/ALERT_ml_alive_p3*.txt >/dev/null 2>&1 && [ -f '$pf' ] && [ \$(sed -n '/takeover SRC [0-9a-f]* FROM 13 C1p/,\$p' '$RD/p3.log' | grep -c 'chain ended') = 0 ]"
  rm -f "$S/ctl/hold_uav-gcs-v7-p3_C1p"
  until_t 60 bash -c "sed -n '/takeover SRC [0-9a-f]* FROM 13 C1p/,\$p' '$RD/p3.log' | grep -q 'chain ended'"
  check "the end marker once the child has finished" bash -c "! kill -0 '$cm' 2>/dev/null && sed -n '/takeover SRC [0-9a-f]* FROM 13 C1p/,\$p' '$RD/p3.log' | grep -q 'chain ended'"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  tk_kill
}

t_mlquery() {   # the real PowerShell queries: live MATLABWebUI.exe / MATLABWindow.exe children (copies of sleep.exe in the sandbox) are no MATLAB
  setup mlquery || return
  local lib="$S/tk_lib.sh" fd="$S/fake/bin/win64" out
  head -n -1 "$TK" > "$lib"
  mkdir -p "$fd"; cp /usr/bin/sleep.exe "$fd/MATLABWebUI.exe"; cp /usr/bin/sleep.exe "$fd/MATLABWindow.exe"
  out=$(V7T_LIB="$lib" FD="$fd" V7T_SYS= bash -c '
    source "$V7T_LIB"; BOOT=0; START_T=$EPOCHSECONDS
    "$FD/MATLABWebUI.exe" 90 & a=$!; "$FD/MATLABWindow.exe" 90 & b=$!
    sleep 2
    read -r wa < /proc/$a/winpid; read -r wb < /proc/$b/winpid
    pp=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"ProcessId=$wa\").ParentProcessId" | tr -dc 0-9)
    pb=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"ProcessId=$wb\").ParentProcessId" | tr -dc 0-9)
    echo "parents: $pp $pb"
    echo "mlchild: $(sysq mlchild "$pp") $(sysq mlchild "$pb")"
    echo "state: $(sysq state "$wa") $(sysq state "$wb")"
    c=$(sysq cmdline "$wa"); if ml_cmd "$c"; then echo "cmd: matlab"; else echo "cmd: other"; fi
    printf "%s\nwin64 %s\n" "$pp" "$wa" > "$R/takeover_ml_p3.pid"; echo "pf parent+win64: $(ml_state p3)"
    printf "%s\n" "$wa" > "$R/takeover_ml_p3.pid"; echo "pf reused by MATLABWebUI.exe: $(ml_state p3)"
    printf "%s\n" "$pp" > "$R/takeover_ml_p3.pid"; echo "pf parent alone: $(ml_state p3)"
    kill $a $b 2>/dev/null; wait' 2>&1)
  echo "$out" | sed 's/^/     | /'
  check "their parents found" grep -q '^parents: [0-9][0-9]* [0-9][0-9]*$' <<< "$out"
  check "mlchild of each parent: none (the helpers do not count)" grep -qx 'mlchild: none none' <<< "$out"
  check "state: other, not a live win64 MATLAB (path bin\\win64\\MATLABWebUI.exe)" grep -qx 'state: other other' <<< "$out"
  check "its command line is no MATLAB" grep -qx 'cmd: other' <<< "$out"
  check "a PID file of the parent and 'win64 <MATLABWebUI.exe>': gone" grep -qx 'pf parent+win64: gone' <<< "$out"
  check "a PID file whose PID a MATLABWebUI.exe now holds: gone" grep -qx 'pf reused by MATLABWebUI.exe: gone' <<< "$out"
  check "a PID file of the parent alone: gone" grep -qx 'pf parent alone: gone' <<< "$out"
}

t_win64() {   # a bin\matlab.exe launcher and its win64\MATLAB.exe child: the launcher ended alone, the child runs on: no second MATLAB
  setup win64 || return
  local pf="$RD/takeover_ml_p3.pid" lw="" cw="" cm="" lm="" d
  touch "$S/ctl/win64" "$S/ctl/hold_uav-gcs-v7-p3_C1p"   # p3's C1p runs until the hold file goes
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 30 grep -q '^win64 [0-9]' "$pf"
  read -r cm cw < "$S/ctl/win64_pid_uav-gcs-v7-p3"; lw=$(head -1 "$pf")
  check "PID file: the launcher, then 'win64 <pid>' of its child" bash -c "[ -n '$cw' ] && [ \"\$(sed -n 2p '$pf')\" = 'win64 $cw' ] && [ \"\$(cat '$S/ctl/ppid_$cw')\" = '$lw' ]"
  for d in /proc/[0-9]*; do [ "$(cat "$d/winpid" 2>/dev/null)" = "$lw" ] && lm=${d#/proc/}; done
  check "the launcher's process found" [ -n "$lm" ]
  kill -9 "$lm" 2>/dev/null; sleep 4
  check "the launcher ended alone: its win64 child runs on" bash -c "! kill -0 '$lm' 2>/dev/null && kill -0 '$cm' && [ -d '$S/ctl/busy_uav-gcs-v7-p3' ]"
  until_t 40 alerted ml_alive_p3
  check "the takeover holds the worktree: alert, PID file kept, no end marker" bash -c "ls '$RD'/ALERT_ml_alive_p3*.txt >/dev/null 2>&1 && [ -f '$pf' ] && [ \$(sed -n '/takeover SRC [0-9a-f]* FROM 13 C1p/,\$p' '$RD/p3.log' | grep -c 'chain ended') = 0 ]"
  kill -9 $(tk_procs) 2>/dev/null; sleep 5
  check "the takeover killed: the win64 child still runs" kill -0 "$cm"
  rm -f "$RD"/ALERT_ml_alive_p3*.txt
  tk_start
  until_t 120 alerted ml_alive_p3; check "the restart waits for the win64 child (its launcher's PID gone)" alerted ml_alive_p3
  check "no second C1p while the child runs" bash -c "kill -0 '$cm' && [ \$(grep -c 'uav-gcs-v7-p3 start C1p' '$S/ctl/calls.log') = 1 ]"
  rm -f "$S/ctl/hold_uav-gcs-v7-p3_C1p"
  tk_wait 300 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "its end marker once the child has finished" grep -q 'chain ended rc=0 (its stages were done before an interruption)' "$RD/p3.log"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
}

p1orphan_setup() {   # profile 1's launcher chain as in the live tree: 43428 -> 43972 -> bin\matlab.exe 44984 -> win64\MATLAB.exe 42560
  echo $(( P1_SE - 3600 )) > "$S/sys/boot"
  export V7T_ALLOW_PIDS="43428 43972"
  printf '%s\n' "43428|$((P1_SE + 8))|$LCMD" "43972|$((P1_SE + 8))|$LCMD" > "$S/sys/scripts"
  echo "$LCMD" > "$S/sys/procs/43428"; echo "$LCMD" > "$S/sys/procs/43972"
  echo 44984 > "$S/sys/children/43972"; echo 42560 > "$S/sys/children/44984"
  echo '"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -batch run_stage(...)' > "$S/sys/procs/44984"
  echo $((P1_SE + 9)) > "$S/sys/created/44984"; echo other > "$S/sys/state/44984"
  echo '"C:\Program Files\MATLAB\R2026a\bin\win64\MATLAB.exe" "-batch" "run_stage(...)"' > "$S/sys/procs/42560"
  echo $((P1_SE + 10)) > "$S/sys/created/42560"; echo live > "$S/sys/state/42560"
}
p1orphan_cut() {   # the launcher 44984 ended alone: the chain writes rc=1 and its subshells exit; 42560 runs on (its ParentProcessId stays 44984)
  rm -f "$S/sys/procs/44984" "$S/sys/state/44984" "$S/sys/children/43972"
  echo "##### chain ended rc=1 $(date) #####" >> "$RD/p1.log"
  rm -f "$S/sys/procs/43428" "$S/sys/procs/43972"; : > "$S/sys/scripts"
}
p1orphan_end() {   # 42560 exited, its process object lingering with live MATLABWebUI.exe and MATLABWindow.exe children (as the zombie 32824)
  rm -f "$S/sys/children/44984"; echo exited > "$S/sys/state/42560"; mkdir -p "$S/sys/kids"
  printf '%s\n' "42561 MATLABWebUI.exe live" "42562 MATLABWindow.exe live" "42563 MathWorksServiceHost.exe live" "42564 MATLAB.exe exited" > "$S/sys/kids/42560"
  printf '%s\n' "42560 MATLAB.exe exited" > "$S/sys/kids/44984"
}
t_p1orphan() {   # profile 1's launcher ended alone: its chain ends, its win64 MATLAB runs on: no resume, rerun or forced C1p beside it
  setup p1orphan || return
  local t a b f="$RD/takeover_p1_chain_ml.txt"
  p1orphan_setup
  echo "B2F B3" > "$RD/p3_brerun.go"
  tk_start
  until_t 60 bash -c "grep -qx '44984 $((P1_SE + 9))' '$f' 2>/dev/null && grep -qx '42560 $((P1_SE + 10))' '$f'"
  check "the launcher chain's MATLAB processes recorded: launcher and win64, with their creation times" bash -c "grep -qx '44984 $((P1_SE + 9))' '$f' && grep -qx '42560 $((P1_SE + 10))' '$f'"
  p1orphan_cut
  until_t 40 alerted p1_failed; check "the chain ended rc=1: p1_failed" alerted p1_failed
  sleep 4
  check "its win64 MATLAB runs on: the pending rerun does not start" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 40 alerted ml_alive_p1_chain; check "p1_resume.go: the resume waits for that MATLAB, with an alert" alerted ml_alive_p1_chain
  sleep 3
  check "no MATLAB in either worktree while it runs" bash -c "! grep -q ' call ' '$S/ctl/calls.log'"
  t=$(date +%s%N); p1orphan_end
  until_t 60 bash -c "grep -q 'uav-gcs-v7 start C1p' '$S/ctl/calls.log' && grep -q 'uav-gcs-v7-p3 start A0' '$S/ctl/calls.log'"
  a=$(ns_of "$S" uav-gcs-v7 start C1p); b=$(ns_of "$S" uav-gcs-v7-p3 start A0)
  check "once it has exited: the resume and the rerun start, both after it" bash -c "[ -n '$a' ] && [ -n '$b' ] && [ '$t' -lt '$a' ] && [ '$t' -lt '$b' ]"
  tk_wait 240 || bad "takeover did not end in time"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"

  setup p1orphan2 || return   # the same, with profile 1 given up and p3_c1p.force
  p1orphan_setup
  f="$RD/takeover_p1_chain_ml.txt"
  tk_start
  until_t 60 bash -c "grep -q '^42560 ' '$f' 2>/dev/null"
  p1orphan_cut
  until_t 40 alerted p1_failed
  touch "$RD/p1.abandon" "$RD/p3_c1p.force"
  until_t 60 grep -q "p3_c1p.force waits until profile 1's chain has stopped" "$S/takeover.log"
  until_t 60 test -f "$RD/takeover_end_p1"; sleep 8   # profile 1's track has ended: only its win64 MATLAB keeps the chain alive
  check "profile 1 given up (its track ended), its win64 MATLAB still runs: p3_c1p.force waits, no p3 C1p" bash -c "[ -f '$RD/takeover_end_p1' ] && ! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log' && grep -q \"p3_c1p.force waits until profile 1's chain has stopped\" '$S/takeover.log'"
  t=$(date +%s%N); p1orphan_end
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p on the force file once that MATLAB has exited" bash -c "[ -n '$b' ] && [ '$t' -lt '$b' ]"
  tk_kill
  unset V7T_ALLOW_PIDS
}

t_c1phold() {   # a hold and a go file written while run_c waits for free commit before C1p: both read again before its part header
  setup c1phold || return
  local a b t
  echo 40 > "$S/sys/headroom"
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'p3: free commit 40 GB < 45 GB; waiting' "$S/takeover.log"
  check "p3, profile 1 past SURV3, waits for free commit before C1p" grep -q 'p3: free commit 40 GB < 45 GB; waiting' "$S/takeover.log"
  touch "$RD/p3_c1p.hold"; echo "B3" > "$RD/p3_brerun.go"; sleep 2
  echo 70 > "$S/sys/headroom"
  until_t 40 grep -q 'p3: a hold, abandon, force or p3_brerun.go file changed during the waits before C1p' "$S/takeover.log"
  check "written during that wait: back to the C1p checks, no C1p part header" bash -c "grep -q 'p3: a hold, abandon, force or p3_brerun.go file changed during the waits before C1p' '$S/takeover.log' && ! grep -q 'takeover SRC [0-9a-f]* FROM 13 C1p' '$RD/p3.log'"
  until_t 60 grep -q '^##### rerun ended rc=0' "$RD/p3.log"
  check "the go file's rerun runs first" grep -q "uav-gcs-v7-p3 call run_stage('A0','B3')" "$S/ctl/calls.log"
  sleep 4
  check "the hold keeps C1p back" bash -c "! grep -q 'uav-gcs-v7-p3 start C1p' '$S/ctl/calls.log'"
  t=$(date +%s%N); rm -f "$RD/p3_c1p.hold"
  tk_wait 240 || bad "takeover did not end in time"
  a=$(ns_of "$S" uav-gcs-v7-p3 done B3); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "C1p after the rerun, once the hold is removed" bash -c "[ -n '$b' ] && [ '${a:-x}' -lt '$b' ] && [ '$t' -lt '$b' ]"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_rerunver() {   # the rerun runs exactly the version of p3_brerun.go that go_state checked (functions of the script, sourced)
  setup rerunver || return
  local lib="$S/tk_lib.sh" out n0
  head -n -1 "$TK" > "$lib"
  check "library copy: the script without its call of main" bash -c "! grep -q '^main ' '$lib'"
  echo "##### chain ended rc=1 $(date) #####" >> "$RD/p1.log"   # profile 1's chain over: the rerun gate is open
  n0=$(grep -c 'takeover-rerun' "$RD/p3.log")
  echo "B2F B3" > "$RD/p3_brerun.go"
  out=$(V7T_LIB="$lib" bash -c '
    source "$V7T_LIB"; BOOT=$(cat "$V7T_SYS_DIR/boot"); START_T=$EPOCHSECONDS
    st=$(go_state); echo "state: $st"
    sleep 1.1; echo "B4s C1p" > "$GO3"
    run_rerun "${st#pending }"; echo "rewritten: rc=$?"
    sleep 1.1; echo "B2F B3 B4" > "$GO3"
    st=$(go_state); echo "state: $st"
    run_rerun "${st#pending }"; echo "unchanged: rc=$?"' 2>&1)
  echo "$out" | sed 's/^/     | /'
  check "go_state gives the version it checked: pending <id> B2F B3" grep -q '^state: pending [0-9a-f]\{12\} B2F B3$' <<< "$out"
  check "rewritten to 'B4s C1p' after the check: refused before the part header" grep -q "p3: p3_brerun.go changed or could not be read before the rerun's part header" <<< "$out"
  check "an unchanged version: one part header and one MATLAB, exactly its checked list" bash -c "[ \$(grep -c 'takeover-rerun' '$RD/p3.log') = $((n0 + 1)) ] && grep -q ' RERUN B2F,B3,B4 GO [0-9a-f]* #####\$' '$RD/p3.log' && [ \"\$(grep ' call ' '$S/ctl/calls.log' | cut -d' ' -f2-)\" = \"uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B4')\" ]"
}

t_watchdog() {   # a stalled track and a died track: alerts, no final phase; a restart resumes
  setup watchdog || return
  export V7T_STALL_S=5
  local p3p p2p a b
  tk_start; HOLD_AT=SURV D=0.2 p1_fake
  until_t 30 bash -c "[ \$(grep -c '^p[123] [0-9]' '$RD/takeover_tracks.txt' 2>/dev/null) = 3 ]"
  p3p=$(awk '$1 == "p3" {print $2}' "$RD/takeover_tracks.txt"); p2p=$(awk '$1 == "p2" {print $2}' "$RD/takeover_tracks.txt")
  sleep 2
  check "no stall alert while the tracks beat" bash -c "! ls '$RD'/ALERT_takeover_track_* >/dev/null 2>&1"
  kill -STOP "$p3p"
  until_t 30 alerted takeover_track_p3_stalled; check "p3's track stopped: stall alert" alerted takeover_track_p3_stalled
  kill -CONT "$p3p"
  kill -9 "$p2p"
  until_t 30 alerted takeover_track_p2_died; check "p2's track killed alone: died alert" alerted takeover_track_p2_died
  touch "$S/ctl/p1_release_SURV"
  tk_wait 240 || bad "takeover did not end in time"
  check "final phase skipped, no 'v7 done'" bash -c "grep -q 'final phase skipped: track p2 died' '$S/takeover.log' && ! grep -q 'v7 done' '$S/takeover.log'"
  check "no final part" bash -c "! grep -q 'takeover-final' '$RD/p1.log' '$RD/p3.log'"
  check "p3 went on after its stall: C1p to RPT" grep -q 'uav-gcs-v7-p3 done RPT' "$S/ctl/calls.log"
  check "takeover.lock removed once no track lives" test ! -f "$RD/takeover.lock"
  export V7T_STALL_S=60
  tk_start
  tk_wait 240 || bad "takeover did not end in time after the restart"
  check "the restart resumes profile 2 and runs the final phase" bash -c "grep -q 'uav-gcs-v7-p2 done RPT' '$S/ctl/calls.log' && [ \$(grep -c 'v7 done' '$S/takeover.log') = 1 ]"
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  a=$(cat "$S/ctl/p1_surv3_at"); b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p after profile 1's SURV3" lt "$a" "$b"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_nolog() {   # a missing p3.log is unknown: never index 0 (no rebuild from A0), an alert, nothing runs for it
  setup nolog || return
  local out
  mv "$RD/p3.log" "$S/p3.log.away"
  tk_start; until_t 30 grep -q 'p3: p3.log missing (unknown' "$S/takeover.log"
  check "logged as missing at the start" grep -q 'p3: p3.log missing (unknown' "$S/takeover.log"
  until_t 40 alerted log_missing_p3; check "p3.log missing: alert" alerted log_missing_p3
  D=0.05 p1_fake; until_t 60 test -f "$S/ctl/p1_end_at"; sleep 4
  check "nothing run for p3 and no p3.log written" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log' && [ ! -e '$RD/p3.log' ]"
  out=$(bash "$TK" 24172 49732 status 2>&1)
  check "status: p3 without its log is unknown" grep -q '^p3: no log (unknown' <<< "$out"
  mv "$S/p3.log.away" "$RD/p3.log"
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  check "p3.log back: p3 goes on at C1p" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 13 C1p A0 0 #####$' "$RD/p3.log"
  check "no rerun or B stages for p3" bash -c "! grep -q 'uav-gcs-v7-p3 start A0' '$S/ctl/calls.log'"
  tk_kill
}

t_mainstall() {   # only the main bash stopped: the tracks raise the main-stall alert, once for its beat
  setup mainstall || return
  export V7T_STALL_S=30
  local t t2
  tk_start; HOLD_AT=SURV D=0.2 p1_fake
  until_t 30 bash -c "[ \"\$(grep -c '^p[123] [0-9]' '$RD/takeover_tracks.txt' 2>/dev/null)\" = 3 ]"
  sleep 3
  check "the main bash beats, no stall alert" bash -c "[ \$(( \$(date +%s) - \$(cat '$RD/takeover_beat_main') )) -lt 20 ] && ! ls '$RD'/ALERT_takeover_main_stalled_* >/dev/null 2>&1"
  kill -STOP "$TKP"; sleep 4
  t=$(cat "$RD/takeover_beat_main"); sleep 3; t2=$(cat "$RD/takeover_beat_main")
  check "main bash stopped (SIGSTOP): its beat stays" [ "$t" = "$t2" ]
  until_t 60 test -f "$RD/ALERT_takeover_main_stalled_$t.txt"
  check "stall alert for that beat" test -f "$RD/ALERT_takeover_main_stalled_$t.txt"
  check "the alert says how to stop and restart" bash -c "grep -q 'Stopping the takeover' '$RD/ALERT_takeover_main_stalled_$t.txt' && grep -q 'start it again with the same launch command' '$RD/ALERT_takeover_main_stalled_$t.txt'"
  sleep 5
  check "raised once for that beat (one log line)" [ "$(grep -c "ALERT takeover_main_stalled_$t:" "$S/takeover.log")" = 1 ]
  check "the tracks beat on meanwhile" bash -c "[ \$(( \$(date +%s) - \$(cat '$RD/takeover_beat_p3') )) -lt 20 ]"
  kill -CONT "$TKP"
  touch "$S/ctl/p1_release_SURV"
  tk_wait 240 || bad "takeover did not end in time"
  check "after SIGCONT the run ends normally" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  export V7T_STALL_S=60
}

t_overwrite() {   # the script file overwritten (cp, another length) while the takeover runs: it runs on as parsed
  setup overwrite || return
  local run="$S/run/v7_d91_takeover.sh" i
  mkdir -p "$S/run"; cp "$TK" "$run"
  { for i in $(seq 1 2500); do echo "echo STRAY_LINE_RAN >> '$S/stray'"; done; cat "$TK"; } > "$S/longer.sh"
  TKRUN=$run tk_start
  until_t 30 grep -q 'v7 takeover started' "$S/takeover.log"; sleep 2
  cp "$S/longer.sh" "$run"
  check "the running script overwritten in place by a longer file" bash -c "[ \$(stat -c %s '$run') -gt \$(stat -c %s '$TK') ]"
  D=0.2 p1_fake
  tk_wait 240 || bad "takeover did not end in time"
  check "no line of the new file ran" bash -c "[ ! -e '$S/stray' ] && ! grep -q 'STRAY_LINE_RAN\|command not found\|syntax error' '$S/takeover.log'"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_forcegate() {   # a force file counts only once the given-up profile's chain has stopped: never two C1p
  setup forcegate || return
  local a b t
  touch "$S/ctl/hold_uav-gcs-v7-p3_C1p" "$S/ctl/fail_uav-gcs-v7-p3_C1p"   # p3's C1p runs until the hold file goes, then fails
  tk_start; D=0.05 p1_fake
  until_t 60 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  until_t 60 grep -q 'uav-gcs-v7-p2 done B4s' "$S/ctl/calls.log"
  check "p3's C1p still runs" test -d "$S/ctl/busy_uav-gcs-v7-p3"
  touch "$RD/p3.abandon" "$RD/p2_c1p.force"
  until_t 60 grep -q "p2_c1p.force waits until profile 3's chain has stopped" "$S/takeover.log"
  check "p3 given up while its C1p runs: no p2_c1p_p3_abandon alert yet" bash -c "[ -d '$S/ctl/busy_uav-gcs-v7-p3' ] && ! ls '$RD'/ALERT_p2_c1p_p3_abandon* >/dev/null 2>&1"
  check "p2_c1p.force waits for p3's chain to stop: no second C1p" bash -c "! grep -q 'uav-gcs-v7-p2 start C1p' '$S/ctl/calls.log' && grep -q \"p2_c1p.force waits until profile 3's chain has stopped\" '$S/takeover.log'"
  rm -f "$S/ctl/hold_uav-gcs-v7-p3_C1p"
  until_t 150 grep -q 'uav-gcs-v7-p2 start C1p' "$S/ctl/calls.log"
  a=$(ns_of "$S" uav-gcs-v7-p3 fail C1p); b=$(ns_of "$S" uav-gcs-v7-p2 start C1p)
  check "p2's C1p only after p3's C1p has ended" lt "$a" "$b"
  check "started on the force file, logged" grep -q 'p2: C1p starts on p2_c1p.force' "$S/takeover.log"
  tk_wait 240 || bad "takeover did not end in time"
  check "v7 done" has "$S/takeover.log" 'v7 done'

  setup forcegate2 || return   # profile 1 given up while its launcher chain runs C1p
  tk_start; FAIL_AT=C1c HOLD_AT=C1c D=0.2 p1_fake
  until_t 40 test -f "$S/ctl/p1_C1p_at"; until_t 60 grep -q "p3: C1p waits for p1's SURV3" "$S/takeover.log"
  touch "$RD/p1.abandon" "$RD/p3_c1p.force"
  until_t 60 grep -q "p3_c1p.force waits until profile 1's chain has stopped" "$S/takeover.log"; sleep 2
  check "profile 1 given up while its chain runs: p3_c1p.force waits, no p3 C1p" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log' && grep -q \"p3_c1p.force waits until profile 1's chain has stopped\" '$S/takeover.log'"
  t=$(date +%s%N); touch "$S/ctl/p1_release_C1c"
  until_t 120 grep -q 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log"
  b=$(ns_of "$S" uav-gcs-v7-p3 start C1p)
  check "p3's C1p once profile 1's chain has ended" bash -c "[ -n '$b' ] && [ '$t' -lt '$b' ] && grep -q '^##### chain ended rc=1' '$RD/p1.log'"
  tk_kill
}

for t in "${SCEN[@]}"; do "t_$t"; done
echo
echo "passed $PASS, failed $FAIL"
for f in "${FAILS[@]}"; do echo "  FAIL $f"; done
[ "$FAIL" = 0 ]
