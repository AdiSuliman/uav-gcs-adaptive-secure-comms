%% C3 — CLOSED-LOOP WITH DETECTOR: The Real Test
% End-to-end pipeline: Simulink threat -> IQ+BER -> spectrogram -> CNN detector
% (uncertain prediction) -> DQN agent decides action -> countermeasure applied
% -> BER re-measured -> agent's real-world performance evaluated.
%
% Unlike C2 (synthetic, perfect-knowledge training), this uses the ACTUAL
% trained CNN detector (92.13% accuracy, sometimes wrong) and ACTUAL BER
% measurements from Simulink — not simulated approximations.
%
% Input:  data/trained_detector.mat (CNN from B2)
%         data/trained_dqn.mat      (DQN agent from C2)
% Output: results/closed_loop_results.png
%         console: per-threat detection + action + recovery summary

close all; clc;
fprintf('=== C3: Closed-Loop with Real Detector + DQN ===\n\n');

%% 1. Load trained models
fprintf('Loading trained CNN detector and DQN agent...\n');
D = load('data/trained_detector.mat', 'net', 'classes');
cnn_net = D.net;
cnn_classes = D.classes;

Q = load('data/trained_dqn.mat', 'agent');
dqn_agent_trained = Q.agent;

% Load normalization stats from B1 (needed to normalize live features for CNN)
S = load('data/splits.mat', 'splits');
feat_mean = S.splits.norm.feat_mean;
feat_std  = S.splits.norm.feat_std;

fprintf('  CNN classes: %s\n', strjoin(cellstr(cnn_classes), ', '));
fprintf('  DQN actions: %s\n', strjoin(dqn_agent_trained.action_names, ', '));

%% 2. Spectrogram config — MUST match extract_spectrograms.m exactly
img_size = 128; win = 128; novlp = 113; nfft = 128;
db_lo = -40; db_hi = 20;

init_params;
p = load('params.mat').params;
fs = p.symbol_rate * p.sps;
delay_bits = 20;   % matches run_dataset_sweep.m (training data generation)

%% 3. Test threats — real Simulink, real CNN, real DQN, real recovery
threats = {'jamming', 'reactive_jamming', 'sweeping_jammer', 'noise_burst', ...
           'path_loss', 'spoofing', 'antenna_fault', 'benign_interference'};
n_threats = numel(threats);

% Strength field per threat (verified against init_params/build_threat_model)
strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference'}, ...
    {'jsr_db', 'jsr_db',           'jsr_db',          'jsr_db',   'path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db'});

% action_effectiveness per action index (1=no_action..5=spatial_diversity)
% same convention used in C2 training — countermeasure strength as dB reduction
action_mitigation_db = struct( ...
    'no_action', 0, 'channel_switch', 15, 'rate_reduce', 8, ...
    'freq_diversity', 8, 'spatial_diversity', 12);
action_names = dqn_agent_trained.action_names;

baseline = struct();
baseline.jsr_db = p.jsr_db; baseline.path_loss_db = p.path_loss_db;
baseline.fault_atten_db = p.fault_atten_db; baseline.spoof_sir_db = p.spoof_sir_db;
baseline.benign_int_db = p.benign_int_db;

% Matches dqn_agent.m stateSpec [0,7] and train_dqn.m threat_encode
threat_encode_map = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','spoofing','path_loss','noise_burst','antenna_fault','benign_interference'}, ...
    {0,1,2,3,4,5,6,7});

results = struct('threat',{},'true_class',{},'cnn_pred',{},'cnn_conf',{}, ...
    'action',{},'ber_before',{},'ber_after',{},'recovery_pct',{},'correct_detection',{});

fprintf('\nRunning closed-loop test per threat...\n\n');

for t = 1:n_threats
    threat = threats{t};
    field  = strength_field(threat);
    fprintf('[%d/%d] Threat: %-18s\n', t, n_threats, threat);

    % Reset all threat fields to baseline (isolate this threat)
    p.jsr_db = baseline.jsr_db; p.path_loss_db = baseline.path_loss_db;
    p.fault_atten_db = baseline.fault_atten_db; p.spoof_sir_db = baseline.spoof_sir_db;
    p.benign_int_db = baseline.benign_int_db;
    p.active_threat = threat;
    params = p;
    save('params.mat', 'params');
    build_threat_model;

    %% --- Step 1: Run Simulink, get REAL BER + IQ (before countermeasure) ---
    [ber_before, iq_rx] = quick_ber_with_iq_fixed('UAV_GCS_Threat_Link', delay_bits);
    rssi = 10*log10(mean(abs(iq_rx).^2) + eps);
    snr_val = p.EbNo_dB(1);   % baseline SNR point used in this test
    plr = double(ber_before > 0.1);

    fprintf('    BER (before): %.3e | RSSI: %.1f dB\n', ber_before, rssi);

    %% --- Step 2: Compute spectrogram (SAME pipeline as A6) ---
    Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
    Pw  = 20*log10(abs(Sxx) + eps);
    Pw  = (Pw - db_lo) / (db_hi - db_lo);
    Pw  = min(max(Pw, 0), 1);
    spec_img = imresize(Pw, [img_size img_size]);

    %% --- Step 3: CNN detector prediction (may be WRONG — real uncertainty) ---
    % Build 7-feature vector matching training format: snr,ber,rssi,plr,var_rssi_10,dber_dt,burst_ratio
    % (temporal features unavailable in single-shot test -> use neutral defaults)
    raw_feats = [snr_val, ber_before, rssi, plr, 0, 0, 1];
    norm_feats = (raw_feats - feat_mean) ./ feat_std;

    X_spec = dlarray(single(spec_img), 'SSCB');
    X_feat = dlarray(single(norm_feats)', 'CB');
    if canUseGPU
        X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat);
    end
    pred_prob = predict(cnn_net, X_spec, X_feat);
    [conf, pred_idx] = max(extractdata(pred_prob));
    cnn_pred_class = char(cnn_classes(pred_idx));

    is_correct = strcmp(cnn_pred_class, threat);
    if is_correct
        verdict_str = 'CORRECT';
    else
        verdict_str = 'WRONG';
    end
    fprintf('    CNN detected: %-18s (conf=%.1f%%) | Ground truth: %-18s | %s\n', ...
        cnn_pred_class, 100*conf, threat, verdict_str);

    %% --- Step 4: DQN agent decides action based on CNN's (possibly wrong) prediction ---
    if isKey(threat_encode_map, cnn_pred_class)
        threat_enc = threat_encode_map(cnn_pred_class);
    else
        threat_enc = -1;  % 'none' or unrecognized
    end
    dqn_state = [threat_enc; ber_before; rssi; snr_val; plr];
    action_idx = dqn_select_action(dqn_agent_trained, dqn_state);
    action_name = action_names{action_idx};
    fprintf('    DQN action:   %-18s (based on detected class)\n', action_name);

    %% --- Step 5: Apply countermeasure — reduce THIS threat's real strength field ---
    mitigation_db = action_mitigation_db.(action_name);
    p.(field) = baseline.(field) - mitigation_db;
    params = p;
    save('params.mat', 'params');
    build_threat_model;
    [ber_after, ~] = quick_ber_with_iq_fixed('UAV_GCS_Threat_Link', delay_bits);

    recovery_pct = 100 * (ber_before - ber_after) / max(ber_before, eps);
    fprintf('    BER (after):  %.3e | Recovery: %.1f%%\n\n', ber_after, recovery_pct);

    results(end+1) = struct('threat', threat, 'true_class', threat, ...
        'cnn_pred', cnn_pred_class, 'cnn_conf', conf, 'action', action_name, ...
        'ber_before', ber_before, 'ber_after', ber_after, ...
        'recovery_pct', recovery_pct, 'correct_detection', is_correct);
end

%% 4. Summary
fprintf('=== C3 Summary ===\n');
fprintf('%-18s %-18s %8s %-16s %10s %10s %8s\n', ...
    'Threat', 'CNN Pred', 'Conf%', 'Action', 'BER_bef', 'BER_aft', 'Recov%');
n_correct = 0;
for i = 1:numel(results)
    r = results(i);
    fprintf('%-18s %-18s %7.1f%% %-16s %10.3e %10.3e %7.1f%%\n', ...
        r.threat, r.cnn_pred, 100*r.cnn_conf, r.action, ...
        r.ber_before, r.ber_after, r.recovery_pct);
    n_correct = n_correct + r.correct_detection;
end
fprintf('\nDetection accuracy in closed-loop: %d/%d (%.1f%%)\n', ...
    n_correct, numel(results), 100*n_correct/numel(results));
fprintf('Average BER recovery: %.1f%%\n', mean([results.recovery_pct]));

%% 5. Plot: BER before/after + detection correctness
fig = figure('Position', [100 100 1000 450], 'Color', 'w');
subplot(1,2,1);
bar_data = [[results.ber_before]', [results.ber_after]'];
b = bar(bar_data);
b(1).FaceColor = [0.85 0.33 0.10]; b(2).FaceColor = [0.00 0.45 0.74];
set(gca, 'XTickLabel', {results.threat}, 'XTickLabelRotation', 25);
ylabel('BER'); title('C3: Real Closed-Loop BER Recovery');
legend('Before', 'After', 'Location', 'northeast'); grid on;

subplot(1,2,2);
correct_flags = [results.correct_detection];
bar(categorical({results.threat}), double(correct_flags), 'FaceColor', [0.2 0.7 0.3]);
set(gca, 'XTickLabelRotation', 25);
ylabel('CNN Correct? (1=yes, 0=no)');
title(sprintf('CNN Detection in Loop (%d/%d correct)', n_correct, numel(results)));
ylim([0 1.2]); grid on;

if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/closed_loop_results.png');
fprintf('\nSaved results/closed_loop_results.png\n');
close(fig);

fprintf('\n=== C3 Complete ===\n');

%% ===== Helper functions =====
function [ber, iq_rx] = quick_ber_with_iq_fixed(model, delay_bits)
    % Fixed-delay version (matches run_dataset_sweep.m's training-data delay)
    out = sim(model);
    tx = double(squeeze(out.get('tx_bits_out'))); tx = tx(:);
    rx = double(squeeze(out.get('rx_bits_out'))); rx = rx(:);
    iq_rx = double(squeeze(out.get('Rx_IQ')));
    if isvector(iq_rx), iq_rx = iq_rx(:); end
    if size(iq_rx,2) > 1, iq_rx = iq_rx(:,1); end  % single frame for spectrogram

    L = min(numel(tx)-delay_bits, numel(rx)-delay_bits);
    ber = mean(tx(1:L) ~= rx(delay_bits+1:delay_bits+L));
end

function action_idx = dqn_select_action(agent, state)
    % Greedy action selection (no exploration — deployed agent)
    state_dl = dlarray(single(state), 'CB');
    if canUseGPU
        state_dl = gpuArray(state_dl);
    end
    qvals = predict(agent.qNetwork, state_dl);
    [~, action_idx] = max(extractdata(qvals), [], 1);
end