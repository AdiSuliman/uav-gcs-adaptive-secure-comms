# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A  
**Students:** Adi Suliman (עדי), Bar Dvir Hassan  
**Supervisor:** Golan Ein-Tzvi  
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + temporal features, 90.9% accuracy, ~7-10ms latency)
- Reinforcement learning policy (DQN trained on true Simulink reward, not approximated), with reward shaping so the agent correctly withholds action on non-hostile interference (benign_interference → no_action)
- Adaptive recovery (channel switching, rate reduction, diversity), with magnitudes empirically validated against a dedicated countermeasure-exploration sweep (EXP phase)
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison

---

## Repository Structure

```
├── main.m                        # Master orchestrator (flags for A, B, C phases)
├── init_params.m                 # System & threat parameters (K=10dB, 160Hz Doppler)
├── models/                       # Simulink Digital Twin
│   ├── UAV_GCS_Base_Link.slx     # A1-A2: clean AWGN channel
│   ├── UAV_GCS_Rician_Link.slx   # A3: fading + Doppler
│   └── UAV_GCS_Threat_Link.slx   # A4-A6: threats + recovery
├── docs/
│   └── DECISIONS.md              # Architecture Decision Record (D1-D11)
├── README.md                     # This file
├── PROJECT_LOG.md                # Living execution log — status, fix history, open issues
├── ROADMAP.md                    # Project timeline (original plan)
└── [Phase scripts]
    ├── A: build_*.m, extract_*.m, run_*_sweep.m
    ├── B: prepare_data.m, train_detector.m, eval_detector.m
    ├── C: train_dqn.m, rule_based_policy.m, run_closed_loop_*.m
    └── EXP: explore_countermeasures.m, analyze_exploration_results.m
```

**Note:** `data/`, `results/`, `logs/` are `.gitignore`'d (too large / regenerable).

---

## Quick Start

1. **Setup:** MATLAB R2026a with Communications, Deep Learning, RL toolboxes
2. **Run:** `main.m` — toggle RUN flags to control which phases execute
3. **Explore:** `logs/run_*.txt` accumulates full console output

**Phases & runtimes:**
- Phase A (link + dataset): 10–60 min
- Phase B (detector train): 5–15 min
- Phase C1 (rule-based): < 1 min
- Phase C2 (DQN train): ~10-15 min (550 episodes, includes 3x oversampling of benign_interference)
- Phase C3 (closed-loop diagnostic): 2–5 min
- Phase EXP (deep countermeasure exploration): ~75 min, run rarely

---

## Latest Results (Sep 13, 2026)

**Phase B3 (9-class CNN):**
- Accuracy: 90.90% | Macro-F1: 90.94%
- Mean latency: CNN 7.3 ms + DQN 4.2 ms = **~11.5 ms total**
- Best classes: noise_burst, antenna_fault, sweeping_jammer (100%)
- Weak classes: jamming (67.3%), spoofing (76.2%)

**Phase C3 (Closed-Loop, post-fix):**
- Mean recovery: **40.8%** (honest figure — no threat gets credited for unnecessary action)
- Best: jamming 68.8% | Worst: antenna_fault 19.4%
- benign_interference correctly resolves to `no_action` (DQN agrees with rule-based policy)
- DQN-Rule agreement: 1/8 — remaining disagreements are cosmetic (see Design Notes below)

**Phase EXP (countermeasure exploration):**
- Validated that stronger mitigation magnitudes (up to 25dB) recover far more BER than the original conservative defaults — this directly drove the C2/C3 magnitude fix below
- antenna_fault's poor recovery was **not** a physical limit — it was an underpowered mitigation setting

**Resolved this session:**
- antenna_fault recovery: 5.4% → 19.4% (magnitude fix)
- benign_interference reward gap: fixed via reward shaping + train/inference state-mismatch fix + 3x oversampling

**Still open (see PROJECT_LOG.md for full detail):**
- noise_burst latency outlier (varies 42-75ms across runs vs 5-12ms for other threats — reproducibility under investigation)
- reactive_jamming CNN misdetection (71.2% confidence → classified as spoofing)

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB, fd=160Hz) + AWGN
- **Threats (8):** jamming, reactive jamming, spoofing, noise burst, path loss, antenna fault, sweeping jammer, benign interference
- **Metrics:** BER, RSSI, SNR, PLR

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] scalar/temporal features
- **Architecture:** CNN (64→128 filters, GAP) + FC (32→16) → merged FC → softmax(9)
- **Performance:** 90.90% accuracy, ~7ms inference

### Decision (DQN)
- **State:** [threat_class, BER, RSSI, SNR, PLR] (5-dim) — real measured values at both train and inference time (train/inference mismatch fixed Sep 13)
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** Real Simulink BER improvement, with a false-alarm penalty shaping term for benign_interference (D9: non-hostile interference should not trigger a countermeasure)
- **Training:** 550 episodes (benign_interference oversampled 3x to counter reward-scale imbalance — see PROJECT_LOG.md), ε-decay

### Recovery — mitigation magnitudes (validated via EXP phase)
- **channel_switch / freq_diversity:** 25 dB reduction (frequency-avoidance-type mitigation)
- **rate_reduce:** 15 dB reduction (robust-modulation/FEC-type mitigation)
- **spatial_diversity:** 25 dB reduction (antenna-diversity/backup-path-type mitigation)
- A physical floor prevents `path_loss_db`/`fault_atten_db` from going negative (unphysical signal amplification) under strong mitigation

**Design note:** in the current implementation, all four non-zero actions apply the same operation (subtract their assigned dB value from the threat's own severity field) — they differ only in assigned magnitude, not mechanism. Most residual "DQN vs rule-based disagreement" is therefore cosmetic (the two choices are functionally equivalent), except where it actually changes behavior — e.g. benign_interference, where the correct choice (no_action) is now reliably learned.

---

## Design Highlights

See `docs/DECISIONS.md` for full Architecture Decision Record:
- **D1:** Model-based simulation (no SDR hardware)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D8:** Signal-level threat injection (not metric-level)
- **D9:** Non-hostile faults (antenna_fault, path_loss, benign_interference) deliberately included so the system learns to distinguish real attacks from benign/faulty conditions
- **D11:** System Objects engine (replaced commfilt2 ISI floor)

See `PROJECT_LOG.md` for the full fix history (3 DQN training iterations, root-cause analysis, and EXP-phase findings behind each design decision above).

---

## Known Issues & Future Work

**Open issues (see PROJECT_LOG.md for details):**
- Noise burst latency outlier (magnitude inconsistent across runs — needs isolated repeated-trial verification)
- Reactive jamming CNN misdetection: 71.2% confidence confusion with spoofing (unaffected by any DQN-side fix; likely spectral overlap or insufficient training samples)

**Future work:**
- Sim-to-real validation (SDR testbed)
- Multi-threat scenarios
- Online reinforcement learning
- FPGA/GPU acceleration

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
- Mnih et al. (2015), "Human-level control through deep reinforcement
  learning," Nature — base DQN architecture.
- Rician channel models & Doppler effects (standard comms textbooks).

---

**Last Updated:** 2026-09-13  
**Status:** Phase A+B+C+EXP complete | 2 of 4 known issues open | Phase D preparation
