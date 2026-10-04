%% B2F - SELECT_FUSION: temporal fusion of the detector over the last decision cycles
% The per-frame detector decides on 0.5 ms of signal; the fusion
% (temporal_evidence.m, fuse_classes.m) decides on the last N cycles. It is fitted
% on the validation split, where the detector's outputs are not overconfident, and
% N and the regularization are chosen by cross-validation over the validation
% sub-runs (5 folds by sub-run, highest macro-F1). The fused decision is judged on its
% window (fusion_target.m: a WLAN frame without a packet whose window holds packet
% frames has the target benign_interference; the per-frame label stays). The
% out-of-fold predictions and their targets are kept for the KPI 1 threshold of
% eval_detector.m.
% The quiet-slot interference alarm of the rule (rule_based_policy.m) is set here from
% the clean validation frames (the sub-runs without a threat), as an AGC jamming monitor
% sets its threshold from interference-free samples, Th = mu - 3 sigma - 2 dB for a gain
% drop (Kazim et al. 2026, eq. 1.3, p. 2); the slot's power rises instead, so
% q_thr = mu + 3 sigma + 2 dB of q_iot. The test split is not used.
% Output: data/fusion.mat (FM, N, lambda, cv table, out-of-fold probabilities and their
% targets, q_thr)

close all; clc;
fprintf('=== B2F: temporal fusion (validation split only) ===\n\n');
S = load('data/splits.mat'); va = S.splits.val; norm = S.splits.norm;
if ~isfield(va, 'pos')
    error('splits.mat has no frame positions (v6 dataset). Run run_dataset_sweep, extract_spectrograms, prepare_data.');
end
va.feat_names = norm.feat_names;
D = load('data/trained_detector.mat', 'net', 'classes');
C = numel(D.classes);
classes = cellstr(string(D.classes(:)'));
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
    yn = fusion_target(y, va.run, va.pos, NS(a), classes);
    for b = 1:numel(LAMBDA)
        pc = zeros(numel(y), C);
        for k = 1:K
            tr = fold ~= k; te = fold == k;
            FM = fuse_classes('fit', Z(tr, :), yn(tr), C, LAMBDA(b));
            pc(te, :) = fuse_classes('apply', FM, Z(te, :));
        end
        [~, yh] = max(pc, [], 2);
        cv(a, b) = macro_f1(yn, yh, C);
        oof{a, b} = pc;
        fprintf('  N = %2d cycles, lambda %.0e: macro-F1 %.2f%% (out of fold)\n', NS(a), LAMBDA(b), 100 * cv(a, b));
    end
end
[~, i] = max(cv(:)); [a, b] = ind2sub(size(cv), i);
N = NS(a); lambda = LAMBDA(b);
Z = fuse_classes('windows', va, P, N);
val_target = fusion_target(y, va.run, va.pos, N, classes);
FM = fuse_classes('fit', Z, val_target, C, lambda);
[~, y1] = max(P, [], 2);
fprintf('\nSelected N = %d cycles, lambda %.0e: macro-F1 %.2f%% out of fold (per frame %.2f%%)\n', ...
    N, lambda, 100 * cv(a, b), 100 * macro_f1(y, y1, C));
fprintf('WLAN frames without a packet judged by their window as benign_interference: %d of %d none frames\n', ...
    sum(val_target ~= y), sum(y == find(strcmp(classes, 'none'))));
val_probs_oof = oof{a, b};
qi = va.feats_raw(isnan(va.level), strcmp(va.feat_names, 'q_iot'));
q_thr = mean(qi) + 3 * std(qi) + 2;
fprintf('Quiet-slot interference alarm: %.2f dB over thermal (clean frames: mean %.2f, std %.2f dB, n = %d)\n', ...
    q_thr, mean(qi), std(qi), numel(qi));
if ~exist('results', 'dir'), mkdir('results'); end
save('data/fusion.mat', 'FM', 'N', 'lambda', 'NS', 'LAMBDA', 'cv', 'val_probs_oof', 'val_target', 'q_thr');
fprintf('Saved data/fusion.mat\n');

function m = macro_f1(y, yh, C)
f = zeros(1, C);
for c = 1:C
    tp = sum(yh == c & y == c); fp = sum(yh == c & y ~= c); fn = sum(yh ~= c & y == c);
    f(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
m = mean(f);
end
