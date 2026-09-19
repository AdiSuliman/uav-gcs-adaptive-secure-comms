%% EXTRACT_SPECTROGRAMS - Phase A6: Convert IQ frames to CNN-ready spectrogram images
% Loads data/dataset.mat, computes a magnitude spectrogram per IQ frame,
% converts to dB, normalizes on a FIXED GLOBAL scale (preserves power differences),
% resizes to img_size x img_size, and computes 7 scalar/temporal features
% (snr, ber, rssi, plr, var_rssi_10, dber_dt, burst_ratio) ready for CNN/LSTM training.
%
% Temporal features (var_rssi_10, dber_dt, burst_ratio) are computed with a
% CAUSAL, RUN-AWARE rolling window: only frames from the SAME contiguous
% (label,level,snr) run as the current frame are used, so no information
% leaks across threat/level/SNR boundaries. First frame(s) of each run fall
% back to whatever history is available within that run (no cross-run bleed).

close all; clc;

if ~exist('data/dataset.mat','file')
    error('data/dataset.mat not found. Run run_dataset_sweep.m first.');
end
fprintf('Loading dataset...\n');
L = load('data/dataset.mat'); ds = L.dataset;
S = load('params.mat'); p = S.params;
fs = p.symbol_rate * p.sps;

% --- Spectrogram + image config ---
img_size = 128;           % CNN input size (square) — quality vs speed balance
win      = 128;           % Hann window
novlp    = 113;           % overlap -> ~128 time frames
nfft     = 128;
db_lo    = -40;           % fixed global dB floor (preserves power differences)
db_hi    =  20;           % fixed global dB ceiling
temporal_window = 10;      % [B2.5] causal window size for var_rssi_10 / burst_ratio

N = numel(ds.iq);
X = zeros(img_size, img_size, 1, N, 'single');   % image tensor
fprintf('Extracting %d spectrograms (%dx%d)...\n', N, img_size, img_size);

for i = 1:N
    iq  = ds.iq{i};
    Sxx = spectrogram(iq, hann(win), novlp, nfft, fs, 'centered');
    P   = 20*log10(abs(Sxx) + eps);          % dB
    P   = (P - db_lo) / (db_hi - db_lo);     % global normalize
    P   = min(max(P, 0), 1);                 % clip [0,1]
    X(:,:,1,i) = imresize(P, [img_size img_size]);
    if mod(i,300)==0, fprintf('  %d/%d\n', i, N); end
end

%% ---- [B2.5] Temporal features: run-aware causal windows ----
fprintf('Computing temporal features (window=%d, run-aware)...\n', temporal_window);

label = ds.label(:);
level = ds.level(:);
snr   = ds.snr(:);
ber   = ds.ber(:);
rssi  = ds.rssi(:);
plr   = ds.plr(:);   % already 0/1 "burst" indicator (ber>0.1) from run_dataset_sweep

% Contiguous run detection — identical logic to build_sequence_index.m,
% so temporal features here are consistent with how sequences are windowed
same_as_prev = false(N,1);
for i = 2:N
    same_as_prev(i) = isequaln(label(i),label(i-1)) && ...
                       isequaln(level(i),level(i-1)) && ...
                       isequaln(snr(i),  snr(i-1));
end
run_id = cumsum(~same_as_prev);

var_rssi_10 = zeros(N,1);
dber_dt     = zeros(N,1);
burst_ratio = zeros(N,1);

run_start_idx = 1;
for i = 1:N
    if i > 1 && run_id(i) ~= run_id(i-1)
        run_start_idx = i;   % new run begins here
    end
    w0 = max(run_start_idx, i - temporal_window + 1);   % causal window, run-clipped

    var_rssi_10(i) = var(rssi(w0:i), 0);                % 0 if window has 1 frame
    burst_ratio(i) = mean(plr(w0:i));

    if i == run_start_idx
        dber_dt(i) = 0;                                  % no prior frame in this run
    else
        dber_dt(i) = (ber(i) - ber(i-1)) / p.frame_duration;
    end
end

% Labels as categorical (CNN-ready)
Y = categorical(ds.label, 1:numel(ds.class_names), ds.class_names);

% Scalar features (for the hybrid branch) — 7 columns
feats = [ds.snr(:), ds.ber(:), ds.rssi(:), ds.plr(:), var_rssi_10, dber_dt, burst_ratio];
feat_names = {'snr','ber','rssi','plr','var_rssi_10','dber_dt','burst_ratio'};

% Package
spec.X          = X;
spec.Y          = Y;
spec.feats      = feats;
spec.feat_names = feat_names;
spec.class_names = ds.class_names;
spec.img_size   = img_size;
spec.meta       = ds.meta;
spec.meta.temporal_window = temporal_window;
spec.meta.temporal_note   = 'var_rssi_10/dber_dt/burst_ratio reconstructed 2026-09 (run-aware causal window=10); verify B2/B3 accuracy still matches historical ~90-91%';

if ~exist('data','dir'); mkdir('data'); end
save('data/spectrograms.mat','spec','-v7.3');

fprintf('\nDone. Saved data/spectrograms.mat\n');
fprintf('  X    : [%d %d 1 %d] single\n', img_size, img_size, N);
fprintf('  Y    : %d labels, %d classes\n', N, numel(ds.class_names));
fprintf('  feats: [%d x %d] (%s)\n', N, numel(feat_names), strjoin(feat_names,', '));