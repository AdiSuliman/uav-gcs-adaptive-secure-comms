%% EVAL_OOD_DETECTION.m - unknown-threat detection, leave-one-threat-out (D32, D42)
% Proposal deliverable (detection of an anomaly / unknown threat) and risk 13.
% For each threat class k the detector is retrained from scratch without k
% (train_hybrid_net.m, same schedule as production), the link features are
% re-normalized on the known classes only, and the feature-space models are
% refitted (fit_ood_model.m). Class k then plays the unknown threat. Scores
% (higher = more like the known classes):
%   MSP     maximum softmax probability (Hendrycks & Gimpel, ICLR 2017)
%   energy  logsumexp of the logits (Liu et al., NeurIPS 2020)
%   Maha    Mahalanobis distance on the 64-d embedding (Lee et al., NeurIPS 2018)
%   iforest isolation forest on the 9 link features (Liu, Ting & Zhou, ICDM 2008)
%   fused   min of the validation-standardized Maha and IF scores
% Reported per held-out class: AUROC and FPR@95%TPR (share of unknown frames
% accepted as known at the threshold that keeps 95% of known validation frames).
% Output: results/ood_detection.{txt,mat}

close all; clc;
fprintf('=== Unknown-threat detection: leave-one-threat-out (D32) ===\n\n');

%% 1. Configuration and data
RETAIN   = 0.95;
N_EPOCHS = 30;                         % as train_detector.m
rng(2026, 'twister');

S = load('data/splits.mat', 'splits');
sp = S.splits;
all_classes = cellstr(string(sp.classes(:)'));
held_out = setdiff(all_classes, {'none'}, 'stable');
T_prod = ood_thresholds(RETAIN);
fprintf('Production detector thresholds (%.0f%% of known validation frames kept): MSP %.3f | energy %.2f\n\n', ...
    100*RETAIN, T_prod.msp, T_prod.energy);

SC = {'msp', 'energy', 'maha', 'iforest', 'fused'};
R = struct('held_out', {}, 'n_ood', {}, 'auroc', {}, 'fpr95', {}, 'id_acc', {}, 'mapped_to', {}, 'same_action', {});

%% 2. One retraining per held-out class
t0 = tic;
for h = 1:numel(held_out)
    k = held_out{h};
    fprintf('[%d/%d] Held-out threat: %s\n', h, numel(held_out), k);
    known = setdiff(all_classes, {k}, 'stable');
    [tr, va, te_id, te_ood] = loto_split(sp, known, k);

    net = train_hybrid_net(tr, va, known, struct('verbose', false));
    M = fit_ood_model(net, tr, known);

    Sv = all_scores(net, M, va);
    Si = all_scores(net, M, te_id);
    So = all_scores(net, M, te_ood);
    [Sv, Si, So] = fuse(Sv, Si, So);

    au = zeros(1, numel(SC)); fp = zeros(1, numel(SC));
    for j = 1:numel(SC)
        thr = lowq(Sv.(SC{j}), 1 - RETAIN);
        au(j) = auroc(Si.(SC{j}), So.(SC{j}));
        fp(j) = mean(So.(SC{j}) >= thr);
    end
    [~, yi] = max(Si.probs, [], 1);
    id_acc = mean(strcmp(known(yi), cellstr(string(te_id.Y(:)'))));
    [~, yo] = max(So.probs, [], 1);
    mapped = known(yo);
    [u, ~, ic] = unique(mapped); [~, im] = max(accumarray(ic(:), 1));
    true_act = rule_based_policy(k);
    same = mean(cellfun(@(c) strcmp(rule_based_policy(c), true_act), mapped));
    R(end+1) = struct('held_out', k, 'n_ood', numel(yo), 'auroc', au, 'fpr95', fp, 'id_acc', id_acc, ...
        'mapped_to', u{im}, 'same_action', same); %#ok<SAGROW>
    ca = [SC; num2cell(au)]; cf = [SC; num2cell(fp)];
    fprintf('    AUROC  %s\n    FPR95  %s\n    known acc %.1f%% (%.1f min)\n\n', ...
        sprintf('%s %.3f  ', ca{:}), sprintf('%s %.2f  ', cf{:}), 100*id_acc, toc(t0)/60);
end

%% 3. Report
A = vertcat(R.auroc); F = vertcat(R.fpr95);
rep = {};
rep{end+1} = '=== UNKNOWN-THREAT DETECTION: LEAVE-ONE-THREAT-OUT (D32, D42) ===';
rep{end+1} = sprintf('Generated: %s | detector retrained without each threat (%d epochs), test split by sub-run', datestr(now), N_EPOCHS);
rep{end+1} = sprintf('AUROC: 0.5 = no separation, 1 = perfect. FPR95: unknown frames accepted as known at the threshold keeping %.0f%% of known validation frames.', 100*RETAIN);
rep{end+1} = '';
hdr = sprintf('%-20s %5s |', 'held-out threat', 'n');
hdr = [hdr sprintf(' %7s', SC{:}) ' |' sprintf(' %7s', SC{:}) sprintf(' | %6s  %-20s %5s', 'known', 'mistaken for', 'same')];
rep{end+1} = sprintf('%s', hdr);
rep{end+1} = sprintf('%-20s %5s |%s |%s', '', '', sprintf(' %7s', 'AUROC', '', '', '', ''), sprintf(' %7s', 'FPR95', '', '', '', ''));
for i = 1:numel(R)
    r = R(i);
    rep{end+1} = sprintf('%-20s %5d |%s |%s | %5.1f%%  %-20s %4.0f%%', r.held_out, r.n_ood, ...
        sprintf(' %7.3f', r.auroc), sprintf(' %7.2f', r.fpr95), 100*r.id_acc, r.mapped_to, 100*r.same_action); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %5s |%s |%s', 'mean', '', sprintf(' %7.3f', mean(A, 1)), sprintf(' %7.2f', mean(F, 1)));
rep{end+1} = '';
[~, jb] = max(mean(A, 1));
rep{end+1} = sprintf('Best score by mean AUROC: %s (%.3f). Production MSP / energy thresholds: %.3f / %.2f.', ...
    SC{jb}, max(mean(A, 1)), T_prod.msp, T_prod.energy);
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/ood_detection.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/ood_detection.mat', 'R', 'SC', 'RETAIN', 'N_EPOCHS', 'T_prod');
fprintf('\nSaved results/ood_detection.{txt,mat} (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function [tr, va, te_id, te_ood] = loto_split(sp, known, k)
% Known-class train/val/test and the held-out test frames; link features
% re-normalized with statistics of the known training frames only.
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
pick = @(P, keep) pick_rows(P, keep, raw(P));
tr = pick(sp.train, known); va = pick(sp.val, known);
te_id = pick(sp.test, known); te_ood = pick(sp.test, {k});
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd; va.feats = (va.feats - mu) ./ sd;
te_id.feats = (te_id.feats - mu) ./ sd; te_ood.feats = (te_ood.feats - mu) ./ sd;
te_ood.Y = categorical(cellstr(string(te_ood.Y(:))));
end

function d = pick_rows(P, keep, F)
y = cellstr(string(P.Y(:)));
m = ismember(y, keep);
d.X = P.X(:, :, :, m);
d.feats = F(m, :);
d.Y = categorical(y(m), keep);
end

function S = all_scores(net, M, P)
[S.probs, ~, S.msp, S.energy] = cnn_scores(net, P.X, P.feats');
[S.maha, S.iforest] = ood_scores(net, M, P.X, P.feats');
end

function [Sv, Si, So] = fuse(Sv, Si, So)
% Standardize Maha and IF with the known validation frames; fused = the lower one.
zm = @(x) (x - mean(Sv.maha)) / std(Sv.maha);
zi = @(x) (x - mean(Sv.iforest)) / std(Sv.iforest);
Sv.fused = min(zm(Sv.maha), zi(Sv.iforest));
Si.fused = min(zm(Si.maha), zi(Si.iforest));
So.fused = min(zm(So.maha), zi(So.iforest));
end

function a = auroc(pos, neg)
% Probability that a known-class frame scores above an unknown one (ties count half).
pos = pos(:); neg = neg(:);
ranks = tiedrank_local([pos; neg]);
np = numel(pos); nn = numel(neg);
a = (sum(ranks(1:np)) - np*(np + 1)/2) / (np * nn);
end

function r = tiedrank_local(x)
[xs, ord] = sort(x(:));
n = numel(xs); r = zeros(n, 1);
i = 1;
while i <= n
    j = i;
    while j < n && xs(j + 1) == xs(i), j = j + 1; end
    r(ord(i:j)) = (i + j) / 2;
    i = j + 1;
end
end

function v = nz(v)
if isnan(v), v = 0; end
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
