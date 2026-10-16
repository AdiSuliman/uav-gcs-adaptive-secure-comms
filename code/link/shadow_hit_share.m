function h = shadow_hit_share(p, n)
%SHADOW_HIT_SHARE  Expected share of the flights whose attitude lets the airframe hide an
%   antenna at the level p.shadow_db (shadow_hidden.m) in some frame of a sub-run, over the
%   dataset's draws: speed uniform over the envelope, an Eb/N0 of the grid (the GCS's
%   distance and elevation), heading rate, bank, wind attitude, altitude and GCS direction
%   from flight_draws.m (d.hidden, p.cap_frames frames). n flights (default 4000) on seeds
%   1..n.
if nargin < 2, n = 4000; end
rs = RandStream('mt19937ar', 'Seed', 2031);
p.active_threat = 'airframe_shadowing';
on = false(1, n);
for i = 1:n
    v = p.speed_kmh_min + rand(rs) * (p.speed_kmh_max - p.speed_kmh_min);
    eb = p.EbNo_dB(randi(rs, numel(p.EbNo_dB)));
    d = flight_draws(i, v / 3.6 * p.carrier_freq / p.c_light, p, struct('ebno', eb));
    on(i) = any(d.hidden > 0);
end
h = mean(on);
end
