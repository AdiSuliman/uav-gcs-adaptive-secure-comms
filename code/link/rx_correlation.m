function rho = rx_correlation(seed, range)
%RX_CORRELATION  Diffuse-fading correlation between adjacent UAV antennas of one seeded
%   sub-run: uniform in range (no source gives it for a small UAV; init_params.m).
rs = RandStream('mt19937ar', 'Seed', mod(round(seed) + 31, 2^32));
rho = range(1) + (range(2) - range(1)) * rand(rs);
end
