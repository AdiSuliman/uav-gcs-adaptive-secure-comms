function [seed, v_kmh] = clean_pool_seed(s, block, k, vrange, fams)
%CLEAN_POOL_SEED  Seed and UAV speed of clean-link geometry k (1-300) of
%   build_clean_test_pools.m at Eb/N0 index s: geometries 1-100 are those of family fams(1) of
%   the seed block, 101-200 of fams(2) and 201-300 of fams(3) (pool_seed.m), each family's
%   geometry mod(k - 1, 100) + 1. fams default [1 3 5] (the 'test' and 'val' sets; [7 8 9] the
%   fresh set, clean_set_layout.m). vrange [km/h] as pool_seed.m (optional, [] for none).
if nargin < 5 || isempty(fams), fams = [1 3 5]; end
i = 1 + floor((k - 1) / 100);
assert(all(k(:) >= 1 & i(:) <= numel(fams) & k(:) == round(k(:))), ...
    'clean_pool_seed: geometry %s outside 1-%d', mat2str(k), 100 * numel(fams));
f = reshape(fams(i), size(k)); r = mod(k - 1, 100) + 1;
if nargin < 4 || isempty(vrange)
    seed = pool_seed(f, s, block, r);
else
    [seed, v_kmh] = pool_seed(f, s, block, r, vrange);
end
end
