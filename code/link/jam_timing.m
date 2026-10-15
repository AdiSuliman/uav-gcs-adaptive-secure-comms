function w = jam_timing(seed, range, duty, j4)
%JAM_TIMING  Timing of the gated jammers of one seeded flight.
%   w = jam_timing(seed, range, duty, j4): [T p0 phi a], from the flight's own 'jam' stream
%   (seed_stream.m). T [s] is the sweep period of the sweeping jammer, uniform in range
%   ([20 83.5] ms default: Liu et al.'s 20 MHz band, and the whole 2.4 GHz band at their
%   1 GHz/s); p0 [s] its phase on the channel clock, uniform in [0, T); a the duty of the
%   noise bursts: with probability j4(2) Marti et al.'s sparse jammer J4 at its duty j4(1)
%   (one-symbol slots, build_threat_model.m), otherwise Xu et al.'s random jammer at a duty
%   uniform in duty ([0.5 0.775] default: their first and second jammers); the fourth draw
%   picks both. phi uniform in [0, 1): the bursts start on when phi < a. Neither jammer is
%   synchronized to our frames.
if nargin < 2 || isempty(range), range = [20e-3 83.5e-3]; end
if nargin < 3 || isempty(duty), duty = [0.5 0.775]; end
if nargin < 4 || isempty(j4), j4 = [0.2 0.5]; end
u = rand(seed_stream(seed, 'jam'), 1, 4);
T = range(1) + (range(2) - range(1)) * u(1);
a = j4(1);
if u(4) >= j4(2), a = duty(1) + (duty(end) - duty(1)) * (u(4) - j4(2)) / (1 - j4(2)); end
w = [T, T * u(2), u(3), a];
end
