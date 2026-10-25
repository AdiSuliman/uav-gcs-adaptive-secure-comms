function [seed, v_kmh] = surv3_shadow_seed(s, j, vrange)
%SURV3_SHADOW_SEED  Seed and UAV speed of candidate j of the airframe-shadowing flights of
%   experiment_survivability_options.m under surv_v2 (surv3_shadow_flights.m).
%   s      Eb/N0 index, 1 to 8
%   j      candidate, 1 to 99 999
%   vrange [km/h] (optional): the speed, uniform in it from the seed's speed stream
%          (seed_stream.m), as pool_seed.m
%   Seeds 62 000 000 + 100 000 (s - 1) + j: 62 000 001 to 62 799 999, above the pools'
%   shadowing candidates (shadow_pool_seed.m, up to 61 199 999; its block position takes no
%   ninth block) and below 2^26 (seed_base.m), so no candidate is another flight.
assert(all(s(:) >= 1 & s(:) <= 8 & s(:) == round(s(:)) & j(:) >= 1 & j(:) <= 99999 & j(:) == round(j(:))), ...
    'surv3_shadow_seed: Eb/N0 index %s or candidate %s outside its range', mat2str(s), mat2str(j));
seed = 62000000 + 100000 * (s - 1) + j;
if nargout > 1
    v_kmh = vrange(1) + rand(seed_stream(seed, 'speed')) * (vrange(2) - vrange(1));
end
end
