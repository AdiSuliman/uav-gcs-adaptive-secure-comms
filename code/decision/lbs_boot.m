function [m, lo, hi] = lbs_boot(d, cl, B, seed)
%LBS_BOOT  Mean of per-episode differences with one-sided 95% bounds from a cluster bootstrap.
%   [m, lo, hi] = lbs_boot(d, cl, B, seed)
%   d   per-episode paired differences (policy on less policy off); cl  the cluster of each
%   episode, the flight geometry: its episodes share the fading, so whole clusters are
%   resampled (boot_cluster.m); B resamples (default 2000), seed the stream (default 1).
%   lo is the 5th and hi the 95th percentile of the resampled means, each a one-sided 95%
%   bound. NaN where fewer than two clusters hold a finite value.
if nargin < 3 || isempty(B), B = 2000; end
if nargin < 4 || isempty(seed), seed = 1; end
ok = isfinite(d);
d = d(ok); cl = cl(ok);
m = NaN; lo = NaN; hi = NaN;
if isempty(d), return; end
[~, ~, j] = unique(cl(:));
Sn = accumarray(j, d(:));
Sd = accumarray(j, ones(numel(d), 1));
m = sum(Sn) / sum(Sd);
nU = numel(Sn);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, nU, nU, B);
q = sort(sum(Sn(idx), 1) ./ sum(Sd(idx), 1));
lo = q(max(1, round(0.05 * B))); hi = q(min(B, round(0.95 * B)));
end
