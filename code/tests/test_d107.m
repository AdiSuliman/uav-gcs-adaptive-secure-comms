function tests = test_d107
%TEST_D107  D107's deploy path (point 5, point 9; d107_after_v0.md sections 3.3 and 3.5): the
%   admissibility test of the no-threat penalty form (aprime_admit.m: (a) the Clopper-Pearson
%   bound, (b) the clustered bootstrap gain with Holm, (b') the geometries, (c) the guards), the
%   selection among the admitted runs and the plain candidates (train_dqn.m section 4b), the stamp
%   that carries the form; the switch off keeps the parent commit's outputs. Synthetic episodes
%   and source texts; no pools, no training. Run from the repository root:
%   results = runtests('code/tests/test_d107.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.base = 'df5cb30';                                    % the merge's first parent: tip3-lb with wf-lb and wf-spd
tc.TestData.pb = {'9e6b7c8', 'ab3410f'};                         % wf-pb (D121 item 16): its parent and its tip
end

%% ---------- (a) the Clopper-Pearson bound ----------
function test_cp_bound_known_values(tc)
% The one-sided 95% upper bound of k false-alarm episodes in n: closed form for k = 0, the
% root of the binomial tail for the others, and the registered 74 of 1800 limit.
W = toy_d107();
for kn = [0 1800; 1 1800; 10 1800; 74 1800; 75 1800; 5 100; 0 59; 0 60]'
    k = kn(1); n = kn(2);
    W.n_w = n; W.fa(:) = k;
    [ADM, ~] = aprime_admit(pack_d107(W), 0.05);
    u = ADM(1).fa_up(1);
    verifyEqual(tc, ADM(1).fa_n, n);
    verifyEqual(tc, u, tail_root(k, n), 'RelTol', 1e-9, sprintf('%d of %d', k, n));
    verifyEqual(tc, ADM(1).fa_up_mean, u, 'RelTol', 1e-12);       % equal counts: the mean is the run
end
W.n_w = 1800; W.fa(:) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).fa_up(1), 1 - 0.05^(1/1800), 'RelTol', 1e-12);
% values from an independent summation of the binomial tail
known = [0 1800 0.001662911535426026; 1 1800 0.002632741074328482; 10 1800 0.009405231220177834; ...
    74 1800 0.04966316220256611; 75 1800 0.050267334503384664; 5 100 0.10225337764327463];
for i = 1:size(known, 1)
    W.n_w = known(i, 2); W.fa(:) = known(i, 1);
    [ADM, ~] = aprime_admit(pack_d107(W), 0.05);
    verifyEqual(tc, ADM(1).fa_up(1), known(i, 3), 'RelTol', 1e-8);
end
% 74 of 1800 is the last count within 5%
W.n_w = 1800; W.fa(:) = 74;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05); verifyTrue(tc, ADM(1).a);
W.fa(1, 3) = 75;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05); verifyFalse(tc, ADM(1).a);
verifyTrue(tc, ADM(2).a);
end

function test_admit_false_alarm_every_run_and_mean(tc)
% (a) holds for every run of the penalty and for the seed mean: one run over the bound fails it
% although the mean (rounded count 74) is within; a run not measured fails it.
W = toy_d107();
W.fa(1, :) = [74 74 75];
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyFalse(tc, ADM(1).a);
verifyEqual(tc, ADM(1).fa_k, [74 74 75]);
verifyLessThanOrEqual(tc, ADM(1).fa_up_mean, 0.05);                 % the mean alone would pass
verifyFalse(tc, ADM(1).admissible);
verifyTrue(tc, ADM(2).admissible);                                   % the other penalty is judged alone
W.fa(1, :) = [20 20 NaN];
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyFalse(tc, ADM(1).a, 'a false-alarm count that was not measured is not within the bound');
W.fa(1, :) = 20; W.fa(2, :) = [90 90 90];
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyTrue(tc, ADM(1).a); verifyFalse(tc, ADM(2).a);
end

%% ---------- (b) the gain, Holm ----------
function test_holm_lower_toy(tc)
B = 10000;
weak = [-ones(1, 300), ones(1, B - 300)];                            % order statistic 250 is -1, 500 is +1
bad = [-ones(1, 600), ones(1, B - 600)];                             % both -1
good = ones(1, B);
% the smaller p is tested at 97.5%: fails, so the other is not tested at all (Holm stops)
[pass, level, lb] = holm_lower([0.03 0.04], {weak, good});
verifyEqual(tc, pass, [false false]);
verifyEqual(tc, level, [0.975 0.95], 'AbsTol', 1e-12);
verifyEqual(tc, lb, [-1 1]);
% the same two with the order of p swapped: good at 97.5%, weak then at 95% passes
[pass, level] = holm_lower([0.04 0.03], {weak, good});
verifyEqual(tc, pass, [true true]);
verifyEqual(tc, level, [0.95 0.975], 'AbsTol', 1e-12);
% the second fails at 95%
[pass, ~] = holm_lower([0.04 0.03], {bad, good});
verifyEqual(tc, pass, [false true]);
% ties go to the lower index
[~, level] = holm_lower([0.02 0.02], {good, good});
verifyEqual(tc, level, [0.975 0.95], 'AbsTol', 1e-12);
% a lower bound of exactly 0 is not above 0
[pass, ~] = holm_lower(0.01, {zeros(1, B)});
verifyFalse(tc, pass);
% one test: the plain 95% bound
[pass, level, lb] = holm_lower(0.01, {[-ones(1, 499), ones(1, B - 499)]});
verifyEqual(tc, [pass level lb], [true 0.95 1], 'AbsTol', 1e-12);
[pass, ~, lb] = holm_lower(0.01, {[-ones(1, 500), ones(1, B - 500)]});
verifyEqual(tc, [pass lb], [false -1]);
% no distribution (fewer than two clusters): fails, and so does everything after it
[pass, ~, lb] = holm_lower([0.5 0.1], {good, []});
verifyEqual(tc, pass, [false false]); verifyTrue(tc, isnan(lb(2)));
% three tests: 1 - 0.05 / 3, 1 - 0.05 / 2, 1 - 0.05 in the order of p
[~, level] = holm_lower([0.3 0.1 0.2], {good, good, good});
verifyEqual(tc, level, [1 - 0.05 / 1, 1 - 0.05 / 3, 1 - 0.05 / 2], 'AbsTol', 1e-12);
end

function test_paired_stats_dist(tc)
% The cluster bootstrap's resample means: sorted, B of them, the 'boot' bounds are their order
% statistics, and 'boot' itself is the parent commit's bit for bit.
rs = RandStream('mt19937ar', 'Seed', 3);
x = randn(rs, 1, 300); cl = randi(rs, 25, 1, 300);
[m, q] = paired_stats('dist', x, cl, 1000, 9);
verifyEqual(tc, size(q), [1 1000]);
verifyTrue(tc, issorted(q));
verifyEqual(tc, m, mean(x), 'AbsTol', 1e-12);
[m1, lb, ub] = paired_stats('boot', x, cl, 1000, 9);
verifyEqual(tc, [m1 lb ub], [m q(50) q(950)]);
[~, q2] = paired_stats('dist', x, cl, 1000, 9); verifyEqual(tc, q2, q);       % a fixed seed
[~, q3] = paired_stats('dist', x, cl, 1000, 10); verifyNotEqual(tc, q3, q);
[m4, q4] = paired_stats('dist', x, ones(1, 300), 1000, 9);                    % one cluster
verifyEqual(tc, m4, mean(x), 'AbsTol', 1e-12); verifyEmpty(tc, q4);
[~, lb4, ub4] = paired_stats('boot', x, ones(1, 300), 1000, 9);
verifyTrue(tc, isnan(lb4) && isnan(ub4));
% the parent's 'boot'
d = parent_copy(tc, 'code/evaluation/paired_stats.m', tc.TestData.base);
addpath(d, '-begin'); clear paired_stats
cl0 = onCleanup(@() fixture_off(d, 'paired_stats')); %#ok<NASGU>
verifyEqual(tc, which('paired_stats'), fullfile(d, 'paired_stats.m'));
cases = {{x, cl, 1000, 9}, {x, cl}, {x, cl, 2000, 1}, {[x NaN], [cl 3], 500, 4}, {x(1:5), 1:5, 300, 2}, {x, ones(1, 300)}, {[], []}};
P = cell(numel(cases), 3);
for k = 1:numel(cases)
    [P{k, 1}, P{k, 2}, P{k, 3}] = paired_stats('boot', cases{k}{:});
end
v0 = paired_stats('mcnemar', 3, 5); u0 = paired_stats('garwood', 4, 100);
fixture_off(d, 'paired_stats');
for k = 1:numel(cases)
    [a, b, c] = paired_stats('boot', cases{k}{:});
    verifyTrue(tc, isequaln([a b c], [P{k, :}]), sprintf('boot case %d', k));
end
verifyEqual(tc, paired_stats('mcnemar', 3, 5), v0);
verifyEqual(tc, paired_stats('garwood', 4, 100), u0);
end

function test_admit_base_case(tc)
% The base episodes: a gain on every harmed S1 episode, no fall anywhere, few false alarms: both
% penalties are admissible, the smaller p at 97.5% and the other at 95%.
W = toy_d107();
[ADM, L] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, [ADM.pen], [120 160]);
verifyEqual(tc, {ADM.runs}, {1:3, 4:6});
verifyTrue(tc, all([ADM.a] & [ADM.b] & [ADM.bprime] & [ADM.c] & [ADM.admissible]));
verifyEqual(tc, [ADM.gain], [1 1], 'AbsTol', 1e-12);
verifyEqual(tc, [ADM.n_gain], [720 720]);
verifyEqual(tc, [ADM.n_clusters], [24 24]);
verifyEqual(tc, [ADM.p], [1 1] / 10001, 'AbsTol', 1e-15);          % every resample mean is above 0
verifyEqual(tc, [ADM.level], [0.975 0.95], 'AbsTol', 1e-12);        % equal p: the lower index first
verifyEqual(tc, ADM(1).geom, 1:6);                                  % antenna_fault's harmed geometries
verifyEqual(tc, ADM(1).geom_diff, ones(1, 6), 'AbsTol', 1e-12);
verifyTrue(tc, all(ADM(1).thr_diff == 0) && ADM(1).pooled_diff == 0 && ADM(1).cov_diff == 0);
verifyTrue(tc, iscellstr(L) && numel(L) == 1 + 5 * 2); %#ok<ISCLSTR>
verifyNotEmpty(tc, strfind(L{2}, 'ADMISSIBLE'));
% one penalty alone: Holm over one test, the 95% bound
W1 = toy_d107(); W1 = keep_pen(W1, 2);
[ADM, ~] = aprime_admit(pack_d107(W1), 0.05);
verifyEqual(tc, [ADM.pen, ADM.level, ADM.admissible], [160 0.95 1], 'AbsTol', 1e-12);
% no runs, more than one discount factor
[ADM, L] = aprime_admit(struct('episodes', W.episodes_empty, 'runs', struct('pen', {})), 0.05);
verifyEmpty(tc, ADM); verifyEmpty(tc, L);
A = pack_d107(W); A.runs(2).gamma = 0;
verifyError(tc, @() aprime_admit(A, 0.05), 'aprime_admit:gamma');
end

function test_admit_gain_is_the_seed_mean_paired(tc)
% (b) reads the per-episode mean over the seeds, minus the paired grid runs' mean: recovered 1,
% 1, 0 for the three seeds against 0 is 2/3 on every harmed S1 episode.
W = toy_d107();
W.Rseed = repmat(W.Ra, [1 1 3]);
W.Rseed(:, 1, :) = repmat(permute([1 1 0], [1 3 2]), size(W.Ra, 1), 1, 1);
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).gain, 2/3, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(2).gain, 1, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(1).geom_diff, (2/3) * ones(1, 6), 'AbsTol', 1e-12);
end

function test_admit_no_gain_fails_b_only(tc)
% No difference on any episode: the lower bound is 0, not above 0; (b'), (c) and (a) hold.
W = toy_d107();
W.Ra(:, 1) = W.Rp(:, 1);
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, [ADM(1).a ADM(1).b ADM(1).bprime ADM(1).c ADM(1).admissible], [true false true true false]);
verifyEqual(tc, ADM(1).gain, 0, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(1).p, 1, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(1).level, 0.95, 'AbsTol', 1e-12);              % the larger p is the second test
verifyEqual(tc, ADM(2).level, 0.975, 'AbsTol', 1e-12);
verifyTrue(tc, ADM(2).admissible);
end

function test_admit_positive_mean_but_lower_bound_not_above_zero(tc)
% A small positive mean over clusters of both signs: the cluster bootstrap's lower bound is
% below 0, so (b) fails although the mean gain is positive.
W = toy_d107();
sg = double(mod(W.r, 2) == 1) * 2 - 1; sg(W.r == 12) = 1;         % odd geometries gain, even lose, geometry 12 gains
for g = {'ah', 'sh'}
    ix = W.ix.(g{1});
    W.Ra(ix, 1) = double(sg(ix) > 0); W.Rp(ix, 1) = double(sg(ix) < 0);
end
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyGreaterThan(tc, ADM(1).gain, 0);
verifyLessThan(tc, ADM(1).lb, 0);
verifyFalse(tc, ADM(1).b);
verifyGreaterThan(tc, ADM(1).p, 0.05);
verifyFalse(tc, ADM(1).admissible);
end

function test_admit_bootstrap_is_the_order_statistic(tc)
% The reported lower bound is the order statistic of the resample means that Holm's level names,
% from a fixed seed: the second test of two reads round(0.05 * B), the first round(0.025 * B).
W = toy_d107();
sg = double(mod(W.r, 2) == 1) * 2 - 1; sg(mod(W.r, 5) == 0) = 1;
for p = 1:2
    for g = {'ah', 'sh'}
        ix = W.ix.(g{1});
        W.Ra(ix, p) = double(sg(ix) > 0); W.Rp(ix, p) = double(sg(ix) < 0);
    end
end
W.Ra(W.ix.sh, 2) = 1; W.Rp(W.ix.sh, 2) = 0;                          % penalty 160 gains more: smaller p
A = pack_d107(W);
[ADM, ~] = aprime_admit(A, 0.05);
% the same bootstrap, outside the function
E = A.episodes; cl = 1000 * E.s + E.r; m = ismember(E.threat, {'antenna_fault', 'airframe_shadowing'}) & E.harmed;
P = zeros(1, 2); Qs = cell(1, 2);
for p = 1:2
    d = W.Ra(:, p)' - W.Rp(:, p)';
    [mm, Qs{p}] = paired_stats('dist', d(m), cl(m), 10000, 107);
    P(p) = (1 + sum(Qs{p} <= 0)) / 10001;
    verifyEqual(tc, ADM(p).gain, mm, 'AbsTol', 1e-12);
    verifyEqual(tc, ADM(p).p, P(p), 'AbsTol', 1e-15);
end
[~, ord] = sort(P);
verifyEqual(tc, ADM(ord(1)).level, 0.975, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(ord(2)).level, 0.95, 'AbsTol', 1e-12);
verifyEqual(tc, ADM(ord(1)).lb, Qs{ord(1)}(250));
verifyEqual(tc, ADM(ord(2)).lb, Qs{ord(2)}(500));
end

%% ---------- (b') the geometries ----------
function test_admit_a_negative_geometry_fails_bprime_only(tc)
% antenna_fault's geometry 1 loses on its harmed episodes while the others gain: the pooled gain
% is clearly positive, (b') is not met.
W = toy_d107();
g1 = W.ix.ah(W.r(W.ix.ah) == 1);
W.Ra(g1, 1) = 0; W.Rp(g1, 1) = 1;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, [ADM(1).a ADM(1).b ADM(1).bprime ADM(1).c ADM(1).admissible], [true true false true false]);
verifyEqual(tc, ADM(1).geom, 1:6);
verifyEqual(tc, ADM(1).geom_diff, [-1 1 1 1 1 1], 'AbsTol', 1e-12);
verifyTrue(tc, ADM(2).admissible);
% a geometry whose seed-mean difference is exactly 0 is not negative
W = toy_d107(); W.Ra(g1, 1) = 0; W.Rp(g1, 1) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyTrue(tc, ADM(1).bprime && ADM(1).admissible);
% a negative geometry of airframe_shadowing is not antenna_fault's
W = toy_d107(); s7 = W.ix.sh(W.r(W.ix.sh) == 7);
W.Ra(s7, 1) = 0; W.Rp(s7, 1) = 1;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyTrue(tc, ADM(1).bprime && ADM(1).admissible);
end

%% ---------- (c) the guards ----------
function test_admit_guard_one_threat_held_falls_by_more_than_1_point(tc)
% 1 of 100 is exactly 1 point (allowed), 2 of 100 more than 1 point: the deploy flag is false.
W = toy_d107();
W.Ha(W.ix.o1(1), 1) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, min(ADM(1).thr_diff), -0.01, 'AbsTol', 1e-12);
verifyTrue(tc, ADM(1).c && ADM(1).admissible);
W.Ha(W.ix.o1(2), 1) = 0;
[ADM, L] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, min(ADM(1).thr_diff), -0.02, 'AbsTol', 1e-12);
verifyEqual(tc, [ADM(1).a ADM(1).b ADM(1).bprime ADM(1).c ADM(1).admissible], [true true true false false]);
verifyGreaterThanOrEqual(tc, ADM(1).pooled_diff, -0.005);          % only this guard
verifyGreaterThanOrEqual(tc, ADM(1).cov_diff, -0.03);
verifyNotEmpty(tc, strfind(L{6}, 'jamming (n 100) -2.00,'));        % the threat over its limit is named with its count
verifyTrue(tc, ADM(2).admissible);
end

function test_admit_guard_pooled_held_falls_by_more_than_half_a_point(tc)
% Six episodes (one per other threat, each 1 point of its threat) are 0.39 point pooled: allowed;
% two more on antenna_fault's harmed episodes make 0.53 point, with no threat above 1 point.
W = toy_d107();
for g = {'o1', 'o2', 'o3', 'o4', 'o5', 'o6'}, W.Ha(W.ix.(g{1})(1), 1) = 0; end
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).pooled_diff, -6 / 1520, 'AbsTol', 1e-12);
verifyTrue(tc, ADM(1).c && ADM(1).admissible);
W.Ha(W.ix.ah(1:2), 1) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).pooled_diff, -8 / 1520, 'AbsTol', 1e-12);
verifyGreaterThanOrEqual(tc, min(ADM(1).thr_diff), -0.01 - 1e-9);   % no threat is over its limit
verifyGreaterThanOrEqual(tc, ADM(1).cov_diff, -0.03);
verifyEqual(tc, [ADM(1).a ADM(1).b ADM(1).bprime ADM(1).c ADM(1).admissible], [true true true false false]);
end

function test_admit_guard_covered_s1_held_falls_by_more_than_3_points(tc)
% Six of the 200 covered S1 episodes are exactly 3 points (allowed), seven are 3.5.
W = toy_d107();
W.Ha(W.ix.ac(1:3), 1) = 0; W.Ha(W.ix.sc(1:3), 1) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).cov_diff, -0.03, 'AbsTol', 1e-12);
verifyTrue(tc, ADM(1).c && ADM(1).admissible);
W.Ha(W.ix.ac(4), 1) = 0;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).cov_diff, -0.035, 'AbsTol', 1e-12);
verifyGreaterThanOrEqual(tc, min(ADM(1).thr_diff), -0.01);          % each threat within its limit
verifyGreaterThanOrEqual(tc, ADM(1).pooled_diff, -0.005);
verifyEqual(tc, [ADM(1).a ADM(1).b ADM(1).bprime ADM(1).c ADM(1).admissible], [true true true false false]);
verifyTrue(tc, ADM(2).admissible);
end

function test_admit_guards_are_seed_means_over_the_recoverable_episodes(tc)
% A fall in one seed of three is a third of it; an episode that is not recoverable is out of
% every reading (the held and the recovered of a non-recoverable episode do not count).
W = toy_d107();
W.Hseed = repmat(W.Ha, [1 1 3]);
W.Hseed(W.ix.o1(1:3), 1, 1) = 0;                                      % 3 episodes lose held in seed 1 only
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, min(ADM(1).thr_diff), -0.01, 'AbsTol', 1e-12);       % 3 / 3 / 100
verifyTrue(tc, ADM(1).admissible);
W = toy_d107();
W.Ha(W.ix.o1(1:10), 1) = 0; W.recoverable(W.ix.o1(1:10)) = false;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, min(ADM(1).thr_diff), 0, 'AbsTol', 1e-12);
verifyTrue(tc, ADM(1).admissible);
% a non-recoverable harmed episode is not part of the gain
W = toy_d107();
W.recoverable(W.ix.ah(1:60)) = false;
[ADM, ~] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).n_gain, 660);
end

%% ---------- the selection ----------
function test_select_run_off_is_the_parent_and_admitted_runs_are_plain_dqn(tc)
% select_run with no third argument is the parent commit's function (the same candidates, pick
% and rule on a set of runs); from a_from on a run is a candidate without the escalation only.
d0 = parent_copy(tc, 'code/decision/train_dqn.m', tc.TestData.base);
cl0 = onCleanup(@() rmdir(d0, 's')); %#ok<NASGU>
[fold, d1] = probe_select(fileread(fullfile(d0, 'train_dqn.m')), 'sel_probe_old_d107');
cl1 = onCleanup(@() fixture_off(d1, 'sel_probe_old_d107')); %#ok<NASGU>
[fnew, d2] = probe_select(fileread(which('train_dqn')), 'sel_probe_new_d107');
cl2 = onCleanup(@() fixture_off(d2, 'sel_probe_new_d107')); %#ok<NASGU>
mk = @(kmin, held, rec, ret, fa) struct('rec', rec, 'held', held, 'kmin', kmin, 'ret', ret, 'fa_w', fa / 1800, 'n_w', 1800, ...
    'sw_w', zeros(1, 4));
runs = struct('esc', {mk(.70, .80, .85, .10, 20), mk(.62, .84, .88, .20, 10), mk(.75, .79, .84, .30, 30)}, ...
    'noesc', {mk(.60, .78, .83, .10, 25), mk(.66, .81, .86, .15, 12), []});     % the third has no reading without the escalation
[c0, b0, w0] = fold(runs, 0.05);
[c1, b1, w1] = fnew(runs, 0.05);
verifyTrue(tc, isequaln(c0, c1) && b0 == b1 && strcmp(w0, w1));
[c2, b2, w2] = fnew(runs, 0.05, Inf);
verifyTrue(tc, isequaln(c0, c2) && b0 == b2 && strcmp(w0, w2));
verifyEqual(tc, numel(c0), 5);
% none within the bound: the three with the lowest bound
bad = runs; for k = 1:3, bad(k).esc.fa_w = 0.3; if ~isempty(bad(k).noesc), bad(k).noesc.fa_w = 0.3; end, end
[c0, b0, w0] = fold(bad, 0.05); [c1, b1, w1] = fnew(bad, 0.05);
verifyTrue(tc, isequaln(c0, c1) && b0 == b1 && strcmp(w0, w1));
% two admitted runs: their escalation readings (higher) are not candidates; the pick can be one of them
ad = struct('esc', {mk(.95, .90, .90, .5, 10), mk(.99, .95, .95, .6, 100)}, 'noesc', {mk(.80, .83, .87, .4, 10), mk(.99, .95, .95, .6, 100)});
RX = [runs, ad];
[c, b, ~] = fnew(RX, 0.05, 4);
verifyEqual(tc, numel(c), 5 + 2);
verifyEmpty(tc, find([c.run] >= 4 & strcmp({c.kind}, 'dqn_esc')));
verifyEqual(tc, c(b).run, 4); verifyEqual(tc, c(b).kind, 'dqn');     % highest weakest-threat held within the bound
[c, b, ~] = fnew(RX, 0.05);                                           % without a_from the escalation reading would win
verifyEqual(tc, [c(b).run, strcmp(c(b).kind, 'dqn_esc')], [4 1]);
% an admitted run over the bound is never picked, whatever its readings
[c, b, ~] = fnew([runs, ad(2)], 0.05, 4);
verifyTrue(tc, c(b).run <= 3);
% an admitted run that is no better than the plain ones is not picked either (rank_pick decides)
weak = struct('esc', mk(.50, .60, .60, .0, 10), 'noesc', mk(.50, .60, .60, .0, 10));
[c, b, ~] = fnew([runs, weak], 0.05, 4);
verifyTrue(tc, c(b).run <= 3);
end

%% ---------- the stamp ----------
function test_policy_stamp_carries_the_form_only_when_set(tc)
S = struct('rule_mmse_db', 6, 'rule_slot', true, 'rule_dwell', 'run', 'esc_drop', false, 'unk_mode', 'all', ...
    'unk_retain', 0.95, 'confirm_sweep', []);
Q = struct('deployed', 'dqn', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', S, 'rule_sel', S);
s1 = policy_stamp(Q);
d = parent_copy(tc, 'code/decision/policy_stamp.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_stamp
cl0 = onCleanup(@() fixture_off(d, 'policy_stamp')); %#ok<NASGU>
verifyEqual(tc, which('policy_stamp'), fullfile(d, 'policy_stamp.m'));
s0 = policy_stamp(Q);
fixture_off(d, 'policy_stamp');
verifyEqual(tc, s1, s0, 'the switch off: the parent commit''s stamp');
Qa = Q; Qa.dec.fa_form = 'all';
Qn = Q; Qn.dec.fa_form = 'nothreat';
sa = policy_stamp(Qa); sn = policy_stamp(Qn);
verifyEqual(tc, numel(unique({s1, sa, sn})), 3);
Qe = Q; Qe.dec.fa_form = [];
verifyEqual(tc, policy_stamp(Qe), s1, 'an empty form is not set');
% a reader that does not load seed_summary reaches the same stamp
Qs = Qn; Qs.seed_summary = struct('selected_fa_form', 'nothreat');
verifyEqual(tc, policy_stamp(Qs), sn);
Qs.seed_summary.selected_fa_form = 'all';
verifyEqual(tc, policy_stamp(Qs), sn, 'the stamp reads dec, which every stamping reader loads');
% every reader that stamps loads dec
for f = {'code/decision/evaluate_policies.m', 'code/evaluation/edge_map.m', 'code/evaluation/measure_latency.m', ...
        'code/evaluation/result_status.m'}
    src = fileread(fullfile(tc.TestData.root, f{1}));
    loads = regexp(src, 'load\(''data/trained_dqn\.mat''[^;]*;', 'match');
    verifyNotEmpty(tc, loads, f{1});
    verifyTrue(tc, all(cellfun(@(l) contains(l, '''dec'''), loads(1))), f{1});
end
end

%% ---------- the switch off ----------
function test_train_dqn_off_view_is_the_parent(tc)
% With the switch off the script is the parent commit's: the parent's text and the current text
% with the code that only runs under the switch removed, and its three one-word substitutions
% undone, are the same text.
d0 = parent_copy(tc, 'code/decision/train_dqn.m', tc.TestData.base);
cl0 = onCleanup(@() rmdir(d0, 's')); %#ok<NASGU>
p = strrep(fileread(fullfile(d0, 'train_dqn.m')), char(13), '');
c = read_lf('train_dqn');
hd0 = '% With "fa_nothreat": true'; hd1 = sprintf('%%\n%% Finished runs (every training run');
sc0 = '%% 7. The no-threat penalty form'; sc1 = 'fprintf(''=== C2 Complete';
p = cut_text(tc, p, hd0, hd1); c = cut_text(tc, c, hd0, hd1);
p = cut_text(tc, p, sc0, sc1); c = cut_text(tc, c, sc0, sc1);
c = cut_text(tc, c, '%% 4b. The no-threat penalty form (D107)', 'B = cand(best); rb = RX(B.run);');
c = swap_text(tc, c, 'rb = RX(B.run);', 'rb = runs(B.run);');
c = swap_text(tc, c, regexp(c, 'fa_form_sel = ''all''; if B\.run[^\n]*', 'match', 'once'), ...
    regexp(p, 'fa_form_sel = ''all'';[^\n]*', 'match', 'once'));
c = swap_text(tc, c, regexp(c, 'if FA_NT\.on, dec\.fa_form = fa_form_sel; end[^\n]*\n', 'match', 'once'), '');
c = swap_text(tc, c, regexp(c, 'rep = \[rep, APL\];[^\n]*\n', 'match', 'once'), '');
c = swap_text(tc, c, regexp(c, 'if FA_NT\.on && numel\(GAMMAS\) ~= 1\n[^\n]*\nend\n', 'match', 'once'), '');
c = swap_text(tc, c, regexp(c, 'if FA_NT\.on && ~\(exist\(''SMOKE'', ''var''\) && SMOKE\) && ~isequal\(SEEDS, 42:44\)\n[^\n]*\nend\n', 'match', 'once'), '');
c = swap_text(tc, c, regexp(c, 'if WF\.force\.aprime && ~FA_NT\.on\n[^\n]*\nend\n', 'match', 'once'), '');
c = swap_text(tc, c, 'the no-threat penalty form (section 4b)', 'the no-threat penalty form (section 7)');
c = swap_text(tc, c, regexp(c, '% The admitted no-threat runs[^\n]*\n[^\n]*\nif nargin < 3, a_from = Inf; end\n', 'match', 'once'), '');
c = swap_text(tc, c, 'select_run(runs, bound, a_from)', 'select_run(runs, bound)');
c = swap_text(tc, c, 'The admissible penalties'''' runs join the selection (aprime_admit.m); the others never enter', ...
    'Descriptive: these runs never enter');
c = swap_text(tc, c, 'if isempty(x) || (k >= a_from && strcmp(q{1}, ''esc'')), continue; end', 'if isempty(x), continue; end');
pl = strsplit(p, newline, 'CollapseDelimiters', false); cl = strsplit(c, newline, 'CollapseDelimiters', false);
n = min(numel(pl), numel(cl)); k = find(~strcmp(pl(1:n), cl(1:n)), 1);
if isempty(k) && numel(pl) ~= numel(cl), k = n + 1; end
verifyTrue(tc, isempty(k), sprintf('first differing line %d', k));
verifyTrue(tc, strcmp(p, c));
end

function test_train_dqn_wiring(tc)
% The registered path in train_dqn.m: the switch, the test of aprime_admit.m on the paired readings
% before the selection, the admitted runs into select_run without the escalation, the stored form,
% the report; the smoke's cell (SMOKE = true; CFG = struct('fa_nothreat', true); run('train_dqn'))
% reaches all of it with one penalty (the grid's 80), one seed and one discount factor.
src = read_lf('train_dqn');
once = {'FA_NT = struct(''on'', fa_nothreat_on(cfgc), ''pen'', [120 160]);', ...
    'if exist(''SMOKE'', ''var'') && SMOKE, FA_NT.pen = FA_PEN; end', ...
    'N_SEEDS = 1; GAMMAS = 0.5; FA_PEN = 80;', ...
    'if FA_NT.on && numel(GAMMAS) ~= 1', ...
    'RX = runs; n_plain = numel(runs); APL = {}; rs7 = {};', ...
    'rp = runs(cand(best).run); ea = struct(''alarm'', rp.alarm, ''drop'', rp.drop);', ...
    '[ADM, APL] = aprime_admit(aprime, FA_BOUND);', ...
    'adm = find(ismember([AR.fa_pen], admp));', ...
    'RX = [runs, AR(adm)];', ...
    '[cand, best, sel_rule] = select_run(RX, FA_BOUND, n_plain + 1);', ...
    'B = cand(best); rb = RX(B.run);', ...
    'fa_form_sel = ''all''; if B.run > n_plain, fa_form_sel = ''nothreat''; end', ...
    'if FA_NT.on, seed_summary.selected_fa_form = fa_form_sel; end', ...
    'if FA_NT.on, dec.fa_form = fa_form_sel; end', ...
    'rep = [rep, APL];', ...
    'rs7 = aprime_lines(aprime, mon_txt(ea.alarm, DROP_MODE), DU);', ...
    '%% 7. The no-threat penalty form''s report'};
for k = 1:numel(once)
    verifyNumElements(tc, strfind(src, once{k}), 1, once{k});
end
% the admitted runs are chosen on the plain selection's monitor and drop threshold and on the
% grid's settings, the pairing is the grid run of the same monitor, drop, penalty, scales, seed
verifyNotEmpty(tc, strfind(src, 'PPa = decision_settings(with_entry(PP, ea, DROP_MODE), Ssel);'));
verifyNotEmpty(tc, regexp(src, 'strcmp\(r\.step, ''grid''\) && strcmp\(r\.alarm, ea\.alarm\) && isequaln\(r\.drop, ea\.drop\)', 'once'));
% the forced smoke cell is wf_force.m's aprime_force (WF.force.aprime), not a field of the switch
verifyEmpty(tc, regexp(src, 'fa_force|FA_NT\.force', 'once'));
end

function test_train_dqn_order_of_the_registered_steps(tc)
src = read_lf('train_dqn');
pos = @(s) strfind(src, s);
a = {'FA_NT = struct(''on'', fa_nothreat_on(cfgc)', 'if FA_NT.on && numel(GAMMAS) ~= 1', ...
    '[cand, best, sel_rule] = select_run(runs, FA_BOUND);', 'RX = runs; n_plain = numel(runs); APL = {}; rs7 = {};', ...
    'AR(end+1) = cached(RC, {''train_one'', ea, fp,', 'A7(i).plain = split_row(P0, PPa, K, val_spec, SPLIT_VAL);', ...
    '[ADM, APL] = aprime_admit(aprime, FA_BOUND);', 'save(''data/aprime_agents.mat'', ''aprime'', ''-v7.3'');', ...
    'RX = [runs, AR(adm)];', '[cand, best, sel_rule] = select_run(RX, FA_BOUND, n_plain + 1);', ...
    'B = cand(best); rb = RX(B.run);', 'fa_form_sel = ''all''; if B.run > n_plain', ...
    '[deployed, fa_bound_met, ir] = choose_deployed(', 'rep = [rep, APL];', 'if FA_NT.on, dec.fa_form = fa_form_sel; end', ...
    'save(''data/trained_dqn.mat'', ''agent''', 'Kft = fa_form_train(Kft, Kf, fa_form_sel);', ...
    '%% 7. The no-threat penalty form''s report'};
at = zeros(1, numel(a));
for k = 1:numel(a)
    x = pos(a{k}); verifyNotEmpty(tc, x, a{k}); at(k) = x(1);
end
verifyEqual(tc, at, sort(at), 'the steps come in the registered order');
verifyNumElements(tc, strfind(src, 'select_run(RX, FA_BOUND, n_plain + 1)'), 1);
% the admitted runs join only inside the branch that has an admissible penalty, only the plain
% runs feed the coordinate steps and the ablation
j = pos('RX = [runs, AR(adm)];'); e = pos('if isempty(adm)'); verifyTrue(tc, ~isempty(e) && e(1) < j(1));
verifyNumElements(tc, strfind(src, 'adm = find(ismember([AR.fa_pen], admp));'), 1);
b = src(at(4):at(11));
verifyEmpty(tc, regexp(b, 'trained_dqn|choose_deployed|PP\.pools\{|SPLIT_TEST|sp\.test', 'once'), 'the choice reads the validation split only');
verifyNotEmpty(tc, strfind(b, 'SPLIT_VAL'));
verifyEmpty(tc, regexp(src, 'FA_NT\.on[^\n]*SPLIT_TEST|SPLIT_TEST[^\n]*FA_NT', 'once'));
end

function test_train_dqn_smoke_cell_reaches_the_step(tc)
% In the smoke the switch comes from CFG, the penalty is the grid's single 80, one seed and one
% discount factor: the checks before the step pass, the step pairs each no-threat run with its one
% grid run, and the admissibility of one penalty is judged by Holm over one test.
src = read_lf('train_dqn');
verifyNotEmpty(tc, strfind(src, 'N_SEEDS = 1; GAMMAS = 0.5; FA_PEN = 80; COST_SCALE = 1; SW_SCALE = 1;'));
verifyEqual(tc, fa_nothreat_on(struct('fa_nothreat', true), 'no_such_profile.json'), true);
% the toy: one penalty, one seed, as the smoke builds it
W = toy_d107(); W = keep_pen(W, 1); W.fa = W.fa(1, 1);
A = pack_d107(W);
verifyEqual(tc, numel(A.runs), 1);
[ADM, L] = aprime_admit(A, 0.05);
verifyEqual(tc, numel(ADM), 1);
verifyEqual(tc, ADM.level, 0.95, 'AbsTol', 1e-12);
verifyTrue(tc, iscellstr(L)); %#ok<ISCLSTR>
% the report is built from the same record, aprime_lines reads the fields the record has
src = read_lf('train_dqn');
verifyNotEmpty(tc, strfind(src, 'rs7 = aprime_lines(aprime, mon_txt(ea.alarm, DROP_MODE), DU);'));
for fld = {'label', 'form', 'w_false', 'alarm', 'drop', 'S', 'pen', 'gammas', 'seeds', 'fa_ebno_thr', 'fa_bound', 'episodes', 'runs'}
    verifyNotEmpty(tc, strfind(src, sprintf('''%s'',', fld{1})), fld{1});
end
end

%% ---------- the forced admission cell (smoke only) ----------
function test_forced_admission_flag_is_read_and_smoke_only(tc)
% aprime_force is read like s1g_force and relm_force (profile.json, CFG over it); a forced cell is
% refused outside the smoke at the stage and at the evaluation; the stamp carries the mark.
f = [tempname '.json'];
cl0 = onCleanup(@() delete_if(f)); %#ok<NASGU>
F = wf_force('read', [], 'none.json');
verifyFalse(tc, F.aprime); verifyFalse(tc, wf_force('any', F));
write_text(f, '{"aprime_force": true}');
F = wf_force('read', [], f);
verifyTrue(tc, F.aprime); verifyEmpty(tc, F.dconf); verifyFalse(tc, F.s1g); verifyFalse(tc, F.relm);
verifyTrue(tc, wf_force('any', F));
F = wf_force('read', struct('aprime_force', false), f); verifyFalse(tc, F.aprime);
F = wf_force('read', struct('aprime_force', true), 'none.json'); verifyTrue(tc, F.aprime);
write_text(f, '{"aprime_force": "yes"}'); verifyError(tc, @() wf_force('read', [], f), 'wf_force:value');
write_text(f, '{"aprime_force": 1}'); verifyError(tc, @() wf_force('read', [], f), 'wf_force:value');
F = wf_force('read', struct('aprime_force', true), 'none.json');
verifyError(tc, @() wf_force('smoke', F, false, 'train_dqn'), 'wf_force:smoke');
wf_force('smoke', F, true, 'train_dqn');
% a cell struct without the field (the earlier callers') is still judged
Fo = struct('dconf', [], 's1g', false, 'relm', false);
verifyFalse(tc, wf_force('any', Fo)); wf_force('smoke', Fo, false, 'stage');
% the mark the agent carries is refused at the evaluation outside the smoke
verifyError(tc, @() wf_force('mark', {'aprime_admission'}, false, 'evaluate_policies'), 'wf_force:smoke');
wf_force('mark', {'aprime_admission'}, true, 'evaluate_policies');
src = read_lf('evaluate_policies');
verifyNotEmpty(tc, strfind(src, 'wf_force(''mark'', Q.dec.wf_forced, exist(''SMOKE'', ''var'') && SMOKE, ''evaluate_policies'');'));
% the stamp tells a forced agent from an unforced one
S = struct('rule_mmse_db', 6, 'rule_slot', true, 'rule_dwell', 'run', 'esc_drop', false, 'unk_mode', 'all', ...
    'unk_retain', 0.95, 'confirm_sweep', [], 'fa_form', 'nothreat');
Q = struct('deployed', 'dqn', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', S, 'rule_sel', S);
Qf = Q; Qf.dec.wf_forced = {'aprime_admission'};
verifyNotEqual(tc, policy_stamp(Qf), policy_stamp(Q));
% wf_options reports it with the other cells
O = wf_options(struct('aprime_force', true), 'none.json'); verifyTrue(tc, O.force.aprime);
end

function test_forced_admission_wiring_in_train_dqn(tc)
src = read_lf('train_dqn');
once = {'if WF.force.aprime && ~FA_NT.on', ...
    'admp = [ADM([ADM.admissible]).pen];', ...
    'admp = ADM(1).pen; aprime.forced = ADM(1).pen; WFF{end+1} = ''aprime_admission'';', ...
    'adm = find(ismember([AR.fa_pen], admp));', ...
    'best = find([cand.run] > n_plain & strcmp({cand.kind}, ''dqn''), 1);'};
for k = 1:numel(once)
    verifyNumElements(tc, strfind(src, once{k}), 1, once{k});
end
verifyNumElements(tc, strfind(src, 'WF.force.aprime'), 3);
% the mark enters dec, which the stamp and the evaluation read; the stage refuses it outside the smoke
verifyNotEmpty(tc, strfind(src, 'wf_force(''smoke'', WF.force, exist(''SMOKE'', ''var'') && SMOKE, ''train_dqn'');'));
verifyNotEmpty(tc, strfind(src, 'if ~isempty(WFF), dec.wf_forced = WFF; end'));
% the forced admission sits in section 4b: after the test, before the saved record and the pick of B
at = [strfind(src, '[ADM, APL] = aprime_admit(aprime, FA_BOUND);'), strfind(src, 'admp = ADM(1).pen;'), ...
    strfind(src, 'save(''data/aprime_agents.mat'', ''aprime'', ''-v7.3'');'), strfind(src, 'adm = find(ismember([AR.fa_pen], admp));'), ...
    strfind(src, 'best = find([cand.run] > n_plain'), strfind(src, 'B = cand(best); rb = RX(B.run);')];
verifyEqual(tc, numel(at), 6); verifyEqual(tc, at, sort(at));
% no decision path knows the cell
for f = {'policy_state', 'policy_mask', 'policy_decide', 'policy_monitor'}
    verifyEmpty(tc, regexp(read_lf(f{1}), 'aprime_force|aprime_admission', 'once'), f{1});
end
% the help text of the stage names it
verifyNotEmpty(tc, strfind(src, '% (profile.json or CFG, wf_force.m; needs fa_nothreat) admits the first penalty'));
end

function test_forced_admission_runs_the_admitted_branch(tc)
% The admitted branch of train_dqn.m section 4b, as its own text (probe_admit), on synthetic runs:
% the admissible penalty's runs join, the pick sentence is written, and a forced cell deploys the
% first admitted run, marked, whatever the rule says; unforced, nothing is marked.
src = fileread(which('train_dqn'));
rd = @(kmin, held, rec, ret, fa) struct('rec', rec, 'held', held, 'kmin', kmin, 'ret', ret, 'fa_w', fa / 1800, 'n_w', 1800, ...
    'sw_w', zeros(1, 4));
mk = @(kmin, held, rec, ret, fa, pen, seed) struct('esc', rd(kmin, held, rec, ret, fa), 'noesc', rd(kmin, held, rec, ret, fa), ...
    'fa_pen', pen, 'seed', seed);
runs = [mk(.70, .80, .85, .10, 20, 80, 42), mk(.62, .84, .88, .20, 10, 80, 43), mk(.75, .79, .84, .30, 30, 80, 44)];
AR = [mk(.95, .90, .90, .5, 10, 120, 42), mk(.94, .90, .90, .5, 10, 120, 43), mk(.40, .50, .50, .0, 10, 160, 42), ...
    mk(.40, .50, .50, .0, 10, 160, 43)];                             % penalty 120 better than the plain runs, 160 worse
ADM = struct('pen', {120, 160}, 'admissible', {true, false});
[fh, d1] = probe_admit(tc, src, 'adm_probe_d107');
cl1 = onCleanup(@() fixture_off(d1, 'adm_probe_d107')); %#ok<NASGU>
[sel, d2] = probe_select(src, 'adm_probe_sel_d107');
cl2 = onCleanup(@() fixture_off(d2, 'adm_probe_sel_d107')); %#ok<NASGU>
[cand0, best0, rule0] = sel(runs, 0.05);
n_plain = numel(runs);
WFno = struct('force', struct('aprime', false));
WFyes = struct('force', struct('aprime', true));
aprime = struct('pen', [120 160]);
% 1. nothing admissible, no force: the plain selection stands, no sentence of the admitted branch
ADM0 = ADM; ADM0(1).admissible = false;
o = fh(ADM0, AR, runs, WFno, 0.05, n_plain, {}, {}, aprime, cand0, best0, rule0);
verifyEqual(tc, numel(o.RX), n_plain); verifyEqual(tc, o.best, best0); verifyEmpty(tc, o.WFF);
verifyTrue(tc, any(contains(o.APL, 'No penalty is admissible')));
verifyFalse(tc, isfield(o.aprime, 'forced'));
% 2. penalty 120 admissible: its two runs join and the better run is picked
o = fh(ADM, AR, runs, WFno, 0.05, n_plain, {}, {}, aprime, cand0, best0, rule0);
verifyEqual(tc, [o.RX.fa_pen], [80 80 80 120 120]);
verifyEqual(tc, o.cand(o.best).run, 4); verifyEqual(tc, o.cand(o.best).kind, 'dqn');
verifyEmpty(tc, find([o.cand.run] > n_plain & strcmp({o.cand.kind}, 'dqn_esc')));
verifyTrue(tc, any(contains(o.APL, 'Admissible: penalty 120. Their runs join')));
verifyTrue(tc, any(contains(o.APL, 'the no-threat run of penalty 120, seed 42')));
verifyEmpty(tc, o.WFF); verifyFalse(tc, isfield(o.aprime, 'forced'));
% 3. forced, the test admits nothing: the first penalty's runs join and the first of them is deployed
o = fh(ADM0, AR, runs, WFyes, 0.05, n_plain, {}, {}, aprime, cand0, best0, rule0);
verifyEqual(tc, [o.RX.fa_pen], [80 80 80 120 120]);
verifyGreaterThan(tc, o.cand(o.best).run, n_plain); verifyEqual(tc, o.cand(o.best).kind, 'dqn');
verifyEqual(tc, o.WFF, {'aprime_admission'}); verifyEqual(tc, o.aprime.forced, 120);
verifyTrue(tc, any(contains(o.APL, 'FORCED (smoke only, not an admission); the test would not admit it')));
verifyTrue(tc, any(contains(o.APL, 'FORCED (smoke only): the no-threat run of penalty 120')));
% 4. forced where the rule would pick a plain run: the admitted run is deployed all the same
AR2 = AR; AR2(1:2) = [mk(.30, .40, .40, .0, 10, 120, 42), mk(.30, .40, .40, .0, 10, 120, 43)];
o = fh(ADM, AR2, runs, WFno, 0.05, n_plain, {}, {}, aprime, cand0, best0, rule0);
verifyLessThanOrEqual(tc, o.cand(o.best).run, n_plain);
verifyTrue(tc, any(contains(o.APL, 'the selection picks a plain run')));
o = fh(ADM, AR2, runs, WFyes, 0.05, n_plain, {}, {}, aprime, cand0, best0, rule0);
verifyGreaterThan(tc, o.cand(o.best).run, n_plain); verifyEqual(tc, o.cand(o.best).kind, 'dqn');
verifyTrue(tc, any(contains(o.APL, 'the selection picks a plain run')));
verifyEqual(tc, o.WFF, {'aprime_admission'});
% 5. the mark of an earlier forced cell stays
o = fh(ADM, AR, runs, WFyes, 0.05, n_plain, {}, {'s1_gate'}, aprime, cand0, best0, rule0);
verifyEqual(tc, o.WFF, {'s1_gate', 'aprime_admission'});
end

%% ---------- the reference entry of C2's rule settings ----------
function test_reference_entry_is_the_monitors_own_threshold(tc)
% The rule settings are tuned at the grid entry equal to the monitor's own drop threshold, also where
% the neighbours are clamped (first CUSUM grid index) or filtered (class_drop below the floor), where
% the middle entry is a neighbour.
src = read_lf('train_dqn');
verifyNotEmpty(tc, strfind(src, 'b0 = drops_of(ENT(iref).alarm, MONP, DROP_MODE, DROP_DB, THC, 0, DROP_FLOOR);'));
verifyNotEmpty(tc, strfind(src, '[~, m0] = min(abs([ENT(jr).drop] - b0));'));
verifyEmpty(tc, strfind(src, 'jr(ceil(numel(jr) / 2))'));
G = 5 * (1:10);
mp = @(p) struct('monitor', {'m'}, 'pick', {p}, 'grid', {G});
for j = [1 2 5 10]                                  % CUSUM grid: first index, interior, last index
    M = mp(G(j));
    ent = drops_of('m', M, 'class_cusum', 36, G, [-2 0 2], 0);
    b0 = drops_of('m', M, 'class_cusum', 36, G, 0, 0);
    [~, m] = min(abs(ent - b0));
    verifyEqual(tc, ent(m), G(j));
end
for p = [3 4 6]                                     % class_drop: floor filters the lower step at 3
    M = struct('monitor', {'m'}, 'pick', {p});
    ent = drops_of('m', M, 'class_drop', 36, G, [-2 0 2], 1);
    b0 = drops_of('m', M, 'class_drop', 36, G, 0, 1);
    [~, m] = min(abs(ent - b0));
    verifyEqual(tc, ent(m), p);
end
end

%% ---------- the pipeline warning, the seeds guard, the comment ----------
function test_reproduced_mismatch_stops_outside_the_smoke_and_stays_out_of_the_rule(tc)
% A re-read that does not reproduce its stored row is an error; only the smoke (a reduced run) warns.
src = read_lf('train_dqn');
w = 'if exist(''SMOKE'', ''var'') && SMOKE, warning(''train_dqn:reproduced'', ''%s'', rmsg);';
e = 'else, error(''train_dqn:reproduced'', ''%s'', rmsg); end';
verifyNumElements(tc, strfind(src, w), 1);
verifyNumElements(tc, strfind(src, e), 1);
verifyNumElements(tc, strfind(src, 'warning(''train_dqn:reproduced'''), 1);
verifyNumElements(tc, strfind(src, 'error(''train_dqn:reproduced'''), 1);
i = strfind(src, w); j = strfind(src, 'a.nothreat.reproduced && a.plain.reproduced');
verifyNumElements(tc, j, 1);
verifyTrue(tc, j < i && i - j < 450, 'the stop follows the test of every run');
verifyTrue(tc, strfind(src, e) - i < 120, 'the error is the warning''s else branch');
verifyTrue(tc, i > strfind(src, 'A7(i).plain = split_row(') && i < strfind(src, '[ADM, APL] = aprime_admit(aprime, FA_BOUND);'));
% the rule never reads it: the field is only recorded and printed
verifyEmpty(tc, regexp(read_lf('aprime_admit'), 'reproduced', 'once'));
verifyNumElements(tc, regexp(src, '''reproduced'', abs\(dqn_held\(V\)', 'match'), 1);
end

function test_no_threat_seeds_are_42_to_44_outside_the_smoke(tc)
src = read_lf('train_dqn');
c = regexp(src, '(?m)^if (FA_NT\.on && ~\(exist\(''SMOKE'', ''var''\) && SMOKE\) && ~isequal\(SEEDS, 42:44\))\n', 'tokens');
verifyNumElements(tc, c, 1);
cond = c{1}{1};
i = strfind(src, cond);
verifyTrue(tc, regexp(src, 'SEEDS = 42 \+ \(0:N_SEEDS-1\);', 'once') < i(1));
verifyTrue(tc, i(1) < strfind(src, 'FA_BOUND = 0.05;'), 'before any training');
% the condition on the cases: the switch, the smoke, the seeds
verifyFalse(tc, guard_d107(cond, true, 42:44, false));
verifyTrue(tc, guard_d107(cond, true, 42:45, false));
verifyTrue(tc, guard_d107(cond, true, 43:45, false));
verifyTrue(tc, guard_d107(cond, true, 42:43, false));
verifyTrue(tc, guard_d107(cond, true, 42, false));
verifyFalse(tc, guard_d107(cond, true, 42, true), 'the smoke has one seed');
verifyFalse(tc, guard_d107(cond, false, 42:43, false), 'the switch off');
end

function test_the_section_of_the_penalty_form_is_named_4b(tc)
src = read_lf('train_dqn');
verifyEmpty(tc, strfind(src, '(section 7)'));
verifyNumElements(tc, strfind(src, '''pen'', [120 160]);   % the no-threat penalty form (section 4b)'), 1);
% the one section 7 left is the descriptive table, and its title names the form's section
verifyNumElements(tc, strfind(src, '%% 7. The no-threat penalty form''s report (section 4b)'), 1);
end

%% ---------- the form in the reader text ----------
function test_the_penalty_form_is_printed_where_the_penalty_is(tc)
% penalty_form_line adds one line when dec.fa_form (or the seed summary's selected_fa_form) is set and
% nothing otherwise; the four places that print the deployed agent's penalty call it, and without
% that call they are the base commit's text.
verifyEmpty(tc, penalty_form_line(struct()));
verifyEmpty(tc, penalty_form_line(struct('dec', struct('confirm', [2 2]), 'seed_summary', struct('selected_fa_pen', 120))));
verifyEmpty(tc, penalty_form_line(struct('dec', struct('fa_form', ''))));
verifyEmpty(tc, penalty_form_line([]));
L = penalty_form_line(struct('dec', struct('fa_form', 'nothreat')));
verifyTrue(tc, iscell(L) && isscalar(L) && ischar(L{1}));
verifyNotEmpty(tc, strfind(L{1}, 'nothreat'));
verifyNotEmpty(tc, strfind(L{1}, 'only on cycles with no threat'));
La = penalty_form_line(struct('dec', struct('fa_form', 'all')));
verifyNotEmpty(tc, strfind(La{1}, ': all ('));
verifyNotEqual(tc, La{1}, L{1});
Ls = penalty_form_line(struct('seed_summary', struct('selected_fa_form', 'nothreat')));
verifyEqual(tc, Ls, L);
Ld = penalty_form_line(struct('dec', struct('fa_form', 'nothreat'), 'seed_summary', struct('selected_fa_form', 'all')));
verifyEqual(tc, Ld, L, 'dec first');
% the places, each with its one call; without the call the file is the base commit's, with wf-pb's change to it
% (behind core3_pools; test_d121 holds it bit-identical against wf-pb's parent) merged in
pl = {'code/decision/evaluate_policies.m', 'for ft = penalty_form_line(Q), rep{end+1} = ft{1}; end'; ...
    'code/decision/experiment_combo_generalization.m', 'for ft = penalty_form_line(Q), rep{end+1} = ft{1}; end'; ...
    'code/decision/experiment_unknown_threat.m', 'for ft = penalty_form_line(Q), rep{end+1} = ft{1}; end'; ...
    'code/evaluation/measure_all_kpis.m', 'for ft = penalty_form_line(Dq), KPI(5).detail{end+1} = ft{1}; end'};
% the one other line the readers hold: evaluate_policies.m's check of the three-state model file (core3_pools only)
ex = {'if c3_on, core3_check(PP, ''evaluate_policies''); end', 'evaluate_policies.m'};
for k = 1:size(pl, 1)
    c = strrep(fileread(fullfile(tc.TestData.root, pl{k, 1})), char(13), '');
    c = cut_line(tc, c, pl{k, 2}, pl{k, 1});
    if endsWith(pl{k, 1}, ex{2}), c = cut_line(tc, c, ex{1}, pl{k, 1}); end
    p = base_with_pb(tc, pl{k, 1});
    verifyTrue(tc, strcmp(c, p), pl{k, 1});
end
% the line sits right after the one that prints the penalty
c = read_lf('evaluate_policies');
verifyNotEmpty(tc, regexp(c, 'selected_fa_pen, PP\.alarm_mode, PP\.confirm, numel\(PP\.combos\)\);\nfor ft = penalty_form_line\(Q\)', 'once'));
c = read_lf('measure_all_kpis');
verifyNotEmpty(tc, regexp(c, 'ss\.selected_fa_pen, ss\.selected_seed[^\n]*\n[^\n]*penalty_form_line\(Dq\)', 'once'));
% the readers load what it reads
for f = {'evaluate_policies', 'experiment_combo_generalization', 'experiment_unknown_threat'}
    src = read_lf(f{1});
    loads = regexp(src, 'load\(''data/trained_dqn\.mat''[^;]*;', 'match');
    verifyTrue(tc, contains(loads{1}, '''dec''') && contains(loads{1}, '''seed_summary'''), f{1});
end
end

function test_the_guard_line_prints_each_threats_count(tc)
% (c)'s line lists every threat with its recoverable episodes and the held change, and the covered
% episodes; the counts are the fields thr_n and cov_n.
W = toy_d107();
W.Ha(W.ix.o1(1:2), 1) = 0;
[ADM, L] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).thr(:)', {'antenna_fault', 'airframe_shadowing', 'jamming', 'noise_burst', 'tone_jamming', ...
    'path_loss', 'benign_interference', 'combined'});
verifyEqual(tc, ADM(1).thr_n(:)', [460 460 100 100 100 100 100 100]);
verifyEqual(tc, ADM(1).cov_n, 200);
verifyEqual(tc, sum(ADM(1).thr_n), 1520);
c = L{6};
verifyNotEmpty(tc, strfind(c, '(c) held against the grid runs, per threat'));
thr = ADM(1).thr(:)'; nn = ADM(1).thr_n(:)';
for i = 1:numel(thr)
    verifyNotEmpty(tc, strfind(c, sprintf('%s (n %d) ', thr{i}, nn(i))), thr{i});
end
verifyNotEmpty(tc, strfind(c, 'jamming (n 100) -2.00,'));
verifyNotEmpty(tc, strfind(c, 'antenna_fault (n 460) +0.00,'));
verifyNotEmpty(tc, strfind(c, 'covered S1 +0.00 (200 episodes, limit -3): FAILS'));
verifyNotEmpty(tc, strfind(L{11}, '(c) held against the grid runs'));    % the other penalty
verifyNotEmpty(tc, strfind(L{11}, 'jamming (n 100) +0.00,'));
verifyNotEmpty(tc, strfind(L{11}, ': ok'));
% fewer recoverable episodes of a threat show in its count
W = toy_d107(); W.recoverable(W.ix.o2(1:40)) = false;
[ADM, L] = aprime_admit(pack_d107(W), 0.05);
verifyEqual(tc, ADM(1).thr_n(4), 60);
verifyNotEmpty(tc, strfind(L{6}, 'noise_burst (n 60) '));
% no recoverable episode at all: no threat to list
W = toy_d107(); W.recoverable(:) = false;
[ADM, L] = aprime_admit(pack_d107(W), 0.05);
verifyEmpty(tc, ADM(1).thr); verifyEmpty(tc, ADM(1).thr_n);
verifyNotEmpty(tc, strfind(L{6}, 'per threat (recoverable episodes, change in points; limit -1): none;'));
verifyFalse(tc, ADM(1).c);
end

%% ---------- static checks ----------
function test_no_truth_field_in_a_decision_path(tc)
% The penalty depends on the simulator's state (sc_eff, healthy), as q does, never on the agent's
% observation; no decision file reads the form or the simulator's state, the policy stamp reads
% the form from dec only, and the admissibility reads stored validation readings only.
for f = {'policy_state', 'policy_mask', 'policy_decide', 'policy_monitor'}
    src = read_lf(f{1});
    for tf = {'healthy', 'harmed', 'sc_eff', '\.ended', 'aprime', 'fa_form', 'fa_nothreat', 'FA_threat', 'FA_NT'}
        verifyEmpty(tc, regexp(src, tf{1}, 'once'), sprintf('%s reads %s', f{1}, tf{1}));
    end
end
src = read_lf('policy_stamp');
verifyEqual(tc, numel(regexp(src, 'fa_form', 'match')), 2);        % the help text and the list of settings
verifyEmpty(tc, regexp(src, 'healthy|harmed|sc_eff|seed_summary|selected_fa', 'once'));
src = read_lf('aprime_admit');
verifyEmpty(tc, regexp(src, '(?<![\w.])(load|fileread|save|fopen)\(', 'once'), 'the admissibility reads no file');
verifyEmpty(tc, regexp(src, 'healthy|sc_eff|\.ended|PP\.|SPLIT|pools', 'once'));
f = regexp(src, '\<E\.(\w+)', 'tokens');
f = unique(cellfun(@(x) x{1}, f, 'UniformOutput', false));
verifyEqual(tc, f(:)', {'harmed', 'r', 's', 'threat'}, 'the episodes'' fields it reads');
src = read_lf('train_dqn');
verifyEmpty(tc, regexp(src, 'FA_NT\.on[^\n]*(healthy|sc_eff)', 'once'));
% the training reward alone reads the state: link_env.m is the parent's but for the form (unchanged here)
% and wf-pb's probs3 field, which it reads from the pools only when they hold it
verifyEqual(tc, base_with_pb(tc, 'code/decision/link_env.m'), read_lf('link_env'));
verifyNotEmpty(tc, strfind(read_lf('link_env'), 'if isfield(P, ''probs3'')'));
end

function test_static_no_conflict_markers_functions_defined_once(tc)
files = {'code/decision/aprime_admit.m', 'code/decision/holm_lower.m', 'code/decision/train_dqn.m', ...
    'code/decision/policy_stamp.m', 'code/decision/fa_nothreat_on.m', 'code/decision/wf_force.m', 'code/decision/penalty_form_line.m', ...
    'code/evaluation/paired_stats.m', ...
    'code/tests/test_d107.m', 'code/tests/test_core.m'};
for f = files
    src = strrep(fileread(fullfile(tc.TestData.root, f{1})), char(13), '');
    verifyEmpty(tc, regexp(src, '(?m)^(<<<<<<<|=======|>>>>>>>)', 'once'), f{1});
    nm = regexp(src, '(?m)^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)\s*\(', 'tokens');
    nm = cellfun(@(x) x{1}, nm, 'UniformOutput', false);
    verifyEqual(tc, numel(unique(nm)), numel(nm), sprintf('%s: a function defined twice', f{1}));
end
for f = {'aprime_admit', 'holm_lower'}
    src = read_lf(f{1});
    nm = regexp(src, '(?m)^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)\s*\(', 'tokens');
    verifyEqual(tc, nm{1}{1}, f{1});
end
% every function the new files call outside MATLAB exists
for f = {'paired_stats', 'holm_lower', 'aprime_admit', 'fa_nothreat_on', 'fa_form_train', 'penalty_form_line', 'wf_force', 'policy_stamp', 'decision_settings'}
    verifyTrue(tc, any(exist(f{1}) == [2 6]), f{1}); %#ok<EXIST>
end
% the local functions train_dqn.m's new code calls are defined there once
src = read_lf('train_dqn');
for f = {'aprime_lines', 'val_episodes', 'split_row', 'select_run', 'rank_pick', 'ternary', 'mon_txt', 'cached', 'run_lines', ...
        'with_entry', 'cp_upper', 'fa_bound_txt'}
    verifyNumElements(tc, regexp(src, ['(?m)^function [^\n]*\<' f{1} '\('], 'match'), 1, f{1});
end
end

function test_cp_upper_of_the_admission_is_the_trainers(tc)
% aprime_admit.m's Clopper-Pearson bound and train_dqn.m's (the false-alarm bound of the
% selection) are the same expression.
a = read_lf('aprime_admit'); b = read_lf('train_dqn');
ta = regexp(a, 'function u = cp_upper\(k, n\)[^\n]*\n[^\n]*\n[^\n]*\nend', 'match', 'once');
tb = regexp(b, 'function u = cp_upper\(k, n\)[^\n]*\n[^\n]*\n[^\n]*\nend', 'match', 'once');
verifyNotEmpty(tc, ta); verifyEqual(tc, ta, tb);
end

%% ---------- helpers ----------
function W = toy_d107()
% Episodes of the admissibility tests: antenna_fault harmed (360, 6 geometries), airframe_shadowing
% harmed (360, 12), each covered (100, 12), six other threats (100 each, 12 geometries); two
% Eb/N0 points. Recovered: the grid runs 0 on the harmed episodes and 1 elsewhere, the no-threat
% runs 1; held 1 everywhere. Two penalties (120, 160), three seeds, 20 of 1800 false alarms.
oth = {'jamming', 'noise_burst', 'tone_jamming', 'path_loss', 'benign_interference', 'combined'};
G = {'antenna_fault', true, 360, 6, 'ah'; 'airframe_shadowing', true, 360, 12, 'sh'; ...
    'antenna_fault', false, 100, 12, 'ac'; 'airframe_shadowing', false, 100, 12, 'sc'};
for k = 1:numel(oth), G(end+1, :) = {oth{k}, false, 100, 12, sprintf('o%d', k)}; end %#ok<AGROW>
thr = {}; harm = []; s = []; r = []; ix = struct();
for g = 1:size(G, 1)
    n = G{g, 3}; nr = G{g, 4}; i = 1:n;
    ix.(G{g, 5}) = numel(thr) + i;
    thr = [thr, repmat(G(g, 1), 1, n)]; %#ok<AGROW>
    harm = [harm, repmat(G{g, 2}, 1, n)]; %#ok<AGROW>
    r = [r, 1 + mod(i - 1, nr)]; %#ok<AGROW>
    s = [s, 1 + mod(floor((i - 1) / nr), 2)]; %#ok<AGROW>
end
nE = numel(thr);
W = struct('thr', {thr}, 'harm', harm, 's', s, 'r', r, 'ix', ix, 'pens', [120 160], 'seeds', 42:44, 'n_w', 1800, ...
    'Rp', ones(nE, 2), 'Ra', ones(nE, 2), 'Hp', ones(nE, 2), 'Ha', ones(nE, 2), 'fa', 20 * ones(2, 3), ...
    'recoverable', true(nE, 1), 'Rseed', [], 'Hseed', []);
hs = [ix.ah, ix.sh];
W.Rp(hs, :) = 0;
W.episodes_empty = struct('threat', {{}}, 'harmed', false(1, 0), 's', zeros(1, 0), 'r', zeros(1, 0));
end

function W = keep_pen(W, k)
% Only the k-th penalty of W.
W.pens = W.pens(k); W.Rp = W.Rp(:, k); W.Ra = W.Ra(:, k); W.Hp = W.Hp(:, k); W.Ha = W.Ha(:, k); W.fa = W.fa(k, :);
if ~isempty(W.Rseed), W.Rseed = W.Rseed(:, k, :); end
if ~isempty(W.Hseed), W.Hseed = W.Hseed(:, k, :); end
end

function A = pack_d107(W)
% The record of train_dqn.m section 4b for W: the episodes, and for every (penalty, seed) the
% no-threat run and its grid run.
nE = numel(W.thr);
A = struct('episodes', struct('scn', zeros(1, nE), 's', W.s, 'r', W.r, 'threat', {W.thr}, 'harmed', W.harm), ...
    'runs', struct('pen', {}, 'gamma', {}, 'seed', {}, 'nothreat', {}, 'plain', {}));
n = 0;
for p = 1:numel(W.pens)
    for k = 1:size(W.fa, 2)
        n = n + 1;
        Ra = W.Ra(:, p); Ha = W.Ha(:, p);
        if ~isempty(W.Rseed), Ra = W.Rseed(:, p, k); end
        if ~isempty(W.Hseed), Ha = W.Hseed(:, p, k); end
        A.runs(n).pen = W.pens(p); A.runs(n).gamma = 0.5; A.runs(n).seed = W.seeds(k);
        A.runs(n).nothreat = reading(Ra, Ha, W.recoverable, W.fa(p, k), W.n_w);
        A.runs(n).plain = reading(W.Rp(:, p), W.Hp(:, p), W.recoverable, 20, W.n_w);
    end
end
end

function x = reading(rec, held, recoverable, fa, n)
nE = numel(rec);
x = struct('recovered', reshape(rec, 1, nE), 'held', reshape(held, 1, nE), 'recoverable', reshape(recoverable, 1, nE), ...
    'threat', true(1, nE), 'noesc', struct('fa_w', fa / n, 'n_w', n));
end

function u = tail_root(k, n)
% The u at which P(X <= k) = 5% for X binomial (n, u): the one-sided 95% Clopper-Pearson bound.
if k >= n, u = 1; return; end
u = fzero(@(p) betainc(1 - p, n - k, k + 1) - 0.05, [1e-12, 1 - 1e-12], optimset('TolX', 1e-16));
end

function [fh, d] = probe_select(src, name)
% select_run of the script text src (with rank_pick and the helpers they call) as a function
% handle: the local functions of a train_dqn.m copied into a function file of their own.
src = strrep(src, char(13), '');
sel = between_text(src, 'function [cand, best, why] = select_run', 'function S = with_nb');
cpu = between_text(src, 'function u = cp_upper(k, n)', 'function t = fa_txt');
ter = between_text(src, 'function out = ternary(c, a, b)', 'function [A, lines] = relm_score');
d = tempname; mkdir(d);
fid = fopen(fullfile(d, [name '.m']), 'w');
fprintf(fid, 'function varargout = %s(varargin)\n[varargout{1:nargout}] = select_run(varargin{:});\nend\n\n%s\n%s\n%s\n', ...
    name, sel, cpu, ter);
fclose(fid);
addpath(d); clear(name);
fh = str2func(name);
end

function t = between_text(s, a, b)
i0 = strfind(s, a); i1 = strfind(s, b);
assert(isscalar(i0) && isscalar(i1) && i1 > i0, 'between_text: %s', a);
t = s(i0:i1 - 1);
end

function s = cut_text(tc, s, a, b)
% s without the text from a (included) to b (excluded), each found once.
i0 = strfind(s, a); i1 = strfind(s, b);
verifyNumElements(tc, i0, 1, a); verifyNumElements(tc, i1, 1, b);
verifyTrue(tc, i1 > i0, a);
s = [s(1:i0 - 1), s(i1:end)];
end

function s = swap_text(tc, s, a, b)
% a, found once, replaced by b.
verifyNotEmpty(tc, a);
i = strfind(s, a);
verifyNumElements(tc, i, 1, a);
s = [s(1:i - 1), b, s(i + numel(a):end)];
end

function s = read_lf(name)
s = strrep(fileread(which(name)), char(13), '');
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy
% queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, ...
    fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function c = cut_line(tc, c, t, nm)
% The one line of c that holds t, cut out.
i = strfind(c, t); verifyNumElements(tc, i, 1, nm);
a = find(c(1:i - 1) == newline, 1, 'last') + 1; if isempty(a), a = 1; end
e = i + find(c(i:end) == newline, 1) - 1;
c = [c(1:a - 1), c(e + 1:end)];
end

function s = base_with_pb(tc, rel)
% The file rel as the base commit holds it with wf-pb's change to it (its tip against its parent) merged in,
% LF only; the base text alone for a file wf-pb leaves alone. A conflict fails the test.
pb = tc.TestData.pb;
d = {parent_copy(tc, rel, tc.TestData.base), parent_copy(tc, rel, pb{1}), parent_copy(tc, rel, pb{2})};
cl = onCleanup(@() cellfun(@(x) rmdir(x, 's'), d)); %#ok<NASGU>
[~, nm, ext] = fileparts(rel);
f = fullfile(d, [nm ext]);
o = [tempname '.txt']; co = onCleanup(@() delete(o)); %#ok<NASGU>
[st, out] = system(sprintf('git merge-file -p "%s" "%s" "%s" > "%s"', f{:}, o));
assertEqual(tc, st, 0, sprintf('git merge-file %s: %s', rel, out));
s = strrep(fileread(o), char(13), '');
end

function fixture_off(d, fn)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
clear(fn);
if isfolder(d), rmdir(d, 's'); end
end

function [fh, d] = probe_admit(tc, src, name)
% The admitted branch of train_dqn.m section 4b (from admp to the line before the report lines'
% APL), as a function of its inputs, with select_run and the helpers it calls: the script's own
% text, not a copy. o = fh(ADM, AR, runs, WF, FA_BOUND, n_plain, APL, WFF, aprime, cand, best, sel_rule).
src = strrep(src, char(13), '');
seg = between_text(src, '    admp = [ADM(', '    APL = [{''''}, APL];');
seg = cut_text(tc, seg, '    save(''data/aprime_agents.mat''', '    adm = find(');
sel = between_text(src, 'function [cand, best, why] = select_run', 'function S = with_nb');
cpu = between_text(src, 'function u = cp_upper(k, n)', 'function t = fa_txt');
ter = between_text(src, 'function out = ternary(c, a, b)', 'function [A, lines] = relm_score');
d = tempname; mkdir(d);
fid = fopen(fullfile(d, [name '.m']), 'w');
fprintf(fid, ['function o = %s(ADM, AR, runs, WF, FA_BOUND, n_plain, APL, WFF, aprime, cand, best, sel_rule)\nRX = runs;\n%s' ...
    'o = struct(''RX'', {RX}, ''cand'', {cand}, ''best'', best, ''sel_rule'', {sel_rule}, ''APL'', {APL}, ''WFF'', {WFF}, ' ...
    '''aprime'', aprime);\nend\n\n%s\n%s\n%s\n'], name, seg, sel, cpu, ter);
fclose(fid);
addpath(d); clear(name);
fh = str2func(name);
end

function t = guard_d107(cond, on, SEEDS, SMOKE) %#ok<INUSD>
% The condition text of the seeds guard in train_dqn.m for a switch, seeds and smoke flag.
FA_NT = struct('on', on); %#ok<NASGU>
t = eval(cond);
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function delete_if(f)
if isfile(f), delete(f); end
end
