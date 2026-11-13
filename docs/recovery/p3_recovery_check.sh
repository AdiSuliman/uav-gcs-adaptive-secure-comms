#!/bin/bash
# Profile 3's chain after an unexpected stop (power loss, crash, forced reboot): every check of the
# recovery, then, with --relaunch and only when every check passes, the approved takeover relaunch.
#
#   bash p3_recovery_check.sh              checks only (reads; one short gated MATLAB reads the kept files)
#   bash p3_recovery_check.sh --relaunch   checks, then the relaunch, then waits for the stage's kept-work line
#   bash p3_recovery_check.sh --no-matlab  checks without the MATLAB full read (when a MATLAB already runs)
#
# Each check prints PASS, WARN or FAIL with its numbers. Exit 0 when nothing FAILs, 1 otherwise.
# The runbook is docs/POWER_RECOVERY.md (uav-gcs-v7-docs). Nothing here deletes a file: leftovers are
# moved to uav-gcs-logs/recovery_moved_<stamp>/.
L="/c/Users/Adi Suliman/uav-gcs-logs"
R="$L/v7_d86"
T="/c/Users/Adi Suliman/uav-gcs-v7-p3"
LOG="$R/p3.log"
TK="$L/v7_d91_takeover.log"
EXP="$L/p3_recovery_expect.txt"
MODE=${1:-check}
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="$L/recovery_${STAMP}.txt"
NF=0; NW=0
exec > >(tee -a "$OUT") 2>&1
ps1() { powershell -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'; }
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; NW=$((NW + 1)); }
fail() { echo "FAIL  $*"; NF=$((NF + 1)); }
hdr() { echo; echo "== $*"; }

echo "Profile 3 recovery check $(date '+%F %T') (mode $MODE); this output: $OUT"

hdr "1. The stop"
boot=$(ps1 "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')")
echo "boot: $boot"
ps1 "Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008} -MaxEvents 1 | % { \$_.TimeCreated.ToString('yyyy-MM-dd HH:mm') + '  ' + \$_.Message }" | head -2
echo "      (6008's time is Windows' last-alive stamp; it can be minutes before the real stop)"
e41=$(ps1 "Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 1 | % { \$x=[xml]\$_.ToXml(); \$_.TimeCreated.ToString('yyyy-MM-dd HH:mm') + ' ' + ((\$x.Event.EventData.Data | ? { \$_.Name -in 'BugcheckCode','PowerButtonTimestamp','LongPowerButtonPressDetected','WHEABootErrorCount' } | % { \$_.Name + '=' + \$_.'#text' }) -join ' ') }")
echo "event 41: $e41"
case "$e41" in
  *"BugcheckCode=0 "*"PowerButtonTimestamp=0"*) echo "      no bugcheck, no power button: a loss of power";;
  *) warn "event 41 names a bugcheck or a button press: read it before going on ($e41)";;
esac
bm=$(date -r "$R/takeover_beat_main" '+%F %T' 2>/dev/null); lp=$(date -r "$LOG" '+%F %T' 2>/dev/null)
echo "last takeover beat: $bm; last p3.log write: $lp (the stop came after the later of the two, within the 5-min beat)"

hdr "2. Nothing of the chain runs"
nml=$(ps1 "@(Get-Process MATLAB -ErrorAction SilentlyContinue).Count")
ntk=$(ps1 "@(Get-CimInstance Win32_Process | ? { \$_.CommandLine -match 'v7_d91_takeover.sh' -and \$_.CommandLine -notmatch ' status' }).Count")
[ "${nml:-0}" = 0 ] && pass "no MATLAB process" || warn "$nml MATLAB processes run (a takeover already restarted, or a hand-run): no relaunch, no full read"
[ "${ntk:-0}" = 0 ] && pass "no takeover runs" || warn "a takeover runs ($ntk processes): the chain may already be resumed; read $TK"
[ -e "$R/p3_hand.busy" ] && warn "p3_hand.busy exists (a hand-run cut by the stop): check it, then move it aside" || pass "no p3_hand.busy"

hdr "3. The takeover's view (status mode, reads only)"
st=$(cd "$L" && V7T_RERUN_NEED_GB=55 V7T_ALLOW_PIDS='43428 43972' timeout 300 bash v7_d91_takeover.sh 24172 49732 status 2>&1)
echo "$st" | grep -A1 "^p3: #####" | sed 's/^/      /'
p3line=$(echo "$st" | grep -A1 "^p3: #####" | tail -1)
nextst=$(echo "$p3line" | sed -n 's/.*next \([A-Za-z0-9]*\).*/\1/p')
openst=$(echo "$p3line" | sed -n 's/.*open stage: \([A-Za-z0-9]*\);.*/\1/p')
case "$p3line" in
  *"finished: no"*) pass "p3 unfinished: the takeover resumes it at $nextst (open stage: ${openst:-none})";;
  *"finished: yes"*) warn "p3's chain is finished: the stop hit the final phase or later; read $TK before relaunching";;
  *) fail "the status mode did not report p3 (output above)";;
esac
for f in "$R"/p3_resume.go "$R"/p3.abandon "$R"/final.hold; do [ -e "$f" ] && warn "$(basename "$f") exists: know why before relaunching"; done
nal=$(ls "$R" | grep -c '^ALERT_'); echo "      ALERT files: $nal ($(ls -t "$R" | grep '^ALERT_' | head -1))"

hdr "4. Code and git"
head=$(git -C "$T" rev-parse HEAD); br=$(git -C "$T" branch --show-current)
exp_head=$(grep '^p3 v7-p3 ' "$R/code_commit.txt" | tail -1 | awk '{print $3}')
[ "$br" = v7-p3 ] && pass "branch v7-p3" || fail "branch is '$br', not v7-p3"
[ "$head" = "$exp_head" ] && pass "HEAD ${head:0:7} = the last code_commit.txt line" || fail "HEAD ${head:0:7} differs from code_commit.txt's ${exp_head:0:7}"
dirty=$(git -C "$T" status --porcelain -- code startup.m profile.json)
[ -z "$dirty" ] && pass "no change under code/, startup.m, profile.json" || fail "uncommitted changes: $dirty"
for d in "$T" "/c/Users/Adi Suliman/uav-gcs-v7" "/c/Users/Adi Suliman/uav-gcs-v7-docs" "/c/Users/Adi Suliman/uav-gcs-adaptive-secure-comms"; do
  if git -C "$d" fsck --no-dangling >/dev/null 2>&1; then pass "git fsck $(basename "$d")"; else fail "git fsck $(basename "$d") reports errors"; fi
done

hdr "5. Frozen inputs (sha256 against $EXP)"
while read -r name sum _; do
  case "$name" in ''|'#'*) continue;; esac
  f="$T/$name"; [ -f "$f" ] || f="$T/data/$name"
  got=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
  [ "$got" = "$sum" ] && pass "$name ${sum:0:12}" || fail "$name is ${got:0:12}, expected ${sum:0:12}"
done < "$EXP"

hdr "6. Finished outputs and leftovers"
for f in policy_pools.mat clean_val_pools.mat clean_test_pools.mat check_pools.mat; do
  p="$T/data/$f"
  if [ -s "$p" ]; then pass "$f $(stat -c %s "$p") bytes, $(date -r "$p" '+%F %T')"; else warn "$f missing or empty (fine only if its stage has not run yet)"; fi
done
mv_dir="$L/recovery_moved_$STAMP"
tmps=$(find "$T/data" "$T/results" -name "*.tmp.mat" 2>/dev/null)
if [ -n "$tmps" ]; then
  mkdir -p "$mv_dir"
  while read -r t; do mv "$t" "$mv_dir/"; echo "      moved $t"; done <<< "$tmps"
  warn "unfinished temporary files moved to $mv_dir (writes the stop cut; their stage writes them again)"
else pass "no unfinished temporary file under data/ and results/"; fi

hdr "7. Kept work of the open stage"
for d in "$T"/data/*_cells "$T"/data/*_chunks "$T"/data/*_jobs "$T"/data/run_cache/*; do
  [ -d "$d" ] || continue
  n=$(find "$d" -maxdepth 1 -name "*.mat" | wc -l)
  echo "      $(realpath --relative-to="$T" "$d"): $n files, newest $(find "$d" -maxdepth 1 -name '*.mat' -printf '%TF %TT\n' | sort | tail -1 | cut -c1-19)"
done

hdr "8. Full read of every kept file and of params.mat (one gated MATLAB)"
if [ "$MODE" = --no-matlab ] || [ "${nml:-0}" != 0 ]; then
  warn "full read skipped (--no-matlab, or MATLAB runs)"
else
  rl="logs/recovery_fullread_$STAMP.txt"
  cmd="cd('C:\Users\Adi Suliman\uav-gcs-v7-p3'); D = [dir('data/*_cells'); dir('data/*_chunks'); dir('data/*_jobs'); dir('data/run_cache/*')]; D = D([D.isdir] & ~ismember({D.name}, {'.', '..'})); nf = 0; bad = 0; for i = 1:numel(D), F = dir(fullfile(D(i).folder, D(i).name, '*.mat')); for k = 1:numel(F), p = fullfile(F(k).folder, F(k).name); nf = nf + 1; try, S = load(p, 'key', 'res'); assert(isfield(S, 'key') && isfield(S, 'res')); clear S; catch e, bad = bad + 1; fprintf('UNREADABLE %s: %s\n', p, e.message); end, end, end; try, P = load('params.mat'); assert(~isempty(fieldnames(P))); pok = 1; catch, pok = 0; end; fprintf('RECOVERY_READ files %d unreadable %d params %d\n', nf, bad, pok); exit(double(bad > 0 || pok == 0))"
  r=$(cd "$L" && bash v7_d91_gated_run.sh 10 uav-gcs-v7-p3 "$rl" "$cmd" 2>&1)
  echo "$r" | grep "UNREADABLE\|RECOVERY_READ\|done rc" | sed 's/^/      /'
  line=$(echo "$r" | grep "RECOVERY_READ")
  case "$line" in
    *"unreadable 0 params 1"*) pass "$line";;
    *) fail "full read: ${line:-no result line} (log $T/$rl). An unreadable kept file is computed again by its stage; move it aside first";;
  esac
fi

hdr "9. The machine"
g=$(find "$LOCALAPPDATA/Temp" -maxdepth 1 -name "*.dmr" -printf "%s\n" 2>/dev/null | awk '{t+=$1} END{printf "%.3f", t/1e9}')
if awk "BEGIN{exit !($g > 1.0)}"; then
  mkdir -p "$L/dmr_old_$STAMP"; find "$LOCALAPPDATA/Temp" -maxdepth 1 -name "*.dmr" -size +100M -exec mv {} "$L/dmr_old_$STAMP/" \;
  warn ".dmr in Temp $g GB: files over 100 MB moved to dmr_old_$STAMP (disk_guard stops the chain at 2 GB)"
else pass ".dmr in Temp $g GB"; fi
ps1 "Get-PhysicalDisk | % { \$_.FriendlyName + ': ' + \$_.HealthStatus }" | while read -r l; do case "$l" in *Healthy) pass "disk $l";; *) fail "disk $l";; esac; done
fg=$(df -BG /c | tail -1 | awk '{print $4}' | tr -d G); [ "$fg" -gt 200 ] && pass "C: free ${fg} GB" || warn "C: free ${fg} GB"
fc=$(ps1 "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1MB)"); [ "${fc:-0}" -ge 55 ] && pass "free commit ${fc} GB" || warn "free commit ${fc} GB (the takeover waits for 55)"
sl=$(ps1 "powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE" | grep "Current AC" | awk '{print $NF}')
hb=$(ps1 "powercfg /q SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE" | grep "Current AC" | awk '{print $NF}')
[ "$sl" = 0x00000000 ] && [ "$hb" = 0x00000000 ] && pass "sleep and hibernate off" || warn "sleep $sl hibernate $hb: the chain stops if the machine sleeps"
wu=$(ps1 "Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'")
[ "$wu" = False ] && pass "no Windows Update reboot pending" || warn "Windows Update wants a reboot: pause updates before relaunching"

hdr "Verdict"
echo "FAIL $NF, WARN $NW"
if [ "$NF" -gt 0 ]; then echo "Not relaunched: fix every FAIL first (docs/POWER_RECOVERY.md section 4)."; exit 1; fi
if [ "${ntk:-0}" != 0 ]; then echo "A takeover already runs: no relaunch. Read $TK and p3.log for the resumed stage."; exit 0; fi
[ "$MODE" = --relaunch ] || { echo "Checks passed. Relaunch: bash p3_recovery_check.sh --relaunch (or p3_takeover_relaunch.ps1)."; exit 0; }
if [ "${ntk:-0}" != 0 ] || [ "${nml:-0}" != 0 ]; then echo "Not relaunched: a takeover or MATLAB already runs."; exit 1; fi

hdr "10. Relaunch (approved command, p3_takeover_relaunch.ps1)"
n0=$(wc -l < "$LOG")
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$L/p3_takeover_relaunch.ps1")" | tr -d '\r' | grep -v '^$'
for i in $(seq 1 60); do grep -q "stages .* started" <(tail -3 "$TK") && break; sleep 10; done
tail -4 "$TK" | sed 's/^/      /'
grep -q "stages .* started" <(tail -3 "$TK") && pass "takeover: $(tail -1 "$TK" | cut -c21-)" || { fail "no 'stages ... started' line in the takeover log within 10 min"; exit 1; }
echo "      waiting for the stage's kept-work line (up to 20 min)..."
for i in $(seq 1 120); do k=$(tail -n +"$n0" "$LOG" | grep -m1 "kept from an earlier start"); [ -n "$k" ] && break; sleep 10; done
tail -n +"$n0" "$LOG" | grep "PART\|##### STAGE\|Connected to parallel" | sed 's/^/      /'
if [ -n "$k" ]; then pass "$k"; else warn "no kept-work line yet (a stage without kept work, or still starting): read p3.log"; fi
echo
echo "Next: re-arm the watchers (docs/POWER_RECOVERY.md section 3, step 6) and report."
exit 0
