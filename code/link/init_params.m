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
%% ========== CHANNEL MODEL ==========
% Pulse shaping (RRC)
params.rolloff      = 0.25;            % RRC roll-off factor
params.filter_span  = 10;              % RRC filter span (symbols)
params.rician_k      = 10;             % K-factor (dB), strong LoS
params.carrier_freq  = 2.4e9;          % 2.4 GHz ISM (range for a given Eb/N0: link_budget_table.m)

% UAV platform velocity and Doppler
% Platform: small tactical ISR UAV — DoD Group 1 (Skylark/Raven class)
% Operational speed envelope: 50-120 km/h (13.9-33.3 m/s) -> Doppler 111-267 Hz @ 2.4 GHz.
% Speed is a CONTINUOUS parameter (any real value inside the envelope, not only
% whole km/h). The dataset generator draws a random real-valued speed per block
% of frames; the GUI accepts decimals. fd_max = v * fc / c.
% v_nominal (20 m/s = 72 km/h -> fd = 160 Hz) is the default cruise speed used by
% every script that does not draw a speed per seeded run.
params.speed_kmh_min = 50;                       % [km/h] envelope lower bound
params.speed_kmh_max = 120;                      % [km/h] envelope upper bound
params.v_min     = params.speed_kmh_min/3.6;     % [m/s]  13.89
params.v_max     = params.speed_kmh_max/3.6;     % [m/s]  33.33
params.v_nominal = 20;      % [m/s] nominal cruise (72 km/h) — default simulation Doppler
params.c_light   = 3e8;     % [m/s] speed of light
params.fd_max    = params.v_nominal * params.carrier_freq / params.c_light;  % [Hz] ~160 @ 20 m/s

% Threat parameters at nominal severity (severity levels: run_dataset_sweep.m, decision_config.m)
params.active_threat = 'jamming';   % threat of the next model build: 'none', a threat, or 'a+b'
params.jsr_db        = 10;          % [dB] Jamming-to-Signal Ratio (barrage jammer power)
params.burst_duty    = 0.3;         % Noise Burst: fraction of time jammer is ON (0-1)
params.burst_period  = 100;         % Noise Burst: on/off cycle length (symbols)
params.path_loss_db  = 10;          % Path Loss: attenuation (dB) applied to Tx signal
params.fault_duty     = 0.15;       % Antenna Fault: fraction of time fault is active (0-1)
params.fault_period   = 200;        % Antenna Fault: fault on/off cycle length (symbols)
params.fault_atten_db = 30;         % Antenna Fault: severe attenuation during fault (dB)
params.spoof_sir_db   = 0;          % Spoofing: Spoof-to-Signal Ratio (dB), 0 = equal power
params.reactive_threshold = 0.5;    % Reactive Jamming: signal-energy threshold to trigger jammer

% Benign Interference: weak NON-MALICIOUS in-band noise (e.g. neighboring
% WiFi/ISM device). Deliberately much weaker than active jamming (-10 to -2 dB vs
% jamming's 0-16 dB) so it never overlaps the attack power range -- exists to give
% the CNN a "looks-like-something but isn't an attack" class for FAR measurement.
params.benign_int_db  = -6;         % Benign Interference power (dB), weak/non-malicious

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
% UAV: n_rx omni dipoles under the fuselage (V-mount, 2x2-class datalink radio), ULA model.
params.n_rx           = 2;            % UAV receive antennas (3 supported)
params.ant_spacing_wl = 0.5;          % element spacing [wavelengths] (6.25 cm @ 2.4 GHz)
params.rx_corr        = 0.3;          % diffuse-fading correlation between adjacent antennas
params.gcs_aoa_deg    = 0;            % GCS direction from array broadside [deg]
params.int_aoa_deg    = [40 -55 70];  % fixed direction of interferer 1..3 (components of a threat) [deg]
params.int_aoa_random = true;         % interferer directions drawn per seeded sub-run (interferer_aoa.m)
params.int_aoa_range_deg = [-90 90];  % range of the random directions (broadside angle) [deg]
params.int_rician_k   = params.rician_k;  % K-factor of the interferer -> UAV channels (dB)
params.rx_combiner    = 'mrc';        % 'mrc' baseline | 'mmse' (spatial_diversity action)
params.csi_block      = 64;           % [symbols] channel-estimation window (MRC)
params.mmse_window    = 32;           % [symbols] channel + interference-covariance window (MMSE)
params.seed           = [];           % [] = drawn from the global stream at every model build

%% ========== EB/N0 GRID ==========
params.EbNo_dB    = 0:2:10;            % Eb/N0 grid of the dataset and the pools (dB)

%% ========== LEGACY (code in legacy/ only) ==========
params.num_frames = 1000;    % frames per Eb/N0 point of the AWGN sweep (run_awgn_sweep.m)
params.seq_len    = 8;       % CNN-LSTM study: frames per sequence window
params.seq_stride = 4;       % CNN-LSTM study: step between window starts

%% ========== FLAGS ==========
params.verbose     = true;
params.quiet_build = true;     % build Simulink models without opening the editor window
%% ========== DERIVED PARAMETERS ==========
params.bits_per_symbol   = log2(params.mod_order);
params.symbols_per_frame = params.frame_length / params.bits_per_symbol;
params.samples_per_frame = params.symbols_per_frame * params.sps;
params.frame_duration    = params.symbols_per_frame / params.symbol_rate;
%% ========== DISPLAY ==========
if params.verbose
    fprintf('\n========== UAV-GCS LINK PARAMETERS ==========\n');
    fprintf('Modulation:       %s\n', params.mod_type);
    fprintf('Symbol Rate:      %.2e sym/s\n', params.symbol_rate);
    fprintf('Bits/Frame:       %d (+ %d CRC)\n', params.bits_per_frame, params.crc_bits);
    fprintf('Symbols/Frame:    %d\n', params.symbols_per_frame);
    fprintf('Channel:          Rician (K=%.1f dB), GCS -> UAV uplink\n', params.rician_k);
    fprintf('UAV antennas:     %d (spacing %.2f wl, rho %.2f), Rx %s\n', params.n_rx, ...
            params.ant_spacing_wl, params.rx_corr, upper(params.rx_combiner));
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