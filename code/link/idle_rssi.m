function [R, A, info] = idle_rssi(p, ctx, ion, pos, opt)
%IDLE_RSSI  RSSI of every antenna in the receiver's idle time before each frame.
%   [R, A, info] = idle_rssi(p, ctx, ion, pos, opt)
%   One frame per decision cycle leaves the receiver idle for the rest of the cycle (about
%   19.3 of 20 ms), where a real radio reads each chain's RSSI. This is that measurement at
%   its own low rate, not the waveform at the sample rate: per bin of 1/p.idle_rssi_hz from
%   the previous frame's end, every emitter's mean power on every antenna, then the RSSI's
%   own average and spread.
%   p    params of the built model (the threat, its levels after any countermeasure)
%   ctx  the model's block values the run was flown with (idle_context.m): seed base,
%        Doppler, Level gain, interferer directions, K-factors, heading rate, receive
%        correlation, attitude, gated timing, delay-line amplitudes, in-band cap reference,
%        calibration errors
%   ion  3 x bins x frames: the on-share of a recorded schedule per bin, by the threat's
%        component order (build_threat_model.m: the WLAN's packets, the noise bursts), NaN
%        for the others
%   pos  frames of the run (1 = the first: no idle time before it)
%   opt  ambient (bins x antennas x frames, model units: an extra emitter's mean power,
%        attenuated like the threat's own by a faulty connector), meas (false: the mean power
%        without the RSSI's spread, calibration and step)
%   R    bins x antennas x frames [dB over the receiver's floor constant thermal_nv.m], each
%        antenna's calibration error included (the frame measurements' draw), NaN where no
%        idle time precedes the frame
%   A    1 x frames: the share of the idle time with one of the threat's emitters on the
%        air (the per-cycle labels, threat_active.m); NaN for the first frame
%   Exactness: the schedules are the threat block's own (recorded from its draws, or the
%   sweeper's window from its drawn period and phase; a reactive jammer is silent without
%   our frame); each emitter's power is the block's (its level, the in-band cap on the run's
%   reference); its channel to each antenna is the block's sum of sinusoids, the first draws
%   of the block's stream in its own order (threat_script: a faulty antenna, each
%   component's own draws then its 32 sinusoids, the chain errors, the delay line's taps),
%   at the bin's centre, with the heading's turn and the pitch wobble; a faulty connector
%   attenuates the antenna's whole field ahead of the fixed thermal floor.
%   Measurement (Grimaldi et al. 2019, CC2420 on TelosB): a sample every 54 us, the mean
%   power over the last 128 us (Sec. II-B), 1 dB steps (Table III); the estimate of a
%   noise-like field over that time is Gamma(M, 1) / M times its mean, M = B x 128 us
%   complex samples in our channel's band B (a tone's power adds without that spread); its
%   own draws come from the flight's 'idle' stream (seed_stream.m), the block's are replicated
%   on a stream of their own: the caller's global stream is never touched.
%   Stated: the delay line's taps add in power for a noise-like emitter (a white waveform
%   over 54 us), coherently for a tone.
if nargin < 5, opt = struct(); end
o = struct('ambient', [], 'meas', true);
f = fieldnames(opt); for i = 1:numel(f), o.(f{i}) = opt.(f{i}); end
fs = p.symbol_rate * p.sps; nr = p.n_rx; nv = thermal_nv(p);
TB = 1 / p.idle_rssi_hz; cyc = round(p.cycle_s * fs) / fs; Ns = p.samples_per_frame;
NT = 1 + p.tdl * floor(p.tdl_max_ns / p.tdl_step_ns); S = round(p.tdl_step_ns * 1e-9 * fs);
NBI = max(0, floor((round(p.cycle_s * fs) - Ns - (NT - 1) * S) / (fs * TB)));
nf = numel(pos);
R = nan(NBI, nr, nf); A = nan(1, nf);
info = struct('NBI', NBI, 'TB', TB, 'hit', 0);
if NBI == 0, return; end
M = max(1, round(p.symbol_rate * (1 + p.rolloff) * p.idle_rssi_avg_s));
wa = max([p.idle_rssi_avg_s / TB - 2, 1, 1], 0); wa = fliplr(wa / sum(wa));   % bins q, q-1, q-2 of the average
% ---- the threat's components, in the threat block's order ----
thr = lower(p.active_threat); parts = {};
if ~any(strcmp(thr, {'', 'none'})), parts = strsplit(thr, '+'); end
sig = parts(ismember(parts, {'path_loss', 'antenna_fault', 'airframe_shadowing'}));
addc = parts(~ismember(parts, {'path_loss', 'antenna_fault', 'airframe_shadowing'}));
nc = numel(addc);
% ---- the block's first draws (rng(seed + 7), threat_script's init order) ----
tb = RandStream('mt19937ar', 'Seed', ctx.seed + 7);       % the block's stream (rng(seed + 7, 'twister')), the caller's untouched
if ismember('antenna_fault', sig), info.hit = randi(tb, nr); end
[fI, pI, fT, pT] = deal(cell(1, nc)); tone_f = zeros(1, nc);
for c = 1:nc
    switch addc{c}
        case 'tone_jamming', tone_f(c) = p.tone_offset_hz * (2*rand(tb) - 1); rand(tb);
        case 'benign_interference', if ~isempty(p.benign_occ), rand(tb); rand(tb); end
        case 'noise_burst', rand(tb);
    end
    fI{c} = cos(2*pi*rand(tb, 32, nr)); pI{c} = 2*pi*rand(tb, 32, nr);
end
gch = ones(1, nr);
if p.chain_amp_db > 0 || p.chain_phase_deg > 0
    ga = 10.^(p.chain_amp_db * randn(tb, 1, nr) / 20);
    gch = ga .* exp(1j * deg2rad(p.chain_phase_deg) * randn(tb, 1, nr));
end
if NT > 1
    for c = 1:nc, fT{c} = cos(2*pi*rand(tb, 32, nr, NT - 1)); pT{c} = 2*pi*rand(tb, 32, nr, NT - 1); end
end
% ---- each component's power per sample (model units, before the Level gain) ----
PL = 0; if ismember('path_loss', sig), PL = p.path_loss_db; end
P = zeros(1, nc); kind = zeros(1, nc);                    % kind: 1 noise-like, 2 tone, 0 silent in the idle time
for c = 1:nc
    [lf, wsc, kind(c)] = level_field(addc{c}, p);
    L = p.(lf); Lr = L;
    if isfield(p, 'inband_ref') && isfield(p.inband_ref, lf), Lr = p.inband_ref.(lf); end
    cf = 1; if isfinite(p.inband_cap_db), cf = min(1, inband_cap_amp(Lr, PL, p.inband_cap_db) * ctx.cap); end
    P(c) = 10^(L / 10) * wsc * cf^2;
end
Gf = abs(gch).^2;
if info.hit > 0, Gf(info.hit) = Gf(info.hit) * 10^(-p.fault_atten_db / 10); end
% ---- bins ----
ms = seed_stream_of(ctx.seed);
Rr = zeros(nr); for i = 1:nr, for j = 1:nr, Rr(i, j) = ctx.rho^abs(i - j); end, end
Rc = chol(Rr);
lk = 2*pi * p.wobble_arm_m * p.carrier_freq / p.c_light;
apos = (0:nr-1) - (nr-1)/2;
Ki = 10^(ctx.kfac(2) / 10); att = ctx.att;
ild = true; if isfield(p, 'int_los_doppler'), ild = double(p.int_los_doppler); end   % the interferers' LoS Doppler (antenna_defaults)
slot = @(c) find(strcmp(parts, addc{c}), 1);
for j = 1:nf
    k = pos(j);
    if k < 2, continue; end
    ga0 = (k - 1) * cyc - cyc + Ns / fs;                      % the previous frame's end on the channel clock
    tq = ga0 + ((1:NBI)' - 0.5) * TB;
    pw = zeros(NBI, nr); pt = zeros(NBI, nr); on_any = zeros(NBI, 1);
    for c = 1:nc
        s = on_share(addc{c}, p, ctx, ion, slot(c), k, ga0, NBI, TB);
        on_any = max(on_any, s);
        if kind(c) == 0 || P(c) == 0 || ~any(s > 0), continue; end
        th = att(4) + att(5) * sin(2*pi*att(6)*tq + att(7));
        sw = lk * sind(th);
        sI = sind(ctx.aoa(c) + ctx.yaw * tq);
        aI = exp(-1j * 2*pi * p.ant_spacing_wl * (cosd(th) .* sI) * apos);
        lI = exp(1j * (2*pi*ctx.fd*sind(ctx.aoa(c)) * tq * ild + lk * cosd(att(3)) * sI .* sind(th)));
        D0 = zeros(NBI, nr);
        for a = 1:nr
            D0(:, a) = exp(1j * (2*pi*tq*(ctx.fd*fI{c}(:, a)') + sw*fI{c}(:, a)' + pI{c}(:, a)')) * ones(32, 1) / sqrt(32);
        end
        D0 = (D0 * Rc) .* aI;
        h = sqrt(Ki/(Ki+1)) * aI .* lI + sqrt(1/(Ki+1)) * ctx.tdl(1, 1 + c) * D0;
        H = h; pc = abs(h).^2;
        for m = 1:NT-1
            if ctx.tdl(m+1, 1 + c) == 0, continue; end
            Dm = zeros(NBI, nr);
            for a = 1:nr
                Dm(:, a) = exp(1j * (2*pi*tq*(ctx.fd*fT{c}(:, a, m)') + sw*fT{c}(:, a, m)' + pT{c}(:, a, m)')) * ones(32, 1) / sqrt(32);
            end
            Dm = (Dm * Rc) .* aI;
            if kind(c) == 2
                H = H + sqrt(1/(Ki+1)) * ctx.tdl(m+1, 1 + c) * Dm * exp(-1j*2*pi*tone_f(c)*m*S/fs);
            else
                pc = pc + (1/(Ki+1)) * ctx.tdl(m+1, 1 + c)^2 * abs(Dm).^2;
            end
        end
        if kind(c) == 2
            pt = pt + ctx.lev^2 * P(c) * abs(H).^2 .* s .* Gf;
        else
            pw = pw + ctx.lev^2 * P(c) * pc .* s .* Gf;
        end
    end
    A(j) = mean(on_any);
    if ~isempty(o.ambient), pw = pw + o.ambient(:, :, j) .* Gf; end
    pw = filter(wa, 1, pw) ./ filter(wa, 1, ones(NBI, 1));   % the RSSI's average over the idle samples
    pt = filter(wa, 1, pt) ./ filter(wa, 1, ones(NBI, 1));
    if o.meas
        x = (pw + nv) .* gam_m(ms, M, NBI, nr) + pt + sqrt(2 * pt .* (pw + nv) / M) .* randn(ms, NBI, nr);
        x = max(x, 1e-3 * nv);
        rd = 10*log10(x / nv) + reshape(ctx.cal, 1, nr);
        R(:, :, j) = p.idle_rssi_step_db * round(rd / p.idle_rssi_step_db);
    else
        R(:, :, j) = 10*log10((pw + pt + nv) / nv);
    end
end
end

function [lf, wsc, kind] = level_field(comp, p)
% Level field of a component, its power per sample at 0 dB, and how it is on the air in
% the idle time (threat_script: noise-like waveforms, the tone at 1/sps, the spoofer's
% filtered symbols at 1/sps; the reactive jammer only while our frame is on the air).
lf = 'jsr_db'; wsc = 1; kind = 1;
switch comp
    case 'tone_jamming', lf = 'tone_jsr_db'; wsc = 1 / p.sps; kind = 2;
    case 'spoofing', lf = 'spoof_sir_db'; wsc = 1 / p.sps;
    case 'benign_interference', lf = 'benign_int_db';
    case 'reactive_jamming', kind = 0;
end
end

function s = on_share(comp, p, ctx, ion, k, j, ga0, NBI, TB)
% Share of each bin with the component on the air.
switch comp
    case {'benign_interference', 'noise_burst'}
        if strcmp(comp, 'benign_interference') && isempty(p.benign_occ)
            s = ones(NBI, 1);
        elseif isempty(ion) || size(ion, 1) < k || size(ion, 3) < j || all(isnan(ion(k, :, j)))
            s = nan(NBI, 1);
        else
            s = reshape(double(ion(k, 1:NBI, j)), [], 1);
        end
    case 'sweeping_jammer'                                     % on while the sweep's window covers our channel
        g = sweep_window_s(p); T = ctx.gate(1); ph = ctx.gate(2);
        a = ga0 + ((1:NBI)' - 1) * TB + ph; b = a + TB;           % bin edges on the sweep's own time
        s = zeros(NBI, 1);
        for n = floor(min(a) / T) - 1:ceil(max(b) / T) + 1
            s = s + max(0, min(b, n*T + g(2)) - max(a, n*T + g(1)));
        end
        s = s / TB;
    case 'reactive_jamming'
        s = zeros(NBI, 1);
    otherwise
        s = ones(NBI, 1);
end
end

function rs = seed_stream_of(b0)
% The RSSI's own stream: seed_stream.m's 'idle' purpose of the flight whose base is b0.
rs = RandStream('mt19937ar', 'Seed', b0 + 5);
end

function g = gam_m(rs, M, n, m)
% Gamma(M, 1) / M, the mean of M unit exponentials, by the Wilson-Hilferty cube of a normal
% (exact to well below the RSSI's 1 dB step for M of a hundred and more), from stream rs.
c = 1 / (9 * M);
g = max(1 - c + sqrt(c) * randn(rs, n, m), 0).^3;
end
