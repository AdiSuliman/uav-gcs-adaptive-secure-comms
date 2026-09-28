%% DIAGNOSE_NONE_CLASS — Standalone check: clean-channel ('none') scenario
% Purpose: 'none' (clean channel, no threat) is genuinely never tested in
% run_closed_loop_diagnostic.m -- its threats list only has the 8 real
% threats. This checks what the CNN predicts and what the DQN decides when
% the ACTUAL scenario is a clean channel, which is exactly what FAR needs
% to measure (does the system stay quiet when there's nothing to react to).
%
% Does NOT modify any other file. Standalone, read-only diagnostic.
%
% Output: console report -- CNN prediction, DQN action + Q-values, and
%         whether that action would waste resources on a clean channel.

close all; clc;
fprintf('=== Diagnose: "none" (clean channel) scenario in the closed loop ===\n\n');

%% 1. Load trained models
D = load('data/trained_detector.mat', 'net', 'classes');
cnn_net = D.net; cnn_classes = D.classes;
Q = load('data/trained_dqn.mat', 'agent');
dqn_agent_trained = Q.agent;
S = load('data/splits.mat', 'splits');
feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std;

img_size = 128; win = 128; novlp = 113; nfft = 128; db_lo = -40; db_hi = 20;

init_params;
p0 = load('params.mat').params;
fs = p0.symbol_rate * p0.sps;
delay_bits = 20;

action_names = dqn_agent_trained.action_names;
threat_encode_map = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','spoofing','path_loss','noise_burst','antenna_fault','benign_interference'}, ...
    {0,1,2,3,4,5,6,7});
% NOTE: 'none' is deliberately absent from threat_encode_map -- this script
% exists to find out what happens as a result.

%% 2. Warm-up
fprintf('Warming up CNN and DQN networks...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(5,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

%% 3. Run 5 repeats of the TRUE 'none' scenario (clean channel, no threat)
n_runs = 5;
fprintf('%-4s %-22s %8s %-18s %s\n', 'Run', 'CNN pred (conf)', 'enc', 'DQN action', 'Q-values');

for run_i = 1:n_runs
    p = p0;
    p.active_threat = 'none';   % build_threat_model.m: 'none' -> passthrough baseline
    params = p; save('params.mat', 'params');
    build_threat_model;

    out = sim('UAV_GCS_Threat_Link');
    tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
    rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);
    L = min(numel(tx)-delay_bits, numel(rx)-delay_bits);
    ber_before = mean(tx(1:L) ~= rx(delay_bits+1:delay_bits+L));
    iq_rx = double(squeeze(out.get('Rx_IQ')));
    if size(iq_rx,2) > 1, iq_rx = iq_rx(:,1); end
    rssi = 10*log10(mean(abs(iq_rx).^2) + eps);
    snr_val = p.EbNo_dB(1);
    plr = double(ber_before > 0.1);

    Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
    Pw = 20*log10(abs(Sxx)+eps); Pw = (Pw-db_lo)/(db_hi-db_lo); Pw = min(max(Pw,0),1);
    spec_img = imresize(Pw, [img_size img_size]);
    raw_feats = [snr_val, ber_before, rssi, plr, 0, 0, 1];
    norm_feats = (raw_feats - feat_mean) ./ feat_std;
    X_spec = dlarray(single(spec_img), 'SSCB');
    X_feat = dlarray(single(norm_feats)', 'CB');
    if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end

    pred_prob = predict(cnn_net, X_spec, X_feat);
    probs_vec = extractdata(pred_prob);
    [conf, pred_idx] = max(probs_vec);
    cnn_pred_class = char(cnn_classes(pred_idx));

    if isKey(threat_encode_map, cnn_pred_class)
        threat_enc = threat_encode_map(cnn_pred_class);
    else
        threat_enc = -1;   % this is the branch 'none' predictions fall into
    end

    dqn_state = [threat_enc; ber_before; rssi; snr_val; plr];
    state_dl = dlarray(single(dqn_state), 'CB');
    if canUseGPU, state_dl = gpuArray(state_dl); end
    qvals = predict(dqn_agent_trained.qNetwork, state_dl);
    qvals_vec = extractdata(qvals);
    [~, action_idx] = max(qvals_vec);
    action_name = action_names{action_idx};

    qstr = '';
    for a = 1:numel(action_names)
        qstr = [qstr sprintf('%s=%.2f ', action_names{a}, qvals_vec(a))];
    end

    fprintf('%-4d %-16s(%.0f%%) %8d %-18s %s\n', ...
        run_i, cnn_pred_class, 100*conf, threat_enc, action_name, qstr);
end

fprintf('\nInterpretation:\n');
fprintf('  - If CNN correctly predicts "none" and DQN still picks no_action anyway\n');
fprintf('    (despite threat_enc=-1 being out-of-distribution) -> lucky but not guaranteed;\n');
fprintf('    still worth adding "none" to threat_encode_map explicitly for robustness.\n');
fprintf('  - If DQN picks a real action (channel_switch etc.) on a clean channel ->\n');
fprintf('    confirmed false alarm risk, must fix before computing FAR.\n');

params = p0; save('params.mat', 'params');
fprintf('\n=== Diagnostic Complete ===\n');