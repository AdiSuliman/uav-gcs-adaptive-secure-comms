function tests = test_side_readers
%TEST_SIDE_READERS  Tests of the labelled side readings (code/evaluation/side) on small synthetic inputs built
%   here, in temporary folders. No project data. Run from the repository root:
%   results = runtests('code/tests/test_side_readers.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.tmp = tempname;
mkdir(tc.TestData.tmp);
end

function teardownOnce(tc)
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

%% ---------- helpers ----------
function [KP, ALL, cells] = synth_eval(seed, with_det)
% Three policies over 11 pool cells: none, jamming x3, path_loss x3, two combined x2 severities.
rng(seed);
cells = [{'none'}, repmat({'jamming'}, 1, 3), repmat({'path_loss'}, 1, 3), repmat({'jamming+path_loss'}, 1, 2), ...
    repmat({'tone_jamming+path_loss'}, 1, 2)];
N = 80;
scn = randi(numel(cells), 1, N);
thr = ~strcmp(cells(scn), 'none');
rec = rand(1, N) < 0.8;
geom = mod(0:N - 1, 20) + 1;
ALL = cell(1, 3);
for p = 1:3
    R = struct('scn', scn, 'threat', thr, 'recoverable', rec, 'geom', geom);
    R.t_rec = nan(1, N); R.t_conf = nan(1, N); R.t_rec_det = nan(1, N);
    ok = rand(1, N) < 0.6 + 0.1 * p;
    R.t_rec(ok) = randi(24, 1, sum(ok));
    if p > 1
        dt = rand(1, N) < 0.8;
        R.t_conf(dt) = randi(5, 1, sum(dt)) - 1;
        rd = dt & rand(1, N) < 0.8;
        R.t_rec_det(rd) = randi(15, 1, sum(rd)) - 1;
    end
    if ~with_det, R = rmfield(R, {'t_conf', 't_rec_det'}); end
    ALL{p} = R;
end
th = {'jamming', 'path_loss', 'jamming+path_loss', 'tone_jamming+path_loss'};
sh = nan(1, 4);
for i = 1:4
    m = strcmp(cells(scn), th{i}) & thr;
    sh(i) = mean(rec(m));
end
KP = struct('threats', {th}, 'sev_names', {{'a', 'b', 'c'}}, 'recoverable_share', sh);
end

function f = save_eval(tc, name, KP, ALL)
d = fullfile(tc.TestData.tmp, name); mkdir(d);
f = fullfile(d, 'policy_evaluation.mat');
POL = {'none', 'blind_esc', 'rule_esc'}; LBL = {'no response', 'blind', 'rule'}; iDQN = 3; %#ok<NASGU>
save(f, 'ALL', 'POL', 'LBL', 'iDQN', 'KP');
end

%% ---------- shared helpers ----------
function test_sha_cp_and_out_dir(tc)
mkdir(fullfile(tc.TestData.tmp, 'in'));
f = fullfile(tc.TestData.tmp, 'in', 'abc.txt');
fid = fopen(f, 'w'); fwrite(fid, 'abc'); fclose(fid);
verifyEqual(tc, side_sha256(f), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
[lo, hi] = side_cp(0, 10); verifyEqual(tc, [lo hi], [0 0.3085], 'AbsTol', 1e-3);
[lo, hi] = side_cp(5, 10); verifyEqual(tc, [lo hi], [0.1871 0.8129], 'AbsTol', 1e-3);
[lo, hi] = side_cp(10, 10); verifyEqual(tc, hi, 1); verifyEqual(tc, lo, 0.6915, 'AbsTol', 1e-3);
[lo, hi] = side_cp(0, 0); verifyTrue(tc, isnan(lo) && isnan(hi));
o = fullfile(tc.TestData.tmp, 'o1');
side_out_dir(o, f);
verifyTrue(tc, isfolder(o));
verifyError(tc, @() side_out_dir(o, f), 'side_out_dir:exists');
verifyError(tc, @() side_out_dir(fullfile(tc.TestData.tmp, 'in', 'inside'), f), 'side_out_dir:inside');
side_write(o, 'x', {'a', 'b'}, struct('v', 1:3));
verifyTrue(tc, isfile(fullfile(o, 'x.txt')) && isfile(fullfile(o, 'x.mat')));
verifyEmpty(tc, dir(fullfile(o, '*.part*')));
verifyError(tc, @() side_write(o, 'x', {'c'}), 'side_write:exists');
t = fileread(fullfile(o, 'x.txt')); verifyEqual(tc, strtrim(t), sprintf('a\nb'));
end

function test_pool_names(tc)
[KP, ALL, cells] = synth_eval(1, true);
[nm, info] = side_pool_names(KP, ALL{1});
verifyEqual(tc, nm, cells(ALL{1}.scn));
verifyEqual(tc, info.ncells, numel(cells));
KP.recoverable_share(2) = KP.recoverable_share(2) + 0.2;
verifyError(tc, @() side_pool_names(KP, ALL{1}), 'side_pool_names:nomatch');
[KP, ALL, cells] = synth_eval(1, true);
nm2 = side_pool_names(KP, ALL{1}, cells);
verifyEqual(tc, nm2, nm);
end

%% ---------- D123 ----------
function test_d123_counts_and_files(tc)
[KP, ALL, cells] = synth_eval(2, true);
f = save_eval(tc, 'd123a', KP, ALL);
out = fullfile(tc.TestData.tmp, 'o_d123a');
S = side_d123_failsafe(f, out, 'synthetic');
txt = fileread(fullfile(out, 'side_d123.txt'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
verifyTrue(tc, contains(txt, side_sha256(f)));
verifyTrue(tc, contains(txt, 'input: '));
verifyTrue(tc, isfile(fullfile(out, 'side_d123.mat')));
% counts for policy 3, mask all threats, onset reference
R = ALL{3}; nm = cells(R.scn);
mk = R.recoverable & R.threat;
t = R.t_rec + 4;
row = S.rows(strcmp({S.rows.policy}, 'rule_esc') & strcmp({S.rows.mask}, 'all threats') & strcmp({S.rows.ref}, 'onset'));
verifyEqual(tc, row.n, sum(mk));
verifyEqual(tc, row.k, [sum(t(mk) <= 30), sum(isfinite(t(mk))), sum(isfinite(t(mk)))]);
verifyEqual(tc, row.kcens, sum(~isfinite(t(mk))));
verifyEqual(tc, row.k(1) + row.kcens, row.n);
[lo, hi] = side_cp(row.k(1), row.n);
verifyEqual(tc, row.ci(1, :), [lo hi], 'AbsTol', 1e-12);
% jamming mask uses the five jamming names, combined ones excluded
jm = mk & ismember(nm, {'jamming', 'noise_burst', 'reactive_jamming', 'sweeping_jammer', 'tone_jamming'});
rowj = S.rows(strcmp({S.rows.policy}, 'rule_esc') & strcmp({S.rows.mask}, 'jamming threats') & strcmp({S.rows.ref}, 'onset'));
verifyEqual(tc, rowj.n, sum(jm));
% via detection
td = R.t_conf + R.t_rec_det + 4;
rowd = S.rows(strcmp({S.rows.policy}, 'rule_esc') & strcmp({S.rows.mask}, 'all threats') & strcmp({S.rows.ref}, 'onset via detection'));
verifyEqual(tc, rowd.k(1), sum(td(mk) <= 30));
verifyEqual(tc, rowd.kcens, sum(~isfinite(td(mk))));
% from detection: detected episodes only
rowf = S.rows(strcmp({S.rows.policy}, 'rule_esc') & strcmp({S.rows.mask}, 'all threats') & strcmp({S.rows.ref}, 'from detection'));
dm = mk & isfinite(R.t_conf);
verifyEqual(tc, rowf.n, sum(dm));
verifyEqual(tc, rowf.k(1), sum(R.t_rec_det(dm) + 4 <= 30));
% static policy has no detector: nothing detected
rows0 = S.rows(strcmp({S.rows.policy}, 'none') & strcmp({S.rows.ref}, 'from detection') & strcmp({S.rows.mask}, 'all threats'));
verifyEqual(tc, rows0.n, 0);
% an existing output folder is refused
verifyError(tc, @() side_d123_failsafe(f, out, 'again'), 'side_out_dir:exists');
end

function test_d123_missing_fields_are_reported(tc)
[KP, ALL] = synth_eval(3, false);
f = save_eval(tc, 'd123b', KP, ALL);
out = fullfile(tc.TestData.tmp, 'o_d123b');
S = side_d123_failsafe(f, out, 'no detection fields');
txt = fileread(fullfile(out, 'side_d123.txt'));
verifyTrue(tc, contains(txt, 'FIELD ABSENT (t_conf, t_rec_det)'));
r = S.rows(strcmp({S.rows.ref}, 'onset') & strcmp({S.rows.policy}, 'none') & strcmp({S.rows.mask}, 'all threats'));
verifyGreaterThan(tc, r.n, 0);
r2 = S.rows(strcmp({S.rows.ref}, 'from detection'));
verifyTrue(tc, all(isnan([r2.n])));
end

%% ---------- D107 ----------
function test_d107_cells_stricter_than_geometries(tc)
A = synth_aprime();
d = fullfile(tc.TestData.tmp, 'd107'); mkdir(d);
f = fullfile(d, 'aprime_agents.mat'); aprime = A; %#ok<NASGU>
save(f, 'aprime', '-v7.3');
out = fullfile(tc.TestData.tmp, 'o_d107');
S = side_d107_cells(f, out);
q = S.per_penalty{1}; h = q.thr(1);
verifyEqual(tc, h.threat, 'antenna_fault');
verifyEqual(tc, h.geom, [2 3 4]);
verifyEqual(tc, h.n_geom, 3); verifyEqual(tc, h.n_cells, 18);
verifyEqual(tc, h.n_cells_neg, 1); verifyEqual(tc, h.n_geom_neg, 0);
verifyTrue(tc, h.bprime_geom); verifyFalse(tc, h.bprime_cells);
i = find(h.cell_s == 2 & h.cell_r == 3);
verifyEqual(tc, h.cell_diff(i), -1, 'AbsTol', 1e-12);
verifyEqual(tc, h.cell_n(i), 3);
verifyEqual(tc, q.n_clusters, numel(unique(h.cell_key)) + numel(unique(q.thr(2).cell_key)) - numel(intersect(h.cell_key, q.thr(2).cell_key)));
txt = fileread(fullfile(out, 'side_d107_cells.txt'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
verifyTrue(tc, contains(txt, 'a cell is negative'));
verifyTrue(tc, contains(txt, 'none negative'));
end

function A = synth_aprime()
thr = {}; s = []; r = []; harm = [];
for si = 1:6
    for ri = 1:6
        for k = 1:3
            thr{end+1} = 'antenna_fault'; s(end+1) = si; r(end+1) = ri; harm(end+1) = ismember(ri, 2:4); %#ok<AGROW>
        end
        thr{end+1} = 'airframe_shadowing'; s(end+1) = si; r(end+1) = ri; harm(end+1) = ismember(ri, 2:3); %#ok<AGROW>
    end
end
n = numel(s);
EP = struct('scn', ones(1, n), 's', s, 'r', r, 'threat', {thr}, 'harmed', logical(harm));
runs = struct('pen', {}, 'gamma', {}, 'seed', {}, 'nothreat', {}, 'plain', {});
for sd = 1:2
    nt = zeros(n, 1); pl = zeros(n, 1);
    for i = 1:n
        if EP.harmed(i), nt(i) = 1; pl(i) = 0; else, nt(i) = 1; pl(i) = 1; end
        if s(i) == 2 && r(i) == 3 && strcmp(thr{i}, 'antenna_fault'), nt(i) = 0; pl(i) = 1; end
    end
    mk = @(x) struct('recovered', x, 'held', x, 'recoverable', true(n, 1), 'threat', true(n, 1));
    runs(end+1) = struct('pen', 120, 'gamma', 0.5, 'seed', sd, 'nothreat', mk(nt), 'plain', mk(pl)); %#ok<AGROW>
end
A = struct('episodes', EP, 'runs', runs);
end

%% ---------- speed, P1 wrapper ----------
function test_speed_p1_post_hoc(tc)
rng(5);
edges = [29 70 100 130 161];
[sg, rg] = ndgrid(1:3, 1:16);
s = repmat(sg(:)', 2, 1); r = repmat(rg(:)', 2, 1);
s = s(:)'; r = r(:)';
n = numel(s);
speed = 30 + 8 * r;
band = 1 + sum(speed(:) >= edges(2:end - 1), 2)';
rec = double(rand(1, n) < 0.7 + 0.04 * band);
mk = @(x) struct('recovered', x, 'speed', speed, 'split', ones(1, n), 'geom', 1000 * s + r, 's', s, 'scn', ones(1, n), ...
    'recoverable', true(1, n), 'threat', true(1, n));
RES = cell(1, 2); RES{1, 1} = mk(zeros(1, n)); RES{1, 2} = mk(rec);
POL = {'none', 'dqn'}; iDQN = 2;
bm = arrayfun(@(b) mean(rec(band == b)), 1:4);
KP = struct('speed_bins', edges);
d = fullfile(tc.TestData.tmp, 'sp'); mkdir(d);
f = fullfile(d, 'policy_evaluation.mat'); save(f, 'RES', 'POL', 'iDQN', 'KP');
out = fullfile(tc.TestData.tmp, 'o_sp');
S = side_speed_p1(f, out);
verifyEqual(tc, S.speed.point, max(bm) - min(bm), 'AbsTol', 1e-12);
txt = fileread(fullfile(out, 'side_speed_p1.txt'));
verifyTrue(tc, contains(txt, 'post hoc, added after the reading'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
verifyTrue(tc, contains(txt, 'Eb/N0 points only'));
verifyFalse(tc, contains(txt, 'NOT REPRODUCED'));
KP.speed_spread = 100 * [max(bm) - min(bm), 0, 1]; %#ok<NASGU>
f2 = fullfile(d, 'pe2.mat'); save(f2, 'RES', 'POL', 'iDQN', 'KP');
out2 = fullfile(tc.TestData.tmp, 'o_sp2');
S2 = side_speed_p1(f2, out2);
verifyTrue(tc, S2.speed.reproduced);
verifyTrue(tc, contains(fileread(fullfile(out2, 'side_speed_p1.txt')), 'reproduced here: yes'));
end

function test_k6_p1_refuses_without_saved_split(tc)
tree = fullfile(tc.TestData.tmp, 'tree_k6'); mkdir(fullfile(tree, 'results')); mkdir(fullfile(tree, 'data'));
out = fullfile(tc.TestData.tmp, 'o_k6a');
verifyError(tc, @() side_k6_split_p1(tree, out), 'side_k6:refused');
txt = fileread(fullfile(out, 'side_k6_split_p1.txt'));
verifyTrue(tc, contains(txt, 'REFUSED'));
verifyTrue(tc, contains(txt, 'pool rebuild'));
% a tree that holds a saved split: printed
rng(7);
n = 60; flag = rand(2, n) < 0.1;
cov = struct('lk', 20 * rand(1, n) - 5, 'speed', 30 + 130 * rand(1, n), 'speed_bins', linspace(29, 161, 5), ...
    'bank', 60 * rand(1, n), 'hide', rand(1, n) < 0.2);
K6C = kpi6_split(flag, mod(0:n - 1, 20) + 1, cov, {'DQN', 'rule'}, 200); %#ok<NASGU>
save(fullfile(tree, 'results', 'dqn_k6_split.mat'), 'K6C');
out2 = fullfile(tc.TestData.tmp, 'o_k6b');
S = side_k6_split_p1(tree, out2);
verifyEqual(tc, S.status, 'printed');
txt = fileread(fullfile(out2, 'side_k6_split_p1.txt'));
verifyTrue(tc, contains(txt, 'estimated link K'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
end

%% ---------- hides, test pools ----------
function test_hides_test_wiring_with_stub(tc)
% clean_hides.m is replaced by a stub on a folder put first on the path: the reader's own arithmetic and
% files are tested, not the geometry.
stub = fullfile(tc.TestData.tmp, 'stub'); mkdir(stub);
fid = fopen(fullfile(stub, 'clean_hides.m'), 'w');
fprintf(fid, 'function H = clean_hides(cov, ebno, p0, level_db, event_frame, frames)\nH = mod(cov.seed, 4) == 0;\nend\n');
fclose(fid);
addpath(stub, '-begin'); c = onCleanup(@() rmpath(stub));
tree = fullfile(tc.TestData.tmp, 'tree_h'); mkdir(fullfile(tree, 'data'));
params = struct('n_rx', 3); save(fullfile(tree, 'params.mat'), 'params');
nS = 3; nF = 40;
z = nan(nS, nF); seed = reshape(1:nS * nF, nS, nF);
cov = struct('seed', seed, 'speed', z, 'alt_m', z, 'k_sig', z, 'aoa', nan(nS, nF, 3), 'rho', z);
cov.seed(3, 31:40) = NaN;
CT = struct('cov', cov, 'ebno', [9 12 15], 'pools', {{ones(10)}}); %#ok<NASGU>
save(fullfile(tree, 'data', 'clean_test_pools.mat'), 'CT', '-v7.3');
out = fullfile(tc.TestData.tmp, 'o_h');
S = side_hides_test(tree, out);
okm = isfinite(cov.seed);
H = mod(cov.seed, 4) == 0 & okm;
verifyEqual(tc, S.n, sum(okm(:)));
verifyEqual(tc, S.k, sum(H(:)));
verifyEqual(tc, [S.rows.k], sum(H, 2)');
verifyEqual(tc, [S.rows.n], sum(okm, 2)');
txt = fileread(fullfile(out, 'side_hides_test.txt'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
verifyTrue(tc, contains(txt, 'input size:'));
verifyTrue(tc, contains(txt, 'loaded:'));
verifyTrue(tc, contains(txt, 'variables in the file: CT'));
end
