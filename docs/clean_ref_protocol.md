# Clean-link reference from the validation clean pools: pre-registered protocol

Written 24.10.2026, before profile 1's C1d has run and before any reading of the new table.
Code: `code/decision/clean_ref_rebuild.m`; tests `test_clean_ref_rebuild` and
`test_clean_ref_in_c1c` (`code/tests/test_core.m`).

## 1. The defect

The decision layer reads one clean-link table per Eb/N0, written by C1p
(`build_policy_pools.m`). That table is the mean over the clean cell's own train flights:
`NGEO(1) = 8` simple random flights per Eb/N0 (`LHS(1) = false`). Each Eb/N0 point draws its
own 8 flights (`pool_seed.m`). The per-flight clean BER is heavy-tailed: bank angle up to
57.3 deg in the train split, attitude and polarisation loss, and Rician K from -5 to 20 dB
per flight. With 8 flights, the mean depends on whether a tail flight was drawn.

Profile 1's logs (`uav-gcs-logs/v7_d86/p1.log`) show the effect. The receiver, the Eb/N0
definition, the frames per flight and the features are the same in both lines (`pool_cell.m`):

| Source | 0 | 1.5 | 3 | 4.5 | 6 | 7.5 | 9 | 10.5 | 12 | 13.5 | 15 dB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| C1p, 8 train flights (line 7904) | 7.1e-2 | | 1.9e-2 | | 1.0e-2 | | **2.4e-5** | | 1.2e-5 | | 0 |
| C1c check pools, 36 LHS flights (line 11440) | | 3.0e-2 | | 9.9e-3 | | 2.2e-3 | **2.0e-3** | 5.9e-4 | | 1.1e-4 | |

The check pools stratify speed, altitude, K, the first interferer direction and the receive
correlation, but not bank angle or attitude. So their own 36-flight values are noisy too.

Readers of the table:
- `clean_ref.ber_est` and `clean_ref.plr_fec`: the monitor's degradation alarm
  (`policy_monitor.m` through `clean_ber_ref.m`). Every policy rollout uses it: C1d's
  whole-monitor false-alarm bound, C2, C2e (KPI 6), C2g, C2u, EDGE and CORE_BW.
- `PP.clean` and `PP.clean_fer`: the `'mean'` restoration reference of `link_env.m`. It feeds
  the reward, `healthy`, `restored` and `restored_plr`, and the goodput normalisation. It is
  used for C2 training and validation, KPI 4 in C2e, C2g and C2u.
- EDGE's restoration uses the same flight's clean link (`'flight'`). Its monitor still reads
  `ber_est`.
- `clean_ref.ber`, `.plr` and `.fer` are printed only.

Both readers floor the reference at 1e-4 (`C.ber_floor`, `C.deg_floor`). At 9 dB the 8-flight
value therefore gives a restoration and degradation threshold of 2 x 1e-4. A
population value near 2e-3 would give about 4e-3. At 15 dB the floor rules either way.

## 2. The change

`clean_ref_rebuild` computes every field the code reads from `data/clean_val_pools.mat`:
- `ber`, `fer`, `ber_est`, `plr` (no_action) and `plr_fec` (fec_interleave);
- `PP.clean = ber` and `PP.clean_fer = fer`.

The source is 300 independent flights per grid Eb/N0, built by C1c (seed block 4: families 1,
3 and 5, 100 flights each; `clean_pool_seed.m`). Each field is the frame mean, as C1p
computes it. Every flight has the same 20 frames, so the frame mean equals the flight mean.

Saved beside the table in `clean_ref`, and printed:
- `ci`: the 95% percentile interval from 2000 resamples of flights with replacement (the
  flight is the independent unit), with a fixed seed per Eb/N0;
- `n_flights`, `source` (file, set, block, run range, build time);
- `jackknife`: the largest relative change when one geometry family is left out;
- `tail`: the median flight BER and the largest single flight's share of the mean;
- `train`: the C1p table it replaces.

The step also writes `results/clean_ref.txt`. No `PP` field is added, so `rekey_pools.m`
accepts the file unchanged. Its `clean_ref` variable passes through a re-key as it is.

## 3. Data rule

- Only the validation clean pools are read. The function refuses any other file name, a set
  other than `'val'`, runs outside block 4 (`401..700`) and a file holding check pools (`CK`).
  The test sets (clean test pools, block 15; test splits; the fourth set) and the check pools
  are never read for this.
- The decision to use this table is made here, before profile 1's C1d and before the table
  is seen. Nothing is tuned on its outcome. The bootstrap seed is fixed, and the check is not
  repeated to obtain another answer.
- Profile 3, and any chain that builds its pools from the start, takes the same table inside
  C1c, after the validation clean pools, the test clean pools and the check pools are built
  (`run_stage.m`, `main.m`: `clean_ref_rebuild('chain')`). Its C1d and every later stage
  read it.

## 4. Pre-registered expectation and decision rule (profile 1)

**Expected at 9 dB:** a mean clean BER of about 1e-3 to 2e-3. The expectation comes from the
check pools' 7.5 / 9 / 10.5 dB values above. **Pre-registered range: 3e-4 to 6e-3.** The C1p
value (2.4e-5) is expected to lie below the new 95% interval.

Descriptive expectations, which are not gates:
- 0 and 3 dB close to C1p (the check pools give about 1.7e-2 at 3 dB against C1p's 1.9e-2);
- 6 dB below C1p's 1.0e-2 (about 4e-3 to 6e-3);
- 12 dB a few 1e-4;
- 15 dB at or below the 1e-4 floor;
- the largest single flight's share of the mean at 9 dB well above 1/300.

**The 1-minute check** (`clean_ref_rebuild('check')`) reads only the validation clean pools and
`clean_ref` of the policy pools, and writes nothing. It prints the table, the intervals, the
table it replaces, the tail summary, the jackknife, and one line:

    VERDICT clean_ref <confirmed|contradicted|stop>: BER at 9 dB ... [lo, hi], pre-registered range 3e-04-6e-03, replaced 2.40e-05, BER rising beyond the intervals: 0|1

| Verdict | Condition | Action |
|---|---|---|
| `confirmed` | new 9 dB mean inside the range, the C1p value outside its interval, no rise | write (step M2) |
| `contradicted` | new 9 dB mean inside the range, the C1p value inside its interval | **write anyway**, and record that the finding's cause (8-flight luck at 9 dB) did not hold. The definition stays the same in both profiles: profile 3's C1c writes this table with no verdict. The tables then agree within their intervals, so the effect is small |
| `stop` | new 9 dB mean outside 3e-4 to 6e-3, or the BER rises with Eb/N0 beyond the intervals | **do not write.** Profile 1 resumes on the C1p table (its frozen definition). Keep the log, and tell Adi. Look into it on validation only: per-flight BER against the flights' draws (`CT.cov`: altitude, K, speed, attitude), and the frames per flight. Never read the test or check pools for it. A later write needs Adi's decision and a note here |

The write mode applies the same rule. On `stop` it raises `clean_ref_rebuild:verdict` and
writes nothing.

## 5. Order and files (profile 1, stop window)

1. After the code is in profile 1's tree (STOP_SOFT I2). The function exists only in the new
   code.
2. **Before** `rekey_pools` (N1) and before C1d (O2, or N2 by hand). Every reader then sees
   one table.
3. The write backs up `data/policy_pools.mat` as `data/policy_pools_before_cleanref_<time>.mat`
   and checks the copy's size. It rewrites the file through `pool_checkpoint('commit')` (a
   temporary file, flushed, then renamed). Its log line `Written to ... file time <new>
   (before: <old>)` records both times.
4. **File time.** `build_check_pools.m` and `build_clean_test_pools.m` rebuild their output
   when it is older than `policy_pools.mat`: about 650 + 120 + 120 min. No frame changes
   here, so the step sets the pools' time back to its old time plus 2 s. It uses the old
   time itself when a dependent file is not newer than that. A later `rekey_pools` saves
   the policy pools first and the C1c files after, which keeps the order. The no-go branch
   runs no re-key, and its order holds through this rule.
5. `clean_ber_ref`'s cache is cleared in the session and on any open parallel pool. In a new
   MATLAB session it is empty anyway.
6. Rollback, only before N1: copy the backup over `data/policy_pools.mat`. Then set its time
   to the logged `before:` time (`touch -d '<before>'`). Then check that the pools file is
   older than `check_pools.mat`, `clean_val_pools.mat` and `clean_test_pools.mat`.

Under plan B (resume on `208602b` without the merged code) there is no step. Profile 1 keeps
the C1p table.

## 6. Known limits and follow-ups

- **In-sample validation readings.**
  - C1d's false-alarm bound (`choose_drop_threshold.m`) and C2's clean-validation
    false-alarm check (`train_dqn.m`) are measured on the same 300 flights that now set the
    reference.
  - One flight carries 1/300 of the mean; a single flight at BER 0.1 adds about 3.3e-4.
  - The printed leave-one-family-out change bounds the effect. Where it exceeds 0.5 at an
    Eb/N0 whose table is above the 1e-4 floor, the C1d and C2 reports state it beside their
    false-alarm numbers.
  - Follow-up: cross-fitted references (a table per family, each flight read against the
    others'). This needs the monitor to know a flight's family. It is not done in this
    stop window.
- **KPI 4 at 9-12 dB becomes more lenient.** This follows from the `'mean'` definition: the
  clean link of the population, not of this flight. EDGE's `'flight'` reading stays beside
  it, and where both exist the report gives both.
- **A table keyed on the measured Eb/N0 (`policy_monitor.m`: `M.ebno_est`, read at the
  receiver's own estimate) is not done.**
  - The validation table fixes the sampling defect on its own.
  - `ebno_est` is the per-frame reference-antenna SINR plus IoT. It moves with fading,
    attitude and the received configuration's gain. A table conditioned on it is a new
    estimator, with binning, smoothing and extrapolation rules.
  - It would also absorb any drop in our own signal: path loss, antenna fault, shadowing.
  - It would change the monitor's operating point after the B-stage rehearsal.
  - Follow-up, on validation only: false alarms and detection delay with the nominal-axis
    table against a measured-axis table, before any adoption.
