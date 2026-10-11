function k = shadow_hidden(beta, el, roll, pitch, nr, roll_band, hdg_min, v, v_min)
%SHADOW_HIDDEN  The UAV antenna the airframe hides from the GCS, 0 when none.
%   k = shadow_hidden(beta, el, roll, pitch, nr, roll_band, hdg_min, v, v_min)
%   beta       broadside angle of the GCS [deg] (0 abeam on the right, 90 ahead; gcs_aoa.m),
%              as it turns with the heading
%   el         elevation of the GCS below the UAV's horizon [deg]; roll, pitch [deg]
%   nr         antennas of the line array along the fuselage
%   roll_band  [lo hi] rolls [deg] at which the level is flown (shadow_roll_band.m)
%   hdg_min    smallest difference between the heading and the GCS azimuth [deg]
%   v, v_min   speed [m/s] and the speed below which no antenna is hidden
%   The airframe lies in the line of sight of the belly antennas when the GCS is above
%   their horizon in the body frame (cz < 0, uav_attitude_db.m: the UAV banks toward the
%   GCS by more than its elevation), the GCS lies more than hdg_min off the heading (Sun
%   et al., Part IV, Sec. III) and the roll is one the level's depth is measured at (Sun et
%   al., Table II). No source measures shadowing while hovering or holding position in wind,
%   so none below v_min. The hidden antenna is the end of the array farther from the GCS
%   along the fuselage: its line of sight runs along the airframe, the other end's clear of
%   it (the array's phase convention, build_threat_model.m: positions grow aft).
%#codegen
k = 0;
if v < v_min, return; end
r = abs(roll);
if r < roll_band(1) || r > roll_band(2), return; end
d = abs(mod(90 - beta + 180, 360) - 180);                 % heading minus GCS azimuth [deg]
if d <= hdg_min, return; end
[~, ca, cz] = uav_attitude_db(el, beta, roll, pitch, -30);
if cz >= 0, return; end                                   % the belly sees the GCS
if ca >= 0, k = nr; else, k = 1; end
end
