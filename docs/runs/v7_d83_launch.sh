#!/usr/bin/env bash
# v7 full rerun from A0 on the code with D81, D82 and D83 (every profile on C:).
# 1. Archive the outputs of the first reading (data/ and results/ are moved aside, not deleted).
# 2. Cherry-pick the fixes into v7-dev (profile 1) and v7-p3 (profile 3), push, test gate.
# 3. Profile 1: every stage, with its heavy parallel stages (C1p, C1c, SURV, SURV3) first.
#    Profile 3: A0-B4s, then C1p onward once profile 1 has passed SURV3 (one parallel turn at a time).
#    Profile 2: starts when profile 1 has finished; A0-B4s, then C1p onward once profile 3 has passed SURV3.
# 4. Decision latency (LAT) on the idle machine and the console bundles, for every finished profile.
# Launch detached (PowerShell):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d83_launch.sh'' > ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d83_launch.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}
V7="/c/Users/Adi Suliman/uav-gcs-v7"
P3="/c/Users/Adi Suliman/uav-gcs-v7-p3"
P2="/c/Users/Adi Suliman/uav-gcs-v7-p2"
L="/c/Users/Adi Suliman/uav-gcs-logs"
FIX="7135c74 19ec5bb 4cfe2bb D83COMMITS"
STAMP=$(date +%Y%m%d_%H%M)
AB="'A0','A4v','A5','A6','B1','B2','B2F','B3n','B3','B3a','B4','OOD','B4s'"
HEAVY_FIRST="'C1p','C1c','SURV','SURV3','C1d','C2','C2e','C2g','C2u','GAL','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT'"
done_or_failed() { grep -q "STAGE RPT done\|ERROR: MATLAB error\|##### chain ended" "$1" 2>/dev/null; }
past_surv3() { grep -q "STAGE SURV3 done" "$1" 2>/dev/null || done_or_failed "$1"; }
case "$FIX" in *D83COMMITS*) echo "FIX not set; not started $(date)"; exit 1;; esac
# 1. Archive
for W in "$V7" "$P3"; do
  A="$W/archive/first_reading_$STAMP"
  mkdir -p "$A" || { echo "archive failed in $W $(date)"; exit 1; }
  for d in data results; do
    if [ -d "$W/$d" ]; then mv "$W/$d" "$A/$d" || { echo "archive of $d failed in $W $(date)"; exit 1; }; fi
    mkdir -p "$W/$d"
  done
  echo "first reading moved to $A $(date)"
done
for f in full_v7p1 full_v7p3 full_v7p2; do [ -f "$L/$f.log" ] && mv "$L/$f.log" "$L/${f}_first_reading_$STAMP.log"; done
# 2. Code
for W in "$V7" "$P3"; do
  for C in $FIX; do
    git -C "$W" cherry-pick "$C" >/dev/null 2>&1 || { git -C "$W" cherry-pick --abort; echo "cherry-pick $C failed in $W $(date)"; exit 1; }
  done
  echo "fixes applied in $W: $(git -C "$W" log --oneline -1)"
done
git -C "$V7" push -q origin v7-dev; git -C "$P3" push -q origin v7-p3
cd "$V7" || exit 1
matlab -batch "startup; evalc('init_params'); r = runtests('code/tests/test_core.m'); fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(~all([r.Passed])))" > "$L/v7_tests_gate_d83.log" 2>&1
P=$(grep -o "V7TESTS [0-9]*/[0-9]*" "$L/v7_tests_gate_d83.log"); A=${P#V7TESTS }
if [ -z "$A" ] || [ "${A%/*}" != "${A#*/}" ]; then echo "tests '$A'; not started $(date)"; exit 1; fi
echo "tests $A $(date)"
# 3. Runs
(cd "$V7" && matlab -batch "run_stage($AB,$HEAVY_FIRST)" > "$L/full_v7p1.log" 2>&1; \
  echo "##### chain ended $(date)" >> "$L/full_v7p1.log") &
echo "profile 1 started $(date)"
(cd "$P3" && matlab -batch "run_stage($AB)" > "$L/full_v7p3.log" 2>&1 && \
  { until past_surv3 "$L/full_v7p1.log"; do sleep 300; done; } && \
  echo "profile 3: C1p onward $(date)" >> "$L/full_v7p3.log" && \
  matlab -batch "run_stage($HEAVY_FIRST)" >> "$L/full_v7p3.log" 2>&1; \
  echo "##### chain ended $(date)" >> "$L/full_v7p3.log") &
echo "profile 3 started (C1p after profile 1's SURV3) $(date)"
until done_or_failed "$L/full_v7p1.log"; do sleep 300; done
if grep -q "STAGE RPT done" "$L/full_v7p1.log"; then
  if [ ! -d "$P2" ]; then
    git -C "$V7" worktree add "$P2" -b v7-p2 v7-dev >/dev/null 2>&1 || exit 1
    printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
    git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" && git -C "$P2" push -q -u origin v7-p2
  fi
  mkdir -p "$P2/data"
  (cd "$P2" && matlab -batch "run_stage($AB)" > "$L/full_v7p2.log" 2>&1 && \
    { until past_surv3 "$L/full_v7p3.log"; do sleep 300; done; } && \
    echo "profile 2: C1p onward $(date)" >> "$L/full_v7p2.log" && \
    matlab -batch "run_stage($HEAVY_FIRST)" >> "$L/full_v7p2.log" 2>&1; \
    echo "##### chain ended $(date)" >> "$L/full_v7p2.log") &
  echo "profile 2 started on C: (C1p after profile 3's SURV3) $(date)"
else
  echo "profile 1 did not finish (see full_v7p1.log); profile 2 not started $(date)"
fi
wait
echo "v7 runs ended $(date)"
for D in "$V7:full_v7p1" "$P3:full_v7p3" "$P2:full_v7p2"; do
  W=${D%:*}; G=${D##*:}
  grep -q "STAGE RPT done" "$L/$G.log" 2>/dev/null || { echo "$G did not finish: no LAT $(date)"; continue; }
  (cd "$W" && matlab -batch "run_stage('LAT','KPI','DASH','WEAK','RPT')" >> "$L/v7_latency.log" 2>&1)
  (cd "$W" && matlab -batch "startup; export_gui_bundle('C:/Users/Adi Suliman/uav-gcs-v7/profiles')" >> "$L/v7_latency.log" 2>&1)
done
echo "v7 done $(date)"
