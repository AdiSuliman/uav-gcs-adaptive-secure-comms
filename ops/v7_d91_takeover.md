# v7 takeover of the d86 launcher (v7_d91_takeover.sh)

Live copy: `C:\Users\Adi Suliman\uav-gcs-logs\v7_d91_takeover.sh`. Its log is `v7_d91_takeover.log` in the same folder.
In the repository it lives on branch `d91-takeover`, under `ops/`, together with the test harness and the stubs. The live copy and `ops/` are kept identical.
`ops/` also holds the gate wrapper for hand-runs, `v7_d91_gated_run.sh` and `v7_d91_gated_state.ps1`, so the harness tests it with the takeover. Its live copies in `uav-gcs-logs` and its copies `docs/d91_gated_run.sh.txt` and `docs/d91_gated_state.ps1.txt` on `v7-deploy-d91` are kept identical to `ops/`.

**Refreshing the live copy.** Bash reads a script file while it runs it. The takeover's run section is the function `main`, called on the file's last line (`main "$@"; exit $?`), so bash has parsed the whole file before anything runs, and a running takeover reads nothing more from it. Even so, replace the live copy only while no takeover runs, or by writing a temp file in the same folder and `mv` over the live copy. Never `cp` onto it: a `cp` rewrites the open file in place, and a takeover that is still starting up would read the new file from its old byte offset. The harness checks this (scenario `overwrite`).

## What it replaces, and why

These processes still run (checked on 18.10 at 09:10, and unchanged at 12:40):

- The d86 launcher, bash PID 24172, in resume mode, holding SRC 9b5c9f1 in memory. Its wrappers are 39928 (`Git\bin\bash.exe -lc …`) and 32328 (`Git\bin\..\usr\bin\bash.exe -lc …`). Three forks of 24172, 47724 → 46828 → 50260 (created 08:49), also carry its command line.
- Its profile 1 chain subshell, 43428, which runs 43972, then the MATLAB stub 44984, then MATLAB 42560. This chain is in C1p. 43428 and 43972 carry the launcher's command line, because MSYS forks keep it; they were created on 17.10 at 16:42:13, 8 s after the launcher's part `20261017_164205` began. 43428 writes the chain's end marker.
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
| P1 | Only reads p1.log. If the chain ends with rc != 0, is cut by a reboot, or its subshells (43428, 43972) are gone with no MATLAB child left and no end marker, it writes an alert and runs nothing until `p1_resume.go` exists. A resume from C1p or C1c waits while profile 3's B-stage rerun runs, and any resume waits while a recorded MATLAB of the launcher chain still runs. On `p1_cut_after.SURV3` it ends the chain's win64 MATLAB once the current part shows `##### STAGE SURV3 done` (see "Deploy controls"). |
| P3 | Waits until p1.log's current part is past SURV3. Never accepts 'chain ended' instead. Meanwhile it runs the B-stage rerun listed in `p3_brerun.go`, if that file exists (conditions below). Then it runs C1p..RPT under a new `##### PART` header in the launcher's format. |
| P2 | Starts once p1.log's current part shows `chain ended rc=0` past RPT, or on `p2_start.go`. Nothing else starts it: not `p1.abandon`, not a failed profile 1. It branches v7-p2 from v7-dev, sets profile.json n_rx to 2, makes fresh data/ and results/, pushes, and writes the commit to code_commit.txt (no SRC check). It runs A0-B2F, B3n, B3m, the stages listed in `p2_set4.stages` (B3q only; B3r is refused), then B3, B3a, B4, OOD and B4s. It waits until p3.log's current part is past SURV3, then runs C1p..RPT. If profile 3 failed before SURV3, or was given up and its chain has stopped, it raises an alert that names `p2_c1p.force`. While `p2_start.hold` exists it neither branches nor starts. |
| Final | Waits until all three tracks have ended on purpose and the machine is idle. It then runs LAT, KPI, DASH, WEAK, RPT and the console bundle for each profile. Per profile it first waits for a MATLAB an earlier takeover started there, and reads the log only after it, so a restart during the final phase never writes a stale final part. While `final.hold` exists it starts nothing, and a hand-run in a worktree holds that profile's part. If a track died, the final phase is skipped (see "Watchdog"). |

The machine counts as idle when all of these hold:

- No live MATLAB runs pipeline stages. A session counts when its `-batch` command contains `run_stage(`. Not counted: exited processes (zombie 32824), smoke runs, and the worktree copies, which are recognised by their exact `-batch` command: `run_stage('A0','B3m')`, `run_stage('A0','B3q')`, `run_stage('A0','B3r')` and `set4_build`. Profile 2's own chain names B3m, B3q and B3r among many stages, so it always counts. A failed MATLAB query counts as busy.
- CPU is below 15 % on two polls taken 10 min apart.
- If that never happens, it goes ahead after at most 4 h.

**Dependencies.** Every dependency between tracks is read from the log markers (`##### PART`, `##### STAGE X done`, `##### chain ended rc=N`), never from process ids. Each profile has one MATLAB at a time in its own worktree. Before each chain starts, the takeover checks:

- the worktree is on its branch;
- no merge is in progress;
- there are no uncommitted changes in code/;
- at least 45 GB of commit is free (65 GB for profile 3's B-stage rerun);
- no bash runs an old run script outside the allow-list (below), and the process scan could be read;
- the profile's log reads as a well-formed part (below); it is read again just before the part header.

**Profile 3's B-stage rerun** starts only when all of these hold:

- profile 1's chain is not between the start of C1p and `##### STAGE C1c done` (pool build, the pool gather into one 18 GB file, and C1c's clean pools). A profile 1 chain that ended with an end marker, or was cut by a reboot, does not hold it, unless a MATLAB of that chain outlives its end marker (see "Profile 1's chain MATLAB" below). `p1.abandon` releases it only once profile 1's chain has stopped (as for the force files): the file does not stop the launcher's chain. A chain whose subshells died inside C1p or C1c without an end marker does hold it, so a resume there goes first;
- at least 65 GB of commit is free (`V7T_RERUN_NEED_GB`): OOD's 36 GB peak on profile 3, about 20 GB of profile 1's pool-gather growth, and a 10 GB margin;
- profile 3's C1p has not started.

Its MATLAB runs with `-singleCompThread`, so it does not slow profile 1's C1p.

The other direction holds too: a profile 1 resume from C1p or C1c (on `p1_resume.go`) waits while a rerun part of this boot has no `rerun ended` line. Both checks and both part headers sit under one lock (`v7_d86/takeover_gate.d`), so the two can never start together.

**Safety at start.** The takeover refuses to start when any of these holds:

- `cygpath -w "$TEMP"` is not `C:\Users\ADISUL~1\AppData\Local\Temp`. Otherwise the parallel turn file would split.
- The boot time cannot be read (5 tries), or it lies in the future. Without it a chain cut by a reboot could not be told from a running one.
- PID 24172 or 49732 is still a bash running its script, or its command line cannot be read (5 tries).
- A bash runs an old run script as its script (`v7_d86_launch.sh`, `v7_d87_p3fix.sh`, `v7_d87_redo.sh`, `v7_d83_launch.sh`, `v7_fix_resume.sh`, `v7_d87_b3m.sh`, `v7_wait_c1p_then_fix.sh` or `v7_guard_c1p_fail.sh`), other than an allowed subshell, or the process scan cannot be read (5 tries). Only a bash that runs the script counts: as its first argument, or as `bash <script>` inside `-lc "…"`. A command that only mentions the name (a grep, an agent's tool call) does not. A process counts only when two scans 5 s apart both list it, so a fork that lives for milliseconds (a command substitution inside the launcher's chain subshell) is not counted. A PID in `V7T_ALLOW_PIDS` counts as allowed only when all of these hold: it runs the launcher; profile 1's current part was written by the launcher (not by the takeover) in this boot; and the process was created within 15 min after that part began. After a reboot, or for a PID reused by a new process, the allow-list therefore matches nothing.
- Another takeover holds `v7_d86/takeover.lock`, written in this boot: the PID in it still runs the takeover, at any lock age (a lock whose takeover still runs is never counted as stale; at 20 min or more the refused start also writes `ALERT_takeover_lock_held_*`); or its main bash is gone but the lock is under 90 s old (3 heartbeats); or that PID's command line cannot be read (5 tries). A lock from before the last boot is stale. The lock is taken atomically (a short `takeover.lock.d` section, then a no-clobber write), so two launches at once start one takeover.

**Unknown is never an answer.** A failed process query never counts as 'process gone'. Every query prints an explicit answer (`none` for a missing process, an `end` line after a list); empty output means the query failed. The MATLAB-children query lists only live processes: an exited one whose process object lingers (such as the zombie 32824) does not count. Each PowerShell call is ended after 120 s, with its process tree (`taskkill /T` on that PowerShell only), and then also counts as failed.

The same holds for the logs. Every value derived from a log is unknown unless it is well formed:

- the current part's header must read `##### PART <stamp> <mode> SRC <sha> FROM <i> <stage> A0 <0|1> … #####`;
- the stage list must be complete (36 stages for profiles 1 and 3; profile 2's from its header's `AB` field);
- each grep over a part must have read all of it (only then does a line `#END` follow its output);
- only profile 2's log may be missing, and then it reads as 'nothing yet' (index 0); a missing p1.log or p3.log is unknown, never index 0 (index 0 would rebuild A0 to B4s), and raises `ALERT_log_missing_<g>` at once; an existing log that reads empty or garbled is unknown.

On unknown, nothing acts. 'Past SURV3', 'finished' and 'chain stopped' read as no; 'profile 1 in C1p or C1c' and 'rerun open' read as yes. No part header is written and no MATLAB starts. The track logs it once (`… could not be read … (read again every 30 s)`), reads again every 30 s, and writes `ALERT_unknown_<what>_*` after 1 h. The start checks ask 5 times, then refuse.

**Retiring the old scripts.** Once the checks pass, the takeover:

1. renames the `SRC <sha>` line of `v7_d86/code_commit.txt` to `SRC_RETIRED_BY_D91 <sha>`. Before that it copies the file to `code_commit_before_d91_<time>.txt` and appends the SHA to `retired_src.txt`, so the run's provenance is kept;
2. renames every old run script in `uav-gcs-logs` to `<name>.retired_by_d91`: `v7_d86_launch.sh`, `v7_d87_p3fix.sh`, `v7_d87_redo.sh`, `v7_d87_resume.ps1`, `v7_d83_launch.sh`, `v7_fix_resume.sh`, `v7_d87_b3m.sh`, `v7_wait_c1p_then_fix.sh` and `v7_guard_c1p_fail.sh`. A rename that fails is alerted and retried every 5 min.

Each rename is logged (`<name> renamed to <name>.retired_by_d91 (old run script); it cannot be run any more`), before the line `v7 takeover started`. From then on none of them can be started in any mode, also not the launcher's launch mode (`<SHA>` without `resume`), which does not read SRC. The renamed files stay readable for the record. `v7_d87_redo.sh` had no lock and no SRC check, and would start MATLAB in both live worktrees at once. `v7_d87_b3m.sh` copies its copies' `*fresh2*` files into the live profile 1 and profile 3 `data/` and `results/`. `v7_wait_c1p_then_fix.sh` ends every MATLAB running `run_stage('B3a'` or a parallel server once a profile 1 C1p is done, then runs `v7_fix_resume.sh`; `v7_guard_c1p_fail.sh` ends a bash running the drive-swap launcher. The d91 scripts (`v7_d91_set4.sh`, `v7_d91_speed_proofs.sh`, `v7_d91_tests2.sh`, `v7_d91_tests3.sh`, `v7_d91_tests4.sh`, the fusion queue `d91q.sh`) are not old run scripts: the takeover neither renames them nor counts them in its scan.

**Renaming the launcher while its chain subshells run is safe.** Only the launcher's main bash (24172) reads the script file, and the start checks confirm it is gone. The chain subshells 43428 and 43972 run the `chain` and `run_ml` functions, which bash parsed before it forked them. They read nothing more from the file, and they write `##### chain ended` with builtins and forks only. On Windows/MSYS a rename (not an edit) leaves every open handle valid. The harness checks this in the sandbox (scenario `rename`):

- a bash whose script is renamed while it runs goes on reading the script's later lines;
- a chain function forked in the background, whose main bash was ended with `taskkill /F` before the rename, runs its forks to the end and writes its end marker.

The retired SRC line also blocks the launcher's resume. The launcher reads that line with `sed -n 's/^SRC //p'` and refuses when it does not equal its own SHA (v7_d86_launch.sh lines 348-350, message `the run was launched on , not <sha>; not resumed`), before it writes any part header or starts any chain. A refused resume removes run.lock when it exits; the takeover's heartbeat recreates it. Nothing else reads that line:

- the takeover writes its own commit notes;
- v7_d87_p3fix.sh read it only for its part header, at its start;
- no MATLAB code in v7-dev, v7-p3, d91-set4 or d91-fuse reads code_commit.txt.

The harness runs a copy of the launcher in a sandbox and confirms both cases. Before the takeover, with SRC intact, its resume passes the code check. After the takeover and a reboot, it refuses with exit 1 and writes nothing.

**While running.** It touches `v7_d86/run.lock` and `takeover.lock` every 30 s, and never more than 60 s apart. Every 5 min it scans for bash processes running the old run scripts (two scans 5 s apart, as at the start). For each one outside the allow-list it writes `ALERT_old_script_<pid>_<created>`, and it starts no MATLAB until that process is gone.

**Watchdog.** The three tracks' MSYS and Windows PIDs are in `v7_d86/takeover_tracks.txt`. Each track writes `takeover_beat_<g>` (the time, with a shell builtin, no fork) at every heartbeat, and `takeover_end_<g>` when it ends on purpose (finished, or given up). The main bash writes `takeover_beat_main` the same way at every pass of its loop and in its naps (also during the final phase); the heartbeat subshell does not write it. Every 5 min the main loop checks the tracks:

- a beat older than 20 min (2 polls + 10 min): `ALERT_takeover_track_<g>_stalled_<beat>`. The track may hang in a query, a git command or a fork. If it does not beat again, stop the takeover and start it again;
- a track gone without its end file (a fork that failed for good, a stray taskkill): `ALERT_takeover_track_<g>_died`. The other tracks go on, but the final phase is skipped (log line `final phase skipped: track <g> died`). Stop the takeover and start it again with the same launch command; the restart resumes that profile from its log.

The main bash itself is watched too. At every heartbeat each track, and the heartbeat subshell every 30 s, reads `takeover_beat_main` with a builtin. When it is 20 min old, they write `ALERT_takeover_main_stalled_<beat>`, once per beat value. A beat read while it is being written (a prefix of the number, below the boot time) is ignored, here and for the track beats; the round-4 full run and a first round-5 run each raised a stall alert on such a prefix (`…_stalled_1`, `…_stalled_17923`). A stalled main bash is still alive, so the tracks finish their chains, but nothing raises the track alerts above, and the final phase does not run once they end. If it does not beat again, stop the takeover (Stopping the takeover, below) and start it again with the step 4 command; a MATLAB it started runs on, and the restart waits for it.

Each track checks at every heartbeat that the takeover's main bash still lives, and it beats right before every part header and every MATLAB start. If the main bash is gone (for example after `taskkill` of the PID in takeover.lock), every track stops within 30 s, `ALERT_takeover_main_gone` is written, and a MATLAB the takeover started runs on, with its PID kept in `takeover_ml_<profile>.pid`. When the main bash exits, it removes takeover.lock only once no track lives. Otherwise nothing refreshes the lock, so the same launch command can start the takeover again after 90 s.

It never touches the parallel turn file. If the PID in that file has exited but still lingers as a zombie, every `take` blocks, so the takeover writes an alert instead.

**MATLAB's PID.** A real MATLAB runs as two processes: the `bin\matlab.exe` launcher, and its child `bin\win64\MATLAB.exe`, which does the work (the pool workers are children of that one). The live profile 1 chain shows it: launcher 44984, win64 42560. The win64 process can outlive its launcher, for example when only the launcher is ended. So the PID file names both.

In every check below, a MATLAB is a process named `MATLAB.exe`: the launcher, the win64 process or a pool worker. Its helper processes `MATLABWebUI.exe`, `MATLABWindow.exe` and `MathWorksServiceHost.exe` never count, and neither does a command line that only has `matlab` in its path. Those helpers can outlive an exited MATLAB by days. On 19.10 the exited 32824 still had two live `MATLABWebUI.exe` children, three days after it ended, and the live 42560 had six `MATLABWebUI.exe` and one `MATLABWindow.exe` beside its six `MATLAB.exe` pool workers. A process counts as a live win64 MATLAB only when its path ends in `\win64\MATLAB.exe`.

Right before forking a MATLAB, the takeover claims `takeover_ml_<profile>.pid`: it writes its own bash's Windows PID and a line `claim <msys pid>`, and only then reads the hand-run file `<profile>_hand.busy` (and, in the final phase, `final.hold`). If either holds the start, it removes the claim and waits. Right after forking, it writes the subshell's Windows PID and an `msys <pid>` line. It then checks every second until that subshell shows a process whose command line runs `matlab.exe` (the launcher), and replaces the file with the launcher's Windows PID. If that does not happen within 60 s (a heavily paging machine), it raises `ALERT_ml_pid_<profile>_*` and rewrites the file with the subshell's current Windows PID and its `msys` line. It goes on checking every 60 s while MATLAB runs, and the file names the launcher once it shows. Once the launcher's live win64 child shows, the file gets a second line `win64 <pid>` and a third `win64_created <time>`, its creation time (checked every 5 s for 60 s, then every 60 s). If the launcher exits before its PID was taken, the file is rewritten with the last Windows PID that subshell showed, plus the `win64` lines if a live win64 child of it shows then, or a live win64 child of an exited `MATLAB.exe` child of it (the launcher, whose process object lingers). A win64 process that outlives such a launcher therefore still holds the worktree. Every write replaces the file in one step (a temp file and `mv`), so a reader never finds it empty.

The worktree counts as busy while either PID, or a live MATLAB child of either, lives. The takeover reads that file (written in this boot) before it starts a MATLAB in a worktree, and again right after each of its MATLAB launchers has exited. When the file has an `msys <pid>` line and MSYS still knows that process (`/proc/<pid>/winpid`, also from a restarted takeover), the Windows process that subshell is now, after its exec, is checked instead of the first line. Then:

- a command line on the first line that runs `matlab.exe` (launcher or win64): alive, unless the state query says that process has exited (its object lingering); then as for a gone process;
- a takeover's command line (the subshell's stub around its exec, or a claim): alive while it has a MATLAB child, or when it was created before this takeover started;
- `none` (the process is gone) or another program on the first line: alive while a live MATLAB child of that PID runs. Windows keeps a child's ParentProcessId after its parent exits, so this finds a win64 MATLAB whose launcher was ended before its `win64` line was written;
- the `win64` PID still a live win64 MATLAB, or a live MATLAB child of it: alive. An exited win64 process whose process object lingers does not count, even while its `MATLABWebUI.exe` or `MATLABWindow.exe` children live on;
- all of them gone: gone, and the file is removed;
- a query failed, or the file reads empty: unknown, it waits and asks again.

While it is alive the takeover waits (`ALERT_ml_alive_<profile>`). After its own MATLAB's launcher has exited, a 60 s grace comes first, so a normal end raises no alert. The wait also holds the chain's end marker: a launcher ended alone writes no `chain ended` line while its win64 MATLAB still runs. So no resume, no force file and no restart can start a second MATLAB beside it.

**Profile 1's chain MATLAB.** Profile 1's launcher chain is not the takeover's, so it has no PID file. While that chain runs, the profile 1 track records its MATLAB processes (at its first pass, then every 30 min, and again right before each check whether the chain's subshells are gone) in `v7_d86/takeover_p1_chain_ml.txt`, each as `<Windows PID> <creation time> <role>`: the live MATLAB children of 43428 and 43972 (the launcher 44984, role `launcher`), and their MATLAB children (the win64 42560, role `win64`, by its path `\bin\win64\MATLAB.exe`). A recorded process counts as alive while that PID is still the process created at that time. It also counts while it has a live MATLAB child created before any new process under that PID. The file counts only when written in this boot. While any recorded process lives, or its query fails:

- profile 1 is not over for the rerun gate, even after its end marker;
- profile 1's chain has not stopped, so `p1.abandon` with a force file does not count yet;
- `p1_cut` does not fire;
- a resume on `p1_resume.go`, and profile 1's final phase, wait (`ALERT_ml_alive_p1_chain`).

## Deploy controls (d91_deploy.md section 7)

Four control files serve the deploy procedures of `docs/d91_deploy.md` (branch `v7-deploy-d91`). Each is read again after every wait, never removed by the takeover (only `p1_cut_after.SURV3` is renamed once used), and listed by the status mode.

**Hand-runs: `<p>_hand.busy`** (`p1_hand.busy`, `p3_hand.busy`, `p2_hand.busy`). Every hand-run MATLAB in a live worktree goes through the gate wrapper `v7_d91_gated_run.sh`, which creates this file atomically before anything else and removes it when its MATLAB has ended. While the file exists, the takeover starts no MATLAB in that worktree:
- it checks the file before the part headers that release work there (profile 1's resume, profile 3's and profile 2's B stages, profile 3's rerun, C1p onward, each profile's final part) and again inside every MATLAB start, after the claim described above;
- a start that finds it logs one line `<p>: waits for a hand-run (<p>_hand.busy: <its command>)`, waits in naps of 5 min, and raises `ALERT_hand_busy_<p>_<mtime>` with the file's content after 12 h; once it is gone, the checks before the start run again;
- the file's `win64 <pid>` line (MATLAB appends it) is recorded with its creation time in `takeover_hand_<p>.pids`; if the file is removed while that MATLAB still lives, the worktree stays held until it has exited;
- the takeover never removes or edits the file. A wrapper ended by force leaves it: remove it by hand once its win64 PID is gone.

The register-then-check race is closed from both sides. The takeover claims its PID file before its last check of the busy file; the wrapper creates the busy file before its first check of the takeover's PID files, waits `D91_SETTLE` (30 s, one takeover step and a margin) after registering, and its state script counts a live takeover bash recorded there (the claim) as busy. Whichever of the two writes last sees the other.

**`final.hold`.** While it exists, the final phase starts no MATLAB. It is read at the start of the final phase, before each profile's part header, right after the idle wait, and inside every MATLAB start of the final phase (LAT to RPT, and the console bundle). While it waits, the final phase logs one line `final phase waits: final.hold` and beats; after 24 h it raises `ALERT_final_hold_<mtime>` (the hold may be intended). Removing it lets the final phase go on from where it waited, and the idle wait starts again (its 4 h limit too). A died track still skips the final phase as before.

**`p2_start.hold`.** While it exists, profile 2's track neither branches v7-p2 nor starts anything, also when profile 1's chain has finished or `p2_start.go` is present (the go file is then left in place). It is read in profile 2's wait and again right before the branch. One log line `p2: start held (p2_start.hold)`; `ALERT_p2_start_hold_<mtime>` after 48 h. Removed, v7-p2 branches from v7-dev's tip of that moment. `p2.abandon` while held ends the track.

**`p1_cut_after.SURV3`.** Stops profile 1's chain at SURV3's end, so the deploy can swap the fusion before C1d's choice is used (d91_deploy.md E2). SURV3 is the only stage accepted; any other name raises `ALERT_p1_cut_invalid_<name>` and ends nothing. While the file exists, profile 1's track looks at p1.log every 10 s (also while its own MATLAB runs):
- before `##### STAGE SURV3 done` is in the current part, nothing happens; a part that ended before SURV3 (a failed chain) keeps the file armed for the resumed part;
- once the marker is there and the part has no end marker, it ends the chain's win64 MATLAB with `taskkill /PID <pid> /F`, never `/T` and never the launcher. The PID is the `win64` entry of `takeover_p1_chain_ml.txt` for the launcher's chain, or the `win64` line of `takeover_ml_p1.pid` for a takeover part. Before the kill it must be alive, a live `\win64\MATLAB.exe`, and created at the recorded time; otherwise nothing is ended, `ALERT_p1_cut_pid_<stamp>` says what failed, and it checks again every 5 min;
- after the kill it appends `##### cut after SURV3 on request (p1_cut_after.SURV3) <date> #####` to p1.log, renames the file `.used_<time>`, and raises `ALERT_p1_cut_on_request_<stamp>`, which names every stage from C1d on whose done marker was already in the part (C1d is then rerun, later ones as E2 says: E9b by hand, or plan B). The launcher exits by itself, the chain writes `chain ended rc=…`, `ALERT_p1_failed_*` follows, and nothing resumes before `p1_resume.go`;
- if `SURV3 done` is already in the part when the file is first seen, the cut comes at once. If the part is already past SURV3 (its chain has ended after it, or the part began after it), nothing is ended: `ALERT_p1_cut_past_<stamp>`, and the file is renamed.

## Procedure

The PIDs below were checked on 18.10 at 09:10 (read-only process queries). Adi runs steps 2-4; the agent may run steps 1 and 5.

### 1. Read-only check

```bash
V7T_ALLOW_PIDS='43428 43972' bash '/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh' 24172 49732 status
```

What it should show:

- p1 at `next C1p (index 13)` with `end marker rc=none` and `idle part: no` (later stages as profile 1 goes on);
- p3 at `next C1p (index 13)` with `idle part: yes`;
- `p2: no log`;
- `p3 rerun request: none`;
- `old scripts outside V7T_ALLOW_PIDS ('43428 43972'):` 39928 32328 24172 47724 46828 50260 39124 24652 49732 before steps 2 and 3 (the forks may be gone), and an empty list after them;
- `allowed launcher subshells: alive; old scripts not yet renamed: v7_d86_launch.sh v7_d87_p3fix.sh v7_d87_redo.sh v7_d87_resume.ps1 v7_d83_launch.sh v7_fix_resume.sh v7_d87_b3m.sh v7_wait_c1p_then_fix.sh v7_guard_c1p_fail.sh`;
- `code_commit.txt: SRC 9b5c9f1…` (still intact);
- a `file` line for each control file present (for example `p3_c1p.hold` and `p2_c1p.hold` of d91_deploy.md 5.0), and `file <p>_hand.busy: …` with its content while a hand-run holds a worktree;
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

Check afterwards (PowerShell):

```powershell
Get-Process -Id 43428,43972,44984,42560 | Select-Object Id,ProcessName,StartTime
(Get-Date) - (Get-Item 'C:\Users\Adi Suliman\uav-gcs-logs\v7_d86\run.lock').LastWriteTime
Get-CimInstance Win32_Process -Filter "Name='bash.exe'" | Where-Object { $_.CommandLine -like '*v7_d8*' } | Select-Object ProcessId,ParentProcessId,CreationDate
```

- All four processes are still alive: the chain subshell, its child, the MATLAB stub and MATLAB.
- run.lock is under 30 s old. The chain subshell touches it every 10 s.
- p1.log keeps growing.
- The last query lists only 43428 and 43972. The wrappers 32328 and 39928 exit on their own. Any other listed PID still there after 1 min (32328, 39928, or the forks 47724, 46828, 50260 of 24172): end it with `taskkill /PID <pid> /F`, one by one, no `/T`. Never end a PID whose ParentProcessId is 43428 or 43972, and never 43428 or 43972 themselves.

### 4. Adi launches the takeover hidden, the same way as the launcher

Use PowerShell. Launching it the same way gives the same TEMP: a login bash sees `TEMP=/tmp`, which is `C:\Users\ADISUL~1\AppData\Local\Temp`. This was checked on 18.10.

```powershell
$si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ShowWindow=[uint16]0}
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='"C:\Program Files\Git\bin\bash.exe" -lc "V7T_ALLOW_PIDS=''43428 43972'' bash ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.sh'' 24172 49732 >> ''/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover.log'' 2>&1"'; CurrentDirectory='C:\Users\Adi Suliman\uav-gcs-logs'; ProcessStartupInformation=$si}
```

`ReturnValue` must be 0.

This is the one launch command for every later start too: after a crash, after stopping the takeover, and after a reboot. The PIDs and the allow-list can stay as they are: a PID that no longer runs its script does not block, and the allow-list stops matching by itself once profile 1's launcher chain is gone or the machine has rebooted.

### 5. Check after the launch (within 5 min)

- `v7_d91_takeover.log` shows these lines, in order:
  1. `code_commit.txt: SRC 9b5c9f1… retired (the launcher's resume refuses)`;
  2. nine lines `<name> renamed to <name>.retired_by_d91 (old run script); it cannot be run any more`, for `v7_d86_launch.sh`, `v7_d87_p3fix.sh`, `v7_d87_redo.sh`, `v7_d87_resume.ps1`, `v7_d83_launch.sh`, `v7_fix_resume.sh`, `v7_d87_b3m.sh`, `v7_wait_c1p_then_fix.sh` and `v7_guard_c1p_fail.sh`;
  3. `v7 takeover started (boot …, TEMP C:\Users\ADISUL~1\AppData\Local\Temp, poll 300 s, allowed launcher subshells: 43428 43972)`;
  4. one line each for p1 and p3: `next C1p (index 13)` (or later for p1);
  5. `p2: waits for profile 1's chain to end with rc=0`;
  6. `p3: C1p waits for p1's SURV3`.
- `v7_d86\code_commit.txt` starts with `SRC_RETIRED_BY_D91 9b5c9f1…`. `code_commit_before_d91_<time>.txt` holds the old line, and `retired_src.txt` names the SHA.
- `uav-gcs-logs` holds the nine `….retired_by_d91` files and none of the nine old names.
- Profile 1's chain runs on: 43428, 43972, 44984 and 42560 are alive, and p1.log keeps growing.
- `v7_d86\takeover_p1_chain_ml.txt` lists profile 1's chain MATLAB: `44984 <time>` and `42560 <time>` (log lines `p1: launcher-chain MATLAB … recorded`).
- `v7_d86\takeover.lock` holds the takeover's PID and is under 60 s old. `run.lock` is under 60 s old. `takeover_tracks.txt` lists p1, p3 and p2, and the four `takeover_beat_*` files (p1, p3, p2 and main) are under 60 s old.
- The status mode (step 1) still shows the same state, with `SRC_RETIRED_BY_D91` and an empty old-script list.
- There is no `v7_d86\ALERT_*.txt`.
- The log has no line `still runs`, `outside V7T_ALLOW_PIDS`, `could not be read` or `not started`.

## Stopping the takeover

End every bash that runs the takeover and has no MATLAB child, oldest first, all with `/F` and none with `/T` (PowerShell, one line):

```powershell
$all = @(Get-CimInstance Win32_Process); $mp = @($all | Where-Object { $_.Name -like 'matlab*' } | ForEach-Object { $_.ParentProcessId }); $all | Where-Object { $_.Name -eq 'bash.exe' -and $mp -notcontains $_.ProcessId -and $_.CommandLine -match '^"[^"]*\\bash\.exe"\s+(-lc\s+"(\w+=(''[^'']*''|\S*)\s+)*bash\s+)?[''"]/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_takeover\.sh[''"]' } | Sort-Object CreationDate | ForEach-Object { taskkill /PID $_.ProcessId /F }
```

It matches the wrapper, the main bash and its track subshells (MSYS forks keep the main bash's command line), and only a bash that runs the live script, not a command that mentions it. The oldest go first, so the main bash and the tracks end before any of their short-lived forks. It never ends a MATLAB, nor the bash stub that waits on one:

- A MATLAB the takeover started runs on: its launcher with the takeover's subshell stub as its parent, and the launcher's win64 child. Both PIDs are in `v7_d86\takeover_ml_<profile>.pid` (the launcher on the first line, `win64 <pid>` on the second). A restarted takeover waits until both are gone.
- Profile 1's launcher chain (43428, 43972) does not match and runs on.

Stopping the takeover stops only its bash processes, never a MATLAB. Leave its MATLAB to finish; the restarted takeover goes on after it. If a takeover MATLAB really must be stopped (it hangs), end its **win64** process, the PID on the file's `win64` line (or the `MATLAB.exe` whose ParentProcessId is the PID on the first line), with `taskkill /PID <pid> /F`, no `/T`. Its launcher and stub then exit by themselves. Never end only the launcher: its win64 child would run on without it. Either way the worktree stays held, and no new MATLAB starts there, until the launcher, the win64 process and every live `MATLAB.exe` child of them are gone. Leftover `MATLABWebUI.exe` or `MATLABWindow.exe` children of an exited MATLAB do not hold the worktree. They can be ended separately (they are not MATLAB), as for `turn_holder`, but the takeover does not wait for that.

Run the same query without the `ForEach-Object` part afterwards: it must list nothing. A stub left beside a running MATLAB is not listed, by design.

Ending only the PID in takeover.lock also stops the takeover: its tracks stop within 30 s with `ALERT_takeover_main_gone`. The one-liner is the cleaner way.

To start it again, use the launch command of step 4. It starts once its main bash is gone and the lock is 90 s old; before that it says `not started` and changes nothing. While the PID in the lock still runs the takeover, a start is always refused, also when that takeover hangs.

## Latest dates

The takeover must be running before profile 1's SURV3 finishes, because it then starts profile 3's C1p. That is at the earliest **22.10 about 13:00**; the estimate runs to 23.10 about 12:30.

It also covers profile 2. The old launcher would refuse profile 2 or misplace it at profile 1's chain end, at the earliest **23.10 about 10:00**.

A profile 3 rerun on the fusion revision needs the takeover running before the 21.10 go/no-go.

Launch it as soon as this review is done (18-19.10). It also covers a profile 1 crash, audit item (c), from the moment it starts. It also blocks the old resume after a reboot.

## Control files (in `uav-gcs-logs\v7_d86\`)

| File | Effect |
|---|---|
| `p1_resume.go` | After `ALERT_p1_failed_*` or `ALERT_p1_cut_*`, and after checking that no MATLAB of profile 1 still runs: profile 1 goes on from its first unfinished stage under a new part. A0 runs first if it stopped inside the B stages. `policy_pools.mat` is checked before C1p. A resume from C1p or C1c waits until profile 3's B-stage rerun has ended. The file must be newer than p1.log; it is renamed `.used_<time>`. |
| `p3_resume.go`, `p2_resume.go` | The same after `ALERT_p3_failed_*` or `ALERT_p2_failed_*`. Also after `ALERT_p3_open_*`, which means p3_fix died with a stage open; check first that no MATLAB runs in uav-gcs-v7-p3. |
| `p2_start.go` | Starts profile 2 before profile 1's chain has finished (e.g. after `p1.abandon`). It is renamed `.used_<time>`. |
| `p3_brerun.go` | The stages of profile 3's B-stage rerun, e.g. `B2F B3 B3a B4 B4s`. They must be stages of uav-gcs-v7-p3's run_stage.m, and no C stage. The test-set stages B3m, B3q and B3r are refused (`ALERT_p3_rerun_invalid_*`, naming d91_set4.md step 4). They run with A0 first, while profile 3 waits for SURV3, under the conditions above. Each version (content plus time) runs once; touching the file runs it again. The version that runs is exactly the one checked: the list is read and checked again, under the gate, right before the rerun's part header, and if the file has changed since, nothing runs and it is read again. It is ignored once profile 3's C1p has started. A failed rerun holds C1p back until the file is written again, or until `p3_rerun.accept`. |
| `p3_rerun.accept` | After `ALERT_p3_rerun_failed_*` or `ALERT_p3_rerun_blocked`: go on with profile 3's B stages as they are. It clears only the failed rerun; C1p still waits for profile 1's SURV3. It must be newer than p3.log; it is renamed `.used_<time>`, and p3.log gets a line `##### rerun accepted GO <id> …`. |
| `p3_c1p.hold`, `p2_c1p.hold` | Hold that profile before C1p. Example: until the 21.10 go/no-go on the fusion revision. The hold, `.abandon`, force and `p3_brerun.go` files are read again after the waits for the code and for free commit (which can take hours), right before C1p's part header. A file written during those waits therefore still counts: C1p goes back to its checks (log line `… changed during the waits before C1p …`). |
| `p3_c1p.force`, `p2_c1p.force` | Skip only the wait for the other profile's SURV3 (profile 1 for P3, profile 3 for P2). It counts only once that other profile is given up (`p1.abandon`, `p3.abandon`) **and its chain has stopped**: its takeover track has ended, no takeover MATLAB is recorded for it, and for profile 1 the launcher's chain is over too (its end marker, a reboot since, or its chain subshells gone with no MATLAB child), with no MATLAB of that chain left (`takeover_p1_chain_ml.txt`). `p2_c1p.force` also needs profile 1 past SURV3, finished, or given up with its chain stopped, since profile 2 otherwise waits on profile 1 through profile 3. Without `.abandon` the file is ignored with `ALERT_<g>_force_ignored_*`. While the chain still runs, it waits (log line `… force waits until profile <n>'s chain has stopped`). So two C1p never run at once. It does not clear a hold or a failed rerun. |
| `p2_set4.stages` | Extra profile 2 stages run after B3m: `B3q` (the fourth test set's build; it reads nothing). `B3r`, the set's single reading, is refused with `ALERT_p2_set4_invalid_*`. It runs by hand after the go/no-go and after profile 2's OOD, because OOD re-saves the detector (d91_set4.md step 7). The stages must be in v7-dev's run_stage.m when profile 2 branches. The file is read once, when profile 2's B stages first start. |
| `final.hold` | The final phase starts no MATLAB while it exists (see "Deploy controls"). Write it before a hand-run after the chains (d91_deploy.md E11) or for plan B (E'), and remove it after. |
| `p2_start.hold` | Profile 2 neither branches v7-p2 nor starts while it exists, even when profile 1 has finished or `p2_start.go` is present. Removed, v7-p2 branches from v7-dev's tip of that moment (plan B, E'). |
| `p1_cut_after.SURV3` | Ends profile 1's chain win64 MATLAB (taskkill /F, no /T) once its current part shows `##### STAGE SURV3 done`, at once if it already does; nothing before that marker, nothing else ever. Renamed `.used_<time>` once used, or once the part is already past SURV3. Plan A's stop (E2). |
| `p1_hand.busy`, `p3_hand.busy`, `p2_hand.busy` | Written and removed by `v7_d91_gated_run.sh`, never by hand while a wrapper runs. No takeover MATLAB starts in that worktree while it exists, or while the MATLAB it names lives. A wrapper ended by force leaves it: remove it once its win64 PID is gone. |
| `p1.abandon`, `p3.abandon`, `p2.abandon` | End that track at its next loop; a running MATLAB is not stopped. The final phase skips that profile. If profile 1 is given up, profile 3 also needs `p3_c1p.force` and profile 2 needs `p2_start.go`. If profile 3 is given up before its SURV3, profile 2 needs `p2_c1p.force`. **An `.abandon` file is final for the run.** Never remove it to bring the profile back. Once a profile is given up, the others may run C1p or C1c on a force file, and a profile brought back would not wait for them. (The takeover does not guard that case; this rule is the simpler correct choice.) A profile given up while its resume or rerun waited for code or free commit does not start it. |

**Alerts** go to `v7_d86\ALERT_<topic>.txt` and to the takeover log. Each alert file is created exclusively (no-clobber), so two tracks that see the same event at once raise it once. Delete each alert once it is handled. Every alert that names a force file says what it skips.

| Topic | Meaning and action |
|---|---|
| `p1_failed`, `p3_failed`, `p2_failed` | A chain ended with rc != 0. Find the cause; check that no MATLAB of that profile still runs; then write its `_resume.go` (or `.abandon`). |
| `p1_cut` | Profile 1's chain stopped without an end marker: a reboot, or its chain subshells are gone with no MATLAB child left. Check with `Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" \| Select-Object ProcessId,ParentProcessId,CommandLine` that no MATLAB of profile 1 still runs, then write `p1_resume.go`. |
| `p3_open` | p3's part has a stage open and its script is gone; see `p3_resume.go`. |
| `p1_silent` | p1.log has not changed for 6 h. Check that profile 1's MATLAB still runs and uses CPU. Alive and busy: nothing to do. Gone: `p1_cut` or `p1_failed` follows by itself. Hanging (alive, no CPU for hours): end its win64 process (42560 now; the `MATLAB.exe` child of the `bin\matlab.exe` launcher, listed in `takeover_p1_chain_ml.txt`) with `taskkill /PID <pid> /F` (no `/T`), never only the launcher. The launcher and the chain then end, with rc != 0, and `p1_failed` follows. |
| `p3_rerun_failed`, `p3_rerun_blocked` | The rerun failed, or the last one did not end well and the go file is gone. Write `p3_brerun.go` again, or `p3_rerun.accept`. |
| `p3_rerun_invalid`, `p3_go_ignored` | The go file names a stage that is not a B stage, or a test-set stage (B3m, B3q, B3r: the fourth set is read by hand in the order of d91_set4.md step 4), or came after C1p started. |
| `p3_force_ignored`, `p2_force_ignored` | A force file while the other profile is not given up; remove it, or give that profile up. |
| `unknown_<what>` | A log, a control file or a process query has not read as well formed for 1 h (`p1log`, `p3log`, `p2log`, `go3`, `rerun`, `set4`, `scan`, `ml_<g>`, `<g>final`). Nothing starts on it meanwhile. Check that file, free memory and the number of processes; the takeover goes on by itself once it reads. |
| `takeover_track_<g>_stalled_<beat>` | A track has not beaten for 20 min. If it does not beat again, stop the takeover and start it again. |
| `takeover_track_<g>_died` | A track ended without its end file; the final phase will be skipped. Stop the takeover and start it again; the restart resumes that profile. |
| `takeover_main_stalled_<beat>` | The main bash has not beaten for 20 min (`takeover_beat_main`): nothing watches the tracks, and the final phase would not run. If it does not beat again, stop the takeover and start it again with the step 4 command. |
| `log_missing_<g>` | p1.log or p3.log is missing. Nothing runs for that profile; it is never taken as a fresh one. Restore the log, or write `<g>.abandon`. |
| `takeover_lock_held_<time>` | A start found takeover.lock held by a takeover that still runs but has not refreshed the lock for 20 min. Check its log, stop it, and start it again. |
| `gate_<time>` | `takeover_gate.d` has been held for 1 h; its holder may have died inside it. Stop the takeover and start it again (the start clears it). |
| `p2_set4_invalid`, `p2_prep` | A problem with `p2_set4.stages`, or profile 2's worktree could not be prepared. |
| `p2_wait_p1_abandon` | Profile 1 is given up; profile 2 starts only on `p2_start.go`. |
| `p2_c1p_p3_abandon`, `p2_c1p_p3_failed` | Profile 3 failed before its SURV3, or was given up and its chain has stopped (the abandon alert comes only then). Profile 2's C1p then starts only on `p2_c1p.force`, once profile 3 is given up with its chain stopped and profile 1 is past SURV3, finished, or given up with its chain stopped; or after profile 3 resumes past SURV3. |
| `old_script_<pid>_<created>` | A bash outside the allow-list runs an old run script; no takeover MATLAB starts until it is gone. End it with `/F` once sure it is not one of profile 1's chain subshells. |
| `retire_<script>` | An old script could not be renamed; retried every 5 min. |
| `takeover_main_gone` | The takeover's main bash died; its tracks stopped. Start it again with the step 4 command. |
| `code_<g>` | A worktree is on the wrong branch, a merge is in progress, or code is uncommitted. |
| `headroom_<g>` | More than 1 h below the free-commit gate (45 GB, 65 GB for the rerun). |
| `ml_alive_<g>` | A takeover MATLAB still runs in that worktree: a PID in `takeover_ml_<g>.pid` (launcher or win64), or a live `MATLAB.exe` child of one. Nothing starts there, and a chain whose launcher has exited writes no end marker, until all are gone. Leftover `MATLABWebUI.exe` or `MATLABWindow.exe` children do not count. If it hangs, end its win64 PID (see Stopping the takeover). |
| `ml_alive_p1_chain` | A MATLAB of profile 1's launcher chain (`takeover_p1_chain_ml.txt`), or a live `MATLAB.exe` child of one, still runs although its chain has ended or its subshells are gone. The resume and profile 1's final phase wait for it. Leftover `MATLABWebUI.exe` or `MATLABWindow.exe` children do not count. If it hangs, end its win64 PID with `/F`, no `/T`. |
| `hand_busy_<g>_<mtime>` | A takeover start has waited 12 h for a hand-run in that worktree (the alert holds the file's content). If the hand-run has ended and its win64 PID is gone, remove `<g>_hand.busy`. |
| `final_hold_<mtime>` | `final.hold` has held the final phase for 24 h. Remove it when the hand-runs after the chains are done. |
| `p2_start_hold_<mtime>` | `p2_start.hold` has held profile 2 for 48 h. Remove it once v7-dev holds the code profile 2 should branch from. |
| `p1_cut_on_request_<stamp>` | `p1_cut_after.SURV3` ended profile 1's chain win64 MATLAB after SURV3. It names the stages from C1d on that were already done (C1d is then rerun; a later one as E2 says). Go on with d91_deploy.md E3; resume with `p1_resume.go`. |
| `p1_cut_pid_<stamp>` | SURV3 is done but no single win64 MATLAB of the chain passed the checks (alive, `\win64\MATLAB.exe`, recorded creation time), or taskkill failed; nothing was ended. Checked again every 5 min. Stop the chain by hand if needed (`taskkill /PID <win64 pid> /F`, no `/T`). |
| `p1_cut_past_<stamp>` | `p1_cut_after.SURV3` came when the current part was already past SURV3; nothing was ended, the file was renamed. |
| `p1_cut_invalid_<name>` | `p1_cut_after.<name>` with a stage other than SURV3; nothing is ended. Remove it. |
| `ml_pid_<g>` | A started MATLAB did not show its Windows PID within 60 s. The subshell's PID was recorded instead; it is replaced once MATLAB shows. |
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

B3m, B3q and B3r are refused in the go file (`ALERT_p3_rerun_invalid_*`, naming d91_set4.md step 4): B3m rebuilds the third test set, B3q builds the fourth, and B3r, its single reading, runs by hand after the go/no-go in the order of d91_set4.md step 4 (docs/d91_set4.md on d91-set4). That decision belongs to the other track.

- To decide on 21.10 without a race against SURV3, write `p3_c1p.hold` first. Remove it once the go file or the no-go decision is in place.
- The rerun waits until profile 1 is past C1c and 65 GB of commit is free. On the overnight audit's estimate, profile 1's C1c ends between 22.10 09:00 and 23.10 02:00, and SURV plus SURV3 then take 6-10 h. That is the rerun's window before profile 1's SURV3. If the rerun runs longer, profile 3's C1p starts when the rerun ends. Write the go file before profile 1's C1c ends so the rerun starts at once.
- If the rerun fails and the B stages should stay as they are, write `p3_rerun.accept`, not `p3_c1p.force`.
- The rerun's code commit and its request id go to code_commit.txt.

**Profile 2.** It uses whatever v7-dev holds when profile 1's chain ends. Its commit goes to code_commit.txt. To build profile 2's fourth test set inside its own chain, write `p2_set4.stages` holding `B3q` before then. The single reading B3r is never listed there, and the takeover refuses it: it runs by hand after the go/no-go and after profile 2's OOD (d91_set4.md step 7).

## Adi's steps for the deploy controls

Paths: `R = C:\Users\Adi Suliman\uav-gcs-logs\v7_d86`. Each control file is an empty file; the status mode (step 1) lists it.

1. **Hand-runs.** Only through the wrapper (d91_deploy.md 5.0): `bash "$L/v7_d91_gated_run.sh" <need_gb> <worktree> <logfile> "<command>"`. It registers `R\<p>_hand.busy`, waits 30 s, then waits for the takeover's MATLAB there; the takeover waits for it in turn. Never write or remove that file by hand while a wrapper runs. After a wrapper was ended by force: check that its win64 PID (the `win64` line of the file) is gone, then remove the file.
2. **Plan A, the stop at SURV3 (E2).** Before profile 1's SURV3 ends, write `R\p1_cut_after.SURV3`. Check the takeover log for no `p1_cut_invalid` alert. When SURV3 is done, `ALERT_p1_cut_on_request_*` appears, then `ALERT_p1_failed_*`; the alert names the stages from C1d on that were already done (E2's rule after the stop). Go on with E3 to E9; resume with `R\p1_resume.go` (E10). If `ALERT_p1_cut_pid_*` appears instead, nothing was ended: stop the chain by hand as in E2 (its win64 PID in `takeover_p1_chain_ml.txt`, role `win64`).
3. **A hand-run after the chains (E11).** Write `R\final.hold` before it and remove it after; the final phase then goes on.
4. **Plan B (E').** Before profile 1's chain ends, write `R\final.hold` and `R\p2_start.hold`. Remove `p2_start.hold` once the merge is on v7-dev (E' step 3), and `final.hold` after E' step 5.

## After a reboot or a crash

Recovery goes only through the takeover, with the launch command of step 4, unchanged. Never run an old run script (all are renamed `.retired_by_d91`; the launcher's resume also refuses on the retired SRC line).

1. Run the step 4 command. The PIDs and the allow-list can stay: a PID that no longer runs its script does not block, and the allow-list no longer matches anything after a reboot.
2. Profile 3's and profile 2's own parts go on from their first unfinished stage. A0 runs first inside the B stages. An unreadable `policy_pools.mat` is moved aside before C1p, and C1p keeps its per-cell checkpoints.
3. A part whose stages were all done before the interruption only gets its end marker.
4. Profile 1's part, cut by the reboot, raises `ALERT_p1_cut_*`. Check p1.log, then write `p1_resume.go`.
5. A profile 3 rerun cut by the reboot runs its remaining stages again when its conditions hold.

A crash without a reboot is handled like this:

- A takeover whose main bash still lives refuses a second start, however old its lock. If only the main bash died, its tracks stop within 30 s (`ALERT_takeover_main_gone`), and the step 4 command starts a new takeover once the lock is 90 s old.
- If a track died (`ALERT_takeover_track_<g>_died`), stop the takeover with the one-liner and start it again; the restart resumes that profile from its log.
- If the takeover's own MATLAB outlived its bash, the new takeover waits for it (`ALERT_ml_alive_*`) before starting another in that worktree. This also holds when the recorded PID is still the subshell that had not yet exec'd MATLAB, when the bash died between the fork and the exec, and when only the launcher was ended while its win64 process runs on.
- If profile 1's launcher was ended alone while its win64 MATLAB runs on, the chain writes `chain ended rc=…`, but the resume, the rerun and a force file wait for that MATLAB (`takeover_p1_chain_ml.txt`, `ALERT_ml_alive_p1_chain`).

## Tests

```bash
bash ops/d91_takeover_test.sh [sandbox] [scenario ...]
```

The default sandbox is `…\scratchpad\d91_takeover_test\`. The default scenarios are `rename status normal p1crash rerun rerunver accept rerungate reboot oldlaunch p1gone p1wait p1orphan orphan mainkill slowexec win64 webui mlquery zombie turn unknown unread nolog mlstub watchdog mainstall overwrite forcegate c1phold p2gate refuse finalhold p2hold p1cut hand handrace mllow`.

**How it runs.**

- It copies p1.log, p3.log, code_commit.txt and v7_d86_launch.sh (or its `.retired_by_d91` name) once from the live logs, as the starting state: profile 1 inside C1p, profile 3 idle after the fix script. The launcher's copy is named `old_launcher_copy.sh`, so no process scan takes it for the launcher.
- It builds a git repository with v7-dev and v7-p3 worktrees and a bare origin, and puts stand-ins of the nine old run scripts in the sandbox's logs folder.
- It replaces MATLAB with `ops/d91_stub_matlab.sh`. The stub prints run_stage's markers, can fail or slow a stage, logs concurrent calls and MATLAB options, and records each start. On a control file it runs as the two processes of a real MATLAB: a launcher, and a `--win64` child that does the work and that the stub queries report as a live win64 MATLAB whose ParentProcessId outlives the launcher.
- It replaces the PowerShell queries with `ops/d91_stub_sys.sh`, which includes the old-script scan, process creation times, MATLAB children, a lagging exec, the sandbox's own processes by Windows PID, and failing or hanging queries. The stub runs under the same query timeout as PowerShell.
- Every `V7T_*` variable points into the sandbox. The launcher's copy runs with every `V7L_*` variable in the sandbox and its PowerShell calls replaced by a function. The harness refuses a sandbox path inside a live folder.

**What the scenarios cover.**

- `rename`: a bash whose script file is renamed while it runs reads the script's later lines; a chain function forked in the background, whose main bash was ended with `taskkill /F` before the rename, runs its forks to the end and writes its end marker.
- Normal flow:
  - p3's C1p starts only after profile 1's SURV3;
  - p2 is created, pushed, given the set-4 build (B3q), and starts after profile 1's chain ends;
  - p2's C1p starts after p3's SURV3;
  - every final phase runs;
  - code_commit.txt changes only in its retired SRC line plus the takeover's notes, with its backup and the retired SHA kept;
  - all nine old run scripts are renamed at the start, each logged before `v7 takeover started`;
  - every track writes its end file, and the track PIDs are recorded.
- A profile 1 crash before SURV3: alert; p3 and p2 held; an old go file is refused; a fresh one resumes from C1c; a set-4 stage that is not in run_stage.m, and then B3r, are refused.
- The rerun go file: an invalid list, each of the test-set stages B3m, B3q and B3r (stages of run_stage.m, refused with an alert naming d91_set4.md step 4), a failed rerun that holds C1p back, a new version that reruns, and a go file written after C1p has started.
- `accept`: a rerun fails while profile 1 is in SURV; the alert names `p3_rerun.accept` and says C1p still waits; `p3_c1p.force` without `p1.abandon` is ignored with an alert; the accept file is taken and logged in p3.log; C1p still starts only after profile 1's SURV3.
- The rerun gate:
  - no rerun while profile 1's C1p is open, or after C1p before C1c is done;
  - after C1c, it waits for 65 GB (50 GB free passes the chains' 45 GB gate but not this one);
  - it then runs, alone with `-singleCompThread`;
  - `p1.abandon` while profile 1's launcher chain is between C1p and C1c: no rerun until that chain has ended.
- Two reboots: one during the wait (profile 1 cut, resumed on its go file) and one inside p3's C1p (a second C part, unreadable pools moved aside). Also a second takeover refused while the first lives.
- The old launcher:
  - a control: with SRC intact, the launcher's copy passes its resume check;
  - the takeover starts beside the allowed subshells and retires SRC;
  - an old launcher under a new PID raises an alert;
  - after a reboot, the launcher's resume refuses with exit 1 and writes no part;
  - an allowed PID reused after the reboot is refused;
  - the takeover restarts, with run.lock back and one backup.
- `p1gone`: profile 1's chain subshells alive: no alert, and every old run script renamed at the start, the launcher too; subshells gone but a MATLAB child still listed: no alert and no rerun; no child left: `p1_cut` (asking to check for a MATLAB first); the go file resumes from C1p; the pending rerun runs only after the resumed C1c.
- `p1wait`: profile 1 fails at C1c, the rerun starts, `p1_resume.go` comes during the rerun: the resume waits, and profile 1's C1c starts after the rerun's last stage.
- The takeover's bash processes killed while its MATLAB runs on (`orphan`): no second MATLAB in that worktree.
- `mainkill`: only the main bash ended (SIGTERM, so its EXIT trap runs): takeover.lock is kept while its tracks live; `ALERT_takeover_main_gone`, every track stops, the MATLAB runs on with its PID file; a restart is accepted once the lock is 3 heartbeats old and waits for that MATLAB; C1p runs once.
- A lagging exec:
  - the PID file is written at the fork with the subshell's PIDs;
  - at 3 s, it is then rewritten with MATLAB's PID, with no alert;
  - beyond the wait, there is an alert and the subshell's PIDs stay;
  - after the takeover is killed and restarted, that PID counts as alive and no second MATLAB starts;
  - the takeover killed inside the exec window: the restart waits for that MATLAB; C1p runs once;
  - an exec that shows only after the wait: the alert, then the PID file names MATLAB once it shows;
  - in the harness the stub MATLAB is an MSYS script, so its exec replaces the subshell's Windows process; a restart that comes before the PID file names MATLAB finds it through the `msys` line.
- Idle: the zombie, exited sessions, smoke runs and the copies' exact commands are not counted. Profile 2's own chain, which names B3m, B3q and B3r, holds LAT back, and so do CPU, a live session and a failed MATLAB query. Also a chain that stopped after RPT before its end marker.
- A turn holder that exited (alert; turn file untouched) and one that is gone; a silent p1.log; a p3 stage left open, resumed on its go file.
- `unknown`: a hanging command-line query is ended after the query timeout (5 times, each process ended) and the start is refused; a failed process scan or a failed command-line query of 24172 refuses the start (no lock, SRC and scripts untouched); a recorded MATLAB whose query fails holds the worktree, then counts as alive once readable; a failed scan while running holds MATLAB starts.
- `unread`: a part header without FROM in p3.log, then in p1.log after its chain has ended: each is logged as unread and alerted after the (test) hour; no MATLAB starts, no part header is written, no p1 alert, profile 2 does not start; once p1.log reads again, profile 2 runs its B stages while p3 and p2's C1p still wait; once p3.log reads again, the run finishes in order.
- `nolog`: p3.log missing: logged at the start, `ALERT_log_missing_p3`, nothing runs for profile 3 and no p3.log is written (no rebuild from A0), the status mode reads it as unknown; once the log is back, profile 3 goes on at C1p.
- `mlstub`: a PID file with an `msys` line whose stub is gone (`none`) while a MATLAB child lives: alive, nothing starts; once no child is left: gone, the file is removed. The same for a PID file with the launcher alone, gone, while a live MATLAB child of it runs; and for a `win64` line whose process lives while the launcher is gone (gone once it has exited, even while its process object lingers). Last, as the zombie 32824: a `win64` line whose process has exited, with live `MATLABWebUI.exe`, `MATLABWindow.exe` and `MathWorksServiceHost.exe` children and one live `MATLAB.exe` pool worker: alive; once the worker has exited, gone (the helpers live on), and p3's next MATLAB (C1p) starts.
- `webui`: every win64 MATLAB leaves, as it exits, a lingering process object with live `MATLABWebUI.exe`, `MATLABWindow.exe` and `MathWorksServiceHost.exe` children. No `ml_alive` alert, p3's C1p part gets its end marker, no PID file is left, and the run ends with every final part. Then (`mlquit`) profile 3's launcher exits after 3 s while its exec still shows as the subshell (6 s), so its PID was never taken: the PID file names the launcher's last Windows PID and its `win64` child, the takeover holds the worktree (alert, no end marker) while the child runs, and the end marker comes once the child has finished.
- `mlquery` (the script's functions, sourced, with the real PowerShell queries): two copies of `sleep.exe` in the sandbox, named `bin\win64\MATLABWebUI.exe` and `MATLABWindow.exe`, run as live children. The children query of each parent gives `none`, the state query gives `other` (not a live win64 MATLAB), the command-line check does not take them for MATLAB, and a PID file naming the parent with `win64 <MATLABWebUI.exe>`, the MATLABWebUI.exe PID alone, or the parent alone reads as gone. No process named `MATLAB.exe` is created, so the live machine's MATLAB lists are never touched.
- `win64`: every MATLAB runs as launcher plus win64 child. The PID file names the launcher, then `win64 <pid>`. The launcher of profile 3's C1p is ended alone: the child runs on, the takeover holds the worktree (alert, PID file kept, no end marker). The takeover is killed and restarted: it waits for the child (its launcher's PID gone); C1p runs once; the end marker comes after the child; the run ends with every final part.
- `p1orphan`: profile 1's chain as in the live tree (43428, 43972, launcher 44984, win64 42560). Both MATLAB processes are recorded with their creation times. The launcher is ended alone, and the chain writes rc=1 while 42560 runs on. The pending rerun does not start, and `p1_resume.go` waits with `ALERT_ml_alive_p1_chain`. Once 42560 has exited, both start, while its lingering process object keeps live `MATLABWebUI.exe` and `MATLABWindow.exe` children. With `p1.abandon` and `p3_c1p.force` instead, profile 3's C1p waits for 42560 too, and starts once it has exited, with the same helpers left.
- `c1phold`: profile 3 past profile 1's SURV3 waits for free commit before C1p. A hold and a go file written during that wait send it back to the C1p checks: the rerun runs first, and C1p starts only after the hold is removed.
- `rerunver` (the script's functions, sourced): `go_state` gives the version it checked (`pending <id> <list>`). The file rewritten to `B4s C1p` after the check is refused before the part header, with no MATLAB. An unchanged version runs exactly its checked list.
- `watchdog`: a track stopped (SIGSTOP) raises `takeover_track_p3_stalled`; a track killed alone raises `takeover_track_p2_died`; the other tracks finish, the final phase is skipped, no `v7 done`, and the lock is removed once no track lives; a restart resumes profile 2 and runs the final phase for all three.
- `mainstall`: the main bash beats; stopped alone (SIGSTOP), its beat stays, and the tracks raise `takeover_main_stalled_<beat>` for that beat, naming how to stop and restart, once (one log line) while they beat on; after SIGCONT the run ends with every final part.
- `overwrite`: the running script file overwritten in place (`cp`) by a longer file whose every line would leave a marker: no line of it runs, and the run ends with every final part and `v7 done`.
- `forcegate`: profile 3 given up while its C1p runs, with `p2_c1p.force` written at once: no `p2_c1p_p3_abandon` alert and no second C1p while profile 3's MATLAB runs; profile 2's C1p starts only after it has ended. Profile 1 given up while its launcher chain runs C1p, with `p3_c1p.force`: profile 3's C1p starts only after that chain has ended.
- `finalhold` (T1): (a) `final.hold` present when the tracks end: one log line, no LAT and no final part, the status mode lists it; removed: LAT starts after the removal and every final part runs. (b) Written during the idle wait (CPU 50 %): no LAT; removed: the idle wait runs again, then LAT, its machine line after the removal. (c) Written while profile 1's final RPT runs: profile 1's bundle waits and profile 3's final part does not begin; removed, profile 1's bundle runs, while a hand-run file in p3 holds profile 3's final part (T3) until it is removed. `watchdog` (d): with `final.hold` present and a died track, the final phase is skipped as before, with no hold wait.
- `p2hold` (T4): (a, c) profile 1 complete, `p2_start.hold` and `p2_start.go` present: no branch, no p2.log, the go file left in place, one log line, the alert after the (test) 48 h; (b) a commit on v7-dev, then the hold removed: v7-p2 branched from that tip, its line in code_commit.txt, the run ends with profile 2's final part; (d) `p2.abandon` while held ends the track, and the run ends without profile 2.
- `p1cut` (T2), with profile 1's launcher chain as sandbox processes (a bash running a stand-in `v7_d86_launch.sh` as its allowed subshell, one stub MATLAB as launcher and win64 child) and a stub taskkill that logs its arguments and ends only sandbox processes:
  - the chain's MATLAB recorded with its roles; (a) the file written while SURV3 runs: nothing ended; SURV3 done: exactly one taskkill, after the marker, `/PID <win64> /F`, the launcher never named; the cut line in p1.log, the file renamed, the alert saying no stage from C1d on had finished; (e) the chain ends rc != 0, `p1_failed`, nothing resumes until `p1_resume.go`, which resumes from C1d; the file written again in that part (begun at C1d): `p1_cut_past`, nothing ended, renamed;
  - the chain inside C2: (d) `p1_cut_after.C1d`: alert, nothing ended; (c) a recorded creation time that differs: `p1_cut_pid` naming it, nothing ended, the chain runs; (b) the record right again: the cut at once, the alert naming C1d as already done;
  - (f) a takeover part: the file written while profile 1 has failed before SURV3 stays armed with no alert; the resumed part is cut at its SURV3 marker, the taskkill naming the `win64` line of `takeover_ml_p1.pid` (with its `win64_created` line), its chain ends rc != 0 with a second `p1_failed`, and nothing resumes.
- `hand` (T3, files written by hand): (a) `p3_hand.busy` present while the rerun would start: one log line with its command, no rerun, the alert after the (test) 12 h with the file's content, (d) the status mode lists it; its `win64` PID is recorded with its creation time and the file is never changed; removed while that MATLAB lives: still no rerun; (c) that MATLAB gone: the rerun starts and the record goes. Then C1p after profile 1's SURV3 waits for a new file and starts once it is removed. (b) A file written while profile 3 waits for free commit before C1p: no C1p, then C1p once removed. A resume of profile 1 on `p1_resume.go` waits for `p1_hand.busy`: no part header, no MATLAB, then the resume once removed.
- `handrace` (T3 with the wrapper of `ops/`, a stub gate, the stub MATLAB, which appends its `win64` line as the real preamble does, and a stand-in of the state script that applies its rules on the stub queries, since a stub MATLAB is no `MATLAB.exe`): a hand-run registers, settles and starts while profile 3 waits for SURV3; after SURV3 profile 3's C1p waits for it; the wrapper ends rc 0 and removes its file, and C1p starts after it. A second hand-run while the takeover's C1p runs registers and waits (`worktree busy`), and its MATLAB starts only after the takeover's chain MATLAB has ended. No two MATLAB in one worktree, and the run ends with every final part. Then the claim, with the script's functions sourced and the real `v7_d91_gated_state.ps1` (read-only): a busy file present at the check removes the claim and holds the start; without one the claim stays (`claim <pid>`), the real state script reads that live takeover bash as `BUSY … a takeover bash about to start MATLAB`, and once the claimer is gone as `FREE`. A track's claim, made in a forked subshell as `start_track` forks (its Windows process keeps the takeover's command line), reads as busy too, while a live bash that is no takeover and has no MATLAB child reads as free (negative control). End to end, the wrapper with the real state script and no settle time, registered while such a claim lives, waits (`worktree busy: … a takeover bash about to start MATLAB`) and starts no MATLAB; once the claimer is gone (its claim left behind, stale) its MATLAB starts and it ends rc 0. With a state stand-in that logs its calls, the wrapper's first state read comes only after `D91_SETTLE`.
- `mllow` (the round-6 lows, functions sourced): a first PID whose command line runs MATLAB but whose process has exited reads as gone, and alive while live; a launcher lost before its PID was taken: the win64 found below its exited launcher (`mlkids`), with its creation time, alive while live and gone once exited. `mlquery` also checks that `mlkids` of the helpers' parents gives `none`.
- Profile 2's start:
  - after `p1.abandon`, an alert names `p2_start.go`, and p2 waits for it;
  - profile 3 failing before SURV3 raises an alert naming `p2_c1p.force` and what it skips; that file is ignored while profile 3 is not given up;
  - profile 3 given up (its chain already stopped): an alert naming the force file and what it still waits for, and p2's C1p starts on the force file.
- The refusals:
  - TEMP elsewhere, launcher alive, fix script alive, a PID reused, a PID missing;
  - a boot time that is empty, non-numeric or in the future;
  - a launcher wrapper outside the allow-list, an allowed PID created long after its part, a fix script under another PID;
  - bash commands that only mention the scripts (a grep, `: v7_d86_launch.sh`, a cat) are not counted, and neither is a launcher fork that only one scan lists;
  - two starts at the same moment: exactly one runs;
  - none of the refusals leaves a lock or changes code_commit.txt.

**Result, 19.10 (round 6).** 385 of 385 checks passed in the full run on the committed files, 12:37-14:48 (log `scratchpad\r13_full.log`). An md5 check confirmed that the tested script, harness and stubs are the committed ones. It ran alone and started no MATLAB.

This round changed three things:

- The children query and every MATLAB check now count only processes named `MATLAB.exe`, and a live win64 MATLAB only by its `\win64\MATLAB.exe` path. Before, a lingering `MATLABWebUI.exe` child of an exited win64 process kept a worktree, or profile 1's chain, held for good.
- A launcher that exits before its PID was taken is followed by its last Windows PID.
- Profile 1's chain record is taken again right before each check whether the chain has stopped.

New tests cover these: `webui`, `mlquit`, `mlquery`, the fourth `mlstub` case, and helpers left at the end of `p1orphan`. As a control, `mlquery` and `mlquit` were run against the round-5 script (55335d7). Nine checks failed there, as intended (eight below, and one sandbox process still running at the kill):

- the parents' children query listed the two helpers;
- the state query called them live win64 MATLAB;
- all three PID files read as alive;
- the PID file was not kept for the launcher that exited early, so no end marker was held back.

The stub-based `webui`, `mlstub4` and `p1orphan` cases model the query's answer, so they pass on both scripts.

Read-only queries on the live tree with the new queries gave these results:

- the children query gives `none` for the exited zombie 32824, though its two `MATLABWebUI.exe` children still live;
- it gives 44984 for 43972, 42560 for 44984, and the six `MATLAB.exe` pool workers for 42560;
- the state query gives `live` for 42560, `other` for the launcher 44984 and for `MATLABWebUI.exe` 11980, and `exited` for 32824;
- the command-line check takes 44984 and 42560 for MATLAB, but not 11980.

**Result, 19.10 (round 5).** 361 of 361 checks passed in the full run on the committed files, 08:21-10:05 (log `scratchpad\r10_full.log`; an md5 check confirmed the tested script, harness and stubs are the committed ones). It ran alone beside the live profile 1 C1p and the side jobs and started no MATLAB. Earlier full runs of this round found three things, all fixed before this run:

- extra load from the new queries: checking for the win64 child every second, recording profile 1's chain at every pass, and the stub's per-process `cat` made the slow scenarios miss their waits. The check is now every 5 s, the recording every 6 polls, and the stub reads with a builtin;
- `takeover_main_stalled` raised twice in one second by two processes. Alerts are now created exclusively;
- a stall alert on a beat read while it was being written (`…_stalled_1`); a beat below the boot time is now ignored.

`win64`, `forcegate` and `unknown` were also made condition-based (a stub hold file instead of a fixed stage time; the new log wording).

As a control, the new scenarios were run against the round-4 script (585eec5). `rerunver`, `mlstub2`, `mlstub3`, `win64`, `p1orphan` (both parts) and `c1phold` failed there: no `win64` line, a launcher gone counted as gone, no chain record, a resume or rerun beside profile 1's win64 MATLAB, C1p started over a hold written during the wait. The read-only status mode on the live logs (real PowerShell, 20 s) reads as before: p1 and p3 at `next C1p (index 13)`, nine old scripts not yet renamed, SRC intact, 42560 holding the turn. Read-only process queries on the live tree confirmed the new queries: the live-children query gives 44984 for 43972 and 42560 for 44984, and `none` for the parent of the exited zombie 32824. With the chain functions sourced against a scratch folder, the record holds 44984 and 42560 with their creation times, and both read as alive.

**Result, 18.10 (round 4).** 320 of 320 checks passed in the full run on the committed files, 20:54-22:27 (log `scratchpad\r6_full.log`; an md5 check confirmed the tested script, harness and stubs are the committed ones). It ran beside the live profile 1 C1p and the side jobs and started no MATLAB. A first full run of this round found one real gap, now fixed: an invalid-file alert was keyed on the file's time only, so after a rewrite read between the list and the time, the next stage's alert was taken as already raised (the topics now carry the stage too). As a control, the new scenarios and cases were also run against the round-3 script (7d4d0b6): `overwrite` (the old main bash ran the new file's lines and lost the final phase), `mainstall`, `nolog`, the test-set stages in `rerun` and the `p1.abandon` case of `rerungate` all failed there. The status mode on the live logs (read-only, 45 s) reads p1 and p3 at `next C1p (index 13)` as before, and lists the nine old scripts as not yet renamed.

**Result, 18.10 (round 3).** 287 of 287 checks passed in the final full run on the committed files, 17:30-19:18 (log `scratchpad\r4_full3.log`; an md5 check confirmed the tested files are the committed ones). It ran beside the live profile 1 C1p and the two side MATLAB jobs and started no MATLAB. The full run before it (13:35-17:20) passed 285 of 287: its two failures were harness checks in `reboot` (a direct second start cut by a 30 s `timeout` before its start-up, which takes 30-40 s on the loaded machine, reached the lock check; and a `tail -5` that no longer held the start line). Both checks were fixed, and `reboot` and `oldlaunch` passed (25 of 25) before the final run. A first full run of this round showed one real gap: a restart that came before the PID file named MATLAB checked the subshell's old Windows PID only. That is fixed by the `msys`-line resolution in `ml_state` and the rewrite at the PID alert; the other failures of that run were harness waits on the loaded machine, now condition-based, with every `until_t` deadline scaled by `SLOW_X` (3).

Read-only checks on the live machine (18.10):

- the status mode with `V7T_ALLOW_PIDS='43428 43972'` (19:20, real PowerShell queries under the 120 s timeout, 26 s in all) reads p1 and p3 at `next C1p (index 13)`, `end marker rc=none`, p1's part not idle and p3's idle, old scripts outside the allow-list 39928 32328 24172 39124 24652 49732 47724 46828 50260, `allowed launcher subshells: alive`, all six old run scripts not yet renamed, SRC intact, the parallel turn held by 42560 (live), and 42560 as the only live pipeline MATLAB;
- the log parsers on copies of the live p1.log and p3.log give the same indices; with a header without FROM, or with the log replaced by a directory, every value reads as unknown (no index 0, not past SURV3, not finished, profile 1 counted as in C1p/C1c, part not idle);
- a PowerShell query killed by the timeout leaves no PowerShell process (`taskkill /T` on its Windows PID), while plain `timeout` (also with `-s KILL`) left the native PowerShell running;
- the real queries answer `none` for a missing process, 43972's MATLAB child is 44984, and the scan and MATLAB lists end with `end`;
- the old-script pattern counts every live launcher and fix-script bash as running its script; of 16 test command lines, it counts the 9 that run a script and none of the 7 that only mention a name or run another file;
- the stop one-liner, in listing mode, lists nothing now; its pattern matches the takeover's wrapper (both forms) and its main bash, not the launcher nor an agent's grep; a bash with a MATLAB child (such as 43972) is left out.

**Heartbeat.** In one earlier run on the loaded machine, the 1 s test heartbeat once stalled for 11 s. With the 30 s period, the live gap therefore stays well under 60 s.
