#!/usr/bin/env bash
# One hand-run MATLAB in a live worktree through the d91 gate (docs/d91_deploy.md section 5).
#
#   bash v7_d91_gated_run.sh <need_gb> <worktree> <logfile> <matlab -batch command>
#
#   need_gb   free commit [GB] the job needs before it starts (docs/d91_deploy.md 5.0: 65 for
#             B2F, the B stages, the rehearsal and B3r; 45 for rekey_pools and C1d)
#   worktree  uav-gcs-v7 (p1), uav-gcs-v7-p3 (p3) or uav-gcs-v7-p2 (p2), by name or path
#   logfile   MATLAB's -logfile, relative to the worktree (e.g. logs/stage_B3r_20261025_1200.txt);
#             it must not exist yet
#   command   the -batch command, without double quotes and never with 'run_stage(' (the
#             takeover and the gate count such a session as a pipeline stage)
#
# 1. Registers the hand-run before anything else: creates v7_d86/<p>_hand.busy atomically
#    (noclobber). If the file exists, another hand-run holds the worktree (or one was killed and
#    left it): the wrapper prints it and stops (exit 3); check by hand, then remove it.
#    The takeover (v7_d91_takeover.sh) starts no MATLAB in that worktree while the file exists.
#    Before each start it claims its PID file (its own bash's PID) and only then reads this file,
#    so a takeover start that missed the registration is in its PID file by then.
# 2. Waits D91_SETTLE s (default 30: one takeover STEP and a margin), then, checking every D91_POLL s
#    (default 600), until all of these hold:
#    - no takeover MATLAB recorded for the worktree is alive (v7_d86/takeover_ml_<p>.pid: its
#      first line and its 'win64 <pid>' line; for p1 also takeover_p1_chain_ml.txt), no process
#      recorded there has a live MATLAB child, and none is a live takeover bash (its claim);
#    - no MATLAB.exe has the worktree's path in its command line (another hand-run's -logfile);
#    - free commit >= need_gb;
#    - then v7_d91_speed_gate.ps1 says OK (>= 35 GB, at most one other non-pipeline MATLAB, no
#      OK from any d91 gate in the last 180 s; its OK writes the shared start stamp).
# 3. Runs, in the worktree: matlab.exe -singleCompThread -logfile <worktree>\<logfile> -batch
#    "<append 'win64 <its PID>' to the busy file>; <command>".
# 4. When MATLAB has ended and its win64 PID is gone, removes the busy file and exits with
#    MATLAB's status. A win64 MATLAB still alive 10 min after its launcher ended keeps the file
#    (exit 4). An interrupted wrapper removes the file only while no MATLAB was started.
#    A wrapper ended by taskkill leaves the file: the worktree stays held until it is removed
#    by hand after checking that no MATLAB of it runs.
# Events: stdout and v7_d91_gated_run.log. D91_GATED_DRY=1 does steps 1-2 without the gate's
# OK (no start stamp), prints the MATLAB command, removes the file and starts nothing.

NEED=${1:-}
WTA=${2:-}
LOGREL=${3:-}
CMD=${4:-}
L=${V7G_LOGS:-"/c/Users/Adi Suliman/uav-gcs-logs"}
ROOT=${V7G_ROOT:-"/c/Users/Adi Suliman"}
R="$L/v7_d86"
MATLAB=${V7G_MATLAB:-"/c/Program Files/MATLAB/R2026a/bin/matlab.exe"}
GATE=${V7G_GATE:-'C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_speed_gate.ps1'}
STATE_PS=${V7G_STATE:-'C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_gated_state.ps1'}
POLL=${D91_POLL:-600}
SETTLE=${D91_SETTLE:-30}
EV="$L/v7_d91_gated_run.log"

say() { local m; m="$(date '+%Y-%m-%d %H:%M:%S') gated_run[$$] $*"; echo "$m"; echo "$m" >> "$EV" 2>/dev/null; }
die() { local c=$1; shift; say "$*"; exit "$c"; }

[ $# -eq 4 ] || die 2 "usage: bash v7_d91_gated_run.sh <need_gb> <worktree> <logfile> <matlab -batch command>"
[[ $NEED =~ ^[0-9]+$ ]] && [ "$NEED" -ge 1 ] || die 2 "need_gb '$NEED' is not a whole number of GB"
case "$(basename "$WTA")" in
  uav-gcs-v7) P=p1;; uav-gcs-v7-p3) P=p3;; uav-gcs-v7-p2) P=p2;;
  *) die 2 "worktree '$WTA' is not uav-gcs-v7, uav-gcs-v7-p3 or uav-gcs-v7-p2";;
esac
WT="$ROOT/$(basename "$WTA")"
[ -d "$WT" ] || die 2 "worktree $WT not found"
case "$CMD" in *run_stage\(*) die 2 "the command holds 'run_stage(': the takeover would count it as a pipeline stage; call the stage's script directly";; esac
case "$CMD" in *\"*) die 2 "the command holds a double quote; use single quotes inside it";; esac
[ -n "$CMD" ] || die 2 "empty command"
case "$LOGREL" in /*|*:*|*..*|'') die 2 "logfile '$LOGREL' must be a path inside the worktree";; esac
LOGP="$WT/$LOGREL"
[ -e "$LOGP" ] && die 2 "logfile $LOGP exists already; give each run a log of its own"
mkdir -p "$(dirname "$LOGP")" || die 2 "cannot create $(dirname "$LOGP")"
[ -d "$R" ] || die 2 "$R not found"

BUSY="$R/${P}_hand.busy"
STARTED=0
WPID=""
if ! ( set -o noclobber; printf 'hand-run %s wrapper msys %s win %s\nworktree %s\nlog %s\nneed_gb %s\ncmd %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$(cat /proc/$$/winpid 2>/dev/null)" "$(cygpath -w "$WT")" \
        "$(cygpath -w "$LOGP")" "$NEED" "$CMD" > "$BUSY" ) 2>/dev/null; then
  say "$BUSY exists: another hand-run holds $WT, or a killed one left the file. Its content:"
  sed 's/^/  /' "$BUSY" 2>/dev/null
  die 3 "not started. Check that no MATLAB of it runs (Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Select ProcessId,CommandLine), then remove the file by hand"
fi
say "registered $BUSY ($P, need $NEED GB): $CMD"

cleanup() {   # the busy file goes only while no MATLAB of this wrapper can be alive
  local rc=$?
  if [ "$STARTED" = 0 ]; then rm -f "$BUSY"; say "ended before MATLAB started (status $rc); $BUSY removed"; fi
}
interrupted() {
  if [ "$STARTED" = 1 ]; then
    say "interrupted while MATLAB runs (win64 ${WPID:-unknown}); $BUSY kept. End that MATLAB with taskkill /PID <win64 pid> /F (no /T) if it must stop, then remove the file"
    trap - EXIT; exit 130
  fi
  exit 130
}
trap cleanup EXIT
trap interrupted INT TERM HUP

pids_of() {   # Windows PIDs recorded for the worktree by the takeover (msys lines left out)
  local f="$R/takeover_ml_$P.pid"
  [ -f "$f" ] && awk 'NR == 1 { gsub(/[^0-9]/, ""); if ($0 != "") print } $1 == "win64" && $2 ~ /^[0-9]+$/ { print $2 }' "$f" | tr -d '\r'
  [ "$P" = p1 ] && [ -f "$R/takeover_p1_chain_ml.txt" ] && awk '$1 ~ /^[0-9]+$/ { print $1 }' "$R/takeover_p1_chain_ml.txt" | tr -d '\r'
}
state() {   # FREE free=<gb>, BUSY free=<gb> <why>, or UNKNOWN <why> (v7_d91_gated_state.ps1)
  D91_PIDS="$(pids_of | sort -u | tr '\n' ' ')" D91_WT="$(cygpath -w "$WT")" MSYS2_ARG_CONV_EXCL='*' \
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$STATE_PS" 2>&1 | tr -d '\r' | tail -1
}
gate() { MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$GATE" 2>&1 | tr -d '\r' | tail -1; }

sleep "$SETTLE" & wait $!   # a takeover start that read no busy file just before the registration shows in its PID file by now
last=""
while :; do
  s=$(state)
  why=""
  case "$s" in
    FREE*) f=${s#FREE free=}; f=${f%% *}; f=${f%%.*}
           if [[ $f =~ ^[0-9]+$ ]] && [ "$f" -ge "$NEED" ]; then
             if [ "${D91_GATED_DRY:-0}" = 1 ]; then why=DRY; break; fi
             g=$(gate)
             case "$g" in OK*) say "gate: $g"; break;; esac
             why="gate: ${g:-no answer}"
           else why="free commit ${f:-?} GB < $NEED GB"; fi;;
    BUSY*) why="worktree busy: ${s#BUSY }";;
    *) why="state unknown: ${s:-no answer}";;
  esac
  key=$(sed -e "s/free=[0-9.]*[A-Za-z]* //" -e "s/commit [0-9?]* GB/commit GB/" <<< "$why"); [ "$key" = "$last" ] || say "waits: $why"; last=$key
  sleep "$POLL" & wait $!
done

BUSYW=$(cygpath -w "$BUSY")
PRE="fid = fopen('$BUSYW', 'a'); fprintf(fid, 'win64 %d\n', feature('getpid')); fclose(fid); fprintf('V7HAND win64 %d\n', feature('getpid'));"
if [ "${D91_GATED_DRY:-0}" = 1 ]; then
  say "DRY: would run in $(cygpath -w "$WT"): matlab.exe -singleCompThread -logfile $(cygpath -w "$LOGP") -batch \"$PRE $CMD\""
  exit 0
fi
say "starts in $(cygpath -w "$WT"), log $(cygpath -w "$LOGP")"
STARTED=1
( cd "$WT" && MSYS2_ARG_CONV_EXCL='*' exec "$MATLAB" -singleCompThread -logfile "$(cygpath -w "$LOGP")" -batch "$PRE $CMD" ) &
mp=$!
wait "$mp"; rc=$?
WPID=$(awk '$1 == "win64" && $2 ~ /^[0-9]+$/ { p = $2 } END { print p }' "$BUSY" 2>/dev/null | tr -d '\r')
say "MATLAB ended rc=$rc (win64 ${WPID:-not recorded})"
if [ -n "$WPID" ]; then
  for _ in $(seq 1 60); do
    a=$(MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -NonInteractive -Command "if (Get-Process -Id $WPID -ErrorAction SilentlyContinue) { 'alive' } else { 'gone' }" 2>&1 | tr -d '\r' | tail -1)
    [ "$a" = gone ] && break
    sleep 10
  done
  if [ "$a" != gone ]; then
    trap - EXIT
    die 4 "win64 MATLAB $WPID still alive 10 min after its launcher ended; $BUSY kept (remove it once that PID is gone)"
  fi
fi
rm -f "$BUSY"
trap - EXIT
say "done rc=$rc; $BUSY removed"
exit "$rc"
