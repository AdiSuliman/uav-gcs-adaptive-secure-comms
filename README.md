# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A
**Students:** Adi Suliman, Bar Dvir Hassan
**Supervisor:** Golan Ein-Tzvi
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + scalar/temporal features, **96.41% accuracy** on a speed-diverse dataset covering a continuous **50–120 km/h** UAV envelope, ~10 ms mean decision latency including full signal preprocessing)
- Reinforcement learning policy (DQN trained on true Simulink reward, one-hot state encoding), with reward shaping so the agent correctly withholds action on non-hostile interference (benign_interference → no_action, none → no_action) — verified **0% false-alarm rate** across 180 non-hostile trials
- Adaptive recovery (channel switching, rate reduction, diversity), with magnitudes empirically validated against a dedicated countermeasure-exploration sweep (EXP phase, 2,790 simulations in the latest run)
- Survivability boundary mapping (proposal deliverable #7): separate Threat-Neutralization and Link-Survivability maps, with gap analysis distinguishing genuine attack removal from SNR-margin tradeoffs
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison, FAR measurement, KPI aggregation
- Interactive operator console (`demo_gui.m`, v3): four tabs — live operations (threat × Eb/N0 × UAV speed × severity matrix, DQN vs rule-based side by side, BER/RSSI timeline before/after the countermeasure, UNKNOWN-threat handling), KPI & results, survivability map, session log
- Speed-robustness evaluation (`eval_speed_robustness.m`): closed-loop detection, decision and recovery swept over 8 UAV speeds (50–120 km/h) — 98.1% detection, 0% false alarms, recovery flat at 69–74%
- Interim report (Word, 7 chapters + limitations/assumptions section) drafted; see `## Report` below

---

## Repository Structure

```
├── main.m                        # Master orchestrator (19 RUN-flags across phases A-DASH; LSTM excluded, D13)
├── init_params.m                 # System & threat parameters (K=10dB; UAV envelope 50–120 km/h → Doppler 111–267 Hz, nominal 72 km/h = 160 Hz; D25)
├── build_dqn_state.m             # Single source of truth: 13-dim one-hot DQN state
├── demo_gui.m                    # Interactive operator console, 4 tabs (D24 architecture, D26 v3)
├── build_kpi_dashboard.m         # 7-panel results dashboard (proposal deliverable #1)
├── models/                       # Simulink Digital Twin (gitignored — regenerated on build)
│   ├── UAV_GCS_Base_Link.slx     # A1-A2: clean AWGN channel
│   ├── UAV_GCS_Rician_Link.slx   # A3: fading + Doppler
│   └── UAV_GCS_Threat_Link.slx   # A4-A6: threats + recovery
├── docs/
│   └── DECISIONS.md              # Architecture Decision Record (D1-D27)
├── diagnostics/                  # Ad-hoc investigation scripts, kept for reproducibility
├── README.md                     # This file
├── PROJECT_LOG.md                # Living execution log — status, fix history, open issues
├── ROADMAP.md                    # Project timeline (original plan)
└── [Phase scripts]
    ├── A: build_*.m, extract_*.m, run_*_sweep.m
    ├── B: prepare_data.m, train_detector.m, eval_detector.m
    ├── B-exp: *_lstm.m, *_seq.m (CNN-LSTM comparison — not pursued, kept for the record; excluded from main.m)
    ├── C: train_dqn.m, dqn_agent.m, rule_based_policy.m, run_closed_loop_*.m
    ├── C-speed: eval_speed_robustness.m (closed-loop detection / decision / recovery vs UAV speed, D25)
    ├── EXP: explore_countermeasures.m, analyze_exploration_results.m, map_survivability_boundary.m
    └── KPI: measure_all_kpis.m, measure_kpi3_recovery_time.m, diagnose_far_measurement.m
```

**Note:** `data/`, `results/`, `logs/`, `models/` are `.gitignore`'d (too large / regenerable). Exception: `results/survivability_*` (Map A/B outputs, proposal deliverable #7) are tracked explicitly — they are a primary research output, not a regenerable byproduct.

---

## Quick Start

1. **Setup:** MATLAB R2026a with Communications, DSP System, Deep Learning, RL toolboxes
2. **Run the full pipeline:** `main.m` — toggle RUN flags to control which phases execute (see in-file presets: full clean run / results-only refresh / dashboard-only)
3. **Live demo:** `demo_gui.m` — pick threat × Eb/N0 cells in the test matrix, set UAV speed (50–120 km/h, continuous) and severity, press Run; see `## Interactive Demo` below. Launch it from a **fresh MATLAB session** (or after `clear all; close all force; bdclose all`) — right after a full `main.m` run the leftover multi-GB workspace makes the UI sluggish
4. **Explore:** `logs/run_*.txt` accumulates full console output (via `diary`)

**Phases & runtimes:**
- Phase A (link + dataset): dataset generation ~102 min in the latest run (speed-diverse sweep: 270 Simulink model builds; the Doppler is baked into each build), spectrogram extraction ~3 min
- Phase B (detector train): 5–15 min
- Phase C1 (rule-based): < 1 min
- Phase C2 (DQN train): ~27 min (measured 2026-09-21)
- Phase C3 (closed-loop, both scripts): 4–8 min total
- Phase C3-speed (`eval_speed_robustness.m`): ~13 min (measured; 8 speeds × 3 SNR × 9 threats)
- Phase EXP (deep countermeasure exploration): ~78 min (measured 77.8), run rarely
- Phase KPI (FAR + aggregation): ~5 min
- Full `main.m` with every flag on: ~4 h 04 min (2026-09-21)
- Survivability mapping: < 5 min (uses cached EXP data)
- Dashboard: < 1 min (needs B3+C3-diag+FAR+SURV already run)

---

## Latest Results (2026-09-21 full re-run, speed-diverse training data)

All numbers below come from one clean run of `main.m` with every RUN flag on (start 19:54, end 23:58, ~4 h 04 min; log `logs/run_20260921_195428.txt`), on the 50–120 km/h speed-diverse dataset (D25). The previous single-speed baseline (2026-09-21, post D22/D23) is shown in parentheses where it exists.

### Phase A — Dataset (D25)
- **27,270 frames** (8 threats × 5 severity levels × 6 Eb/N0 × 100 frames, plus a balanced `none` class). Every 100-frame block is simulated at its own **continuous, non-integer UAV speed** in 50–120 km/h (min 50.0, mean 85.2, max 119.9), assigned through a Latin-square over 6 speed bins so speed is correlated with neither SNR nor class. Split 21,816 / 2,727 / 2,727.
- Speed is stored per frame for analysis; it is **not** a network input.

### Phase B3 — CNN Detector (9-class)
- **Overall accuracy: 96.41%** (96.73%), **macro-F1 96.39%** (96.73%); best validation accuracy 97.1% at epoch 29
- Per-SNR: 91.4% @ 0 dB → 95.6% @ 2 → 96.7% @ 4 → 97.6% @ 6 → 98.5% @ 8 → 98.7% @ 10 dB (was 93.4 → 97.1 → 96.5 → 98.0 → 97.8 → 97.6). Lower at the 0–2 dB edge, higher at 8–10 dB, and now monotonic.
- Accuracy vs UAV speed (7 equal bins, n≈315–480 each): 92.7% (50–60 km/h), 96.9, 96.2, 95.6, 98.2, 97.1, 98.0% (110–120 km/h). The lowest-speed bin is the weakest; the rest stay within about 2.6 points of each other.
- Per-class recall (precision): none 97.0 (93.3) · jamming 98.7 (90.1) · noise_burst 100 (98.7) · **reactive_jamming 87.1 (98.5)** · path_loss 94.7 (97.3) · spoofing 98.7 (100) · antenna_fault 92.8 (98.3) · benign_interference 100 (95.6) · sweeping_jammer 98.7 (97.1)
- Main confusions: reactive_jamming → jamming 33/304 (plus 6 → benign), path_loss → none 12, antenna_fault → none 9 and → sweeping_jammer 9, none → path_loss 5

### Phase C2 — DQN
- Retrained in the same run (training is speed-independent: the state carries no Doppler and the reward table is built at the nominal condition). Post-training validation gate A/B passed: benign_interference and none → `no_action`; every real threat → an active countermeasure.

### Phase C3 (Closed-Loop) — 9 threats × 6 Eb/N0
- Detection accuracy in closed loop: **98.1%** (53/54) (100%, 54/54). The single miss: antenna_fault @ 0 dB, classified as sweeping_jammer with only 31.2% CNN confidence; the DQN then chose `no_action`. This is exactly the case the UNKNOWN-threat threshold in the GUI is meant to catch.
- **KPI #2 — recovery against the no-attack link (proposal definition, D27): 95.6%** per-run mean (95.3% mean of per-threat means). After the countermeasure the link is back within 2× the clean BER in **37/41** runs, marginal (2–5×) in 4, never worse; plus one missed detection (antenna_fault @ 0 dB). Clean reference = the `none` run at the same Eb/N0; it matches the EXP clean BER within 2–15% at every point.
- Previous metric, recovery relative to BER-before: 76.3% over the same runs (74.6% before the re-run). It is kept for comparison only: it penalises threats that start from a low BER, which is why sweeping_jammer and noise_burst looked weak (60–72%) although they return to the clean link.
- Decision latency (CNN preprocessing + inference + DQN): **mean 10.21 ms / median 10.05 ms** (CNN 8.88 + DQN 1.33 ms) — earlier measurement 6.09 / 5.67 ms. The architectures are unchanged; the likely cause is machine/GPU state at the end of a 4-hour session. A re-measurement in a fresh MATLAB session is pending (see Known Issues).
- DQN-vs-rule action agreement: 29/54 = **53.7%** (~44%) — see the design clarification below.
- benign_interference and none: `no_action` in all 12 cases; recovery reported as N/A.

| Threat | Offline recall | Closed-loop detection | DQN action | Recovery vs clean (D27) | BER after / clean | Recovery vs before | Map A recoverable |
|---|---|---|---|---|---|---|---|
| jamming | 98.7% | 6/6 | channel_switch | 97.1% | 1.78× (4 restored, 2 marginal) | 85.8% | 80% |
| reactive_jamming | 87.1% | 6/6 | channel_switch | 97.8% | 1.48× (5 / 1) | 85.7% | 83% |
| sweeping_jammer | 98.7% | 6/6 | channel_switch (5), freq_diversity (1) | 95.4% | 1.14× (6 / 0) | 60.4% | 97% |
| noise_burst | 100% | 6/6 | channel_switch | 96.9% | 1.23× (6 / 0) | 71.6% | 90% |
| path_loss | 94.7% | 6/6 | spatial_diversity | 99.1% | 0.97× (6 / 0) | 83.9% | 75% |
| spoofing | 98.7% | 6/6 | channel_switch | 99.0% | 1.07× (6 / 0) | 83.5% | 97% |
| antenna_fault | 92.8% | 5/6 | channel_switch (5), no_action (1) | 81.9% (5 runs + 1 miss) | 1.67× (4 / 1) | 60.6% | 60% |
| benign_interference | 100% | 6/6 | no_action | N/A | — | N/A | 100% |
| none | 97.0% | 6/6 | no_action | N/A | — (reference) | N/A | — |

Measured against the clean link, every real threat except antenna_fault recovers ≥ 95%, so the earlier "weak" sweeping_jammer and noise_burst figures were an artefact of the BER-before metric (EXP had already shown them at 99.6% / 94.2% of their physical ceiling). antenna_fault is the genuine weak spot: lowest recovery (81.9%), the only marginal outcomes besides jamming at high Eb/N0, and the only missed detection. The high recovery is measured within the modelled countermeasure strength (fixed `action_mitigation_db`, see Architecture → Recovery); it does not by itself validate the magnitude of a real countermeasure.

### Phase C3-speed — Robustness vs UAV speed (D25)
Closed-loop sweep over 8 speeds (50 → 120 km/h, fd = 111 → 267 Hz), 9 threats × 3 Eb/N0 each:

| Speed (km/h) | 50.0 | 57.3 | 66.8 | 72.0 | 84.6 | 97.2 | 108.9 | 120.0 |
|---|---|---|---|---|---|---|---|---|
| fd (Hz) | 111 | 127 | 148 | 160 | 188 | 216 | 242 | 267 |
| Detection | 96.3% | 100% | 96.3% | 96.3% | 96.3% | 100% | 100% | 100% |
| Recovery vs clean (D27) | 95.6% | 94.7% | 96.9% | 94.7% | 95.2% | 95.7% | 95.8% | 96.1% |
| Restored (≤ 2× clean) | 16/20 | 18/21 | 17/20 | 18/21 | 17/21 | 17/21 | 18/21 | 17/21 |
| Recovery vs before (previous) | 70.3% | 69.2% | 73.5% | 71.9% | 72.7% | 73.5% | 73.6% | 74.2% |

Overall detection 98.1% (212/216), false-alarm rate 0% (0/48), recovery vs clean 95.6% (72.4% with the previous metric), flat across speed. All four misses are antenna_fault (1 of 3 SNR points at four speeds); every other threat is detected at 100% at every speed. With 27 runs per speed a single miss moves a point by 3.7%, so the dips are not evidence of a speed dependence. Consistent with D4, fading is deeply quasi-static across the whole envelope (normalized Doppler ≤ 2.7e-4 at 1 Msym/s), so mild speed sensitivity is expected.

### FAR (False Alarm Rate) — proposal KPI, section ה
- **0.0%** — 0/180 trials (none + benign_interference, SNR = 0/4/10 dB, N=30 each)
- Upper 95% bound (Rule of Three): **3.3%** per class (n=90 each), **1.7%** combined (n=180) — two different populations, state which one is meant
- none CNN detection 97.8% (88/90; both misses were labeled benign_interference, which maps to `no_action`, so they are not false alarms); benign_interference 100%
- 180 trials demonstrate the principle and give a statistically valid bound, but are not industrial-grade significance; a Monte Carlo run at tens of thousands of frames per condition is noted as future work

### KPI status (dashboard)
KPI1 detection 96.4% ✓ · KPI2 recovery 95.6% vs the no-attack link, 37/41 restored ≤ 2× clean ✓ · KPI3 decision latency 10.21 ms (DQN 1.33 ms vs rule 0.00028 ms) ✓ · KPI4 FAR 0.0% ✓ · KPI5 end-to-end MET (every real threat recovers end-to-end; best path_loss 99.1% vs clean) ✓

### KPI #3 — Decision Latency (DQN vs Rule-Based), redefined
**Original problem:** the metric was defined as "recovery cycles to convergence," but both policies are single-shot, deterministic dB reductions — there is no multi-cycle dynamic to measure. Redefined to decision **latency**.

Rule-based (hardcoded lookup table) is faster than DQN (neural network inference) by roughly three-to-four orders of magnitude (measured ~4,700×: 0.00028 ms vs 1.33 ms) — expected given the structural difference (constant-time lookup vs. a full forward pass), not a flaw in either policy. In the current static-mitigation environment (every action is a one-shot dB reduction, the threat does not adapt in response), this speed advantage isn't offset by any decision-quality advantage for the DQN — which is exactly why a **Dynamic/Chasing Jammer** scenario (an adversary that reacts to the system's countermeasures) is the priority future-work item: it's the scenario that should let a learned policy actually outperform a static one, closing this open question with a real result instead of a theoretical claim. See `## Known Issues & Future Work`.

**Design clarification for the report:** the DQN-vs-rule "agreement" comparison (Phase C3 diagnostic, 53.7% in the latest run, ~44% before) compares only the *chosen action name* between the two policies. `rule_based_policy.m`'s own per-threat mitigation magnitudes are not applied anywhere in the closed-loop pipeline — both policies' physical effect is computed via the shared `action_mitigation_db` (25/15/25/25 dB per action). This is a deliberate methodological choice, not an oversight: unifying the action space isolates *decision quality* from *execution strength*, so any measured difference in outcomes is attributable to the algorithm, not to one policy being handed a more powerful lever than the other. State this explicitly wherever "agreement" is reported.

### Phase EXP + Survivability Boundary Mapping (proposal deliverable #7)
Ran `explore_countermeasures.m` (re-run in the 2026-09-21 full pass: 2,790 simulations, 77.8 min) then `map_survivability_boundary.m`. EXP is BER-only (uses `quick_ber`, not the Rx_IQ spectrogram path) and runs at the nominal 72 km/h condition, so it was not affected by D18 or by the speed-diverse dataset (D25); the small shifts versus the previous numbers (83.8% / 87.5%) are simulation randomness, not a speed effect. Two separate maps:

- **Map A — Threat Neutralization** (mechanisms: `atten_reduction`, `field_reduction` only — genuine attack removal): **85.5% recoverable**, 11.5% marginal, 3.0% non-recoverable (234 states mapped; 200 / 27 / 7)
- **Map B — Link Survivability** (all mechanisms, including `awgn_margin_boost`): **88.3% recoverable**, 9.2% marginal, 2.5% non-recoverable (240 states mapped; 212 / 22 / 6)

**Why two maps:** `awgn_margin_boost` raises effective SNR rather than neutralizing the threat — it can make the link outperform the nominal clean-channel floor without the attack being weakened at all. A single map conflates "the link survived" with "the threat was removed." Map A is the literal reading of proposal deliverable #7; Map B shows the ceiling of everything the system can do, including SNR-margin tradeoffs.

**Gap analysis:** 1 cell (path_loss, level=8, SNR=10dB; Map A ratio 5.64× clean, Map B recoverable) where the link survives via Map B but not Map A — the proposal's goodput-tradeoff regime made concrete: survival without neutralization.

**Known coverage gap (not a bug):** path_loss at its lowest severity level (level=4) has no Map A data point — the smallest tested `field_reduction` magnitude (5dB) already exceeds that attack's severity (4dB), so every candidate mitigation at that level would imply unphysical signal amplification and is correctly excluded by the legitimacy filter.

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB) + AWGN; Doppler fd = v·fc/c follows the UAV speed — 111–267 Hz over the 50–120 km/h envelope, 160 Hz at the 72 km/h nominal (D25)
- **Classes (9):** jamming, reactive jamming, sweeping jammer, noise burst, path loss, spoofing, antenna fault, benign interference, none (clean channel)
- **Metrics:** BER, RSSI, SNR, PLR — see `## Modeling Assumptions` for which of these are physically measurable at a real receiver and which are simulation ground-truth

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] scalar/temporal features (SNR, BER, RSSI, PLR, var_rssi_10, dber_dt, burst_ratio)
- **Architecture:** CNN (32→64→128 filters, BN+ReLU+Pool, GAP) + FC (32→16) → merged 144-d → FC(64)+Dropout(0.3) → softmax(9)
- **Performance:** 96.41% accuracy (macro-F1 96.39%) across 50–120 km/h; ~10 ms mean decision latency in the latest measurement (CNN preprocessing + inference 8.9 ms, DQN 1.3 ms; 6.1 ms in the earlier D23 measurement)
- **Training data:** speed-diverse — every 100-frame block at its own continuous random speed in 50–120 km/h (D25); speed is analysis metadata, not a network input

### Decision (DQN)
- **State:** one-hot(9 threat classes) + [BER, RSSI, SNR, PLR] = **13-dim**, built exclusively via `build_dqn_state.m` (train and inference share the same function — encoding cannot drift)
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** `100*(BER_before-BER_after)/max(BER_before,eps)` for real threats; fixed false-alarm penalty (no_action=0, all else=-40) for benign_interference and none (D9: non-hostile/no-threat conditions should not trigger a countermeasure)
- **Training:** single-shot bandit formulation (done=1 every episode — no multi-step bootstrapping); benign_interference, none, and antenna_fault oversampled 3x; post-training validation gate (Gate A/B) blocks saving a non-compliant agent

### Recovery — mitigation magnitudes (validated via EXP phase)
- **channel_switch / freq_diversity / spatial_diversity:** 25 dB reduction
- **rate_reduce:** 15 dB reduction
- A physical floor prevents `path_loss_db`/`fault_atten_db` from going negative (unphysical signal amplification) under strong mitigation

**Design note:** the four non-zero actions are mechanistically identical in the current implementation — each subtracts its assigned `action_mitigation_db` from the threat's own severity field, regardless of the action's label. Three of the four actions share the same 25dB value. Most residual DQN-vs-rule-based "disagreement" is therefore cosmetic (the two labels are functionally near-equivalent in effect) — see the KPI #3 design clarification above.

---

## Modeling Assumptions & Limitations

Documented in full in the interim report (section 3.7) and worth summarizing here for anyone extending the codebase:

- **BER is simulation ground-truth ("oracle"), not a physically-measurable feature.** It's computed by comparing `tx_bits_out` to `rx_bits_out` — information a real deployed receiver does not have (it never knows what the transmitter actually sent). A real system would substitute an indirect estimator: EVM, CRC-based frame error rate, or FEC correction counts. This affects not just the `ber` feature but three others derived from it: **PLR** (`ber > 0.1` threshold), **dber_dt**, and **burst_ratio** — i.e. 4 of the 7 detector features are oracle-derived; only RSSI, var_rssi_10, and SNR (configured but realistically estimable from pilots) are directly physical.
- **Countermeasure application is a flat dB subtraction**, not a dynamic RF simulation — no channel re-synthesis, synthesizer lock time, or handoff blind-time is modeled. `spatial_diversity` specifically does not model a real multi-antenna (MIMO/SIMO) RF chain; it represents, abstractly, the effect of switching to a working backup antenna or MRC combining.
- **Transition/switching cost is not in the reward function** — every action's full dB benefit applies instantly and for free in the model. A `λδ`-style transition-cost term (Liu et al. [6]) is documented future work.
- **No PHY-layer timing/carrier synchronization is modeled** (D7) — the project's scope is link-layer AI detection and decision, not a Costas/Gardner-loop receiver. This is also why "spoofing" here means a coherent counterfeit waveform causing interference/detection-confusion, not synchronization hijacking — there's no sync loop in the model to hijack.

None of these are hidden — they're the explicit content of the report's Limitations & Assumptions section, framed as disclosed modeling choices appropriate to a proof-of-concept simulation, with a stated path to a more physically-complete model for each one.

---

## Interactive Demo (`demo_gui.m`, v3)

Operator-console style MATLAB `uifigure` app for live, in-person demonstration, rebuilt (D26) to cover every proposal deliverable. Four tabs:

- **LIVE OPERATIONS** — a test matrix (threat × Eb/N0, per-row and per-cell selection) runs as a queue. Controls: **UAV speed** (50–120 km/h, continuous; the Doppler is applied to the Simulink channel of every run), **threat severity** (nominal or levels 1–5 using the dataset's severity axes), an **UNKNOWN-threat confidence threshold** slider, a rule-based comparison toggle and optional session-video capture. Per run it shows: a threat-specific GCS↔UAV link diagram, spectrogram and IQ constellation before/after, a **BER / RSSI timeline** with the countermeasure boundary and the clean-channel reference, CNN confidence and decision-latency gauges with class probabilities, **DQN Q-values with the rule-based choice marked**, a BER bar chart (no action / DQN / rule), the goodput trade-off flag for `rate_reduce`, and a verdict classified with the survivability-map thresholds (recoverable ≤ 2× clean BER, marginal ≤ 5×).
- **KPI & RESULTS** — six KPI cards, confusion matrix, accuracy and recovery vs Eb/N0, decision latency, action distribution and robustness vs UAV speed, read from `results/`.
- **SURVIVABILITY MAP** — Map A / Map B per threat (severity × Eb/N0 grid, ratio to clean BER, gap-cell analysis) with the last live run marked.
- **SESSION LOG** — full run history table, export to CSV + `.mat` in `GUI_Results/`, per-sequence event log.

Every run calls the real pipeline end-to-end (no mocked or precomputed results): `build_threat_model.m` → `sim()` → `extract_closed_loop_frames.m` → trained CNN → trained DQN → a real second `sim()` per distinct chosen action (DQN, and rule-based if different) to measure the actual post-mitigation BER. Decision latency is timed strictly around the CNN path plus the DQN forward pass (no drawing or pauses inside `tic/toc`), so it is the same quantity the diagnostic reports.

**Architecture note for anyone extending this file:** it deliberately contains **no nested functions** — MATLAB makes a function's workspace "static" whenever it contains a nested function, which then rejects the script-style variable injection used by `init_params.m` and `build_threat_model.m` throughout this codebase. Static state (models, parameters, UI handles, colours) lives in `fig.UserData`; state that changes while a sequence runs (history, video writer, log file, abort flag, last run) lives in appdata so a callback can never overwrite it with a stale copy. `params.mat` is restored after every run through an `onCleanup` guard. See D24 and D26 in `DECISIONS.md`.

**Performance note:** `splits.mat` is >1 GB but the GUI needs only two normalization vectors; the first launch extracts them into `data/gui_norm_stats.mat` (one-time, slow) and later launches skip the big load. Run the GUI from a fresh MATLAB session after `main.m`.

---

## Report

An interim report (Word .docx, 7 chapters — intro, theoretical background with full math, implementation, results, dashboard, risks, future work — plus a dedicated Limitations & Assumptions section) has been drafted covering the material in this README in full academic depth, including the modeling-assumptions disclosures above. It is maintained outside this git repository (a submission deliverable, not project source). **Its results chapters predate the 2026-09-21 full re-run and need syncing** — the list of figures to update is in `PROJECT_LOG.md` (Session 11). A small number of figure placeholders remain, each labeled in the document with a description of what real photo/diagram would fit there (e.g. a tactical UAV photo, a QPSK constellation diagram) — public-domain source suggestions (U.S. DoD / Wikimedia) were provided; final image selection is pending.

---

## Design Highlights

See `docs/DECISIONS.md` for the full Architecture Decision Record:
- **D1:** Model-based simulation (no SDR hardware)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D7:** No PHY-layer carrier/timing synchronization modeled (link-layer AI focus) — see Modeling Assumptions above
- **D8:** Signal-level threat injection (not metric-level)
- **D9:** Non-hostile faults (antenna_fault, path_loss, benign_interference, none) deliberately included so the system learns to distinguish real attacks from benign/faulty/clean conditions
- **D11:** System Objects engine (replaced commfilt2 ISI floor)
- **D12:** Spoofing root-cause fix (coherent QPSK injection) — historical instability was a data-generation bug, not a detector limitation
- **D13:** CNN-LSTM comparison architecture — built, evaluated, not pursued further (production stays CNN+scalar hybrid); excluded from `main.m`
- **D14:** DQN state encoding — ordinal → one-hot (13-dim)
- **D15:** KPI #3 redefinition — recovery cycles → decision latency
- **D16:** Closed-loop sliding-window feature fix
- **D17:** Survivability boundary — two-map methodology (neutralization vs. survivability)
- **D18:** Rx_IQ tap point fixed (post-AWGN, not pre-AWGN) — full pipeline re-run completed, numbers above are post-fix
- **D19:** rule_based_policy.m's per-threat mitigation_db documented as unused (comparison is decision-policy only)
- **D20:** Shared `extract_closed_loop_frames.m` — fixed a FAR-measurement bug (missing AWGN `set_param` per trial) that had inflated FAR to ~72%; real FAR is 0%
- **D21:** Closed-loop diagnostic reports recovery as N/A when the DQN chose no_action; GPU warm-up strengthened
- **D22:** Decision-latency measurement widened to include full preprocessing, not just inference
- **D23:** `spectrogram()` warm-up added — eliminated a one-time JIT skew between mean and median latency
- **D24:** `demo_gui.m` built — interactive operator-console demo; no-nested-functions architecture pattern documented for future MATLAB GUI work
- **D25:** UAV speed envelope widened to a continuous 50–120 km/h (Doppler 111–267 Hz); speed-diverse dataset, accuracy-vs-speed evaluation and `eval_speed_robustness.m`. Amends D4
- **D27:** KPI #2 measured against the no-attack (clean) link, as the proposal defines it (`recovery_vs_clean.m`); clean reference = the `none` run at the same Eb/N0; previous BER-before metric kept alongside
- **D26:** `demo_gui.m` v3 — proposal-complete operator console (4 tabs, DQN-vs-rule comparison, UNKNOWN-threat handling, survivability verdicts, speed-driven Doppler); norm-stats cache for fast startup

See `PROJECT_LOG.md` for the full fix history and session-by-session detail behind each decision above.

---

## Known Issues & Future Work

**Open items:**
- **Dynamic/Chasing Jammer scenario** (priority) — an adversary that reacts to the system's countermeasures, needed to let the DQN demonstrate a real decision-quality advantage over the static rule-based policy (see KPI #3 discussion above). Planned, not yet built.
- A small number of report figure placeholders need real source images (suggestions provided, final selection pending)
- `demo_gui.m` v3 (D26) — rebuilt and delivered; verified only by a syntax parse and helper-function tests outside MATLAB, so live-use feedback and small layout fixes are still expected. A slow-startup report on 2026-09-22 was addressed (norm-stats cache; launch from a fresh session)
- **reactive_jamming 87.1% recall** (was 91.0%; macro-F1 96.39%) — 33 of 304 test samples are labeled jamming. The distinction is temporal, and the extra Doppler variation may blur the temporal features (untested hypothesis). Below the 90% per-class line in absolute terms but above the proposal's 90% macro-F1 target; its closed-loop recovery is unaffected (85.7%) because jamming receives the same countermeasure. Candidate for targeted improvement or documentation as a known limitation.
- **antenna_fault** — weakest class overall: 92.8% recall, 5/6 closed-loop detection (the miss at 0 dB has 31% confidence and ends in `no_action`), 60.6% recovery and 64% of its recovery ceiling.
- **Decision latency** — 10.21 ms mean in the 2026-09-21 full run vs 6.09 ms in the earlier D23 measurement, with unchanged architectures. Re-measure `run_closed_loop_diagnostic` alone in a fresh MATLAB session and cite that value; if it stays near 10 ms, check whether the GPU is in use.
- **Detector-only speed diversity** — the DQN state has no Doppler input and EXP/SURV run at the nominal 72 km/h; only detection and closed-loop robustness are speed-swept.
- `main.m` prints a hard-coded CHECKPOINT line at the end (old numbers); the authoritative numbers are in `results/kpi_summary.txt` and `results/kpi_dashboard.png`.

**Future work:**
- Sim-to-real validation (SDR testbed) — see Modeling Assumptions above for the specific gaps this would need to close (BER estimation via EVM/CRC, real synthesizer switching time, PHY synchronization)
- Multi-threat scenarios (combined attacks)
- Online reinforcement learning
- FPGA/GPU acceleration
- Transition-cost-aware reward shaping (Liu et al.'s λδ term) — could reduce mechanically-driven DQN/rule disagreement, not currently implemented
- Monte Carlo FAR estimation at tens-of-thousands of frames per condition, for industrial-grade statistical resolution

---

## References

Key sources from the project proposal (IEEE format):
- H. Yuan et al., "Joint relay and channel selection against mobile and smart
  jammer: A deep reinforcement learning approach," IET Communications, vol. 15,
  2021.
- X. Liu, Y. Xu, L. Jia, Q. Wu, A. Anpalagan, "Anti-Jamming Communications
  Using Spectrum Waterfall: A Deep Reinforcement Learning Approach," IEEE
  Communications Letters, vol. 22, no. 5, pp. 998-1001, 2018.
- F. Tlili et al., "Advancing UAV security with artificial intelligence: A
  comprehensive survey of techniques and future directions," Internet of
  Things, vol. 27, 2024.
- Z. Yu et al., "Cybersecurity of Unmanned Aerial Vehicles: A Survey," IEEE
  Aerospace and Electronic Systems Magazine, vol. 39, pp. 182-215, 2024.
- S. Nanayakkara et al., "Smart Drone Neutralization: AI Driven RF Jamming
  and Modulation Detection with Software Defined Radio," Drones and
  Autonomous Vehicles, 2025 — latency-aware model comparison, verified
  against the primary source (Table 5): Faster R-CNN 99%@2349ms, CenterNet
  96%@1366ms, SSD ResNet50 48%@1286ms, EfficientDet 58%@233ms. This
  system's ~10 ms mean decision latency (latest measurement; 5.7 ms median earlier) at 96.41% accuracy compares favorably
  against all four on both axes.
- Mnih et al. (2015), "Human-level control through deep reinforcement
  learning," Nature — base DQN architecture.
- Rician channel models & Doppler effects (standard comms textbooks).

---

**Last Updated:** 2026-09-23 (D27: KPI #2 against the no-attack link; D25–D26: speed envelope 50–120 km/h, demo_gui v3)
**Status:** Phase A+B+C+EXP complete and re-run on the speed-diverse dataset, survivability mapping complete, all 5 proposal KPIs met, speed-robustness evaluation complete, interim report drafted (results chapters pending sync to the latest run), operator console v3 delivered and under live testing | Phase D (final report + defense prep) in progress
