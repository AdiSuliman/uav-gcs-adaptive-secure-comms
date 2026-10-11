function [band, r0] = shadow_roll_band(depth_db, p)
%SHADOW_ROLL_BAND  Rolls at which an airframe-shadowing level is flown.
%   [band, r0] = shadow_roll_band(depth_db, p): Sun et al. fit the median loss of an event
%   against its largest roll, S = A + n (roll - r1) + X, X ~ N(0, sigma^2), r1 the smallest
%   roll of the measured events (Part IV, Table II; p.shadow_fit = [A n sigma] of C-band,
%   p.shadow_roll_deg = r1). band = [lo hi] [deg]: the rolls in [r1, p.roll_max_deg] whose
%   fit lies within p.shadow_fit_z sigma of depth_db ([Inf -Inf] when none does, the level
%   is never flown). r0: the roll at which the fit equals the depth, inside the band (the
%   bank of a fixed geometry: maps, gallery, console).
f = p.shadow_fit; r1 = p.shadow_roll_deg; r2 = p.roll_max_deg; z = p.shadow_fit_z;
lo = max(r1, r1 + (depth_db - f(1) - z * f(3)) / f(2));
hi = min(r2, r1 + (depth_db - f(1) + z * f(3)) / f(2));
if lo > hi
    band = [Inf -Inf]; r0 = NaN;
    return
end
band = [lo hi];
r0 = min(max(r1 + (depth_db - f(1)) / f(2), lo), hi);
end
