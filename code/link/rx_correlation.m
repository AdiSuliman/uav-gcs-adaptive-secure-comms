function rho = rx_correlation(seed, range)
%RX_CORRELATION  Diffuse-fading correlation between adjacent UAV antennas of one seeded
%   sub-run: uniform in range (no source gives it for a small UAV; init_params.m).
rho = range(1) + (range(2) - range(1)) * rand(seed_stream(seed, 'corr'));
end
