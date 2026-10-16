%% BUILD_CHECK_POOLS - Off-grid check flights of the decision layer (test only)
% The decision layer trains and is read on the Eb/N0 grid and the five levels of
% decision_config.m; an "up to" edge of edge_map.m spans points between them that no
% closed-loop flight reaches otherwise. These pools fly them, for the edge map only
% (never in training, selection or the KPIs):
%   between the Eb/N0 points (the midpoints of the grid), every single threat at the
%   nominal severity, with the clean link as its restoration reference;
%   between the levels, the midpoint of every two neighbouring levels of every single
%   threat at E_LEVEL (the middle of the grid), with the clean link there.
% 36 flights per point (N_MIN of edge_verdict.m), laid out as a Latin hypercube like the
% test splits (pool_geometries.m, permutation streams LHS_SEED + 100 Eb/N0 index),
% seeds of their own geometry family (pool_seed.m family 2, block 10); every
% configuration through the real link (pool_cell.m) with the detector of the frame pools
% (det_id must match data/policy_pools.mat). Rule (edge_map.m): an "up to" claim that
% spans a check point holds only if that point is not NOT COMMITTED.
% Airframe shadowing flies 36 flights of its own per point, as in the frame pools
% (build_policy_pools.m): a design of their own per group of levels flown at the same
% rolls (shadow_groups.m), each flight the first candidate in its strata whose roll-in lets
% the airframe hide an antenna just before frame C.event_frame of a run of C.event_run
% frames, the loss at the group's lowest level counting by frame C.event_count
% (hides_antenna.m, shadow_pool_seed.m in block 10), over the speeds at which the level can
% occur (shadow_speed_floor.m); the clean link flies them too, only as their restoration
% reference and lead-in (CK.ref_geo) where a group's cells fly; CK.event_frame as PP's.
%
% Output: data/check_pools.mat (CK: the fields of a PP with one split, the check
% flights; CK.kind per cell: 'clean', 'ebno' or 'level')

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Off-grid check pools ===\n\n');

%% 1. Configuration
C = decision_config();
S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true;
N_GEO = 36;                      % flights per check point
FAM = 2; BLOCK = 10;             % pool_seed.m geometry family and seed block of the check flights
LHS_SEED = 7200000;              % permutation stream of a design: LHS_SEED + 100 (Eb/N0 index) (+ shadowing group)
J_MAX = 99999;                   % candidates per (shadowing group, check Eb/N0), shadow_pool_seed.m
E_LEVEL = 9;                     % [dB] Eb/N0 of the level midpoints
N_WORKERS = 6;
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
THREATS = setdiff(PP.singles, {'none'}, 'stable');
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    THREATS = THREATS(unique([1 find(strcmp(THREATS, 'airframe_shadowing'))])); N_GEO = 2;
end
EGRID = PP.ebno; ACTIONS = PP.actions; opt.F_SUB = PP.F_SUB; vrange = PP.speed_range;
EMID = (EGRID(1:end-1) + EGRID(2:end)) / 2;             % between the Eb/N0 points
EB = unique([EMID, E_LEVEL]);                           % check Eb/N0 points
iM = find(ismember(EB, EMID)); iL = find(EB == E_LEVEL);
nS = numel(EB); nA = numel(ACTIONS);
D = load('data/trained_detector.mat', 'net', 'classes', 'ood', 'trained_at');
N = load('data/splits.mat', 'splits');
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', N.splits.norm.feat_mean, 'sd', N.splits.norm.feat_std, 'fs', p0.symbol_rate * p0.sps);
clear N
T = ood_thresholds(0.95);
FZ = fusion_model();
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end
DET_ID = detector_id(D.trained_at, D.ood, FZ, T.maha);
if ~isfield(PP, 'det_id') || ~strcmp(PP.det_id, DET_ID)
    error('build_check_pools: data/policy_pools.mat comes from another detector; rerun C1p first');
end

% Cells: the clean link at every check Eb/N0; every single threat at the nominal level
% between the Eb/N0 points; every level midpoint at E_LEVEL
cells = struct('threat', 'none', 'kind', 'clean', 'sev', C.nominal, 'level', NaN, 'ebs', 1:nS);
for t = THREATS
    lv = C.sev.(t{1}).levels;
    cells(end+1) = struct('threat', t{1}, 'kind', 'ebno', 'sev', C.nominal, 'level', lv(C.nominal), 'ebs', iM); %#ok<SAGROW>
    for k = 1:numel(lv) - 1
        cells(end+1) = struct('threat', t{1}, 'kind', 'level', 'sev', k + 0.5, 'level', (lv(k) + lv(k + 1)) / 2, 'ebs', iL); %#ok<SAGROW>
    end
end
nC = numel(cells);
% Airframe shadowing: groups of levels flown at the same rolls (shadow_groups.m), each with
% N_GEO flights of its own after the shared ones, at the check Eb/N0 its cells fly
shd_db = nan(1, nC);
ics = find(strcmp({cells.threat}, 'airframe_shadowing'));
shd_db(ics) = [cells(ics).level];
[grp, gband, glv] = shadow_groups(shd_db, p0);
nGr = numel(glv);
gpos = arrayfun(@(k) N_GEO * k + (1:N_GEO), 1:nGr, 'UniformOutput', false);   % positions of every group's flights
gebs = arrayfun(@(k) unique([cells(grp == k).ebs]), 1:nGr, 'UniformOutput', false);
cg = repmat({{1:N_GEO}}, 1, nC);
for c = find(grp > 0), cg{c} = gpos(grp(c)); end
ref = [gpos{:}];
N_TOT = N_GEO * (1 + nGr);
vshd = [max(vrange(1), shadow_speed_floor(gband, p0)), repmat(vrange(2), nGr, 1)];   % [km/h] per group: where it can occur
runs = 100 * BLOCK + (1:N_TOT);
f_out = 'data/check_pools.mat';
if isfile(f_out) && dir(f_out).datenum > dir('data/policy_pools.mat').datenum
    Cx = load(f_out, 'CK');
    if isequal(Cx.CK.runs{1}, runs) && isequal(Cx.CK.ebno, EB) && isequal(Cx.CK.actions, ACTIONS) ...
            && isequaln(Cx.CK.level, [cells.level]) && strcmp(Cx.CK.det_id, DET_ID)
        fprintf('%s is up to date (%d cells, %d flights per point), nothing to do\n', f_out, nC, N_GEO);
        return
    end
    clear Cx
end

% Flights per check Eb/N0, shared by every cell that flies it (common random numbers); then
% every shadowing group's own, selected where its cells fly (NaN elsewhere)
SH = struct('band', gband, 'level', glv, 'cell_levels', {arrayfun(@(k) unique(shd_db(grp == k)), 1:nGr, ...
    'UniformOutput', false)}, 'cell_group', grp, 'ebs', {gebs}, 'v_kmh', vshd, 'speed_range', vrange, ...
    'tried', zeros(nGr, 1, nS), 'kept', zeros(nGr, 1, nS));
geo = cell(1, nS);
for s = 1:nS
    geo{s} = pool_geometries(s, BLOCK, 1:N_GEO, vrange, p0, LHS_SEED + 100*s, FAM);
    for k = 1:nGr
        z = nan(1, N_GEO);                              % placeholders where the group does not fly
        gk = struct('seed', z, 'speed', z, 'run', 100 * BLOCK + gpos{k}, 'alt', z, 'ksig', z, 'aoa1', z, 'rho', z);
        if ismember(s, gebs{k})
            ps = p0; ps.active_threat = 'airframe_shadowing'; ps.shadow_db = min(SH.cell_levels{k}); eb = EB(s);
            sel = struct('seed', @(j, v) shadow_pool_seed(k, s, BLOCK, j, v), 'j0', 0, 'jmax', J_MAX, 'floor', @(a) shadow_alt_floor(a, eb, ps), ...
                'keep', @(sd, v, a, kk, o, c) hides_antenna(sd, v, ps, struct('ebno', eb, 'alt_m', a, 'k_sig_db', kk, ...
                'aoa1_deg', o, 'rho', c, 'event_frame', C.event_frame, 'frames', C.event_count)));
            [gk, info] = pool_geometries(s, BLOCK, gpos{k}, vshd(k, :), p0, LHS_SEED + 100*s + k, FAM, sel);
            SH.tried(k, 1, s) = sum(info.tries); SH.kept(k, 1, s) = N_GEO;
        end
        for f = fieldnames(gk)', geo{s}.(f{1}) = [geo{s}.(f{1}), gk.(f{1})]; end
    end
    geo{s}.frames = opt.F_SUB * ones(1, N_TOT); geo{s}.event = nan(1, N_TOT);   % the groups' flights roll in
    geo{s}.frames(ref) = C.event_run; geo{s}.event(ref) = C.event_frame;
end
evf = geo{1}.event;                                     % the event's frame of every check flight (NaN: none)
for k = 1:nGr
    fprintf('Airframe shadowing %s dB (rolls %.1f-%.1f deg): own flights at %s dB, kept of the candidates tried %d/%d\n', ...
        strjoin(compose('%g', SH.cell_levels{k}), '/'), gband(k, :), strjoin(compose('%g', EB(gebs{k})), '/'), ...
        sum(SH.kept(k, 1, :)), sum(SH.tried(k, 1, :)));
end
spd = cell2mat(arrayfun(@(s) geo{s}.speed, (1:nS)', 'UniformOutput', false));
z = nan(nS, N_TOT);
V = struct('seed', z, 'speed', z, 'alt_m', z, 'k_sig', z, 'k_int', z, 'yaw', z, 'rho', z, 'gcs_point_db', z, 'el_db', z, ...
    'aoa', nan(nS, N_TOT, 3), 'align', nan(nS, N_TOT, 3), 'gcs_aoa', z, 'el_deg', z, 'bank', z, 'roll', z, 'pitch', z, ...
    'wob', z, 'att_db', z, 'body_spread_db', z, 'jam', nan(nS, N_TOT, 4), 'ds_ns', z, 'ds_int', nan(nS, N_TOT, 3), ...
    'roll_in', nan(nS, N_TOT, 3));
for s = 1:nS                                            % every per-flight draw, as in PP.cov (build_policy_pools.m)
    g = geo{s};
    for r = find(isfinite(g.seed))
        fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
        d = flight_draws(g.seed(r), fd, p0, struct('ebno', EB(s), 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
            'aoa1_deg', g.aoa1(r), 'rho', g.rho(r), 'event_frame', g.event(r), 'frames', g.frames(r)));
        V.roll_in(s, r, :) = d.roll_in;
        V.seed(s, r) = g.seed(r); V.speed(s, r) = g.speed(r); V.alt_m(s, r) = d.alt_m; V.k_sig(s, r) = d.k_sig;
        V.k_int(s, r) = d.k_int; V.yaw(s, r) = d.yaw; V.rho(s, r) = d.rho; V.gcs_point_db(s, r) = d.gcs_point_db;
        V.el_db(s, r) = d.el_db;
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
geoc = cell(1, nC);
empty = geo{1}; for f = fieldnames(empty)', empty.(f{1}) = empty.(f{1})([]); end
for c = 1:nC
    gc = repmat({empty}, 1, nS);
    for s = cells(c).ebs
        j = cg{c}{1};
        if c == 1, j = [j, gpos{cellfun(@(e) ismember(s, e), gebs)}]; end %#ok<AGROW>   % the clean link: the groups flown here
        g = geo{s};
        for f = fieldnames(g)', g.(f{1}) = g.(f{1})(j); end
        gc{s} = g;
    end
    geoc{c} = gc;
end

%% 2. Simulation, one parallel job per cell
NWP = N_WORKERS;
if exist('SMOKE', 'var') && SMOKE
    NWP = 0;
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
fld = arrayfun(@(ce) C.sev.(ce.threat).field, cells(2:end), 'UniformOutput', false);
fld = [{''}, fld];                                      % the level field of every cell (none for the clean link)
t0 = tic;
fprintf('%d cells x %d configurations, %d flights per point, on %d workers\n', nC, nA, N_GEO, N_WORKERS);
parfor (c = 1:nC, NWP)
    ce = cells(c);
    p = p0; p.active_threat = ce.threat;
    if ~isempty(fld{c}), p.(fld{c}) = ce.level; end
    [Ps, pinfo] = pool_cell(p, ce.threat, ACTIONS, EB, geoc{c}, det, opt);
    results{c} = Ps;
    nuniq(c) = pinfo.n_unique;
    fprintf('  cell %2d/%d %-22s %-6s %6.2f  %2d unique configurations\n', c, nC, ce.threat, ce.kind, ce.level, nuniq(c));
end
fprintf('Simulated in %.1f min\n', toc(t0) / 60);

%% 3. Package
pools = cell(nC, nS, nA, 1);
for c = 1:nC, pools(c, :, :, 1) = results{c}; end
clear results
na = find(strcmp(ACTIONS, 'no_action'));
Pc = pools(1, :, na, 1);
gp = ones(1, nA); bw = ones(1, nA); pw = ones(1, nA);
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', ACTIONS{a});
    gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor; pw(a) = cm.power_factor;
end
own = @(Q) ismember(Q.run, runs(1:N_GEO));             % the clean link's own flights, not the shadowing reference
CK = struct('scen', {{cells.threat}}, 'kind', {{cells.kind}}, 'sev', [cells.sev], 'level', [cells.level], ...
    'sev_names', {C.sev_names}, 'splits', {{'check'}}, 'cell_geo', {cg}, 'ref_geo', {{ref}}, 'shadow', SH, ...
    'cell_ebs', {{cells.ebs}}, 'singles', {[{'none'}, THREATS]}, 'combos', {{}}, 'ebno', EB, 'ebno_grid', EGRID, ...
    'e_level', E_LEVEL, 'actions', {ACTIONS}, 'speed_range', vrange, 'speed', {{spd}}, 'cov', {{V}}, ...
    'gp', gp, 'bw', bw, 'pw', pw, 'cfg_gain_db', config_gain_db(ACTIONS, p0), 'pools', {pools}, ...
    'clean', cellfun(@(Q) mean(Q.ber(own(Q))), Pc), 'clean_fer', cellfun(@(Q) mean(double(Q.fer(own(Q)))), Pc), ...
    'classes', {det.classes}, 'maha_thr', T.maha, 'fuse', FZ.FM, 'fuse_N', FZ.N, 'q_thr', FZ.q_thr, 'unk_win', UW, ...
    'F_SUB', opt.F_SUB, 'event_frame', {{evf}}, 'fec_frames', p0.fec_frames, ...
    'runs', {{runs}}, 'family', FAM, 'block', BLOCK, 'model_tag', PP.model_tag, 'det_id', DET_ID, ...
    'aoa_random', p0.int_aoa_random, 'sps', p0.sps, 'bps', p0.bits_per_symbol, ...
    'feat_names', {link_features('names')}, 'created', datestr(now));
save(f_out, 'CK', '-v7.3');
fprintf('Clean link per check Eb/N0 (%s dB): BER %s | packet loss %s\n', strjoin(compose('%g', EB), '/'), ...
    sprintf('%.1e ', CK.clean), sprintf('%.3f ', CK.clean_fer));
on = zeros(1, 2);                                       % shadowing flights with an antenna hidden in the model, flights
for c = find(grp > 0)
    for s = cells(c).ebs
        Q = pools{c, s, na, 1};
        [~, ~, ir] = unique(Q.run);
        on = on + [sum(accumarray(ir, double(Q.act), [], @max) > 0), max([ir; 0])];
    end
end
if nGr > 0, fprintf('Airframe shadowing on the air in %d of the %d flights of its check cells\n', on); end
fprintf('Saved %s (%.1f min)\n', f_out, toc(t0) / 60);
clear pools CK
