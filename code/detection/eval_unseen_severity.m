%% EVAL_UNSEEN_SEVERITY - detector at threat severities never seen in training
% The dataset trains every threat on 8 severity levels (dataset_levels.m). This script generates
% fresh frames with the dataset's recipe (random UAV speed per block, every
% training Eb/N0, the dataset's labels: threat_active.m) at three kinds of level and
% reads them as the deployed detector does, fused over the last cycles of the block
% (detector_block.m):
%   seen     every other training level (reference from the same generator)
%   between  midpoints between training levels (never trained on), every other one
%   above    beyond the strongest training level, where the sources allow it; every
%            threat is trained up to the sources' most severe value, so none is tested above
% Per frame of the threat: correct class, a class that calls for the same countermeasure
% (rule_based_policy.m), or flagged unknown (production score below the threshold
% keeping 95% of known validation frames). One block per Eb/N0 gives fewer flights than
% a verdict needs (edge_verdict.m): generalization evidence at the midpoints, read by
% edge_map.m. Block k runs on seed 5,000,000 + k.
% Decision rule, fixed before the run: the training levels are extended to the
% map's levels when, above the range, fewer than 90% of a threat's frames are
% read as a class with the same countermeasure.
%
% Output: results/unseen_severity.{txt,mat}

close all; clc;
fprintf('=== Detector at unseen threat severities ===\n\n');

%% 1. Levels
EBNO = load('params.mat').params.EbNo_dB;
N_FRAMES = 20;                   % frames per (threat, level, Eb/N0) block
SEED0 = 5000000;                 % block k: seed SEED0 + k
delay_bits = 20; temporal_window = 10;
rng(4343, 'twister');
clear threat_cfg
% Above the training range only where the sources go further than the training levels
ABOVE = struct('jamming', [], 'noise_burst', [], 'reactive_jamming', [], 'sweeping_jammer', [], ...
    'tone_jamming', [], 'path_loss', [], 'spoofing', [], 'antenna_fault', [], ...
    'benign_interference', [], 'airframe_shadowing', []);
DL = dataset_levels();
threat_cfg = struct('name', {}, 'param', {}, 'lv', {});
for t = 1:numel(DL)
    L = DL(t).levels;
    mids = (L(1:end-1) + L(2:end)) / 2;
    threat_cfg(t) = struct('name', DL(t).name, 'param', DL(t).param, 'lv', ...
        struct('seen', L(1:2:end), 'between', mids(1:2:end), 'above', ABOVE.(DL(t).name)));
end
KINDS = {'seen', 'between', 'above'};
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    threat_cfg = threat_cfg([1 6]); EBNO = EBNO(3);
    for t = 1:2, a = threat_cfg(t).lv.above; threat_cfg(t).lv = struct('seen', threat_cfg(t).lv.seen(1), ...
            'between', threat_cfg(t).lv.between(1), 'above', a(1:min(1, end))); end
end

D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
classes = cellstr(string(D.classes(:)'));
Tood = ood_thresholds(0.95);
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end   % temporal fusion (select_fusion.m)
p0 = load('params.mat').params; p0.quiet_build = true;
G = struct('model', 'UAV_GCS_Threat_Link', 'stop_time', num2str(N_FRAMES * p0.frame_duration), ...
    'delay_bits', delay_bits, 'tw', temporal_window, 'fs', p0.symbol_rate * p0.sps, 'D', D, 'N', load_norm(), ...
    'classes', {classes}, 'FM', FZ.FM, 'FN', FZ.N);
act_of = containers.Map(classes, cellfun(@(c) rule_based_policy(c), classes, 'UniformOutput', false));

%% 2. Generate and classify
R = struct('threat', {}, 'kind', {}, 'level', {}, 'ebno', {}, 'seed', {}, 'speed', {}, 'n', {}, 'correct', {}, ...
    'same_action', {}, 'unknown', {});
kb = 0;
t0 = tic;
for t = 1:numel(threat_cfg)
    cfg = threat_cfg(t);
    for kk = 1:numel(KINDS)
        for lv = cfg.lv.(KINDS{kk})
            p = p0; p.active_threat = cfg.name; p.(cfg.param) = lv;
            evalc('build_threat_model(p)');
            for ebno = EBNO
                kb = kb + 1;
                v_kmh = p0.speed_kmh_min + rand() * (p0.speed_kmh_max - p0.speed_kmh_min);
                [tl, pred, sc] = detector_block(G, p, ebno, SEED0 + kb, v_kmh);
                on = strcmp(tl, cfg.name);                  % frames of the threat (the dataset's labels)
                R(end+1) = struct('threat', cfg.name, 'kind', KINDS{kk}, 'level', lv, 'ebno', ebno, 'seed', SEED0 + kb, ...
                    'speed', v_kmh, 'n', sum(on), 'correct', sum(strcmp(pred(on), cfg.name)), ...
                    'same_action', sum(cellfun(@(c) strcmp(act_of(c), act_of(cfg.name)), pred(on))), ...
                    'unknown', sum(sc(on) < Tood.maha)); %#ok<SAGROW>
            end
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, numel(threat_cfg), cfg.name, toc(t0)/60);
end

%% 3. Report: per threat and level, pooled over Eb/N0
rep = {'=== DETECTOR AT UNSEEN THREAT SEVERITIES ==='};
rep{end+1} = sprintf(['Generated: %s | %d frames per (level, Eb/N0) block, Eb/N0 %s dB, random speed per block | %s | ' ...
    'unknown = production score (%s) below the 95%%-retention threshold'], datestr(now), N_FRAMES, mat2str(EBNO), ...
    ternary(isempty(FZ.FM), 'per-frame reading', sprintf('fused over the last %d cycles', FZ.N)), D.ood.score);
rep{end+1} = 'Rule fixed before the run: extend the training levels if, above the range, < 90% of a threat''s frames get the same countermeasure.';
rep{end+1} = '';
rep{end+1} = sprintf('%-20s %-8s %7s %7s %9s %13s %9s', 'threat', 'kind', 'level', 'frames', 'correct', 'same action', 'unknown');
extend = {};
for t = 1:numel(threat_cfg)
    nm = threat_cfg(t).name;
    for kk = 1:numel(KINDS)
        for lv = threat_cfg(t).lv.(KINDS{kk})
            m = strcmp({R.threat}, nm) & strcmp({R.kind}, KINDS{kk}) & [R.level] == lv;
            n = sum([R(m).n]);
            sa = sum([R(m).same_action]) / n;
            rep{end+1} = sprintf('%-20s %-8s %7g %7d %8.1f%% %12.1f%% %8.1f%%', nm, KINDS{kk}, lv, n, ...
                100 * sum([R(m).correct]) / n, 100 * sa, 100 * sum([R(m).unknown]) / n); %#ok<SAGROW>
            if strcmp(KINDS{kk}, 'above') && sa < 0.9, extend{end+1} = sprintf('%s at %g', nm, lv); end %#ok<SAGROW>
        end
    end
end
rep{end+1} = '';
for kk = 1:numel(KINDS)
    m = strcmp({R.kind}, KINDS{kk}); n = sum([R(m).n]);
    rep{end+1} = sprintf('pooled %-8s correct %.1f%% | same action %.1f%% | unknown %.1f%% (%d frames)', KINDS{kk}, ...
        100 * sum([R(m).correct]) / n, 100 * sum([R(m).same_action]) / n, 100 * sum([R(m).unknown]) / n, n); %#ok<SAGROW>
end
if isempty(extend)
    rep{end+1} = 'Decision: every level above the range keeps >= 90% same countermeasure; the training levels stay.';
else
    rep{end+1} = sprintf('Decision: below 90%% above the range for %s: extend the training levels.', strjoin(extend, ', '));
end
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/unseen_severity.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/unseen_severity.mat', 'R', 'threat_cfg', 'EBNO', 'extend');
fprintf('\nSaved results/unseen_severity.{txt,mat} (%.1f min)\n', toc(t0)/60);

%% ===== Local functions =====
function N = load_norm()
% Feature normalization of the detector's training split (cached as in eval_unseen_snr.m).
cache = 'data/gui_norm_stats.mat';
if ~isfile(cache) || (isfile('data/splits.mat') && dir(cache).datenum < dir('data/splits.mat').datenum)
    S = load('data/splits.mat', 'splits');
    feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std;
    save(cache, 'feat_mean', 'feat_std');
end
L = load(cache, 'feat_mean', 'feat_std');
N = struct('mu', L.feat_mean, 'sd', L.feat_std);
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
