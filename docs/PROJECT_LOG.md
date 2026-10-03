# Project Execution Log (Living Document)

**Last Updated:** 2026-09-23 (Session 12) | **Status:** KPI #2 now measured against the no-attack link as the proposal defines it (D27): 95.6%, 37/41 runs restored within 2× clean. Work proceeds item by item through the agreed improvement plan (Session 12). Speed-diverse full re-run (D25) and demo_gui v3 (D26) from Session 11 unchanged.

## Current headline numbers (2026-09-21 full re-run, speed-diverse data, D25)
| Metric | Latest | Previous (single-speed, D22/D23 baseline) |
|---|---|---|
| CNN accuracy (offline test, 2,727 samples) | **96.41%** (macro-F1 96.39%) | 96.73% (96.73%) |
| Offline accuracy vs UAV speed (7 bins) | 92.7% (50–60 km/h) … 98.2%; rest within 2.6 pts | not measured |
| CNN accuracy (closed loop, 9 threats × 6 SNR) | **98.1%** (53/54) | 100% (54/54) |
| Closed-loop detection over 50–120 km/h (8 speeds) | **98.1%** (212/216), FAR 0/48 | not measured |
| KPI #2 recovery vs no-attack link (D27) | **95.6%** per-run (95.3% per-threat); 37/41 restored ≤ 2× clean, 4 marginal, 1 missed; speed sweep 95.6% | not measured this way |
| Recovery vs BER-before (previous metric) | 76.3% per-run (75.9% per-threat); 72.4% in the speed sweep | 74.6% |
| Decision latency (mean / median, CNN+DQN) | **10.21 / 10.05 ms** (CNN 8.88 + DQN 1.33); reproduced 2026-09-23: 10.63 / 9.99 ms | 6.09 / 5.67 ms (previous build) |
| FAR (non-hostile, 180 trials over SNR) | 0.0% (95% CI upper 3.3% per-class n=90, 1.7% combined n=180) | 0.0% (same bound) |
| DQN-vs-rule action agreement | 53.7% (29/54) | ~44% |
| Survivability Map A / Map B recoverable | **85.5% / 88.3%** | 83.8% / 87.5% |

---

## Phase A: Link Model & Dataset ✅ COMPLETE

| Step | Status | Date | Notes |
|---|---|---|---|
| A1-A2 | ✅ | 2026-08-20 | AWGN link validation, BER matches theory |
| A3 | ✅ | 2026-08-28 | Rician K=10dB, fd=160Hz: 1.43-1.53× degradation |
| A4 | ✅ | 2026-09-02 | 8 threats validated (barrage, reactive, spoofing, noise, path, antenna, sweeping, benign) |
| A5-A6 (v1) | ✅ | 2026-09-05 | Dataset: 10,686 frames, spectrograms [128×128×1] extracted |
| A5-A6 (v2) | ✅ | 2026-09-15 | Dataset expanded: `frames_per_config` 50→100 → **27,246 frames**, re-extracted after spoofing fix |
| A5-A6 (v3) | ✅ | 2026-09-21 | **Speed-diverse dataset (D25):** 27,270 frames, every 100-frame block at its own continuous random speed in 50–120 km/h (270 model builds, ~102 min); per-frame speed stored |

---

## Phase B: Detection ✅ COMPLETE

| Step | Status | Accuracy | Date | Notes |
|---|---|---|---|---|
| B1 | ✅ | — | 2026-09-08 | Data split 80/10/10, z-scored 7 features |
| B2 (v1) | ✅ | 78.8% | 2026-09-09 | CNN+scalar hybrid, 7 classes |
| B2.5 | ✅ | — | 2026-09-10 | Temporal features: var_rssi_10, dber_dt, burst_ratio |
| B2 (v2) | ✅ | 92.13% | 2026-09-11 | With 7 features, reactive_jamming 7.2%→85.5% |
| B3 (9-class, v1) | ✅ | 90.90% | 2026-09-13 | +sweeping_jammer, +benign_interference, +none |
| B3 (9-class, v2) | ✅ | **98.05%** | 2026-09-18 | Post spoofing root-cause fix (see below), verified 2x independently |
| B3 (v3, post-D18) | ✅ | 96.73% | 2026-09-19 | Rx_IQ tap point fixed (D18); genuine SNR-dependent degradation at the low edge |
| B3 (v4, speed-diverse) | ✅ | **96.41%** | 2026-09-21 | Trained/tested on 50–120 km/h data (D25); macro-F1 96.39%; reactive_jamming recall 87.1% |

**Key Finding (v1, superseded):** jamming 67.3%, spoofing 76.2% weak; noise_burst, antenna_fault, sweeping (100%). All classes now well-separated post-fix — see Session 2026-09-18 below.

---

## Phase B-exp: CNN-LSTM Detector — NOT PURSUED FURTHER

Built and evaluated (2026-09-15/16) as a proposed fix for spoofing's weak recall (proposal risk #5 mitigation: "compare multiple model architectures"). Dataset expanded to 27,246 frames specifically to give the LSTM enough sequence data.

| Config | CNN-LSTM overall | CNN+scalar (contemporary) | Delta on spoofing |
|---|---|---|---|
| Run 1 (27,246 frames) | 90.7% | — | -9.8pp vs CNN |
| Run 2 (post data-leakage fix) | lower | — | -21.8pp vs CNN |

**Decision (2026-09-16, see D13):** CNN-LSTM consistently underperformed CNN+scalar on spoofing across two dataset sizes, even after fixing sequence-window data leakage and per-class split imbalance. Once spoofing was fixed at its true root cause (see below, same day) — a data-generation bug, not a detector-architecture limitation — the entire premise for LSTM comparison dissolved: CNN alone now exceeds LSTM's best result by a wide margin with far fewer parameters. Kept in the repo (not deleted) as the actual evidence of proposal risk #5's "compare multiple architectures" mitigation.

---

## Phase C: Recovery & Closed-Loop ✅ COMPLETE (v6, fully verified)

### C1: Rule-Based Policy ✅
```
jamming → channel_switch (15dB)
reactive_jamming → channel_switch_fast (10dB)
sweeping_jammer → channel_switch_fast (15dB)
spoofing → freq_diversity (8dB)
path_loss → rate_reduce (6dB)
noise_burst → rate_reduce (9dB)
antenna_fault → spatial_diversity (12dB)
benign_interference → no_action
none → no_action
```
**Note (found 2026-09-19, see design clarification in README):** `rule_based_policy.m`'s own per-threat `mitigation_db` values above are computed but never applied anywhere in the closed-loop pipeline — both call sites (`run_closed_loop_diagnostic.m`, `measure_kpi3_recovery_time.m`) discard that output. Only the *action name* feeds the DQN-vs-rule agreement comparison; physical effect for both policies is computed via the shared `action_mitigation_db` (25/15/25/25dB per action name). Not a bug — the comparison is decision-policy-only by design — but must be stated precisely in the report.

### C2: DQN Agent — 6 fix iterations

| Version | Date | Fix | Root cause found | Result |
|---|---|---|---|---|
| v1 | 09-13 | — | Synthetic generic reward (same for every threat) | 12.5% rule agreement, antenna_fault 5.4% |
| v2 | 09-13 | Raised `action_mitigation_db` (15/8/8/12→25/15/25/25 dB) + physical floor on path_loss_db/fault_atten_db | Magnitudes far below what EXP validated as achievable | antenna_fault 5.4%→20.2%, mean recovery 31.8%→42.2%-45.2% |
| v3 | 09-13 | Reward shaping (-40pp false-alarm penalty, benign_interference/none) + state-mismatch fix + 3x oversampling on benign_interference/none | benign_interference/none were being "recovered" like threats; reward scale drowned out by other threats | no_action correctly ranked highest for both; DQN-Rule agreement 22.2% |
| v4-v5 | 09-14 | `threat_encode` reassignment (antenna_fault at max distance from benign_interference/none); antenna_fault oversampled 3x | Scalar ordinal encoding let antenna_fault's Q-values bleed from the adjacent benign_interference penalty code; undertraining on antenna_fault's fine-grained ranking | DQN-Rule agreement 22.2%→55.6%; antenna_fault recovery 0.7%→17-20% |
| **v6** | **09-18** | **Full one-hot state encoding (13-dim), replacing the entire scalar-ordinal `threat_encode` scheme (v4-v5's patch).** Post-training validation Gate A/B added — refuses to save an agent that fails either. | The v4-v5 fix patched the *symptom* (which codes were adjacent) but kept the underlying flaw (scalar input the network reads as continuous). One-hot removes the adjacency-bleed failure mode structurally rather than by careful code placement. | Both gates pass; no adjacency-bleed possible by construction. Single shared `build_dqn_state.m` guarantees train/inference encoding can never drift again. |

**Design note (unchanged from v5, still applies):** the four non-zero actions are mechanistically identical in the current implementation — each subtracts `action_mitigation_db.(action)` dB from the threat's own severity field. Most residual "DQN vs rule disagreement" is cosmetic.

### C3: Closed-Loop — ✅ FULLY VERIFIED (2026-09-18/19)

**Sliding-window bug found and fixed (2026-09-18):** a full SNR sweep in `run_closed_loop_diagnostic.m` revealed closed-loop detection accuracy of only 79.6% (vs 98.05% on the held-out test set), with reactive_jamming→jamming and none→path_loss failing **100%** of the time across all SNR points. Root cause: the script fed the CNN neutral placeholder values (0,0,1) for the 3 temporal features (no history exists in a single-shot run), while the CNN was trained on real sliding-window features — and reactive_jamming's entire distinguishing signature *is* its temporal pattern. Each Simulink run actually returns ~20 frames (not 1); the old script discarded 19 of them.

First fix attempt (naive) built temporal features from all 20 frames but **made things worse** (66.7% accuracy, jamming and path_loss dropped to 0%) — root cause: `run_dataset_sweep.m` marks the last frame's BER as NaN in every run (delay_bits truncation), and NaN silently propagated through the network, zeroing entire class outputs. `prepare_data.m` had always guarded against this (`feats(isnan(feats))=0`) but the closed-loop script didn't.

**Final fix:** last-valid-frame selection via `find(~isnan(ber_f),1,'last')`, NaN guards mirroring `prepare_data.m` exactly, and before/after BER both averaged across all valid frames (not single-frame-vs-single-frame, an additional noise source).

**Result: closed-loop detection accuracy 100% (54/54)** — all 9 classes, all 6 SNR points. FAR returned to normal (~0%, down from a spurious 64.5% under the broken feature pipeline).

| Metric | Value |
|---|---|
| Detection accuracy (closed loop) | **100%** (54/54) |
| Mean BER recovery (real threats) | **74.9%** |
| Median latency (CNN+DQN) | **~3.3ms** |
| benign_interference / none | Both correctly resolve to `no_action` |

### C3 re-run on speed-diverse data (2026-09-21)

Closed-loop diagnostic (9 threats × 6 Eb/N0 = 54 runs, sliding window of 20 frames): **53/54 detected (98.1%)**, mean recovery **76.3%**, latency mean 10.21 / median 10.05 ms, DQN-vs-rule agreement 29/54 (53.7%). The single detection miss was antenna_fault @ 0 dB → sweeping_jammer at 31.2% confidence, after which the DQN chose `no_action`.

| Threat | Closed-loop detection | DQN action | Rule action | Mean recovery | Recovery @ 0 dB → 10 dB |
|---|---|---|---|---|---|
| jamming | 6/6 | channel_switch | channel_switch | 85.8% | 66.9 → 97.3 |
| reactive_jamming | 6/6 | channel_switch | channel_switch(_fast) | 85.7% | 65.3 → 98.0 |
| sweeping_jammer | 6/6 | channel_switch (5), freq_diversity (1) | channel_switch(_fast) | 60.4% | 24.5 → 93.1 |
| noise_burst | 6/6 | channel_switch | rate_reduce | 71.6% | 39.3 → 96.1 |
| path_loss | 6/6 | spatial_diversity | rate_reduce | 83.9% | 64.1 → 98.2 |
| spoofing | 6/6 | channel_switch | freq_diversity | 83.5% | 57.0 → 99.0 |
| antenna_fault | 5/6 | channel_switch (5), no_action (1) | spatial_diversity | 60.6% (5 runs) | n/a → 90.5 |
| benign_interference | 6/6 | no_action | no_action | N/A | — |
| none | 6/6 | no_action | no_action | N/A | — |

Reading the recovery column: sweeping_jammer and noise_burst start from a low BER, so their recovery percentage is bounded by a low physical ceiling (EXP: 99.6% and 94.2% of ceiling at mid severity, 0 dB). The genuine decision-quality gaps are path_loss (~80% of ceiling) and antenna_fault (~64%).

**Speed sweep (`eval_speed_robustness.m`, ~13 min):** 8 speeds × 3 Eb/N0 × 9 threats. Detection 96.3 / 100 / 96.3 / 96.3 / 96.3 / 100 / 100 / 100% at 50.0 / 57.3 / 66.8 / 72.0 / 84.6 / 97.2 / 108.9 / 120.0 km/h (212/216 overall); all four misses are antenna_fault (1 of 3 SNR points each); FAR 0/48; mean recovery 70.3 / 69.2 / 73.5 / 71.9 / 72.7 / 73.5 / 73.6 / 74.2% (72.4% overall). One miss moves a speed point by 3.7%, so the dips are not evidence of a speed dependence.

---

## Phase EXP: Deep Countermeasure Exploration ✅ COMPLETE

Ran `explore_countermeasures.m`: **2550 scenarios, 85.8 minutes**, 3 mechanisms (`field_reduction`, `awgn_margin_boost`, `atten_reduction` for antenna_fault only) across 8 threats × 5 severity levels × 6 SNR points.

**Crash bug found and fixed (2026-09-18):** `current_best_static.(b.threat)` in the report-generation section accessed a field that didn't exist for all 8 threats vs. only 6 fields in the historical comparison struct — caused the script to crash **after** 75-86 minutes of runtime, at the report-writing stage, after the actual data was already safely saved. Fixed with an `isfield` guard in the report builder (the console-output path already had one).

This EXP data feeds both the C2 `action_mitigation_db` magnitudes (established 09-13/14, unchanged since) and the survivability boundary mapping below.

**Re-run 2026-09-21 (inside the full `main.m` pass):** 2,790 simulations, 77.8 min, no crash (the `isfield` guard held). EXP runs at the nominal 72 km/h condition and is BER-only, so it does not depend on the speed-diverse dataset.

---

## Survivability Boundary Mapping — Proposal Deliverable #7 ✅ COMPLETE (2026-09-19)

### Bug found and fixed: single-map conflation
The first version of `map_survivability_boundary.m` built one map from `min([sub.ber_after])` across **all** mechanisms without filtering by mechanism — silently conflating genuine threat neutralization with `awgn_margin_boost` (an SNR-margin trick that can make the link outperform the clean-channel floor without touching the attack at all). Symptom: sweeping_jammer and benign_interference showed "achieved recovery" at 221-283% *of the theoretical ceiling* — physically impossible for pure neutralization, and the tell that margin-boost was silently winning the `min()`.

### Fix: two separate maps
```matlab
MECH_A = {'atten_reduction','field_reduction'};                       % genuine neutralization
MECH_B = {'atten_reduction','field_reduction','awgn_margin_boost'};   % all available means
```

| | Map A — Threat Neutralization | Map B — Link Survivability |
|---|---|---|
| Mechanisms | atten_reduction, field_reduction | + awgn_margin_boost |
| Recoverable | 84.6% (198/234) | 87.9% (211/240) |
| Marginal | 12.4% (29/234) | 9.6% (23/240) |
| Non-recoverable | 3.0% (7/234) | 2.5% (6/240) |

sweeping_jammer and benign_interference's "of ceiling" figures dropped from 283.8%/225.5% (Map B, unfiltered) to 105.7%/104.6% (Map A) — confirming the filter isolates genuine neutralization correctly.

### Gap analysis
1 cell: **path_loss, level=8, SNR=10dB** — Map B ratio ≈ 0 (link survives, via margin) vs. Map A ratio = 6.06x (non-recoverable, threat not actually neutralized). This is the concrete instance of the proposal's goodput-tradeoff regime: the link survives by trading margin/rate, not by removing the attack.

### Known coverage gap (documented, not a bug)
`path_loss` at level=4 (its lowest severity) has **no Map A data** — confirmed root cause: `mag_field_reduction = [5 10 15 20 25]` is a single global sweep range applied to every threat, and every value in it exceeds path_loss's level=4 severity. The legitimacy filter (`level - magnitude < 0` → excluded, since it would imply unphysical signal amplification) correctly excludes all 5 candidate points at that level, leaving zero legitimate Map A records there. Map B (which includes awgn_margin_boost, unaffected by this filter) has full coverage at that level.

### Re-run 2026-09-21

Map A (neutralization): **85.5% recoverable** / 11.5% marginal / 3.0% non-recoverable (200 / 27 / 7 of 234 states). Map B (survivability): **88.3%** / 9.2% / 2.5% (212 / 22 / 6 of 240). One gap cell, unchanged: path_loss level 8 @ 10 dB (Map A ratio 5.64× clean, Map B recoverable). Per-threat Map A recoverable, previous → latest: jamming 80→80%, noise_burst 90→90%, reactive_jamming 80→83%, path_loss 67→75% (of 24 mapped states), spoofing 97→97%, antenna_fault 60→60%, sweeping_jammer 93→97%, benign_interference 100→100%. The small shifts are simulation randomness (EXP and SURV are speed-independent); they also resolve the earlier doc/code mismatch (83.8/87.5 in README/PROJECT_LOG vs 84.6/87.9 in the interim report; gap ratio 6.06× vs 5.61×) — the repo docs now carry the latest values.

---

## Phase KPI: Proposal Measurement (section 5) ✅ COMPLETE

| KPI | Result | Notes |
|---|---|---|
| KPI 1 — Detection accuracy | 96.41% (offline, macro-F1 96.39%) / 98.1% (closed-loop) | 2026-09-21 re-run; target macro-F1 ≥ 90% |
| KPI 2 — BER recovery | 76.3% mean (real threats, closed-loop; 75.9% as mean of per-threat means) | See Phase C3 above |
| KPI 3 — DQN vs Rule decision speed | Rule ~4,700× faster (0.00028 ms vs DQN 1.33 ms); full decision 10.21 ms mean | Redefined from "recovery cycles" — see below |
| KPI 4 — FAR (False Alarm Rate) | 0.0% (0/180), upper 95% CI bound 3.3% per class | Rule-of-Three, n=90 per class |
| KPI 5 — End-to-end survivability | MET — jamming recovers 85.7% end-to-end; Map A / B 85.5% / 88.3% | Proposal deliverable #7 |

### KPI #3 redefinition (2026-09-18)
**Original problem:** `measure_kpi3_recovery_time.m` simulated "recovery cycles" via a halving loop that never called `sim()` or consulted either policy's actual action choice — DQN and rule-based always returned identical results regardless of which was "measured."
**Root conceptual issue:** both policies are single-shot deterministic dB reductions in this system — there is no multi-cycle convergence dynamic to measure.
**Fix:** redefined to measure decision **latency** instead. Rule-based: 1000 direct calls to `rule_based_policy.m`, averaged. DQN: pulled from the real `closed_loop_diagnostic_report.txt`. Result: rule-based faster by roughly three orders of magnitude (lookup table vs. neural network inference) — expected, but now measured correctly rather than reported as a meaningless "0 cycles for both."

**Also fixed same session:**
- `MAX_STALE_DAYS` was 3 days in `measure_all_kpis.m`/`measure_kpi3_recovery_time.m`, letting pre-DQN-fix KPI files count as "fresh" and produce numerically inconsistent aggregate reports → changed to 0.5 (12 hours).
- `diagnose_far_measurement.m`: `196*se` typo (should be `1.96*se`) in the 95% CI calculation (off by 100x); Rule-of-Three added for the FAR=0 case (a naive symmetric CI is meaningless at zero count).

---

## Phase D: Documentation & Defense (In Progress)

- [x] README.md — rewritten with current results (2026-09-19)
- [x] PROJECT_LOG.md — this document, rewritten (2026-09-19)
- [x] docs/DECISIONS.md — extended D12-D17 (2026-09-19)
- [x] KPI Dashboard (proposal deliverable #1) — built and generated in the 2026-09-21 full run (`results/kpi_dashboard.png`)
- [~] Interim Report — drafted; results chapters need syncing to the 2026-09-21 re-run (checklist in Session 11)
- [ ] Final Report
- [ ] Defense: 20+10 min, 10 slides
- [ ] Poster: 5% grade

---

## Known Issues & Limitations

### Resolved (2026-09-13/15)
Antenna Fault recovery, benign_interference reward gap, reactive_jamming misdetection false alarm, antenna_fault Q-value bleed (v1-v5), noise_burst latency test-harness artifact — see git history and prior versions of this log for full detail; all confirmed stable across independent re-runs.

### Resolved (2026-09-18)
1. **Spoofing 3-way confusion (formerly 53.0% recall)** — root-caused and fixed at the data-generation level (coherent QPSK injection, not incoherent noise). Recall now 98.7-99.7%. This was NOT a detector limitation as previously documented — it was a threat-injection bug. See D12.
2. **DQN scalar-ordinal state encoding** — replaced with one-hot (13-dim). See D14.
3. **Closed-loop sliding-window feature mismatch** — fixed; closed-loop detection accuracy 79.6%→100%. See D16.
4. **KPI #3 mock measurement** — redefined to real decision latency. See D15.
5. **explore_countermeasures.m crash-after-75min bug** — isfield guard added to report builder.
6. **Survivability map mechanism conflation** — split into Map A/Map B. See D17.

### Open (2026-09-19)
7. **`rule_based_policy.m`'s per-threat `mitigation_db` is unused dead output.** Both call sites discard it; physical mitigation for both DQN and rule-based always goes through the shared `action_mitigation_db`. Not a bug in outcome, but the report must describe the DQN-vs-rule comparison precisely as decision-policy-only, not two independently-realized countermeasure systems.
8. **`src/` directory** — exists locally (per Adi's file listing), not tracked in git, contents not yet audited.
9. **`extract_temporal_features.m`** — confirmed orphaned (not referenced by any script in the repo; its function was folded into `extract_spectrograms.m` at A6). Candidate for removal or explicit DEPRECATED marking.
10. **`.gitignore`** has 4 duplicate/overlapping `models/` entries accumulated across incremental commits — cosmetic, needs a cleanup pass.

### Open (2026-09-22)
11. ~~Decision latency 10.21 ms vs 6.09 ms~~ — **resolved 2026-09-23:** an independent diagnostic run gives 10.63 / 9.99 ms (mean / median), matching the full run. Cite ~10 ms (median); the 6.09 ms D23 figure belongs to the previous build.
12. **reactive_jamming recall 87.1%** (was 91.0%) and **antenna_fault** (92.8% recall, 5/6 closed-loop, 60.6% recovery) are the weak spots; the possible link between speed diversity and the reactive-vs-jamming temporal features is an untested hypothesis. Decide: targeted improvement vs. documented limitation.
13. **Interim report numbers are stale** relative to the 2026-09-21 re-run (checklist in Session 11) and to D27 (KPI #2 is now 95.6% vs the clean link; show both metrics with their definitions).
14. **`main.m` CHECKPOINT footer is a hard-coded string** with pre-re-run numbers (CNN 96.99%, closed-loop 100%, recovery 74.6%, latency 2.67 ms, Map A/B 84.6/87.9); the authoritative values are `results/kpi_summary.txt` and `results/kpi_dashboard.png`.
15. **`demo_gui.m` v3 not yet validated in MATLAB beyond first launches** — syntax-parsed and helper-tested outside MATLAB only; a slow-startup report (2026-09-22) was mitigated with a norm-stats cache and a fresh-session launch recommendation.

---

## Git Snapshots

| Commit | Phase | Date | Status |
|---|---|---|---|
| 2f8f5d3 | B3+C3 | 2026-09-13 | Phase B+C2+C3: 9-class CNN, DQN v2 retrain, diagnostics |
| 245e5aa | Cleanup | 2026-09-13 | Repo hygiene: diagnostic scripts moved into diagnostics/ |
| a826733 | C2 v3-v5 fixes + EXP + docs | 2026-09-14 | action_mitigation_db fix, reward shaping, state-mismatch fix, oversampling, threat_encode reassignment |
| 6f5f393 | Diagnostics + cleanup | 2026-09-14 | diagnose_antenna_fault_reward.m, diagnose_latency_position_test.m added |
| df82f6f | C3 verification | 2026-09-15 | run_closed_loop_with_detector.m verified post-fix; main.m cleanup |
| 6a1e6b1 | KPI framework | 2026-09-15 | FAR measurement + KPI aggregation framework added |
| 85c53da | Root-cause fixes | 2026-09-18 | Spoofing coherent-QPSK injection, one-hot DQN state, sliding-window fix, KPI/FAR framework |
| 1b29b3e | LSTM record | 2026-09-18 | CNN-LSTM comparison scripts committed (evidence for D13/risk #5) |
| c55c76f | Repo hygiene | 2026-09-19 | models/ added to .gitignore |
| 993c344 | Survivability tracking | 2026-09-19 | Map A/B outputs tracked as documented exception to results/ gitignore |
| ed47958 | Survivability fix | 2026-09-19 | map_survivability_boundary.m split into Map A/Map B with gap analysis |
| (pending) | D18 + KPI fixes | 2026-09-19 | Rx_IQ post-AWGN; KPI scripts read .mat; visualize_spectrograms 9-class; .gitignore cleanup; main.m re-run flags; README/PROJECT_LOG/DECISIONS updated |
| (pending) | D20 + D21 | 2026-09-19 | extract_closed_loop_frames.m (shared); FAR script rewritten (SNR set_param + sliding window + SNR sweep); no_action → N/A recovery; GPU warm-up strengthened |
| (pending) | D27 | 2026-09-23 | NEW recovery_vs_clean.m, NEW recompute_recovery_vs_clean.m; run_closed_loop_diagnostic.m, eval_speed_robustness.m, measure_all_kpis.m, build_kpi_dashboard.m, demo_gui.m (recovery vs clean; demo_gui also: video frames captured once per state transition); README/PROJECT_LOG/DECISIONS |
| c3fbdac | D25 + D26 | 2026-09-21/22 | init_params.m (speed envelope), run_dataset_sweep.m (speed-diverse), extract_spectrograms.m, prepare_data.m, eval_detector.m (accuracy vs speed), NEW eval_speed_robustness.m, main.m (flag + preset), demo_gui.m v3; README/PROJECT_LOG/DECISIONS updated |

---

## Session 2026-09-19 (Code Review + Fixes)

A full line-by-line review of every script in the repository (39 .m files, all diagnostics/, all LSTM comparison files, all model builders) was performed. Findings, in order of severity:

### Fixed this session

1. **Rx_IQ tap point (D18, CRITICAL) — `build_threat_model.m`.** `Rx_IQ` was wired from `Threat/1` (pre-AWGN) instead of `AWGN/1` (post-AWGN, matching `build_link_model.m` and `build_rician_model.m`). Every spectrogram (CNN training input) and every RSSI value in the system was computed from a signal that never included the swept AWGN noise; BER was unaffected (computed separately through the full chain). This explained the suspiciously flat per-SNR CNN accuracy (97.6%-98.9%) reported earlier in this log. **Fixed by rewiring the probe, then the full pipeline was re-run** (see "Full pipeline re-run COMPLETED" below). Post-fix accuracy is 96.99% with genuine SNR-dependent degradation at the low edge (94.1% @ 0dB), which is the physically-correct behavior. EXP/survivability are BER-only and were confirmed unaffected (not re-run).

2. **KPI aggregation scripts broken against current report format (CRITICAL).** `measure_kpi3_recovery_time.m` used `strsplit(txt, '--- Threat: ')` to parse `closed_loop_diagnostic_report.txt` — that literal delimiter no longer exists in the report (format changed to `'--- <threat> @ SNR=<x> dB ---'` when the sliding-window fix, D16, was added). This caused a **hard crash** (`error('Could not parse any threat blocks...')`) rather than a silent wrong answer. `measure_all_kpis.m` had the same issue for KPI#2/#5 (regex patterns matching a report format that no longer exists, silently producing empty/"NOT MET" results) plus `MAX_STALE_DAYS` still at 3 (undocumented drift from the 0.5 fix that was applied only to `measure_kpi3_recovery_time.m`). **Fixed:** both scripts now read `results/closed_loop_diagnostic_results.mat` (the struct `run_closed_loop_diagnostic.m` already saves) directly instead of regex-parsing the human-readable `.txt` report — immune to any future report-text reformatting. `MAX_STALE_DAYS` unified to 0.5 in both.

3. **`visualize_spectrograms.m` crash on the current 9-class dataset.** Hardcoded `subplot(2,4,c)` (8-cell grid, sized for the old 7-class dataset) would error on `subplot(2,4,9)`. Not part of `main.m`'s automated RUN flags, so it never surfaced as a pipeline failure — but would crash if run manually. **Fixed:** grid size now computed from `nC` (`ceil(sqrt(nC+1))` columns).

4. **`.gitignore` had 4 duplicate/overlapping `models/` lines** (accumulated across incremental commits). **Cleaned up** into one consolidated, commented file.

5. **Stale comments** in `train_detector.m` (said "softmax(7)"; code correctly uses dynamic `nClasses`=9) and `extract_spectrograms.m` (`spec.meta.temporal_note` referenced the old ~90-91% accuracy target). Both updated to reflect current state; neither affected actual computation.

6. **`rule_based_policy.m` documented, not changed (D19).** Added a header note explaining that its per-threat `mitigation_db` values are computed but never applied downstream — both call sites use only the action name; physical mitigation for both DQN and rule-based goes through the shared `action_mitigation_db`. Prevents the report from implying two independently-realized countermeasure systems are being compared.

### Confirmed via full read, no issues found
`main.m`, `init_params.m`, `build_dqn_state.m`, `dqn_agent.m`, `train_dqn.m`, `run_dataset_sweep.m`, `quick_ber.m`, `quick_ber_with_iq.m`, `run_awgn_sweep.m`, `prepare_data.m`, `eval_detector.m`, `explore_countermeasures.m`, `analyze_exploration_results.m`, `diagnose_far_measurement.m` (self-contained live simulation, not affected by the report-parsing bugs above), `run_closed_loop_diagnostic.m`, `run_closed_loop_with_detector.m`, all 6 `diagnostics/*.m` (historical/standalone, correctly scoped), all 5 CNN-LSTM comparison files, `build_link_model.m`, `build_rician_model.m`, `map_survivability_boundary.m`.

### Full pipeline re-run COMPLETED (post-D18) + follow-on bugs found and fixed

The full pipeline was re-run against the corrected model (A4 sanity → A5 dataset → A6 spectrograms → B1 split → B2 train → B3 eval → C2 DQN → C3 closed-loop → KPI). Post-fix headline numbers are in the table at the top of this document. Two follow-on bugs surfaced only once the re-run produced real noisy inputs:

7. **FAR measurement was itself buggy (D20).** After the re-run, `diagnose_far_measurement.m` reported none→path_loss confusion at ~72-78% FAR — but `run_closed_loop_diagnostic.m` reported none at 100% correct. Same trained model, contradictory results. Two causes, both in the FAR script:
   (a) it still used the pre-D16 neutral placeholder `[0,0,1]` for temporal features (the exact bug D16 fixed in the diagnostic, never propagated here);
   (b) more seriously, it rebuilt the threat model each trial but **never called `set_param(.../AWGN','SNR',...)`**, so every FAR trial ran at Simulink's default AWGN setting rather than the intended SNR — making a clean channel look like weak path_loss.
   **Fixed:** the sliding-window frame extraction was pulled out of `run_closed_loop_diagnostic.m` into a shared `extract_closed_loop_frames.m` (single source of truth, so a third copy can't drift), and `diagnose_far_measurement.m` was rewritten to use it, to set the AWGN SNR per trial, and to sweep SNR = 0/4/10 dB (N=30 each) for a proper characterization. **Result: FAR 0.0% across all 180 trials**, none CNN accuracy 98.9%, benign_interference 100%.

8. **no_action recovery reporting was misleading (D21).** In the closed-loop diagnostic, non-hostile classes (none, benign_interference) correctly got `no_action` from the DQN — but recovery% was still computed as `(BER_before - BER_after)/BER_before` on an untouched channel, i.e. two independent noise draws. At high SNR (BER ~1e-3) this produced large spurious values (e.g. none = -28.9% at 10 dB) that looked like a failure but were pure division noise (it swung both directions across SNR). **Fixed:** when the action is `no_action`, recovery is now reported as **N/A** ("no countermeasure applied, nothing to recover"), which also makes the correct behavior explicit rather than hiding it behind a confusing number. Manually verified: none chose no_action in all 6 SNR points, BER_before ≈ BER_after each time.

9. **GPU latency warm-up artifact (part of D21).** The `noise_burst` latency spike (~11-29ms vs ~2ms for everything else) was not class-specific — it was the largest spike inside the whole first (SNR=0) block, an artifact of cuDNN kernel autotuning finishing lazily on the first real-sized input, not the single dummy warm-up. **Fixed:** warm-up strengthened to 10 iterations with `rand` inputs + `wait(gpuDevice)`, so all latencies are steady (~2.5-3ms) from the first measured run. noise_burst dropped from 11ms to ~3ms.

### Still open (require Adi's input, not fixed this session)
- **`src/` directory** — present locally per file listing, not tracked in git, contents still not audited.
- **`extract_temporal_features.m`** — confirmed orphaned (superseded by the causal-window logic now inline in `extract_spectrograms.m`); recommended for `git rm`, pending confirmation.
- **reactive_jamming 88% recall** — below the 90% per-class line (macro-F1 still 96.98%). Confuses with continuous jamming; the distinction is temporal. Candidate for targeted improvement or documentation as a known limitation.

**Next Steps (in order):**
1. Finalize and run the KPI Dashboard script (`build_kpi_dashboard.m`, proposal deliverable #1) against the post-re-run numbers.
2. Audit `src/` directory contents; decide whether to track or discard.
3. `git rm extract_temporal_features.m` (pending confirmation).
4. Decide on reactive_jamming: targeted improvement vs. document as known limitation.
5. Write Phase D reports (interim + final), using this document and README.md as the factual source.

## Session 2026-09-21 (Session 10) — Interim report drafted; latency bugs found; demo GUI built

Three major threads this session: writing the interim report end-to-end, a
long cycle of external critique against the actual code and document (most
of it via a second AI reviewer Adi consulted in parallel), and building the
interactive demo GUI. Full detail below; headline outcome: two real system
bugs were found and fixed (D22, D23), one real math error was corrected
(FAR confidence-bound population size), and a working `demo_gui.m` (D24)
now exists after two rounds of MATLAB-specific bug fixes.

### Report: built from scratch, then hardened through repeated critique
The interim report (Word `.docx`) was assembled programmatically (title page,
TOC, bilingual abstract, 7 chapters with 17 rendered-as-images equations,
11+ figures, several tables, bibliography). Two build-tooling bugs were
found and fixed along the way, both worth remembering for any future
document-generation work in this style:
- A large fraction of body paragraphs across every chapter were silently
  missing from the actual `.docx` — the JS source called `para(...)` /
  `paraB(...)` / `bullet(...)` directly instead of `C.push(para(...))`, so
  the constructed Paragraph objects were built but never added to the
  document tree. Only headings, tables, and figures (which were correctly
  wrapped) survived. Fixed by grep-auditing every source file for bare
  calls and wrapping them; the fix nearly doubled the paragraph count.
- A second bug, `<align>` elements leaking into the raw OOXML from a
  parenthesization mistake in the abstract's paragraph calls, was crashing
  the document converter used to visually verify pages. Fixed, and
  `validate.py` (schema-level docx validation) was adopted as a
  non-negotiable check before ever presenting a build as final again —
  "looks right in a screenshot" is not the same as "the paragraph is
  actually in the file," a lesson from the first bug above.

The report then went through roughly seven rounds of external critique
(Adi relayed detailed technical review from a second AI he consulted
alongside this one). Each round was independently verified against the
actual code and the actual current document text — not accepted at face
value — because several rounds contained claims that turned out to be
either factually wrong about the code, or based on a stale/earlier version
of the document that had already been fixed. Roughly half of the critique
points across all rounds were real and fixed; the other half were checked
and explicitly rejected, with the verification shown. Genuine findings
that changed the report or the code:
- **BER-as-oracle:** the `ber` feature (and, on closer audit, `PLR`,
  `dber_dt`, and `burst_ratio`, which are all derived from it) requires
  simulator ground-truth (`tx_bits_out` vs `rx_bits_out`) unavailable to a
  real receiver. Documented as an explicit Limitations & Assumptions
  section (new report section 3.7) with a stated real-world substitution
  path (EVM / CRC frame-error-rate / FEC correction counts).
- **Decision latency didn't include preprocessing** — see D22 below.
- **Mitigation is a flat dB subtraction, not a dynamic RF simulation**, and
  `spatial_diversity` specifically doesn't model a real multi-antenna
  chain — both stated explicitly in section 3.7 rather than left implicit.
- **DQN-vs-rule "fairness"** — both policies share the same physical
  mitigation table; framed in the report as a deliberate methodological
  choice (isolating decision-quality from execution-strength), not an
  apology.
- **FAR confidence-bound math error (found by the reviewer, real):** the
  report cited "180 trials... upper bound 3.3%" in the same sentence —
  but 3.3% (3/90) is the Rule-of-Three bound for each class individually
  (n=90), while the correct bound across all 180 combined trials is 1.7%
  (3/180). Fixed throughout the report and in this log's headline table
  to state both numbers with their population sizes explicit.
- **Reward equation division-by-zero:** the report's protection note
  ("the denominator is guarded by ε") was originally only prose next to
  the equation; the equation image itself was regenerated with
  `max(BER_before, ε)` baked into the rendered math, matching the actual
  code (`train_dqn.m` line 79: `max(ber_before,eps)`).
- **Writing tone ("developer diary syndrome"):** sections describing bug
  fixes (the RRC/ISI delay fix, the closed-loop sliding-window fix, the
  warm-up fix) originally narrated the debugging process — initial
  suspicion, first attempt, what that attempt broke, second attempt. Per
  Adi's explicit direction, these were rewritten to describe the final
  architecture and the problem it solves, not the path taken to find it —
  human and readable, not a post-mortem.
- Several smaller fixes: a "Table 0" numbering typo (should be Table 1,
  two occurrences), one overly dense paragraph split into three plus a
  bullet list for a feature explanation, and an explicit statistical
  caveat on the FAR sample size (180 trials demonstrates the principle;
  Monte Carlo at tens-of-thousands of frames would be needed for
  industrial-grade resolution).

Rejected critique points, each verified false against the actual document
before being dismissed (not just asserted): a claimed "delay-scan runs
inside the closed loop" (grep-confirmed `quick_ber()` is never called from
`run_closed_loop_diagnostic.m`); a claimed "raw LaTeX pasted as text
instead of rendered equations" (grep-confirmed zero LaTeX-syntax
occurrences in the document XML — all 18 equations are rendered math
images); a claimed duplicate explanation under a figure caption (grep-
confirmed the explanation appears exactly once); a claimed figure-number
desynchronization (the report has no manual "see Figure N" cross-
references anywhere — captions are auto-numbered and never referenced
elsewhere in prose, so this class of bug isn't structurally possible here).
Two rounds also re-raised issues that had already been fixed in the
previous round (the diary-tone language, the apologetic fairness framing)
— both confirmed already absent before being (correctly) not re-touched.

The report also gained real-world grounding this session: an expanded
Chapter A (background/motivation with cited real incidents — a 1994 sarin-
gas drone attempt, a planned 2013 attack, a real attack on California's
power grid — and a related-work summary table), and substantially deeper
Chapters B and C (full paragraphs explaining engineering reasoning, not
terse bullet-equivalents), per Adi's direct request for more depth and a
more human writing style throughout. Six labeled image placeholders were
added at points where a real photo/diagram would strengthen the document
(QPSK constellation, LOS/multipath, example spectrograms, the RL agent-
environment loop, a MATLAB/Simulink screenshot, a sliding-window diagram)
— Claude cannot fetch external images into the build sandbox, so
public-domain source suggestions (U.S. DoD / Wikimedia, an RQ-11 Raven
launch photo) were given for Adi to source and supply directly.

### D22 — Decision latency now includes preprocessing, not inference-only
`run_closed_loop_diagnostic.m`'s `tic` was moved to the true start of the
per-decision block (before `spectrogram()`, dB conversion, normalization,
and resize), not immediately before `predict()`. The block's own comment
had always said "TIMED" for the whole sequence — the `tic` placement just
hadn't matched that intent. See DECISIONS.md D22 for full detail.

### D23 — spectrogram() warm-up; mean/median latency converged
The very first measurement after the D22 fix showed a large mean-median
gap (mean 18.88ms, median 8.42ms) — traced to MATLAB's `spectrogram()`
paying a one-time JIT/cache cost on its first call in the session,
landing on whichever threat ran first in the sweep. Fixed by extending
the existing CNN/DQN warm-up to also call `spectrogram()` on dummy IQ
data several times before timing starts (same pattern as the existing
network warm-up, applied to the one function that hadn't had it). Adi
re-ran and confirmed convergence: mean 6.09ms / median 5.67ms, a 0.42ms
gap (was 10.46ms) — the fix is verified working, not just theorized.

### D24 — demo_gui.m built (operator-console live demo)
Built in two passes. First pass (basic dropdown + slider + Run + live
spectrogram/results text) hit a MATLAB "Attempt to add 'params' to a
static workspace" error — caused by a nested function (`runOnce` defined
inside `demo_gui`) forcing the containing function's workspace to become
static, which then rejects the script-style variable injection that
`init_params.m` (used identically everywhere else in this codebase)
relies on. Fixed by moving the `init_params` call to a plain sibling
function.

Adi then asked for a substantially higher-quality interface: multi-select
threat list (run several in sequence), an operator-console dark theme, a
GCS↔UAV link-status indicator, live IQ-constellation before/after (not
just the spectrogram), gauges, a persistent exportable run-history table,
and session video recording. Rebuilt with **zero nested functions**
anywhere in the file — `demo_gui` stores all shared state (models,
parameters, UI handles, run history, the video writer) in `fig.UserData`;
every callback is a plain top-level sibling function reached via
`ancestor(source,'figure').UserData`. This pattern is now the documented
standard for any future MATLAB GUI work in this codebase (see D24 in
DECISIONS.md).

This rebuilt version hit two further MATLAB API mistakes on first run,
both fixed: `uipanel` has no `FontColor` property (title-text color is
`ForegroundColor` — fixed in two panels), and `'\u25CF'`/`'\u25B6'`-style
Unicode escapes are not interpreted inside MATLAB single-quoted strings
(that's a JavaScript/Python convention) — replaced with `char(9679)` /
`char(9654)` in three places. As of this session's end, Adi has the
corrected file and is running it; further live-use feedback pending.

### Housekeeping decision (not a bug fix)
Adi asked whether the project's `.m` filenames should be renamed for
clarity (e.g. shorter or less "robotic"). Recommended against: the current
verb_noun convention (`build_X`, `train_X`, `eval_X`, `run_X`,
`measure_X`, `diagnose_X`) is exactly the self-documenting pattern
expected of professional engineering code, already explicitly credited as
a strength in the report (section 3.1's MLOps discussion); a rename would
touch `main.m`, every cross-referencing script, the report's ~40+ code-
identifier mentions, and git history, for no real readability gain. The
README's existing per-file comments already solve the "what does this do
at a glance" problem that a rename would otherwise be solving. Not done.

### Open items going into the next session
- **Dynamic/Chasing Jammer scenario** — planned (added to the report's
  Chapter 7 and Gantt table as the priority future-work item) but not yet
  designed or built. This is the natural next system-engineering task: an
  adversary that reacts to the DQN's countermeasures, needed to let the
  learned policy demonstrate a real decision-quality advantage over the
  static rule-based baseline (currently the DQN's only advantage is
  theoretical — see the KPI #3 discussion in this session's report work).
- `demo_gui.m` — built, fixed twice, currently being live-tested by Adi;
  watch for further MATLAB runtime errors or UI feedback on the next run.
- Interim report — content-complete pending: (a) Adi sourcing the 6 real
  images for the labeled placeholders, (b) filling in the still-blank
  administrative fields on the title page (submission date), (c) a final
  read-through pass now that the tone/depth work is done.
- `git`: as of this session's end, `README.md`, `docs/DECISIONS.md`, and
  `PROJECT_LOG.md` were updated locally (this entry) but not yet committed
  — see the git command given alongside this update. `demo_gui.m` and the
  latency-fixed `run_closed_loop_diagnostic.m` are not yet in git either;
  both need `git add` before the next commit.

---

## Session 2026-09-21/22 (Session 11) — Speed envelope 50–120 km/h, full re-run, operator console v3

### Review findings that started the session
A full project review flagged five things: the GUI latency number was contaminated by drawing and pauses inside the timed block (so it did not match the diagnostic's figure); the GUI speed field was set but never used (Doppler was computed once at load); the docs disagreed with each other on Map A/B percentages; the GUI did not cover the proposal (no DQN-vs-rule comparison, no survivability map, no BER/RSSI timeline, no UNKNOWN-threat handling, no KPI dashboard); and a few diagram/logging bugs. The latency and speed-usage problems and the missing proposal coverage are fixed by D26 (with D25 supplying the speed-diverse data); the Map A/B mismatch by this documentation update, which carries the re-run values.

### D25 — Speed envelope 50–120 km/h, speed-diverse dataset
Adi asked for a continuous, non-integer speed envelope of 50–120 km/h (fd ≈ 2.22 Hz per km/h at 2.4 GHz: 111 Hz at 50, 160 Hz at the 72 km/h nominal, 267 Hz at 120). Files changed: `init_params.m` (`speed_kmh_min/max`; nominal stays 20 m/s so existing scripts are unaffected), `run_dataset_sweep.m` (each block at its own random speed, Latin-square over 6 bins, `none` split into 5 sub-blocks per SNR, per-frame `speed_kmh`, `rng(2026)`), `extract_spectrograms.m` (a speed change now starts a new run, preventing temporal-feature leakage; `spec.speed_kmh`), `prepare_data.m` (`splits.*.speed`, analysis-only), `eval_detector.m` (accuracy vs speed, 7 bins), NEW `eval_speed_robustness.m` (closed-loop sweep of 8 speeds × 3 SNR × 9 threats with real mitigation re-simulation), `main.m` (`RUN.eval_speed_robustness` and a retrain preset). Cost: Doppler is baked into the Simulink model at build time, so the sweep needs 270 builds instead of one per (threat, level).

### Full pipeline re-run (all flags on)
Adi ran `main.m` with every flag true (19:54 → 23:58, 4 h 04 min, log `logs/run_20260921_195428.txt`). No errors, phases executed in the intended order (dataset 21:36 → spectrograms 21:39 → splits 21:41 → detector 21:48 → DQN 22:16 → closed loop 22:17–22:20 → speed sweep 22:33 → EXP 23:51 → SURV 23:52 → KPI/dashboard 23:58). Before the run, all scripts were checked for workspace clobbering (none uses `clear`; downstream scripts re-initialize the shared variable names) and for producer-before-consumer file order.

| Metric | Before | After |
|---|---|---|
| Offline accuracy / macro-F1 | 96.73 / 96.73% | 96.41 / 96.39% |
| Accuracy @ 0 dB / 2 dB | 93.4 / 97.1% | 91.4 / 95.6% |
| Accuracy @ 8 dB / 10 dB | 97.8 / 97.6% | 98.5 / 98.7% |
| Closed-loop detection | 100% (54/54) | 98.1% (53/54) |
| Mean recovery | 74.6% | 76.3% |
| FAR | 0% | 0% |
| Decision latency (mean) | 6.09 ms | 10.21 ms |
| DQN-vs-rule agreement | ~44% | 53.7% |
| Map A / Map B | 83.8 / 87.5% | 85.5 / 88.3% |

Per-class offline recall (precision): none 97.0 (93.3), jamming 98.7 (90.1), noise_burst 100 (98.7), reactive_jamming 87.1 (98.5), path_loss 94.7 (97.3), spoofing 98.7 (100), antenna_fault 92.8 (98.3), benign_interference 100 (95.6), sweeping_jammer 98.7 (97.1). Previously documented: reactive_jamming 91.0, spoofing 100, noise_burst 100, sweeping_jammer 99.7, all others ≥ 93. Offline accuracy by speed bin: 92.7 / 96.9 / 96.2 / 95.6 / 98.2 / 97.1 / 98.0% from 50–60 to 110–120 km/h.

Verdict: essentially the same performance as the single-speed system, now demonstrated across the whole 50–120 km/h envelope (which was previously untested). Detection is 0.3 points lower offline and 1.9 points lower in closed loop (one antenna_fault miss); recovery is 1.7 points higher; latency is worse and unresolved (open item 11). Map/EXP differences are simulation noise since those phases are speed-independent. The DQN was retrained inside the run (validation gate passed); its training does not depend on speed.

### D26 — demo_gui.m v3 (proposal-complete operator console)
Rebuilt as a four-tab app (Live Operations, KPI & Results, Survivability Map, Session Log). Design points: latency timed strictly around the CNN path + DQN forward pass; recovery = mean BER over all valid frames before and after; a real second simulation for the rule-based choice when it differs from the DQN's; UNKNOWN-threat threshold slider (all-zero one-hot state, rule defaults to `no_action`); verdict from the survivability-map thresholds (≤ 2× clean BER recoverable, ≤ 5× marginal); speed applied to `p.v/p.fd_max` before each `build_threat_model`; `params.mat` restored by `onCleanup`; threat-specific link diagrams; still no nested functions (D24). Verification limits: Octave syntax parse of all changed files, plus execution of the dataset sweep and speed-robustness scripts against stubbed Simulink/toolbox functions and unit tests of the GUI's pure helper functions; the GUI itself has not been executed by the author in MATLAB.

### GUI slow-start report (2026-09-22)
Adi reported the GUI as stuck/slow right after the full run. Two causes identified: (1) launching in the same MATLAB session that just ran `main.m` (multi-GB leftover workspace, possibly GPU memory), fixed by launching from a fresh session; (2) `demo_gui` loaded the whole >1 GB `splits.mat` only to read two normalization vectors — replaced with a cache file `data/gui_norm_stats.mat` (regenerated when `splits.mat` is newer) and added startup timing prints. Per-run cost also includes up to three Simulink model builds (baseline, DQN countermeasure, rule countermeasure); unticking the rule comparison saves one.

### Interim-report sync checklist (numbers to update)
Offline accuracy 96.7% → 96.4% and macro-F1 → 96.4%; accuracy at 0 dB 93.4% → 91.4%; reactive_jamming recall 91% → 87.1%; closed-loop detection 100% (54/54) → 98.1% (53/54); mean recovery 74.6% → 76.3%; decision latency ~5.7 ms → 10.2 ms (or the re-measured value); DQN-vs-rule agreement ~44% → 53.7%; reactive_jamming end-to-end recovery 86.1% → 85.7%; Map A / Map B 84.6 / 87.9% (report) → 85.5 / 88.3%; dataset size 27,246 → 27,270 frames; EXP run size/time; add the 50–120 km/h envelope (amends D4, Doppler 111–267 Hz) and the speed-robustness results to the methodology and results chapters; update the GUI description to v3. FAR figures are unchanged.

### Open items going into the next session
- ~~Re-measure decision latency~~ — done 2026-09-23 (open item 11 resolved, ~10 ms).
- Decide on reactive_jamming and antenna_fault (open item 12); consider demonstrating the UNKNOWN-threat threshold on the antenna_fault @ 0 dB case in the GUI.
- Sync the interim report (checklist above); replace the hard-coded CHECKPOINT footer in `main.m` (open item 14).
- Live-test `demo_gui.m` v3 in MATLAB and send back any runtime error text or layout feedback.
- `git`: `README.md`, `docs/DECISIONS.md`, `PROJECT_LOG.md` and the changed scripts (`init_params.m`, `run_dataset_sweep.m`, `extract_spectrograms.m`, `prepare_data.m`, `eval_detector.m`, `eval_speed_robustness.m`, `main.m`, `demo_gui.m`) are updated locally and not yet committed.
- Dynamic/Chasing Jammer scenario remains the priority future-work item (unchanged).

---

## Session 2026-09-22/23 (Session 12) — GUI speed investigation, proposal review, improvement plan, D27

### GUI slowness with video recording
A 15-run and a 54-run GUI session (logs `demo_session_20260922_002756.log`, `_204029.log`) were slow: ~123 s per run on average, of which the measured decision is ~10–25 ms and each Simulink run ~3 s. The per-stage gaps (27 / 44 / 46 s mean) are UI rendering, not computation. `getframe` on a uifigure is expensive per call, so video capture was moved out of the 10 Hz pause loop to one capture per real state transition (21 → 4 captures per run, `VideoWriter` at 1 fps); this roughly halved the time per run but did not remove the gap. Still open: check `opengl('info')` for software rendering, test a session without video, and the planned handle-update rewrite (improvement #10). For demos, record with an external screen recorder (Win+G / OBS). CSV export was never missing — it is on the SESSION LOG tab.

### External review document
A third-party review text was assessed claim by claim. Correct: the LSTM files exist in the repo root and the GUI/dashboard/map scripts exist. Not correct for this code: adding EVM/phase features with `InputSize = 9` (spoofing was already fixed at its root, D12; the CNN input is a spectrogram plus 7 scalar features), "LSTM overfitting" as the reason it was dropped (D13 records measured results), and `main.m` running the LSTM (its flags are off). Moving the LSTM files to an `experiments/` folder is optional and cosmetic.

### Proposal review and agreed plan
The approved proposal is the binding specification: everything it states is implemented as stated; open questions are raised only where the code and the proposal genuinely differ. A line-by-line review against the proposal, verified against the code, found: KPI #2 measured against BER-before instead of the no-attack link (fixed here, D27); KPI #3 "recovery time in decision cycles/frames" replaced by decision speed; unknown-threat detection (deliverable 4, risk 13) without a quantitative evaluation; KPIs not reported "above a defined SNR threshold"; no decision hysteresis/dwell (risk 8); benign_interference leaving the link at ~27–31× the clean BER at 10 dB with `no_action`. The identical 25 dB effect of three actions was already documented (D19, README design note) — a known modelling simplification, not a new finding. The jammer-bandwidth threat-model change was initially ranked first but is not required by the proposal (it cites narrow vs barrage jamming as an example) and was downgraded. Agreed order: (1) KPI #2 vs clean → (2) countermeasure model → (3) DQN reward, benign policy and FAR definition, retrain → (4) episodic closed loop with dwell and recovery time (KPI #3) → (5) unknown-threat evaluation and combined threats → (6) detector quality (reactive_jamming, unseen-SNR test) → (7) KPI reporting (SNR threshold, PLR/goodput, latency protocol) → (8) Monte Carlo and seeds → (9) GUI performance and content → (10) docs and report.

### D27 — KPI #2 against the no-attack link
`recompute_recovery_vs_clean.m` re-scored the saved 2026-09-21 results without simulation. Clean references agree (closed-loop `none` runs vs EXP, within 2–15%). Closed loop: 95.6% per-run / 95.3% per-threat (76.3% / 75.9% previous metric); 37/41 restored, 4 marginal (jamming 2, reactive_jamming 1, antenna_fault 1), 0 not restored, 1 missed detection (antenna_fault @ 0 dB, 1.4× clean). Per threat: jamming 97.1, reactive_jamming 97.8, sweeping_jammer 95.4, noise_burst 96.9, path_loss 99.1, spoofing 99.0, antenna_fault 81.9%. Speed sweep: 94.7–96.9% at every speed, 95.6% overall (72.4% previous). The metric is now computed natively by the diagnostic, the speed sweep, the KPI report, the dashboard and the GUI. Not yet executed inside the full pipeline — the next `run_closed_loop_diagnostic` run will produce these numbers directly.

### D27 native verification (2026-09-23)
`run_closed_loop_diagnostic` with the integrated metric (new random draw, same models): KPI #2 96.2% per-run / 95.8% per-threat; 37/41 restored, 4 marginal, 0 not restored, 1 missed (antenna_fault @ 0 dB, 1.5× clean); consistent with the post-hoc 95.6% / 95.3%. Per threat: jamming 97.6, reactive_jamming 97.7, sweeping_jammer 96.9, noise_burst 96.6, path_loss 99.7, spoofing 99.4, antenna_fault 83.1%. All four marginal outcomes are at 10 dB (jamming 4.31×, antenna_fault 2.94×, reactive_jamming 2.75×, noise_burst 2.27×): the fixed-size countermeasure leaves a residual that dominates when the clean BER is lowest (2.45e-3) — an input to improvement (2). Detection 53/54, agreement 53.7%, latency 10.63 / 9.99 ms (mean / median) — this closes open item 11.

### Bug fixed: KPI report overwritten by auto-run source scripts
`measure_all_kpis.m` is a script and re-runs a stale source script (`run_closed_loop_diagnostic`, `measure_kpi3_recovery_time`, `diagnose_far_measurement`) in the same workspace. Each of those starts with `report = {}`, so the KPI sections assembled before the call were wiped: on 2026-09-23 `kpi_summary.txt` contained only the FAR report and KPI #4, because the FAR result was older than 12 h. Fixed by calling them through a local `run_isolated()` function, which gives each its own workspace. The 2026-09-21 full run was not affected (`main.m` ran every source script before `measure_all_kpis`, so none was re-run inside it).

### D28 — physics-based countermeasure model (improvement 2, code complete)
`apply_countermeasure.m` replaces the duplicated `action_mitigation_db` table in `train_dqn.m`, `run_closed_loop_diagnostic.m`, `run_closed_loop_with_detector.m`, `eval_speed_robustness.m` and `demo_gui.m` (the GUI now also shows each action's goodput/spectrum cost and effect). `rule_based_policy.m` aligned to the same physics (sweeping → freq_diversity, spoofing → channel_switch). New `eval_countermeasure_matrix.m`: threat × action × Eb/N0 {0, 4, 10} through the real link, 45 model builds. Constants `cm_acr_db` = 30, `cm_rate_factor` = 4, `cm_n_rx` = 2 in `init_params.m`. Real-link matrix (2026-09-23): physics verified; non-recoverable regimes found — noise_burst at 10 dB (29× clean with the best action), path_loss marginal at 4 dB (2.6×) and not restorable at 10 dB (7.0×), sweeping_jammer marginal at 10 dB (4.4×); in-channel threats and antenna_fault restored at every Eb/N0. Rule-based choice within 10% of the best BER in 18/21 real-threat cells. `rate_reduce` is the lowest-BER action in 9/21 cells if its goodput cost is ignored.

### D29 — DQN reward, training and FAR definition (improvement 3, code complete)
`train_dqn.m` rewritten: reward table over threat × action × Eb/N0 (270 real-link simulations), reward = link score vs clean − goodput/spectrum cost, false-alarm penalty only on healthy non-hostile links, 4,000 table-based episodes with real per-frame states (10% with the class hidden), per-cell validation gate with regret report, Adam state carried across updates. `build_dqn_state.m` uses log10(BER). `diagnose_far_measurement.m` counts a false alarm only when the link is not degraded. Reward design checked offline against the measured D28 matrix (best action per cell as intended). Pending: MATLAB run of `train_dqn` and the downstream evaluation.

### D29 results (2026-09-23)
`train_dqn`: 7 min, gate passed on 54/54 cells (mean regret 1.5, max 11). Reward-optimal actions: channel_switch for jamming/reactive/spoofing, spatial_diversity for antenna_fault, freq_diversity for sweeping at ≥ 6 dB, rate_reduce for path_loss at every Eb/N0 and for noise_burst at 0–4 dB, channel_switch for benign at ≥ 4 dB, no_action for none. C3 on the new agent: KPI #2 83.0% (30/42 restored, 8 marginal, 4 not restored, 0 missed); noise_burst 33.1%, path_loss 63.4%, sweeping 86.6%, others 98.9–99.9%. FAR 0/120 healthy-link trials, 60/60 justified actions on degraded benign links, any-action rate 33.3%. Agreement 66.7%. Two disagreement areas: noise_burst (DQN spatial_diversity vs rule rate_reduce at 0–4 dB, reward regret 4–11) and benign (rule never acted — fixed by D30).

### D30 — action-based survivability map and degradation-aware rule (code complete)
`map_survivability_boundary.m` rewritten on the real action set (Map A without goodput loss, Map B any action, best action per cell), executed end-to-end against stubbed Simulink. `rule_based_policy.m` reacts to link degradation for none/benign/unknown via `clean_ber_ref.m`; wired into the C3 diagnostic and the GUI. `main.m`: EXP off by default, SURV standalone. GUI and dashboard map labels updated. Pending: MATLAB run.

### D30 results (2026-09-23)
Map A 78.8% recoverable (9.6 M / 11.7 X), Map B 80.8% (10.0 / 9.2); in-channel threats 93–100% recoverable, sweeping 77%, noise_burst 43/50%, path_loss 20/30%; 6 gap cells (rate reduction only). C3 with the new rule: KPI #2 83.5% (31/42 restored, 8 marginal, 3 not restored). Speed sweep: KPI #2 flat at 78.0–84.5% across 50–120 km/h, detection 97.2% (210/216; misses: reactive_jamming ×2 at 50 km/h, antenna_fault and none ×1 each at 57.3/72 and 50/72 km/h). Two evaluation defects found and fixed: the speed sweep still used the pre-D29 false-alarm definition (its 2/6 per speed were the justified benign actions at 4 and 10 dB), and the C3 diagnostic gave the rule the ground truth and did not simulate the rule's outcome. Both fixed (see D30).

### Re-run with the evaluation fixes (2026-09-24)
Predictions were written down before the run. Held: DQN KPI #2 82.8% (30/42, 0 missed); rule 84.4% (31/42) with mean goodput 0.79 vs DQN 0.91; per run rule better 7 / DQN 2 / within 10% 33; rule clearly better on noise_burst (55.2 vs 32.2%) and on path_loss at 10 dB; agreement 63.0%; speed sweep 0/48 false alarms, 16 justified, KPI #2 flat at 82.5–84.7%, detection 98.6%. Not predicted: antenna_fault DQN 99.1% vs rule 84.2% — the 0 dB run was misdetected as sweeping_jammer (46%); the rule applied freq_diversity (no effect on an antenna fault), the DQN chose spatial_diversity (near-tie with rate_reduce, and its policy for a sweeping jammer at 0 dB) and restored the link — one fortunate case, not an established advantage. Latency 12.1 / 11.4 ms (mean / median). DQN weak cell: path_loss at 10 dB, spatial_diversity (27.8× clean) instead of rate_reduce. README results section rewritten on these numbers.

### D31 — episodic closed loop (improvement 4, code complete)
New `run_closed_loop_episodes.m` and `detect_frame.m`; KPI #3 report extended with recovery time in cycles; `main.m` flag `run_closed_loop_episodes`; `clean_ber_ref.m` made robust to a DQN file without the clean table. Stub-tested end to end. Pending: MATLAB run (~25 min).

### D31 first results (2026-09-24)
Hysteresis: DQN switches 18.5 → 1.5 per episode, rule 7.4 → 1.5; false switches on healthy links 14/20 → 1/20; pre-onset switches DQN 58 → 0, rule 99 → 3. With hysteresis: T_act 3 cycles, T_recover median 8 cycles (~90 ms real time) for both policies; recovered DQN 89/115, rule 92/115; goodput DQN 0.92, rule 0.85. Metric artefact found (T_recover = 1 for never-degraded or pre-mitigated episodes) and fixed in `report_closed_loop_episodes.m`, which re-scores from the saved traces. Onset detection: exact class is late (noise_burst ~10 cycles = temporal window; jamming 0–4 dB never exact) because training excluded transition windows — actions are still correct and on time.

### D31 corrected results (2026-09-24)
Re-scored: with hysteresis T_act 3 / T_recover 8 cycles for both; recovered DQN 61/87 (70%), rule 68/91 (75%) of degraded episodes; goodput 0.92 vs 0.85; without hysteresis 47/52 of 115 episodes pre-mitigated by false switches and only 42% / 50% recovered. Non-recovered cells match the survivability map. KPI #3 is now answered as the proposal words it.

### D32 — unknown-threat detection and combined threats (improvement 5, code complete)
New: `eval_ood_detection.m` (leave-one-threat-out, 8 retrainings), `eval_combined_threats.m` (4 combinations × 3 Eb/N0, detection + 4 decision modes scored by the real link), `cnn_scores.m`, `ood_scores.m`, `ood_thresholds.m`, `frame_features.m`. Changed: `build_threat_model.m` (combined threats, single-threat code unchanged), `apply_countermeasure.m` (combinations), `detect_frame.m` (uses `frame_features.m`), `demo_gui.m` (UNKNOWN slider starts at the calibrated threshold), `measure_all_kpis.m` (D32 section), `main.m` (flags). Stub-tested end to end. Pending: MATLAB runs.

### D32 results and D33 (2026-09-24)
Leave-one-threat-out: mean AUROC 0.515 (MSP) / 0.521 (energy); distinct threats separate (benign, antenna_fault, spoofing with energy), sibling threats are absorbed with high confidence (jamming, reactive_jamming, noise_burst AUROC < 0.2). Combined threats: always named as their dominant component (MSP ≥ 0.92), never flagged; never frozen (0 no_action on attacks); best single action restores 2 of 12 cells (DQN reached both, rule one). Confidence-only gating made the DQN act on the clean link at 0 dB (28/114) — fixed in D33 (gating also requires a degraded link). D33 consolidation: 7 files merged/removed, 8 moved to `legacy/`, root 50 → 35.

### D33 verification (2026-09-24)
Merged detection path reproduces the previous combined-threat numbers; with D33 gating the DQN acts on the clean link in 5/114 frames (28/114 with confidence-only gating, 2/114 without gating). Root 35 files, `legacy/` 8.

### D34 — detector quality by measurement (improvement 6, code complete)
New `eval_unseen_snr.m` (Eb/N0 1,3,5,7,9 dB vs the training grid, same generator and run). `eval_detector.m`: macro-F1 per Eb/N0, KPI #1 threshold, action-equivalent accuracy; `measure_all_kpis.m` reports them. reactive_jamming and transition windows documented rather than retrained (see D34). Pending: MATLAB run.

### D34 results (2026-09-25)
KPI #1 threshold 0 dB (macro-F1 91.3% at 0 dB, ≥ 90% at every Eb/N0); macro-F1 above it 96.39%; action-equivalent accuracy 97.84%. Unseen Eb/N0 (1,3,5,7,9 dB) 97.3% vs 96.6% on the training grid in the same run. Committed.

### D35 — steps 7+8: KPI reporting as worded, Monte Carlo CIs, DQN seeds (code complete)
`run_closed_loop_diagnostic.m` rewritten: 5 seeded repeats per (threat, Eb/N0), PLR before/after/rule, goodput kept, t and Wilson 95% intervals, paired DQN − rule difference, seed-effect warning, new figure `closed_loop_plr_goodput.png`. `train_dqn.m`: 5 seeds, gate per seed, best-regret selection, `results/dqn_seed_stability.txt`. `eval_detector.m`: bootstrap CIs. `measure_all_kpis.m`: CIs, PLR, goodput, FAR per Eb/N0 and pooled above the KPI #1 threshold against a 5% bound, episode intervals, seed summary. Dashboard and GUI KPI tab moved to the D27 metric with means over repeats. New `stats_ci.m`. `main.m`: `CFG` block and the steps 7+8 preset (~3–3.5 h).
Predictions before the run: KPI #2 DQN ≈ 80–85% with an interval of a few points; rule ≈ 83–86%; DQN − rule interval contains 0 or is slightly negative; goodput kept higher for the DQN; PLR restored for jamming/reactive/spoofing/antenna_fault at every Eb/N0, not for noise_burst and path_loss at high Eb/N0; FAR 0 events and a pooled upper limit ≈ 3% (MET); detector bootstrap interval about ±0.7 points; most cells identical across DQN seeds, disagreement concentrated at path_loss/noise_burst near the 2× boundary.

### D35 results (2026-09-25)
Seeds worked (per-repeat values differ; no warning). KPI #2 DQN 80.9% [79.9, 82.0], rule 85.0% [82.4, 87.5], DQN − rule −4.0 [−5.7, −2.4] (rule better, significant). BER restored 152/210 (72.4% [66.0, 78.0]); PLR restored 134/210; goodput kept DQN 77.7% vs rule 74.7% vs no action 20.4%. Detection in the loop 267/270. Latency 10.29 ms mean, 9.80 median, 12.58 p95. FAR 0/120 healthy-link trials, 95% upper limit 3.1% → MET. Detector bootstrap: accuracy [95.67, 97.07]. Episodes: DQN 61/90 = 68% [58, 77], rule 72/94 = 77% [67, 84]. DQN seeds: 4/5 passed the gate (seed 42 left noise_burst at 0 dB untouched, regret 78); mean regret 3.4 [2.0, 4.9]; 32/54 cells unanimous. Predictions held except DQN − rule (predicted to contain 0). Cause: path_loss (DQN 36.4% vs rule 69.0%) — all seeds chose spatial_diversity where the reward prefers rate_reduce → D36.
Clean PLR at 0–2 dB is 0.68 / 0.47 (clean BER 0.125 / 0.081 is near the 0.1 loss threshold), so PLR restoration at 0–2 dB is judged against a lossy reference.

### D36 — full-action DQN targets, stricter gate (code complete)
`train_dqn.m`: each sample trains all five Q-values toward the measured table rewards; gate fails regret > 10 where action is needed; seed failures listed. `stats_ci.m`: optional clipping to the metric's range, applied in the diagnostic, KPI summary, dashboard and GUI. `main.m`: D36 preset. Pending: MATLAB run (~3 h).

### D36 results (2026-09-25, full preset in 52 min)
Expectations held. DQN seeds: all 5 pass the gate, mean regret 0.1 [0.0, 0.2], 52/54 cells unanimous (the two others are 5-point near-ties); selected seed 42 has regret 0 in every cell and matches the reward-optimal action everywhere (rate_reduce for path_loss at all Eb/N0 and for noise_burst at 0–4 dB, spatial_diversity for noise_burst at 6–10 dB).
- KPI #2: DQN 86.0% [85.7, 86.2] vs rule 85.0% [82.4, 87.5]; DQN − rule +1.0 [−1.6, 3.6] (not significant). BER restored 157/210 each; PLR restored DQN 150/210 (71.4%) vs rule 67.6%; goodput kept DQN 78.4% [75.7, 81.1] vs rule 74.7% [73.1, 76.4]; goodput factor 0.84 vs 0.79. path_loss 36.4% → 69.0% (= rule).
- Per threat: the DQN is better on sweeping_jammer (87.4 vs 82.4%) and antenna_fault (99.0 vs 89.0%, the 0 dB misdetection handled by spatial_diversity); the rule is better on noise_burst at 6–10 dB (56.1 vs 48.0% overall), where the reward prefers spatial_diversity over paying 75% goodput for rate_reduce — the designed trade-off, now applied consistently.
- Episodes (hysteresis): recovered DQN 66/91 = 73% [63, 81], rule 68/90 = 76% [66, 83]; T_act 3, T_recover median 8 cycles for both; false switches on healthy links DQN 0/20, rule 3/20; goodput 0.89 vs 0.85.
- Speed sweep: KPI #2 85.6–87.6% across 50–120 km/h; detection 207/216 (antenna_fault at 0 dB misdetected at every speed; one none at 50 km/h); 1 false alarm in 32 healthy-link runs (the misdetected none at 50 km/h); 6 misses (antenna_fault at 0 dB, a 1.4× clean link that the rule also leaves alone).
- Combined threats: DQN and rule now choose the same actions (38/456 restored each). The previous DQN's 76/456 came from choosing spatial_diversity on noise_burst mixes, which the reward table does not prefer for a single noise_burst — not a learned advantage.
- FAR 0/120 healthy-link trials, upper limit 3.1% (MET). Latency 11.1 ms mean, 10.9 median, 13.3 p95.
Runtime: the D36 preset (train_dqn + all DQN consumers) took 52 min; the 5-repeat diagnostic 17 min.

### D37 — step 9: continuous episode view, shared decision cycle, GUI build speed (code complete)
New `episode_cycle.m` (one decision cycle, used by `run_closed_loop_episodes.m` and the GUI). `demo_gui.m`: CONTINUOUS EPISODE tab (streamed episode, DQN and rule on identical frames, T_detect/T_act/T_recover, CSV trace), `scenarioParams` helper, models built without the editor window, rate-limited timer redraw. `build_threat_model.m`: optional `quiet_build` with fallback. Pending: MATLAB check — GUI episode tab, and `run_closed_loop_episodes` must reproduce the D36 numbers (DQN 66/91, rule 68/90 with hysteresis).

### D37 check (2026-09-25)
GUI episode tab runs (jamming 4 dB: T_act 3, T_recover 8 for both policies); PNG export added; NONE on the mitigated link shown in amber. `run_closed_loop_episodes` through `episode_cycle.m`: DQN 68/93, rule 66/87 recovered with hysteresis (D36 run: 66/91, 68/90). Not identical because the frame pools are rebuilt from fresh Simulink runs on every execution; within the D36 confidence intervals.

### D38 — step 10: full run from scratch (2026-09-25)
One consistent run of every stage (stopped once at SURV on a `threat_cfg` workspace clash between scripts, fixed, resumed). Dataset build 10 min instead of ~100 thanks to `quiet_build`.
- KPI #1: accuracy 96.33% [95.60, 97.03], macro-F1 96.31%, ≥ 90% from 0 dB; action-equivalent 98.13%; unseen Eb/N0 96.2% vs 96.3%; reactive_jamming recall 82.8% (errors are jamming, same action).
- KPI #2: DQN 86.4% [86.2, 86.6] = rule 86.4% (difference 0.0 [−0.1, 0.2]); BER restored 157/210; PLR restored 150/210; goodput kept DQN 78.3% vs rule 75.9%. Weak cells: noise_burst (51.1%, 11/30) and path_loss (69.0%, 5/30).
- KPI #3: T_act 3, T_recover median 8 cycles for both; recovered DQN 69/93 = 74% [64, 82], rule 70/92 = 76% [66, 84]; decision latency 14.6 ms mean (CNN 13.4 + DQN 1.2).
- KPI #4: 0/120 healthy-link trials, 95% upper limit 3.1% → MET. KPI #5 MET.
- DQN seeds 5/5 pass, mean regret 0.1; survivability Map A 78.3%, Map B 80.8%; speed sweep detection 97.7%, KPI #2 86.2%, 0 false alarms; LOTO AUROC 0.52; combined threats 38/456 for both policies.
- Dashboard FAR now on healthy-link trials (it showed the all-trials 2.1% upper limit).

### D39 — action set v2 (code complete)
`apply_countermeasure.m`: power_control, fec_interleave, two-action pairs. `extract_closed_loop_frames.m`: FEC emulation with erasure decoding on the measured error pattern. `dqn_agent.m`: 16 actions. `train_dqn.m`: power cost in the reward. `rule_based_policy.m`: noise_burst → fec_interleave. `map_survivability_boundary.m`: action set from the agent, Map A = no goodput loss. GUI and dashboard handle any number of actions. Pending: MATLAB run (preset "D39" in `main.m`).

First run (2026-09-25): reward table shows the new actions help (path_loss best spatial+power 77–88, noise_burst best spatial+FEC 85), but `train_dqn` failed the gate on all 5 seeds — near-tied actions such as X vs X + FEC (regret 15). Fix: input z-score, 128-64 network, 12,000 episodes, batch 64, cosine learning-rate decay (D39). Gate unchanged.

Second run (2026-09-25, stopped during SURV): gate PASS on 5/5 seeds, mean regret 0.1. Closed loop DQN KPI #2 98.1% [97.9, 98.3], 206/210 restored, PLR 179/210, goodput kept 97%; noise_burst 99.9%, path_loss 93.4%; combined threats 161/456 (D38: 38/456); episodes 89/93 recovered, T_act 3, T_rec 8. The rule with noise_burst → fec_interleave fell to 72.0% (noise_burst −44.9%: FEC alone below ~6 dB is past the code threshold), so the rule is reverted to its D38 form and the loop stages are re-run.

Final D39 run (2026-09-26, agent from the second run, rule as D38): KPI #2 DQN 98.1% [97.9, 98.3] vs rule 86.4% (paired +11.7 [11.4, 12.1]); 206/210 restored, PLR 179/210, goodput kept 97.4% vs 75.9%; episodes 83/89 vs 65/90 recovered, T_act 3 / T_rec 8; latency 4.98 ms; FAR 0/120 (upper 3.1%); speed sweep 97.9%, 0/48 false alarms; Map A 86.7% / Map B 93.3%; combined threats DQN 93/456, rule 38/456 (DQN 161/456 in the second run with identical decisions: cells near the 2× threshold). Dashboard labels updated for the new action set.

### D40 — combined threats with seeded repeats (code complete)
`eval_combined_threats.m`: `CFG.mc_repeats` seeded repeats with common random numbers, restored share with Wilson and per-repeat t-intervals; `measure_all_kpis.m` reports the interval.

Full run 2026-09-26 (all D39 preset stages, new agent): seeds 4/5 pass (seed 44: sweeping_jammer 2 dB, regret 15), selected 45; KPI #2 DQN 98.7% [98.6, 98.8] vs rule 86.4%, paired +12.3 [12.0, 12.7]; 205/210 restored, PLR 181/210, goodput 95.5%; episodes 84/88 vs 66/90, T_act 3 / T_rec 8; latency 8.10 ms; FAR 0/120; speed 98.5%, 0/48 false alarms; Map A 86.7% / B 93.3%; combined threats DQN 26.5% [24.0, 29.1] (per repeat 26.5 [18.1, 34.9]) vs rule 8.3%, best single action 50%. Reference run for the reports.

### Next
Run the D39 preset, compare with D38 (noise_burst, path_loss, combined threats), commit.

### D41 — multi-antenna UAV receiver (code complete)
`build_threat_model.m` rewritten: GCS → UAV uplink, 2 UAV antennas (3 supported), per-antenna Rician channel with steering vectors, interferers through their own spatial channels, data-aided coherent MRC baseline and MMSE (spatial_diversity), seeds on every random source. `apply_countermeasure.m`: spatial_diversity sets `rx_combiner = 'mmse'`. `init_params.m`: antenna section. New `validate_phy.m` (flag `RUN.validate_phy` in `main.m`). `validate_phy` (2026-09-26): theory gaps 5/5 within 0.3 dB (−0.17 to +0.04 dB); MMSE under 10 dB jamming 6.8–30 dB BER improvement over MRC. Seed check failed: bit source `SeedSource = Auto`; fixed in all seeding helpers, `diag_seeds.m` now identical on every signal. JIT notice `Simulink:cgxe:LeakedJITEngine` silenced. Datasets and models predate D41.

### D42 — detector v2 (code complete)
Sum-of-sinusoids fading with seed/Doppler as Constant-block inputs (`link_seed.m`); dataset from seeded sub-runs, split by sub-run; shared `link_features.m` (SINR estimate, envelope correlation) and `spec_image.m` ([−40, 40] dB) in every consumer; `train_hybrid_net.m` (cosine LR, L2, SpecAugment); Mahalanobis + isolation-forest unknown-threat scoring (`fit_ood_model.m`, `ood_scores.m`, `eval_ood_detection.m`). Pending: MATLAB run (validate_phy, A5, A6, B1–B3, OOD).

### D42–D43 results (2026-09-26)
`validate_phy` 5/5 within 0.3 dB (fd 1 kHz, 20 realizations), seeds PASS. Dataset 27,000 frames / 1,350 seeded sub-runs, 0 shared between train and test. Detector v2 with IoT: accuracy 96.24% [94.78, 97.46], macro-F1 96.26%, ≥ 90% from 0 dB, reactive_jamming 100%. Unknown threats: Mahalanobis mean AUROC 0.901 (was 0.52 with MSP). Next: phase 3 (DQN).

### D44 results (2026-09-26)
Pools 46.6 min, training 3 seeds + bandit, evaluation on the test pools. DQN − rule + escalation: +0.093 single, +0.022 follower, +0.207 combined, −0.017 clean. Gate FAIL: false switches on 52.1% of clean validation episodes. Review found a zero reward reference at 10 dB (oracle capped at 5/6), the episode clock in the state (switching before onset), a fixed interferer direction (always-on MMSE + power as strong as the DQN, follower irrelevant) and sub-run changes inside episodes. Fixed in D45.

### D45 — decision layer v2 (code complete)
Random interferer directions per seed (`interferer_aoa.m`, 'AoA' Constant block via `link_seed.m`), pools with 6/4 geometries per cell and per-geometry episodes, reward floor 1e-4, action rate_reduce + power_control, shared link monitor and shield (`policy_monitor.m`, `policy_mask.m`), learning-rate decay, gradient clipping, best checkpoint per seed, table baseline (`policy_table.m`), always-on MMSE baseline, AoA breakdown. Pending: MATLAB run of A0, A4v, A5–A6, B1–B3, C1p, C2, C2e.

### D45 results (2026-09-26)
`validate_phy` 5/5 within 0.3 dB, seeds PASS. Dataset with random interferer directions: 27,000 frames / 1,350 sub-runs; detector accuracy 96.28% [94.91, 97.44], macro-F1 96.28%, ≥ 91% from 0 dB. Pools 87.8 min (17 configurations, 6/4 geometries per cell). DQN: 3 seeds within 0.001 on validation (0.856–0.857), gate PASS, false-alarm episodes 2.1% (rule 31.6%). Test pools, pooled: DQN 0.761 vs rule + escalation 0.659 (+0.102 [0.094, 0.110]), table +0.021, best fixed +0.033; clean link 0 false switches. The γ = 0 ablation is higher than γ = 0.9 on validation (0.869) and test (+0.020 pooled): with the link monitor in the state the decision is close to myopic. On the unseen combined threats the DQN switches 9.6 times per episode and trails the best fixed configuration (−0.075). Always-on adaptive combining restores 0% with the interferer within 20° of the GCS and 89% beyond 45°.

### D46 — decision layer v3 and phase 4 (code complete)
Discount-factor grid with validation selection, four training combinations (pools extended, not rebuilt), unknown and 768-episode clean sets with Clopper–Pearson FAR, breakdowns per Eb/N0, geometry and speed, `measure_latency.m`, KPI aggregation and dashboard rewritten on the new result files, GUI and `episode_cycle.m` on `policy_decide.m`, survivability map on shared seeds with two geometries, one-shot scripts moved to `legacy/`. Pending: MATLAB run (B4, OOD, C1p, C2, C2e, SURV, LAT, KPI, DASH).

### D46 results (2026-09-26)
One `main.m` pass, 3 h: B4, C1p (13 scenarios reused, 4 training combinations simulated in 26 min), C2 (3 γ × 3 seeds), C2e, OOD, SURV (105 min), LAT, KPI, DASH. No warning or error.
- **Detector:** unseen Eb/N0 1–9 dB 97.7% vs 97.5% on the training grid (largest gap 1.4 points).
- **Unknown threats (LOTO):** Mahalanobis mean AUROC 0.887 (0.807–0.973 per threat); MSP 0.687, energy 0.596, isolation forest 0.601, fused 0.855. At the 95% threshold 42% of unknown frames still pass as known.
- **Training:** validation return γ = 0 0.839, γ = 0.5 0.839, γ = 0.9 0.830; seeds within 0.003. Selected γ = 0, seed 43; gate PASS. False-alarm episodes on validation 5.4% (γ = 0, 0.5), 12–13% for two γ = 0.9 seeds.
- **Test pools, threat sets pooled:** DQN return 0.744 vs rule + escalation 0.614 (+0.130 [0.121, 0.139]), table 0.707 (+0.037), best fixed 0.707 (+0.038), oracle 0.848. Restored cycles 66.2%, recovered episodes 71.3%, median T_rec 2 cycles.
- **Per set (return, DQN / rule+esc / table / fixed / oracle):** single 0.838 / 0.729 / 0.819 / 0.773 / 0.923; follower 0.858 / 0.825 / 0.777 / 0.794 / 0.964; combined 0.509 / 0.266 / 0.482 / 0.535 / 0.638; unknown 0.817 / 0.649 / 0.751 / 0.763 / 0.922; clean 0.980 / 0.959 / 0.960 / 0.872 / 0.978. Training combinations moved the DQN on unseen combinations from 0.460 to 0.509 and from 9.6 to 7.4 switches per episode; it still trails the best fixed configuration there (−0.025).
- **Restoration (single):** DQN 85.6% of cycles after onset, 89.3% on recoverable episodes (oracle 100%); per threat 62% (noise_burst) to 94% (antenna_fault); unknown set 85.5% with the class withheld (rule 51.7%).
- **Geometry:** always-on MMSE restores 0% / 35% / 89% with the interferer 0–20° / 20–45° / 45–90° from the GCS direction; DQN 72.6% / 87.2% / 89.4%.
- **Speed:** DQN 81.2–88.5% across 50–120 km/h (spread 7.3 points).
- **False alarms (clean, 768 episodes):** DQN 37 episodes (4.8%), one-sided 95% bound 6.29% → KPI 6 NOT MET against 5%; per cycle 0.16%. Rule and table 205 (26.7%). The count is the same for every γ: it is set by the 2-cycle alarm confirmation, not by the policy.
- **Latency (RTX 4070 SUPER):** median 10.9 ms, p95 48.9 ms per cycle; CNN 3.9 ms and Mahalanobis 3.4 ms are two separate forward passes of the same network and carry the p95 tail (38 / 37 ms).
- **Survivability (420 states):** Map A 86.2% recoverable, Map B 93.6%. Every loss is at the aligned geometry (10°) or in path loss: noise_burst @ 10° 30% → 47% with rate/FEC, sweeping_jammer @ 10° 50% → 100% with FEC, path_loss 27% → 63% with rate + power; all 45° maps 100%.
- **KPIs:** 7 of 8 MET; KPI 6 (FAR) NOT MET.

### D47 — documentation layout (2026-09-26)
`PROJECT_LOG.md` and `ROADMAP.md` moved to `docs/` next to `DECISIONS.md`; `README.md` stays in the root. Splitting the code into folders is left for the end of the project.

### D48 — false alarms and latency (code complete)
Alarm only on a hostile class or degradation; M-of-N confirmation chosen on validation (4 candidates × 3 seeds, ≤ 2% false-alarm episodes on 512 clean validation episodes); the same confirmation for rule and table; one forward pass for probabilities and Mahalanobis score (`detect_scores.m`), latency timed on GPU and CPU. Proposal check added packet-loss restoration (≤ clean + 0.05) to every report and a reward-weight sensitivity study (costs × 0.5 and × 2, DQN retrained) to C2. Pending: MATLAB run (C2, C2e, LAT, KPI, DASH).


### D48 results (2026-09-26)
One pass, 37 min: C2 (4 confirmations × 3 seeds, γ = 0) with the sensitivity study, C2e, LAT, KPI, DASH. No error.
- **Confirmation:** DQN false-alarm episodes on validation 5.1% for every confirmation and seed (one seed at 2-of-3: 14.5%); returns 0.817 / 0.819 / 0.798 / 0.800 (2-of-2 / 2-of-3 / 3-of-3 / 3-of-4). Rule + escalation 42.2% → 27.5% with 3-of-3. No run met the 2% limit; the fallback took 2-of-2, seed 42; gate FAIL on the false-alarm condition only.
- **Reward sensitivity (costs ×0.5 / ×1 / ×2):** DQN ahead of rule + escalation (+0.114 / +0.107 / +0.110) and table (+0.038 / +0.052 / +0.057) at every scale; DQN false alarms 20.1% / 5.1% / 2.1%, restored 84.9% / 83.3% / 74.1%.
- **Test pools, pooled:** DQN 0.719 vs rule + escalation 0.614 (+0.105 [0.096, 0.114]), table +0.029, best fixed +0.012; restored 66.4%, recovered 72.7%. Single 0.825, follower 0.864, combined 0.439 (best fixed 0.535, −0.096), unknown 0.746, clean 0.980. Packet loss back to ≤ clean + 0.05 on 94.6% of the cycles of recoverable episodes.
- **False alarms (clean, 768):** DQN 37 (4.82%), bound 6.29% → KPI 6 NOT MET, unchanged; rule 205 (26.7%).
- **Latency:** one forward pass; the CPU is faster than the GPU for a single frame (detector median 2.8 vs 5.5 ms). Cycle median 5.62 ms, p95 24.3 ms (D46: 10.9 / 48.9).
- **KPIs:** 7 of 8 MET; KPI 6 NOT MET.
- **Conclusion:** the confirmation length is not what drives the DQN's false alarms (see D49).

### Proposal sources (2026-09-26)
Every source of the proposal was checked against its full text; sources that could not be read in full, or that did not shape a decision, were removed. Final list (12): Oli & Mahalal 2025, Papathanasiou et al. 2026, Tariq et al. 2026, Liu et al. 2018, Simon & Alouini, Lee et al. 2018, Liu, Ting & Zhou 2008, Mnih et al. 2015, van Hasselt et al. 2016, Richards, Alshiekh et al. 2018, Clopper & Pearson 1934.

### D49 — false alarms, second attempt (code complete)
Alarm definition ('class' / 'degraded') and training false-switch penalty (20 / 40 / 80) as hyperparameters, γ reopened (0 / 0.5 / 0.9), 3 seeds; evaluation with the standard reward; false-alarm diagnostics per Eb/N0 and trigger; KPI 7 latency class. Pending: MATLAB run (C2, C2e, LAT, KPI, DASH).

### D49 results (2026-09-27)
One pass, 2 h: C2 (2 alarms × 3 penalties × 3 γ × 3 seeds, 54 runs) with the sensitivity study, C2e, LAT, KPI, DASH. No error.
- **Alarm 'degraded':** validation return 0.737 vs 0.812 ('class'), restored 68% vs 83%; path loss never counts as degradation (the reference is the clean BER at the receiver's own, attenuated, Eb/N0). Rejected.
- **False-switch penalty (class, γ = 0):** validation false alarms 5.1% / 5.1% / 4.1% at 20 / 40 / 80, return 0.817 / 0.815 / 0.812. No run of 'class' met 2%; fallback: 'class', penalty 80, γ = 0, seed 43 (2.1%); gate FAIL.
- **γ:** validation 0.817 / 0.816 / 0.806 (γ = 0 / 0.5 / 0.9, penalty 20); on the test pools γ = 0.9 pooled 0.728 vs 0.719 (γ = 0), follower 0.874 vs 0.849, clean 0 false alarms, but 5–17% false alarms on validation.
- **Test pools, pooled:** DQN 0.719 vs rule + escalation +0.105 [0.096, 0.114], table +0.028, best fixed +0.012; combined −0.082 vs best fixed.
- **False alarms:** DQN 37/768 (bound 6.29%), all at 2 dB, all path_loss, none degraded. Rule + escalation 205: 136 'none' with a degraded link (0, 2 and 10 dB), 69 path_loss.
- **Latency:** median 4.37 ms, p95 20.09 ms (CPU detector 2.1 ms).
- **KPIs:** 7 of 8 MET; KPI 6 NOT MET.
- **Sensitivity (seed 43, penalty 80):** DQN ahead of rule + escalation and table at ×0.5 / ×1 / ×2.

### D50 — attenuation as a change of the link (code complete)
Eb/N0 drop from the episode's reference in `policy_monitor.m`, new state input, alarm 'class_drop' (path_loss only after a ≥ 4 dB drop); grid 2 alarms × 2 penalties × 3 γ × 3 seeds; drop at the first change in the diagnostics. Pending: MATLAB run (C2, C2e, LAT, KPI, DASH).

### D50 results (2026-09-27)
One pass: C2 (2 alarms × 2 penalties × 3 γ × 3 seeds, 36 runs) with the sensitivity study, C2e, LAT, KPI, DASH. No error.
- **Validation:** every good run has a floor of 2.1–2.3% false-alarm episodes (11–12 of 512 clean validation episodes); 'class_drop' reaches it at every γ with penalty 80, 'class' only for some seeds. No run met 2%; the fallback took the best return among the fewest false alarms: 'class', penalty 80, γ = 0.5, seed 44 (0.817); gate FAIL.
- **Test pools, pooled:** DQN 0.722 vs rule + escalation +0.108 [0.099, 0.117], table +0.031, best fixed +0.015; γ = 0 / 0.5 / 0.9 within 0.007. Restored 87.5% of cycles on recoverable single-threat episodes; packet loss back on 95.1%.
- **False alarms:** DQN 37/768 (bound 6.29%), all at 2 dB, path_loss, not degraded, median Eb/N0 drop 4.2 dB: a real fade of the clean signal in one geometry. γ = 0.9 8/768. Rule + escalation 205 (136 'none' with a degraded link at 0, 2 and 10 dB; 69 path_loss, median drop 4.1 dB).
- **Latency:** median 4.43 ms, p95 19.41 ms.
- **KPIs:** 7 of 8 MET; KPI 6 NOT MET.

### D51 — decision layer frozen; KPI 6 on independent geometries (code complete)
`build_clean_test_pools.m`: clean link on 100 new geometries per Eb/N0 under all configurations; `evaluate_policies.m`: one episode per geometry (600 independent episodes) for KPI 6, the 4-geometry set kept for comparison. Pending: MATLAB run (C1c, C2e, KPI, DASH).

### D51 results (2026-09-27)
One pass, 64 min: C1c (17 configurations × 6 Eb/N0 × 100 geometries, 63 min), C2e, KPI, DASH. No error. Decision layer and test pools unchanged, so every other number repeats D50.
- **False alarms, 600 independent clean geometries (KPI 6):** DQN 23/600 episodes (3.83%, two-sided 95% interval 2.4–5.7%), one-sided bound 5.39% → NOT MET against 5% (the bound needs ≤ 20 of 600); per cycle 0.19%. Per Eb/N0 (0–10 dB): 8 / 3 / 8 / 3 / 1 / 0, 19 of 23 at ≤ 4 dB. Class at the first change: path_loss 18 (not degraded, median Eb/N0 drop 4.2 dB), antenna_fault 4 (median drop 7.7 dB), spoofing 1 (degraded). Rule + escalation 218/600 (36.3%, bound 39.7%). On these episodes return DQN 0.964 / rule + escalation 0.932 / oracle 0.983, goodput 1.002 / 0.944 / 1.003.
- **Against the 4-geometry set:** there 37/768, all from one geometry at 2 dB; here 3/100 at 2 dB and false alarms at every Eb/N0 up to 8 dB. γ = 0.9 had 8/768 there and 27/600 here, γ = 0 30/600: the small set also ranked the discount factors wrongly (the selection used validation only).
- **Review of the unknown set:** 0.817 in D46, 0.746 in D48, 0.740 now (restored 85.5% → 69.5%). The D48 change that acts on this set is the alarm definition: an 'unknown' class raises the alarm only with degradation (D33). The false-alarm count on the test pools did not change with it (37/768 before and after). The layer stays frozen; the trade-off is reported.
- **Follow-up in the code (C2e, KPI, DASH rerun, ~2 min):** legends of the evaluation figures drawn without TeX (underscores in configuration names), 'always-on MMSE' in every table, detector accuracy per speed band with its band edges.
- **Next:** the KPI 6 target goes to the supervisor with these numbers. A larger clean sample is not run now: choosing the sample size after a result near the limit is optional stopping; if the supervisor asks for one, it is a new sample of size fixed in advance, reported next to this one.

### D52 — speed diagnostic, drop threshold from data, independent clean validation (code complete)
`diagnostics/diag_speed.m` (2026-09-27): DQN false alarms per speed band 5.1 / 3.7 / 3.1 / 3.3% (Fisher p = 0.53), clean frames read as a threat 4.8 / 4.8 / 3.1 / 4.6%, detector recall per class and speed without a consistent trend; the fade-duration hypothesis rejected, the none ↔ path_loss confusion at low Eb/N0 confirmed as the source. `choose_drop_threshold.m` (threshold on the train pools), `build_clean_test_pools.m` with a validation set (seed block 4), `train_dqn.m` scoring every run on the independent clean geometries with the pre-registered selection rule, `drop_db` carried to evaluation, latency and the GUI. Grid: 'class' / 'class_drop' × penalty 80 × γ 0.5 × 3 seeds. Pending: MATLAB run (C1c val, C1d, C2, C2e, LAT, KPI, DASH).

### D52 results (2026-09-27)
One pass, 86 min: C1c validation set (66 min), C1d, C2 (2 alarms × 3 seeds), C2e, LAT, KPI, DASH. No error.
- **Threshold (train pools, 720 path_loss and 720 clean frames):** drop of path_loss frames 6.8 / 10.0 / 14.4 dB (5th / 50th / 95th percentile), of clean frames read as path_loss −0.4 / 2.0 / 6.4 dB. Separable; threshold 6.5 dB keeps 96.4% of path_loss frames and passes 0% of the misreads.
- **Selection (600 independent validation geometries):** 'class_drop' 8–10/600 per seed vs 'class' 30–45/600; best-return runs 10 vs 30 (Fisher p = 0.002), return 0.808 vs 0.817. 'class_drop' seed 42 selected by the pre-registered rule. Rule + escalation 26.5% vs 39.2% on the same set.
- **Test, 600 independent geometries (KPI 6):** DQN 9/600 (1.5%), one-sided bound 2.60% → MET; per cycle 0.07%; 5 / 2 / 1 / 1 / 0 / 0 per Eb/N0. Class at the first change: antenna_fault 6, path_loss 2 (median drop 6.7 dB), spoofing 1. Rule + escalation 152/600. Return on these episodes 0.963 (oracle 0.983), goodput 1.003. The 4-geometry clean set: 0/768.
- **Cost:** path_loss restored 83.7% → 78.7% (single + follower + combined); KPI 4 87.5% → 86.6%; pooled DQN − rule + escalation +0.108 → +0.110, − table +0.036, − best fixed +0.018; combined 0.457 → 0.477; unknown 0.740 → 0.742; follower 0.849 → 0.851.
- **Latency:** median 5.30 ms, p95 24.3 ms (same code path as D50; run-to-run variation of the machine).
- **KPIs:** 8 of 8 MET. The training gate still reported FAIL against the old 2% criterion on the 6-geometry validation set (2.1%, the one known geometry); the gate now uses the one-sided bound on the independent set, as KPI 6 is worded (code change after the run, affects the report line only).

### GUI live check and D53 (2026-09-27)
Live tab, 12 runs at 90 km/h (8 threats, 3 clean, one duplicate): all detections correct (93.8–100%), latency 2.9–7.6 ms after the first-run warm-up (73 ms, GPU initialization), clean runs no action, DQN and rule agreed 7/12, verdicts and both re-simulations worked; CSV and log export OK. Two findings: (1) PATH LOSS @ 8 dB UNMITIGATED — the live run starts with the threat, so the monitor has no clean reference and the D52 drop gate refuses the path_loss alarm; fixed by a clean lead-in (D53). (2) NOISE BURST @ 10 dB verdict NON-RECOVERABLE at 22.4× clean: the clean reference is floored at 1e-4, DQN still removed 98.1% of the errors and beat the rule (33.9%); consistent with the survivability map, not a defect.
### D53 — clean lead-in in the live tab (code complete)
`demo_gui.m`: the live tab simulates the clean link first and warms both monitors on those frames before the threat frames. Pending: MATLAB re-check of the live tab (no pipeline rerun).

### GUI live re-check after D53, and D54 (2026-09-27)
Live tab, 14 runs at 95 km/h, severity L4: the clean lead-in works — path_loss got rate_reduce + power_control from both policies at 2 and 8 dB (MARGINAL at 3.8x clean, and NON-RECOVERABLE at 16 dB attenuation and 8 dB Eb/N0 with 98.7% of errors removed: the L4 severity is beyond the nominal training level, consistent with the survivability map). All 14 detections correct at the class level; reactive_jamming at L4 flagged UNKNOWN (off-nominal JSR shifts the embedding) and was still restored 96.3% through the degradation alarm — the OOD path working as designed. Four "false alarm during the clean lead-in" lines: with the rule's known 25% clean-episode rate these are almost certainly the rule's switches, and the log line did not say — fixed in D54 (the line now names the policy). Run 13 (clean, 0 dB): the rule false-alarmed live while the DQN held — KPI 6 demonstrated. D54 code complete: hover '?' help on every live-tab setting, tooltips on the episode tab, video capture down to 3 frames per run with OS recording recommended for fluid video. Pending: episode-tab live check.

### D55 — operator language in the live tab (code complete)
Every number the live tab shows now says what it means for the flight: a plain "Bottom line" under the verdict and in the log (link healthy / commands get through with less margin / UAV may miss commands), the channel line translates BER to "% of command bits corrupted", gauges renamed (how sure is the detector, reaction time), chart titles explain what to look for (a drop after the amber line = the response works), outcome block in words (errors before / after DQN / after rule, cost of the response). The episode tab got the same hover help: a '?' with a detailed effect explanation next to every setting (threat, Eb/N0, severity, speed, policy, clean cycles, cycles after onset, escalation, confirmation, dwell/hold, playback, seed). Second pass on request: every tooltip rewritten in plain operator terms (what gets harder/faster/stronger at each setting, no channel-model jargon), and hover help added across the console - both gauges, verdict, outcome block, queue, terminal, session-history table, all six KPI cards (what each KPI means and its target), the KPI refresh button, the survivability map selectors and the episode status box; elements with help carry a [?] cue where a separate mark does not fit. GUI only; no result or KPI changes. Pending: visual check with the next live run.


### D56 — 3D episode view (code complete)
`viz3d.m` (new) and `demo_gui.m` (episode record + 3D VIEW button). Pending: MATLAB check — run an episode in the Continuous episode tab, open the 3D view, play, switch policy and camera, record an MP4.

### D57 — 3D view in Unreal (started)
Smoke test passed (Unreal window with EmptyGrass on the user's machine). Design agreed with the user (see D57). `viz3d/sim3d_probe.m` added: class introspection, calibration scene with axis, size and rotation tests, candidate UAV and jammer models, pattern and beam materials, camera captures per pose, scene sweep. Pending: run in MATLAB.

### D58 — 3D view built (code complete, tested on the reference PC)
Calibration (`sim3d_probe.m`): axes x forward / y right / z up in metres, shape sizes are extents, pitch > 0 nose up, yaw > 0 toward +y, roll > 0 right wing down; UAV classes z up, aircraft classes z down; EmptyGrass ground only for x > 0; the FixedWing UAV mesh is under 1 m (scaled x8). Look iterations with camera captures read back by Claude: pattern as antenna plot, thin rings, glow sheath, procedural countryside, black UAV. Live console tested headless (buttons driven from a script, `exportapp` screenshots): inject, operator vs AI, scenario, cameras, replay of a console episode (80 cycles); no errors. Profiling: `insertText` font lookups were 60% of a render; one font for dynamic text and change-only actor updates fixed it. Defense videos rendered with `v3d_videos` (results/viz3d_videos, not in git).

### D59 — v4 first runs (2026-09-28)
Stages A0–B4 (dataset 43,200 frames, 13 link features), OOD, C1p (4 combinations for training, 4 others for test only), C1c, C2 reduced (one run: 'class_drop', penalty 80, γ 0.5, seed 42), C2e, KPI.
- **Detection (test split):** accuracy 96.58%, macro-F1 96.59% [95.77, 97.28], lowest class 93.59%, ≥ 93.5% from 0 dB; unseen Eb/N0 97.80% vs 97.17% seen.
- **Unknown threats (leave-one-threat-out):** mean AUROC ensemble 0.803, last layer 0.863, MSP 0.648, energy 0.675, isolation forest 0.594 → D60.
- **Decision layer (reduced run, test pools):** single threats recovered 87.5–100% per threat and severity; combined set 59.2% of recoverable episodes; sweeping_jammer+path_loss (test only) 5.2% against an oracle 97.9%; KPI 4 9 of 12 threats. False alarms on 600 independent clean geometries: DQN 27/600 (4.5%, bound 6.15%), rule + escalation 244/600. No run met the false-alarm bound → D61.
- **Disk:** the drive fell to under 80 GB free: killed parallel workers had left 238 GB of Simulation Data Inspector files (.dmr) in the temp folder. Deleted by the user; `disk_guard.m` added (D61).

### D60 — unknown-threat diagnostic (2026-09-28)
`diagnostics/diag_ood_scores.m` on the D59 folds: last layer 0.867, ensemble 0.802; input pre-processing chosen eps = 0 in every fold and costs 85.6 ms per frame; nested selection picks the last layer in every fold (0.867); averaging the score over 5 frames 0.883. Reactive jamming is the weak threat (0.64–0.70).

### D61 — experiments and code (2026-09-28/29)
- **Per-antenna probe** (`bg_branch_probe`): on the clean link the antenna-1 SNR estimate errs by −3.7 to +3.6 dB (1st–99th percentile); the gain ratio between branches does not separate the misreads (median −0.1 dB clean, +0.3 dB antenna fault) and was dropped. The per-antenna dip (median minus minimum of the per-block gain) separates them: unit test, clean < 6 dB, antenna fault median > 10 dB.
- **New-threat learning** (Lee et al., Algorithm 2, 8 folds): known accuracy softmax 96.9%, generative 96.0%; with K = 20 / 100 / all validation frames of the new threat its recall is 58.8 / 87.9 / 88.6%, known accuracy after 95.1 / 94.8 / 94.8%. Reactive jamming is the hardest (62.2% at K = 100).
- **Code:** unknown-threat candidates and nested selection inside `eval_ood_detection.m`; Algorithm 2 in the same stage; all 8 combinations in training; C2g; monitor grid 2/2, 3/3; 20 ms decision period; DQN evaluated as matrix products; `disk_guard.m`; code moved into `code/` with `startup.m`; survivability levels to 28 dB.
- **Checks (2026-09-29):** `params.mat` and the threat model rebuilt from the code (sinks Rx_Z, Rx_H, Rx_R present); unit tests 9/9 pass.
- **Next:** smoke run of the whole chain, then the full run from A0 (about 16 h).

### v4 final run, phases A and B (2026-09-29)
One pass from A0 to OOD, 2 h 26 min, no error; then B4s (10 min).
- **A4v:** 5/5 theory gaps within 0.3 dB (AWGN +0.05, Rician −0.21, ...), seeds reproducible.
- **A5–A6:** 43,200 frames, 2,160 seeded sub-runs, 14 link features (with `branch_dip`).
- **B2–B3 (test split, 10,800 frames):** accuracy 97.02%, macro-F1 97.02% [96.24, 97.60]; every class F1 ≥ 93.85% from 0 dB (jamming lowest; none 94.7%, antenna_fault 99.0%); macro-F1 per Eb/N0 95.1–97.9%; action-equivalent accuracy 97.56%.
- **B3a:** hybrid 97.11% macro-F1, spectrogram only 74.54%, link features only 85.31% (same splits, schedule, seed).
- **B4:** unseen Eb/N0 (1, 3, 5, 7, 9 dB) 97.9% vs 97.7% on the training grid; largest gap to the interpolated curve 1.3 points.
- **OOD (leave-one-threat-out, 55 min):** mean AUROC MSP 0.661, energy 0.656, isolation forest 0.685, last layer 0.871, Lee ensemble 0.782, link-feature Mahalanobis 0.696, last layer or link features 0.898, last layer or isolation forest 0.881. Production score: last layer or link features (FPR95 0.40; averaged over 5 frames 0.920). **Nested estimate (KPI 2): 0.859** (per threat 0.888 0.912 0.641 0.884 0.843 0.882 0.900 0.923): with reactive jamming held out, the choice made on the other seven is the last layer alone, which scores 0.641 on it; with the link features it would be 0.950 (env_corr separates it).
- **New-threat learning (Algorithm 2, 100 frames):** recall of the new threat 84.9% on average (reactive jamming 47.0%, read as jamming: same countermeasure), known-class accuracy 96.6% → 95.5%.
- **B4s (unseen severities):** between the training levels 99.0% correct, 99.6% same countermeasure; above the range (22/28 dB JSR, path loss 26 dB) 95.5% correct, 100% same countermeasure, 68.7% flagged unknown (they are outside the training distribution; the flag adds to the class, it does not replace it). Decision by the rule fixed before the run: the training levels stay.

### v4 decision layer: first test reading, D62, D63 (2026-09-29)
- **First test reading (08:50, kept in `archive/v4_first_test_20260929/`):** KPI 5 +15.7 points over rule + escalation [+13.2, +17.9]; KPI 6 14/600 clean episodes, bound 3.62%; KPI 4 met for 14 of 16 threats (path loss 80.2%, low severity 66.7%; reactive jamming + path loss 89.6%). Diagnosis on validation only → D62.
- **D62 grid (09:01–12:24), stopped at 29 of 36 runs.** Weakest threat on validation per drop threshold: 5 dB 70.2–75.0% (path loss in 11 of 12 runs), 4 dB 68.8–84.7%, 3 dB 71.9–84.4%. False alarms 10–79/600 (the 3/3 runs scored with the 2/2 monitor, see D63). No agent of this grid was saved or evaluated on the test set.
- **Why it was stopped:** the GUI console showed the DQN switching every cycle on a restored link. A first `diag_switching.m` run used `data/trained_dqn.mat`, which at that moment held the agent of the 09:00 smoke run (1,280 episodes; `run_stage('smoke', ...)` overwrites the normal outputs), so the first numbers (6.0 changes per episode) and the GUI observation came from an untrained agent. Repeated on the agent of the first test reading: 4.17 changes per episode, 58.9% within 3 cycles of the previous change, A → B → A in 20.8% of the episodes (rule 0%). Hold adopted as D63.
- **Found on the way:** `clean_world` (train_dqn.m) cached the monitor of its first call, so every run's clean-link false alarms used the first block's monitor since D59 (rule + escalation 38.7% for every monitor; correct: 2/2 at 4 dB 39.5%, 2/2 at 3 dB 40.0%, 3/3 at 4 dB 26.7%). The one-step oracle hopped into an immediately-following jammer (comb set 0.7%). Both fixed (D63).
- **GUI:** action-score panel shows the best 8 configurations the shield allows (with the rule's choice) instead of 36 unreadable bars; the detection time is the median of 5 single-frame calls after a warm-up (the first call had read 102 ms).
- **Code checks:** unit tests 9/9 (the shield test now covers the hold); `checkcode` clean on every edited file; the fixed cache checked on rule + escalation (per-monitor values, repeatable).
- **D63 chain started 12:28:** C2 (24 runs), C2e, C2g, GAL, LAT, KPI, DASH.

### v4 decision layer: second test reading, validation diagnostics, D64 (2026-09-29)
- **Second test reading (D63 agent: class_drop 2/2, drop 4 dB, penalty 80, γ 0.5, seed 43; kept in `archive/v4_second_test_20260929/`):** threat sets pooled DQN 92.7%, DQN + escalation 94.0%, rule + escalation 79.2%; single 95.3%, follower 82.6% (rule + escalation 94.9%), combined 96.5%, unknown 85.4%, comb 55.2% (DQN + escalation 85.4%, oracle 94.4%). KPI 4 met for 12 of 16 threats (antenna fault 87.2%, reactive jamming 87.8%, jamming 88.0%, path loss 89.7%); KPI 5 +13.6 points [+11.7, +15.3]; KPI 6 15/600, bound 3.82%. Switches 1.57 per episode (single set). The latency of this reading (2.96 / 4.23 ms) was measured while a diagnostic MATLAB session ran and is not valid.
- **Leave-one-combination-out (C2g):** combinations never trained on 82.2% (first reading 75.6%), trained on 95.8%; sweeping jammer + path loss 27.1%.
- **Diagnostics, validation split only:** `diag_failure_modes.m` (threat × jammer mode, failure mechanism), `diag_never_acted.m` (monitor miss or agent choice), then scratch checks of the reward, the escalation variants and the monitor's degradation flag against the truth. Findings and numbers in D64. Two hypotheses refuted on the way: releases to no_action are not a failure mechanism (0.3–0.4% of the episodes); a pre-incident degradation reference, though closer to the KPI, costs the follower threats more than it gives path loss.
- **D64 in code** (commit 866c9fd, adoption rule written before the run): escalation out of no_action on a confirmed alarm held for 3 cycles; DQN + escalation deployed; follower delay 0–5 cycles in training and validation; new test flights (block 6) and clean test set (block 7). The repository code reproduces the scratch result exactly on validation (pooled 94.1%, antenna fault 100%, clean false alarms 18/600). Unit tests 9/9.
- **Chain started 15:38:** C1p (test split only), C1c (clean test set), C2 (24 runs). A first start at 15:32 was stopped after 6 minutes, before anything was saved: the pool builder compared the threat list instead of the cell list and would have rebuilt every split. Next: the adoption check on validation, then one reading of the new test set.
- **Weather:** ITU-R P.838-3 read; at 2.5 GHz rain of 100 mm/h attenuates 0.023 dB/km (horizontal polarization), about 0.2 dB over 10 km: negligible against the 6–14 dB path-loss threat, so weather is not modelled as a threat at 2.4 GHz.

### v4 final: third test reading, D65 (2026-09-29, evening)
- **Adoption check (validation):** the fixed rule failed; the user chose the new 3/3 agent before the test reading (D64). The path-loss reference for escalation was tested and not adopted.
- **Crashes explained:** the Claude RTL patch's scheduled task (`ClaudeRtlPatchWatcher`) killed every Claude process when it saw a new Claude version (19:38 and 19:40); the user removed the task and its folder.
- **Third test reading (new flights, block 6; clean block 7; D64 agent with escalation):** pooled 94.2% [90.9, 96.7]; KPI 4 14/16 (benign interference 86.5%, noise burst + antenna fault 85.0%); KPI 5 +16.5 points [+14.6, +18.3]; KPI 6 19/600, bound 4.61%; latency median 2.70 ms, p95 3.16 ms (idle machine); KPI 7 not met by the speed spread (85-102 km/h 87.6%, 10.6 points); follower 93.4%, combined 96.4%, comb 92.0%, unknown 81.0%. Combinations never trained on 79.5% (sweeping jammer + path loss 10.4%). Detector baselines: hybrid 97.0%, MLP 85.7%, random forest 85.2%, CNN 74.8%, kernel SVM 69.6% macro-F1. Kept in `archive/v4_third_test_20260929/`.
- **After the reading, validation only:** benign failures hold a channel switch that does not restore, with escalation silent, or never act; the hybrid (rule for benign) was dropped before running (rule + escalation falls to 92.4% under 3/3); an avoidance check and a 20-frame degradation window gave no gain; clean false alarms of the D64 agent came from class alarms (13 of 15).
- **D65** (degradation alone confirmed on 2 of 2, reduced retrain): not adopted, no run met the false-alarm bound (21-33 of 600). The final system is the D64 agent; code, `data/trained_dqn.mat` and `results/dqn_training.*` restored to it.
- **Sources:** proposal v2 with 16 read references (Alouini & Goldsmith 1999 and Ramírez-Espinosa et al. 2019 replace the Simon & Alouini book; Barajas replaces the Richards book; Thulin replaces Clopper & Pearson; Xu, Shebert added); every citation of an unread source removed from the code, README and LITERATURE.

### v4: D66, D67 and the fourth test reading (2026-09-29, night)
- **D66** (running costs x0.5 in the training reward): validation recovery 97.0-97.3% and the weakest threat 89.5-91.1%, but clean-link false alarms 27-89 of 600; not adopted. Run kept in `archive/v4_D66_not_adopted/`.
- **False-alarm diagnostic** (`diag_false_alarms.m`, validation): under 3/3 the monitor confirms an alarm on 164 of 600 clean geometries (147 from degradation alone), but the agents' false switches come mostly from path-loss misreads (D64 12 of 15, D66 19 of 28). Drop-in without retraining: 4/4 confirmation brings the D66 agent to 11 of 600 (pooled 96.0%) at one extra cycle per response; 5/5 cuts benign detection to 75%; a persistence gate on the path-loss class alone lowers path-loss recovery to 84.7%.
- **D67** (running costs x0.5, false-switch penalty 120 / 160): penalty 160, seed 42 meets the bound (15 of 600) with validation 96.6%, weakest path loss 88.7%, goodput 1.189. Every aggregate adoption condition passed; the weakest threat in the KPI 4 grouping fell short by two path-loss episodes (90.6% -> 90.3%). The user adopted D67 as a documented exception; the fourth test reading (test block 8, clean block 9) is the final result whatever it shows.
- **Report figures (outside the repository):** five block diagrams and eight threat figures, English on the images; the threat scenes are AI-rendered objects with every signal drawn from the threat model.
- **Fourth test reading (final; D67 agent, test block 8, clean block 9):** pooled 96.1% [94.8, 97.5]; KPI 4 14/16 (benign interference 87.2%, noise burst + antenna fault 88.7%); KPI 5 +16.5 points [+14.8, +18.4]; KPI 6 13/600, bound 3.42%; KPI 7 met (speed bands 96.4 / 97.6 / 95.0 / 97.3%, latency 2.91 / 3.97 ms); follower 95.0%, combined 97.1%, comb 97.6%, unknown 83.5%; combinations never trained on 84.4% (sweeping jammer + path loss 25.0%). 7 of 8 KPIs met. Kept in `archive/v4_fourth_test_20260930/`.

### v5: realism extension (D68), code frozen and full run started (2026-09-30)
- **Why:** the v4 envelope (eight threats, three decision severities, K = 10 dB, Eb/N0 up to 10 dB, one speed band) covered a narrow slice of the conditions reported in air-ground measurement campaigns (Khawaja et al.). v5 widens it before the final reading; the v4 final state is kept in `archive/v4_final_D67_20260930/`.
- **Changes (pre-registered in D68):** tone (CW) jamming and airframe shadowing as threats, with the `branch_gap` receiver measurement; Rician K per flight uniform 0-20 dB for the signal and the interferers; Eb/N0 0-15 dB; eight dataset levels and five decision-layer levels per threat, ten combined threats; a one-cycle signalling delay (and a two-cycle sensitivity set); test flights at 20-50 and 120-160 km/h; a single-core latency pass; link budget with three hardware profiles and the radio horizon.
- **Bug found:** `evaluate_policies` took the per-flight speed from the block 2 seeds, so the per-speed breakdown of readings 2-4 of v4 (KPI 7 speed bands) is not reliable. v5 stores the speed of every flight in the pools.
- **Smoke run:** all 22 stages ran end to end (gate failure expected at smoke scale); single-core latency 7.68 ms median.
- **Full run (started 12:56):** PHY validation 7/7 within 0.3 dB (K = 0 dB +0.24, K = 20 dB +0.04), MMSE under a 10 dB jammer lowers the BER 4.7x to 1,260x over MRC, seeds PASS, tone calibration 16.24 dB vs 16.23 dB for the noise jammer. Code committed before the test reading (009f7ea).

### v5: antenna geometry (D69), scope and profiles (D70), full runs (2026-09-30, afternoon)
- **Antennas (D69):** the user's question on monitor and reference antennas showed that the half-wavelength pair could not produce shadowing on one antenna only (Khawaja et al.: spatially separated antennas, 1.2 m in their example). The antennas now span a 1.2 m aperture; the fault or the airframe hits an antenna drawn per run; the IQ measurements and the spectrogram come from the reference antenna (highest SINR) and the new `sinr_gap` compares the others with it (16 link features).
- **Scope (D70):** the lecturer's papers all treat small drones; Tlili et al. classify UAVs up to the close-range class (50 km). Profile 1 = three antennas, 29-161 km/h; profile 2 = two antennas, same envelope. Ranges capped at the most severe value of the sources (K -5..20 dB, 30 dB in-band, 35 dB attenuation). The KPI 1 threshold and the operating envelope are fixed on validation before the test reading. Training scale raised (50 000 episodes; 8 / 6 training / validation geometries).
- **Proposal:** no numbers on speed or on the number of antennas (KPI 7 and the antenna wording changed; backups kept).
- **Aborted run:** the v5 run started at 12:56 was stopped during spectrogram extraction to apply D69; its test flights were never read.
- **Checks:** unit tests 10/10 with three antennas; PHY validation 7/7 within 0.3 dB with three antennas; the parallel-turn lock tested with two sessions.

### v6: evidence over time, a quiet slot, levels to the sources' caps (D71, D72) (2026-10-01)
- **Why:** the v5 detector reading traced the weak classes to one frame deciding alone, two threat pairs with the same physics while we transmit, and an unknown-threat score that read "stronger than trained" as "new" (D72).
- **Changes:** one decision cycle per frame on the channel clock; a quiet slot in every frame (q_iot, q_react); temporal fusion of the last N cycles (stage B2F); the unknown-threat score over a window; detector and decision levels up to the sources' most severe values; antenna fault and WLAN traffic as physical processes; the weak-point analysis (stage WEAK). Profile 2 states antenna fault above 60% duty as a limit (D71).
- **Runs:** profiles 1 and 2 (branches v6-dev, v6-p2) started 2026-10-01 as the ideal-receiver reference for v7.

### v7: real receiver, flight dynamics, source-corrected severities (D73) (2026-10-01/03)
- **Why:** a review of the whole source library found severity caps and shapes beyond what the sources measured, an ideal receiver that hid how a real one fails, and no hover or turns (D73).
- **Changes:** frame with a quiet slot before it, short and long training and pilot blocks; a real receiver (synchronization, frequency offset, decision-directed MVDR passes) checked against the ideal one in PHY validation (V11, V12); speed 0-161 km/h with turns at measured bank angles and yaw rates; per-flight antenna correlation and receive-chain mismatch; source-corrected severities (spoofer, shadowing events, open connector, WLAN gaps); four triple threats; profile 3 with four antennas; the overhead pass (stage OHP); the unknown-threat candidate with input pre-processing.
- **Directional GCS antenna (2026-10-03, user decision):** in every profile. Under the licence-exempt cap (11 dBm e.i.r.p., ETSI density, stricter than Israel's 100 mW) a directional antenna helps as far as the radio is below the cap: the GCS is a low-power radio at -6 dBm on a tracked 12 dBi antenna, 10 dB over an omni on the same radio; pointing loss per flight in the channel; power_control limited to the cap (+5.0 dB; it had exceeded the cap). Check: on a clean link the antenna factor moves the measured SINR by -5.9 / +9.9 dB for -6 / +10 dB; a 10 dB jammer goes from BER 0.46 to 0.10 with the antenna's 10 dB. Tests 16/16.
- **Power loss 2026-10-02 03:07:** the computer shut down during v6 stage C1p (no partial results); both v6 profiles resumed from C1p on 2026-10-03 22:05 (stages before it are saved in data/).
- **Latency (KPI 7):** the v6 and v7 run lists had no LAT stage; the launcher now measures latency on the idle machine after each version's runs and repeats KPI, DASH, WEAK and RPT with it.
- **Runs:** start automatically when v6 ends and the tests pass: profiles 1 and 3 together, profile 2 last.
