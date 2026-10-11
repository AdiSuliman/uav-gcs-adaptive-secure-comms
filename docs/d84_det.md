# D84 group B: detector and unknown threats (branch d84-det)

Fixes of the pre-launch review of v7-merge a66ebb9 (review ids D-F1 to D-F8, T-F5) for the detector and the unknown-threat score. Every item below has its reason, the decision, the sources or the derivation, and its tests (code/tests/test_core.m). This note feeds the D84 entry of docs/DECISIONS.md; it does not replace it.

## B1: the unknown-threat pair chosen on validation, read on the second test set (D-F1, blocker)

**Why.** eval_ood_detection.m chose the deployed (candidate, window) pair of the unknown-threat score by its mean AUROC on test-split frames, and wrote it to data/trained_detector.mat (ood.score, ood.win). That pair enters detector_id.m, which keys every pool, so test frames informed a deployed decision. KPI 2 was also read on the original test split, which the first v7 reading had already read. The second test set (B3n, data/splits_fresh.mat) was never used by this stage.

**Decision.**
- Each fold's frames come from ood_loto_split.m. The known classes' training frames train the fold's network and fit its unknown-threat models. The validation sub-runs are split in two halves, every other sub-run in run order, as D60 split them. The known frames of the first half stop the training early and fit the models' validation parts: the ensemble weights, the standardization of the fused candidates and the pre-processing step. The known windows of the second half are read against the held-out threat's validation windows. They give the AUROC the selection uses and the threshold of FPR95. The halves keep the frames that fitted a candidate out of its own choice.
- Selection on validation only. The production pair has the highest mean validation AUROC over the held-out threats, among the candidates inside the KPI 7 budget (ood_select.m and kpi7_admit.m, unchanged). The nested estimate, the value KPI 2 quotes, takes for each held-out threat the pair chosen on the other threats' validation AUROC, and reads it on that threat's test frames. The held-out threat never fits, weights or chooses anything inside its fold. This is D60's rule, and it now also holds for the frames that make the choice.
- Reading on the second test set. AUROC, FPR95 and Lee et al.'s Algorithm 2 are read on data/splits_fresh.mat. Its link features are un-normalized with the dataset's statistics (asserted equal) and re-normalized with the fold's known training statistics. The script clears the test split as soon as it loads the splits, and it stops when data/splits_fresh.mat is missing. It never falls back to the test split. results/ood_detection.mat stores the validation and test matrices (MpV, MpT, FpT) and TEST_SET. measure_all_kpis.m names the set that KPI 2 was read on.

**Sources.** Lee et al. 2018 (P06): the Mahalanobis score, the validation fit without OOD samples, and Algorithm 2. The threshold that keeps 95% of the known frames is Lee's TNR-at-TPR-95% operating point (docs/v7_research_notes/detection_statistics_sources.md). FPR95 is the metric of Liu et al. 2020 (V7_Liu2020). D60 gives the halves and the nested selection. D82 and proposal mitigations 9 and 17 say the test set is read once.

**Tests.** test_ood_loto_split: the held-out threat is absent from the training and fitting frames. The selection's known windows come from the other half of the sub-runs. The reading frames are the second test set, z-scored with the known training statistics. test_ood_fold_metrics: a score that separates on validation is chosen even when another separates on the test frames. FPR95 takes its threshold from the known validation windows. test_reading_sets_and_labels: the stage mentions sp.test only to clear it, reads data/splits_fresh.mat and selects with ood_select(MpV, ...). The existing test_ood_latency_budget still covers the selection inside the budget.

## B2: the windowed score as the decision cycle reads it (D-F2)

**Why.** win_mean averaged the score over held-out frames only, and separately over known frames only. It joined frames that are not consecutive. A sweeping jammer's isolated hits were averaged with each other and lost their clean neighbours, which inflated its AUROC (0.900 to 0.974 over 8 frames in the review). The deployed monitor averages the last N consecutive cycles, whatever their class (policy_monitor.m).

**Decision.** ood_window.m gives the monitor's statistic: the mean of the score over the last W cycles of the frame's own sub-run, in position order, with partial windows at the start, as the monitor's window fills. ood_fold_metrics.m reads every score at windows of 1, 2, 5 and 8 cycles over each sub-run's full sequence. Each window is labelled by its newest frame's class, which is what the monitor decides on.

**Sources.** policy_monitor.m (mem.wu, unk_now) is the deployed statistic. D60 already reported the averaged score.

**Tests.** test_ood_window_monitor: ood_window gives the same unknown flag as policy_monitor.m, cycle by cycle, over 30 cycles, including the partial windows at the start. Frames given out of order are put in time order, and every run has its own window. test_ood_fold_metrics: two isolated held-out frames among known frames. Per frame the AUROC is 1. Over 4 cycles it is 0.7, because the known neighbours share the hit's window, where the joined mean gave 1.

## B3: the threshold on the deployed statistic (D-F3)

**Why.** ood_thresholds.m set T.maha at the 5% quantile of the per-frame score. The monitor compares the mean of the last ood.win cycles with it. A mean has a smaller spread, so fewer known frames fall below the per-frame quantile: about 97.7% of known frames were kept, not 95% (2.27% flagged at W = 8 in the review). eval_unseen_severity.m counted per-frame flags against a threshold the monitor never applies frame by frame.

**Decision.** T.maha is the 5% quantile of the windowed statistic on the validation split (ood_window.m, per sub-run, partial windows at the start). T.maha_val holds that statistic's sorted values, for the console slider. T.maha_frame is kept beside it for comparison. The cache is recomputed when the detector's score or window differs. eval_unseen_severity.m (B4s) counts a frame as unknown when the windowed statistic of its block is below T.maha. The console's displayed unknown flag uses the same window (demo_gui.m). It must run before C1p, because maha_thr is part of det_id.

**Tests.** test_ood_thresholds_window: a small network on the detector's named layers. T.maha and T.maha_val are the quantile and the values of the windowed statistic over 10 sub-runs. A detector whose window is 1 recomputes the cache and gives the per-frame quantile. test_reading_sets_and_labels: B4s counts the windowed statistic. test_rekey_pools: its fixture now carries the window and score.

## B4: KPI 1 binned by the received Eb/N0; beyond range and the prevalence-normalized reading beside it (D-F4, T-F5)

**Why.** After a path-loss step's label window, a frame is a clean frame: by D83 it is the same link at a longer range. Our signal reaches the receiver L dB below the configured Eb/N0. Those frames were still binned at the configured Eb/N0, so dead links down to −22 dB sat in the 0-15 dB bins and could lower path-loss precision there. Separately, 'none' outnumbers each threat about 9 to 1. Plain macro-F1 lets a small false-positive share of clean frames weigh on every threat's precision.

**Decision.**
- *The Eb/N0 of a frame (kpi_ebno.m).* A frame is read at the Eb/N0 our signal is received with: the configured value, less the path-loss step from its onset on. The dataset's ebno_rx is used when it exists (group A). Otherwise it is derived from the labels: the run's first path_loss frame is the first complete frame after the onset, and the run's level is the step. A frame judged as path_loss is read at the link's Eb/N0 when the step began. The step's depth is the threat's severity level, as a jammer's JSR is, and every threat is read at the link's Eb/N0 without the threat. The bin of a frame is the highest grid point at or below its Eb/N0. "From X dB up" then holds exactly the frames received at X dB or more.
- *Where.* KPI 1, its validation threshold (the same rule on the validation split with the fused targets), the per-Eb/N0 tables and plot (eval_detector.m), the architecture comparison's per-Eb/N0 table (compare_architectures.m), the weak-point breakdown's Eb/N0 factor (analyze_weak_points.m), and the unseen-Eb/N0 table (eval_unseen_snr.m with detector_block.m's received Eb/N0). Each of these readings uses the same rule.
- *Beyond range, never dropped.* Frames received below the grid's lowest point are in no bin. eval_detector.m reports them beside KPI 1: how many, from which classes, how many read right and how many read as path_loss (metrics.beyond). The weak-point breakdown gives them their own 'beyond' cell. eval_unseen_snr.m reports the clean frames after a step's window apart from its table, with their received range. Beside KPI 1 there is also a reading of path-loss frames by their received Eb/N0 after the step (metrics.path_loss_rx), so a reader who prefers the received axis for the step too can see it.
- *Prevalence.* Fixed before any test reading, beside KPI 1 and never in its place. It gives the class shares of the frames above the threshold, and the prevalence-normalized macro-F1 (balanced_macro_f1.m). Every class present weighs the same; precision is R_cc / Σ_j R_jc of the row-normalized confusion matrix (Bayes' rule with equal priors). It has a sub-run bootstrap interval (ci95.macro_f1_above_balanced) and is carried in metrics.prevalence and in measure_all_kpis.m's KPI 1 details.

**Derivation.** Eb/N0 is our received energy per bit over the thermal N0. The receiver's floor is fixed (D83, thermal_nv.m), and a step of L dB lowers our received field by L dB, so the received Eb/N0 is the configured value minus L. Equal-prior precision follows from Bayes' rule: P(true c | read c) = π_c R_cc / Σ_j π_j R_jc, with π_j = 1/C.

**Tests.** test_kpi_ebno: the clean frames after a 10 dB step at 12 dB are read at 2 dB, in bin 0. A 13 dB step at 3 dB puts them beyond range. Path-loss frames and a fused path-loss target are read at the onset's 12 dB. Runs without a step keep their configured value. Numeric targets work, and the dataset's ebno_rx is used, with a rounding just below 9 dB kept in the 9 dB bin. test_balanced_macro_f1: 1000 clean and 100 threat frames, with 5% of the clean frames read as the threat. Plain precision is 0.667 and equal-prior precision is 1/1.05. With equal class counts the two readings agree, and an absent class is out of the mean.

## B5: the mask fill of the training augmentation (D-F6)

**Why.** Since D83 the image is in dB over the thermal floor on [−25, 55] dB, mapped to [0, 1]. The time/frequency masks wrote 0, which is 25 dB below the floor, a value thermal noise reaches in only 0.3% of its bins (spec_image.m). The masked bands were a pattern the receiver never produces.

**Decision.** The masks (now spec_mask.m, called by train_hybrid_net.m) fill with the image's thermal-noise level, spec_image('noise'): the mean image value of a bin that holds thermal noise alone. The bin's power is exponential with mean equal to the floor. The mean of 10 log10 of an exponential variable of mean 1 is −10γ/ln 10 = −2.51 dB, where γ is Euler's constant. That gives (25 − 2.51)/80 = 0.281. A masked band then reads as "no signal there", the way the receiver shows it.

**Derivation.** For X ~ Exp(1), E[ln X] = −γ. The value is checked against a simulated noise-only image.

**Tests.** test_spec_mask_fill: spec_image('noise') equals the formula, and a noise-only image averages to it within 0.01. Masked pixels take exactly that value, and no pixel is set to 0.

## B6: the image scale stated; the architecture comparison on the second test set (D-F7)

**Decision.** extract_spectrograms.m's header now states the scale as it is: dB over the thermal floor of a bin, [−25, 55] dB. compare_architectures.m reads the second test set (data/splits_fresh.mat) when it exists. Otherwise it reads the test split, labelled as a second reading of frames read before (D82). Its per-Eb/N0 table uses the KPI 1 bins, with a 'beyond' column.

**Tests.** test_reading_sets_and_labels (both files).

## B7: the machine's load beside the latency of the candidates (D-F8)

**Why.** D80 decided admissibility from timings on an idle machine. The v7 runs timed it while another profile's run was going.

**Decision.** ood_latency.m logs the machine's load before and after the timings (machine_load.m: CPU load averaged over the processors, the number of MATLAB sessions, the core count). eval_ood_detection.m prints the load and saves it in LC.load. The report states that a concurrent load can only slow the calls, so a candidate admitted under load also fits on an idle machine (conservative), while one excluded under load might fit on an idle machine.

**Tests.** test_ood_latency_load: ood_latency on a small network logs the load before and after, and this MATLAB counts among the MATLAB sessions.

## Smoke check

`run_stage('smoke', 'B2', 'B2F', 'B3', 'B3a', 'B4', 'OOD', 'B4s')` ran in a scratch copy (tar of the branch) on the D83 smoke data, as one MATLAB process. It exited 0 after about 11 min (B2 1.1, B2F 0.3, B3 0.6, B3a 2.5, B4 3.2, OOD 1.8, B4s 0.8). B3n was not rerun: its code is unchanged, so the smoke data's data/splits_fresh.mat was reused. Smoke numbers are not results; they check the chain and the mechanisms.

- **B3, both test sets.** Frames beyond range: 15 of 924 on the test split and 23 of 1848 on the second test set. All of them are clean frames after a path-loss step, received down to −19 dB, and 73% / 65% of them were read as path_loss. These frames used to sit in the 3 dB bin, which is the D-F4 effect. The 2-epoch smoke detector reaches no KPI 1 threshold (NaN, as in D83's smoke), so the prevalence-normalized line prints NaN. Beside it, the path-loss frames by their received Eb/N0 after the step: 12 in the 3 dB bin and 36 below the grid (test split), 24 and 71 (second test set).
- **Validation split** (check script; counts only on the test sets). 58 of 924 frames are received below their configured Eb/N0. 47 of them are judged path_loss and stay at the onset's Eb/N0, 6 move to a lower bin, and 5 are beyond range. On the second test set, 127 of 1848 frames are received lower and 34 are beyond range by the per-frame labels.
- **Prevalence.** On the validation split's out-of-fold fused decisions inside the grid, plain macro-F1 is 44.25% and prevalence-normalized macro-F1 is 41.95% (smoke detector).
- **B3a.** It read the second test set, and its per-Eb/N0 table has a 'beyond' column.
- **OOD.** The selection was made on validation and the reading on the second test set. Over the two smoke folds, mean validation and test AUROC are close, for example last at 8 cycles: 0.936 validation, 0.927 test. The production pair (last over 8 cycles) was chosen on validation. The nested picks were ensemble over 5 and last over 5. The load was logged: CPU 6% before and 9% after the timings. That run counted the -batch launcher as a second MATLAB process; machine_load.m now counts the sessions (bin/win64) only.
- **D-F3 on the smoke detector** (score 'last', 924 validation frames). Against the per-frame threshold, the windowed statistic flags 4.98 / 3.57 / 2.71 / 2.27% of the known validation frames at W = 1 / 2 / 5 / 8: retention reaches 97.7% at W = 8, as the review found. With its own threshold it flags 4.98% at every W.
- **detector_block on a 10 dB path-loss block at 12 dB.** Received Eb/N0 is 12 dB on the two frames before the onset and 2 dB from the onset on. The 7 clean frames after the fused window are the ones eval_unseen_snr.m reports apart. The smoke B4 flies no path-loss block, so its table had none apart.
- **B4s.** Ran with the windowed statistic. In the smoke the production pair is not written (the SMOKE guard), so the window there is 1 and equals the per-frame flag; windows above 1 are covered by the check above and by test_ood_thresholds_window.

**Tests.** All of code/tests/test_core.m passes: 92 of 92, the 83 tests of D83 and 9 new ones, in 11.3 min in the scratch copy as one MATLAB process.

## Open points

- **B4: path-loss frames are read at the onset's Eb/N0, not at ebno_rx.** Read literally, the plan bins every frame by ebno_rx. Here, ebno_rx is applied to every frame except those judged as path_loss: the clean frames after the step's window, which D-F4 is about, and every other frame. A step's own frames keep the link's Eb/N0 when it began, for two reasons. The severity axis (L) stays apart from the Eb/N0 axis, as it does for every other threat. And with ebno_rx on the step's own frames, no path-loss frame could reach the 12 and 15 dB bins (the shallowest step from the top of the grid is 15 − 4 = 11 dB), so KPI 1's "every class from the threshold up" could not be read for path loss there. The received-axis reading of the step's frames is beside KPI 1 (metrics.path_loss_rx). If the main session decides otherwise, it is one line in kpi_ebno.m (eb(st) = eb0(st)).
- **Merge with group A.** kpi_ebno.m takes ebno_rx from the splits when present. Without it, the derivation from the labels is exact and does not depend on A5's label window, because the first labelled frame is the first complete frame after the onset.
- **Thresholds and keys.** maha_thr changes with B3, so det_id changes. rekey_pools stops on pools keyed with the old threshold, and the pools are rebuilt after OOD (the chain reruns from A0). An ood_thresholds.mat cache without the window and score fields is recomputed.
- **Production threshold.** ood_thresholds.m keeps using the full validation split, whose frames also stopped train_detector early and fitted fit_ood_model's validation parts. The leave-one-out reading uses the halves. This is unchanged from before and is stated here.
- **Fold networks.** They stop early and fit on half of the validation sub-runs; production uses all of them.
- **KPI 7.** measure_latency.m does not log the load yet. Group C changes that file (C9).
- **Architecture comparison.** Its per-Eb/N0 macro-F1 now averages over the classes present in a bin. Before, absent classes counted as 0; the two are the same whenever every class is present.
- **Memory.** eval_ood_detection.m holds the second test set (about a third of the dataset's images) beside the training and validation splits. It clears the test split on load, so the total stays close to what it was.
