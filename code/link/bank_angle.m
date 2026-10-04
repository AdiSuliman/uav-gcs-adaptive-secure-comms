function b = bank_angle(w, fd, p)
%BANK_ANGLE  Bank angle of a coordinated turn [deg].
%   b = bank_angle(w, fd, p): atand(|w| v / g) for the heading rate w [deg/s]
%   (heading_rate.m) at the true speed v = fd c / fc, 0 at hover. heading_rate.m keeps
%   it at or below the largest measured bank, p.roll_max_deg (57.9 deg, Gross et al.).
b = atand(abs(deg2rad(w)) .* fd * p.c_light / p.carrier_freq / 9.81);
end
