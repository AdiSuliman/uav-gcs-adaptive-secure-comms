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
| Guards in `eval_detector.m` | `DET_TEST = 'fresh3'` | The reading stops unless all of these hold: `kpi1_set()` is `'fresh3'` (`eval_detector:kpi1_set`), `data/splits_fresh3.mat` exists (`eval_detector:fresh3`), `results/eval_detector_metrics_fresh3.mat` does not exist yet (`eval_detector:fresh3_read`), and neither does `results/fresh3_read_started.txt` (`eval_detector:fresh3_started`). Its other inputs are checked next, still without loading any data: `data/splits.mat`, `data/trained_detector.mat`, `data/fusion.mat` and `params.mat` exist (`eval_detector:fresh3_input`), `data/fusion.mat` holds `val_latch_oof` (read with `whos -file`; `eval_detector:fresh3_fusion`) and is not older than the detector's `trained_at` (`eval_detector:fresh3_fusion_old`). Once all of these pass, B3r writes that marker before it loads any data, so a reading that crashes after printing its numbers still counts as the one reading. The marker holds the time, the commit with `+ local changes in code, models or startup.m` when those differ from it, `code_tree` (`git rev-parse HEAD:code`), `params_id`, and the SHA-256 and modification time of `data/trained_detector.mat` (with its `trained_at`) and `data/fusion.mat`. After the set is loaded, a set without frame positions stops before any number is printed (`eval_detector:fresh3_pos`), so the fusion is never skipped silently. `detector_predictions_fresh3.mat` is saved before `eval_detector_metrics_fresh3.mat`, so a reading cut off between the two still leaves WEAK its input. |
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
2. In the commit that deploys the adopted revision:
   - set `kpi1_set.m` to `'fresh3'`;
   - change the two `kpi1_set()` expectations in `test_core.m`: `test_third_test_set` and the first part of `test_fourth_test_set`.

   With no-go, the switch stays `'fresh2'`, and the set waits, unread, for the revision that is adopted after the run.
3. For each profile, when no MATLAB of that profile runs:
   - copy `set4_out/<p>/data/*fresh3*` into the profile's `data/`;
   - check the hashes from the profile's `data/` folder (the list names the files without a folder):
     `(cd <profile>/data && sha256sum -c "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/sha256_fresh3.txt")`.
     Every line must end in `OK`;
   - check that the profile's `params.mat` still has the `params_id` above;
   - check that the run ids stay inside the seed block: `assert(max(h5read('data/dataset_fresh3.mat', '/dataset/run')) < 1e5)`. It reads only the run ids, not the labels or the frames, so it does not count as reading the set.
4. Run `run_stage('B3r')` once per profile, after the profile's B2F has selected the adopted fusion (B3r refuses a fusion older than the detector). Then rerun KPI, DASH, WEAK and RPT. KPI 1 is read from `results/eval_detector_metrics_fresh3.mat`, with the third and second sets' readings beside it. A second B3r refuses to run (`eval_detector:fresh3_read`, or `eval_detector:fresh3_started` once the marker exists).
   - **Freeze `data/trained_detector.mat`, `data/ood_thresholds.mat` and `data/fusion.mat` from B3r until RPT.** In that profile after its B3r: no B2, B2F or OOD stage and no other save of these three files. The reading cannot be repeated, so a newer detector or fusion leaves KPI 1 STALE for good (`result_status`: read once with an earlier detector or fusion, cannot be reread). The SHA-256 lines in the marker show which files the reading used.
5. Right after B3r, archive the marker and the results of each profile. The marker lives in the profile's `results/`, which `.gitignore` excludes, so it is not committed and `git clean -X` would delete it:
   `mkdir -p "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/read" && cp <profile>/results/fresh3_read_started.txt <profile>/results/*_fresh3.* <profile>/logs/stage_B3r_*.txt "/c/Users/Adi Suliman/uav-gcs-logs/set4_out/<p>/read/"`.
   Later, commit the marker's text under `docs/` (for example `docs/d91_fresh3_read_p1.txt`). Nobody deletes the marker to rerun B3r.
6. A marker with no `_fresh3` result beside it means that a B3r stopped after writing it. Decide from that B3r's log (`logs/stage_B3r_<time>.txt`) only:
   - The set was not read when the log shows no line after the marker other than `Loading test data and trained model...`, `Test set: fourth test set (<n> frames)` and `Running inference on <n> test samples...`, followed by the error. These lines carry no label, score or outcome: the frame count is the build's. This covers a failure in loading `data/splits.mat` or `data/splits_fresh3.mat`, a normalization mismatch, `eval_detector:fresh3_pos` and a failure in the network's inference. Then: move the marker and the log to `set4_out/<p>/read/` as `fresh3_read_started_aborted_<time>.txt` and `stage_B3r_<time>.txt`, write the cause in this note, fix it without touching the three frozen files (when one has to change, the next marker records its new hash), and run B3r once more under the same guards.
   - When the log shows any other line (an accuracy, F1, threshold, confusion or Eb/N0 line) or is missing, the reading counts. Do not rerun B3r: the fourth set is spent in that profile. Its KPI 1 stays on the third test set (`kpi1_set.m` back to `'fresh2'` in that profile's worktree), and this note records the case with whatever numbers the log shows.
7. Profile 2 has no fourth set yet. If its KPI 1 is to come from set 4, run B3q in its own copy the same way, one profile at a time.

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
  - the input checks before the marker: each of `data/splits.mat`, `data/trained_detector.mat`, `data/fusion.mat` and `params.mat` missing (`eval_detector:fresh3_input`, the file named), a fusion without `val_latch_oof` (`eval_detector:fresh3_fusion`) and a fusion older than `trained_at` (`eval_detector:fresh3_fusion_old`), none of them writing the marker;
  - the start marker: its call placed after the input checks and before both data loads, written by a reading that stops right after it with time, commit, `code_tree`, `params_id`, and the SHA-256 (checked against a separate whole-file hash) and modification time of the detector and the fusion, and `eval_detector:fresh3_started` for the next reading;
  - the predictions saved before the metrics, and the local-changes check limited to `code`, `models` and `startup.m`.
- To run later, in one `-singleCompThread` MATLAB: `test_fourth_test_set`, `test_result_status`, `test_seed_streams_disjoint`, `test_third_test_set`, `test_kpi1_file`, `test_gui_bundle_drops_stale` and `test_m_files_parse`. Also try the merge-time `h5read` run-id check (step 3) on the d90 smoke dataset saved with `-v7.3` before it is used at the merge.

The full suite and d90's smoke have not been run on this branch, and neither has run on d90 yet.
