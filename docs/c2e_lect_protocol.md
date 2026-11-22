# Profile 1: the revised proposal's KPIs from an isolated reading of its C2e (protocol)

Fixed on 23.10.2026, before profile 1's C2e runs (its chain was at C1p, 82 of 93 cells).
Nothing in this protocol has been run.

## 1. Why

On 23.10 Adi decided not to stop profile 1. Its chain runs its own code to RPT:
- tree `C:\Users\Adi Suliman\uav-gcs-v7`, branch `v7-dev`, `208602b` (code tree equal to `9b5c9f1`);
- base fusion, latch off.

Profile 1's C2e therefore has no `rule_core`/`blind_core` and none of the lecturer's readings:
- PER vs the static link;
- recovery time from detection;
- goodput in bit/s;
- the CNN's contribution;
- the three link states.

They are read once, after profile 1's C2e has finished, in a separate copy. That copy runs the same
C2e on the same inputs and adds them. Profile 1's tree is only read.

## 2. The code: profile 1's own, with the readers added (branch `lect-p1`, `8118281`)

The copy does not run `lect-kpi` or the merged deploy tip. Both carry changes that alter
numbers profile 1's C2e already produced, so the equality of section 5 could not hold:

| Change on `lect-kpi` (not in `208602b`) | Effect on profile 1's inputs |
|---|---|
| `96771c3`, link_env: reward `q` and `healthy` also need the packet loss restored | `ret`, `false_sw` of every policy; the oracle's choices (it reads `K.q`) |
| `96771c3`, policy_monitor: under `class_drop` the drop reference via `drop_ref` | the monitor's alarms, so every monitored policy's decisions |
| `1456587`, policy_monitor: the unknown flag from the monitor's own threshold also at a one-cycle window | the unknown-threat class, so decisions |
| `96771c3`, evaluate_policies: the `offset` set inserted before `clean2` | consumes the episode stream `rs`, so the validation envelope (`RV`), and shifts `clean2`'s frame seeds (`30000 + 100 si`), so KPI 6 |
| `96771c3`, policy_decide/decision_settings: group dwell, `esc_drop`, `confirm_sweep`, `unk_mode`, `rule_slot` | defaults equal profile 1's without `dec`; not needed |
| d91 fusion revision (`FUSION_REV`, held branch reference) | profile 1 runs the base fusion with its own code |

`lect-p1` is `208602b` plus only these changes. Every one adds something; none changes
anything profile 1's code computes:
- `decision_config.m`: `C.core_actions`, `C.ladder_core` (lect-kpi's lines).
- `policy_setup.m`: the cases `rule_core` and `blind_core`.
- `policy_decide.m`: `opt.core`:
  - `rule_core_policy.m` in place of `rule_based_policy.m`;
  - the ladder `C.ladder_core`;
  - `rate_reduce` as the only link-budget configuration;
  - with `'run'` dwell, slot branch on and wideband action `channel_switch` (lect-kpi's defaults, the same as with profile 1's settings);
  - a core option on a non-rule kind is an error.
- `link_env.m`:
  - `K.rec_core` and `K.rec_core_comb` (some core configuration restores the geometry; under a
    comb jammer, one without `channel_switch` or `freq_diversity`);
  - `info.recoverable_core`.
- `rollout_policy.m`:
  - `per_post`, `dlv_post` and `t_rec_det` (`per_metrics.m`);
  - `recoverable_core`.
- `evaluate_policies.m`:
  - `rule_core` and `blind_core` appended after every other policy (after `oracle`), on the same
    episode sets and frame-draw seeds;
  - the variable `lect_in` (scenario names, decision period, payload rate from `params.mat`,
    det_id).
  - No `lect_kpis` call: the readings come only after the gate.
- From `lect-kpi` `e84a5fd`, byte for byte: `lect_kpis.m`, `per_metrics.m`, `per_reduction.m`,
  `three_state_view.m` and `rule_core_policy.m`.
- `lect_lines.m`: `measure_all_kpis.m`'s local functions of `e84a5fd` word for word
  (`three_states`, `three_txt`, `per_lines`, `rec_lines`, `has_core`, `core_tag`, `tq`, `ternary`).
- New:
  - `c2e_lect.m` (steps eval, gate, read);
  - `c2e_lect_gate.m`;
  - `c2e_lect_read.m`;
  - `code/tests/test_c2e_lect.m`.

`tools/c2e_lect_isolated.sh check` refuses any other code. It checks that:
- the code commit descends from `208602b`;
- it changes exactly the 16 files above;
- the five reader files are `e84a5fd`'s blobs;
- the eight `lect_lines.m` functions match `measure_all_kpis.m`'s.

**Blind policies (`394d4da`).** In profile 1's code a blind policy zeroes the probabilities and sets
`obs.unknown` and `maha = -Inf`. Every class then becomes `unknown`: there is no `unk_mode`, so
the flag overrides every class, latched or fused. `394d4da` changes `blind_esc` only under
`unk_mode = 'nonhostile'`, which profile 1's code cannot deploy. It is not ported. No difference is
expected.

## 3. Inputs

The inputs are what profile 1's `evaluate_policies.m` and its callees read (`load`, `isfile`; read in
`208602b`).

They are copied read-only from profile 1's tree into the copy. Each is hashed with SHA-256 before
the copy, after it and in the copy, and the three hashes must match.

| File | Read by |
|---|---|
| `data/policy_pools.mat` | evaluate_policies (PP); clean_ber_ref.m (`clean_ref`, the monitor) |
| `data/trained_dqn.mat` | evaluate_policies (agents, monitor, deployed, rule_sel, det_id, maha_thr, drop_db) |
| `params.mat` | config_gain_db.m; `lect_in`'s payload rate |
| `data/clean_test_pools.mat` (if present) | evaluate_policies (KPI 6's clean pools) |
| `results/eval_detector_metrics.mat` (if present) | evaluate_policies (KPI 1 threshold of KPI 6) |
| `results/eval_detector_metrics_fresh2.mat`, `results/detector_predictions_fresh2.mat`, `results/detector_predictions.mat` (if present) | the three link states (the KPI 1 reading profile 1's measure_all_kpis.m uses) |

**Gate references.** Profile 1's `results/policy_evaluation.mat` and `.txt` go to
`ref/p1_policy_evaluation.{mat,txt}`.

**Identity records** (hashed, not copied): `data/fusion.mat`, `data/trained_detector.mat`,
`data/ood_thresholds.mat`, `data/check_pools.mat`, `data/drop_threshold.mat`,
`data/clean_val_pools.mat`.

The fusion, the drop threshold and the unknown-threat threshold reach C2e only through the pools
(`PP.fuse`, `PP.q_thr`, `PP.det_id`) and the agent. No callee of C2e loads them.

The manifest `C2E_LECT_ISOLATED` in the copy's root lists every file with its hash, size and time,
and every absent one.

## 4. Timing and the test pools

The script refuses to prepare in these cases:
- profile 1's last `##### STAGE C2e (evaluate_policies)` start in `logs/stage_*.txt` has no
  `##### STAGE C2e done` line after it;
- profile 1's reference results are older than that start;
- any C2e input is newer than that start;
- profile 1's tree is not at `208602b`, its code differs from it, or `code/` holds untracked files;
- this protocol's last commit, the last commit of `tools/c2e_lect_isolated.sh` or the code commit is not
  older than that start (the script and the protocol must also be committed unchanged).

Only a committed deviation note `docs/c2e_lect_deviation_*.md` lifts the last refusal; it is
recorded in the manifest.

Profile 1's C2e has already read the test pools. This run reads the same test episodes again,
with the same seeds and pools. It adds two policies and readings that were fixed before profile 1's
C2e ran. No choice is made from any result of profile 1 or of this run: there are no thresholds,
no policy choice and no tuning, and the targets are the lecturer's.

## 5. Consistency gate (pre-registered)

`c2e_lect_gate.m` compares the copy's `results/policy_evaluation.{mat,txt}` with profile 1's. It
uses exact equality (`isequaln`) with no tolerance.

**What must be equal:**
- `POL` and `LBL`: profile 1's, in order.
- `set_names`, `fixed_best`, `tab`, `iDQN`, `iThreat`, `top_cfg`.
- Per episode: every field profile 1 saved, for every set and every one of profile 1's policies,
  in `RES`, `RW` and `ALL`.
- `KP`: every field of profile 1's (`det_id` and `policy_stamp` included).
- The text: line by line.

**Allowed differences (expected, fixed now):**
- `POL`/`LBL` end with `rule_core`/`blind_core`, labelled 'core: rule + escalation' and 'core: no
  detector + escalation'.
- The copy's per-episode results carry `per_post`, `dlv_post`, `t_rec_det` and `recoverable_core`
  besides profile 1's fields; the two appended policies have their own cells.
- `KP.far`, `KP.far_testpools` and `KP.far_cleanpools` have the two core policies' rows after
  profile 1's.
- The variable `lect_in`.
- In the text, the `Generated:` line and the rows that start with the two core labels (the
  policy tables and the false-alarm lists).

Everything else is a mismatch. Mismatches are not expected, because every change in section 2
only adds:
- the two policies come last, so they draw nothing from the episode stream `rs`;
- every other policy's frame seeds depend on the set index only;
- the new fields are computed after the rollout from its own traces.

**On a mismatch:**
- the gate writes `results/c2e_lect_gate.txt`, starting with `GATE FAIL`, and lists every
  difference, with counts and the largest absolute difference as a diagnosis only;
- `c2e_lect` stops before any reading;
- the failure is reported as it is;
- nothing is adjusted, and no number from that copy is reported.

**Threads.** Profile 1's chain MATLAB runs without `-singleCompThread`. The gated wrapper starts
with it, so the evaluation sets `maxNumCompThreads('automatic')` (MATLAB's default) and records
the count in `results/c2e_lect_threads.txt`. If a mismatch can only come from arithmetic order
(last-bit differences in reductions), the same rules still apply.

**Second run.** One second run is allowed, only for a cause outside the code and the data (for
example the thread count). It needs a deviation note that names the cause and is committed before
that run, and a new copy. The gate stays exact. No reading exists before a pass, so a second run
cannot select on the readings.

## 6. The readings (only after a pass, once: `results/c2e_lect.{txt,mat}`)

**The three configurations:**
- static: `none`;
- conventional (link metrics only): `blind_esc`, and on the core action set `blind_core`;
- CNN-based: `rule_esc`, and on the core action set `rule_core`.

The deployed policy is read beside them. "Recoverable" is profile 1's static-link flag on each
episode (pools and specs, no policy). For the full set, some configuration of the 36 restores the
geometry. For the core set, some core configuration does (`recoverable_core`, primary), with the
36-configuration mask as the second line.

| Lecturer KPI | Reading in this run | Verdict |
|---|---|---|
| BER model validation | not here: profile 1's A4v (`results/phy_validation.txt`) | its own |
| Macro-F1 >= 85% | three link states of profile 1's KPI 1 reading (`_fresh2` when present, else the second test set): the saved confusion matrix, every Eb/N0, and from the KPI 1 threshold from the saved predictions (`lect_lines` 'three'); the 10-class KPI 1 and the CNN's B3c reading stay where they are | met / not met on the point (lect-kpi's wording) |
| False alarm rate <= 5% | system: each configuration's episodes with a change on KPI 6's clean flights (`KP.far`, one-sided 95% Clopper-Pearson bound); detector: clean frames read as a jamming state and as a class that raises an alarm (every class but none and benign_interference), every Eb/N0 and from the threshold | system: MET (committed) when the bound <= 5%, MET (not committed) when only the point, NOT MET; detector: point |
| Recall >= 85% per jamming type | three link states: narrowband (tone_jamming) and wideband (jamming) recall | point |
| PER >= 30% lower than the static link | `lect_kpis.m`: primary per scenario (narrowband tone_jamming, wideband jamming) for `rule_esc` (full set) and `rule_core` (core set, `recoverable_core`), paired by episode, 95% bootstrap over flight geometries; the five jamming threats pooled as the extension; the core set on the 36-mask as its second line | MET (committed) on the 95% lower bound, MET (not committed) on the point, NOT MET |
| Recovery time | first confirmed alarm until the packet loss stays restored for 5 cycles (`t_rec_det`), with onset to detection (`t_conf`) and T_rec from onset; median / p90 / never; none, blind, rule, deployed (and the core pair) | measured and compared (no target) |
| Goodput | delivered payload after onset in bit/s (1000 payload bits per 20 ms cycle from `params.mat`), 95% bootstrap, beside the normalized goodput | measured (no target) |
| The CNN's contribution | `rule_esc` vs `blind_esc` (`rule_core` vs `blind_core`): PER reduction, goodput difference, onset-to-detection and detection-to-restored times on the same episodes | measured (no promise) |

`results/c2e_lect.txt` holds these parts, in this order:
1. the gate line and the manifest;
2. the KPI summary's lines (`lect_lines`, worded as lect-kpi's `kpi_summary.txt`);
3. the `lect_kpis.m` section (worded as lect-kpi's `policy_evaluation.txt`);
4. the detection lines;
5. the false-alarm lines.

**Link-limited Eb/N0 points (D99).** Beside these readings, `docs/lect_ebno_protocol.md` (branch
`lect-ebno`) gives each lecturer reading again on the points where the restoration test of packet
loss is defined and per Eb/N0, once, from the saved `KP.lect` and `ALL`, after a gate that
reproduces them exactly. The verdict lines above are unchanged.

## 7. Running it (after profile 1's C2e has finished; profile 3 waits on `p3_c1p.hold`)

    cd "/c/Users/Adi Suliman/uav-gcs-lectkpi"
    bash tools/c2e_lect_isolated.sh check       # preconditions, no writes
    bash tools/c2e_lect_isolated.sh prepare     # worktree C:\Users\Adi Suliman\uav-gcs-c2elect-p1 at 8118281, inputs copied
    bash tools/c2e_lect_isolated.sh run         # the gated MATLAB in the p3 slot, then verify

`run` calls the wrapper with this command (`command` prints it):

    bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 45 uav-gcs-v7-p3 logs/c2e_lect_p1_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-c2elect-p1'); startup; c2e_lect('all')"

**Before it, once:** the tests, through the same wrapper and slot, with cd into the copy (after
prepare) or into `C:\Users\Adi Suliman\uav-gcs-lectp1`:

    bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 35 uav-gcs-v7-p3 logs/hand_c2elect_tests_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-lectp1'); startup; r = [runtests('code/tests/test_c2e_lect.m'), runtests('code/tests/test_core.m')]; for k = 1:numel(r), fprintf('V7RESULT %d %s\n', r(k).Passed, r(k).Name); end; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(isempty(r) || ~all([r.Passed])))"

The script's own tests run without MATLAB: `bash tools/test_c2e_lect_isolated.sh`.

**Resources (estimates):**
- `prepare`: about 10 min (the pools file, of the order of 15 GB, hashed three times and copied
  once). The disk needs the same again.
- `run`: profile 1's C2e plus two policies on top of 14-17, about +15%. That is 0.6-1.7 h from
  D80's 0.5-1.5 h, plus a few minutes for the gate and the reading.
- Memory: 45 GB free commit at the start (the RUNBOOK's figure for a C2e hand-run).

**Writes:**
- the copy;
- the wrapper's busy file and log (`uav-gcs-logs/v7_d86/p3_hand.busy`, `uav-gcs-v7-p3\logs\c2e_lect_p1_<time>.txt`).

Nothing is written in profile 1's tree.

**Removing the copy afterwards:** `chmod -R u+w` on it, then `git worktree remove --force`.

## 8. Never

- No reading before the gate passes.
- No second reading of a copy: `c2e_lect` refuses a second evaluation and a second read.
- No choice made from a result.
- No write into profile 1's tree.
- No change to this protocol after profile 1's C2e has started, except a committed deviation
  note (section 4).
