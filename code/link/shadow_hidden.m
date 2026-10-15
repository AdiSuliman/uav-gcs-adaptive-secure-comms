function k = shadow_hidden(beta, el, roll, pitch, nr, roll_band, hdg_min, v, v_min, el_s)
%SHADOW_HIDDEN  The UAV antenna the airframe hides from the GCS, 0 when none.
%   k = shadow_hidden(beta, el, roll, pitch, nr, roll_band, hdg_min, v, v_min, el_s)
%   beta       broadside angle of the GCS [deg] (0 abeam on the right, 90 ahead; gcs_aoa.m),
%              as it turns with the heading
%   el         elevation of the GCS below the UAV's horizon [deg]; roll, pitch [deg]
%   nr         antennas of the line array along the fuselage
%   roll_band  [lo hi] rolls [deg] of Sun et al.'s geometry at which the level is flown
%              (shadow_roll_band.m)
%   hdg_min    smallest difference between the heading and the GCS azimuth [deg]
%   v, v_min   speed [m/s] and the speed below which no antenna is hidden
%   el_s       elevation of Sun et al.'s events [deg] (shadow_equiv_roll.m)
%   The airframe lies in the line of sight of the belly antennas when the GCS is above
%   their horizon in the body frame (cz < 0, uav_attitude_db.m: the UAV banks toward the
%   GCS by more than its elevation), the GCS lies more than hdg_min off the heading (Sun
%   et al., Part IV, Sec. III) and the event is one the level's depth is measured in: the
%   roll buries the line of sight, at its deepest with the GCS abeam, as deep as the rolls
%   of the level's band do at Sun et al.'s elevation (the equivalent roll,
%   shadow_equiv_roll.m; Sec. II, Table II). No source measures shadowing while hovering or
%   holding position in wind, so none below v_min. The hidden antenna is the end of the
%   array farther from the GCS along the fuselage: its line of sight runs along the
%   airframe, the other end's clear of it (the array's phase convention,
%   build_threat_model.m: positions grow aft).
%#codegen
k = 0;
if v < v_min, return; end
e = shadow_equiv_roll(0, el, abs(roll), pitch, el_s);
if ~(e >= roll_band(1) && e <= roll_band(2)), return; end
d = abs(mod(90 - beta + 180, 360) - 180);                 % heading minus GCS azimuth [deg]
if d <= hdg_min, return; end
[~, ca, cz] = uav_attitude_db(el, beta, roll, pitch, -30);
if cz >= 0, return; end                                   % the belly sees the GCS
if ca >= 0, k = nr; else, k = 1; end
end
