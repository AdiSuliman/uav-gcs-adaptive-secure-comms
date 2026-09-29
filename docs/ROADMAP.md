# UAV-GCS Adaptive Secure Communications — Roadmap

**Project:** AI-driven adaptive communication security for the GCS → UAV command link in electronic-warfare environments.
**Platform:** MATLAB R2026a + Simulink
**Supervisor:** Golan Ein-Tzvi
**History:** [PROJECT_LOG.md](PROJECT_LOG.md) · **Design decisions:** [DECISIONS.md](DECISIONS.md) · **Results:** [README.md](../README.md)

Last updated: 2026-09-29

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
| C1c | Clean link on 100 new geometries per Eb/N0 under every configuration (KPI 6) | ✅ Done | D51 |
| C2 | Double DQN with shield; monitor, drop threshold, γ and seed chosen on validation; deployed with escalation | ✅ D64 agent (3/3, 3 dB, γ 0.5); D65 not adopted; ⏳ D66 (lower cost weights in the training reward) running, adoption rule fixed before the run | D44–D52, D59–D66 |
| C2e | Every policy on the test pools: single, follower, combined, unknown, clean, comb; false alarms on 600 independent clean geometries | ✅ Three readings; the third (new flights, D64 agent) is the current final; a fourth only if D66 is adopted | D44–D46, D51, D64–D66 |
| SURV | Survivability maps A/B, two geometries (deliverable 8) | ✅ Done, 86% / 94% | D30, D46 |
| LAT + KPI + DASH | Latency per cycle, eight proposal KPIs, dashboard (deliverable 1) | Third reading 6/8 met: KPI 4 14/16 (benign interference 86.5%, noise burst + antenna fault 85.0%), KPI 7 speed spread 10.6 points; latency 2.70 / 3.16 ms | D46, D48, D51, D52, D64–D66 |
| GUI | Operator console on the current decision layer | ⏳ Live tab checked (D53 lead-in, D54 hover help); episode tab check pending | D24, D26, D46, D53, D54, D56 |
| 3D | Unreal 3D view: live console (threat control, operator vs AI), defense videos, console-episode replay | ✅ Built and tested (D58); Cesium terrain optional | D57, D58 |
| Fixes | Latency tail; false-alarm bound (KPI 6) | ✅ latency p95 48.9 → 19.4 ms / ✅ KPI 6: 1.5% over 600 independent geometries, bound 2.60% (D52) | D48–D51 |
| v4 | Receiver-side measurements, 36 combined configurations, combined threats in training, three severities, per-antenna feature, unknown-threat score selection, new-threat learning, 20 ms decision period | ✅ Full run A0–C2g done; hold in the shield (D63); escalation out of no_action (D64) | D59–D64 |
| Layout | Code into `code/` by stage | ✅ Done | D47, D61 |
| D1 | Interim report | ⏳ Drafted, results to sync with the final run | — |
| D2 | Final report | ⏳ | — |
| D3 | Defense (20 + 10 min, English) | ⏳ | — |
| D4 | Poster | ⏳ | — |

---

## Remaining work

1. **D66 round:** training reward with lower cost weights; adoption check on validation; if adopted, new test flights (blocks 8, 9) and a fourth reading, then only the numbers that change are updated.
2. **Operator console and 3D view:** live check on the final deployed policy, after the D66 decision; the threat gallery with the final agent.
3. **Code comments:** a pass over every file (short explanation, no history); files the running chain uses wait until it ends.
4. **Interim report:** final numbers, proposal v2 sources, literature review by the lecturer's five topics (after the final results).
5. **Proposal v2:** ready for the user's review (16 references, all read).
6. **Final report, slides and poster:** last, when the user asks.
7. **Housekeeping:** the v3 backups in `archive/` stay until the user approves deleting them.

---

## Deviations from the original plan

| Original plan | What was done | Why |
|---|---|---|
| Symbol timing / phase recovery | Not modeled; ideal synchronization | Out of scope of the decision-system study (D7); a sim-to-real gap |
| CNN/LSTM on link metrics | CNN on the spectrogram + 9 link features; CNN-LSTM kept in `legacy/` | The LSTM gave no gain for its cost (D13) |
| 5 threat classes | 8 threats + none, plus combined threats | Proposal risk 13 and a more realistic EW set |
| Single-antenna link | Two UAV antennas, MRC baseline, MMSE as the spatial countermeasure | Spatial diversity as a real receiver function (D41) |
| Actions: channel switch, bit rate, diversity | 36 configurations, one choice per domain (frequency, space, link budget): the originals, power control, FEC + interleaving | Threats that no single original action repairs (D39, D45, D59) |
| DQN on a reward table | Sequential environment on measured frames, shield with hold, γ chosen on validation, escalation as a fallback | One-shot decisions could not show recovery over time or a follower jammer (D44–D46, D63, D64) |
| Rule vs DQN by convergence and reward | Return, restored cycles, goodput, recovery time, false alarms, with 95% intervals and paired differences | KPIs as worded in the proposal |

---

## Risk mitigation (proposal section 10)

- **DQN convergence:** rule and table baselines in every comparison; 3 seeds per γ, best checkpoint, validation gate (D44–D46).
- **Reward design:** reward from link quality minus costs; baselines and oracle show where the policy stands.
- **Data leakage:** splits by seeded sub-run; test pools with unseen seeds and geometries.
- **Oscillation:** switching costs, alarm confirmation and shield (D45).
- **Unknown / combined threats:** Mahalanobis score, response to link degradation (unknown set: 69.5% of cycles restored without the class, rule + escalation 51.7%), training combinations (D46).
- **Sim-to-real gap:** validation against theory, documented modeling assumptions (README).
