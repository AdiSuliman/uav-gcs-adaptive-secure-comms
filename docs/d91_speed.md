# d91: value-neutral speedups of the pool stages (branch d91-speed)

Branch `d91-speed` from `d90-loop` (`2cbe559`). It holds two speedups for profiles 3 and 2. Profile 1's live
run is not touched. Both speedups keep every pool value and every checkpoint key bit-identical:

1. **FEC twins share their run.** Each pool stage flies all 36 configurations through `pool_cell.m`:
   C1p (`build_policy_pools.m`), C1c (`build_check_pools.m`, `build_clean_test_pools.m`), SURV
   (`map_survivability_boundary.m`) and SURV3 (`experiment_survivability_options.m`). A configuration
   that differs from an earlier one in `p.fec` alone no longer gets a simulation of its own. Only its
   ground truth and CRC are computed again, from the same run.
2. **The longest job goes first, one job per hand-out.** The parallel loops of the same five stages
   sort their jobs by an estimated cost, longest first. They hand the jobs to the workers one at a
   time (`parforOptions(pool, 'RangePartitionMethod', 'fixed', 'SubrangeSize', 1)`).

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
| `code/decision/pool_schedule.m` (new) | Returns the order (cost descending; `sort` is stable, so equal costs keep their order) and parfor's options. Without a pool (SMOKE, `NWP = 0`) it returns `0`, so the loop runs serially as before. |
| `build_policy_pools.m`, `build_check_pools.m` | `todo` is sorted longest first; `parfor (k = 1:numel(todo), po)`. |
| `build_clean_test_pools.m` | Its chunks are equal, so only the one-chunk hand-out is applied and the order is kept. |
| `map_survivability_boundary.m`, `experiment_survivability_options.m` | The jobs run longest first, one per hand-out. The sliced results are stored by hand-out index and put back in job order (`resB(ord) = resB`, `rec(ord) = rec`), so the code after the loop reads them as before. |
| `code/tests/test_core.m` | Four new tests (section 4). `test_pool_checkpoint_resume` now checks the new parfor line. |
| `code/dev/dev_d91_*.m` | The proofs and the profile (sections 4 and 5). |

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
- **One job per hand-out, longest first.** With MATLAB's default range partitioning, a worker takes
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
`link_features.m`; without it the proofs run with `det = []`, and the log says so.

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
  Expected: `D91PROOF B_old_vs_new PASS`.
- **(c) Order and stream independence** (`dev_d91_order.m`). The reduced cells run twice in one
  process: in index order after `rng(1)`, then in the stage's longest-first order (reversed if that
  equals the index order) after `rng(99)`. Both results are compared with `isequaln`, and the first
  is compared with (b)'s new result. A worker runs whatever cells it is handed, in a process with
  whatever stream state it has, so this also covers the worker count. Expected:
  `D91PROOF C_order PASS` and `D91PROOF C_vs_B PASS`.
- **Real pool** (`dev_d91_parfor_options.m`). One worker with its own job storage, so no other
  session's pool is touched. It checks that `parforOptions` with `SubrangeSize` 1 runs, that the jobs
  go out longest first, and that the results come back in job order. Expected:
  `D91PROOF P_parfor PASS`.
- **Tests.** Job `static` runs the focused tests: `test_fec_twin_configs`, `test_closed_loop_truth`
  (one run extracted with and without `p.fec`: all other fields equal, and `closed_loop_truth`
  reproduces both truths), `test_pool_cell_fec_twins` (each configuration shared equals the same
  configuration simulated alone), `test_pool_schedule`, `test_pool_checkpoint_resume` and
  `test_m_files_parse`. Job `tests` runs the full `test_core` last. Expected:
  `V7TESTS n/n` in both.

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
- **A seventh worker when nothing else runs.** No value changes (section 2, proof (c)). It costs
  4.6 GB of commit per worker and gives 10-14% off C1p.
- **Not value-neutral, so excluded:** GPU scoring; reordered or vectorized sums in `idle_rssi`
  (rounding); one run feeding both combiners (a model change).

## 6. The queue (machine budget)

The queue is `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_speed_proofs.sh <SHA>`. It runs detached
through a hidden WMI launch, and its gate is `v7_d91_speed_gate.ps1`. It runs one MATLAB job at a
time, with `-singleCompThread` and its own TEMP. It starts a job only when:
- commit has at least 35 GB free;
- at most one other busy non-pipeline MATLAB is running. Pipeline sessions, meaning `run_stage(`
  and PID 42560, and their parallelserver workers are not counted. Neither are idle sessions with
  under 1 s of CPU in 60 s, such as the zombie 32824.

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
| `parfor` | The real-pool check. |
| `profile` | Section 5. |
| `tests` | The full `test_core`. |

Logs: `uav-gcs-logs\v7_d91_speed_<job>.log` and `v7_d91_speed_queue.log`. Every `D91PROOF`,
`V7TESTS` and run-count line ends up in `v7_d91_speed_summary.log`. A second launch is refused while
`v7_d91_speed.lock.d` exists; remove that folder after a reboot.

## 7. How to merge

**Preconditions** (both targets):
- every `D91PROOF` line reads PASS: A_static, B_old_vs_new, C_order, C_vs_B and P_parfor;
- both `V7TESTS` lines read n/n;
- the profile has run.

The d91 commits cherry-pick cleanly onto `v7-p3` and onto `v7-dev`. This was checked with
`git merge-tree --write-tree --merge-base 2cbe559 <target> <d91 commit>`. The result differs from
the target only in the d91 files. Cherry-pick the d91 commits only (`git cherry-pick 2cbe559..d91-speed`),
not the whole branch, which also carries d90.

**Into v7-p3, while profile 3 waits for profile 1's SURV3 (before about 25.10):**
1. Check that no MATLAB runs in `uav-gcs-v7-p3`. Use a process query, and check `takeover_ml_p3.pid`.
   On 18.10 the side jobs were running elsewhere: `m_all('p3')` in `scratchpad/d91_fuse` and set4 in
   `uav-gcs-set4-p3`. Also check that p3.log's current part has not started C1p. To be safe, write
   `p3_c1p.hold` first.
2. In `uav-gcs-v7-p3` on `v7-p3`: `git cherry-pick 2cbe559..d91-speed`, then `git status` (it must
   be clean), then `git push`.
3. Remove `p3_c1p.hold`. Before C1p the takeover checks the branch, that no merge is in progress and
   that there are no uncommitted changes. It does not check the commit's SHA.

**For profile 2:**
- **Preferred window.** After the takeover has branched `v7-p2` from `v7-dev` and profile 2's B4s
  has ended, profile 2 waits idle for profile 3's SURV3. During that wait, write `p2_c1p.hold`,
  cherry-pick into `v7-p2` in `uav-gcs-v7-p2` (clean status, push), then remove the hold.
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
