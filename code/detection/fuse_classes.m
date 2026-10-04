function varargout = fuse_classes(cmd, varargin)
%FUSE_CLASSES  Temporal fusion: the class of the current decision cycle from the
%   evidence of the last N cycles (temporal_evidence.m), a multinomial logistic
%   regression on the fused detector log-probabilities and the persistence
%   measurements.
%   Z = fuse_classes('windows', S, probs, N)
%       evidence of every frame of split S (fields run, pos, gain_ant, feats_raw,
%       feat_names) from the frames of its own sub-run at positions pos-N+1..pos
%       (causal); probs frames x C
%   FM = fuse_classes('fit', Z, y, C, lambda)     y class index per frame
%   [pc, k] = fuse_classes('apply', FM, Z)        pc frames x C, k predicted class
%   The fusion is fitted on the validation split (the detector's outputs on its own
%   training frames are overconfident), N and lambda by cross-validation over the
%   validation sub-runs (select_fusion.m); the test split is never used.
switch cmd
    case 'windows', varargout{1} = windows(varargin{:});
    case 'fit',     varargout{1} = fit(varargin{:});
    case 'apply',   [varargout{1}, varargout{2}] = apply(varargin{:});
    otherwise, error('fuse_classes: unknown command %s', cmd);
end
end

function Z = windows(S, probs, N)
[ok, jf] = ismember(link_features('names'), S.feat_names);
if ~all(ok), error('fuse_classes: feats_raw lacks link features (rerun extract_spectrograms, prepare_data)'); end
n = numel(S.run);
Z = zeros(n, numel(temporal_evidence('names', size(probs, 2))));
[~, ~, rid] = unique(S.run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(S.pos(ix)); ix = ix(o);
    for j = 1:numel(ix)
        w = ix(max(1, j - N + 1):j);
        Z(ix(j), :) = temporal_evidence(permute(probs(w, :), [3 2 1]), permute(S.gain_ant(w, :), [3 2 1]), ...
            permute(S.feats_raw(w, jf), [3 2 1]));
    end
end
end

function FM = fit(Z, y, C, lambda)
mu = mean(Z, 1); sd = std(Z, 0, 1); sd(sd < 1e-6) = 1;
X = [(Z - mu) ./ sd, ones(size(Z, 1), 1)];
Y = full(sparse(1:numel(y), y(:), 1, numel(y), C));
W = zeros(size(X, 2), C);
m = zeros(size(W)); v = zeros(size(W)); lr = 0.05; b1 = 0.9; b2 = 0.999;
for it = 1:1500                                           % Adam on the regularized cross-entropy
    Pz = softmax_rows(X * W);
    g = X' * (Pz - Y) / size(X, 1);
    g(1:end-1, :) = g(1:end-1, :) + lambda * W(1:end-1, :);
    m = b1 * m + (1 - b1) * g; v = b2 * v + (1 - b2) * g.^2;
    W = W - lr * (m / (1 - b1^it)) ./ (sqrt(v / (1 - b2^it)) + 1e-8);
end
FM = struct('W', W, 'mu', mu, 'sd', sd, 'C', C, 'lambda', lambda);
end

function [pc, k] = apply(FM, Z)
X = [(Z - FM.mu) ./ FM.sd, ones(size(Z, 1), 1)];
pc = softmax_rows(X * FM.W);
[~, k] = max(pc, [], 2);
end

function P = softmax_rows(A)
A = A - max(A, [], 2);
P = exp(A); P = P ./ sum(P, 2);
end
