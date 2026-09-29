%% DIAG_OOD_SCORES - Which unknown-threat score, leave-one-threat-out
% Tests, on the leave-one-threat-out folds, the parts of Lee et al.'s method (a
% feature ensemble over five layers with logistic weights fitted on known
% validation frames vs their FGSM versions) and the choices around it:
%   1. every layer alone, the ensemble and the last layer
%   2. input pre-processing (x - eps * sign of the gradient of the layer's
%      Mahalanobis distance, per layer), eps from Lee et al.'s list chosen on
%      validation only: logistic weights fitted on half of the validation
%      sub-runs, AUROC known vs FGSM on the other half
%   3. MSP and energy
%   4. nested selection: for each held-out threat the score with the best mean
%      AUROC on the OTHER held-out threats, so the reported value never used
%      the threat it is measured on
%   5. the score averaged over the last W frames of the same run (W = 2, the
%      alarm confirmation; W = 5, the monitor window)
%   6. latency of the pre-processed score for one frame
% The held-out threat is never used to fit, weight or choose anything. The
% fold networks are trained once (as eval_ood_detection.m) and cached in
% data/ood_loto_nets.mat. Known test frames: a fixed random subsample of 3000
% per fold for the pre-processing sweep; all of them for the window study.
%
% Run from the project root: diag_ood_scores (startup.m puts code/ on the path)
% Output: results/diag_ood_scores.txt

close all; clc;
cache = 'data/ood_loto_nets.mat';
EPS  = [0 0.0005 0.001 0.002 0.005];                % from Lee et al.'s list
N_ID = 3000;
WIN  = [1 2 5];
rng(2026, 'twister');
S = load('data/splits.mat', 'splits'); sp = S.splits; clear S
all_classes = cellstr(string(sp.classes(:)'));
held_out = setdiff(all_classes, {'none'}, 'stable');
nH = numel(held_out);
rep = {'=== UNKNOWN-THREAT SCORES, LEAVE-ONE-THREAT-OUT (D60 diagnostic) ==='};
rep{end+1} = sprintf('Generated: %s | fold networks as eval_ood_detection.m; eps chosen on validation (known vs FGSM)', datestr(now));

%% 1. Fold networks (cached)
if isfile(cache) && dir(cache).datenum >= dir('data/splits.mat').datenum
    C = load(cache, 'FOLD'); FOLD = C.FOLD;
else
    FOLD = struct('k', {}, 'net', {}, 'M', {});
end
for h = numel(FOLD) + 1:nH
    k = held_out{h}; known = setdiff(all_classes, {k}, 'stable');
    [tr, va] = loto_split(sp, known, k);
    net = train_hybrid_net(tr, va, known, struct('verbose', false));
    FOLD(h) = struct('k', k, 'net', net, 'M', fit_ood_model(net, tr, known, va)); %#ok<SAGROW>
    save(cache, 'FOLD');
    fprintf('trained fold %d/%d (%s)\n', h, nH, k);
end

%% 2. Scores per fold
CAND = {'ensemble', 'last layer', 'ensemble + pre', 'last + pre', 'msp', 'energy'};
A = zeros(nH, numel(CAND)); AW = zeros(nH, 2, numel(WIN)); EP = zeros(nH, 2); LAY = zeros(nH, 5);
for h = 1:nH
    k = held_out{h}; known = setdiff(all_classes, {k}, 'stable');
    [~, va, te_id, te_ood] = loto_split(sp, known, k);
    net = FOLD(h).net; M = FOLD(h).M;
    sub = sub_rows(te_id, randperm(size(te_id.X, 4), min(N_ID, size(te_id.X, 4))));
    [Xa, Fa] = fgsm_local(net, va.X, va.feats', va.Y, M.eps_img, M.eps_feat);
    runs = unique(va.run); half = ismember(va.run, runs(1:2:end));
    vens = zeros(1, numel(EPS)); vlast = zeros(1, numel(EPS)); WF = cell(1, numel(EPS));
    for e = 1:numel(EPS)
        Sv = layer_scores_pre(net, M, va.X, va.feats', EPS(e));
        Sa = layer_scores_pre(net, M, Xa, Fa, EPS(e));
        w = fit_w(Sv(:, half), Sa(:, half));
        vens(e) = auroc(comb(w, Sv(:, ~half)), comb(w, Sa(:, ~half)));
        vlast(e) = auroc(Sv(end, :), Sa(end, :));
        WF{e} = fit_w(Sv, Sa);
    end
    [~, es] = max(vens); [~, esl] = max(vlast); EP(h, :) = EPS([es esl]);
    au = @(e, f) score_auc(net, M, sub, te_ood, EPS(e), WF{e}, f);
    [a0e, a0l, LAY(h, :)] = au(1, true);
    [ase, ~] = au(es, false); [~, asl] = au(esl, false);
    [~, ~, mi, eni] = cnn_scores(net, sub.X, sub.feats');
    [~, ~, mo, eno] = cnn_scores(net, te_ood.X, te_ood.feats');
    if EPS(es) == 0, ase = a0e; end                             % eps 0: the same score as without pre-processing
    if EPS(esl) == 0, asl = a0l; end
    A(h, :) = [a0e, a0l, ase, asl, auroc(mi, mo), auroc(eni, eno)];
    % window study on all known test frames, eps 0
    Si = layer_scores_pre(net, M, te_id.X, te_id.feats', 0); So = layer_scores_pre(net, M, te_ood.X, te_ood.feats', 0);
    ens = @(S) M.w(1) + M.w(2:end) * ((S - M.z_mu(:)) ./ M.z_sd(:));
    ei = ens(Si); eo = ens(So); li = Si(end, :); lo = So(end, :);
    for w = 1:numel(WIN)
        AW(h, :, w) = [auroc(win_mean(ei, te_id.run, WIN(w)), win_mean(eo, te_ood.run, WIN(w))), ...
                       auroc(win_mean(li, te_id.run, WIN(w)), win_mean(lo, te_ood.run, WIN(w)))];
    end
    fprintf('%-20s eps chosen %.4f / %.4f | %s\n', k, EP(h, 1), EP(h, 2), sprintf('%.3f ', A(h, :)));
end

%% 3. Nested selection
nest = zeros(1, nH); pick = cell(1, nH);
for h = 1:nH
    o = setdiff(1:nH, h); [~, j] = max(mean(A(o, :), 1));
    nest(h) = A(h, j); pick{h} = CAND{j};
end

%% 4. Latency of the pre-processed score, one frame
D = load('data/trained_detector.mat', 'net', 'ood');
X1 = sp.test.X(:, :, :, 1); F1 = sp.test.feats(1, :)';
lat = zeros(1, 2); devs = {'cpu', 'gpu'};
for d = 1:2
    if strcmp(devs{d}, 'gpu') && ~canUseGPU, lat(d) = NaN; continue; end
    t = zeros(1, 60);
    for i = 1:60
        t0 = tic; layer_scores_pre(D.net, D.ood, X1, F1, 0.002, devs{d});
        if strcmp(devs{d}, 'gpu'), wait(gpuDevice); end
        t(i) = toc(t0);
    end
    lat(d) = 1000 * median(t(11:end));
end

%% 5. Report
rep{end+1} = '';
rep{end+1} = sprintf('AUROC per held-out threat (known test subsample %d, all unknown frames):', N_ID);
rep{end+1} = sprintf('%-20s %8s %8s | %s', 'held-out threat', 'eps ens', 'eps last', sprintf('%-15s', CAND{:}));
for h = 1:nH
    rep{end+1} = sprintf('%-20s %8.4f %8.4f | %s', held_out{h}, EP(h, 1), EP(h, 2), sprintf('%-15.3f', A(h, :))); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %8s %8s | %s', 'mean', '', '', sprintf('%-15.3f', mean(A, 1)));
rep{end+1} = '';
rep{end+1} = sprintf('Every layer alone (eps 0), mean AUROC: %s', strjoin(cellfun(@(n, v) sprintf('%s %.3f', n, v), ...
    FOLD(1).M.layers, num2cell(mean(LAY, 1)), 'UniformOutput', false), ', '));
rep{end+1} = sprintf('Nested selection (score chosen on the other held-out threats): mean AUROC %.3f; picks: %s', ...
    mean(nest), strjoin(unique(pick, 'stable'), ', '));
rep{end+1} = sprintf('Score averaged over W frames of the same run (all known test frames), mean AUROC ensemble / last layer: %s', ...
    strjoin(arrayfun(@(w) sprintf('W=%d %.3f / %.3f', WIN(w), mean(AW(:, 1, w)), mean(AW(:, 2, w))), 1:numel(WIN), ...
    'UniformOutput', false), ' | '));
rep{end+1} = sprintf('Pre-processed ensemble, one frame: median %.1f ms (CPU), %.1f ms (GPU)', lat);
fid = fopen('results/diag_ood_scores.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});

%% ===================== Local functions =====================
function [ae, al, lay] = score_auc(net, M, P, Q, ep, w, per_layer)
Si = layer_scores_pre(net, M, P.X, P.feats', ep);
So = layer_scores_pre(net, M, Q.X, Q.feats', ep);
ae = auroc(comb(w, Si), comb(w, So)); al = auroc(Si(end, :), So(end, :));
lay = [];
if per_layer, lay = arrayfun(@(l) auroc(Si(l, :), So(l, :)), 1:size(Si, 1)); end
end

function S = layer_scores_pre(net, M, X, F, ep, device)
% Layer scores (minus the smallest class distance) after Lee et al.'s input
% pre-processing per layer: x_l = x - ep * sign(gradient of the layer-l distance);
% the link features move by the same fraction of their FGSM step.
if nargin < 6, device = 'auto'; end
useGPU = ~strcmp(device, 'cpu') && canUseGPU;
nL = numel(M.layers); N = size(X, 4); S = zeros(nL, N); B = 32;
er = ep * M.eps_feat / M.eps_img;
for i0 = 1:B:N
    idx = i0:min(i0 + B - 1, N); n = numel(idx);
    xs = dlarray(single(repmat(X(:, :, :, idx), 1, 1, 1, nL)), 'SSCB');
    xf = dlarray(single(repmat(F(:, idx), 1, nL)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    if ep > 0
        [gs, gf] = dlfeval(@pre_grad, net, xs, xf, M, n);
        xs = min(max(xs - ep * sign(gs), 0), 1);
        xf = xf - er * sign(gf);
    end
    out = cell(1, nL);
    [out{:}] = predict(net, xs, xf, 'Outputs', M.layers);
    for l = 1:nL
        v = double(gather(extractdata(pool_c(out{l}))));
        S(l, idx) = -min_dist(v(:, (l - 1) * n + (1:n)), M.mu{l}, M.P{l});
    end
end
end

function [gs, gf] = pre_grad(net, xs, xf, M, n)
nL = numel(M.layers);
out = cell(1, nL);
[out{:}] = predict(net, xs, xf, 'Outputs', M.layers);
loss = 0;
for l = 1:nL
    v = pool_c(out{l});
    loss = loss + sum(min_dist(v(:, (l - 1) * n + (1:n)), M.mu{l}, M.P{l}));
end
[gs, gf] = dlgradient(loss, xs, xf);
end

function v = pool_c(a)
if startsWith(dims(a), 'SS')
    v = stripdims(mean(mean(a, 1), 2)); v = reshape(v, size(v, 3), []);
else
    v = stripdims(a);
end
end

function d = min_dist(v, mu, P)
D2 = [];
for c = 1:size(mu, 2)
    Dc = v - mu(:, c);
    D2 = [D2; sum(Dc .* (P * Dc), 1)]; %#ok<AGROW>
end
d = min(D2, [], 1);
end

function w = fit_w(Sp, Sn)
zm = mean(Sp, 2); zs = max(std(Sp, 0, 2), eps);
A = ([Sp, Sn] - zm) ./ zs;
b = glmfit(A', [ones(size(Sp, 2), 1); zeros(size(Sn, 2), 1)], 'binomial');
w = struct('b', b(:)', 'mu', zm, 'sd', zs);
end

function s = comb(w, S)
s = w.b(1) + w.b(2:end) * ((S - w.mu) ./ w.sd);
end

function [Xa, Fa] = fgsm_local(net, X, F, Y, ei, ef)
% FGSM on both inputs, as fit_ood_model.m
useGPU = canUseGPU;
nC = numel(categories(Y));
T = double(onehotencode(Y(:), 2)');
Xa = zeros(size(X), 'single'); Fa = zeros(size(F), 'single');
for i0 = 1:128:size(X, 4)
    idx = i0:min(i0 + 127, size(X, 4));
    xs = dlarray(single(X(:, :, :, idx)), 'SSCB'); xf = dlarray(single(F(:, idx)), 'CB');
    t = dlarray(single(T(1:nC, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); t = gpuArray(t); end
    [gs, gf] = dlfeval(@input_grad, net, xs, xf, t);
    Xa(:, :, :, idx) = gather(extractdata(min(max(xs + ei * sign(gs), 0), 1)));
    Fa(:, idx) = gather(extractdata(xf + ef * sign(gf)));
end
end

function [gs, gf] = input_grad(net, xs, xf, t)
loss = crossentropy(predict(net, xs, xf), t);
[gs, gf] = dlgradient(loss, xs, xf);
end

function m = win_mean(s, run, W)
% Causal mean over the last W frames of the same run; frames without W
% predecessors in their run are dropped.
s = s(:); run = run(:); m = [];
for r = unique(run)'
    v = s(run == r);
    if numel(v) < W, continue; end
    c = movmean(v, [W - 1, 0]);
    m = [m; c(W:end)]; %#ok<AGROW>
end
end

function [tr, va, te_id, te_ood] = loto_split(sp, known, k)
% As eval_ood_detection.m, keeping the sub-run of every frame.
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
tr = pick_rows(sp.train, known, raw(sp.train)); va = pick_rows(sp.val, known, raw(sp.val));
te_id = pick_rows(sp.test, known, raw(sp.test)); te_ood = pick_rows(sp.test, {k}, raw(sp.test));
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd; va.feats = (va.feats - mu) ./ sd;
te_id.feats = (te_id.feats - mu) ./ sd; te_ood.feats = (te_ood.feats - mu) ./ sd;
te_ood.Y = categorical(cellstr(string(te_ood.Y(:))));
end

function d = pick_rows(P, keep, F)
y = cellstr(string(P.Y(:)));
m = ismember(y, keep);
d.X = P.X(:, :, :, m); d.feats = F(m, :); d.Y = categorical(y(m), keep); d.run = P.run(m);
end

function d = sub_rows(P, ii)
d = struct('X', P.X(:, :, :, ii), 'feats', P.feats(ii, :), 'Y', P.Y(ii), 'run', P.run(ii));
end

function a = auroc(pos, neg)
pos = pos(:); neg = neg(:);
r = tiedrank([pos; neg]);
np = numel(pos); nn = numel(neg);
a = (sum(r(1:np)) - np * (np + 1) / 2) / (np * nn);
end
