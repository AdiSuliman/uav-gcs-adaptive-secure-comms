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
params.rx_dd_iter     = 2;             % decision-directed estimation passes after the pilot-based one
%% ========== CHANNEL MODEL ==========
% Pulse shaping (RRC)
params.rolloff      = 0.25;            % RRC roll-off factor
params.filter_span  = 10;              % RRC filter span (symbols)
params.rician_k      = 10;             % K-factor (dB) when not drawn per flight (PHY validation)
params.k_random      = true;           % K-factor of every channel drawn per seeded flight (channel_k.m)
params.k_range_db    = [-5 20];        % measured air-ground K: foliage 2-5, urban -5..10, open L-band ~12, C-band ~28 dB (Khawaja et al.)
params.carrier_freq  = 2.4e9;          % 2.4 GHz ISM (range for a given Eb/N0: link_budget_table.m)

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

% Threat parameters at nominal severity, the middle of the decision layer's five
% levels (dataset levels: run_dataset_sweep.m; decision levels: decision_config.m)
params.active_threat = 'jamming';   % threat of the next model build: 'none', a threat, or 'a+b'
params.jsr_db        = 16;          % [dB] Jamming-to-Signal Ratio (barrage jammer power)
params.burst_duty    = 0.3;         % Noise Burst: fraction of time jammer is ON (0-1)
params.burst_period  = 100;         % Noise Burst: on/off cycle length (symbols)
params.path_loss_db  = 14;          % Path Loss: attenuation (dB) applied to Tx signal
params.fault_duty     = 0.3;        % Antenna Fault: fraction of time the contact is open (0-1)
params.fault_period   = 200;        % Antenna Fault: on/off cycle [symbols] when no vibration band is set
params.fault_vib_hz   = [86 672];   % Antenna Fault: a connector opens at an airframe vibration frequency, drawn
                                    % per flight (motor and frame modes of a multirotor, Verbeke & Debruyne)
params.fault_atten_db = 30;         % Antenna Fault: loss while open [dB]: an open contact couples only through
                                    % its gap capacitance (0.01-0.03 pF at 2.4 GHz in 50 ohm: 26-36 dB)
params.spoof_sir_db   = 3;          % Spoofing: Spoof-to-Signal Ratio (dB), 0 = equal power
params.reactive_threshold = 0.5;    % Reactive Jamming: signal-energy threshold to trigger jammer
params.tone_jsr_db    = 16;         % Tone (CW) jammer: in-band power over our signal (dB)
params.tone_offset_hz = 300e3;      % Tone offset from our carrier, uniform in +-this per flight (flat part of the RRC band)
params.shadow_db      = 20;         % Airframe shadowing: loss on one antenna in a banking turn (dB; up to 40 measured,
                                    % events lasting about 30 s, Sun; Khawaja et al.)

% Benign Interference: packet traffic of a WLAN in our channel, not an attack.
% Frames of 0.27-3.2 ms (Wollenberg et al.), channel occupancy 5-86% (Cheema &
% Salous; Wollenberg et al.), idle gaps exponential. A WLAN access point below the
% UAV can arrive stronger than our GCS (EIRP 20 dBm, ETSI EN 300 328, against the
% link budget of link_budget_table.m; interference grows with altitude, Song et al.),
% up to the in-band cap of the sources (30 dB).
params.benign_int_db  = 0;          % Benign Interference power over our signal while a packet is on the air (dB)
params.benign_occ     = [0.05 0.86];      % channel occupancy, drawn per flight
params.benign_pkt_s   = [0.268e-3 3.2e-3]; % packet duration, log-uniform [s]

% Sweeping Jammer: like jamming, but only dwells on our channel a fraction
% of the time (spends the rest sweeping other channels). Severity axis is still
% jsr_db (consistent with jamming/noise_burst/reactive_jamming), duty/period are
% fixed structural constants (same pattern as burst_duty/burst_period for noise_burst).
params.sweep_duty    = 0.15;        % Sweeping Jammer: fraction of time dwelling on our channel
params.sweep_period  = 300;         % Sweeping Jammer: full sweep cycle length (symbols, longer than noise_burst's 100)

% Countermeasure physics (apply_countermeasure.m)
params.cm_acr_db      = 30;         % [dB] rejection of an interferer left on another channel
params.cm_rate_factor = 4;          % rate_reduce: data rate / 4 -> +6 dB processing gain, goodput x0.25
params.cm_power_db    = 6;          % power_control: transmit power +6 dB (x4 power)
params.cm_fec_rate    = 1/2;        % fec_interleave: code rate, K = 7, generators [171 133] octal

%% ========== ANTENNAS & RECEIVER ==========
% Modeled link: GCS -> UAV command uplink; the receiver (and the detector) is on the UAV.
% GCS: one antenna, its gain is part of Eb/N0. Eb/N0 is per UAV antenna (per branch).
% UAV: n_rx omni antennas under the airframe (fuselage or wings), spatially separated so that airframe
% shadowing rarely hides all of them at once (Khawaja et al.: two bottom-mounted
% antennas about 1.2 m apart; small UAVs measured with three and four antennas).
% Line array over that 1.2 m aperture; three antennas null up to two interferers.
params.n_rx           = 3;            % UAV receive antennas (profile 1)
if isfile('profile.json')             % antenna profile of this checkout (branch profile-2-antennas)
    prof = jsondecode(fileread('profile.json'));
    if isfield(prof, 'n_rx'), params.n_rx = prof.n_rx; end
end
params.ant_aperture_m = 1.2;          % distance between the outer antennas [m]
params.ant_spacing_wl = params.ant_aperture_m / (3e8 / params.carrier_freq) / (params.n_rx - 1);   % element spacing [wavelengths]
params.rx_corr        = 0.3;          % diffuse-fading correlation between adjacent antennas (ground
                                      % scatterers are seen under similar angles from the UAV, Khawaja et al.)
params.gcs_aoa_deg    = 0;            % GCS direction from array broadside [deg]
% Fixed interferer directions (GUI, gallery, PHY validation) and the survivability
% geometries (separated, aligned): the same spatial alignment with the GCS on every
% array (0.25 / 0.2 / 0.93, as 40-45 / 45 / 10 deg on a half-wavelength pair)
if params.n_rx == 2
    params.int_aoa_deg = [44.1 -50 60];   params.geom_aoa_deg = [41.4 6.5];
else
    params.int_aoa_deg = [42 -52.2 61.3]; params.geom_aoa_deg = [42.2 11.4];
end
params.int_aoa_random = true;         % interferer directions drawn per seeded sub-run (interferer_aoa.m)
params.int_aoa_range_deg = [-90 90];  % range of the random directions (broadside angle) [deg]
params.int_rician_k   = params.rician_k;  % K-factor of the interferer -> UAV channels (dB)
params.rx_combiner    = 'mrc';        % 'mrc' baseline | 'mmse' (spatial_diversity action)
params.csi_block      = 64;           % [symbols] channel-estimation window (MRC)
params.mmse_window    = 32;           % [symbols] channel + interference-covariance window (MMSE)
params.seed           = [];           % [] = drawn from the global stream at every model build

%% ========== EB/N0 GRID ==========
params.EbNo_dB    = 0:3:15;            % Eb/N0 grid of the dataset and the pools (dB): 15.7 to 2.8 km (link_budget_table.m)

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
    fprintf('UAV antennas:     %d over %.2f m (spacing %.2f wl, rho %.2f), Rx %s\n', params.n_rx, ...
            params.ant_aperture_m, params.ant_spacing_wl, params.rx_corr, upper(params.rx_combiner));
    if params.int_aoa_random
        fprintf('Interferer AoA:   random per sub-run, %d to %d deg\n', params.int_aoa_range_deg);
    end
    fprintf('Carrier Freq:     %.1f GHz\n', params.carrier_freq/1e9);
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