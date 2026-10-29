### 3.2 D1, the diagnostic run (this section is the rule; copy it unchanged into `rx_diag_rule.md` before dispatch)

**Code.** Branch `rx-ne-fix` (worktree `<main>\worktrees\rx-ne-fix`), new commits on `c580501`. `p.rx_ne_fix` takes tokens joined by `+`; an unknown token raises an error (as now); field absent or `'off'` emits nothing. The built file is copied to `worktrees\link-floor\fix\build_threat_model.m` and put ahead of the export on the path, as in the 07:28 run. Harness: `worktrees\link-floor\rx_diag.m` (new; the machinery of `link_floor_fix.m` and `link_floor_truth.m`; `p.own_out = true` in every R arm so `Thr_sig` is logged). Prints come from the chart through `fprintf` with numeric formats only, captured by `evalc` or `diary`; if the simulation target drops chart prints, a diagnostic output is added only under the token. Code comments short, English, no history tags.

**Arms.** Each is one build, run on the 27 flights with their saved seeds; every arm carries the `log` token.

| Arm (tokens) | What it changes | What it decides |
|---|---|---|
| `log` | prints only | the baseline, guard G1, the per-frame signatures |
| `freq` | candidate (b) | whether (b) brought the frequency back on the three frames (abs(dcfo) ≤ 400 Hz) |
| `freqa` | inside `eq_train` also keep the per-antenna block correlation `Ca(:,b) = Σ_n conj(kn(n)).*y(n,:).'` over the same rows; `bf = angle(Σ Ca(:,b)'·Ca(:,b+1)) / 52` rad per symbol over the 9 pairs 52 symbols apart, in both passes, on the same whitened samples and pairs as (b) | designs 1 and 3's form: it differs from (b) only by per-antenna products |
| `freqf` | the flat path's own estimator (1206-1212: per-antenna one-tap pilot estimates `Hp` from `yw`, `Σ Hp(:,b+1)'Hp(:,b)`, two passes, `Hp` rotated with the samples) in place of the slope | a near-oracle on these near-flat channels (delay spread 81-131 ns; it read +169 Hz on 452/10 in F): whether a correct frequency alone suffices. Never adoptable (d84 item 5: kHz errors on long spreads) |
| `noburst` | burst replacement off (`ga` always measured) | whether the burst rule alone collapses frames. Never adoptable (drops the burst protection) |
| `burstn` | burst rule on its own expectation: flag block b if its residual on the 4 pilot rows exceeds 4 × the sum over those rows of [NR·s2 + Σ_a abs(ga(a,b))² · (sum over the lags that carry an unknown symbol at that row of abs(Gt(a,l))²)] | whether an adoptable rule keeps `noburst`'s effect: a fade no longer looks like a burst, an interferer still does; the constant 4 is kept |
| `freqa+noburst`, `freqa+burstn`, `freqf+noburst` | combinations | whether both steps are needed; whether `burstn`'s form is adequate |
| `hsel1` | `NE > 1` sync on the quiet-slot hypothesis only | whether the hypothesis choice is involved |
| `deq0` | no whole-symbol lag move (`deq = d`) | whether the lag move is involved |
| `log` at Eb/N0 + 30 dB | flights 420, 452, 459, 426 and controls 546, 698 | noise-triggered (recovers) or deterministic (stays) |

**Shadow flat receiver** (token `shadow`, in `log` and `hsel1` only; never used for the output): copies of `y`, `yw`, `Hp` made before the `itf` loop (1277); the flat path's two FIT passes (1179-1222, MODE 1), smoothing and interpolation (1224-1251), MRC, `dd_mvdr` (MRC, `DDI`); its bit errors against `txbits` and its `pilot_mse` printed.

**Also:** F-off against F-all (every new token on, flat channel) on the 27 flights.

**Printed per frame** (one summary line; the harness keeps per-block lines for the 4 named frames, every frame with BER > 0.05 in any arm and 3 clean frames per flight): `hsel`, `d`, `deq − d`, `fc`, `ff`, `bf` of each pass, the final `sy(2)` and dcfo; in every arm the four frequency estimates side by side (slope, b, `freqa`, `freqf`); slip flag (largest wrapped residual of `pq` around the fitted line > π/2); burst flags per block and `rb`/median; per-antenna training power `|Gt_a|²` (dB against the antennas' mean); per-antenna max and min `|ga|²` over the blocks; `s2`; `sy(8)`; `pilot_mse(y, z)` (same yardstick in every arm, reported only); frame BER. From `Thr_sig` in the harness: true per-antenna power in the training window and in each pilot block's window, relative to the frame mean.

**Fresh collapse frames** (decision-free selection; no candidate runs on them in D1): from the as-built frames saved in `link_floor_partA.mat` (or the `clean_val_pools.mat` copy in `worktrees\link-floor\data`), every frame with BER > 0.1 on a validation flight outside the 27; the truth harness (as `link_floor_truth.m`) on those flights; a frame enters the fresh set if its true post-MRC Es/N0 ≥ 8 dB, calibrated on at least 3 clean frames of its flight. The list goes to `results\rx_fresh_frames.txt` with its sha256, written before any candidate touches it.

**Guards** (a failed guard voids D1: no candidate named; fix the harness, rerun):
- G1: `log` reproduces the saved frame BER on 27 of 27 flights (max|d| = 0) with `own_out` on.
- G2: the script with the field absent or `'off'` equals the export's character for character; the `log` script minus its `fprintf` lines equals the off script.
- G3: every arm prints `RXD <arm> tokens ON: ...` naming its own steps (past bug #2) and reaches its done line.
- G4: F-off against F-all max|d| = 0 on `Rx_Z` and frame BER, 27 flights.
- The harness prints `RULE rx_diag_rule.md sha256 <h>`; the same hash is written in the dispatch note before dispatch (Review F6).

**Reading table** (recovered = frame BER ≤ 0.05; 426/9, 511/12 and 411/4 reported only):
1. **Primary candidate:** among the adoptable arms `freqa`, `burstn`, `freqa+burstn`, the one that recovers the most of the three frames, at least 2. Ties: fewer steps changed; then the lower 27-flight FER; then the lower 27-flight BER sum.
2. **Second candidate** (read only if the primary fails 3.5): if the primary contains `freqa` and fails only criterion 1d (accuracy), the same with `ml` in place of `freqa`; otherwise the next adoptable arm in the order of point 1 that also recovers at least 2.
3. **No adoptable arm recovers 2:** the diagnostic arms name the next design.
   - `freqf` or `freqf+noburst` recovers ≥ 2 while `freqa` and `freqa+noburst` do not: the lag-model block correlation itself is corrupted (template, 2.2 c); go to D2.
   - `noburst` or a `+noburst` arm recovers ≥ 2 while `burstn` and `freqa+burstn` do not: the burst repair has the wrong form; redesign it with no new constant and read it under 3.5.
   - `hsel1` or `deq0` recovers ≥ 2: a sync candidate is designed and read under 3.5.
   - only the shadow flat receiver decodes ≥ 2: build G' (3.3) and read it under 3.5.
   - nothing decodes ≥ 2: go to D2.
4. **Class, reported with the reading:** noise-triggered if `log` recovers the frame at +30 dB; "training in a fade" if an antenna's true training-window power is ≥ 10 dB below its own strongest block on that frame.
5. (b)'s dcfo on the three frames is reported; it answers the fix agent's open question.
