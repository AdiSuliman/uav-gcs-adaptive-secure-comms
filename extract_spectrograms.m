%% EXTRACT_SPECTROGRAMS - Phase A6: detector inputs from data/dataset.mat (D42)
% Image: spec_image.m (fixed [-40, 40] dB scale). Scalar features: link_features.m
% (8 features), temporal ones over a causal window of 10 frames inside each
% sub-run. The same two functions are used by every closed-loop script and the
% GUI, so training and deployment see identical inputs.

close all; clc;
if ~exist('data/dataset.mat', 'file')
    error('data/dataset.mat not found. Run run_dataset_sweep.m first.');
end
fprintf('Loading dataset...\n');
L = load('data/dataset.mat'); ds = L.dataset;
S = load('params.mat'); p = S.params;
fs = p.symbol_rate * p.sps;
tw = 10;                                  % temporal window [frames]
if ~isfield(ds, 'run')
    error('dataset.mat predates D42 (no sub-run ids). Run run_dataset_sweep.m first.');
end

N = numel(ds.iq);
X = zeros(128, 128, 1, N, 'single');
fprintf('Extracting %d spectrograms...\n', N);
for i = 1:N
    X(:, :, 1, i) = spec_image(ds.iq{i}, fs);
    if mod(i, 2000) == 0, fprintf('  %d/%d\n', i, N); end
end

fprintf('Computing link features (window %d, per sub-run)...\n', tw);
feats = zeros(N, 8);
runs = unique(ds.run, 'stable');
for r = 1:numel(runs)
    idx = find(ds.run == runs(r));
    M = struct('sinr', ds.sinr(idx), 'ber', ds.ber(idx), 'rssi', ds.rssi(idx), ...
        'plr', ds.plr(idx), 'env_corr', ds.env_corr(idx));
    for k = 1:numel(idx)
        [feats(idx(k), :), feat_names] = link_features(M, k, tw, p.frame_duration);
    end
end

spec = struct();
spec.X = X;
spec.Y = categorical(ds.label, 1:numel(ds.class_names), ds.class_names);
spec.feats = feats;
spec.feat_names = feat_names;
spec.class_names = ds.class_names;
spec.ebno = ds.snr(:);                    % configured Eb/N0, analysis only (not an input)
spec.speed_kmh = ds.speed_kmh(:);
spec.run = ds.run(:); spec.fold = ds.fold(:); spec.level = ds.level(:);
spec.img_size = 128;
spec.meta = ds.meta;
spec.meta.temporal_window = tw;
save('data/spectrograms.mat', 'spec', '-v7.3');

fprintf('\nSaved data/spectrograms.mat: X [128 128 1 %d], %d classes, feats [%d x 8] (%s)\n', ...
    N, numel(ds.class_names), N, strjoin(feat_names, ', '));
fprintf('Envelope correlation per class (mean): ');
for c = 1:numel(ds.class_names)
    fprintf('%s %.3f  ', ds.class_names{c}, mean(feats(ds.label == c, 8)));
end
fprintf('\n');
clear X spec ds L   % large arrays; main.m runs the stages in one workspace
