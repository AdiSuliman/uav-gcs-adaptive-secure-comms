function [g, info] = pool_geometries(s, block, r, vr, p, lhs_seed, fam, sel)
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
%   [g, info] = pool_geometries(..., fam, sel)  flights selected from candidates (the
%       airframe-shadowing cells' own, build_policy_pools.m): flight i takes the first
%       candidate j = sel.j0 + 1, sel.j0 + 2, ... (each tried once, kept or skipped) whose
%       draws in flight i's strata satisfy sel.keep(seed, speed, alt, ksig, aoa1, rho)
%       (hides_antenna.m); [seed, speed] = sel.seed(j, speed range) (shadow_pool_seed.m),
%       the other values the candidate's own draws as above; at most sel.jmax candidates.
%       With sel.floor(alt), the slowest speed [km/h] at which a candidate at altitude alt
%       can be kept (shadow_alt_floor.m), a Latin hypercube's speed strata cut the speeds
%       from max(vr(1), sel.floor(alt)) to vr(2) at the candidate's altitude (drawn first,
%       in its stratum), so no flight is asked for where none can be kept; the same strata
%       as without it where the floor lies at or below vr(1); a candidate whose altitude no
%       speed of the range reaches is skipped.
%       r only numbers the runs. info.tries: candidates tried per flight; info.j: the last.
%   g: seed, speed [km/h], run (100 block + r), alt [m], ksig [dB], aoa1 [deg] and rho
%      (NaN: the flight's own draw), 1 x n each
n = numel(r);
if nargin < 8, sel = []; end
if isempty(sel) && any(r < 1 | r > 99), error('pool_geometries: at most 99 geometries per seed block'); end
if nargin < 7 || isempty(fam), fam = 1; end
seed = zeros(1, n); v = zeros(1, n); alt = nan(1, n); ksig = nan(1, n); aoa1 = nan(1, n); rho = nan(1, n);
lhs = nargin >= 6 && ~isempty(lhs_seed);
if lhs
    rs = RandStream('mt19937ar', 'Seed', lhs_seed);
    q = [randperm(rs, n); randperm(rs, n); randperm(rs, n); randperm(rs, n); randperm(rs, n)] - 1;   % stratum per axis
elseif size(vr, 1) == 1
    vr = repmat(vr, n, 1);
end
st = @(rg, k) rg(1) + (rg(2) - rg(1)) * [k, k + 1] / n;               % bounds of stratum k of range rg
tries = zeros(1, n); j = 0;
if ~isempty(sel), j = sel.j0; end
for i = 1:n
    if lhs, vri = st(vr, q(1, i)); else, vri = vr(i, :); end
    if isempty(sel)
        [seed(i), v(i)] = pool_seed(fam, s, block, r(i), vri);
        if lhs, [alt(i), ksig(i), aoa1(i), rho(i)] = strata_draws(seed(i), p, q(:, i), st); end
        continue
    end
    while true
        j = j + 1; tries(i) = tries(i) + 1;
        if j > sel.jmax
            error('pool_geometries: no candidate up to %d hides an antenna (Eb/N0 index %d, block %d)', sel.jmax, s, block);
        end
        [sd, vv] = sel.seed(j, vri);
        a = NaN; k = NaN; o = NaN; c = NaN;
        if lhs, [a, k, o, c] = strata_draws(sd, p, q(:, i), st); end
        if lhs && isfield(sel, 'floor') && isfinite(a)
            vf = max(vr(1), sel.floor(a));              % the speeds at which this altitude can be kept
            if vf >= vr(2), continue; end
            [sd, vv] = sel.seed(j, st([vf vr(2)], q(1, i)));
        end
        if sel.keep(sd, vv, a, k, o, c), break; end
    end
    seed(i) = sd; v(i) = vv; alt(i) = a; ksig(i) = k; aoa1(i) = o; rho(i) = c;
end
g = struct('seed', seed, 'speed', v, 'run', 100 * block + r, 'alt', alt, 'ksig', ksig, 'aoa1', aoa1, 'rho', rho);
info = struct('tries', tries, 'j', j);
end

function [alt, ksig, aoa1, rho] = strata_draws(seed, p, q, st)
% The flight's own altitude, K of our signal, first interferer direction and receive
% correlation inside its strata q(2:5) (NaN where the draw is off in p).
alt = NaN; ksig = NaN; aoa1 = NaN; rho = NaN;
if isfield(p, 'alt_random') && p.alt_random
    pa = p; pa.alt_range_m = st(p.alt_range_m, q(2));
    alt = flight_altitude(seed, pa);
end
if isfield(p, 'k_random') && p.k_random
    k = channel_k(seed, st(p.k_range_db, q(3)));
    ksig = k(1);
end
if isfield(p, 'int_aoa_random') && p.int_aoa_random
    aoa1 = interferer_aoa(seed, st(p.int_aoa_range_deg, q(4)), 1);
end
if isfield(p, 'corr_random') && p.corr_random
    rho = rx_correlation(seed, st(p.corr_range, q(5)));
end
end
