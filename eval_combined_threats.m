%% EVAL_COMBINED_THREATS.m — combined (multi) threats and the unknown-threat path (D32)
% Proposal risk 13: a new or combined threat that is not in the training data
% must not lead to a wrong decision or a frozen decision layer; the decision layer
% should respond to link degradation with a generic defense (mitigation 13).
%
% Four combined threats, none of them in the dataset, each component at its
% nominal severity, simulated through the real link at Eb/N0 = 0 / 4 / 10 dB:
%   jamming+path_loss, noise_burst+antenna_fault, sweeping_jammer+path_loss,
%   spoofing+noise_burst
% plus the clean link as a control. For every frame of the unmitigated link:
%   - the production detector's class, maximum softmax probability and energy,
%     and whether it falls below the unknown-threat threshold (ood_thresholds.m);
%   - the decision of four policies: DQN and rule-based, each with the detected
%     class as is, or with unknown gating (below threshold AND the link degraded
%     beyond 2x clean -> class 'unknown': DQN with an all-zero one-hot, rule
%     reacting to link degradation only; D33).
% Every action is also simulated on every combined threat, so each decision is
% scored by the link it actually produces (BER / clean).
%
% Output: results/combined_threats.{txt,mat}

close all; clc;
fprintf('=== Combined threats and the unknown-threat path (D32) ===\n\n');

%% 1. Configuration, models, parameters
COMBOS = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst'};
EBNO_LIST = [0 4 10];
N_RUNS = 2;
RATIO_OK = 2;
temporal_window = 10; delay_bits = 20;

D = load('data/trained_detector.mat', 'net', 'classes');
Q = load('data/trained_dqn.mat', 'agent');
agent = Q.agent; actions = agent.action_names; nA = numel(actions);
[feat_mean, feat_std] = load_norm_stats();
T = ood_thresholds(0.95);
fprintf('Unknown-threat threshold (95%% of known validation frames kept): MSP %.3f | energy %.2f\n\n', T.msp, T.energy);

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';
fs = p0.symbol_rate * p0.sps;
links = [COMBOS, {'none'}];
nL = numel(links); nS = numel(EBNO_LIST);
modes = {'DQN (class)', 'DQN (unknown gating)', 'Rule (class)', 'Rule (unknown gating)'};

%% 2. Simulate every link x action x Eb/N0; keep the unmitigated frames for detection
ber_tab = nan(nL, nA, nS);
F = cell(nL, nS);                         % unmitigated runs: per-run frame sequences
t0 = tic;
for l = 1:nL
    p = p0; p.active_threat = links{l};
    for a = 1:nA
        [p2, g_db] = apply_countermeasure(p, links{l}, actions{a});
        params = p2; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:nS
            snr_dB = EBNO_LIST(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
            b_all = [];
            runs = {};
            for r = 1:N_RUNS
                out = sim(modelName);
                [iq_f, ber_f, rssi_f, plr_f] = extract_closed_loop_frames(out, p2, delay_bits);
                b_all = [b_all; ber_f(:)]; %#ok<AGROW>
                if strcmp(actions{a}, 'no_action')
                    runs{end+1} = struct('iq', {iq_f}, 'ber', ber_f(:)', 'rssi', rssi_f(:)', 'plr', plr_f(:)'); %#ok<SAGROW>
                end
            end
            ber_tab(l, a, s) = mean(b_all, 'omitnan');
            if strcmp(actions{a}, 'no_action'), F{l, s} = runs; end
        end
    end
    fprintf('  [%d/%d] %-28s simulated (%.1f min)\n', l, nL, links{l}, toc(t0)/60);
end
params = p0; save('params.mat', 'params');
na = find(strcmp(actions, 'no_action'), 1);
clean = squeeze(ber_tab(strcmp(links, 'none'), na, :))';
ratio = ber_tab ./ reshape(clean, 1, 1, nS);

%% 3. Detection and the four decision modes on every unmitigated frame
Dec = struct('link', {}, 'ebno', {}, 'cls', {}, 'msp', {}, 'energy', {}, 'unknown', {}, 'act', {}, 'ratio', {});
for l = 1:nL
    for s = 1:nS
        ebno = EBNO_LIST(s);
        for r = 1:numel(F{l, s})
            R = F{l, s}{r};
            nf = numel(R.ber);
            for k = 1:nf
                if isnan(R.ber(k)), continue; end
                w0 = max(1, k - temporal_window + 1);
                var_rssi = var(R.rssi(w0:k), 0);
                burst = mean(R.plr(w0:k), 'omitnan');
                if k > 1 && ~isnan(R.ber(k-1)), dber = (R.ber(k) - R.ber(k-1)) / p0.frame_duration; else, dber = 0; end
                raw = [ebno, R.ber(k), R.rssi(k), R.plr(k), var_rssi, dber, burst];
                [cls, ~, ~, msp, en] = detect_frame(D.net, D.classes, R.iq{k}, raw, feat_mean, feat_std, fs);
                unk = msp < T.msp;
                % Unknown gating (D33): low confidence AND a degraded link (BER > 2x clean)
                cls_g = cls; if unk && R.ber(k) > RATIO_OK * clean(s), cls_g = 'unknown'; end
                acts = {dqn_act(agent, cls, R.ber(k), R.rssi(k), ebno, R.plr(k)), ...
                        dqn_act(agent, cls_g, R.ber(k), R.rssi(k), ebno, R.plr(k)), ...
                        rule_based_policy(cls, R.ber(k), ebno), ...
                        rule_based_policy(cls_g, R.ber(k), ebno)};
                rt = cellfun(@(x) ratio(l, strcmp(actions, x), s), acts);
                Dec(end+1) = struct('link', links{l}, 'ebno', ebno, 'cls', cls, 'msp', msp, 'energy', en, ...
                    'unknown', unk, 'act', {acts}, 'ratio', rt); %#ok<SAGROW>
            end
        end
    end
end

%% 4. Report
rep = {};
rep{end+1} = '=== COMBINED THREATS AND THE UNKNOWN-THREAT PATH (proposal risk 13; D32) ===';
rep{end+1} = sprintf('Generated: %s | %d runs per cell | components at nominal severity | thresholds MSP %.3f, energy %.2f', ...
    datestr(now), N_RUNS, T.msp, T.energy);
rep{end+1} = sprintf('Link state = BER / clean (<= %g restored). Decisions scored with the simulated BER of the chosen action.', RATIO_OK);
rep{end+1} = '';

rep{end+1} = '--- 1. Detection: what the detector calls each combined threat ---';
rep{end+1} = sprintf('%-28s %6s %6s  %-44s %9s %11s %11s', 'link', 'Eb/N0', 'frames', 'classes (share)', 'mean MSP', 'unknown MSP', 'unknown En');
for l = 1:nL
    for s = 1:nS
        m = strcmp({Dec.link}, links{l}) & [Dec.ebno] == EBNO_LIST(s);
        rep{end+1} = sprintf('%-28s %4g dB %6d  %-44s %9.2f %10.0f%% %10.0f%%', links{l}, EBNO_LIST(s), sum(m), ...
            top_classes({Dec(m).cls}, 3), mean([Dec(m).msp]), 100*mean([Dec(m).unknown]), ...
            100*mean([Dec(m).energy] < T.energy)); %#ok<SAGROW>
    end
end
rep{end+1} = '';

rep{end+1} = '--- 2. What each action achieves (BER / clean; * = best) ---';
hdr = sprintf('%-28s %6s', 'link', 'Eb/N0');
for a = 1:nA, hdr = [hdr sprintf('%19s', actions{a})]; end %#ok<AGROW>
rep{end+1} = hdr;
for l = 1:nL
    if strcmp(links{l}, 'none'), continue; end
    for s = 1:nS
        [~, best] = min(ratio(l, :, s));
        line = sprintf('%-28s %4g dB', links{l}, EBNO_LIST(s));
        for a = 1:nA
            tag = ''; if a == best, tag = '*'; end
            line = [line sprintf('%19s', sprintf('%.2fx%s', ratio(l, a, s), tag))]; %#ok<AGROW>
        end
        rep{end+1} = line; %#ok<SAGROW>
    end
end
rep{end+1} = '';

rep{end+1} = '--- 3. Decisions on the combined threats: most frequent action (share) and resulting link ---';
rep{end+1} = sprintf('%-28s %6s | %-34s | %-34s | %-34s | %-34s', 'link', 'Eb/N0', modes{:});
for l = 1:nL
    if strcmp(links{l}, 'none'), continue; end
    for s = 1:nS
        m = strcmp({Dec.link}, links{l}) & [Dec.ebno] == EBNO_LIST(s);
        line = sprintf('%-28s %4g dB', links{l}, EBNO_LIST(s));
        for md = 1:numel(modes)
            A = cellfun(@(c) c{md}, {Dec(m).act}, 'UniformOutput', false);
            rt = arrayfun(@(d) d.ratio(md), Dec(m));
            line = [line sprintf(' | %-34s', sprintf('%s -> %.2fx', top_classes(A, 1), median(rt)))]; %#ok<AGROW>
        end
        rep{end+1} = line; %#ok<SAGROW>
    end
end
rep{end+1} = '';

rep{end+1} = '--- 4. Summary over all combined-threat frames ---';
rep{end+1} = sprintf('%-24s %18s %16s %20s', 'policy', 'link restored', 'median BER/clean', 'no_action on attack');
mc = ~strcmp({Dec.link}, 'none');
rt_best = arrayfun(@(d) min(ratio(strcmp(links, d.link), :, EBNO_LIST == d.ebno)), Dec(mc));
for md = 1:numel(modes)
    rt = arrayfun(@(d) d.ratio(md), Dec(mc));
    noact = cellfun(@(c) strcmp(c{md}, 'no_action'), {Dec(mc).act});
    rep{end+1} = sprintf('%-24s %11d/%-5d %16.2f %15d/%-5d', modes{md}, sum(rt <= RATIO_OK), numel(rt), ...
        median(rt), sum(noact), numel(rt)); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-24s %11d/%-5d %16.2f', 'best single action', sum(rt_best <= RATIO_OK), numel(rt_best), median(rt_best));
rep{end+1} = '';

rep{end+1} = '--- 5. Control: clean link (false unknowns and false actions) ---';
mn = strcmp({Dec.link}, 'none');
rep{end+1} = sprintf('Clean frames: %d | flagged unknown: %.1f%% (MSP), %.1f%% (energy)', sum(mn), ...
    100*mean([Dec(mn).unknown]), 100*mean([Dec(mn).energy] < T.energy));
for md = 1:numel(modes)
    acted = cellfun(@(c) ~strcmp(c{md}, 'no_action'), {Dec(mn).act});
    rep{end+1} = sprintf('  %-24s acted on the clean link in %d/%d frames', modes{md}, sum(acted), sum(mn)); %#ok<SAGROW>
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/combined_threats.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/combined_threats.mat', 'Dec', 'ber_tab', 'ratio', 'clean', 'links', 'actions', 'EBNO_LIST', 'T', 'modes');
fprintf('\nSaved results/combined_threats.{txt,mat} (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function a = dqn_act(agent, cls, ber, rssi, ebno, plr)
st = build_dqn_state(cls, ber, rssi, ebno, plr);
q = gather(extractdata(predict(agent.qNetwork, dlarray(single(st), 'CB'))));
[~, i] = max(q);
a = agent.action_names{i};
end

function s = top_classes(c, n)
[u, ~, ic] = unique(c(:));
cnt = accumarray(ic, 1);
[cnt, o] = sort(cnt, 'descend');
parts = {};
for i = 1:min(n, numel(o))
    parts{end+1} = sprintf('%s %.0f%%', u{o(i)}, 100*cnt(i)/numel(c)); %#ok<AGROW>
end
s = strjoin(parts, ', ');
end

function [mu, sd] = load_norm_stats()
cache = 'data/gui_norm_stats.mat';
if ~isfile(cache) || (isfile('data/splits.mat') && dir(cache).datenum < dir('data/splits.mat').datenum)
    S = load('data/splits.mat', 'splits');
    feat_mean = S.splits.norm.feat_mean; feat_std = S.splits.norm.feat_std; %#ok<NASGU>
    save(cache, 'feat_mean', 'feat_std');
end
N = load(cache, 'feat_mean', 'feat_std');
mu = N.feat_mean; sd = N.feat_std;
end
