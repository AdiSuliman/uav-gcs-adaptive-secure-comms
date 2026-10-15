function [beta, roll, dpsi] = turn_attitude(att, yaw, t)
%TURN_ATTITUDE  GCS direction and roll of the UAV at the times t of a flight.
%   [beta, roll, dpsi] = turn_attitude(att, yaw, t)
%   att   'Att' block: [GCS direction at t = 0, elevation, roll of the turn, pitch, wobble
%         amplitude, frequency, phase, roll-in start t_in [s], roll rate w [deg/s], and the
%         roll at which the shadowing event started (shadow_frame.m; not used here)]
%   yaw   heading rate of the turn [deg/s] ('Yaw' block); t [s], scalar or vector
%   beta  broadside angle of the GCS [deg] as it turns with the heading (gcs_aoa.m)
%   roll  roll [deg], right wing down
%   dpsi  heading change since t = 0 [deg]: every direction in the UAV's horizontal plane
%         turns by it (beta = att(1) + dpsi)
%   Without a roll-in (w = 0, or fewer than 9 elements) the turn holds its roll and the
%   heading turns at the heading rate. With one, the UAV flies level until t_in and then
%   rolls at w until it reaches the turn's roll (a linear roll-in); its heading rate
%   follows the roll as a coordinated turn, g tan(roll) / v = yaw tan(roll) / tan(bank)
%   (bank_angle.m), so the heading changes by yaw / tan(bank) (-ln cos(w u)) / w after u
%   seconds of the roll-in, and at the heading rate once the bank is reached.
%#codegen
dpsi = yaw * t;
roll = att(3) + 0 * t;
if numel(att) >= 9 && att(9) > 0 && att(3) ~= 0 && yaw ~= 0
    w = att(9); b = abs(att(3));
    u = t - att(8);
    roll = sign(att(3)) * min(b, w * max(u, 0));
    dpsi = heading(u, b, w, yaw) - heading(-att(8), b, w, yaw);
end
beta = att(1) + dpsi;
end

function h = heading(u, b, w, yaw)
% Heading change since the roll-in start [deg] after u seconds (0 before it).
T = b / w;
c = yaw / tand(b) / deg2rad(w);
h = zeros(size(u));
k = u > 0 & u <= T;
h(k) = -c * log(cosd(w * u(k)));
k = u > T;
h(k) = -c * log(cosd(b)) + yaw * (u(k) - T);
end
