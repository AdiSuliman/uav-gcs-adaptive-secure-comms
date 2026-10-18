# Run scripts (read-only snapshots)

These are copies of the scripts that ran the v7 full runs. The live copies are in `C:\Users\Adi Suliman\uav-gcs-logs\`, outside the repository, and the copies here are not run. The date in each name is the day of the copy's content: the file's last change before it was copied on 2026-10-18. The sha256 values are of the live files, which have LF line ends. The blobs in git hold the same bytes (`git show <commit>:docs/runs/<file> | sha256sum`); a checkout with `core.autocrlf=true` writes CRLF. Their logs are in `uav-gcs-logs/` and `uav-gcs-logs/v7_d86/`.

| File | What it ran | When | sha256 |
|---|---|---|---|
| `v7_d83_launch.sh` | the D83 rerun launcher (cherry-pick, then the chains) | 2026-10-08, not used for the D86 run | (tracked since 21ce603) |
| `v7_fix_resume_superseded.sh` | the D81/D82 fix and resume of the first v7 run | 2026-10-07, superseded | (tracked since 21ce603) |
| `v7_d86_launch_20261017.sh` | the D86 launcher: test gate on a SHA, dry merge, archive of the first reading, merge, chains; resume mode with the heartbeat `v7_d86/run.lock` (DECISIONS D86, "Launch") | launched 2026-10-16 11:09 on c2c8b8b; resumed 2026-10-17 16:42 on 9b5c9f1. This copy is after the 16:42 edit, so `stage_pids` skips the B3m copies | `0af010d0665b16ef1dc648cb75e0e3e41f81691fcb1c562fa0379791a0c88ccb` |
| `v7_d87_redo_20261017.sh` | the redo after the align fix: A0, A6, B1, B2, B2F and the second test set's A6 and B1 (logged as B3n) in profiles 1 and 3; a `HOLD` file pauses it (D88) | 2026-10-17 14:26-16:14 on 725a2f1 | `779230e55e3b98df82790db47f3120b81992bbcbf703f0f27b44d2667459e210` |
| `v7_d87_resume_20261017.ps1` | starts the launcher's resume detached through WMI | 2026-10-17 16:14 (refused, as designed) and 16:42 on 9b5c9f1 (D89) | `e5e8ff130e1659634c38669dcee049beb70145406ccf6c8b9729cf99a4c26195` |
| `v7_d87_b3m_20261017.sh` | the third test set B3m in the isolated copies `uav-gcs-b3m-p1` and `-p3`, then the copy of its files into the profiles (D87) | 2026-10-17 16:15-22:51 | `34cc47dba5be3073e2e2c022ae063fce9eec9b854b51f02f1f66b23a9a6739c7` |
| `v7_d87_p3fix_20261017.sh` | profile 3 after its out-of-memory stop in OOD: A0, OOD, B4s, then C1p to RPT after profile 1's SURV3 | started 2026-10-17 22:09; OOD and B4s done 2026-10-18 04:57; waiting for profile 1's SURV3 | `933a7fa25e6d3ae5f30cd967143e45320e8b4cb76ee9fc7449b5e614bc653618` |
| `v7_d91_speed_proofs_20261018.sh` | the bit-identity proofs and the profile of branch d91-speed, in scratch exports (D91) | 2026-10-18, jobs ended 17:16 | `7d38b9fcb3b65a89e5f653c2f53893880ba5113427a95a5a464aa3df7bb5e772` |
| `v7_d91_tests2_20261018.sh` | the full `test_core` of d91-speed and of 9b5c9f1 in a short path (D91) | 2026-10-18, summary 19:49 | `cd715b92f4b07bea84439ea2f3a02e1594076ddd85564cbcfd6d23c54f0d36c5` |

The other d91 scripts are not copied here, because their branches already carry them:
- the fourth set's build script and driver: branch `d91-set4`, `docs/`;
- the speed gate and the tests3 and tests4 queues: branch `d91-speed`, `docs/`;
- the takeover and its test harness: branch `d91-takeover`, `ops/`.

## Analysis outputs (`analysis/`, read-only snapshots)

The decision record cites these working files of 2026-10-17/18. The originals are in the session's scratch folder, outside the repository. The sha256 values are of the originals. Git stores these files with LF line ends: for the originals with CRLF line ends (`audit1_*`, `rev88_confirmed.json`, `overnight_audit.txt`, `d91_fuse_*`) the blob differs from the original by its CR characters only, and the line numbers are the same. One file is not a plain copy: `weak_branch_recommendation.md` is the `recommendation` text field, extracted from the workflow's JSON result. Line numbers cited in the docs (for example `d91_fuse_m_p1_log.txt:71-77`) refer to these copies. The two measurement logs were `m_p1.log` and `m_p3.log`; they are renamed because `.gitignore` excludes `*.log`.

| File | What it is | Written | sha256 |
|---|---|---|---|
| `audit1_confirmed.json` | the audit of the running chain: 27 of 30 findings confirmed (D88, D90) | 2026-10-17 10:06 | `a88dde838b4c95a00136cc9f8859fe938bff70d7fc8fb164eb75848f44eaa7ee` |
| `audit1_plan.md` | the fix plan for those findings (D88, D90) | 2026-10-17 10:05 | `81cc95b0623fa713da91dae9301772d9e7461c08f8c901798290787e263dc605` |
| `rev88_confirmed.json` | the review of d87 and d88: 9 confirmed findings (D89, D90) | 2026-10-17 14:54 | `d56445965f6ed5e66acb5048f6a93360bf9f76f78f789b79c65bb52e8ec1b65f` |
| `weak_branch_recommendation.md` | the weak-branch analysis of antenna fault and airframe shadowing; it read validation, the already-read third test set and the code (D91) | 2026-10-17 22:58 | `1494865686a79970fe4ce49e45eb861a8cfd9e4d5f57d6d1f5299d436c5f8b4b` |
| `overnight_audit.txt` | the overnight audit: memory, launcher defects (a)-(f), merge rules, the KPI 1 threshold across profiles (D90, D91) | 2026-10-17 23:53 | `9baee4cfaab24c4d04788b461f6bf5d43a29ebae8d554add16091b0a65c82b93` |
| `c1p_rate.txt` | profile 1's C1p build count every 30 min, 12:20-15:20 on 2026-10-18 (D91 part 5) | 2026-10-18 15:20 | `22db5195a23bfbb93d7ec6d3649dac65e795b495ed02aad064068e49c46a9b32` |
| `c1p_slow_model.py` | the C1p cost model of the 93 cells (D91 part 5) | 2026-10-18 12:40 | `db945ec98040848f83facbef3ddfb704feb40f2762762d47005456b83a80546b` |
| `c1p_slow_timeline.py` | the campaign timeline built on that model (D91 part 5) | 2026-10-18 12:43 | `224760272d516c1ffc8ef0c72b71bcefb6cf161c9678b9d506535f6c9924d844` |
| `d91_fuse_m_all.m.txt` | the M1-M4 measurement script of d91-fuse (renamed `.txt`; it is not run from here) | 2026-10-18 | `b0fa6dc8cf171e8abf061c3361c0f02fc8113fccdb71dbd258f2b510117fe398` |
| `d91_fuse_m_p1_log.txt` | its log on profile 1's enlarged fit set (fit-set numbers, out of fold or nested; D91) | 2026-10-18 11:02 | `0ccaf4fdec4f7ec31cecb415fc3bb43dcce1d7bc47fbcf6d86b5d95f699bdd52` |
| `d91_fuse_m_p3_log.txt` | the same on profile 3 | 2026-10-18 16:24 | `c1f7bca764e2dd96b1e47e3a2cb6cf8dc221286327cba4f8d3467ed7636e8e19` |

"Run notes" in the docs are the run's dated working notes. They are kept outside the repository and are not copied. Where a log line holds the same fact, the docs cite the log line instead.
