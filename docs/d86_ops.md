# D86 ops: the parallel turn, the latency's machine load, the console bundle and scenarios, the 3D engine, runtimes and citations (branch d86-ops)

Branch `d86-ops` from v7-merge `a5f0687` (D81-D85 and the cues C1/C2). Pre-launch review, synthesis items 17, 23 (code part), 24 (code part), 25, 26, 27, 28 and the remaining Richards citations; finding ids ops-7, ops-11, ops-9, integration-3, integration-4, integration-6, ops-13 (with the ops-5 and ops-6 figures it asks for). Where a verifier gave a corrected fix, that fix was applied. This note is the merge input. DECISIONS.md received only what the review asked for there: a dated note on the disk floor (D61), a dated cost entry after D74's cost lines, the citations (D59, D61) and one clause in D85's library audit. No old entry was rewritten.

No stage of the evaluated chain changes its numbers: items 1-3 change operations and reporting, items 4-6 the operator console and the 3D view only, items 7-8 documentation.

## 1. The parallel turn cannot be held by a stale file (item 17, ops-7)

Code: `code/parallel_turn.m`.

**Why.** A turn file stays in %TEMP% after a crash or a power loss (one from 2026-10-07, PID 15316, had already survived a restart). The owner check was `tasklist /FI "PID eq n"` without an image filter, so any process that reused the PID after a restart held the turn (about 3% per restart at the PIDs seen on this machine), and `take` printed its message once and waited without a limit: C1p could stall unattended.

**What.**
- The owner counts only as a running process of the MATLAB image: `tasklist /FI "PID eq n" /FI "IMAGENAME eq MATLAB.exe"`.
- A turn file written before the computer's last start (`Win32_OperatingSystem.LastBootUpTime`, read once per `take`) is stale and taken over.
- While a session waits it prints the holder at once and again every hour ("Still waiting for the parallel turn after n h ...").
- `owner = parallel_turn('owner')` returns the live holder ([] when free); an optional second argument names the turn file (the test uses its own file and never touches the live one). The five callers are unchanged.

**Limits.** The image filter also matches the `bin\matlab.exe` launcher stubs (verifier); a PID reused by another MATLAB within the same boot still counts until that MATLAB ends. The hourly message makes such a wait visible in the log. The verifier's optional start-time check was not added.

**Test.** `test_parallel_turn_owner`: this session's fresh turn is held; the same file dated before the last start is free; PID 4 (the System process) is free; `take` takes the stale turn, `give` removes the file; the hourly message and the image filter are in the source.

## 2. The machine's load beside KPI 7 (item 23, code part; ops-11)

Code: `code/evaluation/measure_latency.m`; one line in `code/evaluation/measure_all_kpis.m` (outside this group's files, see the end).

**Why.** LAT is meant to time the decision cycle on an idle machine, but nothing checked or recorded it, and other MATLAB sessions are usually running. D84 B7 already logs the load for the unknown-threat candidates' timings (`machine_load.m`, `ood_latency.m`); LAT did not.

**What.** `machine_load()` is read right before the timed passes and right after them. LAT keeps `LAT.load` (before, after) and `LAT.load_text`, which says: CPU load before / after, other MATLAB processes before / after; a concurrent load only slows the cycle, so a pass under load holds on an idle machine and a fail under load is measured again on an idle machine (`run_stage('LAT')`). The text is the last line of `results/latency.txt` and is printed under KPI 7 in the KPI summary. LAT's other fields, its identity (det_id, policy_stamp) and the KPI 7 rule are unchanged; a latency.mat without the field still reads.

**Not here.** The launcher's bounded wait for zero win64 MATLAB sessions before LAT (the verifier's 10-min poll, 12-h limit) belongs to the launcher.

**Test.** `test_latency_load_logged`: the two readings bracket the timed loop, LAT stores them, latency.txt and the KPI summary print them.

## 3. No stale file survives in a console bundle (item 24, code part; ops-9)

Code: `code/gui/export_gui_bundle.m`.

**Why.** The export copied into an existing `profiles/rx<n>` and skipped optional files that were stale or missing, so an older copy stayed. `profiles/rx3` still holds the 2026-10-01/03 smoke bundle (a 145 MB smoke detector, smoke latency, KPI summary and policy evaluation); a failed LAT or KPI would have left smoke numbers in the full-run console.

**What.** An optional file that is not exported, stale by `result_status.m` (or a KPI summary older than what it reads) or not produced, is deleted from the bundle; the messages say "none in the bundle". An optional second argument `root` names the checkout to export from (default this one), and the working folder is restored on error.

**Not here.** Archiving `profiles/` with data/ and results/ at launch, and exporting only after LAT and KPI succeed, belong to the launcher.

**Test.** `test_gui_bundle_drops_stale`: a stale latency (no identity), a KPI summary older than it, and a missing policy evaluation and survivability map all leave no copy in a bundle that held older ones; a current file replaces the older copy.

## 4. The console's episode pools carry every antenna's gain (item 25, integration-3)

Code: `code/gui/demo_gui.m` (`epBuildPool`, `epPools`, `runEpisode`).

**Why.** The episode pools stored no `gain_ant`, so `obs.gant` was never set: the fusion's gain columns took fixed values (a one-antenna window) and the cause latch never ran. The episode panel showed another classifier and DQN state than the evaluated ones.

**What.**
- `epBuildPool` stores `F.gant` per frame, as `pool_cell.m` does, so every cycle passes `fr.gant`.
- Cached pools without `gant` are dropped from the session's cache and rebuilt.
- When the fusion is set and a pool has no gains, a warning (`demoGui:noGant`) and a log line say that the fusion and the latch do not run as evaluated.
- The pools also keep their flights' seeds (the 3D record takes the flight's seed from the pool) and the event frame (item 5).

**Test.** In `test_console_shadowing_rolls_in` (source checks: the gains stored, stale caches dropped).

## 5. Airframe shadowing in the console rolls in, as on the evaluated flights (item 26, integration-4)

Code: `code/gui/console_scenario.m`, `code/gui/console_flights.m` (new), `code/gui/demo_gui.m` (`runOneRun`, `applyMitigation`, `simRun` (new), `epPools`, `epBuildPool`, `runEpisode`).

**Why.** The console flew shadowing at a held bank (the fit's roll for the level) with the full depth from the first frame, after a lead-in simulated as a separate, unshadowed run of the same held bank. That is a one-frame step of one branch, which the D85 latch reads as an antenna fault (`d85_onset.md`, open risk 2: not flown in the data), and the lead-in is physically inconsistent: at that bank the airframe would already hide the antenna.

**What.**
- `console_scenario.m`: with shadowing the UAV flies a drawn turn (`yaw_random` true, `roll_deg` 0).
- `console_flights.m` selects the flights as the pools select theirs (`build_policy_pools.m`): candidate seed0 + j is kept when `hides_antenna.m` finds that, at the operator's speed and the Eb/N0's distance, the UAV rolls into its turn so that the airframe enters the line of sight just before frame `C.event_frame` (11) of a `C.event_run` (38) frame run and the loss counts by frame `C.event_count` (30). Up to 5000 candidates; none below `shadow_speed_floor.m` (28.8 km/h at 15.5 dB), and the reason is returned.
- Live run: the lead-in is the clean link of the same flight, frames 1-10, before the airframe enters the line of sight (the pools' lead-in rule); the attacked run is the same flight read from frame 11; the responses fly it again and read it from frame 11 (`simRun`). A combined threat with shadowing keeps the pools' rule too: clean before the onset, every component from it. At a speed where the level cannot occur the run is skipped with the reason in the log.
- Episode: both pools fly the two selected flights (the clean pool's cache key carries their seeds); the first cycle after the lead-in reads the event's frame, and past the run's end the last 10 frames (`link_env.m`'s rule); the clean lead-in is capped at 10 cycles, as in the evaluated episodes (onset cycle 3-10), with a log line. At a speed where the level cannot occur the episode stops with the reason.

**Checks (scratch probes, not tests).** One selected flight at 72 km/h and 9 dB (seed 4243, bank 45.6 deg): frames 1-10 of the clean and the shadowing builds are identical (largest gain difference 0.000 dB); the hidden antenna's gain falls from 9.2 dB to 4.5 dB by frame 20, and the event counts (5 dB) from frame 24. Share of candidates kept at a fixed speed (300 each, 1-1.5 ms per candidate): 0 at 0 and 20 km/h; 19-31% from 40 to 161 km/h.

**Not done.** The console's other scenarios still draw a new flight for each build, so their lead-in and attacked run are two flights; this is outside the finding.

**Test.** `test_console_shadowing_rolls_in`: the scenario draws its turn; for shadowing alone and with jamming, two flights at 72 km/h and 9 dB roll in, hide nothing before frame 11 and hide an antenna by frame 30; none at 10 km/h, with a reason; the live run, its lead-in and the responses fly the selected flight; the episode reads the event's frame at the onset.

## 6. The 3D engine resets the event flag (item 27, integration-6)

Code: `code/gui/viz3d/v3d_engine.m` (`inject`).

**What.** `E.ev` is set from `isfinite(ev)` of the flight injected on, and `k0` is moved only for a rolling-in flight. A threat injected after shadowing that moves to a 20-frame shared flight no longer reads frames 11-20 of it in a loop. `clearThreat` is unchanged: it never changes the flight (verifier).

**Test.** `test_v3d_inject_resets_event` (a toy M: shadowing sets the flag and k0 = 4; jamming after it moves to flight 1 and clears the flag).

## 7. Runtimes, the disk floor and the pools' memory (item 28, ops-13 with ops-5 and ops-6)

Code and docs: `code/main.m` (header, presets, every flag); `docs/DECISIONS.md`: a dated note in D61's disk-guard bullet, and "Cost and resources, re-derived (2026-10-16)" after D74's cost lines.

**Why.** main.m still gave runtimes from before the v7 layout (C1p 3-4 h, C2 3 h), its header and its flags disagreed (A5 17 against 40 min), it named a 200 GB floor where `disk_guard.m` has stopped at 150 GB since commit 62a5405 (2026-10-05), and D74's pool figures (4-4.8 GB, peak 25 of 31 GB) predate D84/D85.

**Basis.** The first full v7 reading's stage times (D80 code, logs in uav-gcs-logs), v6's later stages (D72 code), and the factors since: D75's delay line 1.28-1.88x per flight on v6's simulating stages, D84 (x1.03 A5 sub-runs, x1.021 C1p simulations, x1.07 per simulation, C2 twice the runs), D85 (idle model x1.10, up to x1.24 on concurrent smokes), B3n at 4 of 6 sub-runs. Every figure is derived in the DECISIONS.md entry; main.m points to it and gives one figure per flag.

| Stage (profile 1) | main.m before | now |
|---|---|---|
| A4v | none | 6-8 h |
| A5 | 17 min (header) / 40 min (flag) | 3.6-4 h |
| A6 | 7 / 12 min | 35 min |
| B1 | 1 / 2 min | 4 min |
| B2 | 8 min | 20-35 min |
| B2F | none | 4 min |
| B3n | none | 2.8-3.2 h |
| B3 | 2 min | 2 min |
| B3a | 16 min | 45-75 min |
| B4 | 25 / 30 min | 40-50 min |
| OOD | 70 min / 2.5 h | 3.7-4 h |
| B4s | 10 min | 20-35 min |
| C1p | 3-4 h | 90-105 h |
| C1c | 40 min | 11-13 h |
| C2 | 3 h | about 12 h |
| C2e | 1 h | 0.5-1.5 h (estimate) |
| C2g | 50 min | about 3.6 h (estimate) |
| C2u | none | about 2.5 h (estimate) |
| SURV | 1.5 h | 2.6-4.2 h |
| SURV3 | 1 h | 3.6-6 h |
| EDGE | none | 0.5-2 h (estimate) |
| LAT | 2 min | 1-6 min |
| Full run, one profile | 13 h | about 6-7.5 days |
| Decision layer + results | 10 h | about 5-6 days |
| Results only | 1 h | about 0.5-1.5 h |
| Three profiles (critical path) | none | 343-459 h, 14.3-19.1 days |
| Disk floor | 200 GB | 150 GB |

The review's own campaign estimate was 345-450 h; the difference is SURV and SURV3, which it took without the delay-line factor. The entry also states: the pools at 40.2 M stored frames, about 12.5 / 12.7 / 12.4 GB in memory on profiles 1 / 3 / 2 and 12-15 GB on disk, K tables about 0.7 GB each; side-by-side peaks of 32-40 GB against 31.2 GB of RAM at this base (the 83 GB commit limit prevents an out-of-memory stop; the memory item of the review lowers them); about 38-41 GB written per profile, 115-125 GB for the three, so a launch needs about 275 GB free against the 150 GB floor (2.6 TB free on 2026-10-16); the Windows Update pause ends 2026-11-05 13:38 UTC, inside the campaign's span.

## 8. Citations: Richards replaced by a library source

`docs/DECISIONS.md`, D59 (receiver measurements; survivability options) and D61 (antennas: the same claim as D59's), and one clause in D85's library audit. The brief named two places; the third (D61) repeats D59's claim and was corrected with it.

- "an N-element array nulls N-1 interferers": Winters, Salz & Gitlin 1994, Sec. I, p. 1740: with M antennas, M - 1 interferers can be nulled out; p. 1747 repeats it for a channel without multipath.
- "Richards, ch. 9" for the spatial measurements from the channel estimator the MMSE combiner runs: the same paper's optimum combining by direct matrix inversion, weights w = R^-1 r from the sample covariance of the received snapshots and their correlation with a known reference signal (eqs. 19-23, p. 1745); the known-symbol estimator stays the assumption of proposal risk 8.
- Library file: `V7_Winters_Salz_Gitlin1994_Antenna_Diversity_Capacity.pdf`. LITERATURE.md does not list it yet (outside this group's files).

## Tests

Five new tests directly after `test_m_files_parse`: `test_parallel_turn_owner`, `test_latency_load_logged`, `test_gui_bundle_drops_stale`, `test_console_shadowing_rolls_in`, `test_v3d_inject_resets_event`. No existing test changes its expectation (`test_console_scenario` and the fixed-view check in the shadowing test still hold: the maps and the gallery keep the held bank). Full suite (`runtests('code/tests/test_core.m')`): 146 passed, 0 failed, 32.3 min. `console_flights.m` was saved again about 1.5 min after that run started (before the commit), so `test_m_files_parse` and the five new tests were run again on the committed code: 6 passed.

## Files outside this group's list

- `code/evaluation/measure_all_kpis.m`: one line prints `LAT.load_text` under KPI 7.
