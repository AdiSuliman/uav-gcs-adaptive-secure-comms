# d91: value-neutral speedups of the pool stages (branch d91-speed)

Branch `d91-speed` from `d90-loop` (`2cbe559`). It holds two speedups for profiles 3 and 2. Profile 1's live
run is not touched. Both speedups keep every pool value and every checkpoint key bit-identical:

1. **FEC twins share their run.** Each pool stage flies all 36 configurations through `pool_cell.m`:
   C1p (`build_policy_pools.m`), C1c (`build_check_pools.m`, `build_clean_test_pools.m`), SURV
   (`map_survivability_boundary.m`) and SURV3 (`experiment_survivability_options.m`). A configuration
   that differs from an earlier one in `p.fec` alone no longer gets a simulation of its own. Only its
   ground truth and CRC are computed again, from the same run.
2. **The longest job goes first, one job per free worker.** The same five stages sort their jobs
   by an estimated cost, longest first. `pool_lpt.m` submits every job as a future of its own
   (`parfeval`) in that order and collects them with `fetchNext`. The pool's queue is first in,
   first out, so a free worker always takes the longest job left. The job bodies are the old
   parfor bodies, moved unchanged to `pool_job.m`, and each cell is still saved under its own
   index. A parfor loop does not promise the order in which it hands out its ranges, even with
   one iteration per range. That is why the stages no longer use parfor for these loops.

Nothing here changes the link model, the detector, the geometries, the seeds or the keys
(`pool_checkpoint('key', ...)` holds no code version). A cell that is already on disk stays valid,
and a cell built with this code equals the one the old code builds.

## 1. What changed

| File | Change |
|---|---|
| `code/link/closed_loop_truth.m` (new) | The ground truth and CRC block of `extract_closed_loop_frames.m`, moved out unchanged: `[ber, fer, crc_fail] = closed_loop_truth(T, p)`. With `p.fec` it decodes the packets (`fec_packets.m`, which has its own `RandStream`, seed 11); without it, it uses each frame's own bits. It is now the only code that reads `p.fec`. |
| `code/link/extract_closed_loop_frames.m` | Calls `closed_loop_truth.m` and returns its inputs as a second output `T`: aligned bits, antenna-1 samples, combiner output, delay, frame count, erase flags. `F` is unchanged. |
| `code/decision/pool_configs.m` (new) | The configurations of one cell. `map` is the first configuration with identical physics, as `pool_cell.m` had before (same key: `jsonencode(p)` and the Eb/N0 offset). `twin` is the first configuration whose physics equals it apart from `p.fec`: the same key with `fec` removed. |
| `code/decision/pool_cell.m` | One simulation per twin group. The group's first configuration is simulated and extracted as before. For every other member, `closed_loop_truth(T, its own p)` replaces `ber`, `fer` and `crc_fail`, and `add_run` runs for each member separately, so `link_features` and the detector see that member's own CRC and loss. `info.n_unique` and `info.map` keep their meaning: configurations with distinct physics, `p.fec` included. Twins are never aliased in `map`. |
| `code/decision/pool_cost.m` (new) | Estimated cost of a job: runs (twin groups) x frames x (1.75 + 1.15 x emitters) / 20 s. The rates are the C1p timing from the analysis. The cost only orders the jobs. |
| `code/decision/pool_schedule.m` (new) | `order = pool_schedule(w)`: the jobs by cost, descending. `sort` is stable, so equal costs keep their order. |
| `code/decision/pool_lpt.m` (new) | `out = pool_lpt(fn, S, jobs, pl)`: `out{i} = fn(S, jobs(i))`. Without a pool (SMOKE, `pl = []`) the jobs run on the client, in that order. On a pool, every job becomes one `parfeval` future, submitted in that order and collected with `fetchNext`. `S` reaches each worker once, as a `parallel.pool.Constant`, the way a parfor broadcast variable does. Each job's printed lines (`Diary`) are printed when the job ends. An error cancels the jobs that are not done, as a parfor error does. |
| `code/decision/pool_job.m` (new) | The five loop bodies (`c1p`, `c1c`, `clean`, `surv`, `surv3`), moved unchanged. The only differences are `S.` in front of the stage's variables, and the job arriving as an argument rather than through `todo(k)` or `ord(k)`. The pool builders save each cell under its own index `c`, as before. The survivability stages return their results. |
| `build_policy_pools.m`, `build_check_pools.m` | `todo` is sorted longest first. `S` holds exactly the variables the body reads. `pool_lpt(@(S, c) pool_job('c1p', S, c), S, todo, pl)` (or `'c1c'`). |
| `build_clean_test_pools.m` | Its chunks are equal, so they keep their order, one per free worker. |
| `map_survivability_boundary.m`, `experiment_survivability_options.m` | The jobs run longest first. `res(ord) = res` puts the results back in job order, and they are unpacked into `resB/resF/resS` or `rec/best` as before. SURV3's two clean references keep their two-iteration parfor. |
| `code/tests/test_core.m` | Four new tests (section 4). `test_pool_schedule` checks four things: the order; `pool_lpt`'s serial path (results by place, jobs run in the given order); that no stage still has the parfor loop; and that every `S.` field a body reads is set by its stage, and no others. `test_pool_checkpoint_resume` checks the new call. |
| `code/dev/dev_d91_*.m` | The proofs and the profile (sections 4 and 5). `dev_d91_code.m` prints `D91CODE <sha>` from `D91_SHA.txt`. `dev_d91_tick.m` is the timed job of proof P. |

The bodies were compared line by line with the old parfor bodies, using the `S.` prefix and
the job line as the only expected difference. The result: identical.

**Not done: caching `spec_image` across the twins of one run.** The input `F.iq{v}` is the same
for the twins. But a reused image is bit-identical to a recomputed one only if `spec_image` (an
FFT through MKL) is reproducible call to call in the same process. That cannot be shown without a
run. The gain is also below about 1-2% of a stage: `spec_image` is part of the detector's 3-5 ms
per frame, against 90-140 ms per frame for the run, and only on the fec configurations. It is left
as a candidate in section 5.

## 2. Evidence: only the ground truth reads p.fec

`apply_countermeasure.m` 'fec_interleave' does only `p.fec = true`; its Eb/N0 gain is 0. `git grep` of
`\.fec\b|'fec'` over `code/` without comments, at `9b5c9f1` (the code of the running campaign):

```
code/link/apply_countermeasure.m:143:        p.fec = true;
code/link/extract_closed_loop_frames.m:187:if isfield(p, 'fec') && p.fec
code/dev/dev_agc_clip.m:40, code/dev/dev_fec_flights.m:32     q.fec = false   (dev scripts)
code/gui/viz3d/v3d_player.m:76, v3d_scene.m:145-146           V.fec           (another struct, GUI)
code/tests/test_core.m:2295                                   q.fec = true    (a test)
```

On this branch, line 187 has moved to `closed_loop_truth.m:10`. `pool_configs.m:36` removes the field
for the run's key.

The rest of the run path never reads the struct as a whole:
- There is no `fieldnames(p)`, `struct2cell(p)` or `getfield` over params anywhere in `code/`.
- `jsonencode(p)` appears only in the pool key and in `params_id.m`. `params_id.m` is used by
  `result_status.m` and `validate_phy.m`, not in the pool path.
- `build_threat_model.m` writes only named fields into its blocks' UserData. `set_link_snr.m` reads
  `p.sps` and the thermal floor.
- `link_seed.m`, `flight_draws.m`, `idle_rssi.m` and `mmse_predict.m` take no `fec`.

So a configuration and its twin build the same model, set the same level and fly the same seeds,
and their runs are the same. Inside `extract_closed_loop_frames.m`, no field other than `ber`, `fer`
and `crc_fail` depends on `p.fec`, and nothing later in the function reads those three.

Within `pool_cell.m`, the twin's `p` enters only through quantities that do not depend on `p.fec`:
`thermal_nv`, the SNR, `link_loss_db` and `received_ebno`.

`test_fec_twin_configs` turns the grep into a regression guard. It fails if any file of `code/`
outside `legacy/`, `dev/`, `tests/` and `gui/` reads `.fec` or `'fec'` other than
`apply_countermeasure.m`, `closed_loop_truth.m` and `pool_configs.m`.

**Why the global random stream does not matter.** Fewer simulations mean fewer model builds, so the
worker's global stream is drawn from less often. The stream is used only for the build seed
(`build_threat_model.m` line 217, `randi` when `p.seed` is empty, as in `pool_cell.m`).
- That seed reaches only `link_seed(modelName, seed, p.fd_max)` at build time.
- `pool_cell.m` then calls `link_seed` for every flight, which sets everything the build-time call
  set:
  - 'Seed', from which the channel, threat (+7), AWGN (+1) and bit source (+2) seed themselves;
  - every block whose draw is on, under the same switch conditions (Kfac's extra condition is a
    finite `geo.k_sig_db`, which the build-time call never has);
  - 'GCS', 'Att', 'Body', 'Gate', 'Tdl', 'Cap' and 'Cal', unconditionally.
- The threat block seeds its own generator, `rng(seed + 7)`, before any persistent initializer that
  draws (for example `hit_ant`).

The same argument covers the order of the jobs and the worker each one runs on. Proof (c) tests it.

## 3. Expected gains

- **FEC twins.** Every budget group {none, fec_interleave} and {power_control,
  power_control+fec_interleave} becomes one run, so 6 budget variants per (frequency, space) choice
  need 4 runs instead of 6. That is about x0.67 on the runs. The detector scoring and `add_run` still
  run per configuration (about 3-5 ms per frame, against about 90-140 ms per frame for the run), so
  the stage time comes to about **x0.69-0.73** on C1p, C1c's pools, SURV and SURV3. The analysis
  estimated about -45 h on profile 3's C1p and about -37 h on profile 2's. Job `static` prints the
  exact run counts before and after, per array, weighted by the emitter cost.
- **One job per free worker, longest first.** With MATLAB's default range partitioning, a worker takes
  several cells at once. The verifier's makespan simulation (`c1p_slow/verify/chunks.py`) put
  profile 1's C1p at 160-164 h (median, chunks of 3-4) against 148-150 h for one cell per hand-out.
  The longest-first order also moves the 6-16 h combinations, which sit at the end of the index
  order, to the start. Estimated gain: **about 10-25 h per profile** before the FEC sharing, and
  roughly 7-17 h after it.
- **Together**, profile 3's C1p is estimated at about 169 h -> 105-115 h, and profile 2's at about
  135 h -> 85-95 h. These are estimates from the analysis's cost model, not measurements.

## 4. Proofs (bit-identity)

All proofs run in the detached queue (section 6). They use scratch exports (`git archive`) of `9b5c9f1`
(old) and of this branch (new). The detector is profile 1's B3m smoke detector
(`uav-gcs-b3m-p1/data`), copied once to the scratch folder. It has the same feature count as
`link_features.m`. Without it the proofs run with `det = []`, the log says so, and (b) and (c) read
PARTIAL instead of PASS.

Every proof line ends with `D91CODE <sha>`, the commit of the code it ran. `dev_d91_code.m` reads
it from `D91_SHA.txt` at the root of the queue's export, written at a swap. Without that file it
reads `code/dev/d91_sha.txt`, which `git archive` fills with the exported commit (`export-subst`
in `code/dev/.gitattributes`). So every export names its own commit, with no manual step.

- **(a) Static** (`dev_d91_fec_static.m`, no simulation). It covers 2, 3 and 4 antennas and every cell
  of the pool stages: the clean link, 10 single threats x 5 levels, 14 combinations x 3 levels, and
  the 10 x 8 dataset levels of SURV and C1c. For each of the 12 fec_interleave configurations it
  checks four things:
  - `isequal(rmfield(p_fec, 'fec'), p_twin)`;
  - the same `jsonencode`, i.e. the same key, so the sharing actually happens;
  - an equal Eb/N0 offset;
  - the run it takes is its twin's.

  Expected: `D91PROOF A_static PASS`.
- **(b) Old against new on simulations** (`dev_d91_pool_run.m`, `dev_d91_compare.m`). Each commit's
  own `pool_cell.m` is run on the same inputs:
  - 1 Eb/N0 (the middle of the grid) x 2 train flights;
  - {no_action, fec_interleave, power_control, power_control+fec_interleave};
  - four cells at the nominal level: the clean link, jamming, airframe shadowing on two flights of
    its own that roll in (38 frames, event at frame 11, selected by `hides_antenna.m` as C1p selects
    them) and spoofing+noise_burst (two emitters, with sync loss and erasures in the coded path).

  It checks `isequaln` on every field of every pool (probs, maha, feat, gant, ber, fer, crc, run,
  aoa, act, act_comp, ebno_rx, idle, act_idle, bch, mmse_pred) and on `info.map` and `n_unique`.

  A twin's own CRC and loss reach an input only through `link_features` over the temporal window
  and the detector's scores, and `add_run` computes those only with a detector. So PASS needs
  three things:
  - the detector on both sides (`has_det` 1);
  - every pool holding `feat` and `probs` rows for every frame;
  - all values identical.

  Identical values without the detector path read `PARTIAL`, which does not count as a pass.
  Different values read `FAIL`, and the job stops. Expected:
  `D91PROOF B_old_vs_new PASS (detector 1, features and scores on every frame 1)`.
- **(c) Order and stream independence** (`dev_d91_order.m`). The reduced cells run twice in one
  process: in index order after `rng(1)`, then in the stage's longest-first order (reversed if that
  equals the index order) after `rng(99)`. Both results are compared with `isequaln`, and the first
  is compared with (b)'s new result. A worker runs whatever cells it is handed, in a process with
  whatever stream state it has, so this also covers the worker count. Both need the detector, as
  in (b). Expected: `D91PROOF C_order PASS` and `D91PROOF C_vs_B PASS`.
- **(P) Order on a real pool** (`dev_d91_parfor_options.m`, kept under its old name). It runs 8 jobs
  of known length (`dev_d91_tick.m`: 0.2-1.0 s; each records its start time, `posixtime`, and its
  process id) through `pool_lpt.m` in `pool_schedule.m`'s order, `[2 4 6 3 8 5 1 7]`. It does this
  three times: on the client; on one worker; then on two workers. Each pool uses its own job
  storage, so no other session's pool is touched. It checks:
  - with one worker, the jobs start exactly in that order;
  - with two, every job starts after all jobs two or more places before it, and both workers are
    used;
  - every result comes back at its place, and `res(ord) = res` puts the results back in job order.

  Expected: `D91PROOF P_parfor PASS` (the client and one worker) and `D91PROOF P_order2 PASS`. If
  the two-worker pool cannot start, that line reads `SKIPPED`.
- **Tests.** Job `static` runs the focused tests: `test_fec_twin_configs`, `test_closed_loop_truth`
  (one run extracted with and without `p.fec`: all other fields equal, and `closed_loop_truth`
  reproduces both truths), `test_pool_cell_fec_twins` (each configuration shared equals the same
  configuration simulated alone), `test_pool_schedule` (also `pool_lpt`'s serial path and the
  fields of every stage's `S`), `test_pool_checkpoint_resume` and
  `test_m_files_parse`. Job `tests` runs the full `test_core` last. Expected:
  `V7TESTS n/n` in both.

**Proof of `pool_job.m` at full size.** The queue's proofs run `pool_cell.m`, not the stage
scripts. The moved bodies are checked in three ways:
- the line-by-line comparison in section 1;
- `test_pool_schedule`'s check of every `S` field;
- the first stage that runs them, P3's C1p. Its log shows the same `cell n/N ...` lines, and its
  cells resume from `data/c1p_cells` as before.

**Proof (b2), after profile 1's C1p** (manual; not in the queue). Rerun one or two geometries of one
profile 1 cell's fec configurations on this code and compare them with the stored rows. Profile 1's
cells are built by the old code, so this checks the full-size path.

## 5. Profile (step 5)

`dev_d91_profile.m` runs the clean link and jamming at the nominal level, no_action, the middle
Eb/N0 and the same 3 train flights, on one core:

1. **Stage times without a profiler** (mean per 20-frame run): `link_seed`, `sim`,
   `extract_closed_loop_frames`, `idle_rssi` and `mmse_predict` timed again on their own, and
   `add_run`'s detector part. The difference between jamming and clean is the cost of one emitter;
   the analysis left 0.5-0.7 s of it unexplained.
2. **Jamming under profilers.** The MATLAB profiler gives the top 30 functions by self time. The
   Simulink profiler (`set_param(model, 'Profile', 'on')`) gives the top 25 blocks by self time and
   their sums over threat, channel, receiver, transmitter, sinks, AWGN, bit source and other. The
   MATLAB Function blocks run as compiled code, so only the Simulink profiler splits the time inside
   `sim`.

Output: `v7_d91_speed_profile.log` and `res/profile.mat`. The results were not available when this
note was written. Read them from the log.

**Further value-neutral candidates**, to rank once the profile has run. Each is listed with its
bit-identity argument; none is implemented here.

- **`idle_rssi` once per (flight, MRC/MMSE twin).** `spatial_diversity` changes only
  `p.rx_combiner`. Proof needed: grep `idle_rssi.m`, `idle_context.m` and the threat block's
  schedule recording for any read of `rx_combiner` or of a receiver output. If there is none, the
  idle RSSI of the MMSE twin equals the MRC run's and can be reused. That is about 0.26-0.31 s per
  emitter run on half the configurations. It needs the same old-vs-new `isequaln` as proof (b).
- **No `Tx_IQ` logging in the pool path.** `extract_closed_loop_frames.m` never reads `Tx_IQ`. A
  To Workspace sink feeds nothing back into the model, so removing it changes no other output. The
  GUI may read it, so this would be switched off only in pool runs. The gain is under 2%.
- **`spec_image` once per frame across the twins of a run** (section 1). This would be bit-identical
  only if `spec_image` is reproducible call to call. Check that first with `isequal` over repeated
  calls on a worker. Then run the same old-vs-new `isequaln` as proof (b). The gain is about 1-2%.
- **A seventh worker when nothing else runs.** No value changes (section 2, proof (c)). It costs
  4.6 GB of commit per worker and gives 10-14% off C1p.
- **Not value-neutral, so excluded:** GPU scoring; reordered or vectorized sums in `idle_rssi`
  (rounding); one run feeding both combiners (a model change).

## 6. The queue (machine budget)

The queue is `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_speed_proofs.sh <SHA>`. It runs detached
through a hidden WMI launch, and its gate is `v7_d91_speed_gate.ps1`. It runs one MATLAB job at a
time, with `-singleCompThread` and its own TEMP. It starts a job only when:
- commit has at least 35 GB free;
- at most one other non-pipeline MATLAB is running, busy or idle. A side job that waits (for the
  parallel turn, in a sleep, on I/O) still counts, because it will run again. Not counted:
  - pipeline sessions (`run_stage(` and PID 42560) and their parallelserver workers;
  - processes that have exited (`HasExited`), such as the zombie 32824, which is still listed by
    Win32_Process.

The gate is checked every 10 min, and a job is given up after 24 h of waiting.

The queue works only in scratch exports (`scratchpad/d91_speed/old`, `new`). It never takes the
parallel turn, never touches a live worktree, log, `run.lock` or the turn file, and sends no
signals.

Jobs, in order:

| Job | Contents |
|---|---|
| `static` | Copies the detector, runs (a) and the focused tests. |
| `oldpool` | The old side of (b). |
| `newpool` | The new side of (b), then the comparison. |
| `order` | (c). |
| `parfor` | Proof (P): the order on a client, a one-worker pool and a two-worker pool. |
| `profile` | Section 5. |
| `tests` | The full `test_core`. |

Logs: `uav-gcs-logs\v7_d91_speed_<job>.log` and `v7_d91_speed_queue.log`. Every `D91PROOF`,
`V7TESTS` and run-count line ends up in `v7_d91_speed_summary.log`. A second launch is refused while
`v7_d91_speed.lock.d` exists; remove that folder after a reboot.

The summary's header names the SHA the queue was started with. The code a proof actually ran is
the `D91CODE` at the end of its line. They differ after a swap (below).

**Swap of 18.10, 13:55.** The queue was started at 13:27 with `f06a260` (bash PID 5628). At
13:55:24, while its first job `static` was still waiting, its exports were moved onto `70f69f4`
(the review fixes). The queue was not stopped. The steps:
1. Checked that the log's last line was a WAIT of `static`, that no job had started, and that no
   MATLAB of the queue was alive.
2. Exported into `new.tmp_<time>`, with `D91_SHA.txt` holding the full SHA, and copied the
   drivers to `drv.tmp_<time>`.
3. Checked again, then renamed `new`/`drv` to `*.old_f06a260_<time>` and the temporary folders to
   `new`/`drv`.
4. Installed the new gate.
5. Checked a third time and appended a `SWAP` line to the queue log.

The queue's commands are fixed strings: driver names, arguments and the focused test names. The
new code keeps all of them, so its jobs run the new code unchanged. The `old` export (`9b5c9f1`)
is untouched. The summary's header still reads `new f06a260`; the `D91CODE 70f69f4...` on each
proof line is what ran.

**A second run** (needed when the code changes after the first job has started, since the lock
allows one queue at a time):
1. Wait for `queue done` in `v7_d91_speed_queue.log`. The lock folder is then gone.
2. Move the first run's `v7_d91_speed_<job>.log` and `_summary.log` aside, for example to
   `v7_d91_speed_run1_<job>.log`. Each job log is appended to, not replaced.
3. Start it as in the script's header (hidden WMI launch) with the new SHA. The script re-exports
   `new` and the drivers, and keeps `old`. The new export names its commit itself
   (`d91_sha.txt`, section 4), so `D91CODE` needs no manual step.

## 7. How to merge

**Preconditions** (both targets):
- every `D91PROOF` line reads PASS: A_static, B_old_vs_new, C_order, C_vs_B and P_parfor;
  P_order2 reads PASS or SKIPPED;
- B_old_vs_new, C_order and C_vs_B read `detector 1, features and scores on every frame 1`
  (`has_det == 1`). A PARTIAL is not a pass;
- every `D91CODE` is the commit being cherry-picked, or one whose later commits change only `docs/`;
- the profile has run;
- the full `test_core` on the merged tree and on the target's tip (below) shows no merge regression.

**Which run says what.** d91-speed branches from `2cbe559` (d90-loop), so `2cbe559` is the baseline
for attributing a failure to d91. `9b5c9f1` is not: `9b5c9f1..2cbe559` holds the three d90 commits
(52 files, 488 lines of `test_core.m`), so a comparison against it blames d90 on d91. The
`old` job of `v7_d91_tests2.sh` (bash 23720) still runs `9b5c9f1`; it was already queued, and a
running bash queue is not edited. Its result is context only. The comparisons that count come from
the second queue.

**The second queue: `uav-gcs-logs\v7_d91_tests3.sh 74ca87c 686fd11`** (bash 43464, started 18.10
18:36; copy in `docs/d91_speed_tests3.sh.txt`). It starts no job while `v7_d91_tests2.lock.d`
exists, then runs four full `test_core` jobs with the same gate, `-singleCompThread`, and the
same short TEMP `C:\Users\Adi Suliman\d91q\s3\tmp`, in git archive exports under `d91q\s3`
(each with `D91_SHA.txt`):

| Job | Commit | What it is |
|---|---|---|
| `merge` | `686fd11` | the merge candidate: `2cbe559..74ca87c` cherry-picked onto the v7-p3 tip (branch `d91-speed-on-v7-p3`) |
| `tip` | `29510e7` | the v7-p3 tip |
| `new` | `74ca87c` | the d91-speed tip |
| `base` | `2cbe559` | d91-speed's parent |

The candidate was built without a worktree: one `git merge-tree --write-tree --merge-base C^ H C`
plus `git commit-tree` per d91 commit, each keeping its author and message. Its tree `3460910` equals
`git merge-tree --write-tree --merge-base 2cbe559 29510e7 74ca87c`, and `git diff --stat 29510e7
686fd11` equals `git diff --stat 2cbe559 74ca87c` (27 files, +1309/-110). The commits after
`74ca87c` change `docs/` only.

Each job prints every test of the suite before the run (`V7SUITE`) and every outcome after it
(`V7RESULT PASS|FAIL|INCOMPLETE`). The summary `v7_d91_tests3_summary.log` compares two pairs by
test name:
- `attribution` = `new` vs `base`; `fail-new-only` is a d91 regression;
- `merge` = `merge` vs `tip`; `fail-new-only` (fails on the merged tree, passes on the tip) is a
  merge regression, and the only one.

The categories are `fail-both`, `fail-new-only`, `fail-old-only`, `new-test` (absent from the
older suite, listed when it does not pass, counted when it does), `removed-test` and `not-run`
(listed but without an outcome). Each MATLAB is bounded by `timeout -k 10m 6h`. rc 124 or 137 is
written as `V7TIMEOUT` and reported as TIMEOUT, and that pair's outcomes are incomplete. A full run
takes about 1.5 h (the first queue's `new` job was at 103 of 196 tests after 37 min).
The limit kills `bin\matlab.exe`; if its `win64\MATLAB.exe` outlives it, the
gate counts it, and the next job waits.

`test_core` itself now stops with an `ENVIRONMENT, not code` message when its work folder (long
path name) has more than 150 characters. Stateflow writes build files about 75-110 characters
below it, and the long scratch TEMP gave 29 false failures (260-character limit).

**Merge only when** the `merge` pair has no `fail-new-only`, `not-run`, failing `new-test` or
TIMEOUT. A `fail-both` there is the target's own state and is reported, not fixed in d91. The
`attribution` pair explains any d91 failure but does not replace the merge pair. After the
cherry-pick, `git rev-parse HEAD^{tree}` in the live tree must equal the tested tree (`3460910`,
or a tree that differs from it in `docs/` only), so that what was tested is what is pushed. The
exports run on the target's own `profile.json`, which gives P3 four antennas and P2 two.

For a target other than `29510e7` (a newer v7-p3 tip, or v7-p2), build the candidate the same
way, outside every live tree, and rerun the `merge`/`tip` pair:

```
R="/c/Users/Adi Suliman/uav-gcs-d91-speed"; git -C "$R" fetch origin
H=$(git -C "$R" rev-parse origin/v7-p3)                    # origin/v7-p2 for profile 2
for c in $(git -C "$R" rev-list --reverse 2cbe559..d91-speed); do
  T=$(git -C "$R" merge-tree --write-tree --merge-base "$c^" "$H" "$c") || { echo CONFLICT $c; break; }
  H=$(git -C "$R" commit-tree "$T" -p "$H" -m "$(git -C "$R" log -1 --format=%B $c)")
done; echo "candidate $H, tree $T"
```

Then start `v7_d91_tests3.sh` with that tip in place of `TIP` (or a copy with the new SHAs) and
the candidate. The d91 commits cherry-pick cleanly onto `v7-p3` and onto `v7-dev`; cherry-pick the
d91 commits only (`git cherry-pick 2cbe559..d91-speed`), not the whole branch, which also carries
d90.

**Into v7-p3, while profile 3 waits for profile 1's SURV3 (before about 25.10):**
1. Check that no MATLAB runs in `uav-gcs-v7-p3`. Use a process query, and check `takeover_ml_p3.pid`.
   On 18.10 the side jobs were running elsewhere: `m_all('p3')` in `scratchpad/d91_fuse` and set4 in
   `uav-gcs-set4-p3`. Also check that p3.log's current part has not started C1p. To be safe, write
   `p3_c1p.hold` first.
2. Read `v7_d91_tests3_summary.log` (above). If `origin/v7-p3` has moved past `29510e7`, rerun the
   `merge`/`tip` pair on the new tip first.
3. In `uav-gcs-v7-p3` on `v7-p3`: `git cherry-pick 2cbe559..d91-speed`, then `git status` (it must
   be clean), then check that `git rev-parse HEAD^{tree}` equals the tested tree, then `git push`.
4. Remove `p3_c1p.hold`. Before C1p the takeover checks the branch, that no merge is in progress and
   that there are no uncommitted changes. It does not check the commit's SHA.

**For profile 2:**
- **Preferred window, made certain by an early hold.** Write `uav-gcs-logs\v7_d86\p2_c1p.hold`
  before profile 1's chain ends. At the latest, write it as soon as the takeover has created
  `v7-p2`. Without the hold, if profile 3 is already past SURV3 when profile 2's B4s ends, the
  takeover sends profile 2 from B4s straight into C1p, with no idle gap. Its C1p would then run the
  old code, or a cherry-pick would land under a live stage.

  With the hold, profile 2 stops before C1p once its B stages are done. Then:
  1. Check that no MATLAB runs in `uav-gcs-v7-p2`: no process whose command line or working folder
     is that tree, and p2.log's current part waiting before C1p. Its B stages (A4v and A5 call
     `extract_closed_loop_frames.m`) must have ended.
  2. Build the candidate for `origin/v7-p2` (above) and run the `merge`/`tip` pair on it.
  3. Cherry-pick in `uav-gcs-v7-p2`, check that the status is clean and that the tree equals the
     tested tree, then push.
  4. Remove the hold.
- **The task's alternative: into `v7-dev` after profile 1's SURV3**, so that `v7-p2` inherits it.
  `uav-gcs-v7` is profile 1's live tree, and past-bugs item 13 says never to merge under a stage the
  change touches. A merge there is acceptable only while profile 1's current stage calls none of
  the changed files. The callers of `pool_cell.m` and `extract_closed_loop_frames.m` are:
  - C1p, C1c, SURV and SURV3;
  - A4v/A5 (`validate_phy`, `run_dataset_sweep`);
  - GAL (`threat_gallery`) and LAT (`measure_latency`);
  - `detector_block.m` and the GUI.

  That leaves C1d, C2, C2e, C2g or C2u as the window. GAL and LAT afterwards would run the new
  `extract_closed_loop_frames.m`, whose `F` is bit-identical. If no such window is certain, use the
  preferred window.
- **Record it in `v7-dev` for history** once profile 1's chain has ended and before the final phase
  starts LAT, KPI and the others in `uav-gcs-v7`, when no MATLAB runs there.

**Never** into `uav-gcs-v7` while profile 1 is in C1p, C1c, SURV or SURV3. P1's cells are built by
the old code, and the code is equal in value, but its MATLAB and workers read changed `.m` files
live.
