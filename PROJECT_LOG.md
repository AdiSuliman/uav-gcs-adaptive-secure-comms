# Project Execution Log (Living Document)

**Last Updated:** 2026-09-13 | **Status:** Phase A+B+C complete

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
| B3 (9-class) | ✅ | **90.90%** | 2026-09-13 | +sweeping_jammer, +benign_interference |

**Key Finding:** jamming 67.3%, spoofing 76.2% weak; noise_burst, antenna_fault, sweeping (100%).

---

## Phase C: Recovery & Closed-Loop ✅ COMPLETE

### C1: Rule-Based Policy ✅

### C2: DQN Agent (v2) ✅
- **Reward Table:** Real Simulink-measured (40 combos)
- **Training:** 400 episodes, ε decay 1.0→0.01
- **Result:** Reward converged 35-47% per threat

### C3: Closed-Loop Diagnostics ✅

**Per-Threat Summary:**
| Threat | CNN Latency | DQN Latency | Recovery | DQN-Rule Agree |
|---|---|---|---|---|
| jamming | 10.38ms | 4.40ms | 30.0% | ❌ |
| reactive_jamming | 7.08ms | 2.73ms | 32.7% | ❌ CNN: 71.2% spoofing |
| sweeping_jammer | 7.46ms | 4.54ms | 14.5% | ❌ |
| **noise_burst** | **36.13ms** | **21.37ms** | 18.9% | ✓ **OUTLIER** |
| **path_loss** | 10.32ms | 6.33ms | **91.1%** | ❌ DQN better |
| spoofing | 5.81ms | 2.39ms | 40.8% | ❌ |
| antenna_fault | 3.72ms | 2.22ms | **5.4%** | ❌ Worst |
| benign_interference | 3.88ms | 2.71ms | 21.3% | ❌ |

**Mean latency:** 10.60ms (CNN) + 5.84ms (DQN) = **16.44ms** ✅ real-time capable

---

## Phase EXP: Deep Exploration (Pending)

- [ ] Analyze DQN-Rule disagreement (why only 1/8 agreement?)
- [ ] Isolated rerun of noise_burst (57.5ms latency anomaly)
- [ ] CNN misdetection root cause (reactive_jamming vs spoofing spectral overlap)

---

## Phase D: Documentation & Defense (Pending)

- [ ] Interim Report (due end of summer)
- [ ] Final Report (due end of semester)
- [ ] Defense: 20+10 min, 10 slides
- [ ] Poster: 5% grade

---

## Known Issues & Limitations

1. **Antenna Fault Recovery (5.4%):** Spatial diversity (12dB) insufficient vs 30dB fault attenuation. Known limitation; would require TX power adjustment.
2. **Reactive Jamming Misdetection (71.2%):** CNN confuses ~30% with spoofing. Likely spectral overlap in Rician+reactive waveforms.
3. **Noise Burst Latency (57.5ms):** 3-5× other threats. Suspected JIT warm-up artifact. Need isolated rerun.
4. **DQN-Rule Disagreement (12.5%):** Not necessarily bad (path_loss 91% is better). Needs EXP analysis.

---

## Git Snapshots

| Commit | Phase | Date | Status |
|---|---|---|---|
| 2f8f5d3 | B3+C3 | 2026-09-13 | Phase B+C2+C3: 9-class CNN, DQN v2 retrain, diagnostics |
| (next) | README+LOG | TBD | Expand documentation + live log |

---

**Next Steps:**
1. Run EXP phase → analyze DQN-rule, antenna_fault
2. Fix/explain noise_burst latency
3. Write Phase D reports

