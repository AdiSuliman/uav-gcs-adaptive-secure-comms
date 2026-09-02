%% UAV-GCS Adaptive Secure Communications System - Parameters
% Central parameter file. Run this FIRST — it saves params.mat that all
% other scripts load.
% Author: Claude + Adi Suliman, Bar Dvir Hassan
% Created: 2026-09-01
%
% SCOPE TARGET vs CURRENT PHASE:
%   Project target channel = Rician K=10dB (locked in proposal).
%   Current phase (A2) validates the engine on AWGN first, then A3 adds
%   Rician + synchronization. Params below are tagged [ACTIVE] (used now)
%   or [FUTURE] (defined, wired in later — kept intentionally, not dead code).

clear all; close all; clc;

%% ========== PROJECT PHASE ==========
params.phase        = 'A2';          % current phase
params.active_channel = 'AWGN';      % [ACTIVE] channel used in this phase
params.target_channel = 'Rician';    % [FUTURE] scope target (added in A3)

%% ========== MODULATION & TRANSMISSION ==========
params.mod_type            = 'QPSK';   % [ACTIVE] modulation scheme
params.mod_order           = 4;        % [ACTIVE] QPSK -> 4
params.symbol_rate         = 1e6;      % [ACTIVE] 1 Msym/s
params.samples_per_symbol  = 4;        % [FUTURE] oversampling for pulse shaping (A3+, spectral features)
params.sps                 = params.samples_per_symbol;

%% ========== FRAME STRUCTURE ==========
params.bits_per_frame = 1000;          % [ACTIVE] information bits per frame
params.crc_bits       = 32;            % [FUTURE] CRC for Packet Loss Rate metric (A6)
params.frame_length   = params.bits_per_frame + params.crc_bits;  % total bits/frame

%% ========== CHANNEL MODEL ==========
% [FUTURE] Rician params — wired in A3. Kept here as the scope target.
params.rician_k      = 10;             % [FUTURE] K-factor (dB), strong LoS
params.carrier_freq  = 2.4e9;          % [FUTURE] 2.4 GHz ISM (path loss / range model)
params.nominal_range = 100;            % [FUTURE] nominal link range (m)

%% ========== NOISE & SWEEP ==========
params.EbNo_dB    = 0:2:10;            % [ACTIVE] Eb/N0 sweep range (dB)
params.num_frames = 1000;             % [ACTIVE] frames accumulated per Eb/N0 point

%% ========== FLAGS ==========
params.plot_enable = true;
params.verbose     = true;

%% ========== DERIVED PARAMETERS ==========
params.bits_per_symbol   = log2(params.mod_order);
params.symbols_per_frame = params.frame_length / params.bits_per_symbol;
params.samples_per_frame = params.symbols_per_frame * params.sps;   % [FUTURE] used when oversampling active
params.frame_duration    = params.symbols_per_frame / params.symbol_rate;

%% ========== DISPLAY ==========
if params.verbose
    fprintf('\n========== UAV-GCS LINK PARAMETERS ==========\n');
    fprintf('Phase:            %s  (channel now: %s | target: %s)\n', ...
            params.phase, params.active_channel, params.target_channel);
    fprintf('Modulation:       %s\n', params.mod_type);
    fprintf('Symbol Rate:      %.2e sym/s\n', params.symbol_rate);
    fprintf('Samples/Symbol:   %d   [FUTURE — not yet in signal chain]\n', params.sps);
    fprintf('Bits/Frame:       %d (+ %d CRC [FUTURE])\n', params.bits_per_frame, params.crc_bits);
    fprintf('Symbols/Frame:    %d\n', params.symbols_per_frame);
    fprintf('Target Channel:   %s (K=%.1f dB) [FUTURE — A3]\n', params.target_channel, params.rician_k);
    fprintf('Carrier Freq:     %.1f GHz [FUTURE]\n', params.carrier_freq/1e9);
    fprintf('Range:            %d m [FUTURE]\n', params.nominal_range);
    fprintf('Eb/N0 Range:      %.0f to %.0f dB\n', min(params.EbNo_dB), max(params.EbNo_dB));
    fprintf('Frames per SNR:   %d\n', params.num_frames);
    fprintf('=============================================\n\n');
end

%% ========== SAVE PARAMETERS ==========
save('params.mat', 'params');
fprintf('Parameters saved to params.mat\n');