#!/usr/bin/env bash
# Third test set (B3m) of profiles 1 and 3, each in its own worktree copy (no Simulink build shared
# with the running chains); afterwards its files are copied into the profile.
MATLAB="/c/Program Files/MATLAB/R2026a/bin/matlab.exe"
L="/c/Users/Adi Suliman/uav-gcs-logs/v7_d86"
one() {
  local g=$1 c="/c/Users/Adi Suliman/uav-gcs-b3m-$1" w=$2 rc
  echo "$(date '+%F %T') $g: B3m in $c" >> "$L/${g}_b3m.log"
  ( cd "$c" && "$MATLAB" -batch "run_stage('A0','B3m')" ) >> "$L/${g}_b3m.log" 2>&1; rc=$?
  echo "$(date '+%F %T') $g: B3m ended rc=$rc" >> "$L/${g}_b3m.log"
  if [ "$rc" = 0 ]; then
    cp "$c"/data/*fresh2* "$w/data/" && cp "$c"/results/*_fresh2* "$w/results/" && \
      echo "$(date '+%F %T') $g: B3m files copied into $w" >> "$L/${g}_b3m.log"
  fi
}
one p1 "/c/Users/Adi Suliman/uav-gcs-v7" &
one p3 "/c/Users/Adi Suliman/uav-gcs-v7-p3" &
wait
