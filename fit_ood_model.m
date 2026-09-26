function M = fit_ood_model(net, tr, classes)
%FIT_OOD_MODEL  Feature-space models for unknown-threat scoring (D42).
%   Mahalanobis: class means and one shared (tied) covariance of the 64-d
%   embedding 'relu_merge' on the training split, shrunk by 10% toward a scaled
%   identity (Lee et al., NeurIPS 2018). Isolation forest (Liu, Ting & Zhou,
%   ICDM 2008) on the 8 normalized link features of the training split.
%   The scores are computed by ood_scores.m.
Z = embed(net, tr.X, tr.feats');
y = double(tr.Y(:));
d = size(Z, 1); nC = numel(classes);
mu = zeros(d, nC);
R = zeros(size(Z));
for c = 1:nC
    m = y == c;
    mu(:, c) = mean(Z(:, m), 2);
    R(:, m) = Z(:, m) - mu(:, c);
end
Sig = (R * R') / size(Z, 2);
Sig = 0.9 * Sig + 0.1 * trace(Sig) / d * eye(d);
M.mu = mu;
M.P = inv(Sig);
M.forest = iforest(tr.feats, 'NumLearners', 200, 'NumObservationsPerLearner', 256);
end

function Z = embed(net, X, F)
Z = [];
useGPU = canUseGPU;
for i0 = 1:256:size(X, 4)
    idx = i0:min(i0 + 255, size(X, 4));
    xs = dlarray(single(X(:, :, :, idx)), 'SSCB'); xf = dlarray(single(F(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    Z = [Z, double(gather(extractdata(predict(net, xs, xf, 'Outputs', 'relu_merge'))))]; %#ok<AGROW>
end
end
