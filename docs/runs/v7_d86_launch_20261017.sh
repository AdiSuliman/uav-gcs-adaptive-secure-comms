#!/usr/bin/env bash
# v7 full run of one reviewed commit: profile 1 (3 antennas, uav-gcs-v7, v7-dev), profile 3
# (4 antennas, uav-gcs-v7-p3, v7-p3) and profile 2 (2 antennas, uav-gcs-v7-p2, v7-p2 made from
# v7-dev when profile 1 has finished), all on C:.
#
#   bash v7_d86_launch.sh <SHA>          launch: (1) full test_core on an export of <SHA>, N of N
#                                        must pass; (2) dry merge check; (3) the first reading of
#                                        every profile moved to archive/first_reading_<stamp>/;
#                                        (4) <SHA> merged into v7-dev, v7-dev into v7-p3, code of
#                                        every profile checked equal to <SHA>; (5) the runs
#   bash v7_d86_launch.sh <SHA> resume   after a crash or a power loss: no gate, archive or merge;
#                                        every chain restarts at its first unfinished stage
#   bash v7_d86_launch.sh <SHA> gate     the test gate alone; changes nothing
#
# Runs: profile 1 every stage, its heavy parallel stages (C1p, C1c, SURV, SURV3) first; profile 3
# A0-B4s, then C1p onward once profile 1 has passed SURV3; profile 2 once profile 1 has finished,
# A0-B4s, then C1p onward once profile 3 has passed SURV3; at the end, on an idle machine, LAT,
# KPI, DASH, WEAK and RPT again and the console bundle of every finished profile.
# Logs in uav-gcs-logs/v7_d86/: p1.log, p3.log, p2.log (appended; every launch or resume writes a
# '##### PART' header), code_commit.txt, gate_<stamp>.log, merge_<profile>.log.
#
# Start detached (PowerShell; <SHA> = the reviewed commit, not a branch name):
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.sh'' <SHA> >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d86_launch.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'}
# After a power loss or a crash: the same command with "<SHA> resume" in place of "<SHA>". A
# resume refuses while any part of the run is alive (its heartbeat, v7_d86/run.lock, is touched
# at least every 5 min; a heartbeat from before the last boot counts as dead).
# Progress: tail -f the profile logs; the launcher's own messages go to v7_d86_launch.log.
# V7L_* environment variables point the launcher at a test copy; a real run leaves them unset.

SRC_ARG=${1:-}
MODE=${2:-launch}
V7=${V7L_P1:-"/c/Users/Adi Suliman/uav-gcs-v7"}
P3=${V7L_P3:-"/c/Users/Adi Suliman/uav-gcs-v7-p3"}
P2=${V7L_P2:-"/c/Users/Adi Suliman/uav-gcs-v7-p2"}
L=${V7L_LOGS:-"/c/Users/Adi Suliman/uav-gcs-logs"}
MATLAB=${V7L_MATLAB:-"/c/Program Files/MATLAB/R2026a/bin/matlab.exe"}
POLL=${V7L_POLL:-300}                  # [s] between checks of another chain's progress
STEP=${V7L_STEP:-10}                   # [s] between checks of a running MATLAB
STALE_S=${V7L_STALE_S:-1200}           # [s] heartbeat age beyond which no part of the run is alive
IDLE_MAX_MIN=${V7L_IDLE_MAX_MIN:-240}  # [min] longest wait for an idle machine before LAT
IDLE_POLL=${V7L_IDLE_POLL:-600}        # [s]
R="$L/v7_d86"
STAMP=$(date +%Y%m%d_%H%M%S)
T=${V7L_TEMP:-$(cygpath -u "${TEMP:-/tmp}")}   # MATLAB's tempdir: .dmr files, the parallel turn file
TRAILER="Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_EDITOR=true

AB=(A0 A4v A5 A6 B1 B2 B2F B3n B3 B3a B4 OOD B4s)
HV=(C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE KPI DASH WEAK RPT)
FIN=(LAT KPI DASH WEAK RPT BUNDLE)
FULL=("${AB[@]}" "${HV[@]}" "${FIN[@]}")
NAB=${#AB[@]}                          # first index of C1p
NCH=$((NAB + ${#HV[@]}))               # first index after the chain (LAT)
NFULL=${#FULL[@]}
I_SURV3=16; I_KPI2=31                  # FULL[16] = SURV3, FULL[31] = KPI after LAT
GEN_RE='^params\.mat$|^models/[^/]*\.slx$|^results/'   # generated files a merge may take from the incoming side

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
wt()  { case $1 in p1) echo "$V7";; p3) echo "$P3";; p2) echo "$P2";; esac; }
br()  { case $1 in p1) echo v7-dev;; p3) echo v7-p3;; p2) echo v7-p2;; esac; }
dep() { case $1 in p3) echo p1;; p2) echo p3;; esac; }   # whose SURV3 this profile's C1p waits for
hb()  { touch "$LOCK" 2>/dev/null; }

# MATLAB -batch "$4" in folder $1, output appended to $2; heartbeat while it runs; its exit status
run_ml() {
  local w=$1 log=$2 cmd=$3 mp rc
  ( cd "$w" && "$MATLAB" -batch "$cmd" ) >> "$log" 2>&1 &
  mp=$!
  while kill -0 "$mp" 2>/dev/null; do hb; sleep "$STEP"; done
  wait "$mp"; rc=$?
  return "$rc"
}
stage_cmd() { local q; q=$(printf ",'%s'" "$@"); echo "run_stage(${q#,})"; }
wait_until() { until "$@"; do hb; sleep "$POLL"; done; }

# Log markers. A part runs from its '##### PART ... FROM <i> <stage> A0 <0|1>' header to the next.
cur_part() {
  local f="$R/$1.log" n
  [ -f "$f" ] || return 0
  n=$(grep -n '^##### PART ' "$f" | tail -1 | cut -d: -f1)
  [ -n "$n" ] && tail -n +"$n" "$f"
}
# index in FULL of the profile's first unfinished stage: the part's start, advanced over the
# '##### STAGE <s> done' markers of the current part that follow FULL in order
next_idx() {
  local part hdr r a0 i=0 seq
  part=$(cur_part "$1")
  [ -n "$part" ] || { echo 0; return; }
  hdr=$(head -1 <<< "$part")
  r=$(sed -n 's/.* FROM \([0-9]*\) [^ ]* A0 [01] .*/\1/p' <<< "$hdr")
  a0=$(sed -n 's/.* FROM [0-9]* [^ ]* A0 \([01]\) .*/\1/p' <<< "$hdr")
  [ -n "$r" ] || { echo 0; return; }
  mapfile -t seq < <(grep -o '##### STAGE [A-Za-z0-9]* done' <<< "$part" | cut -d' ' -f3)
  if [ "$a0" = 1 ]; then
    [ "${seq[0]:-}" = A0 ] || { echo "$r"; return; }
    i=1
  fi
  while [ "$r" -lt "$NFULL" ] && [ "$i" -lt "${#seq[@]}" ] && [ "${seq[$i]}" = "${FULL[$r]}" ]; do
    r=$((r + 1)); i=$((i + 1))
  done
  echo "$r"
}
ended()  {   # the chain's end marker in the current part, or its process gone without one
  cur_part "$1" | grep -q '^##### chain ended' && return 0
  [ -n "${CH_PID[$1]:-}" ] && ! kill -0 "${CH_PID[$1]}" 2>/dev/null
}
past()   { [ "$(next_idx "$1")" -gt "$2" ] || ended "$1"; }       # stage index $2 done, or the chain over
p_over() { [ "$(next_idx "$1")" -ge "$NCH" ] || ended "$1"; }
part_header() { echo "##### PART $STAMP $MODE SRC $SRC FROM $2 ${FULL[$2]:-end} A0 $3 #####" >> "$R/$1.log"; HDR[$1]=1; }

# The profile's stages from FULL[$2] to RPT; with a dependency, its C1p starts only once that
# profile has passed SURV3; A0 first when $3 = 1 (a stage of A4v-B4s stopped by a crash may leave
# params.mat changed)
chain() {
  local g=$1 r=$2 a0=$3 w log d rc=0 list
  w=$(wt "$g"); log="$R/$g.log"; d=$(dep "$g")
  if [ -n "$d" ] && [ "$r" -lt "$NAB" ]; then
    list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${FULL[@]:r:NAB-r}")
    run_ml "$w" "$log" "$(stage_cmd "${list[@]}")"; rc=$?
    r=$NAB; a0=0
  fi
  if [ "$rc" = 0 ] && [ "$r" -lt "$NCH" ]; then
    if [ -n "$d" ] && [ "$r" -le "$NAB" ]; then
      wait_until past "$d" "$I_SURV3"
      echo "$g: C1p onward after $d's SURV3 $(date)" >> "$log"
    fi
    list=(); [ "$a0" = 1 ] && list+=(A0); list+=("${FULL[@]:r:NCH-r}")
    run_ml "$w" "$log" "$(stage_cmd "${list[@]}")"; rc=$?
  fi
  echo "##### chain ended rc=$rc $(date) #####" >> "$log"
}
start_chain() {
  local g=$1 r=$2 a0=0
  [ "$r" -lt "$NCH" ] || return 0
  [ "$r" -gt 0 ] && [ "$r" -lt "$NAB" ] && a0=1
  [ "$MODE" = resume ] && [ "$r" -le "$NAB" ] && pools_check "$g"
  part_header "$g" "$r" "$a0"
  chain "$g" "$r" "$a0" &
  CH_PID[$g]=$!; CH_PIDS+=($!)
  say "$g: stages ${FULL[$r]} to RPT started (A0 first: $a0)"
}

# On a resume before C1p has finished: a policy_pools.mat that MATLAB cannot read (cut short by
# the crash) is moved aside so C1p does not stop on it; C1p's per-cell checkpoints stay
pools_check() {
  local w f; w=$(wt "$1"); f="$w/data/policy_pools.mat"
  [ -f "$f" ] || return 0
  if run_ml "$w" "$R/$1.log" "whos('-file','data/policy_pools.mat')"; then
    say "$1: data/policy_pools.mat readable, kept"
  else
    mv "$f" "$w/data/policy_pools_partial_$STAMP.mat" && say "$1: unreadable data/policy_pools.mat moved to policy_pools_partial_$STAMP.mat"
  fi
}

n_matlab() {   # win64 MATLAB sessions on this machine (the launcher stubs not counted)
  powershell.exe -NoProfile -Command "@(Get-Process -Name MATLAB -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like '*win64*' }).Count" 2>/dev/null | tr -d '\r '
}
cpu_load() {
  powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average" 2>/dev/null | tr -d '\r '
}
boot_epoch() {
  powershell.exe -NoProfile -Command "([DateTimeOffset](Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToUnixTimeSeconds()" 2>/dev/null | tr -d '\r '
}
stage_pids() {   # win64 MATLAB sessions running pipeline stages (smoke runs and the third test set's own worktree copies not counted)
  powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='MATLAB.exe'\" | Where-Object { \$_.CommandLine -like '*win64*' -and \$_.CommandLine -match 'run_stage\(' -and \$_.CommandLine -notmatch 'run_stage\(.smoke' -and \$_.CommandLine -notmatch 'B3m' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/ *$//'
}
IDLE_END=""
wait_idle() {   # until no win64 MATLAB runs, at most IDLE_MAX_MIN after the first call
  local now
  [ -n "$IDLE_END" ] || IDLE_END=$(( $(date +%s) + IDLE_MAX_MIN * 60 ))
  while [ "$(n_matlab)" != 0 ]; do
    now=$(date +%s)
    [ "$now" -lt "$IDLE_END" ] || return 1
    hb; sleep $(( IDLE_END - now < IDLE_POLL ? IDLE_END - now : IDLE_POLL ))
  done
}

# Merge $2 into the worktree $1 (message $3). A conflict is allowed only in a generated file
# (params.mat, models/*.slx, results/), which takes the incoming version; any other conflict
# aborts the merge. Already merged: nothing to do.
merge_gen() {
  local w=$1 c=$2 m=$3 log U f bad
  log="$R/merge_$(basename "$w").log"
  git -C "$w" merge-base --is-ancestor "$c" HEAD && { echo "$c already merged $(date)" >> "$log"; return 0; }
  git -C "$w" merge --no-ff -m "$m" -m "$TRAILER" "$c" >> "$log" 2>&1 && return 0
  U=$(git -C "$w" -c core.quotepath=off diff --name-only --diff-filter=U)
  bad=$(grep -Ev "$GEN_RE" <<< "$U" | sed '/^$/d')
  if [ -z "$U" ]; then
    git -C "$w" merge --abort >> "$log" 2>&1
    say "merge of $c into $(basename "$w") failed without a conflict (see $log)"
    return 1
  fi
  if [ -n "$bad" ]; then
    git -C "$w" merge --abort >> "$log" 2>&1
    say "merge of $c into $(basename "$w") aborted: conflicts outside the generated files: $(tr '\n' ' ' <<< "$bad")"
    return 1
  fi
  while IFS= read -r f; do
    if git -C "$w" cat-file -e "MERGE_HEAD:$f" 2>/dev/null; then
      git -C "$w" checkout --theirs -- "$f" && git -C "$w" add -f -- "$f"
    else
      git -C "$w" rm -q -f -- "$f"
    fi || { git -C "$w" merge --abort >> "$log" 2>&1; say "merge of $c into $(basename "$w") aborted at $f"; return 1; }
  done <<< "$U"
  git -C "$w" commit -q -m "$m" -m "$TRAILER" >> "$log" 2>&1 || { git -C "$w" merge --abort >> "$log" 2>&1; say "merge commit in $(basename "$w") failed"; return 1; }
  echo "merged $c; generated files from the incoming side: $(tr '\n' ' ' <<< "$U") $(date)" >> "$log"
}

# Result tree of merging $3 into $2 in repository $1, printed; nothing is checked out. Fails on a
# conflict outside the generated files or on an untracked file of worktree $4 the merge would write.
dry_merge() {
  local repo=$1 ours=$2 theirs=$3 w=$4 out rc tree files bad f
  if git -C "$repo" merge-base --is-ancestor "$theirs" "$ours"; then
    git -C "$repo" rev-parse "$ours^{tree}"; return 0
  fi
  out=$(git -C "$repo" merge-tree --write-tree --name-only --no-messages "$ours" "$theirs"); rc=$?
  [ "$rc" -le 1 ] || { say "merge-tree $ours $theirs failed ($rc)" >&2; return 1; }
  tree=$(head -1 <<< "$out"); files=$(tail -n +2 <<< "$out" | sed '/^$/d' | sort -u)
  bad=$(grep -Ev "$GEN_RE" <<< "$files" | sed '/^$/d')
  [ -z "$bad" ] || { say "merging $theirs into $ours conflicts outside the generated files: $(tr '\n' ' ' <<< "$bad")" >&2; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] && git -C "$repo" cat-file -e "$tree:$f" 2>/dev/null && { say "untracked $w/$f would be overwritten by the merge" >&2; return 1; }
  done < <(git -C "$w" -c core.quotepath=off ls-files --others --exclude-standard)
  echo "$tree"
}
code_same() {   # no file of code/ or startup.m differs between $2 and the tree-ish $3 (repository $1)
  local d; d=$(git -C "$1" diff --name-only "$2" "$3" -- code startup.m)
  [ -z "$d" ] || { say "code of $3 in $1 differs from $SRC: $(tr '\n' ' ' <<< "$d")"; return 1; }
}
code_ok() {     # worktree $1 on branch $2, its code committed and equal to SRC
  local w=$1 b=$2 cur
  cur=$(git -C "$w" symbolic-ref --short -q HEAD)
  [ "$cur" = "$b" ] || { say "$w is on '$cur', not $b"; return 1; }
  [ -z "$(git -C "$w" status --porcelain --untracked-files=no -- code startup.m)" ] || { say "$w has uncommitted code changes"; return 1; }
  code_same "$w" "$SRC" HEAD
}

gate() {   # full test_core on an export of SRC; N of N must pass
  local G="$R/gate/${SRC:0:12}_$STAMP" glog="$R/gate_$STAMP.log" rc res fails n
  mkdir -p "$G" || return 1
  ( set -o pipefail; git -C "$V7" archive --format=tar "$SRC" | tar -x -C "$G" ) || { say "export of $SRC failed"; return 1; }
  n=$(grep -c '^function test_' "$G/code/tests/test_core.m")
  say "test gate: test_core of $SRC ($n test functions) in $G"
  run_ml "$G" "$glog" "startup; evalc('init_params'); r = runtests('code/tests/test_core.m'); f = {r(~[r.Passed]).Name}; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); if ~isempty(f), fprintf('V7FAIL %s\n', f{:}); end; exit(double(isempty(r) || ~all([r.Passed])))"
  rc=$?
  res=$(grep -o 'V7TESTS [0-9]*/[0-9]*' "$glog" | tail -1); res=${res#V7TESTS }
  fails=$(grep -o 'V7FAIL [^ ]*' "$glog" | cut -d' ' -f2 | tr '\n' ' ')
  if [ "$rc" != 0 ] || [ -z "$res" ] || [ "${res%/*}" != "${res#*/}" ] || [ "${res#*/}" = 0 ]; then
    say "test gate FAILED on $SRC: passed ${res:-none} (MATLAB exit $rc); failed: ${fails:-see $glog}"
    return 1
  fi
  say "test gate passed: $res on $SRC"
}

usage() { echo "usage: bash v7_d86_launch.sh <commit SHA> [resume|gate]"; }

# 0. Arguments and checks (nothing is changed before the gate)
case "$MODE" in launch|resume|gate) ;; *) usage; exit 1;; esac
[ -n "$SRC_ARG" ] || { usage; say "no commit given; not started"; exit 1; }
[[ "$SRC_ARG" =~ ^[0-9a-fA-F]{7,40}$ ]] || { say "'$SRC_ARG' is not a commit SHA; not started"; exit 1; }
SRC=$(git -C "$V7" rev-parse --verify -q "$SRC_ARG^{commit}") || { say "commit $SRC_ARG not found; not started"; exit 1; }
mkdir -p "$R" || exit 1
[ -f "$MATLAB" ] || { say "MATLAB not found at $MATLAB; not started"; exit 1; }
declare -A HDR=() CH_PID=()
CH_PIDS=()
if [ "$MODE" = gate ]; then
  LOCK="$R/gate.hb"
  gate; exit $?
fi
LOCK="$R/run.lock"
if [ -f "$LOCK" ]; then
  lt=$(stat -c %Y "$LOCK"); age=$(( $(date +%s) - lt )); boot=$(boot_epoch | tr -dc '0-9')
  if [ "$age" -lt "$STALE_S" ] && [ "$lt" -gt "${boot:-0}" ]; then
    say "a launcher of this run (PID $(head -1 "$LOCK")) or one of its MATLAB chains was alive $age s ago; not started (after a crash without a reboot, wait until $LOCK is $((STALE_S / 60)) min old)"
    exit 1
  fi
fi
sp=$(stage_pids)
[ -z "$sp" ] || { say "MATLAB running pipeline stages (PID $sp); not started"; exit 1; }
cat "/proc/$$/winpid" > "$LOCK" 2>/dev/null || echo "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "v7_d86 $MODE of $SRC"
for g in p1 p3 p2; do
  w=$(wt "$g")
  [ "$g" = p2 ] && [ ! -d "$w" ] && continue
  [ -d "$w" ] || { say "worktree $w missing; not started"; exit 1; }
  b=$(git -C "$w" symbolic-ref --short -q HEAD)
  [ "$b" = "$(br "$g")" ] || { say "$w is on '$b', not $(br "$g"); not started"; exit 1; }
  git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null && { say "a merge is in progress in $w; not started"; exit 1; }
done
wu=$(powershell.exe -NoProfile -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime" 2>/dev/null | tr -d '\r')
we=$(date -d "$wu" +%s 2>/dev/null)
[ -n "$wu" ] && [ -n "$we" ] && say "Windows Update pause ends $wu (in $(( (we - $(date +%s)) / 86400 )) days; the full run takes 14-19 days)"

if [ "$MODE" = launch ]; then
  # 1. Test gate on an export of SRC
  gate || { say "not started"; exit 1; }
  # 2. Dry merge: conflicts only in generated files, code equal to SRC, in every profile
  PROFS=(p1 p3); [ -d "$P2" ] && PROFS+=(p2)
  t1=$(dry_merge "$V7" v7-dev "$SRC" "$V7") && code_same "$V7" "$SRC" "$t1" || { say "dry merge into v7-dev failed; not started"; exit 1; }
  if git -C "$V7" merge-base --is-ancestor "$SRC" v7-dev; then c1=$(git -C "$V7" rev-parse v7-dev)
  else c1=$(git -C "$V7" commit-tree "$t1" -p v7-dev -p "$SRC" -m "dry merge"); fi
  for g in "${PROFS[@]:1}"; do
    t=$(dry_merge "$(wt "$g")" "$(br "$g")" "$c1" "$(wt "$g")") && code_same "$V7" "$SRC" "$t" || { say "dry merge into $(br "$g") failed; not started"; exit 1; }
  done
  say "dry merge: conflicts only in generated files; code equal to $SRC in ${PROFS[*]}"
  # 3. Archive the first reading: params.mat, the modified tracked files, git status, data/,
  #    results/ and profiles/; then a clean tree
  for g in "${PROFS[@]}"; do
    w=$(wt "$g"); A="$w/archive/first_reading_$STAMP"
    mkdir -p "$A/tracked" || { say "archive failed in $w; stopped"; exit 1; }
    git -C "$w" status --branch --porcelain=v1 > "$A/git_status.txt"
    git -C "$w" diff --stat HEAD > "$A/git_diff_stat.txt"
    while IFS= read -r -d '' f; do
      [ -f "$w/$f" ] && mkdir -p "$A/tracked/$(dirname "$f")" && cp -p "$w/$f" "$A/tracked/$f"
    done < <(git -C "$w" -c core.quotepath=off diff --name-only -z HEAD)
    [ -f "$w/params.mat" ] && cp -p "$w/params.mat" "$A/params.mat"
    for d in data results profiles; do
      if [ -e "$w/$d" ]; then mv "$w/$d" "$A/$d" || { say "archive of $d failed in $w; stopped"; exit 1; }; fi
    done
    git -C "$w" diff --cached --quiet || git -C "$w" reset -q
    git -C "$w" checkout -- . || { say "checkout failed in $w; stopped"; exit 1; }
    [ -z "$(git -C "$w" status --porcelain --untracked-files=no)" ] || { say "$w not clean after checkout; stopped"; exit 1; }
    say "$g: first reading moved to $A"
  done
  for f in full_v7p1 full_v7p3 full_v7p2; do [ -f "$L/$f.log" ] && mv "$L/$f.log" "$L/${f}_first_reading_$STAMP.log"; done
  O="$R/previous_$STAMP"
  for f in p1.log p3.log p2.log code_commit.txt; do
    [ -f "$R/$f" ] && { mkdir -p "$O"; mv "$R/$f" "$O/$f"; }
  done
  # 4. Code: SRC into v7-dev, v7-dev into v7-p3 (and v7-p2 when it exists); every profile's code equal to SRC
  merge_gen "$V7" "$SRC" "Merge ${SRC:0:12} into v7-dev: reviewed v7 code for the full run" || { say "stopped"; exit 1; }
  for g in "${PROFS[@]:1}"; do
    merge_gen "$(wt "$g")" v7-dev "Merge v7-dev into $(br "$g"): reviewed v7 code ${SRC:0:12} for the full run" || { say "stopped"; exit 1; }
  done
  for g in "${PROFS[@]}"; do code_ok "$(wt "$g")" "$(br "$g")" || { say "stopped"; exit 1; }; done
  # 5. Fresh data/ and results/ (the merged commit's tracked results go to the archive)
  for g in "${PROFS[@]}"; do
    w=$(wt "$g")
    [ -d "$w/results" ] && mv "$w/results" "$w/archive/first_reading_$STAMP/results_tracked"
    mkdir -p "$w/results" "$w/data"
  done
  { echo "SRC $SRC"
    for g in "${PROFS[@]}"; do echo "$g $(br "$g") $(git -C "$(wt "$g")" rev-parse HEAD)"; done
    echo "time $(date '+%Y-%m-%d %H:%M:%S %z')"; } > "$R/code_commit.txt"
  say "code $SRC in ${PROFS[*]}: $(tr '\n' ' ' < "$R/code_commit.txt")"
else
  [ -f "$R/code_commit.txt" ] || { say "no launched run in $R (code_commit.txt missing); not resumed"; exit 1; }
  run_src=$(sed -n 's/^SRC //p' "$R/code_commit.txt")
  [ "$run_src" = "$SRC" ] || { say "the run was launched on $run_src, not $SRC; not resumed"; exit 1; }
  for g in p1 p3 p2; do
    [ -d "$(wt "$g")" ] || continue
    code_ok "$(wt "$g")" "$(br "$g")" || { say "not resumed"; exit 1; }
  done
  say "resume: code equal to $SRC"
fi

# 6. Leftover .dmr files of ended sessions (they count against disk_guard's cap); a parallel turn
#    file whose owner is no live process
nd=$(find "$T" -maxdepth 1 -name '*.dmr' -mmin +60 2>/dev/null | wc -l)
find "$T" -maxdepth 1 -name '*.dmr' -mmin +60 -delete 2>/dev/null
say "$nd .dmr files older than 60 min deleted from $T ($(find "$T" -maxdepth 1 -name '*.dmr' 2>/dev/null | wc -l) left)"
tf="$T/uav_gcs_parallel_turn.txt"
if [ -f "$tf" ]; then
  op=$(tr -dc '0-9' < "$tf")
  if [ -n "$op" ] && tasklist //FI "PID eq $op" //NH 2>/dev/null | grep -qi '^matlab\.exe'; then
    say "parallel turn held by the live MATLAB process $op"
  else
    mv "$tf" "$R/stale_parallel_turn_$STAMP.txt" && say "stale parallel turn file (PID ${op:-none}) moved to $R"
  fi
fi

# 7. Runs
if [ "$MODE" = launch ]; then r1=0; r3=0; else r1=$(next_idx p1); r3=$(next_idx p3); fi
start_chain p1 "$r1"
start_chain p3 "$r3"
for g in p1 p3; do
  timeout 120 git -C "$(wt "$g")" push -q origin "$(br "$g")" || say "push of $(br "$g") failed; the run goes on"
done
wait_until p_over p1
if [ "$(next_idx p1)" -ge "$NCH" ]; then
  p2_ok=1
  if [ ! -d "$P2" ]; then
    if git -C "$V7" show-ref --verify -q refs/heads/v7-p2; then
      git -C "$V7" worktree add "$P2" v7-p2 >> "$R/merge_$(basename "$P2").log" 2>&1 && \
        merge_gen "$P2" v7-dev "Merge v7-dev into v7-p2: reviewed v7 code ${SRC:0:12} for the full run" || p2_ok=0
    else
      git -C "$V7" worktree add -b v7-p2 "$P2" v7-dev >> "$R/merge_$(basename "$P2").log" 2>&1 || p2_ok=0
    fi
    if [ "$p2_ok" = 1 ] && ! grep -q '"n_rx":2' "$P2/profile.json" 2>/dev/null; then
      printf '{"profile":"%s","n_rx":%d}\n' "profile 2: two antennas" 2 > "$P2/profile.json"
      git -C "$P2" add profile.json && git -C "$P2" commit -q -m "v7 profile 2: two antennas" -m "$TRAILER" || p2_ok=0
    fi
    if [ "$p2_ok" = 1 ]; then
      mkdir -p "$P2/archive/tracked_$STAMP"
      [ -d "$P2/results" ] && mv "$P2/results" "$P2/archive/tracked_$STAMP/results"
      mkdir -p "$P2/results" "$P2/data"
      echo "p2 v7-p2 $(git -C "$P2" rev-parse HEAD) $(date '+%Y-%m-%d %H:%M:%S %z')" >> "$R/code_commit.txt"
      timeout 120 git -C "$P2" push -q -u origin v7-p2 || say "push of v7-p2 failed; the run goes on"
    fi
  fi
  if [ "$p2_ok" = 1 ] && code_ok "$P2" v7-p2; then
    start_chain p2 "$(next_idx p2)"
  else
    say "profile 2 worktree $P2 not ready; profile 2 not started"
  fi
else
  say "profile 1 did not finish (see $R/p1.log); profile 2 not started"
fi
chains_alive() { local p; for p in "${CH_PIDS[@]}"; do kill -0 "$p" 2>/dev/null && return 0; done; return 1; }
while chains_alive; do hb; sleep "$POLL"; done
wait
say "chains ended"

# 8. On an idle machine: LAT, then KPI, DASH, WEAK and RPT again; the console bundle once LAT and KPI passed
for g in p1 p3 p2; do
  w=$(wt "$g"); log="$R/$g.log"; r=$(next_idx "$g")
  if [ "$r" -lt "$NCH" ]; then say "$g did not finish (stage ${FULL[$r]}): no LAT"; continue; fi
  [ "$r" -lt "$NFULL" ] || continue
  [ "${HDR[$g]:-0}" = 1 ] || part_header "$g" "$r" 0
  if [ "$r" -lt $((NFULL - 1)) ]; then
    if wait_idle; then idle="idle"; else idle="not idle after $IDLE_MAX_MIN min"; fi
    ld="machine before LAT: CPU $(cpu_load) %, win64 MATLAB sessions $(n_matlab) ($idle)"
    echo "$ld $(date)" >> "$log"; say "$g: $ld"
    run_ml "$w" "$log" "$(stage_cmd "${FULL[@]:r:NFULL-1-r}")"
  fi
  if [ "$(next_idx "$g")" -gt "$I_KPI2" ]; then
    if run_ml "$w" "$log" "startup; export_gui_bundle('$(cygpath -m "$V7")/profiles')"; then
      echo "##### STAGE BUNDLE done #####" >> "$log"; say "$g: console bundle exported"
    else
      say "$g: console bundle export failed (see $log)"
    fi
  else
    say "$g: LAT or KPI failed (see $log); no console bundle"
  fi
done
say "v7 done"
