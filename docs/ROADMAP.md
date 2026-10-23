# UAV-GCS Adaptive Secure Communications — Roadmap

**Project:** AI-driven adaptive communication security for the GCS → UAV command link in electronic-warfare environments.
**Platform:** MATLAB R2026a + Simulink
**Supervisor:** Golan Ein-Tzvi
**History:** [PROJECT_LOG.md](PROJECT_LOG.md) · **Design decisions:** [DECISIONS.md](DECISIONS.md) · **Results:** [README.md](../README.md)

Last updated: 2026-10-23

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
| v7 | Real receiver with training and pilots, hover and turns, source-corrected severities, triples, profile 3 (four antennas), tracked directional GCS antenna under the e.i.r.p. cap; verdict per point (EDGE); fusion with the current frame; second detector test set; RF realism of distance, path loss, antenna fault and airframe shadowing | ⏳ Full run on 9b5c9f1 (D86-D89; launched 2026-10-16, stopped and redone 2026-10-17, resumed 16:42). Profile 1 in C1p since 2026-10-18 03:20 (82 of 93 cells on 2026-10-23 03:07); profile 3 done through B4s, waits before C1p (`p3_c1p.hold`) until profile 1's chain has ended; profile 2 dropped (D92). KPI 1 read once on the third test set (B3m), KPI 2 nested, B4, B4s (PROJECT_LOG). No stop of profile 1 (D93): it runs `208602b` with the base fusion to RPT; the Plan A stop is cancelled | D73–D93 |
| Scope | The lecturer's revised proposal of 2026-10-20 is the official scope: three-state detection, recovery, three configurations, the lecturer's KPIs; everything else built stays as extensions without commitment | ⏳ Code on `lect-kpi` `5b4b970` and `lect-p1` `8118281` (tests written, not run: the gate is closed). Profile 1's lecturer KPIs from isolated runs: C2e-lect after its C2e, B3c on its fourth test set (D93) | D92, D93 |
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
| 1 (3 antennas) | uav-gcs-v7, v7-dev `208602b` | A0-B4s (p1.log:2382), B3m (p1_b3m.log:323) | C1p since 2026-10-18 03:20 (p1.log:2384); 44 of 93 cells on 2026-10-21 morning. Runs OHP and GCSA |
| 3 (4 antennas) | uav-gcs-v7-p3, v7-p3 `29510e7` | A0-B3a, B4 (p3.log:1832), OOD and B4s after the out-of-memory stop (p3.log:2022, :2227), B3m (p3_b3m.log) | waits before C1p (`p3_c1p.hold`) for its deployment; OHP and GCSA skipped by `skip_stages` in its `profile.json`, set at the deployment |
| 2 (2 antennas) | - | - | dropped: `v7_d86/p2.abandon` written 2026-10-21 06:49; the takeover ends the track and the final phase skips it (D92) |

The processor boost is off since 2026-10-20 12:40; stages run up to about 35% slower.

**Official readings so far** (numbers and log lines in PROJECT_LOG, "Official detector readings"; confirmed from the primary files in the results audit of 2026-10-21):
- KPI 1 on the third test set B3m, read once: profile 1 93.58% [93.08, 94.07] above 0 dB; profile 3 94.19% [93.69, 94.68] above 3 dB. The every-class reading has no threshold on either profile: fault, shadowing, path loss and WLAN are below 90%.
- KPI 2 nested: 0.769 and 0.763, below the 0.8 target.
- B4: unseen Eb/N0 92.1% and 91.8%. B4s keeps the training levels on both profiles.
- The decision-layer KPIs (4-8) come after C2e.

**Status 2026-10-23: no stop of profile 1** (DECISIONS D93; supersedes the Plan A stop of D91/D92):
- Profile 1 runs its current code (`208602b`, base fusion, latch off) through C1c, SURV, SURV3, C1d, C2, C2e, C2g, C2u, GAL, OHP, GCSA, EDGE, KPI, DASH, WEAK and RPT. Its tree is only read.
- The fusion revision 'branch evidence, phi = 1' is validated (ADOPT, D91) but not deployed in profile 1; profile 3 deploys it.
- Profile 1's lecturer KPIs: an isolated copy of its C2e after it finishes (`docs/c2e_lect_protocol.md`, code `lect-p1` `8118281`, exact consistency gate), and B3c in a checkout of its own reading the fourth test set once, with no B3r before it (`docs/core_cnn_no_b3r.txt`). CORE_BW after profile 1's chain.
- Profile 3 waits until profile 1's chain has ended, then deploys the candidate `-q3` (`v7-deploy-d91` with `d91-edgefix`, `lect-kpi` and `skip_stages` OHP, GCSA) after the second deploy queue's six jobs on it.
- The gate stays at 28 GB; it is likely closed until profile 1's SURV3 ends (free commit 22-23 GB during the parallel stages, zombies 32824 and 8908). The report gallery job waits at it (relaunched 2026-10-23 03:08, 7-day wait).
- The steps, triggers and checks: the runbook `RUNBOOK_NOSTOP.md` (session scratchpad `interim_report/core/`, not in this repo) (T1 tests, T2 gallery, T3 B3c, T4 C2e-lect, T5 CORE_BW, T6 profile 3, T7 interim report inputs).

**Branches** (pushed; none is merged into a profile; the status column is as of 2026-10-18 except where D92 changes it):

| Branch, commit | Content | Status |
|---|---|---|
| `lect-kpi` (worktree `uav-gcs-lectkpi`, off `v7-deploy-d91`; `27803c3`, `2562605`, `c8ca607`, `0be0662`) | the lecturer's KPIs: `per_metrics.m`, `per_reduction.m`, `lect_kpis.m`, `three_state_view.m`, `profile_skip_stages.m`, `run_stage.m` (DECISIONS D92) | tip `5b4b970` (adds B3c without B3r, the C2e-lect protocol and script; 257 tests) and `lect-p1` `8118281` (profile 1's code plus the readers); tests not run (the gate is closed); not pushed; goes to profile 3 through `-q3`, not into `v7-dev` (D93) |
| `d90-loop` `2cbe559` | C1d/C2/KPI choices on validation (DECISIONS D90; `docs/d90_loop.md`) | full suite passed inside d91-speed (196/196); its own smoke and review pending; merge window: after profile 1's C1c (SURV/SURV3), before C1d, and only once the takeover runs the campaign (launcher defect (b), D91 part 4); into v7-p3 only while no profile 3 MATLAB runs |
| `d91-fuse` `2ea990a` | branch-evidence fusion revision (DECISIONS D91; `docs/d91_fuse.md`) | verdict ADOPT on both profiles by the pre-registered rule; 'branch evidence, phi = 1' validated; deployed in profile 3 only, not in profile 1 (D93); deploy checklist in sec. 7 |
| `d91-set4` `0e410cf` | fourth detector test set B3q and its single reading B3r (`docs/d91_set4.md`) | built for both profiles, unread (`uav-gcs-logs/set4_out/`); profile 1: read once by B3c only, no B3r (D93); profile 3: B3r at its deployment |
| `d91-speed` `0069d03`, `d91-speed-on-v7-p3` `686fd11` | value-neutral pool speedups for profile 3 (`docs/d91_speed.md`) | proofs PASS on `70f69f4` (B_old_vs_new, C_order and C_vs_B with the detector applied) and on `686fd11` with 4 antennas (B_old_vs_new_nrx4, C_order, C_vs_B_nrx4); tests2 196/196; tests4 merge job started 21:09:09 on 2026-10-18, VERDICT not recorded here; goes into v7-p3 by `git cherry-pick 2cbe559..d91-speed` (d91_speed.md sec. 7) |
| `d91-takeover` `7d4d0b6` | takeover of the d86 launcher (`ops/v7_d91_takeover.md`) | not launched on 2026-10-18; review round 3 FIX-NEEDED, round 4 running; it ends the profile 2 track (D92) |

**Timeline** (estimates, not measurements; 2026-10-23, D93):

| Milestone | Projected |
|---|---|
| Profile 1's C1p ends | 2026-10-23 evening to 10-24 morning |
| Profile 1's SURV3 ends, gate likely open (tests, gallery) | about 2026-10-25 |
| Profile 1's C2e ends, then the isolated C2e-lect run | about 2026-10-26/27 |
| B3c reading | 2026-10-26/27 if 65 GB is free during C2, else right after profile 1's end |
| Profile 1's chain ends (RPT) | about 2026-10-28/29 |
| CORE_BW | about 2026-10-29 to 11-02 |
| Profile 3 (deployment after profile 1, then C1p to RPT) | about 2026-11-08/11 |
| Final LAT and KPI | after profile 3 |

- The projection of 2026-10-18 (DECISIONS D91 part 5) is superseded: profile 1 C1p 2026-10-24 14:00 to 10-25 10:00, profile 1 about 2026-10-27/28, profile 3 about 2026-11-04/06. Profile 2's date (about 2026-11-10/15) is void: the track is dropped.
- The boost-off slowdown (up to about 35% per stage) is in the new dates.
- These dates pass the end of the Windows Update pause (2026-11-05 13:38 UTC); the takeover's resume handles a reboot.
- The d91 speedups could save about 3 days on profile 3.
- C2: the 72-run grid of 9b5c9f1 takes about 22-24 h per profile, not D86's 12 h; d90's 108 runs about 38-42 h (`C.drop_steps = [-2 0]` keeps 72 runs, about 26 h; d90_loop.md sec. 7).
- The C1p figure of 2026-10-18 (155-175 h) is a projection from a cost model of the 93 cells (docs/runs/analysis/c1p_slow_model.py; DECISIONS D91 part 5).

## The lecturer's KPIs (revised proposal of 2026-10-20; DECISIONS D92)

Mapping used in the code: narrowband = `tone_jamming`, wideband = `jamming` (barrage); static link = `none` / `no_action`, conventional adaptive (link metrics only) = `blind_esc`, CNN-based adaptive = `rule_esc`. New code is on `lect-kpi` and `lect-p1` (tests not run); for profile 1 the readings come from isolated runs (D93).

| Lecturer's KPI | Target | Code | State |
|---|---|---|---|
| BER model validated against theory | within the 0.3 dB of KPI 3 | `validate_phy.m` (A4v) | read: 7/7 on both profiles |
| Macro-F1 on an independent test set | ≥ 85% | `eval_detector.m` on B3m (read); B3c, the three-state CNN, on the fourth set (profile 1: one reading, no B3r, D93); `three_state_view.m` for the three states clean / narrowband / wideband, from the saved confusion matrix, no new test reading | KPI 1 read (93.58 / 94.19, eleven classes); three-state view not run |
| False alarms in clean states | ≤ 5% | KPI 6 in `evaluate_policies.m` (clean-link episodes) | after C2e |
| Recall per jamming type | ≥ 85% | `three_state_view.m` (narrowband, wideband); per-class recall of `eval_detector.m` for the eleven classes ("Acc" there is recall) | not run |
| PER reduction against the static link, recoverable scenarios | ≥ 30% | `per_metrics.m`, `per_reduction.m`, `lect_kpis.m`: paired geometry-bootstrap interval | after C2e |
| Recovery time | reported; no target | `lect_kpis.m`: `t_rec_det` from detection until the PER stays under the threshold for the fixed window; `t_conf`, onset to detection, measured separately | after C2e |
| Goodput | reported; no target | `lect_kpis.m`: bit/s at 50 kb/s nominal | after C2e |
| CNN contribution against the conventional mechanism | analysis metric, not a promise | the same metrics for `rule_esc` against `blind_esc` | after C2e |

The eight KPIs of the earlier proposal (README, "Proposal KPIs") stay as extensions without commitment.

## Remaining work

1. **Profile 1's lecturer KPIs without a stop** (DECISIONS D93; the runbook `RUNBOOK_NOSTOP.md` (session scratchpad `interim_report/core/`, not in this repo)): the tests of `d91-edgefix` (5), `lect-kpi` (257) and `lect-p1` (192) through the gate's wrapper in the profile 3 slot once the gate opens; B3c on the fourth test set in a checkout of its own; the isolated C2e-lect run once profile 1's C2e is done; CORE_BW after profile 1's chain. No merge into `v7-dev`.
2. **Profile 3's deployment after profile 1's chain** (D93): the candidate `-q3` (`v7-deploy-d91` + `d91-edgefix` + `lect-kpi`, `skip_stages` OHP and GCSA in the tested tree), the second deploy queue's six jobs on it (smoke included: link_env changed), then `d91_deploy.md` D1-D8. The Plan A stop of profile 1 (D91, D92) is cancelled; its checklist is kept for a future stop.
   - profile 3 before its C1p: B2F rerun (the fusion revision), B3-B4s, the rehearsal, B3r once; the speedups and d90 come with the candidate.
3. **The takeover** runs since 2026-10-20 11:22; after any reboot only its recovery command (`ops/v7_d91_takeover.md`, "After a reboot or a crash").
4. **d90 into the profiles:** profile 3 through `-q3`. Profile 1 does not take d90 (D93): its chain runs `208602b` to the end.
5. **Checks after profile 1's C1p:** `PP.model_tag` in its pools must read `v7-D89` (DECISIONS D89, Adoption), and C1c must pass its detector check.
6. **KPI 2 below its target** (0.769 / 0.763): the untried options are in PROJECT_LOG, weak-class status. The OOD score is in the detector identity, so a change after C1p means a pool rebuild.
7. **Classes below 90%** (path loss, WLAN, fault, shadowing): the user accepts at least 85% per class for now and decides with the full results. The candidates are in PROJECT_LOG, weak-class status. For shadowing, M3 of d91-fuse (the coherence columns) meets its note's criterion on the fit set and is a candidate, not yet designed (DECISIONS D91, Evidence).
8. **Interim report** (due 2026-11-01, writing from about 2026-10-20): a chapter per threat, good and correct figures; it needs no final v7 numbers. The results audit of 2026-10-21 found 58 wording issues about what a number measures in the draft (for example, the 2.67 / 3.85 ms latency is the detector forward pass plus the score); they are to be fixed.
9. **Operator console and 3D:** screenshots and a live check with the v7 agent after the run. The high-quality 3D view waits until the code, the final proposal and the interim report are done.
10. **Final report, slides and poster:** last, when the user asks.
11. **Housekeeping**, with the user's approval:
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
