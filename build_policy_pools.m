%% BUILD_POLICY_POOLS - Measured frame pools for the decision layer (D44-D46)
% Every scenario x configuration x Eb/N0 through the real link, with the
% detector already applied, so the decision-layer environment (link_env.m) never
% runs Simulink inside the learning loop.
%
% Scenarios: 8 single threats + none (train and test splits), 4 combined
% threats for the test split only, and 4 OTHER combined threats for the train
% split only (D46): the agent learns combinations, and is tested on
% combinations it never saw. Configurations: the 17
% actions of policy_actions.m, applied by apply_countermeasure.m. Eb/N0 0:2:10 dB,
% nominal severity.
%
% Each (scenario, Eb/N0, sub-run) has its own seed, shared by all 17
% configurations (common random numbers): the same fading, UAV speed and
% interferer directions (interferer_aoa.m) under every configuration, so a
% decision-layer episode can change configuration inside one geometry. Train and
% test sub-runs use different seeds. Per frame: detector class probabilities,
% Mahalanobis score, the 9 link features (link_features.m, temporal ones inside
% the sub-run), BER, PLR and the interferer directions of the sub-run.
% Seeds and speeds: pool_seed.m. An existing pools file made with the same
% detector, configurations, Eb/N0 grid and sub-runs is extended: only the
% scenarios it does not hold yet are simulated (identical seeds).
%
% Output: data/policy_pools.mat

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision-layer frame pools (D44-D46) ===\n\n');

%% 1. Configuration
SINGLES = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
           'antenna_fault', 'benign_interference', 'sweeping_jammer'};
COMBOS  = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst'};
TRAIN_COMBOS = {'reactive_jamming+path_loss', 'jamming+antenna_fault', 'spoofing+sweeping_jammer', ...
                'benign_interference+noise_burst'};
EBNO    = 0:2:10;
N_TRAIN = 6;                  % sub-runs (geometries) per (scenario, Eb/N0) in the train split
N_TEST  = 4;                  % sub-runs per (scenario, Eb/N0) in the test split
F_SUB   = 20;                 % frames per sub-run
tw = 10; delay_bits = 20;
modelName = 'UAV_GCS_Threat_Link';

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
if ~isfield(p0, 'int_aoa_random'), error('params.mat predates D45. Run init_params.m first.'); end
fs = p0.symbol_rate * p0.sps;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
mu = N.splits.norm.feat_mean; sd = N.splits.norm.feat_std;
T = ood_thresholds(0.95);
ACTIONS = policy_actions();
scen = [SINGLES, COMBOS, TRAIN_COMBOS];
nSc = numel(scen); nA = numel(ACTIONS); nS = numel(EBNO);
stop_time = num2str(F_SUB * p0.frame_duration);
runs = {100 + (1:N_TRAIN), 200 + (1:N_TEST)};
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
nsub_of = @(sc) [N_TRAIN * ~ismember(scen{sc}, COMBOS), N_TEST * ~ismember(scen{sc}, TRAIN_COMBOS)];

gp = ones(1, nA); bw = ones(1, nA); pw = ones(1, nA);
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', ACTIONS{a});
    gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor; pw(a) = cm.power_factor;
end

pools = cell(nSc, nS, nA, 2);            % {scenario, Eb/N0, action, split 1=train 2=test}
done = false(1, nSc);
f_pools = 'data/policy_pools.mat';
if isfile(f_pools) && dir(f_pools).datenum > dir('data/trained_detector.mat').datenum
    L = load(f_pools, 'PP'); old = L.PP; clear L
    nOld = numel(old.scen);
    same = isequal(old.actions, ACTIONS) && isequal(old.ebno, EBNO) && isfield(old, 'runs') && ...
        isequal(old.runs, runs) && old.F_SUB == F_SUB && nOld <= nSc && isequal(old.scen, scen(1:nOld)) && ...
        isfield(old, 'aoa_random') && old.aoa_random == p0.int_aoa_random;
    if same
        pools(1:nOld, :, :, :) = old.pools;
        done(1:nOld) = true;
        fprintf('Reusing %d scenarios of %s (same detector, configurations and seeds)\n\n', nOld, f_pools);
    else
        fprintf('%s has other configurations, Eb/N0 grid or sub-runs: full rebuild\n\n', f_pools);
    end
    clear old
elseif isfile(f_pools)
    fprintf('%s is older than the detector: full rebuild\n\n', f_pools);
end
t0 = tic;
for sc = find(~done)
    nsub = nsub_of(sc);
    for a = 1:nA
        p = p0; p.active_threat = scen{sc};
        [p2, g_db] = apply_countermeasure(p, scen{sc}, ACTIONS{a});
        p2.seed = [];
        params = p2; save('params.mat', 'params');
        evalc('build_threat_model');
        for s = 1:nS
            snr_dB = EBNO(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
            set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
            for sp = 1:2
                P = empty_pool();
                for r = 1:nsub(sp)
                    [seed, v_kmh] = pool_seed(sc, s, sp, r, vrange);             % same for every action
                    fd = v_kmh / 3.6 * p0.carrier_freq / p0.c_light;
                    link_seed(modelName, seed, fd);
                    if p0.int_aoa_random
                        aoa = interferer_aoa(seed, p0.int_aoa_range_deg, numel(p0.int_aoa_deg));
                    else
                        aoa = p0.int_aoa_deg(:)';
                    end
                    out = sim(modelName, 'StopTime', stop_time);
                    P = add_run(P, out, p2, delay_bits, tw, D, mu, sd, fs, 100*sp + r, aoa);
                end
                pools{sc, s, a, sp} = P;
            end
        end
    end
    fprintf('  [%2d/%d] %-26s %d configurations x %d Eb/N0 (%.1f min)\n', sc, nSc, scen{sc}, nA, nS, toc(t0)/60);
end
params = S0.params; save('params.mat', 'params');

%% 2. Cell statistics
mber = nan(nSc, nS, nA, 2); mplr = nan(nSc, nS, nA, 2);
for sc = 1:nSc
    for s = 1:nS
        for a = 1:nA
            for sp = 1:2
                P = pools{sc, s, a, sp};
                if ~isempty(P.ber), mber(sc, s, a, sp) = mean(P.ber); mplr(sc, s, a, sp) = mean(P.plr); end
            end
        end
    end
end
na = find(strcmp(ACTIONS, 'no_action'));
clean = squeeze(mber(1, :, na, 1));                  % none / no_action, train split

PP = struct('scen', {scen}, 'singles', {SINGLES}, 'combos', {COMBOS}, 'train_combos', {TRAIN_COMBOS}, ...
    'ebno', EBNO, 'actions', {ACTIONS}, 'speed_range', vrange, ...
    'gp', gp, 'bw', bw, 'pw', pw, 'pools', {pools}, 'mber', mber, 'mplr', mplr, 'clean', clean, ...
    'classes', {cellstr(string(D.classes(:)'))}, 'maha_thr', T.maha, 'F_SUB', F_SUB, ...
    'runs', {runs}, 'aoa_random', p0.int_aoa_random, ...
    'sps', p0.sps, 'bps', p0.bits_per_symbol, 'created', datestr(now));
clean_ref = struct('ebno', EBNO, 'ber', clean);
save('data/policy_pools.mat', 'PP', 'clean_ref', '-v7.3');

fprintf('\nClean-link BER per Eb/N0: %s\n', sprintf('%.2e ', clean));
fprintf('Unmitigated BER / clean (train split, singles):\n');
for sc = 2:numel(SINGLES)
    fprintf('  %-22s %s\n', scen{sc}, sprintf('%8.1f', squeeze(mber(sc, :, na, 1)) ./ clean));
end
fprintf('Saved data/policy_pools.mat (%.1f min)\n', toc(t0)/60);
clear pools PP

%% ===================== Local functions =====================
function P = empty_pool()
P = struct('probs', zeros(0, 9), 'maha', zeros(0, 1), 'feat', zeros(0, 9), 'ber', zeros(0, 1), ...
    'plr', zeros(0, 1), 'run', zeros(0, 1), 'aoa', zeros(0, 3));
end

function P = add_run(P, out, p, delay_bits, tw, D, mu, sd, fs, run_id, aoa)
% Complete frames of one sub-run with detector outputs and link features.
[iqf, ber, rssi, plr, nf, sinr, ec, iot] = extract_closed_loop_frames(out, p, delay_bits);
v = find(~isnan(ber));
if isempty(v), return; end
M = struct('sinr', sinr, 'ber', ber, 'rssi', rssi, 'plr', plr, 'env_corr', ec, 'iot', iot);
X = zeros(128, 128, 1, numel(v), 'single'); F = zeros(numel(v), 9);
for i = 1:numel(v)
    X(:, :, 1, i) = spec_image(iqf{v(i)}, fs);
    F(i, :) = link_features(M, v(i), tw, p.frame_duration);
end
Fn = (F - mu) ./ sd;
probs = cnn_scores(D.net, X, Fn');
maha = ood_scores(D.net, D.ood, X, Fn');
P.probs = [P.probs; probs']; P.maha = [P.maha; maha(:)]; P.feat = [P.feat; F];
P.ber = [P.ber; ber(v)']; P.plr = [P.plr; plr(v)']; P.run = [P.run; repmat(run_id, numel(v), 1)];
P.aoa = [P.aoa; repmat(aoa(1:3), numel(v), 1)];
end
