# Noise bursts and the coded link: pre-registered protocol

Written 25.10.2026, before profile 1's C1d and C2 have run, before dev set C exists and before
any reading of the readings below. Code on `lect-kpi`; tests in `code/tests/test_core.m`
(section 6).

## 1. The defect

The rule maps the class `noise_burst` to `power_control+fec_interleave`, or
`spatial_diversity+fec_interleave` when the interferer is separable (`rule_based_policy.m`). In
the gallery that answer makes the link worse: BER 4.39e-01 with no response, 4.95e-01 with it
(`v7_report_gallery.log:474`). The pools, the gallery and every reader hold the decoded BER, FER
and CRC of a coded configuration (`closed_loop_truth.m`, `fec_packets.m`), decoded with the D78
erasure rules:

- **Antenna-1 energy test.** A symbol is erased when its energy on antenna 1's raw samples is
  above 4 x the median of the codeword's frames, widened over symbols j-7..j+3 around it
  (`movmax(..., [3 3+tm])`, 11 symbols). Under J4 (duty 0.2, one-symbol bursts) that erases
  1 - 0.8^11 = 91% of the symbols. Under the random jammer at duty 0.5 or more the median sits
  inside the bursts and nothing is flagged.
- **Raw antenna 1 under MMSE.** The test reads antenna 1 before combining
  (`extract_closed_loop_frames.m`), so under `spatial_diversity` it erases symbols that the MMSE
  null has already cleaned.
- **Pilot-error frame erasure.** `pilot_err > 0.80` was set on dev frames without bursts
  (D78). Bursts on the pilots erase the whole frame.
- **Result.** With every bit erased the Viterbi output is a fixed tie-break: the flat 0.495.

The receiver's front end has the same median reference: the robust training LS and the
pilot-block burst check (`build_threat_model.m`) treat as a burst a residual above 4 x the
median residual. At duty 0.5 or more a burst over the training corrupts the whole frame
(`d84_rx.md`). That front end is not changed here (section 4.6).

Physics limits the code even with a perfect decoder. Capacity per coded bit, ideal interleaving
and per-symbol jammer state information, single branch, Eb/N0 9 dB (rate 0.503 needed):

| in-band JSR [dB] | 4 | 10 | 16 | 23 | 30 |
|---|---|---|---|---|---|
| J4, duty 0.2 | 0.82 | 0.67 | 0.54 | 0.38 | 0.24 |
| random, duty 0.5 | 0.62 | 0.53 | 0.51 | 0.50 | 0.50 |
| random, duty 0.775 | 0.41 | 0.28 | 0.24 | 0.23 | 0.23 |

At duty 0.775 and 0 dB in-band (what MRC can leave of 4 dB against an uncorrelated jammer) the
capacity is 0.59; at 6 dB it is 0.35. These are our own calculations from the model's parameters,
not quoted results. DuPree (1992) says the same in words: interleaved FEC protects only below a
critical burst duty. So a better decoder does not make the code the answer to noise bursts. It
matters for J4 at 4-16 dB, for the recoverable denominators and for what the DQN, the table and
the oracle learn.

## 2. Profile 1: the rule's answer chosen on validation (no pool rebuild)

Profile 1's pools stay as they are. Only the decision layer changes. It is merged in the stop
window after SURV3, before the re-key and C1d, with the other `lect-kpi` merges. SURV and SURV3
do not read the rule.

### 2.1 Code

- `rule_based_policy.m`: a 10th argument `burst_action`, `{not separable, separable}`, two of
  the 36 configurations other than `no_action`. Empty keeps the class mapping, so every
  one-argument reader (the detection-equivalence grouping of B3, OOD, B4s and EDGE's DET) is
  unchanged.
- `rule_core_policy.m`: a 9th argument `burst_action`, a core action, default `rate_reduce`
  (today's). It acts on `noise_burst` only. `sweeping_jammer` keeps `rate_reduce`.
- `policy_decide.m` passes `PP.rule_nb` to the rule and `PP.core_nb` to the core rule.
  `decision_settings.m` copies both. `policy_stamp.m` adds them to the stamp only when they are
  set, so a file without them keeps its stamp.
- `train_dqn.m` (C2, step 3a) chooses them (2.2). They are stored in `rule_sel` and `dec`
  (`data/trained_dqn.mat`), and every reader applies them through `decision_settings`: C2e (rule,
  rule_esc, rule_core, the rule fallback), C2g, C2u, EDGE, LAT, the console, the 3D view and
  CORE_BW.
- `threat_gallery.m`: the expert-rule fallback uses `dec.rule_nb` when it exists.
- Not changed: the pools, the 36 configurations, the DQN and table action set, `C.ladder` (its
  coded steps 3 and 6 are shared by every threat), and C1d (it does not run the rule).

### 2.2 Candidates (`burst_candidates.m`), cheapest first

The order is the reward's running cost (`link_env.m` K.cost); a configuration with
`channel_switch` comes after its twin without it.

| step | candidates | in force before the step |
|---|---|---|
| not separable | `power_control`, `rate_reduce`, `rate_reduce+power_control`, `channel_switch+rate_reduce+power_control` | `rate_reduce+power_control` |
| separable | `spatial_diversity`, `spatial_diversity+power_control`, `spatial_diversity+rate_reduce+power_control` | `spatial_diversity+power_control` |
| core rule | `rate_reduce`, `channel_switch+rate_reduce` | `rate_reduce` |

On pools decoded with the D78 rules (profile 1's) no candidate is coded: those rules erase the
symbols the code needs (section 1), so a choice made on the coded entries would rest on a known
bias. On pools decoded with the JSI decoder (section 3) `power_control+fec_interleave` and
`spatial_diversity+fec_interleave` join, in cost order. The class mapping's coded answer is
evaluated once and printed as a reference row. It is never a candidate.

### 2.3 Statistic and selection (`nb_pick.m`)

On C2's validation episodes, at the reference monitor, with the common random numbers of the
other settings:

1. **Eligible:** one-sided 95% false-alarm bound <= 5% (none: the three with the lowest bound).
2. **Pooled guard:** pooled held recovery within 0.005 of the best eligible one.
3. **Primary:** `nb_held`, the held recovery (KPI 4 "held") of the recoverable validation
   episodes whose true threat holds a noise burst (the single threat and its four
   combinations, severities pooled). Within 0.01 of the best.
4. **Ties:** the highest pooled recovered, then the highest return, then the cheaper. The
   setting in force has no preference.
5. **Small sample:** with fewer than 10 such episodes step 3 is skipped.

### 2.4 Order in C2

The steps run after "nulling threshold and quiet slot" (the threshold decides the branch):
"not separable", then "separable", then the proposal dwell and the later steps. `S0` holds the
uncoded start values, so no earlier step is scored with the defective answer. The core step runs
after them on `rule_core` (`opt.core`), with the chosen settings. Then the reference row. Cost:
3 + 2 + 2 validation evaluations and one reference evaluation, the same evaluator and episodes as
the other steps. Nothing is shortened.

### 2.5 Labels in profile 1's report

- Rule baseline: "the rule's noise-burst answer was chosen on validation (C2) among uncoded
  configurations: <chosen> / <chosen, separable>; core rule <chosen>".
- Coded configurations: "decoded with the D78 erasure rules (pilot-error frame erasure, set on
  dev frames without bursts; antenna-1 energy test against the codeword's median, widened by 11
  symbols). Under intermittent interferers these rules erase symbols the code needs, so the
  coded entries understate a rate-1/2 code, most of all for J4 bursts at 4-16 dB." The DQN,
  the table, the oracle and ladder steps 3 and 6 carry this limit.
- KPI 4 and the envelope for noise bursts: "recoverable under profile 1's link model".
- B3, OOD, B4s and EDGE DET keep the class mapping they ran with.

## 3. New pool builds: the JSI decoder behind a recorded switch

### 3.1 The switch

`profile.json` field `fec_rx` (`fec_rx_config.m`):

- absent: nothing stated. A full C1p (`build_policy_pools.m`) refuses to start; the smoke uses
  the D78 rules.
- `"d78"`: the D78 rules. The params stay as they are, so cell keys, `params_id` and pools are
  those of today's code.
- `{"mode": "jsi", "rev": ..., "q": ..., "c": ..., "h": ..., "erase_sym": ..., "frame": ...,
  "thr": ..., "flag_clean": ...}`: the JSI decoder with the values of section 4. It enters the
  params as `p.fec_rx` (so every cell key), `PP.fec_rx`, and `PP.model_tag` = `MODEL_TAG + "+" +
  rev`, so pools of another decoder are never reused. The check and clean pools take the
  decoder of the policy pools (`fec_rx_of(PP)`) and record it. SURV, its options experiment and
  the gallery read `profile.json` too.

Profile 1 has no `profile.json`. Its existing pools carry no `fec_rx` and read as D78
(`fec_rx_of.m`). Nothing in profile 1's remaining chain builds policy pools, and every derived
pool follows its policy pools. Profile 1 is therefore off by construction. Only `init_params`
reads `n_rx` from the same file, so `params.mat` and `params_id` do not move. The bandwidth
study builds only the four core configurations: no coded truth, no change.

### 3.2 The decoder (`fec_packets.m` with `J`, `jsi_inputs.m`, `jsi_floor.m`)

- **Residuals on the combiner output** (after sync and any MMSE null). For each data symbol:
  `r_k = |z_k - g_b s_k|^2`. `g_b` is the 32-symbol block gain, the median of the real and
  imaginary parts of `z conj(s)`. The block mean of `bit_reliability.m` is not used here: a
  30 dB burst on a fifth of a block moves the mean by several times |g|, and every residual
  with it.
- **Floor per codeword** (2064 data symbols). Start from the q-quantile over -ln(1-q). With a
  share f of clean symbols this start is about 1/f too high (x5 at duty 0.775). So eight passes
  of the truncated exponential's maximum likelihood follow, below 3 x the current floor, never
  above the start. With our own simulation of exponential residuals:
  - random duty 0.5 and 0.775 at 30 dB: 1.00-1.02 x the thermal variance (the start: 2.2 and 5.4 x);
  - J4: 1.6-1.9 x, because the RRC leaks raise most symbols.
- **Per-symbol variance:** `max(floor, mean r over k-h..k+h)`. Each bit enters with
  `2 sqrt(2) |Im| or |Re| of conj(g) z` over it: per-symbol JSI (Baldi et al. 2013).
- **Symbol flag:** the variance above `c x floor`. With `erase_sym` the flagged symbols enter
  as erasures (a zero metric, IEEE 802.11-2007), otherwise with their low weight alone.
- **No widening.** Each neighbour's residual carries its own RRC leak (0.068, 0.0073, 0.0013 of
  the burst at 1, 2, 3 symbols; roll-off 0.25, span 10).
- **No antenna-1 energy test.**
- **Whole frames:**
  - `frame` a: `pilot_err > p.erase_pilot_mse` (today's rule);
  - `frame` b: none;
  - `frame` c: `pilot_err > thr` only in a frame whose flagged share is below
    `3 x flag_clean` (a frame without bursts, where the pilot error measures the estimate).

Not in this commit: the design's variant (d), a robust pilot error as a new receiver output row.
It needs a model rebuild and a bit-identity test of every other output. Neither can be verified
without running the model, so (d) is not a candidate in this protocol. Part B of the design
(the front end's training LS and pilot-block check against the thermal floor) changes the
features. It belongs to a chain rerun from A0 only, and is not done here.

## 4. Dev set C and the choice (`code/dev/dev_fec_burst.m`)

The decoder is chosen on dev flights only: never the pools, the tests or V-flights. Dev set C
runs in the tree whose pools will be built, with its `profile.json` (`n_rx`). For profile 3 that
is `uav-gcs-v7-p3` after its merge.

### 4.1 Flights (`dev_fec_burst('flights', out)`)

Link seeds 7801-7860, 60 flights x 20 frames per point, nominal Doppler. The block is disjoint
from every pool, test, check and earlier dev seed (`test_seed_streams_disjoint`).

| points | levels | Eb/N0 | configurations |
|---|---|---|---|
| noise burst: J4 (duty 0.2), random at duty 0.5 and 0.775 | 4, 10, 16, 23, 30 dB | 9 dB | no_action, power_control, spatial_diversity |
| sweeping jammer, reactive jammer, WLAN | 16, 30 dB | 9 dB | the same three |
| D78's jammer points | 16 dB, MMSE | 6, 12 dB | as in D78 |
| | 30 dB, 234 ns, rho 0.3, K 10 dB, MMSE | 12, 15 dB | as in D78 |
| clean link, K drawn | - | 0, 3, 9 dB | the same three |

Per flight the stage keeps the truth inputs without antenna 1's samples, the uncoded BER, the
pilot error of every frame, and the D78 decoder's result on the same frames (the reference).

### 4.2 Choice (`dev_fec_burst('select', out, rev)`), order fixed now

1. `c` for h = 0 and h = 1: the smallest on 2:0.1:12 that flags at most 1% of the clean points'
   data symbols against each codeword's floor (q = 0.05). D78's own criterion.
   `flag_clean(h)`: the share flagged at that `c`.
2. `thr`: the smallest on 0.05:0.05:3 whose pilot error flags at most 1% of the frames with
   uncoded BER <= 0.2, over every point (bursts included).
3. Variants: frame b, c, a; then h 0, 1; then `erase_sym` false, true. That order is also the
   tie order (simpler first).
   - **Qualified:** at no D78 point and no clean point does the variant lose more than Q/2 = 2
     packets (one loss event of the coded link, `packet_share.m`) beyond the D78 decoder.
   - **Chosen:** the lowest pooled packet loss over the intermittent points (noise bursts,
     sweeping, reactive, WLAN). Equal counts go to the earlier variant.
4. **Adoption needs all of:**
   - **Floor check.** On the clean link at 9 dB under no_action, the median over codewords of
     floor / mean residual is within 1 dB.
   - **J4 decodes.** J4 at 4 and 10 dB under no_action (MRC) has packet loss <= 2 x the clean
     link's at 9 dB. The clean loss is floored at one packet of the point's packets. Capacity
     0.82 and 0.67 there.
   - **Random 0.775 does not decode** under no_action at 10, 16, 23 and 30 dB (capacity below
     the rate). If it decodes, the bound has been broken: stop and look before anything else.
     At 4 dB MRC can lift the capacity above the rate (0.59 at 0 dB in-band), so that point is
     reported only.
   - **Reported beside the capacity table:** the decoded BER of D78 and of the chosen variant.
5. **Output.** The JSON of `profile.json`'s `fec_rx`: the chosen variant, or `"d78"` when it is
   not adopted. `rev` names the DECISIONS entry that records the dev table.

### 4.3 Records and profile 3

- A DECISIONS entry (`rev`) with the dev table, the checks and the choice.
- Profile 3's `profile.json` gains `fec_rx` (the chosen value, or `"d78"`) in one commit before
  `p3_c1p.hold` is released. Without it profile 3's C1p refuses to start.
- Profile 3 then runs the same C2 step (2.4). With the JSI decoder its candidate sets hold the
  two coded answers. The report states both candidate sets.
- `rate_reduce+fec_interleave` (rate 1/8) is not added. It would change the action set, the DQN
  and the pools. Even it fails the random jammer at duty 0.775 from about 16 dB (capacity about
  0.36 < 0.5). Adi decides.
- A profile 1 bridge (re-simulating only the coded configurations of its noise-burst cells as a
  labelled sensitivity table) is optional and needs compute. Adi decides.

### 4.4 Labels across profiles

- Profile 1: "FEC decoded with the D78 erasure rules".
- Profile 3, when adopted: "FEC decoded with per-symbol JSI and residual erasures (rev)".
- A difference between the profiles in a coded configuration or in noise-burst recovery is not
  attributable to the antennas. Cross-profile tables show those rows separately.

## 5. Sources

- Baldi et al. 2013 (`V7_Baldi2013_...`): pulsed jamming, JSI as per-symbol variance.
- DuPree 1992 (`V7_DuPree1992_...`): coding protects only below a critical burst duty; about
  1 dB loss at 10% duty or less with erasure decoding.
- Ercan et al. 2023 (`V7_Ercan2023_...`): jammed values flagged against the constellation (3
  sigma); frame erasures to bit erasures by interleaving.
- IEEE 802.11-2007 (17.3.5.5): a zero metric for removed bits.
- Garcia-Pena et al. 2021 and Epple 2012: blanking against the receiver's own reference (part B,
  not done).

No source gives `c`, `q`, `h` or `thr`; they are set on dev set C by the criteria above. These
are our own calculations from the model's parameters, not quoted results:
- the capacity numbers;
- the RRC leaks;
- the floor's 1/f bias;
- the truncated refinement (the mean of an exponential truncated at T).

## 6. Tests (`code/tests/test_core.m`)

- `test_rule_noise_burst_setting`, `test_rule_core_burst`: without the setting every answer and
  reason is lect-kpi `8b396e6`'s; each candidate moves only `noise_burst`; bad values refused;
  the candidate sets and their cost order.
- `test_settings_noise_burst`: `decision_settings`, `policy_decide` (rule vs core),
  `policy_stamp` (unchanged without the fields).
- `test_nb_pick`: primary, bound, pooled guard, each tie, the small sample, no candidate within
  the bound; C2's step order and the reference row.
- `test_fec_rx_switch`: `profile.json` values and refusals; D78 leaves the params unchanged; the
  builders' wiring and C1p's refusal.
- `test_jsi_floor`, `test_jsi_inputs`, `test_jsi_tails`: the floor under clean, J4, random and
  continuous residuals; the residuals and rails; flag rates at offsets 1-3 follow the leaks.
- `test_fec_packets_jsi`: clean decode; J4 under MRC decoded where D78 loses the packets;
  antenna-1 bursts with an MMSE-cleaned output decoded where D78 erases the clean symbols; the
  frame variants; `closed_loop_truth` without `p.fec_rx` is D78 and `fec_packets`' D78 path is
  `8b396e6`'s bit for bit.
- `test_seed_streams_disjoint`: dev set C's seeds.
