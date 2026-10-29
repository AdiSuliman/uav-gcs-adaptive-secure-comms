# P1R: profile 1's decision layer with the fixed monitor, pre-registered protocol

Written 26.10.2026, during profile 1's C2, before profile 1's C2e, before any P1R run and before
any data this protocol governs exists. It is committed in DECISIONS as D104 before the smoke and
before P1R's C1d. Basis: D103 part 2, `docs/deg_fix_protocol.md` (the degradation test and its
adoption rule) and the decision of 26.10 on the system-level clean false alarm (our KPI 6).
Code on `lect-kpi`; tests in `code/tests/test_core.m` and `code/tests/test_deg_mode.m`.

## 1. What P1R is

- **The rerun.** C1d with `deg_select`, then C2 and C2e, on profile 1's existing pools. The
  degradation test is chosen at C1d on validation by `deg_adopt.m` (`deg_fix_protocol.md`
  section 3). C2 trains on the adopted monitor.
- **Two kinds of reading.**
  - **KPI 6 (our extension)** is read on a fresh clean test set that no step has read
    (section 4). That reading is P1R's verdict for KPI 6.
  - **Every other C2e reading** (the lecturer KPIs through `lect_kpis.m`, every test-split
    line) reads test pools that profile 1's first C2e has already read. In P1R they are a
    second reading and descriptive only.
- **What it is not.** It changes no pool, no detector, no fusion and no step before C1d.
  CORE_BW's change to the core rule is not part of it: P1R's `blind_core` stays profile 1's.

## 2. Order

1. Profile 1's chain: C2, C2e, then the tail to RPT. Untouched by P1R.
2. CORE_BW (the lecturer's track C).
3. **P1R**, in this order:
   1. Copy the inputs (section 3) and check them with `sha256sum -c`.
   2. C1d with `deg_select`, then its review.
   3. **Stop rule.** If C1d keeps `'ratio'` (no candidate admissible), P1R ends here. The fresh
      set is not built and stays unread for F4, the registered next step. The report says so.
   4. The fresh clean test set (`CLEAN_SET = 'fresh'`), after the adoption and before C2.
   5. C2. Its grid line and the times of its first two runs re-date profile 3 at once.
   6. C2e with `"kpi6_set": "fresh"`.
   7. `system_fa_breakdown` once on P1R's outputs, then the review and the report lines.
4. Profile 3's queue, released after P1R's C2e and its review. Nothing of profile 3 runs
   beside P1R (31.2 GB of physical RAM).

No run is shortened to save time (`no-training-shortcuts`).

## 3. Where it runs and what it reads

- **Worktree.** `C:\Users\Adi Suliman\uav-gcs-v7-p1r`, branch `p1r` from `d4623ed` (profile 1's
  code of record). It takes:
  - the degradation fix `c7fe8f9` and `fcdc199` as cherry-picks;
  - `sysfa` (`4beefb7`) as a merge;
  - the P1R commits of `lect-kpi` as cherry-picks. In `build_clean_test_pools.m` and
    `test_core.m` their context includes `lect-kpi` lines that `d4623ed` does not hold (the
    decoder of the coded link), so those two hunks are applied by hand and the tests rerun.
  The rest of `lect-kpi` and `core-bw-p1` are not taken.
- **Profile 1's tree** (`uav-gcs-v7`) is only read. Its first-chain outputs stay where they are.
- **Runs** go through the gated wrapper only (no `run_stage(`), in the p1 slot through the empty
  `V7G_ROOT` stand-in, one MATLAB at a time at 45 GB.
- **Inputs copied** from profile 1's tree after its RPT, hashed there and checked in P1R:

| File | Read by |
|---|---|
| `params.mat` | every stage |
| `data/policy_pools.mat` | C1d, the fresh build, C2, C2e |
| `data/clean_val_pools.mat` | C1d's fit and check halves, C2's false-alarm filter |
| `data/clean_test_pools.mat` | C2e's union line (descriptive) |
| `data/trained_detector.mat`, `data/fusion.mat`, `data/ood_thresholds.mat` | the detector check of the fresh build |
| `data/splits.mat` | the training z-score of the fresh build (`split_norm.m`) |
| `results/eval_detector_metrics.mat` | the KPI 1 threshold |

`data/drop_threshold.mat` and `data/trained_dqn.mat` are not copied: P1R writes its own.

## 4. The fresh clean test set

- **Seeds.** Geometry families 7, 8 and 9 of seed block 15 (`clean_set_layout.m`), 100
  geometries each, laid out as the clean sets are (`clean_pool_seed.m`). Seeds 1 941 501 to
  1 986 600:
  - no commit has flown these families, and `pool_seed_owner.m` lists them as this set's alone;
  - they are disjoint from every pool, clean-link, check, bandwidth-study, survivability,
    dataset and shadowing seed (`test_seed_streams_disjoint`, `test_band_seeds_disjoint`);
  - they stay below 2 000 000 and 2^26, and their streams below 2^32.
  Blocks 4 and 15 under families 1, 3 and 5 (the clean validation and test sets) are never
  reused: the layout stops on any pair another set owns.
- **Size.** 300 geometries per Eb/N0 point x 6 points (0 to 15 dB, all at or above the KPI 1
  threshold of 0 dB) = **1800 independent clean episodes**, each with its own seed. A one-sided
  95% Clopper-Pearson bound of at most 5% then allows at most 74 false-alarm episodes.
- **Build.** `CLEAN_SET = 'fresh'` in `build_clean_test_pools.m` writes
  `data/clean_fresh_pools.mat` with `CT.set = 'fresh'` and `CT.fams = [7 8 9]`. The recipe is
  the other clean sets' (detector, frames, features, every configuration, the per-flight draws
  kept). The chain's C1c never builds it (`run_stage.m`, `main.m` build 'val' and 'test' only).
- **Generated after adoption.** The build stops unless `data/drop_threshold.mat` holds C1d's
  `DEG` with a candidate adopted (`pick > 0`) and no forced mark (`clean_fresh_guard.m`). The
  smoke skips this check.
- **The smoke flies other seeds.** Under `SMOKE` the fresh build takes families 7-9 of block
  18, the smoke's own block (runs 1801-1804), so no smoke ever flies a fresh-set flight. The
  KPI 6 code of `evaluate_policies.m` therefore never assumes block 15 from `CT.runs`.
- **Read once,** in P1R's C2e. No earlier step and no smoke reads it.

## 5. KPI 6 and the labels of P1R's readings

- **KPI 6 verdict (P1R).** The definition of D103 point 2 on the fresh set alone: per policy,
  one clean episode per geometry and Eb/N0 point at or above the KPI 1 threshold, one-sided 95%
  Clopper-Pearson upper bound at most 5%. `evaluate_policies.m` with `"kpi6_set": "fresh"`:
  - loads `data/clean_fresh_pools.mat` (detector check, the test split), flies it under every
    policy (`RWf`, split id 7) and stops if the file is absent: it never falls back to the
    already-read union;
  - `KP.far` and `KP.far_diag` from `far_report` on `RWf` alone; `KP.far_set = 'fresh'` and
    `KP.far_src` naming the set; `KP.reading = 'P1R'`;
  - the old union (the test splits' clean flights and `clean_test_pools.mat`) as
    `KP.far_union`, printed under "already read in profile 1's C2e: second reading,
    descriptive".
  Without the key, `evaluate_policies.m` is unchanged bit for bit.
- **The breakdown.** `system_fa_breakdown.m` takes `KP.far_set`: under 'fresh' its KPI 6 flights
  are `RWf`, and its exact gate reproduces P1R's `KP.far`. It runs once on P1R's outputs.
- **Labels.**
  - Head of P1R's `policy_evaluation.txt`: "P1R: profile 1's decision layer with the
    degradation test adopted at C1d (`<deg_mode>`). The lecturer readings and every test-split
    line are with the fixed monitor, second reading, descriptive; profile 1's C2e keeps the
    verdicts. KPI 6 (our extension): verdict on the fresh clean test set (families 7-9, block
    15), read once."
  - Every lecturer line of P1R: "with the fixed monitor, second reading, descriptive".
  - The report line: "Profile 1 with the fixed degradation test (P1R, `<mode>`, chosen on
    validation): system-level false alarms on fresh clean flights X% [upper Y%], MET / NOT MET".
- **What stays the verdict from profile 1's first C2e.**
  - Every lecturer KPI verdict, and every test-split reading.
  - Profile 1's first KPI 6 line, worded as D103 point 7 fixes it. P1R's KPI 6 line is reported
    beside it, never in its place.
  - EDGE (D103 point 8). P1R does not rerun EDGE: its envelope would be a second reading of
    test pools.
- **Archive.** At `STAGE C2e done` and again after RPT, profile 1's first-chain outputs are
  copied (`cp -p`) with a `sha256sum` manifest to `uav-gcs-logs/p1_first/` and set read-only.
  The manifest's hash goes into PROJECT_LOG before P1R's C1d. P1R writes only in its own tree
  and in `uav-gcs-logs/p1r/`.

## 6. The smoke's forced candidate

- **Switch.** `deg_force` in `profile.json` or `CFG.deg_force` names one candidate:
  `'ratio'`, `'win'`, `'win_q:0.01'`, `'win_q:0.001'`, `'win_q_gate:0.01'` or
  `'win_q_gate:0.001'` (`deg_force.m`, from `C.deg_alpha`). Any other value stops.
- **What it does.** C1d still reads every candidate and runs `deg_adopt.m`. It then deploys the
  named candidate instead:
  - `DEG.mode`, `DEG.name` and `DEG.ber_q` are the forced candidate's;
  - `DEG.forced` holds the name, `DEG.rule_pick` the name the rule adopted, `DEG.pick` stays
    the rule's index;
  - the report adds "Degradation test FORCED (smoke only, not an adoption): ...; the rule would
    adopt ...".
  C2 prints the mark beside the degradation test and carries it in `dec.deg_forced`, which
  enters the policy stamp, so a forced DQN never carries an adopted one's stamp.
- **Smoke only.** C1d stops on a forced value outside `SMOKE`, and also without `deg_select` or
  clean validation flights. C2 stops on a forced `drop_threshold.mat` and C2e on a forced
  `trained_dqn.mat` outside `SMOKE`. The fresh build stops on a forced C1d file. Without the
  switch nothing of this runs: C1d, C2, C2e and the stamp are unchanged.
- **The smoke.** In a smoke worktree at the tested `p1r` tip, with inputs copied (never written)
  from `d91q/deploy2/smoke` (profile 1's deploy smoke, whose code equals `d4623ed`'s). Each
  command: `SMOKE = true; [CFG.deg_force = '<name>';] run('<script>')`.

| Cell | Steps | Checks |
|---|---|---|
| A, default | C1d (adoption), the fresh build (4 geometries, block 18), C2, C2e with `kpi6_set` fresh, `system_fa_breakdown` | six candidate readings in `drop_threshold.txt`; `CT.set` fresh and `CT.fams`; `KP.far_set`; the breakdown's gate passes on the fresh definition |
| F1, F2 at 1e-2 and 1e-3, F3 at 1e-2 and 1e-3 | C1d forced, C2, C2e | the FORCED line; `dec.deg_mode` and `ber_q` are the forced candidate's; a distinct stamp per cell; F3: `R.deg_quiet` and C1d's quiet line; C2e ends |
| Refusals | the same commands without `SMOKE`, on a scratch copy | C1d forced, C2 on a forced file, the fresh build without an adoption, `kpi6_set` without the fresh file: each stops |

The smoke's quantile tables are flagged `short` (2 fit geometries): expected in the smoke, no
gate. Cap 2 h; about 1-1.5 h from the deploy smoke's stage times.

## 7. F0 trigger (read on profile 1's first C2e, before P1R's C1d)

F0 joins ahead of F1 (`deg_fix_protocol.md` section 6) only if the false changes are
front-loaded, tested on the deployed DQN's clean episodes of the KPI 6 union (D103 point 3e):

- the per-cycle hazard h of a first false change is estimated on cycles `C.win` to T of the
  episodes with no false change before cycle `C.win` (first changes there over the cycles at
  risk there);
- with n episodes, the count X of first false changes in cycles 1 to `C.win` - 1 is compared
  with Binomial(n, 1 - (1 - h)^(`C.win` - 1));
- **front-loaded** when P(X >= observed) < 0.05 (one-sided).

A share above 4/30 alone is not the reference: a stationary first-passage law is front-loaded by
itself.

## 8. Code

| Piece | File | State |
|---|---|---|
| Fresh set layout, owners, seeds | `clean_set_layout.m`, `pool_seed_owner.m`, `clean_pool_seed.m` (families argument, default `[1 3 5]`) | on `lect-kpi` |
| Fresh build and its guard | `build_clean_test_pools.m` ('fresh'), `clean_fresh_guard.m` | on `lect-kpi` |
| Forced candidate | `deg_force.m`, `deg_options.m` (`O.force`), `choose_drop_threshold.m`, `train_dqn.m`, `evaluate_policies.m` (refusal), `policy_stamp.m` (`deg_forced`) | on `lect-kpi` |
| KPI 6 on the fresh set, labels | `evaluate_policies.m` (`kpi6_set`) | written on `p1r` with its tests before the smoke |
| Breakdown on the fresh set | `system_fa_breakdown.m` (`KP.far_set`) | written on `p1r` with its tests before the smoke |
| P1R's profile | `profile.json`: `{"profile": "profile 1, P1R", "deg_select": true, "kpi6_set": "fresh"}` | on `p1r` |

Without `deg_force`, `"kpi6_set"` and `CLEAN_SET = 'fresh'`, profile 1's paths and profile 3's
are unchanged bit for bit (tests below).

## 9. Tests

| Test | What it checks |
|---|---|
| `test_core/test_seed_streams_disjoint` | The fresh seeds 1 941 501-1 986 600 and their smoke build's (block 18), below 2 000 000, unique, disjoint from every other seed, streams unique |
| `test_core/test_band_seeds_disjoint` | Family 6 against the fresh set as well |
| `test_core/test_clean_pool_draws` | The families argument; 'test' and 'val' give the parent commit's (`fcdc199`) seeds and speeds for every geometry of blocks 4 and 15; geometries outside 1-300 stop |
| `test_core/test_clean_fresh_guard` | The three layouts, and the smoke's fresh block 18 ('test' and 'val' unmoved); the owner table; a fresh layout on a taken pair stops; the guard (no file, no `DEG`, not chosen, `'ratio'` kept, forced, adopted, the smoke); the builder stops before any load without an adoption and goes on with one; only the fresh set saves `CT.fams`; C1c never builds it |
| `test_deg_mode/test_force_values` | The six names; other values stop, from `profile.json` or `CFG` |
| `test_deg_mode/test_force_needs_smoke` | The refusals of C1d, C2 and C2e outside the smoke, before any reading |
| `test_deg_mode/test_force_sets_mode` | Mode, name, table, `forced`, `rule_pick` and the report line for every name |
| `test_deg_mode/test_switch_off_keeps_outputs` | No force without the field; `deg_force` applied only when set; `deg_forced` only from a forced file |
| `test_deg_mode/test_settings_and_stamp` | The stamp is the parent commit's without the mark and changes with it |

## 10. Time

About 44-49 h at C2's 72 runs, or 57-64 h at 108 runs (108 when the fixed monitor moves C1d's
CUSUM pick off the top of its grid), plus an unmeasured factor from the wrapper's single-thread
MATLAB, measured on C2's first two runs. The fresh build takes about 2.0-2.3 h. Profile 3 then
ends about 18-21.11 (worst about 22-23.11).

## 11. Amendments (dated; each written before any P1R data)

- **27.10.2026, paths only.** Under Adi's folder rule the P1R worktree is
  `C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\worktrees\p1r` (section 3 said
  `C:\Users\Adi Suliman\uav-gcs-v7-p1r`) and the smoke worktree is `...\worktrees\p1r-smoke`
  (section 6 said `uav-gcs-p1r-smoke`). Nothing else changes with the paths.
- **27.10.2026, where the KPI 6 code lives.** `kpi6_set.m`, `kpi6_fresh_marker.m` and the
  `"kpi6_set": "fresh"` path of `evaluate_policies.m` are written on `lect-kpi` with their tests
  and reach `p1r` by cherry-pick, like the other P1R commits (section 8 said "written on `p1r`").
  Without the key `evaluate_policies.m` keeps every line of the parent commit in order and the
  union's heading reads as before; `KP` gains no field and the save list is unchanged.
- **27.10.2026, read once, enforced.** With `"kpi6_set": "fresh"` C2e first runs every check that
  needs no fresh flight: the fresh pools file present, of these pools' detector, built as the
  fresh set (`CT.set`, `CT.fams`); the agent trained with C1d's degradation test; the marker. It
  then writes `results/kpi6_fresh_read_started.txt` before the first fresh flight: time, commit
  and code tree, the fresh pools' SHA-256, the deployed degradation test and C1d's adopted
  candidate, `det_id`, the policy stamp. An error before the KPI 6 line appends "crash before any
  KPI 6 line" with the error; "KPI 6 read" is appended once the fresh flights are flown, before
  the KPI 6 line is computed. A second start is refused unless the marker's last event is such a
  crash on the same pools file. A MATLAB stopped from outside records no crash, so its restart is
  refused and Adi decides.
- **27.10.2026, run-level resume.** P1R's `profile.json` adds `"run_cache": true`
  (`run_cache.m`). C2 then keeps every finished training run and reward-sensitivity retrain in
  `data/run_cache/C2`, keyed by the code, the input files (the pools, C1d's file, the clean
  validation flights, the KPI 1 threshold), the MATLAB release and thread count, the
  hyperparameters, and the run's settings and seed. A C2 started again after a stop reads the
  finished runs and trains only the rest; its results are those of an uninterrupted C2 run with
  the same thread count. No run is shortened. The file is
  `{"profile": "profile 1, P1R", "deg_select": true, "kpi6_set": "fresh", "run_cache": true}`,
  kept on `lect-kpi` as `tools/p1r/profile.json` (`lect-kpi` has no root `profile.json`) and
  committed as the root `profile.json` of `p1r`. A C2 stop in P1R is resumed by running C2 again
  with the same command.
- **27.10.2026, the breakdown.** `evaluate_policies.m` with the key saves `RWf` (split id 7) and
  sets `KP.far_set = 'fresh'`, `KP.far` and `KP.far_diag` from `RWf` alone and `KP.far_union`,
  `KP.far_diag_union`, `KP.far_src_union` from the union. `system_fa_breakdown.m`'s reader of
  `KP.far_set` (P4) is still to be written on `sysfa` / `p1r` after D103's reading of profile 1.
  Until then, its exact gate on the union does not reproduce P1R's `KP.far`: it stops and never
  misreads.
- **27.10.2026, tests.** Added to section 9:

  | Test | What it checks |
  |---|---|
  | `test_core/test_deg_mode_suite` | `test_deg_mode.m` runs inside `test_core`: every one of its tests ran and passed |
  | `test_core/test_kpi6_set_values` | `'union'` by default; `"fresh"` from `profile.json` or `CFG`; other values stop |
  | `test_core/test_kpi6_fresh_marker` | The marker's lines; a second start refused without a recorded crash, after "KPI 6 read", or on another pools file; allowed after a crash before the KPI 6 line |
  | `test_core/test_evaluate_fresh_checks` | C2e with the key stops on each failed check before any flight and before the marker; without the key none of it runs |
  | `test_core/test_evaluate_fresh_wiring` | Marker, flight, crash record, "KPI 6 read" and the fresh `far_report` in that order; `RWf`, `KP.far_set` and the labels; without the key every parent line in order |
  | `test_core/test_run_cache_*` | A restart skips the finished runs and gives the uninterrupted results; cut-off, unreadable or other-key files are computed again; the entities of C2g and C2u; the switch; the wiring of C2, C2g and C2u |
  | `test_core/test_p1r_profile` | `tools/p1r/profile.json`: `deg_select`, `kpi6_set` `fresh`, `run_cache`, no `n_rx`, no `fec_rx`, no `deg_force` |
- **29.10.2026, the breakdown's reader is written (status and paths only).** The reader of
  `KP.far_set` that the 27.10 amendment "the breakdown" still owed now exists: `sysfa` `649717b`,
  written after profile 1's D103 reading, merged into `p1r` at `b37e8a3`.
  `docs/system_fa_protocol.md` section 8 describes it. Section 5's definition is unchanged:
  - without `KP.far_set` the breakdown reads the union as before. Profile 1's path keeps the gate,
    the readings, the text and every saved variable of `3c9f7ea`, the code of profile 1's reading;
  - with `KP.far_set = 'fresh'` and `KP.reading = 'P1R'` it loads `RWf` from the evaluation file,
    and KPI 6's flights are `RWf` alone (split id 7) from the KPI 1 threshold. The exact gate
    reproduces `KP.far` and `KP.far_diag` with `far_report` on `RWf`, and finds in the text KPI 6's
    fresh header ("the fresh clean test set (P1R, read once)") and the lecturer lines with P1R's
    label. The gate line and the header name the fresh definition. D103 3 reads `RWf`; D103 4 and
    5 read the test episodes as before, labelled as P1R's second reading. `far_set` is saved with
    the outputs, also with a failed gate's;
  - the gate fails on any other `KP.far_set` value, on `'fresh'` without `KP.reading` `'P1R'`,
    without `RWf` (one set per policy with the clean set's fields) and on `RWf` outside split id 7.
    Read as the union (without these two fields), P1R's outputs fail the gate as well, so the
    union's reader never misreads them.
  - **Where it runs.** P1R's breakdown runs with the code of this tree
    (`C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\worktrees\p1r`), the smoke's with that
    of `...\worktrees\p1r-smoke` at the tested `p1r` tip, never from the `sysfa` tree
    (`uav-gcs-sysfa`): there `policy_stamp.m` and `decision_settings.m` are profile 1's, without the
    degradation test, so the gate would stop on P1R's policy stamp. Its inputs are copied read-only
    into `...\worktrees\sysfa-read\p1r\results` and its outputs are written there
    (`system_fa_protocol.md` section 5). The smoke worktree is at `67f933a`, which holds the union's
    reader only; it moves to the tested `p1r` tip before smoke cell A, whose check is the
    breakdown's gate on the fresh definition.
  - Tests added to section 9 (`code/tests/test_system_fa_breakdown.m`):

  | Test | What it checks |
  |---|---|
  | `test_system_fa_breakdown/test_old_path_unchanged` | Without `KP.far_set`: the gate, the readings, the text byte for byte and every saved variable equal those of `sysfa` `3c9f7ea`'s code, on a pass and on a failed gate |
  | `test_system_fa_breakdown/test_gate_fresh` | With `'fresh'` the gate passes on P1R's C2e and reads KPI 6 on `RWf` alone with P1R's labelled lecturer lines; each missing or mislabelled piece, another `far_set` and P1R's outputs read as the union stop it; the label and the KPI 6 header are `evaluate_policies.m`'s |
  | `test_system_fa_breakdown/test_breakdown_fresh` | D103 3's tables count the fresh flights; D103 4 and 5 equal the union's readings apart from P1R's line |
  | `test_system_fa_breakdown/test_run_fresh` | The single run: `RWf` from the file, the fresh gate line and header, D103 3-5 in order, `far_set` saved, once; without `RWf` only the gatefail files, with `far_set` |
- **29.10.2026, the readers' test on `p1r` (status only).**
  `test_system_fa_breakdown/test_copies_and_readers_match_tip` compared all twelve files the
  breakdown relies on with `d4623ed`, so on `p1r` it failed on the six that P1R changes by design:
  `decision_config.m`, `decision_settings.m`, `policy_stamp.m`, `evaluate_policies.m`,
  `rollout_policy.m` and `policy_monitor.m`. On `p1r` it now compares those six with `p1r`
  `b37e8a3` and the other six (`lect_kpis.m`, `per_reduction.m`, `boot_cluster.m`,
  `false_change_rate.m`, `per_metrics.m`, `policy_run_set.m`) with `d4623ed`, still byte for byte
  apart from line ends.
  - **Why `b37e8a3`.** It is the code P1R's C2e runs. P1R runs in this worktree at the tested
    `p1r` tip (section 3 and the 27.10 path amendment; the smoke at the same tip, section 6), and
    the commits after `b37e8a3` change only this test and the docs. The six files are the same at
    `67f933a`, `b37e8a3` and the tip. A later change to one of them fails the test until the pin
    names the commit that holds it.
  - `sysfa`'s test is unchanged: there all twelve stay compared with `d4623ed`.
- **29.10.2026, the no-threat penalty form in C2 (D107, approved by Adi on 29.10.2026; written
  before any P1R data).** Basis: `core/d107_after_v0.md` sections 3.3 and 3.5 and its draft D107
  (section 4); the final text is `core/d107_final.md`. Code on branch `a107` from `p1r` `198f82f`
  (`C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\worktrees\a107`). It reaches `p1r` only
  when all of these hold: its tests pass (they run after CORE_BW's pools end), G0 passes, and the
  fresh-set A′ row's commit is on `a107` with its tests passed (see "Not part of this commit").
  - **What P1R now changes.** P1R's C2 also trains the no-threat form of the false-switch
    penalty (A′), training only:
    - the switch is `"fa_nothreat": true` in `profile.json` (or `CFG.fa_nothreat`,
      `fa_nothreat_on.m`). Without the field it is off, and C2 is the code before this amendment bit
      for bit. P1R's root `profile.json` and `tools/p1r/profile.json` are now
      `{"profile": "profile 1, P1R", "deg_select": true, "kpi6_set": "fresh", "run_cache": true, "fa_nothreat": true}`;
    - the form (`fa_form_train.m`, `link_env.m` `K.fa_form = 'nothreat'`): a change on a healthy
      link costs the training penalty λ on a cycle with no threat on the air (`sc_eff == clean`:
      the clean flight, the cycles before the onset and after the end) and the standard
      `w_false` = 20 on every other cycle. A release after the end costs nothing, as before. The
      validation and test reward, `w_false`, `healthy`, the KPIs and every evaluation file are
      unchanged;
    - `train_dqn.m` section 7 runs after the deployed agent and the sensitivity are saved: at the
      selected monitor and drop threshold, with the grid's settings, cost scales and discount
      factor, λ in {120, 160} x seeds 42-44 (6 runs, through the run cache with the form in the
      key). Each run is scored with and without the escalation, and beside its paired grid run
      (same monitor, drop, λ, discount factor and seed), on the same validation episodes and the
      clean validation flights. Both are also read without the escalation with the harmed and the
      covered episodes apart (harmed: no response does not restore the geometry);
    - the 6 A′ agents, their 6 paired plain agents and every per-episode reading are saved to
      `data/aprime_agents.mat`. `results/dqn_training.txt` gains the block "No-threat penalty form
      (pre-registered candidate (D107), validation-scored, not deployed, descriptive)", with the
      line "grid readings reproduced" for each run;
    - A′ never enters `select_run`, the gate, `choose_deployed` or the deployed policy. The only
      change to `data/trained_dqn.mat` is `seed_summary.selected_fa_form = 'all'`. C2g, C2u and the
      reward-sensitivity retrains read the form from it, so they retrain the plain form. The
      deployed policy, its stamp and every C2e reading of profile 1's line stay as without the
      switch. "P1R differs from profile 1 in the monitor and in the KPI 6 reading only" stays
      true for the deployed policy;
    - section 10: C2 takes about 4 h more (6 runs of about 34 min and 12 validation readings);
    - smoke cell A runs with the switch on: section 7 at the smoke's grid (penalty 80, one seed).
      Added checks: the block in `dqn_training.txt`, `data/aprime_agents.mat` with one run,
      and "grid readings reproduced: yes / yes". This stays inside the 2 h cap;
    - stop rule: if C1d keeps `'ratio'`, P1R ends after C1d and A′ goes to profile 3 only
      (D107 point 6).
  - **Not part of this commit.**
    - The A′ row on the fresh clean test set (D107 point 6, D104 point 6) needs a C2e reader of
      `data/aprime_agents.mat` and a retest of the breakdown's exact gate with the extra row. It is
      written with its tests in a separate commit on `a107`. Stop rule: D104 point 6 allows one
      reading of the fresh set, so `a107` reaches `p1r` only together with that commit, its tests
      passed, and no P1R smoke and no C2e runs before then.
    - The stamp carrying the form, the profile flag that lets the admissible A′ runs join
      `select_run`, and the reader of the admissibility test are for profile 3, where A′ can be
      deployed: a commit on TIP3 with tests and a smoke cell before profile 3's queue.
  - **Precondition G0** (D107 point 4). A validation-only reproduction, before D107 is registered
    in DECISIONS, run multithreaded after CORE_BW's pools end (Adi, 29.10.2026). If the
    validation slice differs, D107 is not registered and the finding goes to Adi first.
    `a107` is merged into `p1r` only after G0 passes. If G0 fails, `p1r` stays without `a107` (the
    switch absent) until Adi rules.
  - **Merge with `d108-p1r`.** Both branches add a dated block here; the merge keeps both, in
    approval order. `code/tests/test_core.m` merges cleanly. After both merges `test_core` has 283
    tests (276 + 4 + 3); `a107` alone has 280.
  - **The admissibility test**, fixed before any A′ data, verbatim from `core/d107_after_v0.md`
    section 3.5. Line references there are to profile 1's code of record `d4623ed` and to that
    note's abbreviations. In P1R it is not a gate: A′'s rows are descriptive. It decides profile
    3 only.

  > ### 3.5 Admissibility test (fixed now, validation only, before any A′ data)
  >
  > **Precondition G0** (a few minutes, gated, validation only, before D107 is registered).
  > - Compare `K.*(:,:,:,2,:)` before and after the test strip, or reproduce C2's validation row exactly. This settles V0's "NOT REPRODUCED" (V0:9; PRR:25).
  > - If the validation slice differs, C2's selection depended on test-split content. A′ is then not registered, and the finding goes to Adi first.
  >
  > **Candidates and comparators.**
  > - Candidates: 6 A′ runs (λ ∈ {120, 160} × seeds 42-44), deployed form plain `dqn` (no escalation).
  > - Comparators: the paired plain grid runs with the same monitor, drop threshold, λ and seed.
  > - Everything is scored on the same validation episodes (common random numbers) and on the 1800 clean validation flights.
  >
  > **A value of λ is admissible only if all of (a) to (c) hold.**
  > - **(a) False alarms.** For every run of that λ, and for the seed mean, the one-sided 95% Clopper-Pearson upper bound is at most 5%, that is at most 74 of 1800 (code `train_dqn.m:122`; DEC D104 point 5).
  > - **(b) Gain.** Harmed S1 recovered, A′ minus plain:
  >   - per-episode seed means, paired;
  >   - cluster bootstrap over (geometry, Eb/N0) cells, 10,000 resamples;
  >   - Holm across the two λ values (the smaller p at a one-sided 97.5% lower bound, the other at 95%);
  >   - the lower bound must be above 0;
  >   - **and (b′)** none of antenna_fault's 6 harmed geometries shows a negative seed-mean paired difference. This guards against correlation within a geometry, since 6 clusters are too few for a bootstrap alone. Taken from the detection designer.
  > - **(c) Guards** (seed means against the paired plain runs):
  >   - no threat's held recovery over its recoverable episodes falls by more than 1 point;
  >   - pooled held falls by at most 0.5 point;
  >   - covered S1 held falls by at most 3 points.
  >
  > **Reported, never gating.**
  > - (d) Mechanism: the harmed and clean Q-gap medians at the first 1-degraded fire, against −0.482 and −0.685 (V0:72), from the saved agents through the V0 reader. If the harmed gap does not move, the state cannot carry the evidence, and B-H becomes the documented next candidate.
  > - (e) antenna_fault and shadowing apart, with intervals; exact McNemar on the deployed-seed pairs.
  > - (f) 161 km/h and 9 dB per threat, as in V0 section 5.
  > - (g) The share of pre-onset changes on recoverable jamming episodes, D103 point 4(a).
  >
  > **Decision.**
  > - **Profile 3:** the admissible A′ runs join `select_run`, and the registered `rank_pick` (code `train_dqn.m:616-631`) decides with no new key. An admissible run can still lose on the weakest-threat key; that is accepted. If neither λ is admissible, the plain choice stands, reported as it falls. The verdict is profile 3's unread test pools.
  > - **P1R:** A′ never enters `select_run`. Its rows are "pre-registered candidate (D107), validation-scored, not deployed, descriptive". Its KPI 6 on the fresh clean set is read once with the other rows.
  > - No threshold, λ or form changes after any of these numbers exist.

  - Tests added to section 9 (`code/tests/test_core.m`; written, not yet run):

  | Test | What it checks |
  |---|---|
  | `test_core/test_fa_form_off_identical` | Without `K.fa_form`, or with `'all'`, `link_env` gives the tables, rewards, observations, info and state of `p1r` `198f82f`'s `link_env.m` bit for bit, at the standard and at a training penalty; `fa_form_train` leaves a reward unchanged for `'all'`, `''` and a `seed_summary` without the field; `train_one`'s default form is `'all'` |
  | `test_core/test_fa_form_nothreat_split` | Per cycle under `'nothreat'`: λ for a change before the onset, on the clean flight and after the end; `w_false` for a change on a covered link; nothing for a release after the end or a change on an unhealthy link; everything but the reward unchanged; other forms stop |
  | `test_core/test_fa_nothreat_switch` | Off without the file or the field; true or false from `profile.json`; `CFG` first; other values stop; P1R's profile sets it; read after the smoke's grid |
  | `test_core/test_fa_nothreat_training_only` | No evaluation file reads the form; validation and checkpoints read the standard reward; section 7 goes through the run cache with the form in the key, runs after the last save of `trained_dqn.mat`, and never reaches `select_run`, `rank_pick` or `choose_deployed`; `selected_fa_form` only with the switch; C2g, C2u and the sensitivity retrain carry it |
  | `test_core/test_p1r_profile` | `fa_nothreat` added to P1R's profile fields and read as true |

  - Targeted run (gated wrapper, after CORE_BW's pools), then the full `test_core`:
    `test_fa_form_off_identical`, `test_fa_form_nothreat_split`, `test_fa_nothreat_switch`,
    `test_fa_nothreat_training_only`, `test_p1r_profile`, `test_run_cache_wiring`,
    `test_m_files_parse`, `test_dqn_deployment_kinds`, `test_held_selection`,
    `test_link_env_cover_default`, `test_reward_needs_plr`.
- **29.10.2026, the fresh-set A′ row (D104 point 6, D107 point 6; written before any P1R data).**
  This is the commit the stop rule under "Not part of this commit" names, on `a107` as `c62a5b7`
  (code and tests) with this text and the reader pin in the next commit. The tests are written
  and not yet run (no MATLAB while CORE_BW's pools run). The merge conditions above are
  unchanged: tests passed, G0 passed.
  - **C2e** (`evaluate_policies.m` with `"kpi6_set": "fresh"`; the reader is `aprime_fresh.m`):
    - With the other fresh checks, before any episode and before the marker, `aprime_fresh('load')`
      reads `data/aprime_agents.mat`.
    - Without the file and with C2's switch off it returns nothing. C2e is then the code before
      this commit, output for output.
    - It stops before the marker in three cases:
      - the file without the switch (`aprime_fresh:switch`);
      - the switch without the file (`aprime_fresh:absent`): the A′ row could never be added
        after the one reading;
      - a file that is not this trained policy's C2 (`aprime_fresh:file`): another monitor, drop
        threshold or false-alarm threshold than `seed_summary`, another label or form, no
        settings, or an agent not in matrix form.
    - On a restart after a crash (`a508956`, fixed in `e265ef9`), right after the load, `aprime_fresh('restart')`
      compares the A′ file with the marker. The marker's `aprime_agents_sha256` line must equal
      the file's SHA-256, or the marker holds no such line and there is no file. Otherwise C2e
      stops before `'start'` (`aprime_fresh:restart`): a changed or removed file, or a file
      present when the first start had none. The restart then flies the A′ runs the marker names.
    - The marker gains the line `aprime_agents_sha256` after the fields it had.
  - **One reading.**
    - The A′ runs fly inside the same marker window as every policy: after `'start'`, before
      `'read'`, in `fly_clean_set`'s one world (one `clean_split`, one `link_env` table set), on
      the same episodes and the same frame-draw seed (40000), after every policy.
    - Each run flies as trained and scored on validation: plain `dqn` without the escalation, with
      the deployed DQN's monitor (the selected monitor and drop threshold) and the grid's settings
      (`aprime.S`) on top, on the standard reward (no training form).
    - A run or a flight missing there stops as a crash before any KPI 6 line
      (`aprime_fresh:row`), so the marker allows a restart.
    - Nothing else in C2e reads the fresh set. D108's LINK reading (`link_fresh.m`, after
      'KPI 6 read') stays the one other registered reading. The added marker line does not
      change what `link_fresh` checks: the exact `pools sha256` line, the `det_id` line and
      'KPI 6 read'.
  - **KPI 6.**
    - One `far_report` call over every policy, then the A′ runs. `KP.far` holds every policy's
      rows as before, then one row per A′ run, labelled "A′ penalty λ, gamma γ, seed s
      (pre-registered candidate (D107), validation-scored, not deployed, descriptive)".
    - The lines follow the policies' lines. After the block, one line names the file and its
      SHA-256, and one line per λ and γ gives the seed mean with its one-sided 95% Clopper-Pearson
      bound, as `train_dqn.m` reports them.
    - `KP.far_diag`, the deployed index and every verdict are unchanged.
    - After the rows, C2e stops if `data/aprime_agents.mat` exists and KPI 6 lacks one of its rows
      (`aprime_fresh:row`).
      This is a post-read assertion: it comes after 'KPI 6 read', so a stop there spends the
      reading. The check inside the reading (`'flown'`) already stops on a run or flight not
      produced, so it is not expected to fire.
    - Saved: `RWa` (one fresh set per run, split id 7) and `KP.far_aprime` (the runs' names,
      labels, λ, γ, seeds, settings, file and SHA-256, without the agents).
  - **The breakdown's exact gate (retested).**
    - With `KP.far_aprime`, `system_fa_breakdown` reads `RWa` from the evaluation file and checks
      it: one set per run, split id 7, the episodes of `RWf`, every field.
    - It then reproduces the new `KP.far`, `KP.far_diag`, their lines and the A′ block exactly
      (`isequaln`).
    - The gate fails on `RWa` without `KP.far_aprime`, on `KP.far` without the A′ rows, or on a
      changed row or line.
    - D103 3 reads the policies' flights only. The header names the A′ rows.
    - A run whose episodes are not those of `RWf` is named as `RWa{k}` against `RWf{1}`.
    - Without them the gate, the readings, the text and every saved variable are those of
      `b37e8a3`. The union path (profile 1) is untouched.
  - **Pin.** `test_copies_and_readers_match_tip` now compares `evaluate_policies.m` and
    `aprime_fresh.m` with `e265ef9` (the restart check on top of `c62a5b7`). The other five P1R
    readers stay compared with `b37e8a3`, and the six unchanged readers with `d4623ed`.
  - **Tests** (written, not yet run):

  | Test | What it checks |
  |---|---|
  | `test_core/test_aprime_fresh_load` | Nothing without the file and with the switch off; the file without the switch and the switch without the file stop; another C2's file, label, form, settings or agent stops; else the A′ agents (not the plain pairs), settings, names, labels and SHA-256; the switch from `CFG`, else `profile.json` |
  | `test_core/test_aprime_fresh_rows` | The stop rule: with the file, a run or a flight not flown, or KPI 6 without an A′ row, stops; without the file and the runs nothing is checked; the block's lines and the seed-mean bound |
  | `test_core/test_aprime_fresh_fly` | Each run with the world's tables, episodes, split and seed, kind `dqn` without the escalation, the world's monitor with the grid's settings on top, no training form, padding dropped, in the file's order (recorder in place of `policy_run_set.m`) |
  | `test_core/test_evaluate_fresh_aprime_wiring` | Load before any episode and the marker; flights, the check and the split inside the single reading in one world; one `far_report` call with the A′ rows, then their block, then the stop rule; `KP.far_aprime` and `RWa` only with them; never in `POL` or the deployed index; every line of `4bb20cc` in order but the six rewritten |
  | `test_core/test_evaluate_fresh_aprime_stops` | C2e on fixtures: no file and switch off runs as before; the switch without the file, the file without the switch and another C2's file stop before the marker; both pass; the union path never reads the file |
  | `test_core/test_evaluate_fresh_aprime_restart_recorded` | A restart whose marker records the A′ file: the same file passes; a changed file, or none with the switch off, stops before `'start'` (`aprime_fresh:restart`); the marker stays as the crash left it |
  | `test_core/test_evaluate_fresh_aprime_restart_unrecorded` | A restart whose marker records no A′ file: still none passes; a file now present with the switch stops before `'start'` (`aprime_fresh:restart`); the marker unchanged |
  | `test_core/test_evaluate_fresh_wiring` | The fresh-set call pin updated to `[RWf, RWa] = fly_clean_set(...)` |
  | `test_system_fa_breakdown/test_gate_fresh_aprime` | The gate reproduces the new `KP.far` with the A′ rows (the policies' rows and `KP.far_diag` as without them); D103 3 unchanged; each broken piece fails it |
  | `test_system_fa_breakdown/test_run_fresh_aprime` | The single run reads `RWa`, passes, names the rows in the header; without `RWa` the gate fails |
  | `test_system_fa_breakdown/test_fresh_path_unchanged` | Without the A′ rows, the gate, the readings, the text and the saved variables equal `b37e8a3`'s, on a pass and a failed gate |
  | `test_system_fa_breakdown/test_copies_and_readers_match_tip` | The pin above |

  - **Merge with `d108-p1r`.** Both dated blocks stay, in approval order (D108's, then this one).
    D108's sentence that `evaluate_policies.m` is unchanged describes D108's own commit. With
    `a107`, C2e's KPI 6 reading also carries the A′ rows (this block), and the marker gains
    `aprime_agents_sha256`. The merge resolution adds this line under D108's block.
  - **Counts.** `test_core` on `a107` has 287 tests (280 + 7). After the merge with `d108-p1r`
    it has 290. `test_system_fa_breakdown` has 18 (15 + 3).
  - **Targeted run** (gated wrapper, after CORE_BW's pools; 39 tests):
    - all of `test_system_fa_breakdown`;
    - in `test_core`: the seven new tests, `test_evaluate_fresh_wiring`,
      `test_evaluate_fresh_checks`, `test_kpi6_fresh_marker`, and the eleven targeted tests
      listed above.
    - Then the full `test_core` and `test_system_fa_breakdown`.
