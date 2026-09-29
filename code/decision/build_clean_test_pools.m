%% BUILD_CLEAN_TEST_POOLS - Clean-link pools over many independent geometries (D51, D52, D59)
% The false-alarm KPI needs independent trials. This script measures the clean
% link ('none') on 100 new geometries per Eb/N0 (seeds never used before), under
% every configuration (common random numbers, as in build_policy_pools.m), with
% the same detector, frames per geometry and features (pool_cell.m, in parallel).
% Two sets, chosen by CLEAN_SET (default 'test'):
%   'test'  seed block 7 -> data/clean_test_pools.mat: evaluate_policies.m runs
%           one clean episode per geometry (600 independent episodes) and KPI 6
%           is computed over them (D51)
%   'val'   seed block 4 -> data/clean_val_pools.mat: train_dqn.m checks the false
%           alarms of every run on it, so the test set is used once (D52)
%
% Output: data/clean_test_pools.mat or data/clean_val_pools.mat (struct CT)

close all; clc;
warning('off', 'Simulink:cgxe:LeakedJITEngine');
fprintf('=== Clean-link pools over many geometries (D51, D52, D59) ===\n\n');

%% 1. Configuration
if ~exist('CLEAN_SET', 'var'), CLEAN_SET = 'test'; end
switch CLEAN_SET
    case 'test', SP = 7; f_out = 'data/clean_test_pools.mat';
    case 'val',  SP = 4; f_out = 'data/clean_val_pools.mat';
    otherwise, error('build_clean_test_pools: CLEAN_SET must be ''test'' or ''val''');
end
N_GEOM = 100;                                 % geometries per Eb/N0 (at most 99 per seed block + 1)
CHUNK = 10;                                   % geometries per parallel job
N_WORKERS = 6;
opt = struct('F_SUB', 20, 'tw', 10, 'delay_bits', 20);
if exist('SMOKE', 'var') && SMOKE, N_GEOM = 4; CHUNK = 2; end   % reduced chain check (run_stage smoke)

L = load('data/policy_pools.mat', 'PP'); PP = L.PP; clear L
EBNO = PP.ebno; ACTIONS = PP.actions; opt.F_SUB = PP.F_SUB; vrange = PP.speed_range; clear PP
nS = numel(EBNO); nA = numel(ACTIONS);
runs = 100 * SP + (1:N_GEOM);

if isfile(f_out) && dir(f_out).datenum > dir('data/policy_pools.mat').datenum
    Cx = load(f_out, 'CT');
    if isequal(Cx.CT.runs, runs) && isequal(Cx.CT.ebno, EBNO) && isequal(Cx.CT.actions, ACTIONS)
        fprintf('%s is up to date (%d geometries per Eb/N0), nothing to do\n', f_out, N_GEOM);
        clear CLEAN_SET; return
    end
end

S0 = load('params.mat'); p0 = S0.params; p0.quiet_build = true; p0.active_threat = 'none';
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
N = load('data/splits.mat', 'splits');
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', N.splits.norm.feat_mean, 'sd', N.splits.norm.feat_std, 'fs', p0.symbol_rate * p0.sps);
clear N D

%% 2. Simulation: every configuration x Eb/N0 x geometry, clean link, in parallel chunks
nJ = ceil(N_GEOM / CHUNK);
geo = cell(nJ, nS);
for j = 1:nJ
    r = (j-1)*CHUNK + 1 : min(j*CHUNK, N_GEOM);
    for s = 1:nS
        [sd_, v_] = arrayfun(@(k) pool_seed(1, s, SP, k, vrange), r);
        geo{j, s} = struct('seed', sd_, 'speed', v_, 'run', runs(r));
    end
end
pl = gcp('nocreate');
if isempty(pl) || pl.NumWorkers ~= N_WORKERS
    delete(pl); pl = parpool('Processes', N_WORKERS);
end
repo = pwd;
spmd
    pool_worker_init(repo);
end
t0 = tic;
res = cell(1, nJ);
parfor j = 1:nJ
    res{j} = pool_cell(p0, 'none', ACTIONS, EBNO, geo(j, :), det, opt);
    fprintf('  geometries chunk %d/%d done\n', j, nJ);
end
pools = cell(1, nS, nA);
f = fieldnames(res{1}{1, 1, 1});
for s = 1:nS
    for a = 1:nA
        Q = res{1}{s, a, 1};
        for j = 2:nJ
            for k = 1:numel(f), Q.(f{k}) = [Q.(f{k}); res{j}{s, a, 1}.(f{k})]; end
        end
        pools{1, s, a} = Q;
    end
end

CT = struct('pools', {pools}, 'runs', runs, 'ebno', EBNO, 'actions', {ACTIONS}, 'n_geom', N_GEOM, ...
    'set', CLEAN_SET, 'created', datestr(now));
save(f_out, 'CT', '-v7.3');
fprintf('Saved %s (%.1f min)\n', f_out, toc(t0)/60);
clear CLEAN_SET
