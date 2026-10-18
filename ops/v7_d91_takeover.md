# v7 takeover of the d86 launcher (v7_d91_takeover.sh)

Live copy: `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_takeover.sh`. Its log is `v7_d91_takeover.log` in the same folder.
In the repository it lives on branch `d91-takeover`, under `ops/`, together with the test harness and the stubs.

## What it replaces, and why

Three things still run:

- The d86 launcher, bash PID 24172, in resume mode, holding SRC 9b5c9f1 in memory.
- Its profile 1 chain subshell, 43428, which runs 43972, then the MATLAB stub 44984, then MATLAB 42560. This chain is in C1p.
- The profile 3 fix script, bash PID 49732. It is waiting for profile 1's SURV3.

The overnight audit found that, left alone, these would:

- **(a)** Let profile 2's C1p skip profile 3's SURV3. The launcher counts profile 3 as ended because its own profile 3 subshell died at 22:02 on 17.10.
- **(b)** Refuse profile 2 once any code is merged into v7-dev. The launcher checks against its in-memory SRC. It would then run LAT on a busy machine.
- **(c)** Start profile 3's C1p as soon as profile 1 crashes. The fix script also accepts 'chain ended'.
- Never count the machine as idle, because the zombie MATLAB 32824 is still counted.
- Lose run.lock after profile 1's chain ends, which leaves the old `resume` free to start a second profile 3 chain.

The takeover keeps profile 1's chain as it is and replaces everything else.

| Track | What it does |
|---|---|
| P1 | Only reads p1.log. If the chain ends with rc != 0, or a reboot cuts it, it writes an alert and runs nothing until `p1_resume.go` exists. |
| P3 | Waits until p1.log's current part is past SURV3. Never accepts 'chain ended' instead. Meanwhile it runs the B-stage rerun listed in `p3_brerun.go`, if that file exists. Then it runs C1p..RPT under a new `##### PART` header in the launcher's format. |
| P2 | Starts once p1.log's current part shows `chain ended rc=0` past RPT. It branches v7-p2 from v7-dev, sets profile.json n_rx to 2, makes fresh data/ and results/, pushes, and writes the commit to code_commit.txt (no SRC check). It runs A0-B2F, B3n, B3m, the stages listed in `p2_set4.stages`, then B3, B3a, B4, OOD and B4s. It waits until p3.log's current part is past SURV3, then runs C1p..RPT. |
| Final | Waits until all three tracks have ended and the machine is idle. It then runs LAT, KPI, DASH, WEAK, RPT and the console bundle for each profile. |

The machine counts as idle when all of these hold:

- No live MATLAB has `run_stage(` in its command line. Exited processes (zombie 32824), smoke runs and the B3m, B3q and B3r copies are not counted.
- CPU is below 15 % on two polls taken 10 min apart.
- If that never happens, it goes ahead after at most 4 h.

**Dependencies.** Every dependency between tracks is read from the log markers (`##### PART`, `##### STAGE X done`, `##### chain ended rc=N`), never from process ids. Each profile has one MATLAB at a time in its own worktree. Before each chain starts, the takeover checks:

- the worktree is on its branch;
- no merge is in progress;
- there are no uncommitted changes in code/;
- at least 45 GB of commit is free.

**Safety at start.** The takeover refuses to start when any of these holds:

- `cygpath -w "$TEMP"` is not `C:\Users\ADISUL~1\AppData\Local\Temp`. Otherwise the parallel turn file would split.
- PID 24172 or 49732 is still alive with its script in its command line.
- Another takeover's heartbeat (`v7_d86/takeover.lock`) is under 20 min old and newer than the last boot.

**While running.** It touches `v7_d86/run.lock` and `takeover.lock` every 30 s, and never more than 60 s apart. The old launcher's `resume` therefore always refuses: **`v7_d86_launch.sh … resume` is retired.**

It never touches the parallel turn file. If the PID in that file has exited but still lingers as a zombie, every `take` blocks, so the takeover writes an alert instead.

## Procedure

The PIDs below were checked on 18.10 at 05:50.

### 1. Read-only check (Adi or the agent)

```bash
bash '/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh' 24172 49732 status
```

What it should show:

- p1 at `next C1p (index 13)` with `idle part: no`;
- p3 at `next C1p (index 13)` with `idle part: yes`;
- `p2: no log`;
- `p3 rerun request: none`;
- a free commit figure.

The status mode writes nothing.

### 2. Adi ends the profile 3 fix script

Run this only once p3.log's current part ends in `##### STAGE B4s done` and p3_fix.log shows `A0 OOD B4s ended rc=0`. Both have been true since 18.10 04:57.

```
taskkill /PID 49732 /F
```

Use `/F` and **no `/T`**.

Check afterwards:

- `Get-Process -Id 49732` finds nothing.
- Its wrapper 24652 exits on its own.
- p3.log is unchanged.

### 3. Adi ends the launcher's main bash only

```
taskkill /PID 24172 /F
```

Again use `/F` and **no `/T`**. With `/T`, profile 1's MATLAB would be killed too.

Check afterwards:

```powershell
Get-Process -Id 43428,43972,44984,42560 | Select-Object Id,ProcessName,StartTime
(Get-Date) - (Get-Item 'C:\Users\Adi Suliman\uav-gcs-logs\v7_d86\run.lock').LastWriteTime
```

- All four processes are still alive: the chain subshell, its child, the MATLAB stub and MATLAB.
- run.lock is under 30 s old. The chain subshell touches it every 10 s.
- The wrappers 32328 and 39928 exit on their own.
- p1.log keeps growing.

### 4. Launch the takeover hidden, the same way as the launcher

Use PowerShell. Launching it the same way gives the same TEMP: a login bash sees `TEMP=/tmp`, which is `C:\Users\ADISUL~1\AppData\Local\Temp`. This was checked on 18.10.

```powershell
$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
```

`ReturnValue` must be 0.

### 5. Check after the launch (within 5 min)

- `v7_d91_takeover.log` shows these lines, in order:
  1. `v7 takeover started (boot …, TEMP C:\Users\ADISUL~1\AppData\Local\Temp, poll 300 s)`;
  2. one line each for p1 and p3: `next C1p (index 13)`;
  3. `p2: waits for profile 1's chain to end with rc=0`;
  4. `p3: C1p waits for p1's SURV3`.
- `v7_d86\takeover.lock` holds the takeover's PID and is under 60 s old. `run.lock` is under 60 s old.
- The status mode (step 1) still shows the same state.
- There is no `v7_d86\ALERT_*.txt`.
- The log has no line `the launcher … still runs` or `not started`.

### Latest dates

The takeover must be running before profile 1's SURV3 finishes, because it then starts profile 3's C1p. That is at the earliest **22.10 about 13:00**; the estimate runs to 23.10 about 12:30.

It also covers profile 2. The old launcher would refuse profile 2 or misplace it at profile 1's chain end, at the earliest **23.10 about 10:00**.

Launch it as soon as the review is done (18-19.10). It also covers a profile 1 crash, audit item (c), from the moment it starts.

## Control files (in `uav-gcs-logs\v7_d86\`)

| File | Effect |
|---|---|
| `p1_resume.go` | After `ALERT_p1_failed_*` or `ALERT_p1_cut_*`: profile 1 goes on from its first unfinished stage under a new part. A0 runs first if it stopped inside the B stages. `policy_pools.mat` is checked before C1p. The file must be newer than p1.log; it is renamed `.used_<time>`. |
| `p3_resume.go`, `p2_resume.go` | The same after `ALERT_p3_failed_*` or `ALERT_p2_failed_*`. Also after `ALERT_p3_open_*`, which means p3_fix died with a stage open; check first that no MATLAB runs in uav-gcs-v7-p3. |
| `p3_brerun.go` | The stages of profile 3's B-stage rerun, e.g. `B2F B3 B3a B4 OOD B4s`. They must be stages of uav-gcs-v7-p3's run_stage.m, and no C stage. They run with A0 first, while profile 3 waits for SURV3. Each version (content plus time) runs once; touching the file runs it again. It is ignored once profile 3's C1p has started. A failed rerun holds C1p back until the file is written again, or until `p3_c1p.force` exists. |
| `p3_c1p.hold`, `p2_c1p.hold` | Hold that profile before C1p. Example: until the 21.10 go/no-go on the fusion revision. |
| `p3_c1p.force`, `p2_c1p.force` | Start C1p without the other profile's SURV3, and past a failed rerun. Use it only when the other profile is given up. |
| `p2_set4.stages` | Extra profile 2 stages run after B3m, e.g. `B3q B3r`. They must be in v7-dev's run_stage.m when profile 2 branches. The file is read once, when profile 2's B stages first start. |
| `p1.abandon`, `p3.abandon`, `p2.abandon` | End that track. The final phase skips that profile. If profile 1 is given up, profile 3 also needs `p3_c1p.force`. |

**Alerts** go to `v7_d86\ALERT_<topic>.txt` and to the takeover log. Delete each alert once it is handled.

| Topic | Meaning |
|---|---|
| `p1_failed`, `p1_cut`, `p3_failed`, `p2_failed`, `p3_open` | A chain failed, was cut, or was left with a stage open. |
| `p1_silent` | p1.log has not changed for 6 h. |
| `p3_rerun_failed`, `p3_rerun_blocked`, `p3_rerun_invalid`, `p3_go_ignored` | A problem with `p3_brerun.go` or its rerun. |
| `p2_set4_invalid`, `p2_prep` | A problem with `p2_set4.stages`, or profile 2's worktree could not be prepared. |
| `code_<g>` | A worktree is on the wrong branch, a merge is in progress, or code is uncommitted. |
| `headroom_<g>` | More than 1 h below 45 GB of free commit. |
| `ml_alive_<g>` | An earlier takeover MATLAB still runs in that worktree. |
| `stale_<file>` | A go file older than the event it should answer. |
| `turn_holder_<pid>` | The parallel turn file names an exited MATLAB. |

For `turn_holder_<pid>`, Adi either:

- ends that process's leftover children (e.g. `MATLABWebUI.exe` with that parent), or
- moves the turn file aside, once sure that no live MATLAB holds the turn.

## Fusion revision and the fourth test set

**Profile 3.** Merge the revision into v7-p3 only while profile 3 waits in the takeover. That is from now until its C1p starts, and never while its rerun runs. Then write `p3_brerun.go` with the stages the revision changes, e.g. `B2F B3 B3a B4 OOD B4s`.

- To decide on 21.10 without a race against SURV3, write `p3_c1p.hold` first. Remove it once the go file or the no-go decision is in place.
- The rerun's code commit and its request id go to code_commit.txt.

**Profile 2.** It uses whatever v7-dev holds when profile 1's chain ends. Its commit goes to code_commit.txt. To give profile 2 the fourth test set inside its own chain, write `p2_set4.stages` (e.g. `B3q B3r`) before then.

## After a reboot or a crash

1. Run the same launch command (step 4). The PIDs can stay: a PID whose command line is no longer its script does not block.
2. Profile 3's and profile 2's own parts go on from their first unfinished stage. A0 runs first inside the B stages. An unreadable `policy_pools.mat` is moved aside before C1p, and C1p keeps its per-cell checkpoints.
3. A part whose stages were all done before the interruption only gets its end marker.
4. Profile 1's part, cut by the reboot, raises `ALERT_p1_cut_*`. Check p1.log, then write `p1_resume.go`.

A crash without a reboot is handled like this:

- A takeover whose subshells still heartbeat refuses a second start.
- If the takeover's own MATLAB outlived its bash, the new takeover waits for it (`ALERT_ml_alive_*`) before starting another in that worktree.

## Tests

```bash
bash ops/d91_takeover_test.sh [sandbox] [scenario ...]
```

The default sandbox is `…\scratchpad\d91_takeover_test\`. The default scenarios are `status normal p1crash rerun reboot orphan zombie turn refuse`.

**How it runs.**

- It copies p1.log, p3.log and code_commit.txt once from the live logs, as the starting state: profile 1 inside C1p, profile 3 idle after the fix script.
- It builds a git repository with v7-dev and v7-p3 worktrees and a bare origin.
- It replaces MATLAB with `ops/d91_stub_matlab.sh`, which prints run_stage's markers, can fail or slow a stage, and logs concurrent calls.
- It replaces the PowerShell queries with `ops/d91_stub_sys.sh`.
- Every `V7T_*` variable points into the sandbox. The harness refuses a sandbox path inside a live folder.

**What the scenarios cover.**

- Normal flow:
  - p3's C1p starts only after profile 1's SURV3;
  - p2 is created, pushed, given the set-4 stages, and starts after profile 1's chain ends;
  - p2's C1p starts after p3's SURV3;
  - every final phase runs.
- A profile 1 crash before SURV3: alert; p3 and p2 held; an old go file is refused; a fresh one resumes from C1c.
- The rerun go file: an invalid list, a failed rerun that holds C1p back, a new version that reruns, and a go file written after C1p has started.
- Two reboots: one during the wait (profile 1 cut, resumed on its go file) and one inside p3's C1p (a second C part, unreadable pools moved aside). Also a second takeover refused while the first lives.
- The takeover's bash killed while its MATLAB runs on: no second MATLAB in that worktree.
- The zombie and exited sessions not counted, plus CPU and live-session holds before LAT. Also a chain that stopped after RPT before its end marker.
- A turn holder that exited (alert; turn file untouched) and one that is gone; a silent p1.log; a p3 stage left open, resumed on its go file.
- The refusals: TEMP elsewhere, launcher alive, fix script alive, a PID reused, a PID missing.

**Result, 18.10.** 105 of 105 checks passed.

The run took about 12 min, beside the live profile 1 C1p, and started no MATLAB.

The status mode, run read-only against the live logs, reads the expected state:

- p1 and p3 at `next C1p (index 13)`;
- the parallel turn held by 42560 (live);
- 46 GB of free commit.

**Heartbeat.** In one earlier run on the loaded machine, the 1 s test heartbeat once stalled for 11 s. With the 30 s period, the live gap therefore stays well under 60 s.
