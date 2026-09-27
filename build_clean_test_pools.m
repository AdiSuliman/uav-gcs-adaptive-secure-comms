%% BUILD_CLEAN_TEST_POOLS - Clean-link test pools over many geometries (D51)
% The false-alarm KPI needs independent trials. The test split of
% build_policy_pools.m holds 4 geometries per Eb/N0, so its 768 clean episodes
% come from only 24 channels and one unfavorable geometry decides the result.
% This script measures the clean link ('none') on CFG.clean_test_geoms new
% geometries per Eb/N0 (default 100, seeds never used before), under every
% configuration (common random numbers, as in build_policy_pools.m), with the
% same detector, frames per geometry and features. evaluate_policies.m runs one
% clean episode per geometry on these pools: 600 independent episodes at the
% default size, and the Clopper-Pearson bound of KPI 6 is computed over them.
%
% Output: data/clean_test_pools.mat (struct CT)

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Clean-link test pools over many geometries (D51) ===\n\n');

%% 1. Configuration
N_GEOM = 100;                                 % geometries per Eb/N0
if exist('CFG', 'var') && isstruct(CFG) && isfield(CFG, 'clean_test_geoms'), N_GEOM = CFG.clean_test_geoms; end
if N_GEOM > 100, error('build_clean_test_pools: at most 100 geometries per Eb/N0 (seed block of pool_seed.m)'); end
SP = 3;                                       % seed block of this set (1 train, 2 test pools)
tw = 10; delay_bits = 20;
modelName = 'UAV_GCS_Threat_Link';
f_out = 'data/clean_test_pools.mat';

L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
EBNO = PP.ebno; ACTIONS = PP.actions; F_SUB = PP.F_SUB; vrange = PP.speed_range; clear PP
nS = numel(EBNO); nA = numel(ACTIONS);
runs = 100 * SP + (1:N_GEOM);

if isfile(f_out) && dir(f_out).datenum > dir('data/trained_detector.mat').datenum
    C = load(f_out, 'CT');
    if isequal(C.CT.runs, runs) && isequal(C.CT.ebno, EBNO) && isequal(C.CT.actions, ACTIONS)
        fprintf('%s is up to date (%d geometries per Eb/N0), nothing to do\n', f_out, N_GEOM);
        return
    end
end

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
fs = p0.symbol_rate * p0.sps;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
mu = N.splits.norm.feat_mean; sd = N.splits.norm.feat_std; clear N
stop_time = num2str(F_SUB * p0.frame_duration);

%% 2. Simulation: every configuration x Eb/N0 x geometry, clean link
pools = cell(1, nS, nA);
t0 = tic;
for a = 1:nA
    p = p0; p.active_threat = 'none';
    [p2, g_db] = apply_countermeasure(p, 'none', ACTIONS{a});
    p2.seed = [];
    params = p2; save('params.mat', 'params');
    evalc('build_threat_model');
    for s = 1:nS
        snr_dB = EBNO(s) + 10*log10(p2.bits_per_symbol) - 10*log10(p2.sps);
        set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB + g_db), 'SignalPower', num2str(1/p2.sps));
        P = empty_pool();
        for r = 1:N_GEOM
            [seed, v_kmh] = pool_seed(1, s, SP, r, vrange);                  % same for every configuration
            fd = v_kmh / 3.6 * p0.carrier_freq / p0.c_light;
            link_seed(modelName, seed, fd);
            out = sim(modelName, 'StopTime', stop_time);
            P = add_run(P, out, p2, delay_bits, tw, D, mu, sd, fs, runs(r));
        end
        pools{1, s, a} = P;
    end
    fprintf('  [%2d/%d] %-32s %d Eb/N0 x %d geometries (%.1f min)\n', a, nA, ACTIONS{a}, nS, N_GEOM, toc(t0)/60);
end
params = S0.params; save('params.mat', 'params');
if bdIsLoaded(modelName), close_system(modelName, 0); end

CT = struct('pools', {pools}, 'runs', runs, 'ebno', EBNO, 'actions', {ACTIONS}, 'n_geom', N_GEOM, ...
    'created', datestr(now));
save(f_out, 'CT', '-v7.3');
fprintf('Saved %s (%.1f min)\n', f_out, toc(t0)/60);

%% ===================== Local functions =====================
function P = empty_pool()
P = struct('probs', zeros(0, 9), 'maha', zeros(0, 1), 'feat', zeros(0, 9), 'ber', zeros(0, 1), ...
    'plr', zeros(0, 1), 'run', zeros(0, 1), 'aoa', zeros(0, 3));
end

function P = add_run(P, out, p, delay_bits, tw, D, mu, sd, fs, run_id)
% Complete frames of one geometry with detector outputs and link features.
[iqf, ber, rssi, plr, ~, sinr, ec, iot] = extract_closed_loop_frames(out, p, delay_bits);
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
P.aoa = [P.aoa; nan(numel(v), 3)];
end
