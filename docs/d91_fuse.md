# d91: a lost branch's evidence in the fusion (branch d91-fuse)

Branch `d91-fuse` from `d90-loop` (`2cbe559`). It implements option A of Adi's decision of
2026-10-18: a fusion-only "branch evidence" revision for antenna_fault, selected with nested
cross-validation by sub-run on an enlarged fit set (validation plus the three test sets already
read), with KPI 1 read exactly once on a new fourth test set after the go/no-go (21.10 evening).
The analysis behind it is the weak-branch recommendation of 17.10 (sections 1-4).

**What was read.** Validation, the first test split, the second test set (B3n, `fresh`) and the
third test set (B3m, `fresh2`) of both profiles, as read-only copies. The fourth test set was
not read. Every number below is a fit-set number (out of fold, or nested), never a test reading.

## Summary

| Item | Status |
|---|---|
| Code behind `FUSION_REV` (off: bit-identical) | done, section 1; bit-identity shown, section 2 |
| Enlarged fit set (`FUSION_FIT = 'enlarged'`) | done, section 3; grids checked (M4 check) |
| Adoption rule, fixed before the M4 numbers | section 4 |
| M1-M4 on both profiles | detached run; numbers and verdicts in section 5 |
| Focused tests | 5 of 5 pass, section 6 |

## 1. The revision: four column groups, computed from `gain_ant` only

Every new column comes from the per-cycle antenna gains (`gain_ant`, the pools' `gant`), so a
later `rekey_pools` suffices; no pool field is added. The columns go last in the fusion's row
(`window_cues('extra')`), and `fuse_classes.m`, `policy_monitor.m`, `fused_class.m`,
`det_frames.m`, `eval_detector.m`, `detector_block.m` and `compare_architectures.m` build the same
row (test below). The fusion learns the cause from them; there is no hard step or ramp rule (the
onset latch's lesson, d87).

| Group | Columns | What it is | Sources |
|---|---|---|---|
| (a) iso | `iso_t iso_db iso_margin iso_agree` | d90's columns, unchanged: per antenna the best split of its offset to the others' median, the largest t over all antennas, not the antenna weakest by its mean | Xie et al. 2021, Sec. III-I (detection-isolation) |
| (b) held | `br_w br_db br_len br_nref` | `branch_ref.m`: each antenna's power over the others' mean (linear), its reference the linear mean of the last 10 reference cycles, a one-sided window-limited CUSUM of a drop below it, the reference held while a drop is under test | Xie et al. 2021, eq. 2-3 (CUSUM) and Sec. II-D1 (b = abs(log alpha)); Xie, Moustakides & Xie 2022, eq. 6-7 (WL-CUSUM); Lee 1985, Sec. IV (linear local mean; Rayleigh as the worst case); `drop_ref.m` (hold and release) |
| (c) glr | `gl_llr gl_db gl_age gl_margin gl_phi` | per antenna the exponential GLR of a drop of its power over the others' mean at an unknown cycle of the window, n log m - n1 log m1 - n2 log m2, one-sided, times the share of independent cycles phi; the largest over the antennas | Xie et al. 2021, eq. 20 (GLR-CUSUM, one-parameter exponential families); Xie, Moustakides & Xie 2022, eq. 9 (window-limited GLR); Lee 1985, Sec. IV (correlated samples count less) |
| (d) post | `ps_k_weak ps_k_strong ps_k_contrast ps_sd_weak ps_sd_contrast ps_n` | the K and spread cues over the cycles after that antenna's split (at least 3, else the whole window); with no drop, the weakest antenna over the whole window, which equals the base columns | Aoki & Honda 2025, eq. 2 (the moment K assumes a stationary sample) |

**Fixed settings (not tuned):** 10 reference cycles (the monitor's reference,
`policy_monitor.m`); the first 3 cycles join the reference as they come (the latch's "at least 3
earlier cycles", `onset_shape.m`); the drop's size estimated over the last `C.cusum_win` = 3
cycles and held in the antenna fault's levels of the envelope, 5-31 dB (`decision_config.m`, as
`drop_cusum.m` holds the path loss's); alpha = 1.87%, the deployed fusion's share of clean frames
read as a lost branch on profile 1's validation (used for both profiles; it only decides whether
an excursion's cycles join the reference).

**Effective sample count for hover.** phi = (1 - rho) / (1 + rho), rho the median over the
antennas of the lag-1 correlation of each antenna's power over the window (at least 0). It scales
the GLR and each CUSUM step.

**Sources that are missing from the library (said plainly):**
- The variance of the log of an exponential variable (pi^2/6, so averaging in dB is about 61%
  efficient under Rayleigh). It is not cited and nothing relies on it; the linear-power GLR is used
  because the exponential likelihood is the model of Xie et al. 2021, eq. 20, not for an
  efficiency claim.
- The first-order autoregressive form of phi. No time-series text is in the library. Lee 1985,
  Sec. IV supports only that correlated cycles carry fewer independent samples.
- Hastie, Tibshirani & Friedman (one-standard-error rule), already flagged in d90.

**Selection code.** `select_fusion.m` (FUSION_REV): the candidates are cfar (d90) and the branch
variants iso, glr, held, post and all four together ("branch evidence"), each against the fusion
without them, out of fold by sub-run, paired by a bootstrap over sub-runs (`fusion_adopt.m`).
With `FUSION_FIT = 'enlarged'` as well, the columns are chosen and the fusion is fitted on the
enlarged fit set (`fit_sets.m`); N and lambda stay chosen on validation (d90 found N 12 on both
profiles), and `val_probs_oof` keeps its validation frames for eval_detector's KPI 1 threshold.

## 2. Bit-identity with the switch off

The d90 harness (scratchpad `d91_bitid/bitid.m`), with `2cbe559` as the old code and this branch
as the new, B2F and B3 on the same smoke data:
- `fusion.mat`: the same 10 variables, every one identical (`isequaln`);
- `detector_predictions.mat`: identical;
- `eval_detector_metrics.mat`: identical except the `generated` time stamp;
- the closed-loop monitor's fused probabilities over 63 validation cycles: largest difference 0.

The revised selection (FUSION_REV) also ran end to end on the same smoke data (`d91_bitid/rev.m`);
its choices on smoke data are not results.

## 3. The enlarged fit set

Per profile: validation 20,328 frames (968 sub-runs), first test split 20,328 (968), second test
set 83,664 (3,984), third test set 83,664 (3,984); 207,984 frames and 9,904 sub-runs in all.
Run keys are offset by set (k x 1e7), so no two sets share a sub-run, and the 5 folds are drawn
over sub-runs (stream seed 9101), never splitting one.

Checks:
- **M4 check (grids).** Every read set has validation's classes, level grid per class and Eb/N0
  grid (0-15 dB), K over -5 to 20 dB in five near-equal bands, speeds 0.1-161 km/h (section 5
  per profile). The second and third sets hold 4 sub-runs per cell where validation and the first
  split hold 1 (the datasets' design).
- **The extracted copies are the stored readings.** The deployed fusion re-applied to each read
  set reproduces its stored reading exactly (monitor and fused class, 100.000% of frames, both
  profiles).
- **`fit_sets.m` against the copies (P1).** Runs, positions, labels, gains, branch records, idle
  records and K equal; the detector's probabilities agree to 3e-8 (the copies store single
  precision).

Consequence: once the fusion is fitted on this set, the B3, B3n and B3m readings are in-sample.
KPI 1 is then read on the fourth test set only.

## 4. Adoption rule (fixed before the M4 numbers were read)

The rule was coded in `fusion_adopt.m` ('branch') before any fit-set reading existed. The
measurement script was first run on every 20th sub-run as a code check. Those numbers are not
used, and the rule was not changed after it.

A branch variant (or the selection procedure, nested) is adopted for a profile only if, against
the deployed fusion's design refitted on the same folds (N 12, lambda 1e-3, the deployed target
rule), in points with 95% intervals of a paired bootstrap over sub-runs (1,000 resamples):
1. antenna_fault F1 gains: lower bound > 0;
2. macro-F1 gains, over every frame and above the KPI 1 threshold: both lower bounds > 0;
3. airframe_shadowing F1 loses nothing beyond its interval: upper bound >= 0;
4. no collapse at K <= 0 dB: the F1 of antenna_fault and of airframe_shadowing over the flights
   with K <= 0 dB, each upper bound >= 0;
5. clean false alarms do not rise beyond their interval: the clean frames read as any threat and
   as a lost branch, both lower bounds <= 0.

**Procedure.** (i) Out of fold on the whole fit set, each variant against the base; the rule
picks, of the variants it adopts, the one with the largest gain over every frame. (ii) Nested
cross-validation of that procedure: each outer fold applies the rule to inner out-of-fold
readings of its four training folds (500 resamples), fits the chosen variant on them and predicts
the held-out fold. **Verdict per profile:** adopt the variant of (i) only if the nested reading of
(ii) also passes the rule; otherwise the deployed fusion stays.

## 5. Measurements (M1-M4)

The script is `m_all.m` in the scratchpad folder `d91_fuse` (with `extract_sets.m`, the logs
`m_p1.txt`, `m_p3.txt` and the checkpoints). One MATLAB at a time, single thread, profile 1 then
profile 3, started 18.10 05:48.

- **M1** splits the errors on the fit set, with the base reading (the deployed design out of
  fold). For shadowing, the real loss of the hidden antenna at every frame is recomputed from the
  stored seed with `flight_draws.m`, `turn_attitude.m` and `shadow_frame.m`. The draws must equal
  the stored ones, and the hidden antenna must equal the label. The tables are by loss, age and K.
  For the antenna fault the tables are by level x K, level x age, level x speed, and K x age at
  5-8.7 dB.
- **M2** gives the share of clean turning flights whose own attitude would hide an antenna at the
  level matching their bank, and how often those frames are read as shadowing.
- **M3** is the shadowing bound with cross-antenna coherence. Bagged trees (100) are trained out of
  fold on shadowing frames against clean frames, set at the base reading's clean budget for
  shadowing. They use the branch-gain columns, then the same plus the coherence and line-of-sight
  columns (`coh_*`, `los_*`). The shadowing recall of each is set against the fusion's, overall,
  at onset age 0-2, at K < 0 and 0-5 dB, and at a real loss of 5-6 and >= 8 dB, with sub-run
  bootstrap intervals. A shadowing change is justified only if the coherence trees beat the fusion
  with an interval above 0.
- **M4** reports each variant out of fold, with per-set fault-F1 point gains and fault recall by
  stratum, then the nested reading and the verdict.

<!-- RESULTS P1 -->
Profile 1: pending (the detached run writes it here).
<!-- END P1 -->

<!-- RESULTS P3 -->
Profile 3: pending (the detached run writes it here).
<!-- END P3 -->

## 6. Tests

Focused tests only (the full suite and the smoke are not run here: the smoke opens a parallel
pool). All pass:
- `test_branch_evidence_cues` (new) checks:
  - the GLR follows the antenna that steps, not the one weakest by its mean (exact value);
  - the post-split cues use the cycles after that split;
  - with no drop, they equal the base columns;
  - the held reference keeps the level before a 10 dB step and takes back a one-cycle dip;
  - a dip's cycle joins no other antenna's reference;
  - the per-cycle state equals the batch run;
  - phi is 1 under 4 cycles and small for a slow fade;
  - `fuse_classes` row = windows + extra, and the held columns = `branch_ref('run')`;
  - the monitor's fused probabilities equal `fuse_classes` cycle by cycle with every column;
  - a fusion without the held columns keeps no state.
- `test_fusion_adopt_rules` (new) checks each condition of the rule, the choice and the
  combination with cfar, and the paired bootstrap's point values against direct counts.
- `test_window_cues_extra`, `test_fusion_target_age` (d90) pass unchanged.
- `test_seed_streams_disjoint` additionally checks the selection's resampling streams (61, 62,
  9101, 9102). No simulation seed was added.

## 7. If a profile adopts: what deployment takes

1. `run_stage.m` `run_one`: `FUSION_REV = true; FUSION_FIT = 'enlarged';` before `select_fusion`.
   B2F then reads the three test sets by HDF5 (the images in blocks). It costs about as much as
   the out-of-fold part of section 5: hours, not the 6-10 min of today's B2F.
2. Rerun B3, B3a, B4 and B4s. They are in-sample on the read sets and are kept only as
   descriptions.
3. Read KPI 1 once, on the fourth test set (FRESH_SET = 3, the d91-set4 track).
4. `rekey_pools` (the columns read only `gant`), then the closed loop from C1d on.
5. Profile 3 before its C1p, profile 1 after its run, profile 2 from its start, as the
   recommendation lays out.
