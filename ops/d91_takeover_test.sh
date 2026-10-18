#!/usr/bin/env bash
# Tests of v7_d91_takeover.sh on sandbox copies of the logs and worktrees, with a stub MATLAB
# (d91_stub_matlab.sh) and stub machine queries (d91_stub_sys.sh). Nothing outside the sandbox is
# written: p1.log, p3.log and code_commit.txt are copied once from the live logs as the starting
# state (profile 1 inside C1p, profile 3 idle at C1p after the fix script), and every V7T_*
# variable points the takeover into the sandbox.
#
#   bash d91_takeover_test.sh [sandbox dir] [scenario ...]
# Scenarios: status normal p1crash rerun reboot orphan zombie turn refuse (default: all).
HERE=$(cd "$(dirname "$0")" && pwd)
TK="$HERE/v7_d91_takeover.sh"
SB=${1:-"/c/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/d91_takeover_test"}
shift 2>/dev/null
SCEN=("$@"); [ "${#SCEN[@]}" -gt 0 ] || SCEN=(status normal p1crash rerun reboot orphan zombie turn refuse)
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
until_t() {   # until_t <seconds> <command...>: poll the condition
  local end=$(( $(date +%s) + $1 )); shift
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
ns_of() { grep " $2 $3 $4\$" "$1/ctl/calls.log" 2>/dev/null | head -1 | cut -d' ' -f1; }   # first "<worktree> <event> <stage>"
alerted() { ls "$RD"/ALERT_"$1"*.txt >/dev/null 2>&1; }
lt() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; }

# Starting state, copied once
mkdir -p "$SB/source" || exit 1
for f in p1.log p3.log code_commit.txt; do cp -p "$LIVE_LOGS/v7_d86/$f" "$SB/source/$f" || exit 1; done
git -C "$LIVE_REPO" show 9b5c9f1:code/run_stage.m | \
  sed "s/'B3m', 'build_fresh_test2', /'B3m', 'build_fresh_test2', 'B3q', 'build_fresh_test3', 'B3r', 'read_fresh_test3', /" > "$SB/source/run_stage.m"
grep -q "'B3q', 'build_fresh_test3'" "$SB/source/run_stage.m" || { echo "run_stage.m stand-in not built"; exit 1; }

setup() {   # fresh sandbox $SB/$1: logs, git repository with v7-dev and v7-p3 worktrees, origin, stubs
  CUR=$1; S="$SB/$1"; RD="$S/logs/v7_d86"
  echo "== $1"
  rm -rf "$S"; mkdir -p "$RD" "$S/temp" "$S/sys/procs" "$S/sys/state" "$S/ctl"
  cp -p "$SB/source/p1.log" "$SB/source/p3.log" "$SB/source/code_commit.txt" "$RD/"
  echo $(( $(date +%s) - 86400 )) > "$S/sys/boot"; echo 5 > "$S/sys/cpu"; echo 60 > "$S/sys/headroom"; : > "$S/sys/matlab"
  : > "$S/ctl/calls.log"
  ( set -e
    git init -q -b main "$S/repo"; cd "$S/repo"; git config core.autocrlf false
    mkdir code; cp "$SB/source/run_stage.m" code/; echo "% startup" > startup.m; echo "test" > README.md
    git add -A; git commit -q -m base
    git branch v7-dev; git checkout -q -b v7-p3
    echo '{"profile":"profile 3: four antennas","n_rx":4}' > profile.json; git add profile.json; git commit -q -m p3
    git checkout -q main
    git init -q --bare "$S/origin.git"; git remote add origin "$S/origin.git"; git push -q origin v7-dev v7-p3
    git worktree add -q "$S/uav-gcs-v7" v7-dev; git worktree add -q "$S/uav-gcs-v7-p3" v7-p3 ) || { bad "sandbox repository"; return 1; }
  export V7T_P1="$S/uav-gcs-v7" V7T_P3="$S/uav-gcs-v7-p3" V7T_P2="$S/uav-gcs-v7-p2" V7T_REPO="$S/repo" V7T_LOGS="$S/logs"
  export V7T_MATLAB="$HERE/d91_stub_matlab.sh" V7T_SYS="$HERE/d91_stub_sys.sh" V7T_SYS_DIR="$S/sys" STUB_CTL="$S/ctl"
  export TEMP; TEMP=$(cygpath -w "$S/temp"); export V7T_TEMP_WIN="$TEMP"
  export V7T_POLL=1 V7T_STEP=0.2 V7T_HB_S=1 V7T_QUIET_S=2 V7T_IDLE_POLL=1 V7T_IDLE_MAX_S=30 V7T_STALE_S=30 \
         V7T_SILENT_S=100000 V7T_HEADROOM_ALERT_S=5 STUB_DELAY=0.05
  [ "$V7T_LOGS" != "$LIVE_LOGS" ] && [ "$V7T_P1" != "/c/Users/Adi Suliman/uav-gcs-v7" ] || { echo "not a sandbox; stopped"; exit 1; }
}
tk_start() { bash "$TK" 24172 49732 >> "$S/takeover.log" 2>&1 & TKP=$!; disown "$TKP"; }
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
# FAIL_AT: the chain ends rc=1 inside that stage; HOLD_AT: waits before that stage for ctl/p1_release
p1_fake() {
  local log="$RD/p1.log" s
  ( echo "##### STAGE C1p done in 1.0 min #####" >> "$log"
    for s in C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT; do
      if [ "$s" = "${HOLD_AT:-}" ]; then until [ -f "$S/ctl/p1_release" ]; do sleep 0.2; done; fi
      echo "##### STAGE $s (fake) $(date) #####" >> "$log"; sleep "${D:-0.2}"
      if [ "$s" = "${FAIL_AT:-}" ]; then echo "Error (fake)" >> "$log"; echo "##### chain ended rc=1 $(date) #####" >> "$log"; exit 0; fi
      echo "##### STAGE $s done in 0.0 min #####" >> "$log"
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
  echo "B3q B3r" > "$RD/p2_set4.stages"
  touch -d '-1 hour' "$RD/run.lock"
  tk_start
  until_t 30 test -f "$RD/takeover.lock"
  check "takeover.lock written" [ -f "$RD/takeover.lock" ]
  until_t 10 bash -c "[ \$(( \$(date +%s) - \$(stat -c %Y '$RD/run.lock') )) -lt 5 ]"
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
  check "p2: B stages with B3m and the set-4 stages" grep -q ' AB A0,A4v,A5,A6,B1,B2,B2F,B3n,B3m,B3q,B3r,B3,B3a,B4,OOD,B4s ' "$RD/p2.log"
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
}

t_p1crash() {
  setup p1crash || return
  echo "B3z" > "$RD/p2_set4.stages"
  tk_start; sleep 2
  FAIL_AT=C1c D=0.2 p1_fake
  until_t 15 alerted p1_failed; check "alert on profile 1's failure" alerted p1_failed
  sleep 3
  check "p3 does not start C1p" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  check "p2 not started" [ ! -d "$S/uav-gcs-v7-p2" ]
  check "no MATLAB for profile 1 without a go file" bash -c "! grep -q 'uav-gcs-v7 call' '$S/ctl/calls.log'"
  touch -d '-10 min' "$RD/p1_resume.go"; sleep 3
  check "an old go file is not taken" [ -f "$RD/p1_resume.go" ]
  check "alert on the old go file" alerted stale_p1_resume.go
  rm -f "$RD/p1_resume.go"; sleep 1.1; echo go > "$RD/p1_resume.go"
  until_t 20 grep -q 'takeover SRC [0-9a-f]* FROM 14 C1c A0 0 ' "$RD/p1.log"
  check "profile 1 goes on from C1c under a new part" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 14 C1c A0 0 #####$' "$RD/p1.log"
  check "the go file is renamed" bash -c "ls '$RD'/p1_resume.go.used_* >/dev/null 2>&1 && [ ! -f '$RD/p1_resume.go' ]"
  until_t 20 grep -q "uav-gcs-v7 call run_stage('C1c','SURV','SURV3'" "$S/ctl/calls.log"
  check "profile 1's MATLAB: C1c to RPT" grep -q "uav-gcs-v7 call run_stage('C1c','SURV','SURV3'" "$S/ctl/calls.log"
  until_t 30 alerted p2_set4_invalid; check "alert on a wrong set-4 stage" alerted p2_set4_invalid
  check "p2 waits on it" bash -c "! grep -q 'uav-gcs-v7-p2 call' '$S/ctl/calls.log'"
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
  until_t 15 alerted p3_rerun_invalid; check "alert on a C stage in the go file" alerted p3_rerun_invalid
  check "nothing run on it" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  touch "$S/ctl/fail_uav-gcs-v7-p3_B4"; sleep 1.1
  echo "B2F B3 B3a B4 OOD B4s B3m" > "$RD/p3_brerun.go"
  until_t 20 grep -q '^##### rerun ended rc=1' "$RD/p3.log"
  check "rerun part: A0 first, its list and request id" grep -q '^##### PART [0-9_]* takeover-rerun SRC [0-9a-f]* FROM 6 B2F A0 1 RERUN B2F,B3,B3a,B4,OOD,B4s,B3m GO [0-9a-f]* #####$' "$RD/p3.log"
  check "rerun MATLAB call" grep -q "uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B3a','B4','OOD','B4s','B3m')" "$S/ctl/calls.log"
  check "rerun failure recorded" grep -q '^##### rerun ended rc=1' "$RD/p3.log"
  until_t 10 alerted p3_rerun_failed; check "alert on the failed rerun" alerted p3_rerun_failed
  touch "$S/ctl/p1_release"; until_t 20 test -f "$S/ctl/p1_surv3_at"; sleep 4
  check "after a failed rerun C1p does not start" bash -c "! grep -q 'FROM 13 C1p' '$RD/p3.log'"
  sleep 1.1; touch "$RD/p3_brerun.go"
  until_t 20 grep -q '^##### rerun ended rc=0' "$RD/p3.log"
  check "a new version of the go file reruns its whole list" [ "$(grep -c "uav-gcs-v7-p3 call run_stage('A0','B2F','B3','B3a','B4','OOD','B4s','B3m')" "$S/ctl/calls.log")" = 2 ]
  touch "$S/ctl/fail_uav-gcs-v7-p3_C1p"
  until_t 20 alerted p3_failed; check "alert on P3's failed C1p" alerted p3_failed
  check "C part after the rerun" bash -c "[ \$(grep -n 'rerun ended rc=0' '$RD/p3.log' | tail -1 | cut -d: -f1) -lt \$(grep -n 'FROM 13 C1p A0 0' '$RD/p3.log' | tail -1 | cut -d: -f1) ]"
  sleep 1.1; echo "B3" > "$RD/p3_brerun.go"; sleep 1.1; echo go > "$RD/p3_resume.go"
  until_t 20 alerted p3_go_ignored; check "a go file after C1p started is ignored" alerted p3_go_ignored
  tk_wait 240 || bad "takeover did not end in time"
  check "no rerun after C1p started" [ "$(grep -c 'takeover-rerun' "$RD/p3.log")" = 2 ]
  check "p3 resumed C1p after its failure" [ "$(grep -c 'FROM 13 C1p A0 0' "$RD/p3.log")" = 2 ]
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
}

t_reboot() {
  setup reboot || return
  mkdir -p "$S/uav-gcs-v7-p3/data"; echo partial > "$S/uav-gcs-v7-p3/data/policy_pools.mat"
  tk_start; HOLD_AT=SURV D=0.2 p1_fake; until_t 30 test -f "$RD/takeover.lock"; sleep 2
  local out
  out=$(timeout 30 bash "$TK" 24172 49732 2>&1); echo "$out" | sed 's/^/     | /'
  check "a second takeover refuses while the first is alive" grep -q 'was alive .* not started' <<< "$out"
  reboot
  tk_start
  until_t 15 alerted p1_cut; check "alert: profile 1 cut by the reboot" alerted p1_cut
  check "the takeover started again after the reboot" grep -q 'v7 takeover started' <<< "$(tail -5 "$S/takeover.log")"
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
    "66666|0|$M \"run_stage('KPI')\"" > "$S/sys/matlab"
  echo 50 > "$S/sys/cpu"
  tk_start; sleep 4
  check "a live pipeline MATLAB holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  grep -v 66666 "$S/sys/matlab" > "$S/sys/m2"; mv "$S/sys/m2" "$S/sys/matlab"; sleep 3
  check "CPU at 50 % holds LAT back" bash -c "! grep -q 'start LAT' '$S/ctl/calls.log'"
  t_free=$(date +%s%N); echo 5 > "$S/sys/cpu"
  tk_wait 120 || bad "takeover did not end in time"
  b=$(ns_of "$S" uav-gcs-v7 start LAT)
  check "LAT once idle (zombie, exited stage session, smoke and copies not counted)" lt "$t_free" "$b"
  check "machine line: idle, no pipeline session, three other live sessions" grep -q 'live pipeline MATLAB sessions: 0, live MATLAB processes in all: 3 (idle)' "$RD/p1.log"
  check "profile 2 given up: no LAT" has "$S/takeover.log" 'p2 given up: no LAT'
  for g in p1 p3; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  check "p3 stopped after RPT before its end marker: marker written, no MATLAB" bash -c "grep -q 'chain ended rc=0 (its stages were done before an interruption)' '$RD/p3.log' && ! grep -q 'uav-gcs-v7-p3 call run_stage()' '$S/ctl/calls.log'"
}

t_orphan() {   # the takeover's bash processes killed while its MATLAB runs on: no second MATLAB there
  setup orphan || return
  export V7T_STALE_S=5
  echo 25 > "$S/ctl/slow_uav-gcs-v7-p3_C1p"
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
  until_t 20 alerted ml_alive_p3; check "alert: an earlier MATLAB still runs in the worktree" alerted ml_alive_p3
  tk_wait 240 || bad "takeover did not end in time"
  check "no two MATLAB in one worktree" bash -c "! grep -q CONCURRENT '$S/ctl/calls.log'"
  check "p3's C1p ran once" [ "$(grep -c 'uav-gcs-v7-p3 start C1p' "$S/ctl/calls.log")" = 1 ]
  check "its end marker written after the orphan finished" grep -q 'chain ended rc=0 (its stages were done before an interruption)' "$RD/p3.log"
  check "v7 done" has "$S/takeover.log" 'v7 done'
  for g in p1 p3 p2; do check "$g: final part LAT..RPT and the bundle" final_ok "$g"; done
  export V7T_STALE_S=30
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
  until_t 15 alerted turn_holder_32824; check "alert: the turn holder has exited" alerted turn_holder_32824
  check "turn file untouched" [ "$(md5sum < "$S/temp/uav_gcs_parallel_turn.txt")" = "$m0" ] && [ "$(stat -c %Y "$S/temp/uav_gcs_parallel_turn.txt")" = "$t0" ]
  until_t 10 alerted p1_silent; check "alert: profile 1's log silent" alerted p1_silent
  until_t 10 alerted p3_open; check "alert: p3's part has a stage open" alerted p3_open
  check "nothing run in p3 while its stage is open" bash -c "! grep -q 'uav-gcs-v7-p3 call' '$S/ctl/calls.log'"
  sleep 1.1; echo go > "$RD/p3_resume.go"
  until_t 20 grep -q "uav-gcs-v7-p3 call run_stage('A0','B4s')" "$S/ctl/calls.log"
  check "p3 goes on at B4s with A0 first" grep -q '^##### PART [0-9_]* takeover SRC [0-9a-f]* FROM 12 B4s A0 1 #####$' "$RD/p3.log"
  printf 99999 > "$S/temp/uav_gcs_parallel_turn.txt"
  until_t 10 grep -q 'names PID 99999, no live MATLAB (none)' "$S/takeover.log"
  check "a holder that is gone: logged, no alert" bash -c "grep -q 'names PID 99999, no live MATLAB' '$S/takeover.log' && [ ! -f '$RD/ALERT_turn_holder_99999.txt' ]"
  tk_kill
  export V7T_SILENT_S=100000
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
}

for t in "${SCEN[@]}"; do "t_$t"; done
echo
echo "passed $PASS, failed $FAIL"
for f in "${FAILS[@]}"; do echo "  FAIL $f"; done
[ "$FAIL" = 0 ]
