#!/usr/bin/env bash
# d91-speed proofs and profile (docs/d91_speed.md on branch d91-speed): one single-thread MATLAB
# job at a time, each only when v7_d91_speed_gate.ps1 says OK (>= 35 GB commit free, at most one
# other busy non-pipeline MATLAB); checked every 10 min, a job given up after 24 h of waiting.
#
#   bash v7_d91_speed_proofs.sh <new SHA>
#
# Works only in scratch exports (git archive) of 9b5c9f1 (old) and <new SHA> (new) under $S,
# never in a live worktree; its MATLAB sessions get their own TEMP (no .dmr file in the
# pipeline's tempdir), never take the parallel turn and open no pool except the one-worker
# check of job 5 (own job storage). Sends no signal to any process.
# Jobs: 1 static proof (a) + detector copy + focused tests; 2 old reduced pools; 3 new reduced
# pools + proof (b); 4 order proof (c); 5 parfor options on a one-worker pool; 6 profile;
# 7 full test_core. Logs: v7_d91_speed_<job>.log; queue: v7_d91_speed_queue.log; the
# D91PROOF/V7TESTS lines of all jobs: v7_d91_speed_summary.log.
#
# Start detached (PowerShell):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_speed_proofs.sh'' <SHA> >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_speed_queue.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}

NEW=${1:-}
OLD=9b5c9f1
L="/c/Users/Adi Suliman/uav-gcs-logs"
REPO="/c/Users/Adi Suliman/uav-gcs-d91-speed"
S="/c/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/d91_speed"
SW="C:/Users/ADISUL~1/AppData/Local/Temp/claude/C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms/0ff3360f-912b-4701-bfb0-77d6917b5fc3/scratchpad/d91_speed"
MATLAB="/c/Program Files/MATLAB/R2026a/bin/matlab.exe"
GATE='C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_speed_gate.ps1'
DET_FROM="C:/Users/Adi Suliman/uav-gcs-b3m-p1/data"
POLL=600
WAIT_MAX=$((24 * 3600))
LOCK="$L/v7_d91_speed.lock.d"

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

[[ "$NEW" =~ ^[0-9a-f]{7,40}$ ]] || { say "usage: bash v7_d91_speed_proofs.sh <new SHA>"; exit 1; }
mkdir "$LOCK" 2>/dev/null || { say "another queue holds $LOCK; not started"; exit 1; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

say "d91-speed queue: old $OLD, new $NEW, scratch $S"
mkdir -p "$S/old" "$S/new" "$S/drv" "$S/res" "$S/det" "$S/tmp" "$S/jobs" || exit 1
if [ ! -f "$S/old/startup.m" ]; then
  ( set -o pipefail; git -C "$REPO" archive --format=tar "$OLD" | tar -x -C "$S/old" ) || { say "export of $OLD failed"; exit 1; }
fi
rm -rf "$S/new" && mkdir -p "$S/new" || exit 1
( set -o pipefail; git -C "$REPO" archive --format=tar "$NEW" | tar -x -C "$S/new" ) || { say "export of $NEW failed"; exit 1; }
cp "$S/new/code/dev/"dev_d91_*.m "$S/drv/" || exit 1
TW=$(cygpath -w "$S/tmp")                              # the jobs' own TEMP
say "exports ready; TEMP of the jobs $TW"

SRC="struct('detector', '$SW/det/trained_detector.mat', 'splits', '$SW/det/splits.mat')"
INIT="startup; evalc('init_params'); maxNumCompThreads(1);"
INEW="$INIT addpath(fullfile(pwd, 'code', 'dev'));"       # the proof scripts (code/dev is off the path)
FOCUS="{'test_fec_twin_configs', 'test_closed_loop_truth', 'test_pool_cell_fec_twins', 'test_pool_schedule', 'test_pool_checkpoint_resume', 'test_m_files_parse'}"
TESTS="f = {r(~[r.Passed]).Name}; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); if ~isempty(f), fprintf('V7FAIL %s\n', f{:}); end; exit(double(isempty(r) || ~all([r.Passed])))"

NAMES=(static oldpool newpool order parfor profile tests)
DIRS=("$S/new" "$S/old" "$S/new" "$S/new" "$S/new" "$S/new" "$S/new")
CMDS=(
  "$INEW try, D = load('$DET_FROM/trained_detector.mat', 'net', 'classes', 'ood'); save('$SW/det/trained_detector.mat', '-struct', 'D', '-v7.3'); [norm, classes] = split_norm('$DET_FROM/splits.mat'); save('$SW/det/splits.mat', 'norm', 'classes'); clear D norm classes; disp('detector copied'); catch e, disp(['detector not copied: ' e.message]); end; dev_d91_fec_static; r = runtests('code/tests/test_core.m', 'ProcedureName', $FOCUS); $TESTS"
  "$INIT addpath('$SW/drv', '-end'); dev_d91_pool_run('$SW/res/old.mat', $SRC);"
  "$INEW dev_d91_pool_run('$SW/res/new.mat', $SRC); dev_d91_compare('$SW/res/old.mat', '$SW/res/new.mat', 'B_old_vs_new');"
  "$INEW dev_d91_order('$SW/res', $SRC); dev_d91_compare('$SW/res/new.mat', '$SW/res/order_1.mat', 'C_vs_B');"
  "$INEW dev_d91_parfor_options('$SW/jobs');"
  "$INEW dev_d91_profile('$SW/res', $SRC);"
  "$INEW r = runtests('code/tests/test_core.m'); $TESTS"
)

gate() { powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$GATE" 2>&1 | tr -d '\r' | tail -1; }

for i in "${!NAMES[@]}"; do
  n=${NAMES[$i]}; log="$L/v7_d91_speed_$n.log"
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

{ echo "d91-speed summary $(date '+%Y-%m-%d %H:%M:%S'), new $NEW, old $OLD"
  for n in "${NAMES[@]}"; do
    f="$L/v7_d91_speed_$n.log"
    [ -f "$f" ] && grep -hE 'D91PROOF|V7TESTS|V7FAIL|runs -> |checked, ' "$f" | sed "s/^/$n: /"
  done; } > "$L/v7_d91_speed_summary.log"
say "queue done; summary in $L/v7_d91_speed_summary.log"
