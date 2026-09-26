# UAV-GCS Adaptive Secure Communications — Roadmap

**Project:** AI-driven adaptive communication security for the GCS → UAV command link in electronic-warfare environments.
**Platform:** MATLAB R2026a + Simulink
**Supervisor:** Golan Ein-Tzvi
**History:** [PROJECT_LOG.md](PROJECT_LOG.md) · **Design decisions:** [DECISIONS.md](DECISIONS.md) · **Results:** [README.md](../README.md)

Last updated: 2026-09-26

---

## Status by phase

| Phase | Content | Status | Decisions |
|---|---|---|---|
| A1–A3 | QPSK link with RRC, AWGN; Rician fading K = 10 dB, Doppler for a 50–120 km/h UAV | ✅ Done | D5, D6, D11, D25 |
| A4 | Two-antenna UAV receiver (MRC, MMSE), eight threats + combinations, interferer direction per seeded run | ✅ Done | D8–D12, D32, D41, D45 |
| A4v | Validation against theory (AWGN, Rician, MRC 2/3 antennas, correlated branches), seeds | ✅ Done, 5/5 within 0.3 dB | D41 |
| A5–A6 | 27,000 frames from 1,350 seeded sub-runs, spectrograms + 9 link features | ✅ Done | D42, D43, D45 |
| B | CNN + link-feature detector, bootstrap intervals, unseen Eb/N0 | ✅ Done, 96.3% | D42, D43 |
| B-unknown | Mahalanobis and isolation-forest scores, leave-one-threat-out | ✅ Done, AUROC 0.887 | D42, D46 |
| C1p | Frame pools: every scenario × configuration × Eb/N0 × geometry | ✅ Done | D44–D46 |
| C2 | Double DQN with shield, γ and seed chosen on validation | ✅ Done, γ = 0 | D44–D46 |
| C2e | Every policy on the test pools: single, follower, combined, unknown, clean | ✅ Done | D44–D46 |
| SURV | Survivability maps A/B, two geometries (deliverable 8) | ✅ Done, 86% / 94% | D30, D46 |
| LAT + KPI + DASH | Latency per cycle, eight proposal KPIs, dashboard (deliverable 1) | ✅ Done, 7/8 met | D46 |
| GUI | Operator console on the current decision layer | ⏳ Code migrated, live check pending | D24, D26, D46 |
| Fixes | False-alarm bound (KPI 6), latency tail | ⏳ Next run | — |
| Layout | Code into folders by stage | ⏳ End of project | D47 |
| D1 | Interim report | ⏳ Drafted, results to sync with the D46 run | — |
| D2 | Final report | ⏳ | — |
| D3 | Defense (20 + 10 min, English) | ⏳ | — |
| D4 | Poster | ⏳ | — |

---

## Remaining work

1. **False alarms (KPI 6):** 4.8% of clean episodes, bound 6.29% against 5%. The count is set by the 2-cycle alarm confirmation; choose the confirmation length on validation.
2. **Latency tail:** one forward pass for class probabilities and the Mahalanobis embedding; CPU vs GPU for single frames.
3. **Operator console:** live check of the migrated live tab and continuous episode.
4. **Reports and defense:** interim report numbers, final report, slides and poster from the same figures.
5. **Repository:** code into folders by stage, final README.

---

## Deviations from the original plan

| Original plan | What was done | Why |
|---|---|---|
| Symbol timing / phase recovery | Not modeled; ideal synchronization | Out of scope of the decision-system study (D7); a sim-to-real gap |
| CNN/LSTM on link metrics | CNN on the spectrogram + 9 link features; CNN-LSTM kept in `legacy/` | The LSTM gave no gain for its cost (D13) |
| 5 threat classes | 8 threats + none, plus combined threats | Proposal risk 13 and a more realistic EW set |
| Single-antenna link | Two UAV antennas, MRC baseline, MMSE as the spatial countermeasure | Spatial diversity as a real receiver function (D41) |
| Actions: channel switch, bit rate, diversity | 17 configurations: the originals, power control, FEC + interleaving and two-action pairs | Threats that no single original action repairs (D39, D45) |
| DQN on a reward table | Sequential environment on measured frames, shield, γ chosen on validation | One-shot decisions could not show recovery over time or a follower jammer (D44–D46) |
| Rule vs DQN by convergence and reward | Return, restored cycles, goodput, recovery time, false alarms, with 95% intervals and paired differences | KPIs as worded in the proposal |

---

## Risk mitigation (proposal section 10)

- **DQN convergence:** rule and table baselines in every comparison; 3 seeds per γ, best checkpoint, validation gate (D44–D46).
- **Reward design:** reward from link quality minus costs; baselines and oracle show where the policy stands.
- **Data leakage:** splits by seeded sub-run; test pools with unseen seeds and geometries.
- **Oscillation:** switching costs, alarm confirmation and shield (D45).
- **Unknown / combined threats:** Mahalanobis score, response to link degradation (unknown set: 85.5% restored without the class), training combinations (D46).
- **Sim-to-real gap:** validation against theory, documented modeling assumptions (README).
