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
| `4f9615f`, `8749f86` | this note (first version), the wrap check |
| `8dbb767` | the second review's code fixes (section 3.8) |
| `3c4e691` | `deploy_state.m`, the check before a hold is removed or a chain resumes (section 5) |
| `2abd51f`, `d081743` | this note: the second review resolved, procedures, section 7 |
| `a397ff3` | `test_core`: a helper that `functiontests` ran as a test, renamed (4.3) |
| `f3aee61` | the third review: `select_fusion` saves `fusion.mat` whole (`commit_mat.m`), `test_fusion_atomic_save`; the second queue takes profile 2 (3.9) |

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
  Merge it into `v7-dev` together with this branch (step E5) and, if wanted, into `v7-p3`. It
  touches no file under `code/`.
- The first review's evidence stands (recomputed by the second review): the merge trees of
  `7662f4b`, `b4f217a` and `9d8fc86` equal `git merge-tree` of their parents (no evil merge);
  only `test_core.m` and `eval_detector.m` are touched by more than one source branch; no
  `d91-speed` file is touched by `d91-set4`, `d91-fuse` or the deploy commits.

## 2. The deploy commit (`docs/d91_fuse.md` section 7.B, with the review findings)

| File | Change |
|---|---|
| `fusion_pick.m` | name `'branch evidence, phi = 1'`, `cues.phi1 = true`, latch false, N 12, lambda 1e-3, target rule 'N' |
| `kpi1_set.m` | `'fresh3'` |
| `run_stage.m` `run_one` | B2F: `FUSION_REV = true`; `FUSION_FIT = 'enlarged'` unless `SMOKE`; a profile's first B2F (neither second nor third test set) fits on validation as before the revision (3.3). The `%#ok<INUSD>` on `SMOKE` is gone |
| `main.m` | B2F as `run_stage.m` runs it (`run_fusion`) |
| `select_fusion.m` | before any data is read: `FUSION_REV` without the enlarged fit only in a smoke or dev copy (`select_fusion:rev_fit`), the fit set's files (`select_fusion:fit_sets`) and the kept fusion as the rule's base (`select_fusion:pick_base`); a failed rule or base writes `data/fusion_nogo.mat`; `deployed_pick.check.kept`; an earlier no-go record is set aside after any save; the record is written whole to `data/fusion_new.mat` and renamed onto `data/fusion.mat` (`commit_mat.m`), so a cut save leaves the earlier file as it was (3.9) |
| `eval_detector.m` | B3r guard: `deployed_pick` equal to `fusion_pick()` (`eval_detector:fresh3_pick`), placed after the `FM.target_age`/`FM.cues` check and before `fresh3_fusion_old`; the set's own link model (`eval_detector:fresh3_params`); after a no-go the kept fusion is read (3.2); every reading records `fusion_rev`, `fusion_state` and `sample` |
| `prepare_data.m` | B3q copies `params.mat` to `data/splits_fresh3_params.mat` |
| `fusion_nogo.m`, `fusion_reading.m`, `enlarged_ready.m`, `deploy_state.m` | new (3.1-3.3, section 5) |
| `measure_all_kpis.m`, `build_kpi_dashboard.m`, `compare_architectures.m`, `export_report_numbers.m` | the in-sample label (3.1) |
| `test_core.m` | `test_third_test_set`, `test_fourth_test_set` (guard cases, no-go cases, the set's link model, the pre-deploy switch by a stand-in), `test_kpi1_file`, `test_fusion_pick_deploy` (phi = 1, the new source lines), new `test_fusion_nogo_reading`, `test_b2f_deploy_guards`, `test_deploy_state`, `test_fusion_atomic_save` |

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
- `compare_architectures.m` (B3a) reads the second test set (or the test split), both in the fit
  set: its set name carries the label in `results/architecture_comparison.txt`, and
  `results/architecture_comparison.mat` (`arch`: set, `fusion_rev`, `fusion_state`, `sample`, the
  test readings) goes to the report export as `architectures`.
- `measure_all_kpis.m` adds the label to each side reading beside KPI 1, a line `KPI 1 reading:
  read with the <state>`, and the label to KPI 1's value itself when the KPI 1 reading is
  in-sample. That happens only if a profile's fourth set is spent by a failed B3r and its KPI 1
  falls back to the third set (`docs/d91_set4.md` step 6). The third set's reading beside a KPI 1
  of the fourth set is named for what it is: `the rehearsal after the deploy, read with the
  <state>` when it carries a fusion state, else `read before it`.
- `build_kpi_dashboard.m` adds it to the set name.

**Archive the pre-deploy readings.** Before a profile's deploy B2F, copy its `results/` and
`data/fusion.mat` to `uav-gcs-logs\deploy_archive\<p>\pre_deploy_<time>\` (steps D2, E3, F2b).
Those readings were taken with the old fusion. They are the record of the run before the
revision, and `result_status` marks them STALE once the new fusion is saved.

### 3.2 A no-go still reads the kept fusion once on the fourth set

`docs/d91_fuse.md` section 7.G set `kpi1_set.m` back to `'fresh2'` after a no-go, so the kept
fusion's KPI 1 would come from a set that the go/no-go itself had looked at. That is replaced
here (and `docs/d91_fuse.md` 7.F, 7.G and `docs/d91_set4.md` step 1 point here):
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

In code: `run_one` (and `main.m`) fall back to the old selection only for a profile's **first**
B2F, when neither `data/splits_fresh.mat` nor `data/splits_fresh2.mat` exists
(`enlarged_ready`'s third output). Then B2F prints `B2F: no enlarged fit set yet (B3n, B3m): the
fusion is fitted on validation as before the revision` and runs the selection of `9b5c9f1`
(switch off, bit-identical, `docs/d91_fuse.md` section 2). When one of the five files
(`data/dataset.mat`, `splits_fresh.mat`, `dataset_fresh.mat`, `splits_fresh2.mat`,
`dataset_fresh2.mat`) is missing but a test set exists (a rename, an archive, a repair), B2F
does not fall back: it stops with `select_fusion:fit_sets` naming the missing files, so a
profile that should deploy never refits its old fusion silently. On profiles 1 and 3 all five
exist (checked 19.10), so their B2F always deploys. The smoke keeps its own path (validation
revision). Procedure: section 5, F.

`FUSION_REV` without `FUSION_FIT = 'enlarged'` (the revised choice, or a `FUSION_PICK`, on
validation only) saves a design no measurement adopted. `select_fusion.m` refuses it
(`select_fusion:rev_fit`) unless `SMOKE` or `FUSION_DEV` is `true`; the smoke sets `SMOKE`, a dev
driver sets `FUSION_DEV`. So a mistyped hand-run of E6 or F3 on a live tree stops before any
data is read.

### 3.4 The base of the rule equals the profile's kept fusion (N, lambda, latch)

The rule compares the design with the fusion without further columns, at the design's N 12 and
lambda 1e-3, the target rule pos - onset < N, latch off. That is a valid test only if it is the
fusion a no-go keeps. So `select_fusion.m` (enlarged fit) reads the kept `data/fusion.mat`
before any data and requires its `N`, `lambda` and `FM.latch` to equal the pick's, with no
further columns. The one exemption is a rerun of the deploy itself: a kept fusion whose
`deployed_pick` (less its check) equals `fusion_pick()` **and** whose `fusion_rev` is
`fusion_rev_id('enlarged')`. A pick saved on the validation fit (`FUSION_PICK`, fusion_rev
`'validation'`) is not exempt: it counts as further columns, a 'base' no-go. Otherwise it
records a 'base' no-go and stops (`select_fusion:pick_base`).
- Profile 1 kept N 12, lambda 1e-3, latch off; so did profile 3 (`uav-gcs-logs\v7_d86\p1.log`
  and `p3.log`, B2F of 17.10: `Selected N = 12 cycles, lambda 1e-03`, `the latch is off`). The
  old fusion fitted without `target_age` reads the targets at age N (`fusion_target.m`), the
  same rule.
- Profile 2's base is whatever its own validation picks in the chain. If that is not 12 / 1e-3
  / off, the 'base' no-go keeps its fusion, and its KPI 1 is read once on its fourth set with
  it. This is declared here, before any profile 2 number exists.

### 3.5 The speed merge rule is cited, not copied

The rule is `docs/d91_speed.md` section 7.1 (parts 1-4).

**Part 1, the proofs on the d91 code** (`v7_d91_speed_summary.log`, code `70f69f4`). Its check
`git diff --name-only 70f69f4 <tip> -- . ':!docs' ':!code/tests'` is not empty for this branch:
for `3c4e691` it prints 29 files (`policy_monitor`, `branch_ref`, `window_cues`, `fuse_classes`,
`fusion_*`, `fit_sets`, `onset_shape`, `select_fusion`, `eval_detector`, `prepare_data`,
`run_dataset_sweep`, `extract_spectrograms`, `compare_architectures`, `enlarged_ready`,
`deploy_state`, `build_kpi_dashboard`, `edge_map`, `export_report_numbers`, `kpi1_file`,
`kpi1_set`, `measure_all_kpis`, `result_status`, `export_gui_bundle`, `main`, `run_stage`). The
rule says to rerun the proofs on the final commit when it prints a file. They are not rerun here,
because none of the 29 is a dependency of any proof:
- the call closure of the proof drivers (`dev_d91_pool_run`, `dev_d91_order`, `dev_d91_compare`,
  `dev_d91_cells`, `dev_d91_code`, `dev_d91_det`: 80 files; and of A_static's and P_parfor's
  `dev_d91_fec_static`, `dev_d91_parfor_options`, `dev_d91_tick`, `dev_d91_profile`: 76 files),
  taken over every identifier of every non-comment line of `code/` at `3c4e691`, holds none of
  the 29 (scratchpad `closure.py`, 19.10). It over-approximates the calls, so an empty
  intersection is conclusive;
- in particular nothing changed under `code/link/`, `pool_*`, `build_*_pools` or the
  survivability files, and A_static (static FEC check) and P_parfor (pool order) read none of
  the changed files;
- proof (b) and proof (c) run again anyway on each candidate at the target's antenna count
  (part 2), which covers the merged code itself.

**Parts 2-3** (the proofs at the target's antenna count and the merge pair) run for this
branch's candidates in the second queue (section 4). **Part 4** is the tree at the merge
(steps D3 and E5).

### 3.6 The takeover's final phase and profile 1's readings after the deploy

The takeover (`d91-takeover` `55335d7`) has no hold for its final phase: `final_phase` starts once
all three tracks have ended, and LAT, KPI, DASH, WEAK and RPT then read profile 1's results. The
first version of this note claimed that plan A needed no such hold. That was wrong: its step E9
(B3, B3a, B4 and B4s by hand, about 5.5 h) came after profile 1's chain, so if the other tracks
ended first, the final phase could run during it.

**Decision: plan A runs B3, B3a, B4 and B4s inside the stop window, before the resume (E7),
and does not depend on `final.hold`.** The reasons:
- the resumed chain's KPI, DASH, WEAK and RPT, and the final phase's, then read current
  readings taken with the deployed fusion and labelled in-sample; nothing is STALE, and no
  reading is taken after the KPI that should have used it;
- no hand-run MATLAB is left in `uav-gcs-v7` after the chain, so the final phase cannot overlap
  one even without `final.hold`, and plan A does not wait for a takeover feature that is still
  in its fix round;
- it costs about 5.5 h more in the stop window (about 9-10 h in all instead of 3-4 h). That
  delays profile 1's end by the same 5.5 h, but runs nothing twice; the alternative (E9 after the
  chain with `final.hold`) would delay the final phase by the same hours anyway.

`final.hold` is still required on `d91-takeover` (section 7, T1): plan B depends on it, and it is
the safety net for any hand-run after a chain (the wrap check, a repair).

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
3. The tested trees of steps D3 and E5 become the new candidates.

`link_env.m` is read by C1d, C2, C2e, C2g and C2u, and by none of the stages before them, so plan
A (E) would take it with no extra rerun.

### 3.8 The second review (19.10 afternoon) and what changed

| Finding | Severity | Change |
|---|---|---|
| D5 told the operator to accept the wrong kind of failed rerun | high | D5 turned around with exact conditions: a no-go is finished with D6-D7 and then accepted; any other B2F failure is never accepted; a failure after B2F only after a review and a rerun (D5); D8 checks `deploy_state` first |
| Hand-run MATLABs skipped the memory gate | high | every hand-run goes through `uav-gcs-logs\v7_d91_gated_run.sh` with the GB it needs (5.0) |
| Two MATLABs in one worktree once hand-runs mix with takeover releases | medium | the wrapper registers each hand-run in `v7_d86\<p>_hand.busy` and waits for every recorded or command-line MATLAB of the worktree; explicit pre-checks before D8, E10 and F4 (5.0); the takeover's side is T3 (section 7) |
| `final.hold` unresolved; plan A's claim wrong | medium | B3..B4s moved into the stop window (3.6, E7); `final.hold` specified as T1 |
| The stop at SURV3 timed by hand | medium | `p1_cut_after.SURV3` specified as T2; until it is live, the interim rule of E2 (C1d is rerun whenever its done marker is present) |
| E1's queue would print a spurious BLOCKED | medium | second queue `v7_d91_deploy_tests2.sh`: `D91_PROFILE=p1`, test_core logs accepted by code tree (`SAME-TREE`) (section 4, E1) |
| Profile 2 had no archive step | medium | F2b |
| Plan B left profile 2 without a fourth set | medium | plan B holds profile 2's start (T4) so it branches with the deploy code; without T4, B3q in a copy before F3 (E') |
| The deploy path that saves was never run end to end | medium | smoke `dep_*` steps: old-layout kept fusion at the pick's base, B2F that saves (`FUSION_RULE_LOG`, smoke only), `rekey_pools`, C1d, C2, C2e, EDGE; `VERDICT smoke` needs `V7SMOKE dep_B2Fsave SAVED` (section 4) |
| The base exemption let a validation-fit pick count as deployed | low | the exemption needs `fusion_rev_id('enlarged')` (3.4; `test_b2f_deploy_guards`) |
| `FUSION_REV` without the enlarged fit could save on a live tree | low | `select_fusion:rev_fit` unless `SMOKE` or `FUSION_DEV` (3.3) |
| The fallback to validation was silent on profiles that should deploy | low | fallback only when both second and third test sets are absent, else `select_fusion:fit_sets` (3.3) |
| The fourth set's params_id not checked after D5's A0 | low | B3q records `data/splits_fresh3_params.mat`; D4 and E6 copy `params_set4.mat` there; B3r refuses another params_id (`eval_detector:fresh3_params`) |
| In-sample labelling incomplete; the side line misnamed the rehearsal | low | B3a and the report export labelled; the side line names the rehearsal (3.1) |
| The fuse and set4 notes still prescribed the old no-go rule | low | pointers in `docs/d91_fuse.md` 7.F, 7.G and `docs/d91_set4.md` step 1 |
| The speed-rule citation glossed over two deviations | low | 3.5 (part 1's diff and the dependency check); section 4 names the old side exactly |
| Holds written later than needed | low | 5.0: the holds now, with a deadline for the takeover launch |
| (found in the first queue) the helper `run_det_test` ran as a test | - | renamed `det_read_run` (`a397ff3`, 4.3) |

### 3.9 The third review (19.10 evening) and what changed

| Finding | Severity | Change |
|---|---|---|
| A B2F cut between its save and its revision record left `fusion.mat` with the new cues and no record; the rerun took it as the kept fusion, wrote a false 'base' no-go and spent the fourth set on it | medium | `select_fusion.m` writes the whole record (FM, N, lambda, `fusion_rev`, `deployed_pick`) to `data/fusion_new.mat` and only then renames it onto `data/fusion.mat` (`commit_mat.m`: written through to the disk, one rename). A cut save leaves the earlier `fusion.mat` byte for byte and the part record aside in `fusion_new.mat`, which the next save overwrites. `test_fusion_atomic_save` runs `select_fusion.m`'s own save block, cut after the revision id and then whole; the smoke checks that `fusion_new.mat` is gone after `dep_B2Fsave`. And before any B2F rerun, D5(c), E7 and F3 restore the archived pre-deploy `fusion.mat` and set `fusion_nogo.mat` and `fusion_new.mat` aside (5.0, the restore) |
| The release check's awk turned `win64 <pid>` into a wrong PID | low | 5.0 item 2 uses the wrapper's own expression (line 1 stripped to digits, the second field of a `win64` line; for p1 the first field of `takeover_p1_chain_ml.txt`) |
| D4 cited a bare MATLAB command | low | D4 (and E6 through it) gives the params check as a wrapper call at 35 GB with its own log |
| A stop after `C2 done` left profile 1 stuck at C2e (`check_det_id:mismatch`) | low | E2: any stage after C1d with its done marker in the current part is rerun by hand through the wrapper before E10 (step 9b), or plan B; T2's alert names every such stage |
| Plan B could not queue profile 2, and the proofs' detector was profile 3's for every profile | low | the second queue takes `D91_PROFILE=p2`; the detector is chosen by profile (4.2) |
| The wrapper/T3 register-then-check race; the post-chain wrap checks without a hold | low | the protocol is fixed in section 7 (T3: the takeover claims its PID file before it checks the busy file, the wrapper counts a claim as busy or settles; owned by the takeover track); E11 says when `final.hold` is needed |

`f3aee61` adds `commit_mat.m`, called only by `select_fusion.m`, which is one of 3.5's 29 files;
neither is in the proofs' call closure, so 3.5's argument stands.

## 4. Tests

### 4.1 The first queue (19.10 12:24, running)

Script `uav-gcs-logs\v7_d91_deploy_tests.sh` (copy `docs/d91_deploy_tests.sh.txt`), bash PID 8764,
log `v7_d91_deploy_tests.log`, on `4f9615f` (this branch before section 3.8), the profile 3
candidate `192a546` (tree `98cb443`), `2a2b525` and the `v7-p3` tip `29510e7`. Its verdicts
are on code that has changed since (3.8); they are read for what they show, but the merges go
by the second queue. Neither it nor its exports are touched.

How the jobs run (both queues):
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
| `pold` | `p3old` | proof (b), old side |
| `pnew` | `p3m` | proof (b), new side on the candidate; `B_old_vs_new_nrx<n>` |
| `porder` | `p3m` | proof (c): `C_order`, `C_vs_B_nrx<n>` |
| `p3core` | `p3m` | full `test_core` on the candidate; paired with `v7_d91_tests4_tip.log` (`29510e7`) |
| `smoke` | `smoke` (this branch) | serial smoke (below) |

- The profile 3 candidate (4.3 names the current one) is one merge commit with first parent
  `v7-p3` `29510e7` and second parent this branch's tip, built with `git merge-tree
  --write-tree` and `git commit-tree`, without a worktree.
- The old side of its proofs is `v7-deploy-d91-nospeed-on-v7-p3` `2a2b525`: `v7-p3` merged with
  `b4f217a`, that is `v7-p3` plus `d91-set4` and `d91-fuse`, with neither `d91-speed` nor the
  deploy commits. So the proofs compare the candidate against the target without the speedups;
  the deploy commits touch no proof dependency (3.5), so the difference they test is
  `d91-speed`'s. The proof's detector is profile 3's B3m smoke detector (`uav-gcs-b3m-p3\data`),
  read only. `2a2b525` does not change with section 3.8 and is kept.

**No parallel pool anywhere.** `test_core` opens none. The proofs run `pool_cell` on this
process. In smoke mode every pool stage sets `NWP = 0`, takes no parallel turn and opens no
pool:
- `build_policy_pools`, `build_clean_test_pools` and `build_check_pools` (`pool_lpt` with
  `pl = []` runs the jobs in order on this process);
- `map_survivability_boundary`;
- `experiment_survivability_options` (its `parfor (k = 1:2, NWP)` runs on the client).

No other `parfor`, `spmd` or `parpool` is on a smoke path (`train_dqn`, `evaluate_policies`,
`edge_map` hold none). The driver checks for an open pool after every step and reports one
(`V7SMOKE POOL`). No MATLAB command line holds `run_stage(`, so neither the launcher nor the
takeover counts a job as a pipeline stage. The turn file held by profile 1's C1p is never
touched.

### 4.2 The second queue (the follow-up run; all six jobs)

Script `uav-gcs-logs\v7_d91_deploy_tests2.sh` (copy `docs/d91_deploy_tests2.sh.txt`), log
`v7_d91_deploy_tests2.log`; same jobs, same lock (`v7_d91_deploy.lock.d`), so it cannot start
before the first queue's `queue done`. It moves the first queue's job logs aside with a time
stamp. Differences:
- `D91_PROFILE=p3|p1|p2` names the candidate in the summary and the verdict (`VERDICT <p> merge
  candidate`) and picks the proofs' detector: profile 3's B3m detector (`uav-gcs-b3m-p3\data`)
  for p3, profile 1's (`uav-gcs-b3m-p1\data`, as `v7_d91_speed_proofs.sh` used at n_rx 3) for p1
  and p2 (profile 2 has no detector of its own before its chain); `D91_DET_FROM=<data folder>`
  overrides it. The proofs compare old and new pools on one fixed detector, whose features do
  not depend on the antenna count (`link_features.m`), so a detector of another profile still
  gives a valid verdict at the target's n_rx. The start line and the summary print `proof
  detector <path>`;
- a `test_core` log counts for a commit whose code tree (`code/`, `startup.m`, `models/`) equals
  the log's commit's: the summary prints `SAME-TREE (code <c>, expected <e> ...)`, which does
  not block; another tree is STALE as before. This is what lets E1 pair the profile 1 candidate
  with the p3core log, and the `v7-dev` tip with the `v7-p3` tip's log;
- `VERDICT smoke` also needs `V7SMOKE dep_B2Fsave SAVED`.

**Rerun all six jobs** on the commits of this version:
- `core`, `p3core` and `smoke`: the code changed (3.8, 3.9);
- `pold`, `pnew`, `porder`: their code closure did not change (3.5), but the verdict pins the
  proof lines to the candidate's SHA, and the candidate is new.

Start it after `v7_d91_deploy_tests.log` ends with `queue done` (PowerShell, hidden; `<TIP>` the
branch tip, `<P3M>` the rebuilt candidate of 4.3):

    $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
    Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_deploy_tests2.sh'' <TIP> <P3M> 29510e7 2a2b525 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_deploy_tests2.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}

Expected about 2 h of tests and proofs plus 6-8 h of smoke (the `dep_*` steps add C2 and
C2e on smoke pools).

**What the smoke runs** (driver `uav-gcs-logs\d91_smoke_deploy.m`, copy
`docs/d91_smoke_deploy.m.txt`; the queue copies it into its export at its start):
- the chain A0 A4v A5 A6 B1 B2 B2F, B2Fcheck (fusion_rev is `fusion_rev_id('validation')`, no
  `deployed_pick`), B3n B3 B3m B3q B3a B4 OOD B4s;
- B3rguard (B3r refused with `eval_detector:fresh3_fusion_rev`, no marker);
- C1p C1c SURV SURV3 C1d C2 C2e C2g C2u GAL OHP GCSA EDGE LAT KPI DASH WEAK RPT;
- the deploy tail on the smoke data:
  - `B2Fpick`: the measured design on the validation fit (`SMOKE` set); its rule may fail on
    smoke data;
  - `B2Fenl`: the deployed path as `run_stage.m` runs it. Accepted: a save, `pick_rule` or
    `pick_base` (after `B2Fpick` saved, the kept fusion is a validation-fit pick, which is now a
    'base' no-go, 3.4);
  - `REHEARSAL` (DET_TEST = 'fresh2'); `B3r` once (marker printed); `B3ragain` refused
    (`fresh3_read` or `fresh3_started`); KPI, RPT and the KPI 1 lines;
- the deploy path end to end, as plan A resumes profile 1:
  - `dep_B2Fold`: B2F without the revision (the old layout of the live trees' kept fusions),
    then N 12, lambda 1e-3 and latch off written into it, the base of profiles 1 and 3;
  - `dep_B2Fsave`: B2F with `FUSION_FIT = 'enlarged'`, `SMOKE` and `FUSION_RULE_LOG`: the base
    check passes, the rule is computed and printed, and the fusion is saved even when the rule
    fails on smoke data (`deployed_pick.check.rule_logged_only`). The step checks
    `fusion_rev`, `deployed_pick` equal to `fusion_pick()`, `check.kept` (N 12, 1e-3, off, no
    columns), `FM.cues.phi1`, no no-go record left, no `data/fusion_new.mat` left (the rename,
    3.9), and the in-sample state. It prints
    `V7SMOKE dep_B2Fsave SAVED (rule yes|no on smoke data, logged only)`;
  - `dep_REKEY`: `rekey_pools` on the smoke pools; the policy, check and clean pools must carry
    the deployed fusion's det_id;
  - `dep_C1d`, `dep_C2`, `dep_C2e`, `dep_EDGE` on the re-keyed pools and the deployed FM
    (`check_det_id` holds throughout).

Smoke numbers are not results.

Verdict lines at the end of the log:
- `VERDICT deploy test_core`: blocked by `fail-new-only`, `not-run`, `removed-test`, a failing
  `new-test`, MISSING, STALE, TIMEOUT, or a `fail-both` with other diagnostics. Against d90 the
  d91 tests are new tests and must pass.
- `VERDICT <p> merge candidate`: parts 2 and 3 of `docs/d91_speed.md` section 7.1 on the
  candidate, with the same blockers and the three proofs PASS with detector 1 at the target's
  n_rx.
- `VERDICT smoke`: every step OK or the expected refusal, and the deployed fusion saved.

A `fail-both` with the same diagnostics is the target's own state: report it, do not fix it here.

### 4.3 The commits the second queue runs

Built on 19.10 as in 4.1 (no worktree, no conflict), from `f3aee61`, the last code commit (the
third review, 3.9):

    T=$(git merge-tree --write-tree 29510e7 f3aee61)     # 0670e150823261c2303a4d8afc67837ae97b90b0
    C=$(git commit-tree "$T" -p 29510e7 -p f3aee61 -m "...")
    git branch -f v7-deploy-d91-on-v7-p3-q2 "$C"; git push origin v7-deploy-d91-on-v7-p3-q2

| Role | Commit | Note |
|---|---|---|
| this branch (`<TIP>`) | `f3aee61` (or a later docs-only commit) | `core`, `smoke`; every commit after `f3aee61` changes `docs/` only, so its code tree is `f3aee61`'s (`code/` tree `8fd14cd`) |
| profile 3 candidate (`<P3M>`) | `v7-deploy-d91-on-v7-p3-q2` = `05e7a7f` | tree `0670e150823261c2303a4d8afc67837ae97b90b0`; parents `29510e7` and `f3aee61`; its `code/` tree is `8fd14cd` |
| old side | `v7-deploy-d91-nospeed-on-v7-p3` = `2a2b525` | unchanged (4.1) |
| target tip | `v7-p3` `29510e7` | n_rx 4 |

Names: each rebuilt candidate gets a new branch, `-q<n>` after the queue that tests it, because
a forced update of a pushed candidate is not done from here. `v7-deploy-d91-on-v7-p3-q1`
(`192a546`) is the first queue's. `v7-deploy-d91-on-v7-p3` still points at `09671af` (from
`a397ff3`), which was replaced before any test ran on it, as `89dede6` (from `2abd51f`) was
before it; neither is used. `a397ff3` itself renamed the `test_core` helper `run_det_test`
(`det_read_run`): `functiontests` runs every local function whose name ends in 'test', and the
first queue's `core` job showed `V7FAIL test_core/run_det_test`.

**The command to run after the first queue ends** (`v7_d91_deploy_tests.log` ends with `queue
done`; both queues share the lock): all six jobs, with 4.2's hidden launch:

    $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
    Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_deploy_tests2.sh'' f3aee61 05e7a7f 29510e7 2a2b525 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_deploy_tests2.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}

that is `bash v7_d91_deploy_tests2.sh f3aee61 05e7a7f 29510e7 2a2b525` (`D91_PROFILE` p3, the
proofs on profile 3's detector). Step D3 merges `origin/v7-deploy-d91-on-v7-p3-q2` and checks
`HEAD^{tree}` against `0670e150823261c2303a4d8afc67837ae97b90b0`.

## 5. Procedures

### 5.0 General rules, and what to do now

Paths: `L = C:\Users\Adi Suliman\uav-gcs-logs`, `R = L\v7_d86`; in bash `L=/c/Users/Adi\
Suliman/uav-gcs-logs`.

**Now, under either plan, before the takeover runs:**
- write `R\p3_c1p.hold` and `R\p2_c1p.hold` (empty files). The takeover honours both; nothing
  else reads them, so they are harmless before it runs;
- **deadline for the takeover launch: before profile 1's C1c ends (about 25.10).** The old fix
  script (`v7_d87_p3fix.sh`, bash 49732) ignores `p3_c1p.hold` and starts profile 3's C1p on
  the old fusion right after profile 1's SURV3. If the takeover is not running by C1c's end,
  Adi ends bash 49732 (`taskkill /PID 49732 /F`, no `/T`; it has no MATLAB child while
  profile 3 waits) before profile 1's SURV3 ends.

**Every hand-run MATLAB in a live worktree goes through the gate wrapper**, never a bare
`matlab.exe`:

    bash "$L/v7_d91_gated_run.sh" <need_gb> <worktree> <logfile> "<command>"

(copies `docs/d91_gated_run.sh.txt`, `docs/d91_gated_state.ps1.txt`). It:
1. registers the hand-run in `R\<p>_hand.busy` (p1 `uav-gcs-v7`, p3 `uav-gcs-v7-p3`, p2
   `uav-gcs-v7-p2`), atomically; an existing file stops it (exit 3): another hand-run, or a
   killed one, holds the worktree;
2. waits until no takeover MATLAB recorded for the worktree is alive (`takeover_ml_<p>.pid`,
   for p1 also `takeover_p1_chain_ml.txt`), no MATLAB names the worktree in its command line,
   free commit >= `need_gb`, and `v7_d91_speed_gate.ps1` says OK;
3. runs `matlab.exe -singleCompThread -logfile <worktree>\<logfile> -batch "<command>"` in the
   worktree; MATLAB appends `win64 <its PID>` to the busy file first;
4. removes the busy file when MATLAB and its win64 process have ended, and exits with MATLAB's
   status. A wrapper ended by force leaves the file; remove it by hand only after checking that
   no MATLAB of it runs.

Commands never hold `run_stage(` (the wrapper refuses them) or double quotes. Run the steps of a
procedure one after another (`&&`), each with a log of its own under `logs\`.

| Hand-run | need_gb | Why |
|---|---|---|
| B2F (enlarged fit) | 65 | the takeover's `RERUN_NEED_GB` for the same stage: `dataset.mat` 2.7 GB, `splits.mat` 7.0 GB, two test sets 2 x (4.8 + 1.9) GB on disk |
| B3 (split, fresh), B3a, B4, B4s, rehearsal, B3r | 65 | each loads `splits.mat` and a test set; the takeover runs the same stages under 65 GB in profile 3's rerun |
| `rekey_pools`, C1d (`choose_drop_threshold`), the wrap check | 45 | the pools; the takeover's `NEED_GB` for a chain MATLAB |
| `deploy_state`, B3q in a copy | 35 | the gate's own floor (`deploy_state` reads only `fusion.mat`; B3q as `v7_d91_set4.sh`) |

The stage commands (the scripts `run_stage.m` calls, with its variables):

| Stage | `-batch` command |
|---|---|
| B2F (deploy) | `cd(setup_paths()); FUSION_REV = true; FUSION_FIT = 'enlarged'; run('select_fusion')` |
| B3, test split | `cd(setup_paths()); DET_TEST = 'split'; run('eval_detector')` |
| B3, second set | `cd(setup_paths()); DET_TEST = 'fresh'; run('eval_detector')` |
| B3a | `cd(setup_paths()); run('compare_architectures')` |
| B4 | `cd(setup_paths()); run('eval_unseen_snr')` |
| B4s | `cd(setup_paths()); run('eval_unseen_severity')` |
| rehearsal | `cd(setup_paths()); DET_TEST = 'fresh2'; run('eval_detector')` |
| B3r | `cd(setup_paths()); DET_TEST = 'fresh3'; run('eval_detector')` |
| re-key | `cd(setup_paths()); rekey_pools` |
| C1d | `cd(setup_paths()); run('choose_drop_threshold')` |
| state | `cd(setup_paths()); st = deploy_state(); exit(double(strcmp(st, 'none')))` |
| fourth set's params check (35 GB) | `cd(setup_paths()); A = load('params.mat'); B = load('data/splits_fresh3_params.mat'); fprintf('%s %s\n', params_id(A.params), params_id(B.params)); assert(strcmp(params_id(A.params), params_id(B.params)) && strcmp(params_id(A.params), '<id>'), 'params_id differs'); assert(max(h5read('data/dataset_fresh3.mat', '/dataset/run')) < 1e5, 'run id out of the seed block')` |
| C2, C2e, C2g, C2u, EDGE, LAT (45 GB) | `cd(setup_paths()); run('<script>')` with `train_dqn`, `evaluate_policies`, `experiment_combo_generalization`, `experiment_unknown_threat`, `edge_map`, `measure_latency` (`run_stage.m`'s map) |
| KPI, DASH, WEAK, RPT (35 GB) | `cd(setup_paths()); run('<script>')` with `measure_all_kpis`, `build_kpi_dashboard`, `analyze_weak_points`, `export_report_numbers` |

**The restore before any B2F rerun** (D5(c), E7, F3), when no MATLAB runs in the worktree (the
release check's items 1 and 2). The rerun's base must be the kept fusion the profile had before
the deploy, whatever the failed B2F left (with the whole-record save, `fusion.mat` is either
unchanged or a complete new record; 3.9):

    A="$L/deploy_archive/<p>/pre_deploy_<time>"            # D2, E3 or F2b
    t=$(date +%Y%m%d_%H%M%S)
    cp "$A/fusion.mat" "<wt>/data/fusion.mat" && cmp "$A/fusion.mat" "<wt>/data/fusion.mat"
    for f in fusion_nogo fusion_new; do [ -f "<wt>/data/$f.mat" ] && mv "<wt>/data/$f.mat" "<wt>/data/${f}_aside_$t.mat"; done

Then the state hand-run must print `DEPLOY_STATE none` (the kept fusion without a record), and
the B2F rerun follows.

**The release check** (before D8, E10 and F4; `<p>`, `<wt>` the profile and its worktree). All
must hold, else the hold stays:
1. no `R\<p>_hand.busy`;
2. in bash (`p=<p>`, `wt=<wt>`), the state script prints `FREE ...`: no MATLAB names the
   worktree in its command line, and no MATLAB recorded by the takeover for it is alive. The PIDs
   are taken as the wrapper takes them (`pids_of`): line 1 of `takeover_ml_<p>.pid` stripped to
   its digits, the second field of its `win64 <pid>` line, and for p1 the first field of each
   line of `takeover_p1_chain_ml.txt`:

       pids=$( { awk 'NR == 1 { gsub(/[^0-9]/, ""); if ($0 != "") print } $1 == "win64" && $2 ~ /^[0-9]+$/ { print $2 }' "$L/v7_d86/takeover_ml_$p.pid"
                 [ "$p" = p1 ] && awk '$1 ~ /^[0-9]+$/ { print $1 }' "$L/v7_d86/takeover_p1_chain_ml.txt"; } 2>/dev/null | tr -d '\r' | sort -u | tr '\n' ' ')
       D91_PIDS="$pids" D91_WT="C:\\Users\\Adi Suliman\\$wt" MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_gated_state.ps1'

3. the state hand-run (35 GB) ends with status 0 and its log shows `DEPLOY_STATE deployed: ...`
   or `DEPLOY_STATE nogo: ...`. `none` keeps the hold: the B2F did not finish as either.

### D. Profile 3 (idle now; between today and its C1p, about 25.10)

Preconditions:
- the second queue's three VERDICT lines read PASS (`VERDICT p3 merge candidate`);
- the wrap check has reported: done, no change needed (3.7);
- **the takeover runs** (5.0's deadline);
- `origin/v7-p3` is still `29510e7`. If not, rebuild the candidate as in 4.3 and rerun `pold pnew
  porder p3core` with the second queue.

1. **Hold.** `R\p3_c1p.hold` exists (5.0). Check that no MATLAB runs in `uav-gcs-v7-p3`: no
   `R\p3_hand.busy`, the state script prints `FREE`, `R\takeover_ml_p3.pid` names no live
   process, and p3.log's current part has not started C1p.
2. **Archive** (3.1): `results\` and `data\fusion.mat` to `L\deploy_archive\p3\pre_deploy_<time>\`.
3. **Code.** In `uav-gcs-v7-p3`: `git fetch` and `git merge --ff-only
   origin/v7-deploy-d91-on-v7-p3-q2` (the candidate of 4.3). The fast-forward makes the tree
   the tested one.
   - Check that `git rev-parse HEAD^{tree}` equals the candidate tree of 4.3 and of the second
     queue's summary line (`p3 candidate ... (tree <T>)`);
   - check that `git status --short` prints nothing;
   - then `git push`.

   Do not cherry-pick `d91-speed-on-v7-p3` separately first: this branch already holds it.
4. **The fourth set** (`docs/d91_set4.md` step 3):
   - `cp "$L/set4_out/p3/data/"*fresh3* uav-gcs-v7-p3/data/`;
   - `(cd uav-gcs-v7-p3/data && sha256sum -c "$L/set4_out/p3/sha256_fresh3.txt")`: every line
     must end in OK;
   - `cp "$L/set4_out/p3/params_set4.mat" uav-gcs-v7-p3/data/splits_fresh3_params.mat`: the link
     model the set was built with; B3r refuses unless its `params_id` equals `params.mat`'s
     (`eval_detector:fresh3_params`), so the check is repeated by B3r itself after D5's A0;
   - the `params_id` and run-id check of step 3, through the wrapper (5.0's command with
     `<id>` = `7ecc49e97d0a5639f458997caa6b58c8`), never as a bare `matlab`:

         bash "$L/v7_d91_gated_run.sh" 35 uav-gcs-v7-p3 logs/set4_params_check_<time>.txt "cd(setup_paths()); A = load('params.mat'); B = load('data/splits_fresh3_params.mat'); fprintf('%s %s\n', params_id(A.params), params_id(B.params)); assert(strcmp(params_id(A.params), params_id(B.params)) && strcmp(params_id(A.params), '7ecc49e97d0a5639f458997caa6b58c8'), 'params_id differs'); assert(max(h5read('data/dataset_fresh3.mat', '/dataset/run')) < 1e5, 'run id out of the seed block')"

     It must end with status 0 and print the id twice.
5. **B stages by the takeover.** Write `R\p3_brerun.go` holding `B2F B3 B3a B4 B4s`. The takeover
   runs them with A0 first, after profile 1 is past C1c and with 65 GB of commit free, as one
   MATLAB (`run_stage('A0','B2F','B3','B3a','B4','B4s')`). When its part in p3.log has ended,
   exactly one of these holds:
   - **(a) Deployed.** `##### STAGE B4s done` in the rerun's part, and its B2F part shows `The
     kept fusion is the rule's base: N = 12 cycles, lambda 1e-03, latch 0, no further columns`
     and the rule line `... -> rule yes`. Go on with D6.
   - **(b) The no-go.** No `##### STAGE B2F done` in the part; the B2F part shows `No-go recorded
     in data/fusion_nogo.mat` and the error of `select_fusion:pick_rule` (`... fails the adoption
     rule on this fit set: no-go`) or `select_fusion:pick_base` (`... is not the rule's base`);
     and the state hand-run gives `DEPLOY_STATE nogo`. B2F did not save, B3 to B4s did not run,
     and the profile's readings are still those of the kept fusion, which has not changed. The
     takeover raises `ALERT_p3_rerun_failed_<id>`. Do **not** write `p3_rerun.accept` yet: first
     D6 and D7 (the rehearsal and B3r with the kept fusion), then write `R\p3_rerun.accept`, then
     D8.
   - **(c) Any other failure of B2F**: no `STAGE B2F done` and no `No-go recorded` line (another
     error, a crash, an out-of-memory end), or the state hand-run gives `none`. B2F saves its
     record whole (3.9): a cut inside the save leaves the earlier `fusion.mat` as it was and
     the part record in `data/fusion_new.mat`. **Never write `p3_rerun.accept` here**: C1p
     would build its pools on a fusion without a decision. Fix the cause, do the restore of 5.0
     (D2's archive), check `DEPLOY_STATE none`, and write `R\p3_brerun.go` again (a new version
     reruns its whole list).
   - **(d) B2F done, a later stage failed** (`STAGE B2F done` present, one of B3, B3a, B4, B4s
     without its done marker). `fusion.mat` is the deployed revision (check the B2F lines as in
     (a) and `DEPLOY_STATE deployed`). Accept only after a review: read the failing stage's
     error, fix its cause, and rerun that stage and the ones after it, either by a new
     `p3_brerun.go` that lists only them (never B2F again: a second B2F changes `fusion.mat`'s
     time and makes the readings just taken STALE) or by hand with the wrapper (5.0). A new
     `p3_brerun.go` that ends well needs no accept. After a rerun by hand, write
     `p3_rerun.accept` only when every one of B3, B3a, B4 and B4s has a reading newer than
     `fusion.mat`. Then D6.

   B3 to B4s are in-sample descriptions now (3.1).
6. **Rehearsal and B3r**, by hand, after (a), (b) or (d) is settled:

       bash "$L/v7_d91_gated_run.sh" 65 uav-gcs-v7-p3 logs/fresh2_rehearsal_<time>.txt "cd(setup_paths()); DET_TEST = 'fresh2'; run('eval_detector')" &&
       bash "$L/v7_d91_gated_run.sh" 65 uav-gcs-v7-p3 logs/stage_B3r_<time>.txt "cd(setup_paths()); DET_TEST = 'fresh3'; run('eval_detector')"

   The rehearsal must end without an error; B3r runs once.
7. **Record.** Archive the marker, `results\*_fresh3.*` and the log to `L\set4_out\p3\read\`.
   Commit the marker as `docs/d91_fresh3_read_p3.txt` on `v7-p3`, then push (`docs/d91_set4.md`
   steps 5-6). After a no-go (5b), write `R\p3_rerun.accept` now.
8. **Release.** The release check (5.0) for `p3`, `uav-gcs-v7-p3`; then remove `p3_c1p.hold`.
   C1p builds the pools on the deployed fusion (or the kept one). Check C1c's `det_id` line.
9. After profile 3's C1p, rerun wrap check A, B and C on its pools (`docs/d91_fuse.md`
   section 10), through the wrapper (45 GB). It normally runs while the chains still run; if it
   would run after all three chains have ended, E11's rule applies.

### E. Profile 1: plan A (recommended), the swap before C1d

Profile 1's chain runs C1p to RPT in one MATLAB (`42560`, launcher stage list), so there is no
gap between stages. `data/fusion.mat` must stay as it is until C1c has checked its `det_id`.
SURV, SURV3, OHP, GCSA and GAL read nothing of the fusion. C1d, C2, C2e, C2g, C2u, EDGE and LAT
do. So the swap goes after SURV3 and before C1d's choice is used. Code may not change in
`uav-gcs-v7` while C1p, C1c, SURV or SURV3 run (`docs/d91_speed.md` 7.6), so the chain has to be
stopped at SURV3's end.

Conditions:
- the D preconditions;
- the profile 1 candidate built and tested (E1);
- the takeover running;
- the stop: T2 (`p1_cut_after.SURV3`, section 7) in the live takeover, or Adi available when
  SURV3 ends (about 26.10).

If any condition fails, take plan B.

1. **Before SURV3 ends: the candidate.** In the deploy worktree:

       T=$(git merge-tree --write-tree v7-dev <tip>)
       P1C=$(git commit-tree "$T" -p v7-dev -p <tip> -m "Merge v7-deploy-d91 into v7-dev (profile 1 candidate)")
       git diff --stat "$P1C" v7-deploy-d91-on-v7-p3-q2 -- code startup.m models     # must print nothing
       TO=$(git merge-tree --write-tree v7-dev b4f217a)
       P1O=$(git commit-tree "$TO" -p v7-dev -p b4f217a -m "Proof baseline: v7-dev merged with v7-deploy-d91 up to d91-fuse")
       git branch -f v7-deploy-d91-on-v7-dev "$P1C"; git branch -f v7-deploy-d91-nospeed-on-v7-dev "$P1O"; git push -f origin v7-deploy-d91-on-v7-dev v7-deploy-d91-nospeed-on-v7-dev

   Then the n_rx 3 proofs with the second queue, profile 1's label, only the proof jobs:
   `D91_PROFILE=p1 bash v7_d91_deploy_tests2.sh <tip> <P1C> <v7-dev tip> <P1O> pold pnew porder`
   (hidden launch as in 4.2). n_rx is 3 (no `profile.json` on `v7-dev`). The summary pairs:
   - `pair-cand`: the p3core log of the second queue (the profile 3 candidate) against
     `v7_d91_tests4_tip.log` (`29510e7`), each as `SAME-TREE` for `<P1C>` and the `v7-dev` tip;
     this stands for part 3 of the merge rule, because the code trees are equal (checked above,
     and `v7-dev` and `v7-p3` hold the same code, section 1);
   - `pair-core` and the smoke verdict from the second queue's run.

   `VERDICT p1 merge candidate: PASS` is required. Merge `v7-docs-d91` into the candidate if the
   docs should go in too; the code tree stays the same.
2. **Stop the chain at SURV3's end.**
   - With T2 in the live takeover: write `R\p1_cut_after.SURV3` before SURV3 ends. The takeover
     ends profile 1's chain MATLAB at `##### STAGE SURV3 done` and raises
     `ALERT_p1_cut_on_request_*`.
   - Until then, by hand (Adi): when p1.log shows `##### STAGE SURV3 done`, `taskkill /PID <win64
     pid> /F`, with no `/T`. The win64 PID is the `MATLAB.exe` under `...\bin\win64\` among the
     PIDs of `R\takeover_p1_chain_ml.txt` (now `42560`; `Get-Process -Id <pid> | Select
     Path`). The takeover then raises `ALERT_p1_failed_*` and waits for `p1_resume.go`.

   **The rule after the stop** (by hand now; T2's alert names the stages): look at p1.log's
   current part. Without `##### STAGE C1d done` the resume starts at C1d. Whenever `C1d done`
   is present, C1d is rerun in step 9, whatever the time of the stop. A stage cut while it runs
   is simply rerun by the resume. **Any stage after C1d with its done marker** (C2 and later,
   e.g. a stop noticed only after `##### STAGE C2 done`) ran on the old fusion and the old pool
   keys: the resume would start after it, and C2e would stop at `check_det_id:mismatch`. Then
   either:
   - plan A with step 9b: rerun every such stage by hand through the wrapper, in chain order,
     before step 10 (GAL, OHP and GCSA read neither the fusion nor the pools and keep their
     results). With C2 among them that is about two days single-thread (C2 alone is 38-42 h in
     the chain); or
   - plan B (E'), if T1 and T4 are live: change nothing in the worktree and write
     `p1_resume.go`; the chain ends on the old fusion, then E'.

   Decide right after the stop, before step 5: plan B needs the old code for the rest of the
   chain.
3. **Archive** (3.1): `results\`, `data\fusion.mat` and `data\trained_dqn.mat`, if present, to
   `L\deploy_archive\p1\pre_deploy_<time>\`.
4. Check that no MATLAB runs in `uav-gcs-v7` (the release check's items 1 and 2).
5. **Code.** In `uav-gcs-v7`: `git merge --ff-only origin/v7-deploy-d91-on-v7-dev`. Check the
   tree (`HEAD^{tree}` equals the candidate's) and `git status`, then push. The takeover's later
   `v7-p2` branches from this, so profile 2 starts with the deploy code (F).
6. **The fourth set**, as D4, with `set4_out/p1`, `set4_out/p1/params_set4.mat` and
   `add18af2b7532a0bd2f7fbc78f06e526`.
7. **B2F and the B stages**, by hand in `uav-gcs-v7`, one after another through the wrapper
   (5.0's commands, 65 GB each):
   - B2F (about 1 h). Check the base line, `rule yes`, and `DEPLOY_STATE deployed` (the state
     hand-run). A stop at `pick_rule` or `pick_base` (`No-go recorded`, `DEPLOY_STATE nogo`) is
     profile 1's no-go: skip the B stages and the re-key (the fusion and the pools keep their
     keys), go on with step 8. Any other stop: fix the cause, do the restore of 5.0 (E3's
     archive), then rerun B2F; never go on with `none`;
   - after `rule yes`: B3 (test split), B3 (second set), B3a, B4, B4s (about 5.5 h; in-sample
     descriptions, 3.1). This is the former step E9, moved here (3.6).
8. **Rehearsal, B3r, record**: the D6 commands with `uav-gcs-v7`, then the record as in D7,
   committed on `v7-dev` as `docs/d91_fresh3_read_p1.txt`.
9. **Re-key, and C1d if needed** (45 GB each):
   - after `rule yes`: `rekey_pools`. It covers the policy, check, clean_val and clean_test
     pools, and backs each one up first. It stops, changing nothing, on an unknown field
     (profile 1's pools have `maha_val` from `9b5c9f1`, which it knows);
   - if `##### STAGE C1d done` is in p1.log's current part (step 2): `choose_drop_threshold`.

   9b. **Stages after C1d already done** (step 2's rule, plan A): rerun each one in chain order
   with 5.0's commands (C2 to LAT at 45 GB, KPI to RPT at 35 GB), each with its own log under
   `logs\`. The resume starts at the first stage without its done marker in the current part,
   so the stages rerun here are not run again: check in p1.log that the first unfinished stage
   is the one after the last stage rerun.
10. **Resume.** The release check (5.0) for `p1`, `uav-gcs-v7`. Then write `R\p1_resume.go`,
    newer than p1.log. The takeover resumes profile 1 from its first unfinished stage (C1d, or C2
    after step 9's C1d) to RPT, with the new fusion and pools; its KPI and RPT read the B
    readings of step 7.
11. **After the chain**: wrap check A, B and C on profile 1's pools through the wrapper (45 GB).
    It only reads the pools, but the final phase would compete with it for memory and write
    results beside it. With T1 live, always write `final.hold` first and remove it after. With
    T3 live, the wrapper's busy file also holds the final phase in profile 1's worktree.
    Without either, the wrap check must end before profile 2's chain ends (the final phase
    starts only after all three tracks), or wait until the final phase has ended. The same
    applies to D9 if it runs that late.

Cost: about 9-10 h between the stop and the resume (B2F 1 h, the B stages 5.5 h, rehearsal,
B3r, re-key, C1d if needed). Nothing of the closed loop runs twice.

Risks:
- the stop must come before C1d's result is used. Step 2 says how to tell, and step 9 repairs
  it;
- profile 3's C1p may start right after profile 1's SURV3 and run beside these single-thread
  jobs. The wrapper's GB and the gate's one-other-MATLAB rule hold the hand-runs back while it
  needs the memory; profile 3's own takeover gate applies to C1p.

### E'. Profile 1: plan B, the rerun after the chain

Needs T1 (`final.hold`) and T4 (`p2_start.hold`) in the live takeover (section 7); `55335d7` has
neither. Before profile 1's chain ends, write `R\final.hold` and `R\p2_start.hold`.
1. Profile 1's chain ends at RPT with the old fusion. The final phase and profile 2 wait.
2. E3 to E9: archive, code, the fourth set, B2F, the B stages, the rehearsal, B3r, the record,
   the re-key, C1d (always: it ran with the old fusion).
3. Remove `p2_start.hold`. Profile 2 now branches from `v7-dev` with the deploy code, so F
   applies as written (`p2_set4.stages` with `B3q`).
4. C2, C2e, C2g, C2u and EDGE by hand through the wrapper (45 GB; about 2 days, C2 alone is 38-42
   h in the chain and runs single-thread here, so longer). None of them opens a pool.
5. KPI, DASH, WEAK and RPT by hand (`measure_all_kpis`, `build_kpi_dashboard`,
   `analyze_weak_points`, `export_report_numbers`), then remove `final.hold`.

Without T4 the takeover branches `v7-p2` at profile 1's chain end, before the merge. Then:
- do not write `p2_set4.stages` (B3q is not in that code; the chain would stop at an unknown
  stage);
- at profile 2's `p2_c1p.hold`, merge this branch into `v7-p2` (its own candidate and second
  queue, `D91_PROFILE` and the target tip of `v7-p2`, n_rx 2);
- build profile 2's fourth set in a copy as for profiles 1 and 3 (`v7_d91_set4.sh`'s recipe and
  seeds, with profile 2's `params.mat`, `profile.json` and `data/splits.mat`), on the merged
  code, so it writes `data/splits_fresh3_params.mat` itself; copy `*fresh3*` into
  `uav-gcs-v7-p2/data`, check the hashes, the `params_id` and the run ids;
- then F2b, F3, F4.

Cost of plan B: the closed loop of profile 1 runs twice, and the run ends about 2 days later.

### F. Profile 2

Under plan A, `v7-p2` branches from `v7-dev` with this code:
1. Before profile 1's chain ends: `R\p2_c1p.hold` exists (5.0); write `R\p2_set4.stages`
   holding `B3q`. `run_stage.m` then has B3q, so the fourth set is built in the chain, with the
   same recipe and seeds as for profiles 1 and 3 and profile 2's link model; B3q writes
   `data/splits_fresh3_params.mat`.
2. The chain runs A0 to B2, then B2F on validation (3.3; its log line says so). Then B3n and B3m
   (its first reading of the third test set), B3q, B3, B3a, B4, OOD and B4s. It stops at the
   hold.

   2b. **Archive** (3.1), on either outcome of step 3: `results\` and `data\fusion.mat` to
   `L\deploy_archive\p2\pre_deploy_<time>\`. The rehearsal of step 3 overwrites
   `results\eval_detector_metrics_fresh2.mat`, profile 2's only out-of-sample reading of the
   third set with its validation fusion (B3m), and B3 to B4s overwrite the rest.
3. **Decision**, by hand: B2F with the enlarged fit set (5.0's command, 65 GB). The outcomes:
   - `rule yes` (`DEPLOY_STATE deployed`): B3 (both sets), B3a, B4 and B4s (in-sample
     descriptions), the rehearsal, B3r once and its record (`docs/d91_fresh3_read_p2.txt` on
     `v7-p2`);
   - `pick_rule` or `pick_base` (`DEPLOY_STATE nogo`): the no-go record (3.2). Then the rehearsal
     and B3r once with the kept fusion, and the record;
   - any other stop: fix the cause, do the restore of 5.0 (F2b's archive), then rerun B2F.

   Either way, copy B2F's base and rule lines into `docs/d91_fuse.md` section 5 under a profile 2
   heading, and state in the report when the profiles' fusions differ.
4. **Release.** The release check (5.0) for `p2`, `uav-gcs-v7-p2`; then remove `p2_c1p.hold`.
   C1p builds the pools on the fusion in `data/fusion.mat`.

### G. No-go on a profile

`fusion_nogo.mat` is written, `kpi1_set.m` stays `'fresh3'`, and the kept fusion is read once on
the fourth set after the rehearsal (3.2). The pools keep their keys: no re-key. The report gives
the reason line (`why`) and the rule's numbers.

## 6. Open items

- The takeover features of section 7 on `d91-takeover`, with their harness scenarios: T3 and the
  launch before 25.10 for profile 3; T2 for plan A's stop; T1 and T4 for plan B.
- The holds of 5.0 (`p3_c1p.hold`, `p2_c1p.hold`), written by Adi or on his word.
- Read `v7_d91_deploy_tests.log` when the first queue ends, then start the second queue (4.2,
  the command in 4.3); this note gets its verdict lines.
- T3's other half: the wrapper or its state script counts a takeover claim as busy, or settles
  after registering (section 7, T3), with T3, on `d91-takeover`.
- KPI 6's rolling-in caveat in the report (3.7).

## 7. Takeover features required (spec for `d91-takeover`)

The procedures above need four features in `ops/v7_d91_takeover.sh` (`55335d7` has none of
them). Each is read again after every wait, like the existing holds, never removed by the
takeover (except T2's file, renamed once used), listed by `status`, and covered by a harness
scenario in `ops/d91_takeover_test.sh`.

**T1. `final.hold`** (`R\final.hold`). While it exists, `final_phase` starts no MATLAB:
- read at the start of `final_phase`, before each profile's part header, again right after
  `wait_idle` returns, and immediately before each `run_ml` (LAT..RPT and the bundle);
- while waiting: one log line `final phase waits: final.hold`, heartbeats, naps of `POLL`; an
  alert `ALERT_final_hold_<mtime>` after 24 h (it may be intended);
- removing it lets the final phase go on from where it waited (the idle wait starts again);
- harness: (a) the hold present when the tracks end: nothing runs; removed: LAT..RPT run;
  (b) the hold written during `wait_idle`: no LAT; (c) written between two profiles: the second
  profile waits; (d) with a track died, the existing skip logic is unchanged.

**T2. `p1_cut_after.SURV3`** (the only stage name accepted; another name raises
`ALERT_p1_cut_invalid_<name>` and does nothing). While it exists and profile 1's current part
has no end marker:
- profile 1's track checks p1.log every `STEP` (not `POLL`) for `##### STAGE SURV3 done` in the
  current part, so the cut lands within seconds, while C1d is still loading;
- the PID to end is the chain's `win64\MATLAB.exe` only: from `takeover_p1_chain_ml.txt` for the
  launcher's chain, which must therefore record the role of each PID (`<pid> <created> win64` or
  `... launcher`, found by the executable's path `\bin\win64\MATLAB.exe`), or the `win64 <pid>`
  line of `takeover_ml_p1.pid` for a takeover part. Before the kill the PID must be alive, its
  executable path end in `\win64\MATLAB.exe`, and its creation time equal the recorded one;
  otherwise nothing is ended and `ALERT_p1_cut_pid_<stamp>` names what failed;
- the kill is `taskkill /PID <pid> /F`, never `/T`, never the `bin\matlab.exe` launcher alone;
- after it: the line `##### cut after SURV3 on request (p1_cut_after.SURV3) <date> #####` in
  p1.log, the control file renamed to `.used_<time>`, and `ALERT_p1_cut_on_request_<stamp>`
  naming every stage from C1d on whose done marker was already in the part (C1d is then rerun,
  later ones as E2's rule says). The chain's end then follows the existing failed or cut path:
  nothing resumes before `p1_resume.go`;
- if `SURV3 done` is already in the part when the file is first seen, the cut happens at once
  and the alert says so;
- harness: (a) the file before SURV3: the stub chain is cut at the marker, the win64 stub
  ended, the launcher stub not ended by the takeover, no `/T`; (b) the file after SURV3 and
  after `C1d done`: cut at once, the alert names C1d; (c) a PID whose creation time differs: no
  kill, alert; (d) another stage name: alert, nothing ended; (e) after the cut, no resume
  without `p1_resume.go`.

**T3. Hand-run registration** (`R\<p>_hand.busy`, written by `v7_d91_gated_run.sh`). While it
exists, the takeover starts no MATLAB in that profile's worktree:
- checked in `run_ml` right before the start (after `ml_guard` and `scripts_wait`), and in the
  checks that release work there: `p1_run` before its part header, `run_ab`, `run_rerun`,
  `run_c` (inside `c1p_still`), `pools_check`, and `final_phase` per profile;
- a takeover that finds it while about to start: one log line `<p>: waits for a hand-run
  (<p>_hand.busy: <its cmd line>)`, naps of `POLL`, `ALERT_hand_busy_<p>_<mtime>` after 12 h with
  the file's content; never removes or edits it;
- the file's existence is the signal; its `win64 <pid>` line is shown in the alert, not used to
  clear it (a stale file is removed by Adi after checking that the PID is gone);
- not chosen: the wrapper writing `takeover_ml_<p>.pid` itself. `ml_guard` removes that file when
  its PIDs are gone and `run_ml` overwrites it, so two writers would race;
- **the register-then-check race, and the protocol that closes it.** A takeover start that has
  passed T3's check but whose MATLAB does not show yet is invisible to the wrapper: takeover
  command lines do not name the worktree, and the state script counts a recorded PID only when
  it is MATLAB or has a MATLAB child. The protocol, two flags each written before the other is
  read:
  1. takeover: write `takeover_ml_<p>.pid` first (a claim: its bash's Windows PID and `claim
     <pid>`), then check `<p>_hand.busy`; when the file is there, remove the claim and wait. The
     takeover track's work in progress does exactly this (`start_claim` in `run_ml`, read in the
     `d91-takeover` worktree on 19.10 at 15:39, uncommitted on `78e7eb4`; it also records the
     hand-run's `win64` PID in `takeover_hand_<p>.pids`, so a busy file removed too early still
     holds the worktree while that MATLAB lives);
  2. wrapper: write `<p>_hand.busy` first (as now), then read the PID file, and count a live
     PID whose file holds a `claim` or `msys` line as busy even without a MATLAB child; or,
     equivalently, wait a settle time of at least `2 x STEP + 10` s (30 s with `STEP` 10) after
     registering before the first check, by which time a start that passed its check shows a
     MATLAB child. The wrapper and `v7_d91_gated_state.ps1` (13:15) do neither yet: they check
     at once and count a claiming bash as free;
  3. then a takeover start always sees the busy file, or the wrapper always sees the start.

  Step 2 is a change to `v7_d91_gated_run.sh` or `v7_d91_gated_state.ps1`, owned by the takeover
  track with T3 (it changes the wrapper if needed). Until both sides are in, the race is latent:
  every hand-run of section 5 runs under a hold (`p3_c1p.hold`, profile 1's stop before
  `p1_resume.go`, `p2_c1p.hold`) under which the takeover starts nothing in that worktree,
  apart from the wrap checks of D9 and E11 (E11 says how they are held);
- harness: (a) the file present when a rerun, a resume, C1p or the final phase would start:
  nothing starts until it is removed; (b) written during `code_wait`/`headroom_wait`: no start;
  (c) removed: the start goes ahead; (d) `status` lists it.

**T4. `p2_start.hold`** (`R\p2_start.hold`). While it exists, profile 2's track neither branches
`v7-p2` nor starts anything, even when profile 1's chain has finished or `p2_start.go` is
present:
- read in `track_p2`'s wait loop and again immediately before `p2_prepare`;
- one log line `p2: start held (p2_start.hold)`; `ALERT_p2_start_hold_<mtime>` after 48 h;
- removing it lets `p2_prepare` branch from `v7-dev`'s tip of that moment (after plan B's merge);
- harness: (a) profile 1 complete and the hold present: no branch, no `p2.log`; (b) removed:
  `v7-p2` branched from the current `v7-dev` tip, its commit in `code_commit.txt`; (c) with
  `p2_start.go` and the hold: still held; (d) `p2.abandon` while held: the track ends.
