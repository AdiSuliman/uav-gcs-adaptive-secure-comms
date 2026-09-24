%% B1-seq — PREPARE SEQUENCE DATA: Load, Normalize, RUN-LEVEL Stratified Split
% Loads data/spectrograms_seq.mat (from extract_spectrograms_seq.m), z-scores
% the 7 scalar/temporal features (train stats only, pooled across all
% timesteps in a sequence).
%
% SPLIT IS RUN-LEVEL, NOT WINDOW-LEVEL: with seq_stride < seq_len, windows
% from the SAME contiguous run overlap in frames. A window-level random split
% would let overlapping frames leak across train/val/test. Instead, every
% window is tagged with the run_id it came from (build_sequence_index.m),
% and splitting happens at the RUN level -- all windows from one run go to
% the same split.
%
% MANUAL PER-CLASS SPLIT (not cvpartition): 'none' has only ~6 runs (one per
% SNR -- it has no level dimension, unlike every threat class's 5 levels x 6
% SNR = 30 runs). cvpartition's stratified holdout can silently assign a
% minority class ZERO runs to val/test when its run count is this small
% (confirmed: 'none' got 0 test windows on 2026-09-15 with cvpartition).
% This version guarantees >=1 run per class in val AND test whenever the
% class has >=3 runs total, by splitting each class's own run list
% independently rather than delegating to a single global stratified call.
%
% Input:  data/spectrograms_seq.mat (X_seq, feats_seq, Y_seq)
%         data/dataset_seq_index.mat (run_id per window)
% Output: data/splits_seq.mat (train/val/test structs + norm stats)

close all; clc;
fprintf('=== B1-seq: Prepare Sequence Data (run-level split, per-class guaranteed) ===\n\n');

if ~exist('data/spectrograms_seq.mat','file')
    error('data/spectrograms_seq.mat not found. Run extract_spectrograms_seq.m first.');
end
if ~exist('data/dataset_seq_index.mat','file')
    error('data/dataset_seq_index.mat not found. Run build_sequence_index.m first.');
end
fprintf('Loading spectrograms_seq.mat and dataset_seq_index.mat...\n');
S = load('data/spectrograms_seq.mat');
spec_seq = S.spec_seq;
Si = load('data/dataset_seq_index.mat');
dsi = Si.dataset_seq_index;

if ~isfield(dsi, 'run_id')
    error(['dataset_seq_index.run_id not found. Rerun the UPDATED build_sequence_index.m ' ...
           '(and then extract_spectrograms_seq.m) to regenerate it with run_id included.']);
end

X_seq      = spec_seq.X_seq;       % [128 128 1 seq_len N]
feats_seq  = spec_seq.feats_seq;   % [N seq_len nFeat]
Y_seq      = spec_seq.Y_seq;       % [N x 1] categorical
feat_names = spec_seq.feat_names;
seq_len    = spec_seq.seq_len;
run_id     = dsi.run_id(:);        % [N x 1]

feats_seq(isnan(feats_seq)) = 0;

N = numel(Y_seq);
nFeat = size(feats_seq, 3);
classes = categories(Y_seq);
nClasses = numel(classes);
fprintf('  Loaded %d sequences, seq_len=%d, %d classes, feats [%d x %d x %d]\n', ...
    N, seq_len, nClasses, size(feats_seq,1), seq_len, nFeat);
fprintf('  Feature columns: %s\n', strjoin(feat_names, ', '));

if numel(run_id) ~= N
    error('run_id length (%d) does not match number of sequences (%d) -- dataset_seq_index.mat and spectrograms_seq.mat are out of sync. Rerun extract_spectrograms_seq.m.', ...
        numel(run_id), N);
end

%% 2. Manual per-class run-level split (guarantees representation in every split)
unique_runs = unique(run_id);
n_runs = numel(unique_runs);
Y_seq_double = double(Y_seq);   % categorical -> numeric class index

% Map each run to its class (every run is homogeneous by construction)
run_class = zeros(n_runs, 1);
for i = 1:n_runs
    windows_this_run = find(run_id == unique_runs(i));
    run_class(i) = Y_seq_double(windows_this_run(1));
end

fprintf('  %d unique runs across %d windows\n', n_runs, N);
fprintf('\n  Runs per class (imbalance check -- ''none'' is expected to have far fewer,\n');
fprintf('  since it has no level dimension in run_dataset_sweep.m, unlike threat classes):\n');
for c = 1:nClasses
    n_runs_c = sum(run_class == c);
    fprintf('    %-22s %d runs\n', classes{c}, n_runs_c);
end

rng(42, 'twister');  % same seed as B1/prepare_data.m, for consistency

train_runs = []; val_runs = []; test_runs = [];

for c = 1:nClasses
    runs_c = unique_runs(run_class == c);
    n_c = numel(runs_c);
    runs_c = runs_c(randperm(n_c));   % shuffle within this class

    if n_c >= 3
        n_val_c  = max(1, round(0.10 * n_c));
        n_test_c = max(1, round(0.10 * n_c));
        % Guard against rounding eating the whole class when n_c is small
        if n_val_c + n_test_c >= n_c
            n_val_c  = 1;
            n_test_c = 1;
        end
        n_train_c = n_c - n_val_c - n_test_c;
    else
        % Fewer than 3 runs total: can't give every split >=1, so
        % everything goes to train and val/test get nothing for this class.
        % (Not expected to occur with this dataset -- flagged if it does.)
        fprintf('    WARNING: class %s has only %d run(s) -- cannot guarantee val/test representation.\n', ...
            classes{c}, n_c);
        n_train_c = n_c; n_val_c = 0; n_test_c = 0;
    end

    train_runs = [train_runs; runs_c(1:n_train_c)]; %#ok<AGROW>
    val_runs   = [val_runs;   runs_c(n_train_c+1 : n_train_c+n_val_c)]; %#ok<AGROW>
    test_runs  = [test_runs;  runs_c(n_train_c+n_val_c+1 : end)]; %#ok<AGROW>
end

idx_train = ismember(run_id, train_runs);
idx_val   = ismember(run_id, val_runs);
idx_test  = ismember(run_id, test_runs);

% Sanity checks
assert(isempty(intersect(train_runs, val_runs)),  'BUG: train/val run overlap');
assert(isempty(intersect(train_runs, test_runs)), 'BUG: train/test run overlap');
assert(isempty(intersect(val_runs, test_runs)),   'BUG: val/test run overlap');
for c = 1:nClasses
    n_test_c = sum(Y_seq_double(idx_test) == c);
    if n_test_c == 0
        warning('Class %s has ZERO windows in the test split.', classes{c});
    end
end

fprintf('\n  Split (run-level, per-class guaranteed): train=%d runs/%d windows (%.0f%%) | val=%d runs/%d windows (%.0f%%) | test=%d runs/%d windows (%.0f%%)\n', ...
    numel(train_runs), sum(idx_train), 100*mean(idx_train), ...
    numel(val_runs),   sum(idx_val),   100*mean(idx_val), ...
    numel(test_runs),  sum(idx_test),  100*mean(idx_test));
fprintf('  Verified: zero runs shared between splits -- no overlapping-window leakage.\n');

%% 3. Normalize scalar features (z-score from train, pooled across timesteps)
train_feats_flat = reshape(feats_seq(idx_train,:,:), [], nFeat);
feat_mean = mean(train_feats_flat, 1);
feat_std  = std(train_feats_flat, 0, 1);
feat_std(feat_std < 1e-8) = 1;

feats_norm = (feats_seq - reshape(feat_mean,1,1,nFeat)) ./ reshape(feat_std,1,1,nFeat);

fprintf('  Feature normalization (z-score, pooled over train sequences x timesteps):\n');
for f = 1:nFeat
    fprintf('    %s: mean=%.3f, std=%.3f\n', feat_names{f}, feat_mean(f), feat_std(f));
end

%% 4. Verify balance per split
fprintf('\n  Class balance check:\n');
fprintf('  %-20s  %6s  %5s  %5s\n', 'Class', 'Train', 'Val', 'Test');
for c = 1:nClasses
    mask = Y_seq == classes{c};
    fprintf('  %-20s  %6d  %5d  %5d\n', classes{c}, ...
        sum(mask & idx_train), sum(mask & idx_val), sum(mask & idx_test));
end

%% 5. Package and save
splits_seq = struct();

splits_seq.train.X     = X_seq(:,:,:,:,idx_train);
splits_seq.train.Y     = Y_seq(idx_train);
splits_seq.train.feats = feats_norm(idx_train,:,:);

splits_seq.val.X       = X_seq(:,:,:,:,idx_val);
splits_seq.val.Y       = Y_seq(idx_val);
splits_seq.val.feats   = feats_norm(idx_val,:,:);

splits_seq.test.X      = X_seq(:,:,:,:,idx_test);
splits_seq.test.Y      = Y_seq(idx_test);
splits_seq.test.feats  = feats_norm(idx_test,:,:);

splits_seq.norm.feat_mean  = feat_mean;
splits_seq.norm.feat_std   = feat_std;
splits_seq.norm.feat_names = feat_names;
splits_seq.classes = classes;
splits_seq.seq_len = seq_len;
splits_seq.meta.split_method = 'per-class run-level (manual, guarantees >=1 run/class in val+test)';
splits_seq.meta.n_runs = n_runs;

fprintf('\nSaving data/splits_seq.mat...\n');
save('data/splits_seq.mat', 'splits_seq', '-v7.3');
d = dir('data/splits_seq.mat');
fprintf('Done. splits_seq.mat saved (%.1f MB)\n', d.bytes/1e6);
fprintf('  train.X: [%s] | train.feats: [%s]\n', ...
    strjoin(string(size(splits_seq.train.X)), ' x '), ...
    strjoin(string(size(splits_seq.train.feats)), ' x '));
fprintf('  val.X:   [%s]\n', strjoin(string(size(splits_seq.val.X)),   ' x '));
fprintf('  test.X:  [%s]\n', strjoin(string(size(splits_seq.test.X)),  ' x '));
fprintf('\n=== B1-seq Complete ===\n');