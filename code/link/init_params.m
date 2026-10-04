%% UAV-GCS Adaptive Secure Communications System - Parameters
% Central parameter file. Run this FIRST — it saves params.mat that all
% other scripts load.
% Author: Adi Suliman, Bar Dvir Hassan
% Created: 2026-09-01
close all; clc;

%% ========== MODULATION & TRANSMISSION ==========
params.mod_type            = 'QPSK';   % modulation scheme
params.mod_order           = 4;        % QPSK -> 4
params.symbol_rate         = 1e6;      % 1 Msym/s
params.samples_per_symbol  = 4;        % oversampling (spectrogram of the detector)
params.sps                 = params.samples_per_symbol;
%% ========== FRAME STRUCTURE ==========
params.bits_per_frame = 1000;          % payload bits per frame
params.crc_bits       = 32;            % CRC-32 per frame: packet check at the receiver
params.frame_length   = params.bits_per_frame + params.crc_bits;  % total bits/frame
% Quiet slot: the GCS is silent right before every frame (the gap between command
% packets). The UAV measures the channel without our signal there, just before it
% has to find the frame: interference alone, as in jammer detection on unused pilots
% (Pirayesh & Zeng); a reactive jammer, which transmits only while it senses our
% signal, is silent there (Xu et al.; Sagduyu et al.). A guard after the frame
% (frame_layout.m) keeps the filter tails out of the next quiet slot.
params.quiet_symbols  = 32;            % [symbols] silent slot before each frame
params.cycle_s        = 0.02;          % [s] decision cycle: channel time between consecutive frames
% Training and pilots (frame_layout.m), as the 802.11 frame (Pirayesh & Zeng): ten identical
% short symbols (frame detection, coarse frequency), two identical long ones (timing, fine
% frequency, channel), pilots for channel and phase tracking (802.11: 4 per 52 subcarriers).
params.stf_len        = 4;             % [symbols] short training sequence: frequency offsets within +-125 kHz
params.stf_rep        = 10;
params.ltf_len        = 16;            % [symbols] long training sequence
params.ltf_rep        = 2;
params.pilot_block    = 4;             % [symbols] pilot block ...
params.pilot_every    = 48;            % ... after every 48 data symbols
% Receiver: 'real' finds every frame in time and frequency from its training and estimates
% the channel from training and pilots; 'ideal' knows the timing, the frequency and every
% transmitted symbol (the reference of validate_phy.m).
params.rx_sync        = 'real';
params.cfo_ppm        = 25;            % [ppm] oscillator tolerance of each radio at 2.4 GHz (IEEE 802.11)
params.timing_max_sym = 4;             % [symbols] unknown arrival time of a frame (uniform, fractional)
params.rx_dd_iter     = 4;             % decision-directed estimation passes after the pilot-based one
%% ========== CHANNEL MODEL ==========
% Pulse shaping (RRC)
params.rolloff      = 0.25;            % RRC roll-off factor
params.filter_span  = 10;              % RRC filter span (symbols)
params.rician_k      = 10;             % K-factor (dB) when not drawn per flight (PHY validation)
params.k_random      = true;           % K-factor of every channel drawn per seeded flight (channel_k.m)
params.k_range_db    = [-5 20];        % measured air-ground K: foliage 2-5, airports -5..10 (5.75 GHz, Tu & Shimamoto), open L-band ~12, C-band ~28 dB (Khawaja et al.)
params.carrier_freq  = 2.4e9;          % 2.4 GHz ISM (range for a given Eb/N0: link_budget_table.m)
% Delay spread: measured at 2.5 GHz from the ground to a UAV at 15-105 m, median RMS delay
% spread 120-302 ns, log-normal, 90th percentiles up to 1.6 us (Rodriguez-Pineiro et al.,
% Table VII); 64-90 ns in rural flight (Lyu et al.). The tapped delay line
% (build_threat_model.m) puts the diffuse part of our signal and of every interferer on
% taps 250 ns apart (one sample) up to 4.5 us, the delay range of their measured power
% delay profile (Fig. 6a), with an exponential profile matched to each channel's spread at
% its K (tdl_profile.m). The flat channel fails the V12c check (validate_phy.m), so every
% flight runs the delay line, the spreads drawn per flight.
params.tdl           = true;           % tapped delay line on every channel (false: flat fading)
params.tdl_random    = true;           % RMS delay spreads drawn per seeded flight (delay_spread.m)
params.tdl_ds_ns     = [234 234];      % [ns] fixed spread of our signal and of every interferer (environment II omni median)
params.tdl_step_ns   = 250;            % [ns] tap spacing
params.tdl_max_ns    = 4500;           % [ns] last tap
params.tdl_sig_ds    = [-6.52 0.32; -6.63 0.16];   % our signal, log10 s (mean, variance): env. II directional OLoS below tdl_sig_alt_m, omni above
params.tdl_sig_alt_m = 25;             % [m]
params.tdl_int_ds    = [-6.63 0.16];   % every interferer, log10 s: env. II omni
params.tdl_clip_ns   = 1000;           % [ns] top of their Fig. 7a

% UAV platform velocity and Doppler
% Platform: mini UAV (Tlili et al.: 5-25 kg, 0.5-2 m). Speed envelope 0-161 km/h:
% from a hovering rotorcraft (measured while hovering, Khawaja et al.; the channel
% then hardly changes, Gomez-Ponce et al.) to the small-UAV limit of 161 km/h quoted
% by Khawaja et al. -> Doppler 0-358 Hz @ 2.4 GHz.
% Speed is a CONTINUOUS parameter (any real value inside the envelope, not only
% whole km/h). The dataset generator draws a random real-valued speed per block
% of frames; the GUI accepts decimals. fd_max = v * fc / c.
% v_nominal (20 m/s = 72 km/h -> fd = 160 Hz) is the default cruise speed used by
% every script that does not draw a speed per seeded run.
params.speed_kmh_min = 0;                        % [km/h] envelope lower bound (hover)
params.speed_kmh_max = 161;                      % [km/h] envelope upper bound
params.v_min     = params.speed_kmh_min/3.6;     % [m/s]
params.v_max     = params.speed_kmh_max/3.6;     % [m/s]
params.v_nominal = 20;      % [m/s] nominal cruise (72 km/h) — default simulation Doppler
params.c_light   = 3e8;     % [m/s] speed of light
params.fd_max    = params.v_nominal * params.carrier_freq / params.c_light;  % [Hz] ~160 @ 20 m/s
% Manoeuvres: the heading turns during a flight (heading_rate.m), so the directions of
% the GCS and of every interferer rotate across the antenna array: a coordinated turn
% at up to the largest bank angle measured on a small UAV (57.9 deg, Gross et al.),
% turn rate g tan(bank) / v with v not below the slowest measured UAV (8 m/s, Khawaja
% et al.), and never above the largest measured yaw rate of a small UAV (28.7 deg/s
% while circling, Allen & Lin).
params.yaw_random    = true;                     % heading rate drawn per seeded sub-run
params.roll_max_deg  = 57.9;                     % [deg] largest measured bank angle of a small UAV
params.turn_v_floor  = 8;                        % [m/s] speed floor of the turn-rate formula
params.yaw_rate_max  = 28.7;                     % [deg/s] largest measured yaw rate of a small UAV
% The turn banks the UAV by atan(w v / g) (bank_angle.m): its antennas tilt and their
% polarization turns against the GCS antenna (uav_attitude_db.m), on our signal only.
% Wind (hover_attitude.m): below the slowest measured flying UAV a multirotor holds its
% position by tilting (30 s means: roll -17.5..19.3 deg, pitch -11.0..14.9 deg, DJI Air 3S
% in 0.8-7.6 m/s wind, Polle et al.) and its attitude jitters (within 1 deg in calm air; in
% wind the LoS sweeps across the airborne antenna's pattern, Lin et al. 2026). The jitter
% is a pitch wobble below 10 deg at 5-25 Hz with the antennas 0.4 m from the centre of
% rotation, Banagar & Dhillon's assumed parameters: the channel decorrelates within
% 6.7-12.3 ms at 2.4 GHz.
params.wobble_random    = true;                  % attitude in wind drawn per seeded flight
params.wobble_v_max     = 8;                     % [m/s] below it: hover attitude and wobble
params.wobble_roll_deg  = [-17.5 19.3];          % [deg] static roll (Polle et al.)
params.wobble_pitch_deg = [-11.0 14.9];          % [deg] static pitch (Polle et al.)
params.wobble_amp_deg   = 10;                    % [deg] largest pitch wobble (Banagar & Dhillon)
params.wobble_pitch_lim_deg = [-17.7 21.1];      % [deg] largest calibrated pitch tilt, forward and backward (Polle et al.)
params.wobble_freq_hz   = [5 25];                % [Hz] wobble frequency (Banagar & Dhillon)
params.wobble_arm_m     = 0.4;                   % [m] antenna offset from the centre of rotation (Banagar & Dhillon)

% Threat parameters at nominal severity, the middle of the decision layer's five
% levels (dataset levels: run_dataset_sweep.m; decision levels: decision_config.m)
params.active_threat = 'jamming';   % threat of the next model build: 'none', a threat, or 'a+b'
params.jsr_db        = 16;          % [dB] Jamming-to-Signal Ratio (barrage jammer power)
params.burst_duty    = 0.3;         % Noise Burst: fraction of time jammer is ON (0-1)
params.burst_period  = 100;         % Noise Burst: on/off cycle length (symbols); its phase drawn per flight (jam_timing.m)
params.path_loss_db  = 14;          % Path Loss: attenuation (dB) applied to Tx signal
% Antenna Fault: a connector of one antenna is open for the flight (a broken connector that
% separates at altitude and stays open, Fedde & Carter, US 4,506,385; opens are the most
% common connector failure, Ginart et al.). The open contact couples only through its gap
% capacitance: an estimate of 0.01-0.03 pF at 2.4 GHz in 50 ohm gives 26-36 dB (no
% measurement of this depth was found).
params.fault_atten_db = 31;         % Antenna Fault: loss of the open antenna [dB]
% Spoofing: a counterfeit GCS on the same radio as ours (Mekdad et al.); its power over our
% signal is set by geometry: 30 dB is a spoofer 31 times closer to the UAV than the GCS
% (it captures the receiver from a 0.2-3 dB advantage, Whitehouse et al.).
params.spoof_sir_db   = 3;          % Spoofing: Spoof-to-Signal Ratio (dB), 0 = equal power
params.reactive_threshold = 0.5;    % Reactive Jamming: signal-energy threshold to trigger jammer
params.tone_jsr_db    = 16;         % Tone (CW) jammer: in-band power over our signal (dB)
params.tone_offset_hz = 300e3;      % Tone offset from our carrier, uniform in +-this per flight (flat part of the RRC band)
% Airframe shadowing: in a banking turn the airframe hides one antenna for seconds; the
% median loss of an event is 15.5 +- 4.9 dB (C-band; 10.8 +- 3 dB at L-band), events up
% to about 25 dB, and the hidden antenna loses its line of sight: its K-factor falls to
% about -16 dB (Sun et al.). Applied in the channel (build_threat_model.m).
params.shadow_db      = 15.5;       % Airframe shadowing: median loss of the hidden antenna [dB]
params.shadow_k_db    = -16;        % Airframe shadowing: K-factor of the hidden antenna [dB]

% Benign Interference: packet traffic of a WLAN in our channel, not an attack.
% Frames of 0.27-3.2 ms and channel occupancy 5-86% (Wollenberg et al.; field duty
% cycles 4.6-11.5%, Cheema & Salous); idle gaps gamma-distributed with the field shape
% 0.49 (Cheema & Salous: the best fit, exponential the worst), their mean set by the
% flight's occupancy. Its level over our signal follows from geometry: an access point
% at the ETSI EN 300 328 limits (20 dBm e.i.r.p., 10 dBm/MHz) close below the UAV against
% our GCS kilometres away reaches tens of dB; capped at the in-band cap of 30 dB.
params.benign_int_db  = 0;          % Benign Interference power over our signal while a packet is on the air (dB)
params.benign_occ     = [0.05 0.86];      % channel occupancy, drawn per flight
params.benign_pkt_s   = [0.268e-3 3.2e-3]; % packet duration, log-uniform [s]
params.benign_idle_shape = 0.49;          % gamma shape of the idle gaps

% Sweeping Jammer (Liu et al.: sweep 1 GHz/s, instantaneous bandwidth 4 MHz, a 20 MHz band):
% its band covers our 1.25 MHz channel for (4 + 1.25) MHz / 1 GHz/s = 5.25 ms of every
% sweep (sweep_window_s.m); the sweep period is the swept band over the speed, 20 ms over
% Liu's 20 MHz to 83.5 ms over the whole 2.4 GHz band (2400-2483.5 MHz, ETSI EN 300 328).
% Period and phase on the channel clock drawn per flight (jam_timing.m): a frame is
% jammed whole, in part or not at all. Severity axis jsr_db, as jamming.
params.sweep_speed_hz_s = 1e9;         % [Hz/s] sweep speed
params.sweep_bw_hz      = 4e6;         % [Hz] instantaneous bandwidth of the jammer
params.sweep_period_s   = [20e-3 83.5e-3];   % [s] range of the sweep period
params.jam_timing_random = true;       % sweep period and phase, burst phase drawn per flight; else the shortest period, phase 0
% In-band cap: no emitter reaches the UAV more than 30 dB over our received signal, the
% sources' most severe in-band level (Liu et al.), whatever path loss, pointing or
% elevation loss our signal has, on its weakest antenna (inband_cap_amp.m, applied in
% build_threat_model.m).
params.inband_cap_db = 30;          % [dB] largest in-band power of an emitter over our received signal

% Countermeasure physics (apply_countermeasure.m)
params.cm_acr_db      = 30;         % [dB] rejection of an interferer left on another channel
params.fdiv_spacing_hz = 25e6;      % [Hz] freq_diversity: second carrier at 802.11's adjacent-channel separation, where it specifies >= 35 dB rejection (IEEE 802.11-2007 18.4.8.3)
params.cm_rate_factor = 4;          % rate_reduce: data rate / 4 -> +6 dB processing gain, goodput x0.25
params.cm_fec_rate    = 1/2;        % fec_interleave: code rate, K = 7, generators [171 133] octal; one packet over two frames (fec_packets.m)

%% ========== ANTENNAS & RECEIVER ==========
% Modeled link: GCS -> UAV command uplink; the receiver (and the detector) is on the UAV.
% Eb/N0 is per UAV antenna (per branch) and includes the GCS antenna gain.
% GCS: an AD9361-class transmitter (power control in 0.25 dB steps over 90 dB, up to
% 7.5 dBm at 2.4 GHz, AD9361 Rev F) at -6 dBm, feeding a 12 dBi directional antenna (the gain
% class of the fixed sector antenna of Rodriguez-Pineiro et al.) on a GPS tracker
% (mean pointing error 5.62 deg azimuth, 1.51 deg elevation, measured with a quadcopter,
% Nugroho & Dectaviansyah). Licence-exempt cap: 100 mW e.i.r.p. in Israel (Ministry of
% Communications), as ETSI EN 300 328, which also caps 10 dBm in any 1 MHz (4.3.2.3): our
% RRC signal puts 95.5% of its power in its central 1 MHz, so 10.2 dBm (eirp_cap_dbm.m),
% the stricter. Nominal e.i.r.p. 6 dBm, 10 dB above an omni on the same radio;
% power_control raises it by the largest step under the cap, +4.0 dB to 10.0 dBm, per
% carrier with freq_diversity (power_step_db.m). One 0.69 ms frame per 20 ms cycle (3.4%
% duty) meets the standard's limits for non-adaptive equipment. The pointing loss of
% each flight (gcs_pointing.m) is applied in the channel. A tracker that lost its target
% falls back to an omni (Boeing, US 8,503,941): 10 dB less, to the receiver a path loss.
params.gcs_pt_dbm      = -6;          % [dBm] nominal conducted power of the GCS radio
params.gcs_pmax_dbm    = 7.5;         % [dBm] largest output of the radio at 2.4 GHz (a 1 MHz CW tone, AD9361)
params.gcs_papr_db     = papr_db(params);   % [dB] peak over mean of our waveform: its mean stays this far below
params.gcs_step_db     = 0.25;        % [dB] power-control step of the radio
params.gcs_ant_dbi     = 12;          % [dBi] tracked directional GCS antenna
params.gcs_omni_dbi    = 2;           % [dBi] omni fallback antenna
params.gcs_psd_dbm_mhz = 10;          % [dBm] e.i.r.p. density cap in any 1 MHz
params.gcs_eirp_cap_dbm = eirp_cap_dbm(params.gcs_psd_dbm_mhz, params.rolloff, params.symbol_rate);   % [dBm]
params.gcs_tracked     = true;        % pointing loss drawn per seeded sub-run
params.gcs_err_deg     = [5.62 1.51]; % [deg] mean pointing error, azimuth / elevation
params.gcs_floor_db    = 14;          % [dB] edge of the F.1336 main-lobe formula (1.08 phi3)
% UAV: n_rx omni antennas under the airframe (fuselage or wings), spatially separated so that airframe
% shadowing rarely hides all of them at once (Khawaja et al.: two bottom-mounted
% antennas about 1.2 m apart; small UAVs measured with three and four antennas).
% Line array over that 1.2 m aperture along the fuselage (D58, the 3D scene; D69 allows
% the wings too): a roll turns about the array, so a bank tilts the antennas but not the
% array. Three antennas null up to two interferers.
params.n_rx           = 3;            % UAV receive antennas (profile 1)
if isfile('profile.json')             % antenna profile of this checkout (branch profile-2-antennas)
    prof = jsondecode(fileread('profile.json'));
    if isfield(prof, 'n_rx'), params.n_rx = prof.n_rx; end
end
params.ant_aperture_m = 1.2;          % distance between the outer antennas [m]
params.ant_spacing_wl = params.ant_aperture_m / (3e8 / params.carrier_freq) / (params.n_rx - 1);   % element spacing [wavelengths]
% Diffuse-fading correlation between adjacent antennas: no source gives it for a small UAV
% (on an aircraft underside the received amplitudes, line of sight included, correlate
% 0.85-0.99, Sun); drawn per flight over a wide range (rx_correlation.m).
params.rx_corr        = 0.3;          % fixed value (PHY validation, maps)
params.corr_random    = true;         % correlation drawn per seeded sub-run
params.corr_range     = [0.3 0.9];
params.gcs_aoa_deg    = 0;            % GCS direction from array broadside [deg]; added to the draw
params.gcs_aoa_random = true;         % GCS direction drawn per flight (gcs_aoa.m); 0 for fixed geometries
params.gcs_aoa_range_deg = [-90 90];  % range of the random GCS direction (broadside angle) [deg]
% Airframe: the drone body changes each mounted antenna's azimuth pattern by 0.016-10.96 dB,
% mean 3.03, SD 2.53 (Badi et al. 2019), drawn per flight and antenna (body_loss.m) on our
% signal; the flight's mean loss is part of the link budget's margin (lb_margin_db).
params.body_random    = true;
params.body_loss_db   = [3.03 2.53 0.016 10.96];   % [dB] mean, SD, min, max
% Fixed interferer directions (GUI, gallery, PHY validation) and the survivability
% geometries (separated, aligned): the same spatial alignment with the GCS on every
% array (0.25 / 0.2 / 0.93, as 40-45 / 45 / 10 deg on a half-wavelength pair)
if params.n_rx == 2
    params.int_aoa_deg = [44.1 -50 60];   params.geom_aoa_deg = [41.4 6.5];
elseif params.n_rx == 4
    params.int_aoa_deg = [42.4 -42.3 62.7]; params.geom_aoa_deg = [42.6 17.5];   % nearest angles with those alignments
else
    params.int_aoa_deg = [42 -52.2 61.3]; params.geom_aoa_deg = [42.2 11.4];
end
params.int_aoa_random = true;         % interferer directions drawn per seeded sub-run (interferer_aoa.m)
params.int_aoa_range_deg = [-90 90];  % range of the random directions (broadside angle) [deg]
params.int_rician_k   = params.rician_k;  % K-factor of the interferer -> UAV channels (dB)
% Receive chains: gain and phase mismatch between the antennas' chains, fixed per flight
% (0.1 dB / 1 deg, the example of Bakr; it limits the null of a calibrated, non-adaptive
% array to about -34 dB). The I/Q imbalance of a transceiver such as the AD9361 (0.2% /
% 0.2 deg: image about 54 dB down) leaves even a 30 dB jammer's image far below our signal.
params.chain_amp_db   = 0.1;          % [dB] std of each chain's gain error
params.chain_phase_deg = 1;           % [deg] std of each chain's phase error
params.rx_combiner    = 'mrc';        % 'mrc' baseline | 'mmse' (spatial_diversity action)
params.csi_block      = 64;           % [symbols] channel-estimation window (MRC)
params.mmse_window    = 32;           % [symbols] channel + interference-covariance window (MMSE; the delay line's taps: rx_taps.m)
params.seed           = [];           % [] = drawn from the global stream at every model build

%% ========== ALTITUDE & LINK BUDGET ==========
% Altitude, drawn per flight: up to the FAA small-UAV ceiling of 122 m, the rule behind the
% 161 km/h cap (Khawaja et al.; 120 m, Cui et al.), down to 15 m, the lowest height with a
% full 2.5 GHz channel table (Rodriguez-Pineiro et al.), above the 0-11 m below-roofline
% band (Cui et al.). It reaches the link only through the UAV dipole's gain toward the GCS
% (flight_draws.m) and, below 25 m, the obstructed-LoS delay spread of our signal
% (delay_spread.m): K and the delay spread above it show no height trend and the Doppler
% spread falls with height (Rodriguez-Pineiro et al.).
params.alt_random   = true;               % altitude drawn per seeded flight (flight_altitude.m)
params.alt_range_m  = [15 120];           % [m] UAV height above ground
params.alt_grid_m   = [15 25 35 45 60 75 90 105 120];   % [m] table heights: Rodriguez-Pineiro et al.'s and the ceiling
params.gcs_h_m      = 10;                 % [m] GCS antenna mast
params.uav_null_db  = -30;                % [dB] UAV dipole gain directly below a drone (Badi et al.)
% Distance attached to each Eb/N0 (link_distance_km.m): the GCS above, free space at the carrier
params.lb_uav_dbi   = 2;                  % [dBi] UAV antenna (omni dipole)
params.lb_nf_db     = 5;                  % [dB] UAV receiver noise figure
params.lb_margin_db = 10;                 % [dB] fading and implementation margin
params.lb_rate_bps  = 2e6;                % [b/s] bit rate (QPSK, 1 Msym/s)

%% ========== EB/N0 GRID ==========
params.EbNo_dB    = 0:3:15;            % Eb/N0 grid of the dataset and the pools (dB): 1.6 to 0.3 km with the licence-exempt GCS (link_budget_table.m)

%% ========== LEGACY (code in legacy/ only) ==========
params.num_frames = 1000;    % frames per Eb/N0 point of the AWGN sweep (run_awgn_sweep.m)
params.seq_len    = 8;       % CNN-LSTM study: frames per sequence window
params.seq_stride = 4;       % CNN-LSTM study: step between window starts

%% ========== FLAGS ==========
params.verbose     = true;
params.quiet_build = true;     % build Simulink models without opening the editor window
%% ========== DERIVED PARAMETERS ==========
params.bits_per_symbol   = log2(params.mod_order);
params.symbols_per_frame = params.frame_length / params.bits_per_symbol;      % data symbols
Lf = frame_layout(params);
params.air_symbols       = Lf.air;                                            % training + data + pilots + quiet slot
params.samples_per_frame = params.air_symbols * params.sps;
params.frame_duration    = params.symbols_per_frame / params.symbol_rate;     % simulation step (bit clock)
%% ========== DISPLAY ==========
if params.verbose
    fprintf('\n========== UAV-GCS LINK PARAMETERS ==========\n');
    fprintf('Modulation:       %s\n', params.mod_type);
    fprintf('Symbol Rate:      %.2e sym/s\n', params.symbol_rate);
    fprintf('Bits/Frame:       %d (+ %d CRC)\n', params.bits_per_frame, params.crc_bits);
    fprintf('Symbols/Frame:    %d\n', params.symbols_per_frame);
    if params.k_random
        fprintf('Channel:          Rician, K drawn per flight in %g-%g dB, GCS -> UAV uplink\n', params.k_range_db);
    else
        fprintf('Channel:          Rician (K=%.1f dB), GCS -> UAV uplink\n', params.rician_k);
    end
    if params.tdl && params.tdl_random
        fprintf('Delay line:       taps %g ns apart to %g ns, RMS delay spread drawn per flight\n', ...
            params.tdl_step_ns, params.tdl_max_ns);
    elseif params.tdl
        fprintf('Delay line:       taps %g ns apart to %g ns, RMS delay spread %g / %g ns\n', ...
            params.tdl_step_ns, params.tdl_max_ns, params.tdl_ds_ns);
    end
    fprintf('UAV antennas:     %d over %.2f m (spacing %.2f wl, rho %.2f), Rx %s\n', params.n_rx, ...
            params.ant_aperture_m, params.ant_spacing_wl, params.rx_corr, upper(params.rx_combiner));
    if params.int_aoa_random
        fprintf('Interferer AoA:   random per sub-run, %d to %d deg\n', params.int_aoa_range_deg);
    end
    fprintf('Carrier Freq:     %.1f GHz\n', params.carrier_freq/1e9);
    if params.alt_random
        fprintf('Altitude:         %g-%g m per flight, GCS mast %g m\n', params.alt_range_m, params.gcs_h_m);
    end
    fprintf('UAV Velocity:     %.1f m/s (%.1f km/h) nominal | envelope %.1f-%.1f km/h (%.1f-%.1f m/s)\n', ...
            params.v_nominal, params.v_nominal*3.6, params.speed_kmh_min, params.speed_kmh_max, params.v_min, params.v_max);
    fprintf('Doppler envelope: %.0f-%.0f Hz (nominal fd_max %.0f Hz)\n', ...
            params.v_min*params.carrier_freq/params.c_light, params.v_max*params.carrier_freq/params.c_light, params.fd_max);
    fprintf('Max Doppler fd:   %.1f Hz  (normalized %.2e)\n', ...
            params.fd_max, params.fd_max/params.symbol_rate);
    fprintf('Active Threat:    %s (JSR=%.0f dB)\n', params.active_threat, params.jsr_db);
    fprintf('Eb/N0 Range:      %.0f to %.0f dB\n', min(params.EbNo_dB), max(params.EbNo_dB));
    fprintf('=============================================\n\n');
end
%% ========== SAVE PARAMETERS ==========
save('params.mat', 'params');
fprintf('Parameters saved to params.mat\n');