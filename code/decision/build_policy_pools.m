%% BUILD_POLICY_POOLS - Measured frame pools for the decision layer
% Every threat cell x configuration x Eb/N0 x geometry through the real link, with
% the detector already applied, so the decision-layer environment (link_env.m)
% never runs Simulink inside the learning loop.
%
% Cells: the clean link; the 10 single threats at five severities
% (decision_config.m); the 14 combined threats (pairs and triples), each component
% at three severities (C.combo_sev), in the train, validation and test splits (a
% combination never trained on is measured by experiment_combo_generalization.m).
% Configurations: the 36 of policy_actions.m, applied by apply_countermeasure.m;
% configurations with identical physics for a threat are simulated once
% (pool_cell.m). Eb/N0: the grid of init_params.
% Splits, geometries per (cell, Eb/N0): train 8, validation 6, test 12; edge speeds
% 24 at hover for the clean link and the single threats at every severity, and 12 at
% 161 km/h (the limit of small UAVs, Khawaja et al.) for the clean link and the
% nominal severity; second test 60 for the clean link and the single threats, 72 per
% point with the test (each cell's geometries per split: PP.cell_geo). The test and
% second test geometries are nested Latin hypercubes over speed, altitude, K of our
% signal, the direction of the first interferer and the receive correlation
% (pool_geometries.m): 2 + 10 flights per sixth of the speed range and 4 + 20 per third
% of the altitude range at every Eb/N0.
% A geometry (seed: fading and its K-factors, UAV speed and altitude, interferer
% directions, threat waveform) is shared by every configuration and every cell that
% flies it, the clean link included (common random numbers), so an episode's frames
% before and after the onset come from one flight; a geometry is never shared by two
% splits. Seeds: pool_seed.m. Per geometry, every per-flight draw (flight_draws.m) is
% kept in PP.cov.
% Airframe shadowing is on the air only while the attitude hides an antenna in a turn whose
% bank its level is measured at (shadow_frame.m), on a minority of the shared flights. A cell
% holding it (alone or in a combination) therefore flies geometries of its own, as many per
% split as the cells it stands beside (pool_layout.m). On them the UAV rolls into its turn
% so that the airframe enters the line of sight just before frame C.event_frame of a run of
% C.event_run frames (flight_draws.m, geo.event_frame; the clean link of the same flight
% before it, the same timeline for every cell that flies it): the shadowing ramps in as the
% roll grows, and an episode's onset reads that frame (link_env.m, PP.event_frame). They are
% selected from the flights' draws before they are simulated so that the event starts during
% the roll-in and counts (its loss at least p.shadow_evt_db at the group's lowest level) by
% frame C.event_count (hides_antenna.m, as the dataset selects its flights): candidates of their own seed
% range (shadow_pool_seed.m), tried in turn, each in the flight's strata of the Latin
% hypercube of its split, over the speeds at which the level can occur (from
% p.shadow_v_min, and from the speed whose turn reaches its smallest roll,
% shadow_speed_floor.m); levels flown at the same rolls share them (shadow_groups.m). The clean
% link flies them too, only as their restoration reference and lead-in (PP.ref_geo), never
% as clean-link flights of a statistic. At the edge speeds shadowing flies the 161 km/h
% flights of the nominal level only: no source measures it at hover. The share of the
% candidates that hide an antenna is kept (PP.shadow): the shadowing points are conditioned
% on a geometry that hides one.
% Per frame: detector class probabilities, unknown-threat score, the link
% features of link_features.m (receiver measurements only), and the true BER and
% frame error (reward and evaluation only).
% The cells run in parallel, each worker in its own folder with its own copy of
% the model. When data/policy_pools.mat holds the same train and validation
% geometries of the same link model (MODEL_TAG) and only the test block differs, only
% the test, edge-speed and second test splits are simulated. PP.det_id identifies the
% detector (detector_id.m); pools of another detector are never reused.
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
NGEO   = [8 6 12 36 60];         % geometries per (cell, Eb/N0): train, validation, test, edge speeds, second test
NHOVER = 24;                     % edge speeds: the first NHOVER at hover (every severity), the rest at 161 km/h (nominal)
NCOMB  = [0 0 0 0 24];           % own geometries of the combined threats (0: they fly the split's geometries);
                                 % second test: 12 + 24 = 36 flights per point, the N_MIN of a verdict
BLOCK  = [1 5 14 16 17];         % pool_seed.m block of each split (pool_seed.m lists every block)
SPLITS = {'train', 'val', 'test', 'speed', 'test2'};
LHS    = [false false true false true];   % splits laid out as nested Latin hypercubes (pool_geometries.m)
LHS_SEED = 7100000;              % permutation stream of a design: LHS_SEED + 100 (Eb/N0 index) + split (+ 10: combined threats;
                                 % + 10 (shadowing group + 1), + 5 more for its combined threats' own)
J_MAX  = 99999;                  % candidates per (shadowing group, Eb/N0, seed block), shadow_pool_seed.m
VOUT   = [0 0; 161 161];         % speeds of the edge-speed split [km/h]: the first NHOVER geometries and the rest, at
                                 % the two ends of the envelope (dedicated test flights; the other splits draw over it)
N_WORKERS = 6;
MODEL_TAG = 'v7-D85';            % link model of the pools: train and validation splits are reused only under the same tag
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
C = decision_config();
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    SINGLES = {'none', 'jamming', 'path_loss', 'airframe_shadowing'};
    COMBOS = {'jamming+path_loss', 'tone_jamming+path_loss', 'jamming+airframe_shadowing'};
    EBNO = [3 12]; NGEO = [2 2 2 2 2]; NCOMB = [0 0 0 0 2]; NHOVER = 1;
    BLOCK(3:5) = [18 18 19];                            % blocks of its own: its flights are never test flights
end

D = load('data/trained_detector.mat', 'net', 'classes', 'ood', 'trained_at');
N = load('data/splits.mat', 'splits');
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', N.splits.norm.feat_mean, 'sd', N.splits.norm.feat_std, 'fs', p0.symbol_rate * p0.sps);
clear N
T = ood_thresholds(0.95);
FZ = fusion_model();                                   % temporal fusion, the rule's quiet-slot alarm (select_fusion.m)
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end                        % unknown-score window (eval_ood_detection.m)
DET_ID = detector_id(D.trained_at, D.ood, FZ, T.maha);
ACTIONS = policy_actions();
scen = [SINGLES, COMBOS];
nA = numel(ACTIONS); nS = numel(EBNO);
vrange = [p0.speed_kmh_min p0.speed_kmh_max];

% Cells: (threat, severity index, level of a single threat); the edge-speed and second
% test splits hold the clean link and the single threats
nSp = numel(SPLITS);
iSpd = find(strcmp(SPLITS, 'speed'));
cells = struct('threat', {}, 'sev', {}, 'level', {});
for i = 1:numel(scen)
    t = scen{i};
    if strcmp(t, 'none')
        cells(end+1) = struct('threat', t, 'sev', C.nominal, 'level', NaN); %#ok<SAGROW>
    elseif contains(t, '+')
        for v = C.combo_sev
            cells(end+1) = struct('threat', t, 'sev', v, 'level', NaN); %#ok<SAGROW>
        end
    else
        for v = 1:numel(C.sev_names)
            cells(end+1) = struct('threat', t, 'sev', v, 'level', C.sev.(t).levels(v)); %#ok<SAGROW>
        end
    end
end
nC = numel(cells);
% In-band cap (build_threat_model.m): the combined cells whose in-band component with the
% path loss on top would exceed it over our received signal
capped = {};
for c = find(contains({cells.threat}, '+') & contains({cells.threat}, 'path_loss'))
    pc = threat_params(p0, cells(c).threat, cells(c).sev, C);
    for q = setdiff(strsplit(cells(c).threat, '+'), {'path_loss', 'antenna_fault', 'airframe_shadowing'})
        L = pc.(C.sev.(q{1}).field);
        if L + pc.path_loss_db > p0.inband_cap_db
            capped{end+1} = sprintf('%s %s: %s %g dB + path loss %g dB -> %g dB', cells(c).threat, ...
                C.sev_names{cells(c).sev}, q{1}, L, pc.path_loss_db, p0.inband_cap_db); %#ok<SAGROW>
        end
    end
end
fprintf('In-band cap %g dB over our received signal (before pointing and elevation loss): %d combined cells\n%s', ...
    p0.inband_cap_db, numel(capped), sprintf('  %s\n', capped{:}));
% Airframe shadowing: the level of every cell holding it, the groups flown at the same rolls
% (shadow_groups.m), the speeds at which each group's levels can occur (shadow_speed_floor.m)
shd_db = nan(1, nC);
for c = find(contains({cells.threat}, 'airframe_shadowing'))
    shd_db(c) = threat_params(p0, cells(c).threat, cells(c).sev, C).shadow_db;
end
[grp, gband, glv] = shadow_groups(shd_db, p0);
nGr = numel(glv);
assert(nGr <= 7, 'build_policy_pools: %d shadowing groups; the permutation streams hold 7', nGr);
vshd = [max(vrange(1), shadow_speed_floor(gband, p0)), repmat(vrange(2), nGr, 1)];   % [km/h] per group: where it can occur
% Geometries of every cell per split (positions in runs): the shared ones, the combined
% threats' own where the split has them, at the edge speeds only the hover ones away from
% the nominal severity, the shadowing groups' own (pool_layout.m); the clean link flies the
% shared and combined ones, and the groups' own as their reference (ref)
kind = 1 + contains({cells.threat}, '+'); kind(strcmp({cells.threat}, 'none')) = 0;
[cg, ref, nG, parts] = pool_layout(kind, grp, [cells.sev], C.nominal, NGEO, NCOMB, NHOVER, iSpd);
for c = 1:nC
    cells(c).geo = cg{c};
    cells(c).splits = find(~cellfun(@isempty, cg{c}));
end
r0 = arrayfun(@(sp) sum(nG(1:sp-1) .* (BLOCK(1:sp-1) == BLOCK(sp))), 1:nSp);   % splits sharing a block take consecutive geometries
runs = arrayfun(@(sp) 100 * BLOCK(sp) + r0(sp) + (1:nG(sp)), 1:nSp, 'UniformOutput', false);
old = [];
if isfile('data/policy_pools.mat')
    Lo = load('data/policy_pools.mat', 'PP');
    if isfield(Lo.PP, 'model_tag') && strcmp(Lo.PP.model_tag, MODEL_TAG) && isfield(Lo.PP, 'det_id') ...
            && strcmp(Lo.PP.det_id, DET_ID) ...
            && numel(Lo.PP.runs) == nSp && isequal(Lo.PP.runs(1:2), runs(1:2)) && ~isequal(Lo.PP.runs{3}, runs{3}) ...
            && isequal(Lo.PP.scen, {cells.threat}) && isequal(Lo.PP.sev, [cells.sev]) ...
            && isequal(Lo.PP.ebno, EBNO) && isequal(Lo.PP.actions, ACTIONS) && isequaln(Lo.PP.level, [cells.level])
        old = Lo.PP.pools(:, :, :, 1:2);
        for c = 1:nC, cells(c).splits = setdiff(cells(c).splits, 1:2); end
        fprintf('Train and validation pools kept; new test flights (block %d) only\n', BLOCK(3));
    end
    clear Lo
end

% Geometries: seeds, speeds, altitudes, K of our signal, first interferer direction and
% receive correlation per (Eb/N0, split), shared by every cell that flies them
% (pool_geometries.m); the combined threats' own after the shared ones, as a design of
% their own; then every shadowing group's own, each a design of its own whose flights are
% the first candidates in their strata whose roll-in lets the airframe hide an antenna, the
% loss of the group's lowest level counting by frame C.event_count (shadow_pool_seed.m,
% hides_antenna.m: at the Eb/N0's distance); the edge speeds' at 161 km/h
pS = cell(1, nGr);                                      % the selection's params of every group
for k = 1:nGr
    pS{k} = p0; pS{k}.active_threat = 'airframe_shadowing'; pS{k}.shadow_db = min(shd_db(grp == k));
end
SH = struct('band', gband, 'level', glv, 'cell_levels', {arrayfun(@(k) unique(shd_db(grp == k)), 1:nGr, ...
    'UniformOutput', false)}, 'cell_group', grp, 'v_kmh', vshd, 'speed_range', vrange, ...
    'tried', zeros(nGr, nSp, nS), 'kept', zeros(nGr, nSp, nS));
geo = cell(1, nS);
for s = 1:nS
    g = struct('seed', {}, 'speed', {}, 'run', {}, 'alt', {}, 'ksig', {}, 'aoa1', {}, 'rho', {});
    for sp = 1:nSp
        r = r0(sp) + (1:NGEO(sp));
        lhs = []; if LHS(sp), lhs = LHS_SEED + 100*s + sp; end
        if strcmp(SPLITS{sp}, 'speed')
            g(sp) = pool_geometries(s, BLOCK(sp), r, VOUT(1 + ((1:NGEO(sp))' > NHOVER), :), p0);
        else
            g(sp) = pool_geometries(s, BLOCK(sp), r, vrange, p0, lhs);
        end
        if NCOMB(sp) > 0
            if LHS(sp), lhs = lhs + 10; end
            gc = pool_geometries(s, BLOCK(sp), r0(sp) + NGEO(sp) + (1:NCOMB(sp)), vrange, p0, lhs);
            for f = fieldnames(gc)', g(sp).(f{1}) = [g(sp).(f{1}), gc.(f{1})]; end
        end
    end
    jc = zeros(nGr, max(BLOCK));                        % last candidate of every (group, seed block)
    for k = 1:numel(parts)
        P = parts(k); sp = P.split; gi = P.group; n = numel(P.pos); b = BLOCK(sp);
        lhs = []; vr = vshd(gi, :);
        if sp == iSpd
            vr = repmat(VOUT(2, :), n, 1);
        elseif LHS(sp)
            lhs = LHS_SEED + 100*s + 10 * (gi + 1) + sp + 5 * (P.part - 1);
        end
        ps = pS{gi}; eb = EBNO(s);
        sel = struct('seed', @(j, v) shadow_pool_seed(gi, s, b, j, v), 'j0', jc(gi, b), 'jmax', J_MAX, ...
            'keep', @(sd, v, a, kk, o, c) hides_antenna(sd, v, ps, struct('ebno', eb, 'alt_m', a, 'k_sig_db', kk, ...
            'aoa1_deg', o, 'rho', c, 'event_frame', C.event_frame, 'frames', C.event_count)));
        [gk, info] = pool_geometries(s, b, r0(sp) + P.pos, vr, p0, lhs, 1, sel);
        jc(gi, b) = info.j;
        SH.tried(gi, sp, s) = SH.tried(gi, sp, s) + sum(info.tries); SH.kept(gi, sp, s) = SH.kept(gi, sp, s) + n;
        for f = fieldnames(gk)', g(sp).(f{1}) = [g(sp).(f{1}), gk.(f{1})]; end
    end
    for sp = 1:nSp                                      % the groups' flights roll in: longer runs, the event's frame
        n = numel(g(sp).seed);
        g(sp).frames = opt.F_SUB * ones(1, n); g(sp).event = nan(1, n);
        g(sp).frames(ref{sp}) = C.event_run; g(sp).event(ref{sp}) = C.event_frame;
    end
    geo{s} = g;
end
evf = arrayfun(@(sp) geo{1}(sp).event, 1:nSp, 'UniformOutput', false);   % the event's frame per split geometry
if nGr > 0
    fprintf(['Airframe shadowing: own flights of %d groups of levels (shadow_groups.m), every one hiding an antenna at ' ...
        'its level; none below %g m/s or at hover (no source measures it there), nor below the speed whose turn ' ...
        'reaches the level''s smallest roll (shadow_speed_floor.m):\n'], nGr, p0.shadow_v_min);
    for k = 1:nGr
        sk = find(sum(SH.tried(k, :, :), 3) > 0);
        fprintf('  %s dB, rolls %.1f-%.1f deg, from %.1f km/h, %d cells | kept of the candidates tried: %s\n', ...
            strjoin(compose('%g', unique(shd_db(grp == k))), '/'), gband(k, :), vshd(k, 1), sum(grp == k), ...
            strjoin(arrayfun(@(sp) sprintf('%s %d/%d', SPLITS{sp}, sum(SH.kept(k, sp, :)), sum(SH.tried(k, sp, :))), sk, ...
            'UniformOutput', false), ' | '));
    end
end
spd = arrayfun(@(sp) cell2mat(arrayfun(@(s) geo{s}(sp).speed, (1:nS)', 'UniformOutput', false)), 1:nSp, ...
    'UniformOutput', false);                    % UAV speed of every geometry, Eb/N0 x geometry per split

% Every per-flight draw of every geometry as the link flies it (flight_draws.m, the GCS
% at the distance of the Eb/N0), Eb/N0 x geometry per split; align: |a_g' a_i|^2 / n^2
% of the steering vectors toward the GCS and toward each interferer; body_spread_db: the
% spread of the airframe loss over the antennas; jam: sweep period [s], sweep phase [s]
% and burst phase of the gated jammers; ds_ns, ds_int: RMS delay spread of our signal and
% of each interferer [ns] (0 on a flat channel); roll_in: the roll-in's start [s], rate
% [deg/s] and the roll at the event's start [deg] (0 0 0 without one)
cv = cell(1, nSp);
for sp = 1:nSp
    z = nan(nS, nG(sp));
    V = struct('seed', z, 'speed', z, 'alt_m', z, 'k_sig', z, 'k_int', z, 'yaw', z, 'rho', z, ...
        'gcs_point_db', z, 'el_db', z, 'aoa', nan(nS, nG(sp), 3), 'align', nan(nS, nG(sp), 3), ...
        'gcs_aoa', z, 'el_deg', z, 'bank', z, 'roll', z, 'pitch', z, 'wob', z, 'att_db', z, 'body_spread_db', z, ...
        'jam', nan(nS, nG(sp), 4), 'ds_ns', z, 'ds_int', nan(nS, nG(sp), 3), 'roll_in', nan(nS, nG(sp), 3));
    for s = 1:nS
        g = geo{s}(sp);
        for r = 1:nG(sp)
            fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
            d = flight_draws(g.seed(r), fd, p0, struct('ebno', EBNO(s), 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
                'aoa1_deg', g.aoa1(r), 'rho', g.rho(r), 'event_frame', g.event(r), 'frames', g.frames(r)));
            V.roll_in(s, r, :) = d.roll_in;
            V.seed(s, r) = g.seed(r); V.speed(s, r) = g.speed(r); V.alt_m(s, r) = d.alt_m;
            V.k_sig(s, r) = d.k_sig; V.k_int(s, r) = d.k_int; V.yaw(s, r) = d.yaw; V.rho(s, r) = d.rho;
            V.gcs_point_db(s, r) = d.gcs_point_db; V.el_db(s, r) = d.el_db;
            ni = min(3, numel(d.aoa));
            V.aoa(s, r, 1:ni) = d.aoa(1:ni);
            V.align(s, r, 1:ni) = d.align(1:ni);
            V.gcs_aoa(s, r) = d.gcs_aoa; V.el_deg(s, r) = d.el_deg; V.bank(s, r) = d.bank;
            V.roll(s, r) = d.roll; V.pitch(s, r) = d.pitch; V.wob(s, r) = d.wobble(1);
            V.att_db(s, r) = d.att_db; V.body_spread_db(s, r) = max(d.body_db) - min(d.body_db);
            V.jam(s, r, :) = d.jam;
            V.ds_ns(s, r) = d.ds_ns(1); V.ds_int(s, r, 1:ni) = d.ds_ns(1 + (1:ni));
        end
    end
    cv{sp} = V;
end
fprintf(['Geometries per Eb/N0 | speed [km/h] | altitude [m] | K of our signal [dB] | largest |heading rate| [deg/s] ' ...
    '| largest bank [deg]:\n']);
for sp = 1:nSp
    V = cv{sp};
    fprintf('  %-6s %3d (block %d) | %5.1f-%5.1f | %5.1f-%5.1f | %5.1f-%5.1f | %.1f | %.1f\n', SPLITS{sp}, nG(sp), BLOCK(sp), ...
        min(V.speed(:)), max(V.speed(:)), min(V.alt_m(:)), max(V.alt_m(:)), min(V.k_sig(:)), max(V.k_sig(:)), ...
        max(abs(V.yaw(:))), max(V.bank(:)));
end
hv = cv{iSpd}.speed == 0;
fprintf('  hover flights (edge speeds): %d per Eb/N0, largest |heading rate| %.2f deg/s, largest |pitch wobble| %.1f deg\n', ...
    sum(hv(1, :)), max(abs(cv{iSpd}.yaw(hv))), max(abs(cv{iSpd}.wob(hv))));

% Geometries of every cell per Eb/N0: its splits, in each its geometries (the clean link
% also the shadowing groups' own)
geoc = cell(1, nC);
for c = 1:nC
    gc = cell(1, nS);
    for s = 1:nS
        g = geo{s}(cells(c).splits);
        for k = 1:numel(g)
            sp = cells(c).splits(k);
            j = cells(c).geo{sp};
            if kind(c) == 0, j = [j, ref{sp}]; end %#ok<AGROW>
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
ic = find(strcmp({cells.threat}, 'none'));
own = @(Q, sp) ismember(Q.run, runs{sp}(cells(ic).geo{sp}));   % the clean link's own flights, not the shadowing reference
mber = nan(nC, nS, nA, nSp); mfer = nan(nC, nS, nA, nSp);
for c = 1:nC
    for s = 1:nS
        for a = 1:nA
            for sp = 1:nSp
                Q = pools{c, s, a, sp};
                if isempty(Q) || isempty(Q.ber), continue; end
                k = event_rows(Q, runs{sp}, evf{sp}); if c == ic, k = own(Q, sp); end   % a rolling-in flight from its event's frame
                mber(c, s, a, sp) = mean(Q.ber(k)); mfer(c, s, a, sp) = mean(Q.fer(k));
            end
        end
    end
end
na = find(strcmp(ACTIONS, 'no_action')); nf = find(strcmp(ACTIONS, 'fec_interleave'));
cq = pools(ic, :, na, 1);
clean_ref = struct('ebno', EBNO, 'ber', squeeze(mber(ic, :, na, 1)), 'fer', squeeze(mfer(ic, :, na, 1)), ...
    'ber_est', cellfun(@(Q) mean(10.^double(Q.feat(own(Q, 1), feature_index('log_ber')))), cq), ...
    'plr', cellfun(@(Q) mean(double(Q.crc(own(Q, 1))), 'omitnan'), cq), ...
    'plr_fec', cellfun(@(Q) mean(double(Q.crc(own(Q, 1))), 'omitnan'), pools(ic, :, nf, 1)));
% Every flight of a shadowing cell hides an antenna in some frame of its run, as selected
SH.on = zeros(1, 2);                                    % flights with the shadowing component on the air, flights
for c = find(grp > 0)
    k = find(strcmp(strsplit(cells(c).threat, '+'), 'airframe_shadowing'));
    for s = 1:nS
        for sp = cells(c).splits
            Q = pools{c, s, na, sp};
            if isempty(Q) || isempty(Q.run), continue; end
            [~, ~, ir] = unique(Q.run);
            on = accumarray(ir, double(Q.act_comp(:, k)), [], @max) > 0;
            SH.on = SH.on + [sum(on), numel(on)];
        end
    end
end
if nGr > 0
    fprintf('Airframe shadowing on the air in %d of the %d flights of its cells\n', SH.on);
    if SH.on(1) < SH.on(2)
        warning('build_policy_pools:shadow', '%d flights of the shadowing cells hide no antenna in the model', SH.on(2) - SH.on(1));
    end
end
gp = ones(1, nA); bw = ones(1, nA); pw = ones(1, nA);
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', ACTIONS{a});
    gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor; pw(a) = cm.power_factor;
end
PP = struct('scen', {{cells.threat}}, 'sev', [cells.sev], 'level', [cells.level], 'sev_names', {C.sev_names}, ...
    'splits', {SPLITS}, 'cell_splits', {{cells.splits}}, 'cell_geo', {{cells.geo}}, 'ref_geo', {ref}, 'shadow', SH, ...
    'threats', {scen}, 'singles', {SINGLES}, ...
    'combos', {COMBOS}, 'ebno', EBNO, 'actions', {ACTIONS}, 'ngeo', NGEO, 'ncomb', NCOMB, 'nhover', NHOVER, 'lhs', LHS, ...
    'speed_range', vrange, 'speed_out', VOUT, 'speed', {spd}, 'cov', {cv}, ...
    'alt', {cellfun(@(V) V.alt_m, cv, 'UniformOutput', false)}, 'ksig', {cellfun(@(V) V.k_sig, cv, 'UniformOutput', false)}, ...
    'gp', gp, 'bw', bw, 'pw', pw, 'cfg_gain_db', config_gain_db(ACTIONS, p0), 'pools', {pools}, 'mber', mber, 'mfer', mfer, ...
    'clean', clean_ref.ber, 'clean_fer', clean_ref.fer, 'classes', {det.classes}, 'maha_thr', T.maha, ...
    'fuse', FZ.FM, 'fuse_N', FZ.N, 'q_thr', FZ.q_thr, 'unk_win', UW, ...
    'F_SUB', opt.F_SUB, 'event_frame', {evf}, 'fec_frames', p0.fec_frames, 'runs', {runs}, 'model_tag', MODEL_TAG, ...
    'det_id', DET_ID, 'aoa_random', p0.int_aoa_random, 'k_random', p0.k_random, 'sps', p0.sps, 'bps', p0.bits_per_symbol, ...
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
