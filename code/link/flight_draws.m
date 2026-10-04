function d = flight_draws(seed, fd, p, geo)
%FLIGHT_DRAWS  Every per-flight draw of one seeded flight, in one place.
%   d = flight_draws(seed, fd, p)       the draws of the seed
%   d = flight_draws(seed, fd, p, geo)  geo.ebno [dB] puts the GCS at the distance of that
%                                       Eb/N0 (link_distance_km.m); geo.alt_m [m] and
%                                       geo.k_sig_db [dB], when finite, replace the seed's
%                                       altitude and K of our signal (stratified designs)
%   fd is the maximum Doppler shift [Hz], p the params (init_params.m names). Each draw
%   comes from its own stream of the seed (seed_stream.m); a draw switched off in p keeps
%   its fixed value.
%   d.k_sig, d.k_int  K-factors of our signal and of the interferers [dB] (channel_k.m)
%   d.aoa             interferer directions [deg] (interferer_aoa.m)
%   d.gcs_aoa         GCS direction [deg] (gcs_aoa.m), p.gcs_aoa_deg added
%   d.yaw             heading rate [deg/s] (heading_rate.m)
%   d.bank            bank angle of the turn [deg] (bank_angle.m)
%   d.roll, d.pitch   attitude [deg]: the bank to the side of the turn, plus the tilt of a
%                     slow flight in wind (hover_attitude.m)
%   d.wobble          pitch wobble of a slow flight [amp deg, freq Hz, phase rad], zeros
%                     from p.wobble_v_max up (hover_attitude.m)
%   d.rho             receive correlation (rx_correlation.m)
%   d.gcs_point_db    GCS pointing loss [dB] (gcs_pointing.m)
%   d.alt_m           UAV altitude [m] (flight_altitude.m), NaN without one
%   d.el_deg          slant elevation of the GCS, asind((alt_m - p.gcs_h_m) / distance)
%                     [deg]; 0 without geo.ebno or an altitude
%   d.el_db           gain of the UAV antenna toward the GCS in level flight [dB]
%                     (uav_dipole_db.m)
%   d.att_db          gain of the tilted UAV antenna toward the GCS at the flight's
%                     attitude, polarization loss included [dB] (uav_attitude_db.m)
%   d.body_db         airframe loss on each UAV antenna [dB] (body_loss.m)
%   d.body_amp        amplitude of our signal on each antenna, the flight's mean loss
%                     taken out ('Body' block)
%   d.align           |a_g' a_i|^2 / n^2 of the steering vectors toward the GCS and each
%                     interferer at the start of the flight
%   d.gcs_amp         amplitude of our signal, 10^((att_db - gcs_point_db)/20) ('GCS' block)
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
d.gcs_aoa = getf(p, 'gcs_aoa_deg', 0);
if getf(p, 'gcs_aoa_random', false), d.gcs_aoa = d.gcs_aoa + gcs_aoa(seed, p.gcs_aoa_range_deg); end
d.yaw = 0;
if getf(p, 'yaw_random', false), d.yaw = heading_rate(seed, fd, p); end
d.bank = 0;
if d.yaw ~= 0, d.bank = bank_angle(d.yaw, fd, p); end
w = zeros(1, 5);
if getf(p, 'wobble_random', false), w = hover_attitude(seed, fd, p); end
d.roll = sign(d.yaw) * d.bank + w(1);           % a right turn (yaw > 0) banks right wing down
d.pitch = w(2); d.wobble = w(3:5);
d.rho = getf(p, 'rx_corr', NaN);
if getf(p, 'corr_random', false), d.rho = rx_correlation(seed, p.corr_range); end
d.gcs_point_db = 0;
if getf(p, 'gcs_tracked', false), [~, d.gcs_point_db] = gcs_pointing(seed, p); end
d.alt_m = getf(geo, 'alt_m', NaN);
if ~isfinite(d.alt_m) && getf(p, 'alt_random', false), d.alt_m = flight_altitude(seed, p); end
d.el_deg = 0; d.el_db = 0;
ebno = getf(geo, 'ebno', NaN);
if isfinite(ebno) && isfinite(d.alt_m)
    d.el_deg = asind(min((d.alt_m - p.gcs_h_m) / (1000 * link_distance_km(ebno, p)), 1));
    d.el_db = uav_dipole_db(d.el_deg, p.uav_null_db);
end
[d.att_db, ca] = uav_attitude_db(d.el_deg, d.gcs_aoa, d.roll, d.pitch, getf(p, 'uav_null_db', -30));
n = getf(p, 'n_rx', 1);
d.body_db = zeros(1, n);
if getf(p, 'body_random', false), d.body_db = body_loss(seed, n, p.body_loss_db); end
d.body_amp = 10.^(-(d.body_db - mean(d.body_db)) / 20);
d.align = nan(size(d.aoa));
if isfield(p, 'ant_spacing_wl')                 % interferers in the UAV's horizontal plane
    st = @(c) exp(-1j * 2*pi * p.ant_spacing_wl * (0:n-1)' * c);
    d.align = abs(st(ca)' * st(cosd(d.pitch) * sind(d.aoa))).^2 / n^2;
end
d.gcs_amp = 10^((d.att_db - d.gcs_point_db) / 20);
end

function v = getf(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end
