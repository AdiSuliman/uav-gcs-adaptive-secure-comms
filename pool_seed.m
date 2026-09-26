function [seed, v_kmh] = pool_seed(sc, s, sp, r, vrange)
%POOL_SEED  Seed and UAV speed of one decision-layer pool sub-run (D44-D46).
%   sc scenario index in PP.scen, s Eb/N0 index, sp split (1 train, 2 test),
%   r sub-run. The seed is shared by every configuration of the cell (common
%   random numbers); the speed is the first draw of the seed's stream, uniform
%   in vrange [km/h]. Single source for build_policy_pools.m and the analyses.
seed = 800000 + 20000*sc + 1000*s + 100*sp + r;
if nargout > 1
    rs = RandStream('mt19937ar', 'Seed', seed);
    v_kmh = vrange(1) + rand(rs) * (vrange(2) - vrange(1));
end
end
