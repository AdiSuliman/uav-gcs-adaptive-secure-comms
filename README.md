# UAV-GCS Adaptive Secure Communications System

**Course:** 50076 (HIT) Capstone | **Semester:** 2026-27 A
**Students:** Adi Suliman, Bar Dvir Hassan
**Supervisor:** Golan Ein-Tzvi
**Language:** MATLAB R2026a + Simulink

---

## Overview

An AI-driven closed-loop system for detecting and adapting to link-layer threats (jamming, spoofing, noise, faults) on small-UAV-to-GCS RF links. **Digital Twin approach:** Simulink-based link model self-generates labeled datasets; CNN detector identifies threats in real time; DQN agent decides recovery actions; closed-loop validates BER improvement.

**Key Contributions:**
- Real-time threat detection (CNN + scalar/temporal features, **96.41% accuracy** on a speed-diverse dataset covering a continuous **50–120 km/h** UAV envelope, ~11 ms median decision latency including full signal preprocessing)
- Reinforcement-learning policy (DQN) trained on a reward table measured through the real link over every threat × action × Eb/N0, pricing each action's goodput and spectrum cost and penalizing only unnecessary actions — **0 false alarms** on healthy links, justified action on degraded ones (D29)
- Adaptive recovery (channel switching, rate reduction, frequency / spatial diversity) modeled by the physics of each action on each threat group — in-channel, swept, broadband, signal-side (`apply_countermeasure.m`, D28)
- Survivability boundary mapping (proposal deliverable #7) on the system's real action set: where each attack is recoverable, marginal or not, which action achieves it, and where survival requires giving up goodput (D30)
- Diagnostic suite: decision traces, timing breakdown, rule-based vs learned-policy comparison, FAR measurement, KPI aggregation
- Interactive operator console (`demo_gui.m`, v3): four tabs — live operations (threat × Eb/N0 × UAV speed × severity matrix, DQN vs rule-based side by side, BER/RSSI timeline before/after the countermeasure, UNKNOWN-threat handling), KPI & results, survivability map, session log
- Speed-robustness evaluation (`eval_speed_robustness.m`): closed-loop detection, decision and recovery over 8 UAV speeds (50–120 km/h) — 98.6% detection, 0 false alarms, recovery vs clean flat at 82.5–84.7%
- Interim report (Word, 7 chapters + limitations/assumptions section) drafted; see `## Report` below

---

## Repository Structure

```
├── main.m                        # Master orchestrator (RUN flags across phases A-DASH; adds legacy/ to the path)
├── init_params.m                 # System & threat parameters (K=10dB; UAV envelope 50–120 km/h → Doppler 111–267 Hz, nominal 72 km/h = 160 Hz; D25)
├── build_dqn_state.m             # Single source of truth: 13-dim one-hot DQN state
├── demo_gui.m                    # Interactive operator console, 4 tabs (D24 architecture, D26 v3)
├── build_kpi_dashboard.m         # 7-panel results dashboard (proposal deliverable #1)
├── models/                       # Simulink Digital Twin (gitignored — regenerated on build)
│   ├── UAV_GCS_Base_Link.slx     # A1-A2: clean AWGN channel
│   ├── UAV_GCS_Rician_Link.slx   # A3: fading + Doppler
│   └── UAV_GCS_Threat_Link.slx   # A4-A6: threats + recovery
├── docs/
│   └── DECISIONS.md              # Architecture Decision Record (D1-D33)
├── diagnostics/                  # Ad-hoc investigation scripts, kept for reproducibility
├── README.md                     # This file
├── PROJECT_LOG.md                # Living execution log — status, fix history, open issues
├── ROADMAP.md                    # Project timeline (original plan)
├── [Phase scripts — root holds only the active pipeline, 35 files]
│   ├── A: init_params.m, build_link_model.m, build_rician_model.m, build_threat_model.m, run_awgn_sweep.m, run_dataset_sweep.m, extract_spectrograms.m, visualize_spectrograms.m, extract_closed_loop_frames.m, quick_ber.m
│   ├── B: prepare_data.m, train_detector.m, eval_detector.m
│   ├── C: dqn_agent.m, build_dqn_state.m, train_dqn.m (also writes the countermeasure matrix), rule_based_policy.m, apply_countermeasure.m, recovery_vs_clean.m
│   ├── C-eval: run_closed_loop_diagnostic.m, eval_speed_robustness.m, run_closed_loop_episodes.m + report_closed_loop_episodes.m, eval_combined_threats.m
│   ├── Detection helpers: detect_frame.m, cnn_scores.m (probabilities, logits, MSP, energy), ood_thresholds.m, eval_ood_detection.m
│   ├── SURV: map_survivability_boundary.m
│   ├── KPI: measure_all_kpis.m, measure_kpi3_recovery_time.m, diagnose_far_measurement.m, build_kpi_dashboard.m
│   └── GUI: demo_gui.m
└── legacy/                       # Kept for the record, not in the active pipeline (D33): CNN-LSTM study (D13, 5 files), pre-D28 EXP mechanism study (2 files), C3 MVP loop
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

## Latest Results (dataset and detector: 2026-09-21 full re-run; decision, closed loop and maps: 2026-09-23/24 on the D28–D30 model)

Dataset and detector numbers come from the 2026-09-21 full `main.m` run on the 50–120 km/h speed-diverse dataset (D25). Everything downstream of the detector was re-run on 2026-09-23/24 after the physics-based countermeasure model (D28), the new DQN reward (D29) and the action-based survivability map (D30); those supersede the earlier closed-loop and map figures.

### Phase A — Dataset (D25)
- **27,270 frames** (8 threats × 5 severity levels × 6 Eb/N0 × 100 frames, plus a balanced `none` class). Every 100-frame block is simulated at its own **continuous, non-integer UAV speed** in 50–120 km/h (min 50.0, mean 85.2, max 119.9), assigned through a Latin-square over 6 speed bins so speed is correlated with neither SNR nor class. Split 21,816 / 2,727 / 2,727.
- Speed is stored per frame for analysis; it is **not** a network input.

### Phase B3 — CNN Detector (9-class)
- **Overall accuracy: 96.41%** (96.73%), **macro-F1 96.39%** (96.73%); best validation accuracy 97.1% at epoch 29
- Per-SNR: 91.4% @ 0 dB → 95.6% @ 2 → 96.7% @ 4 → 97.6% @ 6 → 98.5% @ 8 → 98.7% @ 10 dB (was 93.4 → 97.1 → 96.5 → 98.0 → 97.8 → 97.6). Lower at the 0–2 dB edge, higher at 8–10 dB, and now monotonic.
- Accuracy vs UAV speed (7 equal bins, n≈315–480 each): 92.7% (50–60 km/h), 96.9, 96.2, 95.6, 98.2, 97.1, 98.0% (110–120 km/h). The lowest-speed bin is the weakest; the rest stay within about 2.6 points of each other.
- Per-class recall (precision): none 97.0 (93.3) · jamming 98.7 (90.1) · noise_burst 100 (98.7) · **reactive_jamming 87.1 (98.5)** · path_loss 94.7 (97.3) · spoofing 98.7 (100) · antenna_fault 92.8 (98.3) · benign_interference 100 (95.6) · sweeping_jammer 98.7 (97.1)
- Main confusions: reactive_jamming → jamming 33/304 (plus 6 → benign), path_loss → none 12, antenna_fault → none 9 and → sweeping_jammer 9, none → path_loss 5

### Phase C2 — DQN (D29)
- Reward table measured through the real link for 9 threats × 5 actions × 6 Eb/N0 (270 simulations); reward = link state vs clean − goodput/spectrum cost; −40 for acting on a healthy non-hostile link. 4,000 table-based episodes with real per-frame states, 10% with the class hidden. Training ~7 min.
- Validation gate passed on all 54 (threat, Eb/N0) cells: mean regret 1.5 reward points, maximum 11, none above 15.
- Learned policy: channel_switch for jamming / reactive_jamming / spoofing, spatial_diversity for antenna_fault, rate_reduce for path_loss (0–8 dB), freq_diversity for sweeping_jammer (≥ 4 dB), action on benign interference only where it degrades the link (≥ 4 dB), never on `none`.

### Countermeasure efficacy (D28, `results/countermeasure_matrix.*`)
Every threat × action at nominal severity, Eb/N0 = 0 / 4 / 10 dB, ground-truth threat. Best achievable link: jamming, reactive_jamming, spoofing and antenna_fault restored at every Eb/N0; sweeping_jammer restored at 0–4 dB, marginal at 10 dB (4.4×); noise_burst restored at 0–4 dB, **not restorable at 10 dB (29×)**; path_loss restored at 0 dB, marginal at 4 dB, **not restorable at 10 dB (7.0×)**.

### Phase C3 (Closed-Loop) — 9 threats × 6 Eb/N0, DQN and rule-based on the same runs (2026-09-24)
Both policies decide from the same detector output and link measurements and act through `apply_countermeasure.m`; the rule's action is simulated whenever it differs from the DQN's.

| Threat | DQN action (typical) | DQN recovery vs clean | DQN BER/clean | Rule recovery | Rule BER/clean | Rule goodput |
|---|---|---|---|---|---|---|
| jamming | channel_switch | 99.4% | 1.27× | 99.4% | 1.27× | 1.00 |
| reactive_jamming | channel_switch | 99.4% | 1.17× | 99.4% | 1.17× | 1.00 |
| sweeping_jammer | spatial / freq_diversity | 86.6% | 2.11× | 83.0% | 2.15× | 1.00 |
| noise_burst | spatial_diversity | 32.2% | 11.1× | 55.2% | 9.46× | 0.25 |
| path_loss | rate_reduce (spatial at 10 dB) | 63.5% | 7.10× | 69.7% | 3.93× | 0.25 |
| spoofing | freq_diversity / channel_switch | 99.5% | 1.04× | 99.9% | 1.02× | 1.00 |
| antenna_fault | spatial_diversity | 99.1% | 1.07× | 84.2% | 1.14× | 1.00 |

- **KPI #2 (DQN): 82.8%** recovery vs the no-attack link; 30/42 runs restored (≤ 2× clean), 8 marginal, 4 not restored, 0 missed detections. The shortfall is physical: noise_burst and path_loss at high Eb/N0 are not restorable by any single action (see the survivability map).
- **DQN vs rule (link-quality half of KPI #3):** rule 84.4% recovery, 31/42 restored, mean goodput 0.79; DQN 82.8%, 30/42, mean goodput 0.91. Per run: rule better link in 7, DQN in 2, within 10% in 33. This is the trade-off the reward encodes (rate reduction costs 22.5 of 100 points): the DQN gives up some link quality on noise_burst to keep throughput. It also shows the DQN's one weak cell — path_loss at 10 dB, where it chose spatial_diversity (27.8× clean) instead of rate_reduce (gate regret 11).
- **Detection error:** antenna_fault at 0 dB was misdetected as sweeping_jammer (46% confidence). The rule applied the sweeping action (freq_diversity, no effect on an antenna fault); the DQN chose spatial_diversity and restored the link (1.01× clean). Its Q-values for spatial and rate_reduce were nearly tied (41.9 vs 41.7), and spatial is also its policy for a sweeping jammer at 0 dB, so this is a single, fortunate case rather than an established robustness advantage.
- Detection 53/54 (98.1%); agreement 34/54 (63.0%); decision latency mean 12.1 / median 11.4 ms (CNN 10.9 + DQN 1.3 ms).

### Phase C3-speed — Robustness vs UAV speed (2026-09-24)
| Speed (km/h) | 50.0 | 57.3 | 66.8 | 72.0 | 84.6 | 97.2 | 108.9 | 120.0 |
|---|---|---|---|---|---|---|---|---|
| fd (Hz) | 111 | 127 | 148 | 160 | 188 | 216 | 242 | 267 |
| Detection | 100% | 100% | 96.3% | 96.3% | 100% | 96.3% | 100% | 100% |
| Recovery vs clean | 83.2% | 83.0% | 83.6% | 82.9% | 82.5% | 84.0% | 84.7% | 83.3% |
| Restored (≤ 2× clean) | 16/21 | 15/21 | 16/21 | 16/21 | 16/21 | 15/20 | 16/21 | 16/21 |

Detection 98.6% (213/216; all three misses antenna_fault); **false alarms 0/48** (32 runs on a healthy link); 16 justified actions on degraded benign links; KPI #2 83.4%, flat across speed (82.5–84.7%).

### Phase C3-episodes — recovery time in decision cycles (KPI #3, D31)
Threat onset mid-stream, one decision per received frame, dwell 3 / hold 10 cycles; 9 threats × {0, 4, 10} dB × 5 episodes × {DQN, rule} × {with, without hysteresis}; frames from real Simulink runs of every (threat, action, Eb/N0).

| Configuration | T_act (median) | T_recover (median) | Recovered (degraded episodes) | Switches / episode | False switch on healthy link | Goodput |
|---|---|---|---|---|---|---|
| DQN, hysteresis | 3 cycles | 8 cycles | 61/87 (70%) | 1.5 | 1/20 | 0.92 |
| Rule, hysteresis | 3 cycles | 8 cycles | 68/91 (75%) | 1.5 | 1/20 | 0.85 |
| DQN, no hysteresis | 1 | 7 | 18/43 (42%) | 18.5 | 14/20 | 0.80 |
| Rule, no hysteresis | 1 | 6 | 16/32 (50%) | 7.4 | 14/20 | 0.91 |

- At the measured ~11 ms per decision, 3 cycles ≈ 35 ms to act and 8 cycles ≈ 90 ms to recover.
- Hysteresis (proposal mitigation 8) is essential, above all for the DQN: without it, it switches 18.5 times per episode and in 47/115 episodes a false countermeasure was already active when the threat began.
- Non-recovered cells (sweeping_jammer 10 dB, noise_burst 4–10 dB, path_loss 4–10 dB) match the survivability map at nominal severity.
- Exact-class detection at onset is late (noise_burst ~10 cycles = temporal window; jamming 0–4 dB never exact) because training excluded windows spanning a threat's start; the early labels still map to the right countermeasure, so action and recovery are on time.

### Unknown and combined threats (deliverable 4, risk 13; D32–D33)
- **Leave-one-threat-out** (detector retrained without each threat): mean AUROC MSP 0.515, energy 0.521 — no better than chance on average. Distinct threats separate well (benign 0.90 / 0.97, antenna_fault 0.79 / 0.85, spoofing 0.64 / 0.91); a threat with a close sibling is classified *more* confidently than the known classes (jamming 0.16, reactive_jamming 0.18, noise_burst 0.03). Softmax-based unknown detection therefore does not work for near-duplicate threats — a known limitation of these scores. Operationally, jamming ↔ reactive_jamming map to the same countermeasure (93–100%), while noise_burst → sweeping_jammer and antenna_fault → spoofing lead to an ineffective action.
- **Combined threats** (jamming+path_loss, noise_burst+antenna_fault, sweeping_jammer+path_loss, spoofing+noise_burst): the detector names the dominant component with high confidence (MSP 0.92–1.00) and never flags them as unknown. The loop never freezes (0/456 no_action on an attack). One action cannot repair two impairments: the best single action restores only 2 of 12 (combination, Eb/N0) cells; the DQN reached both, the rule one (per cell, frames within a cell agree).
- **Gating fix (D33):** with confidence alone, 68% of clean-link frames at 0 dB fell below the threshold and the DQN acted on the clean link in 28/114 frames (4/114 without gating). Unknown gating now also requires a degraded link (BER > 2× clean), in the GUI and in the evaluation.
- What protects the system against an unknown threat is the response to link degradation (mitigation 13) and sibling mapping — not the unknown score. Feature-space scores (e.g. Mahalanobis distance) are the candidate improvement.

### FAR (False Alarm Rate) — proposal KPI, section ה (D29 definition)
- A false alarm is an action while the link is not degraded (BER ≤ 2× the clean trials at that Eb/N0) — the proposal's "unnecessary channel switch".
- **0/120** healthy-link trials (none at 0/4/10 dB, benign at 0 dB; 30 each). Upper 95% bound (Rule of Three) 3.3% per class (n = 90).
- Benign interference at 4 and 10 dB degraded the link in 60/60 trials; the system acted in all of them (justified). Old "any action" rate: 60/180 (33.3%).
- none was misdetected as benign 3/90 times at 0 dB; no action followed, because the link was healthy.

### KPI status (dashboard)
KPI1 detection 96.4% ✓ · KPI2 82.8% recovery vs the no-attack link (30/42 restored; non-restorable regimes mapped) ✓ · KPI3 DQN vs rule: act in 3 cycles, recover in 8 (~90 ms), 70% vs 75% of degraded episodes recovered, goodput 0.92 vs 0.85; decision latency ~11 ms ✓ · KPI4 FAR 0/120 ✓ · KPI5 end-to-end MET (jamming 99.5%) ✓

### Survivability Boundary Map (proposal deliverable #7, D30)
Every threat × 5 severity levels × 6 Eb/N0 × every action through the real link (1,200 simulations, 78 min). Map A = actions without goodput loss; Map B = any action including rate reduction.

| Threat | Map A recoverable | Map B recoverable |
|---|---|---|
| spoofing, antenna_fault, benign_interference | 100% | 100% |
| reactive_jamming | 97% | 97% |
| jamming | 93% | 93% |
| sweeping_jammer | 77% | 77% |
| noise_burst | 43% | 50% |
| path_loss | 20% | 30% |
| **All 240 states** | **78.8%** (9.6% marginal, 11.7% non-recoverable) | **80.8%** (10.0% / 9.2%) |

The narrow-versus-broadband contrast the proposal cites appears directly: in-channel interferers are recoverable at every severity by leaving or diversifying the channel; broadband noise_burst is non-recoverable from 6–10 dB even at its lowest severity; strong path loss is non-recoverable because no single action repairs the link budget. 6 gap cells (noise_burst 2, path_loss 4) survive only through rate reduction — the goodput trade-off. The pre-D28 maps built from abstract mechanisms (85.5 / 88.3%) are superseded.

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
- **State:** one-hot(9 threat classes) + [log10 BER, RSSI, Eb/N0, PLR] = **13-dim**, built exclusively via `build_dqn_state.m` (training and inference share it); an unknown class gives an all-zero one-hot
- **Actions:** {no_action, channel_switch, rate_reduce, freq_diversity, spatial_diversity}, applied through `apply_countermeasure.m`
- **Reward (D29):** link score vs the clean link (100 when BER ≤ 1.15× clean, otherwise recovery vs clean) minus cost (0.30 per unit of goodput lost, 0.05 per extra channel); −40 for any action on a non-hostile link that is not degraded
- **Training:** one-shot decisions; reward table measured over every threat × action × Eb/N0; 4,000 episodes sampling real per-frame states, 10% with the class hidden (proposal risk 13); per-cell validation gate
- **Rule-based baseline:** physics-consistent class → action mapping; with the link measurements it also acts on a degraded link whose class maps to no action (proposal mitigation 13)

### Recovery — physics-based countermeasure model (D28, `apply_countermeasure.m`)
One shared function applies the chosen action to the **true** threat for training, evaluation and the GUI. Threats are grouped by how they occupy the spectrum: in-channel (jamming, reactive_jamming, spoofing, benign_interference), swept (sweeping_jammer), broadband (noise_burst) and signal-side (path_loss, antenna_fault).

| Action | Physics | Effective against | No effect on | Cost |
|---|---|---|---|---|
| `channel_switch` | move to a channel the interferer does not occupy; interference falls by the adjacent-channel rejection (`cm_acr_db` = 30 dB) | in-channel threats | swept, broadband, signal-side | — |
| `freq_diversity` | same data on two channels, best branch selected | in-channel threats (−30 dB); swept jammer must hit both channels at once (duty → duty²) | broadband, signal-side | 2× spectrum |
| `spatial_diversity` | second receive antenna, MRC (`cm_n_rx` = 2) | +3 dB against noise and spatially uncorrelated interference; antenna_fault: healthy antenna replaces the faulty one | — | — |
| `rate_reduce` | data rate ÷ `cm_rate_factor` (4) | +6 dB processing gain against noise and noise-like interference | no gain against the coherent spoofer | goodput × 0.25 |

The previous model subtracted a fixed 25/15/25/25 dB from each threat's severity field regardless of the action's physics, so three actions were interchangeable and, for example, a channel switch "repaired" path loss. All closed-loop and map results above were re-run on this model (2026-09-23/24). `eval_countermeasure_matrix.m` measures every threat × action × Eb/N0 through the real link (`results/countermeasure_matrix.*`). First result: in-channel threats and antenna_fault are restorable at every Eb/N0; broadband noise_burst (29× clean at 10 dB) and strong path_loss (7.0× at 10 dB) are not restorable by any single action — the recoverable / non-recoverable contrast of proposal deliverable 7.

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
- **D33:** unknown gating only on a degraded link (confidence alone caused false actions on the clean link at 0 dB); file consolidation — 7 files merged or removed, 8 moved to `legacy/`
- **D32:** unknown-threat detection — leave-one-threat-out retraining with MSP and energy scores, calibrated unknown threshold — and combined threats (jamming+path_loss, noise_burst+antenna_fault, sweeping_jammer+path_loss, spoofing+noise_burst) with class-based vs unknown-gated decisions
- **D31:** episodic closed loop — threat onset mid-stream, per-frame detection and decision, dwell/hysteresis; recovery time in decision cycles for DQN and rule-based (KPI #3 as written)
- **D30:** survivability map rebuilt on the real action set (Map A without goodput loss, Map B any action, best action per cell); rule baseline reacts to link degradation (proposal mitigation 13)
- **D29:** DQN reward = link state vs clean − goodput/spectrum cost, trained over the full Eb/N0 range with real per-frame states (10% class-hidden episodes); FAR counts only unnecessary actions (link not degraded)
- **D28:** physics-based countermeasure model in one shared function (`apply_countermeasure.m`); actions now differ in effect (e.g. channel switch cannot repair path loss); rule-based baseline aligned to the same physics; `eval_countermeasure_matrix.m`
- **D27:** KPI #2 measured against the no-attack (clean) link, as the proposal defines it (`recovery_vs_clean.m`); clean reference = the `none` run at the same Eb/N0; previous BER-before metric kept alongside
- **D26:** `demo_gui.m` v3 — proposal-complete operator console (4 tabs, DQN-vs-rule comparison, UNKNOWN-threat handling, survivability verdicts, speed-driven Doppler); norm-stats cache for fast startup

See `PROJECT_LOG.md` for the full fix history and session-by-session detail behind each decision above.

---

## Known Issues & Future Work

**Open items:**
- **Improvement plan in progress (Session 12):**  KPIs above an SNR threshold, Monte Carlo confidence intervals, GUI performance.
- **Dynamic/Chasing Jammer scenario** (priority) — an adversary that reacts to the system's countermeasures, needed to let the DQN demonstrate a real decision-quality advantage over the static rule-based policy (see KPI #3 discussion above). Planned, not yet built.
- A small number of report figure placeholders need real source images (suggestions provided, final selection pending)
- `demo_gui.m` v3 (D26) — rebuilt and delivered; verified only by a syntax parse and helper-function tests outside MATLAB, so live-use feedback and small layout fixes are still expected. A slow-startup report on 2026-09-22 was addressed (norm-stats cache; launch from a fresh session)
- **reactive_jamming 87.1% recall** (was 91.0%; macro-F1 96.39%) — 33 of 304 test samples are labeled jamming. The distinction is temporal, and the extra Doppler variation may blur the temporal features (untested hypothesis). Below the 90% per-class line in absolute terms but above the proposal's 90% macro-F1 target; its closed-loop recovery is unaffected (85.7%) because jamming receives the same countermeasure. Candidate for targeted improvement or documentation as a known limitation.
- **antenna_fault** — weakest detection class (92.8% recall; the 0 dB closed-loop run is often misdetected at low confidence); recovery itself is 99% once the correct action is taken.
- **Decision latency** — ~10–11 ms median across three independent runs (10.05, 9.99, 11.44 ms). The D23 figure (6.09 ms) belongs to the previous build.
- **Speed diversity** — the DQN state has no Doppler input and its reward table and the survivability map are built at the nominal 72 km/h; detection and the closed loop are speed-swept (flat).
- `main.m` prints a hard-coded CHECKPOINT line at the end (old numbers); the authoritative numbers are in `results/kpi_summary.txt` and `results/kpi_dashboard.png`.

**Future work:**
- Sim-to-real validation (SDR testbed) — see Modeling Assumptions above for the specific gaps this would need to close (BER estimation via EVM/CRC, real synthesizer switching time, PHY synchronization)
- Combined countermeasures for combined attacks (one action per decision today)
- Online reinforcement learning
- FPGA/GPU acceleration
- **DQN weak cell:** path_loss at 10 dB (spatial_diversity chosen, 27.8× clean, where rate_reduce gives ~4–7×); passed the gate with regret 11. Candidate for more training or a finer reward.
- Transition-cost-aware reward shaping (Liu et al.'s λδ term), not currently implemented
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

**Last Updated:** 2026-09-24 (D27–D31: episodic closed loop and recovery time; KPI #2 vs clean link, physics-based countermeasures, DQN reward with costs, action-based survivability map)
**Status:** Phase A+B+C+EXP complete and re-run on the speed-diverse dataset, survivability mapping complete, all 5 proposal KPIs met, speed-robustness evaluation complete, interim report drafted (results chapters pending sync to the latest run), operator console v3 delivered and under live testing | Phase D (final report + defense prep) in progress
