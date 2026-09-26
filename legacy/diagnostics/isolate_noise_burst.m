%% ISOLATE_NOISE_BURST — Standalone latency check, 5x repeated
% Purpose: determine if the ~40-75ms noise_burst latency outlier (seen in
% run_closed_loop_diagnostic.m across multiple runs) is a one-time system
% hiccup or a reproducible threat-specific issue.
%
% Does NOT modify run_closed_loop_diagnostic.m or any other file.
% Copy this into the project root and run standalone.
%
% Output: console table of 5 repeated CNN+DQN latency measurements
%         for noise_burst only, plus jamming as a control comparison.

close all; clc;
fprintf('=== Isolated Latency Check: noise_burst (5x) + jamming control (2x) ===\n\n');

%% 1. Load trained models (same as run_closed_loop_diagnostic.m)
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

strength_field = containers.Map( ...
    {'jamming','noise_burst'}, {'jsr_db','jsr_db'});
threat_encode_map = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','spoofing','path_loss','noise_burst','antenna_fault','benign_interference'}, ...
    {0,1,2,3,4,5,6,7});

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

%% 2. Warm-up (same as diagnostic script — excludes one-time JIT cost)
fprintf('Warming up CNN and DQN networks...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(5,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

%% 3. Test sequence: noise_burst x5, then jamming x2 as control
test_sequence = {'noise_burst','noise_burst','noise_burst','noise_burst','noise_burst', ...
                  'jamming','jamming'};

fprintf('%-4s %-16s %10s %10s %10s\n', 'Run', 'Threat', 'CNN(ms)', 'DQN(ms)', 'Total(ms)');
results_log = [];

for run_i = 1:numel(test_sequence)
    threat = test_sequence{run_i};
    field = strength_field(threat);

    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
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

    t1 = tic;
    pred_prob = predict(cnn_net, X_spec, X_feat);
    cnn_latency_ms = toc(t1) * 1000;

    probs_vec = extractdata(pred_prob);
    [~, pred_idx] = max(probs_vec);
    cnn_pred_class = char(cnn_classes(pred_idx));
    if isKey(threat_encode_map, cnn_pred_class)
        threat_enc = threat_encode_map(cnn_pred_class);
    else
        threat_enc = -1;
    end

    dqn_state = [threat_enc; ber_before; rssi; snr_val; plr];
    state_dl = dlarray(single(dqn_state), 'CB');
    if canUseGPU, state_dl = gpuArray(state_dl); end

    t2 = tic;
    qvals = predict(dqn_agent_trained.qNetwork, state_dl);
    dqn_latency_ms = toc(t2) * 1000;

    total_ms = cnn_latency_ms + dqn_latency_ms;
    fprintf('%-4d %-16s %10.2f %10.2f %10.2f\n', run_i, threat, cnn_latency_ms, dqn_latency_ms, total_ms);
    results_log = [results_log; cnn_latency_ms, dqn_latency_ms, total_ms]; %#ok<AGROW>
end

fprintf('\n=== Summary ===\n');
nb_rows = results_log(1:5,:);
jam_rows = results_log(6:7,:);
fprintf('noise_burst (n=5): CNN mean=%.2fms std=%.2fms | DQN mean=%.2fms std=%.2fms\n', ...
    mean(nb_rows(:,1)), std(nb_rows(:,1)), mean(nb_rows(:,2)), std(nb_rows(:,2)));
fprintf('jamming control (n=2): CNN mean=%.2fms | DQN mean=%.2fms\n', ...
    mean(jam_rows(:,1)), mean(jam_rows(:,2)));
fprintf('\nInterpretation:\n');
fprintf('  - If noise_burst std is small and mean is still 3-5x jamming -> reproducible, real issue.\n');
fprintf('  - If noise_burst values vary widely (one high, rest normal) -> one-time system hiccup.\n');

params = p0; save('params.mat', 'params');