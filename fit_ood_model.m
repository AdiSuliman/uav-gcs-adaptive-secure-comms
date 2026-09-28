function M = fit_ood_model(net, tr, classes, va)
%FIT_OOD_MODEL  Feature-space models for unknown-threat scoring (D42, D59).
%   Mahalanobis feature ensemble (Lee et al., NeurIPS 2018): for each layer of
%   M.layers (convolutional outputs average-pooled over time and frequency) the
%   class means and one shared (tied) covariance on the training split, shrunk by
%   10% toward a scaled identity for a stable inverse (our choice). The layer
%   scores are combined by a logistic-regression detector trained on the
%   validation split: known frames as positives, FGSM adversarial versions of the
%   same frames as negatives (the paper's validation without OOD samples, so no
%   unknown threat is seen). Isolation forest (Liu, Ting & Zhou, ICDM 2008) on the
%   normalized link features of the training split.
%   va  validation split (X, feats, Y); without it the ensemble weights are equal.
%   The scores are computed by ood_scores.m and detect_scores.m.
M.layers = {'relu1', 'relu2', 'relu3', 'relu_feat2', 'relu_merge'};
M.eps_img = 0.02; M.eps_feat = 0.1;                 % FGSM step: image [0,1] units, z-score units
M.classes = classes;
Z = ood_layer_features(net, M.layers, tr.X, tr.feats');
y = double(tr.Y(:));
nC = numel(classes);
for l = 1:numel(M.layers)
    X = Z{l}; d = size(X, 1);
    mu = zeros(d, nC); R = zeros(size(X));
    for c = 1:nC
        m = y == c;
        mu(:, c) = mean(X(:, m), 2);
        R(:, m) = X(:, m) - mu(:, c);
    end
    Sig = (R * R') / size(X, 2);
    Sig = 0.9 * Sig + 0.1 * trace(Sig) / d * eye(d);
    M.mu{l} = mu; M.P{l} = inv(Sig);
end
M.forest = iforest(tr.feats, 'NumLearners', 200, 'NumObservationsPerLearner', 256);

% Ensemble weights: logistic regression, known validation frames vs their FGSM versions
nL = numel(M.layers);
M.z_mu = zeros(1, nL); M.z_sd = ones(1, nL); M.w = [0, ones(1, nL) / nL];
if nargin < 4 || isempty(va), return; end
[~, ~, Sp] = ood_ensemble(M, ood_layer_features(net, M.layers, va.X, va.feats'));
[Xa, Fa] = fgsm(net, va.X, va.feats', va.Y, M.eps_img, M.eps_feat);
[~, ~, Sn] = ood_ensemble(M, ood_layer_features(net, M.layers, Xa, Fa));
Sp = Sp'; Sn = Sn';
M.z_mu = mean(Sp, 1); M.z_sd = max(std(Sp, 0, 1), eps);
A = ([Sp; Sn] - M.z_mu) ./ M.z_sd;
lab = [ones(size(Sp, 1), 1); zeros(size(Sn, 1), 1)];
b = glmfit(A, lab, 'binomial');
M.w = b(:)';
end

function [Xa, Fa] = fgsm(net, X, F, Y, ei, ef)
% Fast gradient sign method (Goodfellow et al.) on both inputs of the detector,
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
