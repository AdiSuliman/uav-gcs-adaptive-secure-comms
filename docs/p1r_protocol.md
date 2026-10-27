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
