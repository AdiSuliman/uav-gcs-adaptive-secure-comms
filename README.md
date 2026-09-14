# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A  
**Students:** Adi Suliman, Bar Dvir Hassan  
**Supervisor:** Golan Ein-Tzvi  
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + temporal features, 90.9% accuracy, ~7-10ms latency)
- Reinforcement learning policy (DQN trained on true Simulink reward, not approximated), with reward shaping so the agent correctly withholds action on non-hostile interference (benign_interference → no_action, none → no_action)
- Adaptive recovery (channel switching, rate reduction, diversity), with magnitudes empirically validated against a dedicated countermeasure-exploration sweep (EXP phase)
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison, reward-table variance verification, latency root-cause isolation

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
│   └── DECISIONS.md              # Architecture Decision Record (D1-D12)
├── diagnostics/                  # Ad-hoc investigation scripts, kept for reproducibility
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
- Phase C2 (DQN train): ~10-15 min (450+ episodes; benign_interference, none, and antenna_fault oversampled 3x each)
- Phase C3 (closed-loop diagnostic): 2–5 min
- Phase EXP (deep countermeasure exploration): ~75 min, run rarely

---

## Latest Results (2026-09-14)

**Phase B3 (9-class CNN):**
- Accuracy: 90.90% | Macro-F1: 90.94%
- Mean latency: CNN 9.3 ms + DQN 4.6 ms = ~14.0 ms | **Median latency: CNN 7.3 ms + DQN 3.1 ms = ~10.3 ms** (median added 09-14; more representative of typical per-decision latency — see Known Issues for why mean runs higher)
- Best classes: noise_burst, antenna_fault, sweeping_jammer (100%)
- Weak classes: jamming (67.3%), spoofing (76.2%, still open — see Known Issues)

**Phase C3 (Closed-Loop, post-fix, verified stable across 2 independent re-runs):**
- Mean recovery: **36.9-38.1%**
- Best: jamming 67.7% | Worst: sweeping_jammer 25.2%
- antenna_fault: 19-20% recovery, DQN agrees with rule-based policy (spatial_diversity)
- benign_interference and none both correctly resolve to `no_action`
- DQN-Rule agreement: 5/9 (55.6%) — remaining disagreements are cosmetic (see Design Notes below)

**Phase EXP (countermeasure exploration):**
- Validated that stronger mitigation magnitudes (up to 25dB) recover far more BER than the original conservative defaults — this directly drove the C2 magnitude fix
- antenna_fault's poor recovery was **not** a physical limit — it was an underpowered mitigation setting (later, a separate learned-ranking bug was also found and fixed — see PROJECT_LOG.md)

**Resolved 2026-09-13:**
- antenna_fault recovery: 5.4% → 20.2% (magnitude fix)
- benign_interference reward gap: fixed via reward shaping + train/inference state-mismatch fix + 3x oversampling
- reactive_jamming CNN misdetection: was a single-sample false alarm, not systematic (88.9% recall on full test set)

**Resolved 2026-09-14:**
- antenna_fault Q-value bleed (encoding adjacency to benign_interference's penalized code) + ranking inversion (insufficient training episodes) — both fixed via threat_encode reassignment and 3x oversampling; DQN-Rule agreement 22.2% → 55.6%, confirmed stable across 2 independent re-runs
- noise_burst latency outlier — confirmed as a test-harness artifact (spike tied to sequential loop position, approx. every 4th predict() call — reproduced moving to a different threat when loop order changed), not threat-specific and not representative of real deployed latency; median latency reporting added

**Still open (see PROJECT_LOG.md for full detail):**
- Spoofing 3-way confusion (53.0% recall) — genuine feature-space overlap with jamming/reactive_jamming/benign_interference, documented as a known limitation (docs/DECISIONS.md D12)

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB, fd=160Hz) + AWGN
- **Classes (9):** jamming, reactive jamming, spoofing, noise burst, path loss, antenna fault, sweeping jammer, benign interference, none (clean channel)
- **Metrics:** BER, RSSI, SNR, PLR

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] scalar/temporal features
- **Architecture:** CNN (64→128 filters, GAP) + FC (32→16) → merged FC → softmax(9)
- **Performance:** 90.90% accuracy, ~7ms inference

### Decision (DQN)
- **State:** [threat_class, BER, RSSI, SNR, PLR] (5-dim) — real measured values at both train and inference time (train/inference mismatch fixed 09-13)
- **Threat encoding:** explicit 9-value assignment (not naive 0-8 ordinal) — antenna_fault deliberately placed at maximum encoding distance from the penalized benign_interference/none classes to prevent Q-value bleed between adjacent codes (fixed 09-14, see PROJECT_LOG.md)
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** Real Simulink BER improvement, with a false-alarm penalty shaping term for benign_interference and none (D9: non-hostile/no-threat conditions should not trigger a countermeasure)
- **Training:** benign_interference, none, and antenna_fault oversampled 3x (see PROJECT_LOG.md for why each needed it), ε-decay

### Recovery — mitigation magnitudes (validated via EXP phase)
- **channel_switch / freq_diversity:** 25 dB reduction (frequency-avoidance-type mitigation)
- **rate_reduce:** 15 dB reduction (robust-modulation/FEC-type mitigation)
- **spatial_diversity:** 25 dB reduction (antenna-diversity/backup-path-type mitigation)
- A physical floor prevents `path_loss_db`/`fault_atten_db` from going negative (unphysical signal amplification) under strong mitigation

**Design note:** in the current implementation, the four non-zero actions apply the same operation (subtract their assigned dB value from the threat's own severity field) — they differ only in assigned magnitude, not mechanism. Most residual DQN-vs-rule-based disagreement is therefore cosmetic (the two choices are functionally near-equivalent). This is separate from the antenna_fault Q-value bug found and fixed on 09-14, which was a genuine learned-ranking error, not a labeling mismatch.

---

## Design Highlights

See `docs/DECISIONS.md` for full Architecture Decision Record:
- **D1:** Model-based simulation (no SDR hardware)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D8:** Signal-level threat injection (not metric-level)
- **D9:** Non-hostile faults (antenna_fault, path_loss, benign_interference, none) deliberately included so the system learns to distinguish real attacks from benign/faulty/clean conditions
- **D11:** System Objects engine (replaced commfilt2 ISI floor)
- **D12:** Spoofing 3-way confusion documented as a known limitation, not retrained (see PROJECT_LOG.md)

See `PROJECT_LOG.md` for the full fix history (5 DQN training iterations, root-cause analysis, and EXP-phase findings behind each design decision above).

---

## Known Issues & Future Work

**Open issues (see PROJECT_LOG.md for details):**
- Spoofing 3-way confusion with jamming/reactive_jamming/benign_interference (53.0% recall) — genuine feature-space overlap, documented as a known limitation rather than retrained

**Future work:**
- Sim-to-real validation (SDR testbed)
- Multi-threat scenarios
- Online reinforcement learning
- FPGA/GPU acceleration
- Dashboard (proposal deliverable, not yet started)
- Survivability-boundary mapping (proposal deliverable, not yet started)

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

**Last Updated:** 2026-09-14  
**Status:** Phase A+B+C+EXP complete | 1 of 5 known issues open | Phase D preparation
