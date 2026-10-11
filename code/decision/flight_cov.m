function V = flight_cov(geo, ebno, p0)
%FLIGHT_COV  Every per-flight draw of a set of seeded flights as the link flies them
%   (flight_draws.m, the GCS at the distance of the flight's Eb/N0).
%   geo{s}  the flights at Eb/N0 ebno(s): seed and speed [km/h], and optionally alt [m],
%           ksig [dB], aoa1 [deg] and rho that replace the seed's own draws (NaN: the
%           seed's own), 1 x n each, the same n at every Eb/N0
%   V       Eb/N0 x flight arrays, the fields of PP.cov (build_policy_pools.m): seed,
%           speed, alt_m, k_sig, k_int, yaw, rho, gcs_point_db, el_db, aoa and align (x 3:
%           |a_g' a_i|^2 / n^2 of the steering vectors toward the GCS and each
%           interferer), gcs_aoa, el_deg, bank, roll, pitch, wob, att_db, body_spread_db
%           (spread of the airframe loss over the antennas), jam (x 3: sweep period, sweep
%           phase, burst phase), ds_ns and ds_int (x 3: RMS delay spread of our signal and
%           of each interferer [ns])
nS = numel(ebno); n = numel(geo{1}.seed);
z = nan(nS, n);
V = struct('seed', z, 'speed', z, 'alt_m', z, 'k_sig', z, 'k_int', z, 'yaw', z, 'rho', z, ...
    'gcs_point_db', z, 'el_db', z, 'aoa', nan(nS, n, 3), 'align', nan(nS, n, 3), ...
    'gcs_aoa', z, 'el_deg', z, 'bank', z, 'roll', z, 'pitch', z, 'wob', z, 'att_db', z, 'body_spread_db', z, ...
    'jam', nan(nS, n, 3), 'ds_ns', z, 'ds_int', nan(nS, n, 3));
for s = 1:nS
    g = geo{s};
    for r = 1:n
        fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
        d = flight_draws(g.seed(r), fd, p0, struct('ebno', ebno(s), 'alt_m', value(g, 'alt', r), ...
            'k_sig_db', value(g, 'ksig', r), 'aoa1_deg', value(g, 'aoa1', r), 'rho', value(g, 'rho', r)));
        V.seed(s, r) = g.seed(r); V.speed(s, r) = g.speed(r); V.alt_m(s, r) = d.alt_m;
        V.k_sig(s, r) = d.k_sig; V.k_int(s, r) = d.k_int; V.yaw(s, r) = d.yaw; V.rho(s, r) = d.rho;
        V.gcs_point_db(s, r) = d.gcs_point_db; V.el_db(s, r) = d.el_db;
        ni = min(3, numel(d.aoa));
        V.aoa(s, r, 1:ni) = d.aoa(1:ni);
        V.align(s, r, 1:ni) = d.align(1:ni);
        V.gcs_aoa(s, r) = d.gcs_aoa; V.el_deg(s, r) = d.el_deg; V.bank(s, r) = d.bank;
        V.roll(s, r) = d.roll; V.pitch(s, r) = d.pitch; V.wob(s, r) = d.wobble(1);
        V.att_db(s, r) = d.att_db; V.body_spread_db(s, r) = max(d.body_db) - min(d.body_db);
        V.jam(s, r, :) = d.jam;
        V.ds_ns(s, r) = d.ds_ns(1); V.ds_int(s, r, 1:ni) = d.ds_ns(1 + (1:ni));
    end
end
end

function v = value(g, f, r)
% Field f of flight r, NaN when the flights do not set it.
if isfield(g, f), v = g.(f)(r); else, v = NaN; end
end
