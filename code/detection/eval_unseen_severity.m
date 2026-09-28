%% EVAL_UNSEEN_SEVERITY - detector at threat severities never seen in training
% The dataset trains every threat on 5 severity levels. This script generates
% fresh frames with the dataset's recipe (random UAV speed per block, every
% training Eb/N0) at three kinds of level and classifies them with the
% production detector:
%   seen     the training levels (reference from the same generator)
%   between  midpoints of the training levels
%   above    beyond the strongest training level, up to the survivability map
%            (in-band threats 22 and 28 dB JSR, path loss 26 dB)
% Per frame: correct class, a class that calls for the same countermeasure
% (rule_based_policy.m), or flagged unknown (production score below the threshold
% keeping 95% of known validation frames).
% Decision rule, fixed before the run: the training levels are extended to the
% map's levels when, above the range, fewer than 90% of a threat's frames are
% read as a class with the same countermeasure.
%
% Output: results/unseen_severity.{txt,mat}

close all; clc;
fprintf('=== Detector at unseen threat severities ===\n\n');

%% 1. Levels
EBNO = 0:2:10;
N_FRAMES = 20;                   % frames per (threat, level, Eb/N0) block
delay_bits = 20; temporal_window = 10;
rng(4343, 'twister');
clear threat_cfg
jsr = struct('seen', [0 4 8 12 16], 'between', [2 6 10 14], 'above', [22 28]);
threat_cfg(1) = struct('name', 'jamming',             'param', 'jsr_db',        'lv', jsr);
threat_cfg(2) = struct('name', 'noise_burst',         'param', 'jsr_db',        'lv', jsr);
threat_cfg(3) = struct('name', 'reactive_jamming',    'param', 'jsr_db',        'lv', jsr);
threat_cfg(4) = struct('name', 'sweeping_jammer',     'param', 'jsr_db',        'lv', jsr);
threat_cfg(5) = struct('name', 'path_loss',           'param', 'path_loss_db',  'lv', ...
    struct('seen', [4 8 12 16 20], 'between', [6 10 14 18], 'above', 26));
threat_cfg(6) = struct('name', 'spoofing',            'param', 'spoof_sir_db',  'lv', ...
    struct('seen', [-4 -1 2 5 8], 'between', [-2.5 0.5 3.5 6.5], 'above', []));
threat_cfg(7) = struct('name', 'antenna_fault',       'param', 'fault_duty',    'lv', ...
    struct('seen', [0.1 0.2 0.3 0.4 0.5], 'between', [0.15 0.25 0.35 0.45], 'above', []));
threat_cfg(8) = struct('name', 'benign_interference', 'param', 'benign_int_db', 'lv', ...
    struct('seen', [-10 -8 -6 -4 -2], 'between', [-9 -7 -5 -3], 'above', []));
KINDS = {'seen', 'between', 'above'};

D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
classes = cellstr(string(D.classes(:)'));
Tood = ood_thresholds(0.95);
N = load_norm();
p0 = load('params.mat').params; p0.quiet_build = true;
modelName = 'UAV_GCS_Threat_Link';
fs = p0.symbol_rate * p0.sps;
stop_time = num2str(N_FRAMES * p0.frame_duration);
act_of = containers.Map(classes, cellfun(@(c) rule_based_policy(c), classes, 'UniformOutput', false));

%% 2. Generate and classify
R = struct('threat', {}, 'kind', {}, 'level', {}, 'ebno', {}, 'n', {}, 'correct', {}, 'same_action', {}, 'unknown', {});
t0 = tic;
for t = 1:numel(threat_cfg)
    cfg = threat_cfg(t);
    for kk = 1:numel(KINDS)
        for lv = cfg.lv.(KINDS{kk})
            p = p0; p.active_threat = cfg.name; p.(cfg.param) = lv;
            evalc('build_threat_model(p)');
            for ebno = EBNO
                v_kmh = p0.speed_kmh_min + rand() * (p0.speed_kmh_max - p0.speed_kmh_min);
                snr_dB = ebno + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
                set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB), 'SignalPower', num2str(1/p.sps));
                link_seed(modelName, randi(2^31 - 1000), v_kmh / 3.6 * p0.carrier_freq / p0.c_light);
                F = extract_closed_loop_frames(sim(modelName, 'StopTime', stop_time), p, delay_bits);
                disk_guard;
                v = find(~isnan(F.ber));
                X = zeros(128, 128, 1, numel(v), 'single'); Fr = zeros(numel(v), numel(N.mu));
                for i = 1:numel(v)
                    X(:, :, 1, i) = spec_image(F.iq{v(i)}, fs);
                    Fr(i, :) = link_features(F, v(i), temporal_window);
                end
                [pr, sc] = detect_scores(D.net, D.ood, X, ((Fr - N.mu) ./ N.sd)');
                [~, k] = max(pr, [], 1); pred = classes(k);
                R(end+1) = struct('threat', cfg.name, 'kind', KINDS{kk}, 'level', lv, 'ebno', ebno, 'n', numel(v), ...
                    'correct', sum(strcmp(pred, cfg.name)), ...
                    'same_action', sum(cellfun(@(c) strcmp(act_of(c), act_of(cfg.name)), pred)), ...
                    'unknown', sum(sc(:)' < Tood.maha)); %#ok<SAGROW>
            end
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, numel(threat_cfg), cfg.name, toc(t0)/60);
end

%% 3. Report: per threat and level, pooled over Eb/N0
rep = {'=== DETECTOR AT UNSEEN THREAT SEVERITIES ==='};
rep{end+1} = sprintf(['Generated: %s | %d frames per (level, Eb/N0) block, Eb/N0 %s dB, random speed per block | ' ...
    'unknown = production score (%s) below the 95%%-retention threshold'], datestr(now), N_FRAMES, mat2str(EBNO), D.ood.score);
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
    feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std; %#ok<NASGU>
    save(cache, 'feat_mean', 'feat_std');
end
L = load(cache, 'feat_mean', 'feat_std');
N = struct('mu', L.feat_mean, 'sd', L.feat_std);
end
