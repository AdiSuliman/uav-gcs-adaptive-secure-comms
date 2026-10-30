function S = speed_inference(x, band, cl, st, pg, nb, B, seed, what)
%SPEED_INFERENCE  Inference on the spread of a rate over bands, the largest minus the smallest
%   band mean (the speed spread of evaluate_policies.m, spread_boot.m), with the flights as clusters.
%   S = speed_inference(x, band, cl, st, pg, nb, B, seed)
%   S = speed_inference(..., what)    what 'all' (default), 'boot' or 'perm': only that part
%   x     the rate per episode (recovered, 0 or 1); band  the band 1..nb of the episode's flight
%         (0: not counted); cl  the flight (cluster) of the episode; st  its Eb/N0 stratum;
%         pg  the airframe-shadowing group whose own flight it is (0: a shared flight)
%   B     resamples (9999); seed  [boot perm], or one value for both streams
%   A flight lies in one band, one stratum and one group. A band mean is the sum of its
%   episodes' rates over their number; a band without an episode in a resample is left out.
%   S.m, S.n, S.nf  band means, episodes and flights; S.point  max - min of the means
%   Cluster bootstrap: flights resampled with replacement within each Eb/N0 stratum, B times
%   from the stream seed(1); m* are the replicates' band means
%   S.lo, S.hi  95% percentile interval of each band mean
%   S.q, S.U    Hall & Miller 2010, joint-centred and one-sided: q is the 95% quantile over the
%               replicates of max over a ~= b of [(m*_a - m*_b) - (m_a - m_b)], and
%               U = max over a ~= b of (m_a - m_b) + q = point + q, a conservative upper bound
%               on the true spread
%   Permutation test of association (Ernst 2004): whole flights' bands permuted within each
%   (Eb/N0 stratum, shadowing group) cell, B times from the stream seed(2); the statistic is
%   max - min of the band means. A group's own flights are permuted among themselves because
%   the speeds shadowing is flown at differ from the shared flights' (build_policy_pools.m).
%   S.p         (1 + permutations with a statistic >= the observed) / (B + 1)
%   S.perm_mean the mean permuted statistic: the spread that noise alone gives (the range of
%               equal bands grows with their standard error, Tippett 1925)
if nargin < 9 || isempty(what), what = 'all'; end
if isscalar(seed), seed = [seed seed]; end
x = x(:)'; band = band(:)'; cl = cl(:)'; st = st(:)'; pg = pg(:)';
k = band > 0 & isfinite(x);
x = double(x(k)); band = band(k); cl = cl(k); st = st(k); pg = pg(k);
S = struct('m', nan(1, nb), 'n', zeros(1, nb), 'nf', zeros(1, nb), 'lo', nan(1, nb), 'hi', nan(1, nb), ...
    'point', NaN, 'pair', [NaN NaN], 'q', NaN, 'U', NaN, 'p', NaN, 'perm_mean', NaN, 'B', B, 'seed', seed, 'nU', 0);
if isempty(x), return; end
[~, ~, j] = unique(cl(:)); nU = max(j);
S.nU = nU;
Sx = accumarray([j, band(:)], x(:), [nU nb]);
Sn = accumarray([j, band(:)], 1, [nU nb]);
cb = one_value(j, band, 'band');
cs = one_value(j, st, 'Eb/N0 stratum');
cg = one_value(j, pg, 'shadowing group');
S.n = sum(Sn, 1); S.nf = accumarray(cb, 1, [nb 1])';
S.m = sum(Sx, 1) ./ sum(Sn, 1);
S.point = spread(S.m);
[~, ia] = max(S.m); [~, ib] = min(S.m); S.pair = [ia ib];
CH = 500;                                               % resamples per block
if ismember(what, {'all', 'boot'})
    rs = RandStream('mt19937ar', 'Seed', seed(1));
    ss = unique(cs); mem = arrayfun(@(u) find(cs == u), ss, 'UniformOutput', false);
    Mb = zeros(B, nb);
    for c0 = 1:CH:B
        nc = min(CH, B - c0 + 1);
        IDX = zeros(nU, nc); r0 = 0;
        for u = 1:numel(mem)
            nk = numel(mem{u}); mu = mem{u}(:);
            IDX(r0 + (1:nk), :) = mu(randi(rs, nk, nk, nc));
            r0 = r0 + nk;
        end
        for b = 1:nb
            xs = Sx(:, b); ns = Sn(:, b);
            Mb(c0 + (0:nc-1), b) = (sum(xs(IDX), 1) ./ sum(ns(IDX), 1))';
        end
    end
    for b = 1:nb
        q = sort(Mb(isfinite(Mb(:, b)), b));
        if ~isempty(q), S.lo(b) = q(max(1, round(0.025 * numel(q)))); S.hi(b) = q(min(numel(q), round(0.975 * numel(q)))); end
    end
    C = Mb - S.m;                                       % centred on the observed means: the joint distribution
    d = max(C, [], 2, 'omitnan') - min(C, [], 2, 'omitnan');   % = max over a ~= b of C_a - C_b
    d = sort(d(isfinite(d)));
    if ~isempty(d)
        S.q = d(min(numel(d), ceil(0.95 * numel(d))));
        S.U = S.point + S.q;
    end
end
if ismember(what, {'all', 'perm'})
    rp = RandStream('mt19937ar', 'Seed', seed(2));
    key = cs(:) * 1000 + cg(:);
    kk = unique(key); pmem = arrayfun(@(u) find(key == u), kk, 'UniformOutput', false);
    sx = sum(Sx, 2); sn = sum(Sn, 2);
    stat = zeros(B, 1);
    for c0 = 1:CH:B
        nc = min(CH, B - c0 + 1);
        PB = zeros(nU, nc);
        for u = 1:numel(pmem)
            ix = pmem{u}(:); nk = numel(ix);
            [~, o] = sort(rand(rp, nk, nc), 1);         % a permutation of the stratum's flights per resample
            PB(ix, :) = cb(ix(o));
        end
        Mp = zeros(nc, nb);
        for b = 1:nb
            L = double(PB == b);
            Mp(:, b) = ((sx' * L) ./ (sn' * L))';
        end
        stat(c0 + (0:nc-1)) = max(Mp, [], 2, 'omitnan') - min(Mp, [], 2, 'omitnan');
    end
    S.p = (1 + sum(stat >= S.point - 1e-12)) / (B + 1);
    S.perm_mean = mean(stat(isfinite(stat)));
end
end

function v = one_value(j, a, what)
% The value of a per cluster j, which must be one for all its episodes.
lo = accumarray(j, a(:), [], @min); hi = accumarray(j, a(:), [], @max);
if any(lo ~= hi), error('speed_inference:cluster', 'a flight lies in more than one %s', what); end
v = lo;
end

function d = spread(r)
r = r(isfinite(r));
if isempty(r), d = NaN; else, d = max(r) - min(r); end
end
