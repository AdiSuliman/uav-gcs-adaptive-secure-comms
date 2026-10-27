# AI-Assisted Adaptive UAV-to-Ground Station Communication System for Jamming Detection and Mitigation

Capstone project, course 50076 (HIT, Faculty of Electrical Engineering). Students: Adi Suliman, Bar Dvir Hassan. Supervisor: Golan Ein-Tzvi. Platform: MATLAB R2026a and Simulink.

A simulated UAV-to-GCS radio link detects narrowband and wideband jamming with a CNN on spectrograms and recovers with a rule-based mechanism (channel switch, rate adaptation). The loop is closed and measured: detect, classify, act, re-measure. Three configurations are compared under identical conditions: a static link, a conventional adaptive link (link metrics only) and a CNN-based adaptive link. The inputs are RF measurements only.

The scope is the lecturer's revised proposal of 20.10.2026. Everything else in the repository is an extension without commitment (see [Extensions](#extensions-no-commitment)).

## Status at a glance

Status as of 27.10.2026. Every "met" verdict is on data never used for training or selection, read once. Intervals are 95% bootstrap.

| Proposal deliverable | Status |
|---|---|
| 1. Simulation environment, validated BER model | Done |
| 2. Labelled spectrogram dataset and trained CNN | Done |
| 3. Rule-based adaptive recovery | Built; evaluation pending (stage C2e) |
| 4. Closed-loop integration | Built; evaluation pending (stage C2e) |
| 5. Static vs conventional adaptive vs CNN-based adaptive | Pending; the preceding training stage (C2) is running and ends about 07:00-09:30 on 28.10.2026 (estimate); the evaluation follows it |
| 6. Graphs, confusion matrix, comparison tables, summary report | After the evaluation |

| Lecturer KPI | Status |
|---|---|
| BER model against theory | Met |
| Macro-F1 >= 85% | Met |
| False alarms in clean states <= 5% | Met (detector level) |
| Recall >= 85% per jamming type | Met |
| PER reduction >= 30% against the static link | Pending |
| Recovery time, goodput, CNN contribution | Pending (reported, no target) |

## Scope

**Purpose.** An adaptive UAV-to-GCS link that detects and classifies jamming and recovers from it, evaluated in a closed loop in MATLAB/Simulink.

**Research question.** Does CNN classification of jamming of different bandwidths, together with adaptive recovery, improve link reliability against a static link and against a recovery mechanism based on link-quality metrics only?

**Threats in scope.** Clean link, narrowband jamming, wideband jamming, at several JSR levels with controlled bandwidth and power. In code, narrowband is `tone_jamming` and wideband is `jamming` (barrage).

**Compared configurations.**

| Configuration | Code name |
|---|---|
| Static link | `none` / `no_action` |
| Conventional adaptive (link metrics only) | `blind_core` on the core action set (channel switching, rate reduction); `blind_esc` on the 36 configurations is an extension (D105) |
| CNN-based adaptive | `rule_core3`: the proposal's three-state CNN drives the rule on the core action set, in the controlled-bandwidth study CORE_BW (the lecturer's verdict row, D106). `rule_core` reads the hybrid detector (C2e, secondary); `rule_esc` on the 36 configurations is an extension (D105) |

**Platform (profile 1).** One trained system for UAVs up to the close-range class of Tlili et al. (up to 50 km), three omnidirectional antennas on a 1.2 m aperture, speeds 29-161 km/h, one tracked directional antenna at the GCS. Profile 2 (two antennas) was dropped on 21.10.2026. Profile 3 (four antennas) is an extension.

**Inputs.** RF measurements only: no IMU, no GNSS. Distance, altitude, speed and angles are simulated through their RF effect.

## How it works

Four layers; the stage names are the ones used by `run_stage`.

| Layer | What it does |
|---|---|
| 1. Link and threat simulation | Simulink link (QPSK, 1 Msym/s, 2.4 GHz, Rician fading with Doppler, delay line, hover and turns) with a real receiver (synchronisation, channel estimation, MRC/MMSE combining). Threat injection with seeded sub-runs. BER validated against theory. |
| 2. Detection | 128x128 spectrograms (plus 23 link features for the extended 11-class monitor). The proposal's three-state CNN (clean / narrowband / wideband) uses spectrograms only; temporal fusion over the last N cycles. |
| 3. Decision | Rule-based policy (channel switch, rate adaptation), a conventional baseline on link metrics only, and, an optional Double DQN with a safety shield (an optional item in the proposal's plan, not a KPI). |
| 4. Closed loop and evaluation | Frame pools measured through the real link; every policy is evaluated on test flights never used in training; KPIs, survivability maps, latency, dashboard. |

Stages in pipeline order:

| Stage | Function | What it does |
|---|---|---|
| A0 | `init_params` | Parameters |
| A4v | `validate_phy` | BER against theory, seeds reproducibility |
| A5 | `run_dataset_sweep` | Seeded sub-runs through the Simulink link: 121,968 frames from 5,808 sub-runs (splits 81,312 / 20,328 / 20,328) |
| A6 | `extract_spectrograms` | Spectrograms and link features |
| B1-B2 | `prepare_data`, `train_detector` | Split by sub-run; extended detector |
| B2F | `select_fusion` | Temporal fusion |
| B3, B3n, B3m, B3q, B3r | `eval_detector`, `build_fresh_test*`, `read_fresh_test3` | Test readings on independent test sets (fourth set read once) |
| B3a | `compare_architectures` | Hybrid vs spectrogram-only, features-only, random forest, SVM |
| B3c | `train_core_cnn` | The proposal's three-state CNN, read once on the fourth test set |
| B4, B4s, OOD | `eval_unseen_snr`, `eval_unseen_severity`, `eval_ood_detection` | Unseen Eb/N0, unseen severities, unknown-threat study |
| C1p, C1c | `build_policy_pools`, `build_clean_test_pools` | Frame pools of every threat, configuration, Eb/N0 and geometry through the real link; clean-link pools |
| SURV, SURV3 | `map_survivability_boundary`, `experiment_survivability_options` | Survivability maps; 3 vs 2 antennas |
| C1d | `choose_drop_threshold` | Drop-alarm threshold and whole-monitor false-alarm analysis |
| C2 | `train_dqn` | DQN grid, selection on validation |
| C2e | `evaluate_policies` | Every policy on test pools; lecturer KPIs 5-8 through `lect_kpis.m` |
| C2g, C2u | `experiment_combo_generalization`, `experiment_unknown_threat` | Generalisation to unseen combinations and threats |
| GAL, OHP, GCSA, EDGE | `threat_gallery`, `overhead_pass`, `gcs_antenna_analysis`, `edge_map` | Threat gallery, overhead pass, GCS antenna analysis, verdict at every envelope point |
| LAT, KPI, DASH, WEAK, RPT | `measure_latency`, `measure_all_kpis`, `build_kpi_dashboard`, `analyze_weak_points`, `export_report_numbers` | Latency, KPI summary, dashboard, weak points, report numbers |

Not part of the `run_stage` chain: CORE_BW (`experiment_core_bw`), a controlled-bandwidth study; `run_stage('smoke', ...)` runs a reduced chain.

## Results so far

Profile 1, fourth test set (4,032 frames per state, 576 sub-runs), read once on 26.10.2026. Detector figures are for the three-state core CNN with a window of N = 3.

| Lecturer KPI | Target | Value [95% interval] | Verdict |
|---|---|---|---|
| BER model against theory | within 0.3 dB (project threshold) | 7/7 gaps within 0.3 dB (+0.01 to +0.14 dB) | Met |
| Macro-F1, three states | >= 85% | 99.83% [99.64, 99.97] (per frame 99.34%) | Met |
| False alarms, clean states | <= 5% | 0.17% [0.00, 0.53] (per frame 0.67%) | Met (detector level) |
| Recall, narrowband | >= 85% | 99.95% [99.87, 100.00] | Met |
| Recall, wideband | >= 85% | 99.73% [99.28, 100.00] | Met |
| PER reduction vs static link | >= 30% | not yet measured | Pending, C2e: 28.10.2026 (estimate) |
| Recovery time | reported | onset-to-detection median 0 cycles; closed-loop part pending | Pending, C2e |
| Goodput | reported | pending | Pending, C2e |
| CNN contribution (`rule_core3` vs a validation-tuned `blind_core`) | reported | pending | Pending: headline CORE_BW (D106); C2e's `rule_core` vs fixed-response `blind_core` is secondary (D105) |

Notes:

- Weakest point of the detector: wideband at JSR 0 dB, 97.82% recall (95.44% per frame). Never-detected episodes: 0.0%.
- The false-alarm KPI is read at detector level, as pre-registered. The whole-monitor false alarm on clean flights (an extension KPI) is not at 5% yet: 12.5-29.9% of 1,800 clean validation episodes depending on the monitor setting. The fix is registered in D103 and D104.
- KPI 5-8 for the proposal's own system come from the controlled-bandwidth study CORE_BW, where the three-state CNN drives the rule (`rule_core3`) against a `blind_core` tuned on validation (D106), estimated 30.10-2.11.2026. In C2e the rule reads the hybrid detector's classes; those readings are the profile-wide secondary lines (D105).

Next dates (estimates): DQN training (C2) is at run 50 of 81 and ends 28.10.2026 about 07:00-09:30; a PC restart follows right after C2 is done, before the policy evaluation (C2e) starts (fallback: at the start of C2g); C2e and the rest of the chain follow, ending at RPT about 29.10; CORE_BW 30.10-2.11 (`rule_core3` against the validation-tuned `blind_core` is the lecturer row); the profile-1 rerun (P1R) 2.11-5.11; profile 3 about 20-25.11.2026 (step 7a is being timed). Windows Update is paused until 30.11.2026. Current numbers and logs are in [docs/ROADMAP.md](docs/ROADMAP.md) and [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md).

## Operator console

`demo_gui.m` is an operator console for the closed loop. The proposal plans a dashboard for detection, decision and recovery (months 6-7); this console goes well beyond it.

| Tab | Shows |
|---|---|
| Live operations | A queue of threat x Eb/N0 cells; each run is a real Simulink run. Spectrogram, constellation, BER/RSSI timeline, class probabilities, DQN Q-values against the rule, BER before and after |
| Continuous episode | Clean cycles, then a threat onset; DQN and rule on identical frames; detection, action and recovery times, switches, goodput; CSV and screenshot export |
| KPI and results | KPI cards and plots read from `results/` |
| Survivability map | Map A / B |
| Session log | Run history |

Start `demo_gui` from a bundle exported by `export_gui_bundle`, not from the pipeline folder. The Live and Episode tabs need `data/trained_dqn.mat` (written when C2 ends); the KPI tab needs `results/policy_evaluation.mat` (C2e); the latency plot needs LAT. The bundle runs from a copy outside the pipeline folder, so a running pipeline is never touched.

State: the antenna count, the threat list, temporal fusion and the decision settings follow the current pipeline. The three-state core view, the core action set and the deployed policy kind from `trained_dqn.mat` are planned on branch `gui-core`; a live check with the final agent from an exported bundle follows RPT.

## Quick start

1. Requirements: MATLAB R2026a with Simulink and the Communications, DSP System, Signal Processing, Deep Learning, Statistics and Machine Learning, and Parallel Computing toolboxes. Full runs use an NVIDIA RTX 4070 SUPER GPU, an 8-core CPU and 32 GB RAM.
2. Open MATLAB in the repository folder; `startup.m` puts `code/` on the path.
3. Full pipeline: `matlab -batch "main"`; the flags at the top of `code/main.m` choose the stages.
4. One or more stages: `matlab -batch "run_stage('B2','B3')"`. A reduced check of the chain: `run_stage('smoke', ...)`.
5. Unit tests: `runtests('code/tests')`.
6. Results go to `results/`, generated data to `data/`, console output to `logs/`. `disk_guard` stops a run before free disk space falls below 150 GB.

The folders `data/`, `results/` and `logs/` are produced by the pipeline. Copies of `results/` and `logs/` tracked in git are from earlier versions (v3-v4) and are overwritten by a run; `data/` is not tracked.

## Repository layout

| Path | Content |
|---|---|
| `startup.m` | Puts `code/` on the path |
| `code/main.m`, `code/run_stage.m` | Pipeline entry point; single stages by name |
| `code/link/` | Link model, threats, countermeasures, receiver measurements, PHY validation |
| `code/detection/` | Dataset, spectrograms, detectors, unknown-threat scores |
| `code/decision/` | Frame pools, environment, policies, DQN training and evaluation |
| `code/evaluation/` | Survivability map, latency, KPIs, dashboard, bootstrap |
| `code/gui/` | Operator console `demo_gui.m`; `gui/viz3d/` is the optional 3D view (parked) |
| `code/tests/` | Unit tests |
| `code/dev/`, `code/diagnostics/` | Investigation scripts behind design thresholds |
| `code/legacy/` | Replaced code, kept for the record (not on the path) |
| `models/`, `params.mat` | Simulink link models and link parameters |
| `docs/` | Decision record, literature, roadmap, log, design notes (below) |
| `data/`, `results/`, `logs/` | Generated by the pipeline |

## Extensions (no commitment)

Built and measured, but outside the proposal. They are reported separately and are not promised.

- **Ten threats plus clean**: barrage jamming, reactive jamming, sweeping jammer, tone jamming, noise burst, spoofing, benign interference (WLAN), path loss, antenna fault, airframe shadowing; pairs and triples of threats; 36 countermeasure configurations.
- **Real receiver** with training and pilots, hover and turns, delay line, tracked 12 dBi GCS antenna under the 10.2 dBm e.i.r.p. cap, AD9361-class front end.
- **Hybrid 11-class detector** (spectrogram plus 23 link features) with temporal fusion. Macro-F1 94.81% [94.35, 95.25] on the fourth test set (read once); unknown-threat detection AUROC 0.769 against a target of 0.8 (not met).
- **Double DQN** (optional in the proposal's plan) with a safety shield and escalation, and the full set of earlier KPIs (restoration, false alarms of the whole monitor, latency).
- **Survivability maps and EDGE**: Map A (no goodput loss) 81.8% and Map B (any configuration) 91.8% of the profile 1 envelope; three antennas against two: single threats 93.1% vs 91.3%, combined threats 67.6% vs 58.2%.
- **Profile 3** (four antennas): detector stages done; decision layer pending.
- **CORE_BW**: controlled-bandwidth study with 41 channels, hop >= 6 MHz and jammer widths from tone to 83.5 MHz; `rule_core3` (the three-state CNN in the loop) against a validation-tuned `blind_core`; `rule_core` (the hybrid) is the secondary row (D106).
- **Operator console and 3D view**: console built; the 3D view is parked until the code, the final proposal and the interim report are done.

## Documentation map

| File | Content |
|---|---|
| [docs/DECISIONS.md](docs/DECISIONS.md) | Decision record D1-D106: why each design choice was made. The lecturer's scope is D92 |
| [docs/LITERATURE.md](docs/LITERATURE.md) | What each source contributes, and what is missing from the library |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Plan, run status and remaining work |
| [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) | Execution log, newest last |
| `docs/d84_*.md` to `docs/d89_*.md` | Design notes behind D84-D89 (link, detector, decision layer, receiver, shadowing, fusion, MMSE) |
| `docs/v7_plan.md`, `docs/v7_source_review.md` | The v7 plan and the review of the source library |
| `docs/v7_research_notes/` | Per-topic source notes |
| `docs/runs/`, `docs/drive_swap/`, `docs/cloud_tasks.md` | Run scripts and analyses cited by the decisions; system-drive swap; cloud tasks |

The previous full version of this README is in git at commit `b648c7b`.

## Known limitations

- **Pending KPIs.** PER reduction, recovery time, goodput and CNN contribution await the closed-loop evaluation (C2e).
- **Whole-monitor false alarms.** On clean flights the full monitor false-alarms in 12.5-29.9% of validation episodes. The lecturer's false-alarm KPI is met at detector level only. A fix is registered (D103, D104) and is read on a fresh clean test set.
- **Noise burst.** The coded answer worsens the link in the gallery (BER 0.495 against 0.439 with no response). Profile 1 uses an uncoded answer chosen on validation; profile 3 gets a decoder.
- **Weak detector classes (extension).** Airframe shadowing 84.5% F1; unknown-threat AUROC 0.769 is below 0.8.
- **BER validation limit.** The receiver on the delay line fails at a 30 dB jammer, rho 0.3, 1 us (D77).
- **Simulation only.** Latency is measured on a desktop with a GPU detector. Countermeasures are modelled, not built; hardware (SDR) validation is future work. The return link that carries the reconfiguration request is assumed, not modelled; a requested change reaches the link one cycle (20 ms) later.
- **Ranges.** Severities and ranges are limited to what the cited sources measure; nothing is simulated beyond them.

## Authors and supervisor

Adi Suliman and Bar Dvir Hassan; supervisor Golan Ein-Tzvi. Course 50076 (HIT), semester 2026-27 A. Repository: https://github.com/AdiSuliman/uav-gcs-adaptive-secure-comms

Last updated 27.10.2026.
