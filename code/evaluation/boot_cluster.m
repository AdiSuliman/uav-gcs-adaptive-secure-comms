function [m, lo, hi, v] = boot_cluster(num, den, cl, B, seed)
%BOOT_CLUSTER  Ratio sum(num) / sum(den) with a 95% percentile bootstrap interval
%   that resamples whole clusters, and the bootstrap variance v of the ratio. The
%   cluster is the flight geometry: the episodes of one geometry share its fading,
%   speed and interferer directions, so they are not independent and are resampled
%   together (proposal mitigation 5: intervals by runs). A mean is the case den = ones;
%   a paired difference is the mean of per-episode differences.
%   num, den  per-episode values; cl  cluster id per episode; B resamples (2000)
if nargin < 4 || isempty(B), B = 2000; end
if nargin < 5 || isempty(seed), seed = 1; end
ok = isfinite(num) & isfinite(den);
num = num(ok); den = den(ok); cl = cl(ok);
m = NaN; lo = NaN; hi = NaN; v = NaN;
if isempty(num) || sum(den) == 0, return; end
[~, ~, j] = unique(cl(:));
Sn = accumarray(j, num(:)); Sd = accumarray(j, den(:));
m = sum(Sn) / sum(Sd);
nU = numel(Sn);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, nU, nU, B);
bs = sum(Sn(idx), 1) ./ max(sum(Sd(idx), 1), eps);
q = sort(bs);
lo = q(max(1, round(0.025 * B))); hi = q(min(B, round(0.975 * B)));
v = var(bs);
end
