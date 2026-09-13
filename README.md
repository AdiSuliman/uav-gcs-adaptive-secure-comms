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


**Note:** `data/`, `results/`, `logs/` are `.gitignore`'d (too large / regenerable). Clone + run `main.m` to rebuild.

---

## Quick Start

1. **Setup:** MATLAB R2026a with Communications, Deep Learning, Reinforcement Learning toolboxes
2. **Run:** `main.m` — toggle RUN flags A/B/C/EXP to control which phases execute
3. **Explore:** `logs/run_*.txt` accumulates full console output; `results/` holds plots & reports

**Stages & approximate runtimes:**
- **Phase A** (link + dataset): 10–60 min (depends on A5-A6 frame count)
- **Phase B** (detector train): 5–15 min
- **Phase C1** (rule-based): < 1 min
- **Phase C2** (DQN train): 20–40 min (400 episodes)
- **Phase C3** (closed-loop diagnostic): 2–5 min

---

## Latest Results (Sep 13, 2026)

**Phase B3 (9-class CNN):**  
- Accuracy: 90.90% | Macro-F1: 90.94%
- CNN latency: 10.6 ms | DQN latency: 5.84 ms | Total: 16.4 ms
- Weakest classes: jamming (67.3%), spoofing (76.2%)
- Perfect classes: noise_burst, antenna_fault, sweeping_jammer (100%)

**Phase C3 (Closed-Loop Diagnostics):**  
- Mean recovery: 31.8% (BER reduction)
- Best: path_loss 91.1% | Worst: antenna_fault 5.4%
- DQN-Rule agreement: 1/8 (12.5%) — flagged for analysis
- Known issue: noise_burst latency outlier (57.5ms) — needs isolated rerun

**Pending:**
- Fix reactive_jamming CNN misdetection (71.2% confusion with spoofing)
- EXP phase deep analysis (DQN-rule disagreement, reward shaping)
- Phase D: interim + final report

---

## Architecture Highlights

### Digital Twin (Simulink)
- **Transmitter:** QPSK mod + RRC pulse shape (sps=4, rolloff=0.25)
- **Channel:** Rician fading (K=10dB, fd=160Hz, 20 m/s UAV) + AWGN
- **Threats (8 classes):** barrage jamming, reactive jamming, spoofing, noise burst, path loss, antenna fault, benign interference, + clean (none)
- **Metrics:** BER, RSSI, SNR, PLR (recomputed per frame)

### Detection (Hybrid CNN)
- **Input:** [128×128×1] spectrogram + [7-dim] feature vector (SNR, BER, RSSI, PLR, temporal)
- **Architecture:** CNN branch (3 conv + GAP) || FC branch → merged FC layers → softmax(9)
- **Training:** 80/10/10 split, z-scored features, class weights, ~30 epochs

### Decision (DQN v2)
- **State:** [threat_class, BER, SNR, PLR]
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}
- **Reward:** measured ΔBER per threat (real Simulink runs, not approximated)
- **Training:** 400 episodes, ε-greedy decay, replay buffer (10k), batch size 32

### Recovery (Adaptive Countermeasures)
- **Channel switch:** escape narrowband jamming (JSR –5 dB improvement)
- **Rate reduce:** trade throughput for robustness against noise/bursts (6–9 dB gain)
- **Freq diversity:** alternate carrier for spoofing/reactive jam (8 dB typical)
- **Spatial diversity:** exploit antenna array (limited by antenna_fault severity)

---

## Key Design Decisions

See `docs/DECISIONS.md` for full ADR. Highlights:
- **D1:** Model-based simulation (no SDR hardware, self-generated labeled data)
- **D2:** All-in MATLAB/Simulink (RF modeling + RL Toolbox, no Python bridge)
- **D3:** Small UAV, 2.4 GHz ISM, short-range LoS
- **D8:** Signal-level threat injection (waveforms, not metrics)
- **D11:** System Objects engine (replaced commfilt2 ISI floor with clean math)

---

## Future Work

1. **Sim-to-real:** Validate on SDR testbed (BladeRF, USRP, Crackle)
2. **Multi-threat:** simultaneous jamming + spoofing scenarios
3. **Protocol layer:** MITM detection, CRC/authentication
4. **Reinforcement:** curriculum learning on threat severity, online adaptation
5. **Hardware:** closed-loop FPGA/GPU accelerator for live GCS integration

---

## References

- Liu et al. (2024): "Smart Jamming Detection in UAV Control Links"
- Yuan et al. (2023): "Reactive Jamming Strategies and Detection"
- Rician channel models & Doppler effects (analog/digital comms textbooks)
- DQN reference: Mnih et al. (2015) Nature

---

**Last Updated:** 2026-09-13 (Phase B+C2+C3 checkpoint)
