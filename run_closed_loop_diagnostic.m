%% RUN_CLOSED_LOOP_DIAGNOSTIC — C3 extended: full decision diagnostics + timing
% Standalone extension of run_closed_loop_with_detector.m (does NOT modify or
% overwrite it). Same pipeline, but records everything needed to explain HOW
% and HOW FAST the system decided what to do:
%   - CNN: full 7-class probability vector (not just top-1), confidence,
%     inference latency (ms)
%   - DQN: full Q-value vector over all 5 actions (not just the chosen one),
%     inference latency (ms)
%   - Rule-based comparison: what rule_based_policy.m would have chosen for
%     the SAME (ground-truth) threat -- shows DQN-vs-rule agreement directly
%   - End-to-end decision latency: CNN + DQN combined (excludes Simulink
%     build/sim time, which is NOT part of a real system's reaction time)
%
% NOTE: tests all 9 threats the CNN was trained on after the Phase B retrain
% (jamming, reactive_jamming, sweeping_jammer, noise_burst, path_loss,
% spoofing, antenna_fault, benign_interference, none).
%
% Output: results/closed_loop_diagnostic_report.txt (full per-threat breakdown)
%         results/closed_loop_diagnostic_timing.png  (latency bar chart)

close all; clc;
fprintf('=== C3-Diagnostic: Full Decision Trace + Timing ===\n\n');

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

% UPDATED (Sep 13): 'none' added -- was previously absent, causing every
% correct 'none' CNN prediction to feed threat_enc=-1 (out-of-distribution)
% to the DQN, which confirmed-picked aggressive actions on a clean channel
% (diagnose_none_class.m). 'none' now has its own trained reward-shaped
% class (see train_dqn.m) so it needs its own encoding here too.
threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','spoofing','antenna_fault','benign_interference','none'};
strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference','none'}, ...
    {'jsr_db','jsr_db','jsr_db','jsr_db','path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db','jsr_db'});
% UPDATED (post-EXP analysis, Sep 13): see train_dqn.m header for rationale.
action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);
action_names = dqn_agent_trained.action_names;
% FIXED (Sep 13-14, antenna_fault Q-value bleed investigation): this map
% previously had noise_burst/spoofing swapped relative to train_dqn.m's
% threat_list index order -- meaning the trained network was queried with
% the wrong encoding for those two threats during this diagnostic. Also
% reassigns antenna_fault away from being adjacent to benign_interference's
% penalized code (see train_dqn.m header for the full rationale). Now
% keys/values match train_dqn.m's threat_encode and
% run_closed_loop_with_detector.m exactly.
threat_encode_map = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','spoofing','antenna_fault','benign_interference','none'}, ...
    {1,2,3,5,6,7,4,8,0});

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

results = struct('threat',{},'cnn_top_class',{},'cnn_conf',{},'cnn_probs',{}, ...
    'cnn_latency_ms',{},'dqn_action',{},'dqn_qvalues',{},'dqn_latency_ms',{}, ...
    'rule_based_action',{},'agrees_with_rule',{},'ber_before',{},'ber_after',{}, ...
    'recovery_pct',{});

%% WARM-UP: first predict() call includes one-time GPU JIT compilation cost
% (~700ms). Run one dummy inference here so it doesn't skew the FIRST real
% threat's measured latency -- this is a deployment reality (the model is
% loaded and warmed up once at startup, not per-decision), so excluding it
% gives the representative per-decision latency.
fprintf('Warming up CNN and DQN networks (one-time GPU JIT cost, excluded from results)...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(5,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

fprintf('Running diagnostic closed-loop on %d known threats...\n\n', numel(threats));

for t = 1:numel(threats)
    threat = threats{t};
    field = strength_field(threat);
    fprintf('[%d/%d] Threat: %s\n', t, numel(threats), threat);

    p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
    p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
    p.benign_int_db=baseline.benign_int_db;
    p.active_threat = threat;
    params = p; save('params.mat', 'params');
    build_threat_model;

    %% --- Simulate: get real BER + IQ ---
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

    %% --- CNN diagnosis (TIMED) ---
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
    [conf, pred_idx] = max(probs_vec);
    cnn_pred_class = char(cnn_classes(pred_idx));

    fprintf('    CNN: %-18s (conf=%.1f%%, %.2f ms)\n', cnn_pred_class, 100*conf, cnn_latency_ms);
    fprintf('    CNN full distribution: ');
    for c = 1:numel(cnn_classes)
        fprintf('%s=%.0f%% ', char(cnn_classes(c)), 100*probs_vec(c));
    end
    fprintf('\n');

    %% --- DQN decision (TIMED) ---
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

    qvals_vec = extractdata(qvals);
    [~, action_idx] = max(qvals_vec);
    action_name = action_names{action_idx};

    fprintf('    DQN: %-18s (%.2f ms) | Q-values: ', action_name, dqn_latency_ms);
    for a = 1:numel(action_names)
        fprintf('%s=%.2f ', action_names{a}, qvals_vec(a));
    end
    fprintf('\n');

    %% --- Rule-based comparison (same ground-truth threat) ---
    [rule_action, ~] = rule_based_policy(threat);
    agrees = strcmp(action_name, rule_action) || ...
             (strcmp(action_name,'channel_switch') && strcmp(rule_action,'channel_switch_fast'));
    fprintf('    Rule-based would choose: %-18s | DQN agrees: %s\n', rule_action, string(agrees));

    %% --- Apply chosen countermeasure, measure recovery ---
    mitigation_db = action_mitigation_db.(action_name);
    p.(field) = baseline.(field) - mitigation_db;
    if any(strcmp(field, {'path_loss_db','fault_atten_db'}))
        p.(field) = max(p.(field), 0);   % physical floor: loss/attenuation can't go negative
    end
    params = p; save('params.mat', 'params');
    build_threat_model;
    ber_after = quick_ber('UAV_GCS_Threat_Link');
    recovery_pct = 100*(ber_before-ber_after)/max(ber_before,eps);

    fprintf('    Recovery: %.1f%% | Total decision latency: %.2f ms\n\n', ...
        recovery_pct, cnn_latency_ms + dqn_latency_ms);

    results(end+1) = struct('threat',threat,'cnn_top_class',cnn_pred_class, ...
        'cnn_conf',conf,'cnn_probs',probs_vec,'cnn_latency_ms',cnn_latency_ms, ...
        'dqn_action',action_name,'dqn_qvalues',qvals_vec,'dqn_latency_ms',dqn_latency_ms, ...
        'rule_based_action',rule_action,'agrees_with_rule',agrees, ...
        'ber_before',ber_before,'ber_after',ber_after,'recovery_pct',recovery_pct);
end

params = p0; save('params.mat', 'params');

%% ========== Full report ==========
report = {};
report{end+1} = '=== C3-DIAGNOSTIC FULL REPORT ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = '';
report{end+1} = 'NOTE: latencies are CNN-inference + DQN-inference only (ms) -- this is';
report{end+1} = 'the actual "reaction time" of the decision system, excluding Simulink';
report{end+1} = 'build/sim time (which is a simulation artifact, not a real deployed cost).';
report{end+1} = '';

for i = 1:numel(results)
    r = results(i);
    report{end+1} = sprintf('--- Threat: %s ---', r.threat);
    report{end+1} = sprintf('  CNN diagnosis: %s (confidence %.1f%%, %.2f ms)', r.cnn_top_class, 100*r.cnn_conf, r.cnn_latency_ms);
    probstr = '';
    for c = 1:numel(cnn_classes)
        probstr = [probstr sprintf('%s=%.0f%% ', char(cnn_classes(c)), 100*r.cnn_probs(c))];
    end
    report{end+1} = sprintf('  CNN full distribution: %s', probstr);
    report{end+1} = sprintf('  DQN decision: %s (%.2f ms)', r.dqn_action, r.dqn_latency_ms);
    qstr = '';
    for a = 1:numel(action_names)
        qstr = [qstr sprintf('%s=%.2f ', action_names{a}, r.dqn_qvalues(a))];
    end
    report{end+1} = sprintf('  DQN Q-values: %s', qstr);
    report{end+1} = sprintf('  Rule-based would choose: %s | DQN agrees: %d', r.rule_based_action, r.agrees_with_rule);
    report{end+1} = sprintf('  BER before=%.3e after=%.3e recovery=%.1f%%', r.ber_before, r.ber_after, r.recovery_pct);
    report{end+1} = sprintf('  Total decision latency: %.2f ms', r.cnn_latency_ms + r.dqn_latency_ms);
    report{end+1} = '';
end

report{end+1} = '=== SUMMARY ===';
report{end+1} = sprintf('Mean CNN latency: %.2f ms | Mean DQN latency: %.2f ms | Mean total: %.2f ms', ...
    mean([results.cnn_latency_ms]), mean([results.dqn_latency_ms]), ...
    mean([results.cnn_latency_ms]+[results.dqn_latency_ms]));
% ADDED (Sep 14): median alongside mean. Confirmed via
% diagnose_latency_position_test.m that noise_burst's prior latency outlier
% (~27-48ms CNN, ~12-29ms DQN) is a periodic ~4th-sequential-call test-harness
% artifact (GPU housekeeping), not threat-specific -- median is robust to
% this kind of positional outlier and better represents true per-decision
% latency than mean.
report{end+1} = sprintf('Median CNN latency: %.2f ms | Median DQN latency: %.2f ms | Median total: %.2f ms', ...
    median([results.cnn_latency_ms]), median([results.dqn_latency_ms]), ...
    median([results.cnn_latency_ms]+[results.dqn_latency_ms]));
report{end+1} = sprintf('DQN-vs-Rule agreement: %d/%d (%.1f%%)', ...
    sum([results.agrees_with_rule]), numel(results), 100*mean([results.agrees_with_rule]));
report{end+1} = sprintf('Mean recovery: %.1f%%', mean([results.recovery_pct]));

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/closed_loop_diagnostic_report.txt','w');
for i=1:numel(report), fprintf(fid,'%s\n',report{i}); end
fclose(fid);
for i=1:numel(report), fprintf('%s\n',report{i}); end
fprintf('\nSaved results/closed_loop_diagnostic_report.txt\n');

%% Timing plot
fig = figure('Position',[100 100 800 400],'Color','w');
bar_data = [[results.cnn_latency_ms]', [results.dqn_latency_ms]'];
b = bar(bar_data,'stacked');
set(gca,'XTickLabel',{results.threat},'XTickLabelRotation',25);
ylabel('Latency (ms)'); title('Decision Latency: CNN + DQN Inference Time');
legend('CNN inference','DQN inference','Location','northeast'); grid on;
saveas(fig,'results/closed_loop_diagnostic_timing.png');
close(fig);
fprintf('Saved results/closed_loop_diagnostic_timing.png\n');
fprintf('\n=== Diagnostic Complete ===\n');