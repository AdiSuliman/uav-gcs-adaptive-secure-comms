function [truth, pred, sc] = detector_block(G, p, ebno, seed, v_kmh)
%DETECTOR_BLOCK  One seeded block of frames through the built link model, read as the
%   deployed detector reads it: the shared generator of eval_unseen_snr.m and
%   eval_unseen_severity.m.
%   G      model, stop_time, delay_bits, tw (temporal window of the link features), fs,
%          D (net, ood), N (mu, sd: feature normalization), classes, FM and FN (temporal
%          fusion, fused_class.m; FM empty: per frame)
%   p      params of the built model (active_threat set); ebno [dB]; seed of the block's
%          streams (link_seed.m); v_kmh UAV speed
%   truth  1 x frames class names, the dataset's labels (threat_active.m)
%   pred   1 x frames fused class names
%   sc     1 x frames unknown-threat score of each frame
snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
set_param([G.model '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
link_seed(G.model, seed, v_kmh / 3.6 * p.carrier_freq / p.c_light, struct('ebno', ebno, 'alt_m', NaN, 'k_sig_db', NaN));
F = extract_closed_loop_frames(sim(G.model, 'StopTime', G.stop_time), p, G.delay_bits);
disk_guard;
v = find(~isnan(F.ber));
X = zeros(128, 128, 1, numel(v), 'single'); Fr = zeros(numel(v), numel(G.N.mu));
for i = 1:numel(v)
    X(:, :, 1, i) = spec_image(F.iq{v(i)}, G.fs);
    Fr(i, :) = link_features(F, v(i), G.tw);
end
[pr, sc] = detect_scores(G.D.net, G.D.ood, X, ((Fr - G.N.mu) ./ G.N.sd)');
k = fused_class(pr', struct('run', ones(numel(v), 1), 'pos', v(:), 'gain_ant', F.gain_ant(:, v)', ...
    'feats_raw', Fr), G.FM, G.FN);
pred = G.classes(k(:)');
truth = repmat({p.active_threat}, 1, numel(v));
truth(~threat_active(p.active_threat, F.act(v))) = {'none'};
sc = sc(:)';
end
