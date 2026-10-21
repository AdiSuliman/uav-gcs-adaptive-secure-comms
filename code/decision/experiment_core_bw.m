function experiment_core_bw(stage, smoke)
%EXPERIMENT_CORE_BW  The bandwidth study: jammer bandwidth and power on an explicit channel
%   plan, the three systems of the revised proposal on its core action set
%   (docs/core_bw_protocol.md, fixed before any run).
%   experiment_core_bw(stage)          from any folder (it works in the repository root)
%   experiment_core_bw(stage, true)    the reduced chain check: its own seed blocks and its own
%                                      data/core_bw_smoke and results/core_bw_smoke; never a result
%   Stages, in order:
%     'pools'   frame pools of the clean link and the 34 jammer cells (band_cells.m) under the
%               four core configurations, 12 validation and 36 test geometries per (cell, Eb/N0)
%               (seed family 6, blocks 5 and 14; nested Latin hypercubes), and the residual's
%               two layers (channel_switch at 24 and 47 dB, the nRF24L01+'s rejections) on the
%               test geometries; the in-band cap's binding share per cell and the time per
%               simulation (gate G2) -> data/core_bw/pools.mat
%     'dset'    the detector-only set D (4 flights per (cell, Eb/N0), 24 clean, block 7):
%               spectrogram images -> data/core_bw/dset.mat
%     'val'     validation only: the coverage check (G3), the wideband action W of the CNN
%               rule per hop rule, the recoverable scenarios; frozen by hash in
%               results/core_bw/protocol.json
%     'test'    the single test reading (refused without the frozen protocol, or a second
%               time), then 'report'
%     'report'  the KPI lines, sensitivities, predictions and the detector analysis ->
%               results/core_bw/core_bw_report.txt, core_bw_kpis.mat
%     'dread'   the frozen three-state CNN (branch core-cnn, after its B3c reading) on set D
%     'smoke'   every stage but 'dread' on the reduced problem
%   Inputs (read only, copies of the profile's deployed files): params.mat,
%   data/trained_detector.mat, data/fusion.mat, data/ood_thresholds.mat, data/splits.mat (its
%   norm and classes) and data/trained_dqn.mat (the deployed decision settings).
%   Not a run_stage stage: neither the takeover nor the chain runs it.
if nargin < 2 || isempty(smoke), smoke = false; end
root = setup_paths(); c0 = cd(root); back = onCleanup(@() cd(c0)); %#ok<NASGU>
if strcmp(stage, 'smoke')
    for st = {'pools', 'dset', 'val', 'test'}, experiment_core_bw(st{1}, true); end
    return
end
X = study_config(smoke);
t0 = tic;
fprintf('\n##### CORE_BW %s%s %s #####\n', stage, ternary(smoke, ' (smoke)', ''), datestr(now));
switch stage
    case 'pools',  stage_pools(X);
    case 'dset',   stage_dset(X);
    case 'val',    stage_val(X);
    case 'test',   stage_test(X); stage_report(X);
    case 'report', stage_report(X);
    case 'dread',  stage_dread(X);
    otherwise, error('experiment_core_bw:stage', 'experiment_core_bw: unknown stage %s', stage);
end
fprintf('##### CORE_BW %s done in %.1f min #####\n', stage, toc(t0) / 60);
end

%% ===================== Configuration =====================
function X = study_config(smoke)
% The study's fixed settings (docs/core_bw_protocol.md section 6).
X.smoke = smoke;
sfx = ''; if smoke, sfx = '_smoke'; end
X.D = ['data/core_bw' sfx]; X.R = ['results/core_bw' sfx];
X.protocol = 'docs/core_bw_protocol.md'; X.frozen = 'docs/core_bw_frozen.json';
X.pools = fullfile(X.D, 'pools.mat'); X.dset = fullfile(X.D, 'dset.mat');
X.val = fullfile(X.R, 'validation.mat'); X.recov = fullfile(X.R, 'recoverable.txt');
X.proto_json = fullfile(X.R, 'protocol.json'); X.marker = fullfile(X.R, 'test_read_started.txt');
X.test = fullfile(X.R, 'test_readings.mat'); X.report = fullfile(X.R, 'core_bw_report.txt');
X.kpis = fullfile(X.R, 'core_bw_kpis.mat'); X.dread = fullfile(X.R, 'core_cnn_bw.txt');
X.FAM = 6;                       % seed family (pool_seed.m)
X.BLOCK = [5 14];                % validation, test
X.BLOCK_D = 7;                   % set D
X.NGEO = [12 36];                % geometries per (cell, Eb/N0): 36 test, the N_MIN of a committed verdict
X.ND = 4; X.ND_CLEAN = 24;       % set D flights per (cell, Eb/N0) and of the clean link
X.LHS_SEED = 7200000;            % permutation stream of a design: + 100 (Eb/N0 index) + split
X.REPS = 2; X.NE = 64; X.T = 30; % onsets per geometry, episodes per batch, cycles per episode
X.RULES = {'H1', 'H3', 'H4'};    % H1 primary (hop_targets.m)
X.ACR = [24 47]; X.ACR_FAR = 12; % residual layers [dB] and the offset [MHz] beyond which the far one holds
X.ENV_MIN = 90;                  % recoverable scenario: >= 90% of its validation episodes recoverable
X.TARGET = 0.30; X.N_RUN = 5; X.B = 2000;
X.W = {'channel_switch', 'channel_switch+rate_reduce', 'rate_reduce'};   % candidates of W, the last tie-break order
X.N_WORKERS = 6;
X.opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
X.pick = {}; X.EBNO = [];
if smoke
    X.BLOCK = [18 19]; X.BLOCK_D = 16; X.NGEO = [2 2]; X.ND = 1; X.ND_CLEAN = 2; X.EBNO = [3 12];
    X.pick = {'cw_tot23', 'bw20_tot23'};
end
end

function [p0, cells, scen, EBNO] = study_cells(X)
% Params, cells and scenarios of the study (the smoke's subset).
p0 = load('params.mat').params; p0.quiet_build = true;
[cells, scen] = band_cells(p0);
EBNO = p0.EbNo_dB; if ~isempty(X.EBNO), EBNO = X.EBNO; end
if ~isempty(X.pick)
    keep = find(ismember({cells.name}, X.pick));
    map = zeros(1, numel(cells)); map(keep) = 1:numel(keep);
    cells = cells(keep);
    scen = scen(map([scen.cell]) > 0);
    for i = 1:numel(scen), scen(i).cell = map(scen(i).cell); end
end
end

function p = cell_params(p0, c)
% Params of one cell (c empty: the clean link).
p = p0;
if isempty(c), p.active_threat = 'none'; return; end
p.active_threat = c.threat; p.(c.field) = c.level;
end

%% ===================== Pools =====================
function stage_pools(X)
[p0, cells, scen, EBNO] = study_cells(X);
assert_frame1_onsets(p0);
C = decision_config(); A = C.core_actions; nA = numel(A); nS = numel(EBNO); nC = numel(cells);
tag = regexp(fileread(which('build_policy_pools')), 'MODEL_TAG\s*=\s*''([^'']+)''', 'tokens', 'once');
MODEL_TAG = tag{1};
D = load('data/trained_detector.mat', 'net', 'classes', 'ood', 'trained_at');
nm = split_norm();
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', nm.feat_mean, 'sd', nm.feat_std, 'fs', p0.symbol_rate * p0.sps);
T = ood_thresholds(0.95); FZ = fusion_model();
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end
DET_ID = detector_id(D.trained_at, D.ood, FZ);
clear D nm
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
geo = cell(1, nS);
for s = 1:nS
    for sp = 1:2
        g(sp) = pool_geometries(s, X.BLOCK(sp), 1:X.NGEO(sp), vrange, p0, X.LHS_SEED + 100*s + sp, X.FAM); %#ok<AGROW>
    end
    geo{s} = g;
end
runs = arrayfun(@(sp) 100 * X.BLOCK(sp) + (1:X.NGEO(sp)), 1:2, 'UniformOutput', false);
% Jobs: every cell on both splits, then the residual's layers of the cells a hop can escape
% (channel_switch configurations only, test geometries)
ACS = A(contains(A, 'channel_switch'));
jobs = struct('name', 'none', 'threat', 'none', 'cell', 0, 'layer', 'pools', 'acr', NaN, 'splits', [1 2], 'actions', {A});
P = {cell_params(p0, [])};
for c = 1:nC
    jobs(end+1) = struct('name', cells(c).name, 'threat', cells(c).threat, 'cell', c, 'layer', 'pools', 'acr', NaN, ...
        'splits', [1 2], 'actions', {A}); %#ok<AGROW>
    P{end+1} = cell_params(p0, cells(c)); %#ok<AGROW>
end
for v = 1:numel(X.ACR)
    for c = find(escapable(cells))
        jobs(end+1) = struct('name', cells(c).name, 'threat', cells(c).threat, 'cell', c, 'layer', sprintf('acr%g', X.ACR(v)), ...
            'acr', X.ACR(v), 'splits', 2, 'actions', {ACS}); %#ok<AGROW>
        q = cell_params(p0, cells(c)); q.cm_acr_db = X.ACR(v); P{end+1} = q; %#ok<AGROW>
    end
end
nJ = numel(jobs);
geoj = @(j) cellfun(@(x) x(jobs(j).splits), geo, 'UniformOutput', false);
keys = arrayfun(@(j) pool_checkpoint('key', {MODEL_TAG, DET_ID, runs, jobs(j), EBNO, geoj(j), X.opt, P{j}}), 1:nJ, ...
    'UniformOutput', false);
CKD = fullfile(pwd, X.D, 'cells');
todo = pool_checkpoint('todo', CKD, keys);
w = arrayfun(@(j) pool_cost(P{j}, jobs(j).threat, jobs(j).actions, geoj(j), X.opt), todo);
todo = todo(pool_schedule(w));
pl = [];
if ~X.smoke
    turn = []; parallel_turn('take'); turn = onCleanup(@() parallel_turn('give')); %#ok<NASGU>
    pl = gcp('nocreate');
    if isempty(pl) || pl.NumWorkers ~= X.N_WORKERS, delete(pl); pl = parpool('Processes', X.N_WORKERS); end
    repo = pwd;
    spmd
        pool_worker_init(repo);
    end
end
fprintf('%d jobs (%d cells + the clean link, %d residual layers) x %d Eb/N0; %d kept from an earlier start (%s)\n', ...
    nJ, nC, nJ - nC - 1, nS, nJ - numel(todo), CKD);
t0 = tic;
S = struct('jobs', jobs, 'P', {P}, 'geo', {geo}, 'det', det, 'opt', X.opt, 'EBNO', EBNO, 'CKD', CKD, 'keys', {keys});
pool_lpt(@(S, j) core_bw_job('pools', S, j), S, todo, pl);
wall = toc(t0); clear S
pools = cell(nC + 1, nS, nA, 2);
alt = repmat({cell(size(pools))}, 1, numel(X.ACR));
nsim = 0; nnow = 0;
for j = 1:nJ
    Rj = pool_checkpoint('load', CKD, j);
    ns = Rj.nuniq * sum(X.NGEO(jobs(j).splits)) * nS;
    nsim = nsim + ns; nnow = nnow + ns * ismember(j, todo);
    ia = cellfun(@(a) find(strcmp(A, a)), jobs(j).actions);
    if isnan(jobs(j).acr)
        pools(jobs(j).cell + 1, :, ia, jobs(j).splits) = Rj.P;
    else
        alt{X.ACR == jobs(j).acr}(jobs(j).cell + 1, :, ia, jobs(j).splits) = Rj.P;
    end
end
clear Rj
na = find(strcmp(A, 'no_action'));
cq = pools(1, :, na, 1);
gp = ones(1, nA); bw = ones(1, nA); pw = ones(1, nA);
for a = 1:nA
    [~, ~, cm] = apply_countermeasure(p0, 'none', A{a});
    gp(a) = cm.goodput_factor; bw(a) = cm.bw_factor; pw(a) = cm.power_factor;
end
spd = cell(1, 2); sd = cell(1, 2);
for sp = 1:2
    spd{sp} = cell2mat(arrayfun(@(s) geo{s}(sp).speed, (1:nS)', 'UniformOutput', false));
    sd{sp} = cell2mat(arrayfun(@(s) geo{s}(sp).seed, (1:nS)', 'UniformOutput', false));
end
PP = struct();
PP.scen = [{'none'}, {cells.threat}]; PP.cells = cells; PP.scenarios = scen; PP.level = [NaN, cells.level];
PP.splits = {'val', 'test'}; PP.ebno = EBNO; PP.actions = A; PP.ngeo = X.NGEO; PP.runs = runs;
PP.speed = spd; PP.seed = sd; PP.speed_range = vrange;
PP.gp = gp; PP.bw = bw; PP.pw = pw; PP.cfg_gain_db = config_gain_db(A, p0);
PP.pools = pools; PP.alt_pools = alt; PP.acr_db = X.ACR;
PP.clean = cellfun(@(Q) mean(Q.ber), cq); PP.clean_fer = cellfun(@(Q) mean(double(Q.fer)), cq);
PP.classes = det.classes; PP.maha_thr = T.maha; PP.maha_val = single(T.maha_val); PP.unk_retain = T.retain;
PP.fuse = FZ.FM; PP.fuse_N = FZ.N; PP.q_thr = FZ.q_thr; PP.unk_win = UW;
PP.F_SUB = X.opt.F_SUB; PP.event_frame = {nan(1, X.NGEO(1)), nan(1, X.NGEO(2))}; PP.fec_frames = p0.fec_frames;
PP.model_tag = MODEL_TAG; PP.det_id = DET_ID; PP.params_id = params_id(p0);
PP.sps = p0.sps; PP.bps = p0.bits_per_symbol; PP.feat_names = link_features('names');
PP.cap = cap_share(p0, cells, geo, EBNO, X.opt);
PP.timing = struct('sims', nsim, 'sims_run', nnow, 'wall_min', wall / 60, 'workers', max(1, X.N_WORKERS * ~X.smoke), ...
    's_per_sim', wall * max(1, X.N_WORKERS * ~X.smoke) / max(nnow, 1), 'jobs_run', numel(todo));
PP.smoke = X.smoke; PP.created = datestr(now);
pool_checkpoint('commit', X.pools, struct('PP', PP));
pool_checkpoint('clear', CKD);
fprintf('Saved %s: %d simulations, %d of them now in %.1f min (%.2f s per simulation per worker)\n', X.pools, nsim, ...
    nnow, wall / 60, PP.timing.s_per_sim);
fprintf('In-band cap (%g dB) binding share of the geometries per cell (G2):\n', p0.inband_cap_db);
for c = 1:nC, fprintf('  %-12s level %6.2f dB  %5.1f%%\n', cells(c).name, cells(c).level, 100 * PP.cap(c)); end
end

function e = escapable(cells)
% Cells some hop can escape: every one but the whole-band jammer (the equal-level cells serve
% widths a hop escapes).
e = arrayfun(@(c) c.slice || ~(strcmp(c.J.kind, 'fixed') && c.J.lo <= 2400 && c.J.hi >= 2483.5), cells);
end

function f = cap_share(p0, cells, geo, EBNO, opt)
% Share of the geometries (both splits, every Eb/N0) on which the in-band cap binds a cell's
% level: L - 20 log10(cap amplitude) > p.inband_cap_db (inband_cap_amp.m, flight_draws.m).
p = p0; p.active_threat = 'jamming';
ca = [];
for s = 1:numel(EBNO)
    for sp = 1:numel(geo{s})
        g = geo{s}(sp);
        for r = 1:numel(g.seed)
            fd = g.speed(r) / 3.6 * p.carrier_freq / p.c_light;
            d = flight_draws(g.seed(r), fd, p, struct('ebno', EBNO(s), 'alt_m', g.alt(r), 'k_sig_db', g.ksig(r), ...
                'aoa1_deg', g.aoa1(r), 'rho', g.rho(r), 'event_frame', NaN, 'frames', opt.F_SUB));
            ca(end+1) = d.cap_amp; %#ok<AGROW>
        end
    end
end
f = arrayfun(@(c) mean(c.level - 20 * log10(ca) > p0.inband_cap_db), cells);
end

function PP = load_pools(X, with_alt)
% The study's pools; with_alt: the residual's layers as full pool arrays in PP.acr_pools
% (link_env.m), the configurations they do not hold taken from the pools.
L = load(X.pools, 'PP'); PP = L.PP;
if with_alt
    PP.acr_pools = cell(1, numel(PP.alt_pools));
    for v = 1:numel(PP.alt_pools)
        Q = PP.pools; e = ~cellfun(@isempty, PP.alt_pools{v});
        Q(e) = PP.alt_pools{v}(e);
        PP.acr_pools{v} = Q;
    end
end
PP = rmfield(PP, 'alt_pools');
end

%% ===================== Detector-only set D =====================
function stage_dset(X)
[p0, cells, ~, EBNO] = study_cells(X);
assert_frame1_onsets(p0);
nS = numel(EBNO);
fixed = find(~[cells.slice]);
jobs = struct('name', 'none', 'cell', 0); P = {cell_params(p0, [])}; G = {};
vrange = [p0.speed_kmh_min p0.speed_kmh_max];
G{1} = arrayfun(@(s) pool_geometries(s, X.BLOCK_D, 1:X.ND_CLEAN, vrange, p0, [], X.FAM), 1:nS, 'UniformOutput', false);
for c = fixed
    jobs(end+1) = struct('name', cells(c).name, 'cell', c); %#ok<AGROW>
    P{end+1} = cell_params(p0, cells(c)); %#ok<AGROW>
    G{end+1} = arrayfun(@(s) pool_geometries(s, X.BLOCK_D, X.ND_CLEAN + (1:X.ND), vrange, p0, [], X.FAM), 1:nS, ...
        'UniformOutput', false); %#ok<AGROW>
end
D0 = load('data/trained_detector.mat', 'ood', 'trained_at'); DET_ID = detector_id(D0.trained_at, D0.ood, fusion_model());
keys = arrayfun(@(j) pool_checkpoint('key', {'dset', DET_ID, jobs(j), EBNO, G{j}, X.opt, P{j}}), 1:numel(jobs), ...
    'UniformOutput', false);
CKD = fullfile(pwd, X.D, 'dset_cells');
todo = pool_checkpoint('todo', CKD, keys);
pl = [];
if ~X.smoke
    turn = []; parallel_turn('take'); turn = onCleanup(@() parallel_turn('give')); %#ok<NASGU>
    pl = gcp('nocreate');
    if isempty(pl) || pl.NumWorkers ~= X.N_WORKERS, delete(pl); pl = parpool('Processes', X.N_WORKERS); end
    repo = pwd;
    spmd
        pool_worker_init(repo);
    end
end
S = struct('jobs', jobs, 'P', {P}, 'geo', {G}, 'opt', X.opt, 'EBNO', EBNO, 'CKD', CKD, 'keys', {keys}, ...
    'fs', p0.symbol_rate * p0.sps);
pool_lpt(@(S, j) core_bw_job('dset', S, j), S, todo, pl);
clear S
Xi = {}; y = []; cel = []; s_ = []; run = []; pos = [];
for j = 1:numel(jobs)
    Rj = pool_checkpoint('load', CKD, j);
    c = jobs(j).cell; st = 1;
    if c > 0, st = 2 + strcmp(cells(c).threat, 'jamming'); end
    n = numel(Rj.s);
    Xi{end+1} = Rj.X; y = [y; st * ones(n, 1)]; cel = [cel; c * ones(n, 1)]; %#ok<AGROW>
    s_ = [s_; Rj.s]; run = [run; Rj.run + 1e4 * j]; pos = [pos; Rj.pos]; %#ok<AGROW>
end
DS = struct('X', cat(4, Xi{:}), 'y', y, 'cell', cel, 's', s_, 'run', run, 'pos', pos, 'ebno', EBNO(s_)', ...
    'cells', {cells}, 'det_id', DET_ID, 'params_id', params_id(p0), 'smoke', X.smoke, 'created', datestr(now));
clear Xi
pool_checkpoint('commit', X.dset, struct('DS', DS));
pool_checkpoint('clear', CKD);
fprintf('Saved %s: %d frames (%d sub-runs)\n', X.dset, numel(DS.y), numel(unique(DS.run)));
end

function stage_dread(X)
% The frozen three-state CNN of branch core-cnn on set D, only after its own B3c reading.
need = {'core_cnn_config', 'core_cnn_eval', 'spec_scores'};
ok = cellfun(@(f) exist(f, 'file') == 2, need);
assert(all(ok), 'experiment_core_bw:core_cnn', ['the three-state CNN''s code (%s) is not on the path: it lives on ' ...
    'branch core-cnn'], strjoin(need(~ok), ', '));
CC = core_cnn_config();
assert(isfile(CC.model) && isfile('results/core_cnn.mat'), 'experiment_core_bw:b3c', ...
    'set D is read only after B3c''s own reading (%s and results/core_cnn.mat)', CC.model);
assert(isfile(X.dset), 'experiment_core_bw:dset', '%s not found: run the dset stage', X.dset);
L = load(X.dset, 'DS'); DS = L.DS; clear L
assert(strcmp(DS.params_id, params_id(load('params.mat').params)), 'experiment_core_bw:params', ...
    '%s comes from another link model than params.mat', X.dset);
Mo = load(CC.model, 'net', 'N');
Pr = spec_scores(Mo.net, DS.X); DS.X = [];
Lp = core_cnn_eval('logp', Pr, DS.run, DS.pos, Mo.N);
[~, yp] = max(Lp, [], 2);
M = core_cnn_eval('metrics', DS.y, yp, 3);
lines = {sprintf(['Three-state CNN (window %d cycles) on set D: macro-F1 %.2f%%, recall clean %.2f%%, narrowband ' ...
    '%.2f%%, wideband %.2f%% (analysis; the KPI verdicts are B3c''s)'], Mo.N, 100 * M.macro_f1, 100 * M.recall)};
[lines, T] = det_table(lines, DS.y, yp, DS.cell, DS.s, DS.cells, DS.ebno, 'CNN');
write_lines(X.dread, lines);
save(strrep(X.dread, '.txt', '.mat'), 'M', 'T', 'yp');
fprintf('%s\n', lines{:});
end

%% ===================== Episodes =====================
function EP = episodes(X, PP, sp, B)
% Every (scenario, Eb/N0, geometry, onset) of split sp, the hop channels of every rule from the
% episode's 'hop' stream (seed_stream.m) and their coverage (band_cover.m). A jammer tuned to
% our channel (tone, centred) takes the channel in use at the onset, so its coverage is that of
% the hops after it (EP.rel, link_env.m cover_rel); a fixed one covers whatever channel we are on.
scen = PP.scenarios; nS = numel(PP.ebno); nG = X.NGEO(sp); T = X.T;
C = decision_config();
rs = RandStream('mt19937ar', 'Seed', 2030 + sp);
ONS = randi(rs, [3 10], nS, nG, X.REPS); FD = randi(rs, C.fdelay, nS, nG, X.REPS);
[k, s, r, e] = ndgrid(1:numel(scen), 1:nS, 1:nG, 1:X.REPS);
n = numel(k);
EP = struct('k', k(:)', 's', s(:)', 'r', r(:)', 'rep', e(:)', 'n', n, 'T', T);
EP.c = [scen(EP.k).cell] + 1;                          % index into PP.scen (1: the clean link)
EP.onset = ONS(sub2ind(size(ONS), EP.s, EP.r, EP.rep)); EP.fdelay = FD(sub2ind(size(FD), EP.s, EP.r, EP.rep));
EP.slice = [scen(EP.k).slice]; EP.bj = [scen(EP.k).bj]; EP.tot = [scen(EP.k).jsr_tot]; EP.inb = [scen(EP.k).jsr_in];
EP.narrow = EP.bj == 0;
EP.rel = arrayfun(@(i) ~strcmp(scen(i).J.kind, 'fixed'), EP.k);   % tuned to our channel: hops counted from the onset
EP.home = zeros(1, n);
for q = 1:numel(X.RULES)
    EP.cover{q} = false(n, T); EP.acr{q} = ones(n, T); EP.part{q} = false(n, T); EP.near{q} = false(n, T);
end
for i0 = find(EP.rep == 1)
    J = scen(EP.k(i0)).J;
    rsh = seed_stream(PP.seed{sp}(EP.s(i0), EP.r(i0)), 'hop');
    for rep = 1:X.REPS
        i = i0 + (rep - 1) * numel(scen) * nS * nG;
        can = true(1, numel(B.f_mhz));
        if strcmp(J.kind, 'fixed'), can = band_cover(band_cover('span', J, NaN), B.f_mhz, B.b_ch); end
        h = hop_targets('home', can, [], rsh);
        c1 = hop_targets('H1', h, T, rsh, B);
        [cv, st, off] = band_cover(band_cover('span', J, B.f_mhz(h)), B.f_mhz, B.b_ch);
        EP.home(i) = h;
        for q = 1:numel(X.RULES)
            ch = c1; if q > 1, ch = hop_targets(X.RULES{q}, h, T, [], B); end
            EP.cover{q}(i, :) = cv(ch); EP.part{q}(i, :) = st(ch) == 2;
            EP.acr{q}(i, :) = 1 + ~cv(ch) .* (1 + (off(ch) > X.ACR_FAR));
            EP.near{q}(i, :) = ~cv(ch) & off(ch) < 4;
        end
    end
end
EP.geom = 1000 * EP.s + EP.r;
end

function specs = make_specs(X, EP, idx, q, follow, acr)
% link_env.m specs of the episodes idx under hop rule q, in batches of X.NE (the last padded
% cyclically, n_valid as policy_episodes.m).
n = numel(idx); nb = ceil(n / X.NE); pad = nb * X.NE - n;
ii = idx(mod(0:n + pad - 1, n) + 1);
specs = cell(1, nb);
for b = 1:nb
    j = ii((b - 1) * X.NE + (1:X.NE));
    sp = struct('scn', EP.c(j), 's', EP.s(j), 'r', EP.r(j), 'onset', EP.onset(j), 'follow', repmat(follow, 1, X.NE), ...
        'fdelay', EP.fdelay(j), 'unk', false(1, X.NE), 'T', X.T, 'cover', EP.cover{q}(j, :), 'cover_rel', EP.rel(j));
    if acr, sp.acr = EP.acr{q}(j, :); end
    specs{b} = sp;
end
if nb > 0, specs{end}.n_valid = X.NE - pad; end
end

function R = run_set(kind, PPx, K, X, EP, idx, q, follow, acr, sp, opt, seed0)
% One policy on the episodes idx (policy_run_set.m), with the episodes' indices.
if isempty(idx), R = struct('ep', zeros(1, 0)); return; end
R = policy_run_set(kind, PPx, K, make_specs(X, EP, idx, q, follow, acr), sp, [], opt, seed0);
R.ep = idx;
end

function [kind, opt] = policy_of(name, na)
Qs = struct('agent', [], 'agents', {{}}, 'rule_sel', []);
if strcmp(name, 'oracle'), kind = 'oracle'; opt = struct(); return; end
[kind, ~, opt] = policy_setup(name, Qs, 1, 1, 1, [], na);
end

function [PP, Q] = decision_inputs(PP)
% The deployed decision settings (data/trained_dqn.mat), as evaluate_policies.m reads them.
f = 'data/trained_dqn.mat';
v = intersect(who('-file', f), {'det_id', 'dec', 'confirm', 'alarm_mode', 'drop_db', 'maha_thr', 'H', 'model_tag'});
Q = load(f, v{:});
check_det_id(PP, Q, 'experiment_core_bw');
PP = decision_settings(PP, Q);
end

%% ===================== Validation =====================
function stage_val(X)
assert(isfile(X.pools), 'experiment_core_bw:pools', '%s not found: run the pools stage', X.pools);
assert(X.smoke || (~isfile(X.marker) && ~isfile(X.test) && ~recorded(params_id(load('params.mat').params))), ...
    'experiment_core_bw:read', 'the test split was read already: the validation choices stay as frozen');
PP = load_pools(X, false);
[PP, Q] = decision_inputs(PP);
if isfield(Q, 'H') && isfield(Q.H, 'T') && Q.H.T ~= X.T
    warning('experiment_core_bw:T', 'the deployed episodes are %d cycles, this study''s %d', Q.H.T, X.T);
end
p0 = load('params.mat').params; B = band_plan(p0); C = decision_config();
K = link_env('tables', PP, 'flight');
EP = episodes(X, PP, 1, B);
na = K.na; nR = numel(X.RULES);
wide = find(~EP.slice & ~EP.narrow);
fprintf('Validation: %d episodes per hop rule (%d scenarios x %d Eb/N0 x %d geometries x %d onsets)\n', EP.n, ...
    numel(PP.scenarios), numel(PP.ebno), X.NGEO(1), X.REPS);
G3 = g3_check(PP, K, X, EP, B);
thr = plr_threshold(PP, K, 1, C);
REC = struct('rule', {}, 'k', {}, 's', {}, 'rec_pct', {}, 'harm', {}, 'per', {}, 'thr', {}, 'ok', {});
WCH = struct('rule', {}, 'W', {}, 'table', {});
for q = 1:nR
    [kn, on] = policy_of('none', na);
    Rn = run_set(kn, PP, K, X, EP, 1:EP.n, q, false, false, 1, on, 51000 + 100*q);
    nS = numel(PP.ebno);
    key = (EP.k(Rn.ep) - 1) * nS + EP.s(Rn.ep);
    th = thr(sub2ind(size(thr), EP.s(Rn.ep), EP.r(Rn.ep)));
    T = core_bw_rules('recoverable', key, Rn.recoverable, Rn.per_post, th, X.ENV_MIN);
    for i = 1:numel(T.key)
        REC(end+1) = struct('rule', X.RULES{q}, 'k', floor((T.key(i) - 1) / nS) + 1, 's', mod(T.key(i) - 1, nS) + 1, ...
            'rec_pct', T.rec_pct(i), 'harm', T.harm(i), 'per', T.per(i), 'thr', T.thr(i), 'ok', T.ok(i)); %#ok<AGROW>
    end
    % W: the CNN rule's action for the wideband class, on the recoverable wideband episodes
    rec = Rn.recoverable(ismember(Rn.ep, wide));
    iw = wide(rec);
    Rw = cell(1, numel(X.W));
    for w = 1:numel(X.W)
        [kr, orr] = policy_of('rule_core', na);
        Pw = PP; Pw.core_wide = X.W{w};
        Rw{w} = run_set(kr, Pw, K, X, EP, iw, q, false, false, 1, orr, 52000 + 100*q);
    end
    pick = @(f) cell2mat(cellfun(@(R) R.(f)(:)', Rw(:), 'UniformOutput', false));
    [pr, gp, tr] = deal(zeros(numel(X.W), 0));
    if ~isempty(iw), pr = pick('per_post'); gp = pick('dlv_post'); tr = pick('t_rec_det'); end
    [W, tab] = core_bw_rules('choose_w', X.W, EP.bj(iw), EP.tot(iw), EP.geom(iw), pr, gp, tr, X.B);
    WCH(end+1) = struct('rule', X.RULES{q}, 'W', W, 'table', tab); %#ok<AGROW>
    fprintf('  %s: W = %s (%d recoverable wideband episodes)\n', X.RULES{q}, W, numel(iw));
end
lines = recoverable_lines(X, PP, REC);
write_lines(X.recov, lines);
meta = study_meta(PP);
save(X.val, 'REC', 'WCH', 'G3', 'meta', 'X');
J = struct('study', 'core_bw', 'smoke', X.smoke, 'params_id', PP.params_id, 'det_id', PP.det_id, ...
    'protocol', X.protocol, 'protocol_sha256', core_bw_rules('sha', X.protocol), 'recoverable', X.recov, ...
    'recoverable_sha256', core_bw_rules('sha', X.recov), 'n_recoverable', nnz([REC.ok]), ...
    'w', cell2struct({WCH.W}', {WCH.rule}', 1), 'created', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
write_lines(X.proto_json, {jsonencode(J, 'PrettyPrint', true)});
fprintf('Frozen: %s (W %s; %d of %d scenarios recoverable). Copy it to %s and commit before the test stage.\n', ...
    X.proto_json, strjoin(strcat({WCH.rule}, '=', {WCH.W}), ', '), nnz([REC.ok]), numel(REC), X.frozen);
end

function thr = plr_threshold(PP, K, sp, C)
% The packet-loss restoration threshold of every (Eb/N0, geometry) of split sp: C.ratio_ok x
% the same flight's clean packet loss + one loss event (packet_share.m), as link_env.m.
nS = numel(PP.ebno); nG = numel(PP.runs{sp});
thr = nan(nS, nG);
for s = 1:nS
    Pc = PP.pools{K.clean, s, K.na, sp};
    for r = 1:nG
        k = Pc.run == PP.runs{sp}(r);
        thr(s, r) = C.ratio_ok * mean(double(Pc.fer(k))) + packet_share('no_action', Pc.fer(k), K.Q);
    end
end
end

function G = g3_check(PP, K, X, EP, B)
% Gate G3: under channel_switch held from the first cycle, every frame after the onset comes
% from the pool band_cover.m names for the channel in use (covered: the configuration
% without channel_switch; a jammer tuned to our channel covers the channel of the hop made
% before the onset), on every validation episode of every hop rule; beside it the
% escape share of the first hop, drawn and enumerated (mid-band and band edge homes, and the
% centred jammers off centre as far as our channel stays covered).
ics = find(strcmp(PP.actions, 'channel_switch'));
G = struct('rule', {}, 'mismatch', {}, 'frames', {}, 'bj', {}, 'drawn', {}, 'mid', {}, 'edge', {}, 'off_centre', {}, ...
    'partial', {}, 'near', {});
for q = 1:numel(X.RULES)
    idx = find(~EP.slice);
    specs = make_specs(X, EP, idx, q, false, false);
    bad = 0; nf = 0;
    for b = 1:numel(specs)
        sp = specs{b}; nv = X.NE; if isfield(sp, 'n_valid'), nv = sp.n_valid; end
        [E, ~] = link_env('reset', PP, K, sp, 1, RandStream('mt19937ar', 'Seed', 61000 + b));
        n0 = zeros(1, X.NE);                            % hops before the onset
        for t = 1:X.T
            [E, ~, ~, info] = link_env('step', E, PP, K, ics * ones(1, X.NE));
            m = info.post & E.cfg_link == ics & K.followable(E.scn); m(nv + 1:end) = false;
            pre = E.t < sp.onset; n0(pre) = E.nhop(pre);
            kh = E.nhop - n0 .* sp.cover_rel;           % a jammer tuned to our channel counts from the onset
            cv = true(1, X.NE); h = kh > 0;
            cv(h) = sp.cover(sub2ind(size(sp.cover), find(h), kh(h)));
            want = ics * ones(1, X.NE); want(cv) = K.strip(ics);
            bad = bad + nnz(m & info.cfg_eff ~= want); nf = nf + nnz(m);
        end
    end
    for bj = unique(EP.bj(idx))
        m = idx(EP.bj(idx) == bj);
        J = PP.scenarios(find([PP.scenarios.bj] == bj & ~[PP.scenarios.slice], 1)).J;
        [mid, edge, offc] = enum_share(J, X.RULES{q}, B);
        G(end+1) = struct('rule', X.RULES{q}, 'mismatch', bad, 'frames', nf, 'bj', bj, 'drawn', mean(~EP.cover{q}(m, 1)), ...
            'mid', mid, 'edge', edge, 'off_centre', offc, 'partial', mean(EP.part{q}(m, :), 'all'), ...
            'near', mean(EP.near{q}(m, :), 'all')); %#ok<AGROW>
    end
    fprintf('  G3 %s: %d of %d frames off the coverage flags\n', X.RULES{q}, bad, nf);
    assert(bad == 0, 'experiment_core_bw:g3', 'G3: %d frames of hop rule %s disagree with band_cover.m', bad, X.RULES{q});
end
end

function [mid, edge, offc] = enum_share(J, rule, B)
% Escape share of the first hop from the middle and the lowest home channel (H1: over its
% uniform targets), and for a centred jammer the mean over centres offset in 0.25 MHz steps
% while our home channel stays covered.
nC = numel(B.f_mhz);
sh = @(h, ctr) first_escape(J, rule, h, ctr, B);
if strcmp(J.kind, 'fixed')
    can = find(band_cover(band_cover('span', J, NaN), B.f_mhz, B.b_ch));
    mid = sh(can(ceil(end / 2)), NaN); edge = sh(can(1), NaN); offc = NaN;
    return
end
mid = sh(B.centre, 0); edge = sh(1, 0); offc = NaN;
if strcmp(J.kind, 'centred')
    o = -(J.half - B.b_ch / 2):0.25:(J.half - B.b_ch / 2);
    offc = mean(arrayfun(@(h) mean(arrayfun(@(x) sh(h, x), o)), 1:nC));
end
end

function e = first_escape(J, rule, h, ctr, B)
% Share of first hops from home h that escape (H1: over its uniform targets).
if isnan(ctr), sp = band_cover('span', J, NaN); else, sp = band_cover('span', J, B.f_mhz(h) + ctr); end
cv = band_cover(sp, B.f_mhz, B.b_ch);
if strcmp(rule, 'H1')
    k = find(abs((1:numel(B.f_mhz)) - h) >= 3);
    e = mean(~cv(k));
else
    e = double(~cv(hop_targets(rule, h, 1, [], B)));
end
end

function lines = recoverable_lines(X, PP, REC)
lines = {sprintf(['# Recoverable scenarios of the bandwidth study, fixed on validation (docs/core_bw_protocol.md 6.4): ' ...
    '>= %d%% of the validation episodes recoverable and the static link harmed (pooled PER above the restoration ' ...
    'threshold). params_id %s, det_id %s'], X.ENV_MIN, PP.params_id, PP.det_id), ...
    ['# rule scenario_index ebno_index scenario B_J_MHz JSR_tot_dB JSR_in_dB EbN0_dB recoverable_pct PER_static ' ...
    'threshold harmed recoverable']};
for i = 1:numel(REC)
    sc = PP.scenarios(REC(i).k);
    lines{end+1} = sprintf('%s %d %d %s %g %.2f %.2f %g %.1f %.4f %.4f %d %d', REC(i).rule, REC(i).k, REC(i).s, ...
        scen_name(PP, REC(i).k), sc.bj, sc.jsr_tot, sc.jsr_in, PP.ebno(REC(i).s), REC(i).rec_pct, REC(i).per, REC(i).thr, ...
        REC(i).harm, REC(i).ok); %#ok<AGROW>
end
end

function n = scen_name(PP, k)
sc = PP.scenarios(k);
if sc.slice, n = sprintf('inb%g_bw%g', sc.jsr_in, sc.bj); else, n = PP.cells(sc.cell).name; end
end

function M = study_meta(PP)
% What the readings need of the pools, without the frames.
M = struct('scenarios', {PP.scenarios}, 'cells', {PP.cells}, 'ebno', PP.ebno, 'actions', {PP.actions}, ...
    'params_id', PP.params_id, 'det_id', PP.det_id, 'cap', PP.cap, 'timing', PP.timing, 'classes', {PP.classes}, ...
    'runs', {PP.runs}, 'smoke', PP.smoke);
end

%% ===================== Test (read once) =====================
function stage_test(X)
J = core_bw_rules('guard', X);
assert(isfile(X.val), 'experiment_core_bw:protocol', '%s not found: run the val stage', X.val);
assert(strcmp(params_id(load('params.mat').params), J.params_id), 'experiment_core_bw:params', ...
    'params.mat names another link model than the frozen protocol');
if ~X.smoke
    assert(~recorded(J.params_id), 'experiment_core_bw:recorded', ...
        'docs/core_bw_read_*.txt records a test reading with params_id %s: the test is read once', J.params_id);
end
marker(X, J.params_id);
fprintf('Test reading started (%s)\n', X.marker);
PP = load_pools(X, true);
assert(strcmp(J.params_id, PP.params_id) && strcmp(J.det_id, PP.det_id), 'experiment_core_bw:pools_changed', ...
    'the pools are not those the protocol was frozen on');
V = load(X.val, 'WCH');
assert(isequal({V.WCH.W}, cellfun(@(r) J.w.(r), {V.WCH.rule}, 'UniformOutput', false)), 'experiment_core_bw:w', ...
    'the validation file''s W differ from the frozen protocol''s');
[PP, ~] = decision_inputs(PP);
p0 = load('params.mat').params; B = band_plan(p0);
K = link_env('tables', PP, 'flight');
EP = episodes(X, PP, 2, B);
na = K.na; fixed = find(~EP.slice);
RES = struct('rule', {}, 'set', {}, 'policy', {}, 'R', {});
for q = 1:numel(X.RULES)
    Pw = PP; Pw.core_wide = J.w.(X.RULES{q});
    sets = {'primary', 1:EP.n, false, false; 'residual', fixed, false, true};
    if q == 1, sets(end+1, :) = {'follower', fixed, true, false}; end
    for si = 1:size(sets, 1)
        pols = {'none', 'blind_core', 'rule_core'};
        if si == 1, pols{end+1} = 'oracle'; end %#ok<AGROW>
        for pk = 1:numel(pols)
            [kind, opt] = policy_of(pols{pk}, na);
            R = run_set(kind, Pw, K, X, EP, sets{si, 2}, q, sets{si, 3}, sets{si, 4}, 2, opt, 81000 + 1000*q + 100*si);
            RES(end+1) = struct('rule', X.RULES{q}, 'set', sets{si, 1}, 'policy', pols{pk}, 'R', R); %#ok<AGROW>
        end
        fprintf('  %s %-9s %d episodes x %d policies\n', X.RULES{q}, sets{si, 1}, numel(sets{si, 2}), numel(pols));
    end
end
MON = monitor_states(PP, K, X, EP, fixed);
meta = study_meta(PP);
EPs = rmfield(EP, {'acr', 'part', 'near'});
save(X.test, 'RES', 'EPs', 'MON', 'meta', 'X', '-v7.3');
fprintf('Saved %s\n', X.test);
end

function MON = monitor_states(PP, K, X, EP, idx)
% The hybrid detector on the static link after the onset, as three states (clean,
% narrowband, wideband; any other class or unknown an error): the decision cycle's monitor
% class (policy_monitor.m through policy_decide.m) and the frame's own argmax.
map = zeros(1, numel(PP.classes) + 1);              % the last: unknown or a class outside the detector's
map(strcmp(PP.classes, 'none')) = 1; map(strcmp(PP.classes, 'tone_jamming')) = 2; map(strcmp(PP.classes, 'jamming')) = 3;
specs = make_specs(X, EP, idx, 1, false, false);
ym = zeros(numel(idx), 1); yf = ym; n = 0;
hm = zeros(numel(idx), 1); hf = hm;
for b = 1:numel(specs)
    sp = specs{b}; nv = X.NE; if isfield(sp, 'n_valid'), nv = sp.n_valid; end
    [E, obs] = link_env('reset', PP, K, sp, 2, RandStream('mt19937ar', 'Seed', 91000 + b));
    mem = []; okm = zeros(1, X.NE); okf = okm; nn = okm;
    want = 2 + strcmp(PP.scen(sp.scn), 'jamming');
    for t = 1:X.T
        pf = E.t >= E.onset;
        [~, mem, d] = policy_decide('rule_esc', obs, E.cfg, mem, PP, [], struct('core', true));
        [~, ix] = ismember(d.cls, PP.classes); ix(ix == 0) = numel(map); sm = map(ix);
        [~, am] = max(obs.probs, [], 2); sf = map(am(:)');
        okm = okm + pf .* (sm == want); okf = okf + pf .* (sf == want); nn = nn + pf;
        [E, ~, obs] = link_env('step', E, PP, K, K.na * ones(1, X.NE));
    end
    j = n + (1:nv);
    hm(j) = okm(1:nv); hf(j) = okf(1:nv); ym(j) = nn(1:nv);
    n = n + nv;
end
MON = struct('ep', idx, 'right_monitor', hm', 'right_frame', hf', 'frames', ym');
end

%% ===================== Report =====================
function stage_report(X)
assert(isfile(X.test), 'experiment_core_bw:test', '%s not found: the test stage comes first', X.test);
L = load(X.test); V = load(X.val, 'G3');
EP = L.EPs; M = L.meta; RES = L.RES; X0 = L.X;
J = jsondecode(fileread(X0.proto_json));
assert(strcmp(J.recoverable_sha256, core_bw_rules('sha', X0.recov)), 'experiment_core_bw:recoverable_changed', ...
    '%s changed since it was frozen', X0.recov);
assert(X0.smoke || (isfile(X0.frozen) && strcmp(core_bw_rules('sha', X0.frozen), core_bw_rules('sha', X0.proto_json))), ...
    'experiment_core_bw:frozen', '%s is no longer the frozen %s the test was read under', X0.proto_json, X0.frozen);
REC = read_recoverable(X0.recov);
p0 = load('params.mat').params;
pay = p0.bits_per_frame / p0.cycle_s;
lines = {sprintf('=== Bandwidth study (docs/core_bw_protocol.md)%s ===', ternary(X0.smoke, ' SMOKE: not a result', '')), ...
    sprintf('params_id %s | det_id %s | test geometries %d per (cell, Eb/N0) x %d onsets | payload %g bit/s', ...
    M.params_id, M.det_id, X0.NGEO(2), X0.REPS, pay), ...
    sprintf('W (validation, frozen): %s', strjoin(cellfun(@(r) sprintf('%s -> %s', r, J.w.(r)), X0.RULES, ...
    'UniformOutput', false), ', '))};
recov = @(rule) recoverable_mask(REC, rule, EP);
for q = 1:numel(X0.RULES)
    lines{end+1} = sprintf('  %s: %d recoverable scenario points (of %d)', X0.RULES{q}, ...
        nnz(strcmp(REC.rule, X0.RULES{q}) & REC.ok), nnz(strcmp(REC.rule, X0.RULES{q}))); %#ok<AGROW>
end
KP = struct();
q1 = X0.RULES{1};
[blk, KP.primary] = per_lines(get_set(RES, q1, 'primary'), EP, recov(q1) & ~EP.slice, X0, pay, ...
    'PRIMARY (H1, 30 dB residual, fixed total power, static jammer)', false);
lines = [lines, blk];
[blk, KP.by_bj] = bj_lines(get_set(RES, q1, 'primary'), EP, recov(q1) & ~EP.slice, X0);
lines = [lines, blk];
lines = [lines, {'', '--- Sensitivities (no verdict of their own; whether any would flip a primary verdict) ---'}];
sens = cell(0, 3);
for q = 1:numel(X0.RULES)
    rl = X0.RULES{q};
    if q > 1, sens(end+1, :) = {sprintf('%s hop rule', rl), get_set(RES, rl, 'primary'), recov(rl) & ~EP.slice}; end %#ok<AGROW>
    sens(end+1, :) = {sprintf('%s, nRF24L01+ residual 24/47 dB', rl), get_set(RES, rl, 'residual'), recov(rl) & ~EP.slice}; %#ok<AGROW>
end
sens(end+1, :) = {'H1, equal in-band level', get_set(RES, q1, 'primary'), recov(q1) & EP.slice};
sens(end+1, :) = {'H1, follower jammer (re-acquires after U[0,5] cycles)', get_set(RES, q1, 'follower'), recov(q1) & ~EP.slice};
KP.sens = struct('name', {}, 'K', {}, 'flip', {});
for i = 1:size(sens, 1)
    [blk, Ks] = per_lines(sens{i, 2}, EP, sens{i, 3}, X0, pay, sens{i, 1}, true);
    a = KP.primary.per; b = Ks.per;
    use = [b.n] > 0 & [a.n] > 0 & strcmp({b.type}, {a.type});
    flip = any(~strcmp({b(use).verdict}, {a(use).verdict}));
    blk{end+1} = sprintf('    flips a primary verdict: %s', ternary(flip, 'YES', 'no')); %#ok<AGROW>
    lines = [lines, blk]; %#ok<AGROW>
    KP.sens(end+1) = struct('name', sens{i, 1}, 'K', Ks, 'flip', flip);
end
[blk, KP.pred] = prediction_lines(get_set(RES, q1, 'primary'), EP, REC, recov(q1), X0, M, J, V.G3);
lines = [lines, blk];
[blk, KP.det] = monitor_lines(L.MON, EP, M);
lines = [lines, blk];
lines = [lines, gate_lines(V.G3, M)];
write_lines(X0.report, lines);
save(X0.kpis, 'KP', 'lines');
fprintf('%s\n', lines{:});
fprintf('Saved %s, %s\n', X0.report, X0.kpis);
end

function REC = read_recoverable(f)
% The frozen list (recoverable_lines): rule, scenario and Eb/N0 indices, recoverable.
t = strtrim(splitlines(fileread(f)));
t = t(~cellfun(@isempty, t) & ~startsWith(t, '#'));
c = cellfun(@(x) strsplit(x, ' '), t, 'UniformOutput', false);
REC = struct('rule', {cellfun(@(x) x{1}, c, 'UniformOutput', false)'}, 'k', cellfun(@(x) str2double(x{2}), c)', ...
    's', cellfun(@(x) str2double(x{3}), c)', 'harm', cellfun(@(x) str2double(x{end - 1}), c)' > 0, ...
    'ok', cellfun(@(x) str2double(x{end}), c)' > 0);
end

function m = recoverable_mask(REC, rule, EP)
% Episodes of the scenarios frozen recoverable under the rule.
j = find(strcmp(REC.rule, rule) & REC.ok);
m = false(1, EP.n);
for i = j, m = m | (EP.k == REC.k(i) & EP.s == REC.s(i)); end
end

function S = get_set(RES, rule, set)
S = RES(strcmp({RES.rule}, rule) & strcmp({RES.set}, set));
end

function R = pol(S, name)
R = S(strcmp({S.policy}, name)).R;
end

function [lines, Kp] = per_lines(S, EP, mask, X, pay, ttl, brief)
% PER reduction vs the static link (verdict), recovery time, goodput and the CNN's
% contribution, pooled and per jamming type, on the episodes of the recoverable scenarios.
lines = {'', sprintf('--- %s ---', ttl)};
Rn = pol(S, 'none'); m0 = mask(Rn.ep);
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
Kp = struct('per', struct('policy', {}, 'type', {}, 'n', {}, 'red', {}, 'lo', {}, 'hi', {}, 'per', {}, 'per_ref', {}, ...
    'verdict', {}), 'rec', struct(), 'gput', struct(), 'cnn', struct());
for pk = {'rule_core', 'blind_core'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        [v, lo, hi] = per_reduction(R.per_post(m), Rn.per_post(m), EP.geom(Rn.ep(m)), X.B, 3);
        vd = core_bw_rules('verdict', v, lo, X.TARGET, nnz(m));
        Kp.per(end+1) = struct('policy', pk{1}, 'type', types{t, 1}, 'n', nnz(m), 'red', v, 'lo', lo, 'hi', hi, ...
            'per', mean(R.per_post(m)), 'per_ref', mean(Rn.per_post(m)), 'verdict', vd);
        lines{end+1} = sprintf('  PER %-10s %-10s n=%5d  %.4f vs %.4f static: reduction %5.1f%% [%5.1f, %5.1f] -> %s', ...
            pk{1}, types{t, 1}, nnz(m), mean(R.per_post(m)), mean(Rn.per_post(m)), 100 * v, 100 * lo, 100 * hi, vd); %#ok<AGROW>
    end
end
if brief, return; end
mr = m0 & Rn.recoverable & Rn.threat;                 % beside it: the per-episode reading (lect_kpis.m)
for pk = {'rule_core', 'blind_core'}
    R = pol(S, pk{1});
    [v, lo, hi] = per_reduction(R.per_post(mr), Rn.per_post(mr), EP.geom(Rn.ep(mr)), X.B, 3);
    lines{end+1} = sprintf('  PER %-10s pooled, recoverable episodes only (n=%d): reduction %5.1f%% [%5.1f, %5.1f]', ...
        pk{1}, nnz(mr), 100 * v, 100 * lo, 100 * hi); %#ok<AGROW>
end
for pk = {'none', 'blind_core', 'rule_core'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        a = qstat(R.t_conf(m)); b = qstat(R.t_rec_det(m));
        [g, glo, ghi] = boot_cluster(pay * R.dlv_post(m), ones(1, nnz(m)), EP.geom(Rn.ep(m)), X.B, 5);
        lines{end+1} = sprintf(['  %-10s %-10s onset->detection %s | detection->restored (%d cycles) %s | goodput ' ...
            '%.0f [%.0f, %.0f] bit/s'], pk{1}, types{t, 1}, a.txt, X.N_RUN, b.txt, g, glo, ghi); %#ok<AGROW>
        Kp.rec.(pk{1}).(types{t, 1}) = struct('det', a, 'rec_det', b); Kp.gput.(pk{1}).(types{t, 1}) = [g glo ghi];
    end
end
Rr = pol(S, 'rule_core'); Rb = pol(S, 'blind_core');
for t = 1:size(types, 1)
    m = m0 & types{t, 2}(Rn.ep); cl = EP.geom(Rn.ep(m));
    [dp, dlo, dhi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, X.B, 6);
    [rr, rlo, rhi] = per_reduction(Rr.per_post(m), Rb.per_post(m), cl, X.B, 7);
    [dg, glo, ghi] = boot_cluster(pay * (Rr.dlv_post(m) - Rb.dlv_post(m)), ones(1, nnz(m)), cl, X.B, 8);
    f = m & isfinite(Rr.t_rec_det) & isfinite(Rb.t_rec_det);
    [dt, tlo, thi] = boot_cluster(Rr.t_rec_det(f) - Rb.t_rec_det(f), ones(1, nnz(f)), EP.geom(Rn.ep(f)), X.B, 9);
    lines{end+1} = sprintf(['  CNN contribution %-10s rule_core - blind_core: PER %+.4f [%+.4f, %+.4f] (reduction %5.1f%% ' ...
        '[%5.1f, %5.1f]) | goodput %+.0f [%+.0f, %+.0f] bit/s | detection->restored %+.2f [%+.2f, %+.2f] cycles on the %d ' ...
        'episodes both recover in (never %.0f%% vs %.0f%%)'], types{t, 1}, dp, dlo, dhi, 100 * rr, 100 * rlo, 100 * rhi, dg, ...
        glo, ghi, dt, tlo, thi, nnz(f), 100 * mean(~isfinite(Rr.t_rec_det(m))), 100 * mean(~isfinite(Rb.t_rec_det(m)))); %#ok<AGROW>
    Kp.cnn.(types{t, 1}) = struct('per', [dp dlo dhi], 'per_red', [rr rlo rhi], 'gput', [dg glo ghi], 'trec', [dt tlo thi], ...
        'n_both', nnz(f));
end
if any(strcmp({S.policy}, 'oracle'))
    Ro = pol(S, 'oracle');
    [v, lo, hi] = per_reduction(Ro.per_post(m0), Rn.per_post(m0), EP.geom(Rn.ep(m0)), X.B, 3);
    lines{end+1} = sprintf('  oracle (one-step, a bound only): PER reduction %5.1f%% [%5.1f, %5.1f]', 100 * v, 100 * lo, 100 * hi);
end
end

function [lines, T] = bj_lines(S, EP, mask, X)
% The PER reduction of both adaptive systems and the CNN's contribution per jammer width.
lines = {'  per jammer width (recoverable scenarios, every JSR_tot and Eb/N0):'};
Rn = pol(S, 'none'); Rr = pol(S, 'rule_core'); Rb = pol(S, 'blind_core'); m0 = mask(Rn.ep);
T = struct('bj', {}, 'n', {}, 'rule', {}, 'blind', {}, 'cnn', {});
for bj = unique(EP.bj(~EP.slice))
    m = m0 & EP.bj(Rn.ep) == bj; cl = EP.geom(Rn.ep(m));
    [a, alo, ahi] = per_reduction(Rr.per_post(m), Rn.per_post(m), cl, X.B, 3);
    [b, blo, bhi] = per_reduction(Rb.per_post(m), Rn.per_post(m), cl, X.B, 3);
    [d, dlo, dhi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, X.B, 6);
    lines{end+1} = sprintf('    B_J %5s n=%5d  rule_core %5.1f%% [%5.1f, %5.1f] | blind_core %5.1f%% [%5.1f, %5.1f] | PER diff %+.4f [%+.4f, %+.4f]', ...
        bj_name(bj), nnz(m), 100 * [a alo ahi], 100 * [b blo bhi], d, dlo, dhi); %#ok<AGROW>
    T(end+1) = struct('bj', bj, 'n', nnz(m), 'rule', [a alo ahi], 'blind', [b blo bhi], 'cnn', [d dlo dhi]); %#ok<AGROW>
end
end

function [lines, P] = prediction_lines(S, EP, REC, rmask, X, M, J, G3)
% The pre-registered predictions P1-P5 with their fixed readings (docs/core_bw_protocol.md
% section 5).
lines = {'', '--- Predictions (written before any run) ---'};
Rn = pol(S, 'none'); Rr = pol(S, 'rule_core'); Rb = pol(S, 'blind_core');
e = Rn.ep; P = struct();
sc = M.scenarios;
r1 = find(strcmp(REC.rule, X.RULES{1}));
bjk = [sc(REC.k(r1)).bj]; totk = [sc(REC.k(r1)).jsr_tot]; slk = [sc(REC.k(r1)).slice];
% P1
m = EP.narrow(e) & EP.tot(e) <= 23 & rmask(e);
p1 = mean(Rr.recovered(m));
m30 = EP.narrow(e) & EP.tot(e) == 30 & rmask(e);
t1 = median(fillmissing(Rr.t_rec_det(m30), 'constant', Inf)); t2 = median(fillmissing(Rb.t_rec_det(m30), 'constant', Inf));
h1 = p1 >= 0.9 && (~any(m30) || t1 > t2);
P.P1 = struct('recovered_le23', p1, 'n30', nnz(m30), 'trec30_rule', t1, 'trec30_blind', t2, 'holds', h1);
lines{end+1} = sprintf(['  P1 narrowband: rule_core recovers %.1f%% of the recoverable CW episodes at JSR_tot <= 23 dB ' ...
    '(>= 90%%); at 30 dB (%d recoverable episodes) median detection->restored %g vs %g cycles blind_core (longer) -> %s'], ...
    100 * p1, nnz(m30), t1, t2, ternary(h1, 'holds', 'does not hold'));
% P2
w1 = J.w.(X.RULES{1}); g = G3(strcmp({G3.rule}, X.RULES{1}) & ismember([G3.bj], [4 8 20]));
P.P2 = struct('W', w1, 'escape', [g.drawn], 'holds', ismember(w1, {'channel_switch', 'channel_switch+rate_reduce'}));
lines{end+1} = sprintf('  P2 wideband 4-20 MHz under H1: W = %s (channel_switch or channel_switch+rate_reduce); first-hop escape %s -> %s', ...
    w1, strjoin(arrayfun(@(x) sprintf('%s MHz %.3f', bj_name(x.bj), x.drawn), g, 'UniformOutput', false), ', '), ...
    ternary(P.P2.holds, 'holds', 'does not hold'));
% P3
m3 = ismember(bjk, [70 83.5]) & totk == 30 & ~slk;
P.P3 = struct('recoverable', nnz(REC.ok(r1(m3))), 'of', nnz(m3), 'holds', ~any(REC.ok(r1(m3))));
lines{end+1} = sprintf('  P3 band-wide jammers (70, 83.5 MHz) at JSR_tot 30 dB: %d of %d scenario points recoverable (0) -> %s', ...
    P.P3.recoverable, P.P3.of, ternary(P.P3.holds, 'holds', 'does not hold'));
% P4
m4 = bjk >= 20 & totk == 4 & ~slk;
P.P4 = struct('harmful', nnz(REC.harm(r1(m4))), 'of', nnz(m4), 'holds', ~any(REC.harm(r1(m4))));
lines{end+1} = sprintf('  P4 20 MHz and wider at JSR_tot 4 dB: %d of %d scenario points harmful (0) -> %s', ...
    P.P4.harmful, P.P4.of, ternary(P.P4.holds, 'holds', 'does not hold'));
% P5
m = EP.narrow(e) & rmask(e) & Rr.recovered & Rb.recovered; cl = EP.geom(e(m));
[dg, glo] = boot_cluster(Rr.dlv_post(m) - Rb.dlv_post(m), ones(1, nnz(m)), cl, X.B, 8);
[~, plo, phi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, X.B, 6);
gr = mean(Rr.dlv_post(m)) / max(mean(Rb.dlv_post(m)), eps);
h5 = glo > 0 && plo <= 0 && phi >= 0;
P.P5 = struct('n', nnz(m), 'gput_ratio', gr, 'gput_diff', dg, 'gput_lo', glo, 'per_ci', [plo phi], 'holds', h5);
lines{end+1} = sprintf(['  P5 narrowband CNN contribution where both recover (%d episodes): goodput x%.2f (difference %.3f, ' ...
    'lower bound %.3f > 0), PER difference [%+.4f, %+.4f] holds 0 -> %s'], nnz(m), gr, dg, glo, plo, phi, ...
    ternary(h5, 'holds', 'does not hold'));
end

function [lines, T] = monitor_lines(MON, EP, M)
% The hybrid's three-state recall per (B_J, JSR_tot, Eb/N0), above and below the detectability
% floor (in-band I/N >= 0 dB: JSR_in + Eb/N0 + 10 log10(bits per symbol) >= 0), no frame dropped.
lines = {'', '--- Detector by bandwidth (analysis; the KPI verdicts are B3c''s and B3''s) ---', ...
    '  hybrid on the static link after the onset, right state of the frames: monitor class | frame argmax'};
e = MON.ep; T = struct('bj', {}, 'tot', {}, 'ebno', {}, 'monitor', {}, 'frame', {}, 'above', {});
fl = EP.inb(e) + M.ebno(EP.s(e)) + 10 * log10(2) >= 0;
for bj = unique(EP.bj(e))
    for tot = unique(EP.tot(e))
        for s = 1:numel(M.ebno)
            m = EP.bj(e) == bj & EP.tot(e) == tot & EP.s(e) == s;
            if ~any(m), continue; end
            T(end+1) = struct('bj', bj, 'tot', tot, 'ebno', M.ebno(s), 'monitor', sum(MON.right_monitor(m)) / sum(MON.frames(m)), ...
                'frame', sum(MON.right_frame(m)) / sum(MON.frames(m)), 'above', all(fl(m))); %#ok<AGROW>
        end
    end
end
for bj = unique([T.bj])
    for ab = [true false]
        m = [T.bj] == bj & [T.above] == ab;
        if ~any(m), continue; end
        lines{end+1} = sprintf('  B_J %5s %s the floor: %.1f%% | %.1f%% over %d (JSR_tot, Eb/N0) points', bj_name(bj), ...
            ternary(ab, 'above', 'below'), 100 * mean([T(m).monitor]), 100 * mean([T(m).frame]), nnz(m)); %#ok<AGROW>
    end
end
end

function lines = gate_lines(G3, M)
lines = {'', '--- Gates ---', sprintf(['  G2: %d simulations, %.2f s per simulation per worker; in-band cap binding share per ' ...
    'cell max %.1f%%'], M.timing.sims, M.timing.s_per_sim, 100 * max(M.cap))};
for i = find(M.cap > 0)
    lines{end+1} = sprintf('    %s %.1f%%', M.cells(i).name, 100 * M.cap(i)); %#ok<AGROW>
end
for g = G3
    lines{end+1} = sprintf(['  G3 %s B_J %5s: %d frames off the flags; first-hop escape drawn %.3f, enumerated mid-band %.3f, ' ...
        'edge %.3f, off-centre %.3f; partial hops %.3f, escaped hops within 4 MHz of the jammer %.3f'], g.rule, ...
        bj_name(g.bj), g.mismatch, g.drawn, g.mid, g.edge, g.off_centre, g.partial, g.near); %#ok<AGROW>
end
end

function [lines, T] = det_table(lines, y, yp, cel, s, cells, ebno, who)
% Recall of the right state per cell and Eb/N0 (set D), above and below the detectability floor.
T = struct('cell', {}, 'ebno', {}, 'recall', {}, 'above', {});
for c = unique(cel(:))'
    for si = unique(s(:))'
        m = cel == c & s == si;
        L = -Inf; if c > 0, L = cells(c).jsr_in; end
        T(end+1) = struct('cell', c, 'ebno', ebno(find(m, 1)), 'recall', mean(yp(m) == y(m)), ...
            'above', c == 0 || L + ebno(find(m, 1)) + 10 * log10(2) >= 0); %#ok<AGROW>
    end
end
for c = unique([T.cell])
    nmc = 'clean'; if c > 0, nmc = cells(c).name; end
    m = [T.cell] == c;
    lines{end+1} = sprintf('  %s %-12s recall %s', who, nmc, strjoin(arrayfun(@(t) sprintf('%g dB %.0f%%%s', t.ebno, ...
        100 * t.recall, ternary(t.above, '', '*')), T(m), 'UniformOutput', false), ' | ')); %#ok<AGROW>
end
lines{end+1} = '  (* below the detectability floor)';
end

%% ===================== Helpers =====================
function Qs = qstat(x)
% Median and p90 over the episodes where it occurs, and the share where it never does.
f = isfinite(x);
Qs = struct('median', NaN, 'p90', NaN, 'never_pct', 100 * mean(~f));
if any(f), Qs.median = median(x(f)); Qs.p90 = prctile(x(f), 90); end
Qs.txt = sprintf('%g/%g (never %.0f%%)', Qs.median, Qs.p90, Qs.never_pct);
end

function s = bj_name(bj)
if bj == 0, s = 'CW'; else, s = sprintf('%g', bj); end
end

function yes = recorded(pid)
% A committed record of a test reading with this link model (docs/core_bw_read_*.txt).
yes = false;
for r = dir('docs/core_bw_read_*.txt')'
    yes = yes || any(strcmp(strtrim(splitlines(fileread(fullfile(r.folder, r.name)))), ['params_id ' pid]));
end
end

function marker(X, pid)
% The test reading starts: time, the code's commit and tree, local changes, the link model's
% params_id and the SHA-256 of the protocol and of the frozen choices.
root = fileparts(fileparts(fileparts(which('experiment_core_bw'))));
g = sprintf('git --no-optional-locks -C "%s" ', root);
[st, o] = system([g 'rev-parse HEAD HEAD:code']);
[sd, d] = system([g 'status --porcelain --untracked-files=all -- code docs/core_bw_protocol.md']);
o = strsplit(strtrim(o)); cm = 'unknown'; tr = 'unknown';
if st == 0 && numel(o) == 2, cm = o{1}; tr = o{2}; end
if st == 0 && (sd ~= 0 || ~isempty(strtrim(d))), cm = [cm ' + local changes']; end
if ~isfolder(X.R), mkdir(X.R); end
write_lines(X.marker, {'bandwidth study (core_bw) test reading started', ['time ' datestr(now, 'yyyy-mm-dd HH:MM:SS')], ...
    ['commit ' cm], ['code_tree ' tr], ['params_id ' pid], [X.protocol ' sha256 ' core_bw_rules('sha', X.protocol)], ...
    [X.proto_json ' sha256 ' core_bw_rules('sha', X.proto_json)]});
end

function write_lines(f, lines)
d = fileparts(f); if ~isempty(d) && ~isfolder(d), mkdir(d); end
fid = fopen(f, 'w');
assert(fid > 0, 'experiment_core_bw:write', 'cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function c = ternary(t, a, b)
if t, c = a; else, c = b; end
end
