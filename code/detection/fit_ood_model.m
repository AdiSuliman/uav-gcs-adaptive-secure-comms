function M = fit_ood_model(net, tr, classes, va)
%FIT_OOD_MODEL  Unknown-threat models of the detector; the
%   candidate scores are computed by ood_score_set.m.
%   Mahalanobis (Lee et al., NeurIPS 2018): for each layer of M.layers
%   (convolutional outputs average-pooled over time and frequency) and for the
%   link features themselves, the class means and one shared (tied) covariance on
%   the training split, shrunk by 10% toward a scaled identity for a stable
%   inverse (our choice). The feature-ensemble weights come from a logistic
%   regression on the validation split: known frames against their FGSM versions
%   (the paper's validation without OOD samples). Isolation forest (Liu, Ting &
%   Zhou, ICDM 2008) on the normalized link features of the training split, with
%   the larger sub-sample the paper recommends when training on normal data only
%   (their section 5.4). The standardization of the fused candidates uses the known
%   validation frames.
%   M.score, the production candidate, is 'last' until eval_ood_detection.m
%   selects it by leave-one-threat-out.
%   va  validation split (X, feats, Y); without it the ensemble weights are equal.
M.layers = {'relu1', 'relu2', 'relu3', 'relu_feat2', 'relu_merge'};
M.candidates = {'last', 'ensemble', 'raw', 'last_or_raw', 'last_or_if'};
M.score = 'last';
M.eps_img = 0.02; M.eps_feat = 0.1;                 % FGSM step: image [0,1] units, z-score units
M.classes = classes;
y = double(tr.Y(:));
Z = ood_layer_features(net, M.layers, tr.X, tr.feats');
for l = 1:numel(M.layers)
    [M.mu{l}, M.P{l}] = tied_gauss(Z{l}, y);
end
[M.raw_mu, M.raw_P] = tied_gauss(tr.feats', y);
M.forest = iforest(tr.feats, 'NumLearners', 100, 'NumObservationsPerLearner', min(8192, size(tr.feats, 1)));

% Ensemble weights: logistic regression, known validation frames vs their FGSM versions
nL = numel(M.layers);
M.z_mu = zeros(1, nL); M.z_sd = ones(1, nL); M.w = [0, ones(1, nL) / nL];
M.zs = struct('last', [0 1], 'raw', [0 1], 'iforest', [0 1]);
if nargin < 4 || isempty(va), return; end
Zv = ood_layer_features(net, M.layers, va.X, va.feats');
Sp = layer_scores(M, Zv);
[Xa, Fa] = fgsm(net, va.X, va.feats', va.Y, M.eps_img, M.eps_feat);
Sn = layer_scores(M, ood_layer_features(net, M.layers, Xa, Fa));
M.z_mu = mean(Sp, 2)'; M.z_sd = max(std(Sp, 0, 2), eps)';
A = ([Sp, Sn] - M.z_mu(:)) ./ M.z_sd(:);
lab = [ones(size(Sp, 2), 1); zeros(size(Sn, 2), 1)];
b = glmfit(A', lab, 'binomial');
M.w = b(:)';

% Standardization of the fused candidates on the known validation frames
Sv = ood_score_set(M, Zv, va.feats', {'last', 'raw', 'last_or_if'});
for f = {'last', 'raw', 'iforest'}
    M.zs.(f{1}) = [mean(Sv.(f{1})), max(std(Sv.(f{1})), eps)];
end
end

function [mu, P] = tied_gauss(X, y)
% Class means and inverse tied covariance (Lee et al., eq. 1), 10% shrinkage.
d = size(X, 1); nC = max(y);
mu = zeros(d, nC); R = zeros(size(X));
for c = 1:nC
    m = y == c;
    mu(:, c) = mean(X(:, m), 2);
    R(:, m) = X(:, m) - mu(:, c);
end
Sig = (R * R') / size(X, 2);
Sig = 0.9 * Sig + 0.1 * trace(Sig) / d * eye(d);
P = inv(Sig);
end

function L = layer_scores(M, Z)
% Minus the smallest class Mahalanobis distance per layer (layers x N).
L = zeros(numel(M.layers), size(Z{1}, 2));
for l = 1:numel(M.layers)
    d = inf(1, size(Z{l}, 2));
    for c = 1:size(M.mu{l}, 2)
        D = Z{l} - M.mu{l}(:, c);
        d = min(d, sum(D .* (M.P{l} * D), 1));
    end
    L(l, :) = -d;
end
end

function [Xa, Fa] = fgsm(net, X, F, Y, ei, ef)
% Fast gradient sign method (FGSM, as in Lee et al.) on both inputs of the detector,
% in batches; the image stays in [0, 1].
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
y = predict(net, xs, xf);
loss = crossentropy(y, t);
[gs, gf] = dlgradient(loss, xs, xf);
end
