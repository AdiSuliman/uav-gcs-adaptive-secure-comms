function k = shadow_hidden(beta, el, roll, pitch, nr, roll_min, hdg_min)
%SHADOW_HIDDEN  The UAV antenna the airframe hides from the GCS, 0 when none.
%   k = shadow_hidden(beta, el, roll, pitch, nr, roll_min, hdg_min)
%   beta    broadside angle of the GCS [deg] (0 abeam on the right, 90 ahead; gcs_aoa.m),
%           as it turns with the heading
%   el      elevation of the GCS below the UAV's horizon [deg]; roll, pitch [deg]
%   nr      antennas of the line array along the fuselage
%   Airframe shadowing occurs only while the roll exceeds roll_min and the GCS lies more
%   than hdg_min off the heading (Sun et al., Part IV, Sec. III: roll > 5 deg, heading
%   minus azimuth > 30 deg). The hidden antenna is the end of the array farther from the
%   GCS along the fuselage: its line of sight runs along the airframe, the other end's
%   clear of it (the array's phase convention, build_threat_model.m: positions grow aft).
%#codegen
k = 0;
d = abs(mod(90 - beta + 180, 360) - 180);                 % heading minus GCS azimuth [deg]
if abs(roll) <= roll_min || d <= hdg_min, return; end
ca = cosd(pitch) * cosd(el) * sind(beta) - sind(pitch) * sind(el);   % forward component of the GCS direction
if ca >= 0, k = nr; else, k = 1; end
end
