# d89 predicted MMSE gain before C1p

Branch `d89-mmse`, from `725a2f1` (v7-merge with d87 and d88). It implements the four confirmed
findings of the independent review of d88's MMSE predictor (`rev88_confirmed.json`): dec-01,
phy-02, phy-03 and phy-01. The predictor (`mmse_predict.m`, `F.mmse_pred`) is the rule's nulling
flag and a row of the agent's state, and C1p bakes it into every pool frame, so it is settled here
before the pools are built. The numbers below were measured on this branch.

## 1. Frequency hypotheses in the search (dec-01, MAJOR)

**Cause.** The predictor removes the frequency the receiver's synchronization left with the
phase step between consecutive pilot blocks (`residual_frequency`). The blocks are
`pilot_block + pilot_every` = 52 symbols apart, so that step cannot tell a frequency from one
fp = 1 Msym/s / 52 = 19.2 kHz away. Under a 30 dB tone the receiver's own estimate jumps between
frames of one run by several such steps. The predictor then measures MMSE at a frequency alias,
and G collapses. Profile 3 (4 antennas) failed V13 9/11 on it: tone 30 dB G +6.7 dB, 54% of
frames at or above 6 dB.

**What the reviewers proposed.** Inside the existing search gate (MMSE SINR below 0 dB at the
receiver's arrival), also evaluate the frequencies sy(2) + m fp, m = -3..3, under the same 2x
acceptance.

**Why the range is wider here.** With m = -3..3 the V13 tone row of profile 3 still failed
(11/12 rows). It read G +24.0 dB against +27.6 dB for the theory of its own combiners, 0.6 dB
beyond rule (b). A per-frame diagnostic of that row (scratchpad `d89/diag/diag_tone30.m`) found
two causes:
- **The range.** In two of the six flights the receiver's frequency was off by 88-90 kHz, which
  is 4.6-4.7 fp, outside +-3.5 fp. Those frames kept G between 0 and +9 dB. In one more flight,
  two frames were off by 187 kHz.
- **The theory's bookkeeping.** V13 left the frames the search took out of its theory column
  (section 4).

The MMSE receiver acquires the frame over its whole frequency window. That window is
+-(2 `cfo_ppm` of the carrier + the largest Doppler) = +-120.4 kHz, the same window
`build_threat_model.m` searches (its FB bins). So the predictor's hypotheses span that window
too, on the receiver's grid sy(2) + j fp/4. The m fp aliases are on the grid, and the reviewers'
-3..3 is a subset of it.

**Scoring cheaply (phy-03 part 2).** Each candidate (arrival 0..`timing_max_sym` x frequency) is
scored by the long training's in-sample DMI fit q = r^H R^-1 r. This is the share of the 32
contiguous training snapshots' power that the known symbols explain.
- R does not depend on the frequency, so one R per arrival serves every frequency.
- The correlation r is computed for every frequency in one matrix product (`pagemtimes`,
  `pagemldivide`).
- The cross-correlation of known PSK symbols under a frequency error f is the Dirichlet kernel
  of 32 symbols, with its first null at 31 kHz. So the contiguous long training separates the
  pilot aliases. A grid step of fp/4 = 4.8 kHz loses at most about 1% of q.
- The short training is not used. Its period of 4 symbols makes a tone near one of its lines
  look like our signal.
- The receiver's own alias at its own arrival is left out, because it was already measured.

Only the two best candidates get the full held-out measurement (`residual_frequency` and
`measure`, as before). The second must be at another arrival or more than fp/2 away. The higher
MMSE SINR is taken if it is at least twice the receiver's (the 2x acceptance is unchanged).

**Max-then-compare (phy-02).** The 725a2f1 code kept the first candidate that doubled the
running best. The search now takes the highest-SINR candidate, then compares it with 2x the
receiver's SINR. This matches the header, d88's description and the receiver's own `st_sync`
maximum.

**Synthetic check** (scratchpad `d89/syn/syn_check.m`; Rician K 10 dB; 150 frames per clean
point, 60 per tone point; old = 725a2f1):

| Case | n_rx | Old | New |
|---|---|---|---|
| clean, receiver's arrival >= 2 symbols off, Eb/N0 -3 dB: true arrival found | 3 / 4 | 37/150, 48/150 | 149/150, 146/150 |
| same at 0 dB | 3 / 4 | 98/150, 122/150 | 150/150, 150/150 |
| tone 30 dB, receiver m = -5..+5 alias steps off: frequency right | 3 / 4 | - | 60/60 every m |
| tone 30 dB, median G at m = +-1, +-3, +-5 | 3 | +3.9..+8.6 dB | +29.4..+31.4 dB |
| tone 30 dB, median G at m = 0 (no alias, unchanged) | 3 / 4 | +30.5 / +31.4 | +30.5 / +31.4 |

At Eb/N0 6 and 15 dB the clean arrival was already right, and G is unchanged.

**The same V13 tone row of profile 3 after the change** (same seeds, per-frame diagnostic):
- 76 of 114 frames are measured at the search's arrival and frequency, including the flights
  88-90 kHz off;
- no frame reads below +17 dB;
- median G +25.7 dB, against +26.8 dB for its combiners' theory over all frames.

## 2. Latency: the predictor timed in the cycle, the search made cheap (phy-03, MAJOR)

`measure_latency.m` (KPI 7) used to copy `obs.mmse_pred` from the precomputed run, so the
predictor was never timed. It now runs the predictor inside the cycle, in its own column
'MMSE predictor', which counts in every cycle total:
- every antenna's samples of frame k as the combiner sees them (`Rx_IQ`, before the level
  calibration);
- frame k - 1 only as the receive filter's memory (its `sy` set to NaN, so it is not measured);
- the receiver's arrival and frequency from `Rx_S`;
- the value goes into the observation.

The single-core pass reports the predictor's median and p95 as well. `test_mmse_predict_search`
checks that this two-frame call reads the same G as the full run.

The predictor also runs on one thread for its own call (`maxNumCompThreads(1)`, restored by
`onCleanup`). It works on 3x3 or 4x4 matrices, where threading costs more than it saves. On 8
threads its call took 4.6 ms against 3.4 ms on one thread, and the switch costs about 21 us.

**Per-frame time on this machine** (LAT's frames: none, jamming, noise burst and spoofing at
Eb/N0 4 dB, seeds 4242 + t, 20 frames each, `scratchpad/d89/ver_lat.m`):

| Frames (80 per profile) | n_rx 3: median / p95 [ms] | n_rx 4: median / p95 [ms] |
|---|---|---|
| search not run (61 / 61 frames) | 1.40 / 1.78 | 1.50 / 1.88 |
| search run (19 / 19 frames; the jamming run 18 / 17 of them) | 3.69 / 4.35 | 3.82 / 4.26 |
| all frames | 1.46 / 3.95 | 1.57 / 4.04 |
| all frames, MATLAB on one core | 1.44 / 3.80 | 1.59 / 4.11 |

These were measured at the session's 8 threads, with the CPU at 35-41% load from the paused
redo's MATLAB processes. A first pass of n_rx 3 at 100% load read 2.64 / 3.23 ms without the
search and 5.61 / 6.43 ms with it. The two-frame call reads the run's G to within 3e-13 dB on all
80 frames.

Before (725a2f1, the reviewers' measurement): with the search, 9.2 ms median and 12.4 ms p95
on one core, and 20.3 / 26.6 ms on 8 threads.

## 3. Our own echoes on the delay line (phy-01)

Every pool flight runs the delay line, so the predictor's DMI sees our own echoes at whole-symbol
lags as part of R. A single tap partly suppresses them. MRC at one tap leaves them, so G reads a
few dB on low-K, long-spread clean links. The deployed receivers equalize these echoes (rx_taps,
space-time taps), so they gain nothing from this. As the reviewers advised, the predictor is
unchanged here and the coverage gap is closed instead:
- **V13** has a clean row over the pools' draws:
  - every draw of the profile's params (K, correlation, directions, attitude, spreads), the speed
    uniform over the envelope and the GCS at the distance of the Eb/N0, as `pool_cell.m` runs a
    flight;
  - 100 flights x 11 frames at Eb/N0 15 dB, the top of the pools' grid, where our echoes stand
    highest over the noise;
  - rules: |median G| <= 1 dB, and at most 2% of frames at or above `rule_mmse_db` (6 dB).
- Two informational corners, K -5 dB / 1000 ns and K 0 dB / 300 ns.
- `test_mmse_predict_known_symbols` has a clean delay-line case over the pools' draws: 8 flights
  at Eb/N0 15 dB, |median G| < 1.5 dB, at most 5% of frames at or above 6 dB.
- One header line in `mmse_predict.m` states the effect.

## 4. V13 as the profiles deploy, and its verdict in the result (dec-01)

- **The channel.** The rows run the delay line as the profile runs it (`P.tdl`, spreads drawn per
  flight with `P.tdl_random`), for n_rx 3 and 4 from the profile's `params.mat`. The exceptions:
  - V8b stays on the flat channel of the closed forms with the ideal receiver.
  - The V12c rows keep V12c's line (jammer channel 234 ns, ours flat).
- **The clean-link rule.** It is now relative to the theory of the predictor's own combiners,
  |median G - its combiners| <= 1 dB, plus the 2% flag share. On a clean link the optimum is MRC,
  and G is the DMI's estimation loss: about 10 log10((K + 2 - M)/(K + 1)) with K = 16 training
  snapshots, -0.5 dB at M = 3 and -0.8 dB at M = 4 (the Reed-Mallett-Brennan mean, Besson 2021
  eq. 21). The old fixed rule (|G| <= 1 dB) failed profile 3 at -1.0 dB for this reason alone.
- **The theory of its combiners** (`v13_theory`) is computed on every frame. Before, frames where
  the search was taken had no theory value, so rule (b) compared G over all frames against a
  theory over the unsearched ones only. Now:
  - the MMSE weights are evaluated at the arrival and frequency where MMSE was measured, with the
    reference correlations they were normalized by (`D.r_mmse`);
  - the MRC weights are evaluated at the receiver's arrival and frequency (`D.df_mrc_hz`), where
    MRC was measured.

  On unsearched frames this is the same as before.
- **The verdict.** `validate_phy()` (and 'flat') returns `ok` false on a failed V13, so A4v stops
  the chain (`run_stage`, `main`). The Overall line prints 'V13 predicted MMSE gain PASS/FAIL'.
- **V13 alone.** `validate_phy('V13')` writes `results/phy_validation_v13.txt` with its params_id,
  as before. It took 7-15 min per profile on this machine under the redo's load.

## 5. Results

### V13, n_rx 3 (profile 1 params, params_id add18af2...)

| Row | Line [ns] | Eb/N0 | Frames | G | Its comb. | Optimum | Ceiling | JMc(1-c) | MMSE meas/th | MRC meas/th | >= 6 dB G/opt | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| clean link | drawn | 6 | 114 | -0.3 | -0.3 | +0.3 | +29.2 | +0.3 | 10.4/10.4 | 10.7/10.5 | 0.0%/0% | PASS |
| V8b jam 10 dB | flat | 6 | 114 | +17.4 | +17.8 | +15.9 | +30.2 | +15.6 | 11.4/11.3 | -6.0/-6.1 | 100.0%/99% | PASS |
| V11 jam 10 dB | drawn | 6 | 114 | +13.0 | +12.5 | +11.2 | +24.9 | +10.8 | 6.1/5.9 | -6.7/-7.0 | 98.2%/100% | PASS |
| V12c jam 16 dB rho 0.3 | 0/234 | 6 | 114 | +19.1 | +19.0 | +14.3 | +22.0 | +12.3 | 3.2/3.3 | -16.9/-16.1 | 100.0%/100% | PASS |
| V12c jam 16 dB rho 0.9 | 0/234 | 6 | 114 | +23.2 | +22.6 | +18.4 | +25.8 | +18.2 | 7.0/6.9 | -17.6/-16.6 | 100.0%/100% | PASS |
| V12c jam 30 dB rho 0.3 | 0/234 | 6 | 114 | +6.7 | +5.6 | +16.3 | +7.1 | +13.1 | -11.7/-13.2 | -18.8/-18.8 | 57.9%/100% | PASS |
| V12c jam 30 dB rho 0.9 | 0/234 | 6 | 114 | +15.1 | +15.4 | +23.0 | +15.2 | +20.3 | -3.6/-3.4 | -18.8/-18.8 | 94.7%/100% | PASS |
| tone 4 dB | drawn | 6 | 114 | +8.8 | +9.0 | +8.7 | +27.6 | +8.9 | 8.8/8.6 | -0.1/-0.5 | 91.2%/92% | PASS |
| tone 16 dB | drawn | 6 | 114 | +25.9 | +23.2 | +20.2 | +27.7 | +20.4 | 8.9/8.9 | -17.8/-14.4 | 100.0%/100% | PASS |
| tone 30 dB | drawn | 6 | 114 | +25.0 | +25.9 | +32.5 | +25.8 | +32.1 | 7.0/7.1 | -18.8/-18.8 | 100.0%/100% | PASS |
| reactive 16 dB | drawn | 6 | 114 | +18.1 | +18.1 | +13.4 | +20.9 | +11.9 | 2.1/2.1 | -17.5/-17.2 | 97.4%/100% | PASS |
| clean, pools' draws | drawn | 15 | 1100 | +0.1 | +0.1 | +0.8 | +31.6 | +0.8 | 12.8/12.8 | 12.7/12.6 | 0.5%/1% | PASS |
| clean K -5 dB 1000 ns | 1000/1000 | 15 | 114 | +2.5 | +2.5 | +3.2 | +26.4 | +2.1 | 7.6/7.8 | 4.6/4.7 | 3.5%/7% | info |
| clean K 0 dB 300 ns | 300/300 | 15 | 114 | +2.1 | +2.0 | +3.1 | +32.8 | +2.8 | 14.0/13.8 | 11.6/11.6 | 2.6%/8% | info |

**V13 predicted MMSE gain: 12/12 rows -> PASS** (run time 7.1 min, on a copy of the profile's `params.mat`).

### V13, n_rx 4 (profile 3 params, params_id 7ecc49e9...)

| Row | Line [ns] | Eb/N0 | Frames | G | Its comb. | Optimum | Ceiling | JMc(1-c) | MMSE meas/th | MRC meas/th | >= 6 dB G/opt | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| clean link | drawn | 6 | 114 | -0.8 | -0.7 | +0.4 | +29.6 | +0.4 | 10.8/10.7 | 11.5/11.3 | 0.0%/0% | PASS |
| V8b jam 10 dB | flat | 6 | 114 | +18.8 | +18.4 | +17.4 | +31.0 | +17.2 | 12.2/12.1 | -6.3/-6.3 | 100.0%/99% | PASS |
| V11 jam 10 dB | drawn | 6 | 114 | +14.2 | +13.9 | +12.1 | +25.3 | +11.3 | 6.5/6.3 | -7.7/-7.5 | 100.0%/100% | PASS |
| V12c jam 16 dB rho 0.3 | 0/234 | 6 | 114 | +20.8 | +21.0 | +16.8 | +23.9 | +13.5 | 5.1/4.8 | -17.1/-16.5 | 100.0%/100% | PASS |
| V12c jam 16 dB rho 0.9 | 0/234 | 6 | 114 | +22.0 | +22.5 | +18.6 | +26.4 | +18.5 | 7.6/7.6 | -14.2/-14.7 | 100.0%/100% | PASS |
| V12c jam 30 dB rho 0.3 | 0/234 | 6 | 114 | +10.4 | +10.1 | +19.2 | +11.4 | +13.5 | -7.4/-8.8 | -18.8/-18.8 | 80.7%/100% | PASS |
| V12c jam 30 dB rho 0.9 | 0/234 | 6 | 114 | +18.0 | +18.5 | +25.7 | +18.4 | +21.1 | -0.4/-0.3 | -18.8/-18.8 | 96.5%/100% | PASS |
| tone 4 dB | drawn | 6 | 114 | +8.8 | +8.8 | +9.4 | +28.2 | +9.9 | 9.4/9.4 | 0.8/0.7 | 93.0%/95% | PASS |
| tone 16 dB | drawn | 6 | 114 | +26.6 | +25.4 | +21.6 | +28.6 | +22.0 | 9.8/9.6 | -18.8/-15.6 | 100.0%/100% | PASS |
| tone 30 dB | drawn | 6 | 114 | +25.7 | +26.8 | +34.5 | +26.7 | +33.5 | 7.9/8.0 | -18.8/-18.8 | 100.0%/100% | PASS |
| reactive 16 dB | drawn | 6 | 114 | +19.5 | +19.4 | +14.4 | +21.7 | +12.3 | 2.9/3.1 | -18.2/-16.1 | 100.0%/100% | PASS |
| clean, pools' draws | drawn | 15 | 1100 | +0.1 | +0.1 | +1.3 | +32.0 | +1.3 | 13.2/13.1 | 13.0/12.8 | 2.0%/3% | PASS |
| clean K -5 dB 1000 ns | 1000/1000 | 15 | 114 | +3.4 | +3.4 | +4.6 | +27.9 | +2.5 | 9.1/9.5 | 6.1/5.9 | 11.4%/29% | info |
| clean K 0 dB 300 ns | 300/300 | 15 | 114 | +2.3 | +2.3 | +3.8 | +33.3 | +3.7 | 14.5/14.3 | 11.9/11.8 | 4.4%/12% | info |

**V13 predicted MMSE gain: 12/12 rows -> PASS** (run time 8.2 min, on a copy of the profile's `params.mat`).

- **Tone at 30 dB.** It now has 100% of its frames at or above 6 dB on both profiles. Before it
  was 54% at 725a2f1 (the reviewers' run on the flat channel) and 86.8% with m = -3..3 on the
  delay line.
- **The pools' draws row for n_rx 4 is at the 2% limit**: 22 of its 1100 frames read 6 dB or
  more.
  - Clean frames at 15 dB never enter the search (their MMSE SINR is about 13 dB), so this share
    comes from our own echoes (section 3), not from this change.
  - The reviewers measured 0.86% over their draws, and 2.4% among flights with K < 5 dB.
  - The sel-08 threshold is chosen on validation frames that run the delay line, so it accounts
    for this.

Columns:
- **G** is the measured gain.
- **its comb.** is the theory of the predictor's own DMI and MRC weights on the true channel and
  interference.
- **optimum** is Winters, Salz & Gitlin 1994 optimum combining against MRC on the true channel.
- **ceiling** is the measured MMSE SINR over the floor.
- **JMc(1-c)** is the closed form for one directional interferer.

### Reduced C1p check

`scratchpad/d89/c1p/c1p_check.m`, with the d88 smoke's detector (`d88_smoke/data`, read only) and
`params.mat` (n_rx 3, delay line drawn). It builds one cell, the tone at 23 dB (a pool level),
through `pool_cell.m` under no_action, spatial_diversity and channel_switch+spatial_diversity, with
2 geometries of 20 frames (49.9 s). **PASS**:
- every pool carries `mmse_pred`, frame by frame, finite;
- every pool field is known to `rekey_pools`.

| Configuration | mmse_pred median (p10, p90) | Share >= 6 dB | Decision-directed mmse_gain |
|---|---|---|---|
| no_action | +20.5 dB (+4.2, +26.5) | 88% | +1.7 dB |
| spatial_diversity | +20.5 dB (+8.3, +26.5) | 95% | +19.7 dB |
| channel_switch+spatial_diversity | +1.0 dB (+0.2, +3.0) | 0% | +1.7 dB |

At 725a2f1 the same cell read +14.4 dB (p10 +2.0) at no_action.

### Tests

- **Targeted tests while working**, all passing:
  - `test_mmse_predict_search` (new): a synthetic fractional arrival 2 symbols off at Eb/N0 -3 dB,
    and a 30 dB tone with the receiver 3 pilot alias steps off. The 725a2f1 predictor fails both
    parts on the same frames: 7/12 arrivals, 0/12 frequencies.
  - `test_latency_times_predictor` (new).
  - `test_mmse_predict_known_symbols`, with the delay-line clean case over the pools' draws
    (300 s).
  - `test_policy_mmse_pred`, `test_params_written_by_init_only`, `test_latency_load_logged` and
    `test_m_files_parse`.
- **Full suite.** `runtests('code/tests/test_core.m')` from the worktree root at `bf32b5e`, one
  MATLAB batch: **174/174 passed** (40.8 min).

## Sources

- J. H. Winters, J. Salz, R. D. Gitlin, "The impact of antenna diversity on the capacity of
  wireless communication systems," IEEE Trans. Commun. 42(2/3/4), 1994: optimum combining by
  direct matrix inversion, w = R^-1 r from the snapshots' sample covariance and their correlation
  with a known reference (eqs. 19-23, p. 1745); the theory column of V13.
- Reed-Mallett-Brennan sample-support loss, mean (K - N + 2)/(K + 1), as restated in O. Besson,
  arXiv:2102.01421 (2021), eqs. 19-21 (`docs/v7_research_notes/adaptive_array_nulling_limits.md`).
- The receiver's frequency window: IEEE 802.11's +-25 ppm oscillator tolerance per radio
  (`init_params.m` `cfo_ppm`), as `build_threat_model.m` searches it.

## Deployment steps for the main session

1. Merge `d89-mmse` into `v7-merge` and run the full suite on the merge. Then bring it into the
   profile worktrees, before C1p, the same way as d88.
2. `MODEL_TAG` is now `v7-D89`, because the pools' `mmse_pred` values change, so no C1p
   checkpoint built with the d88 predictor is reused. After C1p, check that `PP.model_tag` is
   `v7-D89`.
3. Before C1p, run `validate_phy('V13')` on each profile (about 15 min) and require
   'V13 predicted MMSE gain: N/N rows -> PASS' in `results/phy_validation_v13.txt`. The tables
   above were measured on copies of both profiles' current `params.mat`.
4. Rerun LAT after C2 as planned. KPI 7 now includes the predictor.
