29.10.2026: the D1 reading's open point 4 states that a candidate born after D2 is read under ruling 3.7's last bullet ('a new candidate under a new pre-set rule with new fresh frames'); the text below is ruling sections 3.5 and 3.6 copied unchanged.

### 3.5 Adoption rule (copy unchanged into `rx-ne-fix\docs\rx_fix_rule2.md`, commit, print its sha256 in every run log, before the first candidate run)

**Guards** (any failure voids the reading):
- G1: with the field off, the 27 flights reproduce their saved frames (max|d| = 0); 10 flights per Eb/N0 of the clean validation pool reproduce W's file; if stage 3b reads r1 from saved pools, 10 of its geometries re-simulated off reproduce them.
- G2 text identity; G3 on/off lines; G4 `NE == 1` and `NT > 1` bit-identical (unit tests, and F-off against F-on on the 27).
- G5: `MODEL_TAG` bumped in the stage 2 and 3 trees; the clean reference copied into each tree and asserted finite (past bug #16).

**Stage 1** (minutes; the candidate built without `log`):
- 1a, the three frames (seen by D1): at least 2 at BER ≤ 0.05; for a frequency candidate, abs(dcfo) ≤ 400 Hz on every recovered frame.
- 1b, fresh frames (held out): with n ≥ 3 frames in `rx_fresh_frames.txt`, at least ceil(n/2) at BER ≤ 0.05; with n < 3, reported only.
- 1c, no harm on the 27 flights: frames newly lost (CRC pass to fail) ≤ 1; FER27 ≤ 0.3648; 546, 698, 658, 573 at BER 0; on 430, 510, 514 at 9 dB, FER no worse, no newly lost frame and BER ≤ 1.10 × as built (a structural change moves bit counts of unchanged packet outcomes; (b) moved them by 1.1-1.7%).
- 1d, accuracy (frequency candidates only): median abs(dcfo) over frames with as-built BER < 1e-3 at most 1.5 × as built (design 1's predicted lag-1 loss, √2.3).

**Stage 2** (non-selected population; about 2 h on 6 workers): the clean validation pools (set `val`, seed block 4, runs 401-700, every Eb/N0 of W's `clean_val_pools.mat`, 20 frames) rebuilt with the candidate in `<main>\worktrees\rx-adopt`; r1 = W's file (read-only copy, sha256 `99e16d00…2c30`).
- 2a: at each Eb/N0, a one-sided exact McNemar test on frames lost under one receiver only shows no significant worsening at α 0.05 (0.025 for a second candidate);
- 2b: pooled over Eb/N0, frames lost only under the candidate ≤ frames lost only under r1;
- 2c: clean FER at each Eb/N0 ≤ r1 + 0.1 pp;
- 2d: CREF mean BER at 9, 12 and 15 dB ≤ r1 (`clean_ref_rebuild('check')` on the new file).

**Stage 3** (about 3-6 h):
- 3a PHYV: `validate_phy('V12c', 1:3)` (clean MRC on the delay line, 7 spreads): every row within its 0.5 dB gate, and no spread worse than r1 by more than 0.2 dB. r1 = W's `phy_validation_v12c.txt` once a one-point run with the field off reproduces it; else both arms run. V11 and V12c rows 4-9 are bit-identical by G4. `validate_phy('V13')` passes its rules.
- 3b threat footprint (paired; profile 1's validation geometries of the policy pools' split 2, read-only copies): states `none`, `tone_jamming`, `jamming` (the lecturer's three) and `noise_burst` (the burst rule's own target); profile 1's pool levels; the four core configurations and the two MRC configurations of the escalation ladder (`freq_diversity+power_control+fec_interleave`, `channel_switch+rate_reduce+power_control`); Eb/N0 0:3:15; 10 geometries per (state, level, Eb/N0); 20 frames; 6 workers. **No harm:** no (state, Eb/N0) cell, pooled over levels and configurations, with ΔPER > +1 pp and a paired flight-bootstrap 95% interval excluding 0. The same data is read by 3.6.
- 3c: `test_core` in full on the candidate's tree, plus the new tests.

**Decision:** adopt only if every guard and 1a-1d, 2a-2d and 3a-3c hold. At most two candidates are read under this rule, in the order of 3.2 points 1-2. A failed candidate is not tuned and not re-read on these data.

### 3.6 Materiality for the profile-1 family (read on 3b's data, only once r2 is adopted)

MATERIAL if any of:
- M1: in a (state, Eb/N0) cell pooled over levels and MRC configurations, abs(ΔPER) > 1 pp with a paired 95% interval excluding 0 (cells with fewer than 36 geometries: no verdict);
- M2: profile 1's deployed hybrid detector (read-only copies of W's `trained_detector.mat`, `fusion.mat` and the `splits.mat` norm) changes its argmax on more than 1% of decision windows in any state, pooled over levels, Eb/N0 and configurations;
- M3: the validation PER reduction of the mapped core action against `no_action`, pooled per state for `tone_jamming` and `jamming`, crosses the lecturer's 30% between r1 and r2.

Otherwise SMALL. The thresholds are fixed now.
