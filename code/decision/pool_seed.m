function [seed, v_kmh] = pool_seed(sc, s, sp, r, vrange)
%POOL_SEED  Seed and UAV speed of one decision-layer pool geometry (D44-D46, D51, D52, D59).
%   sc  geometry family: 1 for every pool since D59 (the clean link and every
%       threat cell fly the same geometries, so an episode's frames before and
%       after the onset come from one flight)
%   s   Eb/N0 index
%   sp  seed block: 1 train, 5 validation, 6 test pools (build_policy_pools.m);
%       7 clean test and 4 clean validation geometries (build_clean_test_pools.m).
%       Blocks 2 and 3 hold the test flights of the first two test readings (D64)
%       and are not used again.
%   r   geometry (at most 99 per block)
%   The seed is shared by every configuration (common random numbers); the speed
%   is the first draw of the seed's stream, uniform in vrange [km/h].
seed = 800000 + 20000*sc + 1000*s + 100*sp + r;
if nargout > 1
    rs = RandStream('mt19937ar', 'Seed', seed);
    v_kmh = vrange(1) + rand(rs) * (vrange(2) - vrange(1));
end
end
