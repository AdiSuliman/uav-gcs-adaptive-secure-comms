# The lecturer's readings at link-limited Eb/N0 points (protocol)

Fixed on 25.10.2026, before any test data of these readings exists: C2e has not run in profile 1,
CORE_BW or profile 3 (DECISIONS D99). Nothing in this protocol has been run.

## 1. Why

The packet-loss half of "restored" (`link_env.m`: `pl <= C.ratio_ok x clean + one loss event`)
cannot fail where the clean link itself loses half its packets or more. In profile 1's pools that
is 0, 3 and 6 dB (clean loss 0.99 / 0.84 / 0.62, p1.log:7904). There:
- "recoverable" and T_rec from onset are BER-only tests;
- recovery time from detection (`per_metrics.m` `t_rec_det`) is 0 by construction for every
  detected episode, under every policy including no response;
- the PER reduction and the CNN's share can move either way.

Every lecturer reading pools all six Eb/N0 points. This protocol keeps those pooled readings as
the verdict and adds, for reporting only, the same readings where the restoration test is defined.

## 2. The mark (R1)

- A grid Eb/N0 point s is **link-limited (L)** when `C.ratio_ok x PP.clean_fer(s) >= 1`
  (`C.ratio_ok` = 2: a clean packet loss of at least 0.5). At such a point
  `pl <= C.ratio_ok x pr + slack` holds for every configuration and geometry, since `pl <= 1`.
- `PP.clean_fer` is the decision layer's `'mean'` restoration reference (`link_env.m`), as step M
  rebuilt it from the 300 validation clean flights per Eb/N0 (`clean_ref_protocol.md`, D95). It is
  read from the post-M `data/policy_pools.mat` (fields `ebno`, `scen`, `clean_fer`, `det_id`).
- The mark adds no parameter and ignores the one-event slack: it never marks a point where the
  test can fail. A point just below 0.5 is not marked; its row shows its clean loss.
- Descriptive tag beside it: **J** (working point) when `clean_fer < 0.1`, the IEEE 802.11a-1999
  sensitivity criterion (PER < 10%); **M** (marginal) otherwise.
- Whatever the post-M table gives is used, with no further choice. On the current table
  {0, 3, 6} dB are L and {9, 12, 15} dB are J; step M may move 6 dB.
- The mark is computed once, from the pools alone, and written with the pools' SHA-256 to
  `low_ebno_mark.txt` **before** `results/policy_evaluation.mat` is opened.
- A flight geometry (`geom = 1000 s + r`, `policy_run_set.m`) lies inside one Eb/N0, so episodes at
  an L point keep their bootstrap cluster.

## 3. The readings and their order (R2)

For every reading `lect_kpis.m` gives (PER reduction vs the static link per jamming type and
pooled, full and core sets with their second lines; the CNN's contribution in PER, goodput and
times; `t_conf`, `t_rec_det`, T_rec; goodput in bit/s and normalized), always in this order:

1. **Line A, the verdict, unchanged:** all points, exactly C2e's `lect_kpis.m` lines (`KP.lect`).
   PER verdict words (MET committed / MET not committed / NOT MET) come only from this line.
2. **Line B, "restoration test defined (non-L points)":** `lect_kpis.m` unchanged on `ALL`
   restricted to the episodes with `~L(s)`. Its verdict words are printed with
   "[second line, not the verdict]". Where Lines A and B differ in verdict words for a reading,
   the result sentence names both and the reason (the L points); Line A stays the verdict.
3. **Per-Eb/N0 rows:** `lect_kpis.m` unchanged on `ALL` restricted to each s. Each row carries its
   tag (L / M / J), its episode counts and its clean packet loss; its verdict words are labelled
   "descriptive, not a verdict".

**Recovery time from detection.**
- At L points: "undefined (restoration threshold >= 100%)"; the `t_rec_det` values of those rows
  are not printed.
- The headline recovery time is Line B.
- Line A is printed per set of `rec_block` (recoverable threat, recoverable jamming) and policy as
  "all points, includes N episodes at L points where t_rec_det is set by construction". N counts
  the detected episodes there: at 0 when 5 cycles follow the detection, "never" otherwise
  (`per_metrics.m` run_start); a later value can come only from a coded link's first frames. All
  counts are given.
- `t_conf` (onset to detection) is valid everywhere: Lines A, B and every row.
- T_rec from onset and KPI 4's "recovered" are BER-only at L points; their L rows are tagged
  "BER-only" (the per-Eb/N0 rows and C2e's KPI 4/5 per-Eb/N0 table, printed with the mark).

**Normalized goodput.**
- Not defined (NaN, `link_env.m`) where `1 - clean_fer < 0.1`. Line A's normalized mean (mean
  'omitnan') therefore leaves those episodes out; this is stated beside it with their count.
  Goodput in bit/s keeps them.
- Values above 1 at an L point are real (a quarter-rate link that delivers beats a clean full-rate
  link that does not). They are shown, not clipped; Line B gives the value without them.
- Goodput in bit/s: Lines A, B and every row, unchanged.

**False alarms (KPI 6, system), verdict unchanged.** The verdict stays the pre-registered set from
the KPI 1 threshold (`KP.far`). Added, descriptive only: the non-L line and per-Eb/N0 rows, from the
same union the verdict reads (`RU` = `RES` clean and clean2 sets plus `RW`,
`evaluate_policies.m`), each restricted by its own `s` and the KPI 1 threshold. The lecturer's
wording is "in normal communication conditions", and the clean link at an L point loses half its
packets or more.

## 4. No other use (R3)

The mark changes no training, reward, policy choice, threshold or KPI definition. It selects no
line after seeing results: all lines are always printed, in the order of section 3.

## 5. Code (branch `lect-ebno`, from `lect-kpi` `9122b8d`)

- `code/evaluation/lect_kpis_by_ebno.m`: the mark, the gate, the readings, the single run.
- `code/evaluation/core_bw_lect_by_link.m`: the same for CORE_BW (section 7).
- `code/tests/test_lect_kpis_by_ebno.m`: synthetic, no pools.
- The readers it calls are profile 1's merged tip's (`TIP` `66ec267`) files unchanged:
  `lect_kpis.m`, `per_reduction.m`, `boot_cluster.m`, `false_change_rate.m`, `per_metrics.m`,
  `three_state_view.m`, `decision_config.m`, `packet_share.m`, `core_bw_rules.m` (the test
  compares them with `TIP`). `TIP3` holds the same blobs of these files.
- Carried byte for byte (local functions that cannot be called):
  `evaluate_policies.m`'s `far_report` and `cp_upper`; `experiment_core_bw.m`'s `per_lines`,
  `qstat`, `plr_threshold`, `read_recoverable`, `recoverable_mask`, `get_set` and `pol` (the test
  compares them word for word).

## 6. Profiles 1 and 3: inputs, gate, output

`lect_kpis_by_ebno('run', pools, eval_mat, eval_txt, out_dir)`, absolute paths, inputs only read:

| Input | Read |
|---|---|
| post-M `data/policy_pools.mat` | `PP.ebno`, `PP.scen`, `PP.clean_fer`, `PP.det_id` (first, for the mark) |
| `results/policy_evaluation.mat` (read-only copy) | `ALL`, `POL`, `LBL`, `iDQN`, `KP`, `RES`, `RW`, `set_names` |
| `results/policy_evaluation.txt` (read-only copy) | the `lect_kpis` lines and KPI 6's lines |

`payload_bps` and `period_ms` are `KP.lect`'s, as C2e's call used them.

**Integrity gate, before any subset is read** (exact, `isequaln`, no tolerance):
- `KP.ebno` and `KP.det_id` are the pools';
- every policy holds the same episodes (`s`, `geom`, `scn`), and every geometry lies in one Eb/N0;
- `lect_kpis` on the full `ALL` reproduces `KP.lect`, and its lines equal the `lect_kpis` lines of
  `policy_evaluation.txt`;
- the copied `far_report` on the full `RU` reproduces `KP.far` and `KP.far_diag`, and its lines
  equal those under the KPI 6 header of the text (the episode length from `KP.far`).

The run sets `maxNumCompThreads('automatic')`, as C2e, and records the count. On a mismatch it
writes `lect_kpis_by_ebno.txt` starting with `GATE FAIL`, lists every mismatch, prints no subset and
stops. Nothing is adjusted.

**Output** in `out_dir`: `low_ebno_mark.txt` (first), `lect_kpis_by_ebno.txt` and `.mat`: the
inputs' SHA-256, the thread count, the gate line, the mark, Line A with the normalized-goodput
note, Line B, the verdict-word comparison, the recovery-time summary (core sets too), the
per-Eb/N0 rows, the KPI 4/5 table with the mark, KPI 6's Line A, non-L line and per-Eb/N0 rows.
The run refuses when these outputs exist (once), and checks that no input changed during it.

## 7. CORE_BW

CORE_BW keeps its verdicts and code. It reads against the same flight's clean link
(`link_env('tables', PP, 'flight')`) and judges harm on a scenario's pooled means, so the post-M
mark does not apply to it.
- **Mark, per episode:** L when its own flight's threshold, `C.ratio_ok x` that flight's clean
  packet loss `+ packet_share` (`plr_threshold`), is 1 or more. Exact for the core configurations:
  none uses `fec_interleave`, so each has the same slack 1/n. From the CORE_BW pools' clean cell on
  the test split, written with the pools' SHA-256 to `core_bw_low_ebno_mark.txt` before
  `test_readings.mat` is opened. The run refuses rolling-in test flights (`event_frame`), where
  `link_env.m`'s reference spans the event.
- **Gate:** the copied `per_lines` on the primary scenarios (H1, fixed total power, Liu's noise
  reading) reproduces `KP.primary` of `core_bw_kpis.mat` and its lines in `core_bw_report.txt` and
  in the saved `lines`; the test readings' `meta` names the pools' runs, `params_id` and `det_id`.
- **Readings (R2-R3):** Line A (the report's primary block, the verdict); Line B (`per_lines` on
  the non-L episodes of the recoverable scenarios, labelled second line); the verdict-word
  comparison; recovery time from detection with Line B as the headline and Line A with N per
  policy and type; the number of L episodes and of scenario points holding an L episode or only
  L episodes.
- `core_bw_lect_by_link('run', F)` with `F.pools`, `F.test`, `F.recov`, `F.kpis`, `F.report`,
  `F.params` and `F.out`, absolute paths; outputs `core_bw_lect_by_link.{txt,mat}`.
- Before its run, the seven copies are compared with the `experiment_core_bw.m` of the commit its
  test stage ran (its marker's `commit` line). If they differ, they are taken again from that file
  byte for byte, with the test passing, in a commit on `lect-ebno`; the rules here stay as they are.

## 8. When it runs

**Tests, once, in the stop window during T2's smoke, in the p3 slot,** from a clean worktree of
`lect-ebno` (`git status` empty):

    bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 35 uav-gcs-v7-p3 logs/hand_lectebno_tests_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-lectebno'); startup; r = [runtests('code/tests/test_lect_kpis_by_ebno.m'), runtests('code/tests/test_core.m', 'ProcedureName', 'test_m_files_parse')]; for k = 1:numel(r), fprintf('V7RESULT %d %s\n', r(k).Passed, r(k).Name); end; fprintf('V7TESTS %d/%d\n', sum([r.Passed]), numel(r)); exit(double(isempty(r) || ~all([r.Passed])))"

A failing test is fixed on `lect-ebno` before the run, with the rules of sections 2-4 unchanged.

**Profile 1, once, after its `##### STAGE C2e done`:**
1. Copy profile 1's `results/policy_evaluation.mat` and `.txt` into
   `C:\Users\Adi Suliman\uav-gcs-lectebno-read\p1\results` and set them read-only. The post-M
   `data/policy_pools.mat` is read in place (only `load` and the hash read it).
2. Run, through the same wrapper and slot (45 GB: the pools are loaded once):

       bash "/c/Users/Adi Suliman/uav-gcs-logs/v7_d91_gated_run.sh" 45 uav-gcs-v7-p3 logs/lectebno_p1_<time>.txt "restoredefaultpath; cd('C:\Users\Adi Suliman\uav-gcs-lectebno'); startup; lect_kpis_by_ebno('run', '<P1 tree>\data\policy_pools.mat', 'C:\Users\Adi Suliman\uav-gcs-lectebno-read\p1\results\policy_evaluation.mat', 'C:\Users\Adi Suliman\uav-gcs-lectebno-read\p1\results\policy_evaluation.txt', 'C:\Users\Adi Suliman\uav-gcs-lectebno-read\p1\results')"

   `<P1 tree>` is the tree whose chain ran that C2e.
3. If the script and its tests are not ready by `STAGE C2e done`, they still run once afterwards;
   the delay goes on record. No rule here depends on a result.

**Profile 3, once, after its own `STAGE C2e done`:** the same, with its own post-M pools and
results, into `...\uav-gcs-lectebno-read\p3\results`. No change to `TIP3`.

**CORE_BW, once, after its test stage** (`test_readings.mat` and `core_bw_report.txt` written):
`core_bw_lect_by_link('run', F)` through the same wrapper and slot, with CORE_BW's files read in
place and `F.out` = `...\uav-gcs-lectebno-read\core_bw`.

**Writes:** the reading copies and the wrapper's log. Nothing in a profile's tree.

## 9. Never

- No subset before the gate passes; no second run of a reading copy.
- No change to a verdict, a threshold or a KPI definition from the mark.
- No line chosen or dropped after seeing a result.
