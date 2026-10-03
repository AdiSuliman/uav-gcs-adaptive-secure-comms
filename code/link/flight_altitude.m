function h = flight_altitude(seed, p)
%FLIGHT_ALTITUDE  Height of the UAV above ground during one seeded flight [m].
%   h = flight_altitude(seed, p): uniform in p.alt_range_m (init_params.m), from the
%   flight's own 'alt' stream (seed_stream.m).
h = p.alt_range_m(1) + (p.alt_range_m(2) - p.alt_range_m(1)) * rand(seed_stream(seed, 'alt'));
end
