%% MEASURE_LATENCY - Decision latency per cycle (KPI: real time) (D46, D48)
% One decision cycle as deployed: spectrogram image of the received frame,
% link features, detector (class probabilities and Mahalanobis score from one
% forward pass, detect_scores.m), link monitor + policy (policy_decide.m,
% selected DQN and rule). The detector is timed on the GPU and on the CPU; the
% cycle total uses the device with the lower 95th percentile. Real frames of
% the threat link (none, jamming, noise_burst, spoofing at 4 dB), after a
% warm-up pass; GPU work is synchronized before each clock read. Reported:
% median and 95th percentile in ms, and the frame duration for reference.
%
% Output: results/latency.txt, results/latency.mat

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision latency per cycle (D46, D48) ===\n\n');
N_REP = 10;                                   % timed passes over every frame
THREATS = {'none', 'jamming', 'noise_burst', 'spoofing'};
EBNO = 4; delay_bits = 20; tw = 10;
modelName = 'UAV_GCS_Threat_Link';

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
fs = p0.symbol_rate * p0.sps;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
mu = N.splits.norm.feat_mean; sd = N.splits.norm.feat_std; clear N
Q = load('data/trained_dqn.mat', 'agent', 'confirm', 'alarm_mode');
T = ood_thresholds(0.95);
PPm = struct('actions', {policy_actions()}, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'sps', p0.sps, 'bps', p0.bits_per_symbol, 'maha_thr', T.maha);
if isfield(Q, 'confirm'), PPm.confirm = Q.confirm; end
if isfield(Q, 'alarm_mode'), PPm.alarm_mode = Q.alarm_mode; end
nA = numel(PPm.actions); na = find(strcmp(PPm.actions, 'no_action'));
gpu = canUseGPU;

%% 1. Frames of the real link
F = {};
for t = 1:numel(THREATS)
    p = p0; p.active_threat = THREATS{t}; p.seed = 4242 + t;
    params = p; save('params.mat', 'params');
    evalc('build_threat_model');
    set_param([modelName '/AWGN'], 'SNR', num2str(EBNO + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), ...
        'SignalPower', num2str(1/p.sps));
    out = sim(modelName, 'StopTime', num2str(20 * p.frame_duration));
    [iqf, ber, rssi, plr, ~, sinr, ec, iot] = extract_closed_loop_frames(out, p, delay_bits);
    M = struct('sinr', sinr, 'ber', ber, 'rssi', rssi, 'plr', plr, 'env_corr', ec, 'iot', iot);
    for k = reshape(find(~isnan(ber)), 1, [])
        F{end+1} = struct('iq', iqf{k}, 'M', M, 'k', k, 'ber', ber(k)); %#ok<SAGROW>
    end
end
params = S0.params; save('params.mat', 'params');
if bdIsLoaded(modelName), close_system(modelName, 0); end
nF = numel(F);
fprintf('%d frames from %d threat runs at %g dB\n', nF, numel(THREATS), EBNO);

%% 2. Timed cycles
names = {'spectrogram', 'features', 'detector GPU', 'detector CPU', 'DQN policy', 'rule policy'};
tm = nan(N_REP * nF, numel(names));
n = 0;
for rep = 0:N_REP
    memD = []; memR = []; cfgD = na; cfgR = na;
    for f = 1:nF
        x = F{f};
        t0 = tic; img = spec_image(x.iq, fs); t_spec = toc(t0);
        t0 = tic; raw = link_features(x.M, x.k, tw, p0.frame_duration); t_feat = toc(t0);
        X = reshape(single(img), 128, 128, 1, 1); Fn = ((raw - mu) ./ sd)';
        t_gpu = NaN;
        if gpu, t0 = tic; [probs, maha] = detect_scores(D.net, D.ood, X, Fn, 'gpu'); sync(gpu); t_gpu = toc(t0); end
        t0 = tic; [probs, maha] = detect_scores(D.net, D.ood, X, Fn, 'cpu'); t_cpu = toc(t0);
        obs = struct('probs', probs(:)', 'unknown', maha < PPm.maha_thr, 'feat', raw, 'ber', x.ber);
        t0 = tic; [cfgD, memD] = policy_decide('dqn', obs, cfgD, memD, PPm, Q.agent); sync(gpu); t_dqn = toc(t0);
        t0 = tic; [cfgR, memR] = policy_decide('rule', obs, cfgR, memR, PPm, []); t_rule = toc(t0);
        if rep > 0                                   % pass 0 = warm-up
            n = n + 1;
            tm(n, :) = 1000 * [t_spec, t_feat, t_gpu, t_cpu, t_dqn, t_rule];
        end
    end
end
tm = tm(1:n, :);
p95 = @(x) quant(x, 0.95);
jd = 4; if gpu && p95(tm(:, 3)) < p95(tm(:, 4)), jd = 3; end   % detector device used in the cycle
tot_dqn = sum(tm(:, [1 2 jd 5]), 2);
tot_rule = sum(tm(:, [1 2 jd 6]), 2);

%% 3. Report
LAT = struct('names', {names}, 'median_ms', median(tm), 'p95_ms', p95(tm), ...
    'total_dqn_median_ms', median(tot_dqn), 'total_dqn_p95_ms', p95(tot_dqn), ...
    'total_rule_median_ms', median(tot_rule), 'total_rule_p95_ms', p95(tot_rule), ...
    'frame_ms', 1000 * p0.frame_duration, 'n', n, 'gpu', gpu, 'device', device_name(jd == 3), ...
    'devices', device_name(gpu), ...
    'generated', datestr(now));
rep = {};
rep{end+1} = '=== DECISION LATENCY PER CYCLE (D46, D48) ===';
rep{end+1} = sprintf('Generated: %s | %d timed cycles (%d frames x %d passes, after 1 warm-up pass) | %s', ...
    LAT.generated, n, nF, N_REP, LAT.device);
rep{end+1} = sprintf('%-16s %10s %10s', 'component', 'median ms', 'p95 ms');
for i = 1:numel(names)
    rep{end+1} = sprintf('%-16s %10.3f %10.3f', names{i}, LAT.median_ms(i), LAT.p95_ms(i)); %#ok<SAGROW>
end
rep{end+1} = sprintf('Cycle total with the detector on the %s (lower p95):', LAT.device);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (DQN)', LAT.total_dqn_median_ms, LAT.total_dqn_p95_ms);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (rule)', LAT.total_rule_median_ms, LAT.total_rule_p95_ms);
rep{end+1} = sprintf('Frame duration %.3f ms: one decision per %d frames at the p95 latency.', LAT.frame_ms, ...
    ceil(LAT.total_dqn_p95_ms / LAT.frame_ms));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/latency.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/latency.mat', 'LAT', 'tm');
fprintf('Saved results/latency.{txt,mat}\n');

%% ===================== Local functions =====================
function q = quant(x, p)
% Column-wise empirical quantile (nearest rank).
x = sort(x, 1);
q = x(max(1, ceil(p * size(x, 1))), :);
end

function sync(gpu)
if gpu, wait(gpuDevice); end
end

function s = device_name(gpu)
if gpu, g = gpuDevice; s = ['GPU ' g.Name]; else, s = 'CPU'; end
end
