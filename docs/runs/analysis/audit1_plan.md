**Fix plan for the 29 audit findings: profiles 1 and 3, run c2c8b8b, as of 2026-10-17 10:01**

The findings reduce to 16 fixes. Some findings overlap and are merged:
- **SWEEP**: out-sweeper-confirm, loop-monitor-grid and lit-1.
- **ARCH**: sel-04, out-b3a-arch and out-b3a-svm.
- **NULL**: out-mmse-gain-dd and sel-08.
- **FUSE**: sel-03, lit-2, lit-3 and lit-4(3).
- **DROP**: loop-drop-budget and loop-drop-reference.
- **OFFSET**: loop-release(1) and out-fusion-gap(2,3).

**Run timing.**
- **Profile 1** has been in OOD since 09:36. In the first reading OOD took 237 min and B4s 18 min, so C1p would start at about **13:50 today**.
- **Profile 3** has been in B3n since 06:06, when it should end about 10:50. B3 to B4s should finish around 17:30. Its C1p then waits for profile 1's SURV3, which is days away.
- C1p plus C1c took about 30 h in v6. C2 has 72 runs, about 22–24 h; the cost note's 12 h is wrong.

---

## 1. Must land before a named stage

### 1.1 ALIGN (BLOCKER): before profile 1's C1p (about 13:50 today); profile 3 before its own C1p

**Change**
- In run_dataset_sweep.m at :127, :205 and :268, rename the per-flight draw to `align_gcs`.
- Add length checks so every MEAS field has the same length as `label`:
  - in run_dataset_sweep.m before saving, plus a MEAS/non-MEAS name-collision check;
  - in extract_spectrograms.m and prepare_data.m;
  - in test_core.
- Repair the stored datasets with the layout verified in every run (5,808 and 3,984 runs): in each run's 2n block, the second n values are `meas.align`. Repair:
  - profile 1 dataset.mat and dataset_fresh.mat;
  - profile 3 dataset.mat, and its dataset_fresh once its A5 has finished.

**Reruns (no A5 rerun)**
- A6, then B3n's A6 and B1 on the repaired fresh set.
- Then B1, B2, B2F, B3, B3a, B4, OOD, B4s and gui_norm_stats.
- Only then C1p. No pools exist yet, so nothing is rebuilt twice.

**Test sets**
- Reading the repaired second test set again is a diagnostic only.
- The number that is reported is B3m, read once, after 1.2 and 1.3.

**Cost and running stages**
- About 8 h per profile (A6 0.75, fresh A6 0.5, B1 x2 0.15, B2 0.4, B2F 0.1, B3 0.1, B3a 1.0, B4 0.9, OOD 3.9, B4s 0.3).
- The stages running now on the scrambled feature will be replaced: profile 1's OOD and B4s, profile 3's B3 to B4s. Stopping them now saves about 4 h + 6 h of machine time. That is Adi's call; no process was touched.

### 1.2 In the same commit, before the 1.1 rerun

**a) NULL predictor: before profile 1's C1p (it adds a new pool field)**
- Add `F.mmse_pred` in extract_closed_loop_frames.m, computed from known symbols only:
  - `R_y` is the sample covariance of each 32/64-symbol window (Winters, Salz & Gitlin 1994, eqs. 19–23);
  - the channel `hl` is a whitened LS estimate on the long training and pilot symbols;
  - `x = h^H R_y^-1 h`, clipped below 1, and `SINR_mmse = x/(1-x)`;
  - `SINR_mrc` is measured on the pilots;
  - `G = SINR_mmse / SINR_mrc`, and `align` comes from `R_y − hh^H`.
- Feed it to policy_decide.m:76 and policy_monitor.m:207 only. The detector's `mmse_gain` stays as it is, so A5 does not rerun.
- Check `G` in validate_phy on the V8b, V11-jam and V12c-jam rows, plus new tone rows (JSR 4/16/30 dB) and a reactive row. The theory value is about 28 dB at J = 30 dB, M = 3.
- Cost: 1–2 h, inside the 1.1 rerun window. If it fails, it moves to section 2.

**b) Unknown-threat threshold (sel-02 keying)**
- Move `maha_thr` out of detector_id into a PP field. It is applied at decision time (link_env.m:307, policy_monitor.m:256).
- Retention {0.95, 0.99} then becomes a C2 selection without re-keying the pools.
- No compute cost.

**c) ARCH: before B3a reruns**
- In compare_architectures.m, score every variant fused, out of fold, on validation: select_fusion's folds (seed 61), with FM.N and lambda fixed.
- SVM: set `KernelScale` to `sqrt(p)` (the LIBSVM gamma = 1/p; Hsu, Chang & Lin). Tune KernelScale and Lambda, and the RF's leaf size and predictors per split, with a small grid on validation only.
- Print "beyond" as one-class recall, and label the test columns as readings, not selections.
- Cost: +0.5 h per profile.

**d) Print-only lines read in B3 (no cost)**
- KPI 1 with the unknown override applied (sel-02 item 4).
- Sweeper "never confirmed" split by whether the sub-run had a damaged frame.
- Path-loss recall by step x K x onset age (lit-4 item 2).
- The per-frame network scored on the per-cycle targets (out-fusion-gap item 1).
- The B2 labels (out-b2-label).

### 1.3 FUSE: before the B3m read (both profiles) and before profile 1's C1d

These go into the latch-fix agent's B2F. If C1p has already run, rekey_pools.m covers them without a pool rebuild.

- **sel-03:** score every N on the per-cycle label from threat_active.m. Pick N with the one-standard-error rule (ESL §7.10). Print the two relabel counts separately. Expected result: N = 12 unchanged.
- **lit-4(3):** change fusion_target.m:38 to `pr − t0 < N − 1`, as threat_active.m:39 does. Update test_core (about line 2888) to expect `[1 1 2 2 2 1 1]`.
- **lit-2:** add four floor-relative CFAR idle columns (Grimaldi 2019; López-Benítez eq. 9).
  - T1 and T2 come from the training folds' clean gaps, set one step above the 1 dB quantization.
  - Adopt only if the paired run-bootstrap lower bound on the latched macro-F1 above threshold is ≥ −0.1, and the all-frame lower bound is > 0.
- **lit-3:** add four branch-isolation columns (Xie 2021, Sec. III-I), appended after the existing columns. Adopt by its own paired validation test.
- Cost: about 0.5 h per profile.

### 1.4 Before C1d (profile 1: after C1p + C1c, about 30 h after C1p starts; profile 3 the same)

**SWEEP**
- OR a sweeper path into every monitor at policy_monitor.m:185 and eval_detector.m:385, not in confirm_alarm.m.
- The path confirms on 2 sweeping_jammer reads within n = ceil(83.5/20) + 1 = 6 cycles (`C.confirm_sweep = [2 6]`; k-of-n detection, Norouzi 2006).
- 2-of-4 is rejected because it cannot cover sweep periods above 60 ms.
- Adopt at C1d on validation if no class's "never" rate or p90 gets worse and the KPI 6 bound holds. Measured: never confirmed 11.1% → 0%, clean 6 of 48 unchanged.
- This adds no grid rows. Adding "g" rows to the C2 grid instead would cost about 36 runs, about 11 h.
- Add a unit test: a 1-0-1-0 sweeper sequence confirms; a clean sequence is unchanged.

**DROP**
- C1d admits a drop threshold on the union with the whole monitor, per m/n. This is an exact upper bound, derived from policy_mask.m: before the first change every trajectory is the no_action one.
- The C2 drop grid becomes the monitor's own pick with steps [−2, 0, +2] dB, with signed CUSUM indices.
- The median window gets drop_ref.m's hold-and-release reference (Page's change-point logic; Xie eq. 3). Apply it in drop_alarm_seq.m, drop_alarm_any.m, edge_map's win_drop_db and test_core.
- Cost: under 0.5 h.

### 1.5 Before C2: validation only

C2 retrains anyway and C2e is the first test read, so none of these needs extra test runs.

- **loop-reward-plr:** the reward and `healthy` require BER and packet loss together (link_env.m:152–170).
- **loop-select-held:** the checkpoint, the run selection and the gate use held recovery.
- **sel-06:** choose_deployed compares the DQN with rule_sel's recovery. Add the matching unit test.
- **sel-07:**
  - score both `dqn` and `dqn_esc` on every run;
  - plumb `dqn` through choose_deployed, evaluate_policies:160, edge_map:162, measure_latency:60 and measure_all_kpis:312;
  - add a coordinate step: 3 seeds each of gamma = 0 and running costs x1 (+1.8 h).
- **sel-02:** override modes (a) and (b) x retention {0.95, 0.99} in the base loop, plus a DQN coordinate step if one of them wins (up to +1.8 h).
- **NULL threshold (sel-08):**
  - candidates for `rule_mmse_db`: μ+3σ, μ+3σ+2 (Kazim eq. 1.3) on the new predictor's clean validation frames, 3 dB and 9 dB;
  - each with `rule_slot` on and off;
  - store the choice in trained_dqn.mat and carry it to every reader.
- **loop-rule-dwell:** a 2-of-4 proposal-group dwell plus the no-regress guard, chosen on or off on validation.
- **loop-esc-none:** the drop-alarm exception to the escalation guard, chosen on or off on validation.
- Cost: about +4–5 h on the 22–24 h grid.

### 1.6 Before C2e

- **loop-kpi-unharmed:**
  - KPI 4 and KPI 8 read on harmed episodes only;
  - the envelope `ENVv_h` fixed on validation;
  - edge_map gets PROT_h, REC_h and a no-response attribution mark.
- **OFFSET measurement:**
  - a `spec.offset` field in link_env.m (default inf);
  - a share of the test episodes ends its threat;
  - report release latency, the cost held after the end, and re-alarms;
  - a release is counted separately from a false switch.
- Cost: about 0.5 h. Reporting only.

## 2. After the run

- **out-p3-v11:** a dev check of a first pass without our signal (the quiet-slot `Rq0`, or the training residual) on V11 V8b and V12c's flat rows. Adopt only in a full rerun of both profiles from A4v (about 2.5 days).
- **Release design** (loop-release items 2–3) and DQN training with offset episodes.
- **Detector offset sub-runs:** a time gate in build_threat_model.m with a validation share. If the gate, off by default and bit-identical when off, lands before B3m is generated, read it in B3m.
- **NULL fallback:** if 1.2a misses profile 1's C1p, it goes to the next full run, and this run's report states the predictor's limit.

## 3. Documentation only

- **out-b2-label:** fix the labels and DECISIONS.md:333. Redraw training_curves.png from trained_detector.mat. Profile 3's citation is p3.log:688.
- **Docstrings:** fused_class.m and eval_detector.m should say the unknown override is excluded.
- **Fusion gain:** quote N = 1 → 12 out of fold (90.81 → 93.32%), never 81 → 93%.
- **lit-4(4):** the path-loss weak point is the small step against the fading spread (Lee 1985, about 36 samples for ±1 dB).
- **out-p3-v11:** label profile 3's V11 row as the flat receiver; the verdict for the deployed receiver is V12c. Use Besson's terms at DECISIONS.md:657.
- **sel-07(c) wording:** main.m:88, the train_dqn header, ROADMAP.md:24 and :65, and DECISIONS.md:932. Also correct the C2 cost note.
- **Report architecture statement:** the hybrid leads once fused (93.3 vs 92.1%), while the RF leads per frame.

## Evidence used for the timing

- C:\Users\Adi Suliman\uav-gcs-logs\v7_d86\p1.log (STAGE lines)
- C:\Users\Adi Suliman\uav-gcs-logs\v7_d86\p3.log (STAGE lines)
- C:\Users\Adi Suliman\uav-gcs-logs\full_v7p1_first_reading_20261016_110932.log
- C:\Users\Adi Suliman\uav-gcs-logs\scratchpad_text\full_v6p1b.log
- C:\Users\Adi Suliman\uav-gcs-v7-merge\code\run_stage.m:32-41
- C:\Users\Adi Suliman\uav-gcs-v7-merge\code\decision\pool_cell.m:83-118 (pools store probs, maha and idle)
- C:\Users\Adi Suliman\uav-gcs-v7-merge\code\decision\rekey_pools.m:21 (fusion keys can be re-keyed without a rebuild)


REJECTED: ['sel-01: The m-of-n confirmation grid offers only near-consecutive rules, which miss the intermittent sweeper; rules that dominate them are not candidates', 'sel-05: Inverse-frequency class weights and SpecAugment masking are deployed without a validation on/off comparison', "loop-kpi6-rollin: The closed loop never flies a clean UAV that rolls into a turn. KPI 6 and the C1d/C2 false-alarm bounds therefore miss the detector's worst clean case"]
