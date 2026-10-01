%% B2F - SELECT_FUSION: temporal fusion of the detector over the last decision cycles
% The per-frame detector decides on 0.5 ms of signal; the fusion
% (temporal_evidence.m, fuse_classes.m) decides on the last N cycles. It is fitted
% on the validation split, where the detector's outputs are not overconfident, and
% N and the regularization are chosen by cross-validation over the validation
% sub-runs (5 folds by sub-run, highest macro-F1). The out-of-fold predictions are
% kept for the KPI 1 threshold of eval_detector.m. The test split is not used.
% Output: data/fusion.mat (FM, N, lambda, cv table, out-of-fold probabilities)

close all; clc;
fprintf('=== B2F: temporal fusion (validation split only) ===\n\n');
S = load('data/splits.mat'); va = S.splits.val; norm = S.splits.norm;
if ~isfield(va, 'pos')
    error('splits.mat has no frame positions (v6 dataset). Run run_dataset_sweep, extract_spectrograms, prepare_data.');
end
va.feat_names = norm.feat_names;
D = load('data/trained_detector.mat', 'net', 'classes');
C = numel(D.classes);
P = cnn_scores(D.net, va.X, va.feats')';                 % frames x C
y = double(va.Y(:));
NS = [1 3 5 8 12];
LAMBDA = [1e-4 1e-3 1e-2];
K = 5;
runs = unique(va.run);
rs = RandStream('mt19937ar', 'Seed', 61);
fold_of_run = mod(randperm(rs, numel(runs)), K) + 1;
[~, ir] = ismember(va.run, runs);
fold = fold_of_run(ir)';

cv = zeros(numel(NS), numel(LAMBDA)); oof = cell(numel(NS), numel(LAMBDA));
for a = 1:numel(NS)
    Z = fuse_classes('windows', va, P, NS(a));
    for b = 1:numel(LAMBDA)
        pc = zeros(numel(y), C);
        for k = 1:K
            tr = fold ~= k; te = fold == k;
            FM = fuse_classes('fit', Z(tr, :), y(tr), C, LAMBDA(b));
            pc(te, :) = fuse_classes('apply', FM, Z(te, :));
        end
        [~, yh] = max(pc, [], 2);
        cv(a, b) = macro_f1(y, yh, C);
        oof{a, b} = pc;
        fprintf('  N = %2d cycles, lambda %.0e: macro-F1 %.2f%% (out of fold)\n', NS(a), LAMBDA(b), 100 * cv(a, b));
    end
end
[~, i] = max(cv(:)); [a, b] = ind2sub(size(cv), i);
N = NS(a); lambda = LAMBDA(b);
Z = fuse_classes('windows', va, P, N);
FM = fuse_classes('fit', Z, y, C, lambda);
[~, y1] = max(P, [], 2);
fprintf('\nSelected N = %d cycles, lambda %.0e: macro-F1 %.2f%% out of fold (per frame %.2f%%)\n', ...
    N, lambda, 100 * cv(a, b), 100 * macro_f1(y, y1, C));
val_probs_oof = oof{a, b};
if ~exist('results', 'dir'), mkdir('results'); end
save('data/fusion.mat', 'FM', 'N', 'lambda', 'NS', 'LAMBDA', 'cv', 'val_probs_oof');
fprintf('Saved data/fusion.mat\n');

function m = macro_f1(y, yh, C)
f = zeros(1, C);
for c = 1:C
    tp = sum(yh == c & y == c); fp = sum(yh == c & y ~= c); fn = sum(yh ~= c & y == c);
    f(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
m = mean(f);
end
