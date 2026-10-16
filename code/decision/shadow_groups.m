function [g, band, lv] = shadow_groups(level, p)
%SHADOW_GROUPS  Pool cells that fly the same airframe-shadowing geometries.
%   [g, band, lv] = shadow_groups(level, p): level of every cell's airframe-shadowing
%   component [dB] (NaN: none). An antenna is hidden only at the rolls the level is flown at
%   (shadow_roll_band.m) and the depth enters nowhere else (shadow_hidden.m), so two levels
%   with the same band hide an antenna on exactly the same flights and share them, as every
%   cell shares the other geometries (common random numbers); levels with different bands
%   fly flights selected for their own.
%   g     group of every cell, 0 without airframe shadowing, numbered in the order of the
%         cells
%   band  groups x 2, the rolls [deg] of each group
%   lv    1 x groups, a level of each group (its first cell's), for the selection
g = zeros(1, numel(level)); band = zeros(0, 2); lv = zeros(1, 0);
for c = find(isfinite(level(:)'))
    b = shadow_roll_band(level(c), p);
    k = find(all(abs(band - b) < 1e-9, 2), 1);
    if isempty(k)
        band(end+1, :) = b; lv(end+1) = level(c); %#ok<AGROW>
        k = size(band, 1);
    end
    g(c) = k;
end
end
