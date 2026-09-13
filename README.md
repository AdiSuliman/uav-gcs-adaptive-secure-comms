# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A  
**Students:** Adi Suliman (עדי), Bar Dvir Hassan  
**Supervisor:** Golan Ein-Tzvi  
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + temporal features, 90.9% accuracy, 16.4ms latency)
- Reinforcement learning policy (DQN trained on true Simulink reward, not approximated)
- Adaptive recovery (channel switching, rate reduction, diversity, selectable per threat)
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison

---

## Repository Structure
├── main.m # Master orchestrator (flags for A, B, C phases)
├── init_params.m # System & threat parameters (K=10dB, 160Hz Doppler)
├── models/ # Simulink Digital Twin
│ ├── UAV_GCS_Base_Link.slx # A1-A2: clean AWGN channel
│ ├── UAV_GCS_Rician_Link.slx # A3: fading + Doppler
│ └── UAV_GCS_Threat_Link.slx # A4-A6: threats + recovery
├── docs/
│ └── DECISIONS.md # Architecture Decision Record (D1-D11)
├── README.md # This file
├── ROADMAP.md # Project timeline (original plan)
└── [Phase scripts]
├── A: build_.m, extract_.m, run_sweep.m
├── B: prepare_data.m, train_detector.m, eval_detector.m
└── C: train_dqn.m, rule_based_policy.m, run_closed_loop.m
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
- Phase C2 (DQN train): 20–40 min
- Phase C3 (closed-loop diagnostic): 2–5 min

---

## Latest Results (Sep 13, 2026)

**Phase B3 (9-class CNN):**
- Accuracy: 90.90% | Macro-F1: 90.94%
- CNN latency: 10.6 ms | DQN: 5.84 ms | **Total: 16.4 ms**
- Best classes: noise_burst, antenna_fault, sweeping_jammer (100%)
- Weak classes: jamming (67.3%), spoofing (76.2%)

**Phase C3 (Closed-Loop):**
- Mean recovery: 31.8% (BER reduction)
- Best: path_loss 91.1% | Worst: antenna_fault 5.4%
- DQN-Rule agreement: 1/8 (12.5%)

**Pending:**
- EXP phase analysis (DQN-rule disagreement diagnosis)
- Phase D interim + final report

---

## Architecture

### Digital Twin (Simulink)
- **Transmitter:** QPSK + RRC pulse shaping (sps=4)
- **Channel:** Rician (K=10dB, fd=160Hz) + AWGN
- **Threats (8):** jamming, reactive jamming, spoofing, noise burst, path loss, antenna fault, sweeping jammer, benign interference
- **Metrics:** BER, RSSI, SNR, PLR

### Detection (CNN Hybrid)
- **Input:** [128×128×1] spectrogram + [7-dim] features
- **Architecture:** CNN (64→128 filters, GAP) + FC (32→16) → merged FC → softmax(9)
- **Performance:** 90.90% accuracy, 16.6ms latency

### Decision (DQN v2)
- **State:** [threat_class, BER, SNR, PLR] (5-dim)
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** Real Simulink BER improvement (not approximated)
- **Training:** 400 episodes with ε-decay

### Recovery
- **channel_switch:** Escape narrowband jamming (15dB JSR reduction)
- **rate_reduce:** Trade throughput for robustness (6–9 dB SNR gain)
- **freq_diversity:** Alternate carrier for spoofing (8 dB typical)
- **spatial_diversity:** Antenna array exploitation (12 dB configured)

---

## Design Highlights

See `docs/DECISIONS.md` for full Architecture Decision Record:
- **D1:** Model-based simulation (no SDR hardware)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D8:** Signal-level threat injection (not metric-level)
- **D11:** System Objects engine (replaced commfilt2 ISI floor)

---

## Known Issues & Future Work

**Known Limitations:**
- Antenna fault recovery: 5.4% (12dB spatial insufficient vs 30dB fault)
- Noise burst latency outlier: 57.5ms (needs isolated rerun)
- Reactive jamming CNN misdetection: 71.2% confusion with spoofing

**Future:**
- Sim-to-real validation (SDR testbed)
- Multi-threat scenarios
- Online reinforcement learning
- FPGA/GPU acceleration

---

**Last Updated:** 2026-09-13  
**Status:** Phase A+B+C complete | EXP pending | Phase D preparation
