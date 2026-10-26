# Project Log

History of the UAV-GCS adaptive communications project, from the first link model (20.08.2026) to the current run (26.10.2026), one section per version.

- Why each design choice was made: [DECISIONS.md](DECISIONS.md) (D-numbers are cited below).
- What each source contributes: [LITERATURE.md](LITERATURE.md).
- Plan and remaining work: [ROADMAP.md](ROADMAP.md).
- The previous, full session-by-session log is kept in git at commit `b648c7b` (`docs/PROJECT_LOG.md`).

Scope: the lecturer's revised proposal of 20.10.2026 (D92) is the official scope. Everything built beyond it is an extension without commitment and is labelled so. Dates are DD.MM.YYYY, local time. Clocks went back on 25.10.2026 at 02:00.

## Where we are (26.10.2026)

| Item | State |
|---|---|
| Lecturer KPIs 1-4 (BER model, macro-F1, false alarms, recall) | Measured on data never used for training or selection: all met (details in v7) |
| Lecturer KPIs 5-8 (PER reduction, recovery time, goodput, CNN contribution) | Pending: they come from stage C2e |
| Profile 1 (3 UAV antennas) | Stage C2 (decision-layer training) running since 26.10 16:03; 9 of 72 runs finished at 21:11 |
| Next on profile 1 | C2e (first PER, recovery-time, goodput and CNN-contribution lines), then the rest of the chain, a controlled-bandwidth study, a rerun with a corrected monitor, then profile 3 |
| Profile 3 (4 UAV antennas) | Detector stages done; decision layer waits for profile 1 |
| Estimates | C2e 28.10; profile 1 chain ends 28.10 evening to 29.10 early morning; profile 3 about 18-21.11 (D104) |
| Interim report | Draft 4 delivered 26.10; draft 5 structure approved |

## Version overview

| Version | Dates | What it added | Last result |
|---|---|---|---|
| Foundation to v3 | 20.08 - 27.09.2026 | Link model, threats, dataset, hybrid CNN, closed loop, DQN, multi-antenna receiver | D52: 8 of 8 KPIs met (history) |
| v4 | 28.09 - 30.09.2026 | Receiver-side measurements, 36 configurations, stricter evaluation | Final reading 30.09: 7 of 8 KPIs met |
| v5 | 30.09.2026 | Wider realism, spatially separated antennas, sourced platform profile | Superseded by v6 before any test reading |
| v6 | 01.10 - 06.10.2026 | Temporal fusion, quiet slot, levels to the sources' caps | Ideal-receiver reference |
| v7 | 01.10.2026 onward | Real receiver, flight dynamics, triples, profile 3, per-point verdicts | Detector readings done; C2 running |

Stage names used below: A = link and dataset, B = detector, C1 = frame pools, C1d = drop-alarm threshold, C2 = decision-layer training, C2e = evaluation of every policy, SURV and SURV3 = survivability maps, C2g = decision layer retrained without each threat combination, C2u = response to a threat never trained on, OHP = overhead pass of the UAV, GCSA = gain of the tracked GCS antenna, EDGE = verdict per envelope point, LAT = latency, RPT = report numbers.

## Foundation to v3 (20.08 - 27.09.2026)

Goal: a working simulated UAV-to-ground link with threats, a detector and a recovery loop. The early builds are labelled by date and by decision (D1-D58), not by a whole-system version number.

Main changes
- Model-based simulation in MATLAB/Simulink, QPSK at 1 Msym/s over a Rician channel, six base threats (D1-D11).
- 20.08 AWGN link validated against theory; 28.08 Rician link (K = 10 dB); 02.09 eight threats.
- 05.09 first dataset (10,686 frames); 09.09 first CNN plus scalar-feature hybrid (7 classes, 78.8%).
- Latency measured with preprocessing included (D22-D23); operator console (D24, D26).
- Speed-diverse data, 50-120 km/h (D25); recovery measured against the clean link (D27); physics-based countermeasure model (D28); unknown-threat detection and combined threats (D32); action set with power control and FEC (D39).
- v3 (26-27.09): multi-antenna receiver with MRC/MMSE (D41), detector with a run-level split (D42-D43), sequential decision layer on measured frame pools with a Double DQN, follower jammer and escalation (D44-D46), M-of-N alarm confirmation and independent clean geometries for false alarms (D48-D52), 3D view (D53-D58).

Key results (history, superseded by later versions)
- 18.09: 9-class CNN 98.05%, then 96.73% after the receiver tap fix.
- 21.09: CNN 96.41% (macro-F1 96.39%), latency 10.21 ms mean and 10.05 ms median.
- D52 (27.09, last v3 result): false alarms DQN 9/600 = 1.5%, bound 2.60%; 8 of 8 KPIs met.

Bugs that changed results
- Spoofing was weak (recall 53.0%) because of a data-generation fault, not the architecture; the fix raised its recall to 98.7-99.7% (the 9-class CNN reached 98.05%, D12) and made the CNN-LSTM comparison pointless (D13, not pursued).
- The receive tap point was wrong; fixing it gave the honest 96.73% (D18).
- Latency was first measured without preprocessing (D22).
- A KPI report was overwritten by auto-run source scripts (fixed 23.09).

## v4 (28.09 - 30.09.2026)

Goal: stricter, receiver-side evidence and a final, once-read test.

Main changes
- CRC-32, estimated BER, SINR and spatial features measured at the receiver; 36 combined configurations in three severities (D59).
- Unknown-threat score by nested leave-one-threat-out (D60).
- Shield with hold against switching every cycle (D63); escalation out of no_action on a confirmed alarm (D64).
- Penalty for false switches in the reward (D67); disk guard against temporary-file build-up (D61).

Final reading (30.09, fourth test reading, D67; envelope: eight threats, K = 10 dB, Eb/N0 0-10 dB, 2 antennas, one speed band)

| Measure | Result |
|---|---|
| Detector macro-F1 | 97.02% [96.24, 97.60] |
| Unknown-threat AUROC (nested) | 0.859 |
| BER model within 0.3 dB | 5 of 5 |
| Restoration, threats at or above 90% | 14 of 16 (pooled 96.1% [94.8, 97.5]) |
| Learned policy against rule plus escalation | +16.5 points |
| False alarms on clean episodes | 13/600, bound 3.42% |
| Latency | median 2.91 ms, p95 3.97 ms |
| Survivability maps A / B | 82% / 93% |
| KPIs met | 7 of 8 (restoration not met: benign interference 87.2%, noise burst plus antenna fault 88.7%) |

Bugs that changed results
- The clean-link monitor was cached from the first call, so every run's false alarms used the wrong monitor (D63).
- A diagnostic read an agent overwritten by a smoke run; the "switching every cycle" numbers came from an untrained agent and were repeated on the right one.

The v4 state was archived in the live tree as `archive/v4_final_D67_20260930/` (not on this branch).

## v5 (30.09.2026)

Goal: widen the envelope to the conditions of air-ground measurement campaigns before the final reading.

Main changes
- Tone jamming and airframe shadowing as threats; Rician K per flight 0-20 dB; Eb/N0 0-15 dB; ten combined threats; one-cycle signalling delay; test speeds 20-50 and 120-160 km/h (D68).
- Antennas spatially separated over a 1.2 m aperture so shadowing can hit one antenna (D69).
- Platform fixed from the lecturer's sources: small drones up to the close-range class of Tlili et al. (50 km). Profile 1 = 3 antennas, 29-161 km/h; profile 2 = 2 antennas. Ranges capped at the most severe sourced value (D70).

Result: PHY validation 7/7 within 0.3 dB; unit tests 10/10. The run was stopped during spectrogram extraction to apply D69; its test flights were never read. v5 was superseded by v6, because its detector results on development data pointed to the weaknesses fixed there (D72).

Bug that changed results: the per-speed breakdown of the v4 readings 2-4 took the speed from the wrong seed block and is not reliable; v5 stores the speed of every flight.

## v6 (01.10 - 06.10.2026)

Goal: fix the weak classes found in v5 (a single frame deciding alone; two threat pairs with the same physics; an unknown-threat score that read "stronger than trained" as "new").

Main changes (D71-D72)
- Temporal fusion of the last N decision cycles (stage B2F) and the unknown-threat score over a window.
- A quiet slot in every frame; antenna fault and WLAN traffic as physical processes.
- Threat levels up to the sources' most severe values; weak-point analysis (stage WEAK).

Result: profiles 1 and 2 ran to the end as the ideal-receiver reference for v7 (a power loss on 02.10 interrupted them; both resumed on 03.10). A 32-page summary document (in Hebrew) was delivered on 06.10.

## v7 (01.10.2026 onward)

Goal: a realistic receiver and flight dynamics, so the system's weak points show up before a real test. Inputs are RF measurements only (no IMU, no GNSS); flight conditions are simulated through their RF effect.

Main changes (D73-D104)
- Real receiver with training blocks and pilots (synchronisation, frequency offset, MVDR passes), hover and turns, speed 0-161 km/h, source-corrected severities, four triple threats, profile 3 with four antennas, tracked 12 dBi GCS antenna under the 10.2 dBm e.i.r.p. cap (D73).
- Verdict COMMITTED / NOT COMMITTED / UNDETERMINED at every envelope point (stage EDGE, D74).
- Link, detector, receiver and coded-packet gap fixes (D75-D79); fast isolation-forest scorer for unknown threats (D80).
- Fusion regression fixed and a second test set (D81-D82); restart with a fixed noise floor, path loss as a step and shadowing tied to attitude (D83); 34 pre-launch fixes (D84-D86).

### Launch and early runs (06.10 - 16.10.2026)

- 06.10: first v7 run launched; it was relaunched the same morning after the launching session closed. A system-drive swap that evening paused it for a few hours (notes in `docs/drive_swap/`).
- 08.10: run stopped to fix three simulation errors (Eb/N0 set by the noise instead of a fixed floor, antenna fault not applied to the interferers, shadowing not tied to attitude) and rerun from the start (D83).
- 16.10 11:09: full run launched; PHY validation 7/7 theory gaps within 0.3 dB.

Bugs that changed results
- 17.10: a link feature (`align`) was scrambled in every dataset; datasets repaired and the run redone (D87-D88).
- A latch on the fault class lowered fault recall; it became a choice made on validation (D87).
- The MMSE predictor needed four fixes before the pools were built (D89).

### Detector readings (17.10 - 21.10.2026)

Third test set, read once (17.10). Fusion revision "branch evidence" adopted on 18.10 (D91) and read later on the fourth set.

| Measure (third test set, 83,664 frames, 3,984 sub-runs) | Profile 1 (3 antennas) | Profile 3 (4 antennas) |
|---|---|---|
| Macro-F1 above the validation-chosen threshold | 93.58% [93.08, 94.07] | 94.19% [93.69, 94.68] |
| Unknown-threat AUROC (nested, target 0.8) | 0.769 (not met) | 0.763 (not met) |
| Unseen Eb/N0 | 92.1% (seen 92.8%) | 91.8% (seen 91.8%) |

These are third-set readings; the fourth-set readings of 26.10 (fusion revision deployed) are below. Weak classes on this set (extension work; working bar 85% per class): antenna fault 83.1 / 83.6, airframe shadowing 82.7 / 82.0, path loss 87.8 / 88.4, WLAN 89.0 / 89.2 (profile 1 / profile 3). Physics limits and untried levers are recorded in DECISIONS (D91).

18.10 to 21.10: the slowdown of stage C1p (frame pools) was analysed (D91); processor boost was switched off on 20.10 for stability; takeover launched 20.10 11:22.

### Lecturer's revised proposal (20 - 21.10.2026)

- 20.10: the lecturer's revised proposal became the official scope, unchanged (D92): clean, narrowband and wideband jamming; a three-state CNN; rule-based recovery; three configurations compared (static, conventional adaptive on link metrics only, CNN-based adaptive); eight KPIs.
- Mapping to code: narrowband = tone jamming, wideband = barrage jamming; static = no action, conventional = `blind_esc`, CNN-based = `rule_esc`.
- Everything else (ten threats, 3 and 4 antennas, real receiver, hybrid network, unknown-threat detection, 36 configurations, DQN, GUI, survivability maps, EDGE, C2g, C2u, OHP/GCSA on profile 1) stays as extension without commitment. Nothing is rerun to remove it.
- 21.10: profile 2 dropped; relay path and altitude axis not reported; OHP and GCSA skipped on profile 3; Python dropped from the tools.
- New code for the lecturer's KPIs: PER reduction with a paired geometry bootstrap, recovery time from detection, onset-to-detection time, goodput, and a three-state view of the confusion matrix.
- 21.10 results audit: all headline numbers confirmed from the primary files; 58 wording issues about what a number measures were found in the interim-report draft.

### Survivability maps and the noise-burst finding (24 - 25.10.2026)

- 24.10: stage C1p done in 8,692 min; C1c (clean pools) 911 min; report gallery of all threats done.
- 25.10 01:49: SURV done in 386 min. Map A (no goodput loss) 81.8%, Map B (any configuration) 91.8%; 64 gap cells, mostly noise burst (22 at 11.4 degrees) and path loss (16).
- 25.10 10:49: SURV3 done in 600 min. Single threats 91.3 / 93.1 / 90.6% (2 antennas / 3 antennas / relay what-if); combined 58.2 / 67.6 / 53.1%. The third antenna's gain is real (sign test p = 2.3e-7). Noise burst plus antenna fault: 4.2% with 2 antennas against 50% with 3 (2 of 48 against 24 of 48 cells).
- Noise burst (D97): the rule's coded answer makes the link worse (BER 0.495 against 0.439 with no response). Burst symbols are erased wholesale and a rate-1/2 code sits at capacity at duty 0.5. Profile 1 chooses an uncoded answer on validation; profile 3 gets a decoder tuned on a development set. This is a real weakness and is reported as such.
- Clean BER reference rebuilt from 300 validation clean flights per Eb/N0 instead of 8 training flights (D95); check at 9 dB: 1.45e-3 [1.01e-3, 1.97e-3].
- Pre-registrations written before any result: low-Eb/N0 readings of the lecturer KPIs (D99), profile 3 map and SURV3 version 2 (D100-D101), git-dependent tests (D102).

### Stop window and test-set readings (25.10 - 26.10.2026)

A planned software-only stop of profile 1 (25.10 10:50 to 26.10 15:58) deployed the fusion revision, reran the detector stages, rehearsed the readings and resumed the chain (D94-D96).

- 25.10: the chain stopped after SURV3 as designed; tests of the merged code found two test-assumption faults in the core-CNN checks (toolbox detection, working-folder check); both fixed and retested.
- 26.10 14:35-14:40, stage B3r: the eleven-class detector read once on the fourth test set (4,032 frames per state, 576 sub-runs).
- 26.10 14:41-14:52, stage B3c: the proposal's three-state core CNN (spectrograms only) trained and read once on the same set.
- 26.10 15:16: new clean reference written; pools re-keyed 15:31-15:40; chain resumed 15:58.

Results (profile 1, fourth test set, 95% bootstrap intervals)

| Measure | Result |
|---|---|
| Lecturer KPI 2: core CNN macro-F1, window N = 3 | 99.83% [99.64, 99.97] (per frame 99.34%) |
| Lecturer KPI 3: core CNN false alarms on clean | 0.17% [0.00, 0.53] |
| Lecturer KPI 4: recall narrowband / wideband | 99.95% [99.87, 100.00] / 99.73% [99.28, 100.00] |
| Lowest point | wideband at JSR 0 dB, 97.82% windowed |
| Detection delay | median 0 cycles; never detected 0.0% |
| Eleven-class hybrid monitor, macro-F1 | 94.81% [94.35, 95.25]; 94.93% above the 0 dB threshold |
| Hybrid monitor, clean frames read as a threat | 2.66% (limit 5%) |
| Hybrid monitor, weakest class | airframe shadowing 84.46% |
| Hybrid monitor, clean false alarms read as 3 states | 5.36% [3.51, 7.21]: not met, but 0.00% as a jamming state |

The lecturer's false-alarm KPI is read at detector level; the system-level figure below is a separate extension KPI.

### C1d and C2 (26.10.2026)

- 16:02, C1d (drop-alarm threshold): drop threshold 4.5 dB, monitor form class_cusum. The whole monitor at no_action false-alarms on 12.5 to 29.9% of 1,800 clean validation episodes (2/2 29.85%, 3/3 22.07%, 4/5 19.84%, 5/5 12.46%); all above 5%. The cause is the degradation (BER) path at 0-6 dB (D103).
- Reporting rule fixed before any result: "System-level false alarms on clean flights (extension, our KPI 6): NOT MET, X%" with a breakdown. A corrected monitor is registered for profile 3 and a profile 1 rerun (D103-D104).
- 16:03, C2 (Double DQN grid): 4 monitors x 2 drop settings x 3 false-switch penalties x 3 seeds = 72 runs of 50,048 episodes each. About 34 minutes per run; 9 of 72 finished at 21:11. Finished runs recover 94.5 to 97.5% of episodes on validation.
- 18:14: order registered (D104): profile 1 chain, controlled-bandwidth study, profile 1 rerun with the corrected monitor on a fresh clean test set (at most 74 false-alarm episodes of 1,800 for the 5% bound), then profile 3.

## Status of the lecturer's KPIs (profile 1, 26.10.2026)

| KPI | Value | Status |
|---|---|---|
| 1 BER model against theory | 7 of 7 within 0.3 dB | Met |
| 2 Macro-F1 at least 85% | 99.83% | Met |
| 3 False alarms at most 5% in clean states | 0.17% (detector level) | Met |
| 4 Recall at least 85% per jamming type | 99.95% / 99.73% | Met |
| 5 PER reduction at least 30% against static | not measured | Pending (C2e) |
| 6 Recovery time, onset-to-detection reported separately | detection median 0 cycles; closed loop pending | Pending (C2e) |
| 7 Goodput | pending | Pending (C2e) |
| 8 CNN contribution against the conventional mechanism | pending | Pending (C2e, controlled-bandwidth study) |

Known caveat for KPI 5: at 0 and 3 dB the clean packet loss (0.99 and 0.79) makes the 2x packet bound vacuous, so those points are reported separately (D99).

Extension readings (no commitment): the earlier proposal's unknown-threat KPI is 0.769 (target 0.8, not met); the system-level clean false alarm is not at 5% (above).

## Lessons learned

1. Data-generation bugs look like model weaknesses. The spoofing fault (D12) and the scrambled `align` feature (D88) were found by auditing the data, not by changing the network.
2. Read a test set once, and decide thresholds, windows and architectures on validation. Every later reading of the same set is labelled a second reading.
3. A configuration that overwrites shared output files (a smoke run over a trained agent, a cached monitor) silently produces wrong diagnostics. Isolate runs and check which artifact a number came from.
4. Wider realism exposes real weaknesses (noise burst, shadowing, antenna fault). Report them as results with their physics, not as footnotes.
5. Keep the committed scope and the extensions apart. The lecturer's KPIs lead every report; extensions carry no promise.
6. Pre-register how a result will be reported before it exists (D98-D99, D103-D104).
7. Long runs need gates: memory and disk guards, resume modes, and a documented stop and resume procedure.
8. Check what a metric measures before quoting it (latency scope, per-class "accuracy" is recall).
9. Count the tests that ran, not only the failures: three tests were silently filtered for weeks by a toolbox check that is empty in R2026a, and an empty token list made a check pass vacuously.
10. Code must not depend on the checkout it was tested in: a git-less export broke `git show` in tests, and a thread setting failed under a single-thread launcher. Run the final tests the way the real run will run.
