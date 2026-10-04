%% EVAL_UNSEEN_SNR.m — detector generalization to Eb/N0 never seen in training
% Proposal mitigation 4: "test generalization on SNR values not included in
% training". The dataset uses Eb/N0 = 0:3:15 dB; this script generates fresh
% frames with the dataset's own recipe (every threat at every other severity level
% of dataset_levels.m, a balanced 'none' class, each (threat, level) at its own random
% UAV speed over the envelope, run-aware causal temporal features, the dataset's labels:
% threat_active.m) at the midpoints 1.5:3:13.5 dB AND at the training values, and reads
% them as the deployed detector does: the temporal fusion over the last cycles of the
% block (fused_class.m). Seen and unseen points come from the same run, so the
% comparison isolates the effect of Eb/N0 values the network never saw.
% Beyond the trained range, at -3 dB (2.2 km) and 18 dB (0.20 km, link_distance_km.m):
% 36 blocks per class at each point, each at its own speed, the levels cycled over
% dataset_levels.m, for the detector's verdict there (edge_verdict.m, read by
% edge_map.m); the policy is not measured beyond 0-15 dB.
% Block k runs on seed 4,000,000 + k.
%
% Output: results/unseen_snr.{txt,mat,png}

close all; clc;
fprintf('=== Detector generalization to unseen Eb/N0 ===\n\n');

%% 1. Configuration
EBNO_SEEN = p0_grid();
EBNO_ALL  = sort([EBNO_SEEN, EBNO_SEEN(1:end-1) + diff(EBNO_SEEN) / 2]);
EBNO_EDGE = [EBNO_SEEN(1) - 3, EBNO_SEEN(end) + 3];   % beyond the trained range (detector only)
N_FRAMES  = 20;                 % frames per (threat, level, Eb/N0) block
N_EDGE    = 36;                 % blocks per class at each edge point (N_MIN of edge_verdict.m)
SEED0     = 4000000;            % block k: seed SEED0 + k
delay_bits = 20;
temporal_window = 10;           % as extract_spectrograms.m
rng(4242, 'twister');

clear threat_cfg                                  % scripts share the base workspace
DL = dataset_levels();
threat_cfg = DL;
for t = 1:numel(threat_cfg), threat_cfg(t).levels = threat_cfg(t).levels(1:2:end); end
threat_cfg(end+1) = struct('name', 'none', 'param', '', 'levels', 1:numel(threat_cfg(1).levels));   % balanced
DL(end+1) = struct('name', 'none', 'param', '', 'levels', 1);
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    threat_cfg = threat_cfg([1 9 10 end]); for t = 1:numel(threat_cfg), threat_cfg(t).levels = threat_cfg(t).levels(1); end
    DL = DL([1 9 10 end]);
    EBNO_ALL = EBNO_ALL(1:3); N_EDGE = 2;
end

D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
classes = cellstr(string(D.classes(:)'));
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end   % temporal fusion (select_fusion.m)
p0 = load('params.mat').params; p0.quiet_build = true;
G = struct('model', 'UAV_GCS_Threat_Link', 'stop_time', num2str(N_FRAMES * p0.frame_duration), ...
    'delay_bits', delay_bits, 'tw', temporal_window, 'fs', p0.symbol_rate * p0.sps, 'D', D, 'N', load_norm(), ...
    'classes', {classes}, 'FM', FZ.FM, 'FN', FZ.N);
act_of = containers.Map(classes, cellfun(@(c) rule_based_policy(c), classes, 'UniformOutput', false));

%% 2. Generate and classify
truth = {}; pred = {}; ebno_of = [];
blk = struct('cls', {}, 'level', {}, 'ebno', {}, 'seed', {}, 'speed', {}, 'n', {}, 'correct', {}, 'same_action', {});
kb = 0;
t0 = tic;
for t = 1:numel(threat_cfg)
    cfg = threat_cfg(t);
    for lv = 1:numel(cfg.levels)
        p = p0; p.active_threat = cfg.name;
        if ~isempty(cfg.param), p.(cfg.param) = cfg.levels(lv); end
        v_kmh = p0.speed_kmh_min + rand() * (p0.speed_kmh_max - p0.speed_kmh_min);
        evalc('build_threat_model(p)');
        for s = 1:numel(EBNO_ALL)
            kb = kb + 1;
            [tl, pl] = detector_block(G, p, EBNO_ALL(s), SEED0 + kb, v_kmh);
            truth = [truth, tl]; pred = [pred, pl]; ebno_of = [ebno_of, EBNO_ALL(s) * ones(1, numel(tl))]; %#ok<AGROW>
            blk(end+1) = block_row(cfg.name, cfg.levels(lv), EBNO_ALL(s), SEED0 + kb, v_kmh, tl, pl, act_of); %#ok<SAGROW>
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, numel(threat_cfg), cfg.name, toc(t0)/60);
end
% Edge points: N_EDGE blocks per class at each, block b at level mod(b - 1, levels) + 1
for t = 1:numel(DL)
    cfg = DL(t); nL = numel(cfg.levels);
    for lv = 1:nL
        bs = find(mod((1:N_EDGE) - 1, nL) + 1 == lv);
        if isempty(bs), continue; end
        p = p0; p.active_threat = cfg.name;
        if ~isempty(cfg.param), p.(cfg.param) = cfg.levels(lv); end
        evalc('build_threat_model(p)');
        for e = EBNO_EDGE
            for b = bs
                kb = kb + 1;
                v_kmh = p0.speed_kmh_min + rand() * (p0.speed_kmh_max - p0.speed_kmh_min);
                [tl, pl] = detector_block(G, p, e, SEED0 + kb, v_kmh);
                truth = [truth, tl]; pred = [pred, pl]; ebno_of = [ebno_of, e * ones(1, numel(tl))]; %#ok<AGROW>
                blk(end+1) = block_row(cfg.name, cfg.levels(lv), e, SEED0 + kb, v_kmh, tl, pl, act_of); %#ok<SAGROW>
            end
        end
    end
    fprintf('  [%d/%d] %-20s edge points done (%.1f min)\n', t, numel(DL), cfg.name, toc(t0)/60);
end

%% 3. Metrics per Eb/N0
EB = [EBNO_ALL, EBNO_EDGE];
acc = nan(1, numel(EB)); f1 = acc; aeq = acc; n = acc;
for s = 1:numel(EB)
    m = ebno_of == EB(s);
    n(s) = sum(m);
    acc(s) = 100 * mean(strcmp(truth(m), pred(m)));
    f1(s)  = 100 * macro_f1(truth(m), pred(m), classes);
    aeq(s) = 100 * mean(cellfun(@(a, b) strcmp(act_of(a), act_of(b)), truth(m), pred(m)));
end
ie = numel(EBNO_ALL) + (1:numel(EBNO_EDGE));
acc_edge = acc(ie); f1_edge = f1(ie); aeq_edge = aeq(ie); n_edge = n(ie);
acc(ie) = []; f1(ie) = []; aeq(ie) = []; n(ie) = [];
seen = ismember(EBNO_ALL, EBNO_SEEN);
interp_acc = interp1(EBNO_ALL(seen), acc(seen), EBNO_ALL(~seen), 'linear');
gap = acc(~seen) - interp_acc;

mid = ismember(ebno_of, EBNO_ALL(~seen)); ms = ismember(ebno_of, EBNO_SEEN);
recall_unseen = nan(1, numel(classes)); recall_seen = recall_unseen;
for c = 1:numel(classes)
    mu_ = strcmp(truth, classes{c}) & mid;
    ms_ = strcmp(truth, classes{c}) & ms;
    recall_unseen(c) = 100 * mean(strcmp(pred(mu_), classes{c}));
    recall_seen(c)   = 100 * mean(strcmp(pred(ms_), classes{c}));
end
summary = struct('acc_unseen', 100*mean(strcmp(truth(mid), pred(mid))), ...
    'acc_seen', 100*mean(strcmp(truth(ms), pred(ms))), 'max_gap', max(abs(gap)), 'mean_gap', mean(gap));

% Detection at the edge points per class: frames of the class read as a class with its
% countermeasure, over the class's blocks, against 90% (edge_verdict.m)
edge = struct('cls', {}, 'ebno', {}, 'value', {}, 'lo', {}, 'hi', {}, 'n', {}, 'verdict', {});
for c = 1:numel(DL)
    for e = EBNO_EDGE
        b = blk(strcmp({blk.cls}, DL(c).name) & [blk.ebno] == e);
        V = edge_verdict([b.same_action], [b.n], 1:numel(b), 0.9, 'ge', false);
        edge(end+1) = struct('cls', DL(c).name, 'ebno', e, 'value', V.value, 'lo', V.lo, 'hi', V.hi, 'n', V.n, ...
            'verdict', V.verdict); %#ok<SAGROW>
    end
end

%% 4. Report
rep = {};
rep{end+1} = '=== DETECTOR GENERALIZATION TO UNSEEN Eb/N0 (proposal mitigation 4) ===';
rep{end+1} = sprintf(['Generated: %s | %d frames per block, all threats x every other level + balanced none, random speed ' ...
    'per (threat, level) | %s'], datestr(now), N_FRAMES, ...
    ternary(isempty(FZ.FM), 'per-frame reading', sprintf('fused over the last %d cycles (deployed detector)', FZ.N)));
rep{end+1} = sprintf('Training grid: %s dB. Unseen: %s dB. Same generator and run for both.', mat2str(EBNO_SEEN), mat2str(setdiff(EBNO_ALL, EBNO_SEEN)));
rep{end+1} = '';
rep{end+1} = sprintf('%6s %8s %7s %10s %10s %14s %14s', 'Eb/N0', 'in train', 'frames', 'accuracy', 'macro-F1', 'action-equiv', 'gap to interp');
ku = 0;
for s = 1:numel(EBNO_ALL)
    if seen(s), g = '-'; else, ku = ku + 1; g = sprintf('%+.1f', gap(ku)); end
    rep{end+1} = sprintf('%4g dB %8s %7d %9.1f%% %9.1f%% %13.1f%% %14s', EBNO_ALL(s), yesno(seen(s)), n(s), ...
        acc(s), f1(s), aeq(s), g); %#ok<SAGROW>
end
for s = 1:numel(EBNO_EDGE)
    rep{end+1} = sprintf('%4g dB %8s %7d %9.1f%% %9.1f%% %13.1f%% %14s', EBNO_EDGE(s), 'beyond', n_edge(s), ...
        acc_edge(s), f1_edge(s), aeq_edge(s), '-'); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Accuracy: unseen %.1f%% | training grid %.1f%% | largest gap to the interpolated curve %.1f points (mean %+.1f)', ...
    summary.acc_unseen, summary.acc_seen, summary.max_gap, summary.mean_gap);
rep{end+1} = '';
rep{end+1} = '--- Recall per class: training grid vs unseen Eb/N0 ---';
for c = 1:numel(classes)
    rep{end+1} = sprintf('  %-20s %6.1f%% -> %6.1f%%', classes{c}, recall_seen(c), recall_unseen(c)); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf(['--- Beyond the trained range (%d blocks per class and point, levels cycled): frames read as a ' ...
    'class with the same countermeasure [95%% interval], blocks, verdict against 90%% (edge_verdict.m) ---'], N_EDGE);
for c = 1:numel(DL)
    x = edge(strcmp({edge.cls}, DL(c).name));
    rep{end+1} = sprintf('  %-20s %s', DL(c).name, strjoin(arrayfun(@(q) sprintf('%g dB %5.1f%% [%5.1f, %5.1f] %2d %s', ...
        q.ebno, 100 * q.value, 100 * q.lo, 100 * q.hi, q.n, verdict_txt(q.verdict)), x, 'UniformOutput', false), ' | ')); %#ok<SAGROW>
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/unseen_snr.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/unseen_snr.mat', 'summary', 'EBNO_ALL', 'EBNO_SEEN', 'EBNO_EDGE', 'acc', 'f1', 'aeq', 'n', 'gap', ...
    'acc_edge', 'f1_edge', 'aeq_edge', 'n_edge', 'recall_seen', 'recall_unseen', 'classes', 'blk', 'edge');

fig = figure('Position', [100 100 760 420], 'Color', 'w'); hold on;
plot(EBNO_ALL(seen), acc(seen), '-o', 'LineWidth', 1.6, 'MarkerFaceColor', [0 0.45 0.74], 'DisplayName', 'training Eb/N0');
plot(EBNO_ALL(~seen), acc(~seen), 's', 'MarkerSize', 9, 'LineWidth', 1.6, 'Color', [0.85 0.33 0.10], ...
    'MarkerFaceColor', [0.85 0.33 0.10], 'DisplayName', 'unseen Eb/N0');
plot(EBNO_EDGE, acc_edge, 'd', 'MarkerSize', 9, 'LineWidth', 1.6, 'Color', [0.47 0.67 0.19], ...
    'MarkerFaceColor', [0.47 0.67 0.19], 'DisplayName', 'beyond the trained range');
grid on; xlabel('E_b/N_0 (dB)'); ylabel('Accuracy (%)'); ylim([min([acc acc_edge 80]) - 2, 100]);
title('Detector accuracy at training vs unseen E_b/N_0'); legend('Location', 'southeast');
saveas(fig, 'results/unseen_snr.png'); close(fig);
fprintf('\nSaved results/unseen_snr.{txt,mat,png} (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function r = block_row(cls, level, ebno, seed, v_kmh, tl, pl, act_of)
% One block: frames of its class (the dataset's labels), correct and with the same
% countermeasure among them.
on = strcmp(tl, cls);
r = struct('cls', cls, 'level', level, 'ebno', ebno, 'seed', seed, 'speed', v_kmh, 'n', sum(on), ...
    'correct', sum(strcmp(pl(on), cls)), ...
    'same_action', sum(cellfun(@(c) strcmp(act_of(c), act_of(cls)), pl(on))));
end

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

function s = verdict_txt(v)
s = {'NOT COMMITTED', 'UNDETERMINED', 'COMMITTED'}; s = s{v + 2};
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
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

function g = p0_grid()
S = load('params.mat');
g = S.params.EbNo_dB;
end
