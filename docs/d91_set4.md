# d91: the fourth detector test set (B3q) and its single reading (B3r)

Branch `d91-set4` (from `d90-loop` 2cbe559). Adi decided this on 2026-10-18 (option A). The fusion-only "branch evidence" revision
for antenna_fault is selected by nested CV, by sub-run, on an enlarged fit set:
- validation;
- the first test split;
- the second test set (B3n, `_fresh`);
- the third test set (B3m, `_fresh2`).

All of these sets have been read already. So KPI 1 is read **once**, on a new fourth test set, after the go/no-go
(21.10 evening). This branch builds that set and adds the reading path. **Nobody reads the set before the go/no-go.**

## What the branch adds

| Piece | Where | What it does |
|---|---|---|
| `FRESH_SET = 3` | `run_dataset_sweep.m`, `extract_spectrograms.m`, `prepare_data.m` | The third set's recipe: 4 sub-runs per cell, the compensated counts, every sub-run in the test fold 6. It writes `data/dataset_fresh3.mat`, `data/spectrograms_fresh3.mat` and `data/splits_fresh3.mat` (z-scored with the profile's training statistics from `data/splits.mat`). |
| Stage `B3q` | `run_stage.m` (`build_fresh_test3`), `main.m` (`RUN.build_fresh_test3`) | Builds the set and **does not read it**: no `eval_detector`, no `DET_TEST`. |
| Stage `B3r` | `run_stage.m` (`read_fresh_test3`), `main.m` (`RUN.read_fresh_test3`) | Runs `eval_detector` with `DET_TEST = 'fresh3'`. Outputs: `results/eval_detector_metrics_fresh3.mat`, `detector_predictions_fresh3.mat`, `confusion_matrix_fresh3.png` and `accuracy_vs_snr_fresh3.png`. |
| The switch | `code/evaluation/kpi1_set.m` (now `'fresh2'`) | Every KPI 1 reader goes through `kpi1_file.m`, which follows this one switch: `measure_all_kpis`, `build_kpi_dashboard`, `analyze_weak_points` and the GUI. With `'fresh2'`, readers stay on the third test set even when a `_fresh3` reading exists. With `'fresh3'`, they read the fourth set and never fall back: a missing reading shows as missing. |
| Guards in `eval_detector.m` | `DET_TEST = 'fresh3'` | The reading stops unless all of these hold: `kpi1_set()` is `'fresh3'` (`eval_detector:kpi1_set`), `data/splits_fresh3.mat` exists (`eval_detector:fresh3`), `results/eval_detector_metrics_fresh3.mat` does not exist yet (`eval_detector:fresh3_read`), and neither does `results/fresh3_read_started.txt` (`eval_detector:fresh3_started`). Its other inputs are checked next, still without loading the set: `data/splits.mat`, `data/trained_detector.mat`, `data/fusion.mat` and `params.mat` exist (`eval_detector:fresh3_input`); `data/fusion.mat` holds `val_latch_oof` (read with `whos -file`; `eval_detector:fresh3_fusion`); it is the adopted revision: it holds `cvy`, `cvo` and `fusion_rev` equal to `fusion_rev_id('enlarged')` (the id `select_fusion.m` stores with FUSION_REV and FUSION_FIT = 'enlarged', patch in step 2 below), and its `FM` has `target_age` and `cues` (`eval_detector:fresh3_fusion_rev`); it is not older than the detector's `trained_at` (`eval_detector:fresh3_fusion_old`); `results/eval_detector_metrics_fresh2.mat` exists and is not older than the fusion or `trained_at`, so the same path has just run to its end on the already-read third set (`eval_detector:fresh3_rehearsal`); and no committed record `docs/d91_fresh3_read_*.txt` (aborted ones aside) holds `params_id` of this `params.mat` (`eval_detector:fresh3_recorded`). Once all of these pass, B3r writes that marker before it loads any data and prints `B3r: start marker written (results/fresh3_read_started.txt)`, so a reading that crashes after printing its numbers still counts as the one reading. The marker holds the time, the commit with `+ local changes in code, models or startup.m` when those differ from it (untracked files included), `code_tree` (`git rev-parse HEAD:code`), `params_id`, `untracked_m` (every untracked, not ignored `.m` file of the repository, which could shadow the code; `none` when there is none), and the SHA-256 and modification time of `data/trained_detector.mat` (with its `trained_at`) and `data/fusion.mat`. After the set is loaded, a set without frame positions stops before any number is printed (`eval_detector:fresh3_pos`), so the fusion is never skipped silently. No outcome is printed before the fusion and the latch have run: the per-frame lines are held until then. `detector_predictions_fresh3.mat` is saved before `eval_detector_metrics_fresh3.mat`, so a reading cut off between the two still leaves WEAK its input. |
| Other readers | `result_status.m` (a `_fresh3` reading older than `data/fusion.mat` or than the detector's training is STALE with its own reason: read once with an earlier fusion or detector, cannot be reread), `export_report_numbers.m` (`detector_fourth`, `kpi1_set`), `export_gui_bundle.m`, `measure_all_kpis.m` | These readers pick up the fourth set's file when it is present. `measure_all_kpis` lists the third and second sets' readings beside the fourth. |

## Seeds (disjoint from every existing stream)

| Set | Sub-run seed | Speed stream (global twister) |
|---|---|---|
| dataset (A5) | 3 000 000 + run id | 2027 |
| second test set (B3n) | 3 500 000 + run id | 2029 |
| third test set (B3m) | 6 500 000 + run id | 2035 |
| **fourth test set (B3q)** | **6 000 000 + run id** | **2037** |

The 6 000 001 to 6 099 999 range lies between the second B4s reading (5 500 001 to 5 599 999) and the third test set. It sits:
- above every pool seed (below 2 000 000);
- below the pools' shadowing candidates (10 000 001 and up);
- below 2^26, so its streams (`seed_base` = 64 x seed, plus offsets below 64) stay below 2^32.

Before this branch, no file outside the tests used the range. The only other seeds near it are test-only seeds (3.1M, 3.2M, 3.3M, 4.92M, 7.0M), and the fourth set does not touch them.

The tests check this:
- `test_seed_streams_disjoint` includes `6000000 + k`. It also checks that the SEED0 values in `run_dataset_sweep.m` are exactly {3.0M, 3.5M, 6.0M, 6.5M}, so a new set cannot skip the check.
- `test_fourth_test_set` checks that the speed streams are exactly {2027, 2029, 2035, 2037}.

## The generator is the one that built every earlier set

Two diffs:
- `git diff 9b5c9f1 d91-set4` over the data path: every code file reachable from `run_dataset_sweep`, `extract_spectrograms`, `prepare_data`, `init_params` and `build_threat_model` (69 files, closure by name with comments stripped), plus `params.mat`, `models/` and `startup.m`.
- `git diff aea4cc1 208602b`: aea4cc1 is the commit that actually built B3m. Its code differs from 9b5c9f1 only in `mmse_predict.m`, `validate_phy.m`, `measure_latency.m` and `build_policy_pools.m`. `mmse_predict` runs inside `extract_closed_loop_frames`, but its output `F.mmse_pred` is not stored in the dataset and draws no random numbers. So the B3m data equal 9b5c9f1's.

The first diff shows only these hunks:
- `run_dataset_sweep.m`: the `SET3` flag and its `if SET3` block (seed, file name, speed stream). This is the new path only.
- `extract_spectrograms.m`:
  - the fresh3 file names (new path);
  - from d90, an error for a dataset in the old `align` layout. A new dataset has `align_gcs`, so it never fires;
  - from d90, two metadata flags (`frames_checked`, `src_align_gcs`). No value of `X` or `feats` changes.
- `prepare_data.m`:
  - the set index 1/2/3 in place of the boolean `third`. Sets 1 and 2 keep their files and names;
  - from d90, the `checked_a6` guard, an assert only.
- `window_cues.m` (d90: the `'extra'` columns). A false positive of the name closure: the transpose `D.bch'` in `run_dataset_sweep.m` hid a comment. It is not called on the data path. Even if it were, its numeric branch is unchanged: d90 added only a char switch and new local functions.

d90 changed no generator value. So the set is built from `d91-set4` itself (31ab0de), with no minimal patch needed on 9b5c9f1.

After the builds started, `run_dataset_sweep.m` gained one line after its loops: `assert(run_id < 100000, 'run_dataset_sweep:run_id', ...)`. The sub-run seeds SEED0 + run id stay inside their 100 000 block only while this holds, and `test_seed_streams_disjoint` checks k = 1 to 99 999. The assert only compares a scalar: it draws no random number and changes no variable or output, so every set it lets through is the same as without it. The running builds (31ab0de) do not have it; their run ids are checked at the merge (step 3 below).

Before the build, A0 in each copy gave the same `params_id` as the profile's live `params.mat`:
- P1: `add18af2b7532a0bd2f7fbc78f06e526`, n_rx 3;
- P3: `7ecc49e97d0a5639f458997caa6b58c8`, n_rx 4.

`set4_build.m` checks this again before B3q and stops if it differs. Verbatim copies of the two drivers and of the script are kept here: `docs/d91_set4_build_p1.m.txt`, `docs/d91_set4_build_p3.m.txt` (untracked `set4_build.m` of each copy) and `docs/v7_d91_set4.sh.txt` (`uav-gcs-logs/v7_d91_set4.sh`).

## The build (running)

- Copies: `C:\Users\Adi Suliman\uav-gcs-set4-p1` and `-p3`, detached worktrees of 31ab0de. Each holds:
  - the profile's `params.mat` (also kept as `params_profile.mat`);
  - `profile.json` (P3 only);
  - `data/splits.mat`, needed only for `split_norm`: the training z-score and the classes.

  No detector, no fusion and no result files are copied, so nothing in a copy can read the set. The live worktrees (`uav-gcs-v7`, `uav-gcs-v7-p3`) were only read.
- Script: `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_set4.sh`, started hidden through WMI on 2026-10-18 05:14 (bash PID 9800; the P1 MATLAB is PID 8036; lock `uav-gcs-logs/v7_d91_set4.lock`).
  - It runs P1, then P3, one at a time. Each starts only with at least 35 GB of free commit (checked every 5 min, given up after 48 h).
  - MATLAB runs as `-singleCompThread -batch set4_build`. The command line holds no `run_stage(`, so the launcher's `stage_pids` does not count it, the same as the B3m copies.
  - Expected: 6-7 h per profile (B3m took 348 min with other jobs running). P1 should end about 18.10 12:00 and P3 about 18.10 19:00.
- Logs: `uav-gcs-logs/v7_d86/p1_set4.log` and `p3_set4.log`. The copies also keep their own `logs/stage_*.txt`.
- Output: `uav-gcs-logs/set4_out/p1` and `/p3`. Each holds:
  - `data/*fresh3*` (dataset, spectrograms, splits);
  - `sha256_fresh3.txt`;
  - `params_set4.mat`;
  - `logs/`.

  Nothing is written into the live profiles.

## How to read the set later (after the go/no-go only)

1. Decide the go/no-go on the enlarged fit set (the fusion track). Do not open `set4_out` before then. Checking file sizes and hashes is allowed; loading the labels or the frames is not.
2. In the commit that deploys the adopted revision (the merge of `d91-fuse` and this branch):
   - set `kpi1_set.m` to `'fresh3'`;
   - change the two `kpi1_set()` expectations in `test_core.m`: `test_third_test_set` and the first part of `test_fourth_test_set`;
   - `run_stage.m` `run_one`: `FUSION_REV = true; FUSION_FIT = 'enlarged';` before `select_fusion` (`docs/d91_fuse.md`, section 7, step 1);
   - `select_fusion.m` stores the revision's id, which B3r compares with `fusion_rev_id('enlarged')` (patch below; `d91-fuse` is frozen while its measurement runs, so the patch is applied at this merge, not before).

   With no-go, the switch stays `'fresh2'`, and the set waits, unread, for the revision that is adopted after the run.

   The patch for `select_fusion.m` (end of the script; today's line `if REV, save('data/fusion.mat', 'cvy', 'cvo', '-append'); end`):
   ```matlab
   if REV
       fit_name = 'validation';
       if exist('FUSION_FIT', 'var') && strcmp(FUSION_FIT, 'enlarged'), fit_name = 'enlarged'; end
       fusion_rev = fusion_rev_id(fit_name);                % B3r reads the fourth test set only with fusion_rev_id('enlarged')
       save('data/fusion.mat', 'cvy', 'cvo', 'fusion_rev', '-append');
   end
   ```
   and in the output list of its header: `with FUSION_REV also FM.cues, FM.target_age, the cvy, cvo tables and fusion_rev (fusion_rev_id.m)`. Without FUSION_REV the file keeps its old layout, so the bit-identity of the switch when off (`d91_fuse.md`, section 2) holds. With the patch, add to `test_fourth_test_set`:
   ```matlab
   sf = fileread(which('select_fusion'));
   verifyNotEmpty(tc, strfind(sf, 'fusion_rev = fusion_rev_id(fit_name);'));
   verifyNotEmpty(tc, strfind(sf, 'save(''data/fusion.mat'', ''cvy'', ''cvo'', ''fusion_rev'', ''-append'');'));
   verifyNotEmpty(tc, strfind(fileread(which('run_stage')), 'FUSION_REV = true; FUSION_FIT = ''enlarged'';'));
   ```
   and to `d91_bitid/rev.m` (the revised smoke run) a check that its `fusion.mat` holds `fusion_rev` = `fusion_rev_id('validation')`, or `'enlarged'` with `FUSION_FIT`.
3. For each profile, when no MATLAB of that profile runs:
   - copy `set4_out/<p>/data/*fresh3*` into the profile's `data/`;
   - check the hashes from the profile's `data/` folder (the list names the files without a folder):
     `(cd <profile>/data && sha256sum -c "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/sha256_fresh3.txt")`.
     Every line must end in `OK`;
   - check, in one MATLAB started in the profile's folder, that its `params.mat` has the link model the set was built with (`params_set4.mat`, and the id above: `add18af2b7532a0bd2f7fbc78f06e526` for P1, `7ecc49e97d0a5639f458997caa6b58c8` for P3) and that the run ids stay inside the seed block. For P1 (for P3, `p3` and its id):
     ```
     matlab -singleCompThread -batch "A = load('params.mat'); B = load('C:\Users\Adi Suliman\uav-gcs-logs\set4_out\p1\params_set4.mat'); fprintf('%s %s\n', params_id(A.params), params_id(B.params)); assert(strcmp(params_id(A.params), params_id(B.params)) && strcmp(params_id(A.params), 'add18af2b7532a0bd2f7fbc78f06e526'), 'params_id differs'); assert(max(h5read('data/dataset_fresh3.mat', '/dataset/run')) < 1e5, 'run id out of the seed block')"
     ```
     The `h5read` reads only the run ids, not the labels or the frames, so it does not count as reading the set.
4. Per profile, in this order (no MATLAB of that profile running):
   1. **B2F with the adopted revision:** `run_stage('B2F')` with the deploy commit. Check that `load('data/fusion.mat', 'fusion_rev')` gives `d91_branch_evidence_enlarged`. A B2F without the revision writes the old layout, and B3r refuses it (`eval_detector:fresh3_fusion_rev`).
   2. **Everything that writes the three frozen files runs now, never after B3r:** any OOD stage (it re-saves `data/trained_detector.mat` with `-append`), and no B2.
   3. **The rehearsal on the third test set, without rebuilding it** (B3m would rebuild it, 6-7 h), from the profile's folder:
      `matlab -singleCompThread -logfile logs/fresh2_reread_<time>.txt -batch "cd(setup_paths()); DET_TEST = 'fresh2'; run('eval_detector')"`.
      It runs the same path as B3r with the same detector, fusion and params, on a set already read, and only `results/*_fresh2.*` change. It must end without an error: B3r refuses unless `results/eval_detector_metrics_fresh2.mat` exists and is not older than `data/fusion.mat` and the detector's `trained_at` (`eval_detector:fresh3_rehearsal`). Then `run_stage('B3')` (and B3a, B4, B4s, `d91_fuse.md` section 7, step 2), so the third and second sets' readings beside KPI 1 are current.
   4. **`run_stage('B3r')`, once.** A second B3r refuses to run (`eval_detector:fresh3_read`, `eval_detector:fresh3_started` once the marker exists, or `eval_detector:fresh3_recorded` once step 5 is committed).
   5. **The fusion track's reruns:** `rekey_pools`, the pools and the closed loop from C1d on (`d91_fuse.md` section 7, step 4). The new `FM` also changes `detector_id` (`detector_id.m` reads `FZ.FM`), so LAT and EDGE (they carry `det_id`) are rerun too. Then KPI, DASH, WEAK and RPT. KPI 1 is read from `results/eval_detector_metrics_fresh3.mat`, with the third and second sets' readings beside it.
   - **Freeze `data/trained_detector.mat`, `data/ood_thresholds.mat` and `data/fusion.mat` from B3r until RPT.** In that profile after its B3r: no B2, B2F or OOD stage and no other save of these three files. The reading cannot be repeated, so a newer detector or fusion leaves KPI 1 STALE for good (`result_status`: read once with an earlier detector or fusion, cannot be reread). The SHA-256 lines in the marker show which files the reading used.
5. Right after B3r, archive the marker and the results of each profile, and commit the record. The marker lives in the profile's `results/`, which `.gitignore` excludes, so it is not committed and `git clean -X` would delete it:
   - `mkdir -p "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/read" && cp <profile>/results/fresh3_read_started.txt <profile>/results/*_fresh3.* <profile>/logs/stage_B3r_*.txt "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/read/"`;
   - right away, `cp <profile>/results/fresh3_read_started.txt <profile>/docs/d91_fresh3_read_<p>.txt`, commit it on the profile's branch and push. From then on B3r refuses in every checkout of that branch that carries the record: any `docs/d91_fresh3_read_*.txt` (not `*_aborted*`) with the line `params_id <the profile's id>` stops it (`eval_detector:fresh3_recorded`), even in a recreated worktree with the set copied in again.

   Nobody deletes the marker or the record to rerun B3r.
6. A marker with no `_fresh3` result beside it means that a B3r stopped after writing it. The error itself shows in the console or in the `-batch` output, not in the stage log: `run_stage` turns the diary off in an `onCleanup`, which runs before MATLAB prints the uncaught error (to be confirmed in MATLAB). Decide from the lines the stage log (`logs/stage_B3r_<time>.txt`) holds:
   - The set was not read when the log holds, after `B3r: start marker written (results/fresh3_read_started.txt)`, no line other than `Loading test data and trained model...`, `Test set: fourth test set (<n> frames)`, `Running inference on <n> test samples...`, `Decision over the last <N> cycles (temporal fusion)` and either `Decision with the monitor's latched cause of a lost branch (threshold <x>)` or `Decision by the fused class: ...`. These lines carry no label, score or outcome: the frame count is the build's, and N and the threshold were chosen on the fit set. B3r prints its first outcome (the per-frame accuracy) only after the fusion and the latch have run. This covers a failure in loading `data/splits.mat` or `data/splits_fresh3.mat`, a normalization mismatch, `eval_detector:fresh3_pos`, the network's inference, the fusion and the latch. Then: move the marker and the log to `set4_out/<p>/read/` as `fresh3_read_started_aborted_<time>.txt` and `stage_B3r_<time>.txt`, commit the marker as `docs/d91_fresh3_read_<p>_aborted_<time>.txt` (it does not block), write the cause in this note, fix it without touching the three frozen files (when one has to change, the next marker records its new hash, and the rehearsal of step 4.3 is redone), and run B3r once more under the same guards.
   - When the log shows any other line (an accuracy, F1, threshold, confusion or Eb/N0 line) or is missing, the reading counts. Commit the marker as `docs/d91_fresh3_read_<p>.txt` (step 5). Do not rerun B3r: the fourth set is spent in that profile. Its KPI 1 stays on the third test set (`kpi1_set.m` back to `'fresh2'` in that profile's worktree), and this note records the case with whatever numbers the log shows.
   - Adi may prefer a stricter rule: only a failure before `Test set: fourth test set` allows another run. With the rehearsal of step 4.3, the path after the marker has already run to its end on the third set with the same files, so a failure there is unlikely either way.
7. Profile 2 has no fourth set yet. Only **B3q** (the build, it reads nothing) may run in profile 2's chain, through the takeover's `p2_set4.stages` holding `B3q`, or in a copy of its own the same way as P1 and P3, one profile at a time. **B3r is never listed in `p2_set4.stages`:** it runs by hand after the go/no-go, after profile 2's OOD and after the rehearsal of step 4.3, as for the other profiles. In the chain it would come before B3, B3a, B4, OOD and B4s, and OOD re-saves the detector after the reading, which breaks the freeze of step 4. The takeover's note and script (`v7_d91_takeover.md`/`.sh`, at 7edee48) still give `B3q B3r` as the example; that example has to become `B3q` on `d91-takeover` (the takeover track, not this branch).

## Tests

Focused run, one MATLAB, `-singleCompThread`, 2026-10-18: **12/12 passed**. The tests:
- `test_m_files_parse`
- `test_seed_streams_disjoint`
- `test_third_test_set`
- `test_fourth_test_set` (new)
- `test_kpi1_file`
- `test_main_stage_list`
- `test_result_status`
- `test_gui_bundle_drops_stale`
- `test_a6_stamp_required`
- `test_harmed_readings`
- `test_kpi6_union_and_intervals`
- `test_split_norm_memory`

`test_fourth_test_set` covers:
- the seed block and the speed stream;
- B3q never reads;
- B1 on the fourth set;
- KPI 1 stays on `_fresh2` while a `_fresh3` reading is on disk;
- B3r refuses while the switch is `'fresh2'`;
- with a stand-in switch set to `'fresh3'`: no fallback, the read-once refusal, and the missing-set refusal.

Added after that run (not yet run; no MATLAB was started for them):
- `test_fourth_test_set` also checks:
  - the `run_id < 100000` assert, after the last `run_id = run_id + 1` and before the save;
  - the `result_status` reasons for a fusion or a detector newer than the readings: rerun for `_fresh2`, read once and cannot be reread for `_fresh3`;
  - `fusion_rev_id`: the two ids and the refusal of another fit set;
  - the checks before the marker, none of them writing it: each of `data/splits.mat`, `data/trained_detector.mat`, `data/fusion.mat` and `params.mat` missing (`eval_detector:fresh3_input`, the file named); a fusion without `val_latch_oof` (`eval_detector:fresh3_fusion`); the old layout, the revision fitted on validation only and the adopted id without the revised `FM` (`eval_detector:fresh3_fusion_rev`); a fusion older than `trained_at` (`eval_detector:fresh3_fusion_old`); the third set's reading missing or older than the fusion (`eval_detector:fresh3_rehearsal`); a record `docs/d91_fresh3_read_p1.txt` with this `params_id` (`eval_detector:fresh3_recorded`), while an aborted record and another link model's record do not block;
  - the start marker: its call placed after every check and before both data loads, the log line right after it, written by a reading that stops right after it with time, commit, `code_tree`, `params_id`, `untracked_m`, and the SHA-256 (checked against a separate whole-file hash) and modification time of the detector and the fusion, and `eval_detector:fresh3_started` for the next reading;
  - no outcome line before the fusion (`fuse_classes` apply, `fusion_target`) and the latch (`latch_runs`) have run;
  - the predictions saved before the metrics, the local-changes check over `code`, `models` and `startup.m` with untracked files, and the untracked `.m` list.
- To run later, in one `-singleCompThread` MATLAB: `test_fourth_test_set`, `test_result_status`, `test_seed_streams_disjoint`, `test_third_test_set`, `test_kpi1_file`, `test_gui_bundle_drops_stale` and `test_m_files_parse`. Also try the merge-time MATLAB check of step 3 on the d90 smoke dataset saved with `-v7.3` before it is used at the merge, and the `select_fusion` checks of step 2 once the patch is applied.

The full suite and d90's smoke have not been run on this branch, and neither has run on d90 yet.
