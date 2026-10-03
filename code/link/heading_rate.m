function w = heading_rate(seed, fd, p)
%HEADING_RATE  Heading change of the UAV during one seeded sub-run [deg/s].
%   w = heading_rate(seed, fd, p): uniform in +-w_max, the rate of a coordinated turn
%   at the largest measured bank angle, g tan(p.roll_max_deg) / v, with the speed v
%   from the Doppler fd (v = fd c / fc) and not below p.turn_v_floor, capped at the
%   largest measured yaw rate p.yaw_rate_max.
%   The directions of the GCS and of every interferer, seen from the UAV's array,
%   rotate at this rate. At hover (fd = 0) w = 0: no source gives the yaw rate of a
%   hovering UAV.
if fd == 0
    w = 0;
    return;
end
v = max(fd * p.c_light / p.carrier_freq, p.turn_v_floor);
wmax = min(rad2deg(9.81 * tand(p.roll_max_deg) / v), p.yaw_rate_max);
w = wmax * (2 * rand(seed_stream(seed, 'yaw')) - 1);
end
