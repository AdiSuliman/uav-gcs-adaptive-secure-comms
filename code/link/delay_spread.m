function ds = delay_spread(seed, alt_m, n, p)
%DELAY_SPREAD  RMS delay spreads of the channels of one seeded flight [ns].
%   ds = delay_spread(seed, alt_m, n, p): [our signal, n interferers], each log-normal,
%   from the flight's own 'ds' stream (seed_stream.m). Measured at 2.5 GHz from the ground
%   to a UAV at 15-105 m, log10 of the spread in s as (mean, variance) (Rodriguez-Pineiro
%   et al., Table VII). Our signal, from the tracked directional GCS: the larger of the
%   omni and the in-lobe directional fits of environment II in each band, p.tdl_sig_ds:
%   below p.tdl_sig_alt_m (25 m) the directional fit in obstructed LoS (-6.52, 0.32),
%   median 302 ns; from it up, and without an altitude, the omni fit (-6.63, 0.16),
%   234 ns. Every interferer, a ground emitter: its own draw from the omni fit,
%   p.tdl_int_ds. Clipped at p.tdl_clip_ns (1 us, the top of their Fig. 7a).
z = randn(seed_stream(seed, 'ds'), 1, 1 + n);
m = p.tdl_sig_ds(2, :);
if alt_m < p.tdl_sig_alt_m, m = p.tdl_sig_ds(1, :); end
lg = [m(1) + sqrt(m(2)) * z(1), p.tdl_int_ds(1) + sqrt(p.tdl_int_ds(2)) * z(2:end)];
ds = min(1e9 * 10.^lg, p.tdl_clip_ns);
end
