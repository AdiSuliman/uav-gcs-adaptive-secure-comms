# Recovery after an unexpected stop (profile 3's chain)

A power loss, a crash or a forced reboot stops the chain. Nothing that is saved is lost. Each long stage keeps its finished work on disk, and the takeover resumes the chain from the stage that was open. This runbook returns the machine to the running chain, with every check written down. It was written on 13.11.2026 after the fifth unexpected stop (1.11, 6.11, 8.11 and 13.11 were power losses; 12.11 was a disk-guard stop, not power).

Files, all in `C:\Users\Adi Suliman\uav-gcs-logs`:

| File | What it does |
|---|---|
| `p3_recovery_check.sh` | Every check below in one run; prints PASS, WARN or FAIL per item and writes `recovery_<stamp>.txt`. With `--relaunch`, and only when nothing FAILs, it also runs the approved relaunch and waits for the stage's kept-work line. It moves leftovers aside and never deletes a file. |
| `p3_takeover_relaunch.ps1` | The approved takeover relaunch (`p3_deploy_prep.md` 3.5, Adi 2.11.2026 item 4), verbatim. |
| `p3_recovery_expect.txt` | The SHA-256 of the frozen inputs (`fusion.mat`, `trained_detector.mat`, `profile.json`) with the record behind each. |
| `v7_takeover_autostart.ps1` | The same relaunch for a logon-triggered scheduled task. It needs Adi to register the task once (section 5). |

## 1. Why a stop costs little

| Stage | What survives a stop | What is lost |
|---|---|---|
| C1p | finished cells in `data/c1p_cells` | the cells in work on the six workers (up to about 14 h each) |
| C1c | finished chunks and check cells (`data/c1c_*`) | the chunks or cells in work |
| SURV, SURV3 | finished jobs in `data/surv_jobs`, `data/surv3_jobs` | the jobs in work |
| C2, C2g, C2u | finished runs, combinations and threats in `data/run_cache/C2`, `C2g`, `C2u` (`run_cache` on since 11.11) | the runs in work |
| C1d, C2e, GAL, EDGE, KPI, DASH, WEAK, RPT; LAT and the final phase | stage outputs already committed | the open stage from its start (C2e about 1.7 h and EDGE about 3.2 h are the longest) |
| A hand-run (D2c, a test suite) | nothing: an incomplete run is void and is started again whole through the gate | the run so far |

Every kept file is written to a temporary file, flushed to the disk and then renamed. A file cut by the stop is never taken as finished: a temporary file is removed or moved aside, and an unreadable kept file is computed again (`pool_checkpoint.m`, `run_cache.m`). A kept job is used only if its key matches. The key covers the code, `profile.json`, the value of `params.mat`, the MATLAB release and the thread count, so a job can never be reused under changed inputs.

## 2. When to run it

- Adi tells Claude that the machine went down, or Claude finds a boot time later than the last takeover beat.
- Claude runs the whole procedure without asking, because Adi approved the relaunch command on 2.11. Claude stops and asks only on a FAIL that section 4 does not cover, or on a WARN that section 4 marks as Adi's.

## 3. The procedure

1. **Adi:** turn the machine on and log on. Nothing else. While the autostart task is not registered, the takeover does not start by itself.
2. **Checks:** `bash "/c/Users/Adi Suliman/uav-gcs-logs/p3_recovery_check.sh"`. It covers:
   1. **The stop:** boot time, event 6008 (Windows' last-alive stamp, minutes early), event 41 (BugcheckCode 0 and no power-button press mean a power loss), the last takeover beat and the last `p3.log` line.
   2. **Nothing of the chain runs:** no MATLAB, no takeover, no `p3_hand.busy`.
   3. **The takeover's status mode (reads only):** p3 unfinished, its next and open stage, any `p3_resume.go`, `p3.abandon`, `final.hold` and ALERT files.
   4. **Code:** `v7-p3` on branch `v7-p3`, HEAD equal to the last `p3 v7-p3` line of `v7_d86/code_commit.txt`, no change under `code/`, `startup.m`, `profile.json`, and `git fsck` on the four repositories.
   5. **The frozen inputs** against `p3_recovery_expect.txt`.
   6. **Finished pool files:** each present and not empty. Every `*.tmp.mat` under `data/` and `results/` is moved aside.
   7. **Kept work:** each kept folder, its file count and its newest file.
   8. **Full read:** one gated MATLAB of 10 GB reads every kept file in full (`key` and `res`) and `params.mat`.
   9. **The machine:** `.dmr` in Temp (files over 100 MB moved aside above 1 GB, since disk_guard stops the chain at 2 GB), disk health, free disk and commit, sleep and hibernate off, no pending Windows Update reboot.
3. **Any FAIL:** fix it by section 4, then run step 2 again.
4. **Relaunch:** `bash "/c/Users/Adi Suliman/uav-gcs-logs/p3_recovery_check.sh" --relaunch`. It repeats the checks, starts the approved command, waits for `p3: stages <stage> to RPT started` in `v7_d91_takeover.log`, then waits for the stage's line `N of M ... kept from an earlier start` in `p3.log`.
5. **Confirm the resume:**
   - N in that line equals the file count of the stage's kept folder from check 7.
   - The new PART header names the HEAD from check 4.
   - The stage's first numbers equal the ones from before the stop (SURV's clean-link lines, for example). The stage is deterministic, so a difference means a changed input. Stop and read it.
6. **Re-arm the three background watchers** (Claude's background tasks, which do not survive a reboot):
   - `bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_p3_watchdog.sh" 24 8`
   - the `.dmr` watcher loop (warns at 1.5 GB of `.dmr` in Temp);
   - `bash "/c/Users/Adi Suliman/uav-gcs-logs/d2c_after_chain.sh"` (starts D2c after RPT).
7. **Record and report:**
   - a section in `stage_reviews_p3.md`: the stop's time and cause, what was kept and lost, the checks, the relaunch;
   - a line in `PROJECT_LOG.md`;
   - the memory resume state and the task map;
   - a message to Adi with the hours lost and the new end estimate.

## 4. What a FAIL or WARN means

| Item | Meaning | Action |
|---|---|---|
| event 41 with a BugcheckCode or a power-button press | a crash or a manual stop, not a power loss | Read the dump and WHEA events; tell Adi before relaunching |
| MATLAB or a takeover already runs | the autostart or Adi already resumed it | No relaunch; read `v7_d91_takeover.log` and check step 5 |
| `p3_hand.busy` exists | a hand-run was cut | Its result is void; move the file aside (`v7_d86/`); restart that hand-run later through the gate |
| p3 reported finished | the stop hit the final phase | Read the takeover log; the final phase resumes by itself on relaunch, and a cut D2c is started again |
| HEAD or branch differs, or code changed | a commit or edit not in `code_commit.txt` | Stop: find the change; never relaunch on an unexplained tree |
| git fsck errors | repository damage | Stop: fetch the pushed copy (every branch is pushed) and compare; tell Adi |
| a frozen input's hash differs | a changed or damaged model file | Stop: compare with the hash in its record (`p3_recovery_expect.txt` names it); tell Adi before anything is rebuilt |
| a pool file missing or empty | damaged output of a finished stage | Stop: that stage must run again; tell Adi with the cost |
| `*.tmp.mat` moved | a save cut by the stop | Nothing more: the stage writes it again |
| full read: unreadable kept file | a cut write that looked finished | Move that file aside; its stage computes it again |
| `.dmr` over 1 GB | Simulink inspector files | Moved aside by the script (never deleted); Adi deletes them later |
| sleep or hibernate on, or a Windows Update reboot pending | the chain would stop again | Adi's settings: ask Adi; never change system settings without his word |
| free commit under 55 GB | other programs hold memory | The takeover waits by itself; tell Adi which programs hold it |

## 5. Prevention (Adi's choice)

- **A UPS** (suggested on 8.11). Four of the five stops were power losses. Each costs the work in progress plus the time until someone logs on.
- **The autostart task:** registering `v7_takeover_autostart.ps1` as a logon task (logon + 2 min) brings the takeover back by itself. The session's permission classifier refused to register it on 10.11, so Adi registers it once. Claude still runs steps 2, 5, 6 and 7 after such a restart.
- The power plan stays as set: sleep and hibernate off, processor maximum 99%, Windows Update paused until 30.11.

The working copies are in `C:\Users\Adi Suliman\uav-gcs-logs`; `docs/recovery/` holds a versioned copy of the four files as of 13.11.2026. Run the ones in `uav-gcs-logs`.
