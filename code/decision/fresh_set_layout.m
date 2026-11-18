function L = fresh_set_layout(smoke)
%FRESH_SET_LAYOUT  The fresh profile-3 test set of the weak-point fixes (weak19_reading.m): flights
%   no earlier set flew, read once.
%   Threat pools (build_policy_pools.m with FRESH_SET true): the test split's layout, every cell
%   (clean link, single threats at five severities, combined threats at three), L.ngeo geometries
%   per (cell, Eb/N0), geometry family L.fam of seed block L.block (pool_seed.m), nested Latin
%   hypercubes from L.lhs_seed, the shadowing groups' own flights from fresh_shadow_seed.m
%   -> L.out; finished cells kept in data/L.ckd.
%   Clean pools (build_clean_test_pools.m with CLEAN_SET L.clean): 300 geometries per Eb/N0,
%   families 7, 8, 9 of block 17 (clean_set_layout.m) -> data/clean_w19_pools.mat.
%   smoke true: block 18 and 2 geometries, the reduced chain check's own flights (its shadowing
%   candidates shadow_pool_seed.m's block 18), never the set's.
%   Stops when (L.fam, L.block) belongs to another set (pool_seed_owner.m).
if nargin < 1, smoke = false; end
L = struct('fam', 4, 'block', 14, 'ngeo', 24, 'lhs_seed', 7400000, 'out', 'data/fresh_test_pools.mat', ...
    'ckd', 'c1p_fresh_cells', 'clean', 'w19', 'smoke', logical(smoke));
if smoke, L.block = 18; L.ngeo = 2; L.out = 'data/fresh_test_pools_smoke.mat'; L.ckd = 'c1p_fresh_smoke_cells'; end
own = pool_seed_owner(L.fam, L.block);
if ~strcmp(own, 'fresh_threat')
    error('fresh_set_layout:reuse', 'fresh_set_layout: family %d of block %d is not the fresh set''s (%s)', L.fam, L.block, own);
end
end
