# Roadmap

Plan, status and remaining work of the UAV-GCS jamming detection and mitigation project, as of 25.11.2026 (about 08:00). The scope is the lecturer's revised proposal of 20.10.2026 (D92); everything beyond it is an extension without commitment. Schedule: every date below that is not a measured one comes from `worktrees\session_notes_0ff3\core\finish_plan.md`, the single schedule source (official finish about 29.11, book about 3-4.12, presentation about 7.12). KPI names: the lecturer's L1-L8 and the project's own P-1..P-10.

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
| Decision layer: rule-based policy (baseline) | 4-5 | Done | Built and in use; its readings come with the policy evaluation; D124 adopted the layered answers (`keep+st+rate`) on 19.11 as a labelled column |
| Decision layer: DQN agent (optional) | 5-7 | Done | Trained; chosen on validation: held recovery 82.6%, recovered 95.1% against 60.3% and 71.3% for the best rule setting; test reading (C2e): recovered 94.1% [92.7, 95.4] |
| Adaptive Link Recovery and closed-loop integration | 5-7 | Done | Closed loop built; frame pools, survivability runs and the decision-layer chain done on profile 1 (29.10) and profile 3 (18.11) |
| Dashboard (GUI) | 6-7 | Built, live check pending | Operator console built; GUI tests 25/25 on profile 1 (branch `gui-core`, 11.11) and 25 of 25 on profile 3 (`gui-on-p3`, 18.11); the live check with the final agent runs once on the final code line after B1 (done 22.11) and B2, profile 1 first (see item 4) |
| Evaluation on the test set and KPI table | 7-8 | In progress | Detector L-rows read; policy evaluation read 28.10: L5 PER reduction MET (committed), `rule_core` core 38.9% and 43.3% (profile 1), CORE_BW `rule_core3` narrowband 62.3% and wideband 69.2%; profile 3's chain done 18.11 (core 40.7% and 46.3%); D2c done 18.11 22:44; D124 adoption 19.11; LAT done 20.11 (P-7 MET, D126); CORE_BW rule fix read once 21.11 (L5 narrowband 74.0%, wideband 71.4% with keep+rate, a side reading beside the registered rows); the lecturer table L1-L8 for both profiles built from saved files 22.11 (`worktrees\session_notes_0ff3\core\lect_table`, 317 numbers checked against their source lines); next: A6, the final lecturer table and chain rerun after D125's read (`worktrees\session_notes_0ff3\core\finish_plan.md`) |
| Survivability map and complementary experiments | 7-8 | Done | Profile 1: Map A 81.8%, Map B 91.8%; profile 3: Map A 80.0%, Map B 92.9%; edge map done (profile 1 29.10; profile 3 18.11: 21 of 300 single points COMMITTED, 0 of 252 combined) |
| Project book and presentation | 5-8 | Chapters on the final parts start 22.11 | Book drafted from 22.11 on the final parts, numbers from a frozen numbers file; the book goes to Adi after the official finish (about 29.11) and his approval: book about 4-5.12, presentation about 7.12 (`worktrees\session_notes_0ff3\core\finish_plan.md`) |

## Current run (profile 3)

| Milestone | State (estimate, boost off) |
|---|---|
| Deployment tests, fusion rerun, detector stages (smoke 55 steps, 0 errors; B-stage rerun B2F B3 B3a B4 B4s 13:54-17:48 on 5.11, rc=0; deploy state `deployed`) | done 5.11.2026 |
| Fresh2 rehearsal against the registered limits (fault F1 91.0 >= 88, macro-F1 above threshold 95.14 >= 94.5, clean as threat 2.54 <= 2.61) | passed 5.11.2026 |
| B3r: fourth test set read once (P-1 macro-F1 above the 0 dB threshold 94.92% [94.47, 95.31], target 90%; fault F1 89.9%; clean as threat 2.94%); record commit `35a4b66` | done 5.11.2026 |
| Step 7a, decoder on dev set C: the JSI decoder not adopted, `fec_rx` is d78 (D122) | done 5.11.2026 |
| D111 OOD select (hand run), OOD read, release check | done 5.11.2026 |
| C1p (4 antennas): frame pools, 93 cells | started 5.11 22:44 (resumed 7.11 and 8.11 with its kept cells); 56 of 93 on 11.11 15:56, 74 of 93 on 12.11 07:00 (24 cells on 11.11); done 12.11.2026 22:51 (867.9 min after the 08:22 resume; pools 15.9 GB) |
| C1c: clean-link pools and check cells | started 12.11 22:51; validation 106.1 min, test 110.5 min, check cells 478.1 min; done 13.11.2026 10:55 (724.4 min; profile 1 911.3). Clean reference rebuilt from 300 validation flights per Eb/N0: BER 1.6-4.8 times below profile 1's |
| SURV map v2 (D100), profile 3 | started 13.11 10:55; power loss about 16:10 with 23 of 154 jobs saved, resumed 16:48 with all 23 kept; done 14.11.2026 13:32 (1243.5 min): map A 80.0%, map B 92.9% |
| SURV3 v2 (D101), profile 3 | done 14.11.2026 22:26 (534.3 min): four antennas keep the link in 75.0% of combined-threat geometries against 67.9% with three |
| C1d, profile 3 | done 14.11.2026 22:34 (7.9 min): drop threshold 4.5 dB, CUSUM drop alarm at 126 dB^2 |
| C2, profile 3 (99 runs: 11 monitor settings, 3 penalties, 3 seeds) | started 14.11 22:34; power loss 15.11 about 08:41 with 17 runs saved; resumed 18:33 with the 17 read; done 17.11 19:35 (2942.3 min, with the coordinate steps, reward scales and D107 runs): DQN held 84.7%, recovered 95.9% against the rule's 70.2% and 76.3%; false-alarm bound met (deployed form 436.7 false changes per hour, limit 470); Opus check: nothing invalidates C2e |
| Code merged into `v7-p3` during C1p (C1p calls none of the changed files) | `acc2ab0` 10.11 (full suite 585/585); `fb487f8` 11.11 (`profile.json` only: `run_cache` on, approved by Adi); `8cfb172` 11.11 (windows D/E: bounded-search log lines, lecturer KPIs per Eb/N0 and the receiver-robust column, the system false-alarm breakdown, the clean K6 split, SURV kept jobs keyed on the code; suite 619/620, the one wrong test expectation fixed, 13/13) |
| C2e, C2g, C2u, GAL, EDGE, KPI, DASH, WEAK, RPT | C2e done 17.11 22:30 (174 min): the extension pair `rule_esc` 52.7% and 48.7%, the L5 core rule (`rule_core`) 40.7% and 46.3% MET (committed), P-4 22 of 23 threats inside the envelope (21 of 24 at every level; `kpi_summary.txt:51-52`), P-6 3.87% (bound 4.59%); C2g done 18.11 05:11 (402 min): never-trained combinations 93.8% (profile 1 90.6%), trained 95.6%; C2u done 10:28 (316 min): threat never trained 81.5% as the mean over threats (profile 1 68.0%), trained 88.2%, rule with escalation 82.0%; EDGE done 18:01 (448 min, the overhead pass included): LINK COMMITTED at 12 and 15 dB as predicted, 21 single points COMMITTED (15 attributable to the decision layer); P-1, P-5, P-6 MET, P-2 and P-4 NOT MET (P-7 read after LAT, 20.11); chain ended rc=0 18.11 18:09; archive done; D2c v2 done 18.11 22:44 |
| Profile 3 chain ended | 18.11.2026 18:09 (rc=0); the D118 hard limit of 24.11 was not reached, so nothing was shed |
| Finish phase | `final.hold` written 17.11 (E11), lifted 19.11 13:54: after RPT the SHA-256 archive of the first reading (done), D2c v2 (done 18.11 22:44: U_s narrowband 22.0%, wideband 7.2%, every primary L8 verdict receiver-robust), the GUI tests on `gui-on-p3` (25 of 25), the `rule-fix` tests and the D124 readings; LAT, KPI, DASH, WEAK and RPT then ran on both profiles. Done since: B1 (22.11) and A5 (22.11), see the rows below. Still ahead (order in `worktrees\session_notes_0ff3\core\finish_plan.md`): the D125 read and gate, A6, B2, the GUI live check on the final code line, tags and the numbers freeze, the behaviour-preserving cleanup on a branch (gates neither the finish nor the book), the folder consolidation |
| Final phase, adoptions and P-7 (19-20.11) | Final phase done 19.11 on both profiles (P1 14:50, P3 15:43). D124 adopted on both profiles (overlay stages all PASS): rule + escalation recovered 66.8->77.0% (P1) and 70.9->79.7% (P3); P-5 still MET at +17.1 / +15.6 points. D126: the P-7 guards ACCEPTED (bit-identical) on both profiles; the single final LAT..BUNDLE rerun on 20.11 00:16-00:41: P-7 MET on both, P1 median 8.52 ms / p95 12.25 ms, P3 8.87 / 12.68 ms (before: 10.94 / 13.53 and 11.09 / 13.64). Both readings are kept for the book. |
| Profile 3 readers (21.11) | `lect_kpis_by_ebno` (6 min) and `system_fa_breakdown` (5 min) done 22:08 and 22:13, both GATE PASS; Line A reproduces C2e (core 40.7% and 46.3%); per Eb/N0: 0 and 3 dB NOT MET (link-limited), 6 dB committed / not committed, 9-15 dB committed |
| CORE_BW rule fix (D124 point 6), 21.11 | Validation 22:12 (9.2 min): `keep+rate` bound; test read once 22:44-23:12 (27.2 min, off reproduced exactly, draws 82100): L5 `rule_core3` narrowband 74.0% [73.2, 74.6], wideband 71.4% [70.4, 72.3] with keep+rate and the registered rows 62.3% and 69.2% standing; L8 absolute PER difference narrowband -0.0169, wideband -0.0481 (registered +0.0807, -0.0551). Review: valid with notes; goodput and recovery time not read under the setting; D2c needs no rerun |
| Side readings (21.11) | D123 failsafe line, D107 harmed geometries, D121 item 15 (12.8% of clean test flights meet the hiding condition), D116 item 5, D108 point 6 at complex rho U[0.45, 0.79] (no LINK verdict moves); labelled, nothing decided on them; D121 item 12 on profile 1 and the REC/PROT design effect of D108 recorded as not readable without a pool rebuild |
| D125 fresh test-pool build, profile 3 slot | Paused 19.11 13:55 at 11 of 93 cells (corrected cost 2-4 days, about 5 worker-hours per cell); resumed 21.11 23:33 (gate 43 GB at 44.4 GB free commit, memory watch alerting below 3 GB); ETA 24.11 evening to 25.11, allow one power cut (26.11). Then clean set w19 (about 1.9 h), the single test read, the confirmation gate. Extension rows only |
| Independent review (Fable 5.2, 21.11 23:55) | Changes are in the "Changes from the Fable review" section of `worktrees\session_notes_0ff3\core\finish_plan.md`: official 16-risk proposal copy, verdict mapping D105/D106, the lecturer table first from saved outputs, a reader of the rule rows on profile 3's fresh pools registered before it is read, freeze and tags before cleanup, L/P names everywhere |
| B1, code merge (22.11 18:40) | Branch `final-line` `ba3f567`, local: steps 1-5, 7-14 and 16 merged; `lbs-p1` and `lect-p1` kept as as-run tags and reproduced from them; every step's suites 0 failed apart from as-run pins filtered with their reasons (PROJECT_LOG 22.11 18:40) |
| A5, P-2 and P-4 re-audit (22.11 19:10) | Branch `a5-screen` `2f9fd77`, validation only, no test set read; no candidate reaches the target within P-6, so none is registered for a test read; P-2 0.769 / 0.763 and P-4 antenna_fault 78.9% / 86.8% stand as registered, NOT MET; P1-v2 items V1-V7 (D119 dated line) |
| Official finish of code and results | about 28.11.2026 (`worktrees\session_notes_0ff3\core\finish_plan.md`); then the project book after Adi's approval |
| P1-v2 (D119) | after the project book (Adi, 11.11.2026); about 12 days after it per `worktrees\session_notes_0ff3\core\finish_plan.md` |
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
| Operator console with the v7 agent (Live and Episode tabs) | live check from an exported bundle outside the pipeline folder, driven by script with screenshots and a clip for Adi: planned once on the final code line after B2, profile 1 first (bundle rx3, the three-state view), then profile 3 (rx4); the 20.11 bundles lack `clean_ref` and `core_cnn_model.mat` and are re-exported first |
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

**Now (25.11.2026):** B1-R reproduced every registered number on both profiles (24.11). A6 on 25.11: the P1 adoption chain with the D126 latency (KPI 7 MET 8.52 / 12.25 ms), the adopted G5 readings on both profiles and the CORE_BW G4 reading passed their gates, and the lecturer table is rebuilt (440 rows, two-way check PASS). Running: B3 final console captures. Next: table review, B4 frozen numbers and releases (25-26.11), B5 tags and backup (26.11), B2 cleanup (26-27.11), B6 and B7 (about 27.11), official finish about 28.11; book about 3-4.12, presentation about 7.12.

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
| 9 | LAT measure_latency | Decision latency per cycle, on an idle machine | 1-6 min | done 20.11 (D126 final rerun, P-7 MET on both profiles) |

From C2u's start to RPT: about 15-19 h, plus the restart. The OHP figure comes from smoke runs that shared the machine. The processor boost is off (99%), which slows the stages.

## After profile 1

Order: controlled-bandwidth study (done), profile-1 rerun (ended after C1d), profile 3 (chain done), D125 build (B1 and A5 done 22.11), B2, GUI live check on the final code line, tags and numbers freeze, cleanup on a branch, folder consolidation, official finish, project book, P1-v2. Calendar dates are in the milestone tables above and in `worktrees\session_notes_0ff3\core\finish_plan.md`.

| Step | What | Expected duration | State |
|---|---|---|---|
| CORE_BW | Controlled-bandwidth study: 41 channels at 2401 + 2k MHz, jammer widths tone to 83.5 MHz; the lecturer row is `rule_core3` (the three-state CNN in the loop) against the validation-tuned `blind_core`, `rule_core` (the hybrid) is secondary (D106); branch `core-bw-p1` | 30.10-2.11 (estimate) | Done: test read 30.10, reviewed 31.10 |
| P1R | Profile-1 rerun of C1d, C2 and C2e with a fixed monitor, in an isolated worktree; stops after C1d if the old threshold form is kept (D104) | window 2.11-5.11 (estimate) | Ended after C1d on 31.10 (D104 point 4): no candidate admissible, the class path alone breaks P-6's bound; profile 3 answers with D113 (S1G) and D121 |
| Profile 3 deployment | Tests, fusion rerun, detector stages, rehearsal, fourth test set read once; step 7a (decoder on dev set C) | done 5.11 | Done 5.11 (D110-D122) |
| Profile 3 pools | C1p (4 antennas) | 90-105 h (estimate) | From about 6.11 02:00-03:00 |
| Profile 3 maps | SURV map v2 (D100); SURV3 v2 (D101) | 1243.5 min; 534.3 min | Done 14.11 |
| Profile 3 decision layer | C1c, C1d, C2, C2e, C2g, C2u, GAL, EDGE, KPI, DASH, WEAK, RPT, then LAT (the takeover's final phase) | profile 1's durations as a guide | Done 18.11 18:09 (LAT 20.11) |
| Cleanup window | Behaviour-preserving cleanup of the code tree; the plan and the audit are in `docs/review/code_audit_20261105/`; every batch tested before and after | after the as-run tags and the numbers freeze (`worktrees\session_notes_0ff3\core\finish_plan.md`) | Planned; runs on a branch and gates neither the official finish nor the book |
| Folder consolidation | One main project folder with topic subfolders | after the cleanup | Before the official finish (about 28.11) |
| Project book and presentation | Book with the lecturer's KPI table first, extensions in their own section | book about 4-5.12, presentation about 7.12 (`worktrees\session_notes_0ff3\core\finish_plan.md`) | Chapters on the final parts from 22.11; delivered after the official finish and Adi's approval |
| P1-v2 (D119) | Profile-1 rerun with the fixes proven in profile 3, on new never-read sets, on the cleaned code; protocol registered on the cleaned code; D120 predictive readings; two unknown-threat candidates (layer-fused Mahalanobis or k-NN on earlier CNN layers; link-budget residual with per-antenna imbalance), chosen on validation | after the book | Moved after the book (Adi, 11.11.2026) |

Profile 3 = four antennas. OHP and GCSA are skipped on it. Profile 2 (two antennas) was dropped on 21.10.2026.

Order and timeboxes: D117 fixes the profile 3 order (P-7's speed part is read on the union of the test and second-test single sets as the verdict; Adi approved 31.10.2026 09:02, confirmed 5.11) and D118 the timeboxes (hard limit 24.11, shedding order above). D119 puts P1-v2 after profile 3, and since 11.11 after the project book. D121 items 1-2 (CLT at C1d, P-A at C2) are deployed in profile 3's code. D122 (5.11): profile 3's coded-link decoder stays D78, `fec_rx` "d78".

## Remaining work

**Lecturer's scope**

1. Restart the PC at the C2u to GAL boundary: done on 28.10; the chain was resumed from GAL and finished (RPT 29.10 03:19:55).
2. L5-L8 are read: L5 PER reduction MET (committed) in both scenarios (C2e core 38.9% and 43.3%; CORE_BW `rule_core3` 62.3% and 69.2%); Line B (D99) read 29.10; L8 against the equally tuned baseline read in CORE_BW on 30.10; L6 and L7 measured; latency (P-7) read in the final LAT (20.11, MET on both profiles). The verdict pair is `rule_core` and `rule_core3` against `none` and `blind_core` (D105, D106); `rule_esc` and `blind_esc` are an extension. Remaining: the final lecturer table for both profiles (A6-L), the book's 16-row mitigation table.
3. Profile 1's chain to RPT: done (KPI table, dashboard, report numbers). Latency (LAT): done 20.11 on an idle machine in the final rerun (D126).
4. Operator console: the three-state CNN view, the core action set and the deployed policy kind (read from `trained_dqn.mat`) are on branch `gui-core` (GUI tests 25/25 on 11.11; 25 of 25 on `gui-on-p3` 18.11); the console starts from an exported bundle outside the pipeline folder. The live check with the final agent runs once on the final code line after B1 (done 22.11) and B2 (the rx4 console peaked at 18.7 GB commit, too heavy beside the 6-worker build), profile 1 first (rx3, with the three-state view), then profile 3; screenshots and a clip for Adi only. Before it: resolve the gui-core and final-code conflict in `clean_ber_ref.m`, re-export the bundles with the gui-core exporter. Profile 3 has no three-state CNN model and the console says so.
5. Interim report: draft 7 is complete (38 pages; it follows the proposal Gantt).
6. CORE_BW's receiver-robust line (D2c): done 18.11 22:44 (guards G1-G4 PASS; U_s narrowband 22.0%, wideband 7.2%; every primary per-type PER-reduction verdict receiver-robust). The CORE_BW rule fix of D124 point 6 needs no D2c rerun (a policy-independent census).

**Extensions (no commitment)**

7. The chain's extension stages: combination and unknown-threat generalisation (C2g, C2u), threat gallery (GAL), overhead pass (OHP), GCS antenna analysis (GCSA), envelope verdicts (EDGE), weak points (WEAK). Done on profile 1; running for profile 3 (OHP and GCSA skipped).
8. CORE_BW: the CNN contribution under controlled bandwidth (`rule_core3` against the validation-tuned `blind_core`, D106): done, read once on 30.10.
9. P1R: ended after C1d on 31.10 (D104 point 4); system-level false alarms are taken up by profile 3 (D113, D121) and by P1-v2 (D119).
10. Profile 3 (four antennas): deployed 5.11; C1p done 12.11, C1c 13.11, SURV, SURV3 and C1d 14.11; C2 done 17.11 19:35; the chain ended 18.11 18:09 (rc=0). Selected on validation: the DQN holds 84.7% of episodes to the end and recovers 95.9% (profile 1 82.6% and 95.1%); the best rule setting 70.2% and 76.3% (profile 1 60.3% and 71.3%).
11. Weak points: lowest detector class 84.5% (airframe shadowing; per-class 85% accepted for now), unknown-threat AUROC 0.769 against 0.8, noise-burst response.
12. 3D view: parked until the code, the final proposal and the interim report are done.
13. Cleanup (behaviour-preserving) on a branch after the as-run tags and the numbers freeze, then the folder consolidation; P1-v2 (D119) on the cleaned code after the project book. Dates: `worktrees\session_notes_0ff3\core\finish_plan.md`.
14. Labelled side readings after C2e (no verdict changes): D107, D108, D123 (recovery time against the autopilot link-loss failsafe, ArduPilot 5 s and PX4 10 s, with the 0.6 s episode limit): read 21.11 (see the Current run table).

15. D124 (approved by Adi 15.11, registered before any reading): the rule's layered answers (keep with a short stay, a link-budget rate step, a predicted-ACR channel match, coding on a lost-branch answer) on branches `rule-fix` and `core-bw-rule-fix`; read after the chain, validation first, test once; adopted only by its registered rule. Profile 3 validation (18.11): keep+st+rate adopted (rule with escalation held 70.2% to 77.8%), fec on a lost branch not adopted. Profile 1 validation (18.11, 8 threads as C2 ran): keep+st+rate adopted (held 60.3% to 69.8%), keep+st and fec not. Test readings done (read once each, every off row reproduced exactly): rule + escalation PER reduction profile 3 narrowband 52.7% to 59.2%, wideband 48.7% to 53.8%; profile 1 45.9% to 51.7% and 41.0% to 47.1%; CNN contribution to PER now positive on both (+12.2%, +15.0%); goodput falls by about 1.6-2.5 kb/s (the rate step). CORE_BW bound to profile 1's selection: done 21.11 (keep+rate, L5 narrowband 74.0% and wideband 71.4%, a side reading beside the registered 62.3% and 69.2%). Adopted by Adi 19.11 (overlay stages PASS on both profiles); the adopted rows are a labelled column, the registered rows lead the book.
16. Next version (disclosed in the book): the two DQN bugs (a time-limit end treated as terminal; the checkpoint scored with escalation while the plain agent is deployed) and the realism items (shadowing on both receivers, spoofer CFO, ACR 30 dB), with a pool rebuild.
17. Two experiments Adi approved (11.10 and 15.10), after the full run and separate from the pipeline: (a) long flights of 1-2 min with shadowing tied to manoeuvres, and a slow diagnosis layer (seconds to minutes) that tells antenna fault from airframe shadowing; the fast decision window stays as is; (b) a "learning with experience" campaign: many threats in every condition over rounds; between rounds the system learns new classes and the configurations that worked from its own escalation outcomes, and the DQN is updated offline under the same validation gates and shield; each round is measured on new held-out flights to show a learning curve; no self-modification in flight.

18. Final phase of 21.11 (order and dates in `worktrees\session_notes_0ff3\core\finish_plan.md`): the lecturer table L1-L8 for both profiles from saved outputs first (registered rows lead, D124-adopted rows as a labelled column "second reading of the test flights"); a reader of the rule rows on profile 3's fresh pools, registered before they are read (profile 1 has no fresh set); side lines from saved files (L3 at system level for `rule_core3`, per-bandwidth goodput and recovery-time differences, the test-set confusion matrix of the three-state CNN); the D125 read and gate; tags and the numbers freeze before the cleanup.

19. Profile 3 weak points found at C2e (17.11), not covered by a registered item; each needs a fix chosen on validation and read once on a fresh test set: (a) the deployed DQN on harmed lost-branch episodes (antenna fault 32.9%, airframe shadowing 5.9%, against 82.9% and 47.1% for the ungated rule); candidate: a harm-evidence escalation for the DQN, with a validation criterion that includes the harmed lost-branch episodes; (b) C2e's comb stress set (jamming and reactive jamming followers on every usable channel, so only space and link budget help), deployed DQN 73.4% against profile 1's 81.9% (validation look first); (c) from C2g (18.11): never-trained path-loss combinations 87.1% against 92.5% trained; candidates: a rate_reduce step in the link-budget completion when the deficit exceeds the proposal's gain, and single path_loss episodes at all severities kept in every retraining; (d) from C2u (18.11, evidence only): a threat never trained on, noise_burst 43.7% and path_loss 58.5% (73.5% with the completion), the same two as in profile 1 (30.1% and 22.0%); candidate: a residual-error fallback in the completion (burst-pattern errors after an answer lead to fec_interleave), chosen on validation like (a)-(c). Approved by Adi 18.11 ("Yes, fix them"); registered as D125 (18.11); branch weak19 (0f8bcdf, a93fcfe), validation 19.11: dqn_hop=rule adopted (comb set +13.25 points), dqn_harm not adopted (7 clusters, P-6 bound 6.1%), lb_more not adopted; the fresh test-pool build was paused 19.11 13:55 at 11 of 93 cells (the 4.3 h estimate scaled the last resume, not C1p's total; corrected cost 2-4 days, about 5 worker-hours per cell on 6 workers), resumed 21.11 23:33, ETA 24.11 evening to 25.11; then the clean set w19 (about 1.9 h), the single test read and the confirmation gate. With one adopted step (dqn_hop) Holm reduces to a plain one-sided 0.05 test. D125 changes deployed-DQN (extension) rows only.

**Report, book and defense**

20. Project book (final report) with the lecturer's KPI table first, extensions in their own section.
21. Defense: 20-30 min in all including the examiners' questions; a 15-20 minute presentation of at most 12 slides, no literature review or theory slides; Hebrew by default (English only on a written request, and then the defense is in English too). Date set by the faculty coordinators.
22. Poster: not a grade line. A digital poster is made only if the project is selected for the faculty's projects exposure day (about 15 of about 100 projects), on the examiners' and supervisor's recommendation.

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
| Commit shortage (free commit 42-44 GB on 21.11 with desktop use at 22.8 GB, against the 45 GB gate) and a Windows Update reboot | The wrapper's gate may be lowered to the measured free commit minus a margin (DECISIONS, 21.11), with a memory watch alerting below 3 GB; cells are saved whole; Windows Update is paused until 30.11.2026; the resume mode and checkpoints cover a reboot |
| Weak classes and unknown-threat score below target | Choices made on validation only; test sets read once; shortfalls reported, not hidden |
| Interim report depends on unfinished results | Report covers the Gantt rows due by month 4; later items only as work beyond the rows due |
