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

## Phase KPI: Proposal Measurement (section ה) ✅ COMPLETE

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

### Next
Run the D36 preset, check the expectations in D36, commit D35+D36. Then step 9 (GUI performance, continuous episode view) and step 10 (documentation sync, full `main.m` run with the light figure theme).
