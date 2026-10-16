function ph = los_phase(aoa, att, yaw, fd, t)
%LOS_PHASE  Doppler phase of an emitter's line of sight as the UAV turns [rad].
%   ph = los_phase(aoa, att, yaw, fd, t): 2 pi fd times the integral from 0 to t of
%   sin(aoa + the heading change), the emitter's direction aoa [deg] at t = 0 in the UAV's
%   horizontal plane (the broadside angle, 90 ahead), fd [Hz] the Doppler shift straight
%   ahead (times the cosine of the emitter's elevation off that plane), att the 'Att' block
%   and yaw the heading rate [deg/s] (turn_attitude.m: a held bank, or level flight, a
%   roll-in and the bank), t [s] scalar or vector. Its rate is the Doppler shift of the
%   direction at every instant, fd sin(aoa + heading change), so the phase stays continuous
%   from frame to frame and over the idle time between them. Closed form while the heading
%   is constant or turns at a constant rate; the trapezoidal rule on 2001 points over a
%   roll-in (phase error below 2e-3 rad at 358 Hz).
%#codegen
ph = zeros(size(t));
if numel(att) < 9 || att(9) <= 0 || att(3) == 0 || yaw == 0
    if yaw == 0
        ph = 2*pi*fd * sind(aoa) * t;
    else
        ph = 2*pi*fd * (cosd(aoa) - cosd(aoa + yaw * t)) / deg2rad(yaw);
    end
    return
end
ti = att(8); T = abs(att(3)) / att(9);
ta = max(0, ti); tb = max(ta, ti + T);                    % the roll-in's part from t = 0 on
tg = linspace(ta, tb, 2001)';
[~, ~, dg] = turn_attitude(att, yaw, tg);
fg = sind(aoa + dg);
Fg = [0; cumsum((fg(1:end-1) + fg(2:end)) / 2 .* diff(tg))];
F0 = sind(aoa) * ta;                                      % level flight before the roll-in
[~, ~, dt] = turn_attitude(att, yaw, t);
for i = 1:numel(t)
    if t(i) <= ta
        F = sind(aoa) * t(i);
    elseif t(i) <= tb
        j = min(2000, 1 + floor((t(i) - ta) / max(tb - ta, eps) * 2000));
        F = F0 + Fg(j) + (t(i) - tg(j)) * (fg(j) + sind(aoa + dt(i))) / 2;
    else
        F = F0 + Fg(end) + (cosd(aoa + dg(end)) - cosd(aoa + dt(i))) / deg2rad(yaw);
    end
    ph(i) = 2*pi*fd * F;
end
end
