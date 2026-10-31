function tests = test_p1r_post_hoc
%TEST_P1R_POST_HOC  The post-hoc rows on a saved policy_evaluation.mat (p1r_post_hoc.m) on a synthetic
%   evaluation: the link-limited tags, the gate that reproduces KP.per_ebno and KP.per_speed, the rows per
%   Eb/N0 with their deficit split by threat, the A' readout per speed band, and the whole run on files.
%   Run from the repository root: results = runtests('code/tests/test_p1r_post_hoc.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function [E, scen] = synth()
% Cells 1 none, 2 jamming, 3 antenna_fault, 4 path_loss; Eb/N0 3, 9, 15 dB; 10 flights at 25..160 km/h, two onsets.
% Harmed (no response fails): antenna_fault always, path_loss at 3 dB, jamming on flights 1-2. The DQN fails on
% antenna_fault from flight 8 on and on jamming at 3 dB, flight 10. One episode (path_loss, 3 dB, flight 10)
% is not recoverable.
scen = {'none'; 'jamming'; 'antenna_fault'; 'path_loss'};
[sc, s, r, ~] = ndgrid(2:4, 1:3, 1:10, 1:2);
sc = sc(:)'; s = s(:)'; r = r(:)';
n = numel(sc);
R.scn = sc; R.s = s; R.r = r; R.geom = 1000 * s + r; R.speed = 10 + 15 * r;
R.threat = true(1, n); R.recoverable = ~(sc == 4 & s == 1 & r == 10);
harmed = (sc == 3) | (sc == 4 & s == 1) | (sc == 2 & r <= 2);
Rn = R; Rn.recovered = ~harmed;
Rd = R; Rd.recovered = ~((sc == 3 & r >= 8) | (sc == 2 & s == 1 & r == 10)) & R.recoverable;
E.POL = {'none', 'dqn_g1'}; E.LBL = {'no response', 'DQN (deployed)'}; E.iDQN = 2;
E.RES = {Rn, Rd}; E.ALL = {Rn, Rd}; E.set_names = {'single'};
bins = [0 40 80 120 160];
mrec = Rn.recoverable & Rn.threat;
pe = nan(3, 2); pv = nan(4, 2);
for k = 1:2
    for i = 1:3, pe(i, k) = 100 * mean(E.RES{1, k}.recovered(mrec & Rn.s == i)); end
    for b = 1:4
        m = mrec & Rn.speed >= bins(b) & Rn.speed < bins(b + 1) + (b == 4);
        pv(b, k) = 100 * mean(E.RES{1, k}.recovered(m));
    end
end
pt = nan(3, 2);
for k = 1:2
    for ti = 1:3, pt(ti, k) = 100 * mean(E.ALL{k}.recovered(mrec & Rn.scn == ti + 1)); end
end
E.KP = struct('ebno', [3 9 15], 'show', {{'none', 'dqn_g1'}}, 'per_ebno', pe, 'per_speed', pv, 'speed_bins', bins, ...
    'threats', {scen(2:4)'}, 'per_threat', pt, 'reading', 'P1R', 'harmed_consistent', true);
end

function test_link_limited_tags(tc)
M = p1r_post_hoc('mark', [0.99 0.84 0.62 0.02 0.01 0], 2);
verifyEqual(tc, M.L, logical([1 1 1 0 0 0]));
verifyEqual(tc, M.tag, {'L', 'L', 'L', 'J', 'J', 'J'});
M = p1r_post_hoc('mark', [0.5 0.45 0.1 0.099], 2);
verifyEqual(tc, M.tag, {'L', 'M', 'M', 'J'});
end

function test_gate_reproduces_the_saved_tables(tc)
E = synth();
verifyEmpty(tc, p1r_post_hoc('gate', E));
F = E; F.KP.per_ebno(2, 2) = F.KP.per_ebno(2, 2) + 1;
mm = p1r_post_hoc('gate', F);
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'per_ebno'));
F = E; F.KP.per_speed(3, 2) = F.KP.per_speed(3, 2) - 0.5;
mm = p1r_post_hoc('gate', F);
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'per_speed'));
F = E; F.KP = rmfield(F.KP, 'per_speed');
mm = p1r_post_hoc('gate', F);
verifyTrue(tc, contains(mm{1}, 'lacks'));
end

function test_gate_binds_the_threat_labels_to_the_evaluation(tc)
% The by-threat rows read PP.scen of the pools copy; the gate reproduces KP.per_threat through those labels.
[E, scen] = synth();
verifyEmpty(tc, p1r_post_hoc('gate', E, scen));
verifyEmpty(tc, p1r_post_hoc('gate', E, scen'));                 % a row of labels reads like a column
% a copy whose cells are ordered otherwise relabels the threats and fails
mm = p1r_post_hoc('gate', E, scen([1 3 2 4]));
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'per_threat'));
% a copy that lacks a cell the episodes name
mm = p1r_post_hoc('gate', E, scen(1:3));
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'threat cell'));
% a saved table that differs
F = E; F.KP.per_threat(2, 2) = F.KP.per_threat(2, 2) + 1;
mm = p1r_post_hoc('gate', F, scen);
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'per_threat'));
% an evaluation without the table cannot tie the labels: stated, not passed
F = E; F.KP = rmfield(F.KP, 'per_threat');
mm = p1r_post_hoc('gate', F, scen);
verifyEqual(tc, numel(mm), 1); verifyTrue(tc, contains(mm{1}, 'lacks'));
% without labels the gate is the one of KP.per_ebno and KP.per_speed
verifyEmpty(tc, p1r_post_hoc('gate', F));
end

function test_rows_per_ebno(tc)
[E, scen] = synth();
Rd = E.RES{1, 2};
M = p1r_post_hoc('mark', [0.99 0.02 0.45], 2);
C = struct('B', 300, 'seed', 1);
[rows, lines] = p1r_post_hoc('ebno', Rd, [3 9 15], scen, M, 'single set', C);
verifyEqual(tc, {rows.tag}, {'L', 'J', 'M'});
verifyEqual(tc, [rows.n], [58 60 60]);
verifyEqual(tc, [rows.ncl], [10 10 10]);
mrec = Rd.recoverable & Rd.threat;
for s = 1:3
    verifyEqual(tc, rows(s).rate, 100 * mean(Rd.recovered(mrec & Rd.s == s)), 'AbsTol', 1e-9);
    verifyLessThanOrEqual(tc, rows(s).lo, rows(s).rate); verifyGreaterThanOrEqual(tc, rows(s).hi, rows(s).rate);
    verifyEqual(tc, sum(rows(s).defs), 100 - rows(s).rate, 'AbsTol', 1e-9);       % the deficit split by threat adds up
    verifyEqual(tc, rows(s).lb90, rows(s).lo >= 90);
end
% 3 dB: antenna_fault 6 and jamming 2 failures of 58 recoverable episodes, path_loss none
verifyEqual(tc, rows(1).defs, [2 6 0] / 58 * 100, 'AbsTol', 1e-9);
verifyEqual(tc, rows(1).fail, 8);
verifyTrue(tc, iscellstr(lines));
verifyTrue(tc, any(contains(lines, '3 dB  L')) && any(contains(lines, '9 dB  J')) && any(contains(lines, '15 dB  M')));
verifyTrue(tc, any(contains(lines, 'antenna_fault 10.3, jamming 3.4')));
% no failure: the lower bound is 100 and the line says so
Rd.recovered(:) = true;
rows = p1r_post_hoc('ebno', Rd, [3 9 15], scen, M, 'single set', C);
verifyTrue(tc, all([rows.lb90]));
verifyEqual(tc, [rows.lo], [100 100 100]);
end

function test_a_prime_readout_per_speed_band(tc)
[E, scen] = synth();
C = struct('B', 300, 'seed', 1);
[B, lines] = p1r_post_hoc('bands', E.RES{1, 2}, E.RES{1, 1}, [0 40 80 120 160], scen, [3 9 15], 'single set', C);
verifyEqual(tc, [B.band.n], [18 54 54 52]);
verifyEqual(tc, [B.band.ncl], [3 9 9 9]);                 % a flight at each of the three Eb/N0 points is a cluster of its own
verifyEqual(tc, B.names, {'jamming'; 'antenna_fault'; 'path_loss'});
% antenna_fault: always harmed; recovered on the harmed episodes until flight 7, none after it
af = B.lost(strcmp({B.lost.thr}, 'antenna_fault'));
verifyEqual(tc, [af.band], 1:4);
verifyEqual(tc, [af.n], [6 18 18 18]); verifyEqual(tc, [af.n_h], [6 18 18 18]);
verifyEqual(tc, [af.harm], [1 1 1 1]);
verifyEqual(tc, [af.rec_h], [1 1 1 0]);
as = B.lost(strcmp({B.lost.thr}, 'airframe_shadowing'));
verifyEqual(tc, [as.n], [0 0 0 0]);
verifyTrue(tc, all(isnan([as.harm])));
% the top band: 20 failures, 18 of them harmed lost-branch episodes
verifyTrue(tc, any(contains(lines, 'failures of the DQN   20, of them harmed lost-branch episodes  90.0%')));
% per threat and band
k = find(strcmp(B.names, 'jamming'));
verifyEqual(tc, B.thr_band_n(k, :), [6 18 18 18]);
verifyEqual(tc, B.thr_band(k, 4), 100 * 16 / 18, 'AbsTol', 1e-9);
verifyEqual(tc, B.thr_ebno_n(k, :), [20 20 20]);
end

function files = write_inputs(E, scen, reading)
% policy_pools.mat and policy_evaluation.mat of a synthetic evaluation in a folder of their own.
d = tempname; mkdir(d);
PP = struct('ebno', [3 9 15], 'scen', {scen}, 'clean_fer', [0.99 0.02 0.45], 'det_id', 'synthetic'); %#ok<NASGU>
E.KP.reading = reading;
ALL = E.ALL; POL = E.POL; LBL = E.LBL; iDQN = E.iDQN; KP = E.KP; RES = E.RES; set_names = E.set_names; %#ok<NASGU>
save(fullfile(d, 'policy_pools.mat'), 'PP');
save(fullfile(d, 'policy_evaluation.mat'), 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'set_names');
files = struct('dir', d, 'pools', fullfile(d, 'policy_pools.mat'), 'eval', fullfile(d, 'policy_evaluation.mat'));
end

function test_run_on_files_writes_once_and_labels(tc)
[E, scen] = synth();
root = tc.TestData.root;
f = write_inputs(E, scen, 'P1R');
out = fullfile(root, 'results', ['_test_p1_readers_' char(java.util.UUID.randomUUID().toString())]);
tc.addTeardown(@() cleanup({f.dir, out}));
p1r_post_hoc('run', f.pools, f.eval, out, 'abc1234', '');
txt = fileread(fullfile(out, 'p1r_post_hoc.txt'));
verifyTrue(tc, isfile(fullfile(out, 'p1r_post_hoc.mat')));
verifyTrue(tc, contains(txt, 'P1R, descriptive'));
verifyTrue(tc, contains(txt, 'GATE PASS'));
verifyTrue(tc, contains(txt, 'Registration commit abc1234 (unverified: no docs repo)'));
verifyTrue(tc, contains(txt, 'boot_cluster.m '));
verifyTrue(tc, contains(txt, 'Per Eb/N0, single set'));
verifyTrue(tc, contains(txt, 'Per Eb/N0, threat sets pooled'));
verifyTrue(tc, contains(txt, 'A'' readout, single set'));
verifyTrue(tc, contains(txt, 'tags: L'));
S = load(fullfile(out, 'p1r_post_hoc.mat'), 'M', 'OUT');
verifyEqual(tc, S.M.tag, {'L', 'J', 'M'});
verifyEqual(tc, numel(S.OUT), 2);
% the reading runs once
verifyError(tc, @() p1r_post_hoc('run', f.pools, f.eval, out, 'abc1234', ''), 'reader_guard:once');
% no registration commit, no run
verifyError(tc, @() p1r_post_hoc('run', f.pools, f.eval, [out '_b'], '', ''), 'reader_guard:registration');
verifyFalse(tc, isfolder([out '_b']));
end

function test_run_labels_a_reading_that_is_not_p1r(tc)
[E, scen] = synth();
f = write_inputs(E, scen, '');
out = fullfile(tc.TestData.root, 'results', ['_test_p1_readers_' char(java.util.UUID.randomUUID().toString())]);
tc.addTeardown(@() cleanup({f.dir, out}));
p1r_post_hoc('run', f.pools, f.eval, out, 'abc1234', '');
txt = fileread(fullfile(out, 'p1r_post_hoc.txt'));
verifyTrue(tc, contains(txt, 'post hoc, added after the reading, descriptive'));
verifyFalse(tc, contains(txt, 'P1R, descriptive'));
end

function test_a_failed_gate_writes_no_reading(tc)
[E, scen] = synth();
E.KP.per_ebno(1, 2) = E.KP.per_ebno(1, 2) + 5;
f = write_inputs(E, scen, 'P1R');
out = fullfile(tc.TestData.root, 'results', ['_test_p1_readers_' char(java.util.UUID.randomUUID().toString())]);
tc.addTeardown(@() cleanup({f.dir, out}));
verifyError(tc, @() p1r_post_hoc('run', f.pools, f.eval, out, 'abc1234', ''), 'p1r_post_hoc:gate');
verifyTrue(tc, isfile(fullfile(out, 'p1r_post_hoc.gatefail.txt')));
verifyFalse(tc, isfile(fullfile(out, 'p1r_post_hoc.txt')));
verifyFalse(tc, isfile(fullfile(out, 'p1r_post_hoc.mat')));
verifyTrue(tc, contains(fileread(fullfile(out, 'p1r_post_hoc.gatefail.txt')), 'GATE FAIL'));
end

function test_a_relabelled_pools_copy_fails_the_gate(tc)
% Same Eb/N0 grid and det_id, another cell order: the deficit by threat would be relabelled, so no row is read.
[E, scen] = synth();
f = write_inputs(E, scen([1 3 2 4]), 'P1R');
out = fullfile(tc.TestData.root, 'results', ['_test_p1_readers_' char(java.util.UUID.randomUUID().toString())]);
tc.addTeardown(@() cleanup({f.dir, out}));
verifyError(tc, @() p1r_post_hoc('run', f.pools, f.eval, out, 'abc1234', ''), 'p1r_post_hoc:gate');
verifyFalse(tc, isfile(fullfile(out, 'p1r_post_hoc.txt')));
verifyTrue(tc, contains(fileread(fullfile(out, 'p1r_post_hoc.gatefail.txt')), 'per_threat'));
end

function test_inputs_and_outputs_are_guarded(tc)
[E, scen] = synth();
f = write_inputs(E, scen, 'P1R');
tc.addTeardown(@() cleanup({f.dir}));
root = tc.TestData.root;
verifyError(tc, @() p1r_post_hoc('run', f.pools, f.eval, fullfile(root, 'data', 'x'), 'abc1234', ''), 'reader_guard:out');
g = fullfile(f.dir, 'other.mat'); copyfile(f.eval, g);
verifyError(tc, @() p1r_post_hoc('run', f.pools, g, fullfile(root, 'results', 'x'), 'abc1234', ''), 'reader_guard:input');
end

function cleanup(items)
for k = 1:numel(items)
    if isfolder(items{k}), [~, ~] = rmdir(items{k}, 's'); end
end
end
