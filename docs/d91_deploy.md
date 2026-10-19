# d91 deploy: the fusion revision, the fourth test set and the speedups in one branch

Branch `v7-deploy-d91` (worktree `C:\Users\Adi Suliman\uav-gcs-v7-deploy`), from `d90-loop`
`2cbe559`. It replaces the branch name `d91-deploy` of `docs/d91_fuse.md` section 7: every step
there that names `d91-deploy` means this branch. Nothing here has been merged into a live tree
(`uav-gcs-v7`, `uav-gcs-v7-p3`) or into `main`.

Decisions it carries (recorded elsewhere, not repeated):
- the pre-registered rule adopted 'branch evidence' on profiles 1 and 3 (`docs/d91_fuse.md`
  section 5);
- the declared phi comparison: phi is not kept on either profile and phi = 1 passes the adoption
  rule on both, so the deployed design is **'branch evidence, phi = 1'**, latch off
  (`docs/d91_fuse.md` section 12, verdict line of 19.10 01:16:33);
- the merge rule of the speedups is `docs/d91_speed.md` section 7.1. Its parts 2 and 3 were read
  on 19.10 01:14 from `uav-gcs-logs\v7_d91_tests4_summary.log`: `VERDICT merge rule: PASS on
  the logs (n_rx 4)`, for the speed-only candidate `686fd11`. This branch is a different
  candidate, so its own pair and proofs run again (section 4).

## 1. The branch

| Commit | What |
|---|---|
| `7662f4b` | merge `d91-set4` `0e410cf` (`--no-ff`) |
| `b4f217a` | merge `d91-fuse` `fd9796a` |
| `9d8fc86` | merge `d91-speed` `0069d03` |
| `6c186e6` | the deploy commit (section 2) |
| `87fcde6` | a profile's first B2F before B3n and B3m; the 'base' no-go (section 3.3) |
| `26fca69` | B3r after a no-go: the rehearsal must follow the no-go record |

- The three merges had no conflict (the order of `docs/d91_fuse.md` section 7.A).
- `code/detection/fusion_rev_id.m` is the same blob on `d91-set4`, `d91-fuse` and this branch:
  `542cd1a3663fa2b777d304046cf9b5d1afc6e517`.
- Trial merges in the object store (`git merge-tree --write-tree`), none with a conflict:
  this branch onto `v7-p3` `29510e7`, onto `v7-dev` `208602b`, and `v7-docs-d91` `b42c1d4` onto
  this branch.
- `v7-dev`, `v7-p3` and `9b5c9f1` hold the same `code/`, `startup.m` and `models/` (an empty
  `git diff`). So the profile 1 and profile 3 candidates have the same code tree, and
  `test_core`, which always runs with n_rx 3, says the same for both.
- `v7-docs-d91` (docs only, based on `v7-dev`) is not merged here: it carries `v7-dev`'s history.
  Merge it into `v7-dev` together with this branch (step E4) and, if wanted, into `v7-p3`. It
  touches no file under `code/`.

## 2. The deploy commit (`docs/d91_fuse.md` section 7.B, with the review findings)

| File | Change |
|---|---|
| `fusion_pick.m` | name `'branch evidence, phi = 1'`, `cues.phi1 = true`, latch false, N 12, lambda 1e-3, target rule 'N' |
| `kpi1_set.m` | `'fresh3'` |
| `run_stage.m` `run_one` | B2F: `FUSION_REV = true`; `FUSION_FIT = 'enlarged'` unless `SMOKE`; without the enlarged fit set, the old selection (3.3). The `%#ok<INUSD>` on `SMOKE` is gone |
| `main.m` | B2F as `run_stage.m` runs it (`run_fusion`) |
| `select_fusion.m` | before any data is read: the fit set's files (`select_fusion:fit_sets`) and the kept fusion as the rule's base (`select_fusion:pick_base`); a failed rule or base writes `data/fusion_nogo.mat`; `deployed_pick.check.kept`; an earlier no-go record is set aside after any save |
| `eval_detector.m` | B3r guard: `deployed_pick` equal to `fusion_pick()` (`eval_detector:fresh3_pick`), placed after the `FM.target_age`/`FM.cues` check and before `fresh3_fusion_old`; after a no-go the kept fusion is read (3.2); every reading records `fusion_rev`, `fusion_state` and `sample` |
| `fusion_nogo.m`, `fusion_reading.m`, `enlarged_ready.m` | new (3.1-3.3) |
| `measure_all_kpis.m`, `build_kpi_dashboard.m` | the in-sample label (3.1) |
| `test_core.m` | `test_third_test_set`, `test_fourth_test_set` (guard cases, no-go cases, the pre-deploy switch by a stand-in), `test_kpi1_file`, `test_fusion_pick_deploy` (phi = 1, the new source lines), new `test_fusion_nogo_reading` |

Step B5 of the fuse checklist (`d91_bitid/rev.m` must hold `fusion_rev_id('validation')`) is
covered by the smoke's `B2Fcheck` step (section 4).

## 3. The deferred review findings

### 3.1 Read sets become in-sample after the deploy

The enlarged fit set is validation, the test split, the second set (B3n) and the third set (B3m)
(`fit_sets.m`). Once a profile's `data/fusion.mat` holds `fusion_rev =
'd91_branch_evidence_enlarged'`, a reading of the test split, the second or the third set
describes the fit; it does not test it.
- `fusion_reading.m` gives, for a reading's suffix, the fusion's `fusion_rev`, its state
  (`'deployed revision'` or `'kept fusion after a no-go'`) and `sample = 'in-sample (fit set of
  the deployed fusion)'` for every suffix but `_fresh3`.
- `eval_detector.m` prints `Reading: in-sample (fit set of the deployed fusion)` after the test
  set line and stores `metrics.fusion_rev`, `metrics.fusion_state` and `metrics.sample`.
  `export_report_numbers.m` carries them in `detector`, `detector_third` and `detector_fourth`.
- `measure_all_kpis.m` adds the label to each side reading beside KPI 1, a line `KPI 1 reading:
  read with the <state>`, and the label to KPI 1's value itself when the KPI 1 reading is
  in-sample. That happens only if a profile's fourth set is spent by a failed B3r and its KPI 1
  falls back to the third set (`docs/d91_set4.md` step 6).
- `build_kpi_dashboard.m` adds it to the set name.

**Archive the pre-deploy readings.** Before a profile's deploy B2F, copy its `results/` and
`data/fusion.mat` to `uav-gcs-logs\deploy_archive\<p>\pre_deploy_<time>\` (steps D2 and E3).
Those readings were taken with the old fusion. They are the record of the run before the
revision, and `result_status` marks them STALE once the new fusion is saved.

### 3.2 A no-go still reads the kept fusion once on the fourth set

`docs/d91_fuse.md` section 7.G set `kpi1_set.m` back to `'fresh2'` after a no-go, so the kept
fusion's KPI 1 would come from a set that the go/no-go itself had looked at. That is replaced
here:
- B2F with `FUSION_FIT = 'enlarged'` writes `data/fusion_nogo.mat` before it stops, in two
  cases. `why = 'rule'`: the design fails `fusion_adopt('branch')` (`select_fusion:pick_rule`).
  `why = 'base'`: the kept fusion is not the rule's base (`select_fusion:pick_base`, 3.4). The
  record holds the design, the check, the reason, the time and the SHA-256 of the kept
  `data/fusion.mat`. B2F has not saved, so the kept fusion stays.
- `kpi1_set.m` stays `'fresh3'`. B3r reads the fourth set once with the kept fusion, but only
  while the record names `fusion_pick()` and the kept file is unchanged (`fusion_nogo('check')`).
  It also needs a rehearsal on the third set newer than the record. The marker and the
  read-once rules of `docs/d91_set4.md` are unchanged.
- A later B2F that saves sets the record aside as `data/fusion_nogo_superseded_<time>.mat`.

### 3.3 Profile 2's own fusion decision (decided)

Profile 2's enlarged fit set does not exist at the B2F of its chain. That B2F comes before B3n
and B3m (the takeover's AB list).

**Decision: profile 2 builds its second and third sets first, with the fusion fitted on
validation exactly as before the revision. Its B2F after B3m then decides with the rule check
of the fixed design.** The reasons:
- Profiles 1 and 3 followed the same protocol (option A, Adi 18.10): the decision is made on the
  enlarged set, and KPI 1 is read once on a fourth set built after it.
- On profile 2 nothing is chosen: not the variant, N, lambda, phi or the latch. The check is the
  out-of-fold comparison of one fixed design against the base, on profile 2's own enlarged set
  (folds by sub-run, seed 9101; bootstrap seed 9102). No nested reading is needed.
- A validation-only rule check was rejected. Validation holds almost no shallow-fault frames at
  K >= 10 dB, the frames where the gain was measured (weak-branch analysis, 18.10), so the check
  would have little power, and it would differ from the protocol of profiles 1 and 3.
- The chain already builds B3n and B3m, so this costs no extra machine time.

In code: `run_one` (and `main.m`) set `FUSION_FIT = 'enlarged'` only when `enlarged_ready()`
holds, that is when `data/dataset.mat`, `splits_fresh.mat`, `dataset_fresh.mat`,
`splits_fresh2.mat` and `dataset_fresh2.mat` exist. Otherwise B2F prints `B2F: no enlarged fit
set yet (B3n, B3m): the fusion is fitted on validation as before the revision` and runs the
selection of `9b5c9f1` (switch off, bit-identical, `docs/d91_fuse.md` section 2). On profiles 1
and 3 the files exist, so their B2F always deploys. The smoke keeps its own path (validation
revision). Procedure: section 5, F.

### 3.4 The base of the rule equals the profile's kept fusion (N, lambda, latch)

The rule compares the design with the fusion without further columns, at the design's N 12 and
lambda 1e-3, the target rule pos - onset < N, latch off. That is a valid test only if it is the
fusion a no-go keeps. So `select_fusion.m` (enlarged fit) reads the kept `data/fusion.mat`
before any data and requires its `N`, `lambda` and `FM.latch` to equal the pick's, with no
further columns (or the same pick deployed before, for a rerun). Otherwise it records a 'base'
no-go and stops (`select_fusion:pick_base`).
- Profile 1 kept N 12, lambda 1e-3, latch off; so did profile 3 (`uav-gcs-logs\v7_d86\p1.log`
  and `p3.log`, B2F of 17.10: `Selected N = 12 cycles, lambda 1e-03`, `the latch is off`). The
  old fusion fitted without `target_age` reads the targets at age N (`fusion_target.m`), the
  same rule.
- Profile 2's base is whatever its own validation picks in the chain. If that is not 12 / 1e-3
  / off, the 'base' no-go keeps its fusion, and its KPI 1 is read once on its fourth set with
  it. This is declared here, before any profile 2 number exists.

### 3.5 The speed merge rule is cited, not copied

The rule is `docs/d91_speed.md` section 7.1 (parts 1-4). Part 1 is the proofs on the d91 code
(`v7_d91_speed_summary.log`). Parts 2-3 are the pair and the proofs on the target's antenna
count, for this branch's candidates in `v7_d91_deploy_tests.log` (section 4). Part 4 is the
tree at the merge (steps D3 and E4).

### 3.6 The takeover's final phase must wait while profile 1's reruns run

The takeover (`d91-takeover` `55335d7`) has no hold for its final phase. Its `final_phase` starts
once all three tracks have ended, and LAT, KPI, DASH, WEAK and RPT would then read profile 1's
results in the middle of its reruns. **Needed on `d91-takeover` before profile 1's reruns (E):**
- `final.hold` in `v7_d86`: `final_phase` waits while it exists, read before each profile's final
  part and again after `wait_idle`;
- one log line when it starts to wait;
- the hold, like the others, read again after every wait;
- a harness scenario for it.

Until that is in the live takeover, profile 1 takes plan A (E), where its reruns end before its
own chain does, so the tracks cannot end first.

### 3.7 The wrap check

The check on profile 1's real pools ended on 19.10 at 12:06 (`uav-gcs-logs\v7_d91_wrap_real.log`,
results in the scratchpad's `wrap_real\wrap_real.txt`). Its player matched `link_env.m` (`PLAYER
CHECK ... identical over 64 episodes x 30 cycles: 1`).

**The frame-20-to-1 jump is not confirmed on the real pools.**
- A, 324 own clean flights: the jump's gain step is no larger than a step between consecutive
  frames. 4.4% of jumps lie above the consecutive steps' p95, about the 5% expected by chance.
  The lag-1 gain correlation is -0.12, the jump pair's -0.06.
- C, lost-branch reads (`lb`) within 12 cycles after the jump, less before it:
  - deployed fusion: -0.02 [-2.05, +2.07] points;
  - 'branch evidence, phi = 1': +1.22 [-1.64, +3.94];
  - every alarm setting's interval also holds 0.

  The smoke's +25.8 points (8 clean episodes) is not reproduced.
- K6, 'the jump adds': every interval holds 0, with negative point estimates.

So no `link_env` change is needed for the jump before profile 1's C1d.

One effect remains for the reading of KPI 6. Rolling-in flights replayed wrapped give fewer K6
events than played continuously: 'rolling-in wrapped less continuous' is about -1 to -4 points,
and the interval excludes 0 for several settings, for example class_cusum 72 at 5/5: -3.34
[-5.07, -1.83]. That is the known upper-bound caveat of K6 method (iii). It is a matter of
reporting, not of this branch.

If a `link_env` change is decided later:
1. It lands as a commit on this branch.
2. Rerun the `core` and `smoke` jobs, then rebuild the candidates and rerun `pold pnew porder
   p3core` (section 4).
3. The tested trees of steps D3 and E4 become the new candidates.

`link_env.m` is read by C1d, C2, C2e, C2g and C2u, and by none of the stages before them, so plan
A (E) would take it with no extra rerun.

## 4. Tests queued on the tip (19.10)

Script `uav-gcs-logs\v7_d91_deploy_tests.sh` (copy `docs/d91_deploy_tests.sh.txt`). Smoke driver
`uav-gcs-logs\d91_smoke_deploy.m` (copy `docs/d91_smoke_deploy.m.txt`). Progress, the summary and
the verdicts go to `uav-gcs-logs\v7_d91_deploy_tests.log`; each job logs to
`v7_d91_deploy_tests_<job>.log`.

How the jobs run:
- one job at a time, hidden WMI launch;
- each MATLAB started only on an OK from `v7_d91_speed_gate.ps1`: at least 35 GB of commit free,
  at most one other non-pipeline MATLAB, the shared 180 s start stamp;
- `-singleCompThread`;
- in git archive exports under `C:\Users\Adi Suliman\d91q\deploy\<export>`, never a live tree;
- TEMP `C:\Users\Adi Suliman\d91q\deploy\tmp`;
- each MATLAB writes its own PID first and is bounded (6 h, the smoke 14 h). On a timeout the
  queue ends only that PID.

| Job | Export | What |
|---|---|---|
| `core` | `tip` (this branch) | full `test_core`; paired by test name with `v7_d91_tests4_base.log` (`2cbe559`, d90) |
| `pold` | `p3old` | proof (b), old side: v7-p3 + this branch without d91-speed (the merge of `b4f217a`) |
| `pnew` | `p3m` | proof (b), new side on the profile 3 candidate; `B_old_vs_new_nrx4` |
| `porder` | `p3m` | proof (c): `C_order`, `C_vs_B_nrx4` |
| `p3core` | `p3m` | full `test_core` on the profile 3 candidate; paired with `v7_d91_tests4_tip.log` (`29510e7`) |
| `smoke` | `smoke` (this branch) | serial smoke (below) |

The queue (bash PID 8764, started 19.10 12:24) runs on the following commits:
- this branch at `4f9615f`. Later commits on the branch change `docs/` only;
- `v7-deploy-d91-on-v7-p3` = `192a546` (tree `98cb443`);
- `v7-deploy-d91-nospeed-on-v7-p3` = `2a2b525`;
- the `v7-p3` tip `29510e7`.

- The profile 3 candidate is `v7-deploy-d91-on-v7-p3`: one merge commit with first parent `v7-p3`
  `29510e7` and second parent this branch's tip, built with `git merge-tree` and `git
  commit-tree`.
- The old side of its proofs is `v7-deploy-d91-nospeed-on-v7-p3` (v7-p3 merged with `b4f217a`).
  So the proofs isolate d91-speed's change on the deployed code at n_rx 4, and d90's or the
  fusion's own changes cannot read as a speed difference. The proof's detector is profile 3's
  B3m smoke detector (`uav-gcs-b3m-p3\data`), read only.

**No parallel pool anywhere.** `test_core` opens none. The proofs run `pool_cell` on this
process. In smoke mode every pool stage sets `NWP = 0`, takes no parallel turn and opens no
pool:
- `build_policy_pools`, `build_clean_test_pools` and `build_check_pools` (`pool_lpt` with
  `pl = []` runs the jobs in order on this process);
- `map_survivability_boundary`;
- `experiment_survivability_options` (its `parfor (k = 1:2, NWP)` runs on the client).

No other `parfor`, `spmd` or `parpool` is on a smoke path. The driver checks for an open pool
after every step and reports one (`V7SMOKE POOL`). No MATLAB command line holds `run_stage(`, so
neither the launcher nor the takeover counts a job as a pipeline stage. The turn file held by
profile 1's C1p is never touched.

**What the smoke runs** (all of it; the queue's log says what passed):
- the chain A0 A4v A5 A6 B1 B2 B2F, B2Fcheck (fusion_rev is `fusion_rev_id('validation')`, no
  `deployed_pick`), B3n B3 B3m B3q B3a B4 OOD B4s;
- B3rguard (B3r refused with `eval_detector:fresh3_fusion_rev`, no marker);
- C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE LAT KPI DASH WEAK RPT;
- then the deploy tail on the smoke data:
  - `B2Fpick`: the measured design on the validation fit; its rule may fail on smoke data;
  - `B2Fenl`: the deployed path. It needs the enlarged fit set and the kept base, then applies
    the rule. Accepted outcomes are a save, `pick_rule` or `pick_base`; the latter two write the
    no-go record;
  - `REHEARSAL` (DET_TEST = 'fresh2');
  - `B3r`: one reading, with the deployed revision or the kept fusion after a no-go. Its marker
    is printed;
  - `B3ragain`: refused (`fresh3_read` or `fresh3_started`);
  - KPI, RPT, and the KPI 1 lines.

Smoke numbers are not results.

Verdict lines at the end of `v7_d91_deploy_tests.log`:
- `VERDICT deploy test_core`: blocked by `fail-new-only`, `not-run`, `removed-test`, a failing
  `new-test`, MISSING, STALE, TIMEOUT, or a `fail-both` with other diagnostics. Against d90 the
  d91 tests are new tests and must pass.
- `VERDICT p3 merge candidate`: parts 2 and 3 of `docs/d91_speed.md` section 7.1 on this
  candidate, with the same blockers and the three proofs PASS with detector 1 at n_rx 4.
- `VERDICT smoke`: every step OK or the expected refusal.

A `fail-both` with the same diagnostics is the target's own state: report it, do not fix it here.

## 5. Procedures

General rules for every step below:
- Every MATLAB of a profile runs alone in that profile's worktree, with its own log.
- Never put `run_stage(` on a hand-run command line. The takeover counts such a session as a
  pipeline session. Use the scripts directly, as below.
- Paths: `L = C:\Users\Adi Suliman\uav-gcs-logs`, `R = L\v7_d86`.
- MATLAB is `"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -singleCompThread`.

### D. Profile 3 (idle now; between today and its C1p, about 25.10)

Preconditions:
- the three VERDICT lines read PASS;
- the wrap check has reported: done, no change needed (3.7);
- **the takeover runs**. The old fix script (`v7_d87_p3fix.sh`, bash 49732) does not read
  `p3_c1p.hold` and would start C1p as soon as profile 1 passes SURV3;
- `origin/v7-p3` is still `29510e7`. If not, rebuild both profile 3 commits as in section 4 and
  rerun `pold pnew porder p3core`.

1. **Hold.** Write `R\p3_c1p.hold`. Check that no MATLAB runs in `uav-gcs-v7-p3`:
   - `R\takeover_ml_p3.pid` names no live process;
   - `Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" | Select ProcessId,ParentProcessId,CommandLine`;
   - p3.log's current part has not started C1p.
2. **Archive** (3.1): `results\` and `data\fusion.mat` to `L\deploy_archive\p3\pre_deploy_<time>\`.
3. **Code.** In `uav-gcs-v7-p3`: `git fetch` and `git merge --ff-only
   origin/v7-deploy-d91-on-v7-p3`. The fast-forward makes the tree the tested one.
   - Check that `git rev-parse HEAD^{tree}` equals the `p3 candidate ... (tree <T>)` of the
     summary;
   - check that `git status --short` prints nothing;
   - then `git push`.

   Do not cherry-pick `d91-speed-on-v7-p3` separately first: this branch already holds it.
4. **The fourth set** (`docs/d91_set4.md` step 3):
   - `cp "$L/set4_out/p3/data/"*fresh3* uav-gcs-v7-p3/data/`;
   - `(cd uav-gcs-v7-p3/data && sha256sum -c "$L/set4_out/p3/sha256_fresh3.txt")`: every line
     must end in OK;
   - the `params_id` and run-id check of step 3, with `7ecc49e97d0a5639f458997caa6b58c8`.
5. **B stages by the takeover.** Write `R\p3_brerun.go` holding `B2F B3 B3a B4 B4s`. The takeover
   runs them with A0 first, after profile 1 is past C1c and with 65 GB of commit free. B2F runs
   the deployed path, since the enlarged files exist. After it, in p3.log's B2F part:
   - `The kept fusion is the rule's base: N = 12 cycles, lambda 1e-03, latch 0`;
   - the rule line `... -> rule yes`;
   - `load('data/fusion.mat', 'fusion_rev', 'deployed_pick')` gives
     `d91_branch_evidence_enlarged` and the pick with its check.

   B3 to B4s are in-sample descriptions now (3.1).

   A stop at `pick_rule` or `pick_base` is profile 3's no-go: `data/fusion_nogo.mat` exists.
   Continue with step 6 all the same. Set `p3_rerun.accept` only for a failure that is not
   B2F's no-go.
6. **Rehearsal and B3r**, by hand, after the rerun's end marker, in `uav-gcs-v7-p3`:
   - `matlab -singleCompThread -logfile logs\fresh2_rehearsal_<time>.txt -batch "cd(setup_paths()); DET_TEST = 'fresh2'; run('eval_detector')"`;
     it must end without an error;
   - `matlab -singleCompThread -logfile logs\stage_B3r_<time>.txt -batch "cd(setup_paths()); DET_TEST = 'fresh3'; run('eval_detector')"`, once.
7. **Record.** Archive the marker, `results\*_fresh3.*` and the log to `L\set4_out\p3\read\`.
   Commit the marker as `docs/d91_fresh3_read_p3.txt` on `v7-p3`, then push (`docs/d91_set4.md`
   steps 5-6).
8. **Release.** Remove `p3_c1p.hold`. C1p builds the pools on the deployed fusion. Check C1c's
   `det_id` line.
9. After profile 3's C1p, rerun wrap check A, B and C on its pools (`docs/d91_fuse.md`
   section 10).

### E. Profile 1: plan A (recommended), the swap before C1d

Profile 1's chain runs C1p to RPT in one MATLAB (`42560`, launcher stage list), so there is no
gap between stages. `data/fusion.mat` must stay as it is until C1c has checked its `det_id`.
SURV, SURV3, OHP, GCSA and GAL read nothing of the fusion. C1d, C2, C2e, C2g, C2u, EDGE and LAT
do. So the swap goes after SURV3 and before C1d's choice is used. Code may not change in
`uav-gcs-v7` while C1p, C1c, SURV or SURV3 run (`docs/d91_speed.md` 7.6), so the chain has to be
stopped at SURV3's end.

Conditions:
- the D preconditions;
- the profile 1 candidate built (E1);
- the takeover running;
- Adi available when SURV3 ends (about 26.10).

If any condition fails, take plan B.

1. **Before SURV3 ends.** Build `v7-deploy-d91-on-v7-dev`: the merge commit of this branch onto
   the `v7-dev` tip, with `git merge-tree` and `git commit-tree`, as in section 4.
   - Check `git diff --stat <it> v7-deploy-d91-on-v7-p3 -- code startup.m models`: it must be
     empty, so `p3core` covers it.
   - Run the n_rx 3 proofs for it: `bash v7_d91_deploy_tests.sh <tip> <p1 candidate> <v7-dev tip>
     <v7-dev + b4f217a> pold pnew porder`. NRX is read from the tip's `profile.json`, and there
     is none on `v7-dev`, so n_rx is 3.
   - Merge `v7-docs-d91` into it if the docs should go in too; the code tree stays the same.
2. **Stop the chain at SURV3's end (Adi).** When p1.log shows `##### STAGE SURV3 done`, end
   profile 1's chain MATLAB: `taskkill /PID <win64 pid> /F`, with no `/T`. The win64 PID is the
   one in `R\takeover_p1_chain_ml.txt` (now `42560`). The takeover then raises
   `ALERT_p1_failed_*` and waits for `p1_resume.go`. Check p1.log:
   - no `STAGE C1d done`: the resume starts at C1d;
   - `C1d done` already there: C1d chose its threshold with the old fusion. Rerun it in step 7.
3. **Archive** (3.1): `results\`, `data\fusion.mat` and `data\trained_dqn.mat`, if present, to
   `L\deploy_archive\p1\pre_deploy_<time>\`.
4. **Code.** In `uav-gcs-v7`: `git merge --ff-only origin/v7-deploy-d91-on-v7-dev`. Check the
   tree and `git status`, then push. The takeover's later `v7-p2` branches from this, so profile
   2 starts with the deploy code (F).
5. **The fourth set**, as D4, with `set4_out/p1` and `add18af2b7532a0bd2f7fbc78f06e526`.
6. **B2F, rehearsal, B3r**, by hand in `uav-gcs-v7`, each with its own `-logfile` under `logs\`:
   - `-batch "cd(setup_paths()); FUSION_REV = true; FUSION_FIT = 'enlarged'; run('select_fusion')"`
     (about 1 h). Check the base line, `rule yes`, `fusion_rev` and `deployed_pick` as in D5.
     A stop at `pick_rule` or `pick_base` is profile 1's no-go: go on with the kept fusion
     (3.2), and skip step 7's `rekey_pools` (the pools keep their keys).
   - the rehearsal and B3r commands of D6;
   - the record as in D7, committed on `v7-dev` as `docs/d91_fresh3_read_p1.txt`.
7. **Re-key, and C1d if needed:**
   - `-batch "cd(setup_paths()); rekey_pools"`. It covers the policy, check, clean_val and
     clean_test pools, and backs each one up first. It stops, changing nothing, on an unknown
     field;
   - if C1d had finished in step 2: `-batch "cd(setup_paths()); run('choose_drop_threshold')"`.
8. **Resume.** Write `R\p1_resume.go`, newer than p1.log. The takeover resumes profile 1 from its
   first unfinished stage (C1d, or C2 after step 7's C1d) to RPT, with the new fusion and pools.
9. **After the chain**, with `final.hold` written first if the takeover has it (3.6):
   - B3, B3a, B4 and B4s by hand (in-sample descriptions, about 5.5 h);
   - wrap check A, B and C on profile 1's pools;
   - then remove the hold.

Cost: about 3-4 h between the stop and the resume (B2F, rehearsal, B3r, re-key). Nothing of the
closed loop runs twice.

Risks:
- the stop must come before C1d's result is used. Step 2 says how to tell, and step 7 repairs it;
- a C2 cut at its start is simply rerun;
- profile 3's C1p may start right after profile 1's SURV3 and run beside these single-thread
  jobs. The gate's 35 GB applies to the side jobs; profile 3's own takeover gate applies to C1p.

### E'. Profile 1: plan B, the rerun after the chain

Plan B needs the takeover's `final.hold` (3.6) and a hold on profile 2's start: the takeover
branches `v7-p2` from `v7-dev` at profile 1's chain end, which comes before the merge. Neither
hold exists in `55335d7`.
1. Profile 1's chain ends at RPT with the old fusion.
2. Archive, then E4 to E7.
3. C1d, C2, C2e, C2g, C2u and EDGE by hand, about 2 days (C2 alone is 38-42 h).
4. B3, B3a, B4 and B4s by hand.
5. Remove `final.hold`.

Profile 2 then branches with the old code. At its `p2_c1p.hold`, merge this branch into `v7-p2`
(its own pair, as in C1 of `docs/d91_fuse.md` section 7), and continue with F3. Cost: the
closed loop of profile 1 runs twice, and the run ends about 2 days later.

### F. Profile 2

Under plan A, `v7-p2` branches from `v7-dev` with this code:
1. Before profile 1's chain ends, write:
   - `R\p2_c1p.hold`;
   - `R\p2_set4.stages` holding `B3q`. `run_stage.m` then has B3q, so the fourth set is built in
     the chain, with the same recipe and seeds as for profiles 1 and 3 and profile 2's link
     model.
2. The chain runs A0 to B2, then B2F on validation (3.3; its log line says so). Then B3n and B3m
   (its first reading of the third set), B3q, B3, B3a, B4, OOD and B4s. It stops at the hold.
3. **Decision**, by hand: B2F with the enlarged fit set (the E6 command). The outcomes:
   - `rule yes`: the rehearsal, then B3, B3a, B4 and B4s (in-sample descriptions), then B3r once
     and its record (`docs/d91_fresh3_read_p2.txt` on `v7-p2`);
   - `pick_rule` or `pick_base`: the no-go record (3.2). Then the rehearsal and B3r once with the
     kept fusion.

   Either way, copy B2F's base and rule lines into `docs/d91_fuse.md` section 5 under a profile 2
   heading, and state in the report when the profiles' fusions differ.
4. Remove the hold. C1p builds the pools on the fusion in `data/fusion.mat`.

### G. No-go on a profile

`fusion_nogo.mat` is written, `kpi1_set.m` stays `'fresh3'`, and the kept fusion is read once on
the fourth set after the rehearsal (3.2). The pools keep their keys: no re-key. The report gives
the reason line (`why`) and the rule's numbers.

## 6. Open items

- The takeover's `final.hold` (3.6), on `d91-takeover`, with a harness scenario.
- KPI 6's rolling-in caveat in the report (3.7).
- Read `v7_d91_deploy_tests.log` when the queue ends; this note gets its verdict lines.
