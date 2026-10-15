function d = flight_draws(seed, fd, p, geo)
%FLIGHT_DRAWS  Every per-flight draw of one seeded flight, in one place.
%   d = flight_draws(seed, fd, p)       the draws of the seed
%   d = flight_draws(seed, fd, p, geo)  geo.ebno [dB] puts the GCS at the distance of that
%                                       Eb/N0 (link_distance_km.m); geo.alt_m [m],
%                                       geo.k_sig_db [dB], geo.aoa1_deg [deg] and geo.rho,
%                                       when finite, replace the seed's altitude, K of our
%                                       signal, first interferer direction and receive
%                                       correlation (stratified designs); geo.event_frame,
%                                       when finite, makes the flight roll into its turn so
%                                       that the airframe enters the line of sight of its
%                                       belly antennas just before that frame (the pools'
%                                       shadowing flights and their clean reference);
%                                       geo.frames: the frames of the run (default
%                                       p.cap_frames)
%   fd is the maximum Doppler shift [Hz], p the params (init_params.m names). Each draw
%   comes from its own stream of the seed (seed_stream.m); a draw switched off in p keeps
%   its fixed value.
%   d.k_sig, d.k_int  K-factors of our signal and of the interferers [dB] (channel_k.m)
%   d.aoa             interferer directions [deg] (interferer_aoa.m)
%   d.gcs_aoa         GCS direction [deg] at the run's first frame (gcs_aoa.m, p.gcs_aoa_deg
%                     added; with a roll-in that draw is the direction at its start)
%   d.yaw             heading rate [deg/s] (heading_rate.m)
%   d.bank            bank angle of the turn [deg] (bank_angle.m)
%   d.roll, d.pitch   attitude [deg]: the bank to the side of the turn, plus the tilt of a
%                     slow flight in wind (hover_attitude.m); without the heading-rate draw
%                     (p.yaw_random off) a fixed bank p.roll_deg (default 0): the coordinated
%                     turn it flies sets d.yaw (a tilt without a turn at hover)
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
%   d.jam             timing of the gated jammers [sweep period s, sweep phase s, burst
%                     start, burst duty] (jam_timing.m; fixed: the shortest period, phases
%                     0, the duty p.burst_duty) ('Gate' block)
%   d.cal_db          level calibration error of each antenna's receiver [dB], uniform
%                     within +-p.cal_err_db ('Cal' block)
%   d.roll_in         [t_in w r_s]: start of the roll-in [s] (from the run's first frame),
%                     its roll rate [deg/s] (roll_rate.m, first draw of the 'roll' stream)
%                     and the roll [deg] at which the airframe starts to hide an antenna;
%                     [0 0 0] for a flight that holds its bank. A turning flight rolls in
%                     when geo.event_frame sets where the airframe enters the line of
%                     sight, or when p.roll_in_frames is set and the threat holds airframe
%                     shadowing: the loss then first reaches p.shadow_evt_db at a frame
%                     drawn in that range (third draw). The crossing lies 0.1-0.9 of a
%                     cycle before that frame (second draw). The event must start during
%                     the roll-in; otherwise the flight holds its bank, and where an onset
%                     was asked for it hides no antenna (d.hidden 0: every selection skips
%                     it)
%   d.onset_frame     the frame the roll-in places (NaN without one)
%   d.hidden          antenna the airframe hides at the start of each of the run's frames
%                     (geo.frames, or p.cap_frames) a cycle apart while the event counts,
%                     its loss at least p.shadow_evt_db; 0 none (shadow_frame.m; only when
%                     the threat holds airframe shadowing, shadow_spec.m)
%   d.shadow_g        share of the level's depth at those frame starts (shadow_frame.m)
%   d.cap_amp         our signal's amplitude on its weakest antenna at the worst frame of
%                     those (sig_weak_db.m, the 'GCS' amplitude included): the reference of
%                     the in-band cap ('Cap' block, inband_cap_amp.m)
%   d.ds_ns           RMS delay spread of our signal and of every interferer that the
%                     delay line reaches [ns] (delay_spread.m, or p.tdl_ds_ns; tdl_profile.m),
%                     0 with a flat channel
%   d.tdl             diffuse tap amplitudes of the delay line, one column per channel: our
%                     signal, then every interferer ('Tdl' block)
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
d.gcs_aoa = getf(p, 'gcs_aoa_deg', 0);
if getf(p, 'gcs_aoa_random', false), d.gcs_aoa = d.gcs_aoa + gcs_aoa(seed, p.gcs_aoa_range_deg); end
d.yaw = 0;
if getf(p, 'yaw_random', false), d.yaw = heading_rate(seed, fd, p); end
d.bank = 0;
if d.yaw ~= 0, d.bank = bank_angle(d.yaw, fd, p); end
r0 = getf(p, 'roll_deg', 0);
if ~getf(p, 'yaw_random', false) && r0 ~= 0      % a fixed geometry's bank: the coordinated turn it flies
    d.bank = abs(r0);
    d.yaw = sign(r0) * turn_rate(d.bank, fd, p);
end
w = zeros(1, 5);
if getf(p, 'wobble_random', false), w = hover_attitude(seed, fd, p); end
d.roll = sign(d.yaw) * d.bank + w(1);           % a right turn (yaw > 0) banks right wing down
if d.yaw == 0 && r0 ~= 0 && ~getf(p, 'yaw_random', false), d.roll = r0 + w(1); end   % hover: a tilt, no turn
d.pitch = w(2); d.wobble = w(3:5);
d.rho = getf(p, 'rx_corr', NaN);
if getf(p, 'corr_random', false), d.rho = rx_correlation(seed, p.corr_range); end
if isfinite(getf(geo, 'rho', NaN)), d.rho = geo.rho; end
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
shd = run_shadow(p);
[d.roll_in, d.gcs_aoa, d.onset_frame, ok] = roll_in(seed, d, fd, p, geo, shd);
[~, roll0] = turn_attitude([d.gcs_aoa d.el_deg d.roll d.pitch d.wobble d.roll_in], d.yaw, 0);
[d.att_db, ca] = uav_attitude_db(d.el_deg, d.gcs_aoa, roll0, d.pitch, getf(p, 'uav_null_db', -30));
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
sp = getf(p, 'sweep_period_s', [20e-3 83.5e-3]);
d.jam = [sp(1) 0 0 getf(p, 'burst_duty', 0.5)];
if getf(p, 'jam_timing_random', false)
    d.jam = jam_timing(seed, sp, getf(p, 'burst_duty_range', [0.2 0.775]));
end
d.cal_db = zeros(1, n);
if getf(p, 'cal_random', false), d.cal_db = getf(p, 'cal_err_db', 2) * (2 * rand(seed_stream(seed, 'cal'), 1, n) - 1); end
ni = numel(d.aoa);
nt = 1 + getf(p, 'tdl', false) * floor(getf(p, 'tdl_max_ns', 0) / getf(p, 'tdl_step_ns', 1));
d.ds_ns = zeros(1, 1 + ni); d.tdl = [ones(1, 1 + ni); zeros(nt - 1, 1 + ni)];
if nt > 1
    ds = getf(p, 'tdl_ds_ns', 0); ds = [ds(1), ds(end) * ones(1, ni)];
    if getf(p, 'tdl_random', false), ds = delay_spread(seed, d.alt_m, ni, p); end
    k = [d.k_sig, d.k_int * ones(1, ni)];
    for i = 1:1 + ni
        [d.tdl(:, i), d.ds_ns(i)] = tdl_profile(ds(i), k(i), nt, p.tdl_step_ns);
    end
end
[d.hidden, d.cap_amp, d.shadow_g] = run_attitude(d, fd, p, getf(geo, 'frames', getf(p, 'cap_frames', 1)), shd);
if ~ok, d.hidden(:) = 0; end                    % an onset asked for and not placed: no shadowing flight
end

function shd = run_shadow(p)
% Airframe shadowing of the build (shadow_spec.m), from the blocks' params or the full ones.
if isfield(p, 'shadow_spec')
    shd = p.shadow_spec;
elseif all(isfield(p, {'shadow_db', 'shadow_fit', 'shadow_fit_z', 'shadow_roll_deg', 'roll_max_deg', ...
        'shadow_hdg_deg', 'shadow_v_min', 'shadow_k_db'}))
    shd = shadow_spec(p);
else
    shd = zeros(1, 6);
end
end

function [rin, a0, kf, ok] = roll_in(seed, d, fd, p, geo, shd)
% Roll-in of a flight whose shadowing onset the data place (d.roll_in): the timeline from
% the roll-in's start, the GCS at the drawn direction there, scanned every millisecond over
% the roll-in for the first moment the airframe hides an antenna (its roll r_s starts the
% event's shape, shadow_frame.m), then for the onset: that moment (geo.event_frame, every
% level alike) or the loss reaching p.shadow_evt_db at the build's level (p.roll_in_frames);
% the roll-in starts that long before the onset. a0: the GCS direction at t = 0; ok false
% when an onset was asked for and the event does not start during the roll-in.
rin = [0 0 0]; a0 = d.gcs_aoa; kf = NaN; ok = true;
r = rand(seed_stream(seed, 'roll'), 1, 3);
ef = getf(geo, 'event_frame', NaN); rf = getf(p, 'roll_in_frames', []);
if isfinite(ef)
    kf = ef; D0 = 0; band = [0 Inf]; L = 1;
elseif ~isempty(rf) && shd(1) > 0
    kf = rf(1) + floor(r(3) * (rf(end) - rf(1) + 1)); D0 = getf(p, 'shadow_evt_db', 0); band = shd(2:3); L = shd(1);
else
    return
end
ok = false;
if d.yaw == 0 || d.bank <= 0 || ~getf(p, 'yaw_random', false), kf = NaN; return; end
w = roll_rate(r(1), d.bank, p);
T = d.bank / w;
u = unique([(0:1e-3:T)'; T]);
att = [d.gcs_aoa d.el_deg d.roll d.pitch d.wobble 0 w];
[b, ro] = turn_attitude(att, d.yaw, u);
v = fd * getf(p, 'c_light', 3e8) / getf(p, 'carrier_freq', 2.4e9);
sh = @(rs) shadow_frame(b, d.el_deg, ro, [d.bank rs], d.pitch, getf(p, 'n_rx', 1), band, getf(p, 'shadow_hdg_deg', 30), ...
    v, getf(p, 'shadow_v_min', 0));
k = sh(0);
i0 = find(k > 0, 1);
if isempty(i0), kf = NaN; return; end
rs = abs(ro(i0));
[k, g] = sh(rs);
i = find(k > 0 & L * g >= D0, 1);
if isempty(i), kf = NaN; return; end
tin = (kf - 1) * getf(p, 'cycle_s', 0) - (0.1 + 0.8 * r(2)) * getf(p, 'cycle_s', 0) - u(i);
rin = [tin w rs]; ok = true;
a0 = turn_attitude(att, d.yaw, -tin);           % the direction at the run's first frame
end

function [hid, cap, gs] = run_attitude(d, fd, p, H, shd)
% Hidden antenna at the start of every frame of the run while the event counts, and our
% signal's weakest-antenna amplitude over the run (sig_weak_db.m), the frames p.cycle_s
% apart, p.air_s from a frame's first sample to its last.
H = max(1, H); cyc = getf(p, 'cycle_s', 0);
air = getf(p, 'air_s', NaN);
if isnan(air), air = (getf(p, 'samples_per_frame', 1) - 1) / (getf(p, 'symbol_rate', 1) * getf(p, 'sps', 1)); end
v = fd * getf(p, 'c_light', 3e8) / getf(p, 'carrier_freq', 2.4e9);
nul = getf(p, 'uav_null_db', -30);
att = [d.gcs_aoa d.el_deg d.roll d.pitch d.wobble d.roll_in];
k = d.k_sig; if ~isfinite(k), k = 100; end
evt = getf(p, 'shadow_evt_db', 0);
hid = zeros(1, H); gs = zeros(1, H); w = Inf;
for j = 1:H
    t1 = (j - 1) * cyc;
    w = min(w, sig_weak_db(att, d.yaw, t1, [t1; t1 + air], k, d.body_amp, shd, v, nul));
    if shd(1) > 0
        [b, ro] = turn_attitude(att, d.yaw, t1);
        [hs, gs(j)] = shadow_frame(b, att(2), ro, [abs(att(3)) att(10)], att(4), numel(d.body_amp), shd(2:3), shd(4), v, shd(5));
        if shd(1) * gs(j) >= evt, hid(j) = hs; end
    end
end
cap = d.gcs_amp * 10^(w / 20);
end

function w = turn_rate(b, fd, p)
% Heading rate of a coordinated turn at bank b [deg/s], g tan(b) / v, with the speed from
% the Doppler fd and not below p.turn_v_floor (heading_rate.m); 0 at hover.
w = 0;
if fd == 0, return; end
v = max(fd * p.c_light / p.carrier_freq, getf(p, 'turn_v_floor', 0));
w = rad2deg(9.81 * tand(b) / v);
end

function v = getf(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end
