function g = pool_geometries(s, block, r, vr, p, lhs_seed, fam)
%POOL_GEOMETRIES  Seeded flights of one pool split at one Eb/N0 (build_policy_pools.m).
%   g = pool_geometries(s, block, r, vr, p)            flights r of the seed block
%       (pool_seed.m), speed uniform in vr [km/h] (1 x 2, or one row per flight);
%       altitude, K of our signal, interferer directions and receive correlation stay
%       the flights' own draws
%   g = pool_geometries(s, block, r, vr, p, lhs_seed)  the same flights laid out as a
%       Latin hypercube over speed (vr), altitude (p.alt_range_m), K of our signal
%       (p.k_range_db), the direction of the first interferer (p.int_aoa_range_deg)
%       and the receive correlation (p.corr_range): each axis is cut into n = numel(r)
%       equal strata, and a random permutation per axis (stream seeded lhs_seed) gives
%       every flight its own stratum; inside its stratum each value is the flight's own
%       draw (seed_stream.m). The designs nest: a stratum of 12 flights is 2 strata of
%       24 and 5 of 60, and each design puts n/6 flights in every sixth of the speed
%       range and n/3 in every third of the altitude range. An axis whose draw is off in
%       p (alt_random, k_random, int_aoa_random, corr_random) is not stratified.
%   g = pool_geometries(..., fam)  flights of geometry family fam (pool_seed.m, default 1)
%   g: seed, speed [km/h], run (100 block + r), alt [m], ksig [dB], aoa1 [deg] and rho
%      (NaN: the flight's own draw), 1 x n each
n = numel(r);
if any(r < 1 | r > 99), error('pool_geometries: at most 99 geometries per seed block'); end
if nargin < 7 || isempty(fam), fam = 1; end
seed = zeros(1, n); v = zeros(1, n); alt = nan(1, n); ksig = nan(1, n); aoa1 = nan(1, n); rho = nan(1, n);
if nargin < 6 || isempty(lhs_seed)
    if size(vr, 1) == 1, vr = repmat(vr, n, 1); end
    for i = 1:n
        [seed(i), v(i)] = pool_seed(fam, s, block, r(i), vr(i, :));
    end
else
    rs = RandStream('mt19937ar', 'Seed', lhs_seed);
    q = [randperm(rs, n); randperm(rs, n); randperm(rs, n); randperm(rs, n); randperm(rs, n)] - 1;   % stratum per axis
    st = @(rg, k) rg(1) + (rg(2) - rg(1)) * [k, k + 1] / n;           % bounds of stratum k of range rg
    pa = p;
    for i = 1:n
        [seed(i), v(i)] = pool_seed(fam, s, block, r(i), st(vr, q(1, i)));
        if isfield(p, 'alt_random') && p.alt_random
            pa.alt_range_m = st(p.alt_range_m, q(2, i));
            alt(i) = flight_altitude(seed(i), pa);
        end
        if isfield(p, 'k_random') && p.k_random
            k = channel_k(seed(i), st(p.k_range_db, q(3, i)));
            ksig(i) = k(1);
        end
        if isfield(p, 'int_aoa_random') && p.int_aoa_random
            aoa1(i) = interferer_aoa(seed(i), st(p.int_aoa_range_deg, q(4, i)), 1);
        end
        if isfield(p, 'corr_random') && p.corr_random
            rho(i) = rx_correlation(seed(i), st(p.corr_range, q(5, i)));
        end
    end
end
g = struct('seed', seed, 'speed', v, 'run', 100 * block + r, 'alt', alt, 'ksig', ksig, 'aoa1', aoa1, 'rho', rho);
end
