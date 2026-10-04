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
LHS_SEED = 7200000;              % permutation stream of a design: LHS_SEED + 100 (Eb/N0 index)
E_LEVEL = 9;                     % [dB] Eb/N0 of the level midpoints
N_WORKERS = 6;
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
THREATS = setdiff(PP.singles, {'none'}, 'stable');
if exist('SMOKE', 'var') && SMOKE                       % reduced chain check (run_stage smoke)
    THREATS = THREATS(1); N_GEO = 2;
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
FZ = struct('FM', [], 'N', 1);
if isfile('data/fusion.mat'), FZ = load('data/fusion.mat', 'FM', 'N'); end
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
runs = 100 * BLOCK + (1:N_GEO);
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

% Flights per check Eb/N0, shared by every cell that flies it (common random numbers)
geo = cell(1, nS);
for s = 1:nS
    geo{s} = pool_geometries(s, BLOCK, 1:N_GEO, vrange, p0, LHS_SEED + 100*s, FAM);
end
spd = cell2mat(arrayfun(@(s) geo{s}.speed, (1:nS)', 'UniformOutput', false));
z = nan(nS, N_GEO);
V = struct('seed', z, 'speed', z, 'alt_m', z, 'k_sig', z, 'k_int', z, 'yaw', z, 'rho', z, 'gcs_point_db', z, 'el_db', z, ...
    'aoa', nan(nS, N_GEO, 3), 'align', nan(nS, N_GEO, 3));
ag = exp(-1j * 2*pi * p0.ant_spacing_wl * (0:p0.n_rx-1)' * sind(p0.gcs_aoa_deg));
for s = 1:nS
    g = geo{s};
    for r = 1:N_GEO
        fd = g.speed(r) / 3.6 * p0.carrier_freq / p0.c_light;
        d = flight_draws(g.seed(r), fd, p0, struct('ebno', EB(s), 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
            'aoa1_deg', g.aoa1(r), 'rho', g.rho(r)));
        V.seed(s, r) = g.seed(r); V.speed(s, r) = g.speed(r); V.alt_m(s, r) = d.alt_m; V.k_sig(s, r) = d.k_sig;
        V.k_int(s, r) = d.k_int; V.yaw(s, r) = d.yaw; V.rho(s, r) = d.rho; V.gcs_point_db(s, r) = d.gcs_point_db;
        V.el_db(s, r) = d.el_db;
        ni = min(3, numel(d.aoa));
        V.aoa(s, r, 1:ni) = d.aoa(1:ni);
        V.align(s, r, 1:ni) = abs(ag' * exp(-1j * 2*pi * p0.ant_spacing_wl * (0:p0.n_rx-1)' * sind(d.aoa(1:ni)))).^2 / p0.n_rx^2;
    end
end
geoc = cell(1, nC);
empty = geo{1}; for f = fieldnames(empty)', empty.(f{1}) = empty.(f{1})([]); end
for c = 1:nC
    gc = repmat({empty}, 1, nS);
    gc(cells(c).ebs) = geo(cells(c).ebs);
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
CK = struct('scen', {{cells.threat}}, 'kind', {{cells.kind}}, 'sev', [cells.sev], 'level', [cells.level], ...
    'sev_names', {C.sev_names}, 'splits', {{'check'}}, 'cell_geo', {arrayfun(@(c) {1:N_GEO}, 1:nC, 'UniformOutput', false)}, ...
    'cell_ebs', {{cells.ebs}}, 'singles', {[{'none'}, THREATS]}, 'combos', {{}}, 'ebno', EB, 'ebno_grid', EGRID, ...
    'e_level', E_LEVEL, 'actions', {ACTIONS}, 'speed_range', vrange, 'speed', {{spd}}, 'cov', {{V}}, ...
    'gp', gp, 'bw', bw, 'pw', pw, 'pools', {pools}, ...
    'clean', cellfun(@(Q) mean(Q.ber), Pc), 'clean_fer', cellfun(@(Q) mean(double(Q.fer)), Pc), ...
    'classes', {det.classes}, 'maha_thr', T.maha, 'fuse', FZ.FM, 'fuse_N', FZ.N, 'unk_win', UW, 'F_SUB', opt.F_SUB, ...
    'runs', {{runs}}, 'family', FAM, 'block', BLOCK, 'model_tag', PP.model_tag, 'det_id', DET_ID, ...
    'aoa_random', p0.int_aoa_random, 'sps', p0.sps, 'bps', p0.bits_per_symbol, ...
    'feat_names', {link_features('names')}, 'created', datestr(now));
save(f_out, 'CK', '-v7.3');
fprintf('Clean link per check Eb/N0 (%s dB): BER %s | packet loss %s\n', strjoin(compose('%g', EB), '/'), ...
    sprintf('%.1e ', CK.clean), sprintf('%.3f ', CK.clean_fer));
fprintf('Saved %s (%.1f min)\n', f_out, toc(t0) / 60);
clear pools CK
