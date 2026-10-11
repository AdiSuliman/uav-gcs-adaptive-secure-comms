function w = jam_timing(seed, range, duty)
%JAM_TIMING  Timing of the gated jammers of one seeded flight.
%   w = jam_timing(seed, range, duty): [T p0 phi a], from the flight's own 'jam' stream
%   (seed_stream.m). T [s] is the sweep period of the sweeping jammer, uniform in range
%   ([20 83.5] ms default: Liu et al.'s 20 MHz band, and the whole 2.4 GHz band at their
%   1 GHz/s); p0 [s] its phase on the channel clock, uniform in [0, T); a the duty of the
%   noise bursts, uniform in duty ([0.2 0.775] default: Marti et al.'s sparse jammer to Xu
%   et al.'s second random jammer); phi uniform in [0, 1): the bursts start on when
%   phi < a. Neither jammer is synchronized to our frames.
if nargin < 2 || isempty(range), range = [20e-3 83.5e-3]; end
if nargin < 3 || isempty(duty), duty = [0.2 0.775]; end
u = rand(seed_stream(seed, 'jam'), 1, 4);
T = range(1) + (range(2) - range(1)) * u(1);
w = [T, T * u(2), u(3), duty(1) + (duty(end) - duty(1)) * u(4)];
end
