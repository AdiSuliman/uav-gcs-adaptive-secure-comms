# Project Execution Log (Living Document)

**Last Updated:** 2026-09-13 | **Status:** Phase A+B+C complete, pending Phase D & EXP analysis

---

## Phase A: Link Model & Dataset ✅ COMPLETE

| Step | Status | Date | Notes |
|---|---|---|---|
| A0 | ✅ | 2026-08-15 | Params initialized, GitHub repo created |
| A1-A2 | ✅ | 2026-08-20 | AWGN link: BER match theory, ratio 0.99-1.01 |
| A3 | ✅ | 2026-08-28 | Rician K=10dB, fd=160Hz: degradation 1.53× (42.7% vs theory) |
| A4 | ✅ | 2026-09-02 | 6+2 threats (barrage, reactive, spoofing, noise, path, antenna, sweeping, benign) validated |
| A5-A6 | ✅ | 2026-09-05 | Dataset: 10,686 frames, spectrograms [128×128×1] extracted |

---

## Phase B: Detection ✅ COMPLETE (updated)

| Step | Status | Date | Accuracy | Notes |
|---|---|---|---|---|
| B1 | ✅ | 2026-09-08 | — | Data split 80/10/10, z-scored 7 features |
| B2 (v1) | ✅ | 2026-09-09 | 78.8% | CNN+scalar hybrid, 7 classes |
| B2.5 | ✅ | 2026-09-10 | — | Added temporal features (var_rssi_10, dber_dt, burst_ratio) |
| B2 (v2, retrain) | ✅ | 2026-09-11 | 92.13% | With 7 features, reactive_jamming fixed 7.2%→85.5% |
| B3 (9-class) | ✅ | 2026-09-13 | **90.90%** | Expanded: +sweeping_jammer, +benign_interference |

**Key Finding:** jamming (67.3%), spoofing (76.2%) still weak; noise_burst, antenna_fault, sweeping (100%).

---

## Phase C: Recovery & Closed-Loop ✅ COMPLETE (with diagnostics)

### C1: Rule-Based Policy ✅

### C2: DQN Agent (v2) ✅ — 2026-09-13
- **Reward Table:** Real Simulink-measured (40 combos, not approximated)
- **Training:** 400 episodes, ε decay 1.0→0.01
- **Result:** Reward converged to 35-47% (mean 31.8% per threat)
- **Issue:** Only 1/8 DQN-Rule agreement (12.5%) — **flagged for analysis**

### C3: Closed-Loop Diagnostics ✅ — 2026-09-13
**Full decision trace with timing:**

| Threat | CNN Latency | DQN Latency | Total | Recovery | DQN-Rule Agree | Notes |
|---|---|---|---|---|---|---|
| jamming | 10.38ms | 4.40ms | 14.78ms | 30.0% | ✗ | DQN chose rate_reduce, not channel_switch |
| reactive_jamming | 7.08ms | 2.73ms | 9.81ms | 32.7% | ✗ | CNN: 71.2% spoofing (misdetect) |
| sweeping_jammer | 7.46ms | 4.54ms | 12.00ms | 14.5% | ✗ | DQN underperforms |
| **noise_burst** | **36.13ms** | **21.37ms** | **57.50ms** | 18.9% | ✓ | **OUTLIER — latency 3-5× others!** |
| **path_loss** | 10.32ms | 6.33ms | 16.66ms | **91.1%** | ✗ | **DQN beats rule!** channel_switch vs rate_reduce |
| spoofing | 5.81ms | 2.39ms | 8.21ms | 40.8% | ✗ | CNN: 61.3% confidence, 39% jamming confusion |
| antenna_fault | 3.72ms | 2.22ms | 5.94ms | **5.4%** | ✗ | **Worst recovery** — 12dB spatial insufficient |
| benign_interference | 3.88ms | 2.71ms | 6.59ms | 21.3% | ✗ | DQN: rate_reduce, not no_action |

**Mean latency:** 10.60ms (CNN) + 5.84ms (DQN) = **16.44ms total** ✅ real-time capable.

---

## Phase EXP: Deep Exploration (Pending)

- [ ] Analyze DQN-Rule disagreement: why only 1/8 agreement?
  - Is DQN finding better strategies (path_loss 91% supports this)?
  - Or is reward shaping broken (antenna_fault 5.4% suggests this)?
- [ ] Isolated rerun of noise_burst to check 57.5ms latency anomaly
- [ ] CNN misdetection root cause: reactive_jamming vs spoofing spectral overlap?

---

## Phase D: Documentation & Defense (Pending)

- [ ] Interim Report (due end of summer): A+B results
- [ ] Final Report (due end of semester):  Full A→B→C→D with analysis
- [ ] Defense: 20+10 min, 10 slides
- [ ] Poster: 5% grade

---

## Known Issues & Limitations

1. **Antenna Fault Recovery (5.4%):** Spatial diversity (12dB configured) insufficient vs 30dB fault attenuation. Listed as known limitation; would require active TX power adjustment (out of scope).
2. **Reactive Jamming Misdetection (71.2% → spoofing):** CNN confused ~30% of time. Root cause likely: spectral overlap in Rician+reactive waveforms. Fix: retrain B with more reactive samples or augmentation.
3. **Noise Burst Latency (57.5ms):** 3-5× other threats. Suspected JIT warm-up artifact or DQN state-prep overhead. Need isolated rerun to confirm.
4. **DQN-Rule Disagreement (12.5%):** Needs EXP analysis. Not necessarily bad (path_loss 91% is better), but unexplained divergence raises Q-learning design questions.

---

## Commits & Snapshots

| Commit | Date | Phase | Status |
|---|---|---|---|
| d916454 | 2026-09-13 | A+B+C2 | Phase A+B+C2 complete: all MATLAB scripts, datasets, models, results. CNN 92.13%, DQN 300 ep. |
| 2f8f5d3 | 2026-09-13 | B3+C3 | Phase B+C2+C3 complete: 9-class detector, DQN v2 retrain, diagnostic reports |
| (pending) | — | EXP+D | After EXP analysis, commit final documentation |

---

**Next Steps:**
1. Run EXP phase (analyze DQN-rule, antenna_fault reward shaping)
2. Fix/explain noise_burst latency
3. Consider B3 retrain if reactive_jamming misdetection is critical
4. Write Phase D interim report

