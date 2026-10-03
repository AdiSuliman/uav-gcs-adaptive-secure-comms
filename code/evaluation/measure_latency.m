%% MEASURE_LATENCY - Decision latency per cycle (KPI 7: real time)
% One decision cycle as deployed: spectrogram image of the received frame, link
% features, detector (class probabilities and the unknown-threat score from one
% forward pass, detect_scores.m), link monitor with the temporal fusion and the
% unknown-score window + policy (policy_decide.m, the selected DQN and the rule). Real frames of the threat link (none, jamming,
% noise_burst, spoofing at 4 dB).
% A deployed receiver runs the detector on one device, so each device (GPU when
% present, CPU) is timed in its own passes, after a warm-up pass; alternating the
% two devices inside one cycle slows both (CUDA synchronization and GPU memory
% management run into the next call). The cycle total uses the device with the
% lower 95th percentile; GPU work is synchronized before each clock read.
% A third pass runs the whole cycle on one CPU core (maxNumCompThreads(1)), the
% nearest desktop proxy of a small on-board computer (Tariq et al.: a real-time
% claim needs measured wall-clock time); it is not a measurement on UAV hardware.
% Reported: median and 95th percentile in ms per component and per cycle, every
% device, and the frame duration for reference.
%
% Output: results/latency.txt, results/latency.mat

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision latency per cycle ===\n\n');
N_REP = 10;                                   % timed passes over every frame
if exist('SMOKE', 'var') && SMOKE, N_REP = 1; end   % reduced chain check (run_stage smoke)
THREATS = {'none', 'jamming', 'noise_burst', 'spoofing'};
EBNO = 4; delay_bits = 20; tw = 10;
modelName = 'UAV_GCS_Threat_Link';

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
fs = p0.symbol_rate * p0.sps;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
mu = N.splits.norm.feat_mean; sd = N.splits.norm.feat_std; clear N
Q = load('data/trained_dqn.mat', 'agent', 'confirm', 'alarm_mode', 'drop_db');
T = ood_thresholds(0.95);
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end   % temporal fusion (select_fusion.m), as evaluated
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end                        % unknown-score window (eval_ood_detection.m)
PPm = struct('actions', {policy_actions()}, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'sps', p0.sps, 'bps', p0.bits_per_symbol, 'maha_thr', T.maha, 'fuse', FZ.FM, 'fuse_N', FZ.N, 'unk_win', UW);
if isfield(Q, 'confirm'), PPm.confirm = Q.confirm; end
if isfield(Q, 'alarm_mode'), PPm.alarm_mode = Q.alarm_mode; end
if isfield(Q, 'drop_db') && ~isempty(Q.drop_db), PPm.drop_db = Q.drop_db; end
nA = numel(PPm.actions); na = find(strcmp(PPm.actions, 'no_action'));
gpu = canUseGPU;

%% 1. Frames of the real link
F = {};
for t = 1:numel(THREATS)
    p = p0; p.active_threat = THREATS{t}; p.seed = 4242 + t;
    evalc('build_threat_model(p)');
    set_param([modelName '/AWGN'], 'SNR', num2str(EBNO + 10*log10(p.bits_per_symbol) - 10*log10(p.sps)), ...
        'SignalPower', num2str(1/p.sps));
    M = extract_closed_loop_frames(sim(modelName, 'StopTime', num2str(20 * p.frame_duration)), p, delay_bits);
    disk_guard;
    for k = reshape(find(~isnan(M.ber)), 1, [])
        F{end+1} = struct('iq', M.iq{k}, 'M', M, 'k', k); %#ok<SAGROW>
    end
end
if bdIsLoaded(modelName), close_system(modelName, 0); end
nF = numel(F);
fprintf('%d frames from %d threat runs at %g dB\n', nF, numel(THREATS), EBNO);

%% 2. Timed cycles, one device at a time
names = {'spectrogram', 'features', 'detector GPU', 'detector CPU', 'DQN policy', 'rule policy'};
devs = {'cpu', 'cpu1'}; if gpu, devs = {'gpu', 'cpu', 'cpu1'}; end
T = struct();
nt0 = maxNumCompThreads;
for di = 1:numel(devs)
    dv = devs{di}; ug = strcmp(dv, 'gpu');
    ddev = dv; if strcmp(dv, 'cpu1'), ddev = 'cpu'; maxNumCompThreads(1); else, maxNumCompThreads(nt0); end
    tm = nan(N_REP * nF, 4);                      % spectrogram, features, detector, DQN policy, per cycle
    tr = nan(N_REP * nF, 1);                      % rule policy
    n = 0;
    for rep = 0:N_REP
        memD = []; memR = []; cfgD = na; cfgR = na;
        for f = 1:nF
            x = F{f};
            t0 = tic; img = spec_image(x.iq, fs); t_spec = toc(t0);
            t0 = tic; raw = link_features(x.M, x.k, tw); t_feat = toc(t0);
            X = reshape(single(img), 128, 128, 1, 1); Fn = ((raw - mu) ./ sd)';
            t0 = tic; [probs, maha] = detect_scores(D.net, D.ood, X, Fn, ddev); sync(ug); t_det = toc(t0);
            obs = struct('probs', probs(:)', 'unknown', maha < PPm.maha_thr, 'maha', maha, 'feat', raw, ...
                'gant', x.M.gain_ant(:, x.k)');
            t0 = tic; [cfgD, memD] = policy_decide('dqn_esc', obs, cfgD, memD, PPm, Q.agent); t_dqn = toc(t0);
            t0 = tic; [cfgR, memR] = policy_decide('rule_esc', obs, cfgR, memR, PPm, []); t_rule = toc(t0);
            if rep > 0                               % pass 0 = warm-up
                n = n + 1;
                tm(n, :) = 1000 * [t_spec, t_feat, t_det, t_dqn]; tr(n) = 1000 * t_rule;
            end
        end
    end
    T.(dv) = struct('tm', tm(1:n, :), 'tr', tr(1:n), 'dqn', sum(tm(1:n, :), 2), 'rule', sum(tm(1:n, 1:3), 2) + tr(1:n));
end
maxNumCompThreads(nt0);
p95 = @(x) quant(x, 0.95);
dsel = 'cpu'; if gpu && p95(T.gpu.dqn) < p95(T.cpu.dqn), dsel = 'gpu'; end   % detector device used in the cycle
jd = 4; if strcmp(dsel, 'gpu'), jd = 3; end
tm = nan(size(T.(dsel).tm, 1), numel(names));
tm(:, [1 2 5]) = T.(dsel).tm(:, [1 2 4]); tm(:, 6) = T.(dsel).tr;
if gpu, tm(:, 3) = T.gpu.tm(:, 3); end
tm(:, 4) = T.cpu.tm(:, 3);
n = size(tm, 1);
tot_dqn = T.(dsel).dqn;
tot_rule = T.(dsel).rule;
oth = setdiff(devs, {dsel, 'cpu1'});

%% 3. Report
LAT = struct('names', {names}, 'median_ms', median(tm), 'p95_ms', p95(tm), ...
    'total_dqn_median_ms', median(tot_dqn), 'total_dqn_p95_ms', p95(tot_dqn), ...
    'total_rule_median_ms', median(tot_rule), 'total_rule_p95_ms', p95(tot_rule), ...
    'frame_ms', 1000 * p0.frame_duration, 'n', n, 'gpu', gpu, 'device', device_name(jd == 3), ...
    'devices', device_name(gpu), ...
    'single_core', struct('total_dqn_median_ms', median(T.cpu1.dqn), 'total_dqn_p95_ms', p95(T.cpu1.dqn), ...
        'detector_median_ms', median(T.cpu1.tm(:, 3)), 'detector_p95_ms', p95(T.cpu1.tm(:, 3))), ...
    'generated', datestr(now));
if ~isempty(oth)
    LAT.other = struct('device', device_name(strcmp(oth{1}, 'gpu')), 'total_dqn_median_ms', median(T.(oth{1}).dqn), ...
        'total_dqn_p95_ms', p95(T.(oth{1}).dqn));
end
rep = {};
rep{end+1} = '=== DECISION LATENCY PER CYCLE ===';
rep{end+1} = sprintf('Generated: %s | %d timed cycles per device (%d frames x %d passes, after 1 warm-up pass) | %s', ...
    LAT.generated, n, nF, N_REP, LAT.device);
rep{end+1} = 'Each device timed in its own passes (a deployed receiver uses one); components of the selected device, detector on both.';
rep{end+1} = sprintf('%-16s %10s %10s', 'component', 'median ms', 'p95 ms');
for i = 1:numel(names)
    rep{end+1} = sprintf('%-16s %10.3f %10.3f', names{i}, LAT.median_ms(i), LAT.p95_ms(i)); %#ok<SAGROW>
end
rep{end+1} = sprintf('Cycle total with the detector on the %s (lower p95):', LAT.device);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (DQN)', LAT.total_dqn_median_ms, LAT.total_dqn_p95_ms);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (rule)', LAT.total_rule_median_ms, LAT.total_rule_p95_ms);
if isfield(LAT, 'other')
    rep{end+1} = sprintf('%-16s %10.3f %10.3f   (detector on the %s)', 'total (DQN)', LAT.other.total_dqn_median_ms, ...
        LAT.other.total_dqn_p95_ms, LAT.other.device);
end
rep{end+1} = sprintf('%-16s %10.3f %10.3f   (whole cycle on one CPU core; detector %.3f / %.3f ms)', 'total (DQN)', ...
    LAT.single_core.total_dqn_median_ms, LAT.single_core.total_dqn_p95_ms, LAT.single_core.detector_median_ms, ...
    LAT.single_core.detector_p95_ms);
rep{end+1} = sprintf('Frame duration %.3f ms: one decision per %d frames at the p95 latency.', LAT.frame_ms, ...
    ceil(LAT.total_dqn_p95_ms / LAT.frame_ms));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/latency.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save('results/latency.mat', 'LAT', 'tm', 'T');
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
