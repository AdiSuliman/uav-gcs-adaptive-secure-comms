# UAV-GCS Adaptive Secure Communications — Roadmap

**Project:** AI-driven adaptive communication security for UAV-to-ground station links in electronic warfare environments.
**Platform:** MATLAB R2026a + Simulink
**Supervisor:** Golan Ein-Tzvi
**Live status and history:** [PROJECT_LOG.md](PROJECT_LOG.md) · **Design decisions:** [docs/DECISIONS.md](docs/DECISIONS.md) · **Results:** [README.md](README.md)

Last updated: 2026-09-25

---

## Status by phase

| Phase | Content | Status | Decisions |
|---|---|---|---|
| A1–A2 | QPSK link with RRC, AWGN validation against theory | ✅ Done | D5, D6, D11 |
| A3 | Rician fading K = 10 dB, Doppler for a 50–120 km/h UAV | ✅ Done | D4, D25 |
| A4 | Threat injection: jamming, reactive, sweeping, noise burst, path loss, coherent spoofing, antenna fault, benign interference; combined threats | ✅ Done | D8–D10, D12, D32 |
| A5–A6 | Speed-diverse dataset (27,270 frames), spectrograms + 7 link features | ✅ Done | D25 |
| B | Hybrid CNN detector (9 classes), KPI #1 as worded, bootstrap CIs, unseen Eb/N0 | ✅ Done | D16, D34, D35 |
| B-unknown | Unknown-threat scores (leave-one-threat-out), gating on a degraded link | ✅ Done | D32, D33 |
| C1 | Rule-based policy, degradation-aware | ✅ Done | D30 |
| C2 | DQN: measured reward table, 5 seeds, full-action targets, validation gate | ✅ Done | D29, D35, D36 |
| C3 | Closed loop over Eb/N0 with Monte Carlo CIs; PLR and goodput; speed sweep | ✅ Done | D27, D28, D35 |
| C3-episodes | Recovery time in decision cycles, dwell/hysteresis | ✅ Done | D31, D37 |
| SURV | Survivability boundary maps A/B (deliverable #7) | ✅ Done | D30 |
| KPI + DASH | All five proposal KPIs with CIs; results dashboard (deliverable #1) | ✅ Done | D35 |
| GUI | Operator console: live runs, continuous episode, KPIs, maps, session log | ✅ Done | D24, D26, D37 |
| Full run | One consistent end-to-end `main.m` run from scratch | ✅ Done 2026-09-25 | D38 |
| Action set v2 | FEC + interleaving, power control, two-action combinations | ✅ Done 2026-09-26 | D39 |
| D1 | Interim report | ⏳ Drafted, numbers to sync from the full run | — |
| D2 | Final report | ⏳ Next | — |
| D3 | Defense (20 + 10 min, English, ~10 slides) | ⏳ | — |
| D4 | Poster | ⏳ | — |

---

## Remaining work

1. **Interim report:** update its numbers from the full run.
2. **Final report:** detection, decision (DQN vs rule), closed loop, survivability map, limitations and sim-to-real gap.
3. **Defense and poster:** slides and poster from the same figures and numbers.

---

## Deviations from the original plan

| Original plan | What was done | Why |
|---|---|---|
| Symbol timing / phase recovery blocks in A3 | Not modelled; ideal synchronization | Out of scope of the decision-system study (D7); listed as a sim-to-real gap |
| CNN/LSTM on link metrics | Hybrid CNN on spectrogram + 7 link features; CNN-LSTM tested and kept in `legacy/` for the record | The LSTM gave no gain for its cost (D13) |
| 5 threat classes | 8 threats + none, plus combined threats | Proposal risk 13 and a more realistic EW set |
| Actions: channel switch, bit rate, diversity | 16 actions through one physical model: the four originals, power control, FEC + interleaving and 9 two-action pairs | Single source of truth (D28); noise_burst and path_loss needed responses outside the original set (D39, proposal addendum) |
| Rule vs DQN by convergence and reward | Link quality, packet loss, goodput and recovery time, with 95% CIs | KPIs as worded in the proposal (D27, D31, D35) |

---

## Risk mitigation (proposal section IX)

- **DQN convergence:** rule-based baseline in every comparison; validation gate and 5 training seeds (D35, D36).
- **Dataset imbalance:** balanced `none` class, stratified split.
- **Oscillation (risk 8):** dwell/hold hysteresis, measured with and without (D31).
- **Unknown / combined threats (risk 13):** reaction to link degradation, unknown gating (D32, D33).
- **Sim-to-real gap:** modular threat injection and a documented list of modelling assumptions (README).
