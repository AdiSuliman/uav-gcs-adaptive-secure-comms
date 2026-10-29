# Degradation path of the link monitor: pre-registered protocol

Written 26.10.2026, during profile 1's C2, before any C2 or C2e result exists and before any
reading this protocol governs. Code on `lect-kpi` (profile 3's line, later merged for the profile 1
rerun P1R); tests in `code/tests/test_deg_mode.m`. Design: section 4 of the decision of 26.10
(system-level clean false alarms, our KPI 6).

## 1. The defect

At C1d the whole monitor at no_action breaks KPI 6's 5% bound under every confirmation, and the
paths other than the drop alarm break it alone (`results/drop_threshold.txt`). The degradation
test of `policy_monitor.m` is the measured main driver:

- **Single-frame lookup.** The clean reference is read at one frame's Eb/N0 estimate, while the
  BER it is compared with is a mean over `C.win` = 5 frames. The `ber_est` table falls 2.6-4.3x
  per 3 dB between 0 and 12 dB, so an estimate error of +1.4 to +2.2 dB halves the reference.
- **A threshold that is not a quantile.** The threshold is `C.ratio_ok` x the clean population
  mean, not a quantile of the clean statistic. The table is keyed on nominal Eb/N0 and read at
  the measured one.
- **No RF evidence.** A low BER alone does not tell a poor link from jamming (Xu et al. 2005). The
  quiet-slot measurement that does (`q_iot`, interference over thermal in our silent slot) is
  read by the rule's action choice but not by the monitor.

## 2. Candidates

Each is a value of `deg_mode` (`C.deg_mode` in `decision_config.m`, `PP.deg_mode` when deployed).
The default `'ratio'` is the test above, bit for bit.

| Id | `deg_mode` | Test |
|---|---|---|
| reference | `'ratio'` | BER window mean > `C.ratio_ok` x max(clean `ber_est` at the frame's Eb/N0 estimate, `C.deg_floor`) |
| F1 | `'win'` | as `'ratio'`, the reference read at the median of the **measured** Eb/N0 estimates of the same `C.win` frames as the BER mean (`M.ebno_win`) |
| F2 | `'win_q'` | F1's lookup axis; threshold the clean (1 - alpha) quantile of the window BER at `M.ebno_win` (`PP.ber_q`), never below `C.ratio_ok` x `C.deg_floor` |
| F3 | `'win_q_gate'` | F2, and degraded only when `q_iot` >= the quiet-slot threshold in at least one frame of the window; otherwise `M.deg_quiet` ("degraded, no RF evidence": logged, no alarm) |

Definitions fixed now:

- **The window.** The Eb/N0 window holds `M.ebno_est` as measured, with the gain of the
  configuration the frame was received with, the same frames as the BER it is compared with. It
  is not the drop path's gain-removed 3-frame median. It and the quiet-slot window restart with
  `mem.ber` on the first frame received with a change.
- **The quantile table** (`clean_ber_q.m`, `deg_quantile.m`).
  - Source: the fit half of the clean validation geometries (section 4), every Eb/N0 point, at
    no_action. Every window of `C.win` frames of each flight, cyclic in the flight's frames as
    `link_env.m` draws them: the window's mean `ber_est` and its median measured Eb/N0
    estimate.
  - Bins: 1 dB (`C.deg_bin_db`) on the windowed Eb/N0. A bin with fewer than 10/alpha cycles
    (`C.deg_kmin`) or fewer than 30 flights (`C.deg_fmin`) joins a neighbour. The failing bin
    with the fewest cycles goes first, the lower on a tie; it joins its neighbour with fewer
    cycles, the lower on a tie. A geometry counts as one flight at every Eb/N0 point, the
    conservative count.
  - The threshold of a bin is the value with floor(alpha n) of its n cycles above it. A lookup
    takes the bin with the largest lower edge at most the window's Eb/N0.
  - If one bin is left and it still fails, the table is flagged (`short`) and reported, not
    widened.
  - alpha is in {1e-2, 1e-3} per cycle (`C.deg_alpha`, in that order).
- **The floor.** F2's threshold never falls below `C.ratio_ok` x `C.deg_floor` (2e-4), the
  smallest threshold the monitor uses today.
- **The quiet-slot threshold.** F3 uses the deployed `PP.q_thr` (`select_fusion.m`: clean
  validation frames, mu + 3 sigma + 2 dB), else `C.q_alarm_db` (3 dB). It is the same test the
  rule reads.
- **What F1-F3 leave alone.**
  - **The coded test.** With `fec_interleave`, the CRC test is unchanged in every mode. F3's
    gate applies to the whole degradation flag, the coded test included.
  - **The class and drop paths** are unchanged. Faults and shadowing (signal loss) keep their
    alarms.
  - **Consumers of the degradation flag.** The rule, the escalation count and the tried-list
    reset read the degradation flag the mode produces.
  - **The DQN's observation.** Its degradation feature stays log10(BER / mean reference),
    with the reference read on the mode's lookup axis.

## 3. Adoption rule (C1d, `choose_drop_threshold.m`, `deg_adopt.m`)

1. **Order.** The candidates are tried in this order: F1; F2 at alpha 1e-2, then at 1e-3; F3 at
   alpha 1e-2, then at 1e-3.
2. **Reading.** For each candidate and for `'ratio'`, C1d's whole-monitor reading runs on the
   same episodes and frames:
   - every monitor of `C.monitors`, each at its own most sensitive drop threshold whose
     one-sided 95% Clopper-Pearson bound is at most 5%, or the least sensitive one;
   - the sweeper's own confirmation decided as now.
   False alarms come from the check half's clean episodes; delays from the single threats of
   the validation split.
3. **Admissible.** Against `'ratio'`, under every monitor:
   - (a) jamming and tone_jamming: the median and p90 delay and the never share do not grow;
   - (b) every other threat: the never share grows by at most 1 point and the p90 by at most
     1 cycle.
   A threat never confirmed has an infinite delay.
4. **Adopted.** The first admissible candidate whose lowest bound over the monitors is at most
   5%. If none reaches 5%, the admissible candidate with the lowest bound, the first on a tie;
   KPI 6 is then read and reported as it falls.
5. **None admissible.** `'ratio'` stays. F4 (confirmation over n > `C.win` or non-overlapping
   windows, Norouzi et al. 2006) is the next step and is not implemented now.
6. **After the adoption.** The whole-monitor reading of C1d (`MONP`, `confirm_sweep`) then runs
   with the adopted test on all 300 validation geometries, as C2 reads it. That is mildly
   optimistic for C2's selection only. KPI 6's verdict comes from a fresh clean test set.
7. **What it does not read.** The rule reads alarm delays only. F3 also changes the rule's
   answer on a degraded link with a quiet slot. That cost lands in recovery: the adopted
   candidate's held recovery per threat is read in C2's validation rows and reported beside the
   adoption. It does not reopen the choice.

## 4. Validation without in-sample optimism

- **The split.** `clean_halves.m` splits the clean validation geometries by a hash of their id
  (Knuth's multiplicative hash mod 2^32, one xor shift): the floor(n/2) with the smallest hash
  fit, the others check. For 300 geometries that is 150 each; it does not depend on the order
  of the ids.
- **Fit half.** `ber_q` and its bins come from the fit half only. F1's mean reference stays the
  existing table over all 300 geometries (`clean_ref_rebuild.m`).
- **Check half.** Adoption is decided on the check half: 150 geometries x the Eb/N0 points from
  the KPI 1 threshold up (900 clean episodes at six points; a bound <= 5% then needs about 34 or
  fewer).
- **Threat delays** come from the validation split, as in C1d now.
- **KPI 6** is read on a fresh clean test set: a new seed family, generated after adoption, at
  least 600 flights.

## 5. Switch, deployment and bit-identity

- **Switch.** `"deg_select": true` in the checkout's `profile.json` (`deg_options.m`), or
  `CFG.deg_select`. Without it C1d runs nothing new and saves the same variables in the same
  order. Profile 1's running chain and any run without the switch are unchanged.
- **Outputs.** With the switch, `data/drop_threshold.mat` adds:
  - `deg_mode` and `ber_q` (the adopted alpha's table, `[]` for F1 or `'ratio'`);
  - `DEG`: every candidate's readings, the tables per alpha, the fit and check geometries.
  The report goes to `results/drop_threshold.txt`.
- **Deployment.** `train_dqn.m` sets `PP.deg_mode` and `PP.ber_q` from that file, as it sets
  `PP.confirm_sweep`. Every policy, the rule fallback's own monitor (`rule_sel`) included, and
  `dec` carry them. Every reader applies them through `decision_settings.m`.
  `policy_stamp.m` includes them only when they are set, so earlier stamps stay.
- **The table's home.** The table travels with the decision settings (as `confirm_sweep`). It
  is not written into `policy_pools.mat`, so P1R needs no C1c and the pools file is not
  rewritten.
- **Logging.** `M.deg_quiet` (per cycle), `R.deg_quiet` (`rollout_policy.m`: cycles per episode,
  F3 only), and C1d's count of check-half clean episodes and threat episodes with such a cycle.

## 6. Registered, not implemented

- **F0.** If D103 3(e) shows the false changes front-loaded in the first `C.win` - 1 cycles, F0
  joins ahead of F1 under the same rule: the degradation test runs on a full window at an
  episode's start, with the frames before cycle 1 simulated so the window is full, as on a link
  that runs continuously. After a change's arrival the window stays as now. It needs the
  episode start in `link_env.m` and is not trivial, so it is not implemented before that
  reading.
- **F4.** See section 3, point 5.

## 7. Training consistency

- The DQN's false-switch penalty applies only on `healthy` geometries (`link_env.m`), while KPI
  6 counts every clean flight. Under F3 that mismatch shrinks.
- The penalty's definition is not changed: that would be a reward redesign without a source.

## 8. Tests (`code/tests/test_deg_mode.m`)

| Test | What it checks |
|---|---|
| `test_ratio_bit_identical` | `'ratio'` and the default give the parent commit's (899e1c6) `M` and memory bit for bit on a trace with degradation, a drop, hostile classes, a coded link and delayed changes |
| `test_win_median_lookup` | The lookup Eb/N0 is the window median with one +3 dB frame, on the measured axis under a known gain |
| `test_win_window_resets_at_arrival` | The windows restart with `mem.ber` at a change's arrival, not before |
| `test_windows_match_monitor` | The table's statistic is the monitor's own |
| `test_quantile_reproduces_alpha` | alpha is reproduced on Gaussian log-BER |
| `test_quantile_bins_merge` | Bin merging (cycles, flights, ties, the short flag) and the lookup |
| `test_halves_disjoint` | The halves are disjoint, 150/150 and order-free |
| `test_clean_ber_q_fit_half_only` | The tables read the fit half only and the validation set only |
| `test_win_q_threshold` | F2's threshold and its floor |
| `test_gate_needs_quiet_slot` | F3's gate, the deployed `q_thr` and the logged flag |
| `test_class_drop_unchanged` | The class and drop paths do not depend on `deg_mode` |
| `test_adoption_rule` | The adoption rule on synthetic delays and bounds |
| `test_switch_off_keeps_outputs` | The switch and the unchanged save list |
| `test_settings_and_stamp` | `decision_settings` and the stamp |

Smoke: profile 3's own smoke exercises the default. One smoke cell per candidate (2 h cap)
before P3's queue, each cell's candidate forced by the smoke-only switch `deg_force`
(`docs/p1r_protocol.md` section 6).

## 9. Sources

- Xu et al. 2005: consistency of delivery ratio with signal strength or interference.
- Kazim 2026: power plus quality, threshold from interference-free samples.
- López-Benítez 2016 and Grimaldi 2019: CFAR from the noise power alone.
- Norouzi 2006: k-of-n under independent samples.
- Xie 2021 and 2022: ARL, window-limited CUSUM.
- Thulin 2014: Clopper-Pearson.
