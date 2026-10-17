# D87: the onset latch as a validation choice, the weak classes on validation, a third test set, and the mid-run deployment (branch d87-fusion)

Branch `d87-fusion` from v7-merge `c2c8b8b` (the code of the running full run). Validation outputs only were read for every choice below (profile 1: `uav-gcs-v7/data/fusion.mat` and the validation split of `data/splits.mat`, read by HDF5 without the training and test splits; profile 3 the same, as a check). No test split, second test set or third test set was read here. This note is the merge input for a D87 entry of docs/DECISIONS.md.

## 1. Whether the monitor latches a lost branch's cause is chosen on validation

**Why.** select_fusion.m (B2F) chose the onset-shape threshold FM.os_thr but never whether to latch at all: every reader latched (D86 det item 4). B2F's own log already showed the latch lowering the out-of-fold macro-F1 of the monitor's class: profile 1 91.94% with the latch against 93.32% for the fused class, profile 3 90.44% against 92.78%. Profile 1's reading of the second test set (B3, 2026-10-17) agreed (93.11% above the KPI 1 threshold latched, 94.78% fused alone; antenna fault recall 81% to 66% with the latch), but that reading takes no part in the choice. Where the latch loses (section 2): the onset statistic reads a connector's step as a ramp when the branch fades (K at or below 0 dB: antenna-fault recall 64.3% fused, 32.5% latched on profile 1's validation), and it overrides a fused class that was right more often than the shape statistic (73.2% of profile 1's validation faults read right by the shape, B2F log). Antenna fault and airframe shadowing take the same rule action (rule_based_policy.m), so the latch never changed an action, only the class.

**Decision.** select_fusion.m keeps the latch's out-of-fold class (val_latch_oof, threshold chosen on the other folds, as before) and sets `FM.latch = mf_latch > mf_fused`: the latch only where its out-of-fold macro-F1 is above the fused class's, the measure that already chose N and lambda. Beside it, the per-event reading of a lost branch (the first cycle from the onset read as antenna_fault or airframe_shadowing reads the right one) for both. `onset_shape('on', FM)` returns the flag, true for a fusion without it (fitted before this choice) or without a fusion, so a running chain with an old data/fusion.mat behaves exactly as before. Every reader honours it alike:
- fused_class.m (KPI 1's monitor class for B4 and B4s through detector_block.m): off, k = kf;
- policy_monitor.m (the closed loop: C1d, C2, C2e, C2g, C2u, LAT, the GUI): off, onset_shape('latch') is not run and M.probs is the fusion's;
- det_frames.m (EDGE's DET): off, the monitor's class is the fused class (hit = hit_f); edge_map.m states it under its onset table;
- eval_detector.m (B3, B3m): off, Y_pred is the fused class, the KPI 1 threshold is read on val_probs_oof (on: val_latch_oof, as before), the per-event reading takes the first branch class of the monitor, metrics.latch records the state;
- eval_unseen_snr.m and eval_unseen_severity.m state the monitor they read; measure_all_kpis.m words the per-event line by metrics.latch.
FM carries the flag, so detector_id.m (det_id) changes with it: pools built with the old fusion must be re-keyed (rekey_pools.m) or built after the new B2F (section 4).

**Measured (validation, out of fold).** Profile 1: latch off, macro-F1 93.32% (latched 91.94%), nested gain +1.38 points [95% sub-run bootstrap +0.60, +2.26]; per event, first branch reading right: fault 84.4% fused, 78.1% latched; shadowing 89.1%, 92.2%. Profile 3: latch off, 92.78% (90.44%), +2.34 [+1.36, +3.28]; fault 71.9% / 68.8%, shadowing 85.9% / 85.9%. The B2F rerun reproduces the fit exactly (the out-of-fold probabilities of profile 1 were refitted here with max |difference| 0), so FM differs from the running one only by the flag.

**What moves.** The KPI 1 threshold is chosen on the monitor's validation class. Profile 1's fused class per Eb/N0 bin on validation: 0 dB 90.95%, 3 dB 91.30%, 6 dB 93.75%, 9 dB 95.65%, 12 dB 94.74%, 15 dB 94.51% (latched: 89.75, 89.71, 91.84, 92.79, 95.18, 93.17), so its threshold moves from 6 dB to 0 dB. Profile 3 stays at 3 dB (fused 88.65% at 0 dB). C1d, C2, C2e and EDGE read that threshold from results/eval_detector_metrics.mat as the lower edge of KPI 6 and of the decision layer's Eb/N0 range, so B3 must be read again after B2F and before C1d (section 4). result_status.m now flags a detector reading older than data/fusion.mat as stale, and KPI 1 likewise.

**Tests.** test_latch_choice (new): onset_shape('on') for no flag, true, false and no fusion; with a fusion that reads shadowing and a connector's step, fused_class.m, policy_monitor.m and det_frames.m give the fused class with the flag off and the latched fault with no flag or with it on; the source checks of select_fusion.m (the flag set before the save), eval_detector.m (val_probs_oof when off, the gated latch), policy_monitor.m and det_frames.m. test_monitor_class_reading, test_monitor_onset_latch, test_det_frames_onset and test_onset_shape pass unchanged (latch on).

## 2. The weak classes on validation

Profile 1's validation split (968 sub-runs, 20 328 frames), out-of-fold outputs of B2F (N = 12 cycles, lambda 1e-3), targets of fusion_target.m. Recall of the fused class (the monitor's after section 1), the latched class beside where it differs; the confusion partner is the class the misses are read as, in % of the class's frames.

| class | F1 / recall / precision | misses read as | weakest conditions (recall) | flat or strong |
|---|---|---|---|---|
| benign_interference (WLAN) | 90.1 / 87.4 / 93.1 | none 7.6, sweeping_jammer 3.4; false positives from sweeping_jammer (4.2% of its reads), noise_burst (1.4%) | level -12 dB 66.8 and -8 dB 78.0 (at 0 and 3 dB Eb/N0: -12 dB 0.0 and 2.5, -8 dB 48.8 and 4.8); Eb/N0 0 dB 78.9, 3 dB 75.2; the onset cycle 43.8 (read as sweeping_jammer 23.8); idle-time on-air share below 0.1: 66.4; interferer level on the weakest antenna below -10 dB: 28.6 (5 sub-runs) | level -4 dB and above 88-96, Eb/N0 6 dB and above 91-94, K and speed 83-94 without a trend |
| path_loss | 87.1 / 83.1 / 91.6 | none 15.0; false positives from none (5.2% of its reads), antenna_fault (1.7%) | step 4 dB 34.4 (read as none 57.1; 8.8-54.2 per Eb/N0); 7 dB 82.7, 10 dB 80.6; frames 8 or more cycles after the onset 71.0 (the fusion's target, beyond the link-feature window); K below 5 dB 70.8-76.6 | steps of 13 dB and more 93-95; configured Eb/N0 80-87 without a trend; speed 82-86 |
| antenna_fault | 82.9 / 79.2 / 86.9 (latched 74.8 / 67.7 / 83.6) | none 15.0, airframe_shadowing 3.9 (latched: shadowing 15.4) | loss 5 dB 20.2 (none 61.3), 8.7 dB 51.5; K below 0 dB 64.3 (latched 32.5, read as shadowing 48.7), 0-5 dB 66.4 (41.9); the onset cycle 60.9 | 12.4 dB and more 84-99; K 10 dB and more 85-96; Eb/N0 70-89 without a trend |
| airframe_shadowing | 85.1 / 82.4 / 87.9 (latched 77.9 / 79.5 / 76.4) | none 12.0, antenna_fault 4.2 (latched 7.1; false positives from fault 15.1% of its reads) | the first three cycles of the event 35.9, 56.2, 73.4 (read as none 53, 36, 23); K below 0 dB 58.9; levels 12 and 15 dB 76.6 and 70.9 | from cycle 5 on 87-93; K 5 dB and more 91-93; bank and roll rate without a consistent trend |
| none (false alarms) | 93.7 / 97.0 / 90.7 | read as airframe_shadowing 1.0, path_loss 0.9, antenna_fault 0.9 | Eb/N0 6 dB: 6.1% read as a threat (antenna_fault 3.3) | 1.9-3.0% elsewhere |

Profile 3 (4 antennas) shows the same pattern: WLAN 86.4% (-12 dB 65.7, 0 dB Eb/N0 70.5), path loss 83.8% (4 dB step 30.1), antenna fault 75.8% fused / 58.5% latched (5 dB 1.6; K below 5 dB 57.8-63.4 fused, 24.2-32.3 latched), shadowing 78.8% / 72.1% (onset cycles 45-58).

**Remedies at the fusion level, CNN untouched.** Nested cross-validation over the validation sub-runs: outer folds the 5 folds of select_fusion.m; inside every outer training set the fusion is refitted on 3 of its 4 folds and applied to the 4th (inner out-of-fold outputs), the remedy's parameters are chosen there, then the fusion is refitted on the 4 folds and the remedy applied to the outer fold. Gains are macro-F1 points of the pooled outer predictions against the fused class with no remedy, 95% intervals from 1000 bootstraps of whole validation sub-runs. Adoption rule fixed before the run: an interval above 0, and the clean false-alarm rate (every frame whose target is none, read as any other class; one-sided 95% bound by sub-run bootstrap, with Clopper-Pearson over frames beside) not above 5%.

| remedy | parameters chosen inside | profile 1 gain [95%] | profile 3 gain [95%] | clean false alarms P1 / P3 (bound) | verdict |
|---|---|---|---|---|---|
| latch off (section 1) | inner choice: off in 5 of 5 folds, both profiles | +1.38 [+0.60, +2.26] against the latch | +2.34 [+1.36, +3.28] | 3.03% (3.94%) / 3.06% (3.76%), unchanged | adopted |
| per-class logit offsets (plug-in for macro-F1) | coordinate ascent on the inner outputs, grid 0.1 in [-3, 3]; a class's offset differs by up to 2.4 (P1) and 3.0 (P3) between folds | +0.04 [-0.21, +0.36]; above 6 dB -0.25 | -0.07 [-0.38, +0.31] | 2.71% (3.59%) / 2.36% (2.97%) | rejected: no gain |
| class-prior correction, b = -a log(prior) | a in 0-1 by 0.25: a = 0 in 5 of 5 folds (P1), 4 of 5 (P3) | 0.00 | -0.04 [-0.12, +0.04] | unchanged | rejected |
| balanced priors (a = 1, fixed) | none | -1.41 [-1.98, -0.86] | -2.00 [-2.57, -1.51] | 12.04% (13.65%) / 13.31% (15.14%) | rejected: loss, false alarms above the bound |
| majority of the last m monitor classes | m in {1, 2, 3, 5}: m = 1 in every fold | 0.00 | 0.00 | unchanged | rejected |

Sources. Lipton, Elkan and Naryanaswamy (2014) is not in the source library (the index of 112 files and the "scanned, not in use" folder hold no thresholding, F-measure or calibration source). The offsets are stated by their derivation: by Bayes' rule the posterior under class priors pi' is p'(c|x) proportional to p(c|x) pi'_c / pi_c, so argmax_c [log p(c|x) + b_c] with b_c = log(pi'_c / pi_c) is the Bayes decision for another prior or for class-dependent costs; the offsets that maximize macro-F1 are found on held-out outputs (a plug-in rule), which is the procedure scored above, and the prior correction is its one-parameter case. The majority vote is the class-level form of the M-of-N integration the monitor already uses for its alarm (Barajas et al., N03, decision_config.m confirm). None helps: the fusion is a multinomial logistic regression fitted by cross-entropy on these same classes and priors, so a shift of its outputs moves errors between classes rather than removing them (the offsets' folds disagree), and its 12-cycle window already integrates over time.

**Limits that stay, after the breakdown.** These are where the received signal holds too little of the threat in one 240 ms window: WLAN 8-12 dB below our signal at 0-3 dB Eb/N0 (the emitter lies near or below the thermal floor; recall 0-5% at -12 dB, 5-49% at -8 dB); a 4 dB path-loss step (34% recall; 30% on profile 3), inside the per-cycle level variation of a fading link (worse below K = 5 dB); a 5 dB open connector (13-20%) and an 8.7 dB one (42-52%), and either branch class under K below 0 dB fading, where the branch's offset fluctuates by as much as the loss; the first 1-3 cycles of an airframe-shadowing roll-in, before the loss has built up. Above them every weak class reaches 84-99%.

Scripts (scratch, not in the repository): extract_val.m (validation fields and the CNN's validation scores by HDF5), repro_fusion.m (the exact refit check), breakdown_b.m, remedies_b.m; outputs breakdown_p1.txt, breakdown_p3.txt, remedies_p1.txt, remedies_p3.txt in the session's scratchpad d87 folder.

## 3. A third test set (stage B3m)

**Why.** Profile 1's second test set was read (B3) before the latch was made a validation choice, so its post-change reading is no longer the first. KPI 1 after the change is read on sub-runs nothing has read.

**Decision.** run_stage.m stage B3m (build_fresh_test2): run_dataset_sweep.m, extract_spectrograms.m and prepare_data.m with FRESH_TEST = true and FRESH_SET = 2, then eval_detector.m with DET_TEST = 'fresh2'. The recipe is the second test set's (4 sub-runs per cell, the compensated counts of the gated threats, path loss and the lost branches, every sub-run in the test fold 6); only the seeds and the files differ:
- seeds 6 500 000 + run id: above every dataset, B4 and B4s flight seed (3.0/3.5, 4.0/4.5, 5.0/5.5 M families), below the pools' shadowing candidates (10 000 001 on) and 2^26; test_seed_streams_disjoint now holds 6 500 000 + k, k = 1-99 999, and stays N of N; the speeds draw from rng(2035), a stream no other stage uses (2027 the dataset, 2029 the second test set);
- data/dataset_fresh2.mat, data/spectrograms_fresh2.mat, data/splits_fresh2.mat (test, norm and classes, the training z-score of data/splits.mat);
- the reading writes results/eval_detector_metrics_fresh2.mat, detector_predictions_fresh2.mat, confusion_matrix_fresh2.png and accuracy_vs_snr_fresh2.png; the earlier readings keep their files. B3 reads the test split and the second test set as before.
- measure_all_kpis.m reads KPI 1 from the third test set when its file exists, with the second test set's reading beside ("first read before that choice"); export_report_numbers.m exports it as detector_third beside detector. main.m has RUN.build_fresh_test2.

Cost (profile 1's B3n, 2026-10-17): about 4.7 h and about 11.5 GB of disk per profile. Tests: test_third_test_set (the seeds, the counts unchanged, the files, the stage, the reading's suffix, KPI 1's source; prepare_data.m on a small third set writes splits_fresh2.mat with the training z-score and leaves splits_fresh.mat absent), test_seed_streams_disjoint, test_main_stage_list.

## 4. Deploying into the running profiles without stopping their chains

### What reads data/fusion.mat or folds it into an identity

| stage | reads | identity |
|---|---|---|
| B2F select_fusion | writes it | |
| B3 / B3m eval_detector | FM, N, val_probs_oof, val_latch_oof, val_target at its start; the KPI 1 threshold from them | writes results/eval_detector_metrics*.mat, which C1d, C2, C2e and EDGE read for the threshold |
| B4 eval_unseen_snr, B4s eval_unseen_severity | FM, N at their start (fused_class.m) | |
| OOD, B3a, SURV, SURV3, OHP, GCSA, GAL | nothing of the fusion | |
| C1p build_policy_pools | fusion_model() at its start: PP.fuse, fuse_N, q_thr | PP.det_id = detector_id(... FZ ...) at its start; train and validation pools are reused only with the same det_id |
| C1c build_clean_test_pools (twice), build_check_pools | fusion_model() at each start | stops when PP.det_id differs from the det_id of the current fusion.mat ("rerun C1p first"); CT.det_id, CK.det_id and CK.fuse |
| rekey_pools (not a chain stage) | fusion_model() | replaces fuse, fuse_N, q_thr, det_id of policy_pools, check_pools, clean_val_pools, clean_test_pools (backups first); the frames are per-frame outputs, so nothing is simulated again |
| C1d choose_drop_threshold, C2 train_dqn, C2e evaluate_policies, C2g, C2u, EDGE edge_map | the monitor from PP.fuse (policy_monitor.m, det_frames.m), never fusion.mat itself; the KPI 1 threshold from results/eval_detector_metrics.mat | check_det_id between stored ids only (PP against CV, CT, Q); train_dqn stores det_id = PP.det_id |
| LAT measure_latency, the GUI | fusion_model(): PPm.fuse | LAT.det_id from the current fusion.mat |
| KPI, RPT (result_status.m) | fusion_model() for the current det_id | LAT and EDGE stale when their det_id differs; a detector reading older than data/fusion.mat stale |

How the chains run (uav-gcs-logs/v7_d86_launch.sh): profile 1's chain is one MATLAB process running run_stage over A0-RPT; profile 3's is one process over A0-B4s and a second over C1p-RPT after profile 1's SURV3. MATLAB reads a changed .m file the next time it is called, so a merge into a profile's worktree takes effect at the next call of every changed file inside the running process. The launcher finds a resume point from the '##### STAGE <s> done' markers of p1.log and p3.log: a separate MATLAB process must log to another file (below p1_d87.log, p3_d87.log), never to those two.

The branch changes onset_shape.m, fused_class.m, latch_runs.m, policy_monitor.m, det_frames.m, edge_map.m, eval_detector.m, eval_unseen_snr.m, eval_unseen_severity.m, select_fusion.m, run_dataset_sweep.m, extract_spectrograms.m, prepare_data.m, measure_all_kpis.m, result_status.m, export_report_numbers.m, run_stage.m, main.m and the tests. A merge must not land while the running stage calls fused_class.m (B4, B4s: fused_class.m is written before onset_shape.m, and a call between the two writes would ask the old onset_shape.m for 'on' and stop the chain) or policy_monitor.m and det_frames.m (C1d onward). OOD, B3a, C1p, C1c, SURV, SURV3, OHP and GCSA call none of the changed files; a running script (run_dataset_sweep.m of B3n) keeps the version it started with. The merge itself is clean on v7-dev and v7-p3 (git merge-tree) and touches no generated file (params.mat and results/ are modified in both worktrees and are not in the branch).

### Profile 1 (now B4, then OOD, B4s, C1p for about 4 days, C1c, SURV, SURV3, C1d, C2 ...)

1. Wait until p1.log shows `##### STAGE OOD (eval_ood_detection)` and B4 done. Then merge: `git -C "C:/Users/Adi Suliman/uav-gcs-v7" merge --no-ff d87-fusion` (message ending with the Co-Authored-By line). Do not merge during B4 or B4s.
2. Archive the readings that will be replaced: copy results/eval_detector_metrics.mat, eval_detector_metrics_split.mat, detector_predictions*.mat, confusion_matrix*.png, accuracy_vs_snr*.png, unseen_snr.* and data/fusion.mat to archive/pre_d87_<stamp>/.
3. One separate MATLAB process in the profile's root, after free memory is at least about 16 GB (B2F loads the whole data/splits.mat, B3 also splits_fresh.mat):
   `cd "/c/Users/Adi Suliman/uav-gcs-v7" && "/c/Program Files/MATLAB/R2026a/bin/matlab.exe" -batch "run_stage('B2F','B3','B4')" >> "/c/Users/Adi Suliman/uav-gcs-logs/v7_d86/p1_d87.log" 2>&1`
   B2F must end before the chain's B4s starts (OOD takes about 4 h, so there is time); check that p1_d87.log prints "the latch is off (FM.latch = false)" and the same N, lambda, os_thr and q_thr as the first B2F (93.32% fused out of fold). B3 then writes the threshold of the latch-off monitor (expected 0 dB, section 1); B4 reads the unseen Eb/N0 again with that monitor (about 1-2 h).
4. Then, in a second separate process (or the same after B4): `run_stage('B3m')`, logging to p1_d87.log; about 4.7 h of single-process simulation; it overlaps the start of C1p, which runs on its parallel turn. Its reading is profile 1's KPI 1 after the change; nothing else reads the third test set.
5. The chain continues by itself: B4s reads the new fusion.mat; C1p builds the pools with PP.fuse carrying latch = false and the new det_id, so C1c's checks pass and no rekeying is needed; C1d onward run the new policy_monitor.m and det_frames.m.

If the window is missed (C1p started with the old fusion.mat): merging the code during C1p is still safe (an old fusion.mat latches as before), but data/fusion.mat must stay unchanged until C1c has ended, or C1c stops on the det_id. Once p1.log shows SURV running: B2F and `rekey_pools` (both in a separate process; SURV and SURV3 read no pool file), then B3, B4, B4s and B3m in the separate process; all before C1d starts (after SURV3). rekey_pools re-keys policy_pools, check_pools, clean_val_pools and clean_test_pools with backups and stops, changing nothing, if a pool is not only of another fusion.

### Profile 3 (now B3n, then B3, B3a, B4, OOD, B4s in one process; C1p onward after profile 1's SURV3)

Preferred, if it fits before B3n ends (profile 1's B3n took 4.7 h; profile 3's started 06:06): merge into v7-p3 while B3n is still in its sweep or spectrogram extraction, then run `run_stage('B2F')` in a separate process (about 7 min, log p3_d87.log) and check it ended before p3.log shows `##### STAGE B3n done`. B3, B4 and B4s of the chain then read the latch-off monitor, the second test set is first read after the choice, and profile 3 needs no B3m and no rerun. Do not start B2F unless it can end before B3 starts: a fusion.mat written while B3 loads it could stop the chain.

Otherwise: wait until p3.log shows `##### STAGE B3a (compare_architectures)` (B3a calls no changed file; it takes about an hour), merge, run `run_stage('B2F','B3')` in a separate process (B2F must end before the chain's B4 starts), then `run_stage('B3m')`: the second test set was then read with the latch, so KPI 1 is read on the third. The chain's B4, OOD and B4s follow with the new fusion.mat.

Profile 3's C1p starts days later and builds its pools on the new fusion: no rekeying.

### Profile 2

v7-p2 is made from v7-dev once profile 1 has finished, so it carries the branch; its chain runs B2F before B3n and B3, so its second test set is first read after the choice and it needs no B3m.

### Before each profile reaches C1d and C2

- the code of this branch is in the profile's worktree (policy_monitor.m and det_frames.m honour the flag; without it the old code latches whatever FM says);
- data/fusion.mat holds FM.latch (false on both profiles' validation) and the pools carry it: built by C1p after the new B2F, or re-keyed (rekey_pools) after C1c; C1c passing its det_id check confirms the pools match data/fusion.mat;
- results/eval_detector_metrics.mat is newer than data/fusion.mat (B3 read again): C1d, C2, C2e and EDGE take the KPI 1 threshold from it, and on profile 1 it moves from 6 to 0 dB, which widens KPI 6 and the decision layer's range to 0-15 dB; result_status.m and KPI flag it stale otherwise;
- B4 and B4s read with the same monitor (rerun B4 where it ran before the change; B4s runs after it in the chain);
- B3m done on profiles 1 and 3 (if profile 3 missed the preferred window) before KPI and RPT, so KPI 1 is read on the third test set.

Not changed here, for the main session: docs/DECISIONS.md (a D87 entry from this note), PROJECT_LOG and ROADMAP, and the launcher (B3m is not in its chain lists; it is run separately as above).
