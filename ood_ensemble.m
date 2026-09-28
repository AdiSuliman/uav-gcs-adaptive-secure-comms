function [score, last, S] = ood_ensemble(M, Z)
%OOD_ENSEMBLE  Mahalanobis feature-ensemble score from the layer features Z
%   (ood_layer_features.m, one cell per layer of M.layers): minus the smallest
%   class distance per layer, standardized, combined with the logistic weights of
%   fit_ood_model.m. Higher = more like the known classes. last = the last layer's
%   score alone; S = layers x N raw layer scores.
nL = numel(Z); N = size(Z{1}, 2);
S = zeros(nL, N);
for l = 1:nL
    dmin = inf(1, N);
    for c = 1:size(M.mu{l}, 2)
        D = Z{l} - M.mu{l}(:, c);
        dmin = min(dmin, sum(D .* (M.P{l} * D), 1));
    end
    S(l, :) = -dmin;
end
last = S(end, :);
score = M.w(1) + M.w(2:end) * ((S - M.z_mu(:)) ./ M.z_sd(:));
end
