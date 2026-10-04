function d = flight_draws(seed, fd, p, geo)
%FLIGHT_DRAWS  Every per-flight draw of one seeded flight, in one place.
%   d = flight_draws(seed, fd, p)       the draws of the seed
%   d = flight_draws(seed, fd, p, geo)  geo.ebno [dB] puts the GCS at the distance of that
%                                       Eb/N0 (link_distance_km.m); geo.alt_m [m],
%                                       geo.k_sig_db [dB], geo.aoa1_deg [deg] and geo.rho,
%                                       when finite, replace the seed's altitude, K of our
%                                       signal, first interferer direction and receive
%                                       correlation (stratified designs)
%   fd is the maximum Doppler shift [Hz], p the params (init_params.m names). Each draw
%   comes from its own stream of the seed (seed_stream.m); a draw switched off in p keeps
%   its fixed value.
%   d.k_sig, d.k_int  K-factors of our signal and of the interferers [dB] (channel_k.m)
%   d.aoa             interferer directions [deg] (interferer_aoa.m)
%   d.yaw             heading rate [deg/s] (heading_rate.m)
%   d.rho             receive correlation (rx_correlation.m)
%   d.gcs_point_db    GCS pointing loss [dB] (gcs_pointing.m)
%   d.alt_m           UAV altitude [m] (flight_altitude.m), NaN without one
%   d.el_db           gain of the UAV antenna toward the GCS [dB] (uav_dipole_db.m) at the
%                     slant elevation asind((alt_m - p.gcs_h_m) / distance); 0 without
%                     geo.ebno or an altitude
%   d.gcs_amp         amplitude of our signal, 10^((el_db - gcs_point_db)/20) ('GCS' block)
if nargin < 4 || isempty(geo), geo = struct(); end
if getf(p, 'k_random', false)
    k = channel_k(seed, p.k_range_db);
else
    k = [getf(p, 'rician_k', NaN), getf(p, 'int_rician_k', NaN)];
end
if isfinite(getf(geo, 'k_sig_db', NaN)), k(1) = geo.k_sig_db; end
d.k_sig = k(1); d.k_int = k(2);
if getf(p, 'int_aoa_random', false)
    d.aoa = interferer_aoa(seed, p.int_aoa_range_deg, numel(p.int_aoa_deg));
else
    d.aoa = reshape(getf(p, 'int_aoa_deg', NaN), 1, []);
end
if isfinite(getf(geo, 'aoa1_deg', NaN)), d.aoa(1) = geo.aoa1_deg; end
d.yaw = 0;
if getf(p, 'yaw_random', false), d.yaw = heading_rate(seed, fd, p); end
d.rho = getf(p, 'rx_corr', NaN);
if getf(p, 'corr_random', false), d.rho = rx_correlation(seed, p.corr_range); end
if isfinite(getf(geo, 'rho', NaN)), d.rho = geo.rho; end
d.gcs_point_db = 0;
if getf(p, 'gcs_tracked', false), [~, d.gcs_point_db] = gcs_pointing(seed, p); end
d.alt_m = getf(geo, 'alt_m', NaN);
if ~isfinite(d.alt_m) && getf(p, 'alt_random', false), d.alt_m = flight_altitude(seed, p); end
d.el_db = 0;
ebno = getf(geo, 'ebno', NaN);
if isfinite(ebno) && isfinite(d.alt_m)
    th = asind(min((d.alt_m - p.gcs_h_m) / (1000 * link_distance_km(ebno, p)), 1));
    d.el_db = uav_dipole_db(th, p.uav_null_db);
end
d.gcs_amp = 10^((d.el_db - d.gcs_point_db) / 20);
end

function v = getf(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end
