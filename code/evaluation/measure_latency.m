%% MEASURE_LATENCY - Decision latency per cycle (KPI 7: real time)
% One decision cycle as deployed (lat_cycle.m): spectrogram image of the received frame, link
% features with the record of the cycle's idle time (idle_summary.m from that time's
% RSSI samples; the fusion's window cues run inside the monitor), the predicted MMSE gain
% (mmse_predict.m on every antenna's samples of the frame as the combiner sees them, the
% previous frame only as the receive filter's memory: the rule's and the agent's nulling
% input), detector (class
% probabilities and the unknown-threat score from one
% forward pass, detect_scores.m; the score selected by eval_ood_detection.m within the
% KPI 7 budget), link monitor with the temporal fusion and the
% unknown-score window + policy (policy_decide.m): the DEPLOYED policy as train_dqn.m chose
% it (the selected DQN with escalation, or the rule with escalation on its own monitor,
% policy_setup.m), with the DQN and the rule chains beside it. Real frames of the threat
% link (none, jamming, noise_burst, spoofing at 4 dB).
% Each chain (deployed, DQN as selected, rule + escalation) is a whole cycle timed in its own
% passes, in cycle order, one policy per cycle: no other policy runs before it in the cycle.
% The registered figure is the SUM of the deployed chain's components; the glue between them
% counts in the component it serves (the detector's input tensors in the detector, the
% observation in the policy). One clock around the whole deployed cycle is reported beside
% the sum, a side reading without a verdict. The receiver's own estimators (the BER estimate,
% the post-combining SNR and the spatial metrics, extract_closed_loop_frames.m) run in the
% receiver before the cycle and are not timed here; the cycle reads their outputs.
% The monitor reads the pools' settings as evaluated: the configurations' known gains and
% power factors (config_gain_db.m, PPm.pw as build_policy_pools.m stores it).
% A deployed receiver runs the detector on one device, so each device (GPU when
% present, CPU) is timed in its own passes, after a warm-up pass; alternating the
% two devices inside one cycle slows both (CUDA synchronization and GPU memory
% management run into the next call). The cycle total uses the device with the
% lower 95th percentile; GPU work is synchronized before each clock read (the device
% handle read once).
% A third pass runs the whole cycle on one CPU core (maxNumCompThreads(1)), the
% nearest desktop proxy of a small on-board computer (Tariq et al.: a real-time
% claim needs measured wall-clock time); it is not a measurement on UAV hardware.
% Reported: median and 95th percentile in ms per component and per cycle, every
% device, and the frame duration for reference. The machine's load is logged before and
% after the timings (machine_load.m: CPU load, other MATLAB processes), in latency.txt and
% beside KPI 7: a concurrent load only slows the cycle. LAT keeps the identity of what
% was timed, the detector (det_id, detector_id.m) and the deployed policy
% (policy_stamp.m), so the KPIs read a latency of another detector or policy as STALE
% (result_status.m).
% DET_FIRST = true before the run (diagnostic): the detector before the predictor in every
% cycle; written to results/kpi7/latency_det_first.{txt,mat}, never to the record.
% LAT_SETUP_ONLY = true before the run: the setup and the frames only (kpi7_guard.m).
%
% Output: results/latency.txt, results/latency.mat

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision latency per cycle ===\n\n');
N_REP = 10;                                   % timed passes over every frame
if exist('SMOKE', 'var') && SMOKE, N_REP = 1; end   % reduced chain check (run_stage smoke)
if ~exist('DET_FIRST', 'var'), DET_FIRST = false; end
THREATS = {'none', 'jamming', 'noise_burst', 'spoofing'};
EBNO = 4; delay_bits = 20; tw = 10;
modelName = 'UAV_GCS_Threat_Link';

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
assert_frame1_onsets(p0);                       % every threat on from its run's first frame (init_params.m)
fs = p0.symbol_rate * p0.sps;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
mu = N.splits.norm.feat_mean; sd = N.splits.norm.feat_std; clear N
Q = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', ...
    'deployed', 'rule_sel', 'det_id', 'maha_thr', 'dec');
T = ood_thresholds(0.95);
FZ = fusion_model();                                   % temporal fusion (select_fusion.m), as evaluated
Dt = load('data/trained_detector.mat', 'trained_at');
DET_ID = detector_id(Dt.trained_at, D.ood, FZ); clear Dt
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end                        % unknown-score window (eval_ood_detection.m)
PPm = struct('actions', {policy_actions()}, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'sps', p0.sps, 'bps', p0.bits_per_symbol, 'maha_thr', T.maha, 'fuse', FZ.FM, 'fuse_N', FZ.N, 'q_thr', FZ.q_thr, ...
    'unk_win', UW);
PPm = decision_settings(PPm, Q);                       % the deployed DQN's monitor and settings (train_dqn.m)
PPm.cfg_gain_db = config_gain_db(PPm.actions, p0);
nA = numel(PPm.actions); na = find(strcmp(PPm.actions, 'no_action'));
PPm.pw = ones(1, nA);                                  % power factor per configuration, as build_policy_pools.m stores it
for a = 1:nA, [~, ~, cm] = apply_countermeasure(p0, 'none', PPm.actions{a}); PPm.pw(a) = cm.power_factor; end
dep = 'dqn_esc'; if isfield(Q, 'deployed') && ~isempty(Q.deployed), dep = Q.deployed; end
sel = 1; if all(isfield(Q, {'gammas', 'seed_summary'})), sel = find(Q.gammas == Q.seed_summary.selected_gamma, 1); end
[kindP, agP, optP] = policy_setup(dep, Q, sel, [], [], [], na);   % the deployed chain
kindD = 'dqn_esc'; if strcmp(dep, 'dqn'), kindD = 'dqn'; end    % the DQN chain as selected (with or without the escalation)
gpu = canUseGPU;
CH = {'dep', 'dqn', 'rule'};                           % the chains, each in its own passes
POL = struct();
POL.dep = struct('kind', kindP, 'agent', agP, 'opt', optP);
POL.dqn = struct('kind', kindD, 'agent', Q.agent, 'opt', struct());
POL.rule = struct('kind', 'rule_esc', 'agent', [], 'opt', struct());
S = struct('p0', p0, 'fs', fs, 'tw', tw, 'D', D, 'mu', mu, 'sd', sd, 'PPm', PPm, 'dev', 'cpu', 'ug', false, ...
    'gdev', [], 'det_first', DET_FIRST);

%% 1. Frames of the real link
F = {};
for t = 1:numel(THREATS)
    p = p0; p.active_threat = THREATS{t}; p.seed = 4242 + t;
    evalc('build_threat_model(p)');
    set_link_snr(modelName, EBNO + 10*log10(p.bits_per_symbol) - 10*log10(p.sps), p);
    out = sim(modelName, 'StopTime', num2str(20 * p.frame_duration));
    M = extract_closed_loop_frames(out, p, delay_bits);
    iqa = out.get('Rx_IQ'); if ismatrix(iqa), iqa = reshape(iqa, size(iqa, 1), 1, []); end   % before the level calibration
    sy = reshape(out.get('Rx_S'), 8, []);                      % the receiver's arrival and frequency per frame
    disk_guard;
    for k = reshape(find(~isnan(M.ber)), 1, [])
        j = max(1, k - 1):k; s2 = sy(1:2, j);
        if k > 1, s2(:, 1) = NaN; end                         % frame k - 1: the filter's memory only, not measured
        F{end+1} = struct('iq', M.iq{k}, 'M', M, 'k', k, 'iqa', iqa(:, :, j), 'sy', s2); %#ok<SAGROW>
    end
end
if bdIsLoaded(modelName), close_system(modelName, 0); end
nF = numel(F);
fprintf('%d frames from %d threat runs at %g dB\n', nF, numel(THREATS), EBNO);
if exist('LAT_SETUP_ONLY', 'var') && LAT_SETUP_ONLY, return; end

%% 2. Timed cycles, one device at a time, each chain in its own passes
ld0 = machine_load();
names = {'spectrogram', 'features', 'MMSE predictor', 'detector GPU', 'detector CPU', 'DQN policy', 'rule policy', ...
    'deployed policy'};
devs = {'cpu', 'cpu1'}; if gpu, devs = {'gpu', 'cpu', 'cpu1'}; end
T = struct();
nt0 = maxNumCompThreads;
for di = 1:numel(devs)
    dv = devs{di};
    S.dev = dv; if strcmp(dv, 'cpu1'), S.dev = 'cpu'; maxNumCompThreads(1); else, maxNumCompThreads(nt0); end
    S.ug = strcmp(dv, 'gpu'); S.gdev = []; if S.ug, S.gdev = gpuDevice; end
    R = struct();
    for ci = 1:numel(CH)
        tc = nan(N_REP * nF, 6);                  % spectrogram, features, predictor, detector, policy, wall clock
        n = 0;
        for rep = 0:N_REP
            st = struct('cfg', na, 'mem', []);
            for f = 1:nF
                [~, tt, st] = lat_cycle(F{f}, S, POL.(CH{ci}), st);
                if rep > 0                       % pass 0 = warm-up
                    n = n + 1; tc(n, :) = 1000 * tt;
                end
            end
        end
        R.(CH{ci}) = tc(1:n, :);
    end
    T.(dv) = struct('dep', R.dep, 'dqn', R.dqn, 'rule', R.rule);
end
maxNumCompThreads(nt0);
ld1 = machine_load();
p95 = @(x) quant(x, 0.95);
tot = @(x) sum(x(:, 1:5), 2);                     % the cycle: the sum of its components
dsel = 'cpu'; if gpu && p95(tot(T.gpu.dep)) < p95(tot(T.cpu.dep)), dsel = 'gpu'; end   % detector device used in the cycle
n = size(T.(dsel).dep, 1);
tm = nan(n, numel(names));
tm(:, 1:3) = T.(dsel).dep(:, 1:3); tm(:, 6) = T.(dsel).dqn(:, 5); tm(:, 7) = T.(dsel).rule(:, 5); tm(:, 8) = T.(dsel).dep(:, 5);
if gpu, tm(:, 4) = T.gpu.dep(:, 4); end
tm(:, 5) = T.cpu.dep(:, 4);
tot_dep = tot(T.(dsel).dep);
tot_dqn = tot(T.(dsel).dqn);
tot_rule = tot(T.(dsel).rule);
wall_dep = T.(dsel).dep(:, 6);
oth = setdiff(devs, {dsel, 'cpu1'});

%% 3. Report
LAT = struct('names', {names}, 'median_ms', median(tm), 'p95_ms', p95(tm), ...
    'total_dqn_median_ms', median(tot_dqn), 'total_dqn_p95_ms', p95(tot_dqn), ...
    'total_rule_median_ms', median(tot_rule), 'total_rule_p95_ms', p95(tot_rule), ...
    'deployed', dep, 'total_dep_median_ms', median(tot_dep), 'total_dep_p95_ms', p95(tot_dep), ...
    'wall_dep_median_ms', median(wall_dep), 'wall_dep_p95_ms', p95(wall_dep), ...
    'frame_ms', 1000 * p0.frame_duration, 'n', n, 'gpu', gpu, 'device', device_name(strcmp(dsel, 'gpu')), ...
    'devices', device_name(gpu), ...
    'single_core', struct('total_dqn_median_ms', median(tot(T.cpu1.dqn)), 'total_dqn_p95_ms', p95(tot(T.cpu1.dqn)), ...
        'total_dep_median_ms', median(tot(T.cpu1.dep)), 'total_dep_p95_ms', p95(tot(T.cpu1.dep)), ...
        'wall_dep_median_ms', median(T.cpu1.dep(:, 6)), 'wall_dep_p95_ms', p95(T.cpu1.dep(:, 6)), ...
        'detector_median_ms', median(T.cpu1.dep(:, 4)), 'detector_p95_ms', p95(T.cpu1.dep(:, 4)), ...
        'predictor_median_ms', median(T.cpu1.dep(:, 3)), 'predictor_p95_ms', p95(T.cpu1.dep(:, 3))), ...
    'det_first', DET_FIRST, ...
    'score', D.ood.score, 'det_id', DET_ID, 'policy_stamp', policy_stamp(Q), 'generated', datestr(now));
LAT.load = struct('before', ld0, 'after', ld1);
LAT.load_text = load_text(LAT.load);
if ~isempty(oth)
    LAT.other = struct('device', device_name(strcmp(oth{1}, 'gpu')), 'total_dqn_median_ms', median(tot(T.(oth{1}).dqn)), ...
        'total_dqn_p95_ms', p95(tot(T.(oth{1}).dqn)));
end
rep = {};
rep{end+1} = '=== DECISION LATENCY PER CYCLE ===';
rep{end+1} = sprintf('Generated: %s | %d timed cycles per device and chain (%d frames x %d passes, after 1 warm-up pass) | %s', ...
    LAT.generated, n, nF, N_REP, LAT.device);
rep{end+1} = ['Each device timed in its own passes (a deployed receiver uses one); each chain (deployed, DQN, rule) ' ...
    'a whole cycle in its own passes, one policy per cycle; components of the selected device, detector on both.'];
rep{end+1} = ['Glue between the components counts in the one it serves (detector input in the detector, observation ' ...
    'in the policy); the receiver''s own estimators (extract_closed_loop_frames.m) run before the cycle, untimed.'];
if DET_FIRST, rep{end+1} = 'DIAGNOSTIC ORDER: the detector before the MMSE predictor in every cycle (not the record).'; end
rep{end+1} = sprintf('Unknown-threat score of the detector: %s (eval_ood_detection.m).', LAT.score);
rep{end+1} = sprintf('%-16s %10s %10s', 'component', 'median ms', 'p95 ms');
for i = 1:numel(names)
    rep{end+1} = sprintf('%-16s %10.3f %10.3f', names{i}, LAT.median_ms(i), LAT.p95_ms(i)); %#ok<SAGROW>
end
rep{end+1} = sprintf('Cycle total with the detector on the %s (lower p95 of the deployed chain):', LAT.device);
rep{end+1} = sprintf('%-16s %10.3f %10.3f   (deployed: %s)', 'total (deployed)', LAT.total_dep_median_ms, LAT.total_dep_p95_ms, dep);
rep{end+1} = sprintf('%-16s %10.3f %10.3f   (side reading, no verdict: one clock around the whole deployed cycle)', ...
    'wall (deployed)', LAT.wall_dep_median_ms, LAT.wall_dep_p95_ms);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (DQN)', LAT.total_dqn_median_ms, LAT.total_dqn_p95_ms);
rep{end+1} = sprintf('%-16s %10.3f %10.3f', 'total (rule)', LAT.total_rule_median_ms, LAT.total_rule_p95_ms);
if isfield(LAT, 'other')
    rep{end+1} = sprintf('%-16s %10.3f %10.3f   (detector on the %s)', 'total (DQN)', LAT.other.total_dqn_median_ms, ...
        LAT.other.total_dqn_p95_ms, LAT.other.device);
end
rep{end+1} = sprintf('%-16s %10.3f %10.3f   (whole cycle on one CPU core; detector %.3f / %.3f ms, MMSE predictor %.3f / %.3f ms)', ...
    'total (deployed)', LAT.single_core.total_dep_median_ms, LAT.single_core.total_dep_p95_ms, ...
    LAT.single_core.detector_median_ms, LAT.single_core.detector_p95_ms, LAT.single_core.predictor_median_ms, ...
    LAT.single_core.predictor_p95_ms);
rep{end+1} = sprintf('%-16s %10.3f %10.3f   (side reading, no verdict: one clock around the whole cycle on one CPU core)', ...
    'wall (deployed)', LAT.single_core.wall_dep_median_ms, LAT.single_core.wall_dep_p95_ms);
rep{end+1} = sprintf('Frame duration %.3f ms: one decision per %d frames at the p95 latency.', LAT.frame_ms, ...
    ceil(LAT.total_dep_p95_ms / LAT.frame_ms));
rep{end+1} = sprintf('Timed: detector %s, deployed policy %s (result_status.m checks them).', LAT.det_id, LAT.policy_stamp);
rep{end+1} = LAT.load_text;
out_dir = 'results'; out_name = 'latency';
if DET_FIRST, out_dir = fullfile('results', 'kpi7'); out_name = 'latency_det_first'; end
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
fid = fopen(fullfile(out_dir, [out_name '.txt']), 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
save(fullfile(out_dir, [out_name '.mat']), 'LAT', 'tm', 'T');
fprintf('Saved %s/%s.{txt,mat}\n', strrep(out_dir, '\', '/'), out_name);

%% ===================== Local functions =====================
function q = quant(x, p)
% Column-wise empirical quantile (nearest rank).
x = sort(x, 1);
q = x(max(1, ceil(p * size(x, 1))), :);
end

function s = device_name(gpu)
if gpu, g = gpuDevice; s = ['GPU ' g.Name]; else, s = 'CPU'; end
end

function s = load_text(L)
% The machine's load logged with the timings (machine_load.m); a load only slows the cycle.
s = sprintf(['Timed with the machine''s load before / after: CPU %s / %s %%, other MATLAB processes %s / %s. ' ...
    'A concurrent load only slows the cycle: a pass under load holds on an idle machine, a fail under load is ' ...
    'measured again on an idle machine (run_stage(''LAT'')).'], num_txt(L.before.cpu_pct), num_txt(L.after.cpu_pct), ...
    num_txt(L.before.n_matlab - 1), num_txt(L.after.n_matlab - 1));
end

function s = num_txt(v)
if isnan(v), s = 'n/a'; else, s = sprintf('%g', round(v)); end
end
