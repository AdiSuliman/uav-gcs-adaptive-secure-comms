#!/usr/bin/env bash
# Tests of tools/c2e_lect_isolated.sh on a synthetic profile 1 tree (a worktree of 208602b with
# made-up data, results and stage log) and a stub wrapper in place of MATLAB. No MATLAB, no
# live tree: everything lives under a temporary folder and is removed at the end.
#   bash tools/test_c2e_lect_isolated.sh [tmp_parent]
# Prints PASS/FAIL per case and 'C2E_SCRIPT_TESTS n/m'; exit 0 when all pass.

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S="$HERE/tools/c2e_lect_isolated.sh"
PARENT=${1:-${TMPDIR:-/tmp}}
T=$(mktemp -d "$PARENT/c2e_t.XXXX") || exit 2
P1T="$T/p1"; N=0; OK=0
G="git --no-optional-locks"

cleanup() {
  chmod -R u+w "$T" 2>/dev/null
  for w in "$T"/iso*; do [ -d "$w" ] && $G -C "$HERE" worktree remove --force "$w" >/dev/null 2>&1; done
  $G -C "$HERE" worktree remove --force "$P1T" >/dev/null 2>&1
  $G -C "$HERE" worktree prune >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT

res() { N=$((N + 1)); if [ "$1" = 0 ]; then OK=$((OK + 1)); echo "PASS $2"; else echo "FAIL $2"; fi; }
expect() {   # expect <exit> <pattern> <name> -- command...
  local want=$1 pat=$2 name=$3; shift 4
  local out rc; out=$("$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && echo "$out" | grep -q -- "$pat"; then res 0 "$name"; else res 1 "$name (exit $rc): $(echo "$out" | tail -n 3)"; fi
}

# A profile 1 tree at its code, with data, results and a chain log of a finished C2e
$G -C "$HERE" worktree add --detach "$P1T" 208602b >/dev/null 2>&1 || { echo "cannot add the worktree"; exit 2; }
mkdir -p "$P1T/data" "$P1T/results" "$P1T/logs"
for f in data/policy_pools.mat data/trained_dqn.mat params.mat data/clean_test_pools.mat \
         results/eval_detector_metrics.mat results/eval_detector_metrics_fresh2.mat results/detector_predictions_fresh2.mat \
         data/fusion.mat data/trained_detector.mat; do
  head -c 4096 /dev/urandom > "$P1T/$f"; touch -d '2026-11-01 09:00:00' "$P1T/$f"
done
head -c 4096 /dev/urandom > "$P1T/results/policy_evaluation.mat"; echo "=== DECISION-LAYER EVALUATION ===" > "$P1T/results/policy_evaluation.txt"
touch -d '2026-11-01 11:30:00' "$P1T/results/policy_evaluation.mat" "$P1T/results/policy_evaluation.txt"
LOG="$P1T/logs/stage_A0_20261017_164221.txt"
printf '\r\n##### STAGE C2 (train_dqn) 01-Nov-2026 02:00:00 #####\r\n##### STAGE C2 done in 400.0 min #####\r\n' > "$LOG"
printf '\r\n##### STAGE C2e (evaluate_policies) 01-Nov-2026 10:00:00 #####\r\nSaved results/policy_evaluation.{txt,mat,png}\r\n##### STAGE C2e done in 70.0 min #####\r\n' >> "$LOG"

# The stub wrapper: records its arguments and writes what a passing (or failing) run writes
cat > "$T/wrap.sh" <<'EOS'
#!/usr/bin/env bash
echo "$@" > "$(dirname "$0")/wrap_args.txt"
d=$(echo "$4" | sed -n "s/.*cd('\([^']*\)').*/\1/p"); d=$(cygpath -u "$d" 2>/dev/null || echo "$d")
mkdir -p "$d/results"
if [ -f "$(dirname "$0")/fail_gate" ]; then echo "GATE FAIL: 1 mismatches" > "$d/results/c2e_lect_gate.txt"; exit 1; fi
echo "GATE PASS: stub" > "$d/results/c2e_lect_gate.txt"; echo "reading" > "$d/results/c2e_lect.txt"; exit 0
EOS
export C2E_P1="$P1T" C2E_ISO="$T/iso" C2E_WRAPPER="$T/wrap.sh"

expect 0 'CHECK OK: C2e start 2026-11-01 10:00:00' 'check passes on a finished C2e' -- bash "$S" check
expect 0 'PREPARED' 'prepare makes the copy' -- bash "$S" prepare
M="$T/iso/C2E_LECT_ISOLATED"
r=1; [ "$(grep -c '^input ' "$M")" = 7 ] && grep -q '^absent results/detector_predictions.mat' "$M" \
  && grep -q '^ref ref/p1_policy_evaluation.mat sha256 ' "$M" && grep -q '^identity data/check_pools.mat absent' "$M" \
  && grep -q "^input data/policy_pools.mat sha256 $(sha256sum "$P1T/data/policy_pools.mat" | cut -d' ' -f1) " "$M" && r=0
res $r 'the manifest lists inputs, absent files, references and identities with their hashes'
r=1; cmp -s "$P1T/data/trained_dqn.mat" "$T/iso/data/trained_dqn.mat" && [ ! -w "$T/iso/data/trained_dqn.mat" ] \
  && cmp -s "$P1T/results/policy_evaluation.txt" "$T/iso/ref/p1_policy_evaluation.txt" && [ ! -e "$T/iso/results/policy_evaluation.mat" ] \
  && [ ! -e "$T/iso/data/clean_val_pools.mat" ] && r=0
res $r 'inputs copied read-only, references in ref/, no stale results of the checkout'
r=1; [ "$($G -C "$T/iso" rev-parse HEAD)" = "$($G -C "$HERE" rev-parse cd00a01)" ] && r=0
res $r 'the copy is a worktree of the code commit'
expect 1 'exists' 'prepare refuses an existing copy' -- bash "$S" prepare
expect 0 "uav-gcs-v7-p3 logs/c2e_lect_p1_" 'command prints the gated call in the p3 slot' -- bash "$S" command
r=1; m=$(bash "$S" command | sed -n 's/.*\.txt "\(.*\)"$/\1/p')
case "$m" in *\"*|*run_stage\(*) ;; "restoredefaultpath; cd('"*"'); startup; c2e_lect('all')") r=0;; esac
res $r "the MATLAB command cds into the copy, without double quotes or run_stage"
expect 0 'VERIFY OK' 'run calls the wrapper and verifies' -- bash "$S" run
r=1; read -r a b c rest < "$T/wrap_args.txt"; [ "$a $b" = "45 uav-gcs-v7-p3" ] && case "$c" in logs/c2e_lect_p1_*.txt) r=0;; esac
res $r 'the wrapper gets 45 GB, the p3 slot and a new log'
expect 1 'already holds an evaluation' 'run refuses a used copy' -- bash -c "touch '$T/iso/results/policy_evaluation.mat'; bash '$S' run"
chmod u+w "$T/iso/params.mat"; echo x >> "$T/iso/params.mat"
expect 1 'params.mat no longer matches the manifest' 'verify finds a changed input' -- bash "$S" verify

# A failing gate: no reading, verify fails
touch "$T/fail_gate"
expect 1 'the gate failed' 'a failed gate fails the run' -- env C2E_ISO="$T/iso2" bash -c "bash '$S' prepare >/dev/null && bash '$S' run"
rm -f "$T/fail_gate"

# Refusals
expect 1 'is a live tree' 'check refuses a live tree as the copy' -- env C2E_ISO="$T/uav-gcs-v7" bash "$S" check
expect 1 'does not descend' 'check refuses code that is not profile 1s' -- env C2E_CODE=e84a5fd bash "$S" check
expect 1 'not found' 'check refuses an unknown code commit' -- env C2E_CODE=0123456789abcdef0123456789abcdef01234567 bash "$S" check
touch -d '2026-11-01 10:30:00' "$P1T/data/trained_dqn.mat"
expect 1 'changed after the C2e start' 'check refuses an input newer than the C2e start' -- bash "$S" check
touch -d '2026-11-01 09:00:00' "$P1T/data/trained_dqn.mat"
touch -d '2026-11-01 09:30:00' "$P1T/results/policy_evaluation.mat"
expect 1 'older than the C2e start' 'check refuses reference results of another C2e' -- bash "$S" check
touch -d '2026-11-01 11:30:00' "$P1T/results/policy_evaluation.mat"
printf '\r\n##### STAGE C2e (evaluate_policies) 02-Nov-2026 08:00:00 #####\r\n' >> "$LOG"
expect 1 'has no done line' 'check refuses a C2e still running' -- bash "$S" check
sed -i 's/02-Nov-2026 08:00:00/01-Nov-2026 08:00:00/' "$LOG"
expect 0 'CHECK OK: C2e start 2026-11-01 10:00:00' 'an earlier unfinished start does not count' -- bash "$S" check
sed -i 's/01-Nov-2026 10:00:00/01-Jan-2026 10:00:00/; s/01-Nov-2026 08:00:00/01-Jan-2026 08:00:00/' "$LOG"
touch -d '2025-12-01 09:00:00' "$P1T/data/policy_pools.mat" "$P1T/data/trained_dqn.mat" "$P1T/params.mat" "$P1T/data/clean_test_pools.mat" \
  "$P1T/results/eval_detector_metrics.mat" "$P1T/results/eval_detector_metrics_fresh2.mat" "$P1T/results/detector_predictions_fresh2.mat"
expect 1 'committed after the C2e start' 'check refuses a protocol or code newer than the C2e start' -- bash "$S" check
expect 1 'must be docs/c2e_lect_deviation_' 'a deviation note must be such a file' -- env C2E_DEVIATION=README.md bash "$S" check
expect 1 'is not committed unchanged' 'an uncommitted deviation note is refused' -- env C2E_DEVIATION=docs/c2e_lect_deviation_1.md bash "$S" check
rm -f "$LOG"
expect 1 'has not run' 'check refuses a profile 1 without C2e' -- bash "$S" check
echo "% x" >> "$P1T/code/decision/link_env.m"
expect 1 "code differs" 'check refuses a profile 1 tree whose code changed' -- bash "$S" check
expect 2 'usage' 'an unknown subcommand is a usage error' -- bash "$S" other

echo "C2E_SCRIPT_TESTS $OK/$N"
[ "$OK" = "$N" ]
