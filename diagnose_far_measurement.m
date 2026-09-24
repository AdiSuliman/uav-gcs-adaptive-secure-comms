%% DIAGNOSE_FAR_MEASUREMENT.m — False Alarm Rate (FAR) characterization, proposal KPI (section ה)
% The proposal defines a false alarm as an unnecessary countermeasure (an
% unnecessary channel switch disrupts the link). FAR = fraction of non-hostile
% trials (none, benign_interference) in which the system acts although the
% link is NOT degraded (BER <= 2x the clean link at that Eb/N0, D29). An action
% on benign interference that degrades the link beyond 2x is a justified
% response, not a false alarm (proposal risk 13: respond to link degradation);
% those are reported separately, together with the old "any action" rate.
%
% CHARACTERIZATION MODE (2026-09-19, D20): swept across several SNR points
% instead of only the worst case. A single-SNR measurement at 0 dB showed
% none->path_loss confusion at ~70%, but a single (threat,SNR) run in
% run_closed_loop_diagnostic.m had shown 100% -- because that diagnostic uses
% N=1 per cell, while this uses N_REPEATS independent draws. Sweeping SNR here
% tells us whether the confusion is a low-SNR edge effect (none and weak
% path_loss both look like "weak structureless signal + strong AWGN" at 0 dB)
% or a model weakness across the whole envelope -- which decides whether the
% fix is documentation, retraining, or an operational hysteresis/dwell-time.
%
% Uses the same real sliding-window feature pipeline as
% run_closed_loop_diagnostic.m (extract_closed_loop_frames.m, D20) -- NOT the
% pre-D16 neutral placeholder.
%
% Output: results/far_measurement.txt, results/far_measurement.mat

close all; clc;
fprintf('=== FAR CHARACTERIZATION: false alarm rate vs SNR on non-hostile classes ===\n\n');

N_REPEATS = 30;                 % independent trials per (class, SNR)
SNR_TEST_POINTS = [0 4 10];     % low edge, mid, high edge
temporal_window = 10;           % must match extract_spectrograms.m

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
modelName = 'UAV_GCS_Threat_Link';
fs = p0.symbol_rate * p0.sps;
delay_bits = 20;

action_names = dqn_agent_trained.action_names;

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

classes_to_test = {'none', 'benign_interference'};

fprintf('Sweeping SNR = %s dB, %d trials per (class, SNR)\n\n', mat2str(SNR_TEST_POINTS), N_REPEATS);

fprintf('Warming up CNN and DQN networks...\n');
dummy_spec = dlarray(single(zeros(img_size,img_size,1,1)), 'SSCB');
dummy_feat = dlarray(single(zeros(1,7))', 'CB');
if canUseGPU, dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat); end
predict(cnn_net, dummy_spec, dummy_feat);
dummy_state = dlarray(single(zeros(dqn_agent_trained.numStates,1)), 'CB');
if canUseGPU, dummy_state = gpuArray(dummy_state); end
predict(dqn_agent_trained.qNetwork, dummy_state);
fprintf('Warm-up complete.\n\n');

RATIO_OK = 2;
results = struct('class',{},'snr',{},'trial',{},'cnn_pred',{},'cnn_correct',{}, ...
    'dqn_action',{},'acted',{},'ber_mean',{},'false_alarm',{});

for si = 1:numel(SNR_TEST_POINTS)
    ebno = SNR_TEST_POINTS(si);
    snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);

    for c = 1:numel(classes_to_test)
        threat = classes_to_test{c};
        fprintf('--- SNR=%g dB | Class: %s (%d trials) ---\n', ebno, threat, N_REPEATS);

        for r = 1:N_REPEATS
            p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
            p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
            p.benign_int_db=baseline.benign_int_db;
            p.active_threat = threat;
            params = p; save('params.mat', 'params');
            build_threat_model;
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), ...
                'SignalPower', num2str(1/p.sps));

            out = sim(modelName);
            [iq_frames, ber_f, rssi_f, plr_f, nf] = extract_closed_loop_frames(out, p, delay_bits);

            i_last = find(~isnan(ber_f), 1, 'last');
            if isempty(i_last), i_last = nf; end

            w0 = max(1, i_last - temporal_window + 1);
            var_rssi_10 = var(rssi_f(w0:i_last), 0);
            burst_ratio = mean(plr_f(w0:i_last), 'omitnan');
            if i_last > 1 && ~isnan(ber_f(i_last)) && ~isnan(ber_f(i_last-1))
                dber_dt = (ber_f(i_last) - ber_f(i_last-1)) / p.frame_duration;
            else
                dber_dt = 0;
            end

            iq_rx = iq_frames{i_last};
            ber   = ber_f(i_last);
            rssi  = rssi_f(i_last);
            plr   = plr_f(i_last);

            Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
            Pw = 20*log10(abs(Sxx)+eps); Pw = (Pw-db_lo)/(db_hi-db_lo); Pw = min(max(Pw,0),1);
            spec_img = imresize(Pw, [img_size img_size]);
            raw_feats = [ebno, ber, rssi, plr, var_rssi_10, dber_dt, burst_ratio];
            raw_feats(isnan(raw_feats)) = 0;
            norm_feats = (raw_feats - feat_mean) ./ feat_std;
            X_spec = dlarray(single(spec_img), 'SSCB');
            X_feat = dlarray(single(norm_feats)', 'CB');
            if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end

            pred_prob = predict(cnn_net, X_spec, X_feat);
            [~, pred_idx] = max(extractdata(pred_prob));
            cnn_pred_class = char(cnn_classes(pred_idx));
            cnn_correct = strcmp(cnn_pred_class, threat);

            dqn_state = build_dqn_state(cnn_pred_class, ber, rssi, ebno, plr);
            state_dl = dlarray(single(dqn_state), 'CB');
            if canUseGPU, state_dl = gpuArray(state_dl); end
            qvals = predict(dqn_agent_trained.qNetwork, state_dl);
            [~, action_idx] = max(extractdata(qvals));
            action_name = action_names{action_idx};

            results(end+1) = struct('class', threat, 'snr', ebno, 'trial', r, ...
                'cnn_pred', cnn_pred_class, 'cnn_correct', cnn_correct, ...
                'dqn_action', action_name, 'acted', ~strcmp(action_name, 'no_action'), ...
                'ber_mean', mean(ber_f, 'omitnan'), 'false_alarm', false); %#ok<SAGROW>
        end
        n_act_this = sum([results(strcmp({results.class},threat) & [results.snr]==ebno).acted]);
        fprintf('  -> acted in %d/%d trials\n\n', n_act_this, N_REPEATS);
    end
end

params = p0; save('params.mat', 'params');

%% Classify each trial against the clean link (mean BER of the 'none' trials at that Eb/N0)
clean_far = nan(size(SNR_TEST_POINTS));
for si = 1:numel(SNR_TEST_POINTS)
    m = strcmp({results.class}, 'none') & [results.snr] == SNR_TEST_POINTS(si);
    clean_far(si) = mean([results(m).ber_mean]);
end
degraded = false(1, numel(results));
for i = 1:numel(results)
    si = find(SNR_TEST_POINTS == results(i).snr, 1);
    degraded(i) = results(i).ber_mean / clean_far(si) > RATIO_OK;
    results(i).false_alarm = results(i).acted && ~degraded(i);
end

%% Summary — per (class, SNR), then per class, then overall
report = {};
report{end+1} = '=== FAR CHARACTERIZATION REPORT ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = sprintf('N_REPEATS per (class,SNR): %d | SNR points: %s dB', N_REPEATS, mat2str(SNR_TEST_POINTS));
report{end+1} = '';

report{end+1} = sprintf('False alarm = action while BER <= %gx clean (D29). "Justified" = action on a link degraded beyond that.', RATIO_OK);
report{end+1} = '--- FAR vs SNR, per class ---';
report{end+1} = sprintf('%-22s %8s %10s %12s %12s %12s', 'Class', 'SNR', 'FAR', 'Degraded', 'Justified', 'CNN acc');
for c = 1:numel(classes_to_test)
    threat = classes_to_test{c};
    for si = 1:numel(SNR_TEST_POINTS)
        ebno = SNR_TEST_POINTS(si);
        mask = strcmp({results.class}, threat) & [results.snr]==ebno;
        n = sum(mask);
        n_fa = sum([results(mask).false_alarm]);
        n_ok = sum([results(mask).cnn_correct]);
        n_deg = sum(degraded(mask));
        n_jus = sum([results(mask).acted] & degraded(mask));
        if n_deg > 0, jus = sprintf('%d/%d', n_jus, n_deg); else, jus = '-'; end
        report{end+1} = sprintf('%-22s %6g dB %9.1f%% %9d/%-3d %12s %10.1f%%', threat, ebno, 100*n_fa/n, ...
            n_deg, n, jus, 100*n_ok/n);
    end
    report{end+1} = '';
end

report{end+1} = '--- Dominant misclassification (where false alarms come from) ---';
for c = 1:numel(classes_to_test)
    threat = classes_to_test{c};
    mask = strcmp({results.class}, threat) & ~[results.cnn_correct];
    if any(mask)
        wrong = {results(mask).cnn_pred};
        u = unique(wrong);
        counts = cellfun(@(x) sum(strcmp(wrong,x)), u);
        [~, ord] = sort(counts, 'descend');
        parts = arrayfun(@(k) sprintf('%s x%d', u{ord(k)}, counts(ord(k))), 1:numel(u), 'uni', 0);
        report{end+1} = sprintf('  %s misdetected as: %s', threat, strjoin(parts, ', '));
    else
        report{end+1} = sprintf('  %s: no misdetections', threat);
    end
end
report{end+1} = '';

for c = 1:numel(classes_to_test)
    threat = classes_to_test{c};
    mask = strcmp({results.class}, threat);
    n = sum(mask); n_fa = sum([results(mask).false_alarm]); n_ok = sum([results(mask).cnn_correct]);
    far_pct = 100*n_fa/n;
    if n_fa == 0
        ci_lo = 0; ci_hi = 100*3/n; ci_note = ' [Rule of Three: 0 events]';
    else
        se = sqrt((far_pct/100)*(1-far_pct/100)/n);
        ci_lo = max(0,far_pct-100*1.96*se); ci_hi = min(100,far_pct+100*1.96*se); ci_note = '';
    end
    report{end+1} = sprintf('--- %s (all SNR pooled, n=%d) ---', threat, n);
    report{end+1} = sprintf('  CNN detection accuracy: %d/%d (%.1f%%)', n_ok, n, 100*n_ok/n);
    report{end+1} = sprintf('  FAR: %.1f%% (approx 95%% CI: %.1f%%-%.1f%%)%s', far_pct, ci_lo, ci_hi, ci_note);
    report{end+1} = '';
end

n_all = numel(results); n_fa_all = sum([results.false_alarm]);
n_healthy = sum(~degraded);
report{end+1} = '=== OVERALL (all classes, all SNR pooled) ===';
report{end+1} = sprintf('Combined FAR: %d/%d (%.1f%%) | over healthy-link trials only: %d/%d', ...
    n_fa_all, n_all, 100*n_fa_all/n_all, n_fa_all, n_healthy);
report{end+1} = sprintf('Any-action rate (pre-D29 definition): %d/%d (%.1f%%)', ...
    sum([results.acted]), n_all, 100*mean([results.acted]));

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/far_measurement.txt', 'w');
for i = 1:numel(report), fprintf(fid, '%s\n', report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end

save('results/far_measurement.mat', 'results');
fprintf('\nSaved results/far_measurement.txt and results/far_measurement.mat\n');
fprintf('\n=== FAR Characterization Complete ===\n');