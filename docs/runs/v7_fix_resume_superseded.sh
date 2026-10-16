#!/usr/bin/env bash
# Apply the fusion fix (D81) and the test-reading changes (D82), then continue v7.
# Precondition: profile 1 has finished C1p (its log shows "STAGE C1p done") and every v7
# MATLAB run and launcher has been stopped.
# Both profiles: archive the outputs of the first detector reading, cherry-pick the fixes,
# then B2F, the second test set (B3n), B3, B4 and B4s.
# Profile 1: re-key its pools, then C1c and the other heavy parallel stages (SURV, SURV3) first,
# then the rest. Profile 3: its C1p starts once profile 1 has passed SURV3 (or ended), so
# profile 1 never waits for profile 3's C1p for the parallel turn.
# Profile 2 (on C:) starts when profile 1 ends; then LAT on the idle machine and the bundles.
V7="/c/Users/Adi Suliman/uav-gcs-v7"
P3="/d/uav-gcs-v7-p3"
P2="/c/Users/Adi Suliman/uav-gcs-v7-p2"
L="/c/Users/Adi Suliman/uav-gcs-logs"
FIX="7135c74 19ec5bb 4cfe2bb"
STAMP=$(date +%Y%m%d_%H%M)
ALL="'A0','A4v','A5','A6','B1','B2','B2F','B3n','B3','B3a','B4','OOD','B4s','C1p','C1c','C1d','C2','C2e','C2g','C2u','GAL','SURV','SURV3','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT'"
REDET="'B2F','B3n','B3','B4','B4s'"
AFTER_C1P="'C1c','SURV','SURV3','C1d','C2','C2e','C2g','C2u','GAL','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT'"
FROM_C1P="'C1p','C1c','C1d','C2','C2e','C2g','C2u','GAL','SURV','SURV3','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT'"
done_or_failed() { grep -q "STAGE RPT done\|ERROR: MATLAB error\|##### chain ended" "$1" 2>/dev/null; }
# 1. Archive the first reading (copies; results/ and data/ are not in git)
for W in "$V7" "$P3"; do
  A="$W/archive/prefix_D81_$STAMP"
  mkdir -p "$A/data" || { echo "archive failed in $W $(date)"; exit 1; }
  cp -p -r "$W/results" "$A/" || { echo "archive failed in $W $(date)"; exit 1; }
  cp -p "$W/data/fusion.mat" "$A/data/" || { echo "archive failed in $W $(date)"; exit 1; }
  echo "first reading archived in $A $(date)"
done
# The latency files of profile 1 come from an earlier smoke detector; LAT writes them again at the end
mkdir -p "$V7/archive/prefix_D81_$STAMP/stale"
for f in "$V7"/results/latency.*; do [ -f "$f" ] && mv "$f" "$V7/archive/prefix_D81_$STAMP/stale/"; done
# 2. Code
for W in "$V7" "$P3"; do
  for C in $FIX; do
    git -C "$W" cherry-pick "$C" >/dev/null 2>&1 || { git -C "$W" cherry-pick --abort; echo "cherry-pick $C failed in $W $(date)"; exit 1; }
  done
  echo "fixes applied in $W: $(git -C "$W" log --oneline -1)"
done
git -C "$V7" push -q origin v7-dev; git -C "$P3" push -q origin v7-p3
cd "$V7" || exit 1
matlab -batch "startup; evalc('init_params'); r = runtests('code/tests/test_core.m'); fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(~all([r.Passed])))" > "$L/v7_tests_gate_fix.log" 2>&1
P=$(grep -o "V7TESTS [0-9]*/[0-9]*" "$L/v7_tests_gate_fix.log"); A=${P#V7TESTS }
if [ -z "$A" ] || [ "${A%/*}" != "${A#*/}" ]; then echo "tests '$A'; not continued $(date)"; exit 1; fi
echo "tests $A $(date)"
for f in full_v7p1 full_v7p3; do [ -f "$L/$f.log" ] && mv "$L/$f.log" "$L/${f}_before_fix.log"; done
# 3. Runs
(cd "$V7" && matlab -batch "run_stage($REDET)" > "$L/full_v7p1.log" 2>&1 && \
  matlab -batch "startup; rekey_pools" >> "$L/full_v7p1.log" 2>&1 && \
  matlab -batch "run_stage($AFTER_C1P)" >> "$L/full_v7p1.log" 2>&1; \
  echo "##### chain ended $(date)" >> "$L/full_v7p1.log") &
echo "profile 1: B2F-B4s, re-key, C1c onward started $(date)"
(cd "$P3" && matlab -batch "run_stage($REDET)" > "$L/full_v7p3.log" 2>&1 && \
  { until grep -q "STAGE SURV3 done" "$L/full_v7p1.log" 2>/dev/null || done_or_failed "$L/full_v7p1.log"; do sleep 300; done; } && \
  echo "profile 3: C1p onward $(date)" >> "$L/full_v7p3.log" && \
  matlab -batch "run_stage($FROM_C1P)" >> "$L/full_v7p3.log" 2>&1; \
  echo "##### chain ended $(date)" >> "$L/full_v7p3.log") &
echo "profile 3: B2F-B4s started, C1p after profile 1's SURV3 $(date)"
until done_or_failed "$L/full_v7p1.log"; do sleep 300; done
if grep -q "STAGE RPT done" "$L/full_v7p1.log"; then
  if [ ! -d "$P2" ]; then
    git -C "$V7" worktree add "$P2" -b v7-p2 v7-dev >/dev/null 2>&1 || exit 1
    printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
    git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" && git -C "$P2" push -q -u origin v7-p2
  fi
  mkdir -p "$P2/data"
  (cd "$P2" && matlab -batch "run_stage($ALL)" > "$L/full_v7p2.log" 2>&1; \
    echo "##### chain ended $(date)" >> "$L/full_v7p2.log") &
  echo "profile 2 started on C: $(date)"
else
  echo "profile 1 did not finish (see full_v7p1.log); profile 2 not started $(date)"
fi
wait
echo "v7 runs ended $(date)"
# Decision latency on the idle machine, then the reports again and the console bundles, for
# every profile that finished
for D in "$V7:full_v7p1" "$P3:full_v7p3" "$P2:full_v7p2"; do
  W=${D%:*}; G=${D##*:}
  grep -q "STAGE RPT done" "$L/$G.log" 2>/dev/null || { echo "$G did not finish: no LAT $(date)"; continue; }
  (cd "$W" && matlab -batch "run_stage('LAT','KPI','DASH','WEAK','RPT')" >> "$L/v7_latency.log" 2>&1)
  (cd "$W" && matlab -batch "startup; export_gui_bundle('C:/Users/Adi Suliman/uav-gcs-v7/profiles')" >> "$L/v7_latency.log" 2>&1)
done
echo "v7 done $(date)"
