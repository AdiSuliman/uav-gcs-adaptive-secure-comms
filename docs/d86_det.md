# D86 group det: labels, the params file, folds, the deployed latch and the unknown-threat halves (branch d86-det)

Branch `d86-det` from v7-merge `a5f0687` (D81-D85 and cues C1/C2). Fixes of the pre-launch review for the detector stages (synthesis items 5, 6, 9, 14, 15, 18, 19, 22; review ids data-1, data-2, data-3, detector-04 with integration-5, detector-06, detector-01, detector-03, detector-07). Every item below states what changed, why, the source or the derivation, the tests (code/tests/test_core.m) and what moves. No test split or second test set was read; no number of a stage was measured here, because every number below moves only when the chain reruns from A0. This note is the merge input for the D86 entry of docs/DECISIONS.md; it does not replace it.

## 1. Frame-rule labels for the per-frame network and its unknown-threat models (item 5, data-1, MAJOR)

**Why.** Since D85 O3 the dataset's label is per decision cycle: a gated threat (WLAN, sweeper) counts while it is on the air anywhere in the 20 ms cycle, the idle time included (threat_active.m with act_idle). That label went unchanged into the CNN's loss, its class weights and its best-epoch macro-F1 (train_hybrid_net.m), and into the class means and tied covariance of the Mahalanobis models (fit_ood_model.m, Lee et al. 2018, P06, eq. 1), the FGSM targets and the leave-one-threat-out sets. The network sees the 0.69 ms frame and a 10-frame link-feature window only. The sweeper is on the air in 55.8% of the cycles but in about 13.4% of the frames (mean of (5.25 + 0.69 ms) / T for T uniform over 20-83.5 ms, review evidence), so about three of four sweeper-labelled frames carry nothing in the frame; on the D85 study data the per-cycle rule raised the sweeper's labelled frames from 6 146 to 25 181 and the WLAN's from 11 511 to 19 074 (docs/d85_obs.md, O3). D85's evidence (d85_obs.md table, column "integrated, per-cycle labels") kept a CNN trained on the frame rule and changed only the fusion's targets; d85_obs.md lists the per-cycle-trained CNN as an open risk. D76 (DECISIONS.md, "WLAN gaps") keeps the per-frame label as the proposal defines it (mitigation 3).

**Decision.** run_dataset_sweep.m stores both labels per frame: `label` (per cycle, as before) and `label_frame` (threat_active.m without the idle time: the frame rule, what the frame itself holds). extract_spectrograms.m carries it as `spec.Y_frame`, prepare_data.m as `splits.{train,val,test}.Y_frame` and in splits_fresh.mat. frame_labels.m (new) returns a split with Y = Y_frame and stops with a clear message when Y_frame is missing (an old dataset: rerun A5). The frame rule is used by:
- train_detector.m: the CNN's loss, class weights and best epoch, and fit_ood_model.m (class means, tied covariance, FGSM, the validation fits);
- ood_loto_split.m (eval_ood_detection.m): the known and held-out frames of training, vfit, va, vk and the second test set, so the known and unknown windows are labelled by what the frame holds;
- compare_architectures.m: every variant is a per-frame classifier, trained and read on the frame rule;
- eval_detector.m and select_fusion.m: the per-frame reading printed beside the fused one is read against the frame rule (its own labels).

The per-cycle labels stay with fusion_target.m, select_fusion.m (the fusion's targets, the onset threshold), the KPI 1 threshold and every fused reading (eval_detector.m), detector_block.m (B4/B4s), det_frames.m, link_env.m and the pools. This is the configuration D85 measured.

**Tests.** test_frame_rule_labels (new): the sweeper's frame rule against its per-cycle rule on the same frames; frame_labels.m; the label passes A5 -> A6 -> B1 (both split files); the per-frame network, the unknown-threat split and the architecture comparison use it; select_fusion, fused_class, detector_block and kpi_ebno do not. test_ood_loto_split (updated): a jamming sub-run's first frame is 'none' by the frame rule and joins the known training frames (44 instead of 40).

**What moves.** The CNN, the unknown-threat models, the LOTO readings and the per-frame line of B3 (A5 onward). The fusion and KPI 1 move only through the CNN's outputs.

## 2. A4v, A5 and B3n never write params.mat (item 6, data-2, MAJOR)

**Why.** run_dataset_sweep.m wrote params.mat for every level (onsets [2 11], the level, the threat) and restored it only after the 'none' loop; validate_phy.m wrote it for every case (n_rx, rx_sync 'ideal', a fixed seed) and restored it only on success. A stop in the middle (disk_guard, a crash, out of memory) left the last level's parameters, and a resume from that stage wrote them back as "restored". The pools (C1p, C1c), LAT and the gallery load params.mat and expect every threat on from the run's first frame (init_params.m: pl_onset_frames and fault_onset_frames [1 1], roll_in_frames []), so the path-loss and fault cells would have stepped in at frames 2-11 while their episodes counted them from frame 1.

**Decision.**
- run_dataset_sweep.m and validate_phy.m build the model in memory, `evalc('build_threat_model(p)')`, as eval_unseen_snr.m and eval_unseen_severity.m do (build_threat_model.m skips only the save to models/, which no stage loads). The restores are gone: nothing is left to restore.
- assert_frame1_onsets.m (new) stops a stage whose params.mat does not put every threat on from the first frame, or lacks the onset fields (a stale file), with "run init_params (A0)". One-line hooks after the params load of build_policy_pools.m, build_check_pools.m, build_clean_test_pools.m, measure_latency.m and threat_gallery.m. map_survivability_boundary.m (SURV) and experiment_survivability_options.m (SURV3) run init_params themselves before loading, so they need none.
- The run starts at A0 (launcher).

**Tests.** test_params_written_by_init_only (new): no `save('params.mat'` and the in-memory build in both files; A0's parameters pass the assertion, the detector's onsets, a roll-in range or a missing field stop it; the five hooks are present.

**What moves.** Nothing on a run that does not stop.

## 3. The extra sub-runs rotate over the Eb/N0 points (item 9, data-3)

**Why.** FOLD(nk) counted a threat's sub-runs over its cells in the order level, Eb/N0, sub-run. A level is 6 n sub-runs, a multiple of 6, so every level started at the same fold phase and the n mod 6 extra sub-runs fell on the same Eb/N0 points in all 8 levels.

**Decision.** run_dataset_sweep.m passes `FOLD(nk + lv - 1)`: each level starts one fold further. Within a level the sub-runs stay consecutive, so every fold still holds exactly n sub-runs of every level and every cell is in every fold. The second test set (FOLD 6) and 'none' are unchanged.

**Numbers (fold arithmetic, sub-runs per Eb/N0 point 0..15 dB summed over 8 levels).**

| n_sub | class | validation (fold 5) before -> after | test (fold 6) before -> after | training (folds 1-4) before -> after |
|---|---|---|---|---|
| 8 | fault, shadowing | 8 8 16 8 8 16 -> 10 11 11 10 11 11 | 8 8 16 8 8 16 -> 10 10 12 10 10 12 | 48 48 32 48 48 32 -> 44 43 41 44 43 41 |
| 11 | sweeper | 16 8 16 16 16 16 -> 15 14 14 15 15 15 | 8 16 16 16 16 16 -> 14 14 15 15 15 15 | 64 64 56 56 56 56 -> 59 60 59 58 58 58 |
| 13 | path loss | 16 16 16 16 24 16 -> 17 17 17 18 18 17 | 16 16 16 16 16 24 -> 17 17 17 17 18 18 | 72 72 72 72 64 64 -> 70 70 70 69 68 69 |

n_sub 6 (six classes) is 8 at every point before and after. The training-to-evaluation prior shift of fault and shadowing at 6 and 15 dB (0.67x of training, 2x of validation and test) is gone.

**Tests.** test_dataset_balance (extended): for n = 8, 11 and 13, every fold holds 8n sub-runs, n of every level, within 2 of 8n/6 at every Eb/N0 point, and every cell is in all 6 folds; the source carries `FOLD(nk + lv - 1)`.

**What moves.** The dataset's fold assignment (A5 onward); with it every validation choice and test reading is re-drawn.

## 4. KPI 1, its validation threshold, B4 and B4s read the monitor's class (item 14, detector-04 and integration-5)

**Why.** The deployed monitor's class of a lost branch is the fused class with the cause latched from the shape of the branch's onset (policy_monitor.m: the fusion, then onset_shape('latch'), then the class), and the edge map's DET reads it (det_frames.m). KPI 1's test reading, its validation threshold (the out-of-fold fused probabilities) and B4/B4s (detector_block.m through fused_class.m) took the fused argmax without the latch, while eval_detector.m said "as the system decides" and detector_block.m "as the deployed detector reads it". DECISIONS.md D72 ("Temporal fusion"): KPI 1 is read on the decisions of the system; D74: DET over every flight stays KPI 1's reading. D85 measured the latch moving fault and shadowing by 7-22 points after the fusion window (d85_onset.md, Results). The review's two fixes differed; the synthesis chose detector-04's (read KPI 1 on the monitor's class), which also keeps B4/B4s on the same rule as B3.

**Decision.**
- latch_runs.m (new): onset_shape('sequence') over every run's cycles in time order with the deployed heal (decision_config.m C.heal); the one routine of eval_detector.m, select_fusion.m and fused_class.m.
- eval_detector.m: Y_pred is the monitor's class (the fused probabilities latched per test sub-run, the threshold FM.os_thr chosen on validation); the fused class alone is kept as Y_fused (pred.y_fused, metrics.fused_alone: macro-F1 and class F1 above the threshold, printed beside KPI 1; the onset_cue columns "fused" and "latched"). Everything downstream of Y_pred reads the deployed class: the confusion matrix, F1 per Eb/N0, the threshold reading, the stricter reading, the bootstrap, the steady state and the onset latency.
- The KPI 1 threshold on validation reads the monitor's class out of fold: select_fusion.m saves val_latch_oof, the latch over the out-of-fold fused probabilities of every validation sub-run with the onset threshold chosen on the other folds' sub-runs (the same 5 sub-run folds as the fusion); eval_detector.m stops if fusion.mat lacks it. Without a fusion the per-frame validation output is latched at threshold 0, as the monitor does.
- fused_class.m returns the monitor's class (k) and the fusion's alone (kf); detector_block.m passes the classes, so B4 and B4s read the monitor's class. The wording of fused_class.m, detector_block.m, eval_unseen_snr.m (header and report line) and eval_unseen_severity.m (header and report line) says so.

The latch only moves probability between antenna_fault and airframe_shadowing while a branch is lost, both mapped to one rule action; alarms, the same-action values and the B4/B4s verdicts read by edge_map.m do not change, the per-class F1 of the two classes and macro-F1 do.

**Tests.** test_monitor_class_reading (new): latch_runs over the shuffled frames of two runs equals each run's latch in time order, the deployed heal by default; fused_class.m gives the latched fault for a step the fusion calls shadowing and the fusion's class beside it; eval_detector.m latches the test frames and reads val_latch_oof, select_fusion.m saves it, detector_block.m passes the classes. Existing test_onset_shape and test_monitor_onset_latch pass unchanged.

**What moves.** KPI 1 (fault, shadowing and macro-F1), its threshold, the stricter reading, steady state, onset latency, B4/B4s per-class rows. Expected direction from D85: up for the two branch classes.

## 5. The latch threshold is fitted on the events the deployed latch acts on (item 15, detector-06)

**Why.** onset_shape('events') returned the statistic of the first diagnosis anywhere in the sub-run with heal = Inf, and select_fusion.m gave it the sub-run's cause. The latch can arm from cycle 6, so with an onset at frames 7-11 a fading dip of another branch can be diagnosed first; the deployed latch (heal 5) closes that event and diagnoses the real onset, 'events' scored the dip. The verifier showed heal alone changes nothing before a first diagnosis; the return-on-first is the cause. Size: D85 saw the latch fire on 24.3% of clean 40-frame study sub-runs (d85_onset.md, results list; about 0.8% per cycle), so about 1% of the fault and shadowing validation sub-runs, two thirds of them on another branch. The review's time gate (only diagnoses after the labelled frame) would drop real shadowing events: the ramp can be detected before its loss reaches the label's 5 dB (Sun et al., Part IV, event criterion; Heath, US 10,404,368, 5 dB imbalance).

**Decision.** onset_shape('events', G, j0, heal): the latch runs as deployed (heal, default C.heal); j0 is the sub-run's first labelled frame of the threat; the threat's branch is the antenna whose median offset (Willgert, eq. 5, as in temporal_evidence.m) falls most from the frames before j0 to the frames from j0 on; the statistic is the first diagnosis on that branch, read while its cause is latched; NaN if none (another branch's event that never heals, as in the monitor). A diagnosis before j0 on the branch counts. select_fusion.m passes j0 and the deployed heal. Without j0 the behaviour is the first event on any branch (test_onset_shape unchanged).

**Tests.** test_onset_events_branch (new): a ramp-like fading dip on branch 3 (frames 5-9) before a 15 dB step on branch 1 at frame 13: the first event is the dip (positive statistic), the threat's branch gives the step's negative statistic, heal = Inf never reaches it (NaN); a ramp diagnosed before its labelled frame returns the same value as without j0; a permanent loss of another branch leaves NaN; select_fusion.m passes j0 and heal.

**What moves.** FM.os_thr (B2F) and through it the latch everywhere (KPI 1, DET, the pools' monitor). Expected small (about 1% of the threshold's events).

## 6. The unknown-threat validation halves, stratified (item 18, detector-01, MAJOR)

**Why.** ood_loto_split.m took every other validation sub-run in run order. Run ids go threat, level, Eb/N0, sub-run, and a class with 6 sub-runs per cell has one validation sub-run per cell, so the halves alternated by Eb/N0: for jamming, noise_burst, reactive_jamming, spoofing, WLAN and tone the fit half held only 0/6/12 dB and the selection half 3/9/15 dB (fault and shadowing 0/6/9/15 against 3/6/12/15). The selection AUROC and the FPR95 threshold (95% of the known validation windows kept, Lee et al. 2018 P06; FPR95 as in Liu et al. 2020, V7_Liu2020) read known windows without 0 dB threat frames against held-out windows at every Eb/N0. The halves exist to keep the frames that fit a candidate out of its choice (D60, d84_det.md B1); nothing ties them to Eb/N0.

**Decision (derivation, no source needed).** half_of_runs in ood_loto_split.m: a sub-run's class is its per-cycle class; within each (class, Eb/N0) group the sub-runs, ordered by level and by run id inside a level, go to the two halves in turn, starting with the Eb/N0 index's parity. A class with one sub-run per (level, Eb/N0) cell is an exact checkerboard over level rank and Eb/N0 index (every Eb/N0 point has 4 levels in each half, every level 3 Eb/N0 points); a cell of several sub-runs splits inside itself. Plain alternation within (class, Eb/N0) by run id would tie the halves to level parity instead; ordering by level inside the group with the Eb/N0 parity avoids both. Against the review's literal recipe (a parity mod(level rank + Eb/N0 index, 2) per cell, alternating inside the cell from it): identical wherever a class has one sub-run per cell; where cells hold 2-3 sub-runs (n_sub 11 and 13) the per-cell parity leaves up to 2 sub-runs between the halves of a (class, Eb/N0), the alternation over the ordered group at most 1 (fold arithmetic of the A5 layout). On A5's layout (with item 3's folds): every (class, Eb/N0) and (class, level) has sub-runs in both halves, at least 4 per (class, Eb/N0) and 3 per (class, level), and the halves differ by at most one sub-run per (class, Eb/N0) and per (class, level). eval_ood_detection.m's header says so.

**Tests.** test_ood_halves_stratified (new) on A5's run and fold layout (n_sub 6, 13, 11, 8, 'none' 48 per Eb/N0): both halves in every (class, Eb/N0) and (class, level), at most one apart per (class, Eb/N0), the checkerboard for an n_sub = 6 class. test_ood_loto_split (updated): the halves of a small layout follow the checkerboard.

**What moves.** The OOD stage: the fold networks' early stopping, the models' validation fits, the selection AUROC, the (score, window) pair, the FPR95 threshold and KPI 2's FPR95.

## 7. The features-only baseline trains without masking (item 19, detector-03)

**Why.** compare_architectures.m holds the spectrogram at zero for the "link features only (MLP)" variant and trained it with the default augmentation. spec_mask.m fills a band with the image's thermal-noise level (0.281, spec_image('noise'), D84 B5), so on a zero image the masks painted label-free bands on half of every batch, while validation and test images stayed zero; the header's premise (a constant input leaves its branch a fixed bias) no longer held.

**Decision.** The 'spec' mask variant trains with augment = false; the hybrid and the spectrogram-only variants keep the masking. spec_mask.m is unchanged (the noise-level fill is right for real images). Header line added.

**Tests.** test_spec_only_baseline_unmasked (new): spec_mask on zero images writes non-zero bands; the variant's option is set.

**What moves.** The features-only row of results/architecture_comparison.txt (B3a).

## 8. KPI 2's summary gives the deployed statistic and the nested FPR95 (item 22, detector-07)

**Why.** measure_all_kpis.m printed the production score's AUROC and FPR95 at one frame (R.auroc, R.fpr95: window 1), labelled "per frame". The decision cycle compares the score averaged over ood.win cycles (ood_thresholds.m, policy_monitor.m), and the nested estimate's FPR95 (NEST.fpr95, computed by eval_ood_detection.m) was never printed, though the script's own KPI 2 definition names the FPR at 95% of known frames kept.

**Decision.** The KPI 2 detail starts with the deployed statistic: the production score over its window (the (score, window) pair recovered from pj, pw and sel_win), its mean AUROC and FPR95 on the second test set, and the nested estimate's AUROC and FPR95; the per-frame line stays, labelled as before. The KPI 2 value reads "mean AUROC x, FPR95 y (nested)". Files without these fields (before D84) skip the line.

**Tests.** test_kpi2_deployed_statistic (new): measure_all_kpis.m on a results/ood_detection.mat alone gives the value and the deployed line with the pair's MpT and FpT columns and the nested FPR95.

**What moves.** The KPI summary's text only; the KPI 2 status still reads the nested AUROC.

## Files outside the ownership list

- One-line hooks `assert_frame1_onsets(p0);` in code/decision/build_policy_pools.m, code/decision/build_check_pools.m, code/decision/build_clean_test_pools.m, code/evaluation/measure_latency.m and code/evaluation/threat_gallery.m (item 2).
- Not changed, for the main session: docs/DECISIONS.md (the D86 entry, and the D85 note that KPI 1, its threshold and B4/B4s read the latched class); docs/d84_det.md (a line that the halves are stratified, item 6); code/link/params_id.m's header still says stages "write params.mat for each threat and restore it" (after item 2 only the GUI and two diagnostics do); code/evaluation/build_kpi_dashboard.m draws the window-1 AUROC under the production score's name beside the nested bars (item 8's verifier note); code/evaluation/det_frames.m keeps its own copy of the per-run latch (same rule as latch_runs.m); code/diagnostics/diag_ood_scores.m trains on Y (diagnostic, not in the chain).

## Tests

Full suite, code/tests/test_core.m on this branch's code, one MATLAB R2026a process: 148 passed, 0 failed, 0 incomplete of 148 (31.1 min). New: test_frame_rule_labels, test_params_written_by_init_only, test_monitor_class_reading, test_onset_events_branch, test_ood_halves_stratified, test_spec_only_baseline_unmasked, test_kpi2_deployed_statistic (after test_fusion_current_frame). Updated: test_dataset_balance, test_ood_loto_split. No smoke chain here: the main session runs one after merging the groups.
