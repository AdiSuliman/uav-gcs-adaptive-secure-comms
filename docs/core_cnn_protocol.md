# The three-state spectrogram CNN (stage B3c): protocol

Branch `core-cnn` (from `lect-kpi` `0be0662`). This protocol is fixed before any run of the stage.
`train_core_cnn.m` records its SHA-256 in the model file when it trains and reads the fourth test
set only while the file is unchanged.

## 1. What it delivers

This is deliverable 2 of the revised proposal, taken literally: a CNN on spectrograms of the
received signal that classifies three communication states:

- clean;
- narrowband jamming (`tone_jamming`);
- wideband jamming (`jamming`, the barrage noise jammer).

The lecturer's KPI table gives the criteria (section 6):

- macro-F1 >= 85% on an independent test set;
- recall >= 85% for each of the two jamming types;
- false alarms <= 5% in clean states;
- the confusion matrix.

The system's detector does not change. It stays the hybrid: 11 classes, spectrogram and link
features, temporal fusion, the monitor's class. This stage adds the literal deliverable and
compares the two on the same frames (section 7). Nothing in the closed loop reads this model.

## 2. Data

**Sets**
- **Training:** folds 1-4 of `data/splits.mat` (`prepare_data.m`).
- **Validation:** fold 5. Every choice is made here.
- **Test:** the fourth test set `data/splits_fresh3.mat` (stage B3q). Its seeds are 6 000 000 +
  run id, and every sub-run is in fold 6. No three-state model has read it.
- **Not used at all:**
  - the first test split (fold 6 of `data/splits.mat`);
  - the second and third test sets. Both were read before, and both are in the deployed fusion's
    fit set.

**Frames**
- Only the sub-runs of class `none`, `tone_jamming` and `jamming` (`class_run`). A sub-run holds
  one state in all its 20 frames (proposal, mitigation 2). The bootstrap resamples whole
  sub-runs, and the temporal window never crosses one.
- A frame is left out, and counted, when its frame-rule label (`Y_frame`) or its per-cycle label
  (`Y`) differs from its sub-run's class. None are expected, because both jammers are on the air
  in every frame (`threat_active.m`).
- Clean frames of other threats' sub-runs are not part of the task. Examples: the gaps of a WLAN
  sub-run, the frames before a fault's onset, a path-loss sub-run after its step. Their sub-run
  is not a clean link state.

**Expected counts, from the recipe (`run_dataset_sweep.m`)**
- Grid: Eb/N0 from 0 to 15 dB in steps of 3 dB. Each jammer has 8 JSR levels: 0, 4, 8, 12, 16,
  20, 25 and 30 dB (`dataset_levels.m`).
- Per Eb/N0 point in the dataset: 48 clean sub-runs, and 6 sub-runs per JSR level for each
  jammer.
- Training: 3 x 3 840 frames.
- Validation: 3 x 960 frames.
- Fourth test set (4 sub-runs per cell): 3 x 3 840 frames.
- A5 drops frames whose BER is incomplete, so a count can be slightly lower.
- Training class weights: inverse frequency over the training frames, mean 1.

**Input:** the detector image alone (`spec_image.m`), the same image the hybrid sees.
- It is the STFT of the frame: Hann 128, overlap 113, NFFT 128, in dB over the thermal floor of a
  bin, on a fixed scale of -25 to 55 dB, resized to 128 x 128.
- The scale is fixed, so the image keeps the absolute received power.
- No link features, no idle-time records and no antenna gains enter.

## 3. Network and training (`train_spec_net.m`)

**Architecture:** the hybrid's CNN branch (`train_hybrid_net.m`) with a head of its own.
- Three 3x3 convolution blocks with 32, 64 and 128 filters, each with batch normalization and
  ReLU. A 2x2 max pooling follows each of the first two.
- Global average pooling, then FC 64 with ReLU, dropout 0.3, FC 3 and softmax.
- This is the spectrogram-only variant of `compare_architectures.m` without the link-feature
  branch. That variant feeds the branch zeros, so the branch is only a constant bias.

**Training:** the hybrid's schedule.
- Adam, learning rate 1e-3 with cosine decay to lr/20.
- L2 weight decay 1e-4, batch 64.
- Time and frequency masking (`spec_mask.m`: one band of each, on half the images, filled with
  the thermal-noise level).
- Cross-entropy weighted by the training class weights.
- Seed: `rng(42, 'twister')` before each schedule.

**Epochs, chosen on validation only:** two schedules, 30 epochs (the hybrid's) and 60 epochs, are
trained from scratch.
- In each, the epoch with the best validation macro-F1 over the 3 states (per frame) is kept.
- The schedule with the higher best validation macro-F1 is kept. A tie goes to 30.
- So the shorter schedule never limits the network.

## 4. The temporal decision

**What it is**
- The main detector decides on the last N cycles of the frame's own sub-run. The first columns of
  its evidence are the mean log-probability of every class over that window
  (`temporal_evidence.m`, `fuse_classes.m`).
- The three-state decision is that average alone: the class with the highest mean of
  log(max(p, 1e-6)) over the last N frames of the sub-run.
- It is causal. A sub-run's first frames have shorter windows, and a window never crosses into
  another sub-run.
- No link feature enters, so the decision stays spectrogram only.

**Choosing N**
- N comes from {1, 3, 5, 8, 12}, the grid of `select_fusion.m`. N = 1 is the per-frame decision.
- It is chosen on the validation frames by macro-F1 over the 3 states, with 5 folds by sub-run
  (RandStream mt19937ar, seed 61, as `select_fusion.m`).
- The rule: the shortest N whose macro-F1 lies within one standard error (over the folds) of the
  best.
- The validation probabilities come from the epoch chosen on the same set, a slight optimistic
  bias. The test reading is the unbiased check.

## 5. The single reading of the fourth test set

**Before the set is loaded**, the stage stops unless all of these hold:
1. `kpi1_set.m` is `'fresh3'`, the go/no-go is done.
2. The hybrid's own fourth-set reading exists: `results/eval_detector_metrics_fresh3.mat` and
   `results/detector_predictions_fresh3.mat`. So this reading never comes before B3r and never
   changes it.
3. `data/splits_fresh3.mat` exists, and so does `data/splits_fresh3_params.mat`, with the
   `params_id` of `params.mat`.
4. `data/core_cnn_model.mat` exists, is newer than `data/splits.mat` and carries this protocol's
   SHA-256.
5. None of these exists yet:
   - `results/core_cnn.mat`;
   - `results/core_cnn_read_started.txt`;
   - a committed record `docs/core_cnn_read_*.txt` with this `params_id` (records named
     `*_aborted*` do not count).

**The marker**
- `results/core_cnn_read_started.txt` is written before the set is loaded. It records the time,
  the commit and code tree, local changes and untracked `.m` files, the `params_id`, and the
  SHA-256 of the model and of this protocol.
- From then on the model is never retrained in that checkout.

**What the stage never does:** write `data/trained_detector.mat`, `data/fusion.mat` or
`data/ood_thresholds.mat`. These stay frozen from B3r on (`docs/d91_set4.md`, step 4). The hybrid
is only read from its saved reading, with no new inference.

**Order of the outputs**
- No outcome line is printed before every metric is computed.
- The predictions (`results/core_cnn_predictions.mat`) are saved first, then `results/core_cnn.mat`,
  `results/core_cnn.txt` and the figures.

**After the reading**
- Copy the marker to `docs/core_cnn_read_<p>.txt` (`p1`, `p3` or `p2`), and commit it on the
  profile's branch. Nobody deletes the marker or the record to read again.
- If the stage stopped after the marker and its log holds no outcome line, the set was not read
  for this model. Adi may then allow one more run: the marker is kept as
  `docs/core_cnn_read_<p>_aborted_<time>.txt` and removed from `results/`.
- Any outcome line in the log spends the set for this model.

## 6. Metrics and verdicts

**Frames:** the test frames of the three states at every Eb/N0 point, with no Eb/N0 threshold.

**Decisions**
- The official decision is the windowed one at the N chosen on validation.
- The per-frame decision (N = 1) is reported beside it.

**Metrics**
- The 3 x 3 confusion matrix, rows the true state.
- Macro-F1: the mean F1 of the three states.
- Recall of each jamming type.
- False alarms: the share of clean frames read as a jamming state. For the hybrid, the share read
  as any threat class, and its part read as one of the two jamming classes.
- Beside them:
  - macro-F1 per Eb/N0 point;
  - recall per JSR level for each jammer;
  - the steady-state frames (a full window);
  - the detection delay: cycles from a jamming sub-run's first frame to its first frame read as
    the right state, as the median, p90 and the share never read right.

**95% intervals**
- Bootstrap over whole test sub-runs, 1 000 resamples, seed 7 (as `eval_detector.m`). It covers
  macro-F1, the recalls, false alarms, macro-F1 per Eb/N0, and the paired difference to the
  hybrid.
- Recall per level: `boot_cluster.m` (2 000 resamples by sub-run).

**Verdict against each threshold (85% and 85%, 5%)**
- **met (committed):** the 95% interval clears the threshold.
- **met (not committed):** the point clears it, the interval does not.
- **not met:** the point does not clear it.

## 7. Comparison with the hybrid on the same frames

**Source:** the hybrid's saved fourth-set reading, `results/detector_predictions_fresh3.mat`.
- It holds the monitor's class after the fusion over N = 12 cycles (`fusion_pick.m`) on the same
  frames, matched by sub-run and position.
- It is read as three states with `three_state_view.m`'s mapping: a frame read as another class is
  an error of its state ('other'), never a hit.

**Beside it:** for reference, the hybrid's `three_state_view.m` of its whole confusion matrix
(every frame labelled `none`, `tone_jamming` or `jamming`), as `measure_all_kpis.m` reports it.

**The difference:** a paired bootstrap over the same sub-runs, the core CNN's windowed macro-F1
minus the hybrid's.

**What it is for:** analysis only. Nothing is chosen from it, as with the CNN contribution in the
proposal.

## 8. Outputs

| File | What |
|---|---|
| `data/core_cnn_model.mat` | net, the chosen schedule and epoch, N, validation tables, `trained_at`, `protocol_sha` |
| `results/core_cnn_validation.txt` | the epochs of both schedules and the N table (validation) |
| `results/core_cnn_training.png` | validation macro-F1 per epoch of both schedules |
| `results/core_cnn_read_started.txt` | the reading's marker |
| `results/core_cnn_predictions.mat` | per test frame: state, both core decisions, the hybrid's class, run, position, Eb/N0, level |
| `results/core_cnn.mat`, `results/core_cnn.txt` | the reading (section 6) and the comparison (section 7) |
| `results/core_cnn_confusion.png`, `results/core_cnn_confusion_frame.png` | 3 x 3 confusion matrices, windowed and per frame |
| `results/core_cnn_ebno.png`, `results/core_cnn_jsr.png` | macro-F1 per Eb/N0; recall per JSR level |

## 9. Running it

The stage is not in the takeover's chain. It runs by hand, one profile at a time, through the
gate. The MATLAB command holds no `run_stage(`:

```
bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 65 uav-gcs-v7 logs/stage_B3c_<time>.txt "cd(setup_paths()); run('train_core_cnn')"
```

- Training and validation only, before the hybrid's B3r:
  `cd(setup_paths()); CORE_CNN_TRAIN_ONLY = true; run('train_core_cnn')`.
- A later run reuses the saved model and reads the set once.
- `run_stage('B3c')` runs the same script, with its own log, outside the gate only.

## 10. Time and memory (estimate, not measured)

**Time**
- Loading `data/splits.mat` (about 7.0 GB on disk, v7.3): 5-10 min.
- Training on the GPU (RTX 4070 SUPER), 11 520 images:
  - 30 epochs: about 3-7 min;
  - 60 epochs: about 6-13 min;
  - the basis: B2 trained the hybrid on 81 312 images for 30 epochs inside a 21-46 min stage.
- Choosing N: under 1 min.
- Loading the fourth set (about 4.8 GB): 3-6 min.
- Inference, the bootstrap and the figures: about 2 min.
- **Total: about 25-45 min**, up to about 1 h while other jobs run.
- On the CPU alone (`-singleCompThread`, no GPU), training would take about 3-6 h.

**Memory**
- Peak RAM about 10-14 GB, while `data/splits.mat` is loaded: about 122 000 images x 64 KB = 8 GB,
  the other fields, the reader's buffers, and the three-state subset of about 0.95 GB. (B3a held
  18.7 GB, but it keeps three masked copies of the splits.)
- The fourth set: about 6-7 GB.
- GPU: under 1.5 GB.
- The gate figure of the B stages (65 GB of free commit, `docs/d91_deploy.md` 5.0) covers it.

## 11. Tests

The `test_core_cnn_*` functions and `test_spec_net_trains` in `code/tests/test_core.m` cover:

- the frame selection;
- the causal window;
- the metrics and their mapping;
- the choice of N;
- the bootstrap;
- the verdicts;
- the detection delay;
- the network's training on synthetic images;
- the stage's guards before the set is loaded, and their order.
