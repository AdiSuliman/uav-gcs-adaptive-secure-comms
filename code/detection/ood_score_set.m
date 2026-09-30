function S = ood_score_set(M, Z, Xf, need)
%OOD_SCORE_SET  The candidate unknown-threat scores of fit_ood_model.m;
%   higher = more like the known classes. The production score is S.(M.score).
%   Z     hidden features, one cell per layer of M.layers (ood_layer_features.m);
%         cells may be empty when the candidates asked for do not use them
%   Xf    normalized link features, nFeat x N
%   need  candidates to compute (default: all)
%   Candidates:
%     last         Mahalanobis distance of the last hidden layer (Lee et al.)
%     ensemble     Lee et al.'s feature ensemble over M.layers (FGSM-fitted weights)
%     raw          Mahalanobis distance of the link features themselves (the same
%                  class-conditional Gaussians with tied covariance, on the input)
%     last_or_raw  the lower of the two standardized scores: an alarm when either
%                  the network's features or the measurements look unfamiliar
%     last_or_if   the same with the isolation forest on the link features (Liu et
%                  al.), the pairing named in the proposal
%   Components are standardized with the known validation frames (M.zs).
if nargin < 4 || isempty(need), need = M.candidates; end
N = size(Xf, 2);
use = @(c) any(strcmp(need, c));
z = @(x, f) (x - M.zs.(f)(1)) / M.zs.(f)(2);
S = struct();
if use('last') || use('last_or_raw') || use('last_or_if')
    S.last = -min_dist(Z{end}, M.mu{end}, M.P{end});
end
if use('ensemble')
    L = zeros(numel(M.layers), N);
    for l = 1:numel(M.layers), L(l, :) = -min_dist(Z{l}, M.mu{l}, M.P{l}); end
    S.ensemble = M.w(1) + M.w(2:end) * ((L - M.z_mu(:)) ./ M.z_sd(:));
end
if use('raw') || use('last_or_raw')
    S.raw = -min_dist(Xf, M.raw_mu, M.raw_P);
end
if use('last_or_if')
    [~, a] = isanomaly(M.forest, Xf');
    S.iforest = -a(:)';
end
if use('last_or_raw'), S.last_or_raw = min(z(S.last, 'last'), z(S.raw, 'raw')); end
if use('last_or_if'), S.last_or_if = min(z(S.last, 'last'), z(S.iforest, 'iforest')); end
end

function d = min_dist(V, mu, P)
% Smallest class Mahalanobis distance (squared), 1 x N.
d = inf(1, size(V, 2));
for c = 1:size(mu, 2)
    D = V - mu(:, c);
    d = min(d, sum(D .* (P * D), 1));
end
end
