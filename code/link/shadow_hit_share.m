function h = shadow_hit_share(p, n)
%SHADOW_HIT_SHARE  Expected share of the flights whose attitude lets the airframe hide an
%   antenna (shadow_hidden.m) at the start of a sub-run, over the dataset's draws: speed
%   uniform over the envelope, heading rate, bank, wind attitude and GCS direction from
%   flight_draws.m. n flights (default 4000) on seeds 1..n.
if nargin < 2, n = 4000; end
rs = RandStream('mt19937ar', 'Seed', 2031);
on = false(1, n);
for i = 1:n
    v = p.speed_kmh_min + rand(rs) * (p.speed_kmh_max - p.speed_kmh_min);
    d = flight_draws(i, v / 3.6 * p.carrier_freq / p.c_light, p);
    on(i) = shadow_hidden(d.gcs_aoa, d.el_deg, d.roll, d.pitch, p.n_rx, p.shadow_roll_deg, p.shadow_hdg_deg) > 0;
end
h = mean(on);
end
