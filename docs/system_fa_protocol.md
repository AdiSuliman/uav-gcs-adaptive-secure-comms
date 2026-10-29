# System-level clean false alarms: breakdown and pre-onset sensitivity (protocol)

Fixed on 26.10.2026, during C2 of profile 1, before `STAGE C2e done`: no C2 or C2e result exists.
Nothing in this protocol has been run (the gate-failure behaviour and the launch of sections 2 and
5 were fixed the same day, before C2e, after a dry run of the gate on a scratch copy of the smoke).
It implements DECISIONS D103 points 3-6 (decision note
`system_fa_decision.md`, option A+). The verdicts stay as pre-registered:
- **Lecturer KPI 3 (FAR <= 5%)** is read on the detector (B3c, B3r; `design_final.md` 6.5).
- **Our KPI 6 (system level, an extension)** is `KP.far`, read in C2e on the union of clean test
  flights (Clopper-Pearson one-sided 95% upper bound <= 5%, every configuration, >= 600 flights,
  Eb/N0 >= the KPI 1 threshold). It is never called lecturer KPI 3.

Everything here is descriptive. It moves no verdict, threshold, KPI definition, training or
policy choice, and no line is chosen or dropped after a result is seen.

## 1. Inputs (read only, absolute paths)

| Input | Read |
|---|---|
| post-M `data/policy_pools.mat` | `PP.ebno`, `PP.scen`, `PP.clean_fer` (D99's mark), `PP.det_id`, and the monitor fields `alarm_mode`, `confirm`, `drop_db`, `confirm_sweep` when present |
| `results/policy_evaluation.mat` (read-only copy) | `ALL`, `POL`, `LBL`, `iDQN`, `KP`, `RES`, `RW`, `set_names` |
| `results/policy_evaluation.txt` (read-only copy) | the `lect_kpis` lines and KPI 6's lines |
| `data/trained_dqn.mat` (read-only copy) | `agent`, `deployed`, `alarm_mode`, `confirm`, `drop_db`, `rule_sel`, `det_id`, `maha_thr`, `dec` |

The trained policy is read for one reason: point 5 needs each policy's own monitor
(confirmation m-of-n, the sweeper's own k-of-n, alarm mode), and the evaluation saves only the
deployed DQN's `KP.confirm` and `KP.alarm_mode`, without `confirm_sweep` or the rule fallback's
monitor. The monitors are rebuilt as the policies ran: `decision_settings(pools, trained)`, as
`evaluate_policies.m`, and the rule fallback's own on top (`policy_decide.m` `opt.monitor`),
with `policy_monitor.m`'s defaults.

Saved fields used (checked against `rollout_policy.m`, `policy_run_set.m`, `evaluate_policies.m`
at `d4623ed`): `s`, `geom`, `scn`, `split`, `onset`, `switches`, `false_sw`, `fc_t`, `fc_cls`,
`fc_deg`, `fc_dal`, `fc_drop`, `t_conf`, `recoverable`, `recoverable_core`, `threat` and the
fields `lect_kpis.m` reads. `cfg_trace` is not saved (`policy_run_set.m` removes it) and is not
used.

## 2. Gate (D103 point 6)

Exact (`isequaln`, no tolerance), before anything of points 3-5 is read:
- `KP.ebno` and `KP.det_id` are the pools';
- `policy_stamp(trained)` is `KP.policy_stamp`, and the rebuilt monitor of the policies that run
  the deployed DQN's is `KP.confirm` and `KP.alarm_mode`;
- every policy holds the same episodes in `ALL` (`s`, `geom`, `scn`, `onset`) and in the clean
  union `RU` (`s`, `geom`, `split`); every geometry lies in one Eb/N0; every field above exists;
- `lect_kpis.m` on the full `ALL` reproduces `KP.lect`, and its lines equal those of the text;
- the copied `far_report` on the full `RU` (the test split's clean set, `clean2` when present, and
  the clean pools' `RW` as split 6, from the KPI 1 threshold) reproduces `KP.far` and
  `KP.far_diag`, and its lines equal those under KPI 6's header of the text.

On a mismatch the run writes `system_fa_breakdown.gatefail.txt` and `.gatefail.mat` (the first
line `GATE FAIL`, the header with the inputs' SHA-256 and the thread count, every mismatch and, for
a field that differs, the leaves that differ with their count, the largest absolute difference and
the first pair at full precision), holds none of points 3-5, creates neither
`system_fa_breakdown.txt` nor `.mat`, and stops with the error `system_fa_breakdown:gate`.
**A failed gate does not spend the reading:**
- a later run into the same `out_dir` is allowed; an earlier attempt's diagnostics stay there under
  their own time;
- the once-guard covers the outputs of a PASS only: no second run after `system_fa_breakdown.txt`
  or `.mat` exists;
- nothing is adjusted: no tolerance, no threshold, no point of section 3. A defect in the script
  that the diagnostics expose is fixed in a commit with its test and entered in DECISIONS before
  the next attempt; the gate stays exact.

The header names the thread count the session really has (`threads N (how)`, never "as C2e"): the
run sets `maxNumCompThreads('automatic')` where the session allows it, and a `-singleCompThread`
session, as the gated wrapper's, refuses and keeps one thread.

## 3. Readings and their order

**D103 3, on KPI 6's clean flights (`RU` from the KPI 1 threshold); six policies:** none,
rule_esc, blind_esc, rule_core, blind_core and the deployed policy (`POL{iDQN}`).
- KPI 6's lines as C2e printed them (the verdict, reproduced by the gate).
- (a) False-alarm episodes per Eb/N0, one table for the six policies from the same `RU`. Its rows
  for the deployed policy and rule_esc must equal `far_report`'s, or the reading stops (one table,
  not a second definition). Points below the KPI 1 threshold print `-`.
- (b) The path at the first change, from that cycle's flags (`fc_cls`, `fc_deg`, `fc_dal`):
  class (a hostile class as `policy_monitor.m` counts it: with `class_drop`/`class_cusum`,
  path_loss only with the drop alarm; none in the `degraded` mode), degradation (class none,
  benign_interference, unknown, or path_loss without the drop alarm; counted per class), drop
  (the drop alarm alone), no flag (none on that cycle: confirmed from earlier cycles). Overlaps
  beside. A confirmation built from mixed paths is attributed to the change cycle's flags, and the
  row says so.
- (c) The Xu split: false-alarm flights with `false_sw > 0` (the clean link passes the 2x test at
  no_action, `K.healthy`, per flight) against `switches > 0` and `false_sw = 0` (it fails it).
- (d) False changes per cycle and per hour (`far_report`'s `false_change_rate.m`) beside the
  per-episode share, with ARL = 1 / rate per cycle.
- (e) The cycle of the first false change (`fc_t`): the share in cycles 1..`C.win` - 1, where the
  BER window holds fewer than `C.win` frames, then the histogram. Reported as a start-up
  transient of episode starts, never removed from the reading.

**D103 4, the pre-onset sensitivity of the lecturer's readings (labelled "sensitivity").**
- A change before the onset: `0 < fc_t <= onset`. The decision of cycle t reads frame t - 1, and
  frame t - 1 is clean while t - 1 < onset (`link_env.m`, `rollout_policy.m`), so such a change was
  decided on clean frames only, which no threat can affect.
- Compared policies: those `lect_kpis.m` reads (none, rule_esc, blind_esc, the DQN with
  escalation or the deployed DQN, the deployed policy, rule_core, blind_core), the oracle aside
  (it has no monitor).
- (a) Per compared policy, the episodes with a change before the onset among the recoverable
  jamming episodes (36, core, and each lecturer scenario), and per Eb/N0 (36).
- S0: the episodes with no change before the onset under any compared policy; the same episodes
  under every policy (paired). Its size and its Eb/N0 composition are printed.
- (b) `lect_kpis.m` unchanged on S0, pooled; its verdict words carry
  "[sensitivity, not the verdict]". Line A (C2e's lines) stays the verdict; where S0 and Line A
  differ in verdict words, both are named, and the result sentence names both.
- (c) Line B of D99 (the non-L points, the mark of D99 R1 from the pools) and every Eb/N0 point,
  the full set beside S0, so S0's better-link mix is not read as bias. At L points recovery from
  detection is undefined and T_rec a BER-only test.
- An empty subset prints "no episodes" and reads nothing.
- (d) Mechanism D is read from C2's log on validation, before C2e (D103 4(d)), not here.

**D103 5, carried-over alarms**, per compared policy, on the recoverable threat (36), recoverable
jamming (36) and recoverable jamming (core) episodes, with each policy's own monitor (m-of-n, the
sweeper's k-of-n; the blind policies read every cycle as unknown, `policy_decide.m`, so they have
no sweeper path):
- carried over: `t_conf < min(m, k) - 1`, which needs an alarm cycle before the onset;
- the sweeper's path or carried over: `min(m, k) - 1 <= t_conf < m - 1`, not separable from the
  saved fields (no per-cycle class is saved);
- `t_conf` (median / p90, never) with all, without the carried-over, and without both.

## 4. Code (branch `sysfa`, from profile 1's tip `d4623ed`)

- `code/evaluation/system_fa_breakdown.m`: the gate, the readings, the single run.
- `code/tests/test_system_fa_breakdown.m`: synthetic, no pools (gate pass and fail, each table on
  a synthetic `ALL`/`RU`, S0 pairing across policies, empty subsets, the run's order and once).
- The readers it calls are `d4623ed`'s files unchanged (`lect_kpis.m`, `per_reduction.m`,
  `boot_cluster.m`, `false_change_rate.m`, `per_metrics.m`, `decision_config.m`,
  `decision_settings.m`, `policy_stamp.m`; the test compares them, and `evaluate_policies.m`,
  `rollout_policy.m`, `policy_run_set.m`, `policy_monitor.m`, with `d4623ed`).
- Carried byte for byte: `evaluate_policies.m`'s `far_report` and `cp_upper`, `lect_kpis.m`'s
  `tstat` (the test compares them). The mark and the row printing are `lect_kpis_by_ebno.m`'s
  (branch `lect-ebno`); the test compares the mark when that file is on the path.

## 5. When it runs

Amendment 2026-10-27 (path only, Adi's folder rule): `C:\Users\Adi Suliman\uav-gcs-sysfa-read` is now `C:\Users\Adi Suliman\uav-gcs-adaptive-secure-comms\worktrees\sysfa-read`; no other word of this protocol changes.

**Tests, once, before the run,** in a stop window of a short MATLAB job (no pools), from a clean
worktree of `sysfa` (`git status` empty), through the gated wrapper and slot the other readings
use:

    bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 35 uav-gcs-v7-p3 logs/hand_sysfa_tests_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-sysfa'); startup; r = [runtests('code/tests/test_system_fa_breakdown.m'), runtests('code/tests/test_core.m', 'ProcedureName', 'test_m_files_parse')]; for k = 1:numel(r), fprintf('V7RESULT %d %s\n', r(k).Passed, r(k).Name); end; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(isempty(r) || ~all([r.Passed])))"

The script was also run on a scratch copy of the smoke's saved `policy_evaluation.mat`/`.txt`
(its own pools and `trained_dqn.mat`) through the gated wrapper on 26.10.2026: the exact gate
passes there, one thread. That proves little about the chain: the smoke's C2e ran under
`-singleCompThread` (`v7_d91_deploy_tests2.sh`), the chain's C2e does not (`v7_d91_takeover.sh`,
`run_ml p1`), and the smoke is small (a few hundred episodes), so it cannot show a thread-count
effect that appears only on larger reductions. A failing test is fixed on `sysfa` with the rules of
section 3 unchanged.

**Profile 1, once, after its `##### STAGE C2e done`:**
1. Copy profile 1's `results/policy_evaluation.mat`, `.txt` and `data/trained_dqn.mat` into
   `C:\Users\Adi Suliman\uav-gcs-sysfa-read\p1\results` and set them read-only. The post-M
   `data/policy_pools.mat` is read in place (only `load` and the hash read it).
2. Run, through the same wrapper and slot (45 GB: the pools are loaded once). This first attempt is
   the canonical launch: one thread, every gate of the wrapper:

       bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 45 uav-gcs-v7-p3 logs/sysfa_p1_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-sysfa'); startup; system_fa_breakdown('run', '<P1 tree>\data\policy_pools.mat', 'C:\Users\Adi Suliman\uav-gcs-sysfa-read\p1\results\policy_evaluation.mat', 'C:\Users\Adi Suliman\uav-gcs-sysfa-read\p1\results\policy_evaluation.txt', 'C:\Users\Adi Suliman\uav-gcs-sysfa-read\p1\results\trained_dqn.mat', 'C:\Users\Adi Suliman\uav-gcs-sysfa-read\p1\results')"

   `<P1 tree>` is the tree whose chain ran that C2e.
3. **If the gate fails** (section 2: the reading is still open): the same script with the same
   arguments and inputs runs again in a session with the thread count C2e had (`automatic`; the
   chain's MATLAB is started without `-singleCompThread`). The launcher is the wrapper copy
   `sed 's/ -singleCompThread//' v7_d91_gated_run.sh > <scratch>/v7_d91_gated_run_mt.sh`, which
   keeps the busy file, the memory gate and the speed gate; the script itself sets `automatic`,
   and the header names the count. If that attempt fails as well, the reading stays open and
   stops: a DECISIONS entry names the field and the cause (the `.gatefail.txt` leaves) before
   anything else is tried; a tolerance is never one of the options.
4. If the script and its tests are not ready by `STAGE C2e done`, they still run once
   afterwards; the delay goes on record. No rule here depends on a result.

**Writes:** the reading copy's `system_fa_breakdown.{txt,mat}` and the wrapper's log. Nothing in a
profile's tree. The run refuses when its outputs exist and checks that no input changed during it.

## 6. Reading order

1. C2e's KPI 6 line (the verdict) and the lecturer's Line A (`policy_evaluation.txt`).
2. D103 4(d) from C2's log (validation; read before C2e).
3. This output, top down: the gate line, D103 3 (a)-(e), D103 4 (a)-(c), D103 5.
4. Report wording as fixed in D103 point 7: if KPI 6 is not met, "System-level false alarms on
   clean flights (extension, our KPI 6): NOT MET, X% [upper Y%]", with D103 3 as the cause, then
   the degradation path's fix (D103 part 2), chosen on validation and read on a fresh clean test
   set in profile 3 and in the profile 1 rerun. No sentence calls the miss acceptable or out of
   scope. If `fa_bound_met` is false, EDGE commits no point at system level (D103 point 8).

## 7. Never

- Nothing of points 3-5 before the gate passes; no second run of a reading copy after a PASS (a
  failed gate leaves the reading open, section 2).
- No change to a verdict, a threshold or a KPI definition from these readings.
- No episode excluded on anything but pre-onset behaviour; no line chosen or dropped after a
  result is seen.
