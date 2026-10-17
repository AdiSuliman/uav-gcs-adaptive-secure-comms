# d88 blockers before C1p

Branch `d88-blockers`, from the run's code `c2c8b8b`. It covers five audit findings, in priority
order: out-align-scramble, out-mmse-gain-dd, sel-02 keying, out-b3a-arch / out-b3a-svm / sel-04,
and the print-only B3 lines. The evidence for each finding and the verifiers' refined fixes are in
`audit1_confirmed.json`. The numbers below were measured on this branch.

## 1. Link feature 13 (`align`) scrambled in every A5 dataset (BLOCKER)

**Cause.** `run_dataset_sweep.m` appended the per-flight draw `d.align(1)` and the measured `F.align`
to the same field `D.align`. Each sub-run therefore added 2n values: n copies of the draw, then
the n measurements. `extract_spectrograms.m` reads `ds.meas.align(idx)` with `idx` in 1..N, so
feature 13 of frame i came from roughly sub-run i/2.

**Code.**
- `run_dataset_sweep.m`: the draw is now `align_gcs` (struct init, accumulation, `dataset.align_gcs`),
  so the MEAS loop is the only writer of `align`. Two new guards:
  - at init, an assert that no MEAS name is also a field of its own;
  - before the save, `assert_frames`: every field of `D` holds one entry per frame, and every
    `dataset.meas` field holds N values.
- `assert_frames.m` (new): checks per-frame counts. A cell vector counts its elements; an array of
  more than two dimensions counts its last one.
- `extract_spectrograms.m` (A6) checks `ds.meas` and every per-frame field of the dataset.
  `prepare_data.m` (B1) checks every per-frame field of the spectrograms, for the dataset and the
  test sets. A dataset in the old layout now stops A6 and points to `repair_align.m`.
- `repair_align.m` (new) is a one-off, idempotent repair of a stored dataset:
  - it reads every sub-run in stored order (frames contiguous, offset 2 x the frames before it)
    and checks the layout in every sub-run: the first n values must be one constant draw, and the
    spread of the last n is reported;
  - only then does it write `meas.align` (the measurement, N values) and `align_gcs` (the draw, N
    values), remove `align`, and record `meta.align_repair`;
  - it saves to a temporary file, checks it, keeps the original as `<name>_before_align_repair.mat`
    (never deleted) and moves the new file into place;
  - an existing backup stops it, and a second call reports `already`;
  - `repair_align(f, true)` is a dry run that reads only the three fields through HDF5.

**Tests.** `test_dataset_align_fields` and `test_align_repair`:
- the MEAS names and the draw fields are disjoint, by a parse of the source;
- the guard's count rules;
- the repair of a synthetic 2N dataset: values, backup, idempotence, the dry run writing nothing,
  and a broken layout stopping with the file untouched;
- the old layout fails A6's guard.

**Numbers.** Read-only, on copies of profile 1's files:

| File | Frames | Sub-runs | Layout holds in | Time |
|---|---|---|---|---|
| `dataset.mat` (dry run) | 121,968 | 5,808 | 5,808 (100.00%) | 0.3 s |
| `dataset_fresh.mat` (dry run) | 83,664 | 3,984 | 3,984 (100.00%) | 0.1 s |

The full repair was also run on the copy of `dataset_fresh.mat`. It took 4.2 min, and the A6
guards pass on the result. The measured `align` class means now match the audit's "own" values:

| Class | Measured `align` | Flight draw `align_gcs` |
|---|---|---|
| jamming | 0.875 | 0.305 |
| tone | 0.885 | 0.350 |
| path_loss | 0.454 | 0.308 |
| WLAN | 0.682 | 0.326 |
| none | 0.728 | 0.311 |

A second call returned `already`.

## 2. Predicted MMSE gain from known symbols only (MAJOR)

**Cause.** `mmse_gain` is read from the real receiver's decision-directed channel and covariance.
Under strong or CW interferers the MRC decisions fail, the estimates turn toward the interferer,
and the gain collapses (the tone reads 0.6-1.6 dB at every JSR). The rule's nulling flag and the
agent's state read that value.

**What was asked, and what the prototype showed.** The specified estimator was:
- R_y per window of data snapshots and a whitened LS channel on the known symbols;
- x = h^H R_y^-1 h and SINR_mmse = x/(1-x).

It was implemented and measured in a prototype (scratchpad `d88/proto_mmse.m`: 3 antennas,
Rician K 10 dB, 358 Hz, the frame layout, noise jammer and tone, 100 frames per point). The
problem is that x/(1-x) needs K >> M x SINR known symbols, while a window holds 8-16 of them:
- above about 12 dB SINR the bias-corrected estimate clips at x -> 1;
- on the clean link at Eb/N0 12 dB, 40% of frames read G >= 6 dB (false nulling flags);
- without bias correction it saturates the same way.

**What was implemented: `mmse_predict.m`, `F.mmse_pred`.** The same Winters, Salz & Gitlin 1994
DMI (eqs. 19-23) on the reference samples, measured on held-out symbols instead of predicted
through x/(1-x). No decisions are used anywhere.
- **Snapshots.** Every antenna's samples, matched-filtered over the whole run as the receiver
  filters them, taken at the receiver's arrival and frequency.
- **Residual frequency.** The receiver's frequency can be left a few kHz off: 0.6-2.3 kHz after
  the MRC receiver's pilot tracking under a 16-30 dB tone, measured on the true component. This
  offset is removed using the MMSE receiver's own estimator: the pilot-block phase step weighed
  by the inverse covariance between the blocks (build_threat_model.m, MODE 2).
- **Held-out groups.** Each known group (the long training, then every pilot block) is held out
  in turn. On the known symbols of the groups within 2 of it:
  - r = mean(y s*) and R = mean(y y^H) give the DMI weights R^-1 r (Winters eqs. 19-23; K >= 2M
    samples, Reed-Mallett-Brennan, about -0.5 dB at K = 16) and the MRC weights r.
  - Both combine the held-out group.
  - The SINR of each combiner is measured over the frame's 76 held-out symbols against their known
    values. One complex gain is fitted, its own estimation noise (v/N) is taken out, and the floor
    is 1/N, which is -18.8 dB.
  - G is the ratio of the two SINRs. No symbol is judged by weights fitted on it.
- **Short training.** It is a neighbour only, never held out. Its period of 4 symbols puts its
  power on 4 spectral lines, so a CW tone near one of them reads as our signal over its 10
  repeats. Before this change the tone at 30 dB failed V13.
- **Arrival search.** Where MMSE reads no SINR above 0 dB at the receiver's arrival (the MRC
  receiver lost the frame), the arrival window is searched as the MMSE receiver acquires on its
  own. A new arrival is taken only at 2x (3 dB) the receiver's arrival's SINR, so a weak link's
  noisy maximum is not.

**Wiring.**
- `pool_cell.m` stores `mmse_pred` per frame, and `rekey_pools.m` FRAME knows it.
- `link_env.m` puts it in `obs.mmse_pred` (NaN from pools without it). It also reaches the GUI
  (lead-in, run and console), `episode_cycle.m`, `measure_latency.m` and `v3d_engine.m`.
- `policy_decide.m` passes it to `rule_based_policy.m` for the nulling flag, instead of the
  feature `mmse_gain`. NaN means not separable.
- `policy_monitor.m` uses it in the agent's state, in the same row, so the state size is
  unchanged. NaN becomes 0 dB.
- The nulling threshold is now an explicit argument: `PP.rule_mmse_db` when set, else
  `C.rule_mmse_db`. The default is unchanged at 6 dB.
- The detector feature `mmse_gain` is unchanged and re-documented as decision-directed. A5, A6
  and B2 need no change from this item.
- `build_policy_pools.m` MODEL_TAG is now `v7-D88`, so C1p checkpoints from a run without
  `mmse_pred` are never reused.
- `build_threat_model.m` has a new `p.own_out` flag: output 4 (our own received component) for
  the validation's true channel. The link is unchanged; the flag is never set by the pipeline.

**validate_phy V13.** It runs inside `validate_phy()` and `validate_phy('flat')`, and alone as
`validate_phy('V13')`. It has its own PASS/FAIL lines; the existing pass rules and the returned
`ok` are unchanged.

Setup: Eb/N0 6 dB, 6 flights x 19 frames per row. Theory is computed on the true channel (our
own received component) and the true interference + noise of every frame.

| Row | G | Its combiners | Optimum (Winters) | Ceiling | JMc(1-c) | MMSE meas/th | MRC meas/th | Share >= 6 dB (G / optimum) | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| clean link | -0.6 | -0.5 | +0.1 | +30.0 | +0.1 | 11.2/11.1 | 11.7/11.7 | 0%/0% | PASS |
| V8b jam 10 dB | +17.4 | +17.8 | +15.9 | +30.2 | +15.6 | 11.4/11.3 | -6.0/-6.1 | 100%/99% | PASS |
| V11 jam 10 dB | +17.2 | +17.0 | +15.4 | +28.8 | +15.9 | 10.0/10.1 | -7.1/-7.3 | 100%/100% | PASS |
| V12c jam 16 dB rho 0.3 | +19.1 | +19.4 | +14.3 | +22.0 | +12.2 | 3.2/3.6 | -16.9/-15.9 | 100%/100% | PASS |
| V12c jam 16 dB rho 0.9 | +23.2 | +22.7 | +18.4 | +25.8 | +18.2 | 7.0/6.9 | -17.6/-16.5 | 100%/100% | PASS |
| V12c jam 30 dB rho 0.3 | +7.7 | +7.6 | +16.3 | +7.8 | +13.1 | -11.0/-11.2 | -18.8/-18.8 | 67%/99% | PASS |
| V12c jam 30 dB rho 0.9 | +15.5 | +16.6 | +23.0 | +15.6 | +20.4 | -3.2/-2.2 | -18.8/-18.8 | 95%/100% | PASS |
| tone 4 dB | +10.3 | +10.1 | +10.2 | +29.0 | +10.6 | 10.2/10.0 | -0.2/-0.1 | 97%/96% | PASS |
| tone 16 dB | +26.3 | +24.0 | +21.2 | +28.4 | +21.2 | 9.6/9.5 | -18.2/-14.4 | 100%/100% | PASS |
| tone 30 dB | +23.7 | +25.8 | +31.3 | +24.1 | +31.1 | 5.2/7.0 | -18.8/-18.8 | 76%/100% | PASS |
| reactive 16 dB | +25.0 | +24.8 | +20.6 | +28.3 | +21.0 | 9.5/9.5 | -16.8/-15.7 | 98%/99% | PASS |

How to read the columns:
- **G** is the predictor's median.
- **Its combiners** is the theory of the predictor's own DMI and MRC weights on the true channel.
- **Optimum (Winters)** is the theory with perfect CSI.
- **Ceiling** is the measured MMSE SINR over the MRC measurement's floor.
- **JMc(1-c)** is the closed form for one directional interferer.

Rules (all pass, 11/11 rows):
- the clean link within 1 dB of 0;
- every other row within 3 dB of the theory of its combiners and at most 3 dB below the optimum
  or the ceiling, whichever is lower;
- the tone rising from 4 to 16 dB and holding at 30 dB.

Result: `V13 predicted MMSE gain: 11/11 rows -> PASS`, in 2.2 min.

For reference, the theory for one directional jammer is about 28 dB at J = 30 dB, M = 3. The
measured G reads 24-26 dB at 30 dB, held at the ceiling (the MRC floor of 76 symbols).

**Limits.**
- **Spatial-only combining.** The predictor rates combining over the antennas only. Against a
  dispersive 30 dB jammer (V12c rho 0.3) it reads 7.7 dB, while the deployed MMSE receiver's
  space-time taps null more.
- **Frames the MRC receiver loses.** At 30 dB, 5-33% of frames read below 6 dB. In those frames
  the MRC receiver's coarse sync failed: the theory on the true channel, at the same timing,
  reads the same.
- **Over-reading against perfect-CSI MRC.** Over the optimum theory, G reads +2 to +5 dB higher,
  because the MRC its weights come from carries the interferer's leakage of 16 reference symbols
  (the receiver's own MRC has the same, with an effective K of about 11). The rows above check G
  against that MRC.

**Tests.**
- `test_mmse_predict_known_symbols` (the threat model): clean median within 1.5 dB of 0; tone
  16 dB above 12 dB and at least 6 dB above the decision-directed `mmse_gain`.
- `test_policy_mmse_pred`:
  - the rule nulls on `obs.mmse_pred`, not the feature;
  - `PP.rule_mmse_db` overrides the threshold, and NaN means no nulling;
  - the agent's state row reads the value;
  - `link_env` carries the pools' values frame by frame;
  - `pool_cell` and `rekey_pools` know the field.

**Threshold.** `C.rule_mmse_db` is still 6 dB, now on the new reading. Re-choose it on the
validation pools in C2, as the plan says (sel-08: mu + 3 sigma on clean validation frames, 3 dB,
9 dB, each with and without `rule_slot`). The selected value goes in `PP.rule_mmse_db` and is
stored with the agent.

## 3. Unknown-threat threshold out of the detector identity (sel-02 keying)

- `detector_id(trained_at, ood, FZ)` no longer takes the threshold. The pools store every frame's
  score, and `PP.maha_thr` is compared at decision time in `link_env.m` (draw) and
  `policy_monitor.m` (window), unchanged.
- `build_policy_pools.m` also stores `PP.maha_val`, the sorted validation statistic of
  `ood_thresholds.m`, and `PP.unk_retain`. `unk_threshold(PP.maha_val, r)` gives any retention's
  threshold with the same rule as `ood_thresholds.m`, so C2 can choose 0.95 or 0.99 without
  re-keying.
- `train_dqn.m` saves `maha_thr` with the agent. `evaluate_policies.m`,
  `experiment_unknown_threat.m`, `experiment_combo_generalization.m`, `edge_map.m` and
  `measure_latency.m` set `PP.maha_thr` from it.
- `policy_stamp.m` includes it, and `result_status.m` loads it.
- `rekey_pools.m` no longer stops on another threshold and keeps the pools' own. KNOWN lists
  `maha_val`, `unk_retain` and `rule_mmse_db`.
- `check_det_id.m` is documented to match.
- Callers updated: `build_policy_pools`, `build_check_pools`, `build_clean_test_pools`,
  `measure_latency` and `result_status`. The latter two no longer compute `ood_thresholds`.

**Tests.**
- `test_detector_id`: 3 inputs; the identity changes with each remaining key; `unk_threshold`
  follows the quantile rule of `ood_thresholds`; the decision-time readers; the agent readers.
- `test_rekey_pools`: pools with another threshold, `maha_val` and `unk_retain` are re-keyed and
  keep them.
- `test_result_status`: the stamp changes with `maha_thr`.
- `test_clean_pool_identity`.

## 4. Architecture comparison (out-b3a-arch, out-b3a-svm, sel-04)

Changes in `compare_architectures.m`:
- **Fused, out of fold, on validation.** Each variant's validation outputs go through the deployed
  fusion (`fuse_classes`), with `data/fusion.mat`'s N and lambda fixed. The fusion is fitted and
  read out of fold over `select_fusion`'s 5 folds by sub-run (seed 61), on the per-cycle targets
  (`fusion_target`). The latched cause of a lost branch is printed beside, using the deployed
  `FM.os_thr`. After the d87 merge, the monitor's class is that column only if `FM.latch` is true.
- **Random forest grid.** Leaf size {1, 5, 20} x predictors per split {sqrt(p), p/3}, 100 trees
  each, chosen by per-frame validation macro-F1. The final fit has 200 trees.
- **Kernel SVM.** Inputs z-scored on train; the kernel scale is sqrt(p) x {0.5, 1, 2} (sqrt(p) is
  LIBSVM's gamma = 1/p in MATLAB's form) x box constraint {1, 10}, chosen the same way. The fused
  input uses the softmax of the negated losses.
- **Test columns.** They are labelled as readings, not selections: per-frame accuracy, macro-F1 and
  per class; the fused reading, with the fusion refitted on each variant's own validation outputs;
  and per Eb/N0. Frames beyond the grid are reported as the share read right (one class, `none`),
  no longer as a one-class macro-F1.
- **Header.** States the epoch bias of the hybrid's validation outputs and that accuracy is not
  comparable (unweighted forest and SVM).

Expected on profile 1, from the audit's validation runs: fused, the hybrid leads the forest
(93.3 vs 92.1%), while per frame the forest leads (82.8 vs 81.1%).

Cost: 6 SVM fits and 6 100-tree forests on top of B3a, about +20-30 min per profile.

## 5. Print-only lines in `eval_detector.m` (no behaviour change)

- The per-frame network scored on the fused decision's targets. This isolates the label change
  from the fusion's own gain (`select_fusion`, N = 1 to N).
- Path-loss recall by step [dB] x K band of our signal (< 0, 0-10, >= 10 dB) x onset age in
  cycles (0-2, 3 to N-2, N-1), with frames and sub-runs per cell.
- The sweeper's sub-runs never confirmed by the class path, split by whether a frame of ours was
  hit (label_frame `sweeping_jammer`). The degradation path is not read there.

## Verification

- **Targeted tests while working.** All pass after fixes, including the threat-model test of the
  predictor (140 s).
- **Full suite.** `runtests('code/tests/test_core.m')` from the worktree root, one MATLAB batch:
  **170/170 passed** (46.0 min).
- **`validate_phy('flat')`.** Run on the worktree's `params.mat` (params_id `ee81c3c0f98a4bc2...`)
  in a scratch folder: **PASS** in 86.0 min. Theory gaps 7/7 within 0.3 dB, seeds PASS, tone PASS.
  V12c is not run in flat mode. V11 loss is +0.91, +0.98 and +4.92 dB, and V8 holds its MMSE/MRC
  BER ratios of 10.8-44.3 dB; both are unchanged physics.
- **V13.** 11/11 PASS inside the flat run. Its rows are within 1 dB of the standalone run in the
  table above. The exception is V12c jam 30 dB rho 0.3, which reads +6.7 dB with 61% of frames at
  or above 6 dB.
- **Smoke.** `run_stage('smoke','A0','A5','A6','B1','B2','B2F','B3','B3a')` on a scratch
  worktree of `60b285b` (scratchpad `d88_smoke`) passed:
  - A5 20.6 min, B2 1.8 min, B3 0.5 min, B3a 5.8 min;
  - the new B3 lines and the B3a tables print;
  - the SVM grid picked kernel scale sqrt(p) = 4.80 with box constraint 10;
  - smoke figures are not results.
- **Reduced C1p check.** C1p in the smoke takes about 6 h, so it was replaced by `c1p_check.m`
  (in the smoke folder). It runs one cell each of the clean link, jamming at 23 dB and the tone at
  23 dB through `pool_cell.m` with the smoke's detector, under no_action, spatial_diversity and
  channel_switch+spatial_diversity, with 2 geometries of 20 frames.
  - Every pool carries `mmse_pred`, frame by frame, finite.
  - Every pool field is in `rekey_pools`' FRAME list: **PASS**.
  - Medians at no_action:
    - jamming: +18.4 dB, against a decision-directed `mmse_gain` of +5.3 dB;
    - tone: +14.4 dB, against +1.7 dB;
    - clean link: -0.4 dB.
  - After channel_switch (the interferer left behind), about +1 dB.
  - About 80-120 s per cell for 3 configurations.

## Deployment steps for the main session

Merge `d87-fusion` and `d88-blockers` into `v7-merge` (see "Merge with d87"), run the full suite
on the merge, then bring the merge into the profile worktrees. Then, per profile, **before C1p**:

1. **Hold the chain before C1p** (Adi's call). The stages now running on the scrambled feature
   are replaced:
   - profile 1: OOD and B4s;
   - profile 3: B3 to B4s.
   Do not keep any C1p checkpoint: MODEL_TAG changed, so they are not reused anyway.
2. **Repair the datasets.** From the profile's root (`C:\Users\Adi Suliman\uav-gcs-v7` for profile
   1, `C:\Users\Adi Suliman\uav-gcs-v7-p3` for profile 3), first the dry run, which must report
   100%:
   ```
   matlab -batch "addpath('code'); setup_paths; repair_align('data/dataset.mat', true); repair_align('data/dataset_fresh.mat', true)"
   ```
   then the repair:
   ```
   matlab -batch "addpath('code'); setup_paths; repair_align('data/dataset.mat'); repair_align('data/dataset_fresh.mat')"
   ```
   It takes about 5 min per file. The originals stay as `data/*_before_align_repair.mat`.
   - Profile 3: repair `dataset_fresh.mat` once its A5 (B3n) has finished. The dry run asserts the
     layout.
   - The third test set (B3m) is built by the fixed code and needs no repair.
3. **Rerun, in this order (no A5):**
   1. A6: `run_stage('A6')`.
   2. B1: `run_stage('B1')`. The norm of feature 13 changes (it was mean 0.5103, std 0.3837).
   3. The fresh set's A6 and B1, without its A5. B3n would rerun A5, so do not use it:
      ```
      matlab -batch "cd <root>; setup_paths; FRESH_TEST = true; run('extract_spectrograms'); run('prepare_data')"
      ```
   4. B2, B2F, B3 (reads the repaired second test set: a diagnostic only), B3a, B4, OOD and B4s.
      Once d87 is merged, add B3m after B2F; it is the reading that is reported.
   5. `data/gui_norm_stats.mat` is rebuilt by B4 and B4s, because it is older than
      `splits.mat`. Check its time, or delete it before B4.
   6. `data/ood_thresholds.mat` is recomputed when the detector is newer.
   7. Then C1p. The launcher's `resume` goes from C1p.
4. **Check after C1p.** `PP.model_tag` is `v7-D88`; every pool has `mmse_pred` (`c1p_check.m` in
   the smoke folder does this on one cell); `PP` has `maha_val` and `unk_retain`.
5. **C2 (plan 1.5).** Choose `rule_mmse_db` on the validation pools (sel-08) and store it as
   `PP.rule_mmse_db` with the agent. Choose the retention {0.95, 0.99} as
   `unk_threshold(PP.maha_val, r)` (sel-02), stored as the agent's `maha_thr`; the readers
   already apply it.

## Merge with d87

A trial merge of `d87-fusion` at `b1768b4` into `d88-blockers` at `60b285b` ran in a scratch
worktree and was aborted afterwards. It was automatic with no conflicts, `test_core.m` included.
Both branches touch these files in separate hunks:
- `run_dataset_sweep.m`, `extract_spectrograms.m` and `prepare_data.m` (d87: the B3m third test
  set; d88: `align_gcs` and the guards);
- `policy_monitor.m` (d87: the latch; d88: the state row);
- `eval_detector.m`, `edge_map.m` and `result_status.m`;
- `test_core.m`.

After the merge:
- The third test set (`dataset_fresh2.mat`, B3m) is built with `align_gcs` and the guards.
- `compare_architectures.m` prints the fused and the latched columns. The monitor's class is the
  latched column only where `FM.latch` is true (`onset_shape('on', FM)`).

d87 had uncommitted files in its worktree when the trial merge ran (`measure_all_kpis.m`,
`docs/d87_fusion.md`). Repeat the merge on its final commit.
