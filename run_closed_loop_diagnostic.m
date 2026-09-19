%% RUN_CLOSED_LOOP_DIAGNOSTIC — C3 extended: sliding-window decision, SNR sweep
% End-to-end closed loop with full decision diagnostics, repeated at every
% SNR point in params.EbNo_dB.
%
% SLIDING WINDOW: each Simulink run returns ~20 frames. Per-frame BER/RSSI/PLR
% are computed across all of them, and the three temporal features
% (var_rssi_10, dber_dt, burst_ratio) are derived over a real causal window
% exactly as extract_spectrograms.m does, so the detector sees the same kind
% of input it was trained on. This is also what the proposal specifies:
% detection from a sliding window of link metrics.
%
% NaN HANDLING: run_dataset_sweep.m marks a frame's BER as NaN when the
% delay-shifted bit stream runs short (the last frame of a run). prepare_data.m
% zeroes those out before training, so the detector never saw NaN. The same
% guards are applied here -- an unguarded NaN propagates through the network
% and makes the softmax output undefined, which silently destroys whole
% classes rather than degrading them.
%
% Output: results/closed_loop_diagnostic_report.txt
%         results/closed_loop_diagnostic_timing.png
%         results/closed_loop_recovery_vs_snr.png
%         results/closed_loop_diagnostic_results.mat

close all; clc;
fprintf('=== C3-Diagnostic: Sliding-Window Decision + Timing (SNR sweep) ===\n\n');

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
modelName = 'UAV_GCS_Threat_Link';

temporal_window = 10;      % must match extract_spectrograms.m
SNR_points = p0.EbNo_dB;   % full sweep, 0:2:10

threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','spoofing','antenna_fault','benign_interference','none'};
strength_field = containers.Map( ...
    {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss','antenna_fault','spoofing','benign_interference','none'}, ...
    {'jsr_db','jsr_db','jsr_db','jsr_db','path_loss_db','fault_atten_db','spoof_sir_db','benign_int_db','jsr_db'});
action_mitigation_db = struct('no_action',0,'channel_switch',25,'rate_reduce',15, ...
    'freq_diversity',25,'spatial_diversity',25);
action_names = dqn_agent_trained.action_names;

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

results = struct('threat',{},'snr_db',{},'cnn_top_class',{},'cnn_conf',{},'cnn_probs',{}, ...
    'cnn_latency_ms',{},'dqn_action',{},'dqn_qvalues',{},'dqn_latency_ms',{}, ...
    'rule_based_action',{},'agrees_with_rule',{},'cnn_correct',{}, ...
    'ber_before',{},'ber_after',{},'recovery_pct',{},'n_frames',{},'temporal_feats',{});

%% WARM-UP: the first predict() calls trigger one-time GPU JIT + cuDNN kernel
% autotuning (the actual convolution kernels are selected lazily on the first
% real-sized input, not on a single dummy pass). A single warm-up leaves the
% first few real measurements inflated (observed: whole SNR=0 block at 4-29ms
% vs ~2ms steady-state, with the worst single spike landing arbitrarily on
% whichever class ran 4th). Several warm-up iterations force autotuning to
% finish before timing starts, so latencies are steady from the first real run.
fprintf('Warming up CNN and DQN networks (GPU JIT + cuDNN autotune, excluded from results)...\n');
dummy_spec = dlarray(single(rand(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(rand(1,7))', 'CB');
dummy_state = dlarray(single(rand(dqn_agent_trained.numStates,1)), 'CB');
if canUseGPU
    dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat);
    dummy_state = gpuArray(dummy_state);
end
for warm = 1:10
    predict(cnn_net, dummy_spec, dummy_feat);
    predict(dqn_agent_trained.qNetwork, dummy_state);
end
if canUseGPU, wait(gpuDevice); end   % block until all warm-up kernels finish
fprintf('Warm-up complete.\n\n');

total_runs = numel(threats) * numel(SNR_points);
fprintf('Running closed loop: %d threats x %d SNR points = %d runs\n', ...
    numel(threats), numel(SNR_points), total_runs);
fprintf('Temporal window: %d frames\n\n', temporal_window);

t_start = tic;
run_count = 0;

for s = 1:numel(SNR_points)
    ebno = SNR_points(s);
    snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);

    fprintf('========== SNR = %g dB ==========\n', ebno);

    for t = 1:numel(threats)
        threat = threats{t};
        field = strength_field(threat);
        run_count = run_count + 1;
        fprintf('[%d/%d] SNR=%g dB | Threat: %s\n', run_count, total_runs, ebno, threat);

        p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
        p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
        p.benign_int_db=baseline.benign_int_db;
        p.active_threat = threat;
        params = p; save('params.mat', 'params');
        build_threat_model;
        set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
            'SignalPower', num2str(1/p.sps));

        %% --- Simulate: extract ALL frames, not just the first ---
        out = sim(modelName);
        [iq_frames, ber_f, rssi_f, plr_f, nf] = extract_closed_loop_frames(out, p, delay_bits);

        % Decide on the last frame that has a valid BER. The final frame of a
        % run is often NaN by construction (see header).
        i_last = find(~isnan(ber_f), 1, 'last');
        if isempty(i_last), i_last = nf; end

        % Temporal features over a causal window ending at that frame,
        % computed as extract_spectrograms.m does, with NaN guards.
        w0 = max(1, i_last - temporal_window + 1);
        var_rssi_10 = var(rssi_f(w0:i_last), 0);
        burst_ratio = mean(plr_f(w0:i_last), 'omitnan');
        if i_last > 1 && ~isnan(ber_f(i_last)) && ~isnan(ber_f(i_last-1))
            dber_dt = (ber_f(i_last) - ber_f(i_last-1)) / p.frame_duration;
        else
            dber_dt = 0;
        end

        iq_rx      = iq_frames{i_last};
        ber_before = ber_f(i_last);
        rssi       = rssi_f(i_last);
        plr        = plr_f(i_last);
        snr_val    = ebno;

        %% --- CNN diagnosis (TIMED) ---
        Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
        Pw = 20*log10(abs(Sxx)+eps); Pw = (Pw-db_lo)/(db_hi-db_lo); Pw = min(max(Pw,0),1);
        spec_img = imresize(Pw, [img_size img_size]);

        raw_feats = [snr_val, ber_before, rssi, plr, var_rssi_10, dber_dt, burst_ratio];
        raw_feats(isnan(raw_feats)) = 0;   % matches prepare_data.m
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
        cnn_correct = strcmp(cnn_pred_class, threat);

        fprintf('    Window: %d/%d frames | var_rssi=%.4f dber_dt=%.1f burst=%.3f\n', ...
            i_last, nf, var_rssi_10, dber_dt, burst_ratio);
        fprintf('    CNN: %-18s (conf=%.1f%%, %.2f ms) correct=%d\n', ...
            cnn_pred_class, 100*conf, cnn_latency_ms, cnn_correct);

        %% --- DQN decision (TIMED) ---
        dqn_state = build_dqn_state(cnn_pred_class, raw_feats(2), rssi, snr_val, plr);
        state_dl = dlarray(single(dqn_state), 'CB');
        if canUseGPU, state_dl = gpuArray(state_dl); end

        t2 = tic;
        qvals = predict(dqn_agent_trained.qNetwork, state_dl);
        dqn_latency_ms = toc(t2) * 1000;

        qvals_vec = extractdata(qvals);
        [~, action_idx] = max(qvals_vec);
        action_name = action_names{action_idx};

        %% --- Rule-based comparison (same ground-truth threat) ---
        [rule_action, ~] = rule_based_policy(threat);
        agrees = strcmp(action_name, rule_action) || ...
                 (strcmp(action_name,'channel_switch') && strcmp(rule_action,'channel_switch_fast'));

        %% --- Apply chosen countermeasure, measure recovery ---
        % When the DQN chose no_action (correct for non-hostile/no-threat
        % cases), there is no countermeasure to measure: BER "before" vs
        % "after" would just be two independent noise draws of the same
        % untouched channel, and dividing their tiny difference produces a
        % meaningless large ratio (e.g. -28.9% at high SNR where BER ~1e-3).
        % Report recovery as NaN in that case -- "no action taken, nothing to
        % recover" -- which is the correct reading, not a failure.
        if strcmp(action_name, 'no_action')
            ber_before_mean = mean(ber_f, 'omitnan');
            ber_after       = ber_before_mean;   % nothing applied
            recovery_pct    = NaN;
            fprintf('    DQN: %-18s (%.2f ms) | Rule: %-18s | Recovery: N/A (no action)\n\n', ...
                action_name, dqn_latency_ms, rule_action);
        else
            mitigation_db = action_mitigation_db.(action_name);
            p.(field) = baseline.(field) - mitigation_db;
            if any(strcmp(field, {'path_loss_db','fault_atten_db'}))
                p.(field) = max(p.(field), 0);   % physical floor
            end
            params = p; save('params.mat', 'params');
            build_threat_model;
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                'SignalPower', num2str(1/p.sps));

            % Before/after both averaged over all valid frames of their runs,
            % so the comparison is like-for-like.
            out2 = sim(modelName);
            [~, ber_f2, ~, ~, ~] = extract_closed_loop_frames(out2, p, delay_bits);
            ber_after       = mean(ber_f2, 'omitnan');
            ber_before_mean = mean(ber_f,  'omitnan');
            recovery_pct = 100*(ber_before_mean-ber_after)/max(ber_before_mean,eps);

            fprintf('    DQN: %-18s (%.2f ms) | Rule: %-18s | Recovery: %.1f%%\n\n', ...
                action_name, dqn_latency_ms, rule_action, recovery_pct);
        end

        results(end+1) = struct('threat',threat,'snr_db',ebno, ...
            'cnn_top_class',cnn_pred_class,'cnn_conf',conf,'cnn_probs',probs_vec, ...
            'cnn_latency_ms',cnn_latency_ms,'dqn_action',action_name, ...
            'dqn_qvalues',qvals_vec,'dqn_latency_ms',dqn_latency_ms, ...
            'rule_based_action',rule_action,'agrees_with_rule',agrees, ...
            'cnn_correct',cnn_correct,'ber_before',ber_before_mean,'ber_after',ber_after, ...
            'recovery_pct',recovery_pct,'n_frames',nf, ...
            'temporal_feats',[var_rssi_10 dber_dt burst_ratio]); %#ok<SAGROW>
    end
end

params = p0; save('params.mat', 'params');
fprintf('Sweep complete. Total time: %.1f minutes\n\n', toc(t_start)/60);

%% ========== Save raw results ==========
if ~exist('results', 'dir'), mkdir('results'); end
save('results/closed_loop_diagnostic_results.mat', 'results', 'SNR_points', 'threats');

%% ========== Full report ==========
report = {};
report{end+1} = '=== C3-DIAGNOSTIC FULL REPORT (SLIDING WINDOW, SNR SWEEP) ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = sprintf('Threats: %d | SNR points: %s dB | Total runs: %d | Temporal window: %d frames', ...
    numel(threats), mat2str(SNR_points), numel(results), temporal_window);
report{end+1} = '';
report{end+1} = 'Temporal features are computed from a real causal window over the frames of';
report{end+1} = 'each run, matching how the detector was trained. NaN BER values (last frame';
report{end+1} = 'of a run, by construction) are guarded exactly as prepare_data.m does.';
report{end+1} = 'BER before/after are both averaged over all valid frames of their runs.';
report{end+1} = '';
report{end+1} = 'NOTE: latencies are CNN-inference + DQN-inference only (ms) -- the actual';
report{end+1} = 'reaction time of the decision system, excluding Simulink build/sim time.';
report{end+1} = '';

%% --- Section 1: recovery matrix, threat x SNR ---
report{end+1} = '--- Section 1: Recovery % per Threat per SNR ---';
hdr = sprintf('%-22s', 'Threat');
for s = 1:numel(SNR_points)
    hdr = [hdr sprintf('%10s', sprintf('%gdB', SNR_points(s)))];
end
hdr = [hdr sprintf('%10s', 'mean')];
report{end+1} = hdr;

for t = 1:numel(threats)
    line = sprintf('%-22s', threats{t});
    mask_t = strcmp({results.threat}, threats{t});
    for s = 1:numel(SNR_points)
        mask = mask_t & ([results.snr_db] == SNR_points(s));
        rp = results(mask).recovery_pct;
        if isnan(rp)
            line = [line sprintf('%10s', 'N/A')];
        else
            line = [line sprintf('%9.1f%%', rp)];
        end
    end
    mean_rp = mean([results(mask_t).recovery_pct], 'omitnan');
    if isnan(mean_rp)
        line = [line sprintf('%10s', 'N/A')];
    else
        line = [line sprintf('%9.1f%%', mean_rp)];
    end
    report{end+1} = line;
end
report{end+1} = '';
report{end+1} = 'N/A = DQN chose no_action (no countermeasure applied, nothing to recover).';

%% --- Section 2: CNN detection accuracy per SNR ---
report{end+1} = '--- Section 2: CNN Detection Accuracy in Closed Loop, per SNR ---';
report{end+1} = sprintf('%-10s %12s', 'SNR (dB)', 'Correct');
for s = 1:numel(SNR_points)
    mask = [results.snr_db] == SNR_points(s);
    n_ok = sum([results(mask).cnn_correct]);
    n = sum(mask);
    report{end+1} = sprintf('%-10g %7d/%-4d (%.1f%%)', SNR_points(s), n_ok, n, 100*n_ok/n);
end
report{end+1} = '';

%% --- Section 2b: per-class detection, all SNR ---
report{end+1} = '--- Section 2b: CNN Detection per Threat Class (all SNR) ---';
report{end+1} = sprintf('%-22s %12s', 'Threat', 'Correct');
for t = 1:numel(threats)
    mask_t = strcmp({results.threat}, threats{t});
    n_ok = sum([results(mask_t).cnn_correct]);
    n = sum(mask_t);
    report{end+1} = sprintf('%-22s %7d/%-4d (%.1f%%)', threats{t}, n_ok, n, 100*n_ok/n);
end
report{end+1} = '';

%% --- Section 3: DQN-vs-Rule agreement per SNR ---
report{end+1} = '--- Section 3: DQN-vs-Rule Agreement, per SNR ---';
report{end+1} = sprintf('%-10s %12s', 'SNR (dB)', 'Agree');
for s = 1:numel(SNR_points)
    mask = [results.snr_db] == SNR_points(s);
    n_ag = sum([results(mask).agrees_with_rule]);
    n = sum(mask);
    report{end+1} = sprintf('%-10g %7d/%-4d (%.1f%%)', SNR_points(s), n_ag, n, 100*n_ag/n);
end
report{end+1} = '';

%% --- Section 4: per-run detail ---
report{end+1} = '--- Section 4: Per-Run Detail ---';
for i = 1:numel(results)
    r = results(i);
    report{end+1} = sprintf('--- %s @ SNR=%g dB ---', r.threat, r.snr_db);
    report{end+1} = sprintf('  Window: %d frames | var_rssi=%.4f dber_dt=%.1f burst=%.3f', ...
        r.n_frames, r.temporal_feats(1), r.temporal_feats(2), r.temporal_feats(3));
    report{end+1} = sprintf('  CNN: %s (conf %.1f%%, %.2f ms, correct=%d)', ...
        r.cnn_top_class, 100*r.cnn_conf, r.cnn_latency_ms, r.cnn_correct);
    qstr = '';
    for a = 1:numel(action_names)
        qstr = [qstr sprintf('%s=%.2f ', action_names{a}, r.dqn_qvalues(a))];
    end
    report{end+1} = sprintf('  DQN: %s (%.2f ms) | Q: %s', r.dqn_action, r.dqn_latency_ms, qstr);
    report{end+1} = sprintf('  Rule: %s | agrees=%d', r.rule_based_action, r.agrees_with_rule);
    if isnan(r.recovery_pct)
        report{end+1} = sprintf('  BER before=%.3e after=%.3e recovery=N/A (no action)', ...
            r.ber_before, r.ber_after);
    else
        report{end+1} = sprintf('  BER before=%.3e after=%.3e recovery=%.1f%%', ...
            r.ber_before, r.ber_after, r.recovery_pct);
    end
end
report{end+1} = '';

%% --- Section 5: summary ---
report{end+1} = '=== SUMMARY (all SNR points) ===';
report{end+1} = sprintf('Mean CNN latency: %.2f ms | Mean DQN latency: %.2f ms | Mean total: %.2f ms', ...
    mean([results.cnn_latency_ms]), mean([results.dqn_latency_ms]), ...
    mean([results.cnn_latency_ms]+[results.dqn_latency_ms]));
report{end+1} = sprintf('Median CNN latency: %.2f ms | Median DQN latency: %.2f ms | Median total: %.2f ms', ...
    median([results.cnn_latency_ms]), median([results.dqn_latency_ms]), ...
    median([results.cnn_latency_ms]+[results.dqn_latency_ms]));
report{end+1} = sprintf('CNN closed-loop detection accuracy: %d/%d (%.1f%%)', ...
    sum([results.cnn_correct]), numel(results), 100*mean([results.cnn_correct]));
report{end+1} = sprintf('DQN-vs-Rule agreement: %d/%d (%.1f%%)', ...
    sum([results.agrees_with_rule]), numel(results), 100*mean([results.agrees_with_rule]));
report{end+1} = sprintf('Mean recovery (all threats, all SNR): %.1f%%', mean([results.recovery_pct], 'omitnan'));

% Mean over real threats only. benign_interference and none have nothing to
% recover (DQN correctly chose no_action -> recovery is N/A/NaN for them),
% so they are excluded both by the real_mask and by omitnan.
real_mask = ~ismember({results.threat}, {'benign_interference','none'});
report{end+1} = sprintf('Mean recovery (real threats only): %.1f%%', mean([results(real_mask).recovery_pct], 'omitnan'));

fid = fopen('results/closed_loop_diagnostic_report.txt','w');
for i=1:numel(report), fprintf(fid,'%s\n',report{i}); end
fclose(fid);
for i=1:numel(report), fprintf('%s\n',report{i}); end
fprintf('\nSaved results/closed_loop_diagnostic_report.txt\n');

%% ========== Plot 1: recovery vs SNR, per threat ==========
fig1 = figure('Position',[100 100 1000 550],'Color','w');
hold on;
for t = 1:numel(threats)
    mask_t = strcmp({results.threat}, threats{t});
    rec = zeros(1, numel(SNR_points));
    for s = 1:numel(SNR_points)
        mask = mask_t & ([results.snr_db] == SNR_points(s));
        rec(s) = results(mask).recovery_pct;
    end
    plot(SNR_points, rec, '-o', 'LineWidth', 1.5, 'DisplayName', strrep(threats{t},'_','\_'));
end
hold off;
xlabel('E_b/N_0 (dB)'); ylabel('BER Recovery (%)');
title('Closed-Loop Recovery vs SNR (sliding-window detection)');
legend('Location','eastoutside'); grid on;
xticks(SNR_points);
saveas(fig1,'results/closed_loop_recovery_vs_snr.png');
close(fig1);
fprintf('Saved results/closed_loop_recovery_vs_snr.png\n');

%% ========== Plot 2: latency ==========
fig2 = figure('Position',[100 100 900 450],'Color','w');
mean_cnn = zeros(1,numel(threats)); mean_dqn = zeros(1,numel(threats));
for t = 1:numel(threats)
    mask_t = strcmp({results.threat}, threats{t});
    mean_cnn(t) = mean([results(mask_t).cnn_latency_ms]);
    mean_dqn(t) = mean([results(mask_t).dqn_latency_ms]);
end
b = bar([mean_cnn(:), mean_dqn(:)],'stacked');
set(gca,'XTickLabel',threats,'XTickLabelRotation',25);
ylabel('Mean Latency (ms)');
title('Decision Latency: CNN + DQN Inference Time (averaged over SNR)');
legend('CNN inference','DQN inference','Location','northeast'); grid on;
saveas(fig2,'results/closed_loop_diagnostic_timing.png');
close(fig2);
fprintf('Saved results/closed_loop_diagnostic_timing.png\n');

fprintf('\n=== Diagnostic Complete ===\n');

%% ===== Helper: extract per-frame IQ, BER, RSSI, PLR from one sim output =====
% Mirrors local_extract() in run_dataset_sweep.m so the features computed
% here match those the detector was trained on, including its NaN convention
% for the final short frame.
% (extract_closed_loop_frames.m -- shared with diagnose_far_measurement.m as
% of D20, was a local function here only, see that file's header for why)