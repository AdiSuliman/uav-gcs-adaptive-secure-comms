#!/usr/bin/env bash
# The revised proposal's KPIs for profile 1, read in an isolated copy of its C2e
# (docs/c2e_lect_protocol.md). Profile 1's tree is only read; nothing in it is written.
#
#   bash tools/c2e_lect_isolated.sh check     preconditions only (profile 1's C2e finished, inputs
#                                             older than its start, protocol and code committed
#                                             before it, the code is the pre-registered port)
#   bash tools/c2e_lect_isolated.sh prepare   check, then a new worktree of the code commit at
#                                             $C2E_ISO and profile 1's C2e inputs copied into it
#                                             read-only, SHA-256 before and after the copy
#                                             (manifest: $C2E_ISO/C2E_LECT_ISOLATED)
#   bash tools/c2e_lect_isolated.sh command   the gated MATLAB command (p3 slot, cd into the copy)
#   bash tools/c2e_lect_isolated.sh run       prepared copy: that command through the gated
#                                             wrapper, then verify
#   bash tools/c2e_lect_isolated.sh verify    the copy's inputs still match the manifest, the gate
#                                             passed and the reading was written
# Exit 0 on success, 1 on a refused precondition or a failed verification, 2 on a usage error.
# Settings (environment): C2E_P1 profile 1's tree, C2E_ISO the copy, C2E_CODE the code commit
# (branch lect-p1), C2E_P1_COMMIT profile 1's code, C2E_READERS_REF lect-kpi's readers,
# C2E_WRAPPER the gated wrapper, C2E_SLOT its slot, C2E_NEED_GB its memory floor, C2E_DEVIATION a
# committed deviation note (docs/c2e_lect_deviation_*.md) for a protocol or code commit after
# the C2e start.

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
P1=${C2E_P1:-"/c/Users/Adi Suliman/uav-gcs-v7"}
ISO=${C2E_ISO:-"/c/Users/Adi Suliman/uav-gcs-c2elect-p1"}
CODE=${C2E_CODE:-8118281b601d75eeb899e4ceaa2785ee6e2ee54b}
P1_COMMIT=${C2E_P1_COMMIT:-208602b2fecaf531875354ce9e6e0cf5339522d5}
READERS_REF=${C2E_READERS_REF:-e84a5fd6200e9763853b8e2a400c005ec9801627}
WRAP=${C2E_WRAPPER:-"/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh"}
SLOT=${C2E_SLOT:-uav-gcs-v7-p3}
NEED_GB=${C2E_NEED_GB:-45}
DEVIATION=${C2E_DEVIATION:-}
PROTO=docs/c2e_lect_protocol.md
MAN="C2E_LECT_ISOLATED"
G="git --no-optional-locks"

# C2e's inputs (evaluate_policies.m and its callees) and the KPI 1 reading the three states read
REQ=(data/policy_pools.mat data/trained_dqn.mat params.mat)
OPT=(data/clean_test_pools.mat results/eval_detector_metrics.mat results/eval_detector_metrics_fresh2.mat
     results/detector_predictions_fresh2.mat results/detector_predictions.mat)
# Profile 1's own C2e results, the gate's reference
REF=(results/policy_evaluation.mat results/policy_evaluation.txt)
# Identity only (hashed, not copied): what profile 1's pools and agent were built from
IDN=(data/fusion.mat data/trained_detector.mat data/ood_thresholds.mat data/check_pools.mat
     data/drop_threshold.mat data/clean_val_pools.mat)
# The files the code commit changes in profile 1's code, and those it takes from lect-kpi unchanged
PORT=(code/decision/decision_config.m code/decision/evaluate_policies.m code/decision/link_env.m
      code/decision/per_metrics.m code/decision/policy_decide.m code/decision/policy_setup.m
      code/decision/rollout_policy.m code/decision/rule_core_policy.m code/evaluation/c2e_lect.m
      code/evaluation/c2e_lect_gate.m code/evaluation/c2e_lect_read.m code/evaluation/lect_kpis.m
      code/evaluation/lect_lines.m code/evaluation/per_reduction.m code/evaluation/three_state_view.m
      code/tests/test_c2e_lect.m)
SAME=(code/evaluation/lect_kpis.m code/evaluation/per_reduction.m code/evaluation/three_state_view.m
      code/decision/per_metrics.m code/decision/rule_core_policy.m)
LINES_FN=(three_states three_txt per_lines rec_lines has_core core_tag tq ternary)

say() { echo "c2e_lect: $*"; }
fail() { echo "c2e_lect: REFUSED: $*" >&2; exit 1; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
mtime() { stat -c %Y "$1"; }
winpath() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

fn_block() {   # the lines of local function $2 of file $1, up to the next function, no CR, no trailing blank lines
  tr -d '\r' < "$1" | awk -v n="$2" '
    /^function / { f = $0; sub(/\(.*/, "", f); sub(/^function ([^=]*=)? */, "", f); p = (f == n) }
    p { print }' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}

live_path() {   # a tree no step may write into
  local b; b=$(basename "$1")
  case "$b" in uav-gcs-v7|uav-gcs-v7-p3|uav-gcs-v7-p2|uav-gcs-v7-deploy|uav-gcs-logs) return 0;; esac
  case "$1" in */d91q|*/d91q/*) return 0;; esac
  return 1
}

c2e_start() {   # epoch, file and line of the last C2e start in profile 1's stage logs that has its done line
  local best=0 bf="" bl=0 f n d e
  shopt -s nullglob
  for f in "$P1"/logs/stage_*.txt; do
    while IFS=: read -r n rest; do
      d=${rest#*'##### STAGE C2e (evaluate_policies) '}; d=${d% #####*}
      e=$(date -d "$d" +%s 2>/dev/null) || continue
      if [ "$e" -gt "$best" ]; then best=$e; bf=$f; bl=$n; fi
    done < <(grep -n -a '^##### STAGE C2e (evaluate_policies) ' "$f" | tr -d '\r')
  done
  shopt -u nullglob
  [ "$best" -gt 0 ] || { echo "none"; return; }
  if tail -n +"$bl" "$bf" | grep -a -q '^##### STAGE C2e done in '; then echo "$best $bf $bl"; else echo "running $best $bf $bl"; fi
}

check() {
  command -v git >/dev/null && command -v sha256sum >/dev/null || fail "git and sha256sum are needed"
  live_path "$ISO" && fail "$ISO is a live tree; the copy needs a path of its own"
  # protocol committed and unchanged in this checkout
  $G -C "$HERE" ls-files --error-unmatch "$PROTO" >/dev/null 2>&1 || fail "$PROTO is not committed in $HERE"
  $G -C "$HERE" diff --quiet HEAD -- "$PROTO" || fail "$PROTO differs from its commit in $HERE"
  # the code commit: profile 1's code plus the pre-registered port, the readers lect-kpi's unchanged
  $G -C "$HERE" cat-file -e "$CODE^{commit}" 2>/dev/null || fail "code commit $CODE not found"
  $G -C "$HERE" merge-base --is-ancestor "$P1_COMMIT" "$CODE" || fail "$CODE does not descend from profile 1's $P1_COMMIT"
  local want got f
  want=$(printf '%s\n' "${PORT[@]}" | sort); got=$($G -C "$HERE" diff --name-only "$P1_COMMIT" "$CODE" | sort)
  [ "$want" = "$got" ] || fail "$CODE changes other files than the pre-registered port: $(comm -3 <(echo "$want") <(echo "$got") | tr '\n' ' ')"
  for f in "${SAME[@]}"; do
    [ "$($G -C "$HERE" rev-parse "$CODE:$f")" = "$($G -C "$HERE" rev-parse "$READERS_REF:$f")" ] || fail "$f differs from lect-kpi's ($READERS_REF)"
  done
  local tmp; tmp=$(mktemp -d)
  $G -C "$HERE" show "$CODE:code/evaluation/lect_lines.m" > "$tmp/a.m"
  $G -C "$HERE" show "$READERS_REF:code/evaluation/measure_all_kpis.m" > "$tmp/b.m"
  for f in "${LINES_FN[@]}"; do
    [ -n "$(fn_block "$tmp/a.m" "$f")" ] && [ "$(fn_block "$tmp/a.m" "$f")" = "$(fn_block "$tmp/b.m" "$f")" ] \
      || { rm -rf "$tmp"; fail "lect_lines.m's $f is not measure_all_kpis.m's ($READERS_REF)"; }
  done
  rm -rf "$tmp"
  # profile 1's tree runs its own code
  [ -d "$P1" ] || fail "$P1 not found"
  [ "$($G -C "$P1" rev-parse HEAD)" = "$P1_COMMIT" ] || fail "$P1 is not at $P1_COMMIT"
  $G -C "$P1" diff --quiet HEAD -- code startup.m || fail "$P1's code differs from $P1_COMMIT"
  # its C2e finished; its results written after the start, its inputs older than it
  local st; st=$(c2e_start)
  case "$st" in none) fail "no C2e start in $P1/logs/stage_*.txt: profile 1's C2e has not run";;
                running*) fail "profile 1's last C2e ($st) has no done line: wait until it finishes";; esac
  S0=${st%% *}; rest=${st#* }; C2E_LOG=${rest% *}; C2E_LINE=${rest##* }
  for f in "${REF[@]}"; do
    [ -f "$P1/$f" ] || fail "$P1/$f absent"
    [ "$(mtime "$P1/$f")" -ge "$S0" ] || fail "$P1/$f is older than the C2e start ($(date -d @"$S0")): not this C2e's"
  done
  for f in "${REQ[@]}"; do [ -f "$P1/$f" ] || fail "$P1/$f absent"; done
  for f in "${REQ[@]}" "${OPT[@]}"; do
    [ -f "$P1/$f" ] || continue
    [ "$(mtime "$P1/$f")" -lt "$S0" ] || fail "$P1/$f changed after the C2e start: C2e did not read this content"
  done
  # pre-registration: protocol and code committed before the C2e start
  local tp tc
  tp=$($G -C "$HERE" log -1 --format=%ct -- "$PROTO"); tc=$($G -C "$HERE" log -1 --format=%ct "$CODE")
  if [ "$tp" -ge "$S0" ] || [ "$tc" -ge "$S0" ]; then
    [ -n "$DEVIATION" ] || fail "protocol ($(date -d @"$tp")) or code ($(date -d @"$tc")) committed after the C2e start ($(date -d @"$S0")); a deviation note is needed (C2E_DEVIATION)"
    case "$DEVIATION" in docs/c2e_lect_deviation_*.md) ;; *) fail "C2E_DEVIATION must be docs/c2e_lect_deviation_*.md";; esac
    $G -C "$HERE" ls-files --error-unmatch "$DEVIATION" >/dev/null 2>&1 && $G -C "$HERE" diff --quiet HEAD -- "$DEVIATION" \
      || fail "$DEVIATION is not committed unchanged"
    say "deviation note $DEVIATION"
  fi
  PROTO_BLOB=$($G -C "$HERE" rev-parse "HEAD:$PROTO")
  say "CHECK OK: C2e start $(date -d @"$S0" '+%Y-%m-%d %H:%M:%S') ($C2E_LOG line $C2E_LINE), code $CODE, protocol blob $PROTO_BLOB"
}

copy_in() {   # copy $P1/$1 to $ISO/$2 read-only, the same SHA-256 before, after and in the copy
  local src="$P1/$1" dst="$ISO/$2" h1 h2 h3
  mkdir -p "$(dirname "$dst")"
  h1=$(sha "$src"); cp -p "$src" "$dst" || fail "copy of $src failed"
  h2=$(sha "$dst"); h3=$(sha "$src")
  [ "$h1" = "$h2" ] && [ "$h1" = "$h3" ] || fail "$src changed during the copy"
  chmod a-w "$dst"
  echo "$h1 $(stat -c %s "$dst") $(mtime "$dst")"
}

prepare() {
  check
  [ -e "$ISO" ] && fail "$ISO exists: every reading starts from a new copy (remove it with git worktree remove)"
  $G -C "$HERE" worktree add --detach "$ISO" "$CODE" >/dev/null 2>&1 || fail "git worktree add $ISO $CODE failed"
  [ -z "$($G -C "$ISO" status --porcelain -- code startup.m)" ] || fail "$ISO's code is not $CODE"
  rm -rf "$ISO/results" "$ISO/data" "$ISO/ref" && mkdir -p "$ISO/results" "$ISO/data" "$ISO/ref" "$ISO/logs"
  local m="$ISO/$MAN.part" f h
  {
    echo "root $(winpath "$ISO")"
    echo "code $CODE (profile 1's $P1_COMMIT with the port; readers $READERS_REF)"
    echo "protocol $PROTO blob $PROTO_BLOB at lect-kpi $($G -C "$HERE" rev-parse HEAD)${DEVIATION:+ deviation $DEVIATION}"
    echo "p1 $(winpath "$P1") C2e start $(date -d @"$S0" '+%Y-%m-%d %H:%M:%S') log $(basename "$C2E_LOG") line $C2E_LINE"
  } > "$m"
  for f in "${REQ[@]}" "${OPT[@]}"; do
    if [ -f "$P1/$f" ]; then h=$(copy_in "$f" "$f") || exit 1; echo "input $f sha256 $h" >> "$m"
    else echo "absent $f" >> "$m"; fi
  done
  h=$(copy_in results/policy_evaluation.mat ref/p1_policy_evaluation.mat) || exit 1; echo "ref ref/p1_policy_evaluation.mat sha256 $h" >> "$m"
  h=$(copy_in results/policy_evaluation.txt ref/p1_policy_evaluation.txt) || exit 1; echo "ref ref/p1_policy_evaluation.txt sha256 $h" >> "$m"
  for f in "${IDN[@]}"; do
    if [ -f "$P1/$f" ]; then echo "identity $f sha256 $(sha "$P1/$f")" >> "$m"; else echo "identity $f absent" >> "$m"; fi
  done
  echo "prepared $(date '+%Y-%m-%d %H:%M:%S')" >> "$m"
  mv "$m" "$ISO/$MAN"
  say "PREPARED $ISO ($(grep -c '^input ' "$ISO/$MAN") inputs, manifest $ISO/$MAN)"
}

matlab_cmd() {
  echo "restoredefaultpath; cd('$(winpath "$ISO")'); startup; c2e_lect('all')"
}

verify() {
  [ -f "$ISO/$MAN" ] || fail "$ISO is not prepared"
  local ok=1 kind rel w1 h rest
  while read -r kind rel w1 h rest; do
    case "$kind" in input|ref) [ "$(sha "$ISO/$rel")" = "$h" ] || { echo "c2e_lect: $rel no longer matches the manifest" >&2; ok=0; };; esac
  done < "$ISO/$MAN"
  $G -C "$ISO" diff --quiet "$CODE" -- code startup.m || { echo "c2e_lect: $ISO's code differs from $CODE" >&2; ok=0; }
  if [ -f "$ISO/results/c2e_lect_gate.txt" ]; then
    head -n 1 "$ISO/results/c2e_lect_gate.txt" | grep -q '^GATE PASS' || { echo "c2e_lect: the gate failed: $(head -n 1 "$ISO/results/c2e_lect_gate.txt")" >&2; ok=0; }
  else echo "c2e_lect: no gate result" >&2; ok=0; fi
  [ -f "$ISO/results/c2e_lect.txt" ] || { echo "c2e_lect: no reading (results/c2e_lect.txt)" >&2; ok=0; }
  [ "$ok" = 1 ] || { echo "c2e_lect: VERIFY FAIL" >&2; exit 1; }
  say "VERIFY OK: $(head -n 1 "$ISO/results/c2e_lect_gate.txt"); reading $ISO/results/c2e_lect.txt"
}

case "${1:-}" in
  check)   check ;;
  prepare) prepare ;;
  command) echo "bash \"$WRAP\" $NEED_GB $SLOT logs/c2e_lect_p1_\$(date +%Y%m%d_%H%M%S).txt \"$(matlab_cmd)\"" ;;
  run)
    [ -f "$ISO/$MAN" ] || fail "$ISO is not prepared (run prepare first)"
    [ -e "$ISO/results/policy_evaluation.mat" ] && fail "$ISO already holds an evaluation; a new reading starts from a new copy"
    bash "$WRAP" "$NEED_GB" "$SLOT" "logs/c2e_lect_p1_$(date +%Y%m%d_%H%M%S).txt" "$(matlab_cmd)"; rc=$?
    say "MATLAB exit $rc"
    verify
    exit "$rc" ;;
  verify)  verify ;;
  *) echo "usage: bash tools/c2e_lect_isolated.sh check|prepare|command|run|verify" >&2; exit 2 ;;
esac
