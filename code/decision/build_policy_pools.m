%% BUILD_POLICY_POOLS - Measured frame pools for the decision layer
% Every threat cell x configuration x Eb/N0 x geometry through the real link, with
% the detector already applied, so the decision-layer environment (link_env.m)
% never runs Simulink inside the learning loop.
%
% Cells: the clean link; the 10 single threats at five severities
% (decision_config.m); the 14 combined threats (pairs and triples), each component
% at three severities (C.combo_sev), in every split but the edge speeds (a
% combination never trained on is measured by experiment_combo_generalization.m).
% Configurations: the 36 of policy_actions.m, applied by apply_countermeasure.m;
% configurations with identical physics for a threat are simulated once
% (pool_cell.m). Eb/N0: the grid of init_params.
% Splits, geometries per (cell, Eb/N0): train 8, validation 6, test 12; edge speeds
% 24 for the clean link and the single threats at nominal severity (12 at hover and
% 12 at 161 km/h, the limit of small UAVs, Khawaja et al.); second test 60 for the
% clean link and the single threats, and 24 geometries of their own for the combined
% threats (36 per point with the test), which the clean link flies too (each cell's
% geometries per split: PP.cell_geo). The test and second test geometries are nested
% Latin hypercubes over speed, altitude and K of our signal (pool_geometries.m):
% 2 + 10 flights per sixth of the speed range and 4 + 20 per third of the altitude
% range at every Eb/N0.
% A geometry (seed: fading and its K-factors, UAV speed and altitude, interferer
% directions, threat waveform) is shared by every configuration and every cell that
% flies it, the clean link included (common random numbers), so an episode's frames
% before and after the onset come from one flight; a geometry is never shared by two
% splits. Seeds: pool_seed.m. Per geometry, every per-flight draw (flight_draws.m) is
% kept in PP.cov.
% Per frame: detector class probabilities, unknown-threat score, the link
% features of link_features.m (receiver measurements only), and the true BER and
% frame error (reward and evaluation only).
% The cells run in parallel, each worker in its own folder with its own copy of
% the model. When data/policy_pools.mat holds the same train and validation
% geometries of the same link model (MODEL_TAG) and only the test block differs, only
% the test, edge-speed and second test splits are simulated.
%
% Output: data/policy_pools.mat (PP, clean_ref)

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Decision-layer frame pools ===\n\n');

%% 1. Configuration
SINGLES = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
           'antenna_fault', 'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
C = decision_config();
COMBOS  = C.combos;
S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
EBNO   = p0.EbNo_dB;
NGEO   = [8 6 12 24 60];         % geometries per (cell, Eb/N0): train, validation, test, edge speeds, second test
NCOMB  = [0 0 0 0 24];           % own geometries of the combined threats (0: they fly the split's geometries)
BLOCK  = [1 5 14 16 17];         % pool_seed.m block of each split (pool_seed.m lists every block)
SPLITS = {'train', 'val', 'test', 'speed', 'test2'};
LHS    = [false false true false true];   % splits laid out as nested Latin hypercubes (pool_geometries.m)
LHS_SEED = 7100000;              % permutation stream of a design: LHS_SEED + 100 (Eb/N0 index) + split (+ 10: combined threats)
VOUT   = [0 0; 161 161];         % speeds of the edge-speed split [km/h]: half the geometries each, at the two
                                 % ends of the envelope (dedicated test flights; the other splits draw over it)
N_WORKERS = 6;
MODEL_TAG = 'v7-D74';            % link model of the pools (seed streams, altitude, in-band cap)
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
C = decision_config();
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    SINGLES = {'none', 'jamming', 'path_loss', 'airframe_shadowing'}; COMBOS = {'jamming+path_loss', 'tone_jamming+path_loss'};
    EBNO = [3 12]; NGEO = [2 2 2 2 2]; NCOMB = [0 0 0 0 2];
    BLOCK(3:5) = [18 18 19];                            % blocks of its own: its flights are never test flights
end

D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', N.splits.norm.feat_mean, 'sd', N.splits.norm.feat_std, 'fs', p0.symbol_rate * p0.sps);
clear N
T = ood_thresholds(0.95);
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end   % temporal fusion (select_fusion.m)
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end                        % unknown-score window (eval_ood_detection.m)
ACTIONS = policy_actions();
scen = [SINGLES, COMBOS];
nA = numel(ACTIONS); nS = numel(EBNO);
vrange = [p0.speed_kmh_min p0.speed_kmh_max];

% Cells: (threat, severity index, level of a single threat, splits simulated); the
% edge-speed split holds the clean link and the single threats at nominal severity
nSp = numel(SPLITS);
iSpd = find(strcmp(SPLITS, 'speed'));
cells = struct('threat', {}, 'sev', {}, 'level', {}, 'splits', {});
for i = 1:numel(scen)
    t = scen{i};
    if strcmp(t, 'none')
        cells(end+1) = struct('threat', t, 'sev', C.nominal, 'level', NaN, 'splits', 1:nSp); %#ok<SAGROW>
    elseif contains(t, '+')
        for v = C.combo_sev
            cells(end+1) = struct('threat', t, 'sev', v, 'level', NaN, 'splits', setdiff(1:nSp, iSpd)); %#ok<SAGROW>
        end
    else
        for v = 1:numel(C.sev_names)
            sp_ = setdiff(1:nSp, iSpd); if v == C.nominal, sp_ = 1:nSp; end
            cells(end+1) = struct('threat', t, 'sev', v, 'level', C.sev.(t).levels(v), 'splits', sp_); %#ok<SAGROW>
        end
    end
end
nC = numel(cells);
nG = NGEO + NCOMB;                                      % geometries per split
r0 = arrayfun(@(sp) sum(nG(1:sp-1) .* (BLOCK(1:sp-1) == BLOCK(sp))), 1:nSp);   % splits sharing a block take consecutive geometries
runs = arrayfun(@(sp) 100 * BLOCK(sp) + r0(sp) + (1:nG(sp)), 1:nSp, 'UniformOutput', false);
% Geometries of every cell per split (positions in runs): the shared ones, or the
% combined threats' own where the split has them; the clean link flies all of them
for c = 1:nC
    cells(c).geo = cell(1, nSp);
    for sp = cells(c).splits
        if strcmp(cells(c).threat, 'none')
            cells(c).geo{sp} = 1:nG(sp);
        elseif contains(cells(c).threat, '+') && NCOMB(sp) > 0
            cells(c).geo{sp} = NGEO(sp) + (1:NCOMB(sp));
        else
            cells(c).geo{sp} = 1:NGEO(sp);
        end
    end
end
old = [];
if isfile('data/policy_pools.mat')
    Lo = load('data/policy_pools.mat', 'PP');
    if isfield(Lo.PP, 'model_tag') && strcmp(Lo.PP.model_tag, MODEL_TAG) ...
            && numel(Lo.PP.runs) == nSp && isequal(Lo.PP.runs(1:2), runs(1:2)) && ~isequal(Lo.PP.runs{3}, runs{3}) ...
            && isequal(Lo.PP.scen, {cells.threat}) && isequal(Lo.PP.sev, [cells.sev]) ...
            && isequal(Lo.PP.ebno, EBNO) && isequal(Lo.PP.actions, ACTIONS) && isequaln(Lo.PP.level, [cells.level])
        old = Lo.PP.pools(:, :, :, 1:2);
        for c = 1:nC, cells(c).splits = setdiff(cells(c).splits, 1:2); end
        fprintf('Train and validation pools kept; new test flights (block %d) only\n', BLOCK(3));
    end
    clear Lo
end

% Geometries: seeds, speeds, altitudes and K of our signal per (Eb/N0, split), shared
% by every cell that flies them (pool_geometries.m); the combined threats' own after
% the shared ones, as a design of their own
geo = cell(1, nS);
for s = 1:nS
    g = struct('seed', {}, 'speed', {}, 'run', {}, 'alt', {}, 'ksig', {});
    for sp = 1:nSp
        r = r0(sp) + (1:NGEO(sp));
        lhs = []; if LHS(sp), lhs = LHS_SEED + 100*s + sp; end
        if strcmp(SPLITS{sp}, 'speed')
            g(sp) = pool_geometries(s, BLOCK(sp), r, VOUT(1 + ((1:NGEO(sp))' > NGEO(sp) / 2), :), p0);
        else
            g(sp) = pool_geometries(s, BLOCK(sp), r, vrange, p0, lhs);
        end
        if NCOMB(sp) > 0
            if LHS(sp), lhs = lhs + 10; end
            gc = pool_geometries(s, BLOCK(sp), r0(sp) + NGEO(sp) + (1:NCOMB(sp)), vrange, p0, lhs);
            for f = fieldnames(gc)', g(sp).(f{1}) = [g(sp).(f{1}), gc.(f{1})]; end
        end
    end
    geo{s} = g;
end
spd = arrayfun(@(sp) cell2mat(arrayfun(@(s) geo{s}(sp).speed, (1:nS)', 'UniformOutput', false)), 1:nSp, ...
    'UniformOutput', false);                    % UAV speed of every geometry, Eb/N0 x geometry per split

% Every per-flight draw of every geometry as the link flies it (flight_draws.m, the GCS
% at the distance of the Eb/N0), Eb/N0 x geometry per split; align: |a_g' a_i|^2 / n^2
% of the steering vectors toward the GCS and toward each interferer
cv = cell(1, nSp);
ag = exp(-1j * 2*pi * p0.ant_spacing_wl * (0:p0.n_rx-1)' * sind(p0.gcs_aoa_deg));
for sp = 1:nSp
    z = nan(nS, nG(sp));
    V = struct('seed', z, 'speed', z, 'alt_m', z, 'k_sig', z, 'k_int', z, 'yaw', z, 'rho', z, ...
        'gcs_point_db', z, 'el_db', z, 'aoa', nan(nS, nG(sp), 3), 'align', nan(nS, nG(sp), 3));
    for s = 1:nS
        g = geo{s}(sp);
        for r = 1:nG(sp)
            fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
            d = flight_draws(g.seed(r), fd, p0, struct('ebno', EBNO(s), 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r)));
            V.seed(s, r) = g.seed(r); V.speed(s, r) = g.speed(r); V.alt_m(s, r) = d.alt_m;
            V.k_sig(s, r) = d.k_sig; V.k_int(s, r) = d.k_int; V.yaw(s, r) = d.yaw; V.rho(s, r) = d.rho;
            V.gcs_point_db(s, r) = d.gcs_point_db; V.el_db(s, r) = d.el_db;
            ni = min(3, numel(d.aoa));
            ai = exp(-1j * 2*pi * p0.ant_spacing_wl * (0:p0.n_rx-1)' * sind(d.aoa(1:ni)));
            V.aoa(s, r, 1:ni) = d.aoa(1:ni);
            V.align(s, r, 1:ni) = abs(ag' * ai).^2 / p0.n_rx^2;
        end
    end
    cv{sp} = V;
end
fprintf('Geometries per Eb/N0 | speed [km/h] | altitude [m] | K of our signal [dB] | largest |heading rate| [deg/s]:\n');
for sp = 1:nSp
    V = cv{sp};
    fprintf('  %-6s %3d (block %d) | %5.1f-%5.1f | %5.1f-%5.1f | %5.1f-%5.1f | %.1f\n', SPLITS{sp}, nG(sp), BLOCK(sp), ...
        min(V.speed(:)), max(V.speed(:)), min(V.alt_m(:)), max(V.alt_m(:)), min(V.k_sig(:)), max(V.k_sig(:)), ...
        max(abs(V.yaw(:))));
end
hv = cv{iSpd}.speed == 0;
fprintf('  hover flights (edge speeds): %d per Eb/N0, largest |heading rate| %.2f deg/s\n', sum(hv(1, :)), ...
    max(abs(cv{iSpd}.yaw(hv))));

% Geometries of every cell per Eb/N0: its splits, in each its geometries
geoc = cell(1, nC);
for c = 1:nC
    gc = cell(1, nS);
    for s = 1:nS
        g = geo{s}(cells(c).splits);
        for k = 1:numel(g)
            j = cells(c).geo{cells(c).splits(k)};
            for f = fieldnames(g)', g(k).(f{1}) = g(k).(f{1})(j); end
        end
        gc{s} = g;
    end
    geoc{c} = gc;
end

%% 2. Simulation, one parallel job per cell
NWP = N_WORKERS;
if exist('SMOKE', 'var') && SMOKE
    NWP = 0;                                            % reduced chain check: on this process, no parallel turn
else
    turn = []; parallel_turn('take'); turn = onCleanup(@() parallel_turn('give'));   % one heavy parallel stage at a time on this computer
    pl = gcp('nocreate');
    if isempty(pl) || pl.NumWorkers ~= N_WORKERS
        delete(pl); pl = parpool('Processes', N_WORKERS);
    end
    repo = pwd;
    spmd
        pool_worker_init(repo);
    end
end
results = cell(1, nC); nuniq = zeros(1, nC);
t0 = tic;
fprintf('%d cells x %d configurations x %d Eb/N0 on %d workers\n', nC, nA, nS, N_WORKERS);
parfor (c = 1:nC, NWP)
    ce = cells(c);
    p = threat_params(p0, ce.threat, ce.sev, C);
    [Ps, pinfo] = pool_cell(p, ce.threat, ACTIONS, EBNO, geoc{c}, det, opt);
    Pc = cell(nS, nA, nSp);
    Pc(:, :, ce.splits) = Ps;
    nuniq(c) = pinfo.n_unique;
    results{c} = Pc;
    fprintf('  cell %2d/%d %-28s %-8s %2d unique configurations\n', c, nC, ce.threat, C.sev_names{ce.sev}, nuniq(c));
end
fprintf('Simulated in %.1f min\n', toc(t0) / 60);

%% 3. Package
pools = cell(nC, nS, nA, nSp);
for c = 1:nC, pools(c, :, :, :) = results{c}; end
if ~isempty(old), pools(:, :, :, 1:2) = old; end
clear results old
mber = nan(nC, nS, nA, nSp); mfer = nan(nC, nS, nA, nSp);
for c = 1:nC
    for s = 1:nS
        for a = 1:nA
            for sp = 1:nSp
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
    'splits', {SPLITS}, 'cell_splits', {{cells.splits}}, 'cell_geo', {{cells.geo}}, 'threats', {scen}, 'singles', {SINGLES}, ...
    'combos', {COMBOS}, 'ebno', EBNO, 'actions', {ACTIONS}, 'ngeo', NGEO, 'ncomb', NCOMB, 'lhs', LHS, ...
    'speed_range', vrange, 'speed_out', VOUT, 'speed', {spd}, 'cov', {cv}, ...
    'alt', {cellfun(@(V) V.alt_m, cv, 'UniformOutput', false)}, 'ksig', {cellfun(@(V) V.k_sig, cv, 'UniformOutput', false)}, ...
    'gp', gp, 'bw', bw, 'pw', pw, 'pools', {pools}, 'mber', mber, 'mfer', mfer, ...
    'clean', clean_ref.ber, 'clean_fer', clean_ref.fer, 'classes', {det.classes}, 'maha_thr', T.maha, ...
    'fuse', FZ.FM, 'fuse_N', FZ.N, 'unk_win', UW, ...
    'F_SUB', opt.F_SUB, 'runs', {runs}, 'model_tag', MODEL_TAG, ...
    'aoa_random', p0.int_aoa_random, 'k_random', p0.k_random, 'sps', p0.sps, 'bps', p0.bits_per_symbol, ...
    'feat_names', {link_features('names')}, 'created', datestr(now));
save('data/policy_pools.mat', 'PP', 'clean_ref', '-v7.3');

fprintf('\nClean link per Eb/N0: BER %s | estimated BER %s | packet loss %s\n', sprintf('%.1e ', clean_ref.ber), ...
    sprintf('%.1e ', clean_ref.ber_est), sprintf('%.2f ', clean_ref.plr));
fprintf('Unmitigated BER / clean, nominal severity (train split):\n');
for c = find([cells.sev] == C.nominal & ~strcmp({cells.threat}, 'none') & ~contains({cells.threat}, '+'))
    fprintf('  %-22s %s\n', cells(c).threat, sprintf('%9.1f', squeeze(mber(c, :, na, 1)) ./ max(PP.clean, C.ber_floor)));
end
fprintf('Saved data/policy_pools.mat (%.1f min)\n', toc(t0) / 60);
clear pools PP
