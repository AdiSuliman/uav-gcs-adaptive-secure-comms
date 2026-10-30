function [d, lo, hi, n] = cluster_contrast(x, a, b, cl, B, seed)
%CLUSTER_CONTRAST  Mean of x over the episodes of group a minus its mean over group b, with a 95%
%   percentile bootstrap interval that resamples whole clusters cl (the flight geometries,
%   boot_cluster.m) jointly for both groups.
%   x per-episode values; a, b logical masks of the episodes; cl cluster id per episode;
%   B resamples (2000); seed of the stream. A resample that leaves a group empty is left out.
%   n = [episodes of a, episodes of b, clusters of a, clusters of b]; d, lo, hi are NaN when
%   a group has no episode (lo, hi also with fewer than two clusters).
if nargin < 5 || isempty(B), B = 2000; end
if nargin < 6 || isempty(seed), seed = 1; end
x = double(x(:)); a = logical(a(:)); b = logical(b(:)); cl = cl(:);
ok = isfinite(x) & (a | b);
d = NaN; lo = NaN; hi = NaN; n = [0 0 0 0];
if ~any(ok), return; end
x = x(ok); a = a(ok); b = b(ok); cl = cl(ok);
[~, ~, j] = unique(cl);
nU = max(j);
Sa = accumarray(j, double(a) .* x, [nU 1]); Na = accumarray(j, double(a), [nU 1]);
Sb = accumarray(j, double(b) .* x, [nU 1]); Nb = accumarray(j, double(b), [nU 1]);
n = [sum(a), sum(b), sum(Na > 0), sum(Nb > 0)];
if sum(Na) == 0 || sum(Nb) == 0, return; end
d = sum(Sa) / sum(Na) - sum(Sb) / sum(Nb);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, nU, nU, B);
bs = sum(Sa(idx), 1) ./ sum(Na(idx), 1) - sum(Sb(idx), 1) ./ sum(Nb(idx), 1);
bs = bs(isfinite(bs));
if numel(bs) < 2, return; end
q = sort(bs);
lo = q(max(1, round(0.025 * numel(q)))); hi = q(min(numel(q), round(0.975 * numel(q))));
end
