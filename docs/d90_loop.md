# d90: the fixes before C1d, C2 and the KPI readings (branch d90-loop)

Branch `d90-loop` from `9b5c9f1`, the code of the running full run (v7-merge with d87, d88 and
d89). It implements the remaining confirmed findings:
- the audit plan (`audit1_plan.md`, findings in `audit1_confirmed.json`): section 1.4 SWEEP and
  DROP, 1.5 the C2 items and 1.6 the KPI reporting;
- section 1.3 FUSE, as candidates only (section 1): the detector stays as it is, per Adi's
  decision of 2026-10-17;
- the d88 review (`rev88_confirmed.json`): data-01, data-02, data-03, dec-05 and dec-06;
- dec-04: C2 chooses the rule's nulling threshold, its quiet-slot branch, and the unknown-threat
  flag's retention and override on validation. They are stored with the agent and read by
  every reader.

Items already done before this branch are not repeated: the latch choice (d87), align (d88),
the MMSE predictor (d88, d89), maha_thr out of detector_id (d88) and the architecture
comparison (d88).

**What was read.** Every choice below is made on validation. No test split, second test set or
third test set was read here. The FUSE numbers were measured on read-only copies of both
profiles' validation outputs (`data/fusion.mat`, the validation split of `data/splits.mat`, the
per-cycle labels of `data/dataset.mat`, read by HDF5). Every other number is either a smoke
figure (not a result) or the audit's earlier reading, and is labelled as such. The profiles
measure their own at C1d and C2, where both readings are printed side by side.

## Summary

| Item | Findings | Code | Acts in | Must land before |
|---|---|---|---|---|
| 1 FUSE | sel-03, lit-4(3), lit-2, lit-3 | `select_fusion.m` behind `FUSION_REV` (off; bit-identical when off), `fusion_target.m`, `window_cues.m`, `fuse_classes.m` and every fusion reader | nothing while off | candidates only (section 1) |
| 2 SWEEP | out-sweeper-confirm, loop-monitor-grid, lit-1 | `policy_monitor.m`, `decision_config.m` `confirm_sweep`, `choose_drop_threshold.m`, `eval_detector.m` | C1d (adoption), every monitor | C1d |
| 3 DROP | loop-drop-budget, loop-drop-reference | `choose_drop_threshold.m` (whole monitor per m/n), `monitor_trace.m`, `monitor_confirm.m`, `drop_alarm_seq.m`, `drop_alarm_any.m`, `policy_monitor.m`, `monitor_window_drop.m`, `train_dqn.m` | C1d, C2, OHP, EDGE | C1d |
| 4 C2 | loop-reward-plr, loop-select-held, sel-06, sel-07, sel-02, sel-08, dec-04, loop-rule-dwell, loop-esc-none | `link_env.m`, `train_dqn.m`, `dqn_train_run.m`, `dqn_held.m`, `choose_deployed.m`, `policy_decide.m`, `rule_based_policy.m`, `policy_monitor.m`, `decision_settings.m` and every reader | C2 and every later stage | C2 (in practice C1d: same merge) |
| 5 KPI | loop-kpi-unharmed, loop-release (1), out-fusion-gap (3) | `evaluate_policies.m`, `measure_all_kpis.m`, `edge_map.m`, `link_env.m`, `rollout_policy.m` | C2e, EDGE, KPI | C2e |
| 6 rev88 | data-01, data-02, data-03, dec-05, dec-06 | `extract_spectrograms.m`, `prepare_data.m`, `kpi1_file.m`, dashboard, GUI, bundle, weak points, `edge_map.m`, `demo_gui.m`, `v3d_engine.m`, `compare_architectures.m` | A6/B1, B3a, EDGE, DASH, WEAK, GUI | C1d (no stage before it reads them) |

**Not done here:**
- a printed KPI 1 reading with the unknown-threat override (sel-02 item 4; section 6 says why);
- the detector's offset sub-runs: the plan places them after the run.

## 1. FUSE: candidates for a later campaign (not deployed)

**Scope.** Adi decided on 2026-10-17 that the detector stays as it is for now: every class's F1
is at least 85%, and he decides on more changes after the full results. The four FUSE items
(sel-03, lit-4(3), lit-2, lit-3) are therefore evaluated on validation, with nested
cross-validation, and written here as candidates. The deployed fusion, the layout of
`fusion.mat` and the detector's reading do not change, and the closed loop is not affected.

### Where the code is, and why it changes nothing while off

The candidates sit behind one switch, `FUSION_REV` in `select_fusion.m` (B2F). It is off by
default, and nothing in the pipeline sets it. With the switch off:
- **`select_fusion.m`** selects, fits and saves exactly as `9b5c9f1` does, with the same
  `fusion.mat` variables. Only the log adds each candidate's score on the per-cycle label and
  the relabelled frames per kind.
- **`fusion_target.m`**: a fusion without `FM.target_age` keeps its rule, `pos - onset < N`.
- **`fuse_classes('windows', ..., fuse_classes('cues', FM))`**: a fusion without `FM.cues` adds no
  column. So `policy_monitor.m`, `fused_class.m`, `det_frames.m`, `eval_detector.m` and
  `compare_architectures.m` build the same row as before.

**Bit-identity check.** BITID_PLACEHOLDER

### What the switch would do

1. **lit-4(3), the path-loss target.** The target ends at `pos - onset < N - 1`, threat_active.m's
   rule: the window must still hold a cycle before the step. The rule is stored as
   `FM.target_age`, and every reader passes the fusion (`eval_detector.m`,
   `compare_architectures.m`, `detector_block.m`).
2. **sel-03, the window N.**
   - Each candidate is fitted on its own window's targets, as now.
   - It is scored on the frames whose target no candidate's window changes, where all
     candidates share the per-cycle label.
   - Of the candidates within one standard error (over the 5 folds) of the best, the shortest
     is taken. This is the one-standard-error rule (Hastie, Tibshirani and Friedman, *The
     Elements of Statistical Learning*, 2nd ed., sec. 7.10). The book is not in the source
     library.
3. **lit-2 and lit-3, the further columns.** They come from `window_cues('extra')`, and
   `fuse_classes` puts them last in the row. Each is chosen against the fusion without it, out
   of fold, paired by bootstrap over sub-runs:
   - **cfar:** four columns from each idle gap's crest (max - p10) and spread (p90 - p10) over
     the gap's own floor. T1 and T2 are the smallest values at most 1% of the training folds'
     clean gaps exceed (nearest rank); m0 is their median crest. Sources: Grimaldi, Mahmood and
     Gidlund 2019 (a threshold on the radio's own noise, the crest factor) and Kazim et al.
     2026, eq. 1.3. **Adopted when:**
     - every frame's macro-F1 gains (lower bound > 0);
     - the reading above the KPI 1 threshold loses nothing (lower bound >= -0.1 point);
     - clean frames read as a threat do not rise (lower bound <= 0).
   - **iso:** four columns from the branch whose own offset steps (detection-isolation, Xie et
     al. 2021, Sec. III-I). They are added beside the weakest-by-mean cues, which stay: replacing
     those cost 0.3 points and shadowing recall. **Adopted when:**
     - every frame's macro-F1 gains (lower bound > 0);
     - clean frames read as a lost branch do not rise;
     - shadowing recall, overall and at K < 0 dB, does not fall.
   - **Both:** adopted when both rules hold together. Otherwise the single adopted variant with
     the larger gain is kept.

### Measured on both profiles' validation

**Setup.** The measurements ran on read-only copies of each profile's `data/fusion.mat`, the
validation split of `data/splits.mat`, and the per-cycle labels of `data/dataset.mat`. The setup
reproduces the deployed fusion exactly:
- the folds use seed 61;
- the refit's out-of-fold probabilities equal `val_probs_oof` (largest difference 0);
- the targets equal `val_target`.

The scripts are in the scratchpad: `d90/fuse/fuse_val.m` and `n_common.m`, with outputs
`fuse_p1.txt`, `fuse_p3.txt`, `ncommon_p1.txt` and `ncommon_p3.txt`.

**sel-03, the window N.** Lambda 1e-3 is best throughout; macro-F1 is out of fold.

| | Profile 1 | Profile 3 |
|---|---|---|
| Deployed: own targets, N 1-12 | N 12, 93.43% | N 12, 93.01% |
| Own targets, grid extended to 16 | N 16, 93.96% | N 16, 93.42% |
| Frames no candidate relabels (N 1-16) | 19,706 of 20,328 | 19,684 of 20,328 |
| On those frames, N 1 / 3 / 5 / 8 / 12 / 16 | 90.77 / 92.65 / 92.93 / 93.34 / **93.92** / 93.96 | 91.03 / 92.64 / 92.75 / 92.92 / **93.52** / 93.45 |
| The same with the N - 1 target, N 12 / 16 | 94.02 / 93.97 | 93.52 / 93.54 |
| One-standard-error pick (grid 1-12 or 1-16, either target) | **N 12** | **N 12** |
| Biased: per-cycle label of every frame, best | N 8, 93.06% | N 8, 92.79% |

The finding was right that the own-target score is biased: a longer window gains on the very
frames it relabels, which is why the grid extended to 16 picks N 16. But scoring every frame on
the per-cycle label is biased the other way. It penalizes a long window on the same frames,
which it was fitted to call by its window, and that is why it suggested N 8 (P1) or N 5 (P3).
On the frames no candidate relabels, the comparison is neutral. There the best window and the
shortest within one standard error is **N 12 on both profiles**, the deployed value.

**Candidate status (sel-03): nothing to change.** The deployed N is the corrected rule's pick.

**lit-4(3), the path-loss target** (N 12, lambda 1e-3):

| | Profile 1 | Profile 3 |
|---|---|---|
| Path-loss recall at onset age N - 1 = 11, old target | 13.0% (92 frames) | 8.4% (95 frames) |
| Macro-F1 on the new target: old fit / new fit | 93.71 / 93.96% | 93.34 / 93.47% |
| On the per-cycle label: old / new | 92.71 / 92.97% | 92.48 / 92.61% |
| On the frames no candidate relabels: old / new | 93.92 / 94.02% | 93.52 / 93.52% |

At age 11 the window holds no cycle before the step, so the old target asks for a step the
window cannot see; this reproduces the verifier's diagnosis on the repaired data. The gain is
small: +0.1 to +0.26 points on P1 and 0 to +0.13 on P3.

**Candidate status (lit-4(3)): physically correct, small gain.** It changes the detector, so
KPI 1 must be read again (see the note below).

**lit-2 and lit-3, the further columns** (N 12, lambda 1e-3, old target). The table is the
paired bootstrap over sub-runs, 1,000 resamples, in macro-F1 points:

| Variant | P1 all frames | P1 above the KPI 1 threshold (0 dB) | P3 all frames | P3 above the KPI 1 threshold (3 dB) |
|---|---|---|---|---|
| cfar | +0.19 [+0.02, +0.38] | +0.19 [+0.03, +0.38] | +0.25 [+0.07, +0.49] | +0.09 [-0.02, +0.22] |
| iso | +0.19 [+0.02, +0.37] | +0.18 [+0.01, +0.36] | +0.15 [-0.08, +0.43] | +0.17 [-0.06, +0.48] |
| both | +0.35 [+0.12, +0.61] | +0.35 [+0.11, +0.61] | +0.39 [+0.08, +0.74] | +0.24 [-0.02, +0.57] |

Further readings:
- **Weak WLAN** (level <= -8 dB, Eb/N0 0-3 dB): cfar lifts recall from 17.1% to 38.2% (P1) and
  from 15.3% to 49.2% (P3). Clean frames read as WLAN fall from 0.21% to 0.11% (P1) and from
  0.18% to 0.10% (P3).
- **Clean frames read as any threat:** unchanged within the intervals.
- **cfar thresholds** (training folds): T1 about 1.41-1.47 dB, T2 1.0 dB, m0 1.0 dB.
- **Adoption on the out-of-fold reading:**
  - P1: cfar yes and iso yes, but not both together (clean frames read as a lost branch rise
    by 0.02 points, by the point rule);
  - P3: cfar only.

**Nested cross-validation of the adoption procedure.** Each outer fold decides the variants on
inner out-of-fold readings of its four training folds, then predicts the held-out fold. The
table gives the gain against the deployed out-of-fold reading, in points:

| | All frames | Above the KPI 1 threshold | Clean frames read as a threat |
|---|---|---|---|
| Profile 1 | +0.05 [-0.03, +0.13] | +0.05 [-0.03, +0.13] | -0.10 [-0.27, +0.02] |
| Profile 3 | +0.18 [+0.03, +0.38] | +0.04 [+0.00, +0.08] | -0.03 [-0.13, +0.05] |

The inner decisions vary from fold to fold:
- P1 picks cfar in 2 of 5 folds and none in 3;
- P3 picks none in 3 and cfar in 2.

**Candidate status:**
- **lit-2 (cfar)** is the strongest candidate. Its out-of-fold gain is clear on both profiles,
  and weak-WLAN recall more than doubles. But the procedure's nested gain on the KPI 1 reading
  is not clear: +0.05 points on P1 and +0.04 on P3.
- **lit-3 (iso)** gains on P1 only, and the nested procedure rarely keeps it.

### Ready-to-merge note (for a later campaign)

The code is already merged in this branch and stays off. To turn the candidates on, apply the
same steps in all three profiles, so the antenna-count comparison stays like for like:
1. **Turn the switch on.** In `run_stage.m` `run_one`, add a branch before the generic `run`:
   `elseif strcmp(name, 'select_fusion'), FUSION_REV = true; run(name);`. To take lit-4(3) and
   the further columns but keep N fixed at 12, nothing else is needed: the rule picks 12 here.
   To drop the one-standard-error step, take the best on the common frames, which is also N 12.
2. **Rerun the detector's stages.** Rerun B2F, then B3, B3a, B4 and B4s. They read the fusion
   through `fused_class.m`, `detector_block.m` and `compare_architectures.m`, which
   already pass `FM.cues` and `FM.target_age`.
3. **Read KPI 1 on a new test set.** B3m (the third test set) has already been read, so KPI 1 of
   the new fusion must be read on a test set built after the change: a fourth set, built as B3m
   was.
4. **Re-key the pools.** Run `rekey_pools` (no rebuild). The pools hold per-frame outputs, and the
   cfar and iso columns read the pools' `idle` and `gant` frames (`pool_cell.m`). The re-key
   changes `PP.fuse`, `fuse_N`, `q_thr` and `det_id`, so every closed-loop result from C1d on
   must be rerun.
5. **Add the source.** Put *The Elements of Statistical Learning* in the source library, or leave
   out the one-standard-error step.
6. **Tests.** The candidates are already covered by `test_window_cues_extra` (the cfar and iso
   columns, the monitor's row equal to `fuse_classes`, a fusion without cues keeping its row)
   and `test_fusion_target_age` (both target rules, the common-frames scoring, the switch-off
   layout).

## 2. SWEEP: the sweeping jammer's own confirmation

The sweep revisits our channel once per period, up to 83.5 ms (Liu et al.'s sweep rate over the
2.4 GHz band, `init_params.m`). With 20 ms cycles, two passes lie at most ceil(83.5/20) = 5 cycles
apart. A sweeper read therefore falls on isolated cycles, which every m-of-n of C2's grid needs
near-consecutive.

**Code.** `decision_config.m` sets `C.confirm_sweep = [2 6]`. With `PP.confirm_sweep` set,
`policy_monitor.m` ORs a second path into the m-of-n: two sweeping_jammer reads within the last 6
cycles confirm the alarm. This is the k-out-of-n detector Norouzi et al. 2006 name for a swept
jammer (library: `V7_Norouzi2006_K_out_of_N_Detector_EUSIPCO.pdf`).
- The path is the same under every monitor of the grid, so C2 needs no extra rows.
- It is kept off `confirm_alarm.m` (the drop alarm's).
- `eval_detector.m`'s onset-latency line prints the class path with and without it, and states
  that the degradation and drop paths are not read there.

**Adoption (C1d, `choose_drop_threshold.m` section 5).** The monitor runs at no_action over the
clean validation episodes and every single threat of the validation split (section 3). The path
is adopted when, with every monitor at its own drop threshold:
- no monitor loses an admissible threshold or needs a less sensitive one, and
- no threat's never-confirmed share or 90th-percentile delay grows.
Both readings are printed and the choice is saved (`data/drop_threshold.mat` `confirm_sweep`).
C2 sets it for every run, and every reader then takes it from the agent's settings.

Because the path is ORed, it can only add confirmations. Its only possible cost is extra
confirmations on clean flights or other classes. The audit's verifiers measured it on profile
1's earlier detector, validation out of fold (368 sweeper sub-runs of 21 cycles, class path):
- **2/2:** never confirmed 10.9-11.1% -> 0%; median 3 -> 2 cycles; p90 11 -> 4 cycles; damaged
  frames before the confirmation 0.86 -> 0.40 per sub-run.
- **3/3, 4/5 and 5/5:** never confirmed 66.8%, 60.6% and 76.6% on the class path alone; the path
  works the same under them.
- **Other classes:** unchanged. Clean sub-runs with a confirmed alarm stay 6 of 48, WLAN sub-runs
  9 of 80. The class reads the sweeper on 0 of 1,008 clean cycles.

The deployed monitor also alarms on degradation (the 5-frame BER window), which already confirms
most sub-runs whose frames are hit (the verifier: never 7.1% at 2/2, 15.5-20.1% at the other
three). So on the whole monitor the path's gain is the earlier response, and it guards the
stricter m/n entries, which C2's false-alarm bound may favour.
The profiles' own numbers are printed at C1d.

**Tests.** `test_sweeper_confirmation`: a 1-0-1-0 sweeper sequence confirms on its second read
under 2/2 and 3/3 with the path, and never without it; a clean sequence and another class's
isolated reads stay unconfirmed. The adoption's arithmetic is covered by `test_drop_whole_monitor`.

## 3. DROP: the drop threshold on the whole monitor, the median window's held reference

### Each monitor's threshold on the whole monitor (loop-drop-budget)

A policy changes the configuration only on a confirmed alarm (`policy_mask.m`). So up to its
first change, every policy flies the no_action episode with the same frame draws. The share of
clean episodes whose no_action monitor confirms an alarm is therefore an exact upper bound on
every policy's false-alarm share on those same episodes.

`choose_drop_threshold.m` (C1d) gains a section 5:
- `monitor_trace.m` runs the monitor once at no_action, with batch b at seed 41000 + b as
  `rollout_policy.m` does, over:
  - the clean validation episodes `train_dqn.m` reads its false alarms on (`clean_wide_specs.m`,
    shared with `train_dqn.m` through `clean_world.m`);
  - every single threat of the validation split.
- Per cycle it records the alarm without the drop (a hostile class except path_loss, or
  degradation), the sweeper reads, and the compensated Eb/N0 estimate.
- `monitor_confirm.m` rebuilds, per monitor m/n of C2's grid (`C.monitors`) and per threshold of
  the chosen form, the drop alarm with its reference free of every alarm cycle
  (`drop_alarm_seq.m`'s new `other` mask). It ORs the other paths and confirms the result with
  that m/n.
- Each monitor takes the most sensitive threshold whose one-sided 95% bound is at most 5% (KPI 6).
- When the other paths alone break the bound, the report says that no drop threshold can meet
  KPI 6 with that monitor, and the monitor takes the least sensitive threshold.
- The result is saved as `MONP` in `data/drop_threshold.mat`.

C2 (`train_dqn.m`) tries each monitor at its own threshold and the steps `C.drop_steps = [-2 0 2]`
around it. For the median window these are dB, above the moving-away floor. For the CUSUM they
are one grid step per step's sign. Before, every monitor got the form's threshold alone and two
more sensitive steps. The drop-alone comparison of the two forms is unchanged.

**Tests.** `test_drop_whole_monitor`:
- monitor_confirm on a hand-made trace: other-path alarms, a step at the threshold, 2/2 against
  3/3, and the sweeper path;
- on a toy world, monitor_trace's first confirmation equals `rollout_policy`'s `t_conf` for
  rule + escalation on the same seeds (the exactness argument);
- source checks for C1d and C2.

### The median window's reference held through an excursion (loop-drop-reference)

The median window ('class_drop') now keeps its reference with `drop_ref.m`'s hold-and-release,
as the CUSUM's does (Page's change-point logic, Xie et al. 2021 eq. 3):
- An excursion starts when the median drop reaches half the smallest path-loss level (3 dB).
- Its cycles are held.
- They join the reference if it ends without the drop alarm, and are dropped if it raised the
  alarm.

A step below the threshold is therefore no longer absorbed. The change is applied in
`policy_monitor.m`, `drop_alarm_seq.m`, `drop_alarm_any.m` (the excursion start of both forms)
and `monitor_window_drop.m`, so `overhead_pass.m`'s `win_drop_db` and edge_map's overhead-pass
reading follow it. The verifier's one-sided value guard was not used: it raises the false alarms
(it keeps every low cycle out of the reference for good).

**Tests.** `test_drop_hold_release`:
- a 4 dB step under a 5 dB threshold, then 2 dB more, raises the alarm at the second step (the
  rolling reference would have absorbed the first);
- the monitor equals `drop_alarm_seq.m` with another path's alarm cycles kept out;
- a ramp past the excursion's start reads its whole depth;
- a slow ramp below it reads 0.9 dB as before.
`test_drop_cusum_alarm`, `test_drop_cusum_bounded` and `test_overhead_monitor_drop` pass
unchanged.

## 4. C2: the reward, the selection, the deployment and the rule's settings

### loop-reward-plr

`link_env.m` tables now use KPI 4's test, BER and packet loss together:
- `q = C.q_restored` only when both are restored; otherwise the partial formula, which caps at
  `C.q_partial`.
- `K.healthy` means no_action restores both.
- `K.restored` stays the BER test (the `restored_post` reading).
The tables are built at run time: no pool is touched.

Test `test_reward_needs_plr`: a configuration that restores BER but loses half the packets earns
`q_partial`, and a no_action that loses packets is not healthy.

### loop-select-held

`dqn_held.m` is held recovery among the recoverable threat episodes, the edge map's REC. It now
drives:
- checkpoints: `dqn_train_run.m` scores `dqn_held + 1e-3 return`; the curve keeps both;
- the run selection: the weakest threat's held within 1 point, the pooled held within 0.5, then
  the recovered (KPI 4), then the return;
- the gate: held >= the rule's held at the same monitor and settings;
- the fallback `rule_sel`: the best held.

Every run row and baseline prints held and recovered side by side.

Test `test_held_selection`: a hop-only configuration against a follower at fdelay 5 recovers
(KPI 4) but does not hold; one that escapes it holds.

### sel-06

`choose_deployed.m` takes the DQN's recovery and deploys it only when it passed the gate and
either:
- no rule setting is within the bound, or
- it recovers at least as much as the best admissible rule setting.

Test `test_choose_deployed`: a gate that passed against an admissible rule that recovers more
deploys the rule; `'dqn'` is deployed as `'dqn'`.

### sel-07

**With and without escalation.** Every run is scored with and without the escalation on the same
validation and clean episodes. The selection runs over (run, with or without) pairs, and
`'dqn'` can be deployed. The plumbing:
- `choose_deployed.m` returns `dqn_kind`;
- `evaluate_policies.m` maps `'dqn'` to `dqn_g<sel>`;
- `edge_map.m` (NAMES, the unknown path), `measure_latency.m` (kindD) and the experiments
  (`DK`) run the deployed kind;
- `measure_all_kpis.m`'s KPI 5 compares the deployed DQN.
The checkpoint is still chosen with the escalation (`dqn_train_run.m`), which slightly favours
it; the report says so.

**Coordinate steps after the grid**, at the selected monitor, drop threshold and penalty, with
the same seeds:
- gamma 0 (the bandit), so `evaluate_policies` prints the ablation row;
- running and switching costs x1;
- when the unknown flag's settings moved, their default for the agent;
- the escalation on a drop, scored both ways on the selected agent (no retraining).
The runs are appended and the selection and gate are redone.

**Wording.** `main.m` now calls gamma a fixed setting, with gamma 0 tried as a coordinate step
on validation; the `train_dqn.m` header lists both.

### sel-02, sel-08 and dec-04: the rule's settings and the unknown-threat flag

`decision_settings.m` is the one place every reader applies the agent's settings.
`train_dqn.m` chooses on validation, one coordinate at a time against the setting in force (the
same selection rule), with rule + escalation at the reference monitor (C.confirm 2/2 at its own
drop threshold). The coordinates are:
1. **The nulling threshold on the predicted MMSE gain.** Candidates:
   - mu + 3 sigma and mu + 3 sigma + 2 dB of the clean validation frames' `mmse_pred` at Eb/N0 from
     the KPI 1 threshold up (Kazim et al. 2026 eq. 1.3: a threshold from interference-free
     samples, as q_thr);
   - 3, 6 (the earlier constant, the baseline) and 9 dB.
   Each runs with the quiet-slot branch on and off (`PP.rule_slot`, `rule_based_policy.m`). Only
   the D5 branch is gated; the slot still keeps a drop alarm from the budget answer.
2. **The proposal dwell**, 'run' or 'group' (section loop-rule-dwell).
3. **The unknown flag.** Retention 0.95 or 0.99 of the validation windows
   (`unk_threshold(PP.maha_val, r)`, no re-key), and the override 'all' (as before) or
   'nonhostile' (`PP.unk_mode`, `policy_monitor.m`). In 'nonhostile' only none or
   benign_interference is overridden, so a hostile read keeps its alarm. The agent's state keeps
   the flag either way.
4. **The escalation on a drop alarm**, off or on (section loop-esc-none).

The chosen settings run the baselines of every monitor and the whole grid. They are stored:
- `trained_dqn.mat` `dec`: the deployed DQN's monitor and all settings, with `maha_thr` beside;
- `rule_sel`: carries them too.

Every reader applies them: `policy_decide` (opt.monitor), `policy_monitor`, `evaluate_policies`,
`edge_map` (its check pools: `CK = decision_settings(CK, PP)`), `measure_latency`, the
experiments, the GUI (and its threshold slider's default, the agent's retention) and the 3D
engine. `policy_stamp.m` includes `dec`, so a result of other settings is flagged stale.

Tests: `test_decision_settings`, `test_rule_slot_and_group_dwell`, `test_unknown_override_mode`,
`test_rule_settings_on_validation`.

### loop-rule-dwell

With `PP.rule_dwell = 'group'`, a proposal commits when its group (the threat-specific elements
it holds; link-budget configurations as one group) appears in at least C.dwell of the last
C.dwell_n = 4 cycles (Barajas et al.'s M-of-N), unless:
- the configuration in use already holds its elements and at least its known gain (no regress,
  so there is no ping-pong), or
- the escalation tried it in this incident.

It is chosen on validation in the settings step above. The C.ladder is unchanged.

Test: alternating sweeper and degraded-none cycles. The 'run' dwell never commits; 'group'
commits freq_diversity+power_control once and never returns to freq_diversity.

### loop-esc-none

With `PP.esc_drop`, a confirmed drop alarm read as none escalates in two cases:
- out of no_action, or
- out of a configuration whose known gain no longer covers the drop.
Its first step is the link-budget configuration with the smallest known gain covering the drop,
if untried. A covering configuration stays protected from degraded cycles. It is chosen on
validation in the settings step, and for the DQN at the coordinate step.

Test `test_escalation_on_drop`: escalates to rate_reduce+power_control (gain 9 dB for an 8 dB
drop) with the setting and never without; a covering configuration on degraded cycles is not
left.

## 5. KPI reporting: harmed episodes and threats that end

### loop-kpi-unharmed

`evaluate_policies.m` computes per episode whether no response restores its geometry (no_action
in the tables). On the test sets this equals no response's own recovery, and the report checks
that. Beside KPI 4 it reports:
- the recovery among the harmed recoverable episodes, per threat and severity, with bootstrap
  intervals and counts;
- the envelope on the harmed validation episodes (`ENVv_h`, fixed before the test is read) and
  the test inside it.

`measure_all_kpis.m`:
- prints the harmed reading beside KPI 4 (the proposal's reading and status unchanged);
- reads KPI 8 on the harmed episodes, with every-episode count beside;
- prints the offset summary below.

`edge_map.m` adds:
- REC_h and PROT_h on the harmed flights (tables beside REC and PROT, counts in the summary and
  `EDGE_NUM`; no target of their own);
- the no-response attribution mark n beside r (no response's PROT COMMITTED);
- `commit_not_attributable` now counts both marks, and `commit_no_response` counts n alone.

### loop-release (1) and out-fusion-gap (3): threats that end

`link_env.m` takes `spec.offset` (default Inf, so every earlier reading is unchanged):
- From the offset the episode flies the same flight's clean link at the same frame positions,
  and the follower stops.
- A change to no_action decided on a frame after it is a release: `info.released`, not
  `false_switch`, and no false-switch cost.

`rollout_policy.m` reads, per episode:
- the configuration held when the threat ends;
- the cycles to its release to no_action;
- the running cost held after it (`K.cost`, points per cycle) and the share of those cycles not
  at no_action;
- the decisions with a confirmed alarm after it (re-alarms);
- the changes after it that are no release.

`evaluate_policies.m` runs a new set 'offset', reported apart and never in KPI 4: the single
threats ending 20 cycles after the onset, 50-cycle episodes, test split. It reports these
readings for the deployed policy, rule + escalation and the table. Training is unchanged.

Detector offsets (B3m sub-runs that end) are not in this branch: the plan places them after the
run.

Tests: `test_threat_offset`, `test_harmed_readings`.

## 6. The d88 review's items

- **data-01:** A6 stamps `spec.meta.frames_checked` (and `src_align_gcs`) after its per-frame
  guards. B1 (`prepare_data.m`, both paths) refuses spectrograms without the stamp, and
  spectrograms older than their dataset. Note: a profile that reruns B1 now needs A6 first,
  because the spectrograms built before this branch carry no stamp.
- **data-03:** a dataset in the layout from before align_gcs stops A6 with `extract_spectrograms:align`,
  naming `repair_align` (dry run, then the repair).
- **data-02:** `kpi1_file.m` gives the third test set's reading when it exists. It is used by
  `measure_all_kpis.m`, the dashboard (both panel titles name the test set), the GUI's KPI tab
  (card 1 names it) and `analyze_weak_points.m` (which prints the file). `export_gui_bundle.m`
  copies `eval_detector_metrics_fresh2.mat`.
- **dec-05:** the edge map's check pools, the GUI (with the slider's default at the agent's
  retention) and the 3D engine take the agent's `maha_thr` and settings (section 4).
- **dec-06:** `compare_architectures.m` states the deployed monitor in the validation header and
  above the test table. When the latch is off it labels the latch column 'fused+latch (not
  deployed)'. It latches each validation fold at a threshold chosen on the other folds, as
  `select_fusion.m` does, and keeps the deployed `os_thr` for the test reading only.
- **sel-02 item 4:** `fused_class.m` and `eval_detector.m` now say that KPI 1's class leaves out
  the unknown-threat override the closed loop's monitor applies. A printed reading of KPI 1 with
  the override would need the unknown statistic on every test frame in B3. It is not added here:
  B3m is read by its own copies' code, and the override's effect on the closed loop is chosen on
  validation in C2.

## 7. Cost of the stages that change

**C1d** adds the whole monitor's traces: one no_action pass over the clean validation episodes
(about 3,600 at profile scale) and over every single threat of the validation split. Then
thresholds x monitors x 2 settings of the sweeper path are rebuilt from the traces. Expected
minutes, against under 1 min before.

**C2** grows from 72 runs to 108 (4 monitors x 3 drop thresholds x 3 penalties x 3 seeds),
plus:
- up to 9 coordinate runs;
- every run scored twice (with and without the escalation);
- about 15 rule evaluations of the settings step and the baselines of 12 entries;
- the reward sensitivity's 2 retrainings as before.

At v6's 18-20 min per run, C2 takes about 38-42 h per profile, against 22-24 h. If the time is
needed, `decision_config.m` `C.drop_steps = [-2 0]` (each monitor's threshold and 2 dB less
sensitive, the loop-drop-budget verifier's minimum) brings the grid back to 72 runs, about 26 h.

**C2e** adds the offset set (single threats, 50-cycle episodes, one pass per policy). That is
about the single set's cost again.

**EDGE**, **KPI** and **DASH**: reporting only.

## 8. Tests

TESTS_PLACEHOLDER

## 9. Smoke

SMOKE_PLACEHOLDER

## 10. Deployment into the running profiles

**Nothing of this branch is needed before C1p, C1c, SURV or SURV3.** Those stages call none of
the changed files: `build_policy_pools.m`, `pool_cell.m`, `build_clean_test_pools.m`,
`build_check_pools.m`, `map_survivability_boundary.m` and `experiment_survivability_options.m`
were checked. A merge during them changes nothing that runs.

**No pool is rebuilt or re-keyed:**
- the pools' frames and keys are unchanged (`pool_cell.m` untouched);
- the fusion is not changed (section 1);
- the new settings are applied at decision time from `trained_dqn.mat`.

**`data/fusion.mat` stays.** B3m's reading (the third test set) stays KPI 1's; no fourth test set
is needed.

### Profile 1 (`C:\Users\Adi Suliman\uav-gcs-v7`, v7-dev)

Expected: C1p from about 2026-10-17 23:45, then C1c, SURV, SURV3, C1d about 5 days later.

1. **Merge.** Any time after C1p has started and before C1d starts; the safe window is the whole
   of C1p, C1c, SURV and SURV3 (deadline: C1d, about 2026-10-22). First merge `d90-loop` into
   `v7-merge` (after the main session's review), run the full suite on the merge, then:
   `git -C "C:/Users/Adi Suliman/uav-gcs-v7" merge --no-ff v7-merge` (message ending with the
   Co-Authored-By line). Generated files (`params.mat`, `results/`) are not in the branch.
2. **Check before C1d.** `results/eval_detector_metrics.mat` is newer than `data/fusion.mat` (B3
   ran after B2F; it did on 2026-10-17). `data/clean_val_pools.mat` exists (C1c).
3. **Nothing else.** The chain's C1d runs the new `choose_drop_threshold.m`: each monitor's
   threshold on the whole monitor, and the sweeper path's adoption, printed both ways. C2, C2e,
   C2g, C2u, OHP, EDGE, KPI, DASH, WEAK and RPT follow with the new code.
4. **The launcher's code check.** `uav-gcs-logs/v7_d86/code_commit.txt` SRC must name the merged
   commit for a later `resume` (code_ok compares the profiles' code with SRC). Update it to the
   new v7-merge SHA when the profiles are merged.
5. **Time.** C2 now takes about 38-42 h (section 7), so profile 1 finishes about a day later than
   with the 72-run grid. Decide `C.drop_steps` before C2 starts if that day matters.

### Profile 3 (`C:\Users\Adi Suliman\uav-gcs-v7-p3`, v7-p3)

Expected: A0-B4s now, then waiting for profile 1's SURV3, then C1p (about 4 days), C1c, SURV,
SURV3, C1d.

1. **Merge.** After its B4s has finished (it then waits for profile 1), or at any time during its
   C1p, C1c, SURV or SURV3. Not during B3a, B4 or B4s: they call `compare_architectures.m`,
   `fused_class.m` and `detector_block.m`, which changed. The changes read an old `fusion.mat`
   exactly as before, but a file replaced under a running stage is avoided.
   Deadline: profile 3's C1d.
2. The same checks as profile 1.

### Profile 2

Made from v7-dev after profile 1 has finished, so it carries the branch. Its B2F runs without
`FUSION_REV`, so all three profiles' fusions are selected alike. Its B1 runs on spectrograms its
own A6 stamps.

### If a profile reruns B1 later

Spectrograms built before this branch carry no `frames_checked` stamp (data-01). Rerun A6 first
(about 30 min), or B1 stops with `prepare_data:stale`.

### For the main session (not changed here)

- **DECISIONS.md:** a D90 entry from this note.
- **Wording:** ROADMAP.md:24 and :65, and DECISIONS.md:932, still say "gamma chosen on
  validation" (sel-07 (c)); `main.m` and `train_dqn.m` are corrected.
- **PROJECT_LOG, ROADMAP and the pipeline page:** C2's longer cost.
- **The source library:** Hastie, Tibshirani & Friedman (ESL) is cited by `select_fusion.m`'s
  FUSION_REV branch only; add it if that branch is ever used.

## Sources

All in the source library unless noted:
- **Norouzi et al. 2006**, the k-out-of-n detector of a swept jammer:
  `V7_Norouzi2006_K_out_of_N_Detector_EUSIPCO.pdf`. Used for the sweeper's confirmation.
- **Barajas et al. 2026**, M-of-N: `N03_Barajas2026_Resilient_Control_Loops_Jamming.pdf`. Used
  for the confirmation and the group dwell.
- **Xie, Zou, Xie & Veeravalli 2021**, eq. 2-3 (Page's CUSUM, the change point) and Sec. III-I
  (detection-isolation): `V7_Xie2021_Sequential_Change_Detection_Survey_JSAIT.pdf`. Used for
  drop_ref's hold-and-release on the median window and the iso columns.
- **Xie, Moustakides & Xie 2022**, the window-limited CUSUM: `W04_Xie2022_Window_Limited_CUSUM.pdf`.
- **Grimaldi, Mahmood & Gidlund 2019**, a threshold on the radio's own noise and the crest
  factor: `V7_Grimaldi2019_RealTime_Interference_Identification_IoT.pdf`. Used for the cfar
  columns.
- **Kazim et al. 2026**, eq. 1.3, a threshold from interference-free samples:
  `V7_Kazim2026_GNSS_Jamming_Detection_AGC_CN0_COTS.pdf`. Used for the cfar thresholds and the
  rule's nulling-threshold candidates.
- **López-Benítez & Lehtomäki 2016**, eq. 9: `V7_LopezBenitez2016_Energy_Detection_Channel_Occupancy_Rate.pdf`.
  The occupancy reading at a low detection probability (lit-2's diagnosis).
- **Lee 1985**, the local average power: `Estimate_of_local_average_power_of_a_mobile_radio_signal.pdf`.
  The path-loss weak point (lit-4).
- **Alshiekh et al. 2018** (shield), **Mnih et al. 2015**, **van Hasselt et al. 2016**: as before.
- **Not in the library:** Hastie, Tibshirani & Friedman, *The Elements of Statistical
  Learning*, 2nd ed., sec. 7.10 (the one-standard-error rule), used only in the FUSION_REV branch.
