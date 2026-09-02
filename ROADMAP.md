# UAV-GCS Adaptive Secure Communications System — Project Roadmap

**Project:** AI-driven adaptive communication security for UAV-to-ground station links in electronic warfare environments.  
**Platform:** MATLAB R2026a + Simulink  
**Supervisor:** Golan Ein-Tzvi  
**Deliverable Deadline:** End of semester (A')

---

## Phase A: Link Model & Dataset Generation

### Phase A1-A2: AWGN Validation [COMPLETE] ✅
**Objective:** Build and validate the clean link engine against QPSK theory.

- [x] Build programmable link model (Tx → AWGN → Rx → BER calculation)
- [x] Implement Eb/No sweep (0–10 dB)
- [x] Compare measured BER to berawgn theoretical curve
- [x] Verify engine accuracy (< 5% deviation across sweep)
- [x] Code documentation (active/future component flags)
- [x] Git commit & GitHub push

**Key Result:** Engine verified — ready for Rician + synchronization.

---

### Phase A3: Rician Channel + Synchronization [TODO] ⏳
**Objective:** Add realistic channel model and symbol timing recovery.

- [ ] Add Rician fading channel (K=10 dB, Rayleigh envelope)
- [ ] Implement symbol timing synchronizer block
- [ ] Implement phase/frequency recovery
- [ ] Validate new BER curve against Rician theory
- [ ] Document synchronization latency impact
- [ ] Git commit

**Estimated Duration:** 1 week  
**Dependency:** A1-A2 complete

---

### Phase A4: Threat Injection Module [TODO] ⏳
**Objective:** Add five threat classes to the link model (modular, scalable).

Threat Classes:
- Jamming (narrowband, wideband)
- Spoofing (frequency/timing offset)
- Noise Burst (transient interference)
- Antenna Fault (simulated path loss spike)
- Path Loss (distance-dependent attenuation)

- [ ] Build threat injection subsystem (Simulink)
- [ ] Parametrize each threat class
- [ ] Generate self-labeled dataset (threat class ground truth)
- [ ] Validate that clean link recovers under no threat
- [ ] Git commit

**Estimated Duration:** 1 week  
**Dependency:** A3 complete

---

### Phase A5-A6: Dataset & Detection [TODO] ⏳
**Objective:** Generate balanced dataset and train CNN/LSTM detector.

- [ ] Run dataset generation (1000+ frames per threat, per SNR point)
- [ ] Balance classes (oversample rare threats)
- [ ] Train CNN/LSTM on [RSSI, BER, PLR, SNR] over sliding window
- [ ] Measure accuracy, macro-F1, confusion matrix vs SNR
- [ ] Validate anomaly detection (OoD handling)
- [ ] Git commit

**Estimated Duration:** 2 weeks  
**Dependency:** A4 complete

---

## Phase B: Detection & Decision Layer (Offline)

### Phase B1-B2: Rule-Based Baseline + DQN [TODO] ⏳
**Objective:** Implement decision logic (rule-based MVP + deep Q-learning agent).

- [ ] Rule-based policy (if-then thresholds on detector output)
- [ ] DQN agent with state = detector features, action = link recovery action
- [ ] Compare rule-based vs DQN: convergence, reward, false-positive rate
- [ ] Generate regime map (recoverable vs non-recoverable regions)
- [ ] Git commit

**Estimated Duration:** 2 weeks  
**Dependency:** A5-A6 complete

---

## Phase C: Closed-Loop System & Dashboard (Online)

### Phase C1-C2: Closed-Loop Integration [TODO] ⏳
**Objective:** Integrate detection + decision in real-time loop with dashboard.

- [ ] Build closed-loop Simulink model (detect → decide → recover → measure)
- [ ] Implement adaptive actions (channel switch, bit rate, diversity)
- [ ] Create real-time dashboard (RSSI, BER, PLR, SNR, action log)
- [ ] Test survivability: BER improvement under each threat
- [ ] End-to-end validation
- [ ] Git commit

**Estimated Duration:** 1 week  
**Dependency:** B1-B2 complete

---

## Phase D: Reports, Defense, Poster

### Phase D1: Interim Report [TODO - Due: End of Summer]
- [ ] Write sections: intro, system architecture, A1-A3 results, methodology
- [ ] Include BER validation plots, Rician channel performance
- [ ] Document risk mitigation (sycnhronization, dataset balance)

### Phase D2: Final Report [TODO - Due: End of Semester]
- [ ] Complete sections: D, E (detection), F (decision + DQN), G (closed-loop)
- [ ] Include regime map (research contribution)
- [ ] Comparison: rule-based vs DQN performance
- [ ] Discussion: sim-to-real gap, future work

### Phase D3: Defense [TODO - 20+10 min, English, 10 slides]
- [ ] Prepare slides: motivation, architecture, key results, lessons learned
- [ ] Practice Q&A: synchronization, spoofing realism, DQN convergence

### Phase D4: Poster [TODO - 5% grade]
- [ ] Summarize project visually

---

## Key Milestones & Timeline

| Phase | Status | Start | End | Notes |
|---|---|---|---|---|
| A1-A2 (AWGN) | ✅ Complete | Sept 1 | Sept 8 | Engine verified |
| A3 (Rician+Sync) | ⏳ In Progress | Sept 9 | Sept 15 | Sync is critical |
| A4 (Threats) | 🔄 Queued | Sept 16 | Sept 22 | Modular injection |
| A5-A6 (Dataset+Det) | 🔄 Queued | Sept 23 | Oct 7 | Heavy training |
| B (Decision) | 🔄 Queued | Oct 8 | Oct 22 | Rule + DQN |
| C (Closed-Loop) | 🔄 Queued | Oct 23 | Oct 29 | Integration |
| D (Reports) | 🔄 Queued | Oct 30 | Nov 30 | Interim + Final |

---

## Risk Mitigation

See proposal document (Section IX) for detailed risk analysis. Key mitigations:
- **DQN convergence:** Use rule-based MVP as fallback
- **Dataset imbalance:** Class weights + oversampling
- **Synchronization latency:** Document impact, plan for A3
- **Sim-to-real gap:** Design for modular threat injection (enables custom validation)

---

## Notes

- All code in GitHub (per requirement §31)
- Memory-efficient dataset generation (chunks + v7.3 HDF5)
- Every phase produces Git commits with clear messages
- Active/future component flags in params.m clarify what's working now vs what's coming
