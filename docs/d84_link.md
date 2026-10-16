# D84, group A: the link, the threats and the dataset (branch d84-link)

Source of every item: the pre-launch review of v7-merge a66ebb9 (2026-10-11), findings L- (link and receiver physics), T- (threats and dataset) and S- (sources); the fix plan's group A, items A1-A14. Every change lands before any v7 reading. This note is the input of the D84 entry of `docs/DECISIONS.md`; it does not replace it.

**Consequence for the runs:** the threat link changes (the reactive trigger, airframe shadowing, the cap, the LoS Doppler, the calibration error, the noise bursts, the delay spread of high flights) and so do the dataset's labels and cell sizes: A0, A4v, A5 and every later stage rerun.

---

## A1. The reactive jammer listens to our transmitted frame (L-F1, T-F1, blocker)

**Why.** The jammer was triggered per sample by OUR signal as the UAV receives it, after its fading, airframe loss and a path-loss step (`ys = y(:, 1)`, `abs(ys(i))^2 > threshold`). A reactive jammer senses our transmission over its own channel; it cannot follow our symbol envelope at the UAV. Two artefacts followed: after a path-loss step the jammer fell silent (reactive + path loss = path loss alone in the pools: q_react 0, q_iot 0), and its per-sample gating correlated its residual with our envelope (env_corr 0.117 against -0.030 for a barrage jammer), a feature a real reactive jammer does not give.

**Decision.** `build_threat_model.m`: the Threat block takes the transmitter's output (Tx, before any channel) and the frame's arrival delay at the UAV (Channel output 2). An energy detector, protocol-unaware, marks the frame from the first to the last sample of our transmitted waveform above `p.reactive_threshold` of its mean power; the jammer is on from that start plus the reaction delay `p.reactive_delay_s` until the frame ends, at the frame's arrival. Level and in-band cap as before. The reaction delay is 3.75 us (15 samples): the shortest jamming-initialization delay Wilhelm et al. measured (Fig. 4a, digitised; mean 14.4 us), the detector's own time taken as zero, so the most severe measured value; zero delay is not measured by any source. A jammer off the GCS-UAV line adds a geometric delay (path difference over c), zero on the line, so the delay stands for the most severe geometry too.

**Sources.** Xu et al. 2005 (A02), Sec. 2: the reactive jammer stays quiet while the channel is idle and transmits as soon as it senses activity. Wilhelm et al. 2011 (V7_Wilhelm2011, WiSec), Sec. 5.1 and Fig. 4a: t_init 3.75-21.8 us (digitised), mean 14.4 us, plus 4 us of their correlation detector (protocol-aware, not used here).

**Tests.** `test_reactive_trigger`: the generated Threat code triggers on `xt` (the Tx output) and no longer on the received signal; with our signal removed at the UAV ('GCS' 0) the jammer still jams, at the noise floor before the frame's first sample + 15 samples, more than 25 dB above it over the frame, at the floor after its end (two frames); with a 22 dB path-loss step the jammer keeps q_react above 10 dB, equal before and after the step within 2 dB (its power is fixed), and its recorded level is the cap (30 dB) after the step. `test_receiver_measurements` (quiet slot: silent, q_react above 10 dB) unchanged.

**Result (chk, 9 dB, JSR 23 dB, 6 frames).** Reactive alone: q_react 33-36 dB, q_iot 1 dB (silent in the quiet slot). Reactive + 18 dB path loss: q_react 17-20 dB in every frame (D83: 0 dB after the step), level 30 dB (capped).

## A2. Airframe shadowing only where the airframe is in the line of sight, at a roll the level is measured at (L-F2, S-1 blocker, T-F2 part)

**Why.** `shadow_hidden.m` hid an antenna whenever |roll| > 5 deg and the GCS lay more than 30 deg off the heading, at the full drawn depth (up to 25 dB). Sun et al.'s roll > 5 deg is their criterion to declare an event in the measured data (Sec. III, with a third: at least 5 dB of measured excess loss), not the smallest roll of one: the events' largest rolls are 16.1-58.3 deg (Table II), and the median loss grows with the roll. The model also hid antennas whose belly had the GCS in view (the UAV banking away from it), and hovering multirotors in wind (no source). Share of flights hiding an antenna: 73.5-74.2% (reviewer and D83), of which 56.5% had the GCS below the belly's horizon.

**Decision.**
- *Geometry* (`shadow_hidden.m`): the belly antennas are hidden only when the GCS is above their horizon in the body frame (cz < 0 of `uav_attitude_db.m`: the UAV banks toward the GCS by more than its elevation), the GCS more than 30 deg off the heading, and the roll inside the level's band (below). The far-end rule (D83) stays.
- *Depth and roll paired* (`shadow_roll_band.m`): Sun et al. fit the median loss against the event's largest roll, S = A + n (roll - 16.1) + X, X ~ N(0, sigma^2), rolls 16.1-58.3 deg. At 2.4 GHz the loss lies between their bands (C-band about 5 dB more, an electrically larger obstruction, Sec. IV-A); the levels (6-25 dB, D73) come from the C-band statistics (median 15.5 +- 4.9 dB), so the C-band fit pairs them with the roll: A 12.4 dB, n 0.25 dB/deg, sigma 4.4 dB, the more severe of the two measured bands (L-band: 9.6 dB, 0.09 dB/deg, 2.8 dB, would not support 25 dB at any roll within 57.9 deg). A level is flown only at rolls whose fit lies within 1.96 sigma of it (two-sided 95%), within [16.1, 57.9] deg (57.9 deg the largest bank of the envelope, inside Sun's 58.3): 6 dB at 16.1-25.0 deg, 8 dB 16.1-33.0, 12 dB 16.1-49.0, 15-21 dB 16.1-57.9, 23 dB 24.0-57.9, 25 dB 32.0-57.9 deg. The level stays the event's median loss, the dataset and decision levels unchanged.
- *Hover:* no source measures shadowing on a hovering multirotor or one holding position in wind, so none is flown below `p.shadow_v_min` = 8 m/s (Khawaja et al.'s slowest flying UAV, the speed below which the attitude is the wind tilt of `hover_attitude.m`). A hover cell then flies no hidden antenna: its episodes are no threat episodes (link_env.m K.on), stated as outside the sources.
- *Fixed views* (survivability map, gallery, console): the bank is the roll at which the fit equals the level (`shadow_roll_band.m`, second output; 28.5 deg at the nominal 15.5 dB, 16.1 deg up to 12.4 dB, 57.9 deg from 22.85 dB), the GCS abeam, a coordinated turn (D83's 16.1 deg for every level replaced).
- *Dataset* (`run_dataset_sweep.m`): the shadowing cells fly N_SUB flights that hide an antenna in some frame of the sub-run, one per fold, found from the flights' draws before they are simulated (`flight_draws.m`, d.hidden; the rejected seeds are simply skipped). This replaces the plan's "N_SUB over the share, spread over the folds": with a hit share h, 1/h sub-runs per fold leave a fold without a single hiding flight with probability (1 - h)^(1/h), about e^-1 = 37% whatever h (25% of the val/test cells at D83's share, T-F5); a flight that hides no antenna is, under the shadowing build, exactly the clean link, so skipping it loses no physics (the 'none' class has its own sub-runs) and no bias enters the labelled frames (the same conditional population of flights that hide an antenna).
- `shadow_hit_share.m` recomputed per level, over the dataset's draws (an Eb/N0 of the grid sets the GCS's distance and elevation), any frame of the 20-frame sub-run.

**Sources.** Sun et al., Part IV, IEEE TVT 66(9), 2017: Sec. III (criteria), Table II (fit, rolls 16.1-58.3 deg), Fig. 13 (median losses), Sec. IV-A (C-band 5 dB above L-band). Khawaja et al. 2019 (8 m/s). Polle et al. (wind tilt of a hovering multirotor).

**Result (4000 flights per level, `shadow_hit_share.m`).** Share of flights hiding an antenna: 6 dB 5.6%, 8 dB 10.8%, 9 dB 13.1%, 10 dB 15.3%, 12 dB 19.8%, 13.75 dB 23.9%, 15-21 dB 24.7%, 22.5 dB 21.1%, 23 dB 19.7%, 25 dB 14.3% (D83: 74.2% at every level). The same draws under D83's criteria give 73.7%; with the cz < 0 geometry 32.0% (the reviewer's figure); with the speed floor 28.1%; with the roll band the table above.

**Tests.** `test_shadow_attitude` (rewritten): the bands of 6, 15.5 and 25 dB and a level no roll supports; banking toward the GCS hides the aft end abeam and ahead of the beam, the front end behind it; banking away, a GCS 25 deg below under a 20 deg bank, a roll below 16.1 deg or outside the band, and 7 m/s hide none; `flight_draws.m` d.hidden equals `shadow_hidden.m` at every frame start of 200 flights; a slow flight hides none; the share at 15.5 dB in 0.15-0.35, smaller at 6 dB; the dataset's selection; the fixed view at 28.5 deg with its coordinated turn, none at hover. `test_receiver_measurements` (the model hides the aft / aft / front end with the GCS abeam / ahead / behind, none in level flight) unchanged and passing.

## A3. The in-band cap on every antenna over the run (S-2, T-F7, L-F4)

**Why.** The cap (no emitter above 30 dB over our signal, Liu et al.; D74, D75 item 24) took our signal at the 'GCS' block and the weakest airframe amplitude only: the hidden antenna of airframe shadowing then saw level + depth (jamming + shadowing high 23 + 20 = 43 dB; with path loss 50 dB; 55 dB at the top), and the per-frame attitude term was not in it. Its path-loss term acted on every frame while the step starts at its onset, so the level recorded for a frame was not the level on the air (L-F4).

**Decision.** An emitter's power is fixed for the run (it does not know our attitude or an obstruction); the cap fixes it at the level that stays within 30 dB of our signal on every antenna at every frame of the run, as the path-loss step was already included: `flight_draws.m` computes d.cap_amp, our signal's weakest-antenna amplitude over `p.cap_frames` frames (`sig_weak_db.m`: the 'GCS' amplitude, the airframe loss, the attitude's gain toward the GCS on the LoS at each frame, the diffuse part at the flight's K, and the shadowing depth and K on the hidden antenna when the threat has shadowing and the flight hides one); `link_seed.m` sets it into a new Constant block 'Cap'; the Threat block scales each component by min(1, inband_cap_amp(L, PL, 30) x Cap). Per frame the level each component reaches over our signal on the weakest antenna, the path loss counted from its onset, is recorded (Threat output 3, `extract_closed_loop_frames.m` lev_db; dataset lev_db). `p.cap_frames` = 20 (the dataset's and the pools' runs; the survivability map sets its 57, the gallery its 40). The attitude term is small on moving flights (a run's worst frame 0.0 dB median, 0.14 dB p95, 0.8 dB at most below the flight-start value; hover 0.1 / 0.4 / 0.8 dB, 4000 flights); the depth is the term that mattered.

**Sources.** Liu et al. (30 dB, as D74/D75); Sun et al. (depth and K -16 dB on the hidden antenna).

**Tests.** `test_inband_cap_run`: a 23 dB jammer on a flight hiding an antenna by 20 dB reaches 30 dB (+-1.5) over our signal on the hidden antenna and 10 dB (+-2) on the others, measured from the received powers of the jammer alone ('GCS' 0) and our signal alone; the cap's reference holds the depth (more than 19 dB below the 'GCS' amplitude); the recorded level stays at or below 30 dB in every frame, above 29 dB at the hidden frames. `test_inband_cap` updated: the Threat code scales by the 'Cap' block; the reference never exceeds the 'GCS' amplitude times the weakest airframe amplitude; the model's 30 dB jammer against a 22 dB path loss still reaches 30, not 52 dB.

## A4. A combination is on the air while any of its components is (T-F2)

**Why.** In a combination the last gated component overwrote the frame's on-air share (act): spoofing + sweeping jammer was "off" in the frames the sweeper missed (10.7% of the runs entirely: those geometries dropped although the spoofer was always on; DET read on about 13% of the frames), benign interference + noise burst and jamming + spoofing + benign interference lost their no-packet frames; with airframe shadowing, nothing told the flights that hid no antenna from those that did (about a quarter of the shadowing combinations' geometries hid none). The union keeps such a flight a flight of the combination (its additive component is on the air), and act_comp tells which components are.

**Decision.** `build_threat_model.m`: per frame every component's share on the air, actc, in the threat's order (path loss 0/1 from its onset, antenna fault 1, shadowing 0/1 while an antenna is hidden, the WLAN and the sweeper their shares, every other additive component 1); output 2 is their union: 1 while a component that is not gated is on the air, else the largest gated share; output 3 [actc levc]. `threat_active.m`: a combination with a gated component counts by the gated 10% rule (its union is 1 while a non-gated component is on). The per-component vector is kept for analysis: dataset act_comp (frames x 3), pools act_comp (pool_cell.m), frames F.act_comp.

**Tests.** `test_combination_on_air`: spoofing + sweeping jammer with a sweep that misses some frames is on the air in every frame, the sweeper's own share per component exact, the third slot NaN, the levels finite; the labels of gated combinations. `test_threat_on_air` (K.on) unchanged and passing.

## A5. The path-loss label window and the received Eb/N0 (D-F5, T-F3, interface with group B)

**Why.** A path-loss frame was labelled while pos - t0 < TW: at offset 9 the frame's 10-frame causal window holds no frame before the step, so the step is invisible there (var_rssi, dlog_ber, plr). After the window the frames are clean frames at the configured Eb/N0 although the received Eb/N0 is up to 22 dB lower.

**Decision.** `threat_active.m`: pos - t0 < TW - 1 (9 labelled frames per sub-run); `run_dataset_sweep.m`: path-loss cells fly round(N_SUB F_SUB / (TW - 1)) = 13 sub-runs. The received Eb/N0 of every frame, `received_ebno.m` (the configured value less the path-loss step on the frames where its component is on the air), is stored as **ebno_rx** in: the dataset (`run_dataset_sweep.m`, the FRESH_TEST set too), the spectrograms (`extract_spectrograms.m`), the splits (`prepare_data.m`: train/val/test, and splits_fresh.mat's test), the detector blocks (`detector_block.m`, fourth output) and the pools (`pool_cell.m`: Q.ebno_rx, the configuration's Eb/N0 gain and the relay loss included: the Eb/N0 per information bit of the frame as the Level block sets it, less the step).

**Tests.** `test_path_loss_onset` (window [0 0 1 1 0 0 0] at TW 3 and 9 frames at TW 10; act_comp and the received Eb/N0 15 - 14 dB from the onset in the model), `test_received_ebno` (the function; ebno_rx in the dataset, spectrograms, splits, splits_fresh and pools; detector_block's four outputs), `test_dataset_balance` (13 sub-runs).

## A6. Class balance: the WLAN's labelled share, extra sub-runs over every fold (T-F5)

**Why.** The WLAN counts only in frames with a packet on 10% of the frame or more (58.5% of its frames, reviewer): 562 against about 960 labelled frames per Eb/N0 for the other threats. Extra sub-runs (sweeper 46, shadowing 8 per cell) went to folds 1-2 (FOLD = mod(k - 1, N_SUB) + 1 per cell), the training folds.

**Decision.** `benign_hit_share.m` measures the labelled share from the threat block's packet schedule (3000 runs of 20 frames: 0.574); WLAN cells fly round(N_SUB / share) = 10 sub-runs. The fold counter runs over all the cells of a threat (FOLD(nk)), so every fold holds the same share of the extra sub-runs (path loss: 104 per fold over 48 cells, every cell in every fold; WLAN 80; sweeper 368). Shadowing flies one hiding flight per fold (A2). The threat block's WLAN schedule now starts on with the occupancy's probability (it started with the complementary one: its first switch at t = 0 flipped the initial draw), the same number of draws.

**Tests.** `test_dataset_balance` (share 0.5-0.65, 10 sub-runs, the fold rotation giving 104 per fold), `test_slot_and_burst_measurements` unchanged.

## A7. Noise bursts as a sourced random jammer (T-F6)

**Why.** Duty 0.3 and period 100 symbols had no source.

**Decision.** The noise burst is a sourced random jammer; the slot is one symbol (Marti et al.'s time slot carries one symbol). Per flight the regime is drawn (`jam_timing.m`, fourth draw of the 'jam' stream, the first three unchanged): Marti et al.'s J4 at 20% (one-symbol slots, each jammed with probability 0.2), or Xu et al.'s random jammer with the duty a uniform in [0.5, 0.775] (bursts U[0, 31] symbols, sleeps U[0, 31 (1 - a) / a] <= 31 symbols); half the flights each (D86 item 12). a = 0.5 is Xu et al.'s first random jammer (tj, ts = U[0, 31]) exactly, a = 0.775 its second's mean duty (ts = U[1, 8], mean 4.5 slots). The bursts start on when the third draw is below a, the first switch drawn inside that first burst or sleep, so the samples before the frame (the delay line's early taps) carry the same state. Fixed geometries: a = 0.5. `p.burst_duty`/`p.burst_period` replaced by `p.burst_duty_range`, `p.burst_on_sym`, `p.burst_duty` (fixed), and `p.burst_j4` (J4's duty and the share of flights).

**Sources.** Xu et al. 2005, Sec. 2 (random jammer) and Table 1 (tj = U[0,31], ts = U[0,31] or U[1,8]); Marti et al. 2023 (Mitigating Smart Jammers in MU-MIMO), Sec. VII-A (J4) and Fig. 5(d): random unit-symbol bursts, duty 20%.

**Tests.** `test_jam_timing` (four draws, half J4 at 0.2 and the rest uniform in 0.5-0.775, the fixed duty 0.5), `test_noise_burst_duty` (the duty at 0.2, 0.5 and 0.775; at 0.2 runs of 1.25 symbols and almost no jam-free 32-symbol window; at 0.5 bursts of 15.5 symbols), `test_gated_jammers` (the bursts start on or off with the flight's draws), `test_draws_independent` (the duty's uniform among the flight's draws).

## A8. Delay spread of high flights and its clip (S-3, S-3b)

**Why.** From 25 m up our signal took the omni fit of environment II (-6.63, 0.16; median 234 ns), although the code's own rule is "the larger of the omni and directional fits" and Table VII's directional fit at 75/90/105 m is larger (-6.43, 0.26; 372 ns). The clip at 1 us cited the top of Fig. 7a (an axis end, environment I omni).

**Decision.** `delay_spread.m`: three height bands, the lower edges `p.tdl_sig_alt_m` = [25 75] m (Table VII's rows): below 25 m directional OLoS (-6.52, 0.32), 25-75 m omni (-6.63, 0.16; the directional fit is smaller there), from 75 m directional (-6.43, 0.26). The clip `p.tdl_clip_ns` = 2250 ns: half the 4.5 us delay range of the measured power delay profile of environment II (Fig. 6a), the largest RMS spread any profile confined to that range can have (two equal paths at its ends: a physics bound, not a measured spread). The delay line itself holds at most its flat profile (1.54 us at K -5 dB, 1.39 us at 2 dB, 0.77 us at 10 dB, `tdl_profile.m`). The real receiver's space-time taps were tied to the clip (`rx_taps.m`, +-2 RMS spreads at the clip): raising the clip would have doubled them (19 per antenna, D77 found longer spans worse); they now follow the receiver's own design spread `p.rx_span_ns` = 1 us (9 taps, unchanged), whatever the channel draws.

**Result (20 000 dataset flights).** Our signal: median 291 ns (D83 243), p90 1216 ns (831); drawn above 1 us 13.4% (D83: 7.2%, clipped there), 20.6% of the flights at 75 m and above; above 1 us as the line holds it 6.3%, the largest 1542 ns; at the clip 3.8%. Interferers: above 1 us 5.9%, at the clip 0.7%.

**V12c.** A column at the clip (2250 ns) for the clean rows whose K lets the line go beyond 1 us (K -5 and 2 dB); the jammer rows' channel (K 10 dB) holds its flat profile (767 ns) from 1 us on, so their 1 us column stands for every larger spread. Results below.

**Tests.** `test_delay_spread` (the three bands' medians and spreads, the clip at half the delay range, the share at the clip and above 1 us of the top band), `test_rx_taps` (the receiver's taps from `p.rx_span_ns`, unchanged by the clip).

## A9. The receiver's level calibration (L-F7)

**Why.** The receiver reported absolute levels and compared them with its thermal-floor constant perfectly.

**Decision.** Per flight and antenna a calibration error uniform within +-2 dB (`flight_draws.m` d.cal_db, its own seed stream 'cal', offset 13; `link_seed.m` sets a new Constant block 'Cal', logged to 'Cal_db'). `extract_closed_loop_frames.m` applies it to every level the receiver reports against its floor: the received samples behind rssi, iot, q_iot, duty, edges and the detector image (iq), and the channel gains behind gain_ant and branch_gap. Ratios within a chain (sinr, env_corr, q_react, coh, q_sfm, q_par, est_margin, branch_dip) do not change; the combiner and its predictions (mmse_gain, align) work on the samples as they are (a gain after the noise scales signal and noise of a chain alike). Uniform within the bound: the data sheet gives the bound only.

**Sources.** AD9361 data sheet Rev. F, Table 1 (p. 3): RSSI range 100 dB, accuracy +-2 dB.

**Tests.** `test_level_calibration` (the draw and its stream, within +-2 dB; between the same flight with and without the error: RSSI and IoT move by the reference antenna's error, the antenna gains by each one's, SINR, q_react and the bits not). `test_seed_streams_disjoint` and `test_draws_independent` extended. The tests of the measurement design (`test_fixed_noise_floor`, `test_path_loss_onset`, `test_receiver_measurements`, `test_slot_and_burst_measurements`) run without the error.

## A10. Our LoS Doppler from the GCS direction (L-F8)

**Why.** Our LoS Doppler was fd cos(2 pi rand), drawn apart from the GCS direction (`gcs_aoa.m`) used for the steering vector, the attitude gain and shadowing: inconsistent (mostly absorbed by the frequency estimate).

**Decision.** The channel block takes fd cos(elevation) sin(direction + heading rate x t) at every frame (the UAV flies along its heading; 90 deg the GCS ahead), as each interferer takes fd sin(aoa + heading change), its line-of-sight phase integrated over the turn (`los_phase.m`; the threat block, `idle_rssi.m` and `emitter_idle.m`; D86 item 4). The per-flight draw is gone (the channel's later draws shift: every realization changes, so validate_phy's real-receiver rows are new realizations).

**Tests.** `test_los_doppler`: no oscillator offset, LoS only: the receiver finds +fd (358 Hz) with the GCS ahead, -fd behind and 0 abeam, within 40 Hz.

**Consequence.** V12c's fixed geometry (the GCS at broadside) now has no LoS Doppler, and its clean K -5 dB row floors at 1 us (Results: diagnosed to the zero LoS Doppler, a receiver issue).

## A11. Path-loss top level and the altitude band on library sources (S-4, T-F6)

**Why.** The 22 dB top level and the 0-11 m below-roofline band cited Cui et al. 2019, not in the library (and its 21.9 dB is a model intercept at 0 m).

**Decision.** Re-anchored on Simunek et al. 2011 (now in the library): a 2 GHz UAV link at 1.6-6.5 deg elevation to a GCS at street level behind the last building loses 33-42 dB over free space (4000-wavelength means, Figs. 6 and 11; raw down to about 28 dB), modelled by knife-edge diffraction (eqs. 6-8: 20 log10(v / 0.225) dB for v > 2.5). The levels up to 22 dB (an edge v = 2.8 into the line of sight) are obstructions below it: kept. The altitude's top is 120 m within Khawaja et al.'s 122 m (FAA ceiling); the bottom 15 m is Rodriguez-Pineiro et al.'s lowest full table; the 0-11 m band is dropped. `init_params.m`, `dataset_levels.m`, `decision_config.m`, `link_budget_table.m`, README.

**Stated.** Simunek et al. measured more than 22 dB: raising the top level toward the measured 33-42 dB is a change of the dataset and decision levels, of the overhead-pass rule ("a drop above 22 dB is beyond the measured levels") and of the edge map, not made here (open for the main session; a link 33 dB down is lost at every grid Eb/N0).

## A12. Antenna-fault levels: Heath's wording (S-5, T-F4)

**Decision.** Levels 5-31 dB kept: the gap-capacitance estimate (an open connector couples through 0.01-0.03 pF, |S21| = 2 w C Z0 between 50-ohm ports: 26-36 dB at 2.4 GHz) is a stated physics derivation. Heath's Table 2 (cols. 41-42) worded as it reads: a severely degraded antenna connection shows as one branch weaker than the other with a diversity-imbalance indicator (and a high VSWR alarm); the table's imbalance indicator fires at a branch difference above 5 dB (|val1 - val2| > 5 dB, in its external interference and PIM rows). `init_params.m`, `dataset_levels.m`, `temporal_evidence.m`. Fedde & Carter and Ginart et al. (not in the library) dropped.

**T-F4 (stated):** the 5 dB fault lies within the airframe's own spread between antennas (Badi et al.'s body loss: the weakest antenna's offset from the others' median 4.9 dB at p90, 7.1 dB at p99 on clean flights; 49% of 5 dB fault flights below the clean p90): at 5 dB the fault and the airframe are the same physics; kept, reported per level.

## A13. Wording and citations (L-F10, S-6 to S-11)

- Receive correlation floor 0.3 (D73: no source): Badi et al. 2019, Sec. 4.3, Fig. 7(c): envelope correlations 0.2-0.62 between two drone-mounted antennas 2/3 wavelength apart (ours 3.2-9.6 wavelengths); the range 0.3-0.9 lies within 0.2 (Badi) and 0.99 (Sun). `init_params.m`.
- Willgert, Table 1: its threshold of std / |average| is written "<3 dB" / ">3 dB" (a ratio given in dB), read as 3; the code said "ratio below 3" as if stated. `temporal_evidence.m`, `init_params.m`.
- Sun et al.: "events up to about 25 dB" replaced: medians to about 27.5 dB at C-band (Fig. 13), the largest loss over 35 dB (abstract), 47 dB at L-band.
- 57.9 deg (Gross et al., Fig. 4) and 28.7 deg/s (Allen & Lin, Fig. 12) marked as digitised; Allen & Lin's is the body yaw rate r, the heading rate of the same turn r / cos(bank) is larger, so capping the heading rate at r keeps every turn within the measured one. `init_params.m`.
- Sweep periods 20-83.5 ms: 20 ms is Liu et al.'s 20 MHz band at their 1 GHz/s; up to 83.5 ms is a derivation (their rate over the whole 2.4 GHz band, ETSI EN 300 328), not a band they swept. `init_params.m`, `jam_timing.m`.
- Badi et al. 2019's 30 dB is the RSS change of a drone-to-drone link with the elevation angle (Sec. 4.2), not a single antenna's gain below the drone: reworded as the floor of the dipole's null. `uav_dipole_db.m`, `init_params.m`, `overhead_pass.m`.
- Not in the library, removed from the code: Boeing US 8,503,941 (the tracker's omni fallback is now an assumed fallback, 12 - 2 = 10 dB), Fedde & Carter US 4,506,385 and Ginart et al. (connector faults), the Israeli ministry's 100 mW rule (the cap is ETSI EN 300 328's: 20 dBm e.i.r.p., 4.3.2.2.3, and 10 dBm/MHz, 4.3.2.3.3), Cui et al. (A11). Winters US 6,147,985 appears only in D73 (DECISIONS): the D84 entry should mark it as not in the library. Gomez-Ponce et al. (now in the library): hovering LoS power std 0.48 dB against 0.08 dB static (Sec. IV-B). `init_params.m`, `gcs_antenna_analysis.m`, `link_budget_table.m`.

**Tests.** `test_citations_in_library`: no code file outside legacy cites Cui et al., Boeing, Fedde, Ginart, the ministry or Winters' patent; init_params states Heath's indicator and Simunek et al.

## A14. Shadowing and obstruction scale the LoS and the diffuse part alike (L-F5, L-F6): stated assumption

The airframe-shadowing depth scales our signal's LoS and diffuse part on the hidden antenna alike (with its K set to -16 dB, Sun's Fig. 12), and a path-loss step scales our whole signal keeping its K. Physically a blocked LoS would leave part of the diffuse power (Sun's 15 dB depth with K 15 dB outside the event is a blocked LoS), and an obstruction lowers K. Both are kept as stated assumptions: the depth is the measured median loss of the event (Sun et al.), which already holds whatever the diffuse part kept, and the step is the measured excess loss of the path (Simunek et al.), not split into LoS and diffuse parts by any source.

---

## The interface with group B: ebno_rx

Field name **ebno_rx**, per frame, [dB]: `dataset.ebno_rx` (data/dataset.mat and data/dataset_fresh.mat), `spec.ebno_rx` (spectrograms*.mat), `splits.train/val/test.ebno_rx` (data/splits.mat) and `splits.test.ebno_rx` (data/splits_fresh.mat), the fourth output of `detector_block.m`, and `Q.ebno_rx` in every pool cell (pool_cell.m). Definition: `received_ebno.m`, the configured Eb/N0 less the path-loss step on the frames where it is on the air (in the pools also the configuration's Eb/N0 gain and the relay experiment's loss). It does not include the per-flight pointing, attitude and airframe losses, which are part of a flight at that Eb/N0 as before.

## Results

### Unit tests
`code/tests/test_core.m`: 92 tests (83 of D83, 9 new: test_reactive_trigger, test_inband_cap_run, test_combination_on_air, test_received_ebno, test_dataset_balance, test_noise_burst_duty, test_level_calibration, test_los_doppler, test_citations_in_library; rewritten or extended: test_shadow_attitude, test_path_loss_onset, test_delay_spread, test_rx_taps, test_jam_timing, test_gated_jammers, test_inband_cap, test_seed_streams_disjoint, test_draws_independent, and the calibration switched off where a test checks the measurement design against an exact floor): all pass, 17.9 min (commit 369d9eb, scratch copy). The tests touched by the two later fixes (af6431d, 9cc37df) rerun and pass.

### validate_phy (scratch copy of 369d9eb, one process: 'flat' 73 min, then 'V12c' 272 min; the later commits change no path it runs)
Flat checks against D83:

| check | D84 | D83 |
|---|---|---|
| V1-V7 gap to theory [dB] | +0.03 / +0.01 / +0.08 / +0.06 / +0.13 / +0.14 / +0.07, all PASS | the same, BER identical to the last digit (the ideal receiver's draws are unchanged) |
| V8a / V8b | 2.77e-1 ... 2.67e-1 / 2.32e-2 ... 9.99e-6 | the same |
| V9, V10 (tone 16.24 vs 16.23 dB) | PASS, PASS | PASS, PASS |
| V11 real-receiver loss V1 / V5 / V8b [dB] | +0.91 / +0.98 / +4.92 | +0.95 / +1.01 / +4.96 |
| V12 specular 0.8 at 80 ns (480 ns informational) | +0.49 dB (NaN: error floor) | the same |

V11 moves by a few hundredths of a dB: the channel no longer draws a LoS Doppler cosine per flight (A10), so the real receiver's flights are new realizations, and the fixed geometry's GCS at broadside now has no LoS Doppler.

V12c, shift of the delay line against the flat channel [dB] at 64 / 138 / 234 / 302 / 372 / 1000 / 2250 ns (D83 below each row; the 2250 ns column only where the line's K lets it pass 1 us):

| case | D84 | D83 | limit | verdict |
|---|---|---|---|---|
| clean K -5 dB, MRC | -0.05 / -0.05 / -0.00 / +0.00 / +0.00 / **+6.19** / **+11.44** | +0.25 / +0.01 / -0.21 / -0.16 / -0.15 / +0.00 | 0.5 | **FAIL from 1 us** (new) |
| clean K 2 dB, MRC | -0.17 / -0.23 / -0.23 / -0.21 / -0.20 / -0.07 / -0.03 | -0.19 / -0.24 / -0.24 / -0.25 / -0.26 / -0.17 | 0.5 | PASS |
| clean K 10 dB, MRC | -0.16 / -0.17 / -0.17 / -0.16 / -0.16 / -0.14 | -0.15 / -0.16 / -0.16 / -0.15 / -0.14 / -0.10 | 0.5 | PASS |
| jam 16 dB, rho 0.3, MMSE | -1.01 / -0.87 / -0.71 / -0.50 / -0.22 / +1.82 | -1.07 / -0.91 / -0.69 / -0.48 / -0.24 / +1.40 | 3 | PASS |
| jam 16 dB, rho 0.9, MMSE | -1.20 / -1.13 / -0.99 / -0.90 / -0.76 / +0.00 | -1.28 / -1.23 / -1.19 / -1.03 / -0.88 / +0.00 | 3 | PASS |
| jam 30 dB, rho 0.3, MMSE | -0.30 / +0.00 / +0.00 / +0.92 / +2.18 / +14.08 | -0.16 / +0.00 / +0.00 / +1.36 / +2.56 / +14.21 | 3 | FAIL at 1 us (as before) |
| jam 30 dB, rho 0.9, MMSE | -3.00 / -2.53 / -1.73 / -0.88 / +0.00 / +3.00 | -3.31 / -2.79 / -1.96 / -1.07 / -0.18 / +3.00 | 3 | PASS (at the limit, as before) |
| jam 16 dB, rho 0.3 / 0.9, 358 Hz, 234 ns (informational) | -0.25 / -0.91 | -0.04 / -0.82 | - | - |

Verdicts (results/phy_validation_v12c.txt of the scratch copy, 272 min): channel model: the flat channel fails, the link runs the delay line -> PASS; receiver on the delay line: FAIL (above the limit: clean K -5 dB, MRC; jam 30 dB, rho 0.3, MMSE). validate_phy('flat'): every check PASS (73 min).

**The clean K -5 dB row (diagnosed, scratch `diag_v12c.m`).** At 1 us the D84 curve floors at 15 dB (BER 5.5e-4, D83 1.3e-5), from one flight of the 20 (BER 1.1e-2 at 15 dB; the other 19 at most 6e-5). Flown on D83's channel draws, the row gives 1.3e-5 at 15 dB with D83's random LoS Doppler and 1.2e-3 with the LoS Doppler at zero (four of 20 flights between 1e-3 and 1e-2): the floor comes from the zero LoS Doppler that V12c's fixed geometry now has (the GCS at broadside, A10: fd cos(el) sin(0) = 0), not from the new delay-spread fit. So the real receiver on the delay line has an error floor on some flights whose LoS has no Doppler shift relative to the diffuse part, at K -5 dB and 1 us; D83's per-flight random LoS Doppler (inconsistent with the geometry) hid it from V12c. In the link the GCS direction is drawn per flight, so |sin(direction)| < 0.1 on about 6% of the flights, the same share as before A10 (the old cosine had the same arcsine law): the dataset and the pools are no worse off, but the case is now visible. The channel-model verdict is unchanged (the flat channel fails, the link runs the line: PASS); the receiver verdict on the line was already FAIL (30 dB, rho 0.3, 1 us) and now names this row too. Not changed here: the receiver (D77) is outside group A; open for the main session.

### Smoke chain (scratch copy of af6431d, from an empty data/)
`run_stage('smoke', 'A0', 'A5', 'A6', 'B1', 'B2', 'B2F', 'B3n', 'B3', 'B4', 'B4s', 'C1p', 'C1c')`: exit 0, every stage, 229.3 min (A5 6.4, B3n 2.6, C1p 192.4, C1c 22.5 min). The first launch stopped at A5's save: `exist('data', 'dir')` found a folder of that name elsewhere on the MATLAB path and data/ was never made; fixed with `isfolder` (af6431d), relaunched from A0. Checks on its outputs (`smoke_check.m`):
- dataset: ebno_rx, act_comp, lev_db and cal_db present, jam 4 columns; ebno_rx below the configured value on 77% of the path-loss sub-runs' frames, by the steps of the smoke levels (4 and 22 dB); calibration errors -2.00..2.00 dB; the largest level recorded over the weakest antenna 30.02 dB (the cap took a frame's end one sample later than the record; aligned in 9cc37df, so the two now take the same samples).
- labelled frames per fold: every threat 84 per fold, path loss 36, airframe shadowing 81-84 (hiding flights: level 6 dB 12 of 234 flights tried, 5.1%; 25 dB 12 of 71, 16.9%), WLAN 40-56, sweeper 10-16, none 234-247.
- second test set: 1848 frames, all in fold 6, ebno_rx present; spectrograms and spectrograms_fresh carry ebno_rx; splits train/val/test (3696/924/924) and splits_fresh test (1848) carry ebno_rx.
- pools: ebno_rx and act_comp in all 7488 pool cells; the path-loss cell's ebno_rx is the configured value less its level (3 - 6 = -3 dB); the airframe-shadowing cells hide no antenna in the smoke's two train geometries (the open risk below).
- No warning in the log. Smoke numbers are not results (B3's KPI 1 threshold is NaN on the smoke's two Eb/N0 points).

## Not backed by a source, stated

- The C-band fit for 2.4 GHz (the more severe measured band) and the two-sided 1.96 sigma band pairing a level with the roll.
- No shadowing below 8 m/s (no source covers a hovering multirotor).
- The reactive jammer's energy detector threshold (`p.reactive_threshold`, unchanged) and its detector time taken as zero.
- The noise bursts' slot as one symbol, the duty uniform between Xu et al.'s values, the sleep law that gives the duty, half the flights J4.
- The delay-spread clip as a physics bound from the measured profile's range.
- The calibration error uniform within the data sheet's bound, independent per antenna.
- A14's assumptions.

## Open risks

- The pools fly shared geometries for every cell (common random numbers, D74), so a shadowing cell is on the air only in the flights whose attitude hides an antenna at its level: 5.6-24.7% of them (D83 74%), about 4-18 of a point's 72 flights. The shadowing points of the edge map will mostly stay UNDETERMINED (n below 36) unless the pools select hiding geometries for the shadowing cells (as A5's dataset does) with a clean reference of the same geometry. Not changed here (decision layer and pools: main session / group C).
- eval_unseen_snr.m and eval_unseen_severity.m (B4, B4s) draw their block seeds without the selection: their shadowing blocks hide an antenna in about a fifth of the cases, so their shadowing readings thin out.
- A5 flies more sub-runs: path loss 13 per cell (12), WLAN 10 (6), shadowing 6 hiding flights (8 flown); the selection itself costs no simulation.
- About 6% of our signal's flights now run the delay line above 1 us (up to 1.54 us), beyond the receiver's 1 us design spread, where V12c's 30 dB rho 0.3 row already fails at 1 us: those flights' commitment rests on their measured outcome.
- The real receiver on the delay line floors on some flights whose LoS has no Doppler shift (the GCS abeam) at K -5 dB and 1 us (V12c's clean K -5 dB row, diagnosed above): a receiver issue (D77's synchronization or estimation on the line), visible now that the LoS Doppler follows the geometry. About 6% of the link's flights have |sin(direction)| < 0.1, as before A10; to be investigated on the receiver side.
- The in-band cap now holds at the worst frame of a 20-frame run (p.cap_frames); the edge map's episodes replay a pool run's 20 frames, so the cap holds there; a stage that flies longer runs sets p.cap_frames (the survivability map 57, the gallery 40).
