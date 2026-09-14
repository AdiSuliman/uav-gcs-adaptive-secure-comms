# Project Execution Log (Living Document)

**Last Updated:** 2026-09-15 | **Status:** Phase A+B+C+EXP complete | 1 of 5 known issues remain open

---

## Phase A: Link Model & Dataset ✅ COMPLETE

| Step | Status | Date | Notes |
|---|---|---|---|
| A1-A2 | ✅ | 2026-08-20 | AWGN link validation, BER matches theory |
| A3 | ✅ | 2026-08-28 | Rician K=10dB, fd=160Hz: 1.53× degradation |
| A4 | ✅ | 2026-09-02 | 8 threats validated (barrage, reactive, spoofing, noise, path, antenna, sweeping, benign) |
| A5-A6 | ✅ | 2026-09-05 | Dataset: 10,686 frames, spectrograms [128×128×1] extracted |

---

## Phase B: Detection ✅ COMPLETE

| Step | Status | Accuracy | Date | Notes |
|---|---|---|---|---|
| B1 | ✅ | — | 2026-09-08 | Data split 80/10/10, z-scored 7 features |
| B2 (v1) | ✅ | 78.8% | 2026-09-09 | CNN+scalar hybrid, 7 classes |
| B2.5 | ✅ | — | 2026-09-10 | Temporal features: var_rssi_10, dber_dt, burst_ratio |
| B2 (v2) | ✅ | 92.13% | 2026-09-11 | With 7 features, reactive_jamming 7.2%→85.5% |
| B3 (9-class) | ✅ | **90.90%** | 2026-09-13 | +sweeping_jammer, +benign_interference, +none |

**Key Finding:** jamming 67.3%, spoofing 76.2% weak; noise_burst, antenna_fault, sweeping (100%).

---

## Phase C: Recovery & Closed-Loop ✅ COMPLETE (v5, fully verified)

### C1: Rule-Based Policy ✅
```
jamming → channel_switch
reactive_jamming → channel_switch_fast
spoofing → freq_diversity
path_loss → rate_reduce
noise_burst → rate_reduce
antenna_fault → spatial_diversity
sweeping_jammer → channel_switch
benign_interference → no_action
none → no_action
```

### C2: DQN Agent — 5 fix iterations

| Version | Date | Fix | Root cause found | Result |
|---|---|---|---|---|
| v1 | 09-13 | — | Synthetic generic reward (same for every threat) | 12.5% rule agreement, antenna_fault 5.4% |
| v2 | 09-13 | Raised `action_mitigation_db` (15/8/8/12→25/15/25/25 dB) + physical floor on path_loss_db/fault_atten_db | Magnitudes far below what EXP validated as achievable (field_reduction/awgn_margin_boost ceilings) | antenna_fault 5.4%→20.2%, mean recovery 31.8%→42.2%-45.2% |
| v3 | 09-13 | Reward shaping (-40pp false-alarm penalty, benign_interference/none) + state-mismatch fix (real RSSI/SNR/PLR at train time) + 3x oversampling on benign_interference/none | benign_interference/none (not real attacks, D9) were being "recovered" like threats; reward scale (~-1 to -17) drowned out by other threats (~20-90) in shared regression network | no_action correctly ranked highest for both; DQN-Rule agreement 22.2% |
| v4 | 09-14 | `threat_encode` reassigned so antenna_fault sits at the array midpoint (max distance from benign_interference/none); fixed a separate pre-existing bug where noise_burst/spoofing had swapped encode values between train_dqn.m and the closed-loop scripts — all three files now share one identical `threat_encode_map` | Scalar ordinal encoding let antenna_fault's Q-values "bleed" from the adjacent benign_interference penalty code (trained Q-values matched benign_interference's penalty scale, -14 to -16, not antenna_fault's own reward table, 0 to +24%). Confirmed via `diagnostics/diagnose_antenna_fault_reward.m`: reward table itself is stable (std<2% across 8 repeated Simulink runs per action) | DQN-Rule agreement 22.2%→44.4%. antenna_fault Q-values now correctly scaled, but ranking still inverted (rate_reduce, the weakest action, scored highest) |
| v5 | 09-14 | antenna_fault oversampled 3x (same mechanism as benign_interference/none) | Only 50 non-oversampled episodes were insufficient for the shared regression network to learn antenna_fault's fine-grained action ranking (gaps of 8-23pp, much smaller than most other threats' 40-90pp gaps) | **Fixed** — DQN now selects spatial_diversity (Q=22.86-22.90, highest, stable across re-runs), matching rule-based policy. antenna_fault recovery 0.7%→17-20%. DQN-Rule agreement 44.4%→55.6% |

**Design note (for report):** the four non-zero actions (channel_switch/rate_reduce/freq_diversity/spatial_diversity) are mechanistically identical in the current implementation — each just subtracts `action_mitigation_db.(action)` dB from the threat's own severity field, regardless of label. Most residual "DQN vs rule disagreement" (4/9 remaining after v5) is therefore cosmetic — the chosen and rule-suggested actions produce near-identical recovery. This is distinct from the v4/v5 antenna_fault issue, which was a genuine learned-ranking bug (confirmed by the reward table itself, not just a labeling mismatch) — now resolved and stable across independent re-runs (run_20260914_223849, run_20260914_235045, run_20260915_000442 all agree within noise).

### C3: Closed-Loop — ✅ FULLY VERIFIED (2026-09-15)

Both closed-loop scripts now confirmed working end-to-end, post-fix, in the same run (`run_20260915_000442`, zero errors/warnings):

**`run_closed_loop_diagnostic.m`** (ground-truth-conditioned, full Q-value/timing trace) — verified stable across 3 independent runs:

| Threat | DQN action | Rule action | Agree | Recovery |
|---|---|---|---|---|
| jamming | channel_switch | channel_switch | ✅ | 67.7% |
| reactive_jamming | spatial_diversity | channel_switch_fast | ❌ (mechanically equal) | 66.5% |
| sweeping_jammer | channel_switch | channel_switch_fast | ✅ | 25.2% |
| noise_burst | channel_switch | rate_reduce | ❌ (mechanically equal) | 40.0% |
| path_loss | spatial_diversity | rate_reduce | ❌ (mechanically equal) | 64.3% |
| spoofing | channel_switch | freq_diversity | ❌ (mechanically equal) | 52.2% |
| **antenna_fault** | **spatial_diversity** | **spatial_diversity** | **✅** | **17-20%** |
| benign_interference | no_action | no_action | ✅ | -3.4% (correct: no threat, nothing to recover; sign is Simulink run-to-run noise) |
| none | no_action | no_action | ✅ | 0.3% (correct: clean channel, nothing to recover) |

**DQN-Rule agreement: 5/9 (55.6%)** — identical across all 3 runs.
**Mean recovery:** 36.6-38.1% across runs.
**Latency:** Median CNN 4.36-7.31ms + DQN 2.95-3.06ms — consistently well under real-time budget.

**`run_closed_loop_with_detector.m`** (CNN-prediction-conditioned, the "real" closed loop with detector uncertainty in the loop) — **run for the first time post-fix on 2026-09-15**, zero errors:

| Threat | CNN Pred | Conf% | Action | Recovery |
|---|---|---|---|---|
| jamming | jamming ✅ | 93.3% | channel_switch | 68.3% |
| reactive_jamming | spoofing ❌ | 60.2% | spatial_diversity | 65.2% |
| sweeping_jammer | sweeping_jammer ✅ | 100% | channel_switch | 24.9% |
| noise_burst | noise_burst ✅ | 100% | channel_switch | 42.4% |
| path_loss | path_loss ✅ | 100% | spatial_diversity | 64.7% |
| spoofing | jamming ❌ | 55.5% | channel_switch | 51.3% |
| antenna_fault | antenna_fault ✅ | 100% | spatial_diversity | 17.4% |
| benign_interference | benign_interference ✅ | 100% | no_action | -1.3% |

**Detection accuracy in closed-loop: 6/8 (75.0%) | Average BER recovery: 41.6%**

The two misdetections (reactive_jamming→spoofing, spoofing→jamming) are the already-documented Known Issue #6 (spoofing 3-way confusion) resurfacing in a live closed-loop context — an expected confirmation of a known limitation, not a new finding.

**Conclusion: Phase C3 is complete.** Both closed-loop scripts are verified, consistent with each other and with the reward table, and produce stable results across independent runs.

---

## Phase EXP: Deep Exploration ✅ COMPLETE

Ran `explore_countermeasures.m` (150+ combos, 2 new mechanisms: `field_reduction`, `awgn_margin_boost`, + `atten_reduction` for antenna_fault) + `analyze_exploration_results.m`.

| Threat | Best mechanism found | Magnitude | Recovery | vs old C3 |
|---|---|---|---|---|
| jamming | field_reduction | 25dB | 83.6% | +51.9% |
| reactive_jamming | field_reduction | 25dB | 83.1% | +49.2% |
| noise_burst | field_reduction | 25dB | 68.8% | +46.9% |
| path_loss | awgn_margin_boost | 15dB | 89.6% | +12.7% |
| spoofing | field_reduction | 25dB | 80.7% | +41.2% |
| **antenna_fault** | atten_reduction | 25dB | 60.5% | **+55.8%** |
| sweeping_jammer | field_reduction | 25dB | 57.6% | N/A (new) |
| benign_interference | field_reduction | 25dB | 64.2% | N/A — **not applied**, benign_interference should stay no_action by design (D9) |

**This directly triggered the C2 v2 fix** (raising `action_mitigation_db`): the EXP numbers are SNR-averaged (0-10dB), while C3 evaluates only at worst-case SNR=0dB, so actual C3 recovery is lower than these EXP figures — expected, not a discrepancy.

**Caveat for report:** 25dB/15dB were the *ceiling* of the tested magnitude sweep, not a proven optimum — the sweep didn't test beyond that.

---

## Phase D: Documentation & Defense (Pending)

- [ ] Interim Report (due end of summer)
- [ ] Final Report (due end of semester)
- [ ] Defense: 20+10 min, 10 slides
- [ ] Poster: 5% grade
- [ ] Dashboard (proposal deliverable #1, final product) — not yet started
- [ ] Survivability-boundary mapping (proposal deliverable #7, research output) — not yet started
- [ ] FAR (false alarm rate) — named KPI in proposal section ה — not yet directly measured
- [ ] Cross-check all proposal KPIs (section ה) explicitly against current results

---

## Known Issues & Limitations

### Resolved (2026-09-13)
1. ~~**Antenna Fault Recovery (5.4%)**~~ — **Fixed in v2.** Was underpowered mitigation magnitude (12dB), not a physical limit. See v4/v5 below for a second, separate antenna_fault bug found and fixed on 09-14.
2. ~~**benign_interference reward gap**~~ — **Fixed** via reward shaping (v3) + state-mismatch fix + oversampling. DQN now correctly picks no_action.
3. ~~**"Reactive Jamming Misdetection"**~~ — **Was a false alarm.** Full-test-set confusion matrix (1374 samples) via `diagnostics/diagnose_reactive_jamming.m` shows reactive_jamming at 88.9% recall / 86.6% F1 — healthy. The earlier "71.2% confidence → spoofing" was one unrepresentative sample, not a systematic issue.

### Resolved (2026-09-14/15)
4. ~~**antenna_fault Q-value bleed + ranking inversion**~~ — **Fixed** (v4+v5 above). Two separate bugs: (a) scalar ordinal `threat_encode` let antenna_fault's learned Q-values bleed from the adjacent benign_interference penalty code; (b) undertraining (no oversampling) caused an inverted action ranking within antenna_fault specifically. Also fixed, in the same review: a pre-existing `noise_burst`/`spoofing` encode-value swap between `train_dqn.m` and the closed-loop scripts. Verified via `diagnostics/diagnose_antenna_fault_reward.m` (reward table stability, std<2%) and confirmed stable across 3 independent C3 re-runs (run_20260914_223849, run_20260914_235045, run_20260915_000442).
5. ~~**Noise Burst Latency Outlier**~~ — **Fully resolved, confirmed as a test-harness artifact, not a code bug.** Isolated via `diagnostics/diagnose_latency_position_test.m` (position-swap test): moved noise_burst to loop position 1 (ran normally) and sweeping_jammer to position 4 (the spike followed it there). Conclusion: the spike is tied to sequential loop position (approx. every 4th `predict()` call), not to any threat's signal content — consistent with MathWorks-documented GPU inference non-determinism. Not representative of real deployed single-decision latency. `run_closed_loop_diagnostic.m` now reports median latency alongside mean for robustness to this artifact.
6. ~~**`run_closed_loop_with_detector.m` unverified post-fix**~~ — **Resolved.** The script had received the same threat_encode_map fix as the other two files but had never actually been executed since (its RUN flag was always false). Ran for the first time post-fix on 2026-09-15 (`run_20260915_000442`) — zero errors/warnings, antenna_fault behavior consistent with the diagnostic script, detection accuracy 75.0% (6/8), average recovery 41.6%.

### Still open
7. **Spoofing 3-way confusion (53.0% recall, 62.0% F1):** The REAL weak class, found via the same confusion-matrix diagnostic that cleared reactive_jamming. Breaks down as 80/152 correct, 27→jamming, 17→reactive_jamming, 27→benign_interference. Root cause: genuine feature-space overlap (proposal risk #5), NOT training-data imbalance (test-set counts are balanced, ~152/class). Documented in `docs/DECISIONS.md` D12. Decision: document as known limitation rather than retrain — class weights are the wrong tool for an overlap problem (risk of degrading currently-strong classes like jamming/benign_interference), and the proposal's own named alternative (LSTM architecture, section ה) is too large a change for remaining time. Reconfirmed live in the 09-15 `run_closed_loop_with_detector.m` run (reactive_jamming→spoofing, spoofing→jamming misdetections) — consistent with the confusion-matrix finding, not a new issue. Candidate future work.

---

## Git Snapshots

| Commit | Phase | Date | Status |
|---|---|---|---|
| 2f8f5d3 | B3+C3 | 2026-09-13 | Phase B+C2+C3: 9-class CNN, DQN v2 retrain, diagnostics |
| 245e5aa | Cleanup | 2026-09-13 | Repo hygiene: diagnostic scripts moved into diagnostics/ |
| a826733 | C2 v3-v5 fixes + EXP + docs | 2026-09-14 | action_mitigation_db fix, reward shaping, state-mismatch fix, oversampling, threat_encode reassignment (antenna_fault bleed fix), noise_burst/spoofing encode-swap fix, latency position-test, median latency reporting, README/PROJECT_LOG rewrite |
| 6f5f393 | Diagnostics + cleanup | 2026-09-14 | Added diagnose_antenna_fault_reward.m and diagnose_latency_position_test.m to diagnostics/; untracked regenerated .slx build artifacts |
| (pending) | C3 verification + main.m cleanup | 2026-09-15 | run_closed_loop_with_detector.m verified post-fix (first run since threat_encode fix); main.m: removed stray non-English comment line, "8 threats"→"9 threats/classes" consistency fix, RUN.run_closed_loop enabled |

---

**Next Steps:**
1. Compute FAR (false alarm rate) explicitly — named KPI in proposal section ה, not yet directly measured (see KPI explanation discussed with the team 09-15).
2. Start Dashboard implementation (proposal deliverable #1) and survivability-boundary mapping (proposal deliverable #7) — both required deliverables, not yet begun.
3. Cross-check all proposal KPIs (section ה) explicitly against current results.
4. Write Phase D reports.
