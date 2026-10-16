function [Z, names] = emitter_idle(F, p, seed, v)
%EMITTER_IDLE  The idle time of a run with an emitter of opportunity added, per condition:
%   the input of the fault-vs-shadowing reading per condition (emitter_reading.m), never part
%   of the default link or its labels.
%   [Z, names] = emitter_idle(F, p, seed, v): F of extract_closed_loop_frames.m (idle_ctx,
%   idle_on), p its params, seed the flight's seed, v the frames kept. Z frames x 15: per
%   condition u of p.amb_inr_db, each antenna's mean power over the busy bins (pa1..pa4 [dB],
%   NaN beyond the array) and the busy bins (nbusy), from idle_rssi.m and idle_summary.m.
%   The emitter: a WLAN on the ground with the threat block's packet law (packets
%   log-uniform in p.benign_pkt_s, gamma idle gaps of shape p.benign_idle_shape) at a duty
%   uniform in p.amb_duty (Cheema & Salous 2019's measured 2.4 GHz channels), its own
%   Rician channel (K uniform in p.k_range_db, the array's steering, the flight's Doppler,
%   heading turn and receive correlation, 32 sinusoids per antenna), INR p.amb_inr_db(u) at
%   the UAV; the flight's own 'amb' stream (seed_stream.m). Its direction: an azimuth uniform
%   over the full circle (either side of the UAV, as gcs_aoa.m's broadside angle), and the
%   elevation of the farthest emitter that reaches that INR (emitter_elevation.m).
%   A faulty connector attenuates it like everything its antenna receives (idle_rssi.m). In
%   an airframe-shadowing flight the airframe hides it as it hides the GCS (shadow_frame.m
%   at the emitter's direction in every idle bin, its own horizon crossing starting the
%   shape): the hidden antenna loses the share of the level's depth its burial has reached
%   and its K is the shadow's once that loss counts as an event. The emitter's own event,
%   buried at its deepest at least as deep as the shallowest event the level is paired
%   with, keeps the level (the fit rises with roll, so a deeper one at least the level); a
%   shallower one carries none. Stated: the emitter is added to the idle time
%   only; its packets inside our frames (a few percent of the cycles at that duty) are not
%   simulated.
nU = numel(p.amb_inr_db);
names = {};
for u = 1:nU
    names = [names, arrayfun(@(a) sprintf('amb%d_pa%d', u, a), 1:4, 'UniformOutput', false), {sprintf('amb%d_nbusy', u)}]; %#ok<AGROW>
end
Z = nan(numel(v), 5 * nU);
if ~isfield(F, 'idle_ctx') || isempty(F.idle_ctx), return; end
ctx = F.idle_ctx; nr = p.n_rx; nv = thermal_nv(p);
fs = p.symbol_rate * p.sps; TB = 1 / p.idle_rssi_hz; cyc = round(p.cycle_s * fs) / fs; Ns = p.samples_per_frame;
NT = 1 + p.tdl * floor(p.tdl_max_ns / p.tdl_step_ns); S = round(p.tdl_step_ns * 1e-9 * fs);
NBI = max(0, floor((round(p.cycle_s * fs) - Ns - (NT - 1) * S) / (fs * TB)));
if NBI == 0, return; end
rs = seed_stream(seed, 'amb');
occ = p.amb_duty(1) + diff(p.amb_duty) * rand(rs);
Kd = p.k_range_db(1) + diff(p.k_range_db) * rand(rs);
be = -180 + 360 * rand(rs);
ee = emitter_elevation(seed, p, p.amb_inr_db);
nf = max(v);
on = wlan_shares(rs, occ, p, NBI, TB, cyc, Ns, nf);         % NBI x frames
h2 = fading(rs, Kd, be, ee, ctx, p, NBI, TB, cyc, Ns, nf);  % NBI x nr x frames x conditions, unit mean power unshadowed
ion = []; if isfield(F, 'idle_on'), ion = double(F.idle_on); end
for u = 1:nU
    amb = nv * 10^(p.amb_inr_db(u) / 10) * h2(:, :, :, u) .* permute(on, [1 3 2]);
    R = idle_rssi(p, ctx, ion, v, struct('ambient', amb(:, :, v)));
    Sm = idle_summary(R, p); nm = idle_summary('names');
    Z(:, 5 * (u - 1) + (1:4)) = Sm(:, strcmp(nm, 'pa1') | strcmp(nm, 'pa2') | strcmp(nm, 'pa3') | strcmp(nm, 'pa4'));
    Z(:, 5 * u) = Sm(:, strcmp(nm, 'nbusy'));
end
end

function on = wlan_shares(rs, occ, p, NBI, TB, cyc, Ns, nf)
% On-share per idle bin of a WLAN with the threat block's packet law (benign_hit_share.m).
fs = p.symbol_rate * p.sps; d = p.benign_pkt_s; md = (d(2) - d(1)) / log(d(2) / d(1)); k = p.benign_idle_shape;
tend = nf * cyc; t = 0; st = rand(rs) < occ; iv = zeros(0, 2);
while t < tend
    if st
        dur = exp(log(d(1)) + log(d(2) / d(1)) * rand(rs)); iv(end+1, :) = [t, t + dur]; t = t + dur; %#ok<AGROW>
    else
        t = t + gamma1(rs, k) * md * (1 - occ) / occ / k;
    end
    st = ~st;
end
on = zeros(NBI, nf);
for j = 2:nf
    ga = (j - 2) * cyc + Ns / fs;
    a = ga + ((1:NBI)' - 1) * TB; b = a + TB;
    for q = 1:NBI
        on(q, j) = sum(max(0, min(iv(:, 2), b(q)) - max(iv(:, 1), a(q)))) / TB;
    end
end
end

function h2 = fading(rs, Kd, be, ee, ctx, p, NBI, TB, cyc, Ns, nf)
% |h|^2 of every antenna per condition: Rician K, LoS from the emitter's direction (azimuth
% be, elevation ee(u)) with its Doppler phase (los_phase.m), 32 sinusoids per antenna with
% the flight's Doppler, heading turn (turn_attitude.m) and receive correlation; the airframe
% shadowing of the build at the emitter's direction (emitter_shadow).
fs = p.symbol_rate * p.sps; nr = p.n_rx; nU = numel(ee);
fI = cos(2*pi*rand(rs, 32, nr)); pI = 2*pi*rand(rs, 32, nr);
Rr = zeros(nr); for i = 1:nr, for j = 1:nr, Rr(i, j) = ctx.rho^abs(i - j); end, end
Rc = chol(Rr); apos = (0:nr-1) - (nr-1)/2;
h2 = zeros(NBI, nr, nf, nU);
for j = 2:nf
    tq = (j - 2) * cyc + Ns / fs + ((1:NBI)' - 0.5) * TB;
    [~, rq, dq] = turn_attitude(ctx.att, ctx.yaw, tq);      % roll and heading change (a roll-in included)
    D0 = zeros(NBI, nr);
    for a = 1:nr, D0(:, a) = exp(1j * (2*pi*tq*(ctx.fd*fI(:, a)') + pI(:, a)')) * ones(32, 1) / sqrt(32); end
    D0 = D0 * Rc;
    for u = 1:nU
        aI = exp(-1j * 2*pi * p.ant_spacing_wl * (cosd(ee(u)) * sind(be + dq)) * apos);
        lI = exp(1j * los_phase(be, ctx.att, ctx.yaw, ctx.fd * cosd(ee(u)), tq));
        [G, Kq] = emitter_shadow(be + dq, ee(u), rq, ctx, p, Kd, NBI);
        Kl = 10 .^ (Kq / 10);
        h2(:, :, j, u) = G .* abs(sqrt(Kl ./ (Kl + 1)) .* aI .* lI + sqrt(1 ./ (Kl + 1)) .* (D0 .* aI)).^2;
    end
end
end

function [G, Kq] = emitter_shadow(bq, eq, rq, ctx, p, Kd, NBI)
% Power share G and K-factor Kq [dB] of every antenna in every bin (NBI x n_rx): the
% emitter's own K and no loss, unless the build holds airframe shadowing and the airframe
% hides the emitter's direction bq [deg] at elevation eq [deg] and roll rq (shadow_frame.m
% with the flight's bank and pitch from ctx.att, the level's band from its smallest roll up).
nr = p.n_rx;
G = ones(NBI, nr); Kq = Kd * ones(NBI, nr);
s = shadow_spec(p);
if s(1) <= 0, return; end
v = ctx.fd * p.c_light / p.carrier_freq;
[k, g] = shadow_frame(bq, eq, rq, [abs(ctx.att(3)) 0], ctx.att(4), nr, [s(2) Inf], s(4), v, s(5), s(8));
for a = 1:nr
    h = k == a;
    G(h, a) = 10 .^ (-s(1) * g(h) / 10);
    Kq(h & s(1) * g >= s(7), a) = s(6);
end
end

function g = gamma1(rs, k)
% Gamma(k, 1) by Marsaglia-Tsang, as the threat block (gamma_draw).
a = k + (k < 1); dd = a - 1/3; c = 1 / sqrt(9 * dd); g = 0;
while g == 0
    x = randn(rs); w = (1 + c * x)^3;
    if w > 0 && log(rand(rs)) < 0.5 * x^2 + dd - dd * w + dd * log(w), g = dd * w; end
end
if k < 1, g = g * rand(rs)^(1 / k); end
end
