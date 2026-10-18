#!/usr/bin/env bash
# Profile 3 after its chain stopped in OOD (out of memory, 2026-10-17 22:02): A0, OOD, B4s once its
# third test set (B3m) has ended and the commit headroom allows; then C1p to RPT once profile 1 has
# passed SURV3, as the launcher's chain does. The part header and stage markers follow the
# launcher's format so its next_idx and a later resume read this part.
MATLAB="/c/Program Files/MATLAB/R2026a/bin/matlab.exe"
R="/c/Users/Adi Suliman/uav-gcs-logs/v7_d86"
W="/c/Users/Adi Suliman/uav-gcs-v7-p3"
LOG="$R/p3.log"
OUT="$R/p3_fix.log"
SRC=$(sed -n 's/^SRC //p' "$R/code_commit.txt")
NEED_GB=${P3FIX_NEED_GB:-45}           # [GB] free commit before OOD starts
POLL=300
say() { echo "$(date '+%F %T') $*" >> "$OUT"; }
headroom_gb() {
  powershell.exe -NoProfile -Command "\$o = Get-CimInstance Win32_OperatingSystem; [int](\$o.FreeVirtualMemory / 1MB)" 2>/dev/null | tr -dc '0-9'
}
p1_past_surv3() {   # profile 1's current part has SURV3 done, or its chain is over
  local n
  n=$(grep -n '^##### PART ' "$R/p1.log" | tail -1 | cut -d: -f1)
  tail -n +"${n:-1}" "$R/p1.log" | grep -qE '^##### (STAGE SURV3 done|chain ended)'
}

say "p3 fix started (SRC $SRC)"
until grep -q 'p3: B3m ended' "$R/p3_b3m.log"; do sleep "$POLL"; done
say "p3 B3m ended"
until h=$(headroom_gb); [ "${h:-0}" -ge "$NEED_GB" ]; do say "commit headroom ${h:-?} GB < $NEED_GB GB; waiting"; sleep "$POLL"; done
say "commit headroom $h GB; OOD starts"

echo "##### PART $(date +%Y%m%d_%H%M%S) fix SRC $SRC FROM 11 OOD A0 1 #####" >> "$LOG"
( cd "$W" && "$MATLAB" -batch "run_stage('A0','OOD','B4s')" ) >> "$LOG" 2>&1; rc=$?
say "A0 OOD B4s ended rc=$rc"
if [ "$rc" = 0 ]; then
  until p1_past_surv3; do sleep "$POLL"; done
  echo "p3: C1p onward after p1's SURV3 $(date)" >> "$LOG"
  ( cd "$W" && "$MATLAB" -batch "run_stage('C1p','C1c','SURV','SURV3','C1d','C2','C2e','C2g','C2u','GAL','OHP','GCSA','EDGE','KPI','DASH','WEAK','RPT')" ) >> "$LOG" 2>&1; rc=$?
fi
echo "##### chain ended rc=$rc $(date) #####" >> "$LOG"
say "p3 chain ended rc=$rc"
