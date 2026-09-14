%% DIAGNOSE_LATENCY_POSITION_TEST.m — isolates whether the noise_burst
% latency spike (CNN~47ms/DQN~25ms vs ~2-8ms for everyone else, seen
% reproducibly in 3 prior runs, always at loop position 4/9) is caused by
% noise_burst's SIGNAL CONTENT or by LOOP POSITION (e.g. periodic GPU
% memory/JIT housekeeping every ~4 calls, unrelated to which threat it is).
%
% Test: noise_burst moved to position 1 (was always 4). sweeping_jammer
% moved to position 4 (was always 3, previously always measured normal).
% Everything else identical to run_closed_loop_diagnostic.m.
%
% READ THE RESULT LIKE THIS:
%   - noise_burst spikes again at position 1 (and sweeping_jammer normal
%     at position 4)      -> THREAT-SPECIFIC (something about noise_burst's
%                            IQ/spectrogram content). Worth digging into
%                            build_threat_model.m / extract_spectrograms.m.
%   - noise_burst normal at position 1, and sweeping_jammer spikes instead
%     at position 4        -> POSITION-SPECIFIC / systemic (GPU housekeeping,
%                            OS scheduling, etc.) -- not a code bug, can be
%                            documented as a measurement artifact in Phase D.
%   - no spike anywhere    -> the pattern was itself non-reproducible noise;
%                            re-run once more to confirm before concluding.

close all; clc;
fprintf('=== LATENCY POSITION TEST: noise_burst @ pos1, sweeping_jammer @ pos4 ===\n\n');

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

% REORDERED for this test only (see header). Original order for reference:
% {jamming, reactive_jamming, sweeping_jammer, noise_burst, path_loss,
%  spoofing, antenna_fault, benign_interference, none}
threats = {'noise_burst','jamming','reactive_jamming','sweeping_jammer','path_loss','spoofing','antenna_fault','benign_interference','none'};

strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference','none'}, ...
    {'jsr_db','jsr_db','jsr_db','jsr_db','path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db','jsr_db'});
action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);
action_names = dqn_agent_trained.action_names;
threat_encode_map = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','spoofing','antenna_fault','benign_interference','none'}, ...
    {1,2,3,5,6,7,4,8,0});

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

results = struct('threat',{},'cnn_latency_ms',{},'dqn_latency_ms',{});

fprintf('Warming up CNN and DQN networks...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(5,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

for t = 1:numel(threats)
    threat = threats{t};
    field = strength_field(threat);
    fprintf('[%d/%d] Threat: %-18s (loop position %d)\n', t, numel(threats), threat, t);

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
    qvals = predict(dqn_agent_trained.qNetwork, state_dl); %#ok<NASGU>
    dqn_latency_ms = toc(t2) * 1000;

    fprintf('    CNN=%.2fms  DQN=%.2fms  total=%.2fms\n\n', ...
        cnn_latency_ms, dqn_latency_ms, cnn_latency_ms + dqn_latency_ms);

    results(end+1) = struct('threat', threat, 'cnn_latency_ms', cnn_latency_ms, ...
        'dqn_latency_ms', dqn_latency_ms); %#ok<SAGROW>
end

params = p0; save('params.mat', 'params');

fprintf('=== POSITION TEST SUMMARY ===\n');
for i = 1:numel(results)
    fprintf('  pos %d: %-18s CNN=%.2fms DQN=%.2fms\n', i, results(i).threat, ...
        results(i).cnn_latency_ms, results(i).dqn_latency_ms);
end
fprintf('\nCheck: is the spike at position 1 (noise_burst) or position 4 (sweeping_jammer)?\n');

if ~exist('results', 'dir'), mkdir('results'); end
save('results/latency_position_test.mat', 'results');
fprintf('Saved results/latency_position_test.mat\n');