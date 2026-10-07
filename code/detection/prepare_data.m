%% B1 - PREPARE DATA: split by independent sub-runs, z-score from train
% Every (class, level, Eb/N0) cell has 6 seeded sub-runs (run_dataset_sweep.m):
% sub-runs 1-4 -> train, 5 -> validation, 6 -> test (67/17/17). Frames of one
% sub-run never cross splits, so no fading realization, noise draw or temporal
% window is shared between training and test. Every cell is present in every split.
%
% Input:  data/spectrograms.mat
% Output: data/splits.mat (train/val/test with X, Y, feats, ebno, speed, run, level, and
%         the frame position and per-antenna gains when present; norm stats)
% With FRESH_TEST true (build_fresh_test.m): the second test set of data/spectrograms_fresh.mat,
% z-scored with the training statistics of data/splits.mat -> data/splits_fresh.mat
% (test, norm and classes only).

close all; clc;
fprintf('=== B1: Prepare Data (split by sub-run) ===\n\n');
if exist('FRESH_TEST', 'var') && FRESH_TEST
    prepare_fresh_test();
    return
end
S = load('data/spectrograms.mat');
sp0 = S.spec;
if ~isfield(sp0, 'fold')
    error('spectrograms.mat predates D42. Run run_dataset_sweep and extract_spectrograms first.');
end
classes = categories(sp0.Y);
fold = sp0.fold(:);
ix = struct();
ix.train = ismember(fold, 1:4);
ix.val   = fold == 5;
ix.test  = fold == 6;

feat_mean = mean(sp0.feats(ix.train, :), 1);
feat_std  = std(sp0.feats(ix.train, :), 0, 1);
feat_std(feat_std < 1e-8) = 1;
feats_norm = (sp0.feats - feat_mean) ./ feat_std;

splits = struct();
names = {'train', 'val', 'test'};
for i = 1:3
    m = ix.(names{i});
    splits.(names{i}) = struct('X', sp0.X(:, :, :, m), 'Y', sp0.Y(m), 'feats', feats_norm(m, :), ...
        'ebno', sp0.ebno(m), 'speed', sp0.speed_kmh(m), 'run', sp0.run(m), 'level', sp0.level(m));
    if isfield(sp0, 'pos')
        splits.(names{i}).pos = sp0.pos(m); splits.(names{i}).gain_ant = sp0.gain_ant(m, :);
        splits.(names{i}).feats_raw = sp0.feats(m, :);
    end
    if isfield(sp0, 'k_db'), splits.(names{i}).k_db = sp0.k_db(m); splits.(names{i}).aoa = sp0.aoa(m); end
end
splits.norm = struct('feat_mean', feat_mean, 'feat_std', feat_std, 'feat_names', {sp0.feat_names});
splits.classes = classes;

fprintf('Split: train %d | val %d | test %d frames; sub-runs %d / %d / %d\n', ...
    sum(ix.train), sum(ix.val), sum(ix.test), numel(unique(sp0.run(ix.train))), ...
    numel(unique(sp0.run(ix.val))), numel(unique(sp0.run(ix.test))));
shared = intersect(unique(sp0.run(ix.train)), unique(sp0.run(ix.test)));
fprintf('Sub-runs shared between train and test: %d\n', numel(shared));
fprintf('\n  %-20s %6s %5s %5s\n', 'class', 'train', 'val', 'test');
for c = 1:numel(classes)
    mc = sp0.Y == classes{c};
    fprintf('  %-20s %6d %5d %5d\n', classes{c}, sum(mc & ix.train), sum(mc & ix.val), sum(mc & ix.test));
end
fprintf('\n  feature z-score (train): ');
for f = 1:numel(sp0.feat_names)
    fprintf('%s %.3g/%.3g  ', sp0.feat_names{f}, feat_mean(f), feat_std(f));
end
fprintf('\n');
save('data/splits.mat', 'splits', '-v7.3');
fprintf('Saved data/splits.mat\n=== B1 Complete ===\n');
clear S sp0 splits feats_norm   % large arrays; main.m runs the stages in one workspace

function prepare_fresh_test()
% The second test set: every sub-run in the test fold, the training z-score of data/splits.mat.
S = load('data/spectrograms_fresh.mat'); sp0 = S.spec; clear S
N = load('data/splits.mat', 'splits'); nm = N.splits.norm; classes = N.splits.classes; clear N
assert(isequal(categories(sp0.Y), classes(:)), 'prepare_data: the second test set has other classes');
assert(isequal(sp0.feat_names, nm.feat_names), 'prepare_data: the second test set has other features');
assert(all(sp0.fold == 6), 'prepare_data: the second test set holds sub-runs outside the test fold');
splits = struct();
splits.test = struct('X', sp0.X, 'Y', sp0.Y, 'feats', (sp0.feats - nm.feat_mean) ./ nm.feat_std, ...
    'ebno', sp0.ebno, 'speed', sp0.speed_kmh, 'run', sp0.run, 'level', sp0.level);
if isfield(sp0, 'pos')
    splits.test.pos = sp0.pos; splits.test.gain_ant = sp0.gain_ant; splits.test.feats_raw = sp0.feats;
end
if isfield(sp0, 'k_db'), splits.test.k_db = sp0.k_db; splits.test.aoa = sp0.aoa; end
splits.norm = nm;
splits.classes = classes;
fprintf('Second test set: %d frames, %d sub-runs\n', numel(sp0.Y), numel(unique(sp0.run)));
for c = 1:numel(classes)
    fprintf('  %-20s %5d\n', classes{c}, sum(sp0.Y == classes{c}));
end
save('data/splits_fresh.mat', 'splits', '-v7.3');
fprintf('Saved data/splits_fresh.mat\n=== B1 Complete ===\n');
end
