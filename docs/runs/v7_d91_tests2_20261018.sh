#!/usr/bin/env bash
# d91-speed tests in a short path: one single-thread MATLAB job at a time, each only when
# v7_d91_speed_gate.ps1 says OK (>= 35 GB commit free, at most one other running non-pipeline
# MATLAB); checked every 10 min, a job given up after 24 h of waiting.
#
#   bash v7_d91_tests2.sh <new SHA>
#
# Works only in git archive exports under C:\Users\Adi Suliman\d91q (new: <new SHA>, old:
# 9b5c9f1, the baseline), with its own short TEMP (Stateflow build paths stay below 260
# characters); never in a live worktree. Takes no parallel turn, opens no pool, sends no
# signal to any process.
# Jobs: 1 focused d91 tests (new); 2 full test_core (new); 3 full test_core (old, baseline).
# Logs: v7_d91_tests2_<job>.log; queue: v7_d91_tests2_queue.log; V7TESTS/V7FAIL lines and
# the reason of every failure: v7_d91_tests2_summary.log.
#
# Start detached (PowerShell):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_tests2.sh'' <SHA> >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_tests2_queue.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}

NEW=${1:-}
OLD=9b5c9f1
L="/c/Users/Adi Suliman/uav-gcs-logs"
REPO="/c/Users/Adi Suliman/uav-gcs-d91-speed"
Q="/c/Users/Adi Suliman/d91q"
MATLAB="/c/Program Files/MATLAB/R2026a/bin/matlab.exe"
GATE='C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_speed_gate.ps1'
POLL=600
WAIT_MAX=$((24 * 3600))
LOCK="$L/v7_d91_tests2.lock.d"

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

[[ "$NEW" =~ ^[0-9a-f]{7,40}$ ]] || { say "usage: bash v7_d91_tests2.sh <new SHA>"; exit 1; }
mkdir "$LOCK" 2>/dev/null || { say "another queue holds $LOCK; not started"; exit 1; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

say "d91 tests: new $NEW, old $OLD, working copies under $Q"
rm -rf "$Q/new" "$Q/old" && mkdir -p "$Q/new" "$Q/old" "$Q/tmp" || exit 1
for t in new old; do
  sha=$NEW; [ "$t" = old ] && sha=$OLD
  ( set -o pipefail; git -C "$REPO" archive --format=tar "$sha" | tar -x -C "$Q/$t" ) || { say "export of $sha failed"; exit 1; }
done
TW=$(cygpath -w "$Q/tmp")                              # the jobs' own short TEMP
say "exports ready; TEMP of the jobs $TW"

INIT="startup; evalc('init_params'); maxNumCompThreads(1); fprintf('V7TEMP %s\n', tempdir);"
FOCUS="{'test_surv3_run_ids', 'test_shadow_attitude', 'test_pool_checkpoint_resume', 'test_pool_schedule', 'test_pool_cell_fec_twins', 'test_fec_twin_configs', 'test_closed_loop_truth', 'test_m_files_parse'}"
TESTS="f = {r(~[r.Passed]).Name}; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); if ~isempty(f), fprintf('V7FAIL %s\n', f{:}); end; exit(double(isempty(r) || ~all([r.Passed])))"

NAMES=(focus new old)
DIRS=("$Q/new" "$Q/new" "$Q/old")
CMDS=(
  "$INIT r = runtests('code/tests/test_core.m', 'ProcedureName', $FOCUS); $TESTS"
  "$INIT r = runtests('code/tests/test_core.m'); $TESTS"
  "$INIT r = runtests('code/tests/test_core.m'); $TESTS"
)

gate() { powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$GATE" 2>&1 | tr -d '\r' | tail -1; }

for i in "${!NAMES[@]}"; do
  n=${NAMES[$i]}; log="$L/v7_d91_tests2_$n.log"
  : > "$log"
  t0=$(date +%s)
  while :; do
    g=$(gate)
    case "$g" in OK*) say "job $n: $g"; break;; esac
    if [ $(( $(date +%s) - t0 )) -ge "$WAIT_MAX" ]; then say "job $n: gave up after 24 h of waiting ($g)"; break 2; fi
    say "job $n waits: ${g:-no answer}"
    sleep "$POLL"
  done
  say "job $n starts in ${DIRS[$i]} (log $log)"
  ( cd "${DIRS[$i]}" && TEMP="$TW" TMP="$TW" "$MATLAB" -singleCompThread -batch "${CMDS[$i]}" ) >> "$log" 2>&1
  rc=$?
  say "job $n ended rc=$rc ($(( ($(date +%s) - t0) / 60 )) min with the wait)"
done

# Summary: totals, failed tests and the first diagnostic line of every failure
{ echo "d91 tests summary $(date '+%Y-%m-%d %H:%M:%S'), new $NEW, old $OLD, TEMP $TW"
  for n in "${NAMES[@]}"; do
    f="$L/v7_d91_tests2_$n.log"
    [ -f "$f" ] || continue
    grep -hE 'V7TEMP|V7TESTS|V7FAIL' "$f" | sed "s/^/$n: /"
    awk -v n="$n" '
      /^(Error occurred in|Verification failed in|Assertion failed in) test_core\// { t = $0; sub(/ and it did not.*/, "", t); want = 1; next }
      want && /(Error using|Error in|verify[A-Za-z]+ failed|--> |Build failed|Undefined|Unable|not found|exceed)/ {
        line = $0; gsub(/^ +/, "", line); print n ": REASON " t " :: " substr(line, 1, 220); want = 0 }
    ' "$f"
  done; } > "$L/v7_d91_tests2_summary.log"
say "queue done; summary in $L/v7_d91_tests2_summary.log"
