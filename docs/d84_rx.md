# D84: the receiver on the delay line, the clean link's floor (branch d84-rx)

Branch `d84-rx` from v7-merge `d299036` (with `86e57dc`, the merge-defect fix). Input: `docs/d84_link.md`, V12c section: after A10 the clean K -5 dB row (MRC) shifted +6.19 dB at 1 us and +11.44 dB at the 2.25 us clip (limit 0.5 dB), attributed there to the zero LoS Doppler of V12c's broadside geometry. This note is the merge input for the D84 entry of DECISIONS.md (DECISIONS.md itself is not edited here). Every choice was made on dev flights (seeds 7601-7730, never validate_phy's or the tests'); V12c's flights were used for the diagnosis only.

## Diagnosis

**Not the LoS Doppler.** The same 100 dev flights (K -5 dB, 1 us, 15 dB, 4900 frames, identical channel draws): D83's random LoS cosine 3.33e-4 BER with 8 frames lost (BER > 1e-2), zero LoS Doppler 3.72e-4 with 8 frames lost. The floor is a rate of lost frames, about 0.16% at 1 us and 4.2% at the clip (1533 ns on the line: 6.9e-3 BER, 208 of 4900 frames lost), independent of the LoS Doppler and of the Eb/N0. V12c flies 980 frames per point: at 0.16% it meets 1.6 lost frames on average, none with probability e^-1.6 = 20% (D83's draws), one on D84's draws (flight 400101, frame 45: 0.53 BER, alone 5.5e-4 at 15 dB). Group A's 20-flight comparison was within that scatter. So every flight whose delay spread exceeds a few hundred ns was exposed, hover or not.

**Not physics.** On the true channels of the lost frames at the clip (a genie LS fit of the received samples on the transmitted symbols), the optimal linear receiver (every antenna, half-symbol taps over 18 symbols) reaches a median SINR of 22.8 dB (10th percentile 20.2 dB) at 15 dB Eb/N0, where QPSK errs below 1e-10. The delay line keeps the received power (test_delay_line) and spreads it over paths, so the matched-filter bound is that of the flat channel with more diversity. The floor was the receiver's. Five mechanisms, all in the MRC receiver on the line (the equalizer path; the MMSE space-time receiver lost no frame on 50 dev flights of the same cases: 4.0e-6 at 1 us, 1.9e-5 at the clip):

1. *Arrival window.* The training's energy was searched over arrivals 0-4 symbols, the frame's own uncertainty, while the line holds paths up to 4.5 us after the arrival: a frame arriving late had its strong paths beyond the window. The long training is a Zadoff-Chu chirp (root 1, length 16): s(k-1) s(k)* = exp(j pi (2k - 1) / 16), so a path one symbol off an arrival correlates with it at an offset of 1/(16 T) = 62.5 kHz. V12c's lost frame: arrival 15.3 of 16 samples, frequency off by 57 kHz. At the clip, 14 frames were 57-58, 125-135 or 184 kHz off.
2. *Timing on the strongest path.* The arrival is the largest training energy, up to 4.5 symbols after the first path; the equalizer's lags reach 2 symbols before it, so the line of sight (24% of the power at K -5 dB) fell outside. V12c's flight 400107, frame 12: timing 11 samples after the LoS, 21% of the channel's energy outside the lags, 2.9e-3. At the clip the lost frames' timing lay 8.8 samples after the first path on average (others 1.4), with 24% of the energy outside the lags (median; others 0.5%).
3. *Whitening hypothesis.* With the window widened, the local power inversion (hypothesis 3) won the timing-prominence choice on 6 clean frames at the clip, its frequency 80-250 kHz off: on a dispersive channel the training's energy spreads over the delays, so a timing peak over its window mean no longer tells a coherent training from a whitened one.
4. *First pass.* The lag channels came from 4-symbol pilot blocks, where a lag's correlation picks up the other lags' unknown data symbols: on long channels 113-160 of the 516 symbols were wrong after the first pass, and the decision-directed passes stalled at 30-77.
5. *Residual frequency.* The pilots' phase steps on the single tap at the arrival erred by 2-3 kHz on channels spread over the line, rotating the 128-symbol estimation windows of the decision-directed passes by up to 2.4 rad.

Beyond these, the 11-tap equalizer after the MRC: on the true channels at the clip the MRC + 11 taps reach a median SINR of 14.0 dB (1st percentile 10.0 dB), 21 taps 16.8 / 13.0 dB.

## Fix (`build_threat_model.m`, `rx_taps.m`: the MRC receiver on the delay line only)

- *Search over the line's delays* (TE = arrival window + p.tdl_max_ns): the training's energy at every delay where it can lie. *Frequency* where its sum over the delays peaks: each path's periodogram peaks at the offset, so the sum (the same non-coherent sum the receiver takes over antennas) collects every path at the true frequency, while a chirp ridge holds only the long training's share, (32/72)^2 = 0.2 of a path's energy (Morelli & D'Amico 2007, eq. 24 and the coarse/fine search, Sec. 3; their outliers are the peaks far from the truth). The arrival is the largest energy at that frequency.
- *Hypothesis* by how much that summed energy's frequency peak stands out over the searched band.
- *Lags moved by whole symbols* from the arrival (its sampling phase kept) to where they hold the most training energy, unless that is within 1% of their energy at the arrival. Moving by a fraction of a symbol was tried and dropped: half-symbol phases put the raised cosine's band edge into the symbol-spaced equalizer as a null (K -5 dB, 64 ns: 8.7e-6 to 1.0e-4 at 15 dB).
- *First pass* (`eq_train`): the channel of every lag by joint LS on the training's rows whose symbols are all known, robust to a burst over part of them (rows whose residual exceeds 4 times the median weighed down by that ratio); its phase at every pilot block from the correlation of the block's samples with the known symbols' share of them (on the whitened samples, so an interferer the whitening suppresses does not move it); the residual frequency from the slope of those phases over the frame, twice; every antenna's gain at every pilot block against the training's channel (the fading over the frame: at the envelope's 358 Hz the channel decorrelates to J0(2 pi 358 Hz 0.63 ms) = 0.6 between the frame's ends), a block whose fit leaves more than 4 times the median residual keeping the common phase, smoothed [1 2 1]/4 and interpolated; then MRC and the linear MMSE equalizer. A common phase per block alone was tried first and dropped: at 358 Hz it lost K -5 dB, 64 ns to 6.5e-4 at 15 dB (dev; 6.6e-6 before the branch). This is the 802.11 receiver's sequence (IEEE 802.11-2007, 17.3.2.1 a: the long training for channel estimation and fine frequency; 17.3.9.7 b-f: fine timing, coarse and fine frequency, de-rotation, the channel from the training, then for every data symbol the phase from the pilots). The one-tap pilot steps (FIT) stay for the flat receivers.
- *Equalizer of 21 taps* (`rx_taps.m`: twice the line's window on either side). The MRC output's symbol response spans +-7 symbols; on the dev flights at the clip 11 taps left 3.1e-5 at 15 dB, 21 taps 3.0e-6. The decision-directed passes compute the MRC output once per symbol (bit-identical to before, about half the work of the 21 taps).
- Unchanged: the flat receivers, the MMSE space-time receiver (every V12c jammer row is bit-identical), the outputs' meaning (output 6's arrival is the timing peak, the remodulation in extract_closed_loop_frames uses it).

Not adopted (dev flights): hard-decision ISI cancellation in the decision-directed passes (errors lock in: 31 against 1 for the equalizer on a frame), a decision-feedback equalizer on the MRC output (no gain over 21 taps once the first pass is fixed), a space-time equalizer under white noise (2.2e-3 at the clip: its +-4-symbol regressors leave our own ISI unmodelled), 5 precursor lags (9.4e-4 at the clip), frequency tracking from the decision-directed windows (no gain).

## Results

### Dev flights (15 dB unless stated; frames lost: BER > 1e-2)

| case | before | after |
|---|---|---|
| K -5 dB, 1 us, 100 flights | 3.7e-4, 8 lost | 4.0e-7, 0 lost |
| K -5 dB, clip (1533 ns), 100 flights | 6.9e-3, 208 lost | 3.4e-6, 0 lost |
| K 2 dB, clip (1388 ns), 50 flights, 9 / 15 dB | 1.2e-4 / 1.3e-5 | 6.3e-6 / 0 |
| K -5 dB, 64 ns, 50 flights, 9 / 15 dB | 4.1e-4 / 8.7e-6 | 4.1e-4 / 8.3e-6 |
| 358 Hz, K -5 dB, 64 ns, 30 flights, 9 / 15 dB | 4.3e-4 / 6.6e-6 (19 / 0 lost) | 4.8e-4 / 7.3e-6 (21 / 0 lost) |
| 358 Hz, K -5 dB, 1 us, 30 flights, 9 / 15 dB | 3.0e-4 / 1.7e-4 (7 / 3 lost) | 2.3e-4 / 1.3e-4 (6 / 5 lost) |
| V12c's flights, K -5 dB, 1 us (diagnosis only) | 5.5e-4, 1 lost | 0, 0 lost |

### validate_phy (scratch copies of 17c9e3e; the clean rows in three processes, 38-42 min each)

Flat checks, identical to `docs/d84_link.md` (the flat receivers are unchanged): V1-V7 gaps +0.03 / +0.01 / +0.08 / +0.06 / +0.13 / +0.14 / +0.07 dB, all PASS; V8a 2.77e-1 ... 2.67e-1, V8b 2.32e-2 ... 9.99e-6; V9, V10 (16.24 vs 16.23 dB) PASS; V11 +0.91 / +0.98 / +4.92 dB; V12 +0.49 dB (480 ns NaN, informational).

V12c, shift of the delay line against the flat channel [dB] at 64 / 138 / 234 / 302 / 372 / 1000 / 2250 ns:

| case | d84-rx | d84_link.md | limit | verdict |
|---|---|---|---|---|
| clean K -5 dB, MRC | +0.00 / +0.00 / -0.03 / -0.04 / -0.00 / -0.04 / -0.11 | -0.05 / -0.05 / -0.00 / +0.00 / +0.00 / **+6.19** / **+11.44** | 0.5 | PASS (was FAIL from 1 us) |
| clean K 2 dB, MRC | -0.21 / -0.25 / -0.29 / -0.28 / -0.29 / -0.31 / -0.41 | -0.17 / -0.23 / -0.23 / -0.21 / -0.20 / -0.07 / -0.03 | 0.5 | PASS |
| clean K 10 dB, MRC | -0.18 / -0.20 / -0.21 / -0.21 / -0.22 / -0.23 | -0.16 / -0.17 / -0.17 / -0.16 / -0.16 / -0.14 | 0.5 | PASS |
| jam rows, MMSE (16 / 30 dB, rho 0.3 / 0.9, 358 Hz informational) | as d84_link.md | | 3 | jam 30 dB, rho 0.3: FAIL at 1 us (+14.08, as before); the others PASS |

The jammer rows are not rerun: they run the MMSE space-time receiver, whose code this branch does not touch (the cost run's 490 jammed frames below give the same BER, 5.40e-4, on the base and on 17c9e3e).

Verdicts: channel model: the flat channel fails, the link runs the delay line -> PASS; receiver on the delay line: FAIL only at 30 dB, rho 0.3, 1 us (as in D77-D84). The clean rows now run below the flat channel at every spread (frequency diversity of the line).

### Run time

The same 490 frames on the base and on 17c9e3e, run side by side (ms per frame): clean MRC, K -5 dB, 1 us 49.5 / 49.1; the clip 45.3 / 47.1; jam 16 dB, MMSE, 1 us 77.3 / 75.9. The first pass's LS and per-block gains cost about what the decision-directed MRC output saves.

### Tests

`code/tests/test_core.m` on a scratch copy of 17c9e3e (30.6 min): 117 passed, 3 failed. `test_rate_reduce_chip_level` fails identically on the base (jamming: 39.04 against 39.98 with tolerance 0.5; a flat channel, receivers this branch does not change); `test_clean_pool_identity` (data/splits.mat) and `test_result_status` (no trained network) need files the scratch copy does not hold. Every receiver test passes. New: `test_equalizer_sync` (four static channels of known paths at 30 dB: the arrival at the window's end with a path 15.6 / 12.5 dB stronger one symbol later, six paths in the three symbols before the strongest, the line of sight 3.25 symbols before a path 0.5 dB stronger; the frequency within 500 Hz and every frame decodes; the receiver before this fix lost them, 2-7 kHz off and 70-530 bit errors per frame). Extended: `test_receiver_delay_spread` (the clip, below 1e-3 at 12 dB), `test_rx_taps` (21 equalizer taps). Changed: `test_slot_and_burst_measurements`, noise bursts: every frame shows edges, in place of a median of at least 5 (below).

## Open risks

- *The MRC link under noise bursts.* At the default 16 dB bursts the MRC link is lost with either receiver (31 dev flights, 12 dB: BER 0.421 before, 0.438 after), but the decisions between the bursts are a little worse (frames below 0.35 BER: 78 of 341 before, 58 after), and the receiver measurements that need correct decisions move with them: the energy edges of the residual (`edges`) fall from a median of 4 to 2 per frame (frames with at least 5: 48% to 36%; flights with a median of at least 5: 15 to 12 of 31; the clean link 0 in both). test_slot_and_burst_measurements asked a median of at least 5 on its single flight (17 before, 7 after), now edges in every frame of that flight (met by both). The detector is retrained on the new frames (A0 onwards); whether the noise-burst class loses recall there is open. The training-only channel of the first pass is the cause (a burst over the training corrupts it for the whole frame; the robust LS and the whitened phases recovered about half the loss: BER 0.455 to 0.428; the per-block gains, 0.438).
- *358 Hz at 1 us.* At the envelope's top Doppler and K -5 dB, 1 us, the MRC link keeps a small floor with either receiver (15 dB: 1.7e-4 before, 1.3e-4 after; 3 and 5 of 1470 frames lost): the per-block gains follow every antenna's fading, not every lag's. Per-lag tracking over the frame is the next step if such flights matter; V12c has no clean 358 Hz row.
- The lag search assumes paths within p.tdl_max_ns of the arrival; a longer line needs TE and the lags to follow (both read it).
- Not covered by V12c: the MRC receiver on the line under a continuous jammer (no V12c row); its sync now chooses the whitening by the frequency peak.

## Merge notes

Only `code/link/build_threat_model.m` (the Rx script: sync, first pass, `eq_train`, the decision-directed passes' MRC output), `code/link/rx_taps.m` (t.ne) and `code/tests/test_core.m` change. The pools and the dataset of the MRC configurations on the line change (A0 and later stages rerun, as D84 already requires).
