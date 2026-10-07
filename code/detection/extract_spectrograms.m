%% EXTRACT_SPECTROGRAMS - Phase A6: detector inputs from data/dataset.mat
% Image: spec_image.m (fixed [-40, 40] dB scale). Scalar features: link_features.m
% (receiver measurements), temporal ones over a causal window of 10 frames
% inside each sub-run. The same two functions are used by every closed-loop
% script and the GUI, so training and deployment see identical inputs.
% With FRESH_TEST true (build_fresh_test.m): data/dataset_fresh.mat -> data/spectrograms_fresh.mat.

close all; clc;
f_in = 'data/dataset.mat'; f_out = 'data/spectrograms.mat';
if exist('FRESH_TEST', 'var') && FRESH_TEST, f_in = 'data/dataset_fresh.mat'; f_out = 'data/spectrograms_fresh.mat'; end
if ~exist(f_in, 'file')
    error('%s not found. Run run_dataset_sweep.m first.', f_in);
end
fprintf('Loading %s...\n', f_in);
L = load(f_in); ds = L.dataset;
S = load('params.mat'); p = S.params;
fs = p.symbol_rate * p.sps;
tw = 10;                                  % temporal window [frames]
if ~isfield(ds, 'meas')
    error('dataset.mat predates D59 (no receiver measurements). Run run_dataset_sweep.m first.');
end

N = numel(ds.iq);
X = zeros(128, 128, 1, N, 'single');
fprintf('Extracting %d spectrograms...\n', N);
for i = 1:N
    X(:, :, 1, i) = spec_image(ds.iq{i}, fs);
    if mod(i, 2000) == 0, fprintf('  %d/%d\n', i, N); end
end

fprintf('Computing link features (window %d, per sub-run)...\n', tw);
feat_names = link_features('names');
feats = zeros(N, numel(feat_names));
mf = fieldnames(ds.meas);
runs = unique(ds.run, 'stable');
for r = 1:numel(runs)
    idx = find(ds.run == runs(r));
    M = struct();
    for i = 1:numel(mf), M.(mf{i}) = ds.meas.(mf{i})(idx); end
    for k = 1:numel(idx)
        feats(idx(k), :) = link_features(M, k, tw, p.frame_duration);
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
if isfield(ds, 'pos'), spec.pos = ds.pos(:); spec.gain_ant = ds.gain_ant; end   % temporal evidence
if isfield(ds, 'k_db'), spec.k_db = ds.k_db(:); spec.aoa = ds.aoa(:); end         % analysis only
spec.img_size = 128;
spec.meta = ds.meta;
spec.meta.temporal_window = tw;
save(f_out, 'spec', '-v7.3');

fprintf('\nSaved %s: X [128 128 1 %d], %d classes, feats [%d x %d] (%s)\n', ...
    f_out, N, numel(ds.class_names), N, numel(feat_names), strjoin(feat_names, ', '));
fprintf('%-22s', 'mean per class'); fprintf('%10s', feat_names{:}); fprintf('\n');
for c = 1:numel(ds.class_names)
    fprintf('%-22s', ds.class_names{c}); fprintf('%10.3f', mean(feats(ds.label == c, :), 1)); fprintf('\n');
end
clear X spec ds L   % large arrays; main.m runs the stages in one workspace
