# D85 cues: telling a faulty antenna from a hidden one by the receiver's own channel estimates (branch d85-cues)

Branch `d85-cues` from v7-merge `f9b813d` (D81-D85, with the D85 onsets: the connector's step and the shadowing roll-in inside the sub-run, and the D85 obs cues). This note is the merge input for the DECISIONS.md entry; DECISIONS.md is not edited here. Every number below comes from validation-style sub-runs with our own seeds. The test split was not read.

## Why

When one branch is lost, D85 recalls the cause on about two frames of three: a faulty connector against a hidden antenna. The D85 cues read only the antennas' gains (`window_cues.m`: the weak branch's moment K, its spread, its offset). From gain magnitudes alone, the moment K of a window of about 10 cycles scatters by several dB. At low link K, both branches look Rayleigh.

The receiver already holds more: every antenna's complex channel per data block (`Hq`), its residual power (`Rq`), and the decided frame. From these it can rebuild every antenna's channel at whole-symbol lags (the equalizer's first pass estimates the same lag channels from the training, `eq_train`).

The physics separates the two causes:
- **Faulty connector.** It scales everything its antenna receives. The branch's normalised correlation with the other antennas does not change, and neither does its line-of-sight share across delay.
- **Hidden antenna.** It loses its line of sight (K about -16 dB, Sun et al., Part IV). What remains correlated with the other antennas is only its diffuse part, through the receive correlation.

## Decision

### The record: every antenna's channel estimates per frame
Code: `branch_record.m` (new) and `extract_closed_loop_frames.m`.

`extract_closed_loop_frames.m` adds these per-frame fields (receiver measurements only):
- `F.hq`: the frame mean of every antenna's `Hq`, calibrated.
- `F.rq`: the diagonal of `Rq`.
- `F.cir`, `F.cir_nv`, `F.cir_d` from `lag_channels`: each antenna's LS channel on the frame rebuilt from the decisions (`remod_frames`, at the receiver's own arrival and CFO), at whole-symbol lags -3 .. 1 + ceil(p.tdl_max_ns x symbol rate). Also the residual power, and the diagonal of inv(X'X), so the noise of each lag's estimate is known.

`F.bch = branch_record(F)` holds 9 values per antenna:
- the gain;
- the frame-mean channel and its noise power;
- the channel at the frame's line-of-sight lag l0 (the lag holding the most power summed over the antennas) and its noise power;
- the noise-debiased power at l0, and at every other lag together.

### The fusion columns
Code: `window_cues.m`, 42 to 52 columns.

The ten new columns are computed over the last `window_cues('branch_window')` = 10 cycles (the link features' window). The cycles used start at the weakest antenna's step: the best split of its offset, kept only when it drops by more than 3 dB.

| Group | Column | Meaning |
|---|---|---|
| C1, coherence | `coh_weak` | the weakest antenna's normalised cross-correlation with each other antenna, over the cycles, with noise-debiased powers |
| | `coh_others` | the same between the other antennas: the link's own line-of-sight share |
| | `coh_ref` | the weakest against the others' sum, aligned by their mean cross phase |
| | `coh_contrast` | `coh_weak` minus `coh_others` |
| | `coh_cycles` | the cycles used, over 10 |
| C2, line-of-sight lag | `los_weak` | the weakest's power at l0 over its other lags [dB] |
| | `los_others` | the same for the other antennas |
| | `los_contrast` | `los_weak` minus `los_others` |
| | `los_k` | the Rician K of its l0 power over the cycles (moment method, Aoki & Honda 2025, eq. 2) |
| | `los_coh` | its l0 coherence with the others |

Further rules:
- A common phase of the frame cancels in every cross-product.
- Only the gains decide which antenna is weakest. The antenna's place in the array is not used (as in D85 obs): `shadow_hidden.m`'s far-end antenna is a stated assumption, not a source.
- A missing record gives 0.

The spatial covariance concentration (lambda1 / trace) was studied and not adopted:
- On the raw covariance it carries no information (AUC 0.55): a fault changes it too.
- Normalised, it is a weaker copy of C1 (AUC 0.82 against 0.93).

### Carriers
- **Dataset and splits:** `run_dataset_sweep.m` (`D.bch`, `dataset.bch`, `bch_names`; FRESH_TEST takes the same path), `extract_spectrograms.m`, `prepare_data.m`.
- **Fusion builders:** `fuse_classes.m` (S.bch; the branch records over the last 10 positions), `detector_block.m`, `det_frames.m`.
- **Pools and closed loop:** `pool_cell.m`, `rekey_pools.m`, `link_env.m` (obs.bch), `episode_cycle.m`, and `policy_monitor.m`. `policy_monitor.m` keeps its window at least 10 cycles when a fusion is loaded and builds the same row as fuse_classes.m.
- **Others:** `measure_latency.m`, `demo_gui.m`.
- **Fusion refit:** the fusion is refitted by B2F (select_fusion.m, unchanged). The column guard in `fuse_classes('apply')` stops a fusion fitted before this change. The dataset (A5) and the pools are rebuilt.

## Sources and derivations
- Sun et al., Air-Ground Channel Characterization for UAS, Part IV: Airframe Shadowing (IEEE TVT 2017): inside shadowing the hidden antenna's K is about -16 dB. That is the model's `p.shadow_k_db`, unchanged.
- Aoki & Honda 2025 (library, V7): the moment-method K, eq. 2, for `los_k`. Greenstein et al. 1999 (IEEE Commun. Lett., doi:10.1109/4234.769521) gives the same estimator form. Tepedelenlioglu, Abdi & Giannakis 2003 (IEEE TWC, doi:10.1109/TWC.2003.814338) size its window. **Neither is in the project library.** The window size here is the link features' 10 cycles, not derived from them.
- Physics behind C1:

  - Branch model: h_k = g_k (sqrt(kappa_k) a_k e^{j theta} + sqrt(1 - kappa_k) d_k), with E[d_i d_j*] = rho^|i-j|.
  - Normalised correlation of the weak branch with another antenna:
    - fault: |kappa e^{j phi} + (1 - kappa) rho|, the same as before the fault;
    - shadowing: about sqrt(1 - kappa) rho.
  - The contrast is large when the link K is moderate or high.
- Physics behind C2: a hidden antenna's power at the line-of-sight lag is only its diffuse share there. That share is about 0.6 at a 234 ns delay spread with 1 us symbols, and about 0.2-0.3 above 300 ns. A faulty branch keeps the link's share, 0.8-0.9.

## Results

### Study on v7-merge `a170806`
Validation only: a private copy, 720 sub-runs, 8 levels x 6 Eb/N0 x 5 per class, onsets inside the sub-run. Frames with a full window after the onset, weak branch at an end of the array.

| Cue | AUC, fault vs shadowing | By link K band [-5,0) / [0,5) / [5,10) / [10,15) / [15,20] |
|---|---|---|
| C1 `coh_contrast` | 0.93 [0.91, 0.95] | 0.80 / 0.95 / 0.96 / 0.95 / 0.97 |
| C2 `los_contrast` | 0.81 [0.76, 0.85] | 0.62 / 0.77 / 0.85 / 0.87 / 0.96 |
| C2 `los_coh` | 0.88 | n/a |
| Magnitude K of the gains (base) | 0.66 | n/a |

### On this branch (D85 fusion with its onset and obs cues)
Validation-style set: 720 sub-runs, seeds 7 200 001 and up, all levels and Eb/N0, the D85 onsets. Sub-run-grouped 5-fold CV as select_fusion.m (stream 61), N chosen by CV macro-F1 (12 for both). Recall with a sub-run bootstrap interval.

| | D85 fusion | + coherence + line-of-sight lag (adopted) | Paired gain |
|---|---|---|---|
| Antenna fault, every frame | 69.3 [64.9, 73.6] | **79.4 [75.5, 83.0]** | **+10.2 [+7.7, +13.0]** |
| Airframe shadowing, every frame | 69.6 [65.9, 73.2] | **73.2 [69.9, 76.7]** | **+3.7 [+2.0, +5.3]** |
| Antenna fault, steady (9+ cycles), end antenna | 65.6 [58.5, 72.4] | 76.7 [70.8, 82.8] | +11.1 [+6.5, +15.7] |
| Airframe shadowing, steady, end antenna | 80.8 [76.5, 85.1] | 86.2 [82.3, 89.8] | +5.3 [+3.0, +8.0] |
| Clean sub-runs read as a lost branch | 6.48% | 6.35% | |
| CV macro-F1 | 78.2% | 82.8% | |

- **Each group alone:**
  - Coherence only: +6.3 fault, +2.6 shadowing (every frame).
  - Line-of-sight lag only: +9.6 fault, +2.8 shadowing.
- **"One branch lost"** is unchanged: 86.6% fault, 78.8% shadowing every frame. Shadowing's 76-79% is set by the roll-in frames, where the loss is still small: 75.6% inside the onset window, 91% after it.
- **Steady state, adopted:**
  - Shadowing by link K band: 68 / 81 / 90 / 93 / 96.
  - Fault by level: 5 dB 22, 8.7 dB 56, 12.4 dB 69, 16.1-31 dB 88-100.

### Limits (not fixed here)
- **Low link K (below 0 dB).** The line of sight holds at most about a quarter of a branch's power. The diffuse part correlated across antennas (rho 0.3-0.9) then gives the hidden branch about the coherence a faulty one has. An ideal-model check shows the practical statistics (coherence, normalised covariance, magnitude K) at AUC 0.44-0.56 at K -5 dB, rho at least 0.6, 10 frames. A genie that knows rho, K and the array's line-of-sight phases still reaches 0.79-0.99. An RF-only receiver has neither the attitude nor the GCS direction. Steady shadowing recall in this band is 68%.
- **Shallow fault (5-9 dB).** The faulty branch is the weakest only part of the time under fading, so the cue is often read on the wrong antenna. Steady recall at 5 dB is 22%.
- **Onset.** A coherence over one cycle is 1 by construction. The cues need 3-5 cycles (60-100 ms) after the step.

## Cost
- `lag_channels`: 0.68 ms per frame for 3 antennas and 10 lags, against about 50 ms per frame of the link simulation.
- The window columns: about 0.3 ms per cycle.
- Record: 27 values per frame (single precision) in the dataset, splits and pools.

## Tests
`code/tests/test_core.m`, full suite on this branch: 140 passed, 1 failed. The failure, `test_rate_reduce_chip_level`, is the base's known one (a flat channel and a jammer; unchanged code).

- **New `test_window_cues_branch_coherence`:**
  - fault against shadowing on synthetic records: `coh_contrast` and `los_contrast` separate them;
  - every column unchanged when the weak branch is scaled by 25 or 40 dB;
  - the cycles start at the step (`coh_cycles` 0.6 for a fault from cycle 5);
  - zeros without a record.
- **New `test_fusion_monitor_branch_columns`:** policy_monitor.m's fused probabilities equal fuse_classes.m's at every cycle of a run, with the branch records.
- **Extended `test_receiver_measurements`:** `F.bch` is 9 n_rx x frames and finite; its gains are `F.gain_ant`.

## Smoke chain
Scratch copy of this branch, one MATLAB process, fresh data:
- `run_stage('smoke', 'A0', 'A5', 'A6', 'B1', 'B2', 'B2F', 'B3')`: exit 0 in 20.9 min.
- The validation and test splits carry `bch` (924 x 27), every row finite.
- B2F fitted the fusion on 85 columns, as expected (N = 8).
- The new columns' fitted means on validation: `coh_weak` 0.88, `coh_contrast` -0.03, `los_contrast` -2.3 dB.

Smoke numbers are not results.

## Open risks
- The gains above are from a validation-style set of 720 sub-runs. The detector's own probabilities enter the full chain, and its validation numbers come with the rebuilt dataset (A5 onward).
- `policy_monitor.m` now keeps at least 10 cycles when a fusion is loaded. The fusion window itself (N) is unchanged.
- At four antennas (profile 3), the columns average over the other antennas' pairs. They were not evaluated there.
