function [k, g] = shadow_frame(beta, el, roll, ev, pitch, nr, roll_band, hdg_min, v, v_min, el_s)
%SHADOW_FRAME  The UAV antenna the airframe hides from the GCS and the share of the
%   event's depth it has lost, at one attitude or a vector of them.
%   [k, g] = shadow_frame(beta, el, roll, ev, pitch, nr, roll_band, hdg_min, v, v_min, el_s)
%   beta, roll  GCS direction and roll [deg] (turn_attitude.m), scalars or equal vectors
%   el, pitch   elevation of the GCS below the UAV's horizon and the pitch [deg]
%   ev          [bank r_s]: the turn's bank [deg], the event's largest roll, and the roll at
%               which the event started during a roll-in (0, or absent, without one)
%   nr          antennas of the line array along the fuselage
%   roll_band   [lo hi] rolls [deg] of Sun et al.'s geometry the level is flown at
%               (shadow_roll_band.m)
%   hdg_min     smallest difference between the heading and the GCS azimuth [deg]
%   v, v_min    speed [m/s] and the speed below which no antenna is hidden
%   el_s        elevation of Sun et al.'s events [deg] (shadow_equiv_roll.m)
%   k           hidden antenna (0 none): shadow_hidden.m's geometry at the attitude (the
%               GCS above the belly's horizon, more than hdg_min off the heading, the far
%               end of the array) in an event the level is flown in: the equivalent roll of
%               its deepest burial, at the bank with the GCS abeam, in the level's band
%               (shadow_equiv_roll.m; Sun et al., Table II pair the median loss with the
%               event's largest roll)
%   g           share of the depth: Sun et al.'s shape of the loss within an event (Part
%               IV, Sec. IV-C, eq. 8: a cubic spline through (0, 0), (0.5, 1) and (1, 0) of
%               the event's duration; its rising half f(x) = (3x - x^3) / 2), x the progress
%               of the burial from the event's start (the GCS on the belly's horizon, or r_s
%               where the heading's criterion came later) to its deepest: 1 with the bank
%               held and the GCS abeam, less as a roll-in builds up or the turn carries the
%               GCS off the beam; 0 where k is 0
%#codegen
bank = ev(1); rs = 0;
if numel(ev) > 1, rs = ev(2); end
k = zeros(size(beta)); g = zeros(size(beta));
if v < v_min, return; end
[ep, dp] = shadow_equiv_roll(0, el, bank, pitch, el_s);    % the event's deepest burial and its equivalent roll
if ~(ep >= roll_band(1) && ep <= roll_band(2)), return; end
d = abs(mod(90 - beta + 180, 360) - 180);                 % heading minus GCS azimuth [deg]
[~, ca, cz] = uav_attitude_db(el, beta, roll, pitch, -30);
on = d > hdg_min & cz < 0;
[~, dl] = shadow_equiv_roll(beta, el, abs(roll), pitch, el_s);
ds = zeros(size(beta));
if rs > 0
    [~, ds] = shadow_equiv_roll(beta, el, rs, pitch, el_s);   % the burial where the event started
    ds = max(ds, 0);
end
x = min(1, max(0, (dl - ds) ./ max(dp - ds, 1e-9)));
x(dp <= ds) = 1;
k(on & ca >= 0) = nr;
k(on & ca < 0) = 1;
gx = (3 * x - x .^ 3) / 2;
g(on) = gx(on);
end
