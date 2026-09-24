%% RUN_CLOSED_LOOP_EPISODES.m — episodic closed loop, recovery time (proposal KPI #3, D31)
% A link runs clean, the threat starts mid-stream, and every decision cycle
% (one received frame) the detector classifies the current frame and the policy
% proposes an action. An action is a persistent configuration change;
% no_action keeps the current configuration. Dwell/hysteresis (proposal risk 8):
% a new action is committed only after it is proposed on DWELL consecutive
% cycles, and not within HOLD cycles of the previous switch.
%
% Frames come from real Simulink runs of every (threat, action, Eb/N0) —
% the link a frame is drawn from follows the configuration currently applied,
% so detection after a countermeasure sees the mitigated link. Detection runs
% the trained CNN on each frame (detect_frame.m) with the causal temporal
% features over the episode's own history.
%
% Measured per episode (cycles counted from threat onset):
%   T_detect  first cycle with the correct class
%   T_act     first committed countermeasure
%   T_recover first cycle from which the 5-cycle BER average stays <= 2x clean
%             for 10 cycles (NaN if the link never recovers in the episode)
%   switches, false alarms (switches on a healthy link), final BER/clean, goodput
% for DQN and rule-based, each with and without hysteresis, on identical
% random frame draws.
%
% Output: results/closed_loop_episodes.{txt,mat,png}

close all; clc;
fprintf('=== Episodic closed loop: recovery time in decision cycles (D31) ===\n\n');

%% 1. Configuration
EBNO_LIST   = [0 4 10];
N_PRE       = 20;          % clean cycles before threat onset
N_POST      = 60;          % cycles after onset
N_EPISODES  = 5;           % per (threat, Eb/N0, policy, hysteresis)
N_POOL_RUNS = 2;           % Simulink runs per (threat, action, Eb/N0) frame pool
DWELL = 3; HOLD = 10;      % hysteresis setting under test
RATIO_OK = 2; MA_LEN = 5; STAY = 10;
temporal_window = 10;      % must match extract_spectrograms.m
delay_bits = 20;

threats = {'jamming','reactive_jamming','sweeping_jammer','noise_burst','path_loss', ...
           'spoofing','antenna_fault','benign_interference','none'};
policies = {'dqn','rule'};
hyst = struct('name', {'hysteresis','no hysteresis'}, 'dwell', {DWELL, 1}, 'hold', {HOLD, 0});

%% 2. Models and parameters
D = load('data/trained_detector.mat', 'net', 'classes');
Q = load('data/trained_dqn.mat', 'agent');
agent = Q.agent;
actions = agent.action_names;
na = find(strcmp(actions, 'no_action'), 1);
[feat_mean, feat_std] = load_norm_stats();

init_params;
p0 = load('params.mat').params;
modelName = 'UAV_GCS_Threat_Link';
fs = p0.symbol_rate * p0.sps;
nT = numel(threats); nA = numel(actions); nS = numel(EBNO_LIST);

%% 3. Frame pools: every (threat, action, Eb/N0) through the real link
fprintf('Building frame pools: %d threats x %d actions x %d Eb/N0 x %d runs...\n', nT, nA, nS, N_POOL_RUNS);
pools = cell(nT, nA, nS);
t0 = tic;
for t = 1:nT
    p = p0; p.active_threat = threats{t};
    for a = 1:nA
        [p2, g_db] = apply_countermeasure(p, threats{t}, actions{a});
        params = p2; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:nS
            snr_dB = EBNO_LIST(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
            F = struct('iq', {{}}, 'ber', [], 'rssi', [], 'plr', []);
            for r = 1:N_POOL_RUNS
                out = sim(modelName);
                [iq_f, ber_f, rssi_f, plr_f] = extract_closed_loop_frames(out, p2, delay_bits);
                b = ber_f(:)'; rs = rssi_f(:)'; q = plr_f(:)';
                v = find(~isnan(b));
                F.iq   = [F.iq, reshape(cellfun(@single, iq_f(v), 'UniformOutput', false), 1, [])];
                F.ber  = [F.ber, b(v)];
                F.rssi = [F.rssi, rs(v)];
                F.plr  = [F.plr, q(v)];
            end
            pools{t, a, s} = F;
        end
    end
    fprintf('  [%d/%d] %-20s pooled (%.1f min)\n', t, nT, threats{t}, toc(t0)/60);
end
params = p0; save('params.mat', 'params');

it_none = strcmp(threats, 'none');
clean = zeros(1, nS);
for s = 1:nS, clean(s) = mean(pools{it_none, na, s}.ber); end
degraded = false(nT, nS);                 % does the unmitigated threat degrade the link?
for t = 1:nT
    for s = 1:nS
        degraded(t, s) = mean(pools{t, na, s}.ber) > RATIO_OK * clean(s);
    end
end
hostile = ~ismember(threats, {'benign_interference', 'none'});
gp_act = ones(1, nA);                     % goodput factor of each configuration
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', actions{a});
    gp_act(a) = cm.goodput_factor;
end

%% 4. Episodes
cfg_keys = {};
for pi_ = 1:numel(policies)
    for h = 1:numel(hyst), cfg_keys{end+1} = sprintf('%s | %s', policies{pi_}, hyst(h).name); end %#ok<SAGROW>
end
nC = numel(cfg_keys);
E = struct('threat', {}, 'ebno', {}, 'cfg', {}, 'ep', {}, 'T_detect', {}, 'T_act', {}, 'T_recover', {}, ...
    'switches', {}, 'fa_pre', {}, 'final_ratio', {}, 'goodput', {}, 'actions_taken', {}, 'trace', {});
fprintf('\nRunning %d episodes (%d cycles each)...\n', nT*nS*nC*N_EPISODES, N_PRE + N_POST);
t1 = tic;
for t = 1:nT
    for s = 1:nS
        ebno = EBNO_LIST(s);
        for ep = 1:N_EPISODES
            seed = 100000*t + 1000*s + ep;
            for pi_ = 1:numel(policies)
                for h = 1:numel(hyst)
                    rng(seed, 'twister');
                    R = run_episode(t, s, ebno, threats, actions, na, pools, agent, D, feat_mean, feat_std, fs, ...
                        policies{pi_}, hyst(h), N_PRE, N_POST, temporal_window, p0.frame_duration, gp_act);
                    [Trec, fratio] = recovery_time(R.ber, N_PRE, clean(s), RATIO_OK, MA_LEN, STAY);
                    E(end+1) = struct('threat', threats{t}, 'ebno', ebno, ...
                        'cfg', sprintf('%s | %s', policies{pi_}, hyst(h).name), 'ep', ep, ...
                        'T_detect', R.T_detect, 'T_act', R.T_act, 'T_recover', Trec, ...
                        'switches', R.switches_post, 'fa_pre', R.switches_pre, 'final_ratio', fratio, ...
                        'goodput', R.goodput_post, 'actions_taken', {R.committed}, 'trace', R); %#ok<SAGROW>
                end
            end
        end
    end
    fprintf('  [%d/%d] %-20s done (%.1f min)\n', t, nT, threats{t}, toc(t1)/60);
end

%% 5. Save and report
if ~exist('results', 'dir'), mkdir('results'); end
save('results/closed_loop_episodes.mat', 'E', 'clean', 'degraded', 'threats', 'actions', 'EBNO_LIST', ...
    'N_PRE', 'N_POST', 'DWELL', 'HOLD', 'RATIO_OK', 'MA_LEN', 'STAY', 'cfg_keys');
report_closed_loop_episodes;

%% 6. Figure
plot_closed_loop_episodes;


%% ===== Local functions =====
function R = run_episode(t, s, ebno, threats, actions, na, pools, agent, D, feat_mean, feat_std, fs, ...
    policy, hy, N_PRE, N_POST, tw, frame_dur, gp_act)
% One episode: clean cycles, onset, policy loop with dwell/hysteresis.
it_none = strcmp(threats, 'none');
N = N_PRE + N_POST;
ber = nan(1, N); rssi = nan(1, N); plr = nan(1, N);
cfg = na; last_switch = -inf; cand = 0; cand_n = 0;
R.T_detect = NaN; R.T_act = NaN; R.switches_pre = 0; R.switches_post = 0;
R.switch_at = []; R.committed = {}; gp = zeros(1, N_POST);
for k = 1:N
    if k <= N_PRE, src_t = find(it_none); else, src_t = t; end
    F = pools{src_t, cfg, s};
    j = randi(numel(F.ber));
    iq = double(F.iq{j}); ber(k) = F.ber(j); rssi(k) = F.rssi(j); plr(k) = F.plr(j);

    w0 = max(1, k - tw + 1);
    var_rssi = var(rssi(w0:k), 0);
    burst = mean(plr(w0:k), 'omitnan');
    if k > 1, dber = (ber(k) - ber(k-1)) / frame_dur; else, dber = 0; end
    raw = [ebno, ber(k), rssi(k), plr(k), var_rssi, dber, burst];
    cls = detect_frame(D.net, D.classes, iq, raw, feat_mean, feat_std, fs);
    if k > N_PRE && isnan(R.T_detect) && strcmp(cls, threats{t}), R.T_detect = k - N_PRE; end

    if strcmp(policy, 'dqn')
        st = build_dqn_state(cls, ber(k), rssi(k), ebno, plr(k));
        qv = extractdata(predict(agent.qNetwork, dlarray(single(st), 'CB')));
        [~, prop] = max(gather(qv));
    else
        prop = find(strcmp(actions, rule_based_policy(cls, ber(k), ebno)), 1);
    end

    % Dwell / hysteresis: no_action or the current configuration keeps things as they are
    if prop == na || prop == cfg
        cand = 0; cand_n = 0;
    else
        if prop == cand, cand_n = cand_n + 1; else, cand = prop; cand_n = 1; end
        if cand_n >= hy.dwell && (k - last_switch) >= hy.hold
            cfg = prop; last_switch = k; cand = 0; cand_n = 0;
            R.switch_at(end+1) = k; R.committed{end+1} = actions{cfg};
            if k <= N_PRE
                R.switches_pre = R.switches_pre + 1;
            else
                R.switches_post = R.switches_post + 1;
                if isnan(R.T_act), R.T_act = k - N_PRE; end
            end
        end
    end
    if k > N_PRE, gp(k - N_PRE) = gp_act(cfg); end
end
R.ber = ber;
R.goodput_post = mean(gp);
end

function [Trec, fratio] = recovery_time(ber, N_PRE, bc, RATIO_OK, MA_LEN, STAY)
% First post-onset cycle from which the causal MA_LEN-cycle BER average stays
% within RATIO_OK x clean for STAY cycles; final ratio over the last 20 cycles.
ma = movmean(ber, [MA_LEN-1 0]);
ok = ma <= RATIO_OK * bc;
N = numel(ber);
Trec = NaN;
for k = N_PRE + 1 : N - STAY + 1
    if all(ok(k : k + STAY - 1)), Trec = k - N_PRE; break; end
end
fratio = mean(ber(max(N_PRE + 1, N - 19):N), 'omitnan') / bc;
end

function tf = needs_action(e, threats, hostile, degraded, EBNO_LIST)
t = find(strcmp(threats, e.threat), 1);
s = find(EBNO_LIST == e.ebno, 1);
tf = hostile(t) || degraded(t, s);
end

function c = pick(E, threat, ebno, cfg)
c = E(strcmp({E.threat}, threat) & [E.ebno] == ebno & strcmp({E.cfg}, cfg));
end

function s = med(x)
x = x(~isnan(x));
if isempty(x), s = '-'; else, s = sprintf('%.0f', median(x)); end
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