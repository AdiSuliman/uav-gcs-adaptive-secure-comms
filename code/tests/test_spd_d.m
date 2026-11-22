function tests = test_spd_d
%TEST_SPD_D  SPD-D's tables and routing table (spd_d_tables.m) on synthetic episodes: the bands, the restoring
%   set and its families, every table, and each routing branch fired alone and together with the policy
%   branch first. Run from the repository root: results = runtests('code/tests/test_spd_d.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.C = spd_d_tables('config', [0 161]);
tc.TestData.C.B = 200;
end

function E = base()
% 4 speed bands x 3 bank bands x 6 flights x 4 threats x 2 onsets, every episode recovered, harmed only for
% antenna_fault, |R| = 10, no failure: the tests break chosen groups. sbi, bbi, th are the design indices.
speeds = [20; 60; 100; 140]; banks = [10; 30; 45];
names = {'jamming', 'antenna_fault', 'benign_interference', 'path_loss'};
[sp, bk, fl, th, ~] = ndgrid(1:4, 1:3, 1:6, 1:4, 1:2);
n = numel(sp);
E.sbi = sp(:); E.bbi = bk(:); E.th = th(:); E.flight = fl(:);
E.speed = speeds(E.sbi); E.bank = banks(E.bbi);
nm = names(:); E.thr = nm(E.th);
E.split = 1 + double(E.flight > 3);
E.geom = 1e6 * E.split + (E.sbi - 1) * 18 + (E.bbi - 1) * 6 + E.flight;
E.s = ones(n, 1);
E.rec = true(n, 1); E.harmed = E.th == 2; E.recovered = true(n, 1);
E.nR = 10 * ones(n, 1); E.r_sc = true(n, 1); E.r_only = false(n, 1);
E.cfg_end = ones(n, 1); E.shadow_fl = false(n, 1);
E.na = 1; E.actions = {'no_action', 'channel_switch', 'power_control', 'channel_switch+power_control'};
E.sc_cfg = [false; true; false; true];
end

function CL = clean_link(rising)
% Clean-link flights at the working points, bank 0-20 deg: FER rising with speed, or flat.
speeds = repelem([20; 60; 100; 140], 6);
CL.speed = speeds; CL.bank = 10 * ones(24, 1);
CL.fer = 0.005 * ones(24, 1) + rising * 0.0001 * speeds;
CL.geom = (1:24)';
end

function test_bands(tc)
C = tc.TestData.C;
[sb, bb] = spd_d_tables('bands', [0; 40; 40.25; 80.5; 120.75; 161; NaN], [0; 19.9; 20; 39.9; 40; 58; NaN], C);
verifyEqual(tc, sb, [1; 1; 2; 3; 4; 4; 0]);
verifyEqual(tc, bb, [1; 1; 2; 2; 3; 3; 0]);
verifyEqual(tc, C.speed_edges, linspace(0, 161, 5));
verifyEqual(tc, C.bank_edges, [0 20 40 58]);
verifyEqual(tc, [C.hi_speed C.contrast C.nr_small C.share], [112 3 3 0.5]);
verifyFalse(tc, C.cov_registered);
end

function test_families_and_restoring_set(tc)
names = {'no_action', 'channel_switch', 'spatial_diversity', 'power_control', 'rate_reduce+power_control', ...
    'channel_switch+power_control', 'fec_interleave', 'freq_diversity'};
[sc, bud] = spd_d_tables('families', names);
verifyEqual(tc, sc', logical([0 1 1 0 0 1 0 1]));
verifyEqual(tc, bud', logical([0 0 0 1 1 1 1 0]));
ok = false(8, 6);
ok([4 7], 1) = true;                 % power_control, fec_interleave: link budget alone
ok(2, 2) = true;                     % channel_switch
ok([4 6], 3) = true;                 % power_control and channel_switch+power_control
ok([1 4], 4) = true;                 % no_action beside power_control
ok(5, 5) = true;                     % rate_reduce+power_control: link budget alone
[nR, r_sc, r_only] = spd_d_tables('restoring', ok, sc, bud);
verifyEqual(tc, nR, [2 1 2 2 1 0]);
verifyEqual(tc, r_sc, logical([0 1 1 0 0 0]));
verifyEqual(tc, r_only, logical([1 0 0 0 1 0]));
end

function test_tables_of_a_clean_design(tc)
C = tc.TestData.C;
E = base();
T = spd_d_tables('tables', E, clean_link(0), C);
verifyEqual(tc, T.n_episodes, 576); verifyEqual(tc, T.n_rec, 576);
verifyEqual(tc, numel(T.G), 4);
verifyEqual(tc, {T.G.key}, {'all', 'other', 'lost', 'benign'});
verifyEqual(tc, [sum(T.G(1).m) sum(T.G(2).m) sum(T.G(3).m) sum(T.G(4).m)], [576 432 144 144]);
c = T.t1{1};
verifyEqual(tc, size(c), [4 3]);
verifyEqual(tc, [c.n], 48 * ones(1, 12));
verifyTrue(tc, all([c.rate] == 1));
verifyEqual(tc, [c.ncl], 6 * ones(1, 12));
verifyEqual(tc, T.t1s(1).split, 1); verifyEqual(tc, T.t1s(2).split, 2);
verifyEqual(tc, T.t1s(1).n, 24 * ones(4, 3));
verifyEqual(tc, numel(T.t2), 6);
verifyTrue(tc, all([T.t2.d] == 0));
verifyFalse(tc, any([T.t2.point3]));
verifyEqual(tc, T.t3{1}.n, 48 * ones(4, 3));
verifyEqual(tc, T.t3{1}.mean_nR, 10 * ones(4, 3));
verifyEqual(tc, T.t3{2}.n, 12 * ones(4, 3));
verifyEqual(tc, {T.t4.name}, {'antenna_fault', 'airframe_shadowing', 'benign_interference'});
verifyEqual(tc, T.t4(1).n, 36 * ones(1, 4));
verifyEqual(tc, T.t4(1).harm, ones(1, 4));
verifyEqual(tc, T.t4(2).n, zeros(1, 4));
verifyEqual(tc, T.t4(3).harm, zeros(1, 4));
verifyEqual(tc, [T.t5.n], zeros(1, 4));
verifyFalse(tc, T.route.defined);
verifyEqual(tc, T.route.first, 'none');
lines = spd_d_tables('lines', T, C);
verifyTrue(tc, iscellstr(lines));
verifyTrue(tc, any(contains(lines, 'the DQN has no failure in the top band, no branch applies')));
end

function test_bank_only_branch(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.bbi == 3 & E.th == 1) = false;            % jamming fails on the steep bank, at every speed
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyTrue(tc, r.bank_only.met);
verifyFalse(tc, r.bank_only.speed_meets);
verifyEqual(tc, T.t2(3).d, 0.25, 'AbsTol', 1e-12);       % bank below 40 deg minus 40 deg and above, from 112 km/h
verifyFalse(tc, r.policy.met); verifyFalse(tc, r.doppler.met); verifyFalse(tc, r.coverage.met);
verifyEqual(tc, r.met, {'bank_only'});
verifyEqual(tc, r.first, 'bank_only');
end

function test_doppler_branch(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.sbi == 4 & E.bbi == 1 & E.th == 1) = false;   % jamming fails at the top speed band inside bank 0-20 deg
T = spd_d_tables('tables', E, clean_link(1), C);
r = T.route;
verifyEqual(tc, T.t2(4).grp, 'other');
verifyEqual(tc, T.t2(4).d, 1/3, 'AbsTol', 1e-12);         % 4 of 6 recovered at the top band, all below
verifyTrue(tc, T.t2(4).meets3);
verifyTrue(tc, r.doppler.met);
verifyTrue(tc, r.doppler.fer_up);
verifyTrue(tc, r.bank_only.speed_meets);                  % the speed contrast inside bank < 40 deg is there, so not the bank
verifyFalse(tc, r.bank_only.met);
verifyFalse(tc, r.policy.met); verifyFalse(tc, r.coverage.met);
verifyEqual(tc, r.met, {'doppler'});
% the same failures with a flat clean-link FER: the clean link does not rise with speed, no Doppler
T0 = spd_d_tables('tables', E, clean_link(0), C);
verifyFalse(tc, T0.route.doppler.fer_up);
verifyFalse(tc, T0.route.doppler.met);
verifyEmpty(tc, T0.route.met);
% and without any clean-link reading the row cannot fire
Tn = spd_d_tables('tables', E, [], C);
verifyFalse(tc, Tn.route.doppler.met);
end

function test_doppler_reads_the_other_threats_only(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.sbi == 4 & E.bbi == 1 & E.th == 2) = false;   % only antenna_fault fails there
T = spd_d_tables('tables', E, clean_link(1), C);
verifyEqual(tc, T.t2(1).grp, 'all');
verifyTrue(tc, T.t2(1).meets3);
verifyEqual(tc, T.t2(4).d, 0, 'AbsTol', 1e-12);
verifyFalse(tc, T.route.doppler.met);
% the shadowing group's flights are left out of the other threats
E2 = base();
E2.shadow_fl = E2.th == 4;
E2.recovered(E2.sbi == 4 & E2.bbi == 1 & E2.th == 4) = false;
T2 = spd_d_tables('tables', E2, clean_link(1), C);
verifyEqual(tc, sum(T2.G(2).m), 288);                      % jamming and benign_interference only
verifyEqual(tc, T2.t2(4).d, 0, 'AbsTol', 1e-12);
verifyFalse(tc, T2.route.doppler.met);
end

function test_policy_branch_goes_first(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.sbi == 4 & E.th == 2) = false;               % antenna_fault fails at the top band, harmed
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyEqual(tc, r.policy.share, 1);
verifyTrue(tc, r.policy.met);
verifyEqual(tc, r.first, 'policy');
verifyFalse(tc, r.doppler.met); verifyFalse(tc, r.coverage.met);
% the policy branch together with the coverage branch (reading registered): policy first, both listed
E.nR(E.sbi == 4 & E.th == 2) = 2; E.r_only(E.sbi == 4 & E.th == 2) = true; E.cfg_end(E.sbi == 4 & E.th == 2) = 2;
C.cov_registered = true;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyEqual(tc, T.route.met, {'policy', 'coverage'});
verifyEqual(tc, T.route.first, 'policy');
lines = spd_d_tables('lines', T, C);
verifyTrue(tc, any(contains(lines, 'routing: first policy; branches met: policy, coverage')));
end

function test_coverage_branch(tc)
C = tc.TestData.C;
C.cov_registered = true;
E = base();
m = E.sbi == 4 & E.bbi == 2 & E.th == 1;
E.recovered(m) = false; E.nR(m) = 2; E.r_only(m) = true; E.r_sc(m) = false; E.cfg_end(m) = 2;
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyEqual(tc, r.coverage.small, 1); verifyEqual(tc, r.coverage.only_sc, 1);
verifyEqual(tc, [r.coverage.n_t5 r.coverage.nested], [12 1]);
verifyTrue(tc, r.coverage.met);
verifyFalse(tc, r.policy.met); verifyFalse(tc, r.doppler.met); verifyFalse(tc, r.bank_only.met);
verifyEqual(tc, r.met, {'coverage'});
% T5: the failures from 112 km/h up, where the DQN ends
t5 = T.t5(1);
verifyEqual(tc, t5.n, 12); verifyEqual(tc, t5.end_sc, 12); verifyEqual(tc, t5.end_na, 0); verifyEqual(tc, t5.end_bud, 0);
verifyTrue(tc, startsWith(t5.top, 'channel_switch 12'));
verifyEqual(tc, t5.r_only, 1); verifyEqual(tc, t5.r_small, 1);
% a DQN that ends on no_action is a hold, not a coverage problem
E.cfg_end(m) = 1;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyFalse(tc, T.route.coverage.met);
verifyEqual(tc, T.route.coverage.only_sc, 0);
verifyEqual(tc, T.t5(1).end_na, 12);
% a large restoring set is not a coverage problem either
E.cfg_end(m) = 2; E.nR(m) = 9;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyFalse(tc, T.route.coverage.met);
verifyEqual(tc, T.route.coverage.small, 0);
end

function test_coverage_reads_the_t5_population(tc)
% The ending condition is read on T5's failures (from 112 km/h up), not only on the top-band failures with |R| <= 3.
C = tc.TestData.C;
C.cov_registered = true;
ftop = @(E) E.sbi == 4 & E.bbi == 2 & E.th == 1;            % 12 failures at 140 km/h, in the top band
fmid = @(E) E.sbi == 3 & E.bbi >= 2 & E.th == 1;            % 24 failures at 115 km/h: from 112 km/h up, below the top band
% the top-band failures meet the condition among themselves, the failures below the top band do not
E = base();
m = ftop(E); E.recovered(m) = false; E.nR(m) = 2; E.r_only(m) = true; E.cfg_end(m) = 2;
k = fmid(E); E.speed(k) = 115; E.recovered(k) = false; E.nR(k) = 9; E.r_only(k) = false; E.cfg_end(k) = 1;
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyEqual(tc, [r.coverage.n_small r.coverage.n_t5], [12 36]);
verifyEqual(tc, [r.coverage.small r.coverage.nested], [1 1]);
verifyEqual(tc, r.coverage.only_sc, 1/3, 'AbsTol', 1e-12);
verifyFalse(tc, r.coverage.met);
verifyFalse(tc, ismember('coverage', r.met));
lines = spd_d_tables('lines', T, C);
verifyTrue(tc, any(contains(lines, 'of the 36 failures from 112 km/h up (T5)') & contains(lines, '33.3% (needs 50%)') & ...
    contains(lines, 'the same share is 100.0%')));
% the reverse: among the top-band failures with |R| <= 3 R holds a spatial/channel part, on T5's failures it does not
E = base();
m = ftop(E); E.recovered(m) = false; E.nR(m) = 2; E.r_only(m) = false; E.cfg_end(m) = 2;
k = fmid(E); E.speed(k) = 115; E.recovered(k) = false; E.nR(k) = 9; E.r_only(k) = true; E.cfg_end(k) = 2;
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyEqual(tc, [r.coverage.small r.coverage.nested], [1 0]);
verifyEqual(tc, r.coverage.only_sc, 2/3, 'AbsTol', 1e-12);
verifyTrue(tc, r.coverage.met);
verifyTrue(tc, ismember('coverage', r.met));
% no failure from 112 km/h up: no reading, no branch
E = base();
T = spd_d_tables('tables', E, clean_link(0), C);
verifyEqual(tc, T.route.coverage.n_t5, 0);
verifyFalse(tc, T.route.coverage.met);
end

function test_coverage_is_not_raised_until_its_reading_is_registered(tc)
% The registered text gives the second clause no share: the branch is read and printed, never raised, until a
% dated line registers it (cov_registered); it is the only branch that can switch the training design.
C = tc.TestData.C;
E = base();
m = E.sbi == 4 & E.bbi == 2 & E.th == 1;
E.recovered(m) = false; E.nR(m) = 2; E.r_only(m) = true; E.r_sc(m) = false; E.cfg_end(m) = 2;
T = spd_d_tables('tables', E, clean_link(0), C);
r = T.route;
verifyFalse(tc, r.coverage.registered);
verifyTrue(tc, r.coverage.read);
verifyFalse(tc, r.coverage.met);
verifyEmpty(tc, r.met);
verifyEqual(tc, r.first, 'none');
lines = spd_d_tables('lines', T, C);
verifyTrue(tc, any(contains(lines, '   coverage (reading not registered): ') & contains(lines, '-> met by the reading, not raised')));
verifyTrue(tc, any(contains(lines, 'coverage is met by the reading but not raised')));
verifyTrue(tc, any(contains(lines, 'routing: first none; branches met: none of the four branches is met')));
% the same episodes with the reading registered raise it
C.cov_registered = true;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyTrue(tc, T.route.coverage.read); verifyTrue(tc, T.route.coverage.met);
verifyEqual(tc, T.route.met, {'coverage'});
lines = spd_d_tables('lines', T, C);
verifyFalse(tc, any(contains(lines, 'reading not registered')));
verifyFalse(tc, any(contains(lines, 'not raised')));
% an unmet reading is unmet whether or not it is registered
E.cfg_end(m) = 1;
for reg = [false true]
    C.cov_registered = reg;
    T = spd_d_tables('tables', E, clean_link(0), C);
    verifyFalse(tc, T.route.coverage.read); verifyFalse(tc, T.route.coverage.met);
    verifyFalse(tc, any(contains(spd_d_tables('lines', T, C), 'coverage is met by the reading')));
end
end

function test_benign_rows_and_labels(tc)
C = tc.TestData.C;
E = base();
m = E.sbi == 4 & E.th == 3;
E.recovered(m) = false; E.cfg_end(m) = 4;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyEqual(tc, T.G(4).name, 'benign_interference');
verifyEqual(tc, T.t4(3).name, 'benign_interference');
verifyEqual(tc, T.t4(3).rec(4).rate, 0);
verifyEqual(tc, T.t5(4).name, 'benign_interference');
verifyEqual(tc, T.t5(4).n, 36);
verifyEqual(tc, T.t5(4).end_sc, 36);
lines = spd_d_tables('lines', T, C);
verifyTrue(tc, any(startsWith(lines, 'T1 benign_interference')));
verifyTrue(tc, any(contains(lines, 'T4 per speed band')) && any(contains(lines, '   benign_interference')));
verifyTrue(tc, any(contains(lines, 'benign_interference') & contains(lines, 'failures  36')));
verifyTrue(tc, any(contains(lines, 'train split (in sample for the DQN)')));
verifyTrue(tc, any(contains(lines, 'validation split (used for selection)')));
verifyTrue(tc, any(contains(lines, 'indicative for profile 3')));
end

function test_contrast_values_and_intervals(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.sbi == 4 & E.bbi == 2 & E.th == 1) = false;
T = spd_d_tables('tables', E, clean_link(0), C);
c = T.t2(2);                                              % all threats, bank 20-40 deg, lower bands minus the top band
verifyEqual(tc, [c.d c.lo c.hi], [0.25 0.25 0.25], 'AbsTol', 1e-12);
verifyEqual(tc, c.n, [144 48 18 6]);
verifyTrue(tc, c.point3); verifyTrue(tc, c.meets3);
g = T.t1{1}(4, 2);
verifyEqual(tc, [g.n g.rate g.ncl], [48 0.75 6], 'AbsTol', 1e-12);
% a contrast under 3 points does not count even with a tight interval
E = base();
E.recovered(find(E.sbi == 4 & E.bbi == 1 & E.th == 1, 1)) = false;
T = spd_d_tables('tables', E, clean_link(0), C);
verifyFalse(tc, T.t2(1).point3);
verifyFalse(tc, T.t2(1).meets3);
end

function test_repeatable(tc)
C = tc.TestData.C;
E = base();
E.recovered(E.sbi == 4 & E.bbi == 1 & E.th == 1 & E.flight < 3) = false;
T1 = spd_d_tables('tables', E, clean_link(1), C);
T2 = spd_d_tables('tables', E, clean_link(1), C);
verifyEqual(tc, spd_d_tables('lines', T1, C), spd_d_tables('lines', T2, C));
end
