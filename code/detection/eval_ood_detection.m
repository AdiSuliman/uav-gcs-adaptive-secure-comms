%% EVAL_OOD_DETECTION.m - unknown-threat detection, leave-one-threat-out
% Proposal deliverable 4 (alert on a threat not seen in training) and the leave-one-threat-out KPI.
% For each threat class k the detector is retrained from scratch without k
% (train_hybrid_net.m, same schedule as production), the link features are
% re-normalized on the known classes only, and the unknown-threat models are
% refitted (fit_ood_model.m). Class k then plays the unknown threat. Scores
% (higher = more like the known classes):
%   msp, energy   maximum softmax probability and logsumexp of the logits: baselines
%   iforest       isolation forest on the link features alone (Liu, Ting & Zhou)
%   candidates of the production score (ood_score_set.m): last, ensemble, raw,
%                 last_or_raw, last_or_if
% The held-out threat is never used to fit, weight or choose anything inside its
% fold. Reported per held-out threat: AUROC, and FPR@95%TPR (share of unknown
% frames accepted as known at the threshold that keeps 95% of known validation
% frames); every candidate also averaged over the last 2, 5 and 8 decision cycles
% of a run (one frame per cycle).
% Selection: the production score and its window are the (candidate, window) pair
% with the highest mean AUROC over the held-out threats; they are written to
% data/trained_detector.mat (ood.score, ood.win) and the thresholds are recomputed,
% so this stage runs before the frame pools (C1p). Because the choice uses the same
% folds, the value to quote is the nested estimate: for each held-out threat, the
% pair chosen on the OTHER threats, scored on this one.
% Learning the new threat (Lee et al., Algorithm 2): once flagged and labelled, the
% held-out threat is added as a new class from K of its validation frames (never
% used in the fold) by its mean and an update of the tied covariance in the last
% hidden layer, without retraining the network; its test frames are then
% classified by the smallest Mahalanobis distance (K = 100 random frames, 5 draws,
% and all of them), and the known classes are checked for the cost.
% Output: results/ood_detection.{txt,mat}

close all; clc;
fprintf('=== Unknown-threat detection: leave-one-threat-out ===\n\n');

%% 1. Configuration and data
RETAIN   = 0.95;
N_EPOCHS = 30;                         % as train_detector.m
WIN      = [2 5 8];                    % decision cycles of the averaged score
rng(2026, 'twister');

S = load('data/splits.mat', 'splits');
sp = S.splits;
all_classes = cellstr(string(sp.classes(:)'));
held_out = setdiff(all_classes, {'none'}, 'stable');
if exist('SMOKE', 'var') && SMOKE, held_out = held_out(1:2); N_EPOCHS = 3; end   % reduced chain check
D0 = load('data/trained_detector.mat', 'ood');
CAND = D0.ood.candidates;
SC = [{'msp', 'energy', 'iforest'}, CAND];
R = struct('held_out', {}, 'n_ood', {}, 'auroc', {}, 'fpr95', {}, 'auroc_win', {}, 'id_acc', {}, ...
    'mapped_to', {}, 'same_action', {}, 'incr', {});
K_NEW = 100; N_DRAW = 5;               % Algorithm 2: frames of the new threat, random draws

%% 2. One retraining per held-out class
t0 = tic;
for h = 1:numel(held_out)
    k = held_out{h};
    fprintf('[%d/%d] Held-out threat: %s\n', h, numel(held_out), k);
    known = setdiff(all_classes, {k}, 'stable');
    [tr, va, te_id, te_ood, vk] = loto_split(sp, known, k);

    net = train_hybrid_net(tr, va, known, struct('verbose', false, 'epochs', N_EPOCHS));
    M = fit_ood_model(net, tr, known, va);

    Sv = all_scores(net, M, va);
    Si = all_scores(net, M, te_id);
    So = all_scores(net, M, te_ood);

    au = zeros(1, numel(SC)); fp = zeros(1, numel(SC)); aw = zeros(numel(SC), numel(WIN));
    for j = 1:numel(SC)
        thr = lowq(Sv.(SC{j}), 1 - RETAIN);
        au(j) = auroc(Si.(SC{j}), So.(SC{j}));
        fp(j) = mean(So.(SC{j}) >= thr);
        for w = 1:numel(WIN)
            aw(j, w) = auroc(win_mean(Si.(SC{j}), te_id.run, WIN(w)), win_mean(So.(SC{j}), te_ood.run, WIN(w)));
        end
    end
    [~, yi] = max(Si.probs, [], 1);
    id_acc = mean(strcmp(known(yi), cellstr(string(te_id.Y(:)'))));
    [~, yo] = max(So.probs, [], 1);
    mapped = known(yo);
    [u, ~, ic] = unique(mapped); [~, im] = max(accumarray(ic(:), 1));
    true_act = rule_based_policy(k);
    same = mean(cellfun(@(c) strcmp(rule_based_policy(c), true_act), mapped));
    inc = learn_new_class(net, M, te_id, te_ood, vk, K_NEW, N_DRAW);
    R(end+1) = struct('held_out', k, 'n_ood', numel(yo), 'auroc', au, 'fpr95', fp, 'auroc_win', aw, ...
        'id_acc', id_acc, 'mapped_to', u{im}, 'same_action', same, 'incr', inc); %#ok<SAGROW>
    ca = [SC; num2cell(au)];
    fprintf('    AUROC  %s\n    known acc %.1f%% | learned from %d frames: new threat %.1f%%, known %.1f%% (%.1f min)\n\n', ...
        sprintf('%s %.3f  ', ca{:}), 100*id_acc, K_NEW, 100*inc.new_k, 100*inc.known_k, toc(t0)/60);
end

%% 3. Selection of the production score, nested estimate
A = vertcat(R.auroc); F = vertcat(R.fpr95);
AW = cat(3, R.auroc_win);                               % scores x windows x held-out threats
jc = find(ismember(SC, CAND));
Mp = zeros(numel(R), numel(jc) * (1 + numel(WIN))); pj = zeros(1, size(Mp, 2)); pw = pj;
c = 0;
for j = jc                                              % (candidate, window) pairs; window 1 = the frame alone
    for w = [1 WIN]
        c = c + 1; pj(c) = j; pw(c) = w;
        if w == 1, Mp(:, c) = A(:, j); else, Mp(:, c) = squeeze(AW(j, WIN == w, :)); end
    end
end
[~, b] = max(mean(Mp, 1)); sel = SC{pj(b)}; sel_win = pw(b);
NEST = struct('auroc', zeros(1, numel(R)), 'pick', {cell(1, numel(R))});
for i = 1:numel(R)
    [~, b2] = max(mean(Mp(setdiff(1:numel(R), i), :), 1));
    NEST.auroc(i) = Mp(i, b2); NEST.pick{i} = sprintf('%s over %d', SC{pj(b2)}, pw(b2));
end
if ~(exist('SMOKE', 'var') && SMOKE)
    D = load('data/trained_detector.mat', 'ood'); ood = D.ood; ood.score = sel; ood.win = sel_win; %#ok<NASGU>
    save('data/trained_detector.mat', 'ood', '-append');
    if isfile('data/ood_thresholds.mat'), delete('data/ood_thresholds.mat'); end
end
T_prod = ood_thresholds(RETAIN);

%% 4. Report
js = find(strcmp(SC, sel));
rep = {};
rep{end+1} = '=== UNKNOWN-THREAT DETECTION: LEAVE-ONE-THREAT-OUT ===';
rep{end+1} = sprintf('Generated: %s | detector retrained without each threat (%d epochs), test split by sub-run', datestr(now), N_EPOCHS);
rep{end+1} = sprintf('AUROC: 0.5 = no separation, 1 = perfect. FPR95: unknown frames accepted as known at the threshold keeping %.0f%% of known validation frames.', 100*RETAIN);
rep{end+1} = '';
w8 = max(8, max(cellfun(@numel, SC)) + 1);
rep{end+1} = sprintf('%-20s %5s |%s | %6s  %-20s %5s', 'held-out threat', 'n', sprintf(sprintf(' %%%ds', w8), SC{:}), ...
    'known', 'mistaken for', 'same');
rep{end+1} = sprintf('%-20s %5s |%s |', '', '', sprintf(sprintf(' %%%ds', w8), 'AUROC'));
for i = 1:numel(R)
    r = R(i);
    rep{end+1} = sprintf('%-20s %5d |%s | %5.1f%%  %-20s %4.0f%%', r.held_out, r.n_ood, ...
        sprintf(sprintf(' %%%d.3f', w8), r.auroc), 100*r.id_acc, r.mapped_to, 100*r.same_action); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %5s |%s |', 'mean AUROC', '', sprintf(sprintf(' %%%d.3f', w8), mean(A, 1)));
rep{end+1} = sprintf('%-20s %5s |%s |', 'mean FPR95', '', sprintf(sprintf(' %%%d.2f', w8), mean(F, 1)));
AW = cat(3, R.auroc_win);
for w = 1:numel(WIN)
    rep{end+1} = sprintf('%-20s %5s |%s |', sprintf('mean AUROC, %d frames', WIN(w)), '', ...
        sprintf(sprintf(' %%%d.3f', w8), mean(squeeze(AW(:, w, :)), 2))); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf(['Production score (highest mean AUROC among %s, each over 1, %s cycles): %s over %d ' ...
    'cycles, mean AUROC %.3f (single frame %.3f, FPR95 %.2f).'], strjoin(CAND, ', '), strjoin(compose('%d', WIN), ', '), ...
    sel, sel_win, max(mean(Mp, 1)), mean(A(:, js)), mean(F(:, js)));
rep{end+1} = sprintf(['Nested estimate (score chosen on the other held-out threats, the value to quote): mean AUROC %.3f; ' ...
    'per threat %s; picks %s.'], mean(NEST.auroc), sprintf('%.3f ', NEST.auroc), strjoin(unique(NEST.pick, 'stable'), ', '));
rep{end+1} = sprintf('Production thresholds (%.0f%% of known validation frames kept): MSP %.3f | energy %.2f | %s %.3f.', ...
    100*RETAIN, T_prod.msp, T_prod.energy, sel, T_prod.maha);
IN = [R.incr];
rep{end+1} = '';
rep{end+1} = sprintf(['Learning the new threat without retraining (Lee et al., Algorithm 2; last hidden layer, generative ' ...
    'classifier): known-class accuracy before %.1f%% (softmax %.1f%%)'], 100*mean([IN.known_before]), 100*mean([R.id_acc]));
rep{end+1} = sprintf('%-20s %22s %22s %18s', 'new threat', sprintf('%d frames: new / known', K_NEW), 'all val frames', 'frames available');
for i = 1:numel(R)
    rep{end+1} = sprintf('%-20s %13.1f%% / %5.1f%% %13.1f%% / %5.1f%% %18d', R(i).held_out, 100*IN(i).new_k, ...
        100*IN(i).known_k, 100*IN(i).new_all, 100*IN(i).known_all, IN(i).n_val); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %13.1f%% / %5.1f%% %13.1f%% / %5.1f%%', 'mean', 100*mean([IN.new_k]), 100*mean([IN.known_k]), ...
    100*mean([IN.new_all]), 100*mean([IN.known_all]));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/ood_detection.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/ood_detection.mat', 'R', 'SC', 'CAND', 'sel', 'sel_win', 'NEST', 'WIN', 'RETAIN', 'N_EPOCHS', 'T_prod', 'K_NEW');
fprintf('\nSaved results/ood_detection.{txt,mat}; production score written to data/trained_detector.mat (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function inc = learn_new_class(net, M, te_id, te_ood, vk, K, ND)
% Lee et al., Algorithm 2: the held-out threat becomes class C+1 from its
% validation frames (mean, and the tied covariance updated as C/(C+1) old +
% 1/(C+1) new); classification by the smallest Mahalanobis distance in the last
% hidden layer. new = held-out test frames recognized, known = known test frames
% still correct.
L = M.layers(end);
fi = ood_layer_features(net, L, te_id.X, te_id.feats'); fi = fi{1};
fo = ood_layer_features(net, L, te_ood.X, te_ood.feats'); fo = fo{1};
fv = ood_layer_features(net, L, vk.X, vk.feats'); fv = fv{1};
yid = double(te_id.Y(:))';
mu = M.mu{end}; Sig = inv(M.P{end}); nC = size(mu, 2);
inc.known_before = mean(md_class(fi, mu, M.P{end}) == yid);
inc.n_val = size(fv, 2);
rs = RandStream('mt19937ar', 'Seed', 5);
r = zeros(ND, 2);
for d = 1:ND
    X = fv(:, randperm(rs, size(fv, 2), min(K, size(fv, 2))));
    [r(d, 1), r(d, 2)] = add_and_score(X, mu, Sig, nC, fo, fi, yid);
end
inc.new_k = mean(r(:, 1)); inc.known_k = mean(r(:, 2));
[inc.new_all, inc.known_all] = add_and_score(fv, mu, Sig, nC, fo, fi, yid);
end

function [a_new, a_known] = add_and_score(X, mu, Sig, nC, fo, fi, yid)
% Class C+1 from the frames X; share of new-threat and known test frames classified right.
Su = nC / (nC + 1) * Sig + 1 / (nC + 1) * cov(X', 1);
P = inv(Su); mu2 = [mu, mean(X, 2)];
a_new = mean(md_class(fo, mu2, P) == nC + 1);
a_known = mean(md_class(fi, mu2, P) == yid);
end

function y = md_class(F, mu, P)
% Class of the smallest Mahalanobis distance (Lee et al., eq. 3).
D2 = zeros(size(mu, 2), size(F, 2));
for c = 1:size(mu, 2)
    Dc = F - mu(:, c); D2(c, :) = sum(Dc .* (P * Dc), 1);
end
[~, y] = min(D2, [], 1);
end

function [tr, va, te_id, te_ood, vk] = loto_split(sp, known, k)
% Known-class train/val/test, the held-out test frames and the held-out
% validation frames (Algorithm 2 only); link features re-normalized with
% statistics of the known training frames only.
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
pick = @(P, keep) pick_rows(P, keep, raw(P));
tr = pick(sp.train, known); va = pick(sp.val, known);
te_id = pick(sp.test, known); te_ood = pick(sp.test, {k}); vk = pick(sp.val, {k});
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd; va.feats = (va.feats - mu) ./ sd;
te_id.feats = (te_id.feats - mu) ./ sd; te_ood.feats = (te_ood.feats - mu) ./ sd; vk.feats = (vk.feats - mu) ./ sd;
te_ood.Y = categorical(cellstr(string(te_ood.Y(:))));
end

function d = pick_rows(P, keep, F)
y = cellstr(string(P.Y(:)));
m = ismember(y, keep);
d.X = P.X(:, :, :, m);
d.feats = F(m, :);
d.Y = categorical(y(m), keep);
d.run = P.run(m);
end

function S = all_scores(net, M, P)
[S.probs, ~, S.msp, S.energy] = cnn_scores(net, P.X, P.feats');
[~, T] = ood_scores(net, M, P.X, P.feats');
for f = fieldnames(T)', S.(f{1}) = T.(f{1}); end
end

function m = win_mean(s, run, W)
% Causal mean over the last W frames of the same run (frames in time order
% within a run); frames without W predecessors in their run are dropped.
s = s(:); run = run(:); m = [];
for r = unique(run)'
    v = s(run == r);
    if numel(v) < W, continue; end
    c = movmean(v, [W - 1, 0]);
    m = [m; c(W:end)]; %#ok<AGROW>
end
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

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
