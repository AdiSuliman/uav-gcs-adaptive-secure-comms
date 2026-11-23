function [seed, v_kmh] = fresh_shadow_seed(g, s, j, vrange)
%FRESH_SHADOW_SEED  Seed and UAV speed of candidate j of the airframe-shadowing flights of the
%   fresh profile-3 test set (fresh_set_layout.m, build_policy_pools.m with FRESH_SET), as
%   shadow_pool_seed.m for the pools.
%   g      shadowing group, 1 to 8;  s  Eb/N0 index, 1 to 8;  j  candidate, 1 to 59 999
%   vrange [km/h] (optional): the speed, uniform in it from the seed's speed stream
%   Seeds 63 000 000 + 60 000 (8 (g - 1) + s - 1) + j: 63 000 001 to 66 839 999, above the pools'
%   candidates (shadow_pool_seed.m, up to 61 199 999) and the survivability options' (surv3_shadow_seed.m,
%   62 000 001 to 62 799 999), below 2^26 (seed_base.m).
assert(all(g(:) >= 1 & g(:) <= 8 & s(:) >= 1 & s(:) <= 8 & j(:) >= 1 & j(:) <= 59999 & j(:) == round(j(:))), ...
    'fresh_shadow_seed: group %s, Eb/N0 index %s or candidate %s outside its range', mat2str(g), mat2str(s), mat2str(j));
seed = 63000000 + 60000 * (8 * (g - 1) + s - 1) + j;
if nargout > 1
    v_kmh = vrange(1) + rand(seed_stream(seed, 'speed')) * (vrange(2) - vrange(1));
end
end
