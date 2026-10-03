# v7 plan (worktree C:/Users/Adi Suliman/uav-gcs-v7, branch v7-dev from v6 7dfe444)

Approved by Adi 2026-10-01. Everything goes into training (except held-out triples / unseen-threat tests).
Full runs start only after v6 ends. Code + smoke tests now (serial smoke, light CPU).

## Step 1 - real receiver (gate: PHY validation real vs ideal before anything else)
- Frame: preamble (known, two identical halves for CFO, as 802.11 STF/LTF: Pirayesh) + data with periodic pilot
  symbols + quiet slot. Overhead from a source (802.11: 4 pilots of 52 subcarriers; preamble 16 us).
- Impairments: carrier frequency offset per flight (oscillator tolerance: SOURCE NEEDED, 802.11 +-20/25 ppm),
  Doppler shift of the LoS component (fd cos angle; today the LoS has none), unknown frame start (timing search).
- Receiver: preamble cross-correlation timing, CFO from preamble, residual phase from pilots, channel from
  preamble+pilots, MMSE w = Ryy^-1 h with Ryy from all samples (needs no symbol knowledge).
- validate_phy: curves real vs ideal; report the estimation loss.

## Step 2 - protocol-aware attacks on that receiver (Pirayesh table)
- preamble jamming (jams only the preamble; energy efficient), pilot jamming, preamble phase warping /
  false preamble (sync deception). Preamble nulling: Pirayesh says hard to realize -> unseen test only, if at all.
- Levels capped at 30 dB like every in-band threat.

## Step 3 - flight dynamics
- Hover / slow 0-29 km/h (Khawaja: rotorcraft measured while hovering). Speed envelope 0-161 km/h.
- Maneuvers: coordinated-turn rate g*tan(roll)/v, roll within Sun's measured values; GCS and interferer
  directions rotate during the flight; shadowing on when roll > 5 deg (Sun's criterion), depth from Sun's table;
  polarization tilt loss 20log10(cos roll); monopole elevation pattern (Cui E-plane) incl. overhead pass.

## Step 4 - GCS antenna (every profile)
- Done (D73): low-power radio at -6 dBm on a tracked 12 dBi antenna, 6 dBm e.i.r.p. under the 11 dBm cap
  (ETSI EN 300 328 density; Israel 100 mW), 10 dB over an omni on the same radio; power_control up to the cap.
- Tracker errors enter only by their RF effect: the measured pointing error per flight (Nugroho) through the
  ITU-R F.1336 main lobe, and a lost target as the omni fallback, i.e. path loss. No GNSS attack and no
  telemetry model (out of scope).
- Gain applies to our signal only (the jammer is received by the UAV antennas).

## Step 5 - triples
- Physically consistent triples (three emitters; two emitters + fault/shadowing; emitter + shadowing + path loss).
  Some in training, the rest held out (like C2g).

## Step 6 - adaptive adversary (unseen tests)
- quiet-slot-aware jammer (silent in the slot -> mimics reactive; or jams only the slot), rate-adaptation attack
  (keeps throughput below a threshold, Pirayesh).

## Step 7 - profile 3 (4 antennas)
- profile.json n_rx 4; recompute fixed directions and survivability geometries for alignment 0.25/0.2/0.93.
- Read Winters 1984 (N-L diversity) before citing.

## Order of full runs (after v6): P1 (3 ant), P3 (4 ant); P2 (2 ant) last / optional (pending Adi).

## Step 1 status (2026-10-01 13:30)
- Real receiver: quiet slot moved before the frame + guard after; dual whitening sync (quiet slot / training
  region, chosen by timing-peak contrast); pilot residual frequency removed; local-whitening MMSE first pass;
  2 decision-directed passes. Bad frames (BER>5%) of 120 at 161 km/h, real vs ideal: clean 0/0 (~1 dB loss),
  jam 10 dB 0/0, spoof 3 dB 0/0, reactive 16 dB 32/0, pulsed 16 dB 23/0, spoof+sweep 14/0, jam 30 dB ~80/246 vs 0.
- jam 30 dB: 0 failures with a static jammer channel (K_i 40 dB); failures grow with Doppler (6% at 29 km/h,
  ~35% at 100, ~50% at 161 km/h); frequency estimates of failed frames are off by 5-22 kHz even without
  oscillator offset -> residual of a time-varying jammer after whitening corrupts the frequency statistics.
  Waiting for literature (fork P1/P2) on practical null depth; candidates: multi-lag frequency estimator
  (Luise-Reggiannini / Fitz), local whitening for sync.

## Detector fixes for v7 (from the fork's review of the v6 code, 2026-10-01)
- Label noise antenna_fault: frames with the contact never open are labelled antenna_fault (~91% at duty 0.05 /
  86 Hz). Fix: Threat output act = share of the frame with the contact open; relabel act == 0 as none (as benign).
- Vibration aliasing: one sinusoid per flight sampled every 20 ms -> stroboscopic visibility; use the measured
  vibration spectrum (Verbeke: modes / harmonics, jitter) instead of a single pure tone.
- KPI 2 OOD: base Mahalanobis (Lee 2018 weakest variant); consider input pre-processing / layer ensemble, energy
  score (Liu 2020), MSP (Hendrycks & Gimpel 2017); Outlier Exposure (Hendrycks 2019).
- CUSUM over cycles (Xie 2021 survey, Page) for intermittent fault / low-occupancy WLAN at the decision level.
- Citations: "N antennas null N-1" -> Winters, Salz & Gitlin 1994 (not Shebert: 4 elements, 68% for 3 emitters);
  Shebert's hybrid is protocol-decoder selection, not our CNN+features; Yu 2020 (S_09) withdrawn - never cite;
  Isolation Forest psi: docs say 256, code min(8192, N) (Liu 2008 sec. 5.4 backs larger) - align the docs.
- DONE in v7 code: antenna_fault act = share of the frame with the contact open (single threat); run_dataset_sweep
  relabels act == 0 frames as none.

## Receiver: literature (fork, 2026-10-01)
- Marti, Koelle & Studer, IEEE TSP 2023 (arXiv 2208.01453): quiet-slot jammer estimate "fails spectacularly" when
  the jammer is silent there; joint jammer estimation + data detection over the coherence interval (MAED/SO-MAED)
  stays within 2-3 dB of jammer-free at 0.1% BER for all jammer types incl. 30 dB, 20%-duty bursts. -> our DD
  per-window estimation is a simple relative; consider MAED-style projection iterations.
- Pulsed jammers: fast-attack / slow-release null memory (DuPree, TRW patent 5,175,558); blanking cost
  N0/(1-bdc)(1 + I0/N0 + R_I) (Garcia-Pena 2021); per-symbol noise-variance LLR scaling (Baldi 2013); interleaver
  depth ~ burst length.

## Citation hygiene for the report / DECISIONS (fork review)
- "30 dB over our signal": Yuan's 30 dBm vs 0 dBm are transmit powers (not received JSR) - word as D61 does; Liu 2018
  check pending.
- Alshiekh shield guarantee: tabular learners, not DQN; preemptive shield, minimal interference, 3-step hold OK.
- Hold on every change (D63): W03 backs a slower timescale for frequency switching only.
- C.hist = 4: Mnih frame stack (3-5 work); argue "history covers the jammer memory" (Yuan; S14); "history 8" unsourced.
- Do not cite Yuan for gamma (reversed); van Hasselt overestimation-vs-actions: caveats; 500-update target unsourced.
- Tlili: "jamming second most common" rests on one reference; ">50 km other link types" not in Tlili (D70).
- Oli & Mahalal: "high likelihood" is GPS jamming; <10 ms is their IDS threshold, not a standard.
- Yang's 5th strategy is "deceit", not "bypass" (ranking file).
- Adaptive adversary models with sourced parameters: W01 threshold-adaptive reactive jammer (stay 0.8 after hit,
  0.2 otherwise), Yuan comb jammer switching after a miss, S14 jammer blocking last-5-slot channels; defences:
  power below sensing threshold (W01), randomized channel choice.

## Step 1 status (2026-10-01 15:10) - joint timing/frequency search (CAF) added
- Bad frames of 120 (real receiver, 161 km/h): clean 0, jam10 0, spoof 0, pulsed 2, reactive 16, spoof+sweep 6, jam30 46.
  jam30 speed test: 5% / 22% / 30% at 29 / 100 / 161 km/h (literature: physical limit of 3 antennas, covariance aging).
- Committed 16f1c58 on v7-dev (pushed). Tests 14/14. validate_phy now has V11 (real vs ideal loss).
## Step 2 sources (Adi's IEEE downloads, fork notes)
- Clancy 2011 ICC: pilot jamming ~2 dB more efficient than barrage, pilot nulling ~7.5 dB (BER 0.4, QPSK, pilot
  density 1/8; nulling needs known pilot values) -> pilot-attack levels; keep pilot values secret.
- La Pan, Lichtman, Clancy & McGwier 2013 WPMC: sync-amble randomization + CAF acquisition, "dramatically improves"
  sync under smart jamming, minimal cost -> our CAF sync is the sourced design; add secret/randomized training.
- La Pan 2012 MILCOM (false preamble moves the timing peak), 2013 ICASSP (frequency-sync attacks): attack models.
- Li 2022 IEEE WCL: intelligent reactive jammer (tracks when it detects us, sweeps/combs otherwise) + DRL defence
  with power + idle-channel choice (power concealment) -> adaptive-adversary model + possible power-down action.

## Approved 2026-10-01 ~15:40: three realism additions
- RF-chain mismatch (phase/amplitude per antenna, Bakr: 1 deg / 0.1 dB -> ~-34 dB null floor).
- Overhead-pass test scenario (UAV antenna null below: -24 / -30 dB, Badi 2019).
- PHY validation curve with a ground reflection / delay spread (Sun: specular 20-80% of LoS, RMS-DS 15-153 ns).
