function w = roll_rate(u, bank, p)
%ROLL_RATE  Roll rate of a roll-in from level flight to the bank [deg/s].
%   w = roll_rate(u, bank, p): uniform (u in [0, 1]) from p.roll_rate_lo, the measured
%   roll-in of a small UAV (Allen & Lin, Fig. 12, digitised: 0 to 30 deg of bank in about
%   1.6 s), up to the largest roll rate measured over a window as long as the roll-in
%   itself (p.roll_rate_win, rows [window s, rate deg/s]: Gross et al., Fig. 4, digitised,
%   45.4 deg/s over 0.5 s and 35.5 deg/s over 1 s; Allen & Lin's 31.7 and 28.8 deg/s lie
%   below). A roll-in of T = bank / w seconds may reach the rate of the shortest window
%   that holds it, linear in T between the two windows (a derivation), so the most severe
%   measured rate bounds every roll-in and none exceeds it.
lo = p.roll_rate_lo; W = p.roll_rate_win;
hi = W(end, 2);
if bank <= W(1, 2) * W(1, 1)
    hi = W(1, 2);                                   % the roll-in lasts no longer than the shortest window
elseif bank < W(end, 2) * W(end, 1)
    s = (W(1, 2) - W(end, 2)) / (W(end, 1) - W(1, 1));   % rate lost per second of window [deg/s^2]
    a = W(1, 2) + s * W(1, 1);                      % w = a - s T, T = bank / w: w^2 - a w + s bank = 0
    hi = (a + sqrt(max(a^2 - 4 * s * bank, 0))) / 2;
end
w = lo + u * (max(hi, lo) - lo);
end
