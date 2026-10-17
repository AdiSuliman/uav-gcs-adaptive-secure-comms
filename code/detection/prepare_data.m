%% B1 - PREPARE DATA: split by independent sub-runs, z-score from train
% Every (class, level, Eb/N0) cell has 6 seeded sub-runs (run_dataset_sweep.m):
% sub-runs 1-4 -> train, 5 -> validation, 6 -> test (67/17/17). Frames of one
% sub-run never cross splits, so no fading realization, noise draw or temporal
% window is shared between training and test. Every cell is present in every split.
%
% Input:  data/spectrograms.mat
% Output: data/splits.mat (train/val/test with X, Y (per decision cycle), Y_frame (the frame
%         rule, frame_labels.m), feats, ebno, speed, run, level, and
%         the frame position, per-antenna gains, received Eb/N0 (ebno_rx) and the idle
%         time's records (idle, act_idle, idle_amb) when present; norm stats; norm and
%         classes also as variables of their own, read without the splits, split_norm.m)
% With FRESH_TEST true (build_fresh_test.m): the second test set of data/spectrograms_fresh.mat,
% z-scored with the training statistics of data/splits.mat -> data/splits_fresh.mat
% (test, norm and classes only); with FRESH_SET = 2 as well (B3m) the third test set,
% data/spectrograms_fresh2.mat -> data/splits_fresh2.mat.

close all; clc;
fprintf('=== B1: Prepare Data (split by sub-run) ===\n\n');
if exist('FRESH_TEST', 'var') && FRESH_TEST
    prepare_fresh_test(exist('FRESH_SET', 'var') && isequal(FRESH_SET, 2));
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
    if isfield(sp0, 'Y_frame'), splits.(names{i}).Y_frame = sp0.Y_frame(m); end
    if isfield(sp0, 'pos')
        splits.(names{i}).pos = sp0.pos(m); splits.(names{i}).gain_ant = sp0.gain_ant(m, :);
        splits.(names{i}).feats_raw = sp0.feats(m, :);
    end
    if isfield(sp0, 'k_db'), splits.(names{i}).k_db = sp0.k_db(m); splits.(names{i}).aoa = sp0.aoa(m); end
    splits.(names{i}) = meta_fields(splits.(names{i}), sp0, m);
    if isfield(sp0, 'ebno_rx'), splits.(names{i}).ebno_rx = sp0.ebno_rx(m); end
    splits.(names{i}) = idle_fields(splits.(names{i}), sp0, m);
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
N = struct('norm', splits.norm, 'classes', {classes});
save('data/splits.mat', '-struct', 'N', '-append');
fprintf('Saved data/splits.mat\n=== B1 Complete ===\n');
clear S sp0 splits feats_norm N   % large arrays; main.m runs the stages in one workspace

function prepare_fresh_test(third)
% The second test set (third: the third, B3m): every sub-run in the test fold, the training
% z-score of data/splits.mat.
sfx = ''; name = 'second'; if third, sfx = '2'; name = 'third'; end
S = load(['data/spectrograms_fresh' sfx '.mat']); sp0 = S.spec; clear S
[nm, classes] = split_norm('data/splits.mat');
assert(isequal(categories(sp0.Y), classes(:)), 'prepare_data: the %s test set has other classes', name);
assert(isequal(sp0.feat_names, nm.feat_names), 'prepare_data: the %s test set has other features', name);
assert(all(sp0.fold == 6), 'prepare_data: the %s test set holds sub-runs outside the test fold', name);
splits = struct();
splits.test = struct('X', sp0.X, 'Y', sp0.Y, 'feats', (sp0.feats - nm.feat_mean) ./ nm.feat_std, ...
    'ebno', sp0.ebno, 'speed', sp0.speed_kmh, 'run', sp0.run, 'level', sp0.level);
if isfield(sp0, 'Y_frame'), splits.test.Y_frame = sp0.Y_frame; end
if isfield(sp0, 'pos')
    splits.test.pos = sp0.pos; splits.test.gain_ant = sp0.gain_ant; splits.test.feats_raw = sp0.feats;
end
if isfield(sp0, 'k_db'), splits.test.k_db = sp0.k_db; splits.test.aoa = sp0.aoa; end
splits.test = meta_fields(splits.test, sp0, true(numel(sp0.run), 1));
if isfield(sp0, 'ebno_rx'), splits.test.ebno_rx = sp0.ebno_rx; end
splits.test = idle_fields(splits.test, sp0, true(numel(sp0.run), 1));
splits.norm = nm;
splits.classes = classes;
fprintf('%s test set: %d frames, %d sub-runs\n', [upper(name(1)) name(2:end)], numel(sp0.Y), numel(unique(sp0.run)));
for c = 1:numel(classes)
    fprintf('  %-20s %5d\n', classes{c}, sum(sp0.Y == classes{c}));
end
save(['data/splits_fresh' sfx '.mat'], 'splits', '-v7.3');
fprintf('Saved data/splits_fresh%s.mat\n=== B1 Complete ===\n', sfx);
end

function s = idle_fields(s, sp0, m)
% The idle time's records (the fusion's input, window_cues.m), its on-air share and the
% emitter-of-opportunity records (emitter_reading.m), when the spectrograms carry them.
for f = {'idle', 'act_idle', 'idle_amb', 'bch'}
    if isfield(sp0, f{1}), s.(f{1}) = sp0.(f{1})(m, :); end
end
end

function S = meta_fields(S, sp0, m)
% The flight's altitude, bank, delay spread, the interferers' levels over our signal, the
% class of the frame's sub-run and its roll-in of the frames m, for the analysis only
% (analyze_weak_points.m, roll_in_false_alarms.m), never a detector input.
for f = {'alt_m', 'bank', 'ds_ns', 'lev_db', 'class_run', 'roll_in'}
    if isfield(sp0, f{1}), S.(f{1}) = sp0.(f{1})(m, :); end
end
end
