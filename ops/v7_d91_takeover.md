# v7 takeover of the d86 launcher (v7_d91_takeover.sh)

Live copy: `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_takeover.sh`. Its log is `v7_d91_takeover.log` in the same folder.
In the repository it lives on branch `d91-takeover`, under `ops/`, together with the test harness and the stubs. The live copy and `ops/` are kept identical.

## What it replaces, and why

These processes still run (checked on 18.10 at 07:15):

- The d86 launcher, bash PID 24172, in resume mode, holding SRC 9b5c9f1 in memory. Its wrappers are 39928 (`Git\bin\bash.exe -lc …`) and 32328 (`usr\bin\bash.exe -lc …`).
- Its profile 1 chain subshell, 43428, which runs 43972, then the MATLAB stub 44984, then MATLAB 42560. This chain is in C1p. 43428 and 43972 carry the launcher's command line, because MSYS forks keep it; they were created on 17.10 at 16:42:13, 8 s after the launcher's part `20261017_164205` began.
- The profile 3 fix script, bash PID 49732, with its wrappers 39124 and 24652. It is waiting for profile 1's SURV3.

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
| P3 | Waits until p1.log's current part is past SURV3. Never accepts 'chain ended' instead. Meanwhile it runs the B-stage rerun listed in `p3_brerun.go`, if that file exists (conditions below). Then it runs C1p..RPT under a new `##### PART` header in the launcher's format. |
| P2 | Starts once p1.log's current part shows `chain ended rc=0` past RPT, or on `p2_start.go`. Nothing else starts it: not `p1.abandon`, not a failed profile 1. It branches v7-p2 from v7-dev, sets profile.json n_rx to 2, makes fresh data/ and results/, pushes, and writes the commit to code_commit.txt (no SRC check). It runs A0-B2F, B3n, B3m, the stages listed in `p2_set4.stages`, then B3, B3a, B4, OOD and B4s. It waits until p3.log's current part is past SURV3, then runs C1p..RPT. If profile 3 is given up or its chain failed before SURV3, it raises an alert that names `p2_c1p.force`. |
| Final | Waits until all three tracks have ended and the machine is idle. It then runs LAT, KPI, DASH, WEAK, RPT and the console bundle for each profile. |

The machine counts as idle when all of these hold:

- No live MATLAB runs pipeline stages. A session counts when its `-batch` command contains `run_stage(`. Not counted: exited processes (zombie 32824), smoke runs, and the worktree copies, which are recognised by their exact `-batch` command: `run_stage('A0','B3m')`, `run_stage('A0','B3q')`, `run_stage('A0','B3r')` and `set4_build`. Profile 2's own chain names B3m, B3q and B3r among many stages, so it always counts.
- CPU is below 15 % on two polls taken 10 min apart.
- If that never happens, it goes ahead after at most 4 h.

**Dependencies.** Every dependency between tracks is read from the log markers (`##### PART`, `##### STAGE X done`, `##### chain ended rc=N`), never from process ids. Each profile has one MATLAB at a time in its own worktree. Before each chain starts, the takeover checks:

- the worktree is on its branch;
- no merge is in progress;
- there are no uncommitted changes in code/;
- at least 45 GB of commit is free (65 GB for profile 3's B-stage rerun);
- no bash runs an old script outside the allow-list (below).

**Profile 3's B-stage rerun** starts only when all of these hold:

- profile 1's chain is not between the start of C1p and `##### STAGE C1c done` (pool build, the pool gather into one 18 GB file, and C1c's clean pools). A profile 1 chain that ended, was given up, or was cut by a reboot does not hold it;
- at least 65 GB of commit is free (`V7T_RERUN_NEED_GB`): OOD's 36 GB peak on profile 3, about 20 GB of profile 1's pool-gather growth, and a 10 GB margin;
- profile 3's C1p has not started.

Its MATLAB runs with `-singleCompThread`, so it does not slow profile 1's C1p.

**Safety at start.** The takeover refuses to start when any of these holds:

- `cygpath -w "$TEMP"` is not `C:\Users\ADISUL~1\AppData\Local\Temp`. Otherwise the parallel turn file would split.
- The boot time cannot be read (5 tries), or it lies in the future. Without it a chain cut by a reboot could not be told from a running one.
- PID 24172 or 49732 is still alive with its script in its command line.
- Any bash process has `v7_d86_launch.sh` or `v7_d87_p3fix.sh` in its command line, other than an allowed subshell. A PID in `V7T_ALLOW_PIDS` counts as allowed only when all of these hold: its command line is the launcher's; profile 1's current part was written by the launcher (not by the takeover) in this boot; and the process was created within 15 min after that part began. After a reboot, or for a PID reused by a new process, the allow-list therefore matches nothing.
- Another takeover's heartbeat (`v7_d86/takeover.lock`) is under 20 min old and newer than the last boot.

**Retiring the old launcher.** Once the checks pass, the takeover renames the `SRC <sha>` line of `v7_d86/code_commit.txt` to `SRC_RETIRED_BY_D91 <sha>`. Before that it copies the file to `code_commit_before_d91_<time>.txt` and appends the SHA to `retired_src.txt`, so the run's provenance is kept.

The launcher's resume reads that line with `sed -n 's/^SRC //p'` and refuses when it does not equal its own SHA (v7_d86_launch.sh lines 348-350, message `the run was launched on , not <sha>; not resumed`). So from the takeover's first start on, `v7_d86_launch.sh … resume` refuses for good, also after a reboot. That refusal comes before it writes any part header or starts any chain.

Nothing else reads that line:

- the takeover writes its own commit notes;
- v7_d87_p3fix.sh reads it only for its part header, and it is retired too;
- no MATLAB code in v7-dev, v7-p3, d91-set4 or d91-fuse reads code_commit.txt.

The harness runs a copy of the launcher in a sandbox and confirms both cases. Before the takeover, with SRC intact, its resume passes the code check. After the takeover and a reboot, it refuses with exit 1 and writes nothing.

A refused resume removes run.lock when it exits. The takeover's heartbeat recreates it.

Do not run `v7_d86_launch.sh` again in any mode. Its launch mode (`<SHA>` without `resume`) is not blocked by the retired line, and it would archive the logs and merge code. The scan below alerts on it, and no new takeover MATLAB starts while it runs.

**While running.** It touches `v7_d86/run.lock` and `takeover.lock` every 30 s, and never more than 60 s apart. Every 5 min it scans for bash processes running the old scripts. For each one outside the allow-list it writes `ALERT_old_script_<pid>_<created>`, and it starts no MATLAB until that process is gone.

It never touches the parallel turn file. If the PID in that file has exited but still lingers as a zombie, every `take` blocks, so the takeover writes an alert instead.

**MATLAB's PID.** After starting a MATLAB, the takeover waits up to 60 s until the subshell's Windows PID shows a process with `matlab` in its command line, and only then records it in `takeover_ml_<profile>.pid`. If that does not happen within 60 s (a heavily paging machine), it raises `ALERT_ml_pid_<profile>_*` and records the subshell's PID.

When a restarted takeover finds a recorded PID whose command line is a takeover's, it treats that PID as possibly alive in two cases:

- the PID has a live MATLAB child;
- the PID was created before this takeover started, so it may still exec MATLAB.

In either case it starts no second MATLAB in that worktree.

## Procedure

The PIDs below were checked on 18.10 at 07:15 (status mode and a read-only process query).

### 1. Read-only check (Adi or the agent)

```bash
V7T_ALLOW_PIDS='43428 43972' bash '/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh' 24172 49732 status
```

What it should show:

- p1 at `next C1p (index 13)` with `idle part: no`;
- p3 at `next C1p (index 13)` with `idle part: yes`;
- `p2: no log`;
- `p3 rerun request: none`;
- `old scripts outside V7T_ALLOW_PIDS ('43428 43972'): 39928 32328 24172 39124 24652 49732` before steps 2 and 3, and an empty list after them;
- `code_commit.txt: SRC 9b5c9f1…` (still intact);
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
- Its wrappers 24652 and 39124 exit on their own. If they are still there after 1 min, end them the same way: they only wait for 49732.
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
Get-CimInstance Win32_Process -Filter "Name='bash.exe'" | Where-Object { $_.CommandLine -like '*v7_d8*' } | Select-Object ProcessId,ParentProcessId,CreationDate
```

- All four processes are still alive: the chain subshell, its child, the MATLAB stub and MATLAB.
- run.lock is under 30 s old. The chain subshell touches it every 10 s.
- The last query lists only 43428 and 43972. The wrappers 32328 and 39928 exit on their own. If either is still there after 1 min, end it with `taskkill /PID <pid> /F`; it only waits for 24172.
- p1.log keeps growing.

### 4. Launch the takeover hidden, the same way as the launcher

Use PowerShell. Launching it the same way gives the same TEMP: a login bash sees `TEMP=/tmp`, which is `C:\Users\ADISUL~1\AppData\Local\Temp`. This was checked on 18.10.

```powershell
$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "V7T_ALLOW_PIDS=''43428 43972'' bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
```

`ReturnValue` must be 0.

The same command serves every later start, after a crash or a reboot. The allow-list stops matching by itself once profile 1's launcher chain is gone or the machine has rebooted.

### 5. Check after the launch (within 5 min)

- `v7_d91_takeover.log` shows these lines, in order:
  1. `code_commit.txt: SRC 9b5c9f1… retired (the launcher's resume refuses)`;
  2. `v7 takeover started (boot …, TEMP C:\Users\ADISUL~1\AppData\Local\Temp, poll 300 s, allowed launcher subshells: 43428 43972)`;
  3. one line each for p1 and p3: `next C1p (index 13)`;
  4. `p2: waits for profile 1's chain to end with rc=0`;
  5. `p3: C1p waits for p1's SURV3`.
- `v7_d86\code_commit.txt` starts with `SRC_RETIRED_BY_D91 9b5c9f1…`. `code_commit_before_d91_<time>.txt` holds the old line, and `retired_src.txt` names the SHA.
- `v7_d86\takeover.lock` holds the takeover's PID and is under 60 s old. `run.lock` is under 60 s old.
- The status mode (step 1) still shows the same state, with `SRC_RETIRED_BY_D91` and an empty old-script list.
- There is no `v7_d86\ALERT_*.txt`.
- The log has no line `the launcher … still runs`, `outside V7T_ALLOW_PIDS` or `not started`.

### Latest dates

The takeover must be running before profile 1's SURV3 finishes, because it then starts profile 3's C1p. That is at the earliest **22.10 about 13:00**; the estimate runs to 23.10 about 12:30.

It also covers profile 2. The old launcher would refuse profile 2 or misplace it at profile 1's chain end, at the earliest **23.10 about 10:00**.

A profile 3 rerun on the fusion revision needs the takeover running before the 21.10 go/no-go.

Launch it as soon as this review is done (18-19.10). It also covers a profile 1 crash, audit item (c), from the moment it starts. It also blocks the old resume after a reboot.

## Control files (in `uav-gcs-logs\v7_d86\`)

| File | Effect |
|---|---|
| `p1_resume.go` | After `ALERT_p1_failed_*` or `ALERT_p1_cut_*`: profile 1 goes on from its first unfinished stage under a new part. A0 runs first if it stopped inside the B stages. `policy_pools.mat` is checked before C1p. The file must be newer than p1.log; it is renamed `.used_<time>`. |
| `p3_resume.go`, `p2_resume.go` | The same after `ALERT_p3_failed_*` or `ALERT_p2_failed_*`. Also after `ALERT_p3_open_*`, which means p3_fix died with a stage open; check first that no MATLAB runs in uav-gcs-v7-p3. |
| `p2_start.go` | Starts profile 2 before profile 1's chain has finished (e.g. after `p1.abandon`). It is renamed `.used_<time>`. |
| `p3_brerun.go` | The stages of profile 3's B-stage rerun, e.g. `B2F B3 B3a B4 B4s`. They must be stages of uav-gcs-v7-p3's run_stage.m, and no C stage. They run with A0 first, while profile 3 waits for SURV3, under the conditions above. Each version (content plus time) runs once; touching the file runs it again. It is ignored once profile 3's C1p has started. A failed rerun holds C1p back until the file is written again, or until `p3_c1p.force` exists. |
| `p3_c1p.hold`, `p2_c1p.hold` | Hold that profile before C1p. Example: until the 21.10 go/no-go on the fusion revision. |
| `p3_c1p.force`, `p2_c1p.force` | Start C1p without the other profile's SURV3, and past a failed rerun. Use it only when the other profile is given up. |
| `p2_set4.stages` | Extra profile 2 stages run after B3m, e.g. `B3q B3r`. They must be in v7-dev's run_stage.m when profile 2 branches. The file is read once, when profile 2's B stages first start. |
| `p1.abandon`, `p3.abandon`, `p2.abandon` | End that track. The final phase skips that profile. If profile 1 is given up, profile 3 also needs `p3_c1p.force` and profile 2 needs `p2_start.go`. If profile 3 is given up before its SURV3, profile 2 needs `p2_c1p.force`. |

**Alerts** go to `v7_d86\ALERT_<topic>.txt` and to the takeover log. Delete each alert once it is handled.

| Topic | Meaning |
|---|---|
| `p1_failed`, `p1_cut`, `p3_failed`, `p2_failed`, `p3_open` | A chain failed, was cut, or was left with a stage open. |
| `p1_silent` | p1.log has not changed for 6 h. |
| `p3_rerun_failed`, `p3_rerun_blocked`, `p3_rerun_invalid`, `p3_go_ignored` | A problem with `p3_brerun.go` or its rerun. |
| `p2_set4_invalid`, `p2_prep` | A problem with `p2_set4.stages`, or profile 2's worktree could not be prepared. |
| `p2_wait_p1_abandon` | Profile 1 is given up; profile 2 starts only on `p2_start.go`. |
| `p2_c1p_p3_abandon`, `p2_c1p_p3_failed` | Profile 3 was given up or failed before its SURV3; profile 2's C1p starts only on `p2_c1p.force` (or after profile 3 resumes past SURV3). |
| `old_script_<pid>_<created>` | A bash outside the allow-list runs v7_d86_launch.sh or v7_d87_p3fix.sh; no takeover MATLAB starts until it is gone. |
| `code_<g>` | A worktree is on the wrong branch, a merge is in progress, or code is uncommitted. |
| `headroom_<g>` | More than 1 h below the free-commit gate (45 GB, 65 GB for the rerun). |
| `ml_alive_<g>` | An earlier takeover MATLAB still runs in that worktree. |
| `ml_pid_<g>` | A started MATLAB did not show its Windows PID within 60 s; the subshell's PID was recorded instead. |
| `stale_<file>` | A go file older than the event it should answer. |
| `turn_holder_<pid>` | The parallel turn file names an exited MATLAB. |

For `turn_holder_<pid>`, Adi either:

- ends that process's leftover children (e.g. `MATLABWebUI.exe` with that parent), or
- moves the turn file aside, once sure that no live MATLAB holds the turn.

## Fusion revision and the fourth test set

**Profile 3.** Merge the revision into v7-p3 only while profile 3 waits in the takeover. That is from now until its C1p starts, and never while its rerun runs. Then write `p3_brerun.go` with the stages the revision changes.

For a fusion-only revision (select_fusion and what reads `data/fusion.mat`), the list is `B2F B3 B3a B4 B4s`:

- B2F builds the fusion;
- B3 (eval_detector), B4 (eval_unseen_snr) and B4s (eval_unseen_severity) read the system's class through it;
- B3a (compare_architectures) also loads `data/fusion.mat` (N, lambda, the latch threshold) and refits the fusion for each architecture, so it stays in the list;
- leave OOD out unless the revision touches eval_ood_detection or its inputs. eval_ood_detection reads no fusion output, and OOD is the 36 GB peak.

Do not list B3m or B3r: they re-read a test set, and that decision belongs to the other track.

- To decide on 21.10 without a race against SURV3, write `p3_c1p.hold` first. Remove it once the go file or the no-go decision is in place.
- The rerun waits until profile 1 is past C1c and 65 GB of commit is free. On the overnight audit's estimate, profile 1's C1c ends between 22.10 09:00 and 23.10 02:00, and SURV plus SURV3 then take 6-10 h. That is the rerun's window before profile 1's SURV3. If the rerun runs longer, profile 3's C1p starts when the rerun ends. Write the go file before profile 1's C1c ends so the rerun starts at once.
- The rerun's code commit and its request id go to code_commit.txt.

**Profile 2.** It uses whatever v7-dev holds when profile 1's chain ends. Its commit goes to code_commit.txt. To give profile 2 the fourth test set inside its own chain, write `p2_set4.stages` (e.g. `B3q B3r`) before then.

## After a reboot or a crash

1. Run the same launch command (step 4). The PIDs can stay: a PID whose command line is no longer its script does not block, and the allow-list no longer matches anything after a reboot.
2. The old launcher's resume stays refused (retired SRC line). If someone runs it anyway, it refuses before writing a part; run.lock comes back with the takeover's heartbeat.
3. Profile 3's and profile 2's own parts go on from their first unfinished stage. A0 runs first inside the B stages. An unreadable `policy_pools.mat` is moved aside before C1p, and C1p keeps its per-cell checkpoints.
4. A part whose stages were all done before the interruption only gets its end marker.
5. Profile 1's part, cut by the reboot, raises `ALERT_p1_cut_*`. Check p1.log, then write `p1_resume.go`.

A crash without a reboot is handled like this:

- A takeover whose subshells still heartbeat refuses a second start.
- If the takeover's own MATLAB outlived its bash, the new takeover waits for it (`ALERT_ml_alive_*`) before starting another in that worktree. This also holds when the recorded PID is still the subshell that had not yet exec'd MATLAB.

## Tests

```bash
bash ops/d91_takeover_test.sh [sandbox] [scenario ...]
```

The default sandbox is `…\scratchpad\d91_takeover_test\`. The default scenarios are `status normal p1crash rerun rerungate reboot oldlaunch orphan slowexec zombie turn p2gate refuse`.

**How it runs.**

- It copies p1.log, p3.log, code_commit.txt and v7_d86_launch.sh once from the live logs, as the starting state: profile 1 inside C1p, profile 3 idle after the fix script.
- It builds a git repository with v7-dev and v7-p3 worktrees and a bare origin.
- It replaces MATLAB with `ops/d91_stub_matlab.sh`. The stub prints run_stage's markers, can fail or slow a stage, logs concurrent calls and MATLAB options, and records each start.
- It replaces the PowerShell queries with `ops/d91_stub_sys.sh`, which includes the old-script scan, process creation times, MATLAB children and a lagging exec.
- Every `V7T_*` variable points into the sandbox. The launcher's copy runs with every `V7L_*` variable in the sandbox and its PowerShell calls replaced by a function. The harness refuses a sandbox path inside a live folder.

**What the scenarios cover.**

- Normal flow:
  - p3's C1p starts only after profile 1's SURV3;
  - p2 is created, pushed, given the set-4 stages, and starts after profile 1's chain ends;
  - p2's C1p starts after p3's SURV3;
  - every final phase runs;
  - code_commit.txt changes only in its retired SRC line plus the takeover's notes, with its backup and the retired SHA kept.
- A profile 1 crash before SURV3: alert; p3 and p2 held; an old go file is refused; a fresh one resumes from C1c.
- The rerun go file: an invalid list, a failed rerun that holds C1p back, a new version that reruns, and a go file written after C1p has started.
- The rerun gate:
  - no rerun while profile 1's C1p is open, or after C1p before C1c is done;
  - after C1c, it waits for 65 GB (50 GB free passes the chains' 45 GB gate but not this one);
  - it then runs, alone with `-singleCompThread`.
- Two reboots: one during the wait (profile 1 cut, resumed on its go file) and one inside p3's C1p (a second C part, unreadable pools moved aside). Also a second takeover refused while the first lives.
- The old launcher:
  - a control: with SRC intact, the launcher's copy passes its resume check;
  - the takeover starts beside the allowed subshells and retires SRC;
  - an old launcher under a new PID raises an alert;
  - after a reboot, the launcher's resume refuses with exit 1 and writes no part;
  - an allowed PID reused after the reboot is refused;
  - the takeover restarts, with run.lock back and one backup.
- The takeover's bash killed while its MATLAB runs on: no second MATLAB in that worktree.
- A lagging exec:
  - at 3 s, the PID file waits for the MATLAB and there is no alert;
  - beyond the wait, there is an alert and the subshell's PIDs are recorded;
  - after the takeover is killed and restarted, that PID counts as alive and no second MATLAB starts.
- Idle: the zombie, exited sessions, smoke runs and the copies' exact commands are not counted. Profile 2's own chain, which names B3m, B3q and B3r, holds LAT back, and so do CPU and a live session. Also a chain that stopped after RPT before its end marker.
- A turn holder that exited (alert; turn file untouched) and one that is gone; a silent p1.log; a p3 stage left open, resumed on its go file.
- Profile 2's start:
  - after `p1.abandon`, an alert names `p2_start.go`, and p2 waits for it;
  - profile 3 failing, then being given up, before SURV3 raises alerts naming `p2_c1p.force`;
  - p2's C1p starts only on that file.
- The refusals:
  - TEMP elsewhere, launcher alive, fix script alive, a PID reused, a PID missing;
  - a boot time that is empty, non-numeric or in the future;
  - a launcher wrapper outside the allow-list, an allowed PID created long after its part, a fix script under another PID;
  - none of them leaves a lock or changes code_commit.txt.

**Result, 18.10.** 164 of 164 checks passed in the final full run (an earlier full run failed 6 checks, all from harness timing on the loaded machine plus one wrong path in the test; it also found a race in which profile 1's end marker, written between two reads, raised a false `p1_failed` alert; the track now re-checks completion first).

The run took about 26 min (07:37-08:03), beside the live profile 1 C1p and the two side MATLAB jobs, and started no MATLAB.

The status mode, run read-only against the live logs on 18.10 at 07:12 with `V7T_ALLOW_PIDS='43428 43972'`, reads the expected state:

- p1 and p3 at `next C1p (index 13)`;
- old scripts outside the allow-list: 39928 32328 24172 39124 24652 49732 (43428 and 43972 allowed);
- the parallel turn held by 42560 (live);
- 45 GB of free commit;
- 42560 the only live pipeline MATLAB (the set-4 build 8036 and the d91 measurement 47680 are not counted).

The real process queries were also checked read-only:

- 43972's MATLAB child is 44984;
- 42560 was created at 16:42:14 on 17.10.

**Heartbeat.** In one earlier run on the loaded machine, the 1 s test heartbeat once stalled for 11 s. With the 30 s period, the live gap therefore stays well under 60 s.
