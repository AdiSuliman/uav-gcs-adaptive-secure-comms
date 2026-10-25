# UAV-GCS Adaptive Secure Communications — Roadmap

**Project:** AI-driven adaptive communication security for the GCS → UAV command link in electronic-warfare environments.
**Platform:** MATLAB R2026a + Simulink
**Supervisor:** Golan Ein-Tzvi
**History:** [PROJECT_LOG.md](PROJECT_LOG.md) · **Design decisions:** [DECISIONS.md](DECISIONS.md) · **Results:** [README.md](../README.md)

Last updated: 2026-10-25 (afternoon; the stop window of profile 1 has been open since 10:50)

---

## Status by phase

| Phase | Content | Status | Decisions |
|---|---|---|---|
| A1–A3 | QPSK link with RRC, AWGN; Rician fading K = 10 dB, Doppler for a 50–120 km/h UAV | ✅ Done | D5, D6, D11, D25 |
| A4 | Two-antenna UAV receiver (MRC, MMSE), eight threats + combinations, interferer direction per seeded run | ✅ Done | D8–D12, D32, D41, D45 |
| A4v | Validation against theory (AWGN, Rician, MRC 2/3 antennas, correlated branches at K = 0/10/20 dB), MMSE under jamming, seeds, tone calibration | ✅ v5: 7/7 within 0.3 dB, seeds and tone PASS | D41, D68 |
| A5–A6 | 27,000 frames from 1,350 seeded sub-runs, spectrograms + 9 link features | ✅ Done | D42, D43, D45 |
| B | CNN + link-feature detector, bootstrap intervals, unseen Eb/N0 | ✅ Done, 96.3% | D42, D43 |
| B-unknown | Mahalanobis and isolation-forest scores, leave-one-threat-out | ✅ Done, AUROC 0.887 | D42, D46 |
| C1p | Frame pools: every scenario × configuration × Eb/N0 × geometry | ✅ Done | D44–D46 |
| C1c | Clean link on 100 new geometries per Eb/N0 under every configuration (KPI 6) | ✅ Done | D51 |
| C2 | Double DQN with shield; monitor, drop threshold, false-switch penalty and seed chosen on validation (γ chosen on validation up to D64; one fixed value, 0.5, since D65: D65-D67 retrain at the D64 selection, v5-v7 from D68 on; D90); deployed with escalation | ✅ D67 agent (3/3, 3 dB, γ 0.5, running costs ×0.5, false-switch penalty 160), adopted as a documented exception; D65, D66 not adopted | D44–D52, D59–D67 |
| C2e | Every policy on the test pools: single, follower, combined, unknown, clean, comb; false alarms on 600 independent clean geometries | ✅ Four readings; the fourth (new flights, blocks 8 and 9, D67 agent) is final | D44–D46, D51, D64–D67 |
| SURV | Survivability maps A/B, two geometries (deliverable 8) | ✅ Done, 86% / 94% | D30, D46 |
| LAT + KPI + DASH | Latency per cycle, eight proposal KPIs, dashboard (deliverable 1) | Fourth reading 7/8 met: KPI 4 14/16 (benign interference 87.2%, noise burst + antenna fault 88.7%); KPI 7 met (speed spread 2.6 points, latency 2.91 / 3.97 ms); KPI 6 13/600 | D46, D48, D51, D52, D64–D67 |
| GUI | Operator console on the current decision layer | ⏳ Live tab checked (D53 lead-in, D54 hover help); episode tab check pending | D24, D26, D46, D53, D54, D56 |
| 3D | Unreal 3D view: live console (threat control, operator vs AI), defense videos, console-episode replay | ✅ Built and tested (D58); Cesium terrain optional | D57, D58 |
| Fixes | Latency tail; false-alarm bound (KPI 6) | ✅ latency p95 48.9 → 19.4 ms / ✅ KPI 6: 1.5% over 600 independent geometries, bound 2.60% (D52) | D48–D51 |
| v4 | Receiver-side measurements, 36 combined configurations, combined threats in training, three severities, per-antenna feature, unknown-threat score selection, new-threat learning, 20 ms decision period | ✅ Full run A0–C2g done; hold in the shield (D63); escalation out of no_action (D64) | D59–D64 |
| v5 | Ten threats (tone jamming, airframe shadowing), K 0–20 dB per flight, Eb/N0 0–15 dB, eight dataset and five decision levels, ten combined threats, one-cycle signalling delay, speeds outside training, single-core latency | ✅ Superseded by v6 (detector reading led to D72) | D68–D70 |
| v6 | Evidence over time, quiet slot, levels to the sources' caps, weak-point analysis | ✅ Done, both profiles (summary document 2026-10-06); superseded by v7 | D71, D72 |
| v7 | Real receiver with training and pilots, hover and turns, source-corrected severities, triples, profile 3 (four antennas), tracked directional GCS antenna under the e.i.r.p. cap; verdict per point (EDGE); fusion with the current frame; second detector test set; RF realism of distance, path loss, antenna fault and airframe shadowing | ⏳ Full run on 9b5c9f1 (D86-D89; launched 2026-10-16, stopped and redone 2026-10-17, resumed 16:42). Profile 1: C1p, C1c, SURV and SURV3 done (SURV 2026-10-25 01:49 summer time, 386.3 min, 64 gap cells; SURV3 10:49:56, 599.9 min), cut there as designed; the stop window is open since 10:50, the deploy queue T2 runs since 11:59:01. Profile 3 done through B4s, waits before C1p (`p3_c1p.hold`) until profile 1's chain and CORE_BW; profile 2 dropped (D92). KPI 1 read once on the third test set (B3m), KPI 2 nested, B4, B4s (PROJECT_LOG). Software-only Plan A stop of profile 1 (D94): D90, D91, d91-edgefix and lect-kpi up to `9122b8d` deployed before C1d, the clean reference from the validation clean flights (step M, D95), the rule's noise-burst answer chosen on validation in C2 (D97); the end-to-end plan approved 2026-10-25 (D96, floors 55 GB, time box 2026-10-27 18:00), pre-registrations D98; the merged tip (`TIP` `85484b0`) built locally and tested in the window, not pushed | D73–D101 |
| Scope | The lecturer's revised proposal of 2026-10-20 is the official scope: three-state detection, recovery, three configurations, the lecturer's KPIs; everything else built stays as extensions without commitment | ⏳ Code on `lect-kpi` (tip `53f7b24`; the part up to `9122b8d` ran in T0 on `TIP`, the commits after it run in profile 3's own `core`). Up to `9122b8d` it is merged into `v7-deploy-d91` (`TIP` `85484b0`) and enters profile 1 at the software-only stop before C1d (D94, D96): profile 1's own C2e and KPI write the lecturer's lines, and B3c reads its fourth test set once, after B3r. The JSI decoder (`f328e7b`-`e922d63`, D97), the survivability map v2 (D100) and SURV3 v2 (D101) go to profile 3 only. CORE_BW after profile 1, with the clean table and a validation-chosen conventional baseline (D98 a). The isolated runs of D93 are plan B only | D92–D101 |
| Layout | Code into `code/` by stage | ✅ Done | D47, D61 |
| D1 | Interim report | ⏳ Drafted, results to sync with the final run | — |
| D2 | Final report | ⏳ | — |
| D3 | Defense (20 + 10 min, English) | ⏳ | — |
| D4 | Poster | ⏳ | — |

---

## v7 full run: status 2026-10-21 (morning)

The run is on code `9b5c9f1` (v7-merge: c2c8b8b + D87 + D88 + D89). It was launched on 2026-10-16 11:09, stopped and redone on 2026-10-17, and resumed at 16:42 (DECISIONS D86-D89; PROJECT_LOG 2026-10-15/21). Logs: `C:\Users\Adi Suliman\uav-gcs-logs\v7_d86\` (p1.log, p3.log, p1_b3m.log, p3_b3m.log, p3_fix.log, p1_set4.log, p3_set4.log). The earlier status at the drive swap (2026-10-06) is in `docs/drive_swap/`.

The lecturer's revised proposal of 2026-10-20 is the official scope (DECISIONS D92; KPIs in "The lecturer's KPIs" below). Profile 2 is dropped, and the relay path and the altitude axis of the envelope are not reported.

| Profile | Worktree, branch | Done (log markers) | Now |
|---|---|---|---|
| 1 (3 antennas) | uav-gcs-v7, v7-dev `208602b` | A0-B4s (p1.log:2382), B3m (p1_b3m.log:323) | C1p done (8692.4 min, p1.log:7918), C1c done (911.3 min, :11444), SURV done 2026-10-25 01:49 summer time (386.3 min, :17628); SURV3 done 10:49:56 (599.9 min, :17630-20521), cut there for the deploy before C1d (D94, D96); the stop window is open (status below). Runs OHP and GCSA |
| 3 (4 antennas) | uav-gcs-v7-p3, v7-p3 `29510e7` | A0-B3a, B4 (p3.log:1832), OOD and B4s after the out-of-memory stop (p3.log:2022, :2227), B3m (p3_b3m.log) | waits before C1p (`p3_c1p.hold`) for its deployment after profile 1 and CORE_BW: its own `core` and smoke on `TIP3` (D98 d), dev set C chooses `fec_rx` before its C1p (D97); OHP and GCSA skipped by `skip_stages` in its `profile.json`, set at the deployment together with `surv_v2` (D100, D101) and, after dev set C, `fec_rx` (D97) |
| 2 (2 antennas) | - | - | dropped: `v7_d86/p2.abandon` written 2026-10-21 06:49; the takeover ends the track and the final phase skips it (D92) |

The processor boost is off since 2026-10-20 12:40; stages run up to about 35% slower.

**Official readings so far** (numbers and log lines in PROJECT_LOG, "Official detector readings"; confirmed from the primary files in the results audit of 2026-10-21):
- KPI 1 on the third test set B3m, read once: profile 1 93.58% [93.08, 94.07] above 0 dB; profile 3 94.19% [93.69, 94.68] above 3 dB. The every-class reading has no threshold on either profile: fault, shadowing, path loss and WLAN are below 90%.
- KPI 2 nested: 0.769 and 0.763, below the 0.8 target.
- B4: unseen Eb/N0 92.1% and 91.8%. B4s keeps the training levels on both profiles.
- The decision-layer KPIs (4-8) come after C2e.

**Status 2026-10-25 (afternoon): software-only Plan A stop of profile 1, the stop window open** (DECISIONS D94; the end-to-end plan approved 2026-10-25, D96; pre-registrations D98, D99, D101):
- **The cut.** Done as designed. The cut file `v7_d86/p1_cut_after.SURV3` (2026-10-23 08:56) stood; SURV3 ended 2026-10-25 10:49:56 (599.9 min, `p1.log:17630-20521`). C1d's header printed at 10:49:45 and the chain MATLAB was killed at 10:49:56 with nothing written by C1d; the chain ended rc=1 and the ALERT files were as expected. F0 = 66.05 GB free commit at 10:51 (42560 gone, turn file absent), so no reboot (D96 C4). B4 archive `uav-gcs-logs/deploy_archive/p1/pre_deploy_20261025_105141`, the two `fusion.mat` SHA-256 equal (`1675c9a3`). The stop window is open since 10:50. SURV (386.3 min) and SURV3 are reviewed (`surv_review.md`, `surv3_review.md`, session scratchpad `interim_report/core/`): no lecturer KPI reads either; profile 1's report takes wording only, profile 3 gets the map v2 (D100) and SURV3 v2 (D101).
- **Before C1d,** profile 1 takes one merged tip, `TIP` = `v7-deploy-d91` + `d91-edgefix` (with its test fix `ad92546`, merge `0830fa5`) + `lect-kpi` up to `9122b8d` + the B3c test fix: `85484b0`, tree `553658e4`; profile 1's candidate `P1C` `c05285e` (tree `e6df2604`), `-q3` `9328e37` (tree `061207a1`), `P1O` `2a70d56` (unchanged); built locally 2026-10-25 (STOP_SOFT A2-A4, redone twice for test fixes, the 01:15 values `8b28bdf`, `794bf2a`, `7e905e0` superseded), worktree `X` = `uav-gcs-tip` detached at `TIP`, not pushed. It carries:
  - D90's audit fixes, with C2 at 108 runs;
  - D91's fusion revision 'branch evidence, phi = 1', with the B-stage rerun, the rehearsal (numeric pass first, D98 e) and one B3r reading of the fourth test set;
  - the EDGE fix;
  - the lecturer-KPI code and the clean-reference rebuild (D95);
  - the rule's noise-burst answer chosen on validation in C2 among uncoded configurations (D97); the JSI decoder is for profile 3 only.

  B3c then reads the fourth set once, after B3r, and a read-only KPI summary follows. Then step M (M1 ran early, below, D96 C6; M2 after B3c), `rekey_pools`, a 30-minute notice and the resume from C1d (`p1_resume.go`).
- **The window so far** (PROJECT_LOG, 2026-10-25). T1 (the edgefix tests) found one failing test, `test_rekey_unknown_agents`, fixed in `ad92546`. T0, the full merged suite by hand on `X`, gave 260/264 at `66ec267`: three B3c tests had never run (`ver('deeplearning')` is empty in R2026a) and `test_core_cnn_inputs` failed (a run in the source checkout itself did not stop); fixed in `85484b0` (cherry-picked to `lect-kpi` as `9b29dcb`), rerun 8/8. The deploy queue T2 (`core pold pnew porder p3core smoke` on `85484b0`, `c05285e`, `208602b`, `2a70d56`) runs since 11:59:01, 69 min after the cut. E-ebno (the tests of D99's script): 13/13 after a thread-count guard (`lect-ebno` `be89e74`). M1 early (D95): verdict `clean_ref` confirmed, clean BER at 9 dB 1.45e-3 [1.01e-3, 1.97e-3], inside the pre-registered 3e-4 to 6e-3 (C1p's table: 2.42e-5); physically sound (`m1_review.md`: a per-flight attitude-null tail that deepens as the grid brings the GCS closer, not an error floor). D99's L points are then 0 and 3 dB only and 9 dB is tagged M (clean loss 0.14); the restoration test is stricter at 6 dB and more lenient at 9-15 dB.
- **Gates still open.** The queue's verdicts (`core` 264/264, the proofs at n_rx 3, the smoke 14-24 h) must pass before the code enters `v7-dev` (I2). Branches are pushed after their tests pass (T3), never `main`. Plan B (resume on `208602b`, with step M and B3c before its resume, D98 b-c) if I2 has not run by 2026-10-27 18:00.
- **Next, in order:** the queue's verdicts, T3 pushes, I2, the fourth set copied in, the B stages (B2F, B3-B4s), the rehearsal, B3r once, B3c once, the read-only KPI summary, M2, the re-key, and the resume from C1d (about 2026-10-26).
- **Memory floors** (the user, 2026-10-25): 55 GB for B2F, the B stages and the rehearsal; B3r `max(55, rehearsal peak + 10)`; B3c `max(55, train-only peak + 7 + 10)`. Measured 10:51: F0 = 66.05 GB free commit (42560 exited, turn file absent). The gate stays at 28 GB.
- **The report gallery** ended 2026-10-24 08:45:48 rc=0.
- **After profile 1:** CORE_BW first (D98 a), then profile 3 on `TIP3` with its own `core` and smoke (D98 d).
- **The steps:** `STOP_SOFT.md` with its V2 section, and `plan_v2.md` (session scratchpad `interim_report/core/`, not in this repo).

**Branches** (pushed unless a row says not pushed; none is merged into a profile; the status column is as of 2026-10-18 except where D92-D101 change it):

| Branch, commit | Content | Status |
|---|---|---|
| `lect-kpi` (worktree `uav-gcs-lectkpi`, off `v7-deploy-d91`; `27803c3`, `2562605`, `c8ca607`, `0be0662`) | the lecturer's KPIs: `per_metrics.m`, `per_reduction.m`, `lect_kpis.m`, `three_state_view.m`, `profile_skip_stages.m`, `run_stage.m` (DECISIONS D92) | tip `53f7b24` (`5b4b970` adds B3c without B3r, the C2e-lect protocol and script, 257 tests; `2ae5f46`, `503b03a`, `8b396e6` add `clean_ref_rebuild`, its two tests and `docs/clean_ref_protocol.md`, D95; `9122b8d` the rule's noise-burst answer on validation and `docs/noise_burst_protocol.md`, 4 tests, D97, merged suite 264; `f328e7b`, `c96d801`, `ad92110`, `e922d63` the JSI decoder for profile 3, D97; `3e7c945`, `f345910`, `706fa79`, `70f3c2d` the J4 gate and profile 3's survivability map v2, D97, D100; `9b29dcb` the B3c test fix; `b958265`, `53f7b24` SURV3 v2 for profile 3, D101) and `lect-p1` `8118281` (profile 1's code plus the readers, plan B only); tests: the part up to `9122b8d` ran in T0 on `TIP` (260/264, then the fix and 8/8), the commits after it run in profile 3's own `core` (283 tests on `TIP3`); not pushed; up to `9122b8d` merged locally with `d91-edgefix` into `v7-deploy-d91` (`TIP` `85484b0`, which also holds the B3c test fix, 2026-10-25), into `v7-dev` at I2 and into profile 3 through `-q3`; the rest goes to profile 3 as `TIP3` (D96 C1, D98 d, D101) |
| `lect-ebno` `be89e74` (off `lect-kpi` `9122b8d`; `9d5bfc8`, `b0df851`, `c7f8107`, `dcb89f0`) | D99's reporting-only readings at link-limited Eb/N0 points: `lect_kpis_by_ebno.m`, `core_bw_lect_by_link.m`, `docs/lect_ebno_protocol.md` | tests 13/13 after `be89e74` (the thread-count guard); not pushed; run once after profile 1's `STAGE C2e done` |
| `d91-edgefix` `ad92546` (`fbdeba0`, `8fdb09e`) | `edge_map` names the leave-one-out agents' file and C2u, the smoke's `dep_*` steps run in chain order, `test_rekey_unknown_agents` (D94); `ad92546` lets a file with no `check_det_id` call pass that test | merged into `v7-deploy-d91` (edgefix merge `0830fa5`, then `lect-kpi` up to `9122b8d` and `85484b0`) as `TIP`; not pushed |
| `d90-loop` `2cbe559` | C1d/C2/KPI choices on validation (DECISIONS D90; `docs/d90_loop.md`) | full suite passed inside d91-speed (196/196); in `v7-deploy-d91`; enters profile 1 at the software-only stop before C1d (D94), profile 3 through `-q3` |
| `d91-fuse` `2ea990a` | branch-evidence fusion revision (DECISIONS D91; `docs/d91_fuse.md`) | verdict ADOPT on both profiles by the pre-registered rule; 'branch evidence, phi = 1' validated; deployed in profile 1 at the software-only stop (B2F, B3-B4s rerun, D94) and in profile 3 at its deployment; deploy checklist in sec. 7 |
| `d91-set4` `0e410cf` | fourth detector test set B3q and its single reading B3r (`docs/d91_set4.md`) | built for both profiles, unread (`uav-gcs-logs/set4_out/`); profile 1: B3r once at the stop, then B3c once after it (D94); profile 3: B3r at its deployment |
| `d91-speed` `0069d03`, `d91-speed-on-v7-p3` `686fd11` | value-neutral pool speedups for profile 3 (`docs/d91_speed.md`) | proofs PASS on `70f69f4` (B_old_vs_new, C_order and C_vs_B with the detector applied) and on `686fd11` with 4 antennas (B_old_vs_new_nrx4, C_order, C_vs_B_nrx4); tests2 196/196; tests4 merge job started 21:09:09 on 2026-10-18, VERDICT not recorded here; goes into v7-p3 by `git cherry-pick 2cbe559..d91-speed` (d91_speed.md sec. 7) |
| `d91-takeover` `7d4d0b6` | takeover of the d86 launcher (`ops/v7_d91_takeover.md`) | not launched on 2026-10-18; review round 3 FIX-NEEDED, round 4 running; it ends the profile 2 track (D92) |

**Timeline** (estimates, not measurements; 2026-10-25, D96, `plan_v2.md` section 4; no failure, boost off):

| Milestone | Best | Expected | Worst |
|---|---|---|---|
| The cut (SURV3 done; started 2026-10-25 01:49:50 summer time) | 10-25 05:30 | 10-25 10:49:56 (measured: 599.9 min, SURV3/SURV 1.55) | 10-25 16:00 (about 19:30 at the v7-smoke ratio) |
| I2, the point of no return | 10-26 02:00 | 10-26 11:00 | 10-26 21:00 (time box 10-27 18:00) |
| B3c recorded (three-state macro-F1, recall per type, detector false alarms) | 10-26 10:00 | 10-26 21:00 | 10-27 09:00 |
| Profile 1 resumes from C1d | 10-26 10:00 | 10-26 22:00 | 10-27 11:00 |
| Profile 1's C2e (lecturer's lines) | 10-28 03:30 | 10-29 06:00-08:00 | 10-30 03:30 (box: 10-31 00:00) |
| Profile 1's RPT | 10-28 15:00 | 10-29 22:00 | 10-30 22:00 |
| CORE_BW | 10-30 night | 10-31 midday | 11-02 |
| Profile 3 (own core and smoke, dev set C, its map v2 and SURV3 v2, C1p to RPT) | about 11-14 | about 11-16/18 | about 11-20 |
| Final LAT and KPI | after profile 3 | | |

- The cut came at 10:49:56 (expected 11:00). T1's failure and redo and T0 (the full suite by hand on `X`, about 1 h, an estimate) move the dates after the cut by about 1-2 h; the T2 queue started 11:59:01, 69 min after the cut. The dates below the cut row are not recomputed.
- Profile 3's row includes its map v2 (44-50 h, D100); its SURV3 v2 (11.5-13.5 h, D101) costs what the plan assumed for SURV3, so no date moves for it.
- C2e reaches 2026-10-29 only if I2 runs by about 2026-10-26 19:00. With the boost at 100% during C2 (optional, the user), C2e lands about 2026-10-28 evening.
- The stop window: about 26-43 h from the cut to the resume (the smoke 14-24 h; the B stages 5.5-8.7 h single-thread). C2 at 108 runs plus 8 noise-burst evaluations: 51-57 h with the boost off.
- The dates of 2026-10-23 (D94: the resume about 10-25/26, C2e about 10-28/29, RPT about 10-30/31, profile 3 about 11-10/13) are superseded.
- The no-stop projection of D93 (profile 1 about 2026-10-28/29, profile 3 about 2026-11-08/11) is superseded by D94.
- The projection of 2026-10-18 (DECISIONS D91 part 5) is superseded: profile 1 C1p 2026-10-24 14:00 to 10-25 10:00, profile 1 about 2026-10-27/28, profile 3 about 2026-11-04/06. Profile 2's date (about 2026-11-10/15) is void: the track is dropped.
- The boost-off slowdown (up to about 35% per stage) is in the new dates.
- These dates pass the end of the Windows Update pause (2026-11-05 13:38 UTC); the takeover's resume handles a reboot.
- The d91 speedups are in profile 3's new dates.
- C2: the 72-run grid of 9b5c9f1 takes about 22-24 h per profile, not D86's 12 h; d90's 108 runs about 38-42 h (`C.drop_steps = [-2 0]` keeps 72 runs, about 26 h; d90_loop.md sec. 7).
- The C1p figure of 2026-10-18 (155-175 h) is a projection from a cost model of the 93 cells (docs/runs/analysis/c1p_slow_model.py; DECISIONS D91 part 5).

## The lecturer's KPIs (revised proposal of 2026-10-20; DECISIONS D92)

Mapping used in the code: narrowband = `tone_jamming`, wideband = `jamming` (barrage); static link = `none` / `no_action`, conventional adaptive (link metrics only) = `blind_esc`, CNN-based adaptive = `rule_esc`. New code is on `lect-kpi` (tests not run). It enters profile 1 at the software-only stop, so profile 1's own C2e, KPI and B3c give the readings (D94); a read-only KPI summary after B3c gives the detector lines before the resume (D96 C8). The rule's noise-burst answer is chosen on validation in C2 (D97). CORE_BW (track C, controlled bandwidth) runs after profile 1 with a validation-chosen conventional baseline (D98 a). The isolated runs of D93 are plan B only.

| Lecturer's KPI | Target | Code | State |
|---|---|---|---|
| BER model validated against theory | within the 0.3 dB of KPI 3 | `validate_phy.m` (A4v) | read: 7/7 on both profiles |
| Macro-F1 on an independent test set | ≥ 85% | `eval_detector.m` on B3m (read); B3c, the three-state CNN, on the fourth set (profile 1: one reading, after B3r, D94); `three_state_view.m` for the three states clean / narrowband / wideband, from the saved confusion matrix, no new test reading | KPI 1 read (93.58 / 94.19, eleven classes); B3c and the three-state view expected about 2026-10-26 21:00 |
| False alarms in clean states | ≤ 5% | KPI 6 in `evaluate_policies.m` (clean-link episodes); the detector's in B3c | detector about 2026-10-26 21:00; system after C2e (about 2026-10-29) |
| Recall per jamming type | ≥ 85% | `three_state_view.m` (narrowband, wideband); per-class recall of `eval_detector.m` for the eleven classes ("Acc" there is recall) | expected about 2026-10-26 21:00 (B3c) |
| PER reduction against the static link, recoverable scenarios | ≥ 30% | `per_metrics.m`, `per_reduction.m`, `lect_kpis.m`: paired geometry-bootstrap interval | after C2e (about 2026-10-29 06:00-08:00) |
| Recovery time | reported; no target | `lect_kpis.m`: `t_rec_det` from detection until the PER stays under the threshold for the fixed window; `t_conf`, onset to detection, measured separately | after C2e; onset latency also from B3r |
| Goodput | reported; no target | `lect_kpis.m`: bit/s at 50 kb/s nominal | after C2e |
| CNN contribution against the conventional mechanism | analysis metric, not a promise | the same metrics for `rule_esc` against `blind_esc` (C2e, blind's fixed first response, stated); `rule_core` against `blind_core` in CORE_BW with blind_core's first response chosen on validation (D98 a) | C2e about 2026-10-29; CORE_BW about 2026-10-31 |

The eight KPIs of the earlier proposal (README, "Proposal KPIs") stay as extensions without commitment.

## Remaining work

1. **The software-only stop of profile 1** (DECISIONS D94, D96, D98; steps in `STOP_SOFT.md` with its V2 section, session scratchpad `interim_report/core/`, not in this repo). Done in phase 0 (2026-10-25, local, not pushed): the merges into `v7-deploy-d91` (`TIP` `85484b0` after two test fixes), `P1C`, `P1O`, `-q3`, worktree `X`, the smoke driver, the records D96-D101. The cut came 2026-10-25 10:49:56. After the cut at SURV3's end:
   - F0 and the turn file (D96 C4): done, 66.05 GB at 10:51; the B4 archive done;
   - the edgefix tests (5) and T1b (the noise-burst tests from `X`): inside T0, the full suite by hand (260/264, fixed as `85484b0`, rerun 8/8; T1's one failure was fixed as `ad92546`); then the deploy queue on `TIP`, running since 11:59:01: the suite of 264 tests, the proofs at n_rx 3, and the smoke (14-24 h); M1 early done (D95, confirmed);
   - push the tested branches (never `main`); fast-forward `v7-dev` (I2, the point of no return; a push notice);
   - copy in the fourth set;
   - B2F, B3-B4s and the rehearsal at 55 GB; the rehearsal's numeric pass (`docs/d91_b3r_expect_p1.txt` in `W`); B3r once; B3c once (`docs/core_cnn_floor_note.txt` in `W` first); the read-only KPI summary;
   - step M2 (D95): the `'write'` of `clean_ref`, `PP.clean` and `PP.clean_fer`; on `stop` no write;
   - `rekey_pools` with the 30-minute notice, then the resume from C1d.
   - Plan B (resume on `208602b`, with step M and B3c before the resume, D98 b-c) if I2 has not run by 2026-10-27 18:00.
   - During C2 (no MATLAB): write and review CORE_BW's commit (D98 a). After the chain: the wrap check (`d91_deploy.md` E11).
2. **CORE_BW after profile 1's chain** (D98 a): `core-bw-p1` from `W`'s `v7-dev` at C2e done, inputs with the post-M `policy_pools.mat` (hashed), the clean-table assert, blind_core's first response chosen on validation; tests and smoke in the p3 slot; `pools`, `dset`, `val`, test once, report, `dread` at profile 1's end.
3. **Profile 3's deployment after CORE_BW** (D93 part 5, D94, D96, D98 d). The candidate is `TIP3` = `TIP` (`85484b0`) + `lect-kpi` `f328e7b`-`53f7b24` (the JSI decoder, the survivability map v2 and SURV3 v2: D97, D100, D101; trees recomputed 2026-10-25: `TIP3` `19f2bfe6`, `29510e7` + `TIP3` `38d61145`, `Q3'` `8d0d07bf`, `code/` `f9f225b1`, 283 tests), with `skip_stages` OHP and GCSA. It runs its own `core` and smoke, then `pold pnew porder p3core`, its non-smoke jobs only after profile 1's C2e and CORE_BW's smoke. Then `d91_deploy.md` D1-D9.
   - Dev set C chooses `fec_rx` (the JSI decoder, or `"d78"`) before its C1p, committed in its `profile.json` with its own DECISIONS entry (D97).
   - Its SURV (the map v2, 44-50 h) and SURV3 v2 (11.5-13.5 h) run with `"surv_v2": true` in its `profile.json` and refuse to start without `fec_rx` (D100, D101); their logs show the L marks, the like-for-like line and the shadowing candidates.
   - Profile 3's C1c ends with `clean_ref_rebuild('chain')` (D95): its clean reference comes from its own validation clean flights, with no step M.
   - Profile 3 before its C1p: the B2F rerun (the fusion revision), B3-B4s, the rehearsal and B3r once. The speedups and d90 come with the candidate.
4. **The takeover** runs since 2026-10-20 11:22; after any reboot only its recovery command (`ops/v7_d91_takeover.md`, "After a reboot or a crash").
5. **d90 into the profiles:** profile 1 at the software-only stop, before C1d (D94); profile 3 through `-q3`.
6. **Checks after profile 1's C1p:** `PP.model_tag` in its pools must read `v7-D89` (DECISIONS D89, Adoption), and C1c must pass its detector check.
7. **KPI 2 below its target** (0.769 / 0.763): the untried options are in PROJECT_LOG, weak-class status. The OOD score is in the detector identity, so a change after C1p means a pool rebuild.
8. **Classes below 90%** (path loss, WLAN, fault, shadowing): the user accepts at least 85% per class for now and decides with the full results. The candidates are in PROJECT_LOG, weak-class status. For shadowing, M3 of d91-fuse (the coherence columns) meets its note's criterion on the fit set and is a candidate, not yet designed (DECISIONS D91, Evidence).
9. **Interim report** (due 2026-11-01, writing from about 2026-10-20): a chapter per threat, good and correct figures; it needs no final v7 numbers. The results audit of 2026-10-21 found 58 wording issues about what a number measures in the draft (for example, the 2.67 / 3.85 ms latency is the detector forward pass plus the score); they are to be fixed. Draft 3 delivered (39 pages). Draft 4 about 2026-10-27: B3r and B3c in place of B3m, the pre-resume KPI summary, C2e dated about 2026-10-29 with the pre-registered lines marked "measurement in progress" if C2e is later, the noise-burst labels of D97 (D96 C15), the SURV and SURV3 wording (D101: 12-15 dB first, by family, 9 dB tagged M, D99). Review 2026-10-30/31, submission 2026-11-01.
10. **Operator console and 3D:** screenshots and a live check with the v7 agent after the run. The high-quality 3D view waits until the code, the final proposal and the interim report are done.
11. **Final report, slides and poster:** last, when the user asks.
12. **Housekeeping**, with the user's approval:
    - the zombie MATLAB 32824 (only a reboot frees its 4.6 GB);
    - the worktree copies `uav-gcs-b3m-p1/-p3` (their files are already in the profiles: copied 2026-10-17 22:04:19 and 22:51:15, p1_b3m.log:325, p3_b3m.log:325) and `uav-gcs-set4-p1/-p3` (after the fourth set is copied in at deployment, or after a no-go);
    - the stray empty folder `C:\ADISUL~1`;
    - the v3 backups in `archive/`, which stay until the user approves deleting them.

---

## Deviations from the original plan

| Original plan | What was done | Why |
|---|---|---|
| Symbol timing / phase recovery | v7: a real receiver with training, pilots and timing and frequency synchronization; the ideal receiver only as the validation reference | The ideal receiver hid how a real one fails (D7, D73) |
| CNN/LSTM on link metrics | CNN on the spectrogram + 9 link features; CNN-LSTM kept in `legacy/` | The LSTM gave no gain for its cost (D13) |
| 5 threat classes | 10 threats + none, ten pairs and four triples | A more realistic EW set within RF scope (D68, D73) |
| Single-antenna link | Two UAV antennas, MRC baseline, MMSE as the spatial countermeasure | Spatial diversity as a real receiver function (D41) |
| Actions: channel switch, bit rate, diversity | 36 configurations, one choice per domain (frequency, space, link budget): the originals, power control, FEC + interleaving | Threats that no single original action repairs (D39, D45, D59) |
| DQN on a reward table | Sequential environment on measured frames, shield with hold, γ chosen on validation in v4 up to D64 and fixed at 0.5 since D65 (γ = 0 tried as one coordinate step on validation in d90), escalation as a fallback | One-shot decisions could not show recovery over time or a follower jammer (D44–D46, D63, D64) |
| Rule vs DQN by convergence and reward | Return, restored cycles, goodput, recovery time, false alarms, with 95% intervals and paired differences | KPIs as worded in the proposal |
| Proposal v2 and the v7 scope (ten threats, eight KPIs, three profiles) | The lecturer's revised proposal of 2026-10-20 as the scope: clean / narrowband / wideband detection, rule-based recovery, three configurations (static, conventional adaptive, CNN-based adaptive), its KPIs; the rest stays as extensions without commitment; profile 2, the relay path and the altitude axis dropped | The user decided the revised proposal is the official one, unchanged (D92) |

---

## Risk mitigation (proposal section 10)

- **DQN convergence:** rule and table baselines in every comparison; 3 seeds per run setting (γ fixed at 0.5 since D65), best checkpoint, validation gate (D44–D46).
- **Reward design:** reward from link quality minus costs; baselines and oracle show where the policy stands.
- **Data leakage:** splits by seeded sub-run; test pools with unseen seeds and geometries.
- **Oscillation:** switching costs, alarm confirmation and shield (D45).
- **Unknown / combined threats:** Mahalanobis score, response to link degradation (unknown set: 69.5% of cycles restored without the class, rule + escalation 51.7%), training combinations (D46).
- **Sim-to-real gap:** validation against theory, documented modeling assumptions (README).
