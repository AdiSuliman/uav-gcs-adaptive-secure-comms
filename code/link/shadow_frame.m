function [k, g] = shadow_frame(beta, el, roll, ev, pitch, nr, roll_band, hdg_min, v, v_min)
%SHADOW_FRAME  The UAV antenna the airframe hides from the GCS and the share of the
%   event's depth it has lost, at one attitude or a vector of them.
%   [k, g] = shadow_frame(beta, el, roll, ev, pitch, nr, roll_band, hdg_min, v, v_min)
%   beta, roll  GCS direction and roll [deg] (turn_attitude.m), scalars or equal vectors
%   el, pitch   elevation of the GCS below the UAV's horizon and the pitch [deg]
%   ev          [bank r_s]: the turn's bank [deg], the event's largest roll, and the roll at
%               which the event started during a roll-in (0, or absent, without one)
%   nr          antennas of the line array along the fuselage
%   roll_band   [lo hi] rolls [deg] the level is flown at (shadow_roll_band.m)
%   hdg_min     smallest difference between the heading and the GCS azimuth [deg]
%   v, v_min    speed [m/s] and the speed below which no antenna is hidden
%   k           hidden antenna (0 none): shadow_hidden.m's geometry at the attitude (the
%               GCS above the belly's horizon, more than hdg_min off the heading, the far
%               end of the array), with the level's band on the bank, the event's largest
%               roll (Sun et al., Table II pair the median loss with it)
%   g           share of the depth: Sun et al.'s shape of the loss within an event (Part
%               IV, Sec. IV-C, eq. 8: a cubic spline through (0, 0), (0.5, 1) and (1, 0) of
%               the event's duration; its rising half f(x) = (3x - x^3) / 2), x the progress
%               of the roll from the event's start (where the GCS reaches the belly's
%               horizon, or r_s where the heading's criterion came later) to the bank; 1 in
%               a turn that holds its bank, 0 where k is 0
%#codegen
bank = ev(1); rs = 0;
if numel(ev) > 1, rs = ev(2); end
k = zeros(size(beta)); g = zeros(size(beta));
if v < v_min || bank < roll_band(1) || bank > roll_band(2), return; end
d = abs(mod(90 - beta + 180, 360) - 180);                 % heading minus GCS azimuth [deg]
[~, ca, cz] = uav_attitude_db(el, beta, roll, pitch, -30);
on = d > hdg_min & cz < 0;
ux = cosd(el) .* sind(beta); uy = cosd(el) .* cosd(beta); uz = sind(el);
rc = max(rs, atand((sind(pitch) .* ux + cosd(pitch) .* uz) ./ max(abs(uy), 1e-12)));   % roll where the event starts
x = min(1, max(0, (abs(roll) - rc) ./ max(bank - rc, 1e-9)));
x(bank <= rc) = 1;
k(on & ca >= 0) = nr;
k(on & ca < 0) = 1;
gx = (3 * x - x .^ 3) / 2;
g(on) = gx(on);
end
