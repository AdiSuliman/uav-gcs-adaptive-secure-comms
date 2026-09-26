%% EVAL_SPEED_ROBUSTNESS — closed-loop detection / decision / recovery vs UAV speed
% Sweeps the UAV speed across the whole flight envelope (50-120 km/h, several
% NON-INTEGER speeds) and, at every speed, runs the same sliding-window closed
% loop used by run_closed_loop_diagnostic.m: real Simulink run at that Doppler
% -> real frame extraction -> CNN -> DQN -> (if an action was chosen) a second
% real run with the countermeasure applied.
%
% Channel Doppler follows the speed:  fd = v * fc / c   (2.4 GHz -> ~2.22 Hz per km/h)
%
% WHY: the detector/DQN were originally trained at one speed (72 km/h, fd=160 Hz).
% After regenerating the dataset with speed diversity (run_dataset_sweep.m), this
% script measures whether detection accuracy, false-alarm behaviour and BER
% recovery hold across the envelope -- a robustness result for the report.
%
% Inputs : data/trained_detector.mat, data/trained_dqn.mat, data/splits.mat
% Output : results/speed_robustness.mat / .txt / .png
%
% Runtime: ~ n_speeds x n_SNR x 9 threats sims (+ recovery sims). With the default
% 8 speeds x 3 SNR points this is roughly 30-60 min. Shorten SPEEDS_KMH / SNR_LIST
% for a quick check.

close all; clc;
fprintf('=== Speed Robustness (closed loop, Doppler sweep) ===\n\n');

%% ---------- Configuration ----------
SPEEDS_KMH  = [50 57.3 66.8 72 84.6 97.2 108.9 120];   % km/h (real-valued, non-integers included)
SNR_LIST    = [0 4 10];                                 % Eb/N0 [dB]
DO_RECOVERY = true;                                     % also measure BER recovery after the DQN action

%% ---------- Load models ----------
D = load('data/trained_detector.mat', 'net', 'classes');
Q = load('data/trained_dqn.mat', 'agent');
S = load('data/splits.mat', 'splits');
agent = Q.agent;

init_params;
p0 = load('params.mat').params;

env = struct();
env.net = D.net; env.classes = D.classes;
env.feat_mean = S.splits.norm.feat_mean; env.feat_std = S.splits.norm.feat_std;
env.fs = p0.symbol_rate * p0.sps;
env.win = 128; env.novlp = 113; env.nfft = 128;
env.db_lo = -40; env.db_hi = 40; env.img_size = 128;
env.temporal_window = 10; env.delay_bits = 20;

modelName = 'UAV_GCS_Threat_Link';
threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss', ...
           'spoofing','antenna_fault','benign_interference','none'};
action_names = agent.action_names;
baseline = struct('jsr_db',p0.jsr_db,'path_loss_db',p0.path_loss_db, ...
    'fault_atten_db',p0.fault_atten_db,'spoof_sir_db',p0.spoof_sir_db, ...
    'benign_int_db',p0.benign_int_db);

results = struct('speed_kmh',{},'fd_hz',{},'threat',{},'snr_db',{},'cnn_class',{}, ...
    'cnn_conf',{},'correct',{},'dqn_action',{},'ber_before',{},'ber_after',{},'recovery_pct',{});

%% ---------- Warm-up ----------
dummy_iq = complex(randn(2064,1), randn(2064,1));
for w = 1:3, Sxx_w = spectrogram(dummy_iq, hann(env.win), env.novlp, env.nfft, env.fs, 'centered'); end %#ok<NASGU>
dspec = dlarray(single(rand(env.img_size,env.img_size,1,1)), 'SSCB');
dfeat = dlarray(single(rand(1,numel(env.feat_mean)))', 'CB');
if canUseGPU, dspec = gpuArray(dspec); dfeat = gpuArray(dfeat); end
for w = 1:5, predict(env.net, dspec, dfeat); end

t_start = tic;
total = numel(SPEEDS_KMH) * numel(threats);
count = 0;

for vi = 1:numel(SPEEDS_KMH)
    v_kmh = SPEEDS_KMH(vi);
    fd_hz = (v_kmh/3.6) * p0.carrier_freq / p0.c_light;
    fprintf('========== Speed %.1f km/h (fd = %.1f Hz) ==========\n', v_kmh, fd_hz);

    for t = 1:numel(threats)
        threat = threats{t};
        count = count + 1;

        p = p0; p.jsr_db=baseline.jsr_db; p.path_loss_db=baseline.path_loss_db;
        p.fault_atten_db=baseline.fault_atten_db; p.spoof_sir_db=baseline.spoof_sir_db;
        p.benign_int_db=baseline.benign_int_db;
        p.active_threat = threat;
        p.v_kmh = v_kmh; p.v = v_kmh/3.6; p.fd_max = fd_hz;
        params = p; save('params.mat','params');
        evalc('build_threat_model');

        % ---- Stage 1: detection + decision at every SNR (one baseline build) ----
        grp = struct('snr_db',{},'cls',{},'conf',{},'correct',{},'action',{},'ber_before',{});
        for s = 1:numel(SNR_LIST)
            ebno = SNR_LIST(s);
            snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
            out = sim(modelName);

            [cls, conf, ber_mean, raw] = local_detect(out, p, ebno, env);
            state = build_dqn_state(cls, raw(2), raw(3), ebno, raw(4));
            sdl = dlarray(single(state), 'CB'); if canUseGPU, sdl = gpuArray(sdl); end
            qv = gather(extractdata(predict(agent.qNetwork, sdl)));
            [~, aidx] = max(qv);
            grp(end+1) = struct('snr_db',ebno,'cls',cls,'conf',conf, ...
                'correct',strcmp(cls,threat),'action',action_names{aidx},'ber_before',ber_mean); %#ok<AGROW>
        end

        % ---- Stage 2: recovery, one rebuild per distinct action ----
        ber_after = nan(1, numel(grp));
        if DO_RECOVERY
            acts = unique({grp.action});
            acts = acts(~strcmp(acts,'no_action'));
            for ai = 1:numel(acts)
                act = acts{ai};
                [p2, g_db] = apply_countermeasure(p, threat, act);   % D28
                params = p2; save('params.mat','params');
                evalc('build_threat_model');
                for s = find(strcmp({grp.action}, act))
                    snr_dB = grp(s).snr_db + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
                    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p.sps));
                    out2 = sim(modelName);
                    [~, ber_f2, ~, ~, ~] = extract_closed_loop_frames(out2, p2, env.delay_bits);
                    ber_after(s) = mean(ber_f2, 'omitnan');
                end
            end
        end

        for s = 1:numel(grp)
            g = grp(s);
            if strcmp(g.action,'no_action') || isnan(ber_after(s))
                rec = NaN; ba = g.ber_before;
            else
                ba = ber_after(s);
                rec = 100*(g.ber_before - ba)/max(g.ber_before, eps);
            end
            results(end+1) = struct('speed_kmh',v_kmh,'fd_hz',fd_hz,'threat',threat, ...
                'snr_db',g.snr_db,'cnn_class',g.cls,'cnn_conf',g.conf,'correct',g.correct, ...
                'dqn_action',g.action,'ber_before',g.ber_before,'ber_after',ba,'recovery_pct',rec); %#ok<AGROW>
        end
        fprintf('  [%d/%d] %-20s detected correctly: %d/%d\n', count, total, threat, ...
            sum([grp.correct]), numel(grp));
    end
end

params = p0; save('params.mat','params');
fprintf('\nSweep complete in %.1f min.\n\n', toc(t_start)/60);

%% ---------- KPI #2 against the no-attack link (clean = none run at same speed and Eb/N0) ----------
nonhostile = ismember({results.threat}, {'none','benign_interference'});
RATIO_OK = 2;
for i = 1:numel(results)
    m = strcmp({results.threat}, 'none') & [results.speed_kmh] == results(i).speed_kmh & ...
        [results.snr_db] == results(i).snr_db;
    bc = NaN; if any(m), bc = mean([results(m).ber_before]); end
    results(i).ber_clean    = bc;
    results(i).rec_vs_clean = NaN;
    results(i).ratio_clean  = results(i).ber_after / bc;
    results(i).missed       = false;
    if nonhostile(i), continue; end
    if strcmp(results(i).dqn_action, 'no_action')
        results(i).missed = true;
        results(i).rec_vs_clean = 0;
    else
        [results(i).rec_vs_clean, results(i).ratio_clean] = recovery_vs_clean( ...
            results(i).ber_before, results(i).ber_after, bc);
    end
end
active = ~nonhostile & ~[results.missed];
% False alarm (D29): action on a non-hostile link that is NOT degraded (BER <= 2x clean)
acted     = ~strcmp({results.dqn_action}, 'no_action');
degraded  = [results.ber_before] > RATIO_OK * [results.ber_clean];
false_al  = nonhostile & acted & ~degraded;
justified = nonhostile & acted & degraded;

%% ---------- Save + report ----------
if ~exist('results','dir'), mkdir('results'); end
save('results/speed_robustness.mat','results','SPEEDS_KMH','SNR_LIST','threats');

report = {};
report{end+1} = '=== SPEED ROBUSTNESS (closed loop, Doppler sweep) ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = sprintf('Speeds [km/h]: %s | Eb/N0 points: %s dB | 9 threats/classes', ...
    mat2str(SPEEDS_KMH), mat2str(SNR_LIST));
report{end+1} = 'fd = v * fc / c  (fc = 2.4 GHz)';
report{end+1} = '';
report{end+1} = sprintf('False alarm = action on a non-hostile link with BER <= %gx clean (D29).', RATIO_OK);
report{end+1} = sprintf('%-10s %-10s %-14s %-14s %-16s %-16s', 'km/h','fd (Hz)','Detection','False alarms', ...
    'Rec vs clean', 'Restored (<=2x)');
acc_v = nan(1,numel(SPEEDS_KMH)); rec_v = nan(1,numel(SPEEDS_KMH));
for vi = 1:numel(SPEEDS_KMH)
    m = [results.speed_kmh] == SPEEDS_KMH(vi);
    acc_v(vi) = 100*mean([results(m).correct]);
    mn = m & nonhostile;
    fa = sum(false_al(mn));
    mr = m & active;
    rec_v(vi) = mean([results(mr).rec_vs_clean],'omitnan');
    report{end+1} = sprintf('%-10.1f %-10.1f %6.1f%% (%d/%d) %5d/%-8d %10.1f%% %8d/%-6d', SPEEDS_KMH(vi), ...
        (SPEEDS_KMH(vi)/3.6)*p0.carrier_freq/p0.c_light, acc_v(vi), sum([results(m).correct]), sum(m), ...
        fa, sum(mn), rec_v(vi), sum([results(mr).ratio_clean] <= RATIO_OK), sum(mr)); %#ok<AGROW>
end
report{end+1} = '';
report{end+1} = '--- Detection accuracy per threat x speed (%) ---';
hdr = sprintf('%-22s', 'Threat');
for vi = 1:numel(SPEEDS_KMH), hdr = [hdr sprintf('%8.1f', SPEEDS_KMH(vi))]; end %#ok<AGROW>
report{end+1} = hdr;
for t = 1:numel(threats)
    line = sprintf('%-22s', threats{t});
    for vi = 1:numel(SPEEDS_KMH)
        m = strcmp({results.threat}, threats{t}) & [results.speed_kmh] == SPEEDS_KMH(vi);
        line = [line sprintf('%8.0f', 100*mean([results(m).correct]))]; %#ok<AGROW>
    end
    report{end+1} = line; %#ok<AGROW>
end
report{end+1} = '';
report{end+1} = sprintf('OVERALL detection accuracy: %.1f%% (%d/%d)', 100*mean([results.correct]), ...
    sum([results.correct]), numel(results));
report{end+1} = sprintf('OVERALL false alarms: %d/%d non-hostile runs (%d on a healthy link) | justified actions on degraded links: %d', ...
    sum(false_al), sum(nonhostile), sum(nonhostile & ~degraded), sum(justified));
report{end+1} = sprintf('OVERALL KPI #2 recovery vs clean link (real threats): %.1f%% | restored %d/%d | missed %d', ...
    mean([results(active).rec_vs_clean],'omitnan'), sum([results(active).ratio_clean] <= RATIO_OK), ...
    sum(active), sum([results.missed]));
report{end+1} = sprintf('OVERALL recovery vs BER-before (previous metric): %.1f%%', ...
    mean([results(~nonhostile).recovery_pct],'omitnan'));

fid = fopen('results/speed_robustness.txt','w');
for i = 1:numel(report), fprintf(fid,'%s\n',report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end

fig = figure('Position',[100 100 1000 420],'Color','w');
subplot(1,2,1);
plot(SPEEDS_KMH, acc_v, '-o','LineWidth',2,'MarkerFaceColor','b'); grid on;
xlabel('UAV speed (km/h)'); ylabel('Closed-loop detection accuracy (%)');
title('Detection vs UAV speed'); ylim([max(0,floor(min(acc_v)/10)*10) 100]);
subplot(1,2,2);
plot(SPEEDS_KMH, rec_v, '-s','LineWidth',2,'MarkerFaceColor',[0.85 0.4 0.1],'Color',[0.85 0.4 0.1]); grid on;
xlabel('UAV speed (km/h)'); ylabel('Recovery vs clean link (%)');
title('KPI #2 vs UAV speed (real threats)'); ylim([0 100]);
saveas(fig,'results/speed_robustness.png'); close(fig);
fprintf('\nSaved results/speed_robustness.{mat,txt,png}\n');

%% ===== Local function: detection on the last valid frame of one sim run =====
function [cls, conf, ber_mean, raw_feats] = local_detect(out, p, ebno, env)
    [iq_frames, ber_f, rssi_f, plr_f, nf, sinr_f, ec_f] = extract_closed_loop_frames(out, p, env.delay_bits);
    i_last = find(~isnan(ber_f), 1, 'last');
    if isempty(i_last), i_last = nf; end
    spec_img = spec_image(iq_frames{i_last}, env.fs);
    raw_feats = link_features(struct('sinr', sinr_f, 'ber', ber_f, 'rssi', rssi_f, 'plr', plr_f, ...
        'env_corr', ec_f), i_last, env.temporal_window, p.frame_duration);
    norm_feats = (raw_feats - env.feat_mean) ./ env.feat_std;
    X_spec = dlarray(single(spec_img), 'SSCB');
    X_feat = dlarray(single(norm_feats)', 'CB');
    if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end
    probs = gather(extractdata(predict(env.net, X_spec, X_feat)));
    [conf, idx] = max(probs);
    cls = char(env.classes(idx));
    ber_mean = mean(ber_f, 'omitnan');
end