function [m, lo, hi, v] = boot_cluster(num, den, cl, B, seed, grp)
%BOOT_CLUSTER  Ratio sum(num) / sum(den) with a 95% percentile bootstrap interval
%   that resamples whole clusters, and the bootstrap variance v of the ratio. The
%   cluster is the flight geometry: the episodes of one geometry share its fading,
%   speed and interferer directions, so they are not independent and are resampled
%   together (proposal mitigation 5: intervals by runs). A mean is the case den = ones;
%   a paired difference is the mean of per-episode differences.
%   num, den  per-episode values; cl  cluster id per episode; B resamples (2000)
%   grp       two groups (per episode): m is the ratio of the second (the larger value)
%             less the first's, their clusters resampled within each group
if nargin < 4 || isempty(B), B = 2000; end
if nargin < 5 || isempty(seed), seed = 1; end
if nargin >= 6 && ~isempty(grp), [m, lo, hi, v] = two_groups(num, den, cl, B, seed, grp); return; end
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

function [m, lo, hi, v] = two_groups(num, den, cl, B, seed, grp)
ok = isfinite(num) & isfinite(den);
num = num(ok); den = den(ok); cl = cl(ok); grp = grp(ok);
g = unique(grp(:));
assert(numel(g) == 2, 'boot_cluster:groups', 'two groups are needed, %d given', numel(g));
m = NaN; lo = NaN; hi = NaN; v = NaN;
S = cell(2, 2);
for k = 1:2
    q = grp(:) == g(k);
    [~, ~, j] = unique(cl(q));
    S{k, 1} = accumarray(j(:), reshape(num(q), [], 1)); S{k, 2} = accumarray(j(:), reshape(den(q), [], 1));
end
if any(cellfun(@(x) sum(x), S(:, 2)) == 0), return; end
m = sum(S{2, 1}) / sum(S{2, 2}) - sum(S{1, 1}) / sum(S{1, 2});
n1 = numel(S{1, 1}); n2 = numel(S{2, 1});
if n1 < 2 || n2 < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
i1 = randi(rs, n1, n1, B); i2 = randi(rs, n2, n2, B);
bs = sum(S{2, 1}(i2), 1) ./ max(sum(S{2, 2}(i2), 1), eps) - sum(S{1, 1}(i1), 1) ./ max(sum(S{1, 2}(i1), 1), eps);
q = sort(bs);
lo = q(max(1, round(0.025 * B))); hi = q(min(B, round(0.975 * B)));
v = var(bs);
end
