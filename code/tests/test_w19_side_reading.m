function tests = test_w19_side_reading
%TEST_W19_SIDE_READING  The descriptive side readings of the saved test read (w19_side_reading.m) on
%   small synthetic readings: the table, the paired differences, the subsets, the false changes per
%   hour with the Garwood bound, the recomputed claims and the Bonferroni line. No saved output is read.
%   Run from the repository root: results = runtests('code/tests/test_w19_side_reading.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

function test_d125_table(tc)
c0 = struct('geom', [1 1 2 2 3 3 4 4 5], 'recoverable', logical([1 1 1 1 1 1 1 1 0]), 'threat', true(1, 9), ...
    'recovered', logical([0 0 1 1 0 0 1 1 0]), 'held', [0 0 1 1 0 0 1 0 0], 'per_post', [.9 .8 .1 .2 .7 .6 .1 .1 1], ...
    'dlv_post', [.1 .1 .6 .6 .1 .2 .6 .6 0]);
c1 = c0;
c1.recovered = logical([0 1 1 1 1 1 1 0 1]); c1.held = [0 1 1 1 1 1 1 0 1];
c1.per_post = [.9 .3 .1 .1 .2 .2 .1 .4 .1]; c1.dlv_post = [.1 .5 .6 .7 .5 .5 .6 .2 .9];
A = struct('RONs', {cell(4, 2)}, 'sets', {{'single', 'follower', 'combined', 'comb'}});
A.RONs{4, 1} = c0; A.RONs{4, 2} = c1;
S = w19_side_reading('d125', A);
verifyEqual(tc, S.tab, [1 3; 1 3]);                               % the ninth episode is not recoverable
verifyEqual(tc, S.n, 8);
verifyEqual(tc, S.ncl, 4);
verifyEqual(tc, S.gain, 0.25, 'AbsTol', 1e-12);
verifyEqual(tc, S.per.d, mean(c1.per_post(1:8) - c0.per_post(1:8)), 'AbsTol', 1e-12);
verifyEqual(tc, S.dlv.d, mean(c1.dlv_post(1:8) - c0.dlv_post(1:8)), 'AbsTol', 1e-12);
verifyTrue(tc, S.lo <= S.gain && S.gain <= S.hi);
verifyTrue(tc, any(contains(S.lines, 'off not recovered')) && any(contains(S.lines, 'on recovered')));
c1.geom(1) = 9;
A.RONs{4, 2} = c1;
verifyError(tc, @() w19_side_reading('d125', A), 'w19_side_reading:pairs');
end

function test_d127_subsets(tc)
pay = 50e3; cn = w19_side_reading('cells');
scn = [find(strcmp(cn, 'jamming'), 1), find(strcmp(cn, 'path_loss'), 1), find(contains(cn, '+'), 1), find(strcmp(cn, 'tone_jamming'), 1)];
pols = {'none', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core'};
F0 = cell(3, 5); F1 = F0;
for si = 1:3
    base = struct('scn', scn, 'geom', [1 1 2 2] + 10 * si, 'recoverable', true(1, 4), ...
        'recoverable_core', logical([0 0 1 1]), 'threat', true(1, 4), 'dlv_post', 0.5 * ones(1, 4), ...
        'gput_post', 0.6 * ones(1, 4), 'per_post', ones(1, 4), 'recovered', true(1, 4));
    for pk = 1:5
        F0{si, pk} = base; F1{si, pk} = base;
        if pk > 1
            F1{si, pk}.dlv_post = 0.25 * ones(1, 4); F1{si, pk}.gput_post = 0.5 * ones(1, 4);
        end
    end
end
B = struct('pols', {pols}, 'F0', {F0}, 'F1', {F1});
S = w19_side_reading('d127', B, pay);
verifyEqual(tc, S.n, struct('threat', 12, 'jam36', 6, 'jamcore', 3));    % jamming and tone_jamming; combination and path_loss out
v = S.val.rule_core.jam36;
verifyEqual(tc, [v.off v.on v.d], pay * [0.5 0.25 -0.25], 'AbsTol', 1e-9);
verifyEqual(tc, [v.lo v.hi], pay * [-0.25 -0.25], 'AbsTol', 1e-9);
verifyEqual(tc, [v.g_off v.g_on v.g_d], [0.6 0.5 -0.1], 'AbsTol', 1e-12);
verifyEqual(tc, S.val.rule_core.jamcore.n, 3);
verifyFalse(tc, isfield(S.val.rule_esc, 'jamcore'));
verifyEqual(tc, S.val.blind_esc.threat.n, 12);
% the recomputed claims on the same rows
for si = 1:3
    for pk = 4
        F0{si, pk}.per_post = 0.6 * ones(1, 4); F1{si, pk}.per_post = 0.3 * ones(1, 4);
    end
    F1{si, 2}.recovered = false(1, 4); F1{si, 2}.recovered(1:2) = true;
end
B.F0 = F0; B.F1 = F1;
B.claims = struct('claims', struct('P', {struct('p', 0), struct('p', 0), struct('p', 0)}));
P = w19_side_reading('p127', B);
verifyEqual(tc, P.name, {'esc_recovered', 'core_narrowband', 'core_wideband'});
verifyEqual(tc, P.gain(1), -0.5, 'AbsTol', 1e-12);                       % recovered 1 -> 0.5 over the recoverable
verifyEqual(tc, P.gain(2), 0.3, 'AbsTol', 1e-12);                        % (0.6 - 0.3) / 1 on the tone_jamming episodes
verifyEqual(tc, P.p(1), 1);                                              % a loss is never a gain
end

function test_clean(tc)
SW = struct('rule_core', [0 0 1 2 0 0; 0 1 1 2 0 0]);
S = w19_side_reading('clean', SW, 30, 20);
q = S.row.rule_core;
verifyEqual(tc, [q.k0 q.k1 q.n q.up q.dn], [3 4 6 1 0]);
verifyEqual(tc, q.fph0, 3 / 180 * 180000, 'AbsTol', 1e-9);
verifyEqual(tc, q.fph1, 4 / 180 * 180000, 'AbsTol', 1e-9);
verifyEqual(tc, q.u1, gammaincinv(0.95, 5) / 180 * 180000, 'RelTol', 1e-12);
verifyEqual(tc, q.uu, gammaincinv(0.95, 2) / 180 * 180000, 'RelTol', 1e-12);
verifyEqual(tc, [q.flights0 q.flights1], [2 3]);
end

function test_bonf(tc)
S = w19_side_reading('bonf', [0 0 0 0.0125], {'a', 'b', 'c', 'd'}, 4);
verifyTrue(tc, S.pass);
verifyEqual(tc, S.alpha, 0.0125);
S = w19_side_reading('bonf', [0 0 0 0.02], {'a', 'b', 'c', 'd'}, 4);
verifyFalse(tc, S.pass);
verifyEqual(tc, S.ok, [true true true false]);
verifyNumElements(tc, S.lines, 1);
end

function test_seeds_apart_from_the_read(tc)
R = w19_side_reading('reg'); W = weak19_reading('reg');
verifyTrue(tc, R.seed > W.rr.seed_d + 24 && R.seed > W.rr.claims(3).seed);
verifyEqual(tc, R.B, W.B);
end
