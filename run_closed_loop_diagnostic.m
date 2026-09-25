%% RUN_CLOSED_LOOP_DIAGNOSTIC — C3d: closed-loop decision over Eb/N0, Monte Carlo (D35)
% End-to-end closed loop repeated at every Eb/N0 in params.EbNo_dB, for every
% threat, over N_MC independent seeds.
%
% Per run: simulate the attacked link, detect on the last valid frame (CNN on the
% spectrogram + 7 link features over a causal 10-frame window, as in training),
% decide with the DQN and with the rule-based policy on the same input, apply
% each decision through apply_countermeasure.m (D28) and re-simulate.
% Before/after sims of one run share the same seed (common random numbers), so
% the comparison is paired; repeats use different seeds.
%
% Link metrics (KPI #2, proposal: BER / packet loss restored to a defined share
% of the no-attack values):
%   BER   rec = 100*(before-after)/(before-clean), capped at 100; ratio after/clean
%         restored <= 2x, marginal <= 5x (D27).
%   PLR   a frame (packet) is lost when its BER > 0.1, the detector's own PLR
%         feature (no FEC modelled); restored when PLR_after <= PLR_clean + 0.05.
%   Goodput kept = goodput_factor(action) * (1 - PLR_after) / (1 - PLR_clean):
%         the share of no-attack throughput the link delivers after the action,
%         the survivability-vs-goodput tradeoff.
% Clean reference = the 'none' run at the same Eb/N0 in the same repeat.
% Headline numbers are means over repeats with a Student-t 95% CI over the
% per-repeat values; proportions pooled over repeats carry a Wilson 95% CI.
%
% Repeats: CFG.mc_repeats from main.m (default 5).
%
% Output: results/closed_loop_diagnostic_report.txt
%         results/closed_loop_diagnostic_results.mat
%         results/closed_loop_recovery_vs_snr.png
%         results/closed_loop_plr_goodput.png
%         results/closed_loop_diagnostic_timing.png

close all; clc;
fprintf('=== C3-Diagnostic: closed loop over Eb/N0, Monte Carlo ===\n\n');

%% 1. Configuration
N_MC = 5;
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'mc_repeats'), N_MC = CFG.mc_repeats; end
SEED_BASE = 1000;
PLR_TOL   = 0.05;
RATIO_OK  = 2; RATIO_MARG = 5;          % same thresholds as the survivability maps
NONHOSTILE = {'benign_interference', 'none'};

%% 2. Models and link
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
temporal_window = 10;                    % must match extract_spectrograms.m
SNR_points = p0.EbNo_dB;

threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss', ...
           'spoofing','antenna_fault','benign_interference','none'};
action_names = dqn_agent_trained.action_names;

baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

results = struct('mc',{},'seed',{},'threat',{},'snr_db',{},'cnn_top_class',{},'cnn_conf',{},'cnn_probs',{}, ...
    'cnn_latency_ms',{},'dqn_action',{},'dqn_qvalues',{},'dqn_latency_ms',{}, ...
    'rule_based_action',{},'agrees_with_rule',{},'cnn_correct',{}, ...
    'ber_before',{},'ber_after',{},'recovery_pct',{},'n_frames',{}, ...
    'ber_after_rule',{},'gp_dqn',{},'gp_rule',{},'temporal_feats',{}, ...
    'plr_before',{},'plr_after',{},'plr_after_rule',{});

%% 3. Warm-up (GPU JIT, cuDNN autotune, spectrogram JIT; excluded from timing)
fprintf('Warming up CNN, DQN and spectrogram()...\n');
dummy_iq_frame = complex(randn(2064,1), randn(2064,1));
for warm = 1:3
    Sxx_warm = spectrogram(dummy_iq_frame, hann(win), novlp, nfft, fs, 'centered'); %#ok<NASGU>
end
dummy_spec  = dlarray(single(rand(img_size,img_size,1,1)), 'SSCB');
dummy_feat  = dlarray(single(rand(1,7))', 'CB');
dummy_state = dlarray(single(rand(dqn_agent_trained.numStates,1)), 'CB');
if canUseGPU
    dummy_spec = gpuArray(dummy_spec); dummy_feat = gpuArray(dummy_feat);
    dummy_state = gpuArray(dummy_state);
end
for warm = 1:10
    predict(cnn_net, dummy_spec, dummy_feat);
    predict(dqn_agent_trained.qNetwork, dummy_state);
end
if canUseGPU, wait(gpuDevice); end
fprintf('Warm-up complete.\n\n');

%% 4. Sweep: repeat x Eb/N0 x threat
total_runs = N_MC * numel(SNR_points) * numel(threats);
fprintf('Closed loop: %d repeats x %d Eb/N0 x %d threats = %d runs\n\n', ...
    N_MC, numel(SNR_points), numel(threats), total_runs);
t_start = tic;
run_count = 0;
n_seeded = NaN;

for mc = 1:N_MC
    fprintf('################ REPEAT %d/%d ################\n', mc, N_MC);
    for s = 1:numel(SNR_points)
        ebno = SNR_points(s);
        snr_dB = ebno + 10*log10(p0.bits_per_symbol) - 10*log10(p0.sps);

        for t = 1:numel(threats)
            threat = threats{t};
            run_count = run_count + 1;
            seed = SEED_BASE + 10000*mc + 100*s + t;
            fprintf('[%d/%d] mc=%d Eb/N0=%g dB | %s\n', run_count, total_runs, mc, ebno, threat);

            p = p0; p.jsr_db = baseline.jsr_db; p.path_loss_db = baseline.path_loss_db;
            p.fault_atten_db = baseline.fault_atten_db; p.spoof_sir_db = baseline.spoof_sir_db;
            p.benign_int_db = baseline.benign_int_db;
            p.active_threat = threat;

            %% --- Attacked link ---
            out = sim_seeded(p, modelName, snr_dB, seed);
            [iq_frames, ber_f, rssi_f, plr_f, nf] = extract_closed_loop_frames(out, p, delay_bits);
            [ber_before, plr_before] = link_means(ber_f);
            if isnan(n_seeded), n_seeded = seed_blocks(modelName, seed); end

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

            %% --- CNN diagnosis (timed: STFT, normalization, resize, forward pass) ---
            t1 = tic;
            Sxx = spectrogram(iq_rx, hann(win), novlp, nfft, fs, 'centered');
            Pw = 20*log10(abs(Sxx)+eps); Pw = (Pw-db_lo)/(db_hi-db_lo); Pw = min(max(Pw,0),1);
            spec_img = imresize(Pw, [img_size img_size]);
            raw_feats = [ebno, ber_f(i_last), rssi_f(i_last), plr_f(i_last), var_rssi_10, dber_dt, burst_ratio];
            raw_feats(isnan(raw_feats)) = 0;     % matches prepare_data.m
            norm_feats = (raw_feats - feat_mean) ./ feat_std;
            X_spec = dlarray(single(spec_img), 'SSCB');
            X_feat = dlarray(single(norm_feats)', 'CB');
            if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end
            pred_prob = predict(cnn_net, X_spec, X_feat);
            cnn_latency_ms = toc(t1) * 1000;

            probs_vec = extractdata(pred_prob);
            [conf, pred_idx] = max(probs_vec);
            cnn_pred_class = char(cnn_classes(pred_idx));
            cnn_correct = strcmp(cnn_pred_class, threat);

            %% --- DQN decision (timed) ---
            dqn_state = build_dqn_state(cnn_pred_class, raw_feats(2), raw_feats(3), ebno, raw_feats(4));
            state_dl = dlarray(single(dqn_state), 'CB');
            if canUseGPU, state_dl = gpuArray(state_dl); end
            t2 = tic;
            qvals = predict(dqn_agent_trained.qNetwork, state_dl);
            dqn_latency_ms = toc(t2) * 1000;
            qvals_vec = extractdata(qvals);
            [~, action_idx] = max(qvals_vec);
            action_name = action_names{action_idx};

            %% --- Rule-based decision on the same input ---
            rule_action = rule_based_policy(cnn_pred_class, raw_feats(2), ebno);
            agrees = strcmp(action_name, rule_action) || ...
                     (strcmp(action_name,'channel_switch') && strcmp(rule_action,'channel_switch_fast'));

            %% --- Outcome of each decision on the true threat (same seed) ---
            [ber_after, plr_after] = outcome(p, threat, action_name, modelName, snr_dB, seed, ...
                delay_bits, ber_before, plr_before);
            if strcmp(rule_action, action_name)
                ber_after_rule = ber_after; plr_after_rule = plr_after;
            else
                [ber_after_rule, plr_after_rule] = outcome(p, threat, rule_action, modelName, snr_dB, seed, ...
                    delay_bits, ber_before, plr_before);
            end
            if strcmp(action_name, 'no_action')
                recovery_pct = NaN;
            else
                recovery_pct = 100*(ber_before - ber_after)/max(ber_before, eps);
            end
            [~, ~, cmD] = apply_countermeasure(p, threat, action_name);
            [~, ~, cmR] = apply_countermeasure(p, threat, rule_action);

            fprintf('    CNN %-18s (%.1f%%, %.2f ms) | DQN %-16s | rule %-16s | BER %.2e -> %.2e | PLR %.2f -> %.2f\n', ...
                cnn_pred_class, 100*conf, cnn_latency_ms, action_name, rule_action, ...
                ber_before, ber_after, plr_before, plr_after);

            results(end+1) = struct('mc',mc,'seed',seed,'threat',threat,'snr_db',ebno, ...
                'cnn_top_class',cnn_pred_class,'cnn_conf',conf,'cnn_probs',probs_vec, ...
                'cnn_latency_ms',cnn_latency_ms,'dqn_action',action_name, ...
                'dqn_qvalues',qvals_vec,'dqn_latency_ms',dqn_latency_ms, ...
                'rule_based_action',rule_action,'agrees_with_rule',agrees, ...
                'cnn_correct',cnn_correct,'ber_before',ber_before,'ber_after',ber_after, ...
                'recovery_pct',recovery_pct,'n_frames',nf, ...
                'ber_after_rule',ber_after_rule,'gp_dqn',cmD.goodput_factor,'gp_rule',cmR.goodput_factor, ...
                'temporal_feats',[var_rssi_10 dber_dt burst_ratio], ...
                'plr_before',plr_before,'plr_after',plr_after,'plr_after_rule',plr_after_rule); %#ok<SAGROW>
        end
    end
end

params = p0; save('params.mat', 'params');
fprintf('\nSweep complete. Total time: %.1f minutes\n\n', toc(t_start)/60);

%% 5. Metrics against the no-attack link of the same repeat and Eb/N0
clean_ber = nan(N_MC, numel(SNR_points));
clean_plr = nan(N_MC, numel(SNR_points));
for mc = 1:N_MC
    for s = 1:numel(SNR_points)
        m = strcmp({results.threat}, 'none') & [results.snr_db] == SNR_points(s) & [results.mc] == mc;
        if any(m)
            clean_ber(mc, s) = mean([results(m).ber_before]);
            clean_plr(mc, s) = mean([results(m).plr_before]);
        end
    end
end

for i = 1:numel(results)
    r = results(i);
    s = find(SNR_points == r.snr_db, 1);
    cb = clean_ber(r.mc, s); cp = clean_plr(r.mc, s);
    results(i).ber_clean    = cb;
    results(i).plr_clean    = cp;
    results(i).rec_vs_clean = NaN;
    results(i).ratio_clean  = r.ber_after / cb;
    results(i).missed       = false;
    results(i).rec_rule     = NaN;
    results(i).ratio_rule   = r.ber_after_rule / cb;
    results(i).plr_rec      = NaN;
    results(i).plr_rec_rule = NaN;
    results(i).plr_ok       = r.plr_after      <= cp + PLR_TOL;
    results(i).plr_ok_rule  = r.plr_after_rule <= cp + PLR_TOL;
    results(i).gp_kept      = r.gp_dqn  * (1 - r.plr_after)      / max(1 - cp, eps);
    results(i).gp_kept_rule = r.gp_rule * (1 - r.plr_after_rule) / max(1 - cp, eps);
    results(i).gp_kept_none = (1 - r.plr_before) / max(1 - cp, eps);
    if ismember(r.threat, NONHOSTILE), continue; end

    results(i).plr_rec      = plr_recovery(r.plr_before, r.plr_after, cp);
    results(i).plr_rec_rule = plr_recovery(r.plr_before, r.plr_after_rule, cp);
    if strcmp(r.rule_based_action, 'no_action')
        results(i).rec_rule = 0;
    else
        [results(i).rec_rule, results(i).ratio_rule] = recovery_vs_clean(r.ber_before, r.ber_after_rule, cb);
    end
    if strcmp(r.dqn_action, 'no_action')
        results(i).missed = true;
        results(i).rec_vs_clean = 0;
        results(i).plr_rec = 0;
    else
        [results(i).rec_vs_clean, results(i).ratio_clean] = recovery_vs_clean(r.ber_before, r.ber_after, cb);
    end
end

%% 6. Per-repeat KPI values (the samples behind every confidence interval)
real_mask = ~ismember({results.threat}, NONHOSTILE);
kpi_names = {'rec_dqn','rec_rule','rec_diff','restored_dqn','restored_rule', ...
             'plr_restored_dqn','plr_restored_rule','plr_rec_dqn','plr_rec_rule', ...
             'gp_dqn','gp_rule','gp_kept_dqn','gp_kept_rule','gp_kept_none', ...
             'cnn_acc','agree','missed'};
kpi_mc = struct();
for k = 1:numel(kpi_names), kpi_mc.(kpi_names{k}) = nan(1, N_MC); end
for mc = 1:N_MC
    R = results(real_mask & [results.mc] == mc);
    A = results([results.mc] == mc);
    kpi_mc.rec_dqn(mc)           = mean([R.rec_vs_clean], 'omitnan');
    kpi_mc.rec_rule(mc)          = mean([R.rec_rule], 'omitnan');
    kpi_mc.rec_diff(mc)          = kpi_mc.rec_dqn(mc) - kpi_mc.rec_rule(mc);
    kpi_mc.restored_dqn(mc)      = 100*mean([R.ratio_clean] <= RATIO_OK);
    kpi_mc.restored_rule(mc)     = 100*mean([R.ratio_rule]  <= RATIO_OK);
    kpi_mc.plr_restored_dqn(mc)  = 100*mean([R.plr_ok]);
    kpi_mc.plr_restored_rule(mc) = 100*mean([R.plr_ok_rule]);
    kpi_mc.plr_rec_dqn(mc)       = mean([R.plr_rec], 'omitnan');
    kpi_mc.plr_rec_rule(mc)      = mean([R.plr_rec_rule], 'omitnan');
    kpi_mc.gp_dqn(mc)            = mean([R.gp_dqn]);
    kpi_mc.gp_rule(mc)           = mean([R.gp_rule]);
    kpi_mc.gp_kept_dqn(mc)       = 100*mean([R.gp_kept]);
    kpi_mc.gp_kept_rule(mc)      = 100*mean([R.gp_kept_rule]);
    kpi_mc.gp_kept_none(mc)      = 100*mean([R.gp_kept_none]);
    kpi_mc.cnn_acc(mc)           = 100*mean([A.cnn_correct]);
    kpi_mc.agree(mc)             = 100*mean([A.agrees_with_rule]);
    kpi_mc.missed(mc)            = sum([R.missed]);
end
kpi_ci = struct();
for k = 1:numel(kpi_names)
    lim = [0 100];
    if strcmp(kpi_names{k}, 'rec_diff'), lim = [-100 100]; end
    if startsWith(kpi_names{k}, 'gp_kept') || strcmp(kpi_names{k}, 'missed'), lim = [0 Inf]; end
    [mm, lo, hi] = stats_ci('t', kpi_mc.(kpi_names{k}), lim);
    kpi_ci.(kpi_names{k}) = [mm lo hi];
end
seeds_effective = N_MC < 2 || std(kpi_mc.rec_dqn) > 0 || std(kpi_mc.cnn_acc) > 0 || ...
    numel(unique(round([results(real_mask).ber_before], 8))) > nnz(real_mask) / N_MC;

%% 7. Save
if ~exist('results', 'dir'), mkdir('results'); end
save('results/closed_loop_diagnostic_results.mat', 'results', 'SNR_points', 'threats', ...
    'clean_ber', 'clean_plr', 'RATIO_OK', 'RATIO_MARG', 'PLR_TOL', 'N_MC', 'SEED_BASE', ...
    'kpi_mc', 'kpi_ci', 'seeds_effective');

%% 8. Report
real_threats = threats(~ismember(threats, NONHOSTILE));
nR = nnz(real_mask);
rep = {};
rep{end+1} = '=== C3-DIAGNOSTIC REPORT (closed loop over Eb/N0, Monte Carlo) ===';
rep{end+1} = sprintf('Generated: %s', datestr(now));
rep{end+1} = sprintf('Repeats: %d (seeds %d + 10000*mc + 100*s + t) | Eb/N0: %s dB | threats: %d | runs: %d', ...
    N_MC, SEED_BASE, mat2str(SNR_points), numel(threats), numel(results));
rep{end+1} = sprintf('Seeded blocks per build: %d (AWGN, bit source) | temporal window: %d frames', ...
    n_seeded, temporal_window);
if ~seeds_effective
    rep{end+1} = 'WARNING: repeats returned identical values -- the seeds did not reach the link randomness.';
end
rep{end+1} = 'Headline values: mean over repeats [95% t-interval over the per-repeat values].';
rep{end+1} = sprintf('BER restored: after <= %gx clean (marginal <= %gx). PLR: frame lost when BER > 0.1; restored when PLR_after <= PLR_clean + %.2f.', ...
    RATIO_OK, RATIO_MARG, PLR_TOL);
rep{end+1} = 'Goodput kept = goodput factor x (1-PLR_after) / (1-PLR_clean), share of no-attack throughput.';
rep{end+1} = 'Latency = STFT + preprocessing + CNN forward pass, plus DQN forward pass (decision chain only, D7).';
rep{end+1} = '';

rep{end+1} = '--- Section 1: headline KPIs (real threats, DQN vs rule-based on the same runs) ---';
rep{end+1} = sprintf('%-34s %-26s %-26s %-26s', 'metric', 'DQN', 'rule-based', 'DQN - rule');
rep{end+1} = sprintf('%-34s %-26s %-26s %-26s', 'KPI2 BER recovery vs clean (%)', ...
    ci_txt(kpi_ci.rec_dqn), ci_txt(kpi_ci.rec_rule), ci_txt(kpi_ci.rec_diff));
rep{end+1} = sprintf('%-34s %-26s %-26s', 'KPI2 BER restored (% of runs)', ...
    ci_txt(kpi_ci.restored_dqn), ci_txt(kpi_ci.restored_rule));
rep{end+1} = sprintf('%-34s %-26s %-26s', 'KPI2 PLR restored (% of runs)', ...
    ci_txt(kpi_ci.plr_restored_dqn), ci_txt(kpi_ci.plr_restored_rule));
rep{end+1} = sprintf('%-34s %-26s %-26s', 'KPI2 PLR recovery vs clean (%)', ...
    ci_txt(kpi_ci.plr_rec_dqn), ci_txt(kpi_ci.plr_rec_rule));
rep{end+1} = sprintf('%-34s %-26s %-26s', 'goodput factor of the action', ...
    ci_txt(kpi_ci.gp_dqn, '%.2f'), ci_txt(kpi_ci.gp_rule, '%.2f'));
rep{end+1} = sprintf('%-34s %-26s %-26s %-26s', 'goodput kept vs no-attack (%)', ...
    ci_txt(kpi_ci.gp_kept_dqn), ci_txt(kpi_ci.gp_kept_rule), ['no action: ' ci_txt(kpi_ci.gp_kept_none)]);
rep{end+1} = sprintf('%-34s %-26s', 'missed detections per repeat', ci_txt(kpi_ci.missed));
k_bd = sum([results(real_mask).ratio_clean] <= RATIO_OK);
k_br = sum([results(real_mask).ratio_rule]  <= RATIO_OK);
[pd, ld, hd] = stats_ci('wilson', k_bd, nR);
[pr, lr, hr] = stats_ci('wilson', k_br, nR);
rep{end+1} = sprintf('Pooled BER restored: DQN %d/%d = %.1f%% [%.1f, %.1f] | rule %d/%d = %.1f%% [%.1f, %.1f] (Wilson)', ...
    k_bd, nR, 100*pd, 100*ld, 100*hd, k_br, nR, 100*pr, 100*lr, 100*hr);
k_pd = sum([results(real_mask).plr_ok]);
[pp, lp, hp] = stats_ci('wilson', k_pd, nR);
rep{end+1} = sprintf('Pooled PLR restored: DQN %d/%d = %.1f%% [%.1f, %.1f] (Wilson)', k_pd, nR, 100*pp, 100*lp, 100*hp);
if ~isnan(kpi_ci.rec_diff(2))
    if kpi_ci.rec_diff(2) > 0
        verdict = 'DQN recovers more than the rule (interval above 0)';
    elseif kpi_ci.rec_diff(3) < 0
        verdict = 'rule recovers more than the DQN (interval below 0)';
    else
        verdict = 'no significant recovery difference (interval contains 0)';
    end
    rep{end+1} = sprintf('DQN vs rule, paired per repeat: %s; goodput factor DQN %.2f vs rule %.2f.', ...
        verdict, kpi_ci.gp_dqn(1), kpi_ci.gp_rule(1));
end
rep{end+1} = '';

rep{end+1} = '--- Section 2: KPI2 BER recovery vs clean per threat and Eb/N0 (mean over repeats; ratio after/clean) ---';
hdr = sprintf('%-20s', 'threat');
for s = 1:numel(SNR_points), hdr = [hdr sprintf('%16s', sprintf('%gdB', SNR_points(s)))]; end %#ok<AGROW>
rep{end+1} = [hdr sprintf('%22s', 'mean [95% CI]')];
for t = 1:numel(real_threats)
    ln = sprintf('%-20s', real_threats{t});
    mt = strcmp({results.threat}, real_threats{t});
    for s = 1:numel(SNR_points)
        c = results(mt & [results.snr_db] == SNR_points(s));
        nm = sum([c.missed]);
        cell_txt = sprintf('%.0f%% %.2fx', mean([c.rec_vs_clean], 'omitnan'), mean([c.ratio_clean], 'omitnan'));
        if nm > 0, cell_txt = sprintf('%s M%d', cell_txt, nm); end
        ln = [ln sprintf('%16s', cell_txt)]; %#ok<AGROW>
    end
    per_mc = arrayfun(@(k) mean([results(mt & [results.mc] == k).rec_vs_clean], 'omitnan'), 1:N_MC);
    rep{end+1} = [ln sprintf('%22s', stats_ci('fmt', per_mc, [-Inf 100]))]; %#ok<SAGROW>
end
rep{end+1} = 'M<n> = the DQN left the link untouched in n repeats (missed, counted as 0% recovery).';
rep{end+1} = sprintf('Clean BER by Eb/N0 (mean over repeats): %s', mat2str(mean(clean_ber, 1, 'omitnan'), 3));
rep{end+1} = sprintf('Clean PLR by Eb/N0 (mean over repeats): %s', mat2str(mean(clean_plr, 1, 'omitnan'), 3));
rep{end+1} = '';

rep{end+1} = '--- Section 3: packet loss per threat and Eb/N0 (mean over repeats: before -> after DQN) ---';
rep{end+1} = hdr;
for t = 1:numel(real_threats)
    ln = sprintf('%-20s', real_threats{t});
    mt = strcmp({results.threat}, real_threats{t});
    for s = 1:numel(SNR_points)
        c = results(mt & [results.snr_db] == SNR_points(s));
        ln = [ln sprintf('%16s', sprintf('%.2f->%.2f', mean([c.plr_before]), mean([c.plr_after])))]; %#ok<AGROW>
    end
    rep{end+1} = ln; %#ok<SAGROW>
end
rep{end+1} = '';

rep{end+1} = '--- Section 4: DQN vs rule per threat (means over Eb/N0 and repeats) ---';
rep{end+1} = sprintf('%-20s %9s %8s %8s %9s   %9s %8s %8s %9s', 'threat', 'DQN rec', 'ratio', 'PLR ok', 'gp kept', ...
    'rule rec', 'ratio', 'PLR ok', 'gp kept');
for t = 1:numel(real_threats)
    c = results(strcmp({results.threat}, real_threats{t}));
    rep{end+1} = sprintf('%-20s %8.1f%% %7.2fx %7.0f%% %8.0f%%   %8.1f%% %7.2fx %7.0f%% %8.0f%%', real_threats{t}, ...
        mean([c.rec_vs_clean], 'omitnan'), mean([c.ratio_clean], 'omitnan'), 100*mean([c.plr_ok]), 100*mean([c.gp_kept]), ...
        mean([c.rec_rule], 'omitnan'), mean([c.ratio_rule], 'omitnan'), 100*mean([c.plr_ok_rule]), 100*mean([c.gp_kept_rule])); %#ok<SAGROW>
end
rd = [results(real_mask).ratio_clean]; rr = [results(real_mask).ratio_rule];
rep{end+1} = sprintf('Per run: DQN better link %d | rule better %d | within 10%% %d (of %d)', ...
    sum(rd < 0.9*rr), sum(rr < 0.9*rd), sum(abs(rd - rr) <= 0.1*max(rd, rr)), nR);
rep{end+1} = '';

rep{end+1} = '--- Section 5: detection and agreement in the loop, per Eb/N0 (pooled over repeats, Wilson 95% CI) ---';
rep{end+1} = sprintf('%-9s %-28s %-28s', 'Eb/N0', 'CNN correct', 'DQN = rule');
for s = 1:numel(SNR_points)
    m = [results.snr_db] == SNR_points(s);
    rep{end+1} = sprintf('%-9s %-28s %-28s', sprintf('%g dB', SNR_points(s)), ...
        wilson_txt(sum([results(m).cnn_correct]), sum(m)), wilson_txt(sum([results(m).agrees_with_rule]), sum(m))); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-22s %-28s', 'threat', 'CNN correct');
for t = 1:numel(threats)
    m = strcmp({results.threat}, threats{t});
    rep{end+1} = sprintf('%-22s %-28s', threats{t}, wilson_txt(sum([results(m).cnn_correct]), sum(m))); %#ok<SAGROW>
end
rep{end+1} = sprintf('All runs: CNN %s | agreement %s', ci_txt(kpi_ci.cnn_acc), ci_txt(kpi_ci.agree));
rep{end+1} = '';

rep{end+1} = '--- Section 6: per-repeat values ---';
rep{end+1} = sprintf('%-4s %8s %9s %10s %10s %9s %9s %8s %8s %6s', 'mc', 'DQN rec', 'rule rec', 'DQN rest', 'rule rest', ...
    'PLR rest', 'gp kept', 'CNN acc', 'agree', 'miss');
for mc = 1:N_MC
    rep{end+1} = sprintf('%-4d %7.1f%% %8.1f%% %9.1f%% %9.1f%% %8.1f%% %8.1f%% %7.1f%% %7.1f%% %6d', mc, ...
        kpi_mc.rec_dqn(mc), kpi_mc.rec_rule(mc), kpi_mc.restored_dqn(mc), kpi_mc.restored_rule(mc), ...
        kpi_mc.plr_restored_dqn(mc), kpi_mc.gp_kept_dqn(mc), kpi_mc.cnn_acc(mc), kpi_mc.agree(mc), kpi_mc.missed(mc)); %#ok<SAGROW>
end
rep{end+1} = '';

lat = [results.cnn_latency_ms] + [results.dqn_latency_ms];
rep{end+1} = '--- Section 7: decision latency (all runs) ---';
rep{end+1} = sprintf('CNN mean %.2f ms | DQN mean %.2f ms | total mean %.2f ms, median %.2f ms, 95th pct %.2f ms', ...
    mean([results.cnn_latency_ms]), mean([results.dqn_latency_ms]), mean(lat), median(lat), p95(lat));
rep{end+1} = '';

rep{end+1} = '--- Section 8: per-run detail, repeat 1 ---';
for i = find([results.mc] == 1)
    r = results(i);
    qstr = '';
    for a = 1:numel(action_names), qstr = [qstr sprintf('%s=%.1f ', action_names{a}, r.dqn_qvalues(a))]; end %#ok<AGROW>
    rep{end+1} = sprintf('%s @ %g dB | CNN %s (%.1f%%) | DQN %s | rule %s | BER %.2e->%.2e (clean %.2e) rec %.1f%% %.2fx | PLR %.2f->%.2f | Q: %s', ...
        r.threat, r.snr_db, r.cnn_top_class, 100*r.cnn_conf, r.dqn_action, r.rule_based_action, ...
        r.ber_before, r.ber_after, r.ber_clean, r.rec_vs_clean, r.ratio_clean, r.plr_before, r.plr_after, qstr); %#ok<SAGROW>
end

rep{end+1} = '';
rep{end+1} = '=== SUMMARY ===';
rep{end+1} = sprintf('KPI #2 recovery vs clean link (real threats, per-run mean): %.1f%% [%.1f, %.1f] over %d repeats', ...
    kpi_ci.rec_dqn(1), kpi_ci.rec_dqn(2), kpi_ci.rec_dqn(3), N_MC);
rep{end+1} = sprintf('KPI #2 link state after countermeasure: %d/%d restored (<= %gx clean), %d marginal, %d not restored | missed detections: %d', ...
    sum(rd <= RATIO_OK), nR, RATIO_OK, sum(rd > RATIO_OK & rd <= RATIO_MARG), sum(rd > RATIO_MARG), sum([results(real_mask).missed]));
rep{end+1} = sprintf('KPI #2 packet loss restored: %d/%d | goodput kept DQN %.0f%% vs rule %.0f%% vs no action %.0f%%', ...
    k_pd, nR, kpi_ci.gp_kept_dqn(1), kpi_ci.gp_kept_rule(1), kpi_ci.gp_kept_none(1));
rep{end+1} = sprintf('Real threats: DQN rec %.1f%%, restored %d/%d, mean goodput %.2f | Rule rec %.1f%%, restored %d/%d, mean goodput %.2f', ...
    kpi_ci.rec_dqn(1), k_bd, nR, kpi_ci.gp_dqn(1), kpi_ci.rec_rule(1), k_br, nR, kpi_ci.gp_rule(1));
rep{end+1} = sprintf('Mean CNN latency: %.2f ms | Mean DQN latency: %.2f ms | Mean total: %.2f ms', ...
    mean([results.cnn_latency_ms]), mean([results.dqn_latency_ms]), mean(lat));
rep{end+1} = sprintf('CNN closed-loop detection accuracy: %d/%d (%.1f%%)', ...
    sum([results.cnn_correct]), numel(results), 100*mean([results.cnn_correct]));
rep{end+1} = sprintf('DQN-vs-Rule agreement: %d/%d (%.1f%%)', ...
    sum([results.agrees_with_rule]), numel(results), 100*mean([results.agrees_with_rule]));

fid = fopen('results/closed_loop_diagnostic_report.txt', 'w');
fprintf(fid, '%s\n', rep{:});
fclose(fid);
fprintf('%s\n', rep{:});
fprintf('\nSaved results/closed_loop_diagnostic_report.txt\n');

%% 9. Plots
plot_recovery(results, real_threats, SNR_points, N_MC);
plot_plr_goodput(results, real_threats, SNR_points);
plot_latency(results, threats);
fprintf('\n=== Diagnostic Complete ===\n');

%% ========== Local functions ==========
function out = sim_seeded(p, modelName, snr_dB, seed)
% Build the link for p, set the AWGN level and every seeded block, simulate.
params = p; save('params.mat', 'params'); %#ok<NASGU>
rng(seed, 'twister');
build_threat_model;
set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
seed_blocks(modelName, seed);
out = sim(modelName);
end

function n = seed_blocks(modelName, seed)
% Seeds the AWGN channel and the bit source. Parameter names differ between
% releases, so they are matched case-insensitively among the dialog parameters.
blks = {[modelName '/AWGN'], [modelName '/BitSource']};
n = 0;
for b = 1:numel(blks)
    try
        dp = fieldnames(get_param(blks{b}, 'DialogParameters'));
        for j = 1:numel(dp)
            if strcmpi(dp{j}, 'RandomStream')
                try, set_param(blks{b}, dp{j}, 'mt19937ar with seed'); catch, end
            end
        end
        for j = 1:numel(dp)
            if strcmpi(dp{j}, 'seed')
                set_param(blks{b}, dp{j}, num2str(seed + b));
                n = n + 1;
            end
        end
    catch
    end
end
end

function [ber_after, plr_after] = outcome(p, threat, action, modelName, snr_dB, seed, delay_bits, ber_before, plr_before)
% Link state after applying one action to the true threat (D28).
if strcmp(action, 'no_action')
    ber_after = ber_before; plr_after = plr_before;
    return;
end
[p_cm, g_db] = apply_countermeasure(p, threat, action);
out = sim_seeded(p_cm, modelName, snr_dB + g_db, seed);
[~, ber_f] = extract_closed_loop_frames(out, p, delay_bits);
[ber_after, plr_after] = link_means(ber_f);
end

function [ber, plr] = link_means(ber_f)
% Mean BER and packet loss over the valid frames of one run (frame lost when BER > 0.1).
v = ber_f(~isnan(ber_f));
if isempty(v), ber = NaN; plr = NaN; return; end
ber = mean(v);
plr = mean(v > 0.1);
end

function r = plr_recovery(before, after, clean)
% Share of the attack-induced packet loss that was removed; NaN when the attack
% caused no packet loss beyond the clean link.
gap = before - clean;
if ~isfinite(gap) || gap <= 0.02, r = NaN; return; end
r = min(100, 100 * (before - after) / gap);
end

function y = p95(x)
x = sort(x(:));
y = x(max(1, ceil(0.95 * numel(x))));
end

function s = ci_txt(v, f)
if nargin < 2, f = '%.1f'; end
if isnan(v(2))
    s = sprintf(f, v(1));
else
    s = sprintf([f ' [' f ', ' f ']'], v(1), v(2), v(3));
end
end

function s = wilson_txt(k, n)
[p, lo, hi] = stats_ci('wilson', k, n);
s = sprintf('%d/%d %.1f%% [%.1f, %.1f]', k, n, 100*p, 100*lo, 100*hi);
end

function plot_recovery(results, real_threats, SNR_points, N_MC)
fig = figure('Position', [100 100 1000 550], 'Color', 'w');
hold on;
for t = 1:numel(real_threats)
    mt = strcmp({results.threat}, real_threats{t});
    mu = nan(1, numel(SNR_points)); lo = mu; hi = mu;
    for s = 1:numel(SNR_points)
        v = [results(mt & [results.snr_db] == SNR_points(s)).rec_vs_clean];
        [mu(s), lo(s), hi(s)] = stats_ci('t', v, [-Inf 100]);
    end
    if N_MC > 1 && any(~isnan(lo))
        lo(isnan(lo)) = mu(isnan(lo)); hi(isnan(hi)) = mu(isnan(hi));
        errorbar(SNR_points, mu, mu - lo, hi - mu, '-o', 'LineWidth', 1.4, 'CapSize', 4, ...
            'DisplayName', strrep(real_threats{t}, '_', '\_'));
    else
        plot(SNR_points, mu, '-o', 'LineWidth', 1.4, 'DisplayName', strrep(real_threats{t}, '_', '\_'));
    end
end
hold off;
xlabel('E_b/N_0 (dB)'); ylabel('Recovery vs clean link (%)');
title(sprintf('KPI #2: recovery vs the no-attack link (mean and 95%% CI over %d repeats)', N_MC));
legend('Location', 'eastoutside'); grid on; xticks(SNR_points); ylim([-20 110]);
saveas(fig, 'results/closed_loop_recovery_vs_snr.png'); close(fig);
fprintf('Saved results/closed_loop_recovery_vs_snr.png\n');
end

function plot_plr_goodput(results, real_threats, SNR_points)
fig = figure('Position', [100 100 1200 480], 'Color', 'w');
real_mask = ismember({results.threat}, real_threats);
subplot(1, 2, 1); hold on;
pb = nan(1, numel(SNR_points)); pd = pb; pr = pb; pc = pb;
for s = 1:numel(SNR_points)
    c = results(real_mask & [results.snr_db] == SNR_points(s));
    pb(s) = mean([c.plr_before]); pd(s) = mean([c.plr_after]);
    pr(s) = mean([c.plr_after_rule]); pc(s) = mean([c.plr_clean]);
end
plot(SNR_points, pb, 'k--o', 'LineWidth', 1.4, 'DisplayName', 'attacked, no action');
plot(SNR_points, pd, 'b-o', 'LineWidth', 1.6, 'DisplayName', 'after DQN');
plot(SNR_points, pr, 'r-s', 'LineWidth', 1.4, 'DisplayName', 'after rule');
plot(SNR_points, pc, 'g-^', 'LineWidth', 1.4, 'DisplayName', 'no-attack link');
hold off; grid on; xticks(SNR_points);
xlabel('E_b/N_0 (dB)'); ylabel('Packet loss rate'); ylim([0 1]);
title('KPI #2: packet loss, real threats'); legend('Location', 'northeast');

subplot(1, 2, 2); hold on;
for t = 1:numel(real_threats)
    c = results(strcmp({results.threat}, real_threats{t}));
    xd = mean([c.gp_dqn]);  yd = mean([c.rec_vs_clean], 'omitnan');
    xr = mean([c.gp_rule]); yr = mean([c.rec_rule], 'omitnan');
    plot([xr xd], [yr yd], ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    plot(xd, yd, 'bo', 'MarkerFaceColor', 'b', 'HandleVisibility', 'off');
    plot(xr, yr, 'rs', 'HandleVisibility', 'off');
    text(xd + 0.01, yd, strrep(real_threats{t}, '_', '\_'), 'FontSize', 8);
end
plot(nan, nan, 'bo', 'MarkerFaceColor', 'b', 'DisplayName', 'DQN');
plot(nan, nan, 'rs', 'DisplayName', 'rule');
hold off; grid on; xlim([0 1.1]); ylim([-10 110]);
xlabel('Goodput factor of the chosen action'); ylabel('Recovery vs clean (%)');
title('Survivability vs goodput, per threat'); legend('Location', 'southwest');
saveas(fig, 'results/closed_loop_plr_goodput.png'); close(fig);
fprintf('Saved results/closed_loop_plr_goodput.png\n');
end

function plot_latency(results, threats)
fig = figure('Position', [100 100 900 450], 'Color', 'w');
mc = zeros(1, numel(threats)); md = mc;
for t = 1:numel(threats)
    m = strcmp({results.threat}, threats{t});
    mc(t) = mean([results(m).cnn_latency_ms]);
    md(t) = mean([results(m).dqn_latency_ms]);
end
bar([mc(:), md(:)], 'stacked');
set(gca, 'XTickLabel', strrep(threats, '_', '\_'), 'XTickLabelRotation', 25);
ylabel('Mean latency (ms)'); title('Decision latency: CNN path + DQN (all runs)');
legend('CNN path', 'DQN', 'Location', 'northeast'); grid on;
saveas(fig, 'results/closed_loop_diagnostic_timing.png'); close(fig);
fprintf('Saved results/closed_loop_diagnostic_timing.png\n');
end
