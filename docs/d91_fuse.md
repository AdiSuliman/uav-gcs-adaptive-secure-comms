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
| M1-M4 on both profiles | done: adopt 'branch evidence' on both profiles, section 5 |
| phi against phi = 1 | declared before it ran (section 8, commit 5abf87d); queued, results in section 12 |
| Deployment tied to the measured pick | `fusion_pick.m` (latch off, as measured), `select_fusion.m`, section 9 |
| Closed-loop wrap check | queued on the d90 smoke pools, section 10 |
| Focused tests | 5 of 5 pass (section 6); the new and changed ones queued |

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
| (b) held | `br_w br_db br_len br_nref` | `branch_ref.m`: each antenna's power over the others' mean (linear), its reference the linear mean of the last 10 reference cycles, a one-sided window-limited CUSUM of a drop below it, the reference held while a drop is under test | Xie et al. 2021, eq. 2-3 (CUSUM) and Sec. II-D1 (b = abs(log alpha), asymptotic, alpha a false-alarm rate; here a frame share, see below); Xie, Moustakides & Xie 2022, eq. 6-7 (WL-CUSUM); Lee 1985, Sec. IV, eq. 31 (the local mean; 36 uncorrelated samples for +-1 dB at 90%); the cap W <= 2 b has no source; `drop_ref.m` (hold and release) |
| (c) glr | `gl_llr gl_db gl_age gl_margin gl_phi` | per antenna the exponential GLR of a drop of its power over the others' mean at an unknown cycle of the window, n log m - n1 log m1 - n2 log m2, one-sided, times the share of independent cycles phi; the largest over the antennas | an exponential change-point GLR with the means before and after the change both unknown (estimated in the window), adapted from Xie et al. 2021, eq. 20 and Xie, Moustakides & Xie 2022, eq. 9, which assume a known pre-change density; phi has no library source (Lee 1985, Sec. IV, says only that correlated samples count less) |
| (d) post | `ps_k_weak ps_k_strong ps_k_contrast ps_sd_weak ps_sd_contrast ps_n` | the K and spread cues over the cycles after that antenna's split (at least 3, else the whole window); with no drop, the weakest antenna over the whole window, which equals the base columns | Aoki & Honda 2025, eq. 2 (the moment K assumes a stationary sample) and Sec. 3.4 (with few samples its error can be large; here as few as 3 cycles) |

**Fixed settings (not tuned):** 10 reference cycles (the monitor's reference,
`policy_monitor.m`); the first 3 cycles join the reference as they come (the latch's "at least 3
earlier cycles", `onset_shape.m`); the drop's size estimated over the last `C.cusum_win` = 3
cycles and held in the antenna fault's levels of the envelope, 5-31 dB (`decision_config.m`, as
`drop_cusum.m` holds the path loss's); alpha = 1.87%, the deployed fusion's share of clean frames
read as a lost branch on profile 1's validation (117 of 6,270 frames; used for both profiles; it
only decides whether an excursion's cycles join the reference).

**What the sources support, and what they do not.**
- b = |log alpha| is the threshold Xie et al. 2021, Sec. II-D1 give asymptotically (alpha -> 0)
  for a false-alarm rate alpha = 1/ARL (eq. 6-7). Here alpha is a frame share (clean frames read
  as a lost branch), used as the per-cycle false-alarm rate. That is an analogy, not the source's
  quantity.
- The cap W <= 2 b has no source.
- The GLR of group (c) estimates the mean before the change in the window as well as the mean
  after it. Xie et al. 2021, eq. 20 and Xie, Moustakides & Xie 2022, eq. 9 assume a known
  pre-change density, so the form here is adapted from them, not taken from them.
- Lee 1985, Sec. IV, eq. 31 averages the envelope r and needs at least 36 uncorrelated samples
  for the local mean to be within +-1 dB at 90%. The held reference averages NR = 10 cycles of
  linear power. For 10 independent exponential powers the 90% interval of their mean is
  -2.7/+2.0 dB about the true mean (chi-square with 20 degrees of freedom; computed, not a
  library number), and wider when the cycles are correlated (hover).
- The exponential power (Rayleigh fading) is the likelihood model. It is an assumption, not a
  sourced worst case.

**Effective sample count for hover.** phi = (1 - rho) / (1 + rho), rho the median over the
antennas of the lag-1 correlation of each antenna's power over the window (at least 0). It scales
the GLR and each CUSUM step. It has no library source and was not compared with phi = 1 in
section 5; the comparison is declared in section 8.

**Sources that are missing from the library (said plainly):**
- The variance of the log of an exponential variable (pi^2/6, so averaging in dB is about 61%
  efficient under Rayleigh). It is not cited and nothing relies on it; the linear-power GLR is used
  because the exponential likelihood is the model of Xie et al. 2021, eq. 20, not for an
  efficiency claim.
- The first-order autoregressive form of phi. No time-series text is in the library. Lee 1985,
  Sec. IV supports only that correlated cycles carry fewer independent samples. rho is also
  computed on the raw power about the window mean, so a step inside the window raises it.
  Section 8 compares phi with phi = 1.
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
  per profile). Sub-runs per (class, level, Eb/N0) cell, min/median/max over 486 cells: 1/1/8 in
  validation and the first split, 4/6/32 in the second and third sets (`m_p1.log`, `m_p3.log`;
  the datasets' design).
- **The extracted copies are the stored readings.** The deployed fusion re-applied to each read
  set reproduces its stored reading exactly (monitor and fused class, 100.000% of frames, both
  profiles).
- **`fit_sets.m` against the copies (P1).** Runs, positions, labels, gains, branch records, idle
  records and K were equal, and the detector's probabilities agreed to 3e-8 (the copies store
  single precision). That run (`check_fit_sets.m`) printed to the console only; no log of it was
  saved, so the figure is not cited as evidence. It reads profile 1's live worktree, so it is
  rerun with a log only when profile 1 runs no MATLAB. The extracts themselves are checked by
  the line above (`extract_p1.log`, `extract_p3.log`).

Consequence: once the fusion is fitted on this set, the B3, B3n and B3m readings are in-sample.
KPI 1 is then read on the fourth test set only.

## 4. Adoption rule (fixed before the M4 numbers were read)

The rule was coded in `fusion_adopt.m` ('branch') before any fit-set reading existed. Only file
times prove the order before the first commit. The timeline (18.10, local time; files in the
scratchpad folder `d91_fuse` unless a path is given):

| Time | Event |
|---|---|
| 05:15:41 | `code/detection/fusion_adopt.m` last written (the rule; unchanged since: sha256 of the file as run `159dd59cc51fcfaebb1de5e0c1f6a3e2e5a6fd043dbfef90b1df7a5156edd6f3`, git blob `f31285a3`) |
| 05:38:53 | `m_all.m` last written (by `ed3.py`; unchanged since: sha256 `b0fa6dc8cf171e8abf061c3361c0f02fc8113fccdb71dbd258f2b510117fe398`, git blob `d36747ff`) |
| 05:39:10 | the code check starts: `m_all('p1', true)`, every 20th sub-run |
| 05:39:16 | `branch_ref.m` header comment edited (`ed4.py`, comment only) while the check ran its windows |
| 05:47:47 | the code check ends: `quick_p1.log` holds the full M4 table, the nested picks and the line **`VERDICT p1: adopt branch evidence`** |
| 05:48:26 | the full measurement starts (`m_p1.log` header; `job_m.sh` 05:48:15) |
| 05:48:34 | commit `ad3cde8`: the code, the rule included, as the measurement loaded it |
| 05:51:15 | commit `21d1a62`: this note with section 4 |

So the code check reached a verdict before the rule was committed, but after both the rule
(05:15:41) and the measurement script (05:38:53) were last written. The rule's file and the
script are byte-identical to what ran (the hashes above). The check's numbers are not used.
Verbatim copies: `docs/d91_fuse_m_all.m.txt` and `docs/d91_fuse_quick_p1.log.txt` (sha256
`3cda6fc2690c570e88c787d35e95b348f9989a7476512d9881c488e90b814a09`); `m_p1_quick.mat` stays in the scratchpad folder (sha256
`e55c8e3f85325c5a07afa7e039a1295246ce1a525b56f4c7eacbbc1cd500a375`).

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
### Profile 1

**VERDICT p1: adopt branch evidence**

The run wrote the log below; the rule of section 4 decided the verdict mechanically. Interpretation follows at review.

```
===== d91 measurements, p1, 18-Oct-2026 05:48:26: N 12, lambda 1e-03, latch 0, 3 antennas =====
val     20328 frames,  968 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.8), speed 0.4..160.9 km/h, sub-runs per (class, level, Eb/N0) cell [1 1 8 486]
test    20328 frames,  968 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.6), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [1 1 8 486]
fresh   83664 frames, 3984 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.4), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [4 6 32 486]
fresh2  83664 frames, 3984 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.1), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [4 6 32 486]
  test: same class/level/Eb/N0 grid as validation: 1
  fresh: same class/level/Eb/N0 grid as validation: 1
  fresh2: same class/level/Eb/N0 grid as validation: 1
  val    K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.206 0.189 0.191 0.213 0.201]
  test   K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.198 0.194 0.207 0.207 0.194]
  fresh  K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.201 0.193 0.201 0.208 0.197]
  fresh2 K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.204 0.204 0.207 0.19 0.196]
windows of 207984 frames: 3.0 min
branch-evidence columns: 2.0 min
validation rows of the fit set equal the validation windows: 1
extra columns: iso_t iso_db iso_margin iso_agree gl_llr gl_db gl_age gl_margin gl_phi ps_k_weak ps_k_strong ps_k_contrast ps_sd_weak ps_sd_contrast ps_n br_w br_db br_len br_nref
  OOF base: 12.5 min

M1 shadowing: 704 sub-runs recomputed, draws equal to the stored ones in 704; hidden antenna equal to the label in 14784 of 14784 frames
  labelled shadowing frames by real loss [5-6 6-7 7-8 8-10 >=10 dB]: n [3583 2110 1703 1968 1481], read as shadowing [70.6 83.1 88.6 91.8 92.3]%, as none [25.1 12.9 7.9 4.4 1.4]%
  by age [0-2 3-5 6-11 12+]: n [2108 2102 4123 2512], read as shadowing [58.8 80.3 90.2 92.3]%
  by K [<0 0-5 5-10 10-15 >=15 dB]: n [1989 2129 2153 2234 2340], read as shadowing [62.3 73.6 87.4 91.3 95.6]%
    K [-Inf 0]: by real loss n [697 401 337 321 233], read [48.4 54.9 72.1 81.3 76.4]%
    K [0 5]: by real loss n [749 353 305 414 308], read [56.7 76.2 83.6 83.6 88]%
    K [5 10]: by real loss n [693 436 339 382 303], read [76.9 87.8 91.7 95.8 95.4]%
    K [10 15]: by real loss n [722 454 366 401 291], read [80.7 94.9 96.7 96.5 97.9]%
    K [15 Inf]: by real loss n [722 466 356 450 346], read [90 96.8 97.2 99.3 99.4]%
  none frames of shadowing sub-runs by real loss [0-1 1-2 2-3 3-4 4-5 dB]: n [238 164 380 958 2199], read as shadowing [10.5 0.6 1.1 2.1 3.5]%
  clean sub-runs: read as shadowing 4.14% of 10080 frames

M1 antenna fault: 10870 labelled frames, recall 80.6%, read as none 15.0%
  level x K [<0 0-5 5-10 10-15 >=15 dB]: recall % (frames; sub-runs)
      5.0 dB:  17.9 (179; 12)   12.9 (364; 24)    7.9 (254; 16)   20.1 (204; 13)   41.0 (344; 23)  
      8.7 dB:  33.0 (215; 14)   44.4 (284; 19)   60.9 (284; 18)   66.4 (268; 17)   72.7 (293; 20)  
     12.4 dB:  75.5 (351; 22)   77.1 (236; 15)   87.8 (188; 12)   90.2 (307; 21)   93.2 (263; 18)  
     16.1 dB:  82.8 (250; 16)   90.5 (285; 18)   96.8 (221; 15)   94.4 (356; 22)   98.5 (267; 17)  
     19.9 dB:  89.2 (369; 25)   95.3 (214; 14)   96.9 (356; 22)   98.9 (262; 16)   98.9 (179; 11)  
     23.6 dB:  88.2 (238; 15)   97.2 (352; 23)   99.0 (292; 19)   99.3 (275; 17)   99.1 (221; 14)  
     27.3 dB:  93.1 (189; 12)   98.4 (245; 16)   99.7 (334; 22)  100.0 (334; 21)   97.8 (273; 17)  
     31.0 dB:  95.0 (242; 17)   99.6 (241; 15)   98.8 (172; 13)   99.2 (386; 25)   99.6 (283; 18)  
  level x age [0-2 3-5 6-11 12+]:
      5.0 dB:   9.8 (264; 88)   25.8 (264; 88)   32.9 (520; 88)    5.4 (297; 69)  
      8.7 dB:  42.0 (264; 88)   76.1 (264; 88)   69.8 (517; 88)   29.4 (299; 72)  
     12.4 dB:  67.0 (264; 88)   94.3 (264; 88)   93.4 (517; 88)   75.0 (300; 65)  
     16.1 dB:  84.5 (264; 88)   97.0 (264; 88)   96.9 (522; 88)   89.1 (329; 74)  
     19.9 dB:  82.2 (264; 88)   97.3 (264; 88)   98.8 (520; 88)   98.2 (332; 71)  
     23.6 dB:  91.3 (264; 88)   98.5 (264; 88)   99.0 (520; 88)   96.1 (330; 72)  
     27.3 dB:  93.2 (264; 88)   98.9 (264; 88)   99.8 (521; 88)   99.4 (326; 76)  
     31.0 dB:  96.6 (264; 88)   98.5 (264; 88)   98.8 (514; 88)  100.0 (282; 67)  
  level x speed [0-23 23-60 60-120 >=120 km/h]:
      5.0 dB:  20.3 (231; 15)   21.6 (194; 13)   19.4 (464; 30)   22.4 (456; 30)  
      8.7 dB:  45.3 (128; 8)   58.1 (353; 23)   58.3 (568; 38)   56.6 (295; 19)  
     12.4 dB:  77.9 (172; 12)   87.8 (263; 18)   84.3 (516; 32)   84.8 (394; 26)  
     16.1 dB:  91.6 (226; 13)   89.2 (223; 14)   93.9 (542; 36)   93.6 (388; 25)  
     19.9 dB:  93.0 (243; 16)   93.4 (346; 22)   98.1 (476; 29)   94.6 (315; 21)  
     23.6 dB:  98.8 (173; 12)   98.5 (264; 17)   94.0 (531; 33)   98.3 (410; 26)  
     27.3 dB:  96.0 (174; 12)   99.2 (393; 24)   98.0 (560; 35)   98.8 (248; 17)  
     31.0 dB:  98.9 (190; 12)   99.0 (381; 25)   97.7 (442; 30)   99.0 (311; 21)  
  K x age at 5-8.7 dB:
    K [-Inf 0]:  21.8 (78; 26)   34.6 (78; 26)   34.0 (153; 26)    8.2 (85; 21)  
    K [0 5]:  16.3 (129; 43)   34.1 (129; 43)   33.5 (251; 43)   17.3 (139; 31)  
    K [5 10]:  22.5 (102; 34)   48.0 (102; 34)   47.8 (203; 34)   18.3 (131; 31)  
    K [10 15]:  31.1 (90; 30)   63.3 (90; 30)   61.5 (179; 30)   21.2 (113; 27)  
    K [15 Inf]:  37.2 (129; 43)   71.3 (129; 43)   75.3 (251; 43)   19.5 (128; 31)  

M2: 480 clean sub-runs (draws equal to the stored ones in 480), 480 turning; 83 of them (17.3%) would hide an antenna at the level of their bank in 1490 of 10080 frames (14.8%); frames per level [99 428 1090 1358 1425 1464 1308 1117]
  read as shadowing: on those frames 3.4% (1490), on the other frames of turning clean flights 4.3% (8590)

M3 shadowing: 10845 shadowing and 10080 clean frames; the fusion's clean budget 4.14% (trees at 4.14% / 4.14%)
  all               n 10845: recall fusion 82.7%, gain-only trees 79.5%, with coherence 87.4%; coherence trees - fusion +4.7 [+3.9, +5.6], coherence - gain-only +7.9 [+6.6, +9.1] points
  age 0-2           n  2108: recall fusion 58.8%, gain-only trees 61.8%, with coherence 69.5%; coherence trees - fusion +10.8 [+8.9, +12.8], coherence - gain-only +7.7 [+6.0, +9.7] points
  K < 0 dB          n  1989: recall fusion 62.3%, gain-only trees 53.1%, with coherence 65.0%; coherence trees - fusion +2.7 [-0.3, +5.5], coherence - gain-only +11.9 [+8.1, +15.4] points
  K 0-5 dB          n  2129: recall fusion 73.6%, gain-only trees 64.4%, with coherence 80.9%; coherence trees - fusion +7.4 [+5.2, +9.6], coherence - gain-only +16.5 [+13.2, +19.9] points
  real loss 5-6 dB  n  3583: recall fusion 70.6%, gain-only trees 67.1%, with coherence 77.1%; coherence trees - fusion +6.6 [+5.0, +8.2], coherence - gain-only +10.0 [+8.1, +12.1] points
  real loss >= 8 dB n  3449: recall fusion 92.0%, gain-only trees 91.6%, with coherence 96.0%; coherence trees - fusion +4.0 [+2.7, +5.3], coherence - gain-only +4.4 [+3.0, +5.8] points
  OOF iso: 12.2 min
  OOF glr: 24.7 min
  OOF held: 36.5 min
  OOF post: 48.5 min
  OOF branch evidence: 60.4 min

M4 out of fold over 207984 frames (9904 sub-runs), KPI 1 threshold of the base reading 0 dB
  base: macro-F1 all 94.26%, above 94.36%; F1 fault 85.80%, shadowing 84.78%; clean as a threat 2.79%, as a lost branch 1.70%
  iso              all +0.22 [+0.16, +0.27], above +0.22 [+0.16, +0.27], clean as threat -0.06 [-0.13, +0.00], as lost branch -0.06 [-0.12, +0.00], F1 fault +1.62 [+1.21, +2.07], shadowing +0.25 [+0.06, +0.45], K<=0 fault +1.14 [+0.22, +2.18], shadowing -0.11 [-0.92, +0.57] -> rule yes
  glr              all +0.20 [+0.14, +0.26], above +0.20 [+0.15, +0.26], clean as threat -0.07 [-0.16, +0.02], as lost branch -0.04 [-0.11, +0.03], F1 fault +1.47 [+1.11, +1.89], shadowing +0.10 [-0.13, +0.33], K<=0 fault +2.08 [+0.88, +3.35], shadowing -0.11 [-0.93, +0.78] -> rule yes
  held             all +0.44 [+0.33, +0.55], above +0.44 [+0.33, +0.55], clean as threat -0.15 [-0.27, -0.02], as lost branch -0.15 [-0.26, -0.02], F1 fault +3.75 [+2.79, +4.67], shadowing +0.14 [-0.24, +0.55], K<=0 fault +2.13 [-0.29, +4.49], shadowing -0.52 [-2.25, +1.09] -> rule yes
  post             all +0.03 [-0.01, +0.07], above +0.03 [-0.01, +0.07], clean as threat -0.05 [-0.12, +0.01], as lost branch -0.04 [-0.09, +0.01], F1 fault +0.15 [-0.04, +0.35], shadowing +0.03 [-0.24, +0.29], K<=0 fault +0.16 [-0.54, +0.87], shadowing -0.32 [-1.37, +0.77] -> rule no
  branch evidence  all +0.64 [+0.52, +0.76], above +0.64 [+0.52, +0.77], clean as threat -0.29 [-0.43, -0.15], as lost branch -0.23 [-0.36, -0.10], F1 fault +5.14 [+4.16, +6.20], shadowing +0.39 [-0.02, +0.80], K<=0 fault +3.38 [+0.78, +6.07], shadowing -0.54 [-2.17, +0.96] -> rule yes
  set val    fault F1 base 85.74%: iso +0.64, glr +1.02, held +5.40, post +0.34, branch evidence +5.65
  set test   fault F1 base 85.73%: iso +2.06, glr +1.58, held +3.47, post -0.19, branch evidence +4.73
  set fresh  fault F1 base 87.24%: iso +1.65, glr +1.30, held +3.04, post +0.10, branch evidence +4.48
  set fresh2 fault F1 base 84.35%: iso +1.72, glr +1.73, held +4.17, post +0.24, branch evidence +5.80
  fault recall 5 dB               ( 1345 frames): base 20.9%, iso 29.1%, glr 25.1%, held 44.2%, post 20.6%, branch evidence 52.0%
  fault recall 8.7 dB             ( 1344 frames): base 56.6%, iso 60.9%, glr 62.5%, held 77.6%, post 57.3%, branch evidence 79.8%
  fault recall K >= 10 dB         ( 4515 frames): base 86.1%, iso 89.9%, glr 88.0%, held 93.3%, post 86.6%, branch evidence 96.3%
  fault recall K < 0 dB           ( 2033 frames): base 74.8%, iso 75.4%, glr 77.1%, held 79.3%, post 75.0%, branch evidence 79.8%
  fault recall age >= 12          ( 2495 frames): base 75.0%, iso 74.9%, glr 76.1%, held 90.9%, post 75.4%, branch evidence 90.7%
  fault recall age 0-2            ( 2112 frames): base 70.8%, iso 77.1%, glr 73.7%, held 71.3%, post 71.4%, branch evidence 76.6%
  fault recall hover (< 23 km/h)  ( 1537 frames): base 77.9%, iso 80.4%, glr 79.2%, held 84.5%, post 78.1%, branch evidence 87.5%
  nested outer fold 1: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (48.2 min)
  nested outer fold 2: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (93.4 min)
  nested outer fold 3: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (139.5 min)
  nested outer fold 4: inner rule iso 1, glr 1, held 1, post 1, branch evidence 1 -> branch evidence (186.9 min)
  nested outer fold 5: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (234.6 min)
  NESTED selection against the base: all +0.64 [+0.52, +0.76], above +0.64 [+0.52, +0.77], clean as threat -0.29 [-0.43, -0.15], as lost branch -0.23 [-0.36, -0.10], F1 fault +5.14 [+4.16, +6.20], shadowing +0.39 [-0.02, +0.80], K<=0 fault +3.38 [+0.78, +6.07], shadowing -0.54 [-2.17, +0.96] -> rule yes
  on the whole fit set the rule picks: branch evidence; nested picks per outer fold: branch evidence, branch evidence, branch evidence, branch evidence, branch evidence
  VERDICT p1: adopt branch evidence
##### m_all p1 done 18-Oct-2026 11:02:35
```
<!-- END P1 -->

<!-- RESULTS P3 -->
### Profile 3

**VERDICT p3: adopt branch evidence**

The run wrote the log below; the rule of section 4 decided the verdict mechanically. Interpretation follows at review.

```
===== d91 measurements, p3, 18-Oct-2026 11:02:53: N 12, lambda 1e-03, latch 0, 4 antennas =====
val     20328 frames,  968 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.8), speed 0.4..160.9 km/h, sub-runs per (class, level, Eb/N0) cell [1 1 8 486]
test    20328 frames,  968 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.6), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [1 1 8 486]
fresh   83664 frames, 3984 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.4), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [4 6 32 486]
fresh2  83664 frames, 3984 sub-runs, classes of sub-runs [1 2 3 4 5 6 7 8 9 10 11], Eb/N0 [0 3 6 9 12 15] dB, K -5.0..20.0 dB (median 7.1), speed 0.1..161.0 km/h, sub-runs per (class, level, Eb/N0) cell [4 6 32 486]
  test: same class/level/Eb/N0 grid as validation: 1
  fresh: same class/level/Eb/N0 grid as validation: 1
  fresh2: same class/level/Eb/N0 grid as validation: 1
  val    K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.206 0.189 0.191 0.213 0.201]
  test   K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.198 0.194 0.207 0.207 0.194]
  fresh  K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.201 0.193 0.201 0.208 0.197]
  fresh2 K bands of the sub-runs (<0, 0-5, 5-10, 10-15, >=15 dB): [0.204 0.204 0.207 0.19 0.196]
windows of 207984 frames: 3.3 min
branch-evidence columns: 3.0 min
validation rows of the fit set equal the validation windows: 1
extra columns: iso_t iso_db iso_margin iso_agree gl_llr gl_db gl_age gl_margin gl_phi ps_k_weak ps_k_strong ps_k_contrast ps_sd_weak ps_sd_contrast ps_n br_w br_db br_len br_nref
  OOF base: 12.8 min

M1 shadowing: 704 sub-runs recomputed, draws equal to the stored ones in 704; hidden antenna equal to the label in 14784 of 14784 frames
  labelled shadowing frames by real loss [5-6 6-7 7-8 8-10 >=10 dB]: n [3583 2110 1703 1968 1481], read as shadowing [67 79.7 86.7 91.6 91.1]%, as none [28.4 16.1 9.6 5 2.7]%
  by age [0-2 3-5 6-11 12+]: n [2108 2102 4123 2512], read as shadowing [52.2 77 89.4 91.9]%
  by K [<0 0-5 5-10 10-15 >=15 dB]: n [1989 2129 2153 2234 2340], read as shadowing [59.8 72.7 84.5 89.3 92.3]%
    K [-Inf 0]: by real loss n [697 401 337 321 233], read [51.9 56.1 62.6 72 68.7]%
    K [0 5]: by real loss n [749 353 305 414 308], read [52.6 68.8 85.2 91.5 88]%
    K [5 10]: by real loss n [693 436 339 382 303], read [70.9 84.6 92 94.2 95]%
    K [10 15]: by real loss n [722 454 366 401 291], read [77 90.7 95.9 97 98.6]%
    K [15 Inf]: by real loss n [722 466 356 450 346], read [83 92.7 96.3 98.4 99.1]%
  none frames of shadowing sub-runs by real loss [0-1 1-2 2-3 3-4 4-5 dB]: n [238 164 380 958 2199], read as shadowing [8 0 1.1 2.5 3.5]%
  clean sub-runs: read as shadowing 4.31% of 10080 frames

M1 antenna fault: 10858 labelled frames, recall 80.0%, read as none 16.0%
  level x K [<0 0-5 5-10 10-15 >=15 dB]: recall % (frames; sub-runs)
      5.0 dB:  11.4 (175; 12)    8.3 (360; 24)    5.4 (240; 16)   22.5 (191; 13)   26.9 (353; 23)  
      8.7 dB:  45.8 (216; 14)   39.0 (290; 19)   55.8 (294; 18)   71.7 (254; 17)   73.9 (314; 20)  
     12.4 dB:  70.6 (354; 22)   80.3 (239; 15)   79.6 (186; 12)   89.3 (318; 21)   93.5 (294; 18)  
     16.1 dB:  85.7 (238; 16)   91.4 (280; 18)   95.9 (218; 15)   95.0 (362; 22)   97.9 (242; 17)  
     19.9 dB:  93.5 (400; 25)   94.6 (223; 14)   96.1 (333; 22)   98.5 (269; 16)   98.8 (165; 11)  
     23.6 dB:  96.6 (236; 15)   98.0 (354; 23)   97.4 (271; 19)   98.9 (275; 17)   99.1 (220; 14)  
     27.3 dB:  94.8 (173; 12)   98.7 (232; 16)   98.6 (349; 22)   99.7 (302; 21)   97.5 (277; 17)  
     31.0 dB:  94.0 (250; 17)   99.2 (250; 15)   97.6 (206; 13)   98.5 (390; 25)   98.5 (265; 18)  
  level x age [0-2 3-5 6-11 12+]:
      5.0 dB:   7.6 (264; 88)   15.9 (264; 88)   22.4 (522; 88)    8.2 (269; 71)  
      8.7 dB:  38.3 (264; 88)   73.1 (264; 88)   72.8 (511; 88)   37.7 (329; 66)  
     12.4 dB:  59.8 (264; 88)   89.8 (264; 88)   92.1 (518; 88)   80.3 (345; 70)  
     16.1 dB:  79.5 (264; 88)   95.8 (264; 88)   96.9 (516; 88)   97.0 (296; 67)  
     19.9 dB:  84.1 (264; 88)   98.5 (264; 88)   99.2 (520; 88)   98.0 (342; 73)  
     23.6 dB:  90.5 (264; 88)  100.0 (264; 88)   99.6 (520; 88)  100.0 (308; 69)  
     27.3 dB:  92.4 (264; 88)   99.6 (264; 88)   99.4 (516; 88)   99.7 (289; 59)  
     31.0 dB:  94.3 (264; 88)   99.6 (264; 88)   99.0 (521; 88)   96.5 (312; 73)  
  level x speed [0-23 23-60 60-120 >=120 km/h]:
      5.0 dB:  13.9 (216; 15)   21.7 (203; 13)   13.7 (461; 30)   14.6 (439; 30)  
      8.7 dB:  70.9 (110; 8)   49.6 (357; 23)   59.3 (607; 38)   59.5 (294; 19)  
     12.4 dB:  86.0 (186; 12)   90.1 (284; 18)   79.2 (515; 32)   80.0 (406; 26)  
     16.1 dB:  96.1 (205; 13)   90.7 (214; 14)   95.0 (556; 36)   90.7 (365; 25)  
     19.9 dB:  94.7 (246; 16)   95.0 (361; 22)   97.4 (458; 29)   95.7 (325; 21)  
     23.6 dB:  98.3 (179; 12)   98.0 (248; 17)   98.5 (533; 33)   97.2 (396; 26)  
     27.3 dB:  96.5 (201; 12)   99.2 (353; 24)   97.8 (511; 35)   98.5 (268; 17)  
     31.0 dB:  97.5 (198; 12)   96.1 (384; 25)   97.6 (457; 30)   99.7 (322; 21)  
  K x age at 5-8.7 dB:
    K [-Inf 0]:  16.7 (78; 26)   35.9 (78; 26)   34.7 (150; 26)   30.6 (85; 19)  
    K [0 5]:  10.1 (129; 43)   24.8 (129; 43)   31.9 (254; 43)   12.3 (138; 35)  
    K [5 10]:  21.6 (102; 34)   35.3 (102; 34)   42.4 (198; 34)   26.5 (132; 26)  
    K [10 15]:  32.2 (90; 30)   65.6 (90; 30)   62.5 (176; 30)   30.3 (89; 23)  
    K [15 Inf]:  34.1 (129; 43)   62.0 (129; 43)   63.5 (255; 43)   26.6 (154; 34)  

M2: 480 clean sub-runs (draws equal to the stored ones in 480), 480 turning; 83 of them (17.3%) would hide an antenna at the level of their bank in 1490 of 10080 frames (14.8%); frames per level [99 428 1090 1358 1425 1464 1308 1117]
  read as shadowing: on those frames 5.0% (1490), on the other frames of turning clean flights 4.2% (8590)

M3 shadowing: 10845 shadowing and 10080 clean frames; the fusion's clean budget 4.31% (trees at 4.31% / 4.31%)
  all               n 10845: recall fusion 80.3%, gain-only trees 78.0%, with coherence 87.3%; coherence trees - fusion +7.0 [+6.1, +7.9], coherence - gain-only +9.3 [+8.0, +10.6] points
  age 0-2           n  2108: recall fusion 52.2%, gain-only trees 57.0%, with coherence 68.0%; coherence trees - fusion +15.7 [+13.4, +18.1], coherence - gain-only +11.0 [+8.9, +13.0] points
  K < 0 dB          n  1989: recall fusion 59.8%, gain-only trees 53.3%, with coherence 67.5%; coherence trees - fusion +7.7 [+4.6, +10.7], coherence - gain-only +14.1 [+10.9, +17.5] points
  K 0-5 dB          n  2129: recall fusion 72.7%, gain-only trees 62.3%, with coherence 81.1%; coherence trees - fusion +8.5 [+6.1, +10.8], coherence - gain-only +18.8 [+14.8, +22.5] points
  real loss 5-6 dB  n  3583: recall fusion 67.0%, gain-only trees 63.7%, with coherence 77.2%; coherence trees - fusion +10.1 [+8.4, +11.8], coherence - gain-only +13.5 [+11.1, +16.1] points
  real loss >= 8 dB n  3449: recall fusion 91.4%, gain-only trees 91.4%, with coherence 95.7%; coherence trees - fusion +4.3 [+3.1, +5.7], coherence - gain-only +4.3 [+2.9, +5.8] points
  OOF iso: 13.1 min
  OOF glr: 26.4 min
  OOF held: 39.4 min
  OOF post: 52.8 min
  OOF branch evidence: 67.2 min

M4 out of fold over 207984 frames (9904 sub-runs), KPI 1 threshold of the base reading 0 dB
  base: macro-F1 all 94.22%, above 94.31%; F1 fault 85.25%, shadowing 83.40%; clean as a threat 2.80%, as a lost branch 1.84%
  iso              all +0.19 [+0.14, +0.26], above +0.19 [+0.14, +0.25], clean as threat -0.06 [-0.14, +0.03], as lost branch -0.01 [-0.08, +0.07], F1 fault +1.71 [+1.22, +2.26], shadowing +0.06 [-0.13, +0.27], K<=0 fault +1.02 [-0.08, +2.05], shadowing -0.36 [-1.13, +0.45] -> rule yes
  glr              all +0.21 [+0.15, +0.28], above +0.21 [+0.15, +0.28], clean as threat -0.15 [-0.26, -0.04], as lost branch -0.12 [-0.21, -0.02], F1 fault +1.60 [+1.13, +2.09], shadowing +0.26 [-0.02, +0.54], K<=0 fault +2.02 [+0.58, +3.55], shadowing +1.03 [-0.07, +2.26] -> rule yes
  held             all +0.48 [+0.37, +0.59], above +0.49 [+0.39, +0.61], clean as threat -0.22 [-0.35, -0.08], as lost branch -0.18 [-0.31, -0.04], F1 fault +4.40 [+3.53, +5.35], shadowing +0.28 [-0.12, +0.71], K<=0 fault +2.72 [+0.72, +4.66], shadowing +1.37 [-0.16, +2.85] -> rule yes
  post             all +0.01 [-0.03, +0.06], above +0.01 [-0.03, +0.05], clean as threat -0.13 [-0.20, -0.06], as lost branch -0.09 [-0.16, -0.03], F1 fault +0.11 [-0.13, +0.34], shadowing -0.08 [-0.39, +0.22], K<=0 fault +0.06 [-0.86, +1.00], shadowing -0.61 [-1.87, +0.63] -> rule no
  branch evidence  all +0.61 [+0.49, +0.74], above +0.62 [+0.50, +0.74], clean as threat -0.32 [-0.47, -0.17], as lost branch -0.22 [-0.35, -0.07], F1 fault +5.19 [+4.23, +6.25], shadowing +0.30 [-0.13, +0.74], K<=0 fault +2.53 [+0.45, +4.69], shadowing +0.88 [-0.71, +2.58] -> rule yes
  set val    fault F1 base 84.74%: iso +0.40, glr +0.75, held +2.45, post +0.03, branch evidence +2.71
  set test   fault F1 base 85.58%: iso +1.14, glr +2.07, held +4.67, post +0.24, branch evidence +5.23
  set fresh  fault F1 base 85.70%: iso +2.10, glr +1.56, held +4.44, post +0.28, branch evidence +5.38
  set fresh2 fault F1 base 84.84%: iso +1.76, glr +1.74, held +4.74, post -0.07, branch evidence +5.54
  fault recall 5 dB               ( 1319 frames): base 15.2%, iso 26.4%, glr 19.6%, held 42.8%, post 15.9%, branch evidence 49.1%
  fault recall 8.7 dB             ( 1368 frames): base 57.7%, iso 60.7%, glr 62.6%, held 78.9%, post 58.6%, branch evidence 80.8%
  fault recall K >= 10 dB         ( 4491 frames): base 85.2%, iso 89.7%, glr 87.2%, held 93.3%, post 85.6%, branch evidence 95.9%
  fault recall K < 0 dB           ( 2042 frames): base 77.1%, iso 77.7%, glr 79.3%, held 80.5%, post 76.8%, branch evidence 80.0%
  fault recall age >= 12          ( 2490 frames): base 78.0%, iso 77.3%, glr 77.4%, held 93.6%, post 78.2%, branch evidence 92.8%
  fault recall age 0-2            ( 2112 frames): base 68.3%, iso 75.0%, glr 73.1%, held 70.7%, post 68.8%, branch evidence 75.2%
  fault recall hover (< 23 km/h)  ( 1541 frames): base 81.8%, iso 84.2%, glr 83.1%, held 87.4%, post 81.2%, branch evidence 89.7%
  nested outer fold 1: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (44.8 min)
  nested outer fold 2: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (88.3 min)
  nested outer fold 3: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (136.9 min)
  nested outer fold 4: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (185.0 min)
  nested outer fold 5: inner rule iso 1, glr 1, held 1, post 0, branch evidence 1 -> branch evidence (233.3 min)
  NESTED selection against the base: all +0.61 [+0.49, +0.74], above +0.62 [+0.50, +0.74], clean as threat -0.32 [-0.47, -0.17], as lost branch -0.22 [-0.35, -0.07], F1 fault +5.19 [+4.23, +6.25], shadowing +0.30 [-0.13, +0.74], K<=0 fault +2.53 [+0.45, +4.69], shadowing +0.88 [-0.71, +2.58] -> rule yes
  on the whole fit set the rule picks: branch evidence; nested picks per outer fold: branch evidence, branch evidence, branch evidence, branch evidence, branch evidence
  VERDICT p3: adopt branch evidence
##### m_all p3 done 18-Oct-2026 16:24:36
```
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
  9101, 9102). No simulation seed was added. That check compared them only with a fixed list;
  it now also checks them, and the measurement's streams (section 11), against every flight
  stream of the test: none shared, all below the lowest (queued, section 9).

## 7. If a profile adopts: what deployment takes

1. `run_stage.m` `run_one`: `FUSION_REV = true; FUSION_FIT = 'enlarged';` before `select_fusion`
   (in the deploy commit, with the fourth set's `kpi1_set` switch, `docs/d91_set4.md` step 2).
   B2F then deploys `fusion_pick.m` without choosing again (section 9). It reads the three test
   sets by HDF5 (the images in blocks) and fits two variants out of fold: about an hour, not the
   6-10 min of today's B2F. The smoke has no third test set, so the smoke's B2F needs
   `FUSION_FIT` off.
2. In the same deploy commit, the fourth set's guard in `eval_detector.m` (d91-set4, B3r) also
   requires `deployed_pick` in `data/fusion.mat` and
   `isequal(rmfield(deployed_pick, 'check'), fusion_pick())`. Every pick writes the same
   `fusion_rev`, so without this a `fusion.mat` from an earlier B2F (before `fusion_pick.m`
   changes, for example after the phi verdict) would pass on the revision id alone.
   `fusion_rev_id.m` stays byte-identical to `d91-set4`'s.
3. Rerun B3, B3a, B4 and B4s. They are in-sample on the read sets and are kept only as
   descriptions.
4. Read KPI 1 once, on the fourth test set (FRESH_SET = 3, the d91-set4 track).
5. `rekey_pools` (the columns read only `gant`), then the closed loop from C1d on.
6. Profile 3 before its C1p, profile 1 after its run, profile 2 from its start, as the
   recommendation lays out.

## 8. phi: the declared comparison (fixed before any phi = 1 number exists)

phi = (1 - rho) / (1 + rho) (section 1) has no library source and was never compared with
phi = 1. Every adopted choice is compared with its baseline, so it is measured now. This
section was written and committed before the comparison ran; no phi = 1 number existed then.

**Variants.** 'branch evidence' (iso + glr + held + post, phi as is, the adopted variant) and
'branch evidence, phi = 1': the same four groups with phi fixed at 1 in the GLR
(`window_cues.m` `branch_glr`) and in every CUSUM step (`branch_ref.m`), and without the
`gl_phi` column (a constant). Everything else as in section 5: the enlarged fit set from the
same extracts, N 12, lambda 1e-3, the deployed target rule, no cfar, the outer folds by
sub-run (stream seed 9101), the paired bootstrap over sub-runs (1,000 resamples, seed 9102).
The checkpoints of section 5 are reused (windows, the phi columns, the base and 'branch
evidence' out of fold), after the job checks that its code rebuilds the same phi columns.

**Readings.** D = 'branch evidence' less 'branch evidence, phi = 1' (the gain of keeping
phi), in points with 95% intervals, the items of `fusion_adopt('paired')`:
- (i) out of fold on the whole fit set;
- (ii) nested: each outer fold applies the keep rule below to inner out-of-fold readings of
  its four training folds (500 resamples, seeds 9151-9155), fits the variant it keeps on them
  and predicts the held-out fold; D over the nested predictions against phi = 1 out of fold.

**Keep rule.** D keeps phi only if fault F1 gains (lower bound > 0) and no other rule item is
worse: macro-F1 over every frame and above the KPI 1 threshold, shadowing F1, and both
lost-branch F1 at K <= 0 dB each with upper bound >= 0; clean frames read as a threat and as
a lost branch each with lower bound <= 0. phi is kept on a profile only if (i) and (ii) both
pass the keep rule.

**Deployment (one design for both profiles).**
1. phi kept on both profiles: deploy 'branch evidence' (phi as is).
2. Otherwise deploy 'branch evidence, phi = 1' (simpler, no unsourced factor), provided that
   on both profiles it passes the adoption rule of section 4 against the base, out of fold
   and through the nested reading of (ii) (`fusion_adopt('branch')`).
3. If phi = 1 fails that rule on a profile, 'branch evidence' stays, and phi stays flagged as
   an unsourced factor.

The verdict line is printed by the job, per profile and for both together. The pick goes
into `fusion_pick.m`, which `select_fusion.m` deploys (section 9).

## 9. Deployment tied to the measured pick

The pick of section 5 was measured on one design: N 12, lambda 1e-3, the deployed target rule
(a path-loss onset is the target while pos - onset < N), the four branch groups, no cfar. B2F's
revised selection by itself would choose again: it uses d90's target rule (N - 1), and it can
add cfar or the combination 'cfar and X'. Neither of those was measured on the enlarged set, so
B2F now deploys exactly the measured design.

- **`fusion_pick.m`** holds the design: name, its columns (`cues`), N, lambda, the target rule
  ('N') and where the verdict is recorded. It is the one place the phi verdict of section 8
  changes (to `'branch evidence, phi = 1'` with `cues.phi1 = true`).
- **`select_fusion.m`.** With `FUSION_REV` and `FUSION_FIT = 'enlarged'` it takes
  `fusion_pick()` (or `FUSION_PICK` when the caller gives one) and never runs
  `fusion_adopt('choose')`. The measured N and lambda replace validation's own choice, which is
  printed beside. The target is `FM.target_age = N`, the deployed rule. With these, on the
  enlarged set's folds (seed 9101) and bootstrap (seed 9102), it refits the base and the design
  out of fold and checks the rule of section 4 on the target it deploys. If the rule fails, B2F
  stops with `select_fusion:pick_rule`, which is a no-go. On profiles 1 and 3 this is expected
  to reproduce section 5's 'branch evidence' row, to the precision of the extracts (their
  probabilities are single precision; B2F scores in double). No deploy B2F log exists yet.
- **The latch.** m_all measured the fused class with the onset latch off (both logs' header
  reads 'latch 0'). `fusion_pick.m` records `latch = false`. The pick path sets
  `FM.latch = PK.latch` instead of choosing it on validation, prints validation's out-of-fold
  latch comparison beside it and records it in `deployed_pick.check.latch_val`. A pick without
  a latch state stops B2F (`select_fusion:pick_latch`). Without a pick the latch is chosen on
  validation as before.
- **`data/fusion.mat`** also holds:
  - `fusion_rev = fusion_rev_id('enlarged')`, the id the fourth set's B3r requires
    (`docs/d91_set4.md`, step 2; `fusion_rev_id.m` is byte-identical to `d91-set4`'s, so the
    merge has no conflict);
  - `deployed_pick`, the design (with its latch state) and its rule check (`check`, the
    paired comparison, with `check.latch_val`).

  Without `FUSION_REV` the file keeps its old layout, so section 2's bit-identity holds. With
  `FUSION_REV` alone (validation fit, no pick) the d90 selection runs as before and records
  `fusion_rev_id('validation')`.
- **phi = 1 option.** `opt.phi1 = true` fixes phi at 1 in `window_cues.m` (`branch_glr`, without
  the `gl_phi` column) and in `branch_ref.m` (`'init'` and `'run'` take it). `fuse_classes.m`
  and `policy_monitor.m` pass it on, so every reader builds the same row. Without the field
  nothing changes, so section 5's columns are rebuilt bit for bit (`m_phi.m` checks this before
  it reuses them).
- **Profile 2 is not covered.** `fusion_pick.m` was measured on profiles 1 and 3 only. In
  profile 2's chain B2F runs before B3n and B3m have built its second and third test sets, so
  its enlarged fit set does not exist then. Profile 2 needs its own decision: measure there
  first, or deploy only after its test sets exist. Either way the rule check above is its
  guard.
- **Tests (queued, section 6):**
  - `test_fusion_pick_deploy` (new) checks the pick (latch off), the revision ids, and that
    select_fusion takes the pick, asserts the rule, sets the pick's latch before the save,
    records the latch comparison and never reaches 'choose' when it has a pick; and the deploy
    guard of section 7, step 2, on a `deployed_pick` built as B2F builds it;
  - `test_branch_evidence_cues` adds phi = 1: the unscaled GLR, the columns without `gl_phi`,
    the held CUSUM step by step equal to the batch run, and the monitor equal to
    `fuse_classes` with phi = 1;
  - `test_fusion_target_age` reads the new save lines;
  - `test_seed_streams_disjoint` compares the resampling streams with the flight streams.

  The wrap job also runs the pick path once on the smoke data, as a code check: it either
  saves the file or stops at the rule check. Smoke numbers are not results.

## 10. Closed-loop wrap check

**The mechanism.**
- A closed-loop episode plays its geometry's pool frames cyclically. `link_env.m`
  `draw()` reads row `mod(k0 + t, n) + 1`, with n = `F_SUB` = 20 frames per geometry
  (`build_policy_pools.m`).
- An episode lasts T = 30 decisions (`train_dqn.m`, `H.T`). The decision of cycle t reads frame
  k0 + t - 1, and k0 is drawn in 0..19.
- So every episode except a rolling-in flight jumps from frame 20 back to frame 1 at cycle
  tw = 21 - k0, and again at cycle 41 - k0 when k0 >= 11. A rolling-in flight instead cycles
  over its last 10 frames past its run's end.
- At the jump, every antenna's gain is that of a frame 19 cycles earlier: 0.38 s back in the
  flight.

**What it can do to a monitor.** The fading itself is not the issue at speed. At 2.4 GHz
(wavelength 0.125 m) the coherence time is about 0.423 / f_D (Clarke model, a standard
approximation, not from the library). That is 8 ms at 23 km/h, below one 20 ms cycle, so
consecutive cycles are already nearly independent fades and the jump looks like any other cycle.
In hover (0.1-23 km/h) consecutive cycles share a fade, and the jump replaces it by one 19
cycles away. Any monitor that compares the latest cycles with a reference then sees a change:
- the held reference and its CUSUM (`branch_ref.m`);
- the fusion's window cues;
- the Eb/N0 drop alarm (`drop_cusum.m`, `drop_ref.m`).

**The check (queued; d90 smoke pools only, no live data).** `wrap_check.m` runs on a copy of
`scratchpad/d90_smoke/data` and reports three things:
- A. The jump in the pools' gains (frame 20 to 1) against consecutive frames, per antenna and
  for the branch ratio, by speed band (the speed of each Eb/N0 and geometry,
  `PP.speed{split}(s, r)`, as `policy_run_set.m` reads it).
- B. The held CUSUM alone, on the gains as an episode plays them for every k0, with phi as is
  and phi = 1.
- C. The whole monitor at no_action, on the clean validation episodes the false-alarm readings
  use (`clean_world.m`, `clean_wide_specs.m`, frame seeds 41000 + batch). It runs three
  monitors: the deployed smoke fusion, and the revision with phi as is and with phi = 1, each
  fitted on the smoke validation split.

The quantities:
- per cycle relative to the jump, the clean cycles read as a lost branch and as an antenna
  fault, drop alarms, any alarm and confirmed alarms;
- the rate within 11 cycles after the jump less the rate before it, over cycles t >= 13 (the
  fusion's window and the held reference full), stratified by t, with a 95% interval of a
  bootstrap over episodes (seed 9161), for hover and faster flights apart;
- antenna-fault recall within 11 cycles of the jump and elsewhere (seed 4400 episodes), and
  their difference stratified by the cycles since the onset (Mantel-Haenszel weights, as for
  the clean rates): the cycles after the jump come later in an episode, so an unstratified
  difference could not be put on the jump.

**Not covered: rolling-in flights.** A rolling-in flight cycles over its last 10 frames past
its run's end, a jump 9 frames back every 10 cycles during the ramp (`link_env.m` `draw()`).
C leaves them out (`~R.ev`) and no other part reads them, so the check says nothing about them.

**What the smoke run can show.** It is a mechanism check only. The smoke pools have 2
geometries per split and few hover flights (`build_policy_pools.m`, smoke settings), and the
smoke detector is reduced, so C's levels are not results; the question is only whether the
jump moves the rates at all. A null result on smoke cannot support 'no change needed'. A, B and
C are rerun on profile 3's pools after its C1p and on profile 1's after its run, before any
such conclusion; neither profile has `data/policy_pools.mat` yet (C1p builds it). A and B
depend only on the pools' simulated gains, which the smoke builds as the profiles do.

**If the jump raises alarms: the fix belongs in the environment, not the detector.** None is
implemented here.

| Option | What it does | Cost | Physically |
|---|---|---|---|
| (a) Longer pools: F_SUB >= 50 with k0 drawn in 0..F_SUB - T (a `link_env.m` change), or F_SUB >= 50 with k0 kept in 0..19 | every episode reads consecutive frames of one flight. Longer pools alone do not do it: `link_env.m` draws k0 in 0..F_SUB - 1, so with F_SUB = 50 every k0 > 20 still wraps within T = 30 | every pool rebuilt (C1p, the clean, check and edge pools) at 2.5 times the frames: days per profile, on the critical path. The k0 rule sets the start diversity per geometry: 0..F_SUB - T gives 21 starts, 0..19 keeps today's 20; the cost is the same | no jump within an episode: exact for the playback. The frames an episode samples change with the k0 rule, so the readings are not bit-comparable with today's |
| (b) Ping-pong playback (1..20, 19..1, 2..20, ...) | the gains stay continuous at the turn | `link_env.m` only, plus: the coded-packet pairing (`obs.pkt`) and the FEC codeword span (`PP.fec_frames` consecutive frames, `fec_packets.m`) break at every reversal and need their own rule; the rolling-in 10-frame cycling needs the same change. No pool rebuilt; the closed loop rerun from C1d on, which the deployment reruns anyway (section 7, step 5) | each segment is reversible in distribution (an even autocorrelation), but the joined path is not a stationary sample path: at the turn X(t - 1) = X(t + 1) (correlation 1 in place of rho(2 dt)), and an episode revisits only 20 distinct fades, which shrinks the variance any reference sees and can make false-alarm rates look optimistic. The slow parts reverse too (attitude in a turn, range drift up to 18 m per 0.4 s at 161 km/h) |
| (c) T <= n - k0 | no jump | none | changes the closed loop's protocol (episode length and start diversity); not recommended |

**Bias of the existing closed-loop results, if the jump raises alarms.** All of these read
T = 30 episodes on 20-frame pools: train_dqn, choose_drop_threshold (monitor_trace),
evaluate_policies and the edge map. The bias runs both ways:
- conservative: clean false alarms (KPI 6) overstated; the drop alarm's threshold, chosen
  against a false-alarm bound on clean episodes, set higher than the link needs, so detection
  delays pessimistic;
- optimistic: in threat episodes an alarm the jump causes after the onset counts as a
  detection, so recall and delay near the onset can look better than they are;
- the policy: the DQN is trained and evaluated on the same artefact, and the check runs only at
  no_action, so the policy's reaction to the jump is not measured.

Every monitor sees the same jump, so the comparisons stay paired, but a monitor more sensitive
to steps, such as the held revision, is moved more, in either direction. The size comes from
C on the profiles' pools (see above), not from the smoke.

<!-- WRAP RESULTS -->
Pending: `wrap_check.txt` of the queue (`C:\Users\Adi Suliman\d91q\fuse\wrap\wrap_check.txt`).
<!-- END WRAP -->

## The queue

The jobs of sections 9, 10 and 12 run in `C:\Users\Adi Suliman\d91q\fuse\d91q.sh` (verbatim:
`docs/d91_fuse_queue.sh.txt`, its fill step `docs/d91_fuse_fill.py.txt`). It was started hidden on
18.10 at 18:14:56 (bash PID 27552) with code `eb87297`, exported by `git archive` to
`d91q\fuse\eb87297`. The jobs:
1. tests, focused;
2. wrap, `wrap_check.m` on the smoke copy `d91q\fuse\wrap`;
3. phi_p1, then phi_p3, `m_phi.m` in the scratchpad folder `d91_fuse`;
4. phi_both, the verdict.

They run one at a time, single thread, with TEMP `C:\Users\ADISUL~1\d91q\fuse\tmp`. Each job
starts only when at least 35 GB of commit is free and at most one other non-pipeline MATLAB
runs (`gate.ps1`, the d91-speed queue's gate). The gate is checked every 10 min, and a job is
given up after 24 h of waiting. Logs: `d91q\fuse\logs` (`queue.log`, one log per job, and
`summary.log` at the end). The wrap and phi results are written into sections 10 and 12 and
committed (this file only).

**Edits before the jobs started (18.10, 18:37, recorded in `queue.log`).** While the tests job
still waited at the gate, the folder `d91q\fuse\eb87297` was replaced by a `git archive` of
`774a73e` (`D91_SHA.txt` names it; the `eb87297` export is kept as `eb87297_orig`), so the
tests, the wrap check's pick path and the phi jobs run the code with the latch fix of
section 9. The pending copies were changed to the text committed in `774a73e`:
`wrap\wrap_check.m` (the speed read per Eb/N0 and geometry; fault recall stratified by the
cycles since the onset) and `m_phi.m` (it asserts that the reused 'branch evidence' reading
reproduces m_all's M4 row before anything uses it, and stops with `m_phi:tests` unless
`logs\tests.log` reads `D91TESTS n/n` with no `D91FAIL`, so the phi jobs are skipped after a
failed test run; `phi_both` is then skipped by the queue, as its inputs are missing). The
summary header still names `eb87297`, the folder's name.

## 11. Resampling streams

| Seed | Where | What |
|---|---|---|
| 61, 62 | `select_fusion.m` | folds of the validation sub-runs; bootstrap over them |
| 9101 | `select_fusion.m` (enlarged), `m_all.m`, `m_phi.m` | folds of the enlarged fit set's sub-runs |
| 9102 | the same | paired bootstrap over sub-runs, 1,000 resamples |
| 9103 | `m_all.m` M3 | bootstrap of the shadowing bound |
| 9111-9115 | `m_all.m` M4 nested | inner bootstraps (500), one per outer fold |
| 9131-9135, 9141-9145 | `m_all.m` M3 | `rng(9120 + 10 j + k, 'twister')` of the bagged trees (j = 1 gain-only, 2 with coherence; k the fold) |
| 9151-9155 | `m_phi.m` nested | inner bootstraps (500), one per outer fold |
| 9161 | `wrap_check.m` | bootstrap over the smoke episodes (smoke only) |

All of them lie below 64 x 700 001, the lowest flight stream (`seed_base.m`, `pool_seed.m`).
`test_seed_streams_disjoint` checks them against every flight stream of the test. The wrap
check's frame draws reuse the readings' own seeds (41000 + batch for the clean episodes, 4400
and 4500 + batch for the threat episodes, as `choose_drop_threshold.m`), so it flies the same
frames as those readings.

## 12. phi: results

The job (`m_phi.m`, verbatim in `docs/d91_fuse_m_phi.m.txt`) appends its log here when it ends.
The verdict is mechanical from section 8.

**Which reading governs for phi = 1.** phi = 1 is a fixed design, so its out-of-fold check
against the base, (i) (`af`), is the governing check. The nested reading (ii) is a mixture: in
an outer fold whose inner reading keeps phi, the predictions are those of 'branch evidence'
with phi as is, so `an` does not test phi = 1 alone. Rule 2 of section 8 requires both, so the
nested reading can only make deploying phi = 1 stricter.

<!-- PHI RESULTS -->
Pending.
<!-- END PHI -->
