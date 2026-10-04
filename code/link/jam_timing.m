function w = jam_timing(seed, range)
%JAM_TIMING  Timing of the gated jammers of one seeded flight.
%   w = jam_timing(seed, range): [T p0 phi], from the flight's own 'jam' stream
%   (seed_stream.m). T [s] is the sweep period of the sweeping jammer, uniform in range
%   ([20 83.5] ms default: Liu et al.'s 20 MHz band to the 2.4 GHz band at 1 GHz/s); p0 [s]
%   its phase on the channel clock, uniform in [0, T); phi the phase of the noise bursts,
%   a fraction of their period, uniform in [0, 1). Neither jammer is synchronized to our
%   frames.
if nargin < 2 || isempty(range), range = [20e-3 83.5e-3]; end
u = rand(seed_stream(seed, 'jam'), 1, 3);
T = range(1) + (range(2) - range(1)) * u(1);
w = [T, T * u(2), u(3)];
end
