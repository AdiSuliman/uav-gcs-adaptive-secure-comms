function [seed, v_kmh] = clean_pool_seed(s, block, k, vrange)
%CLEAN_POOL_SEED  Seed and UAV speed of clean-link geometry k (1-300) of
%   build_clean_test_pools.m at Eb/N0 index s: geometries 1-100 are those of family 1 of
%   the seed block, 101-200 of family 3 and 201-300 of family 5 (pool_seed.m), each
%   family's geometry mod(k - 1, 100) + 1. vrange [km/h] as pool_seed.m (optional).
f = 1 + 2 * floor((k - 1) / 100); r = mod(k - 1, 100) + 1;
if nargin < 4
    seed = pool_seed(f, s, block, r);
else
    [seed, v_kmh] = pool_seed(f, s, block, r, vrange);
end
end
