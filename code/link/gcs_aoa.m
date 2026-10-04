function b = gcs_aoa(seed, range)
%GCS_AOA  Direction of the GCS from the UAV array of one seeded flight [deg].
%   b = gcs_aoa(seed, range): broadside angle in the horizontal plane, uniform in range
%   ([-90 90] default), from the flight's own 'gcsaoa' stream (seed_stream.m). The UAV's
%   heading relative to the GCS is arbitrary in flight, so the GCS is not held at
%   broadside, the most favourable direction for nulling with two or three antennas.
%   The array lies along the fuselage: 0 is abeam, 90 ahead (uav_attitude_db.m).
if nargin < 2 || isempty(range), range = [-90 90]; end
b = range(1) + (range(2) - range(1)) * rand(seed_stream(seed, 'gcsaoa'));
end
