# What to do after the computer shut down unexpectedly

This file tells Claude what to do after a power loss, a crash or a forced reboot. Adi turns the machine on, logs on, opens Claude and writes, for example: "The computer shut down. Do what RECOVERY_AFTER_SHUTDOWN.md says."

Adi does nothing else. Claude runs every step below without asking, except where a step says "ask Adi".

Nothing starts by itself after a reboot: no scheduled task, no autostart. The chain stays stopped until Claude relaunches it in step 4.

All scripts are in `C:\Users\Adi Suliman\uav-gcs-logs`. Run them from Bash with the full path.

## Why a stop costs little

Each long stage keeps its finished work on disk. Every kept file is written to a temporary file, flushed and then renamed, so a file cut by the stop is never taken as finished. A kept job is used only if its key matches. The key covers the code, `profile.json`, `params.mat`, the MATLAB release and the thread count.

| Stage | Kept after a stop | Lost |
|---|---|---|
| C1p | finished cells (`data/c1p_cells`) | the cells in work |
| C1c | finished chunks and check cells (`data/c1c_*`) | the chunks or cells in work |
| SURV, SURV3 | finished jobs (`data/surv_jobs`, `data/surv3_jobs`) | the jobs in work |
| C2, C2g, C2u | finished runs (`data/run_cache/C2`, `C2g`, `C2u`) | the runs in work |
| C1d, C2e, GAL, EDGE, KPI, DASH, WEAK, RPT, LAT, final phase | outputs of finished stages | the open stage from its start |
| A hand-run through the gate (D2c, a test suite) | nothing | the whole run; it is started again |

## Step 0: find what was running

Read, in this order:
1. The memory file `v7-resume-state.md` (what was running and what came next).
2. The end of `uav-gcs-logs/v7_d91_takeover.log` and of the open stage's `p3.log`.
3. Any `*_hand.busy` file in `uav-gcs-logs/v7_d86/` (a hand-run that was cut).

Then follow the case that fits:
- **The profile 3 chain was running** (the takeover had not reported p3 finished): steps 1 to 7 below.
- **The chain had finished and only a hand-run was cut** (D2c, a test, a side reading): steps 1 and 2, then move the `.busy` file aside, start that hand-run again whole through `v7_d91_gated_run.sh`, then steps 6 and 7.
- **Nothing was running** (book work, documents): items 3, 4 and 8 of step 2 only (code, frozen inputs, machine), then step 7.

## Step 1: what stopped the machine

`bash "/c/Users/Adi Suliman/uav-gcs-logs/p3_recovery_check.sh"` prints it first:
- the boot time;
- event 6008 (the last time Windows was alive);
- event 41: BugcheckCode 0 with no power-button press means a power loss;
- the last takeover beat and the last log line, which give the hours lost.

If event 41 shows a BugcheckCode or a power-button press, the cause was a crash or a manual stop, not power. Read the dump and the WHEA events, and ask Adi before relaunching.

## Step 2: check that nothing was damaged

The same script, `bash "/c/Users/Adi Suliman/uav-gcs-logs/p3_recovery_check.sh"`, checks each item and prints PASS, WARN or FAIL. Its full output is saved in `uav-gcs-logs/recovery_<date>_<time>.txt`.

1. **Nothing of the chain runs:** no MATLAB, no takeover, no `p3_hand.busy`.
2. **Takeover status** (read only): where p3 stands, its next and open stage, any `p3_resume.go`, `p3.abandon`, `final.hold` or ALERT file.
3. **Code:**
   - the `v7-p3` worktree is on branch `v7-p3`;
   - HEAD equals the last `p3 v7-p3` line of `v7_d86/code_commit.txt`;
   - nothing changed under `code/`, `startup.m` or `profile.json`;
   - `git fsck` passes on the four repositories.
4. **Frozen inputs:** the SHA-256 of `fusion.mat`, `trained_detector.mat` and `profile.json` equals `p3_recovery_expect.txt`.
5. **Pool files of finished stages:** each is present and not empty. Every `*.tmp.mat` is moved aside, never deleted.
6. **Kept work:** each kept folder, its file count and its newest file.
7. **Full read:** one gated MATLAB of 10 GB reads every kept file and `params.mat` in full.
8. **The machine:**
   - `.dmr` files in Temp (over 1 GB they are moved aside, because disk_guard stops the chain at 2 GB);
   - disk health, free disk and free commit;
   - sleep and hibernate off;
   - no pending Windows Update reboot.

Use `--no-matlab` instead if a MATLAB already runs; it skips item 7.

## Step 3: handle each FAIL or WARN, then run step 2 again

| Finding | Meaning | Action |
|---|---|---|
| MATLAB or a takeover already runs | Someone already started it | No relaunch; read the takeover log and go to step 5 |
| `p3_hand.busy` exists | A hand-run was cut | Its result is void. Move the file aside and start that hand-run again later through the gate |
| p3 reported finished | The stop hit the final phase | The final phase resumes on relaunch; a cut D2c is started again |
| HEAD, branch or code differs | A change not recorded in `code_commit.txt` | Stop and find the change. Never relaunch on an unexplained tree. Ask Adi |
| `git fsck` errors | Repository damage | Stop. Compare with the pushed copy (every branch is pushed). Ask Adi |
| A frozen input's hash differs | A changed or damaged model file | Stop. Ask Adi before anything is rebuilt |
| A pool file missing or empty | Damaged output of a finished stage | Stop. That stage must run again. Ask Adi, with the cost in hours |
| `*.tmp.mat` moved aside | A save cut by the stop | Nothing more; the stage writes it again |
| Full read: an unreadable kept file | A cut write | Move that file aside; its stage computes it again |
| `.dmr` over 1 GB | Simulink inspector files | Moved aside by the script; Adi deletes them later |
| Sleep or hibernate on, or an update reboot pending | The chain would stop again | System settings are Adi's. Ask Adi; never change them |
| Free commit under 55 GB | Other programs hold memory | The takeover waits by itself. Tell Adi which programs hold it |

Claude never deletes a file in recovery; it moves files aside, and Adi deletes later.

## Step 4: relaunch the chain

Only after every FAIL is fixed:

`bash "/c/Users/Adi Suliman/uav-gcs-logs/p3_recovery_check.sh" --relaunch`

It repeats the checks. It then runs `p3_takeover_relaunch.ps1`, the relaunch command Adi approved on 2.11.2026 (`p3_deploy_prep.md` 3.5). It waits for `p3: stages <stage> to RPT started` in `v7_d91_takeover.log`, then for the stage's `N of M ... kept from an earlier start` line in `p3.log`.

## Step 5: confirm that the stage resumed correctly

- N in the kept line equals the kept folder's file count from item 6 of step 2.
- The new PART header names the same HEAD as item 3 of step 2.
- The stage's first numbers equal those from before the stop (for SURV, the clean-link lines). The stages are deterministic, so a difference means a changed input. Stop and investigate.

## Step 6: re-arm Claude's background watchers

They do not survive a reboot. Each runs as one background task with a single completion notice; never a polling loop of agents.

- **The watchdog**, while the chain runs: `bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_p3_watchdog.sh" 24 8`
- **The `.dmr` watcher:** a loop that checks the total `.dmr` size in Temp every 2 minutes and warns at 1.5 GB.
- **The D2c starter**, until D2c has run: `bash "/c/Users/Adi Suliman/uav-gcs-logs/d2c_after_chain.sh"`

## Step 7: record and report

1. A section in `worktrees/session_notes_0ff3/core/review/stage_reviews_p3.md`: the time and cause of the stop, what was kept and lost, the check results and the relaunch.
2. A dated line in `uav-gcs-v7-docs/docs/PROJECT_LOG.md` (commit and push).
3. Update the memory file `v7-resume-state.md` and the task map artifact.
4. A message to Adi (Hebrew), with:
   - the cause;
   - that nothing was damaged, or what was and how it was fixed;
   - the hours lost;
   - the stage that resumed;
   - the new end estimate.

## Prevention

A UPS is the only protection against power cuts; that choice is Adi's. Keep the power plan as set: sleep and hibernate off, processor maximum 99%, Windows Update paused.

## History of stops

| Date | Cause |
|---|---|
| 1.11.2026 | power loss |
| 6.11.2026 | power loss |
| 8.11.2026 | power loss |
| 12.11.2026 | disk_guard stop (`.dmr` files in Temp) |
| 13.11.2026 | power loss during SURV; resumed with 23 of 154 jobs kept |

Add a row after each stop.
