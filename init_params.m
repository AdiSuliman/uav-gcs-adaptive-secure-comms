%% UAV-GCS Adaptive Secure Communications System - Parameters
% Central parameter file. Run this FIRST — it saves params.mat that all
% other scripts load.
% Author: Adi Suliman, Bar Dvir Hassan
% Created: 2026-09-01
clear all; close all; clc;
%% ========== PROJECT PHASE ==========
params.phase        = 'A4';          % current phase
params.active_channel = 'Rician';    % [ACTIVE] channel used now
params.target_channel = 'Rician';    % scope target
%% ========== MODULATION & TRANSMISSION ==========
params.mod_type            = 'QPSK';   % [ACTIVE] modulation scheme
params.mod_order           = 4;        % [ACTIVE] QPSK -> 4
params.symbol_rate         = 1e6;      % [ACTIVE] 1 Msym/s
params.samples_per_symbol  = 4;        % [FUTURE] oversampling (A3+, spectral features)
params.sps                 = params.samples_per_symbol;
%% ========== FRAME STRUCTURE ==========
params.bits_per_frame = 1000;          % [ACTIVE] information bits per frame
params.crc_bits       = 32;            % [FUTURE] CRC for Packet Loss Rate metric (A6)
params.frame_length   = params.bits_per_frame + params.crc_bits;  % total bits/frame
%% ========== CHANNEL MODEL ==========
params.rician_k      = 10;             % [ACTIVE] K-factor (dB), strong LoS
params.carrier_freq  = 2.4e9;          % [ACTIVE] 2.4 GHz ISM
params.nominal_range = 100;            % [FUTURE] nominal link range (m)

% [A3] UAV platform velocity & derived Doppler
% Platform: small tactical ISR UAV — DoD Group 1 (Skylark/Raven class)
% Operational speed envelope: 18-22 m/s (65-79 km/h), documented for the report.
% Nominal speed drives the channel Doppler in simulation.
params.v_min     = 18;      % [m/s] envelope lower bound (65 km/h) — documentation
params.v_max     = 22;      % [m/s] envelope upper bound (79 km/h) — documentation
params.v_nominal = 20;      % [m/s] nominal cruise (72 km/h) — drives simulation Doppler
params.c_light   = 3e8;     % [m/s] speed of light
params.fd_max    = params.v_nominal * params.carrier_freq / params.c_light;  % [Hz] ~160 @ 20 m/s

% [A4] Threat injection parameters
params.active_threat = 'jamming';   % 'none' | 'jamming' (more threats added incrementally)
params.jsr_db        = 10;          % [dB] Jamming-to-Signal Ratio (barrage jammer power)
params.burst_duty    = 0.3;         % [A4] Noise Burst: fraction of time jammer is ON (0-1)
params.burst_period  = 100;         % [A4] Noise Burst: on/off cycle length (symbols)
params.path_loss_db  = 10;          % [A4] Path Loss: attenuation (dB) applied to Tx signal
%% ========== NOISE & SWEEP ==========
params.EbNo_dB    = 0:2:10;            % [ACTIVE] Eb/N0 sweep range (dB)
params.num_frames = 1000;             % [ACTIVE] frames accumulated per Eb/N0 point
%% ========== FLAGS ==========
params.plot_enable = true;
params.verbose     = true;
%% ========== DERIVED PARAMETERS ==========
params.bits_per_symbol   = log2(params.mod_order);
params.symbols_per_frame = params.frame_length / params.bits_per_symbol;
params.samples_per_frame = params.symbols_per_frame * params.sps;
params.frame_duration    = params.symbols_per_frame / params.symbol_rate;
%% ========== DISPLAY ==========
if params.verbose
    fprintf('\n========== UAV-GCS LINK PARAMETERS ==========\n');
    fprintf('Phase:            %s  (channel: %s)\n', params.phase, params.active_channel);
    fprintf('Modulation:       %s\n', params.mod_type);
    fprintf('Symbol Rate:      %.2e sym/s\n', params.symbol_rate);
    fprintf('Bits/Frame:       %d (+ %d CRC [FUTURE])\n', params.bits_per_frame, params.crc_bits);
    fprintf('Symbols/Frame:    %d\n', params.symbols_per_frame);
    fprintf('Channel:          Rician (K=%.1f dB)\n', params.rician_k);
    fprintf('Carrier Freq:     %.1f GHz\n', params.carrier_freq/1e9);
    fprintf('Range:            %d m [FUTURE]\n', params.nominal_range);
    fprintf('UAV Velocity:     %.0f m/s (%.0f km/h) nominal | envelope %.0f-%.0f m/s\n', ...
            params.v_nominal, params.v_nominal*3.6, params.v_min, params.v_max);
    fprintf('Max Doppler fd:   %.1f Hz  (normalized %.2e)\n', ...
            params.fd_max, params.fd_max/params.symbol_rate);
    fprintf('Active Threat:    %s (JSR=%.0f dB)\n', params.active_threat, params.jsr_db);
    fprintf('Eb/N0 Range:      %.0f to %.0f dB\n', min(params.EbNo_dB), max(params.EbNo_dB));
    fprintf('Frames per SNR:   %d\n', params.num_frames);
    fprintf('=============================================\n\n');
end
%% ========== SAVE PARAMETERS ==========
save('params.mat', 'params');
fprintf('Parameters saved to params.mat\n');