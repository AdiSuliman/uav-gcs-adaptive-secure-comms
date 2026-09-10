%% EXTRACT_SPECTROGRAMS - Phase A6: Convert IQ frames to CNN-ready spectrogram images
% Loads data/dataset.mat, computes a magnitude spectrogram per IQ frame,
% converts to dB, normalizes on a FIXED GLOBAL scale (preserves power differences),
% resizes to img_size x img_size, and saves an image tensor + labels + scalar
% features ready for CNN/LSTM training. Global norm keeps none vs path_loss distinct.

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

% Labels as categorical (CNN-ready)
Y = categorical(ds.label, 1:numel(ds.class_names), ds.class_names);

% Scalar features (for the hybrid branch)
feats = [ds.snr, ds.ber, ds.rssi, ds.plr];
feat_names = {'snr','ber','rssi','plr'};

% Package
spec.X          = X;
spec.Y          = Y;
spec.feats      = feats;
spec.feat_names = feat_names;
spec.class_names = ds.class_names;
spec.img_size   = img_size;
spec.meta       = ds.meta;

if ~exist('data','dir'); mkdir('data'); end
save('data/spectrograms.mat','spec','-v7.3');

fprintf('\nDone. Saved data/spectrograms.mat\n');
fprintf('  X    : [%d %d 1 %d] single\n', img_size, img_size, N);
fprintf('  Y    : %d labels, %d classes\n', N, numel(ds.class_names));
fprintf('  feats: [%d x %d] (%s)\n', N, numel(feat_names), strjoin(feat_names,', '));