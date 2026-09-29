%% BUILD_POLICY_POOLS - Measured frame pools for the decision layer (D44-D46, D59, D61)
% Every threat cell x configuration x Eb/N0 x geometry through the real link, with
% the detector already applied, so the decision-layer environment (link_env.m)
% never runs Simulink inside the learning loop.
%
% Cells: the clean link; the 8 single threats at three severities (low, nominal,
% high; decision_config.m); 8 combined threats at nominal severity, like the single
% threats in every split (D61: the agent is tested on new flights of every threat
% type; generalization to a combination never trained on is measured separately by
% experiment_combo_generalization.m). Configurations: the 36 of policy_actions.m (one choice per domain),
% applied by apply_countermeasure.m; configurations with identical physics for a
% threat are simulated once (pool_cell.m). Eb/N0 0:2:10 dB.
% Splits: train 6, validation 4, test 8 geometries per (cell, Eb/N0). A geometry
% (seed: fading, UAV speed, interferer directions, threat waveform) is shared by
% every configuration and by every cell, the clean link included (common random
% numbers): an episode's frames before and after the onset come from the same
% flight (D59; until D58 the seed depended on the scenario, so the clean frames
% before the onset came from another flight), and it is never shared by two splits. Per frame: detector class probabilities, unknown-threat
% score, the link features of link_features.m (receiver measurements only), and
% the true BER and frame error (reward and evaluation only). Seeds: pool_seed.m.
% The cells run in parallel (Parallel Computing Toolbox), each worker in its own
% folder with its own copy of the model. When data/policy_pools.mat already holds
% the same train and validation geometries and only the test block differs (new
% test flights, D64), only the test split is simulated and the train and
% validation pools are kept.
%
% Output: data/policy_pools.mat (PP, clean_ref)

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision-layer frame pools (D44-D46, D59) ===\n\n');

%% 1. Configuration
SINGLES = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
           'antenna_fault', 'benign_interference', 'sweeping_jammer'};
COMBOS  = {'jamming+path_loss', 'noise_burst+antenna_fault', 'sweeping_jammer+path_loss', 'spoofing+noise_burst', ...
           'reactive_jamming+path_loss', 'jamming+antenna_fault', 'spoofing+sweeping_jammer', ...
           'benign_interference+noise_burst'};
EBNO   = 0:2:10;
NGEO   = [6 4 8];                % geometries per (cell, Eb/N0): train, validation, test
BLOCK  = [1 5 8];                % pool_seed.m block of each split (pool_seed.m lists every block)
SPLITS = {'train', 'val', 'test'};
N_WORKERS = 6;
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
C = decision_config();
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    SINGLES = {'none', 'jamming', 'path_loss'}; COMBOS = {'jamming+path_loss', 'reactive_jamming+path_loss'};
    EBNO = [2 8]; NGEO = [2 2 2];
end

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', N.splits.norm.feat_mean, 'sd', N.splits.norm.feat_std, 'fs', p0.symbol_rate * p0.sps);
clear N
T = ood_thresholds(0.95);
ACTIONS = policy_actions();
scen = [SINGLES, COMBOS];
nA = numel(ACTIONS); nS = numel(EBNO);
vrange = [p0.speed_kmh_min p0.speed_kmh_max];

% Cells: (threat, severity index, splits simulated)
cells = struct('threat', {}, 'sev', {}, 'level', {}, 'splits', {});
for i = 1:numel(scen)
    t = scen{i};
    if strcmp(t, 'none') || contains(t, '+')
        cells(end+1) = struct('threat', t, 'sev', 2, 'level', NaN, 'splits', 1:3); %#ok<SAGROW>
    else
        for v = 1:3
            cells(end+1) = struct('threat', t, 'sev', v, 'level', C.sev.(t).levels(v), 'splits', 1:3); %#ok<SAGROW>
        end
    end
end
nC = numel(cells);
runs = arrayfun(@(sp) 100 * BLOCK(sp) + (1:NGEO(sp)), 1:3, 'UniformOutput', false);
old = [];
if isfile('data/policy_pools.mat')
    Lo = load('data/policy_pools.mat', 'PP');
    if isequal(Lo.PP.runs(1:2), runs(1:2)) && ~isequal(Lo.PP.runs{3}, runs{3}) && isequal(Lo.PP.scen, {cells.threat}) ...
            && isequal(Lo.PP.ebno, EBNO) && isequal(Lo.PP.actions, ACTIONS) && isequaln(Lo.PP.level, [cells.level])
        old = Lo.PP.pools(:, :, :, 1:2);
        [cells.splits] = deal(3);
        fprintf('Train and validation pools kept; new test flights (block %d) only\n', BLOCK(3));
    end
    clear Lo
end

% Geometries: seeds and speeds per (Eb/N0, split), shared by every cell
geo = cell(1, nS);
for s = 1:nS
    g = struct('seed', {}, 'speed', {}, 'run', {});
    for sp = 1:3
        r = 1:NGEO(sp);
        [sd_, v_] = arrayfun(@(k) pool_seed(1, s, BLOCK(sp), k, vrange), r);
        g(sp) = struct('seed', sd_, 'speed', v_, 'run', 100 * BLOCK(sp) + r);
    end
    geo{s} = g;
end

%% 2. Simulation, one parallel job per cell
pl = gcp('nocreate');
if isempty(pl) || pl.NumWorkers ~= N_WORKERS
    delete(pl); pl = parpool('Processes', N_WORKERS);
end
repo = pwd;
spmd
    pool_worker_init(repo);
end
results = cell(1, nC); nuniq = zeros(1, nC);
t0 = tic;
fprintf('%d cells x %d configurations x %d Eb/N0 on %d workers\n', nC, nA, nS, N_WORKERS);
parfor c = 1:nC
    ce = cells(c);
    p = p0; p.active_threat = ce.threat;
    if ~isnan(ce.level), p.(C.sev.(ce.threat).field) = ce.level; end
    g = cellfun(@(x) x(ce.splits), geo, 'UniformOutput', false);
    [Ps, pinfo] = pool_cell(p, ce.threat, ACTIONS, EBNO, g, det, opt);
    Pc = cell(nS, nA, 3);
    Pc(:, :, ce.splits) = Ps;
    nuniq(c) = pinfo.n_unique;
    results{c} = Pc;
    fprintf('  cell %2d/%d %-28s %-8s %2d unique configurations\n', c, nC, ce.threat, C.sev_names{ce.sev}, nuniq(c));
end
fprintf('Simulated in %.1f min\n', toc(t0) / 60);

%% 3. Package
pools = cell(nC, nS, nA, 3);
for c = 1:nC, pools(c, :, :, :) = results{c}; end
if ~isempty(old), pools(:, :, :, 1:2) = old; end
clear results old
mber = nan(nC, nS, nA, 3); mfer = nan(nC, nS, nA, 3);
for c = 1:nC
    for s = 1:nS
        for a = 1:nA
            for sp = 1:3
                Q = pools{c, s, a, sp};
                if ~isempty(Q) && ~isempty(Q.ber), mber(c, s, a, sp) = mean(Q.ber); mfer(c, s, a, sp) = mean(Q.fer); end
            end
        end
    end
end
na = find(strcmp(ACTIONS, 'no_action')); nf = find(strcmp(ACTIONS, 'fec_interleave'));
ic = find(strcmp({cells.threat}, 'none'));
cq = pools(ic, :, na, 1);
clean_ref = struct('ebno', EBNO, 'ber', squeeze(mber(ic, :, na, 1)), 'fer', squeeze(mfer(ic, :, na, 1)), ...
    'ber_est', cellfun(@(Q) mean(10.^double(Q.feat(:, feature_index('log_ber')))), cq), ...
    'plr', cellfun(@(Q) mean(double(Q.feat(:, feature_index('crc_fail')))), cq), ...
    'plr_fec', cellfun(@(Q) mean(double(Q.feat(:, feature_index('crc_fail')))), pools(ic, :, nf, 1)));
gp = ones(1, nA); bw = ones(1, nA); pw = ones(1, nA);
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', ACTIONS{a});
    gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor; pw(a) = cm.power_factor;
end
PP = struct('scen', {{cells.threat}}, 'sev', [cells.sev], 'level', [cells.level], 'sev_names', {C.sev_names}, ...
    'splits', {SPLITS}, 'cell_splits', {{cells.splits}}, 'threats', {scen}, 'singles', {SINGLES}, ...
    'combos', {COMBOS}, 'ebno', EBNO, 'actions', {ACTIONS}, ...
    'speed_range', vrange, 'gp', gp, 'bw', bw, 'pw', pw, 'pools', {pools}, 'mber', mber, 'mfer', mfer, ...
    'clean', clean_ref.ber, 'clean_fer', clean_ref.fer, 'classes', {det.classes}, 'maha_thr', T.maha, ...
    'F_SUB', opt.F_SUB, 'runs', {runs}, ...
    'aoa_random', p0.int_aoa_random, 'sps', p0.sps, 'bps', p0.bits_per_symbol, ...
    'feat_names', {link_features('names')}, 'created', datestr(now));
save('data/policy_pools.mat', 'PP', 'clean_ref', '-v7.3');

fprintf('\nClean link per Eb/N0: BER %s | estimated BER %s | packet loss %s\n', sprintf('%.1e ', clean_ref.ber), ...
    sprintf('%.1e ', clean_ref.ber_est), sprintf('%.2f ', clean_ref.plr));
fprintf('Unmitigated BER / clean, nominal severity (train split):\n');
for c = find([cells.sev] == 2 & ~strcmp({cells.threat}, 'none') & ~contains({cells.threat}, '+'))
    fprintf('  %-22s %s\n', cells(c).threat, sprintf('%9.1f', squeeze(mber(c, :, na, 1)) ./ max(PP.clean, C.ber_floor)));
end
fprintf('Saved data/policy_pools.mat (%.1f min)\n', toc(t0) / 60);
clear pools PP
