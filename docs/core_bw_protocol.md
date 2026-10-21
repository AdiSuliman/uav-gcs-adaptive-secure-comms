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
| 8 MHz | wideband | Mekdad et al.: Gaussian noise at 10 MS/s, low-pass 4 MHz, 1 MHz transition (GNU Radio) | +-4.5 MHz, the stopband edge; a raised-cosine edge centred on the 4 MHz cutoff (section 4) |
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
physical. Neither is the more severe throughout. The link meets the residual, the in-band level
minus R_eff (section 4), and each reading has its own in-band level. At fixed total power the
occupied reading puts 1.14 dB more into every covered channel (the static link, `rate_reduce` and
the frames before a hop, -4.88 against -6.02 dB). The noise reading's occupied edge lies 0.6 MHz
nearer every hop target, so its escaped-hop residual is up to 6.9 dB more severe: H1's 6 MHz hop
JSR_tot - 18.7 dB against - 25.6, a 14 MHz hop 5.0 dB more, an 8 MHz hop 0.2 dB, H4's 4 MHz hop
0.9 dB (covered, - 6.0 against - 7.0 with 2.1 dB of rejection). From 16 MHz on the residuals are
equal or within 0.63 dB either way; the occupied reading's is the more severe by 0.63 dB at 32 and
64 MHz and by 0.12 dB at 10 MHz. The study takes the noise reading, whose hop residual is up to
6.9 dB more severe, against 1.14 dB in band.

**Sensitivity, pre-registered: the occupied reading.** Since neither reading is the more severe
throughout, the 4 MHz cells are simulated a second time under the occupied reading
(`band_cells.m` bw4occ_tot4 to bw4occ_tot30, 5 cells): symbol rate 4 / 1.3 = 3.08 MHz, occupied
+-2 MHz, so its edge lies 0.6 MHz farther from every hop; in band JSR_tot - 4.88 dB against
-6.02; its own residual layers (section 4). Its scenarios get their recoverable status on
validation with the others (6.4) and stay out of W (6.3), of the primary, per-width and other
sensitivity lines, of set D and of the detector analysis. The report gives them their own lines
beside the primary 4 MHz cells (`experiment_core_bw.m` liu_lines: the PER reduction vs the static
link with its interval, goodput and detection to restored, pooled and per JSR_tot, for
`rule_core` and `blind_core`), with no verdict.

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
escaped when our band is clear of it (touching counts as clear), the receiver's rejection there
is sourced (below: 2 MHz or more from the jammer) and the jammer's effective rejection R_eff is
2 dB or more; partial otherwise, counted as covered (conservative against `channel_switch`; its
share is reported). A channel clear of the jammer by under 2 MHz, or with R_eff under 2 dB (its
layer at or below is 0 dB, the frames without `channel_switch`), also counts as covered (its
share is reported).

- `channel_switch` on an escaped channel: the frames of that channel's residual layer (field - R,
  below).
- `channel_switch` on a covered channel: the frames of the same configuration without it, in the
  same geometry (as after a follower's re-acquisition).
- `rate_reduce`: +6.02 dB processing gain on any B_J, goodput x 1/4.
- `channel_switch+rate_reduce`: both; covered, the `rate_reduce` frames at a switch's cost.

**Residual after an escape: the nRF24L01+'s rejection by offset over the jammer's whole spectrum
(primary, `band_reject.m`).** The rejection at an offset is the sheet's co-channel C/I minus its
C/I there (2 Mb/s, our raw rate; Table 8, ETSI EN 300 440-1, measured 0 to +-40 MHz in 1 MHz
steps): +7 dBc co-channel; +3, -17, -21, -40 and -48 dBc at 2, 4, 6, beyond 12 and beyond 36 MHz,
so 4, 24, 28, 47 and 55 dB, the row at or below the offset (4 dB from 2 MHz, 24 from 4, 28 from 6
to 12, 47 beyond 12, 55 beyond 36 MHz). At n x 2 f_xtal (32 and 64 MHz, f_xtal 16 MHz) the sheet's
footnote puts it about 5 dB under the adjacent figures, 42 and 50 dB. The 42 dB holds strictly
between the measured points next to 32 MHz (31-33 MHz: the sheet's 1 MHz steps put the adjacent
figures at 31 and 33 MHz, and the spur passes what the receiver's 2 MHz bandwidth passes). The
sheet measured only to +-40 MHz: 50 dB over 63-65 MHz is the footnote's n x 2 f_xtal rule applied
past that range with the same +-1 MHz width, and 55 dB beyond 40 MHz is the open "> 36 MHz" row
applied there; both are the most severe values the sheet states for those offsets (a receiver's
rejection does not fall farther out). Below 2 MHz the sheet's
only row is co-channel: such a channel counts as covered. The 2 Mb/s rows are the sheet's most
severe at every offset from 2 MHz (1 Mb/s: 29, 39, 49, 56 dB; Table 9, a modulated interferer: 7,
29, 35, 51, 59 dB); at 2 Mb/s the nRF's 20 dB bandwidth is 2 MHz, ours 1.25 MHz. 802.11-2007 is
milder where it applies: the FH PHY's desensitization of at least 30 dB at 2 MHz and 40 dB from
3 MHz (Table 14-19, 1 MHz channels), 35 dB adjacent-channel rejection at 25 MHz and more
(18.4.8.3); its -30 dBr (15.4.7.4) is a transmit mask, not a receiver's rejection.

A wide jammer spreads its power over offsets the sheet rejects differently, so the residual
counts all of it, the effective rejection

    R_eff = -10 log10( sum over the jammer's spectrum of (P_slice / P_ref) x 10^(-rej(offset)/10) )

in slices no wider than the sheet's 1 MHz step, split where the row changes; P_ref is the power
the jammer puts in our channel when it covers it (its in-band level, section 3). The flat jammers
(20, 70, 83.5 MHz) hold their in-band density over their span. Mekdad et al. low-pass their 8 MHz
jammer in GNU Radio (cutoff 4 MHz, transition 1 MHz), whose cutoff is the transition's centre: the
transition runs 3.5-4.5 MHz. Its spectrum is a raised cosine of symbol rate 8 MHz and roll-off
0.125: flat to +-3.5 MHz, half its density at the cutoff, none from the +-4.5 MHz stopband edge,
so its power is that of B_J = 8 MHz (section 3; full density over the transition would carry 9/8
of it). A windowed FIR is -6 dB at the cutoff and puts less near the edge, so the raised cosine is
the more severe for an escaped hop. Liu's 4 MHz jammer follows
its raised cosine (roll-off 0.3, its flat part the in-band density); a tone holds all its power
at one unknown offset of its +-0.3 MHz range and takes the lowest rejection over that range, as
before. d, the distance from our new carrier to the jammer's nearest frequency, decides the
sourced rows (`band_cover.m` off).

| hop from the jammer's centre | 2 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 20 | 24 | 32 | 40 | 64 MHz |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CW | c | 4 | 24 | 28 | 28 | 28 | 47 | 47 | 47 | 47 | 42 | 55 | 50 |
| 4 MHz | cov | c | 12.7 | 21.8 | 22.1 | 24.9 | 36.0 | 41.0 | 41.0 | 41.0 | 37.8 | 49.0 | 45.8 |
| 8 MHz | cov | cov | c | 12.7 | 20.1 | 21.9 | 24.8 | 35.2 | 38.0 | 38.0 | 36.1 | 45.7 | 44.1 |
| 20 MHz | cov | cov | cov | cov | cov | 0.9 (cov) | 17.5 | 20.1 | 24.5 | 33.1 | 34.1 | 36.0 | 41.1 |

(R_eff in dB; cov covered by geometry, c clear by under 2 MHz, both counted covered; under 2 dB
counted covered.) The 70 MHz jammer leaves 2475 MHz at 3.8 dB, 2477 at 18.5, 2479 at 20.6 and
2481 at 22.6; 2401 and 2473 MHz, 1 MHz off its edges, count as covered.

Against the reading before (the lowest row over the offsets the jammer occupies, for its in-band
share alone) R_eff is lower, more severe, wherever a flat jammer's power reaches beyond its
nearest row: by 10 log10(B_J / 1 MHz) where the whole jammer meets one row (up to 13.0 dB for
20 MHz, 9.0 for 8, 6.0 for 4), 3.5-8.9 dB for 20 MHz 14-64 MHz away, 7.4 dB for the 70 MHz
jammer at 2479 MHz; and a 20 MHz jammer 12 MHz away, 4 dB before, is now covered (0.9 dB). It is
higher where only a thin edge of the jammer met the nearer row: Liu's raised cosine 6 MHz away
(12.7 against 4 dB: its taper puts 0.11 of the in-band share within 4 MHz of our carrier), the
8 MHz jammer 8 MHz away (12.7 against 4: its raised-cosine edge puts 0.09 of the in-band share
there), a jammer whose edge touches a row's
boundary (20 MHz 22 MHz away: 33.5 against 28 at exactly 12 MHz). The spectrum, not its nearest
point, carries the physics; the tone keeps its rows.

**Layers.** The frames of an escaped hop come from a layer: the same cell's `channel_switch`
configurations simulated with `cm_acr_db` at the layer (`PP.acr_pools`, `link_env.m` spec.acr), on
both splits. A cell's layers (`band_reject.m` 'grid', `experiment_core_bw.m` cell_grids) cover
every R_eff its hops can meet (the jammer tuned to any channel of the plan, the fixed ones where
they sit; an equal-level cell over the widths it serves): ascending, each opened by the first value
more than 2 dB above the layer before it and floored to 0.1 dB. Every hop then reads the layer at
or below its R_eff (more severe, never milder), at most 2 dB below it (G3 checks it; over the
values a cell meets 0.7-0.8 dB below on average for 4-20 MHz, the CW exact, 70 MHz within 0.1 dB):

| cell | layers [dB] |
|---|---|
| CW (5 cells) | 4, 24, 28, 42, 47, 50, 55 |
| 4 MHz (5) | 12.6, 21.8, 24.9, 36.0, 39.1, 43.3, 45.7, 48.3 |
| 8 MHz (5) | 12.7, 20.1, 24.8, 35.2, 37.9, 42.3, 44.9 |
| 20 MHz (5) | 17.5, 20.0, 24.5, 33.1, 35.4, 37.6, 40.1 |
| 70 MHz (5) | 3.8, 18.4, 20.6, 22.6 |
| 83.5 MHz (5) | none |
| equal level 4, 10 dB (4-83.5 MHz) | 3.8, 12.6, 17.5, 20.0, 22.0, 24.5, 33.1, 35.2, 37.6, 40.1, 42.3, 44.9, 47.1 |
| equal level 16 dB (4-20 MHz) | the same without 3.8 |
| equal level 23 dB (4 MHz) | those of 4 MHz |
| 4 MHz, occupied reading (5, sensitivity, section 3) | 2.0, 20.6, 23.1, 26.0, 38.3, 40.7, 44.4, 48.7 |

211 (cell, layer) pairs, 35 distinct layers, for the primary and equal-level cells; with the
occupied reading 251 pairs and 42 layers. The crystal's 42 and 50 dB stay (the sheet's footnote
states them): the CW cells' own layers, and inside every wide jammer's sum. The recoverable rule
reads the same layer (section 6.4). The main pipeline's 30 dB (`cm_acr_db`) stays as it is there.

**Sensitivity** (test only, no choice): 30 dB on every channel clear of the jammer by geometry,
the pipeline's value (the pools' own `channel_switch` frames, `band_cover.m` alone).

**Fading after a hop** is not redrawn: the same statistics on every channel; keeping it withholds
from the hop its escape from a deep fade, conservative for every adaptive system.

**H1 escape share of one hop** (centred jammer, the enumeration): CW and 4 MHz 1; 8 MHz 34/36
mid-band to 37/38 at the edge (its 6 MHz hop is 1.5 MHz off the edge); 20 MHz 28/36 to 34/38
(its 12 MHz hop keeps 0.9 dB, counted covered); 70 MHz: 2475-2481 MHz escape (four; the home is
drawn among the 35 channels the span covers; 2401 and 2473 MHz, clear by 1 MHz and counted
covered, are never home); 83.5 MHz 0.

## 5. Predictions (written before any run) and their fixed readings

- **P1.** Narrowband: `rule_core` recovers >= 90% of the recoverable CW episodes at JSR_tot
  <= 23 dB; at 30 dB, where recoverable episodes exist, its median detection-to-restored time
  equals `blind_core`'s within the interval (the 95% interval of the difference of the medians,
  bootstrap over flight geometries, holds 0; never restored counts as the longest; 28 of H1's 36
  mid-band first-hop targets lie 14 MHz or more from the tone, at least 42 dB, where
  `channel_switch` alone restores); on the episodes whose first hop lands 6-12 MHz away (24 or
  28 dB, 6 or 2 dB left in band) its median is longer, the rule needing the escalation to
  `channel_switch+rate_reduce`, which `blind_core` takes first (`core_bw_rules.m` 'p1').
- **P2.** Wideband 4-20 MHz under H1: the hop escapes; W chosen on validation is
  `channel_switch` or `channel_switch+rate_reduce`.
- **P3.** 70 and 83.5 MHz at JSR_tot 30 dB: no scenario point recoverable by the core set.
- **P4.** 20 MHz and wider at JSR_tot 4 dB (in band <= -9 dB): no scenario point harmful.
- **P5.** The CNN's contribution is mainly goodput: on the narrowband episodes both systems
  recover, the goodput difference `rule_core` - `blind_core` has a 95% lower bound above 0 and the
  PER difference's interval holds 0.

Each is reported as holds / does not hold; none changes a KPI verdict.

## 6. The experiment

**6.1 Grid.** B_J {CW, 4, 8, 20, 70, 83.5} MHz x JSR_tot {4, 10, 16, 23, 30} dB (30 cells), the
4 equal-level cells and the 5 cells of Liu's occupied reading (section 3); Eb/N0 0:3:15 dB per
branch; the pools' nested Latin hypercube over speed,
altitude, K, the first interferer's direction and the receive correlation; hop rule H1 (H3, H4 on
the same pools); residual R_eff by offset (section 4, each cell's layers on both splits; the
pipeline's 30 dB on the test geometries as a sensitivity); static jammer (the follower re-acquiring after U[0, 5]
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
the group dwell the rule does not commit a configuration tried in the incident again; `rule_core` and
`blind_core` run the same dwell. `oracle`
(cover-aware, `oracle_action.m`) is read as a bound only.

**The choice of W (validation, per hop rule).** W in {channel_switch,
channel_switch+rate_reduce, rate_reduce}, on the recoverable validation episodes of the wideband
fixed-total cells (Liu's 4 MHz as the noise bandwidth only), equal weight per (B_J, JSR_tot):
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
- **PER reduction >= 30% vs static** (`per_reduction.m`, paired, geometry bootstrap), the primary
  verdict per jamming type, as in C2e (`lect_kpis.m`): `rule_core` on every test episode of the
  recoverable scenarios of the type, narrowband (the CW cells, the only narrowband state of
  section 3) and wideband (the 4-83.5 MHz cells pooled over B_J), each MET (committed) when the
  95% lower bound >= 30%, MET (not committed) when only the point is, NOT MET otherwise (also
  without episodes; `core_bw_rules.m` 'verdict', 'per_verdicts'). Both types pooled is a second
  line, labelled so; `blind_core` gets the same three lines as the conventional system's reading.
  Beside them the per-episode recoverable reading of `lect_kpis.m`.
- **Recovery time** (lecturer): onset to the first confirmed alarm (t_conf) and detection to the
  packet loss restored for 5 cycles (t_rec_det, `per_metrics.m`): median, p90 and the share never
  reached (censoring within 30 cycles). Measured and compared, no threshold.
- **Goodput** in bit/s at the nominal 50 kb/s, geometry bootstrap.
- **CNN contribution** (analysis): `rule_core` - `blind_core` in PER, goodput and t_rec_det,
  paired, 95% intervals; pooled, per type and per B_J.
- **Sensitivities** (no verdict): H3, H4, the 30 dB residual (each rule), the equal in-band
  level, the follower; each says whether it would flip a primary verdict (`rule_core`'s per
  jamming type). Liu's occupied reading has its own lines beside the primary 4 MHz cells
  (section 3), without a verdict word.
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
  mismatches, else the stage stops); every escaped hop's layer is in the pools and lies at most
  2 dB below its R_eff (else the stage stops); beside it the first-hop escape share drawn and
  enumerated (mid-band, edge, and the centred jammers off centre while our channel stays
  covered), the share of hops clear but counted covered (under 2 MHz, or R_eff under 2 dB), the
  share of hop channels at each layer and the mean and largest distance from R_eff to its layer.
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

`code/tests/test_core.m`: test_band_plan, test_jsr_inband, test_band_cover, test_band_reject,
test_band_reject_eff, test_band_reject_layers, test_band_liu_occupied, test_hop_targets,
test_link_env_cover_default, test_link_env_cover_recoverable, test_link_env_cover_relative,
test_link_env_residual_layer, test_link_env_residual_recoverable, test_oracle_cover, test_rule_core_wide,
test_band_cells, test_band_recoverable_scenarios, test_band_per_verdicts, test_band_p1_reading,
test_band_seeds_disjoint, test_band_protocol_guard, and the existing test_rule_core_policy,
test_core_decide_escalation, test_core_policies_rollout, test_per_reduction, test_three_state_view,
test_rule_dwell_tried.

## 9. Time and memory (estimate; the smoke measures it)

2.83-3.15 s per 20-frame simulation with one jammer, 6 workers, x 1.35 with the boost off.
Pools: 39 cells (34, and the occupied reading's 5) x 4 configurations x 6 Eb/N0 x 48 geometries
(44 928, fewer where configurations share their physics), the clean link (1 152) and the
residual's layers: 251 (cell, layer) pairs (section 4: CW 5 x 7, 4 MHz 5 x 8, 8 MHz 5 x 7, 20 MHz
5 x 7, 70 MHz 5 x 4, equal level 13 + 13 + 12 + 8, the occupied reading 5 x 8) x 2 configurations
x 6 Eb/N0 x 48 geometries (144 576): about 190 700 simulations, 25.0-27.8 h (33.7-37.5 h boost
off). Of these, the R_eff layers cost 16 128 simulations more than the sheet's rows alone (183
pairs), 2.1-2.4 h (2.8-3.2 h boost off), and the occupied reading 28 800 (5 760 in the pools,
23 040 in its layers), 3.8-4.2 h (5.1-5.7 h boost off). Every run keeps its full length. Set D:
864 runs, 0.2-0.6 h. Validation and test rollouts (49 scenarios, 42 layers' tables): 1.1-2.8 h.
Total about 26.3-31.2 h (35-42 h boost off). Memory: pools about 1.6 GB, set D about 1.1 GB.

## 10. Risks, stated

1. The window hides the width (section 3); reported per B_J. A wide-sensing scan (the AD9361
   opens up to 56 MHz) is future work.
2. The residual is the nRF24L01+'s selectivity, not a measurement of our receiver: the sheet's
   rows summed over the jammer's spectrum (R_eff), each slice an interferer of its own at its
   offset, the rows between measured points at the one at or below; the layer at most 2 dB
   below R_eff. LNA blocking by a strong jammer outside the window is not modelled.
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
