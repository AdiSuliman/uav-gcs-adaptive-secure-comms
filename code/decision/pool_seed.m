function [seed, v_kmh] = pool_seed(sc, s, sp, r, vrange)
%POOL_SEED  Seed and UAV speed of one decision-layer pool geometry.
%   sc  geometry family: 1 for every pool (the clean link and every threat cell
%       fly the same geometries, so an episode's frames before and after the
%       onset come from one flight)
%   s   Eb/N0 index
%   sp  seed block: 1 train, 5 validation, 10 test and 12 unseen-speed pools
%       (build_policy_pools.m); 4 clean validation and 11 clean test geometries
%       (build_clean_test_pools.m); 13 the geometries of
%       experiment_survivability_options.m. Blocks 2, 3 and 6 to 9 hold the test flights of
%       earlier test readings and are not used again.
%   r   geometry (at most 99 per block)
%   The seed is shared by every configuration (common random numbers); the speed
%   is the first draw of the seed's stream, uniform in vrange [km/h].
%   Blocks 10 and above take their own seed range, so no two (Eb/N0, block,
%   geometry) triples share a seed.
if sp < 10
    seed = 800000 + 20000*sc + 1000*s + 100*sp + r;
else
    seed = 1800000 + 20000*sc + 1000*s + 100*(sp - 10) + r;
end
if nargout > 1
    rs = RandStream('mt19937ar', 'Seed', seed);
    v_kmh = vrange(1) + rand(rs) * (vrange(2) - vrange(1));
end
end
