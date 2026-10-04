function A = overhead_drop_db(h, R0, hG, null_db, bank)
%OVERHEAD_DROP_DB  Largest drop of our signal below its cruise level while the UAV passes over the GCS [dB].
%   A = overhead_drop_db(h, R0, hG, null_db): a straight pass at altitude h [m] over a GCS
%   antenna on a hG [m] mast, from the cruise point at slant distance R0 [km] to overhead.
%   Along the pass our signal changes by the free-space term 20 log10(R0 / r) and by the
%   gain of the UAV dipole toward the GCS (uav_dipole_db.m, floored at null_db) against its
%   gain at the cruise point; A is the largest fall below the cruise level, 0 when the pass
%   never falls below it. Every antenna loses alike: to the receiver the drop is path loss.
%   A = overhead_drop_db(h, R0, hG, null_db, bank): the pass flown banked by bank [deg]
%   (a turn over the GCS): the tilted antenna's gain with its polarization loss
%   (uav_attitude_db.m), the worst over the GCS's bearing from the nose, against the
%   wings-level gain at the cruise point.
if nargin < 5, bank = 0; end
hh = h - hG;                                         % height over the GCS antenna [m]
R = 1000 * R0;
d = linspace(0, sqrt(max(R^2 - hh^2, 0)), 4001);     % horizontal distance to the GCS inside the cruise distance [m]
r = hypot(d, hh);
th = atand(hh ./ max(d, eps));                       % elevation of the GCS [deg]
g = uav_dipole_db(th, null_db);
if bank ~= 0
    g = min(uav_attitude_db(th, (0:5:355)', bank, 0, null_db), [], 1);
end
rel = 20*log10(R ./ r) + g - uav_dipole_db(asind(min(hh / R, 1)), null_db);
A = max(0, -min(rel));
end
