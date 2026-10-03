function [P, info] = pool_cell(p, threat, actions, ebno, geo, det, opt)
%POOL_CELL  Measured frames of one threat cell under every configuration:
%   the shared worker of build_policy_pools.m and build_clean_test_pools.m.
%   p        params with the threat and its severity configured (active_threat set)
%   threat   true threat name (apply_countermeasure.m)
%   actions  configuration names (policy_actions.m)
%   ebno     Eb/N0 grid [dB]
%   geo      1 x nS cell, one per Eb/N0: 1 x nSplit struct array, fields seed,
%            speed (km/h), run (ids), and optionally alt (m) and ksig (dB), which
%            replace the seed's altitude and K of our signal (NaN: the seed's own);
%            one entry per geometry (sub-run); the same geometries under every
%            configuration (common random numbers)
%   det      detector: net, ood, classes, mu, sd (feature normalization), fs; [] = no
%            detector (link measurements and ground truth only: survivability maps)
%   opt      F_SUB (frames per sub-run), tw (temporal window), delay_bits
%   P        {nS, nA, nSplit} pools; per frame: probs (classes x ... stored N x C),
%            maha, feat (link_features.m), gant (mean channel gain of every antenna),
%            ber and fer (ground truth), run, aoa, act (share of the frame with the
%            threat on the air)
%   info     configurations actually simulated (identical physics is simulated once)
modelName = 'UAV_GCS_Threat_Link';
nA = numel(actions); nS = numel(ebno); nSp = numel(geo{1});
stop_time = num2str(opt.F_SUB * p.frame_duration);
P = cell(nS, nA, nSp);
keys = {}; first = zeros(1, 0);
info = struct('n_unique', 0, 'map', zeros(1, nA));
for a = 1:nA
    [p2, g_db] = apply_countermeasure(p, threat, actions{a});
    p2.seed = [];
    k = physics_key(p2, g_db);
    j = find(strcmp(keys, k), 1);
    if ~isempty(j)                                  % same physics as an earlier configuration
        P(:, a, :) = P(:, first(j), :);
        info.map(a) = first(j);
        continue;
    end
    keys{end+1} = k; first(end+1) = a; %#ok<AGROW>
    info.map(a) = a; info.n_unique = info.n_unique + 1;
    build_threat_model(p2);
    for s = 1:nS
        snr_dB = ebno(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
        loss = 0; if isfield(p2, 'link_loss_db'), loss = p2.link_loss_db; end   % extra path loss (relay experiment)
        set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db - loss), 'SignalPower', num2str(1/p2.sps));
        for sp = 1:nSp
            g = geo{s}(sp);
            if isempty(det), Q = empty_pool(0, 0); else, Q = empty_pool(numel(det.classes), numel(det.mu)); end
            for r = 1:numel(g.seed)
                seed = g.seed(r);
                fd = g.speed(r) / 3.6 * p.carrier_freq / p.c_light;
                d = link_seed(modelName, seed, fd, struct('ebno', ebno(s), 'alt_m', geo_value(g, 'alt', r), ...
                    'k_sig_db', geo_value(g, 'ksig', r)));
                F = extract_closed_loop_frames(sim(modelName, 'StopTime', stop_time), p2, opt.delay_bits);
                disk_guard;
                Q = add_run(Q, F, det, opt.tw, g.run(r), d.aoa);
            end
            P{s, a, sp} = Q;
        end
    end
end
end

function k = physics_key(p, g)
% Everything that changes the simulated link: the params and the Eb/N0 offset.
k = [jsonencode(p) sprintf('|%.6f', g)];
end

function Q = empty_pool(nC, nF)
Q = struct('probs', zeros(0, nC, 'single'), 'maha', zeros(0, 1, 'single'), 'feat', zeros(0, nF, 'single'), ...
    'gant', zeros(0, 0, 'single'), 'ber', zeros(0, 1), 'fer', zeros(0, 1, 'single'), 'run', zeros(0, 1), ...
    'aoa', zeros(0, 3, 'single'), 'act', zeros(0, 1, 'single'));
end

function v = geo_value(g, f, r)
% Field f of geometry r, NaN when the geometries do not set it.
if isfield(g, f), v = g.(f)(r); else, v = NaN; end
end

function Q = add_run(Q, F, det, tw, run_id, aoa)
% Complete frames of one sub-run with the detector outputs and link features.
v = find(~isnan(F.ber));
if isempty(v), return; end
n = numel(v);
if ~isempty(det)
    X = zeros(128, 128, 1, n, 'single'); Fr = zeros(n, numel(det.mu));
    for i = 1:n
        X(:, :, 1, i) = spec_image(F.iq{v(i)}, det.fs);
        Fr(i, :) = link_features(F, v(i), tw);
    end
    [probs, maha] = detect_scores(det.net, det.ood, X, ((Fr - det.mu) ./ det.sd)', 'cpu');
    Q.probs = [Q.probs; single(probs')]; Q.maha = [Q.maha; single(maha(:))]; Q.feat = [Q.feat; single(Fr)];
end
if isfield(F, 'gain_ant'), Q.gant = [Q.gant; single(F.gain_ant(:, v)')]; end
Q.ber = [Q.ber; F.ber(v)']; Q.fer = [Q.fer; single(F.fer(v)')]; Q.run = [Q.run; repmat(run_id, n, 1)];
a3 = nan(1, 3); a3(1:min(3, numel(aoa))) = aoa(1:min(3, numel(aoa)));
Q.aoa = [Q.aoa; repmat(single(a3), n, 1)];
Q.act = [Q.act; single(F.act(v)')];
end
