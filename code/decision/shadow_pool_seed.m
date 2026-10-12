function [seed, v_kmh] = shadow_pool_seed(g, s, block, j, vrange)
%SHADOW_POOL_SEED  Seed and UAV speed of candidate j of the airframe-shadowing geometries of
%   the decision-layer pools (build_policy_pools.m, build_check_pools.m). A shadowing group
%   (shadow_groups.m) flies the candidates j = 1, 2, ... in turn whose attitude hides an
%   antenna at its level (hides_antenna.m, pool_geometries.m with a selection); every
%   candidate is tried once, kept or skipped.
%   g      shadowing group, 1 to 8
%   s      Eb/N0 index, 1 to 8
%   block  seed block of the split (pool_seed.m): 1, 5, 10, 14, 16, 17, 18 or 19
%   j      candidate, 1 to 99 999
%   vrange [km/h] (optional): the speed, uniform in it from the seed's speed stream
%          (seed_stream.m), as pool_seed.m
%   Seeds 10 000 000 + 100 000 (64 (g - 1) + 8 (s - 1) + block position) + j: 10 000 001 to
%   61 199 999, above every other flight seed (pool_seed.m below 2 000 000, the dataset, B4
%   and B4s below 6 000 000) and below 2^26 (seed_base.m), so no candidate is another
%   flight and no two (group, Eb/N0, block, candidate) share a seed.
BLOCKS = [1 5 10 14 16 17 18 19];
b = find(BLOCKS == block, 1);
assert(~isempty(b), 'shadow_pool_seed: seed block %d holds no shadowing geometries', block);
assert(all(g(:) >= 1 & g(:) <= 8 & s(:) >= 1 & s(:) <= 8 & j(:) >= 1 & j(:) <= 99999 & j(:) == round(j(:))), ...
    'shadow_pool_seed: group %s, Eb/N0 index %s or candidate %s outside its range', mat2str(g), mat2str(s), mat2str(j));
seed = 10000000 + 100000 * (64 * (g - 1) + 8 * (s - 1) + b - 1) + j;
if nargout > 1
    v_kmh = vrange(1) + rand(seed_stream(seed, 'speed')) * (vrange(2) - vrange(1));
end
end
