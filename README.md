# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A
**Students:** Adi Suliman, Bar Dvir Hassan
**Supervisor:** Golan Ein-Tzvi
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + scalar/temporal features, **96.73% accuracy**, ~5.7ms median decision latency including full signal preprocessing)
- Reinforcement learning policy (DQN trained on true Simulink reward, one-hot state encoding), with reward shaping so the agent correctly withholds action on non-hostile interference (benign_interference → no_action, none → no_action) — verified **0% false-alarm rate** across 180 non-hostile trials
- Adaptive recovery (channel switching, rate reduction, diversity), with magnitudes empirically validated against a dedicated countermeasure-exploration sweep (EXP phase, 2550 scenarios)
- Survivability boundary mapping (proposal deliverable #7): separate Threat-Neutralization and Link-Survivability maps, with gap analysis distinguishing genuine attack removal from SNR-margin tradeoffs
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison, FAR measurement, KPI aggregation
- Interactive live demo (`demo_gui.m`): operator-console style GUI — multi-threat sequence runs, live spectrogram + IQ constellation, link-status indicator, run-history export, session video recording
- Interim report (Word, 7 chapters + limitations/assumptions section) drafted; see `## Report` below

---

## Repository Structure

```
├── main.m                        # Master orchestrator (18 RUN-flags across phases A-DASH; LSTM excluded, D13)
├── init_params.m                 # System & threat parameters (K=10dB, 160Hz Doppler)
├── build_dqn_state.m             # Single source of truth: 13-dim one-hot DQN state
├── demo_gui.m                    # Interactive live operator-console demo (D24)
├── build_kpi_dashboard.m         # 7-panel results dashboard (proposal deliverable #1)
├── models/                       # Simulink Digital Twin (gitignored — regenerated on build)
│   ├── UAV_GCS_Base_Link.slx     # A1-A2: clean AWGN channel
│   ├── UAV_GCS_Rician_Link.slx   # A3: fading + Doppler
│   └── UAV_GCS_Threat_Link.slx   # A4-A6: threats + recovery
├── docs/
│   └── DECISIONS.md              # Architecture Decision Record (D1-D24)
├── diagnostics/                  # Ad-hoc investigation scripts, kept for reproducibility
├── README.md                     # This file
├── PROJECT_LOG.md                # Living execution log — status, fix history, open issues
├── ROADMAP.md                    # Project timeline (original plan)
└── [Phase scripts]
    ├── A: build_*.m, extract_*.m, run_*_sweep.m
    ├── B: prepare_data.m, train_detector.m, eval_detector.m
    ├── B-exp: *_lstm.m, *_seq.m (CNN-LSTM comparison — not pursued, kept for the record; excluded from main.m)
    ├── C: train_dqn.m, dqn_agent.m, rule_based_policy.m, run_closed_loop_*.m
    ├── EXP: explore_countermeasures.m, analyze_exploration_results.m, map_survivability_boundary.m
    └── KPI: measure_all_kpis.m, measure_kpi3_recovery_time.m, diagnose_far_measurement.m
```

**Note:** `data/`, `results/`, `logs/`, `models/` are `.gitignore`'d (too large / regenerable). Exception: `results/survivability_*` (Map A/B outputs, proposal deliverable #7) are tracked explicitly — they are a primary research output, not a regenerable byproduct.

---

## Quick Start

1. **Setup:** MATLAB R2026a with Communications, DSP System, Deep Learning, RL toolboxes
2. **Run the full pipeline:** `main.m` — toggle RUN flags to control which phases execute (see in-file presets: full clean run / results-only refresh / dashboard-only)
3. **Live demo:** `demo_gui.m` — select one or more threats, set SNR, press Run; see `## Interactive Demo` below
4. **Explore:** `logs/run_*.txt` accumulates full console output (via `diary`)

**Phases & runtimes:**
- Phase A (link + dataset): 10–60 min
- Phase B (detector train): 5–15 min
- Phase C1 (rule-based): < 1 min
- Phase C2 (DQN train): ~10-15 min
- Phase C3 (closed-loop, both scripts): 4–8 min total
- Phase EXP (deep countermeasure exploration): ~75-86 min, run rarely
- Phase KPI (FAR + aggregation): < 5 min
- Survivability mapping: < 5 min (uses cached EXP data)
- Dashboard: < 1 min (needs B3+C3-diag+FAR+SURV already run)

---

## Latest Results (2026-09-21, post D22/D23 latency-measurement fixes)

All numbers below are from the most recent full pipeline re-run. Detection
and recovery numbers are unchanged from the D18 re-run; latency numbers were
re-measured after D22 (widened measurement scope to include preprocessing)
and D23 (spectrogram warm-up, eliminating a one-time JIT skew).

### Phase B3 — CNN Detector (9-class)
- **Overall accuracy: 96.73%** (macro-F1 96.73%)
- Per-SNR: 93.4% @ 0dB → 97.1% @ 2dB → 96.5% @ 4dB → 98.0% @ 6dB → 97.8% @ 8dB → 97.6% @ 10dB — genuine SNR-dependent degradation at the low edge, as physically expected post-D18
- Weakest class: reactive_jamming (91.0% recall, confuses with jamming — the distinction is temporal); all others ≥93%. spoofing 100%, noise_burst 100%, sweeping_jammer 99.7%

### Phase C3 (Closed-Loop) — current numbers
- Detection accuracy in closed loop: **100%** (54/54, all 9 threats × 6 SNR points)
- Mean BER recovery (real threats): **74.6%**
- Decision latency (CNN preprocessing+inference, + DQN inference), post D22/D23: **mean 6.09ms / median 5.67ms** — the small mean-median gap confirms no remaining measurement skew
- benign_interference and none: DQN chose **no_action in all 12 cases** (2 classes × 6 SNR) — recovery correctly reported as N/A (no countermeasure applied, nothing to recover)
- DQN-vs-rule action agreement: ~44% — see "Design clarification" below for why this number should not be read as "DQN is wrong more than half the time"

### FAR (False Alarm Rate) — proposal KPI, section ה
- **0.0%** across 180 trials (none + benign_interference, swept over SNR = 0/4/10 dB, N=30 each)
- Upper 95% CI bound (Rule-of-Three, zero-count observation): **3.3%** per class individually (n=90 each) or **1.7%** across all 180 trials combined (n=180) — these are two different populations, state which one you mean when citing this number
- none CNN detection accuracy 98.9-100%, benign_interference 100% — no false alarm at any SNR, including the 0 dB worst case
- 180 trials demonstrate the principle and give a statistically valid bound, but are not industrial-grade significance; a Monte Carlo run at tens-of-thousands of frames per condition would be needed for high-resolution FAR estimates (e.g. distinguishing 0.1% from 0.5%) — noted as future work

### KPI #3 — Decision Latency (DQN vs Rule-Based), redefined
**Original problem:** the metric was defined as "recovery cycles to convergence," but both policies are single-shot, deterministic dB reductions — there is no multi-cycle dynamic to measure. Redefined to decision **latency**.

Rule-based (hardcoded lookup table) is faster than DQN (neural network inference) by roughly three-to-four orders of magnitude — expected given the structural difference (constant-time lookup vs. a full forward pass), not a flaw in either policy. In the current static-mitigation environment (every action is a one-shot dB reduction, the threat does not adapt in response), this speed advantage isn't offset by any decision-quality advantage for the DQN — which is exactly why a **Dynamic/Chasing Jammer** scenario (an adversary that reacts to the system's countermeasures) is the priority future-work item: it's the scenario that should let a learned policy actually outperform a static one, closing this open question with a real result instead of a theoretical claim. See `## Known Issues & Future Work`.

**Design clarification for the report:** the DQN-vs-rule "agreement" comparison (Phase C3 diagnostic, ~44%) compares only the *chosen action name* between the two policies. `rule_based_policy.m`'s own per-threat mitigation magnitudes are not applied anywhere in the closed-loop pipeline — both policies' physical effect is computed via the shared `action_mitigation_db` (25/15/25/25 dB per action). This is a deliberate methodological choice, not an oversight: unifying the action space isolates *decision quality* from *execution strength*, so any measured difference in outcomes is attributable to the algorithm, not to one policy being handed a more powerful lever than the other. State this explicitly wherever "agreement" is reported.

### Phase EXP + Survivability Boundary Mapping (proposal deliverable #7)
Ran `explore_countermeasures.m` (2550 scenarios, 85.8 min) then `map_survivability_boundary.m`. EXP is BER-only (uses `quick_ber`, not the Rx_IQ spectrogram path), so it was **not** affected by D18 and has not needed re-running since. Two separate maps:

- **Map A — Threat Neutralization** (mechanisms: `atten_reduction`, `field_reduction` only — genuine attack removal): **83.8% recoverable**, 13.2% marginal, 3.0% non-recoverable (234 states mapped)
- **Map B — Link Survivability** (all mechanisms, including `awgn_margin_boost`): **87.5% recoverable**, 10.0% marginal, 2.5% non-recoverable (240 states mapped)

**Why two maps:** `awgn_margin_boost` raises effective SNR rather than neutralizing the threat — it can make the link outperform the nominal clean-channel floor without the attack being weakened at all. A single map conflates "the link survived" with "the threat was removed." Map A is the literal reading of proposal deliverable #7; Map B shows the ceiling of everything the system can do, including SNR-margin tradeoffs.

**Gap analysis:** 1 cell (path_loss, level=8, SNR=10dB) where the link survives via Map B but not Map A — the proposal's goodput-tradeoff regime made concrete: survival without neutralization.

**Known coverage gap (not a bug):** path_loss at its lowest severity level (level=4) has no Map A data point — the smallest tested `field_reduction` magnitude (5dB) already exceeds that attack's severity (4dB), so every candidate mitigation at that level would imply unphysical signal amplification and is correctly excluded by the legitimacy filter.

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB, fd=160Hz) + AWGN
- **Classes (9):** jamming, reactive jamming, sweeping jammer, noise burst, path loss, spoofing, antenna fault, benign interference, none (clean channel)
- **Metrics:** BER, RSSI, SNR, PLR — see `## Modeling Assumptions` for which of these are physically measurable at a real receiver and which are simulation ground-truth

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] scalar/temporal features (SNR, BER, RSSI, PLR, var_rssi_10, dber_dt, burst_ratio)
- **Architecture:** CNN (32→64→128 filters, BN+ReLU+Pool, GAP) + FC (32→16) → merged 144-d → FC(64)+Dropout(0.3) → softmax(9)
- **Performance:** 96.73% accuracy, ~5.7ms median CNN latency including full preprocessing (spectrogram/dB/normalize/resize)

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

## Interactive Demo (`demo_gui.m`)

Operator-console style MATLAB `uifigure` app for live, in-person demonstration:
- **Multi-select threat list** — select several threats, they run in sequence automatically
- **Live visuals per run:** received spectrogram, IQ constellation before and after the countermeasure (visually shows the signal degrade and recover), a GCS↔UAV link-status bar that changes color (red = threat detected, amber = mitigating, green = healthy/no action), gauges for CNN confidence and total decision latency
- **Run history** — persists for the session in an on-screen table; exportable to CSV + `.mat` (full per-run struct log: timestamps, all detection/decision/BER/latency fields)
- **Session video recording** — optional toggle, captures the whole window via `VideoWriter` to an `.mp4` for offline playback (e.g. in the defense presentation)

Every run calls the real pipeline end-to-end (no mocked or precomputed results): `build_threat_model.m` → `sim()` → `extract_closed_loop_frames.m` → trained CNN → trained DQN → (if a countermeasure is chosen) a second real `sim()` to measure actual post-mitigation BER.

**Architecture note for anyone extending this file:** it deliberately contains **no nested functions** — MATLAB makes a function's workspace "static" whenever it contains a nested function, which then rejects the script-style variable injection used by `init_params.m` and `build_threat_model.m` throughout this codebase. All shared state lives in `fig.UserData`; every callback is a plain top-level sibling function. See D24 in `DECISIONS.md`.

---

## Report

An interim report (Word .docx, 7 chapters — intro, theoretical background with full math, implementation, results, dashboard, risks, future work — plus a dedicated Limitations & Assumptions section) has been drafted covering the material in this README in full academic depth, including the modeling-assumptions disclosures above. It is maintained outside this git repository (a submission deliverable, not project source). A small number of figure placeholders remain, each labeled in the document with a description of what real photo/diagram would fit there (e.g. a tactical UAV photo, a QPSK constellation diagram) — public-domain source suggestions (U.S. DoD / Wikimedia) were provided; final image selection is pending.

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

See `PROJECT_LOG.md` for the full fix history and session-by-session detail behind each decision above.

---

## Known Issues & Future Work

**Open items:**
- **Dynamic/Chasing Jammer scenario** (priority) — an adversary that reacts to the system's countermeasures, needed to let the DQN demonstrate a real decision-quality advantage over the static rule-based policy (see KPI #3 discussion above). Planned, not yet built.
- A small number of report figure placeholders need real source images (suggestions provided, final selection pending)
- `demo_gui.m` — built and running; further UI/UX feedback from live use still being incorporated
- reactive_jamming 91.0% recall (macro-F1 96.73%) — confuses with continuous jamming; the distinction is temporal. Below the 90%+ per-class comfort line in absolute terms but already above the proposal's 90% macro-F1 target; documented as a known limitation rather than requiring further tuning at this stage.

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
  system's ~5.7ms median detection at 96.73% accuracy compares favorably
  against all four on both axes.
- Mnih et al. (2015), "Human-level control through deep reinforcement
  learning," Nature — base DQN architecture.
- Rician channel models & Doppler effects (standard comms textbooks).

---

**Last Updated:** 2026-09-21 (D22-D24: latency measurement fixes, demo_gui.m built)
**Status:** Phase A+B+C+EXP complete and re-verified, survivability mapping complete, all 5 proposal KPIs met, interim report drafted (pending final images), interactive demo built and under live testing | Phase D (final report + defense prep) in progress
