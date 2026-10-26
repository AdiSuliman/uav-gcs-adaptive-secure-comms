# Roadmap

Plan, status and remaining work of the UAV-GCS jamming detection and mitigation project, as of 26.10.2026. The scope is the lecturer's revised proposal of 20.10.2026 (D92); everything beyond it is an extension without commitment.

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
| Interim report | 2-4 | In progress | Draft 4 delivered 26.10.2026; draft 5 structure approved; due 01.11.2026 |
| Decision layer: rule-based policy (baseline) | 4-5 | Ahead of schedule | Built and in use; its readings come with the policy evaluation |
| Decision layer: DQN agent (optional) | 5-7 | Ahead of schedule | Training in progress (see Current run) |
| Adaptive Link Recovery and closed-loop integration | 5-7 | Ahead of schedule | Closed loop built; frame pools and survivability runs done on profile 1 |
| Dashboard (GUI) | 6-7 | Ahead of schedule | Operator console built; live check with the v7 agent after DQN training |
| Evaluation on the test set and KPI table | 7-8 | In progress | Detector KPIs read; PER, recovery time, goodput and CNN contribution at the policy evaluation |
| Survivability map and complementary experiments | 7-8 | Ahead of schedule | Profile 1: Map A 81.8%, Map B 91.8%; edge map still to run |
| Project book and presentation | 5-8 | Not started | Final report, defense and poster are last |

## Current run (profile 1)

| Milestone | Expected (estimate, boost off) |
|---|---|
| DQN training (C2) ends | 28.10.2026, about 06:00-12:00 |
| Policy evaluation (C2e): the lecturer's open KPIs are read | 28.10.2026, about 07:00-14:00 |
| Operator console with the v7 agent (Live and Episode tabs) | from the end of C2 |
| Profile 1 chain ends (RPT): KPI table, dashboard, report numbers | 28.10.2026 evening to 29.10.2026 early morning |
| Controlled-bandwidth study (CORE_BW) | 30.10-31.10.2026 |
| Profile-1 rerun with the fixed monitor (P1R) | 2.11-3.11.2026 |
| Profile 3 ends (last extension) | 18.11-21.11.2026 |

Profile 1 = three UAV antennas, branch `v7-dev`. Each stage starts when the previous one ends; the dates come from the measured C2 pace (about 34 min per run, run 10 of 72 started 26.10.2026 21:11) and the stage durations below.

**Done (measured):**

| Stage | Result |
|---|---|
| Detector stages through unseen-severity evaluation | Done; fourth test set read once, core CNN trained and read once on it |
| Frame pools (C1p) | 8692.4 min |
| Clean-link pools and clean reference (C1c) | 911.3 min; reference rebuilt from 300 validation clean flights per Eb/N0 |
| Survivability maps (SURV) | 386.3 min |
| Antenna options (SURV3) | 599.9 min |
| Drop-threshold choice (C1d) | 3.9 min; threshold 4.5 dB |

**Now:** DQN training (C2) started 26.10.2026 16:03: 72 runs of 50,048 episodes (4 monitors x 2 drop settings x 3 false-switch penalties x 3 seeds). Nine runs were finished at 21:11, at about 34 min per run, so about 41 h in all.

**Stages left, in order** (durations are estimates from smoke runs and the earlier full runs; no full-scale v7 run exists yet for these stages):

| # | Stage | What it does | Expected duration | Start |
|---|---|---|---|---|
| 1 | C2 train_dqn | Double DQN grid, choice on validation | about 36 h left, plus 0.5-1.4 h noise-burst evaluations | running |
| 2 | C2e evaluate_policies | Every policy on test pools; the lecturer's PER, recovery-time, goodput and CNN-contribution lines | 1-2 h | after C2 |
| 3 | C2g experiment_combo_generalization | DQN retrained without each combination | 3.6-4.5 h | after C2e |
| 4 | C2u experiment_unknown_threat | Response to a threat never trained on | 2.5-3.5 h | after C2g |
| 5 | GAL threat_gallery | One figure per threat | 5-10 min | after C2u |
| 6 | OHP overhead_pass | UAV flying over the GCS (dipole null) | 3.8-4.7 h | after GAL |
| 7 | GCSA gcs_antenna_analysis | What the tracked directional GCS antenna gives | under 1 min | after OHP |
| 8 | EDGE edge_map | Committed / not committed verdict at every envelope point | 0.5-2 h | after GCSA |
| 9 | KPI, DASH, WEAK, RPT | KPI summary, dashboard, weak-point analysis, numbers export | about 1 min each | after EDGE |
| 10 | LAT measure_latency | Decision latency per cycle, on an idle machine | 1-6 min | after RPT |

From 26.10.2026 evening to the end of RPT: about 48-55 h. The OHP figure comes from smoke runs that shared the machine. The processor boost is off (99%), which slows the stages.

## After profile 1

Order: controlled-bandwidth study, profile-1 rerun, profile 3. Calendar dates are in the milestone table above.

| Step | What | Expected duration | Start |
|---|---|---|---|
| CORE_BW | Controlled-bandwidth study: 41 channels at 2401 + 2k MHz, jammer widths tone to 83.5 MHz, `rule_core` vs `blind_core`; branch `core-bw-p1` | about 1.5-2 days (planning estimate) | after RPT of profile 1 |
| P1R | Profile-1 rerun of C1d, C2 and C2e with a fixed monitor, in an isolated worktree; stops after C1d if the old threshold form is kept (D104) | 44-49 h at 72 runs | after CORE_BW |
| Profile 3 deployment | Tests, fusion rerun, detector stages, rehearsal, fourth test set read once | not estimated | after P1R |
| Profile 3 pools | C1p (4 antennas) | 90-105 h (estimate) | after deployment |
| Profile 3 maps | SURV map v2 (D100); SURV3 v2 (D101) | 44-50 h; 690-786 min | after C1c |
| Profile 3 decision layer | C1c, C1d, C2, C2e, C2g, C2u, GAL, EDGE, KPI, DASH, WEAK, RPT, then LAT | profile 1's durations as a guide | after the maps |

Profile 3 = four antennas. OHP and GCSA are skipped on it. Profile 2 (two antennas) was dropped on 21.10.2026.

## Remaining work

**Lecturer's scope**

1. Finish DQN training (C2) and run the policy evaluation (C2e).
2. Read the lecturer's four open KPIs at the policy evaluation (C2e): PER reduction (target at least 30% vs the static link), recovery time, goodput, CNN contribution vs the conventional adaptive mechanism.
3. Finish profile 1's chain to RPT: the KPI table (KPI), the dashboard (DASH) and the report numbers (RPT) are proposal deliverables; latency (LAT) on an idle machine after it.
4. Operator console: add the three-state CNN view and the core action set, then a live check with the v7 agent from a copy outside the pipeline folder, and screenshots.
5. Submit the interim report on 01.11.2026 (draft 5 follows the proposal Gantt).

**Extensions (no commitment)**

6. The chain's extension stages: combination and unknown-threat generalisation (C2g, C2u), threat gallery (GAL), overhead pass (OHP), GCS antenna analysis (GCSA), envelope verdicts (EDGE), weak points (WEAK).
7. CORE_BW: the CNN contribution under controlled bandwidth.
8. P1R: bring system-level false alarms on clean flights below 5% (12.5-29.9% at C1d); the verdict comes from a fresh clean test set (our KPI 6, not a lecturer KPI).
9. Profile 3 (four antennas): full decision-layer chain.
10. Weak points: lowest detector class 84.5% (airframe shadowing; per-class 85% accepted for now), unknown-threat AUROC 0.769 against 0.8, noise-burst response.
11. 3D view: parked until the code, the final proposal and the interim report are done.

**Report, book and defense**

12. Project book (final report) with the lecturer's KPI table first, extensions in their own section.
13. Defense: 20 + 10 min, English, at most 12 slides.
14. Poster (5% of the grade).

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
| System-level false alarms on clean flights above 5% (12.5-29.9% at C1d) | P1R with a fixed monitor; verdict from a fresh clean test set; reported as measured (D103, D104) |
| PER target meaningless at 0 and 3 dB (clean packet loss 0.99 and 0.79) | Pre-registered rule: verdict on pooled readings; low-Eb/N0 points reported separately (D99) |
| Noise-burst response worsens the link (BER 0.495 vs 0.439 with no response) | Uncoded answer chosen on validation for profile 1; JSI decoder for profile 3; reported as a weakness (D97) |
| CNN contribution small against the conventional mechanism | Defined as an analysis metric, not a promise; CORE_BW gives hops a frequency geometry (D98) |
| Long run times (C2 about 41 h; chain 48-55 h) | Pre-built frame pools, parallel workers, checkpoints, fixed stage order, takeover recovery after a reboot |
| Weak classes and unknown-threat score below target | Choices made on validation only; test sets read once; shortfalls reported, not hidden |
| Interim report depends on unfinished results | Report covers the Gantt rows due by month 4; later items only as ahead of schedule |
