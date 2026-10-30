function tests = test_combo_miss
%TEST_COMBO_MISS  R5's categories, mechanism naming and tables (combo_miss_tables.m) on synthetic frames: every
%   class of the monitor falls in exactly one category, the missed frames are counted by category and
%   the largest share names the mechanism, split by onset age and Eb/N0, with DET_h and DET_u by
%   harmed flights. Run from the repository root: results = runtests('code/tests/test_combo_miss.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function mp = pair_meta(kind)
% Classes: 1 none, 2 jamming, 3 spoofing, 4 path_loss, 5 antenna_fault, 6 airframe_shadowing, 7 sweeping_jammer.
fam = logical([0 0 0 1 1 1 0]);
switch kind
    case 'jam+pl',  mp = struct('J', logical([0 1 1 0 0 0 0]), 'Lc', 4, 'fam', fam, 'none_idx', 1, 'drop_used', true, 'pl_idx', 4);
    case 'jam+af',  mp = struct('J', logical([0 1 1 0 0 0 0]), 'Lc', 5, 'fam', fam, 'none_idx', 1, 'drop_used', false, 'pl_idx', 0);
    case 'spf+sw',  mp = struct('J', logical([0 0 1 0 0 0 1]), 'Lc', 0, 'fam', fam, 'none_idx', 1, 'drop_used', false, 'pl_idx', 0);
end
end

function test_every_class_falls_in_one_category(tc)
ct = combo_miss_tables('categories', [2 3 4 5 6 1 7 0]', pair_meta('jam+pl'));
verifyEqual(tc, ct', [1 1 2 3 3 4 5 0]);
ct = combo_miss_tables('categories', [2 3 4 5 6 1 7]', pair_meta('jam+af'));
verifyEqual(tc, ct', [1 1 3 2 3 4 5]);
ct = combo_miss_tables('categories', [2 3 4 5 6 1 7]', pair_meta('spf+sw'));
verifyEqual(tc, ct', [5 1 3 3 3 4 1]);
% a row or a column of classes gives a column of categories
verifyEqual(tc, size(combo_miss_tables('categories', [2 3 4], pair_meta('jam+pl'))), [3 1]);
end

function test_mechanism_names_the_largest_share(tc)
mp = pair_meta('jam+pl');
[name, k] = combo_miss_tables('mechanism', [0 30 5 15 0], mp);
verifyEqual(tc, k, 2); verifyTrue(tc, startsWith(name, '(a)'));
[name, k] = combo_miss_tables('mechanism', [0 3 20 15 0], mp);
verifyEqual(tc, k, 3); verifyTrue(tc, startsWith(name, '(b)'));
[name, k] = combo_miss_tables('mechanism', [0 3 5 15 0], mp);
verifyEqual(tc, k, 4); verifyTrue(tc, contains(name, 'none'));
[name, k] = combo_miss_tables('mechanism', [0 0 0 1 4], mp);
verifyEqual(tc, k, 5); verifyTrue(tc, contains(name, 'another class'));
[name, k] = combo_miss_tables('mechanism', [0 0 0 0 0], mp);
verifyEqual(tc, k, 0); verifyEqual(tc, name, 'no missed frame');
[~, k] = combo_miss_tables('mechanism', [0 3 3 0 0], mp);              % a tie goes to the lowest category
verifyEqual(tc, k, 2);
% a pair whose level component needs no drop alarm does not name the scoring
[name, k] = combo_miss_tables('mechanism', [0 6 1 1 0], pair_meta('jam+af'));
verifyEqual(tc, k, 2); verifyFalse(tc, startsWith(name, '(a)'));
end

function [F, M] = frames()
% Pair 1 (jamming+path_loss, the class path_loss counts only with the drop alarm): 100 threat-active frames,
% 40 read as jamming, 30 as path_loss without the drop alarm, 10 as path_loss with it, 15 as none, 5 as
% airframe_shadowing. Pair 2 (spoofing+sweeping_jammer): 20 frames, 10 read as a jammer, 6 as none, 4 as
% antenna_fault.
cls1 = [2 * ones(40, 1); 4 * ones(40, 1); ones(15, 1); 6 * ones(5, 1)];
dr1 = [false(40, 1); false(30, 1); true(10, 1); false(20, 1)];
hit1 = cls1 == 2 | dr1;
i1 = (1:100)';
cls2 = [3 * ones(10, 1); ones(6, 1); 5 * ones(4, 1)];
hit2 = cls2 == 3;
i2 = (1:20)';
F.pair = [ones(100, 1); 2 * ones(20, 1)];
F.s = [1 + double(i1 > 50); 1 + double(i2 > 10)];
F.flight = [1000 * 0 + mod(i1 - 1, 5) + 1; mod(i2 - 1, 4) + 1];
F.age = [mod(i1 - 1, 15); mod(i2 - 1, 15)];
F.cls = [cls1; cls2]; F.dr = [dr1; false(20, 1)]; F.hit = [hit1; hit2];
F.harmed = F.flight <= 3;
F.on = true(120, 1);
M = struct('pairs', {{'jamming+path_loss', 'spoofing+sweeping_jammer'}}, 'classes', {{'none', 'jamming', 'spoofing', 'path_loss', ...
    'antenna_fault', 'airframe_shadowing', 'sweeping_jammer'}}, 'pm', [pair_meta('jam+pl'), pair_meta('spf+sw')], 'fuse_N', 12, ...
    'ebno', [3 12], 'det_h_read', 82.2);
end

function test_tables_count_the_missed_frames_by_category(tc)
[F, M] = frames();
C = struct('B', 200, 'seed', 1);
T = combo_miss_tables('tables', F, M, C);
P = T.p(1);
verifyEqual(tc, P.pair, 'jamming+path_loss');
verifyEqual(tc, [P.n_on P.n_flights], [100 5]);
verifyEqual(tc, P.det.rate, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, P.cnt, [40 40 5 15 0]);
verifyEqual(tc, P.mcnt, [0 30 5 15 0]);
verifyEqual(tc, P.pl_class, 0.4, 'AbsTol', 1e-12);
verifyEqual(tc, P.drop, 0.1, 'AbsTol', 1e-12);
verifyEqual(tc, P.both, 0.1, 'AbsTol', 1e-12);
verifyEqual(tc, P.det_cf, 0.8, 'AbsTol', 1e-12);
verifyEqual(tc, P.mech_k, 2);
verifyTrue(tc, startsWith(P.mech, '(a)'));
% DET_h and DET_u split the same frames by the flight's harm
m = F.pair == 1;
verifyEqual(tc, P.n_h, sum(F.harmed(m)));
verifyEqual(tc, P.det_h.rate, mean(F.hit(m & F.harmed)), 'AbsTol', 1e-12);
verifyEqual(tc, P.det_u.rate, mean(F.hit(m & ~F.harmed)), 'AbsTol', 1e-12);
verifyEqual(tc, P.det_h.n + P.det_u.n, 100);
Q = T.p(2);
verifyEqual(tc, Q.det.rate, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, Q.mcnt, [0 0 4 6 0]);
verifyEqual(tc, Q.mech_k, 4); verifyTrue(tc, contains(Q.mech, 'none'));
verifyTrue(tc, isnan(Q.pl_class) && isnan(Q.det_cf));
end

function test_tables_split_by_onset_age_and_ebno(tc)
[F, M] = frames();
C = struct('B', 200, 'seed', 1);
T = combo_miss_tables('tables', F, M, C);
verifyEqual(tc, T.edge, [3 12]);
P = T.p(1);
age = F.age(F.pair == 1);
verifyEqual(tc, [P.age.n], [sum(age <= 2), sum(age >= 3 & age <= 11), sum(age >= 12)]);
verifyEqual(tc, sum([P.age.n]), 100);
verifyEqual(tc, sum(vertcat(P.age.mcnt), 1), P.mcnt);
verifyEqual(tc, [P.ebno.n], [50 50]);
verifyEqual(tc, sum(vertcat(P.ebno.mcnt), 1), P.mcnt);
% frames that are not threat-active are left out
F2 = F; F2.on(1:10) = false;
T2 = combo_miss_tables('tables', F2, M, C);
verifyEqual(tc, T2.p(1).n_on, 90);
end

function test_lines_quote_the_reading_and_name_the_mechanism(tc)
[F, M] = frames();
C = struct('B', 200, 'seed', 1);
T = combo_miss_tables('tables', F, M, C);
lines = combo_miss_tables('lines', T, M, C);
verifyTrue(tc, iscellstr(lines));
verifyTrue(tc, contains(lines{1}, '82.2%'));
verifyTrue(tc, any(contains(lines, '--- jamming+path_loss: 100 threat-active frames')));
verifyTrue(tc, any(contains(lines, 'largest share of the missed frames: (a)')));
verifyTrue(tc, any(contains(lines, 'DET if the class counted without the drop alarm')));
verifyTrue(tc, any(contains(lines, 'Eb/N0     3 dB')));
verifyTrue(tc, any(contains(lines, 'onset age 0-2')));
% the second pair has no path_loss line
k = find(contains(lines, '--- spoofing+sweeping_jammer'));
verifyEqual(tc, numel(k), 1);
verifyFalse(tc, any(contains(lines(k:end), 'path_loss: read as the class')));
end

function test_repeatable(tc)
[F, M] = frames();
C = struct('B', 200, 'seed', 1);
a = combo_miss_tables('lines', combo_miss_tables('tables', F, M, C), M, C);
b = combo_miss_tables('lines', combo_miss_tables('tables', F, M, C), M, C);
verifyEqual(tc, a, b);
end
