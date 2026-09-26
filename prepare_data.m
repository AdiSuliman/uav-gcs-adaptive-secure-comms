%% B1 - PREPARE DATA: split by independent sub-runs, z-score from train (D42)
% Every (class, level, Eb/N0) cell has 5 seeded sub-runs (run_dataset_sweep.m):
% sub-runs 1-3 -> train, 4 -> validation, 5 -> test (60/20/20). Frames of one
% sub-run never cross splits, so no fading realization, noise draw or temporal
% window is shared between training and test. Every cell is present in every split.
%
% Input:  data/spectrograms.mat
% Output: data/splits.mat (train/val/test with X, Y, feats, ebno, speed, run, level; norm stats)

close all; clc;
fprintf('=== B1: Prepare Data (split by sub-run) ===\n\n');
S = load('data/spectrograms.mat');
sp0 = S.spec;
if ~isfield(sp0, 'fold')
    error('spectrograms.mat predates D42. Run run_dataset_sweep and extract_spectrograms first.');
end
classes = categories(sp0.Y);
fold = sp0.fold(:);
ix = struct();
ix.train = ismember(fold, 1:3);
ix.val   = fold == 4;
ix.test  = fold == 5;

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
