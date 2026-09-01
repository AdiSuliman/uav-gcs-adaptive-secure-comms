%% UAV-GCS Adaptive Secure Communications System - Parameters
% Phase A1: Clean Link Model Parameters
% Created: 2026-09-01
% Author: Claude + Adi Suliman, Bar Dvir Hassan

clear all; close all; clc;

%% ========== SYSTEM PARAMETERS ==========

% Modulation & Transmission
params.mod_type = 'QPSK';           % Modulation: QPSK
params.mod_order = 4;               % QPSK order
params.symbol_rate = 1e6;           % 1 million symbols/sec
params.samples_per_symbol = 4;      % Oversampling factor
params.sps = params.samples_per_symbol;

% Frame Structure
params.bits_per_frame = 1000;       % Information bits per frame
params.crc_bits = 32;               % CRC bits
params.frame_length = params.bits_per_frame + params.crc_bits;  % Total bits

% Channel Model
params.channel_type = 'Rician';     % Rician fading channel
params.rician_k = 10;               % K-factor (dB) — strong LoS component
params.carrier_freq = 2.4e9;        % 2.4 GHz ISM band
params.nominal_range = 100;         % Nominal range: 100 meters

% Noise & SNR
params.EbNo_dB = 0:2:10;            % Eb/N0 range (dB) for BER sweep
params.num_frames = 1000;           % Frames per Eb/N0 point

% Plotting & Display
params.plot_enable = true;
params.verbose = true;

%% ========== DERIVED PARAMETERS ==========

params.bits_per_symbol = log2(params.mod_order);
params.symbols_per_frame = params.frame_length / params.bits_per_symbol;
params.samples_per_frame = params.symbols_per_frame * params.sps;
params.frame_duration = params.symbols_per_frame / params.symbol_rate;

%% ========== DISPLAY ==========

if params.verbose
    fprintf('\n========== UAV-GCS LINK PARAMETERS ==========\n');
    fprintf('Modulation:       %s\n', params.mod_type);
    fprintf('Symbol Rate:      %.2e sym/s\n', params.symbol_rate);
    fprintf('Samples/Symbol:   %d\n', params.sps);
    fprintf('Bits/Frame:       %d (+ %d CRC)\n', params.bits_per_frame, params.crc_bits);
    fprintf('Symbols/Frame:    %d\n', params.symbols_per_frame);
    fprintf('Channel:          %s (K=%.1f dB)\n', params.channel_type, params.rician_k);
    fprintf('Carrier Freq:     %.1f GHz\n', params.carrier_freq/1e9);
    fprintf('Range:            %d m\n', params.nominal_range);
    fprintf('Eb/N0 Range:      %.0f to %.0f dB\n', min(params.EbNo_dB), max(params.EbNo_dB));
    fprintf('Frames per SNR:   %d\n', params.num_frames);
    fprintf('=============================================\n\n');
end

%% ========== SAVE PARAMETERS ==========

save('params.mat', 'params');
fprintf('Parameters saved to params.mat\n');