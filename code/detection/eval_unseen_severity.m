%% EVAL_UNSEEN_SEVERITY - detector at threat severities never seen in training
% The dataset trains every threat on 8 severity levels (dataset_levels.m). This script generates
% fresh frames with the dataset's recipe (random UAV speed per block, every
% training Eb/N0, the dataset's labels: threat_active.m) at three kinds of level and
% reads them as the deployed detector does, fused over the last cycles of the block
% (detector_block.m):
%   seen     every other training level (reference from the same generator)
%   between  midpoints between training levels (never trained on), every other one
%   above    beyond the strongest training level, where the sources allow it: every
%            threat is trained up to the sources' most severe value, but the antenna
%            fault, trained up to 31 dB, is tested at 36 dB (an open contact of
%            0.01 pF, the gap-capacitance estimate)
% Per frame of the threat: correct class, a class that calls for the same countermeasure
% (rule_based_policy.m), or flagged unknown: the statistic of the decision cycle, the
% production score averaged over the last ood.win cycles of the block (ood_window.m,
% partial windows at its start), below its threshold (ood_thresholds.m, 95% of the known
% validation frames kept on the same statistic). One block per Eb/N0 gives fewer flights than
% a verdict needs (edge_verdict.m): generalization evidence at the midpoints, read by
% edge_map.m. Block k runs on seed 5,500,000 + k. An airframe-shadowing block flies, in its
% place, the next candidate 5,550,000 + j whose attitude hides an antenna at its level
% (hiding_flight.m, as the dataset selects its flights; each candidate tried once), at the
% candidate's own speed over the envelope: its frames are conditioned on such a flight, the
% share of the candidates that hide one reported beside.
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
SEED0 = 5500000;                 % block k: seed SEED0 + k
SEED_SHD = SEED0 + 50000;        % airframe shadowing: candidate j, seed SEED_SHD + j (j < 50 000, inside the block range)
delay_bits = 20; temporal_window = 10;
rng(4345, 'twister');
clear threat_cfg
% Above the training range only where the sources go further than the training levels
ABOVE = struct('jamming', [], 'noise_burst', [], 'reactive_jamming', [], 'sweeping_jammer', [], ...
    'tone_jamming', [], 'path_loss', [], 'spoofing', [], 'antenna_fault', 36, ...
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
    threat_cfg = threat_cfg([1 6 10]); EBNO = EBNO(3);
    for t = 1:3, a = threat_cfg(t).lv.above; threat_cfg(t).lv = struct('seen', threat_cfg(t).lv.seen(1), ...
            'between', threat_cfg(t).lv.between(1), 'above', a(1:min(1, end))); end
end

D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
classes = cellstr(string(D.classes(:)'));
Tood = ood_thresholds(0.95);
UW = 1; if isfield(D.ood, 'win') && ~isempty(D.ood.win), UW = D.ood.win; end   % unknown-score window
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end   % temporal fusion (select_fusion.m)
p0 = load('params.mat').params; p0.quiet_build = true;
p0.pl_onset_frames = p0.pl_onset_det;              % the dataset's recipe: a path-loss step inside the block
p0.cap_frames = N_FRAMES;                          % the block's frames (the cap's, and those a shadowing flight hides an antenna in)
G = struct('model', 'UAV_GCS_Threat_Link', 'stop_time', num2str(N_FRAMES * p0.frame_duration), ...
    'delay_bits', delay_bits, 'tw', temporal_window, 'fs', p0.symbol_rate * p0.sps, 'D', D, 'N', load_norm(), ...
    'classes', {classes}, 'FM', FZ.FM, 'FN', FZ.N);
act_of = containers.Map(classes, cellfun(@(c) rule_based_policy(c), classes, 'UniformOutput', false));

%% 2. Generate and classify
R = struct('threat', {}, 'kind', {}, 'level', {}, 'ebno', {}, 'seed', {}, 'speed', {}, 'n', {}, 'correct', {}, ...
    'same_action', {}, 'unknown', {});
kb = 0;
jsh = 0; SHT = [0 0];                             % airframe shadowing: last candidate; blocks, candidates tried
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
                sd = SEED0 + kb;
                if strcmp(cfg.name, 'airframe_shadowing')
                    [sd, v_kmh, jsh, nt] = hiding_flight(p, ebno, SEED_SHD, jsh, 49999); SHT = SHT + [1 nt];
                end
                [tl, pred, sc] = detector_block(G, p, ebno, sd, v_kmh);
                sw = ood_window(sc, ones(size(sc)), [], UW)';   % the block's frames in time order
                on = strcmp(tl, cfg.name);                  % frames of the threat (the dataset's labels)
                R(end+1) = struct('threat', cfg.name, 'kind', KINDS{kk}, 'level', lv, 'ebno', ebno, 'seed', sd, ...
                    'speed', v_kmh, 'n', sum(on), 'correct', sum(strcmp(pred(on), cfg.name)), ...
                    'same_action', sum(cellfun(@(c) strcmp(act_of(c), act_of(cfg.name)), pred(on))), ...
                    'unknown', sum(sw(on) < Tood.maha)); %#ok<SAGROW>
            end
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, numel(threat_cfg), cfg.name, toc(t0)/60);
end

%% 3. Report: per threat and level, pooled over Eb/N0
rep = {'=== DETECTOR AT UNSEEN THREAT SEVERITIES ==='};
rep{end+1} = sprintf(['Generated: %s | %d frames per (level, Eb/N0) block, Eb/N0 %s dB, random speed per block | %s | ' ...
    'unknown = production score (%s) averaged over the last %d cycles below the 95%%-retention threshold of the same ' ...
    'statistic'], datestr(now), N_FRAMES, mat2str(EBNO), ...
    ternary(isempty(FZ.FM), 'per-frame reading', sprintf('fused over the last %d cycles', FZ.N)), D.ood.score, UW);
rep{end+1} = 'Rule fixed before the run: extend the training levels if, above the range, < 90% of a threat''s frames get the same countermeasure.';
if SHT(1) > 0
    rep{end+1} = sprintf(['Airframe shadowing: every block flies a flight whose attitude hides an antenna at its level (its ' ...
        'readings conditioned on one, at the flight''s own speed); %d blocks kept of %d candidates (%.1f%% hide one).'], ...
        SHT(1), SHT(2), 100 * SHT(1) / SHT(2));
end
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
save('results/unseen_severity.mat', 'R', 'threat_cfg', 'EBNO', 'extend', 'SHT');
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
