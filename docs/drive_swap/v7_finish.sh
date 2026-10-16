#!/usr/bin/env bash
# Finish the v7 runs: profile 1 (C:) and profile 3 (D:) are already running; profile 2 starts on C:
# when profile 1 has ended; then decision latency (LAT) on the idle machine and the console bundles.
# Every new worktree goes on C: (the 4 TB system drive).
# Launch detached (PowerShell):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-v7/docs/drive_swap/v7_finish.sh'' > ''/c/Users/Adi Suliman/uav-gcs-logs/v7_finish.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-v7'}
V7="/c/Users/Adi Suliman/uav-gcs-v7"
P3="${P3:-/d/uav-gcs-v7-p3}"
P2="/c/Users/Adi Suliman/uav-gcs-v7-p2"
L="/c/Users/Adi Suliman/uav-gcs-logs"
STAGES="'A0','A4v','A5','A6','B1','B2','B2F','B3','B3a','B4','OOD','B4s','C1p','C1c','C1d','C2','C2e','C2g','C2u','GAL','SURV','SURV3','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT'"
done_or_failed() { grep -q "STAGE RPT done\|ERROR: MATLAB error" "$1" 2>/dev/null; }
echo "waiting for profile 1 $(date)"
until done_or_failed "$L/full_v7p1.log"; do sleep 300; done
echo "profile 1 ended $(date)"
if [ ! -d "$P2" ]; then
  git -C "$V7" worktree add "$P2" -b v7-p2 v7-dev >/dev/null 2>&1 || exit 1
  printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
  git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" && git -C "$P2" push -q -u origin v7-p2
fi
mkdir -p "$P2/data"
(cd "$P2" && matlab -batch "run_stage($STAGES)" > "$L/full_v7p2.log" 2>&1) &
echo "profile 2 started on C: $(date)"
until done_or_failed "$L/full_v7p3.log"; do sleep 300; done
echo "profile 3 ended $(date)"
wait
echo "v7 runs ended $(date)"
for D in "$V7" "$P3" "$P2"; do
  (cd "$D" && matlab -batch "run_stage('LAT','KPI','DASH','WEAK','RPT')" >> "$L/v7_latency.log" 2>&1)
done
for D in "$V7" "$P3" "$P2"; do
  (cd "$D" && matlab -batch "startup; export_gui_bundle('C:/Users/Adi Suliman/uav-gcs-v7/profiles')" >> "$L/v7_latency.log" 2>&1)
done
echo "v7 done $(date)"
