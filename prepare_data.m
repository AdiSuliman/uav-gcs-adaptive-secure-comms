%% B1 — PREPARE DATA: Load, Normalize, Stratified Split
% Loads spectrograms.mat, z-scores scalar features (train stats only),
% splits 80/10/10 stratified by class × SNR bin, saves splits.mat.
%
% Input:  data/spectrograms.mat  (X, Y, feats — now [N×7] after B2.5:
%         snr, ber, rssi, plr, var_rssi_10, dber_dt, burst_ratio)
% Output: data/splits.mat        (train/val/test structs + norm stats)

close all; clc;
fprintf('=== B1: Prepare Data ===\n\n');

%% 1. Load
fprintf('Loading spectrograms.mat...\n');
S = load('data/spectrograms.mat');
X      = S.spec.X;          % [128 128 1 N] single — spectrograms
Y      = S.spec.Y;          % [N×1] categorical — class labels
feats  = S.spec.feats;      % [N×nFeat] double
feats(isnan(feats)) = 0;    % 0 errors → BER=0, not NaN; also guards new temporal feats

nFeat = size(feats, 2);
feat_names = S.spec.feat_names;

N = size(X, 4);
classes = categories(Y);
nClasses = numel(classes);
fprintf('  Loaded %d frames, %d classes, feats [%d × %d]\n', ...
    N, nClasses, size(feats,1), nFeat);
fprintf('  Feature columns: %s\n', strjoin(feat_names, ', '));

%% 2. Stratified split by class × SNR bin
snr_col = feats(:,1);  % first column is always SNR
snr_edges = [-inf, 1, 3, 5, 7, 9, inf];  % splits 0,2,4,6,8,10
snr_bin   = discretize(snr_col, snr_edges);

strat_key = strings(N, 1);
for i = 1:N
    strat_key(i) = string(Y(i)) + "_" + string(snr_bin(i));
end

rng(42, 'twister');  % reproducibility

cv1 = cvpartition(strat_key, 'HoldOut', 0.2);
idx_train = training(cv1);
idx_rest  = test(cv1);

strat_rest = strat_key(idx_rest);
cv2 = cvpartition(strat_rest, 'HoldOut', 0.5);

rest_indices = find(idx_rest);
idx_val  = false(N,1);  idx_val(rest_indices(training(cv2)))  = true;
idx_test = false(N,1);  idx_test(rest_indices(test(cv2)))     = true;

fprintf('  Split: train=%d (%.0f%%) | val=%d (%.0f%%) | test=%d (%.0f%%)\n', ...
    sum(idx_train), 100*mean(idx_train), ...
    sum(idx_val),   100*mean(idx_val), ...
    sum(idx_test),  100*mean(idx_test));

%% 3. Normalize scalar features (z-score on train only)
feat_mean = mean(feats(idx_train, :), 1);
feat_std  = std(feats(idx_train, :), 0, 1);
feat_std(feat_std < 1e-8) = 1;

feats_norm = (feats - feat_mean) ./ feat_std;

fprintf('  Feature normalization (z-score from train set):\n');
for f = 1:nFeat
    fprintf('    %s: mean=%.3f, std=%.3f\n', feat_names{f}, feat_mean(f), feat_std(f));
end

%% 4. Verify balance per split
fprintf('\n  Class balance check:\n');
fprintf('  %-20s  %6s  %5s  %5s\n', 'Class', 'Train', 'Val', 'Test');
for c = 1:nClasses
    mask = Y == classes{c};
    fprintf('  %-20s  %6d  %5d  %5d\n', classes{c}, ...
        sum(mask & idx_train), sum(mask & idx_val), sum(mask & idx_test));
end

%% 5. Package and save
splits = struct();

splits.train.X     = X(:,:,:,idx_train);
splits.train.Y     = Y(idx_train);
splits.train.feats = feats_norm(idx_train, :);

splits.val.X       = X(:,:,:,idx_val);
splits.val.Y       = Y(idx_val);
splits.val.feats   = feats_norm(idx_val, :);

splits.test.X      = X(:,:,:,idx_test);
splits.test.Y      = Y(idx_test);
splits.test.feats  = feats_norm(idx_test, :);

splits.norm.feat_mean = feat_mean;
splits.norm.feat_std  = feat_std;
splits.norm.feat_names = feat_names;
splits.classes = classes;

fprintf('\nSaving data/splits.mat...\n');
save('data/splits.mat', 'splits', '-v7.3');
d = dir('data/splits.mat');
fprintf('Done. splits.mat saved (%.1f MB)\n', d.bytes/1e6);
fprintf('  train.X: [%s] | train.feats: [%s]\n', ...
    strjoin(string(size(splits.train.X)), ' × '), ...
    strjoin(string(size(splits.train.feats)), ' × '));
fprintf('  val.X:   [%s]\n', strjoin(string(size(splits.val.X)),   ' × '));
fprintf('  test.X:  [%s]\n', strjoin(string(size(splits.test.X)),  ' × '));
fprintf('\n=== B1 Complete ===\n');