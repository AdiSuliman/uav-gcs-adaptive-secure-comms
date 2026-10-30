# rx_fix_rule3: the per-block genie D3, new fresh frames, adoption after D2, and the CORE_BW census D2c

Registered 30.10.2026, before any D3, fresh-frame, candidate or D2c data exists. This is the "new pre-set rule with new fresh frames" of ruling 3.7's last bullet, as the D1 reading (open point 4) and the D2 reading (sections 4.1 and 4.2) call for it. It governs D3, the fresh-frame list, every candidate born after D2 (at most two) and D2c. Ruling 3.6 (materiality, as registered in `rx_fix_rule2.md`) applies unchanged after an adoption under this rule. Every harness under this file prints `RULE rx_fix_rule3.md sha256 <h>` (LF line ends) before anything runs, and stops when the hash differs from the one in its dispatch note.

Names, as in the ruling:
- **r1**: the receiver as built (d4623ed, receiver blob `40dc1f9`). **r2**: r1 plus an adopted `p.rx_ne_fix` option.
- **The three frames**: 420/5, 452/10 and 459/16 at 12 dB. 426/9, 511/12 and 411/4 are reported only.
- **The 27 flights**: `link_floor_partA/partB.mat`, validation runs 411-698 at 9, 12 and 15 dB (clean validation pool, seed block 4).
- **Recovered**: frame BER ≤ 0.05, as in D1 and D2.

## 1. D3, the per-block genie (diagnostic only)

D3 asks two things: does a channel model that follows the true lag shape block by block decode the three frames, and must the equalizer follow it too. It reads `txbits` (through the `rxd_true` fit), so nothing in it is adoptable and release builds refuse its tokens. It runs on the 27 flights only, never on the fresh frames of section 2.

### 1.1 Code

- Branch `rx-ne-fix`, new commits on this file's commit. Two tokens in `rx_ne_fix_code`. Both are diagnostic only, both need `own_out`, and both are refused when `p.rx_release` is true.
  - `twinb`: the twin input of D2 (`Threat/4` through `LevelTw` to the receiver's third input, its own receive filter, the samples' timing, frequency and whitening).
    - After the frequency passes, for the training (block 0) and for every pilot block b, the twin's lag profile `G_b` (NR × NRK): LS with every symbol known (data from `txbits`), on the rows `rxd_true` uses for that block, on the twin's samples `yxt`.
    - Every symbol of the MRC output, the equalizer's span included, takes the profile of the block whose centre (`tq`, the training's centre included) is nearest, ties to the earlier block. It is held over that segment, with no smoothing and no interpolation.
    - `G_b` replaces `gk .* Gt` in the MRC. `fe_b = le_taps(G_b, s2, NE)` replaces `le_taps(Gt, s2, NE)` for the data symbols of segment b.
    - `s2`, the frequency passes (unless `twinf` is on), `Gt`, `ga`, the burst rule and the DD passes stay as built. `Gt` and `ga` then feed the prints only.
  - `eqt`, only with `twinb`: the equalizer stays `le_taps(Gt, s2, NE)`, designed once from the training as built. The MRC keeps `twinb`'s profiles.
  - `twinb` combines only with `twinf`, `eqt` and `log`. Any other token beside `twinb` raises an error, and so does `eqt` without `twinb`.
- With the field absent or `'off'`, the script text is unchanged. Every build with the field on prints `Rx NE>1 options: <tokens>` and `Rx NE>1 diagnostic-only: <tokens>` (past bug #2).
- Tests added to `code/tests/test_rx_ne_fix.m`, run in the dispatch with D2's six as one `runtests` call:
  - each new token changes only its own lines;
  - `NE == 1` and `NT > 1` are bit-identical with `twinb+twinf` and with `twinb+eqt`;
  - check (f3b) of section 1.3.
- Harness `worktrees\link-floor\rx_d3.m`:
  - checks this file's hash and the fix file's hash, as D2's `RULE_SHA` and `FIX_SHA`;
  - runs the fresh pool of section 2 first, on the export, before the fix file is on the path;
  - then runs the arms with the built file copied to `link-floor\fix` (D2's copy kept in its own folder, as before);
  - prints as D2's interpretation (h): the RXL truth, each antenna's true residual frequency, one line per frame and arm.

### 1.2 Arms

On the 27 flights with their saved seeds, `own_out` on, each arm with `log`:

| Arm (tokens) | What it changes | What it isolates |
|---|---|---|
| `log` | prints only | r1; guard G1 |
| `twinb+log` | the per-block true profile in the combining and in the equalizer design | the model and the equalizer together |
| `twinb+twinf+log` | as `twinb`, with D2's twin frequency in both passes | the same, with the frequency step's error removed as far as `twinf` removes it |
| `twinb+eqt+log` | the per-block true profile in the combining; the training-designed equalizer kept | the model alone |

The flat channel also runs off against `twinb+twinf+log` and against `twinb+eqt+log` (G4).

### 1.3 Guards and checks

A failed guard voids D3: nothing is read, the harness or the code is fixed, and D3 is rerun.
- **G1:** `log` reproduces the saved frame BER on 27 of 27 flights, max|d| = 0, with `own_out` on.
- **G2:** text and wiring.
  - The script with the field absent, `'off'`, or `'off'` with `own_out` equals the export's.
  - `log` minus its prints equals off, and every arm minus its prints equals its tokens' script.
  - The fix file equals the `rx-ne-fix` file and its registered hash.
  - There is no twin input without a twin token, and every `twinb` arm's third input comes from `LevelTw <- Threat/4`.
- **G3:** every arm prints `tokens ON ... match 1`, completes its flights, and its prints agree with the frame BER element by element.
- **G4:** on the flat channel, off against `twinb+twinf+log` and against `twinb+eqt+log`: max|d| = 0 on `Rx_Z` and frame BER over the 27 flights.
- **G5:** every `twinb` arm prints `truth prints valid 1` (D2's condition (f2)). Here it is a guard, because `twinb` reads `txbits` inside the receiver: a misaligned `txbits` would corrupt the arm itself, not only its prints.
- **(f3)**, carried from D2: the `twinf+log` training check stays in the tests (median |10 log10 |c|²| < 1 dB, median |angle c| < 0.2 rad).
- **(f3b)**, new and failable, in the tests. Under `twinb+log` on the flights of the three frames at 12 dB, take the antenna-blocks of their clean frames (BER < 1e-3) where r1's template fits the twin (misfit ≤ −10 dB). There, c_b is the multiple of `Gt(a, :)` closest to `G_b(a, :)`. Required: median |10 log10(|c_b|² / |ga(a, b)|²)| < 1 dB and median |angle(c_b / ga(a, b))| < 0.2 rad. This checks that the genie's profiles sit at the receiver's level, timing and rotation. A failure stops the dispatch before D3.

### 1.4 Reading (fixed now)

n_e is the number of the three frames `twinb+eqt` recovers. n_p is the larger of the numbers `twinb` and `twinb+twinf` recover (the arms with a per-block equalizer).

| n_e | n_p | Reading | Candidate class |
|---|---|---|---|
| ≥ 2 | ≥ 2 | A model that follows the shape suffices with the linear equalizer | A frame-long time-varying channel per antenna and per lag, decision-free in the first pass, with per-block combining and per-block equalizer design |
| < 2 | ≥ 2 | The equalizer design must follow the model | The same class; the per-block equalizer design is a required part of it |
| ≥ 2 | < 2 | The model suffices; the per-block equalizer design as computed does not | The same channel and per-block combining, with the training-designed equalizer kept |
| < 2 | < 2 | None: the 21-tap linear equalizer structure is the limit | The equalizer structure, designed and read under this rule |

- **Frequency.** When n_p ≥ 2 comes from `twinb+twinf` alone (`twinb` recovers fewer than 2), the class also replaces the first-pass frequency step by an estimate that does not ride on the frozen template, and stage 1d applies to the candidate.
- The harness prints the three counts without a name, then one line computed by this table: `D3 reads (rule 3, 1.4): <row>`.
- Reported with the reading, not read:
  - 426/9, 511/12 and 411/4;
  - each arm's FER27 and BER27 sum;
  - the twin truth on the three frames (RXL, RXET), with the `twinb` arms' per-antenna true residual frequency f_res. It bounds the phase the hold leaves at a segment's edge, π × f_res × 52 / SR rad.
- D3 names a class, not a candidate, and adopts nothing. The candidate's design note follows the reading, with its sources entered in `LITERATURE.md` before any rule cites them.

## 2. Fresh frames

### 2.1 The seed block

Fresh flight k takes the seed 2 400 000 + k: k = 1-150 for the first batch, k = 151-300 for the second (section 2.5). No pool, test set, dataset, harness or test has used these seeds. The proof below covers the code of every branch of the repository on 30.10.2026 and the D1 and D2 harnesses.

| Flight seeds in use | Range | Source |
|---|---|---|
| Pool geometries: family 1 (every block), 2 (block 10), 3 and 5 (blocks 4 and 15), 6 (CORE_BW: blocks 5, 7, 14, 16, 18 and 19), 7-9 (P1R's fresh clean set: blocks 15 and 18). D1's 27 flights and its fresh candidates (block 4) and D2's census (family 1, block 5) are among them | 821 101 to at most 1 989 000 | `pool_seed.m`, `clean_pool_seed.m`, `pool_seed_owner.m` |
| Survivability map | 700 001-700 005; 901 011-920 086 | `test_seed_streams_disjoint` |
| Dataset, unseen Eb/N0, unseen severity, the second to fourth test sets, B4 and B4s, with their shadowing seeds SEED0 + 50 000 + j | 3 000 001 to 6 599 999, in blocks of 99 999 | `run_dataset_sweep.m`, `eval_unseen_snr.m`, `eval_unseen_severity.m` |
| Airframe-shadowing candidates | 10 000 001 to 61 199 999 | `shadow_pool_seed.m` |
| SURV3 shadowing | 62 000 000 + 100 000 (s − 1) + j | `surv3_shadow_seed.m` |
| Physics validation, tools and legacy scripts | below 700 000: `validate_phy.m` 1 000 + c, 2 001-2 002, 3 001, 4 000 + c and 7 000 + c; `threat_gallery.m` 424 242; `dev_fec_burst.m` 7 801-7 860; the legacy scripts' 1 000 and 50 000 plus 10 000 per Monte Carlo run (5 by default) | as named |
| Unit-test seeds | 3 000 501, 3 200 000 + s, 4 920 200 and others at or above 3 000 000 | `test_core.m` |

1. **Search.** Every flight seed in the table is below 2 000 000 or at or above 3 000 000. No `.m` file on any branch uses a number from 2 000 001 to 2 999 999 as a seed; the only such numbers are two `linspace` sample counts in `test_core.m`. The D1 and D2 harnesses fly only saved pool seeds.
2. **`pool_seed.m` cannot reach the block.** Its values are 800 000 + 20 000 f + 1 000 s + 100 b + r (block b < 10) or 1 800 000 + 20 000 f + 1 000 s + 100 (b − 10) + r, with the last two terms together between 1 and 1 000. Both bases are multiples of 20 000, so a value from 2 400 001 to 2 400 300 needs 1 000 s plus those terms to equal 1-300 plus a multiple of 20 000: s = 0, or s ≥ 20. The Eb/N0 indices in use are 1-8, so no family, present or future, reaches the block at an Eb/N0 index from 1 to 19.
3. **Streams.** Every seed is below 2^26, so `seed_base` (64 × seed) is one-to-one, and a flight's 64 streams (offsets 0-63) are its own: distinct seeds never share a stream. The fresh set's streams run from 153 600 064 to 153 619 263, below 2^32. Every direct stream seed in use lies below 64 × 700 001 = 44 800 064: the Latin-hypercube permutations (7 100 000 to 7 201 000), the edge map's frame draws (40 000-300 000), the fusion and d91 resamplings (61-9 155), the link-floor harnesses' (7, 11, 42, 1 000 + s, 100 000 s + j) and `validate_phy.m`'s.
4. **Test.** `test_seed_streams_disjoint` is extended in the commit that adds the fresh-pool harness. It adds 2 400 000 + (1:300)' to its flight seeds, with the families 6 and 7-9 that its `rx-ne-fix` copy does not list yet. It asserts that all flight seeds are unique, that their streams are unique, below 2^26 and 2^32, and that the fresh seeds lie above every pool seed and below the lowest dataset seed.

### 2.2 Flights

- 150 flights per batch, 20 frames each, at Eb/N0 12 dB.
- Profile 1's validation link, flown as the 27 flights were: `link-floor\data\params.mat`, threat `none`, `no_action` through `pool_configs`, on the export (r1, field absent), `own_out` on.
- Speed uniform over 100-161 km/h from the seed's own speed stream: v = 100 + 61 u, with u = rand(seed_stream(seed, 'speed')), as `pool_seed.m` draws it. The range lies inside profile 1's 29-161 km/h envelope and holds the three frames' 104-150 km/h.
- Everything else is the flight's own draw from its seed, as in the clean validation pool: `link_seed` with altitude, K, interferer direction and correlation NaN, event NaN, 20 frames.

### 2.3 Selection (decision-free, by D1's truth harness)

- A frame enters the list when r1's frame BER > 0.1 and its true post-MRC Es/N0 ≥ 8 dB.
- The true Es/N0 comes from our own component (`Thr_sig`), calibrated on at least 3 clean frames of its flight (BER < 1e-3, pilot error < 0.3), as `rx_diag.m`'s `fresh_frames` computes it.
- A flight with fewer than 3 clean frames gives no frame; it is reported.
- No D3 arm ever runs on these flights, and no candidate runs on them before the list is committed.

### 2.4 List, hash, commit

- The harness writes `link-floor\results\rx_fresh3_frames.txt` and its `.sha256`, and prints the hash.
  - Header: this file's sha256, the seed formula, the speed range, the Eb/N0, the criteria, the flights examined, the candidate frames, the frames in.
  - One row per frame: Eb/N0, k, seed, frame, r1 BER, true Es/N0, speed, calibration frames.
- It commits the same text as `rx-ne-fix\docs\rx_fresh3_frames.txt` (that file only) and prints the commit.
- D3 starts only after that line. A failed commit stops D3.
- The list closes after its last batch. It is never edited, and every candidate is read on it as written.

### 2.5 Batches and the requirement

- n is the number of frames in the list. If n < 3 after the first batch, the second batch (k = 151-300) runs at once in the same dispatch, and the list then closes whatever n is.
- Adoption requires n ≥ 3 and at least ceil(n/2) of them recovered (stage 1b, section 3). With n < 3 after the second batch, no candidate can be adopted under this rule.
- D1's "with n < 3, reported only" does not carry over: the three frames have now been seen by D1, D2 and D3.
- The fresh flights lie outside stage 2's non-selected population (seed block 4, runs 401-700) and outside every test set, so neither changes.

## 3. Candidates and adoption

- At most two candidates, of the class section 1.4 names. Each is registered in its dispatch note (commit, tokens, the row of 1.4 it implements) before its first stage-1 run, and they are read in that order.
- A candidate is decision-free in its first pass and sits behind an adoptable `p.rx_ne_fix` token under ruling 3.3's switch rules:
  - field absent = r1, with the script text unchanged;
  - `NE == 1` and `NT > 1` bit-identical;
  - `Rx NE>1 options:` printed by every build with the field on;
  - `MODEL_TAG` bumped in every tree that turns it on;
  - profile 3's release check an allow-list of the adopted value.
- It carries 3.3's unit tests and a synthetic test of a lag shape that changes within the frame, written before stage 1.

The guards, stages 1c, 1d, 2 and 3 below are ruling 3.5's text unchanged (as in `rx_fix_rule2.md`). 1a and 1b are this rule's.

**Guards** (any failure voids the reading):
- G1: with the field off, the 27 flights reproduce their saved frames (max|d| = 0); 10 flights per Eb/N0 of the clean validation pool reproduce W's file; if stage 3b reads r1 from saved pools, 10 of its geometries re-simulated off reproduce them.
- G2 text identity; G3 on/off lines; G4 `NE == 1` and `NT > 1` bit-identical (unit tests, and F-off against F-on on the 27).
- G5: `MODEL_TAG` bumped in the stage 2 and 3 trees; the clean reference copied into each tree and asserted finite (past bug #16).

**Stage 1** (minutes; the candidate built without `log`):
- 1a (rule 3), the three frames (seen by D1, D2 and D3): at least 2 at BER ≤ 0.05. Ruling 3.5's frequency clause ("for a frequency candidate, abs(dcfo) ≤ 400 Hz on every recovered frame") is dropped. D2 measured each antenna's true phase slope on these frames at [95 −551 −1258], [−1633 −2077 −247] and [−796 415 −646] Hz: spreads of 1.35, 1.83 and 1.21 kHz, above 2·fd at the flights' speeds (about 462, 667 and 600 Hz). An oscillator offset is common to all antennas, so on these frames one dcfo has no defined target.
- 1b (rule 3), fresh frames (held out): the list of section 2. n ≥ 3 is required, and at least ceil(n/2) at BER ≤ 0.05.
- 1c, no harm on the 27 flights: frames newly lost (CRC pass to fail) ≤ 1; FER27 ≤ 0.3648; 546, 698, 658, 573 at BER 0; on 430, 510, 514 at 9 dB, FER no worse, no newly lost frame and BER ≤ 1.10 × as built (a structural change moves bit counts of unchanged packet outcomes; (b) moved them by 1.1-1.7%).
- 1d, accuracy (frequency candidates only): median abs(dcfo) over frames with as-built BER < 1e-3 at most 1.5 × as built (design 1's predicted lag-1 loss, √2.3).

Stage 1d is kept for any candidate that changes the frequency step, including one that section 1.4's frequency line requires.

**Stage 2** (non-selected population; about 2 h on 6 workers): the clean validation pools (set `val`, seed block 4, runs 401-700, every Eb/N0 of W's `clean_val_pools.mat`, 20 frames) rebuilt with the candidate in `<main>\worktrees\rx-adopt`; r1 = W's file (read-only copy, sha256 `99e16d00…2c30`).
- 2a: at each Eb/N0, a one-sided exact McNemar test on frames lost under one receiver only shows no significant worsening at α 0.05 (0.025 for a second candidate);
- 2b: pooled over Eb/N0, frames lost only under the candidate ≤ frames lost only under r1;
- 2c: clean FER at each Eb/N0 ≤ r1 + 0.1 pp;
- 2d: CREF mean BER at 9, 12 and 15 dB ≤ r1 (`clean_ref_rebuild('check')` on the new file).

**Stage 3** (about 3-6 h):
- 3a PHYV: `validate_phy('V12c', 1:3)` (clean MRC on the delay line, 7 spreads): every row within its 0.5 dB gate, and no spread worse than r1 by more than 0.2 dB. r1 = W's `phy_validation_v12c.txt` once a one-point run with the field off reproduces it; else both arms run. V11 and V12c rows 4-9 are bit-identical by G4. `validate_phy('V13')` passes its rules.
- 3b threat footprint (paired; profile 1's validation geometries of the policy pools' split 2, read-only copies): states `none`, `tone_jamming`, `jamming` (the lecturer's three) and `noise_burst` (the burst rule's own target); profile 1's pool levels; the four core configurations and the two MRC configurations of the escalation ladder (`freq_diversity+power_control+fec_interleave`, `channel_switch+rate_reduce+power_control`); Eb/N0 0:3:15; 10 geometries per (state, level, Eb/N0); 20 frames; 6 workers. **No harm:** no (state, Eb/N0) cell, pooled over levels and configurations, with ΔPER > +1 pp and a paired flight-bootstrap 95% interval excluding 0. The same data is read by 3.6.
- 3c: `test_core` in full on the candidate's tree, plus the new tests.

**Decision:** adopt only if every guard, 1a-1d as above, 2a-2d and 3a-3c hold. At most two candidates are read under this rule, in the order their dispatch notes register them; the second is read with 2a's α 0.025. A failed candidate is not tuned and not re-read on these data.

**After an adoption:** ruling 3.6 (`rx_fix_rule2.md`) is read on stage 3b's data, and profile 3 follows ruling 4.4. The reading is `rx_fix_reading3.md`.

## 4. D2c, the r1 census on CORE_BW's core configurations

### 4.1 Purpose and place

- Ruling 4.2: CORE_BW runs on r1, and "the bound comes from 3.6 (or D2's census) before CORE_BW's numbers enter the book".
- D2's census is not a bound (D2 reading, section 4.1): the instrument is blind to this defect, and the jammed cells are saturated under `no_action`. It is never cited as 0% under jamming.
- D2c takes its place. It measures how often r1 loses a frame the link should carry, on the restored link that CORE_BW's adaptive systems fly, in the two jammed states.
- Without an adoption before the book, D2c is 4.2's bound. With one, 3.6 on stage 3b's data is the bound, and D2c is reported beside it as r1's measured rate.
- r1 only (field absent): no rung, no genie.
- It runs in any free p3-slot window before CORE_BW's numbers enter the book (about 4.2027). It is not on profile 3's path. Its reading is `rx_d2c_reading.md`.

### 4.2 Data and code

- **No CORE_BW test data.** No CORE_BW data or results file is opened at all: nothing under `data\core_bw*` or `results\core_bw*`. Block 14 (test), block 7 (set D) and the smoke blocks 16, 18 and 19 are never flown. The validation geometries are recomputed from the code.
- **Code.** A read-only export of `uav-gcs-v7-bw` at `f84384c` into `<main>\worktrees\d2c` (receiver blob `40dc1f9` asserted), with a copy of its `params.mat`. Nothing is written in `-bw`, `-p3` or W. Harness `worktrees\d2c\rx_d2c.m`.
- **Truth taps.** `own_out` on (`Thr_sig`), and two sinks the harness adds to the built model: the outputs of `Level` and of `AWGN`. The receiver script is untouched.

### 4.3 Population (fixed now)

- **Geometries.** CORE_BW's validation design: family 6, block 5, geometries 1-12 per Eb/N0, with its Latin hypercube (permutation stream 7 200 000 + 100 s + 1) and its speed range, as `experiment_core_bw.m`'s pools stage builds them.
- **Cells.** CORE_BW's fixed-total cells at JSR_tot 16, 23 and 30 dB, the upper three of its five levels, where the residual after an action is largest. Narrowband: CW. Wideband: 4 MHz (the noise reading, CORE_BW's primary), 20, 70 and 83.5 MHz. The static jammer.
- **Configurations**, the core set without `no_action`:
  - CW, 4 and 20 MHz: `channel_switch` and `channel_switch+rate_reduce` at the lowest layer of the cell that an H1 hop meets when it escapes (CW 24 dB, 4 MHz 12.6 dB, 20 MHz 17.5 dB; CORE_BW protocol section 4), and `rate_reduce`.
  - 70 and 83.5 MHz: `rate_reduce` only. An H1 hop escapes the 70 MHz jammer on 4 of 41 channels and the 83.5 MHz jammer never.
  - The lowest escaped layer carries the most severe residual a restored hop meets. Weaker residuals approach the clean link, whose rate is already bounded (≤ 0.25 pp at 12 dB).
- **Flights.** Each (cell, configuration, layer) is flown as the pools stage parameterizes it (`cell_params`, the configuration's countermeasure, `cm_acr_db` at the layer), every geometry with `link_seed` as `pool_cell` flies it, 20 frames.
- **Clean twins.** Every geometry is also flown in the clean cell under `no_action` and under `rate_reduce`. By common random numbers they have the same own component and noise as the jammed flights; `channel_switch` changes nothing on a clean link.
- **Passes.**
  - Pass 1 at Eb/N0 12 dB: 33 jammed combinations and 2 clean ones, 12 geometries each, 420 flights.
  - If a state has fewer than 1200 eligible frames after pass 1, pass 2 flies that state's combinations and the clean twins at 15 dB, then pass 3 at 9 dB, while the state is short.
  - Then the census closes.

### 4.4 Per frame

- r1's frame BER, from `txbits`, as the pools compute it.
- The true post-combining SINR, on D1's scale: SINR = Es/N0_true − L.
  - **Es/N0_true** is D1's true post-MRC Es/N0 of the same frame in the geometry's clean twin of the same configuration type (`no_action` for `channel_switch`; `rate_reduce` for `rate_reduce` and `channel_switch+rate_reduce`): our own component, calibrated on at least 3 clean frames of that twin flight. A geometry whose twin has fewer than 3 calibration frames gives no eligible frame; it is reported.
  - **L** = 10 log10[λ_max(R_n⁻¹ R_s) / λ_max(R_in⁻¹ R_s)] ≥ 0 dB, the interference's loss to the best linear spatial combiner. λ_max is the largest generalized eigenvalue.
  - R_s, R_in and R_n are the NR × NR sample covariances over the frame's signal window (D1's window: the frame after the quiet slot), after the receiver's own receive filter (root raised cosine, its roll-off, span and samples per symbol), of:
    - our own component, `Level` × `Thr_sig`;
    - interference plus noise, the `AWGN` output minus `Level` × `Thr_sig`;
    - noise alone, the `AWGN` output minus the `Level` output.
  - Without an interferer L = 0, and SINR is D1's Es/N0.
  - It is a truth of the field before the front end; the ADC is excluded, as for D2's twin.

### 4.5 Count and bound

- **Eligible frame:** SINR ≥ 8 dB. **Collapse frame:** an eligible frame with r1 BER > 0.1. This is ruling 3.7's definition extended to SINR; it adds no threshold.
- Per state s (narrowband, wideband), pooled over cells, configurations and passes: n_s eligible frames and k_s collapse frames.
- U_s is the one-sided 95% Clopper-Pearson upper limit of k_s / n_s (for k_s = 0, 1 − 0.05^(1/n_s), about 3 / n_s).
- Target n_s ≥ 1200, which gives U_s ≤ 0.25% at k_s = 0. Below it, U_s is given at its n_s and labelled "below the 1200 target".
- Reported, not read: k and n per (cell, configuration); every collapse frame (geometry, Eb/N0, frame, SINR, L, BER); the share of ineligible frames.
- The count holds every frame r1 loses at good SINR, from this defect or from another cause, so U_s bounds the defect from above.

### 4.6 How it becomes 4.2's bound

- Every CORE_BW number of a jammed state that enters the book carries "r1; receiver loss on the restored link ≤ U_s (D2c, validation)", in place of ruling 3.7's "unmeasured". The clean state keeps ≤ 0.25 pp at 12 dB.
- **The lecturer's PER-reduction verdicts.** Red = 1 − PER_sys / PER_static. A receiver without these losses lowers each PER by at most U_s, so with PER_sys ≤ PER_static, |ΔRed| ≤ U_s / (PER_static,s − U_s). PER_static,s is the static link's pooled post-onset PER in that state as CORE_BW's report prints it.
  - A verdict word whose point and 95% lower bound both lie farther than that from 30% is "receiver-robust".
  - Any other verdict keeps its word, printed with "within the receiver bound" beside it.
- If U_s > 1 pp (the scale of 3.6's M1), the state's CORE_BW numbers are labelled "receiver-limited". If an r2 is adopted later, 3.6 is read for CORE_BW (ruling 3.7's last bullet and 4.5).

### 4.7 Guards

A failed guard voids D2c: nothing is read, the harness is fixed, and D2c is rerun.
- **G1:** the taps change nothing. The first geometry of every combination, flown without the sinks (and without `own_out` where its configuration does not set it), gives the same frame BER and `Rx_Z`, max|d| = 0.
- **G2:** the receiver script equals the export's with the field absent; the receiver blob is `40dc1f9`; the `params.mat` copy's sha256 equals the `-bw` file's.
- **G3:** the seeds and speeds equal CORE_BW's validation design (family 6, block 5, geometries 1-12, the permutation stream above), printed per Eb/N0. Every layer used is in the cell's own grid in the code. The harness's folder holds no CORE_BW data or results file.
- **G4:** on the clean twins, L ≤ 0.1 dB on at least 99% of frames. Our own component left in R_in, from a misaligned or misscaled tap, would raise it.
- The harness prints `RULE rx_fix_rule3.md sha256 <h>`.

## 5. Time budget

- **One gated dispatch** after CORE_BW's report and before P1R: at most 45 min of MATLAB, the gated wrapper with floor 45, the p3 slot, one MATLAB, in the background with one completion notice and no polling (past bug #8).
  1. The tests: D2's six and those of section 1.1, in one `runtests`. A failure stops the dispatch. About 10 min.
  2. The fresh pool: batch 1 (and batch 2 if n < 3), the list, its hash and its commit. About 10-12 min per batch.
  3. D3: the G2 builds, the four arms on the 27 flights, the flat G4 and the reading line. About 13-16 min.
     - D3 starts only if the dispatch has used at most 30 min by then, and no D3 arm starts after 41 min.
     - A D3 that does not start, or does not finish, is not read. It runs whole after P1R's end, before any candidate stage.
- **Readiness.** The dispatch runs only if its code (the tokens, the tests, `rx_d3.m`, the extended seed test) is committed and pushed, and its dispatch note holds the hashes, before CORE_BW's report is out. Otherwise P1R starts, and the dispatch runs after P1R's end.
- **P1R never waits** for anything not ready at CORE_BW's report, and for nothing beyond this one dispatch.
- **Before dispatch** (past bugs #10, #11, #15): no other MATLAB; `p1.log`'s last STAGE line is not GAL, EDGE or WEAK; free commit at least 45 GB; `p3_hand.busy` absent.
- **Then.**
  - During P1R, without MATLAB: the D3 reading, the candidate's design note and its code.
  - Between P1R's end and the timebox (ruling 4.4: two days after P1R ends): stages 1, 2 and 3, about 1.5 + 2 + 3-6 h.
  - D2c, about 1 h per pass, in any free window before the book.

## 6. Fixed points

- This file is fixed before any data it governs. A change is a new file with its own hash, registered before the data it governs; data already read under this file stay read under it.
- A failed guard voids that run only. It is fixed and rerun, and nothing is read from it.
- Adi may veto the thresholds of this file within 30 minutes of its summary. Without a reply, the file stands as committed.
