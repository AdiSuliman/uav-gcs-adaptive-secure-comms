# Recommendation: antenna_fault and airframe_shadowing (v7, profile 1)

**Bottom line.** Don't stop the live run, and don't change the dataset or the CNN now. No label bug was found. Most of the fault errors and nearly all the shadowing errors are a lost branch read as 'none'. About half of the fault misses and most of the shadowing misses come from physical limits:
- a 5 dB fault at low K cannot be resolved in a 240 ms window against the static per-antenna imbalance;
- a shadowing onset is still on its ramp at the 5 dB event criterion.

The fixable part is mostly faults: shallow faults at high K, hover, and frames after the onset has left the window. Fix it with one fusion-only revision computed from fields already stored, fitted on a larger fit set, and read once on a fourth test set.

The honest expected result: fault F1 rises to about 85 (validation, not yet shown on a test set), and shadowing stays about where it is. The evidence does not support bringing both classes to 85% or above. The report should say that and explain the physics.

## 1. Diagnosis

**Numbers to correct before the report.** The brief's "validation 84.7 / 83.2" is the first test split (p1.log lines 1604-1630). Out-of-fold validation is fault 83.4 and shadowing 85.2 (macro 93.60). The third-test set reproduces the brief exactly. The one exception is the 'none' row: none->path_loss is 266 in the brief and 128 in the reproduction. Check that row before quoting it.

**Labels: no bug.**
- **Fault:** the label and the attenuation switch on together, from the same per-run onset (build_threat_model.m lines 583 and 742).
- **Shadowing:** the label and the loss come from the same shadow_frame call, with the same 5 dB rule and the K switch to -16 dB. Tests exist: test_onsets_in_the_model, test_shadow_k_onset, test_shadow_onset_ramp.
- **Clean roll-in:** it cannot hide an antenna, because the attitude gain is common to all antennas. The 4.28% of clean roll-in frames read as shadowing are classifier errors.

**Fault: where the misses are (validation, 165 misses, 145 of them read as 'none')**
- **By severity:** 87 misses at 5 dB and 59 at 8.7 dB. On the third test set, 651 of the 759 fault->none frames are at those two levels. From 12.4 dB up, recall is 84-99%.
- **Static imbalance:** body loss (Badi 2019 Table 1) plus the ±2 dB calibration error (AD9361) give each antenna an offset with SD 2.9 dB. In 15-21% of clean frames the weakest antenna is already 5 dB or more down. A 5 dB fault frame has a median window deficit of only 3.8-4.1 dB.
- **Fading:**
  - One power sample spreads 5.5 / 5.1 / 3.7 / 2.0 dB at K = -5 / 0 / 5 / 10 dB.
  - A window holds at most 12 independent samples, against the 36 Lee 1985 needs for ±1 dB (eq. 31).
  - At the actual operating point (1.87% of clean frames read as a lost branch, about 50 cycles between false alarms), Lai's bound (Xie 2021 Thm 1, Rician KL) gives the minimum delay for a 5 dB step: at least 8.1 / 6.7 / 3.9 / 1.7 cycles at K = -5 / 0 / 5 / 10 dB. That holds even if the level before the change is known exactly. This is my arithmetic from the verified KL values.
- **The window forgets the onset:** detection is 65.6% on the onset cycle, about 90% by +3, and back to 81.7% at +11/+12 (test 78.7 / 76.5%). 25% of labelled frames have no pre-onset cycle in their window.
- **Triage of the 165 misses (downgraded):** 27 recoverable within the window, 22 more with a held reference, 40 marginal, 76 limited. This is a model triage, not a certificate. Its false-alarm rate was never calibrated on real clean frames, and the CNN beats its "ideal" in the 5 dB, K<0 cell (58% against 28%, about 3 sub-runs). Read "limited" as "not separable by per-cycle gains alone".
- **The fixable stratum hardly exists in validation.** On the third test set (described, not used for any estimate), 255 of the 813 fault misses are shallow faults at K ≥ 10 dB:

  | Stratum | CNN | Gain-only ideal |
  |---|---|---|
  | 5 dB, K 10-15 dB | 10.6% | 88.1% |
  | 5 dB, K ≥ 15 dB | 30.5% | 99.3% |
  | 8.7 dB, K 10-15 dB | 48.1% | 99.5% |

  Validation has 0 frames at 5 dB with K 10-15 dB and only 1-2 sub-runs at K ≥ 15 dB. Yet the fusion is fitted on validation only (select_fusion.m header): 64 fault sub-runs, 8 of them at 5 dB.
  - **Likely mechanism (inferred from code, not tested):** the branch cues follow the antenna that is weakest by mean (window_cues.m lines 82-89). At high K, the static imbalance makes a clean antenna the weakest, so the branch that actually stepped is not the one being read.
  - **Hover:** CNN 82.7% against 96.8% for the ideal (few sub-runs).

**Shadowing (validation, 129 misses)**
- **The frames are shallow whatever the nominal level.** An event starts at the 5 dB crossing and ramps in with the roll-in. Labelled frames carry 5.4-11.2 dB (10-90%), and only about 5% come within 1 dB of the nominal 6-25 dB level.
- **Misses:** 71 of 129 within 2 cycles of the onset, 106 of 129 at K < 5 dB, and 92% are read as 'none'.
- **The CNN already beats the gain-only ideal:** 86.7% against 84.3% with the onset known (test 84.7 against 80.2). Per-branch gain levers therefore cannot help. At low K, the hidden antenna's switch to K = -16 dB cannot be seen in 12 samples:
  - moment K at a true -16 dB: median -0.3 dB, 10-90% range [-20, 5.0];
  - moment K at a true 0 dB: median 2.2 dB, range [-20, 6.4];
  - the estimator is Aoki eq. 2, which equals Sun eq. 5.12 (Tepedelenlioglu).
- **Likely partly a label-boundary effect:** the 'none' frames just before the onset already carry 2-5 dB of real loss. That figure is a model estimate, not measured on data.
- **Clean false alarms** are driven more by static imbalance than by the roll-in (test: 4.28% inside a roll-in against 5.85% outside).

**Correctness items (none of them a label bug)**
- (a) The window-wide moment-K and spread cues (k_w, k_strong, k_contrast, sd_weak, sd_contrast) are computed across the onset step. That is a non-stationary sample, against the stationarity Aoki eq. 2 assumes. At link K ≥ 10 dB it can make a fault look more like a shadow than a real shadow does. Effect is small: it touches only the fault/shadowing swaps (39 + 42 validation frames).
- (b) Per-level shadowing results must not be reported as detection at the nominal level.
- (c) Realism, not yet measured: clean turning flights whose geometry would hide an antenna fly with no loss.
- (d) Stale comments: "fd ≤ 267 Hz, 0.5 ms frame" should be 0.69 ms and 358 Hz.

**Claims dropped or downgraded**
- **"The emitter of opportunity explains the CNN's edge at low K / is an extra fault detector": refuted (I checked the code).** idle_amb is simulated only in fault and shadowing sub-runs (run_dataset_sweep.m lines 291-293). Only emitter_reading.m reads it, as a two-class cause reading, fault against shadowing, "beside KPI 1, never in it". KPI-1 data has no emitter in the idle time. So 73.8 -> 80-81% is cause recall, not detection.
- **"A held reference adds +1-3 F1 to both classes":** only the fault gains. In the what-if, shadowing moves -0.3 to -1.7.
- **"A new per-branch K estimator": dropped.** It is the same estimator already in the code.
- **"No held per-branch reference was ever tried": wrong.** The onset latch exists. It is off because it cost 1.37 macro points (92.06 against 93.43, p1.log) and, at K ≤ 0 dB, it read faults as ramps.
- **"A linear GLR detects 2-4x more":** this was measured against a re-implemented single t statistic, not against the fusion. Uncertain.

## 2. Options

| Option | Expected gain (basis) | Cost per profile | Latest entry / kill? |
|---|---|---|---|
| **O0. Continue unchanged** | 0. Fault 83.1, shadowing 82.7 (third test) | 0 | – |
| **O1. Fusion revision fitted on validation only** (iso + held reference + linear GLR + K fix) | Validation what-if (out of fold, budget share chosen in-sample, naive cause rule): fault +1.1 to +1.5, shadowing -0.3 to -1.7, macro -0.04 to +0.13. Upper bound fault +2.94 [1.14, 5.41]. d90 nested gain +0.05 / +0.04 macro | Code + finishing d90's tests and smoke (~25 min + ~4.3 h). B2F..B4s 2.5-5 h. Rekey 0.5-1.5 h (unmeasured). 4th test set ~6 h. P1 closed loop C1d..RPT 19-22 h (45-52 h with d90's C2) | P3: before its C1p (= P1 SURV3 end, 22.10 13:00 to 23.10 12:30), no rekey. P2: before it starts (~24-25.10). P1: after its run. **No kill.** Risk: validation cannot learn the stratum, so nested CV probably rejects it again, as it did iso |
| **O2. As O1, fitted on an enlarged fit set**: validation + the already-read test sets (first test split, B3n, B3m), with a fresh 4th set for the single KPI-1 reading | Unknown. It makes the stratum where the misses concentrate learnable and measurable, with 5-10x the nested-CV power | O1 + a code path for B2F to fit on several sets (hours; check memory: splits.mat 7.0 GB, splits_fresh2 4.8 GB). Fallback: a fresh fit-set sweep (~6 h) | Same as O1. **Needs Adi's approval** (changes what the read sets are used for) |
| **O3. Dataset or CNN change**: clean unscored lead-in, more or mid-event sub-runs, per-antenna CNN input, emitters in every class | Lead-in: fault +2.6 to +3.9 upper bound only. Mid-event sub-runs: shadowing up, shallow fault down. Per-antenna CNN: low for the fault (the attenuation is already in gain_ant/bch). Emitters: cause only | A5 + sweeps + chain + pools 101-118 h + closed loop: **6-8 days per profile** | P1 before C1p (~18.10 03:00-04:30): **kill PID 42560**, losing the OOD folds already done (no checkpoint). Otherwise after the whole run. Lead-in and mid-event change what KPI 1 measures |
| **O4. Slow layer (cause by persistence) + monitor-level held reference** | 0 on KPI 1 by construction (independent 0.4 s sub-runs). Value: the steady state (test 74-79%) and per-event cause (84.4 / 83.3%) | The long-flight experiment already planned | After the run. Needs body loss that depends on azimuth (Badi measured the pattern over azimuth) and body loss on the emitter path, or the result will look better than real flight |

Not recommended (already rejected or near-zero physical value): per-class offsets, prior corrections, a new K estimator, more sub-runs aimed at 5 dB faults at K < 10 dB.

## 3. The recommended path: O2 now, O4 after the run, no kill

1. Leave PID 42560 and p3_fix.sh (PID 76595) untouched.
2. Build one "branch evidence" revision in a new branch off d90, behind FUSION_REV, computed only from stored gain_ant and bch:
   - (a) iso: the maximum step over all antennas, not the antenna weakest by mean (Xie 2021 Sec. III-I);
   - (b) a per-branch held reference in linear power, frozen while a drop is under test, as drop_ref.m does;
   - (c) a one-sided exponential GLR of one branch against the pooled others, window-limited (Xie 2021 eq. 20; Xie 2022 WL-CUSUM), with an effective sample count for hover;
   - (d) post-split K and spread, as a correctness fix.

   The fusion learns the cause. There is no hard step/ramp rule, which is the lesson of the latch. One source is missing: the π²/6 variance of the log of exponential power, i.e. why averaging in dB is only about 61% efficient. Add that PDF before citing it.
3. Select with d90's nested CV by sub-run on the enlarged fit set. Adopt only if all of these hold:
   - fault F1 gain with its CI above 0;
   - macro CI above 0;
   - no shadowing loss beyond its CI;
   - no collapse at K ≤ 0 dB (the latch's failure).
4. Build the fourth test set now (FRESH_SET=3, in worktree copies). Read KPI 1 on it exactly once.
5. If adopted by 21.10 evening: re-run P3's B-stages before its C1p (coordinate with p3_fix.sh and run.lock). P2 uses the revision from its start. For P1, re-key the pools and re-run its closed loop after its run. If it is not ready in time, the run stays as is, and the revision goes to all profiles after the run (after 1.11).
6. Shadowing: no detector change until M3 below is done.
7. Interim report (1.11):
   - KPI 1 passes: 93.58 [93.08, 94.07];
   - fault results by severity: the shallowest depth detected at 85% or more;
   - shadowing results by realized depth;
   - the physics above, and the revision in progress;
   - no gain claimed before the fourth test set is read.

**Why this path:** it is the only lever aimed at the population that can be fixed. It stays in the hours-not-weeks cost class, needs no kill, keeps the test sets clean, and removes the likely reason iso was not adopted (the fit set is too small).

## 4. What to measure next (validation only, or the enlarged fit set once approved)

Memory is busy until about 18.10 08:00 (P1 OOD, P3 OOD/B4s). After that, start only with at least 45 GB of free commit. Adi should decide whether to stop orphan MATLAB PID 32824, which holds 4.6 GB.

- **M1, by 19.10:** split the errors on validation. Shadowing->none and none->shadowing by the real loss at each frame, recomputed with shadow_frame and turn_attitude from the stored draws, by age and by K. Fault->none by level × K × age × speed. MATLAB-light, no Simulink.
- **M2, by 19.10:** the share of clean turning flights whose draws would hide an antenna (flight_draws with active_threat set to shadowing). If it is material, fix the generator for the next dataset, not now.
- **M3, by 20.10:** a shadowing bound that includes cross-antenna coherence (va.bch coh_* and los_* columns). It decides whether any shadowing change is justified.
- **M4, by 21.10 evening (go/no-go for P3):**
  - the nested CV of the candidate columns, on validation alone and on the enlarged fit set;
  - per-class F1 by stratum, with sub-run bootstrap intervals;
  - clean false alarms (now 5.09% on clean flights, 1.87% on all clean frames);
  - the K ≤ 0 dB check;
  - a check that the read sets share validation's class, level and K grids.
- **M5, in parallel:** the fourth test set sweeps for P1 and P3, about 6 h each.

Files are in C:\Users\ADISUL~1\AppData\Local\Temp\claude\C--Users-Adi-Suliman-uav-gcs-adaptive-secure-comms\0ff3360f-912b-4701-bfb0-77d6917b5fc3\scratchpad\weak_branch\:
- wb_anatomy.txt (the what-if is at lines 391-397)
- wb_final.txt
- wb_boundary.txt
