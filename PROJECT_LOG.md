# Project Execution Log (Living Document)

**Last Updated:** 2026-09-19 (Session 9, complete) | **Status:** Rx_IQ tap-point bug found and fixed (D18); full pipeline re-run (A5→C3) COMPLETED; FAR re-measured correctly (D20); no_action recovery reporting fixed (D21). All 5 proposal KPIs met with post-fix numbers. See "Session 2026-09-19" at the bottom for the full detail.

## Current headline numbers (post-D18 re-run)
| Metric | Value |
|---|---|
| CNN accuracy (offline test) | 96.99% (macro-F1 96.98%) |
| CNN accuracy (closed loop) | 100% (54/54) |
| Mean BER recovery (real threats) | 74.6% |
| Decision latency (mean / median) | 2.67 / 2.54 ms |
| FAR (non-hostile, 180 trials over SNR) | 0.0% (95% CI upper 3.3%) |
| Survivability Map A / Map B recoverable | 84.6% / 87.9% |

---

## Phase A: Link Model & Dataset ✅ COMPLETE

| Step | Status | Date | Notes |
|---|---|---|---|
| A1-A2 | ✅ | 2026-08-20 | AWGN link validation, BER matches theory |
| A3 | ✅ | 2026-08-28 | Rician K=10dB, fd=160Hz: 1.43-1.53× degradation |
| A4 | ✅ | 2026-09-02 | 8 threats validated (barrage, reactive, spoofing, noise, path, antenna, sweeping, benign) |
| A5-A6 (v1) | ✅ | 2026-09-05 | Dataset: 10,686 frames, spectrograms [128×128×1] extracted |
| A5-A6 (v2) | ✅ | 2026-09-15 | Dataset expanded: `frames_per_config` 50→100 → **27,246 frames**, re-extracted after spoofing fix |

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

---

## Phase EXP: Deep Countermeasure Exploration ✅ COMPLETE

Ran `explore_countermeasures.m`: **2550 scenarios, 85.8 minutes**, 3 mechanisms (`field_reduction`, `awgn_margin_boost`, `atten_reduction` for antenna_fault only) across 8 threats × 5 severity levels × 6 SNR points.

**Crash bug found and fixed (2026-09-18):** `current_best_static.(b.threat)` in the report-generation section accessed a field that didn't exist for all 8 threats vs. only 6 fields in the historical comparison struct — caused the script to crash **after** 75-86 minutes of runtime, at the report-writing stage, after the actual data was already safely saved. Fixed with an `isfield` guard in the report builder (the console-output path already had one).

This EXP data feeds both the C2 `action_mitigation_db` magnitudes (established 09-13/14, unchanged since) and the survivability boundary mapping below.

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

---

## Phase KPI: Proposal Measurement (section ה) ✅ COMPLETE

| KPI | Result | Notes |
|---|---|---|
| KPI 1 — Detection accuracy | 98.05% (offline) / 100% (closed-loop) | See Phase B3 / C3 above |
| KPI 2 — BER recovery | 74.9% mean (real threats, closed-loop) | See Phase C3 above |
| KPI 3 — DQN vs Rule decision speed | Rule ~3 orders of magnitude faster | Redefined from "recovery cycles" — see below |
| KPI 4 — FAR (False Alarm Rate) | 0%, upper 95% CI bound 3% | Rule-of-Three (100 trials, zero false alarms) |
| KPI 5 — End-to-end survivability | See survivability boundary mapping above | Proposal deliverable #7 |

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
- [ ] KPI Dashboard (proposal deliverable #1, final product) — script drafted, not yet finalized
- [ ] Interim Report
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
