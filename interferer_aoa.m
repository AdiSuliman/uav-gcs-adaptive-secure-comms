function th = interferer_aoa(seed, range, n)
%INTERFERER_AOA  Directions of the interferers of one seeded sub-run [deg] (D45).
%   th = interferer_aoa(seed, range, n): n directions, uniform in range (broadside
%   angle of the UAV array). A uniform azimuth of the interferer around the UAV
%   gives the same distribution of sin(theta) as a uniform broadside angle in
%   [-90, 90] deg, so the default range covers every flight geometry.
if nargin < 2 || isempty(range), range = [-90 90]; end
if nargin < 3, n = 3; end
rs = RandStream('mt19937ar', 'Seed', mod(round(seed) + 11, 2^32));
th = range(1) + (range(2) - range(1)) * rand(rs, 1, n);
end
