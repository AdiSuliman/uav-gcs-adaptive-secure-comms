#!/usr/bin/env bash
# Resume the v7 full runs after an interruption: each profile restarts at the first stage its
# old log started but did not finish (completed stages are kept in that profile's data/ and
# results/). Profile 1 and profile 3 run together; profile 2 starts when profile 1 has ended;
# then decision latency (LAT) on the idle machine and the console bundles.
# Usage (Git Bash):  bash v7_resume.sh [P3_PATH] [OLD_LOG_DIR]
#   P3_PATH      profile-3 worktree (default /d/uav-gcs-v7-p3; after a drive swap it may be /e/...)
#   OLD_LOG_DIR  folder with full_v7p1.log / full_v7p3.log of the interrupted run
# Logs of the resumed run go to /c/Users/Adi Suliman/uav-gcs-logs (a permanent folder, not Temp).
# Launch it detached from any app session (PowerShell), so closing the app does not stop it:
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-v7/docs/drive_swap/v7_resume.sh'' > ''/c/Users/Adi Suliman/uav-gcs-logs/v7_resume.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-v7'}
V7="/c/Users/Adi Suliman/uav-gcs-v7"
P3="${1:-/d/uav-gcs-v7-p3}"
P2="$(dirname "$P3")/uav-gcs-v7-p2"
OLD="${2:-/c/Users/Adi Suliman/uav-gcs-logs/interrupted_20261006}"
L="/c/Users/Adi Suliman/uav-gcs-logs"
mkdir -p "$L"
ALL=(A0 A4v A5 A6 B1 B2 B2F B3 B3a B4 OOD B4s C1p C1c C1d C2 C2e C2g C2u GAL SURV SURV3 OHP GCSA EDGE KPI DASH WEAK RPT)
from_stage() {   # first stage of ALL that the log started without finishing (A0 when no log)
  local log="$1" st
  for st in "${ALL[@]}"; do
    grep -q "##### STAGE $st done" "$log" 2>/dev/null || { echo "$st"; return; }
  done
  echo DONE
}
stage_list() {   # quoted MATLAB argument list from stage $1 to the end
  local s="$1" on=0 out="" st
  for st in "${ALL[@]}"; do
    [ "$st" = "$s" ] && on=1
    [ $on = 1 ] && out="$out,'$st'"
  done
  echo "${out#,}"
}
done_or_failed() { grep -q "STAGE RPT done\|ERROR: MATLAB error" "$1" 2>/dev/null; }
cd "$V7" || exit 1
matlab -batch "startup; evalc('init_params'); r = runtests('code/tests/test_core.m'); fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(~all([r.Passed])))" > "$L/v7_tests_gate.log" 2>&1
P=$(grep -o "V7TESTS [0-9]*/[0-9]*" "$L/v7_tests_gate.log"); A=${P#V7TESTS }
if [ -z "$A" ] || [ "${A%/*}" != "${A#*/}" ]; then echo "v7 tests '$A'; not resumed $(date)"; exit 1; fi
echo "v7 tests $A $(date)"
S1=$(from_stage "$OLD/full_v7p1.log"); S3=$(from_stage "$OLD/full_v7p3.log")
echo "profile 1 resumes at $S1, profile 3 at $S3 ($P3)"
if [ "$S1" != DONE ]; then (cd "$V7" && matlab -batch "run_stage($(stage_list "$S1"))" > "$L/full_v7p1.log" 2>&1) & fi
if [ "$S3" != DONE ]; then (cd "$P3" && matlab -batch "run_stage($(stage_list "$S3"))" > "$L/full_v7p3.log" 2>&1) & fi
until [ "$S1" = DONE ] || done_or_failed "$L/full_v7p1.log"; do sleep 300; done
if [ ! -d "$P2" ]; then
  git -C "$V7" worktree add "$P2" -b v7-p2 v7-dev >/dev/null 2>&1 || exit 1
  printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
  git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" && git -C "$P2" push -q -u origin v7-p2
fi
mkdir -p "$P2/data"
(cd "$P2" && matlab -batch "run_stage($(stage_list A0))" > "$L/full_v7p2.log" 2>&1) &
echo "v7 profile 2 started $(date)"
wait
echo "v7 runs ended $(date)"
for D in "$V7" "$P3" "$P2"; do
  (cd "$D" && matlab -batch "run_stage('LAT','KPI','DASH','WEAK','RPT')" >> "$L/v7_latency.log" 2>&1)
done
for D in "$V7" "$P3" "$P2"; do
  (cd "$D" && matlab -batch "startup; export_gui_bundle('C:/Users/Adi Suliman/uav-gcs-v7/profiles')" >> "$L/v7_latency.log" 2>&1)
done
echo "v7 done $(date)"
