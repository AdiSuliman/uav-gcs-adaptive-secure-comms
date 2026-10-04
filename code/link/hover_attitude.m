function w = hover_attitude(seed, fd, p)
%HOVER_ATTITUDE  Attitude of a hovering or slow UAV in wind, one seeded flight.
%   w = hover_attitude(seed, fd, p): [roll pitch amp freq phase], from the flight's own
%   'wobble' stream (seed_stream.m). Below p.wobble_v_max (speed v = fd c / fc) the UAV
%   tilts to hold its position: roll and pitch [deg] uniform within the measured 30 s
%   means p.wobble_roll_deg and p.wobble_pitch_deg (Polle et al.); and its pitch wobbles
%   by amp sin(2 pi freq t + phase): amp [deg] uniform in +-p.wobble_amp_deg, freq [Hz]
%   uniform in p.wobble_freq_hz, phase [rad] uniform (Banagar & Dhillon's assumed
%   parameters, not measurements). Zeros from p.wobble_v_max up.
u = rand(seed_stream(seed, 'wobble'), 1, 5);
w = zeros(1, 5);
if fd * p.c_light / p.carrier_freq >= p.wobble_v_max, return; end
w(1) = p.wobble_roll_deg(1) + diff(p.wobble_roll_deg) * u(1);
w(2) = p.wobble_pitch_deg(1) + diff(p.wobble_pitch_deg) * u(2);
w(3) = p.wobble_amp_deg * (2 * u(3) - 1);
w(4) = p.wobble_freq_hz(1) + diff(p.wobble_freq_hz) * u(4);
w(5) = 2 * pi * u(5);
end
