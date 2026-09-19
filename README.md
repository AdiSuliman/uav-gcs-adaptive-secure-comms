# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A
**Students:** Adi Suliman, Bar Dvir Hassan
**Supervisor:** Golan Ein-Tzvi
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + scalar/temporal features, **96.99% accuracy**, ~2.7ms decision latency)
- Reinforcement learning policy (DQN trained on true Simulink reward, one-hot state encoding), with reward shaping so the agent correctly withholds action on non-hostile interference (benign_interference → no_action, none → no_action) — verified **0% false-alarm rate** across 180 non-hostile trials
- Adaptive recovery (channel switching, rate reduction, diversity), with magnitudes empirically validated against a dedicated countermeasure-exploration sweep (EXP phase, 2550 scenarios)
- Survivability boundary mapping (proposal deliverable #7): separate Threat-Neutralization and Link-Survivability maps, with gap analysis distinguishing genuine attack removal from SNR-margin tradeoffs
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison, FAR measurement, KPI aggregation

---

## Repository Structure

```
├── main.m                        # Master orchestrator (flags for A, B, C, EXP, KPI phases)
├── init_params.m                 # System & threat parameters (K=10dB, 160Hz Doppler)
├── build_dqn_state.m             # Single source of truth: 13-dim one-hot DQN state
├── models/                       # Simulink Digital Twin (gitignored — regenerated on build)
│   ├── UAV_GCS_Base_Link.slx     # A1-A2: clean AWGN channel
│   ├── UAV_GCS_Rician_Link.slx   # A3: fading + Doppler
│   └── UAV_GCS_Threat_Link.slx   # A4-A6: threats + recovery
├── docs/
│   └── DECISIONS.md              # Architecture Decision Record (D1-D21)
├── diagnostics/                  # Ad-hoc investigation scripts, kept for reproducibility
├── README.md                     # This file
├── PROJECT_LOG.md                # Living execution log — status, fix history, open issues
├── ROADMAP.md                    # Project timeline (original plan)
└── [Phase scripts]
    ├── A: build_*.m, extract_*.m, run_*_sweep.m
    ├── B: prepare_data.m, train_detector.m, eval_detector.m
    ├── B-exp: *_lstm.m, *_seq.m (CNN-LSTM comparison — not pursued, kept for the record)
    ├── C: train_dqn.m, dqn_agent.m, rule_based_policy.m, run_closed_loop_*.m
    ├── EXP: explore_countermeasures.m, analyze_exploration_results.m, map_survivability_boundary.m
    └── KPI: measure_all_kpis.m, measure_kpi3_recovery_time.m, diagnose_far_measurement.m
```

**Note:** `data/`, `results/`, `logs/`, `models/` are `.gitignore`'d (too large / regenerable). Exception: `results/survivability_*` (Map A/B outputs, proposal deliverable #7) are tracked explicitly — they are a primary research output, not a regenerable byproduct.

---

## Quick Start

1. **Setup:** MATLAB R2026a with Communications, DSP System, Deep Learning, RL toolboxes
2. **Run:** `main.m` — toggle RUN flags to control which phases execute
3. **Explore:** `logs/run_*.txt` accumulates full console output (via `diary`)

**Phases & runtimes:**
- Phase A (link + dataset): 10–60 min
- Phase B (detector train): 5–15 min
- Phase C1 (rule-based): < 1 min
- Phase C2 (DQN train): ~10-15 min
- Phase C3 (closed-loop, both scripts): 4–8 min total
- Phase EXP (deep countermeasure exploration): ~75-86 min, run rarely
- Phase KPI (FAR + aggregation): < 5 min
- Survivability mapping: < 5 min (uses cached EXP data)

---

## Latest Results (2026-09-19, post full re-run after D18)

All numbers below are from the pipeline re-run after the Rx_IQ tap-point fix
(D18) — spectrograms and RSSI now reflect the real swept AWGN noise, so these
are the physically-correct results, not the earlier artificially-flat ones.

### Phase B3 — CNN Detector (9-class)
- **Overall accuracy: 96.99%** (macro-F1 96.98%)
- Per-SNR: 94.1% @ 0dB → 98.0% @ 2dB → 96.3% @ 4dB → 98.2% @ 6dB → 97.8% @ 8dB → 97.6% @ 10dB — now shows genuine SNR-dependent degradation at the low edge (as physically expected, post-D18), not the earlier artificially-flat curve
- Weakest class: reactive_jamming (88.0% recall, confuses with jamming — the distinction is temporal); all others ≥95%. spoofing 100%, noise_burst 100%, sweeping_jammer 100%

### Phase C3 (Closed-Loop) — current numbers
- Detection accuracy in closed loop: **100%** (54/54, all 9 threats × 6 SNR points)
- Mean BER recovery (real threats): **74.6%**
- Mean/median decision latency: **2.67 / 2.54 ms** (CNN + DQN inference)
- benign_interference and none: DQN chose **no_action in all 12 cases** (2 classes × 6 SNR) — recovery correctly reported as N/A (no countermeasure applied, nothing to recover)

### FAR (False Alarm Rate) — proposal KPI, section ה
- **0.0%** across 180 trials (none + benign_interference, swept over SNR = 0/4/10 dB, N=30 each), upper 95% CI bound 3.3% via Rule-of-Three
- none CNN detection accuracy 98.9%, benign_interference 100% — no false alarm at any SNR, including the 0 dB worst case

### Prior root-cause fixes (2026-09-18, still in effect — see DECISIONS.md D12/D14/D16)
- **Spoofing (D12):** was injected as incoherent per-sample noise (indistinguishable from jamming). Now coherent QPSK, RRC-shaped like the real Tx. Recall 53-79% → ~100%.
- **DQN state (D14):** scalar-ordinal threat code caused Q-value bleed between adjacent codes. Replaced with 13-dim one-hot via the shared `build_dqn_state.m`.
- **Closed-loop sliding window (D16):** CNN was fed placeholder temporal features in the closed loop while trained on real ones. Now builds real sliding-window features from each run's ~20 frames.

### Phase EXP + Survivability Boundary Mapping (proposal deliverable #7)
Ran `explore_countermeasures.m` (2550 scenarios, 85.8 min) then `map_survivability_boundary.m`. EXP is BER-only (uses `quick_ber`, not the Rx_IQ spectrogram path), so it was **not** affected by D18 and did not need re-running. Two separate maps:

- **Map A — Threat Neutralization** (mechanisms: `atten_reduction`, `field_reduction` only — genuine attack removal): **84.6% recoverable**, 12.4% marginal, 3.0% non-recoverable (234 states mapped)
- **Map B — Link Survivability** (all mechanisms, including `awgn_margin_boost`): **87.9% recoverable**, 9.6% marginal, 2.5% non-recoverable (240 states mapped)

**Why two maps:** `awgn_margin_boost` raises effective SNR rather than neutralizing the threat — it can make the link outperform the nominal clean-channel floor without the attack being weakened at all. A single map conflates "the link survived" with "the threat was removed." Map A is the literal reading of proposal deliverable #7; Map B shows the ceiling of everything the system can do, including SNR-margin tradeoffs.

**Gap analysis:** 1 cell (path_loss, level=8, SNR=10dB) where the link survives via Map B but not Map A — the proposal's goodput-tradeoff regime made concrete: survival without neutralization.

**Known coverage gap (not a bug):** path_loss at its lowest severity level (level=4) has no Map A data point — the smallest tested `field_reduction` magnitude (5dB) already exceeds that attack's severity (4dB), so every candidate mitigation at that level would imply unphysical signal amplification and is correctly excluded by the legitimacy filter.

### KPI #3 — Decision Latency (DQN vs Rule-Based), redefined
**Original problem:** the metric was defined as "recovery cycles to convergence," but both policies are single-shot, deterministic dB reductions — there is no multi-cycle dynamic to measure. Redefined to decision **latency**: Rule-based (hardcoded lookup) is faster than DQN (neural network inference) by roughly three orders of magnitude — expected and unremarkable on its own, but worth stating precisely rather than reporting a meaningless "cycles" number.

**Design clarification for the report:** the DQN-vs-rule "agreement" comparison (Phase C3 diagnostic, ~52%) compares only the *chosen action name* between the two policies. `rule_based_policy.m`'s own per-threat mitigation magnitudes are not applied anywhere in the closed-loop pipeline — both policies' physical effect is computed via the shared `action_mitigation_db` (25/15/25/25 dB per action). This should be stated explicitly wherever "agreement" is reported, to avoid implying two independently-implemented countermeasure systems are being compared.

### Phase EXP + Survivability Boundary Mapping (proposal deliverable #7, 2026-09-19)
Ran `explore_countermeasures.m` (2550 scenarios, 85.8 min) then `map_survivability_boundary.m`, producing **two separate maps**:

- **Map A — Threat Neutralization** (mechanisms: `atten_reduction`, `field_reduction` only — genuine attack removal): **84.6% recoverable**, 12.4% marginal, 3.0% non-recoverable (234 states mapped)
- **Map B — Link Survivability** (all mechanisms, including `awgn_margin_boost`): **87.9% recoverable**, 9.6% marginal, 2.5% non-recoverable (240 states mapped)

**Why two maps:** `awgn_margin_boost` raises effective SNR rather than neutralizing the threat — it can make the link outperform the nominal clean-channel floor without the attack being weakened at all. A single map conflates "the link survived" with "the threat was removed." Map A is the literal reading of proposal deliverable #7; Map B shows the ceiling of everything the system can do, including SNR-margin tradeoffs.

**Gap analysis:** 1 cell (path_loss, level=8, SNR=10dB) where the link survives via Map B but not Map A — the proposal's goodput-tradeoff regime made concrete: survival without neutralization.

**Known coverage gap (not a bug):** path_loss at its lowest severity level (level=4) has no Map A data point — the smallest tested `field_reduction` magnitude (5dB) already exceeds that attack's severity (4dB), so every candidate mitigation at that level would imply unphysical signal amplification and is correctly excluded by the legitimacy filter.

### FAR (False Alarm Rate) — proposal KPI, section ה
**0%** measured (100 trials on non-hostile classes), upper 95% CI bound **3%** via Rule-of-Three (appropriate for a zero-count observation — a naive symmetric CI would be meaningless at 0%).

### KPI #3 — Decision Latency (DQN vs Rule-Based), redefined
**Original problem:** the metric was defined as "recovery cycles to convergence," but both policies are single-shot, deterministic dB reductions — there is no multi-cycle dynamic to measure. Redefined to decision **latency**: Rule-based (hardcoded lookup) is faster than DQN (neural network inference) by roughly three orders of magnitude — expected and unremarkable on its own, but worth stating precisely rather than reporting a meaningless "cycles" number.

**Design clarification for the report:** the DQN-vs-rule "agreement" comparison (Phase C3 diagnostic) compares only the *chosen action name* between the two policies. `rule_based_policy.m`'s own per-threat mitigation magnitudes are not applied anywhere in the closed-loop pipeline — both policies' physical effect is computed via the shared `action_mitigation_db` (25/15/25/25 dB per action). This should be stated explicitly wherever "agreement" is reported, to avoid implying two independently-implemented countermeasure systems are being compared.

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB, fd=160Hz) + AWGN
- **Classes (9):** jamming, reactive jamming, sweeping jammer, noise burst, path loss, spoofing, antenna fault, benign interference, none (clean channel)
- **Metrics:** BER, RSSI, SNR, PLR

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] scalar/temporal features (SNR, BER, RSSI, PLR, var_rssi_10, dber_dt, burst_ratio)
- **Architecture:** CNN (64→128 filters, GAP) + FC (32→16) → merged FC → softmax(9)
- **Performance:** 96.99% accuracy, ~1.8ms CNN inference (2.67ms combined with DQN)

### Decision (DQN)
- **State:** one-hot(9 threat classes) + [BER, RSSI, SNR, PLR] = **13-dim**, built exclusively via `build_dqn_state.m` (train and inference share the same function — encoding cannot drift)
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** Real Simulink BER improvement, with a fixed false-alarm penalty (no_action=0, all else=-40) for benign_interference and none (D9: non-hostile/no-threat conditions should not trigger a countermeasure)
- **Training:** single-shot bandit formulation (done=1 every episode — no multi-step bootstrapping); benign_interference, none, and antenna_fault oversampled 3x; post-training validation gate (Gate A/B, see above) blocks saving a non-compliant agent

### Recovery — mitigation magnitudes (validated via EXP phase)
- **channel_switch / freq_diversity / spatial_diversity:** 25 dB reduction
- **rate_reduce:** 15 dB reduction
- A physical floor prevents `path_loss_db`/`fault_atten_db` from going negative (unphysical signal amplification) under strong mitigation

**Design note:** the four non-zero actions are mechanistically identical in the current implementation — each subtracts its assigned `action_mitigation_db` from the threat's own severity field, regardless of the action's label. Three of the four actions share the same 25dB value. Most residual DQN-vs-rule-based "disagreement" is therefore cosmetic (the two labels are functionally near-equivalent in effect).

---

## Design Highlights

See `docs/DECISIONS.md` for the full Architecture Decision Record:
- **D1:** Model-based simulation (no SDR hardware)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D8:** Signal-level threat injection (not metric-level)
- **D9:** Non-hostile faults (antenna_fault, path_loss, benign_interference, none) deliberately included so the system learns to distinguish real attacks from benign/faulty/clean conditions
- **D11:** System Objects engine (replaced commfilt2 ISI floor)
- **D12:** Spoofing root-cause fix (coherent QPSK injection) — historical instability was a data-generation bug, not a detector limitation
- **D13:** CNN-LSTM comparison architecture — built, evaluated, not pursued further (production stays CNN+scalar hybrid)
- **D14:** DQN state encoding — ordinal → one-hot (13-dim)
- **D15:** KPI #3 redefinition — recovery cycles → decision latency
- **D16:** Closed-loop sliding-window feature fix
- **D17:** Survivability boundary — two-map methodology (neutralization vs. survivability)
- **D18:** Rx_IQ tap point fixed (post-AWGN, not pre-AWGN) — full pipeline re-run completed, numbers above are post-fix
- **D19:** rule_based_policy.m's per-threat mitigation_db documented as unused (comparison is decision-policy only)
- **D20:** Shared `extract_closed_loop_frames.m` — the sliding-window frame extraction (D16) was still missing from `diagnose_far_measurement.m`; extracted to one shared function so it can't drift again. Fixed a FAR-measurement bug (missing AWGN `set_param` per trial) that had inflated FAR to ~72%; real FAR is 0%.
- **D21:** Closed-loop diagnostic reports recovery as N/A when the DQN chose no_action (non-hostile/no-threat cases), instead of a meaningless BER ratio on an untouched channel. GPU warm-up strengthened so latency is steady from the first measured run.

See `PROJECT_LOG.md` for the full fix history and session-by-session detail behind each decision above.

---

## Known Issues & Future Work

**Open items:**
- KPI Dashboard (proposal deliverable #1, final product) — script drafted (`build_kpi_dashboard.m`), not yet finalized
- Interim/final report writeup (Phase D) — not started
- `src/` directory — present locally, not tracked in git; contents not yet audited
- `extract_temporal_features.m` — orphaned (not called anywhere in the pipeline; folded into `extract_spectrograms.m`); candidate for removal
- reactive_jamming 88% recall (below the 90% per-class line, though macro-F1 is 96.98%) — confuses with continuous jamming; the distinction is temporal. Candidate for targeted improvement or documentation as a known limitation.

**Future work:**
- Sim-to-real validation (SDR testbed)
- Multi-threat scenarios (combined attacks)
- Online reinforcement learning
- FPGA/GPU acceleration
- Transition-cost-aware reward shaping (Liu et al.'s λδ term) — could reduce mechanically-driven DQN/rule disagreement, not currently implemented

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
- N. Nanayakkara et al., "Smart Drone Neutralization: Real-time RF Signal
  Classification for Countering Unauthorized Drones," 2025 — latency-aware
  model comparison (Faster R-CNN 99%@2349ms, CenterNet 96%@1366ms,
  EfficientDet 58%@233ms); this system's 3-8ms detection at 98.05% accuracy
  compares favorably on both axes.
- Mnih et al. (2015), "Human-level control through deep reinforcement
  learning," Nature — base DQN architecture.
- Rician channel models & Doppler effects (standard comms textbooks).

---

**Last Updated:** 2026-09-19 (post D18 full re-run + D20/D21 fixes)
**Status:** Phase A+B+C+EXP complete and re-verified, survivability mapping complete, all 5 proposal KPIs met | Phase D (dashboard + writeup) in progress
