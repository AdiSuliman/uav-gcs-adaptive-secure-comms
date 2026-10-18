#!/usr/bin/env bash
# Redo after the align fix (2026-10-17): in profiles 1 and 3, rebuild the detector stages on the
# repaired datasets (A0, A6, B1, B2, B2F, then the second test set's A6 + B1 from its repaired
# dataset, logged as B3n), then resume the full run with the launcher (B3 onward in each chain).
# A file named HOLD in uav-gcs-logs/v7_d86 pauses the script before its next step.
#   Start detached (PowerShell):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d87_redo.sh'' <SHA> >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d87_redo.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}
set -u
SRC=$1
R="/c/Users/Adi Suliman/uav-gcs-logs/v7_d86"
MATLAB="/c/Program Files/MATLAB/R2026a/bin/matlab.exe"
STAMP=$(date +%Y%m%d_%H%M%S)
declare -A WT=([p1]="/c/Users/Adi Suliman/uav-gcs-v7" [p3]="/c/Users/Adi Suliman/uav-gcs-v7-p3")
say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
hold() { while [ -f "$R/HOLD" ]; do sleep 60; done; }

redo() {   # profile: A0-B2F and the second test set's features, markers in its own log
  local g=$1 w=${WT[$1]} log="$R/$1.log" t0 rc
  echo "##### PART $STAMP redo SRC $SRC FROM 3 A6 A0 1 #####" >> "$log"
  hold
  ( cd "$w" && "$MATLAB" -batch "run_stage('A0','A6','B1','B2','B2F')" ) >> "$log" 2>&1; rc=$?
  [ "$rc" = 0 ] || { echo "##### redo stopped rc=$rc $(date) #####" >> "$log"; return "$rc"; }
  hold
  t0=$(date +%s)
  echo "##### STAGE B3n (the second test set's A6 and B1 from its repaired dataset) $(date) #####" >> "$log"
  ( cd "$w" && "$MATLAB" -batch "startup; FRESH_TEST = true; run('extract_spectrograms'); run('prepare_data');" ) >> "$log" 2>&1; rc=$?
  [ "$rc" = 0 ] || { echo "##### redo stopped rc=$rc $(date) #####" >> "$log"; return "$rc"; }
  echo "##### STAGE B3n done in $(( ($(date +%s) - t0) / 60 )).0 min #####" >> "$log"
}

say "redo of $SRC in p1 and p3"
redo p1 & P1=$!
redo p3 & P3=$!
wait "$P1"; r1=$?
wait "$P3"; r3=$?
say "redo ended: p1 rc=$r1, p3 rc=$r3"
[ "$r1" = 0 ] && [ "$r3" = 0 ] || { say "not resumed"; exit 1; }
hold
say "resuming the full run"
"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:/Users/Adi Suliman/uav-gcs-logs/v7_d87_resume.ps1" "$SRC"
say "resume requested"
