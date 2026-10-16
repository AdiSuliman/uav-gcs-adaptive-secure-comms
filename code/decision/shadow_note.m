function [txt, share, env, lv] = shadow_note(SH, sp, ebno)
%SHADOW_NOTE  The statement every airframe-shadowing reading carries: its flights are
%   selected to hide an antenna (build_policy_pools.m, build_check_pools.m), so its results
%   hold conditioned on such a geometry, with the share of the flights that hide one beside.
%   [txt, share, env, lv] = shadow_note(SH, sp, ebno)
%   SH    PP.shadow (or CK.shadow): groups' bands and levels, the candidates tried and kept
%         per (group, split, Eb/N0), the count (groups x [tried kept] x Eb/N0) of the
%         candidates drawn after the designs, independently and uniformly over the group's
%         speeds with their own altitudes, counted only, the speeds each group is flown at
%         (v_kmh, groups x 2: from shadow_speed_floor.m) and the envelope's (speed_range)
%   sp    splits pooled without a count (the edge speeds' fixed 161 km/h excluded by the
%         caller)
%   ebno  Eb/N0 grid [dB]
%   share groups x Eb/N0: kept / tried of the count, the share of the flights over
%         the group's speeds and the altitudes that hide an antenna at its level. A Latin
%         hypercube's kept / tried is not that share: each of its flights tries candidates
%         in its own strata, from the floor at its altitude up (pool_geometries.m), until one
%         hides an antenna, so its count of tries weighs the strata where few do. env: the
%         same over the whole speed envelope (no slower flight hides one, and the speeds are
%         uniform: share times the fraction of the envelope the group is flown over); lv: the
%         levels of each group
%   txt   '' without shadowing groups
txt = ''; share = zeros(0, numel(ebno)); env = share; lv = {};
if isempty(SH) || ~isfield(SH, 'level') || isempty(SH.level), return; end
nGr = numel(SH.level);
v = SH.v_kmh; if size(v, 1) < nGr, v = repmat(v(1, :), nGr, 1); end
if isfield(SH, 'count') && any(SH.count(:, 1, :) > 0, 'all')
    share = squeeze(SH.count(:, 2, :) ./ SH.count(:, 1, :));
else
    share = squeeze(sum(SH.kept(:, sp, :), 2) ./ sum(SH.tried(:, sp, :), 2));
end
share = reshape(share, nGr, []);
env = share .* (diff(v, 1, 2) / diff(SH.speed_range));
lv = arrayfun(@(k) strjoin(compose('%g', SH.cell_levels{k}), '/'), 1:nGr, 'UniformOutput', false);
parts = arrayfun(@(k) sprintf('%s dB (rolls %.1f-%.1f deg, flown from %.1f km/h) %s of the flights, %s of the envelope', ...
    lv{k}, SH.band(k, :), v(k, 1), rng_txt(share(k, :)), rng_txt(env(k, :))), 1:nGr, 'UniformOutput', false);
txt = sprintf(['Airframe shadowing, alone and in combinations, flies flights selected before simulation so that the ' ...
    'attitude hides an antenna at its level in some frame (hides_antenna.m): its readings hold conditioned on such a ' ...
    'geometry. Share of the flights that hide one, over Eb/N0 %s dB: %s. None is flown at hover or below %.1f km/h ' ...
    '(no source measures shadowing there), nor a level below the speed whose turn, at the flight''s altitude, buries ' ...
    'the line of sight as deep as its smallest roll (shadow_speed_floor.m, shadow_alt_floor.m): outside the sources.'], ...
    strjoin(compose('%g', ebno), '/'), strjoin(parts, '; '), min(v(:, 1)));
end

function s = rng_txt(x)
x = 100 * x(isfinite(x));
if isempty(x), s = '-'; elseif max(x) - min(x) < 0.05, s = sprintf('%.1f%%', x(1)); else, s = sprintf('%.1f-%.1f%%', min(x), max(x)); end
end
