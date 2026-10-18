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
