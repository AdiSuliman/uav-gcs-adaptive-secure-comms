function [truth, pred, sc, ebno_rx] = detector_block(G, p, ebno, seed, v_kmh)
%DETECTOR_BLOCK  One seeded block of frames through the built link model, read as the
%   deployed detector reads it: the shared generator of eval_unseen_snr.m and
%   eval_unseen_severity.m.
%   G      model, stop_time, delay_bits, tw (temporal window of the link features), fs,
%          D (net, ood), N (mu, sd: feature normalization), classes, FM and FN (temporal
%          fusion, fused_class.m; FM empty: per frame)
%   p      params of the built model (active_threat set); ebno [dB]; seed of the block's
%          streams (link_seed.m); v_kmh UAV speed
%   truth  1 x frames class names, the dataset's labels (threat_active.m, per decision
%          cycle: the frame or the idle time before it); with a fusion
%          the fused decision's target (fusion_target.m: a WLAN frame without a packet
%          whose window holds packet frames is benign_interference)
%   pred   1 x frames fused class names
%   sc     1 x frames unknown-threat score of each frame
%   ebno_rx 1 x frames received Eb/N0 [dB]: ebno less a path-loss step from its onset
%          (received_ebno.m)
snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_link_snr(G.model, snr_dB, p);
link_seed(G.model, seed, v_kmh / 3.6 * p.carrier_freq / p.c_light, struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN));
F = extract_closed_loop_frames(sim(G.model, 'StopTime', G.stop_time), p, G.delay_bits);
disk_guard;
v = find(~isnan(F.ber));
X = zeros(128, 128, 1, numel(v), 'single'); Fr = zeros(numel(v), numel(G.N.mu));
for i = 1:numel(v)
    X(:, :, 1, i) = spec_image(F.iq{v(i)}, G.fs, thermal_nv(p));
    Fr(i, :) = link_features(F, v(i), G.tw);
end
[pr, sc] = detect_scores(G.D.net, G.D.ood, X, ((Fr - G.N.mu) ./ G.N.sd)');
k = fused_class(pr', struct('run', ones(numel(v), 1), 'pos', v(:), 'gain_ant', F.gain_ant(:, v)', ...
    'feats_raw', Fr, 'idle', F.idle(:, v)'), G.FM, G.FN);
pred = G.classes(k(:)');
truth = repmat({p.active_threat}, 1, numel(v));
truth(~threat_active(p.active_threat, F.act(v), v, G.tw, F.act_idle(v))) = {'none'};   % per decision cycle
if ~isempty(G.FM)
    [~, yi] = ismember(truth, G.classes);
    truth = G.classes(fusion_target(yi, ones(numel(v), 1), v(:), G.FN, G.classes)');
end
sc = sc(:)';
ebno_rx = received_ebno(p.active_threat, ebno, F.act_comp(:, v), p.path_loss_db);
end
