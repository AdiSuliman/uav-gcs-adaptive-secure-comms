# Survivability map, profile 3 (surv_v2): pre-registered protocol

Written 25.10.2026, before profile 3's SURV has run and before any of its data exist. It fixes
the rules of profile 3's survivability map (`code/evaluation/map_survivability_boundary.m`)
from the refutation pass over profile 1's map (session review `surv_review.md`, items 1-6, 10,
11, N1, N2). Amended the same day, still before any data: a coded configuration's BER bound
from its lost packets (section 6, review item 5) and N on R and L cells only (section 5). Code
on `lect-kpi`; tests in `code/tests/test_core.m` (section 8).

## 1. Switch and scope

- `profile.json` field `surv_v2` (`surv_options.m`): `true` runs this protocol; absent or
  `false` runs the one-flight map. Any other value is refused.
- Profile 1 has no `profile.json` and its TIP does not take this code. Without `surv_v2` every
  line, number and file of the map is the one-flight map's (`test_surv_map_profile1_identity`).
- Profile 3's `profile.json` gains `"surv_v2": true` (step 7a) before its SURV starts.
- `surv_v2` maps the coded link with the decoder `profile.json` states (`fec_rx`, D97,
  `docs/noise_burst_protocol.md`). Outside the smoke it refuses to start without a stated
  `fec_rx`. SURV and SURV3 already read it (`p0 = fec_rx_on(p0, fec_rx_config());`).
- Unchanged: the 36 configurations, Map A and Map B, the levels (`dataset_levels.m`, path loss
  up to 42 dB), the geometries (42.2 and 11.4 deg), the nominal link (K 10 dB, no altitude,
  fixed directions, `jam_timing_random` off), 57 frames per flight, the clean reference (5
  flights per Eb/N0, floor 1e-4) and the status rule.

## 2. Status rule (unchanged)

On the means over a cell's flights, per Eb/N0 against the clean link at the same Eb/N0:

- **R:** some configuration of the map has BER <= 2x the reference and packet loss <= 2x the
  clean link's plus its slack (one loss event of a flight, `packet_share.m`, averaged over the
  flights). It is the KPI 4 rule.
- **M:** otherwise the best BER is within 5x.
- **X:** otherwise.

`grid_data.status` keeps 1 / 2 / 3, so every reader of the map (`measure_all_kpis.m`,
`build_kpi_dashboard.m`) reads the rule's status. The marks below are separate fields.

## 3. Noise bursts: two entries (`surv_nb_entries.m`)

Each geometry's `noise_burst` entry becomes two, with `jam_timing_random` off:

- **random 0.775:** Xu et al.'s random jammer at `burst_duty = burst_duty_range(end)` = 0.775,
  the most severe duty of their measured range (the one-flight map used 0.5, the least severe);
- **J4 0.2:** Marti et al.'s sparse jammer J4 at `burst_duty = burst_j4(1)` = 0.2, one-symbol
  slots (below the random range, `build_threat_model.m`), the pattern of half the pool flights.

Expected from physics (`noise_burst_protocol.md` section 1), stated now: at duty 0.775 the
capacity is at most 0.41 per coded bit from 4 dB in-band, so coded configurations do not
recover the aligned geometry from about 10 dB; J4 shows where the code helps. The uncoded rows
at duty >= 0.5 and JSR >= 12 dB are also limited by the receiver front end's median burst
reference (review N1); that front end is not changed here (it belongs to a chain rerun from A0).

## 4. Flights: common random numbers and repeats (`surv_flights.m`, `surv_runs.m`)

- **NR = 5 flights per cell** (the clean link's repeats). Each flight 57 frames.
- **Seeds** `900000 + 1000 t + r`, r = 1..5, t the entry. They depend on neither the level nor
  the Eb/N0: two cells of an entry differ only in the level or the noise, as the
  configurations of a cell already share their flights. They are disjoint from the one-flight
  map's seeds (`900000 + 1000 t + 10 li + s`, li >= 1) and from every other seed family
  (`test_seed_streams_disjoint`).
- The per-flight draws stay on (body imbalance, wobble, calibration, fading): the repeats
  average over them. `body_random` is not switched off.
- Per configuration and cell each flight's BER, packet loss and slack are kept
  (`ber_run`, `fer_run`); the rule uses their means.
- The smoke runs 2 flights of 20 frames per cell, with jamming, the two noise-burst entries and
  path loss.

## 5. Marks and labels (`surv_grid.m`, `surv_cell_label.m`, `surv_report.m`)

- **L (link-limited):** an R cell where the clean link itself loses >= 50% of its packets.
  There the packet-loss bound passes 1 and BER alone decides. Shown as L, counted apart from
  R; the overall line also gives R + L (the rule's R).
- **N:** `no_action` alone passes the R test (the link is not degraded). Shown in place of the
  configuration's letters on R and L cells; M and X cells keep their best configuration's
  letters (both maps exclude `no_action`). The status stays the rule's; the N count covers
  every cell.
- **none:** an X cell with every configuration at BER >= 0.45 (saturated): no letters, since
  the best of 35 noise-level results names no configuration.
- **0 err:** a ratio of zero is written "0 err" (gap file and figures), not "0.00x" or "<0.1".
- **Header:** "floor 1e-4 = the decision layer's reference floor; cell resolution
  1/(NR x 57 x 1032) uncoded / 1/(NR x 28 x 1032) coded" (3.4e-6 / 6.9e-6 at NR = 5); levels
  "up to 30 dB (the in-band cap, Liu et al.)".

## 6. Interval and verdict per cell

- Per configuration and cell: a 95% percentile bootstrap over the cell's flights (whole
  flights, `boot_cluster.m`, 4000 resamples, seed 74) of the mean BER and of the mean packet
  loss, widened to hold the mean. When no flight has an error (a lost packet), the upper bound
  is at least the Clopper-Pearson bound of no event in all the flights' bits (frames, or packets
  of the coded link).
- Coded configurations (`fec_interleave`): the decoder's errors come in whole lost packets, not
  in independent bits, so their BER upper bound is at least the one-sided 95% Clopper-Pearson
  upper bound of the packet loss over the cell's packets (5 x 28) x 0.5, the BER of a lost
  packet (a failed Viterbi packet is at most at chance level; D97's total erasure measured
  0.495). With errors this floors the bootstrap bound; with none it is the bound: 0.5 x 2.1% =
  1.06e-2 at no lost packet, above 5x any reference from the floor 1e-4 up to 2.1e-3. A cell
  that only a coded configuration recovers will therefore usually be not committed with five
  flights: five flights cannot show its BER within 2x the reference, and the map says so.
  Uncoded configurations keep the bit-level bound.
- `status_lo`: the rule with every configuration at the low end of its intervals; `status_hi`:
  at the high end. The slack and the clean reference stay at their means.
- **Committed** when `status_lo == status_hi`; otherwise the cell is marked `?`. The text and
  the figures carry the mark; each entry's line and the overall line count committed cells.
- With five flights this is the spread over flights of one geometry, not the envelope's
  commitment (36 flights, `edge_verdict.m`). The map remains an oracle over the configurations
  at the nominal geometry; it is not an envelope over K, altitude, speed or distance.

## 7. Gap classes (`surv_gap_report.m`)

- **Class 1:** Map A X, Map B R or M (the one-flight map's gap: survival bought with throughput).
- **Class 2:** Map A M, Map B R (full recovery bought with throughput).
- Lines carry L when the Map B cell is link-limited and ? when either cell is not committed.

## 8. Tests (`code/tests/test_core.m`)

- `test_surv_options`: the switch's values and refusals.
- `test_surv_flights_crn`: seeds independent of level and Eb/N0, run ids, disjoint from the
  one-flight seeds; `surv_runs` per flight.
- `test_surv_nb_entries`: the two entries, their duties and names, the gate the model reads.
- `test_surv_grid_marks`: the rule equals the one-flight map's on random cells; L, N, none;
  the interval, the Clopper-Pearson floor, the coded link's bound from its lost packets and
  the committed verdict.
- `test_surv_cell_label`, `test_surv_gap_report`: labels, the two classes, "0 err".
- `test_surv_map_profile1_identity`: the whole map script on a stand-in `pool_cell.m`, without
  and with `surv_v2`: without it the seeds, statuses, saved variables and texts are the
  one-flight map's; with it the common flights, the noise-burst duties, the marks and the
  saved per-flight values.
- `test_seed_streams_disjoint`: the new seeds.

## 9. Run time

Profile 1's SURV took 386.3 min (138 jobs, three antennas, one flight per cell). Profile 3:
x 5 flights; x 1.125 for the 16 added J4 jobs (154 jobs, emitter jobs weighted by
`pool_cost.m`); x 1.15-1.31 for four antennas (profile 3 over profile 1 on the link-simulation
stages A5 and A4v of the same chain). About 2500-2850 min, 42-48 h, plus up to 2 h for the last
jobs' tail on six workers. The bootstrap adds about a minute. Nothing is shortened: no fewer
flights, frames, levels or configurations.
