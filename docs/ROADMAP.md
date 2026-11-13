# Roadmap

Plan, status and remaining work of the UAV-GCS jamming detection and mitigation project, as of 12.11.2026 (morning). The scope is the lecturer's revised proposal of 20.10.2026 (D92); everything beyond it is an extension without commitment.

Related files: [README](../README.md) | [PROJECT_LOG.md](PROJECT_LOG.md) (execution history) | [DECISIONS.md](DECISIONS.md) (design record) | [LITERATURE.md](LITERATURE.md)

The previous full version of this file is in commit `b648c7b`.

## Proposal Gantt

Rows and months are exactly those of the proposal (months 1-8). The interim report covers the rows due by month 4.

| Task | Months | Status | Evidence |
|---|---|---|---|
| Literature review (theory, EW threats, AI methods; focus on jamming) | 1-3 | Done | [LITERATURE.md](LITERATURE.md) |
| Simulation environment and validation (UAV-GCS link in Simulink, BER vs theory) | 1-3 | Done | 7 of 7 theory gaps within 0.3 dB (0.01 to 0.14 dB) |
| Threat injection module and dataset (labelled; train, validation, test) | 2-4 | Done | 121,968 frames from 5,808 sub-runs; splits 81,312 / 20,328 / 20,328 |
| Detection layer (CNN): training, threat classification, unknown-threat detection | 3-4 | Done | Core CNN macro-F1 99.83% on a fourth, never-trained test set; unknown-threat detection built, AUROC 0.769 against our own 0.8 target (not met) |
| Interim report | 2-4 | Draft complete | Draft 7 complete (38 pages) |
| Decision layer: rule-based policy (baseline) | 4-5 | Ahead of schedule | Built and in use; its readings come with the policy evaluation |
| Decision layer: DQN agent (optional) | 5-7 | Ahead of schedule | Trained; chosen on validation: held recovery 82.6%, recovered 95.1% against 60.3% and 71.3% for the best rule setting; test reading (C2e): recovered 94.1% [92.7, 95.4] |
| Adaptive Link Recovery and closed-loop integration | 5-7 | Ahead of schedule | Closed loop built; frame pools and survivability runs done on profile 1 |
| Dashboard (GUI) | 6-7 | Ahead of schedule | Operator console built; branch `gui-core` GUI tests 25/25 (11.11, Session Log table dark to its full height); live check with the final agent from an exported profile-3 bundle after RPT |
| Evaluation on the test set and KPI table | 7-8 | In progress | Detector KPIs read; policy evaluation read 28.10: PER reduction MET (committed) narrowband 38.9% and wideband 43.3%; recovery time and goodput measured; Line B read 29.10 and CORE_BW read 30.10 (`rule_core3`: narrowband 62.3%, wideband 69.2%, MET (committed)); profile 3's chain in SURV (C1p and C1c done 12-13.11); D2c (receiver-robust line for CORE_BW) still to run |
| Survivability map and complementary experiments | 7-8 | Ahead of schedule | Profile 1: Map A 81.8%, Map B 91.8%; edge map still to run |
| Project book and presentation | 5-8 | Not started | Starts after the official finish of code and results (about 25-26.11) and Adi's approval; book about 26.11-10.12, presentation about 20.12 |

## Current run (profile 3)

| Milestone | State (estimate, boost off) |
|---|---|
| Deployment tests, fusion rerun, detector stages (smoke 55 steps, 0 errors; B-stage rerun B2F B3 B3a B4 B4s 13:54-17:48 on 5.11, rc=0; deploy state `deployed`) | done 5.11.2026 |
| Fresh2 rehearsal against the registered limits (fault F1 91.0 >= 88, macro-F1 above threshold 95.14 >= 94.5, clean as threat 2.54 <= 2.61) | passed 5.11.2026 |
| B3r: fourth test set read once (KPI 1 macro-F1 above the 0 dB threshold 94.92% [94.47, 95.31], target 90%; fault F1 89.9%; clean as threat 2.94%); record commit `35a4b66` | done 5.11.2026 |
| Step 7a, decoder on dev set C: the JSI decoder not adopted, `fec_rx` is d78 (D122) | done 5.11.2026 |
| D111 OOD select (hand run), OOD read, release check | done 5.11.2026 |
| C1p (4 antennas): frame pools, 93 cells | started 5.11 22:44 (resumed 7.11 and 8.11 with its kept cells); 56 of 93 on 11.11 15:56, 74 of 93 on 12.11 07:00 (24 cells on 11.11); done 12.11.2026 22:51 (867.9 min after the 08:22 resume; pools 15.9 GB) |
| C1c: clean-link pools and check cells | started 12.11 22:51; validation 106.1 min, test 110.5 min, check cells 478.1 min; done 13.11.2026 10:55 (724.4 min; profile 1 911.3). Clean reference rebuilt from 300 validation flights per Eb/N0: BER 1.6-4.8 times below profile 1's |
| SURV map v2 (D100), profile 3 | started 13.11 10:55 (estimate 44-50 h); power loss about 16:10 with 23 of 154 jobs saved, resumed 16:48 with all 23 kept; end about 14.11 evening to 15.11 midday |
| Code merged into `v7-p3` during C1p (C1p calls none of the changed files) | `acc2ab0` 10.11 (full suite 585/585); `fb487f8` 11.11 (`profile.json` only: `run_cache` on, approved by Adi); `8cfb172` 11.11 (windows D/E: bounded-search log lines, lecturer KPIs per Eb/N0 and the receiver-robust column, the system false-alarm breakdown, the clean K6 split, SURV kept jobs keyed on the code; suite 619/620, the one wrong test expectation fixed, 13/13) |
| SURV3 v2 (D101), C1d, C2, C2e, C2g, C2u, GAL, EDGE, KPI, DASH, WEAK, RPT | after SURV; profile 1's durations as a guide (C1p and C1c ran at 0.8-1.3 times them); chain end about 18-20.11 |
| Profile 3 chain ends | about 18-20.11.2026; hard limit 24.11 (D118: past it, D117 item 2, D111's serial OOD run, D114 and D115 are shed in that order) |
| Finish phase | LAT on the idle machine, then KPI, DASH, WEAK and RPT again; D2c; the console check on a profile-3 copy; the labelled side readings (D107, D108, D123); the behaviour-preserving cleanup (plan in `review/code_audit`) and the folder consolidation |
| Official finish of code and results | about 25-26.11.2026; then the project book, after Adi's approval |
| P1-v2 (D119) | after the project book (Adi, 11.11.2026) |
| Windows Update | paused until 30.11.2026 (registry `PauseUpdatesExpiryTime`); a forced reboot is covered by the resume mode |

Profile 3 = four antennas, branch `v7-p3` (candidate `q7` merged 4.11; OHP and GCSA skipped, `57a5ad2`). The 4.11 deploy queue ran the tests of the core (54 min) and of p3core (53 min): 314/314 PASS. Each stage starts when the previous one ends.

## Profile 1 (finished)

| Milestone | Result |
|---|---|
| DQN training (C2) done | 28.10.2026, 07:22 (measured; 2,359 min) |
| PC restart | done at the C2u to GAL boundary on 28.10 |
| Policy evaluation (C2e): the lecturer's open KPIs are read | 28.10.2026, 07:22-09:02 (measured; 99.8 min) |
| Combination generalisation (C2g) | 28.10.2026, 09:02-14:56 (measured; 354 min) |
| Unknown-threat generalisation (C2u) | 28.10.2026, 14:56 to the evening |
| Operator console with the v7 agent (Live and Episode tabs) | live check from a bundle outside the pipeline folder, with Adi present; not done yet |
| Profile 1 chain ends (RPT): KPI table, dashboard, report numbers | done 29.10.2026, 03:19:55 (rc=0); second archive, D99, D103, G0, clean_ref, GUI clean check and the final lecturer table done the same night |
| Controlled-bandwidth study (CORE_BW): `rule_core3` against the validation-tuned `blind_core` (D106) | test read once 30.10.2026 (20:20-22:39); reviewed 31.10; results in PROJECT_LOG |
| Profile-1 rerun with the fixed monitor (P1R) | ended after C1d on 31.10.2026 (D104 point 4): `'ratio'` kept, no admissible candidate; the fresh set stays unbuilt and unread |

Profile 1 = three UAV antennas, branch `v7-dev`. The dates come from C2's measured end and the stage durations below.

**Done (measured):**

| Stage | Result |
|---|---|
| Detector stages through unseen-severity evaluation | Done; fourth test set read once, core CNN trained and read once on it |
| Frame pools (C1p) | 8692.4 min |
| Clean-link pools and clean reference (C1c) | 911.3 min; reference rebuilt from 300 validation clean flights per Eb/N0 |
| Survivability maps (SURV) | 386.3 min |
| Antenna options (SURV3) | 599.9 min |
| Drop-threshold choice (C1d) | 3.9 min; threshold 4.5 dB |
| DQN training (C2) | 26.10 16:03 to 28.10 07:22; 81 runs and 2 sensitivity retrains. Deployed: the DQN without escalation (`class_drop` 5/5, 171 dB², penalty 120, costs x0.5, gamma 0.5, seed 44); validation held recovery 82.6%, recovered 95.1% (best rule setting 60.3% and 71.3%); 94 false changes in 54,000 clean cycles, bound met on validation. Reward sensitivity: held 80.1% (costs x0.5) and 80.6% (x2.0), at least the rule's and the table's at every scale |

**Now:** profile 1's chain is done (29.10 03:19:55, rc=0), CORE_BW is read, P1R ended after C1d, and profile 3 is deployed and running (see the current run above). Next, in order: the finish phase, the official finish, the project book, P1-v2.

**Chain stages** (all done 29.10; durations are estimates from smoke runs and the earlier full runs; no full-scale v7 run exists yet for these stages):

| # | Stage | What it does | Expected duration | Start |
|---|---|---|---|---|
| 1 | C2e evaluate_policies | Every policy on test pools; the lecturer's PER, recovery-time, goodput and CNN-contribution lines | 1-2 h | done 28.10 (99.8 min) |
| 2 | C2g experiment_combo_generalization | DQN retrained without each of 14 combinations (one full training each) | 7-8.5 h | done 28.10 (354 min) |
| 3 | C2u experiment_unknown_threat | DQN retrained without each of 10 single threats; response to a threat never trained on | 5-6 h | done (chain finished 29.10 03:19:55) |
| 4 | GAL threat_gallery | One figure per threat | 5-10 min | done (chain finished 29.10 03:19:55) |
| 5 | OHP overhead_pass | UAV flying over the GCS (dipole null) | 3.8-4.7 h | done (chain finished 29.10 03:19:55) |
| 6 | GCSA gcs_antenna_analysis | What the tracked directional GCS antenna gives | under 1 min | done (chain finished 29.10 03:19:55) |
| 7 | EDGE edge_map | Committed / not committed verdict at every envelope point | 0.5-2 h | done (chain finished 29.10 03:19:55) |
| 8 | KPI, DASH, WEAK, RPT | KPI summary, dashboard, weak-point analysis, numbers export | about 1 min each | done (chain finished 29.10 03:19:55) |
| 9 | LAT measure_latency | Decision latency per cycle, on an idle machine | 1-6 min | after profile 3 ends, in the takeover's final phase (LAT is not part of the profile 1 chain); it can be hand-run after RPT on the idle machine, then KPI, DASH, WEAK and RPT are rerun |

From C2u's start to RPT: about 15-19 h, plus the restart. The OHP figure comes from smoke runs that shared the machine. The processor boost is off (99%), which slows the stages.

## After profile 1

Order: controlled-bandwidth study (done), profile-1 rerun (ended after C1d), profile 3, cleanup window, folder consolidation, official finish, project book, P1-v2. Calendar dates are in the milestone tables above.

| Step | What | Expected duration | State |
|---|---|---|---|
| CORE_BW | Controlled-bandwidth study: 41 channels at 2401 + 2k MHz, jammer widths tone to 83.5 MHz; the lecturer row is `rule_core3` (the three-state CNN in the loop) against the validation-tuned `blind_core`, `rule_core` (the hybrid) is secondary (D106); branch `core-bw-p1` | 30.10-2.11 (estimate) | Done: test read 30.10, reviewed 31.10 |
| P1R | Profile-1 rerun of C1d, C2 and C2e with a fixed monitor, in an isolated worktree; stops after C1d if the old threshold form is kept (D104) | window 2.11-5.11 (estimate) | Ended after C1d on 31.10 (D104 point 4): no candidate admissible, the class path alone breaks KPI 6's bound; profile 3 answers with D113 (S1G) and D121 |
| Profile 3 deployment | Tests, fusion rerun, detector stages, rehearsal, fourth test set read once; step 7a (decoder on dev set C) | profile 3 as a whole ends about 18-21.11 (estimate) | Done 5.11 (D110-D122) |
| Profile 3 pools | C1p (4 antennas) | 90-105 h (estimate) | From about 6.11 02:00-03:00 |
| Profile 3 maps | SURV map v2 (D100); SURV3 v2 (D101) | 44-50 h; 690-786 min | After C1c |
| Profile 3 decision layer | C1c, C1d, C2, C2e, C2g, C2u, GAL, EDGE, KPI, DASH, WEAK, RPT, then LAT (the takeover's final phase) | profile 1's durations as a guide | After the maps |
| Cleanup window | Behaviour-preserving cleanup of the code tree; the plan and the audit are in `docs/review/code_audit_20261105/`; every batch tested before and after | about 21-25.11 | After profile 3's KPI stage |
| Folder consolidation | One main project folder with topic subfolders | with the window | Before the official finish (about 25-26.11) |
| Project book and presentation | Book with the lecturer's KPI table first, extensions in their own section | book about 26.11-10.12, presentation about 20.12 | After the official finish and Adi's approval |
| P1-v2 (D119) | Profile-1 rerun with the fixes proven in profile 3, on new never-read sets, on the cleaned code; protocol registered on the cleaned code; D120 predictive readings; two unknown-threat candidates (layer-fused Mahalanobis or k-NN on earlier CNN layers; link-budget residual with per-antenna imbalance), chosen on validation | after the book | Moved after the book (Adi, 11.11.2026) |

Profile 3 = four antennas. OHP and GCSA are skipped on it. Profile 2 (two antennas) was dropped on 21.10.2026.

Order and timeboxes: D117 fixes the profile 3 order (KPI 7's speed part is read on the union of the test and second-test single sets as the verdict; Adi approved 31.10.2026 09:02, confirmed 5.11) and D118 the timeboxes (hard limit 24.11, shedding order above). D119 puts P1-v2 after profile 3, and since 11.11 after the project book. D121 items 1-2 (CLT at C1d, P-A at C2) are deployed in profile 3's code. D122 (5.11): profile 3's coded-link decoder stays D78, `fec_rx` "d78".

## Remaining work

**Lecturer's scope**

1. Restart the PC at the C2u to GAL boundary: done on 28.10; the chain was resumed from GAL and finished (RPT 29.10 03:19:55).
2. Lecturer KPIs 5-8 are read: PER reduction MET (committed) in both scenarios (C2e 38.9% and 43.3%; CORE_BW 62.3% and 69.2%); Line B (D99) read 29.10; the CNN contribution against the equally tuned baseline read in CORE_BW on 30.10. Remaining: the latency row (LAT).
3. Profile 1's chain to RPT: done (KPI table, dashboard, report numbers). Latency (LAT) on an idle machine: at the end of profile 3 in the takeover's final phase, or hand-run if Adi decides so.
4. Operator console: the three-state CNN view, the core action set and the deployed policy kind (read from `trained_dqn.mat`) are on branch `gui-core` (not merged; GUI tests 25/25 on 11.11 with the Session Log fix); the console starts from an exported bundle outside the pipeline folder; then a live check with the final agent on a profile-3 copy after RPT, with screenshots.
5. Interim report: draft 7 is complete (38 pages; it follows the proposal Gantt).
6. CORE_BW's receiver-robust line (D2c, about 3-4 h per pass): run before the book quotes CORE_BW's KPI 5 numbers.

**Extensions (no commitment)**

7. The chain's extension stages: combination and unknown-threat generalisation (C2g, C2u), threat gallery (GAL), overhead pass (OHP), GCS antenna analysis (GCSA), envelope verdicts (EDGE), weak points (WEAK). Done on profile 1; running for profile 3 (OHP and GCSA skipped).
8. CORE_BW: the CNN contribution under controlled bandwidth (`rule_core3` against the validation-tuned `blind_core`, D106): done, read once on 30.10.
9. P1R: ended after C1d on 31.10 (D104 point 4); system-level false alarms are taken up by profile 3 (D113, D121) and by P1-v2 (D119).
10. Profile 3 (four antennas): deployed 5.11; the decision-layer chain finished C1p on 12.11 22:51 and finished C1c on 13.11 10:55 and is in SURV, then SURV3 and the decision stages.
11. Weak points: lowest detector class 84.5% (airframe shadowing; per-class 85% accepted for now), unknown-threat AUROC 0.769 against 0.8, noise-burst response.
12. 3D view: parked until the code, the final proposal and the interim report are done.
13. Cleanup window about 21-25.11 (behaviour-preserving), then the folder consolidation; P1-v2 (D119) on the cleaned code after the project book.
14. Labelled side readings after C2e (no verdict changes): D107, D108, D123 (recovery time against the autopilot link-loss failsafe, ArduPilot 5 s and PX4 10 s, with the 0.6 s episode limit).

**Report, book and defense**

15. Project book (final report) with the lecturer's KPI table first, extensions in their own section.
16. Defense: 20-30 min in all including the examiners' questions; a 15-20 minute presentation of at most 12 slides, no literature review or theory slides; Hebrew by default (English only on a written request, and then the defense is in English too). Date set by the faculty coordinators.
17. Poster: not a grade line. A digital poster is made only if the project is selected for the faculty's projects exposure day (about 15 of about 100 projects), on the examiners' and supervisor's recommendation.

## Deviations from the original plan

| Deviation | Reason | Decision |
|---|---|---|
| Ideal receiver replaced by a real one (training, pilots, timing and frequency sync); ideal receiver kept as validation reference | The ideal receiver hid how a real one fails | D7, D73 |
| CNN on spectrogram plus link features; CNN-LSTM kept in `legacy/`; spectrogram-only three-state CNN added for the proposal's KPIs | The LSTM gave no gain for its cost; the proposal asks for a spectrogram CNN | D13, D92 |
| Single-antenna link became three antennas (profile 1) and four (profile 3); profile 2, relay path and altitude axis dropped | Spatial diversity is a real receiver function; the lecturer's sources set the platform | D41, D70, D92 |
| DQN built as Double DQN with shield and escalation, ahead of the optional slot | One-shot decisions could not show recovery over time | D44-D46, D63, D64 |
| Python dropped from the tools | MATLAB covers the whole pipeline | D92 |
| Ten threats, pairs, triples, 36 configurations and the operator console kept as extensions | The lecturer's proposal is the scope; extras carry no commitment | D92 |
| Full run restarted and redone before any test reading | Bugs found before launch and in the alignment field | D83, D87-D89 |
| Software-only stop of profile 1 (25.10.2026 to 26.10.2026) to deploy fixes before C1d | Fixes and lecturer-KPI code needed before the decision layer | D94, D96 |

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| System-level false alarms on clean flights above 5% (12.5-29.9% at C1d) | P1R ended after C1d (D104 point 4); the remedy is built into profile 3 (D113, D121) and P1-v2 rereads it on profile 1 (D119); reported as measured |
| PER target meaningless at 0 and 3 dB (clean packet loss 0.99 and 0.79) | Pre-registered rule: verdict on pooled readings; low-Eb/N0 points reported separately (D99) |
| Noise-burst response worsens the link (BER 0.495 vs 0.439 with no response) | Uncoded answer chosen on validation for profile 1; on profile 3 the JSI decoder was not adopted on dev set C, D78 kept (D122); reported as a weakness (D97) |
| CNN contribution small against the conventional mechanism | Defined as an analysis metric, not a promise; CORE_BW gives hops a frequency geometry (D98) |
| Long run times (C2 took 39.3 h; chain from C2 done to RPT about 18-24 h) | Pre-built frame pools, parallel workers, checkpoints, fixed stage order, takeover recovery after a reboot |
| A restart inside a stage loses that stage's progress | The PC is restarted only at a stage boundary (the chain is stopped as the new stage starts and resumed from it) |
| Low free memory (about 1 GB available on 27.10) and a Windows Update reboot | The restart cleared the memory on 28.10; Windows Update is paused until 30.11.2026; the resume mode and checkpoints cover a reboot |
| Weak classes and unknown-threat score below target | Choices made on validation only; test sets read once; shortfalls reported, not hidden |
| Interim report depends on unfinished results | Report covers the Gantt rows due by month 4; later items only as ahead of schedule |
