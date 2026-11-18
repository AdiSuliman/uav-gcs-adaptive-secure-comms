# D2c reading: receiver loss bound for CORE_BW (rule 3, `rx_fix_rule3.md`)

Run 18.11.2026, 18:31-22:44 (253.3 min), one MATLAB through the gated wrapper (single thread):
`rx_d2c(d2c, rx-ne-fix, uav-gcs-v7-bw)`. Log `uav-gcs-v7/logs/hand_d2c_v2_20261118_1810.txt`.
Output `worktrees/d2c/results/rx_d2c_20261118_2244.mat` (SHA-256 `03aa92c88dd025da073b0bc31d1035105cbc52f87d7f92994fc5bf33384bc042`).
Rule file SHA-256 `d058fd366799a61632ee529938ef572347e62032e56595277d1e5981c0deeb19`.

## Guards

| Guard | What it checks | Result |
|---|---|---|
| G1 | taps change nothing: 35 combinations, max abs difference 0 | PASS |
| G2 | receiver blob r1 `40dc1f9a`, params copy equals `uav-gcs-v7-bw/params.mat` | PASS |
| G3 | no CORE_BW data or results under the harness folder; the design as CORE_BW flies it (14 of 14 lines); every layer in its cell's grid; 33 jammed combinations of the core set | PASS |
| G4 | clean twins: L <= 0.1 dB on 5760 of 5760 frames (max 0.000 dB); L_opt likewise | PASS |

D2c is valid.

## Bound per state (validation, 72 geometries per pass, 12 and 15 dB)

| State | n_s eligible | k_s collapse | flights | U_s (one-sided 95% CP) | Label |
|---|---|---|---|---|---|
| narrowband | 1295 of 2880 (55.0% ineligible) | 260 | 69 (at most 14 in one) | 21.9965% | receiver-limited |
| wideband | 2265 of 2880 (21.4% ineligible) | 142 | 43 (at most 16 in one) | 7.1721% | receiver-limited |

Both states meet the n_s >= 1200 target. U_s > 1 pp in both, so every CORE_BW number of a jammed state that enters the book carries "r1; receiver loss on the restored link <= U_s (D2c, validation)" and the label "receiver-limited". The clean state keeps <= 0.25 pp at 12 dB.

## The lecturer's PER-reduction verdicts (KPI 8)

Margin |dRed| <= U_s / (PER_static,s - U_s), with PER_static,s as CORE_BW's report prints it (`uav-gcs-v7-bw/results/core_bw/core_bw_report.txt`, SHA-256 `02e2624182e2c94726639838a123e48e894771f6733acd4d505e2e76b427768d`): narrowband 0.2200 / (0.9966 - 0.2200) = 28.3 pp, wideband 0.0717 / (0.8692 - 0.0717) = 9.0 pp. A verdict is receiver-robust when its point and its 95% lower bound both lie farther than the margin from 30%.

Primary (H1, nRF24L01+ residual by offset, fixed total power, static jammer):

| Policy | State | Reduction [95% CI] | Verdict | Side column |
|---|---|---|---|---|
| rule_core3 | narrowband | 62.3% [59.1, 65.4] | MET (committed) | receiver-robust (> 58.3%) |
| rule_core3 | wideband | 69.2% [67.8, 70.5] | MET (committed) | receiver-robust (> 39.0%) |
| rule_core (hybrid, secondary) | narrowband | 62.2% [60.6, 63.7] | MET (committed) | receiver-robust |
| rule_core (hybrid, secondary) | wideband | 65.8% [64.4, 67.0] | MET (committed) | receiver-robust |
| blind_core | narrowband | 70.4% [69.0, 71.6] | MET (committed) | receiver-robust |
| blind_core | wideband | 62.9% [60.9, 64.8] | MET (committed) | receiver-robust |

Every primary per-type verdict is receiver-robust. The pooled second lines have no state bound and keep their words.

Sensitivities (no verdict of their own): every wideband verdict is receiver-robust except H4's hop rule for rule_core3 (38.3% [36.8]) and blind_core (39.8% [38.2]) and the follower jammer rows. In narrowband, 4 of the 18 sensitivity rows are receiver-robust (blind_core with the 30 dB residual under H1 and H3; rule_core and blind_core under H3's hop rule); the other 14 print "within the receiver bound" beside their words (the 28.3 pp margin needs 58.3%). No verdict word changes.

With no receiver adopted before the book, D2c is ruling 4.2's bound for CORE_BW.
