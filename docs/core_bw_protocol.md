# The bandwidth study (experiment_core_bw): protocol

Branch `core-bw` (from `lect-kpi` `394d4da`). This protocol is fixed before any run. The
validation stage writes its SHA-256 into `results/core_bw/protocol.json`; the test stage reads the
test split only while this file is unchanged, committed, and the frozen choices are committed as
`docs/core_bw_frozen.json`.

## 1. What it answers

The revised proposal (D92) asks for jamming "of different bandwidths, which affect how the
interference energy is distributed over frequency and the link's performance", and for the two
scenarios "at several JSR levels, with a controlled definition of the bandwidth and the jammer
power". Its research question: does CNN classification plus adaptive recovery beat a static link
and a mechanism that uses link metrics only?

The main pipeline cannot answer the bandwidth part: `channel_switch` lowers every in-channel
interferer by the fixed `cm_acr_db` = 30 dB, so a hop escapes the barrage exactly as well as the
tone, and the core rule maps both jamming classes to `channel_switch`. This study gives the hop a
frequency geometry (a channel plan and hop rules) and the jammer a width B_J and a total power.
A hop then escapes a jammer narrower than its distance and not a wider one; at fixed total power a
wider jammer puts less power into our channel.

It is a separate experiment: its own stage, seeds, data and results. It is not a `run_stage`
stage; neither the takeover nor the chain runs it, and it changes no live output.

## 2. Channel plan and hop rules

**Plan (`band_plan.m`).** 41 channels at 2401 + 2k MHz, k = 0..40; our occupied bandwidth
B_ch = (1 + 0.25) x 1 MHz = 1.25 MHz; edges 2400.375-2481.625 MHz, inside the 2400-2483.5 MHz band
(ETSI EN 300 328). The 2 MHz spacing is the nRF24L01+'s for non-overlapping channels at 2 Mb/s, our
raw rate; it is at least B_ch (ETSI's hopping separation). The plan holds 2481 MHz, the channel
Mekdad et al. jammed, and more than ETSI's 15 channels of an adaptive hopper.

**Home channel.** Drawn per episode from the flight seed's `'hop'` stream (`seed_stream.m`,
offset 39), uniform over the channels the cell's jammer covers, the same for every policy.

**Hop rules (`hop_targets.m`).** The k-th hop that reaches the link moves to the k-th channel of
the episode's sequence; each target is taken from the channel before it. Against a jammer tuned to
our channel (section 3) the k-th hop after the onset meets the coverage of the k-th channel.

| Rule | Hop | Source | Role |
|---|---|---|---|
| H1 | pseudo-random, uniform over the plan's channels at least 6 MHz from the channel in use, from the episode's stream (shared by GCS and UAV) | IEEE 802.11-2007 14.6.8: a pseudo-random pattern using the band uniformly, minimum hop 6 MHz (North America, Europe); ETSI uniform use | **primary** |
| H3 | 26 MHz (13 channels) toward the plan's middle channel, up from the middle itself | 802.11: channels 25 MHz or more apart operate without interference | sensitivity |
| H4 | 4 MHz (2 channels) toward the middle, on in that direction, reflected at the edges | the smallest grid hop that leaves a jammer the window shows whole | sensitivity |

A 2 MHz hop is not a rule: the nRF24L01+ rejects its 2 MHz neighbour by only 4 dB at 2 Mb/s
(C/I +7 dBc co-channel, +3 dBc first ACS).

**Re-hops** follow `link_env.m`: a hop is requested when a `channel_switch` configuration follows
one without it, or while the frame just received fails its CRC, and reaches the link after the
signalling delay (1 cycle).

## 3. Jammer: bandwidth, centre, JSR

**Widths (`band_cells.m`).**

| B_J | State | Source | Span used for coverage |
|---|---|---|---|
| CW tone | narrowband | Mekdad CW; Barajas CW; Panitsas tones; `tone_jamming` | the tone's offset range, home +-0.3 MHz |
| 4 MHz | wideband | Liu et al.: 4 MHz instantaneous bandwidth, raised cosine, roll-off 0.3, read as its noise bandwidth (below) | +-2.6 MHz, the occupied edge (1 + 0.3) x 2 MHz |
| 8 MHz | wideband | Mekdad et al.: Gaussian noise at 10 MS/s, low-pass 4 MHz, 1 MHz transition | +-4.5 MHz, the stopband edge |
| 20 MHz | wideband | Panitsas et al.: a $20 dongle covering 20 MHz | +-10 MHz |
| 70 MHz | wideband | Panitsas et al.: AWGN over 802.11 channels 1, 6, 11 (20 MHz each) | fixed 2402-2472 MHz |
| 83.5 MHz | wideband | the whole band, inside the 160 MHz of Panitsas et al.'s radio | 2400-2483.5 MHz |

Noise jammers of 4-20 MHz are centred on the channel we use at the onset (Mekdad et al. tuned to
the target's channel), the tone likewise: our home channel, or the channel a hop made before the
onset moved us to, so such a hop escapes nothing and the hops after the onset meet the same
coverage under every policy (`link_env.m` spec.cover_rel). The 70 MHz jammer sits where Panitsas
et al. put it and the whole-band one everywhere; they cover whatever channel we use. Every B_J >= 4 MHz fills the
receiver's +-2 MHz window flat, so it is the existing barrage `jamming` waveform at its in-band
level; Liu's raised-cosine edge is kept white. Narrowband noise (0.3125, 1.25 MHz) needs a new
generator and is not part of this study (Tier 2, not run).

**Liu et al.'s 4 MHz.** The paper gives the user's signal and the jammer as raised-cosine
waveforms of roll-off 0.3 and their bandwidth as 4 MHz ("the instantaneous bandwidth of the
jamming is set to be 4MHz"), and never says whether that is the symbol rate (the noise-equivalent
and -3 dB width; occupied (1 + 0.3) x 4 = 5.2 MHz) or the occupied width (symbol rate
4 / 1.3 = 3.08 MHz). Its geometry leans to the occupied width (K = 9 positions 2 MHz apart in a
20 MHz band, so centred 2-18 MHz, and comb signals at 2, 10 and 18 MHz: with 4 MHz occupied the
edges fall exactly at 0 and 20 MHz) but does not settle it, since a simulation may let the
roll-off pass the sensing band. Both readings are
physical, so the study takes the one more severe for our link, the noise bandwidth. At fixed total
power it puts 1.14 dB less into a covered channel (-6.02 against -4.88 dB), and its occupied edge
lies 0.6 MHz nearer every hop target, which costs an escaped hop a row of the rejection (section 4):
H1's 6 MHz hop keeps 4 dB instead of 24, an 8 MHz hop 24 instead of 28, H4's 4 MHz hop none instead
of 4 dB. For every reading of the study both effects work against the adaptive systems: less harm
to the static reference and less rejection after a hop.

**JSR (`jsr_inband.m`).** The controlled variable is the total power JSR_tot = P_J / P_S (Liu
et al.: a 30 dBm jammer against a 0 dBm signal). The model's level is the in-band ratio after the
matched filter, in which tone and white noise are equal in band: tone `tone_jsr_db` = JSR_tot;
covering flat noise `jsr_db` = JSR_tot - 10 log10(B_J / 1 MHz) (-6.02, -9.03, -13.01, -18.45,
-19.22 dB for 4, 8, 20, 70, 83.5 MHz). No roll-off factor enters: it is common to tone and noise.

**Levels.** JSR_tot in {4, 10, 16, 23, 30} dB, the decision layer's five levels, the top Liu's
30 dB: 30 cells. The 30 dB in-band cap is never exceeded (JSR_in <= JSR_tot).
**Equal in-band level (secondary).** JSR_in in {4, 10, 16, 23} dB of the barrage (4 cells; one
cell serves every B_J >= 4 MHz), read only where the implied total stays at or below 30 dB:
4 MHz all four; 8 and 20 MHz 4-16 dB; 70 and 83.5 MHz 4 and 10 dB (14 scenarios).

**What the receiver sees.** A 4 MHz jammer at JSR_tot 16 dB and an 83.5 MHz one at 29.2 dB give
identical frames: no detector on this receiver can tell a jammer a hop escapes from one it cannot;
only the post-hop link metrics, through the escalation, can. The claim "the CNN tells partial-band
from band-wide" is never made.

## 4. The actions on each B_J (`band_cover.m`, `link_env.m` spec.cover)

**Coverage of a channel** against the jammer's span: covered when our band lies inside it;
escaped when our band is clear of it (touching counts as clear) and the receiver's rejection
there is sourced (below: 2 MHz or more from the jammer); partial otherwise, counted as covered
(conservative against `channel_switch`; its share is reported). A channel clear of the jammer by
under 2 MHz also counts as covered (its share is reported).

- `channel_switch` on an escaped channel: the frames of that channel's residual layer (field - R,
  below).
- `channel_switch` on a covered channel: the frames of the same configuration without it, in the
  same geometry (as after a follower's re-acquisition).
- `rate_reduce`: +6.02 dB processing gain on any B_J, goodput x 1/4.
- `channel_switch+rate_reduce`: both; covered, the `rate_reduce` frames at a switch's cost.

**Residual after an escape: the nRF24L01+'s rejection by offset (primary, `band_reject.m`).**
The rejection R of a channel is the sheet's co-channel C/I minus its C/I at the offset (2 Mb/s,
our raw rate; Table 8, ETSI EN 300 440-1): +7 dBc co-channel; +3, -17, -21, -40 and -48 dBc at 2,
4, 6, beyond 12 and beyond 36 MHz, so 4, 24, 28, 47 and 55 dB; at the offsets n x 2 f_xtal (32 and
64 MHz, f_xtal 16 MHz) about 5 dB less, 42 and 50 dB. The geometry the code measures is d, the
distance from our new carrier to the jammer's nearest frequency (`band_cover.m` off), and the
offsets the jammer occupies, d to its far edge. Each channel takes the lowest rejection the sheet
gives over those offsets: the row at or below d (4 dB from 2 MHz, 24 from 4, 28 from 6 to 12, 47
beyond 12, 55 beyond 36 MHz), and 42 or 50 dB where they hold 32 or 64 MHz. Below 2 MHz the
sheet's only row is co-channel: such a channel counts as covered. The 2 Mb/s rows are the sheet's
most severe at every offset from 2 MHz (1 Mb/s: 29, 39, 49, 56 dB; Table 9, a modulated
interferer: 7, 29, 35, 51, 59 dB); at 2 Mb/s the nRF's 20 dB bandwidth is 2 MHz, ours 1.25 MHz.
802.11-2007 is milder where it applies: the FH PHY's desensitization of at least 30 dB at 2 MHz
and 40 dB from 3 MHz (Table 14-19, 1 MHz channels), 35 dB adjacent-channel rejection at 25 MHz and
more (18.4.8.3); its -30 dBr (15.4.7.4) is a transmit mask, not a receiver's rejection.

| hop from the jammer's centre | 2 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 64 MHz |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CW | c | 4 | 24 | 28 | 28 | 28 | 47 | 47 | 47 | 47 | 42 | 55 | 50 |
| 4 MHz | cov | c | 4 | 24 | 28 | 28 | 28 | 47 | 47 | 47 | 42 | 55 | 50 |
| 8 MHz | cov | cov | c | 4 | 24 | 28 | 28 | 28 | 47 | 47 | 42 | 47 | 50 |
| 20 MHz | cov | cov | cov | cov | cov | 4 | 24 | 28 | 28 | 42 | 42 | 42 | 50 |

(R in dB; cov covered by geometry, c clear by under 2 MHz and counted covered.) The 70 MHz jammer
leaves 2475 MHz at 4 dB, 2477 at 24, 2479 and 2481 at 28; 2401 and 2473 MHz, 1 MHz off its edges,
count as covered.

The frames of an escaped hop come from the layer of its rejection: the same cell's
`channel_switch` configurations simulated with `cm_acr_db` = R (`PP.acr_pools`, `link_env.m`
spec.acr), on both splits. A cell gets the layers its hops can meet (`band_reject.m` 'layers', the
jammer centred on any channel): CW, 4, 8 and 20 MHz all seven, 70 MHz 4, 24 and 28 dB, 83.5 MHz
none; an equal-level cell those of the widths it serves (all seven). The recoverable rule reads the
same layer (section 6.4). The main pipeline's 30 dB (`cm_acr_db`) stays as it is there.

**Sensitivity** (test only, no choice): 30 dB on every channel clear of the jammer by geometry,
the pipeline's value (the pools' own `channel_switch` frames, `band_cover.m` alone).

**Fading after a hop** is not redrawn: the same statistics on every channel; keeping it withholds
from the hop its escape from a deep fade, conservative for every adaptive system.

**H1 escape share of one hop** (centred jammer, the enumeration): CW and 4 MHz 1; 8 MHz 34/36
mid-band to 37/38 at the edge (its 6 MHz hop is 1.5 MHz off the edge); 20 MHz 30/36 to 35/38;
70 MHz: 2475-2481 MHz escape (four; the home is drawn among the 37 other channels); 83.5 MHz 0.

## 5. Predictions (written before any run) and their fixed readings

- **P1.** Narrowband: `rule_core` recovers >= 90% of the recoverable CW episodes at JSR_tot
  <= 23 dB; at 30 dB, where recoverable episodes exist, its median detection-to-restored time is
  longer than `blind_core`'s (a first hop 6-12 MHz away leaves 6 or 2 dB in band; the rule needs
  the escalation to channel_switch+rate_reduce, which `blind_core` takes first).
- **P2.** Wideband 4-20 MHz under H1: the hop escapes; W chosen on validation is
  `channel_switch` or `channel_switch+rate_reduce`.
- **P3.** 70 and 83.5 MHz at JSR_tot 30 dB: no scenario point recoverable by the core set.
- **P4.** 20 MHz and wider at JSR_tot 4 dB (in band <= -9 dB): no scenario point harmful.
- **P5.** The CNN's contribution is mainly goodput: on the narrowband episodes both systems
  recover, the goodput difference `rule_core` - `blind_core` has a 95% lower bound above 0 and the
  PER difference's interval holds 0.

Each is reported as holds / does not hold; none changes a KPI verdict.

## 6. The experiment

**6.1 Grid.** B_J {CW, 4, 8, 20, 70, 83.5} MHz x JSR_tot {4, 10, 16, 23, 30} dB (30 cells) and
the 4 equal-level cells; Eb/N0 0:3:15 dB per branch; the pools' nested Latin hypercube over speed,
altitude, K, the first interferer's direction and the receive correlation; hop rule H1 (H3, H4 on
the same pools); residual by offset (section 4, its layers on both splits; the pipeline's 30 dB on
the test geometries as a sensitivity); static jammer (the follower re-acquiring after U[0, 5]
cycles, `C.fdelay`, reported apart). Profile 1 (3 antennas).

**6.2 Seeds, geometries, episodes.** Geometry family 6 (`pool_seed.m`): validation block 5,
test block 14, set D block 7; the smoke 18, 19 and 16. Per (cell, Eb/N0): 12 validation and 36
test geometries (36 is N_MIN of a committed verdict, `edge_verdict.m`); no training split. Every
cell flies the same geometries (common random numbers), the clean cell gives the lead-in and the
restoration reference (`link_env.m` 'flight'). Episodes: 30 cycles, onset uniform in cycles 3-10,
two onsets per geometry (72 test episodes per (cell, Eb/N0)). Bootstrap: 2000 resamples over flight
geometries (`boot_cluster.m`).

**6.3 The three systems on the core action set.** Static: `none`. Conventional (link metrics
only): `blind_core`. CNN-based: `rule_core`, with the class `jamming` mapped to the wideband
action W (`rule_core_policy.m` wide_action, `PP.core_wide`); every other class keeps its mapping,
`tone_jamming` stays `channel_switch`. All run the deployed decision settings
(`decision_settings.m`, `data/trained_dqn.mat`), the same episodes and frame draws. Among them
the proposal dwell, chosen on validation for rule + escalation (`train_dqn.m`): under the
consecutive dwell ('run') the class answer can commit again after an escalation left it, under
the group dwell a configuration tried in the incident is not proposed again; `rule_core` and
`blind_core` run the same dwell. `oracle`
(cover-aware, `oracle_action.m`) is read as a bound only.

**The choice of W (validation, per hop rule).** W in {channel_switch,
channel_switch+rate_reduce, rate_reduce}, on the recoverable validation episodes of the wideband
fixed-total cells, equal weight per (B_J, JSR_tot):
1. the lowest pooled PER after onset;
2. a candidate whose paired 95% bootstrap interval of the PER difference to the best holds 0 ties;
   among the tied, the highest goodput, ties by the same interval rule;
3. then the shortest median detection-to-restored time (never recovered counts as longest);
4. then the order channel_switch, channel_switch+rate_reduce, rate_reduce.
The equal weights over B_J are the prior the CNN cannot see past (section 3), stated in the
report.

**6.4 Recoverable scenarios, fixed on validation.** Episode: some core configuration held for
the episode restores BER and packet loss (<= 2x clean + one loss event); a configuration with
`channel_switch` counts only when a hop of the episode's sequence that can reach the link after
the onset, floor((T - onset - 1) / 2) of them, escapes and restores it at that hop's residual
layer. Scenario = (B_J, JSR_tot or JSR_in,
Eb/N0, hop rule); recoverable when on validation
1. at least 90% of its episodes are recoverable (ENV_MIN, the envelope rule), and
2. it is harmful: the static link's pooled PER after onset is above the pooled restoration
   threshold (2x the same flight's clean packet loss + one loss event).
Harm is judged per scenario, never as a per-episode filter on test. The list is written to
`results/core_bw/recoverable.txt`; its SHA-256 goes into `protocol.json`.

**6.5 Readings (test split, read once).** Primary: H1, residual by offset, fixed total power,
static jammer.
- **PER reduction >= 30% vs static** (`per_reduction.m`, paired, geometry bootstrap) for
  `rule_core`, pooled over every test episode of the recoverable scenarios of both jamming types:
  met (committed) when the 95% lower bound >= 30%; met (not committed) when only the point is;
  not met otherwise. The same per type (narrowband; wideband pooled over B_J) and for `blind_core`.
  Beside it the per-episode recoverable reading of `lect_kpis.m`.
- **Recovery time** (lecturer): onset to the first confirmed alarm (t_conf) and detection to the
  packet loss restored for 5 cycles (t_rec_det, `per_metrics.m`): median, p90 and the share never
  reached (censoring within 30 cycles). Measured and compared, no threshold.
- **Goodput** in bit/s at the nominal 50 kb/s, geometry bootstrap.
- **CNN contribution** (analysis): `rule_core` - `blind_core` in PER, goodput and t_rec_det,
  paired, 95% intervals; pooled, per type and per B_J.
- **Sensitivities** (no verdict): H3, H4, the 30 dB residual (each rule), the equal in-band
  level, the follower; each says whether it would flip a primary verdict.
- **Detector by bandwidth** (analysis; the KPI verdicts of macro-F1, recall and false alarms stay
  with B3c, `docs/core_cnn_protocol.md`, and with the hybrid's B3 through `three_state_view.m`):
  the hybrid's monitor class and frame argmax on the static test episodes after the onset, as the
  three states, per (B_J, JSR_tot, Eb/N0); the frozen three-state CNN on set D (4 flights per
  (fixed-total cell, Eb/N0), 24 clean; the no_action link of the pools' flights) only after B3c's
  own reading. Detectability floor, fixed now: in-band I/N >= 0 dB, JSR_in + Eb/N0 + 3.01 >= 0;
  recall is shown above and below it, no frame dropped. False alarms are not read here.

**6.6 Gates before the test reading.**
- G1: every test of section 8 passes.
- G2: the pools stage reports the time per simulation and, per cell, the share of geometries on
  which the in-band cap binds.
- G3: under `channel_switch` held from the first cycle, every validation frame after the onset
  comes from the pool the coverage (`band_reject.m`) names for the channel in use (zero
  mismatches, else the stage stops); every escaped hop's rejection has its layer in the pools
  (else the stage stops); beside it the first-hop escape share drawn and enumerated (mid-band,
  edge, and the centred jammers off centre while our channel stays covered), the share of hops
  clear by under 2 MHz and the share of hop channels at each rejection.
- G4: `protocol.json` holds W per hop rule, the recoverable list's hash and this file's hash, and
  is committed byte for byte as `docs/core_bw_frozen.json`. The test stage refuses without them,
  on any hash mismatch, with this file or the frozen copy uncommitted, after a marker
  (`results/core_bw/test_read_started.txt`) or a committed record `docs/core_bw_read_*.txt` with
  the same `params_id`. After the reading, copy the marker to `docs/core_bw_read_p1.txt` and
  commit it. Once the test is read the validation stage refuses to run again, and the report is
  written only while `protocol.json` is still byte for byte the frozen copy.

## 7. Running it

Inputs (read-only copies of the profile's deployed files, after the final detector is deployed):
`params.mat`, `data/trained_detector.mat`, `data/fusion.mat`, `data/ood_thresholds.mat` (copied
with its time stamp), `data/splits.mat` (its norm and classes) and `data/trained_dqn.mat`. Never
beside C1p: the pools stage takes the machine's parallel turn (`parallel_turn.m`).

Stages, in order: `experiment_core_bw('smoke')`, then `'pools'`, `'dset'`, `'val'`, commit the
frozen copy, `'test'` (which ends with `'report'`); `'dread'` once B3c's reading exists, with the
branch core-cnn's three files on the path.

Outputs: `data/core_bw/pools.mat`, `data/core_bw/dset.mat`; `results/core_bw/validation.mat`,
`recoverable.txt`, `protocol.json`, `test_read_started.txt`, `test_readings.mat`,
`core_bw_report.txt`, `core_bw_kpis.mat`, `core_cnn_bw.txt`. The smoke writes the same under
`data/core_bw_smoke` and `results/core_bw_smoke` and is never a result.

## 8. Tests

`code/tests/test_core.m`: test_band_plan, test_jsr_inband, test_band_cover, test_band_reject, test_hop_targets,
test_link_env_cover_default, test_link_env_cover_recoverable, test_link_env_cover_relative,
test_link_env_residual_layer, test_link_env_residual_recoverable, test_oracle_cover, test_rule_core_wide,
test_band_cells, test_band_recoverable_scenarios,
test_band_seeds_disjoint, test_band_protocol_guard, and the existing test_rule_core_policy,
test_core_decide_escalation, test_core_policies_rollout, test_per_reduction, test_three_state_view,
test_rule_dwell_tried.

## 9. Time and memory (estimate; the smoke measures it)

2.83-3.15 s per 20-frame simulation with one jammer, 6 workers, x 1.35 with the boost off.
Pools: 34 cells x 4 configurations x 6 Eb/N0 x 48 geometries (39 168, fewer where configurations
share their physics), the clean link (1 152) and the residual layers: 183 (cell, rejection) pairs
(CW, 4, 8, 20 MHz: 20 cells x 7; 70 MHz: 5 x 3; equal level: 4 x 7) x 2 configurations x 6 Eb/N0
x 48 geometries (105 408): about 145 700 simulations, 19.0-21.2 h (25.7-28.6 h boost off). Set D:
864 runs, 0.2-0.6 h. Validation and test rollouts (seven layers' tables): 1-2.5 h. Total about
20.5-24 h (27-31.5 h boost off). Memory: pools about 1.2 GB, set D about 1.1 GB.

## 10. Risks, stated

1. The window hides the width (section 3); reported per B_J. A wide-sensing scan (the AD9361
   opens up to 56 MHz) is future work.
2. The residual is the nRF24L01+'s selectivity, not a measurement of our receiver, taken at the
   jammer's nearest frequency: the power a wide jammer holds beyond its first megahertz is not
   added. LNA blocking by a strong jammer outside the window is not modelled.
3. Partial cover counted as covered; its share reported.
4. The 4 MHz raised cosine simulated white over the window.
5. Below-floor wideband cells are mostly harmless and leave the PER denominator through the
   harmful rule; their detector rows shown apart.
6. Fading kept across a hop (conservative).
7. The answer depends on the hop rule: H1 fixed as primary before any data; H3, H4 reported
   whatever they show.
8. Recovery-time censoring within 30 cycles; the never-recovered share reported.
9. W and the recoverable list are the only choices, both on validation, frozen by hash; the test
   is read once.
10. The return link carrying the hop command is assumed, as in the main loop.
