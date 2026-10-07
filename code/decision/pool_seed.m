function [seed, v_kmh] = pool_seed(sc, s, sp, r, vrange)
%POOL_SEED  Seed and UAV speed of one decision-layer pool geometry.
%   sc  geometry family: 1 for every pool (the clean link and every threat cell
%       fly the same geometries, so an episode's frames before and after the
%       onset come from one flight); 2 the off-grid check flights
%       (build_check_pools.m, block 10); 3 and 5 the clean-link geometries 101-200
%       and 201-300 of build_clean_test_pools.m (blocks 4 and 15)
%   s   Eb/N0 index
%   sp  seed block: 1 train, 5 validation, 14 test, 16 edge-speed and 17 second test
%       pools (build_policy_pools.m); 4 clean validation and 15 clean test geometries
%       (build_clean_test_pools.m); 13 the geometries of
%       experiment_survivability_options.m; 18 and 19 the test pools of the reduced
%       chain check (run_stage smoke), so its flights are never test flights. Blocks 2,
%       3, 6 to 9, 10, 11 and 12 hold the test flights of earlier test readings and are
%       not used again.
%   r   geometry (at most 99 per block)
%   The seed is shared by every configuration (common random numbers); the speed
%   comes from the seed's speed stream (seed_stream.m), uniform in vrange [km/h] (one
%   stratum of the speed range in a stratified design, pool_geometries.m).
%   Blocks 10 and above take their own seed range, so no two (Eb/N0, block,
%   geometry) triples share a seed.
if sp < 10
    seed = 800000 + 20000*sc + 1000*s + 100*sp + r;
else
    seed = 1800000 + 20000*sc + 1000*s + 100*(sp - 10) + r;
end
if nargout > 1
    v_kmh = vrange(1) + rand(seed_stream(seed, 'speed')) * (vrange(2) - vrange(1));
end
end
