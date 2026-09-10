%% RUN_DATASET_SWEEP - Phase A5: Generate labeled dataset (SINGLE JSR - debug pipeline)
% Runs all 7 classes (none + 6 threats) x Eb/No sweep, collects per-frame:
%   - IQ frame (post-threat, pre-Rx-filter) -> for spectrogram (A6, CNN)
%   - scalar metrics: BER, SNR, RSSI, PLR  -> for hybrid detection features
%   - label (class index)
% Single JSR per threat (fixed params) — fast pipeline validation before the
% full multi-JSR dataset. Saves data/dataset.mat.

clear; close all; clc;

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;

%% ---- Dataset configuration ----
classes = {'none','jamming','noise_burst','path_loss','antenna_fault','spoofing','reactive_jamming'};
EbNo_list        = p.EbNo_dB;    % 0:2:10 dB
frames_per_config = 50;          % frames per (class, SNR) — small for single-JSR debug
delay_bits        = 20;          % known RRC group delay (validated)
modelName         = 'UAV_GCS_Threat_Link';

StopTime = frames_per_config * p.frame_duration;   % enough sim time for N frames

% Storage (cell for IQ, arrays for scalars)
iq_all    = {};
label_all = [];
snr_all   = [];
ber_all   = [];
rssi_all  = [];
plr_all   = [];

fprintf('\n=== A5 Dataset Generation (SINGLE JSR) ===\n');
fprintf('Classes: %d | SNR points: %d | frames/config: ~%d\n', ...
    numel(classes), numel(EbNo_list), frames_per_config);
fprintf('%-18s %6s %8s %10s %10s\n', 'Class', 'Eb/No', 'nFrames', 'meanBER', 'meanRSSI');

t_start = tic;

for c = 1:numel(classes)
    % Set active threat and rebuild model (chart code changes per threat)
    p.active_threat = classes{c};
    params = p; save('params.mat', 'params');
    evalc('build_threat_model');   % suppress build printout

    for s = 1:numel(EbNo_list)
        % SNR + SignalPower for this Eb/No (oversampling-corrected)
        snr_dB = EbNo_list(s) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
        set_param([modelName '/AWGN'], ...
            'SNR', num2str(snr_dB), ...
            'SignalPower', num2str(1/p.sps));

        % Run
        out = sim(modelName, 'StopTime', num2str(StopTime));

        % Extract bit streams and IQ frames
        txb = double(squeeze(out.get('tx_bits_out')));   % [bpf x nf]
        rxb = double(squeeze(out.get('rx_bits_out')));   % [bpf x nf]
        iq  = squeeze(out.get('Rx_IQ'));                 % [nSamp x nf] complex

        % Guard: ensure 2D
        if isvector(txb), txb = txb(:); end
        if isvector(rxb), rxb = rxb(:); end
        if isvector(iq),  iq  = iq(:);  end

        nf  = size(iq, 2);
        bpf = p.frame_length;   % bits per frame (1032)

        % Align full bit stream once (delay is on the stream, not per-frame)
        tx_all = txb(:);
        rx_all = rxb(:);
        Lmax   = min(numel(tx_all), numel(rx_all)) - delay_bits;
        tx_al  = tx_all(1:Lmax);
        rx_al  = rx_all(delay_bits+1 : delay_bits+Lmax);

        ber_cfg = [];
        for f = 1:nf
            iq_f = iq(:, f);

            % Per-frame BER from aligned stream
            idx0 = (f-1)*bpf + 1;
            idx1 = f*bpf;
            if idx1 <= numel(tx_al)
                ber_f = mean(tx_al(idx0:idx1) ~= rx_al(idx0:idx1));
            else
                ber_f = NaN;   % last frame beyond aligned length
            end

            rssi_f = 10*log10(mean(abs(iq_f).^2) + eps);   % dB
            plr_f  = double(ber_f > 0.1);                   % CRC proxy: frame lost if BER>10%

            % Store
            iq_all{end+1}    = iq_f;
            label_all(end+1) = c;
            snr_all(end+1)   = EbNo_list(s);
            ber_all(end+1)   = ber_f;
            rssi_all(end+1)  = rssi_f;
            plr_all(end+1)   = plr_f;

            ber_cfg(end+1) = ber_f;
        end

        fprintf('%-18s %6.1f %8d %10.3e %10.2f\n', ...
            classes{c}, EbNo_list(s), nf, mean(ber_cfg,'omitnan'), ...
            mean(rssi_all(end-nf+1:end)));
    end
end

% Restore default threat
p.active_threat = 'jamming';
params = p; save('params.mat', 'params');

%% ---- Package dataset ----
dataset.iq          = iq_all;          % cell {nSamp x 1} complex per frame
dataset.label       = label_all(:);    % class index (1..7)
dataset.class_names = classes;         % index -> name
dataset.snr         = snr_all(:);      % Eb/No (dB)
dataset.ber         = ber_all(:);
dataset.rssi        = rssi_all(:);
dataset.plr         = plr_all(:);
dataset.meta.frames_per_config = frames_per_config;
dataset.meta.EbNo_list = EbNo_list;
dataset.meta.delay_bits = delay_bits;
dataset.meta.mode = 'single_JSR';
dataset.meta.created = datestr(now);

if ~exist('data', 'dir'); mkdir('data'); end
save('data/dataset.mat', 'dataset', '-v7.3');

%% ---- Summary ----
fprintf('\n=== Dataset Summary ===\n');
fprintf('Total frames : %d\n', numel(label_all));
fprintf('IQ frame size: %d samples\n', numel(iq_all{1}));
fprintf('Elapsed      : %.1f s\n', toc(t_start));
fprintf('\nFrames per class:\n');
for c = 1:numel(classes)
    fprintf('  %-18s %d\n', classes{c}, sum(label_all==c));
end
fprintf('\nSaved to data/dataset.mat\n');