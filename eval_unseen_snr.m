%% EVAL_UNSEEN_SNR.m — detector generalization to Eb/N0 never seen in training (D34)
% Proposal mitigation 4: "test generalization on SNR values not included in
% training". The dataset uses Eb/N0 = 0:2:10 dB; this script generates fresh
% frames with the dataset's own recipe (every threat at all 5 severity levels,
% a balanced 'none' class, each block at its own random UAV speed in the
% 50-120 km/h envelope, run-aware causal temporal features) at the odd values
% 1,3,5,7,9 dB AND at the training values 0:2:10 dB, and classifies them with the
% production detector. Seen and unseen points come from the same run, so the
% comparison isolates the effect of Eb/N0 values the network never saw.
%
% Output: results/unseen_snr.{txt,mat,png}

close all; clc;
fprintf('=== Detector generalization to unseen Eb/N0 (D34) ===\n\n');

%% 1. Configuration
EBNO_ALL  = 0:1:10;
EBNO_SEEN = 0:2:10;
N_FRAMES  = 20;                 % frames per (threat, level, Eb/N0) block
delay_bits = 20;
temporal_window = 10;           % as extract_spectrograms.m
rng(4242, 'twister');

threat_cfg(1) = struct('name','jamming',             'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(2) = struct('name','noise_burst',         'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(3) = struct('name','reactive_jamming',    'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(4) = struct('name','path_loss',           'param','path_loss_db',  'levels',[4 8 12 16 20]);
threat_cfg(5) = struct('name','spoofing',            'param','spoof_sir_db',  'levels',[-4 -1 2 5 8]);
threat_cfg(6) = struct('name','antenna_fault',       'param','fault_duty',    'levels',[0.1 0.2 0.3 0.4 0.5]);
threat_cfg(7) = struct('name','benign_interference', 'param','benign_int_db', 'levels',[-10 -8 -6 -4 -2]);
threat_cfg(8) = struct('name','sweeping_jammer',     'param','jsr_db',        'levels',[0 4 8 12 16]);
threat_cfg(9) = struct('name','none',                'param','',              'levels',1:5);   % 5 sub-blocks: balanced

D = load('data/trained_detector.mat', 'net', 'classes');
classes = cellstr(string(D.classes(:)'));
N = load_norm();
init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';
fs = p0.symbol_rate * p0.sps;
stop_time = num2str(N_FRAMES * p0.frame_duration);

%% 2. Generate and classify
truth = {}; pred = {}; ebno_of = [];
t0 = tic;
for t = 1:numel(threat_cfg)
    cfg = threat_cfg(t);
    for lv = 1:numel(cfg.levels)
        p = p0; p.active_threat = cfg.name;
        if ~isempty(cfg.param), p.(cfg.param) = cfg.levels(lv); end
        v_kmh = p0.speed_kmh_min + rand() * (p0.speed_kmh_max - p0.speed_kmh_min);
        p.v_kmh = v_kmh; p.v = v_kmh / 3.6; p.fd_max = p.v * p0.carrier_freq / p0.c_light;
        params = p; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:numel(EBNO_ALL)
            ebno = EBNO_ALL(s);
            snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
            out = sim(modelName, 'StopTime', stop_time);
            [iq_f, ber_f, rssi_f, plr_f] = extract_closed_loop_frames(out, p, delay_bits);
            for k = 1:numel(ber_f)
                if isnan(ber_f(k)), continue; end
                w0 = max(1, k - temporal_window + 1);
                if k > 1 && ~isnan(ber_f(k-1)), dber = (ber_f(k) - ber_f(k-1)) / p0.frame_duration; else, dber = 0; end
                raw = [ebno, ber_f(k), rssi_f(k), plr_f(k), var(rssi_f(w0:k), 0), dber, mean(plr_f(w0:k), 'omitnan')];
                truth{end+1} = cfg.name; %#ok<SAGROW>
                pred{end+1} = detect_frame(D.net, D.classes, iq_f{k}, raw, N.mu, N.sd, fs); %#ok<SAGROW>
                ebno_of(end+1) = ebno; %#ok<SAGROW>
            end
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, numel(threat_cfg), cfg.name, toc(t0)/60);
end
params = p0; save('params.mat', 'params');

%% 3. Metrics per Eb/N0
act_of = containers.Map(classes, cellfun(@(c) rule_based_policy(c), classes, 'UniformOutput', false));
acc = nan(1, numel(EBNO_ALL)); f1 = acc; aeq = acc; n = acc;
for s = 1:numel(EBNO_ALL)
    m = ebno_of == EBNO_ALL(s);
    n(s) = sum(m);
    acc(s) = 100 * mean(strcmp(truth(m), pred(m)));
    f1(s)  = 100 * macro_f1(truth(m), pred(m), classes);
    aeq(s) = 100 * mean(cellfun(@(a, b) strcmp(act_of(a), act_of(b)), truth(m), pred(m)));
end
seen = ismember(EBNO_ALL, EBNO_SEEN);
interp_acc = interp1(EBNO_ALL(seen), acc(seen), EBNO_ALL(~seen), 'linear');
gap = acc(~seen) - interp_acc;

recall_unseen = nan(1, numel(classes)); recall_seen = recall_unseen;
for c = 1:numel(classes)
    mu_ = strcmp(truth, classes{c}) & ~ismember(ebno_of, EBNO_SEEN);
    ms_ = strcmp(truth, classes{c}) &  ismember(ebno_of, EBNO_SEEN);
    recall_unseen(c) = 100 * mean(strcmp(pred(mu_), classes{c}));
    recall_seen(c)   = 100 * mean(strcmp(pred(ms_), classes{c}));
end
summary = struct('acc_unseen', 100*mean(strcmp(truth(~ismember(ebno_of, EBNO_SEEN)), pred(~ismember(ebno_of, EBNO_SEEN)))), ...
    'acc_seen', 100*mean(strcmp(truth(ismember(ebno_of, EBNO_SEEN)), pred(ismember(ebno_of, EBNO_SEEN)))), ...
    'max_gap', max(abs(gap)), 'mean_gap', mean(gap));

%% 4. Report
rep = {};
rep{end+1} = '=== DETECTOR GENERALIZATION TO UNSEEN Eb/N0 (proposal mitigation 4; D34) ===';
rep{end+1} = sprintf('Generated: %s | %d frames per block, all threats x 5 levels + balanced none, random speed per block', ...
    datestr(now), N_FRAMES);
rep{end+1} = 'Training grid: 0,2,4,6,8,10 dB. Unseen: 1,3,5,7,9 dB. Same generator and run for both.';
rep{end+1} = '';
rep{end+1} = sprintf('%6s %8s %7s %10s %10s %14s %14s', 'Eb/N0', 'in train', 'frames', 'accuracy', 'macro-F1', 'action-equiv', 'gap to interp');
ku = 0;
for s = 1:numel(EBNO_ALL)
    if seen(s), g = '-'; else, ku = ku + 1; g = sprintf('%+.1f', gap(ku)); end
    rep{end+1} = sprintf('%4g dB %8s %7d %9.1f%% %9.1f%% %13.1f%% %14s', EBNO_ALL(s), yesno(seen(s)), n(s), ...
        acc(s), f1(s), aeq(s), g); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Accuracy: unseen %.1f%% | training grid %.1f%% | largest gap to the interpolated curve %.1f points (mean %+.1f)', ...
    summary.acc_unseen, summary.acc_seen, summary.max_gap, summary.mean_gap);
rep{end+1} = '';
rep{end+1} = '--- Recall per class: training grid vs unseen Eb/N0 ---';
for c = 1:numel(classes)
    rep{end+1} = sprintf('  %-20s %6.1f%% -> %6.1f%%', classes{c}, recall_seen(c), recall_unseen(c)); %#ok<SAGROW>
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/unseen_snr.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/unseen_snr.mat', 'summary', 'EBNO_ALL', 'EBNO_SEEN', 'acc', 'f1', 'aeq', 'n', 'gap', ...
    'recall_seen', 'recall_unseen', 'classes');

fig = figure('Position', [100 100 760 420], 'Color', 'w'); hold on;
plot(EBNO_ALL(seen), acc(seen), '-o', 'LineWidth', 1.6, 'MarkerFaceColor', [0 0.45 0.74], 'DisplayName', 'training Eb/N0');
plot(EBNO_ALL(~seen), acc(~seen), 's', 'MarkerSize', 9, 'LineWidth', 1.6, 'Color', [0.85 0.33 0.10], ...
    'MarkerFaceColor', [0.85 0.33 0.10], 'DisplayName', 'unseen Eb/N0');
grid on; xlabel('E_b/N_0 (dB)'); ylabel('Accuracy (%)'); ylim([min([acc 80]) - 2, 100]);
title('Detector accuracy at training vs unseen E_b/N_0'); legend('Location', 'southeast');
saveas(fig, 'results/unseen_snr.png'); close(fig);
fprintf('\nSaved results/unseen_snr.{txt,mat,png} (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function f = macro_f1(yt, yp, classes)
f1 = nan(1, numel(classes));
for c = 1:numel(classes)
    tp = sum(strcmp(yt, classes{c}) & strcmp(yp, classes{c}));
    fp = sum(~strcmp(yt, classes{c}) & strcmp(yp, classes{c}));
    fn = sum(strcmp(yt, classes{c}) & ~strcmp(yp, classes{c}));
    if tp + fn == 0, continue; end
    f1(c) = 2*tp / max(2*tp + fp + fn, 1);
end
f = mean(f1, 'omitnan');
end

function s = yesno(b)
if b, s = 'yes'; else, s = 'no'; end
end

function N = load_norm()
cache = 'data/gui_norm_stats.mat';
if ~isfile(cache) || (isfile('data/splits.mat') && dir(cache).datenum < dir('data/splits.mat').datenum)
    S = load('data/splits.mat', 'splits');
    feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std; %#ok<NASGU>
    save(cache, 'feat_mean', 'feat_std');
end
L = load(cache, 'feat_mean', 'feat_std');
N = struct('mu', L.feat_mean, 'sd', L.feat_std);
end
