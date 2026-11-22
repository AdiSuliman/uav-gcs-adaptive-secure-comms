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
verifyEqual(tc, S.speed.test.point, max(bm) - min(bm), 'AbsTol', 1e-12);
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

%% ---------- L3 at system level, rule_core3 (CORE_BW) ----------
function test_l3_core3_not_flown_then_flown(tc)
d = fullfile(tc.TestData.tmp, 'l3'); mkdir(d);
n = 40;
EPs = struct('c', 2 + mod(0:n - 1, 3), 'n', n);
mk = @(fc, fs) struct('scn', EPs.c, 'ep', 1:n, 'fc_t', fc, 'onset', 5 * ones(1, n), 'false_sw', fs, 'switches', double(fc > 0));
fc3 = zeros(1, n); fc3(1:3) = [2 5 6];                         % 2 and 5 decided on clean frames (<= onset), 6 after
RES = struct('rule', {'H1', 'H1'}, 'set', {'primary', 'primary'}, 'policy', {'none', 'rule_core3'}, ...
    'R', {mk(zeros(1, n), zeros(1, n)), mk(fc3, [1, zeros(1, n - 1)])});
f = fullfile(d, 'test_readings.mat'); save(f, 'RES', 'EPs', '-v7.3');
t1 = fullfile(d, 'core_cnn.txt'); fid = fopen(t1, 'w');
fprintf(fid, 'core CNN, window N = 3 (official)\n  false alarms, clean frames (<= 5%%)    0.17%% [0.00, 0.53]  met (committed)\n'); fclose(fid);
t2 = fullfile(d, 'policy_evaluation.txt'); fid = fopen(t2, 'w');
fprintf(fid, '  rule   264 / 2376 =  11.11%%\n  core: rule + escalation                   264 / 2376 =  11.11%%   upper  12.23%%\n'); fclose(fid);
out = fullfile(tc.TestData.tmp, 'o_l3a');
S = side_l3_core3(f, out, t1, t2);
verifyFalse(tc, S.flown);
txt = fileread(fullfile(out, 'side_l3_core3.txt'));
verifyTrue(tc, contains(txt, 'NOT FLOWN'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
verifyTrue(tc, contains(txt, '0.17% [0.00, 0.53]') && contains(txt, 'core: rule + escalation') && contains(txt, '12.23%'));
p = S.proxy(strcmp({S.proxy.policy}, 'rule_core3'));
verifyEqual(tc, [p.k_pre, p.n, p.pre_frames, p.k_healthy], [2, n, 5 * n, 1]);
p0 = S.proxy(strcmp({S.proxy.policy}, 'none'));
verifyEqual(tc, [p0.k_pre, p0.k_healthy], [0 0]);
% clean-link episodes flown: the share and its one-sided bound
RES(2).R.scn(1:10) = 1; RES(2).R.switches = double(1:n <= 3);
f2 = fullfile(d, 'test_readings2.mat'); save(f2, 'RES', 'EPs', '-v7.3');
S2 = side_l3_core3(f2, fullfile(tc.TestData.tmp, 'o_l3b'));
verifyTrue(tc, S2.flown);
r = S2.rows(strcmp({S2.rows.policy}, 'rule_core3'));
verifyEqual(tc, [r.k, r.n], [3, 10]);
verifyEqual(tc, r.upper, betaincinv(0.95, 4, 7), 'AbsTol', 1e-12);
verifyTrue(tc, contains(fileread(fullfile(tc.TestData.tmp, 'o_l3b', 'side_l3_core3.txt')), 'not given'));
end

%% ---------- CNN contribution per B_J (CORE_BW) ----------
function test_bj_cnn3_reproduces_then_reads(tc)
[tree, Rs, EPs, m0, pay] = bw_tree(tc, 'bw1', false);
out = fullfile(tc.TestData.tmp, 'o_bj1');
S = side_bj_cnn3(tree, out);
txt = fileread(fullfile(out, 'side_bj_cnn3.txt'));
verifyTrue(tc, contains(txt, 'reproduced exactly first'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing'));
r = S.rows(strcmp({S.rows.pair}, 'rule_core3 - blind_core') & [S.rows.bj] == 20 & isnan([S.rows.tot]));
m = m0 & EPs.bj == 20;
[g, glo, ghi] = boot_cluster(pay * (Rs.rule_core3.dlv_post(m) - Rs.blind_core.dlv_post(m)), ones(1, nnz(m)), EPs.geom(m), 200, 8);
verifyEqual(tc, r.gput, [g glo ghi]);
verifyEqual(tc, r.n, nnz(m));
fb = m & isfinite(Rs.rule_core3.t_rec_det) & isfinite(Rs.blind_core.t_rec_det);
verifyEqual(tc, r.n_both, nnz(fb));
verifyEqual(tc, r.trec(1), mean(Rs.rule_core3.t_rec_det(fb) - Rs.blind_core.t_rec_det(fb)), 'AbsTol', 1e-12);
r2 = S.rows(strcmp({S.rows.pair}, 'rule_core3 - blind_core') & [S.rows.bj] == 0 & [S.rows.tot] == 10);
verifyEqual(tc, r2.n, nnz(m0 & EPs.bj == 0 & EPs.tot == 10));
verifyEqual(tc, numel(S.rows), 2 * 2 * 3);                     % two pairs x two widths x (every JSR_tot, 4 dB, 10 dB)
% the report's numbers not reproduced: nothing is written
tree2 = bw_tree(tc, 'bw2', true);
out2 = fullfile(tc.TestData.tmp, 'o_bj2');
verifyError(tc, @() side_bj_cnn3(tree2, out2), 'side_bj:reproduce');
verifyFalse(tc, isfolder(out2));
end

function [tree, Rs, EPs, m0, pay] = bw_tree(tc, name, spoil)
% A CORE_BW tree of 80 episodes: CW and 20 MHz at JSR_tot 4 and 10 dB, two Eb/N0, ten geometries; one
% scenario point not recoverable; its report numbers computed as experiment_core_bw.m does.
tree = fullfile(tc.TestData.tmp, name); d = fullfile(tree, 'results', 'core_bw'); mkdir(d);
params = struct('bits_per_frame', 1000, 'cycle_s', 0.0625); save(fullfile(tree, 'params.mat'), 'params');   % 16 kbit/s, exact in binary
pay = 16000;
[k, s, r] = ndgrid(1:4, 1:2, 1:10);
bjv = [0 0 20 20]; totv = [4 10 4 10];
EPs = struct('k', k(:)', 's', s(:)', 'r', r(:)', 'n', 80);
EPs.bj = bjv(EPs.k); EPs.tot = totv(EPs.k); EPs.slice = false(1, 80); EPs.occ = false(1, 80);
EPs.narrow = EPs.bj == 0; EPs.geom = 1000 * EPs.s + EPs.r; EPs.c = EPs.k + 1;
fid = fopen(fullfile(d, 'recoverable.txt'), 'w');
fprintf(fid, '# header\n# columns\n');
for kk = 1:4
    for ss = 1:2, fprintf(fid, 'H1 %d %d x 0 0 0 0 100 1 1 1 %d\n', kk, ss, ~(kk == 4 && ss == 2)); end
end
fclose(fid);
m0 = ~(EPs.k == 4 & EPs.s == 2);
rs = RandStream('mt19937ar', 'Seed', 11);
P = {'none', 'blind_core', 'rule_core', 'rule_core3'};
Rs = struct(); RES = struct('rule', {}, 'set', {}, 'policy', {}, 'R', {});
for i = 1:numel(P)
    t = randi(rs, 6, 1, 80) - 1; t(rand(rs, 1, 80) < 0.15) = NaN;
    R = struct('ep', 1:80, 'per_post', rand(rs, 1, 80), 'dlv_post', rand(rs, 1, 80), 't_rec_det', t);
    Rs.(P{i}) = R;
    RES(end+1) = struct('rule', 'H1', 'set', 'primary', 'policy', P{i}, 'R', R); %#ok<AGROW>
end
X = struct('RULES', {{'H1'}}, 'B', 200); %#ok<NASGU>
save(fullfile(d, 'test_readings.mat'), 'RES', 'EPs', 'X', '-v7.3');
types = {'pooled', true(1, 80); 'narrowband', EPs.narrow; 'wideband', ~EPs.narrow};
KP = struct('primary', struct('cnn', struct(), 'cnn_hybrid', struct()), 'by_bj', struct('bj', {0, 20}, 'cnn3', {[], []}));
pr = {'rule_core3', 'cnn'; 'rule_core', 'cnn_hybrid'};
for c = 1:2
    for ti = 1:3
        KP.primary.(pr{c, 2}).(types{ti, 1}) = kp_pair(Rs.(pr{c, 1}), Rs.blind_core, m0 & types{ti, 2}, EPs, pay);
    end
end
for b = 1:2
    m = m0 & EPs.bj == KP.by_bj(b).bj;
    [dd, lo, hi] = boot_cluster(Rs.rule_core3.per_post(m) - Rs.blind_core.per_post(m), ones(1, nnz(m)), EPs.geom(m), 200, 6);
    KP.by_bj(b).cnn3 = [dd lo hi];
end
if spoil, KP.primary.cnn.pooled.gput(1) = KP.primary.cnn.pooled.gput(1) + 1; end
lines = {'report'}; %#ok<NASGU>
save(fullfile(d, 'core_bw_kpis.mat'), 'KP', 'lines');
end

function V = kp_pair(Rr, Rb, m, EP, pay)
cl = EP.geom(m);
[dp, dlo, dhi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, 200, 6);
[rr, rlo, rhi] = per_reduction(Rr.per_post(m), Rb.per_post(m), cl, 200, 7);
[dg, glo, ghi] = boot_cluster(pay * (Rr.dlv_post(m) - Rb.dlv_post(m)), ones(1, nnz(m)), cl, 200, 8);
f = m & isfinite(Rr.t_rec_det) & isfinite(Rb.t_rec_det);
[dt, tlo, thi] = boot_cluster(Rr.t_rec_det(f) - Rb.t_rec_det(f), ones(1, nnz(f)), EP.geom(f), 200, 9);
V = struct('per', [dp dlo dhi], 'per_red', [rr rlo rhi], 'gput', [dg glo ghi], 'trec', [dt tlo thi], 'n_both', nnz(f));
end

%% ---------- three-state CNN, test confusion matrix ----------
function test_core_cnn_confusion(tc)
d = fullfile(tc.TestData.tmp, 'cm'); mkdir(d);
state = repelem(1:3, 100)'; run = repelem(1:30, 10)';
win = state; win([5 150 250]) = [3 1 1];
frm = state; frm(1:4) = 2;
hyb = state; hyb([10 20]) = 0;
cpred = struct('state', state, 'core_window', win, 'core_frame', frm, 'hybrid', hyb, 'run', run, 'N', 3, ...
    'states', {{'clean', 'narrowband jamming', 'wideband jamming'}}); %#ok<NASGU>
f = fullfile(d, 'core_cnn_predictions.mat'); save(f, 'cpred');
cw = [99 0 1 0; 1 99 0 0; 1 0 99 0]; cf = [96 4 0 0; 0 100 0 0; 0 0 100 0]; ch = [98 0 0 2; 0 100 0 0; 0 0 100 0];
core = struct('metrics', {{struct('cm', ch), struct('cm', cw), struct('cm', cf)}});
fc = fullfile(d, 'core_cnn.mat'); save(fc, 'core');
out = fullfile(tc.TestData.tmp, 'o_cm1');
S = side_core_cnn_confusion(f, out, fc);
verifyEqual(tc, {S.rows.reader}, {'core CNN, window N = 3 (official)', 'core CNN, per frame', 'hybrid (monitor class)'});
verifyEqual(tc, S.rows(1).cm, cw); verifyEqual(tc, S.rows(2).cm, cf); verifyEqual(tc, S.rows(3).cm, ch);
verifyEqual(tc, S.rows(1).recall, [0.99 0.99 0.99], 'AbsTol', 1e-12);
verifyEqual(tc, S.rows(1).precision, [99 / 101, 1, 99 / 100], 'AbsTol', 1e-12);
verifyEqual(tc, S.rows(3).recall(1), 0.98, 'AbsTol', 1e-12);
verifyTrue(tc, all(strcmp({S.rows.registered}, 'equals the registered matrix')));
verifyLessThanOrEqual(tc, S.rows(1).recall_ci(:, 1)', S.rows(1).recall);
txt = fileread(fullfile(out, 'side_core_cnn_confusion.txt'));
verifyTrue(tc, contains(txt, 'side reading, decides nothing') && contains(txt, 'recall [95%]'));
core.metrics{2}.cm(1, 1) = 98; save(fc, 'core');
S2 = side_core_cnn_confusion(f, fullfile(tc.TestData.tmp, 'o_cm2'), fc);
verifyEqual(tc, S2.rows(1).registered, 'DIFFERS from the registered matrix');
S3 = side_core_cnn_confusion(f, fullfile(tc.TestData.tmp, 'o_cm3'));
verifyEqual(tc, S3.rows(1).registered, 'not compared');
end
