# D84, group C: the decision layer and the evaluation (branch d84-dec)

Branch `d84-dec` from v7-merge `a66ebb9`, the fix plan's group C (items C1-C14) with the review findings DL-F1..F7, E-F1..F8, L-F3 and L-F9. This note is the merge input for the D84 entry of DECISIONS.md (DECISIONS.md itself is not edited here). Every choice below was made on code, physics and validation data; no test reading was taken.

## C1: the monitor takes our own configuration's gain out of the drop (DL-F1, L-F3)

**Why.** The link monitor's drop memory (`policy_monitor.m`: the reference median of the last 10 cycles without an alarm, minus the median of the last 3) held the Eb/N0 estimate as measured. A frame received under power_control carries the power step (4.00 dB with the D83 radio: `power_step_db.m`), under rate_reduce the processing gain (6.02 dB), under both 10.02 dB. Releasing a configuration on a clean link therefore read its own gain as a drop: on the v6 clean validation pools (600 flights, the a66ebb9 monitor, table A2 below) a power_control release raised a drop alarm in 97.5% of the flights (the v6 radio's 6 dB step, drop threshold 3.5 dB; 95.0% confirmed). A released configuration could re-apply itself (release, drop alarm, the reference freezes, latch). And the rule answered every loss of our signal with a fixed configuration, whatever its depth.

**Decision.**
1. `config_gain_db.m` (new): the known Eb/N0 gain of every configuration, `apply_countermeasure(p, 'none', a)`'s gain: the power step of power_control (Friis: the received power follows the transmitted power) and 10 log10(cm_rate_factor) of rate_reduce (Eb/N0 = S/N0 x 1/R). The pools store it (`PP.cfg_gain_db`, `CK.cfg_gain_db`; `build_policy_pools.m`, `build_check_pools.m`); the console (`demo_gui.m`) and `measure_latency.m` set it; pools built before it take it from params.mat.
2. `policy_monitor.m`: both drop windows hold the estimate less the known gain of the configuration the frame was received with (`obs.cfg_link`); the estimate itself stays as measured for the degradation test (`clean_ber_ref.m` compares the measured BER with the clean link's at the measured Eb/N0). `M.drop` and the agent's observation carry the compensated drop.
3. `rule_based_policy.m` / `policy_decide.m`: the answer to a loss of our signal (the drop alarm with a class that has no mapping, and the class path_loss) is a link-budget match: the received power fell by the drop, so the link-budget configuration (power_control, rate_reduce, rate_reduce+power_control) with the smallest known gain that covers the compensated drop, the largest when none does, and the configuration in use when its own gain already covers it (no flip after the first answer). Without the budget (one-argument calls, tables) the class mapping is unchanged.
4. `episode_cycle.m`: the live cycle passes `obs.cfg_link` (the configuration the console drew the frame with), so the compensation runs in the console too.

**L-F3, rate_reduce in the receiver.** Decision: the measurement route, not a despreading receiver. A real despreading receiver would need each bit spread over 4 symbols at the same rate: the transmitter's bit source and frame (1000 + 32 CRC bits per frame), the receiver's decisions, the CRC per frame and the FEC codeword over 4 frames (`fec_packets.m`) would all change shape, inside group A's link model, in parallel with A's changes; not feasible within this fix without a conflict. Instead the simulated field stays that of the despread link (our signal up by the gain against thermal noise and every interferer not spread like it, the BER and CRC physics unchanged), and the receiver takes the gain out of the level measurements a despreading receiver takes before despreading (chip synchronization, timing and the channel estimate come before the despreader: Pirayesh & Zeng 2022, the ZigBee receiver of Fig. 15 and its text). `apply_countermeasure.m` sets `p.proc_gain_db` for rate_reduce; `extract_closed_loop_frames.m` then scales the receiver's own estimate of our signal on every antenna (the re-modulated decisions fitted per 32-sample block, the fit env_corr already uses) by 10^(-g/20) before rssi and the detector image (`F.iq`), and takes g out of gain_ant (our channel's gain per antenna; every reader of it, temporal_evidence.m, uses it relative between antennas). The despread measurements keep the gain: sinr, snr_post, ber_est and est_margin (the channel estimate's margin over its noise, over the despread pilots), so the Eb/N0 estimate (sinr + iot) rises by it, and the monitor takes it out (item 2). iot and the residual measurements are those of the interference and noise, which keep their power. A first version also took g out of est_margin; on a jammed link whose receiver had failed (10 dB jammer at 6 dB, BER 0.45) the channel estimates track the jammer and do not move with our signal, so that put est_margin 9 dB under no_action: est_margin stays a despread measurement.

*The spoofer made consistent.* The model's spoofer is a counterfeit of our modulation and pulse shape with its own random symbols (`build_threat_model.m`, threat script), and D74 puts attacks aware of our protocol outside the commitment. A counterfeit that does not follow our protocol does not follow our spreading either, so despreading suppresses it like any signal not spread like ours: rate_reduce now lowers `spoof_sir_db` by its processing gain, as it lowers the jammers', the tone's and the WLAN's. Its absolute power is then unchanged under rate_reduce in every measurement (before: +6 dB absolute in the field). This is a change of the spoofer's response to rate_reduce (before: "no gain against a coherent spoofer", DECISIONS line 198); see Open risks.

**Tests.** test_config_gain (the gains from the params, the pools, the defaults), test_monitor_known_gain (power_control and rate_reduce+power_control held 12 cycles on a clean link and released: compensated, no drop alarm and a zero drop; uncompensated, the release reads the gain as the drop and raises the alarm; the estimate stays as measured), test_rule_budget_match (the matches, the keep, the quiet-slot and class cases, no budget = the old mapping; closed loop: a 3 dB step takes power_control and a 5 dB step rate_reduce, once each), test_rate_reduce_chip_level (the real link at 6 dB, same flight under no_action and rate_reduce, clean and with a 10 dB jammer: rssi and the mean detector-image level within 0.5 dB; clean: gain_ant within 0.5 dB, the despread SINR and est_margin up by the gain within 1 dB; the spoofer's field down by the gain, power_control leaves `proc_gain_db` unset), test_episode_cycle_link (the console's cycle passes cfg_link; the console's PP carries the gains).

Measured (rr_diag.m, rate_reduce minus no_action on the same flight at 6 dB): flat clean rssi -0.03, sinr +5.96, iot +0.04, gain_ant -0.03, image +0.01 dB; flat with a 10 dB jammer (the receiver fails, BER 0.45) rssi -0.23, image -0.14 dB; delay line clean rssi +0.06, image -0.01 dB; delay line jammed rssi +0.27, image -0.21 dB.

## C2: the drop threshold's grid and the deployed monitor (DL-F2)

**Why.** `train_dqn.m` tried the drop threshold 2 dB below the train-pool threshold only. On the v6 clean validation pools (drop path alone, the real monitor and rule, every flight from every start frame) T - 2 dB keeps the clean flights' false changes at 12.0 / 5.0 / 2.9 / 1.0% for 2/2, 3/3, 4/5, 5/5, against 1.2 / 0.4 / 0.3 / 0.02% at T itself (table below). The edge map ran DET's drop alarm and every policy on the DQN's monitor even when the rule fallback was deployed.

**Decision.** `DROP_STEPS = [0 2]` in `train_dqn.m` and `CFG.drop_steps = [0 2]` in `main.m`: validation selects between the train-pool threshold and 2 dB below it (D83's Open item), within the same false-alarm bound and weakest-threat selection (D62). `edge_map.m` sets PP's monitor from the deployed policy (`Q.rule_sel` when `deployed == 'rule_sel'`), so the policies, DET's drop alarm (`det_frames.m`), the check pools and the overhead pass read the deployed monitor. Cost: C2 trains twice the runs (72 DQN runs and 8 baselines at the full grid).

**Tests.** test_drop_step_grid.

## C3: DET of a path-loss step is the drop alarm alone under class_drop (DL-F3)

**Why.** Under 'class_drop' the monitor counts the class path_loss only together with the drop alarm (`policy_monitor.m`), but DET counted the fused class path_loss or the drop; on the smoke pools 29% of the clean frames read path_loss, so DET credited detections the deployed monitor never makes. Combinations with path loss read the class alone, without the clean lead-in the drop needs.

**Decision.** `det_frames.m` (moved out of `edge_map.m`, unchanged otherwise): with 'class_drop' the class path_loss is removed from the classes DET counts for a cell with a path-loss component, so the path-loss component is detected by the drop alarm alone, the other components by their classes; every cell with a path-loss component, combinations included, is read after the same flight's clean link (the drop needs the lead-in). With 'class' the fused class counts as before.

**Tests.** test_det_frames_drop (a path-loss class without a drop: no hit; a 6 dB drop read as clean: hit from its second frame; jamming+path_loss: the jamming class counts, the path_loss class does not; 'class': the class counts).

## C4: the clean pools keep their seeds and draws (DL-F4, E-F1)

**Why.** `edge_map.m` re-derived the draws of the 300 clean-link flights of `data/clean_test_pools.mat` with `pool_seed(1, s, blk, r)` for r = 1..300, while the pools flew families 1/3/5 with r = mod(k - 1, 100) + 1: flights 101-300 got the draws of other seeds (altitude, K, rho, bank and delay-spread bands wrong).

**Decision.** `build_clean_test_pools.m` stores `CT.seed` and every per-flight draw `CT.cov` (`flight_cov.m`, the fields of PP.cov, factored from build_policy_pools.m's loop); the seed of geometry k is `clean_pool_seed.m` (the one mapping, used by the builder and by the edge map's fallback for older pools); `edge_map.m` reads `CT.cov`. `pool_seed.m` asserts the geometry index in 1-100: the plan said <= 99, but the clean pools' hundredth geometry of a family is r = 100 (seed of the next block's geometry 0, which no block uses; test_seed_streams_disjoint already covers it), so 100 stays allowed and anything else (101-300 above) stops.

**Tests.** test_clean_pool_draws (the mapping, the assert, flight_cov against flight_draws, the edge map and the builder use them).

## C5: SURV counts the flights with the threat on the air (E-F2)

**Decision.** `edge_map.m` carries `FT.on` / `KF.on` (link_env.m K.on); `surv_layer.m` (moved out of edge_map.m) counts the recoverable flights among those with the threat on the air, so its n, the bands and SYSTEM follow. REC, PROT and DET already counted only the threat episodes and frames (R.threat, threat_active.m).

**Tests.** test_surv_on_air.

## C6: the unknown and unseen-combination experiments keep K.on (DL-F5, E-F5)

**Decision.** `mark()` in `experiment_unknown_threat.m` and `experiment_combo_generalization.m` keeps `R.threat` from `dqn_eval_batches.m` (K.on) instead of overwriting it with true.

**Tests.** test_experiments_keep_on_air.

## C7: escalation needs a confirmed alarm (DL-F6)

**Decision.** `policy_decide.m`: escalation, as every change of the rule and the table and the DQN's shield, happens only on a confirmed alarm (with 4/5 or 5/5 confirmation, 3 degraded cycles no longer escalate before the alarm is confirmed).

**Tests.** test_escalation_needs_confirmation (2/2: at the third degraded cycle; 5/5: at the fifth).

## C8: the clean pools carry the detector and the link model (DL-F7)

**Decision.** `build_clean_test_pools.m` computes the detector identity (detector_id.m), stops when the policy pools come from another detector, and stores `CT.det_id` and `CT.model_tag`; its up-to-date check requires them. `check_det_id.m` takes the file it checks (`check_det_id(PP, CT, who, 'data/clean_..._pools.mat')`) and also compares model tags; `train_dqn.m` (clean validation pools), `evaluate_policies.m` and `edge_map.m` (clean test pools) call it. `rekey_pools.m` moves a clean pool's det_id with the policy pools' when it re-keys a fusion, and knows `cfg_gain_db` as fusion-independent.

**Tests.** test_clean_pool_identity (the checks, the callers, the re-key of a clean pool of the same pools and not of another).

## C9: staleness and identity of the KPI inputs (E-F3)

**Decision.**
- `measure_latency.m` times the deployed chain (`policy_setup.m` of `Q.deployed`: the DQN with escalation, or the rule with escalation on rule_sel's monitor) beside the DQN and the rule chains; LAT stores `deployed`, `total_dep_*`, the detector's `det_id` and the deployed policy's `policy_stamp` (`policy_stamp.m`: SHA-256 of the deployed kind, both monitors, the agent's weights and the pools' det_id).
- `result_status.m` (new): latency.mat (det_id, stamp, newer than trained_dqn.mat), policy_evaluation.mat (stamp, newer than trained_dqn.mat), edge_map.mat (det_id, stamp, newer than policy_evaluation.mat), phy_validation.txt (newer than params.mat), eval_detector_metrics.mat (newer than the detector's training); a file without the identity fields counts as stale.
- `measure_all_kpis.m`: KPI 7 grades the deployed chain's latency and is PENDING without results/latency.mat or with a latency of another detector or deployed policy (before: NOT MET, or graded on whatever latency.mat was on disk); KPI 3 STALE against params.mat (before: never); KPI 6 STALE when its Eb/N0 threshold is not the current KPI 1 threshold; KPI 4-8 STALE also on another stamp; the edge map's detail lines are prefixed [STALE edge map: why] when it is stale.
- `export_report_numbers.m` records `N.stale` (every stale file and a KPI summary older than a file it reads) and warns; `export_gui_bundle.m` refuses to export a stale latency, evaluation, KPI summary or edge map (warns).
- `evaluate_policies.m` stores `KP.det_id` and `KP.policy_stamp`; `edge_map.m` stores `EM/EDGE_NUM.det_id`, `policy_stamp` and the monitor it ran.

**Tests.** test_result_status (fresh vs stale latency, evaluation and edge map; a stamp per policy, monitor and weights; KPI 7 PENDING and the deployed chain in the sources).

## C10: the overhead pass is a ramp (E-F4)

**Why.** The overhead verdict read the path_loss commitment of the step pools at the pass's drop. A pass is a ramp: at the 20 ms decision period the monitor's drop statistic (10-cycle reference median minus 3-cycle median) reads about 4.5 times the per-cycle change, so a slow pass may never reach the drop alarm's threshold, while the step pools' commitment assumes the alarm.

**Decision.** `overhead_pass.m` computes per altitude, distance and speed band the largest drop the monitor reads along the pass (`monitor_window_drop.m`, the monitor's statistic on a level sequence after a steady cruise; the pass flown from the cruise point over the GCS and out), the smallest over the band's speeds (every 2 km/h, both ends: the read drop is not monotonic in speed, a fast pass crosses the narrow null overhead within fewer cycles than the 3-cycle median), the wings-level pass and the banked pass at every fixed bearing: `OHP.win_drop_db`, the drop every flight of the band reads. `edge_map.m` / `overhead_verdict.m`: a bound (tracked: + the mean pointing loss; tracker lost: + the omni fallback, a step read in full, so max(read ramp, fallback)) reads the commitment at the smallest level at or above its drop only where the read drop reaches the deployed threshold; elsewhere the policy sees no drop and the link is as without a response: the no-response PROT at that level, COMMITTED when it is, else UNDETERMINED (never NOT COMMITTED on that path: the degradation alarm may still act). COMMITTED when both bounds are, NOT COMMITTED when the tracked bound's commitment is not. The verdict is now altitude x distance x band; the summary prints one letter per band.

**Tests.** test_overhead_monitor_drop (monitor_window_drop equals the real monitor's largest drop on a step, a ramp and a dip; a step reads in full, a ramp 4.5 s per cycle, a 2-cycle dip reads and a 1-cycle dip does not; every verdict branch; overhead_drop_db's profile agrees with its drop).

## C11: KPI 6 over every independent clean flight (E-F6)

**Decision.** `evaluate_policies.m` adds a 'clean2' set, one episode per clean flight of the second test split (84 per Eb/N0 at the full run), and KPI 6 pools the test split's, the second test split's and data/clean_test_pools.mat's clean episodes (the edge map's union, 396 per Eb/N0); `KP.far_src` names the sources and the threshold's origin; a missing KPI 1 threshold or missing clean pools warns (`evaluate_policies:kpi1`, `evaluate_policies:cleanpools`), and `KP.far_cleanpools` is empty instead of silently holding the test pools' reading.

## C12: KPI 4 and KPI 7 with their intervals (E-F7)

**Decision.** `evaluate_policies.m` stores the deployed policy's per-threat rate with its 95% bootstrap interval over flight geometries (`KP.per_threat_ci`, every level; `KP.per_threat_env_ci`, inside the envelope) and the spread over the speed bands with its interval (`KP.speed_spread`, `spread_boot.m`: the clusters resampled, the spread recomputed); `measure_all_kpis.m` prints them and lists the threats with no level inside the envelope (left out of KPI 4's reading inside it; their every-level rate is printed beside).

**Tests.** test_kpi6_union_and_intervals.

## C13: main.m runs every stage (E-F8)

**Decision.** `main.m` gains the flags and calls of B2F, B3n (FRESH_TEST), B3 on both test sets (DET_TEST, as run_stage.m), C2u, OHP, GCSA, EDGE, WEAK and RPT, in run_stage.m's order; the new stages run in a workspace of their own (`run_own`: edge_map.m's own `RUN` would overwrite main's flags). The dependencies header lists them.

**Tests.** test_main_stage_list (every script of run_stage.m's map appears in main.m).

## C14: the hover label and the table's fairness (L-F9)

**Decision.** `edge_map.m`'s hover label is built from the attitude the hover flights fly (`hover_attitude.m`): roll -17.5..19.3 deg and pitch -11.0..14.9 deg (Polle et al.) and a pitch wobble up to 10 deg at 5-25 Hz (Banagar & Dhillon), not "calm air, within +-1 deg".

**Fairness note (table baseline).** The class -> configuration table (`policy_table.m`, `table_action` in policy_decide.m) reads the detected class and the degradation flag only; it never reads the drop alarm, so a path-loss step that the fusion window has passed (labelled clean, D83) is answered by the table only through degradation, while the rule and the DQN see the drop. Its path-loss recovery is a lower reading of a class-only policy, not of the information the system has; the comparison of KPI 5 is against the rule with escalation, which reads the drop.

**Tests.** test_hover_label.

## Results

### Clean-flight false alarms before and after C1 and C2

`fa_measure.m` (scratchpad), the same data with the code of a66ebb9 (before) and of d84-dec (after).

**A. v6 clean validation pools** (100 geometries x 6 Eb/N0 = 600 flights, every start frame: 12 600 episodes of 30 cycles; pre-D83 receiver, so indicative; the drop path isolated: class none, not degraded, the frames' sinr and iot; rule + escalation; v6 train-pool threshold T = 5.5 dB, the v6 DQN deployed at T - 2 = 3.5 dB with 3/3):

Clean episodes with a configuration change, % (A1):

| drop threshold | code | 2/2 | 3/3 | 4/5 | 5/5 |
|---|---|---|---|---|---|
| T - 2 = 3.5 dB | before (a66ebb9) | 11.99 | 4.98 | 2.90 | 0.98 |
| T - 2 = 3.5 dB | after (d84-dec) | 11.98 | 4.51 | 2.73 | 0.90 |
| T = 5.5 dB | before | 1.22 | 0.41 | 0.34 | 0.02 |
| T = 5.5 dB | after | 1.07 | 0.25 | 0.21 | 0.02 |

C2 is the T row: the grid now offers it to validation (the v6 DQN was deployed at T - 2 with 3/3: 4.98% of the clean episodes changed on the drop path alone, 0.41% at T). The before code reproduces the review's drop-path simulation (rv_b.m, 3.5 and 5.5 dB rows) to the last digit. The small drop after the change is C1's rule: its proposal now follows the measured drop (power_control up to 6.00 dB in v6, rate_reduce up to 6.02, both above), and a drop read on either side of a boundary on two cycles proposes two configurations, which the dwell of two equal proposals does not commit.

A configuration held 12 cycles on a clean flight and released (A2, 600 flights, the v6 DQN's 3/3; the known gain against the measured shift of the Eb/N0 estimate on the same frames shows the gains are right):

| configuration | known gain | measured shift, median [p5, p95] | drop | before: drop alarm / confirmed after the release | after |
|---|---|---|---|---|---|
| power_control | 6.00 dB (v6 radio) | 5.99 [5.83, 6.06] | 3.5 dB | 97.5% / 95.0% | 7.7% / 1.8% |
| power_control | | | 5.5 dB | 68.0% / 52.5% | 0.7% / 0.2% |
| rate_reduce | 6.02 dB | 6.02 [5.85, 6.09] | 3.5 dB | 97.5% / 95.0% | 7.7% / 1.8% |
| rate_reduce | | | 5.5 dB | 68.7% / 53.5% | 0.7% / 0.2% |
| rate_reduce+power_control | 12.02 dB | 12.01 [11.32, 12.12] | 3.5 dB | 100% / 100% | 7.2% / 1.8% |
| rate_reduce+power_control | | | 5.5 dB | 100% / 100% | 0.8% / 0.2% |

After C1 what is left is the clean link's own fluctuation over the 8 cycles after the release, the same at every configuration.

**B. D83 smoke pools** (40 clean flights x 20 start frames; the full features and the detector; closed loop):

| reading | before | after |
|---|---|---|
| B1 rule + escalation, clean episodes with a change at drop 3 / 4 / 5 dB (T = 5 dB smoke) | 157 / 124 / 105 of 800 | 157 / 124 / 105 of 800 |
| B1 DQN + escalation (the smoke agent) | 85 / 82 / 81 of 800 | 85 / 82 / 81 of 800 |
| B2 rule + escalation, 88 validation episodes: drop-alarm cycles, changes, restored cycles after the onset | 681, 159, 38.4% | 886, 153, 42.4% |
| B2 DQN + escalation: drop-alarm cycles, changes (releases), restored cycles | 773, 238 (29), 38.5% | 854, 241 (24), 39.0% |

The smoke detector's class false alarms dominate its clean flights (the same before and after: no first change there came from a drop). On the threat episodes the compensated drop stays an alarm for as long as the loss lasts (more drop-alarm cycles, by design: a step stays an alarm until the link comes back), and the rule's link-budget answer restores more cycles (38.4 -> 42.4%). Small samples (the smoke's 2 geometries per split): a chain check, not a result.

### Smoke chain

Scratch copy `d84_dec_run` (tar of the worktree without .git) on the D83 smoke data, single process: `run_stage('smoke','C1p','C1c','C1d','C2','C2e','C2g','C2u','OHP','GCSA','EDGE','LAT','KPI','DASH','WEAK','RPT')`, exit 0 (C1p 178.5 min, C1c 19.0 min, the rest under 2 min each); after the C10 speed-grid fix, OHP, EDGE, KPI, DASH, WEAK and RPT again, exit 0. C1p ran from scratch because the rate_reduce referral changes the pools.

- *Pools (C1p).* `PP.cfg_gain_db` = 6.02 / 4.00 / 10.02 dB for rate_reduce / power_control / both. rate_reduce minus no_action on the same frames (delay line, real receiver): clean rssi +0.06, sinr +5.44, iot +0.41 dB; jamming rssi -0.08, sinr +5.00, iot +0.14 dB; power_control, a real power change, rssi +3.09 dB clean.
- *C1c.* Both clean pools rebuilt (the up-to-date check now wants `cov` and `det_id`), with `CT.seed`, `CT.cov`, `CT.det_id`, `CT.model_tag`; train_dqn.m, evaluate_policies.m and edge_map.m accepted them.
- *C2.* The grid ran the train-pool threshold 5.0 dB and 3.0 dB (smoke: one monitor, one seed); validation selected 5.0 dB (the DQN's false alarms tie at 1/8; the rule's 12.5% at 5.0 dB against 25.0% at 3.0 dB).
- *C2e.* KPI 6 pooled 2 test-split + 4 second-test-split + 4 clean-pool geometries per Eb/N0 (20 episodes in the smoke), with the warning `evaluate_policies:kpi1` (the smoke detector has no KPI 1 threshold); per-threat intervals and the speed spread with its interval (12.6 points [0.0, 36.4]) in the report; the five smoke threats listed as outside the envelope.
- *OHP / EDGE.* The read drop is far below the pass drop at most points (at 120 m: 0.1-1.1 dB read against 12.9-26.9 dB passes) and is not monotonic in speed (a fast pass crosses the narrow null overhead within fewer cycles than the 3-cycle median), which is why the band reads the smallest over its speeds; every smoke overhead point is UNDETERMINED (the smoke commits nothing: its false-alarm bound is not met).
- *LAT / KPI.* The deployed chain (dqn_esc) timed at 4.42 / 5.27 ms (median / p95), with det_id and stamp; KPI 7 graded on it, not STALE; KPI 3 STALE because the scratch copy's params.mat is newer than the copied phy report (the check working as designed); RPT's `N.stale` lists only that file.
- *Tests.* `code/tests/test_core.m`, 100 tests, all pass on the committed code (scratch copy of HEAD).

## Open risks

1. *The spoofer under rate_reduce (C1/L-F3).* rate_reduce now gains its processing gain against the spoofer too (a counterfeit that does not follow our protocol, D74). A protocol-aware spoofer that copied our spreading would keep its SIR; that attack stays outside the commitment as D74 states, but the change raises recovery of spoofing cells under rate_reduce configurations against v7. If the main session prefers the coherent case, restore 'spoofing' in the exclusion of apply_countermeasure.m's rate_reduce case: the chip-level referral then leaves the spoofer 6 dB high in rssi and the image (the receiver cannot separate it).
2. *The referral is decision-directed (L-F3).* It scales the receiver's own estimate of our signal (one gain per 32-sample block): on the flat link rssi and the image match no_action within 0.1 dB, on the delay line within 0.3 dB (multipath beyond the block fit stays unscaled), with a 10 dB jammer that breaks the receiver within 0.3 dB (rr_diag.m in the scratchpad). gain_ant under a failed receiver tracks the jammer and reads 5 dB low after the referral; every reader uses it relative between antennas, where a common shift cancels. The AGC/ADC front end still sees the despread-equivalent level (6 dB more of our signal before the ADC): not referred.
3. *Link-budget answer (C1).* The rule now picks the smallest gain covering a measured drop; a drop read low picks too little, and the rule upgrades on later confirmed cycles (the compensated drop persists while the loss does) at the cost of dwell and hold cycles. Its effect on the rule's and the DQN's path-loss recovery is read only at C2/C2e; the smoke's validation episodes gained restored cycles (38.4 -> 42.4%), small sample.
4. *Cost.* C2 trains twice the runs (DROP_STEPS [0 2]); C2e adds the second test split's clean episodes for every policy; the overhead pass computes about 15 speeds x 73 profiles per point (under a minute).
5. *C10 is conservative by construction.* A band's read drop is the smallest over its speeds (every 2 km/h; 0 km/h in the first band: never read), wings level and every fixed bearing, while its drop is the largest (the worst bearing at the band's largest bank): a band commits only when every flight reads the drop, and an unread band reads the no-response PROT at the worst drop. Pairing every flight's read drop with its own drop would be finer. The tracked bound's pointing loss has no measured time profile and is not counted toward the read drop. With the smoke numbers almost every pass is UNDETERMINED: the full run will show how many points the overhead pass still commits.
6. *Staleness checks bite.* KPI 3 reads STALE whenever params.mat is newer than results/phy_validation.txt (A0 rewrites params.mat even unchanged), so the launcher must run A4v after A0; KPI 7 is PENDING until LAT has run on the deployed policy; a re-key of the fusion must re-key the clean pools in the same call (rekey_pools.m's default order does).
7. *pool_seed's range.* The plan asked r <= 99; the clean pools' hundredth geometry of each family uses r = 100 (collision-free, already tested), so the assert allows 1-100. Pools built before C4 lack CT.cov: the edge map re-derives their draws with the correct mapping.
8. *Pools built before C1* lack PP.cfg_gain_db: the monitor then derives the gains from params.mat of the working folder (cached); a params.mat with another power step than the pools' would mismatch. Every stage from C1p reruns after the merge anyway (det_id and the rate_reduce referral change the pools).

## Merge notes (files other groups may also touch)

- `code/link/extract_closed_loop_frames.m` (group A's A9 calibration error and A5 may touch the same loop): one block in the per-antenna loop (`gp`, `chip_field`: rs recomputed on the chip-rate field after the residual metrics), `F.gain_ant - gp` after it, the local function `chip_field`, and a header paragraph. A calibration error on the reported level belongs after the referral (it applies to the reported rssi), and the thermal-floor estimate it perturbs is not used by the referral.
- `code/link/apply_countermeasure.m`: the rate_reduce case only (`p.proc_gain_db`, 'spoofing' no longer excluded) and its header lines; no configuration gain changed.
- `code/decision/build_policy_pools.m`, `build_check_pools.m`: one field, `cfg_gain_db`, in the PP / CK struct literals (A4/A5 add fields to the same literals and to pool_cell.m, which C does not touch).
- `code/decision/rekey_pools.m`: `cfg_gain_db` added to KNOWN; any field A or B adds to PP or to the frames must be added to KNOWN / FRAME as well.
- `code/evaluation/measure_all_kpis.m` (group B's B4 reading beside KPI 1): C edits the header, the top (result_status) and the KPI 3-8 and edge blocks, not the KPI 1 block.
- `code/evaluation/edge_map.m`: det_frames, surv_layer moved to their own files (unchanged logic plus C3/C5); the overhead section, the monitor, the clean flights' draws, the hover label, the identity fields.
- `code/tests/test_core.m`: 17 tests appended at the end of the file (after the helpers); other groups' appended tests merge beside them.
- `code/main.m`: CFG.drop_steps, the new RUN flags and calls, the `run_own` helper.
- No edit to `build_threat_model.m`, `init_params.m`, `pool_cell.m`, `threat_active.m` or the detector files.
