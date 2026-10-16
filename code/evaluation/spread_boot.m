function S = spread_boot(x, bin, cl, nb, B, seed)
%SPREAD_BOOT  Spread of a rate over bins, the largest minus the smallest bin mean of x over
%   the episodes of bins 1..nb (bin 0: not counted), and its 95% percentile bootstrap
%   interval resampling whole clusters cl (the flight geometries, boot_cluster.m) B times
%   from the stream seed: [value lo hi]. A bin without an episode in a resample is left out
%   of it (evaluate_policies.m: KPI 7's spread over the speed bands).
m = bin > 0; x = x(m); bin = bin(m); cl = cl(m);
S = [NaN NaN NaN];
if isempty(x), return; end
[~, ~, j] = unique(cl(:)); nU = max(j);
Sx = accumarray([j, bin(:)], x(:), [nU nb]); Sn = accumarray([j, bin(:)], 1, [nU nb]);
f = @(ix) spread(sum(Sx(ix, :), 1) ./ sum(Sn(ix, :), 1));
S(1) = f(1:nU);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
bs = zeros(1, B);
for b = 1:B, bs(b) = f(randi(rs, nU, nU, 1)); end
q = sort(bs(isfinite(bs)));
if isempty(q), return; end
S(2) = q(max(1, round(0.025 * numel(q)))); S(3) = q(min(numel(q), round(0.975 * numel(q))));
end

function d = spread(r)
r = r(isfinite(r));
if isempty(r), d = NaN; else, d = max(r) - min(r); end
end
