%% DIAGNOSE_FAR_MEASUREMENT.m — measures False Alarm Rate (FAR), proposal KPI (section ה)
% FAR = fraction of non-hostile cases (none, benign_interference) where the
% closed-loop system (CNN detection -> DQN decision) triggers ANY countermeasure
% other than no_action. The proposal names this explicitly as a KPI: false
% alarms have a real operational cost (an unnecessary channel switch disrupts
% a healthy link), so this must be measured directly.
%
% Runs N_REPEATS independent trials per class (fresh Simulink/Rician draw each
% time), through the FULL closed loop (CNN prediction feeds the DQN, exactly as
% deployed -- not the ground-truth-conditioned path used in
% run_closed_loop_diagnostic.m). Also reports CNN detection accuracy on
% none/benign_interference specifically: a false alarm can originate from
% either a CNN misdetection or the DQN's own decision on a correct detection.
%
% Output: results/far_measurement.txt, results/far_measurement.mat

close all; clc;
fprintf('=== FAR MEASUREMENT: false alarm rate on non-hostile classes ===\n\n');

N_REPEATS = 50;   % independent trials per class; raise if CI is too wide

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

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

classes_to_test = {'none', 'benign_interference'};
strength_field = containers.Map({'none','benign_interference'}, {'jsr_db','benign_int_db'});

fprintf('Warming up CNN and DQN networks...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(dqn_agent_trained.numStates,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

results = struct('class',{},'trial',{},'cnn_pred',{},'cnn_correct',{}, ...
    'dqn_action',{},'false_alarm',{});

for c = 1:numel(classes_to_test)
    threat = classes_to_test{c};
    field = strength_field(threat);
    fprintf('--- Class: %s (%d trials) ---\n', threat, N_REPEATS);

    for r = 1:N_REPEATS
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
        ber = mean(tx(1:L) ~= rx(delay_bits+1:delay_bits+L));
        iq_rx = double(squeeze(out.get('Rx_IQ')));
        if size(iq_rx,2) > 1, iq_rx = iq_rx(:,1); end
        rssi = 10*log10(mean(abs(iq_rx).^2) + eps);
        snr_val = p.EbNo_dB(1);
        plr = double(ber > 0.1);

        Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
        Pw = 20*log10(abs(Sxx)+eps); Pw = (Pw-db_lo)/(db_hi-db_lo); Pw = min(max(Pw,0),1);
        spec_img = imresize(Pw, [img_size img_size]);
        raw_feats = [snr_val, ber, rssi, plr, 0, 0, 1];
        norm_feats = (raw_feats - feat_mean) ./ feat_std;
        X_spec = dlarray(single(spec_img), 'SSCB');
        X_feat = dlarray(single(norm_feats)', 'CB');
        if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end

        pred_prob = predict(cnn_net, X_spec, X_feat);
        [~, pred_idx] = max(extractdata(pred_prob));
        cnn_pred_class = char(cnn_classes(pred_idx));
        cnn_correct = strcmp(cnn_pred_class, threat);

        % DQN decides based on the CNN's prediction, exactly as deployed --
        % NOT on ground truth. A false alarm can come from either a CNN
        % misdetection OR the DQN's own policy on a correctly-detected
        % non-hostile class.
        dqn_state = build_dqn_state(cnn_pred_class, ber, rssi, snr_val, plr);
        state_dl = dlarray(single(dqn_state), 'CB');
        if canUseGPU, state_dl = gpuArray(state_dl); end
        qvals = predict(dqn_agent_trained.qNetwork, state_dl);
        [~, action_idx] = max(extractdata(qvals));
        action_name = action_names{action_idx};

        is_false_alarm = ~strcmp(action_name, 'no_action');

        results(end+1) = struct('class', threat, 'trial', r, ...
            'cnn_pred', cnn_pred_class, 'cnn_correct', cnn_correct, ...
            'dqn_action', action_name, 'false_alarm', is_false_alarm); %#ok<SAGROW>

        if mod(r, 10) == 0
            fprintf('  trial %2d/%d: CNN=%-18s (%s) DQN=%-16s %s\n', r, N_REPEATS, ...
                cnn_pred_class, string(cnn_correct), action_name, ...
                string(~is_false_alarm) + " (no false alarm)");
        end
    end
    fprintf('\n');
end

params = p0; save('params.mat', 'params');

%% Summary
report = {};
report{end+1} = '=== FAR MEASUREMENT REPORT ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = sprintf('N_REPEATS per class: %d', N_REPEATS);
report{end+1} = '';

for c = 1:numel(classes_to_test)
    threat = classes_to_test{c};
    mask = strcmp({results.class}, threat);
    n = sum(mask);
    n_fa = sum([results(mask).false_alarm]);
    n_cnn_correct = sum([results(mask).cnn_correct]);
    far_pct = 100 * n_fa / n;

    % Confidence interval. With zero observed false alarms the normal (Wald)
    % approximation collapses to 0%-0%, which is not a real bound -- use the
    % Rule of Three (upper bound 3/n at 95% confidence) instead.
    if n_fa == 0
        ci_lo = 0; ci_hi = 100 * 3 / n;
        ci_note = ' [Rule of Three: 0 events observed]';
    else
        se = sqrt((far_pct/100)*(1-far_pct/100)/n);
        ci_lo = max(0, far_pct - 100*1.96*se);
        ci_hi = min(100, far_pct + 100*1.96*se);
        ci_note = '';
    end

    report{end+1} = sprintf('--- %s (n=%d) ---', threat, n);
    report{end+1} = sprintf('  CNN detection accuracy: %d/%d (%.1f%%)', n_cnn_correct, n, 100*n_cnn_correct/n);
    report{end+1} = sprintf('  False alarms: %d/%d', n_fa, n);
    report{end+1} = sprintf('  FAR: %.1f%% (approx 95%% CI: %.1f%%-%.1f%%)%s', far_pct, ci_lo, ci_hi, ci_note);
    if n_fa > 0
        fa_actions = {results(mask & [results.false_alarm]).dqn_action};
        report{end+1} = sprintf('  False-alarm actions triggered: %s', strjoin(unique(fa_actions), ', '));
    end
    report{end+1} = '';
end

n_all = numel(results);
n_fa_all = sum([results.false_alarm]);
far_all = 100*n_fa_all/n_all;
report{end+1} = '=== OVERALL ===';
report{end+1} = sprintf('Combined FAR (none + benign_interference): %d/%d (%.1f%%)', n_fa_all, n_all, far_all);
if n_fa_all == 0
    report{end+1} = sprintf('  95%% CI upper bound (Rule of Three): %.1f%%', 100*3/n_all);
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/far_measurement.txt', 'w');
for i = 1:numel(report), fprintf(fid, '%s\n', report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end

save('results/far_measurement.mat', 'results');
fprintf('\nSaved results/far_measurement.txt and results/far_measurement.mat\n');
fprintf('\n=== FAR Measurement Complete ===\n');