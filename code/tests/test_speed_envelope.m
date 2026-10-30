function tests = test_speed_envelope
%TEST_SPEED_ENVELOPE  Unit tests of the speed readings on synthetic data, without pools and without
%   Simulink: speed_options.m (the profile.json switches), speed_inference.m (cluster bootstrap,
%   Hall & Miller bound, permutation test), speed_reading.m (the union reading and its criterion),
%   speed_edge_lines.m, speed_band_table.m, the edge161_n switch of build_policy_pools.m
%   (pool_layout.m, pool_geometries.m, the shadowing flights' selection at 161 km/h, the added
%   C1p work) and the insert-only wiring of build_policy_pools.m, evaluate_policies.m,
%   train_dqn.m and measure_all_kpis.m, whose outputs without the switches are those of the
%   parent commit.
%   Run from the repository root: results = runtests('code/tests/test_speed_envelope.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- the switches ----------
function test_options_off_without_fields(tc)
% No file, no field, other fields only: every reading off and the edge-speed split at 36.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
O0 = struct('inference', false, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"profile": "profile 3", "n_rx": 4, "kpi6_set": "union"}');
verifyEqual(tc, speed_options([], f), O0);
verifyEqual(tc, speed_options(struct('dqn_seeds', 3), f), O0);
verifyEqual(tc, speed_options(), speed_options([], 'profile.json'));
end

function test_options_values(tc)
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
O0 = struct('inference', false, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
write_json(f, '{"speed_inference": true, "speed_band_table": true, "edge161_n": 48}');
O = O0; O.inference = true; O.band_table = true; O.edge161_n = 48;
verifyEqual(tc, speed_options([], f), O);
write_json(f, '{"edge161_n": 36}'); verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"kpi7_union": "descriptive"}');
O = O0; O.union = 'descriptive'; verifyEqual(tc, speed_options([], f), O);
write_json(f, '{"kpi7_union": "off"}'); verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"kpi7_union": "verdict", "kpi7_union_yes": " 30.10.2026 21:30 "}');
O = O0; O.union = 'verdict'; O.yes = '30.10.2026 21:30'; verifyEqual(tc, speed_options([], f), O);
% CFG before the file, field by field
write_json(f, '{"speed_inference": true}');
verifyFalse(tc, speed_options(struct('speed_inference', false), f).inference);
verifyTrue(tc, speed_options(struct('speed_band_table', true), f).band_table);
verifyEqual(tc, speed_options(struct('kpi7_union', 'descriptive'), fullfile(d, 'none.json')).union, 'descriptive');
end

function test_options_errors(tc)
% A wrong value stops; the union is the verdict only with the approval's stamp.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
bad = {'{"speed_inference": 1}', 'speed_options:value'; '{"speed_band_table": "yes"}', 'speed_options:value'; ...
    '{"kpi7_union": "on"}', 'speed_options:value'; '{"kpi7_union": true}', 'speed_options:value'; ...
    '{"kpi7_union": "verdict"}', 'speed_options:yes'; ...
    '{"kpi7_union": "verdict", "kpi7_union_yes": ""}', 'speed_options:yes'; ...
    '{"kpi7_union": "verdict", "kpi7_union_yes": 5}', 'speed_options:yes'; ...
    '{"kpi7_union": "descriptive", "kpi7_union_yes": "30.10.2026 21:30"}', 'speed_options:yes'; ...
    '{"kpi7_union_yes": "30.10.2026 21:30"}', 'speed_options:yes'; ...
    '{"edge161_n": 40}', 'speed_options:value'; '{"edge161_n": "48"}', 'speed_options:value'; ...
    '{"edge161_n": null}', 'speed_options:value'};
for i = 1:size(bad, 1)
    write_json(f, bad{i, 1});
    verifyError(tc, @() speed_options([], f), bad{i, 2}, bad{i, 1});
end
end

%% ---------- the statistics ----------
function test_inference_hand_example(tc)
% Three bands, two strata, seven flights; the episode of band 0 is not counted.
x    = [1 1  1 0  0 0 1  1  1 1 1 0  0 0  1];
band = [1 1  1 1  2 2 2  3  2 2 2 2  3 3  0];
cl   = [1 1  2 2  3 3 3  4  5 5 5 5  6 6  7];
st   = [1 1  1 1  1 1 1  2  2 2 2 2  2 2  1];
pg   = zeros(size(x));
S = speed_inference(x, band, cl, st, pg, 3, 400, [5 6]);
verifyEqual(tc, S.n, [4 7 3]);
verifyEqual(tc, S.nf, [2 2 2]);
verifyEqual(tc, S.m, [3/4 4/7 1/3], 'AbsTol', 1e-12);
verifyEqual(tc, S.point, 3/4 - 1/3, 'AbsTol', 1e-12);
verifyEqual(tc, S.pair, [1 3]);
verifyEqual(tc, S.nU, 6);
verifyGreaterThanOrEqual(tc, S.q, 0);
verifyEqual(tc, S.U, S.point + S.q, 'AbsTol', 1e-12);
verifyTrue(tc, all(S.lo <= S.hi));
verifyGreaterThan(tc, S.p, 0); verifyLessThanOrEqual(tc, S.p, 1);
S2 = speed_inference(x, band, cl, st, pg, 3, 400, [5 6]);
verifyTrue(tc, isequaln(S, S2), 'the same streams, the same result');
Sb = speed_inference(x, band, cl, st, pg, 3, 400, [5 6], 'boot');
verifyTrue(tc, isnan(Sb.p) && isnan(Sb.perm_mean) && Sb.q == S.q);
Sp = speed_inference(x, band, cl, st, pg, 3, 400, [5 6], 'perm');
verifyTrue(tc, isnan(Sp.q) && isnan(Sp.U) && Sp.p == S.p && Sp.perm_mean == S.perm_mean);
% a flight in two bands, strata or groups stops
verifyError(tc, @() speed_inference([1 0], [1 2], [1 1], [1 1], [0 0], 2, 50, 1), 'speed_inference:cluster');
verifyError(tc, @() speed_inference([1 0], [1 1], [1 1], [1 2], [0 0], 2, 50, 1), 'speed_inference:cluster');
verifyError(tc, @() speed_inference([1 0], [1 1], [1 1], [1 1], [0 1], 2, 50, 1), 'speed_inference:cluster');
% nothing to count
E = speed_inference([1 0], [0 0], [1 2], [1 1], [0 0], 2, 50, 1);
verifyTrue(tc, isnan(E.point) && isnan(E.p) && isnan(E.U));
end

function test_inference_identical_flights(tc)
% Flights alike inside every band and stratum: every resample is the sample, so the interval is
% the mean, q is 0 and U is the point.
[x, band, cl, st, pg] = flat_flights(RandStream('mt19937ar', 'Seed', 3), 3, 12);
x(:) = 0.75;
S = speed_inference(x, band, cl, st, pg, 4, 300, [1 2]);
verifyEqual(tc, S.q, 0); verifyEqual(tc, S.U, S.point, 'AbsTol', 1e-12);
verifyEqual(tc, S.lo, S.m, 'AbsTol', 1e-12); verifyEqual(tc, S.hi, S.m, 'AbsTol', 1e-12);
verifyEqual(tc, S.point, 0, 'AbsTol', 1e-12);
end

function test_inference_matches_reference(tc)
% The vectorized resampling against plain loops on other streams: the same band intervals, the
% same q (the Hall & Miller quantile) and the same permutation p and noise-only spread, up to
% the sampling error of 2000 resamples; groups' own flights are permuted among themselves.
rs = RandStream('mt19937ar', 'Seed', 11);
[x, band, cl, st, pg] = banded_flights(rs, [0.95 0.9 0.88 0.82], 3, 12);
B = 2000;
S = speed_inference(x, band, cl, st, pg, 4, B, [21 22]);
[q, lo, hi, p, pm] = reference_inference(x, band, cl, st, pg, 4, B, [31 32]);
verifyEqual(tc, S.q, q, 'RelTol', 0.2);
verifyEqual(tc, S.lo, lo, 'AbsTol', 0.02);
verifyEqual(tc, S.hi, hi, 'AbsTol', 0.02);
verifyEqual(tc, S.p, p, 'AbsTol', 0.05);
verifyEqual(tc, S.perm_mean, pm, 'RelTol', 0.06);
verifyLessThan(tc, S.p, 0.2);                           % the bands differ by construction
verifyGreaterThan(tc, S.perm_mean, 0);
verifyGreaterThan(tc, S.U, S.point);
end

function test_permutation_p_uniform_on_flat_set(tc)
% Bands unrelated to the rates: the permutation p is uniform (exact under exchangeability,
% Ernst 2004). 500 flat sets, 199 permutations each.
rs = RandStream('mt19937ar', 'Seed', 2024);
R = 500; P = zeros(1, R);
for i = 1:R
    [x, band, cl, st, pg] = flat_flights(rs, 3, 30);
    S = speed_inference(x, band, cl, st, pg, 4, 199, [i i + 1], 'perm');
    P(i) = S.p;
end
P = sort(P);
D = max(max(abs((1:R) / R - P), abs((0:R-1) / R - P)));   % Kolmogorov-Smirnov distance to the uniform
verifyLessThan(tc, D, 0.1);
verifyEqual(tc, mean(P), 0.5, 'AbsTol', 0.07);
verifyEqual(tc, mean(P <= 0.05), 0.05, 'AbsTol', 0.04);
verifyGreaterThanOrEqual(tc, min(P), 1 / 200);
% power: a clear band effect is found
[x, band, cl, st, pg] = banded_flights(rs, [0.98 0.9 0.8 0.7], 3, 12);
S = speed_inference(x, band, cl, st, pg, 4, 999, [7 8], 'perm');
verifyLessThan(tc, S.p, 0.01);
end

function test_permutation_stays_in_groups(tc)
% Flights of a shadowing group are permuted among themselves only. Group 1 flies band 4 alone
% at a rate far below the shared flights' (bands 1-3, equal rates): permuted within the group the
% gap to band 4 stays whatever the shared flights' bands are, so noise alone gives a spread as
% large as the observed one; permuted over all flights the gap is spread over the bands and
% noise alone gives a small spread, against which the observed one is highly significant.
rs = RandStream('mt19937ar', 'Seed', 5);
nsh = 24; nsd = 60;
band = [4 * ones(1, nsh), randi(rs, 3, 1, nsd)];
cl = 1:(nsh + nsd);
pg = [ones(1, nsh), zeros(1, nsd)];
st = [mod(0:nsh-1, 3) + 1, mod(0:nsd-1, 3) + 1];
x = [0.5 + 0.02 * rand(rs, 1, nsh), 0.9 + 0.02 * rand(rs, 1, nsd)];
Sg = speed_inference(x, band, cl, st, pg, 4, 999, [1 2], 'perm');
Su = speed_inference(x, band, cl, st, zeros(size(pg)), 4, 999, [1 2], 'perm');
verifyGreaterThan(tc, Sg.point, 0.35);
verifyGreaterThan(tc, Sg.perm_mean, 0.35);
verifyLessThan(tc, Su.perm_mean, 0.2);
verifyLessThan(tc, Su.p, 0.01);
end

%% ---------- the readings ----------
function test_reading_modes_and_criterion(tc)
edges = [29 62 95 128 161]; cg = [0 1];
O = struct('inference', false, 'union', 'descriptive', 'yes', '', 'band_table', false, 'edge161_n', 36);
% flights alike: spread 0 on both readings, the bound 0 -> committed
R1 = make_run(3, 12, [0 0 0 0], [1 1 1 0], [1 1 1 0], false);
R2 = make_run(5, 36, [0 0 0 0], [1 1 1 0], [1 1 1 0], false);
[SU, lines] = speed_reading(R1, R1.recoverable & R1.threat, R2, cg, edges, registered_spread(R1, edges), O);
verifyEqual(tc, SU.word_union, 'MET (committed)'); verifyEqual(tc, SU.word_test, 'MET');
verifyEqual(tc, SU.U_union, 0); verifyEqual(tc, SU.point_union, 0);
verifyEqual(tc, SU.union.nU, 4 * (12 + 36));
verifyTrue(tc, SU.reproduced);
txt = strjoin(lines, newline);
verifyTrue(tc, contains(txt, 'KPI 7 speed part on the union of the test and second-test single sets'));
verifyTrue(tc, contains(txt, 'criterion (D117 point 1): MET (committed) iff U <= 10 points; MET (not committed) iff the point <= 10 < U; NOT MET iff the point > 10 -> MET (committed) (descriptive)'));
verifyTrue(tc, contains(txt, 'continuity line with profile 1, the test single set alone under the registered rule'));
verifyTrue(tc, endsWith(lines{find(contains(lines, 'continuity line with profile 1'), 1)}, '-> MET (the verdict)'));
verifyTrue(tc, contains(txt, 'result, KPI 7 speed part: test single set alone, the registered rule and the verdict, MET (spread 0.0 points); union, descriptive, MET (committed) (spread 0.0 points, U 0.0)'));
verifyFalse(tc, contains(txt, 'result, KPI 7 speed part: union'));
verifyFalse(tc, contains(txt, 'THE TWO READINGS DIFFER'));
verifyFalse(tc, contains(txt, 'NOT REPRODUCED'));
% the Hall & Miller bound is written out
verifyTrue(tc, contains(txt, 'Hall & Miller 2010, joint-centred cluster bootstrap, one-sided 95%'));
verifyTrue(tc, contains(txt, 'U = max over a ~= b of (m_a - m_b) + q = 0.0 + 0.0 = 0.0 points'));
verifyTrue(tc, contains(txt, 'the 95% quantile over 9999 replicates of max over a ~= b of [(m*_a - m*_b) - (m_a - m_b)]'));
verifyTrue(tc, contains(txt, 'permutation test of association (whole flights'' bands permuted within Eb/N0 strata'));
% the point within the target, a wide bound -> not committed; the test-only line alone says MET
R1 = make_run(3, 10, [2 3 3 3], [1 1 1 1], [1 1 0 0], false);
R2 = make_run(5, 10, [2 3 3 3], [1 1 1 1], [1 1 0 0], false);
SU = speed_reading(R1, R1.recoverable & R1.threat, R2, cg, edges, registered_spread(R1, edges), O);
verifyEqual(tc, SU.word_union, 'MET (not committed)'); verifyEqual(tc, SU.word_test, 'MET');
verifyEqual(tc, SU.point_union, 5, 'AbsTol', 1e-9);
verifyGreaterThan(tc, SU.U_union, 10);
% a spread above the target -> NOT MET on both
R1 = make_run(3, 10, [0 0 10 10], [1 1 1 1], [1 1 0 0], false);
R2 = make_run(5, 10, [0 0 10 10], [1 1 1 1], [1 1 0 0], false);
SU = speed_reading(R1, R1.recoverable & R1.threat, R2, cg, edges, registered_spread(R1, edges), O);
verifyEqual(tc, SU.word_union, 'NOT MET'); verifyEqual(tc, SU.word_test, 'NOT MET');
% the shadowing group's own flights in the data: the same estimand
R1 = make_run(3, 10, [2 3 3 3], [1 1 1 1], [1 1 0 0], true);
R2 = make_run(5, 10, [2 3 3 3], [1 1 1 1], [1 1 0 0], true);
SU = speed_reading(R1, R1.recoverable & R1.threat, R2, cg, edges, registered_spread(R1, edges), O);
verifyEqual(tc, SU.point_union, 5, 'AbsTol', 1e-9);
end

function test_reading_descriptive_unless_approved(tc)
% The two readings disagree (the small test set spreads 50 points, the union 3): without the
% approval the verdict stays the test-only line and says so; with it the union is the verdict.
edges = [29 62 95 128 161]; cg = [0 1];
R1 = make_run(3, 4, [0 0 2 4], [1 1 1 1], [1 1 0 0], false);
R2 = make_run(5, 60, [0 0 0 0], [1 1 1 0], [1 1 1 0], false);
m1 = R1.recoverable & R1.threat; SPR = registered_spread(R1, edges);
O = struct('inference', false, 'union', 'descriptive', 'yes', '', 'band_table', false, 'edge161_n', 36);
[SU, lines] = speed_reading(R1, m1, R2, cg, edges, SPR, O);
txt = strjoin(lines, newline);
verifyEqual(tc, SU.mode, 'descriptive');
verifyEqual(tc, SU.word_test, 'NOT MET');
verifyTrue(tc, startsWith(SU.word_union, 'MET'));
verifyFalse(tc, SU.met, 'descriptive: the verdict is the test-only line');
verifyTrue(tc, contains(txt, 'DESCRIPTIVE ONLY, Adi''s approval of D117 point 1 is not recorded: the verdict stays the test-only line'));
verifyFalse(tc, contains(txt, 'VERDICT LINE'));
verifyTrue(tc, contains(txt, 'THE TWO READINGS DIFFER'));
verifyTrue(tc, contains(txt, 'result, KPI 7 speed part: test single set alone, the registered rule and the verdict, NOT MET (spread '));
verifyTrue(tc, contains(txt, '); union, descriptive, MET'));
verifyFalse(tc, contains(txt, 'result, KPI 7 speed part: union'));         % the union is never the result line's first reading
verifyTrue(tc, endsWith(lines{find(contains(lines, 'criterion (D117 point 1)'), 1)}, ' (descriptive)'));
verifyTrue(tc, endsWith(lines{find(contains(lines, 'continuity line with profile 1'), 1)}, '-> NOT MET (the verdict)'));
verifyEqual(tc, SU.point_test, 100 * SPR(1), 'AbsTol', 1e-9);
verifyTrue(tc, any(contains(SU.kpi_lines, 'DESCRIPTIVE')) && any(contains(SU.kpi_lines, 'THE TWO READINGS DIFFER')));
O.union = 'verdict'; O.yes = '30.10.2026 21:30';
[SV, lines] = speed_reading(R1, m1, R2, cg, edges, SPR, O);
txt = strjoin(lines, newline);
verifyEqual(tc, SV.mode, 'verdict');
verifyTrue(tc, SV.met, 'verdict: the union decides');
verifyTrue(tc, contains(txt, 'VERDICT LINE, approved by Adi on 30.10.2026 21:30'));
verifyFalse(tc, contains(txt, 'DESCRIPTIVE ONLY'));
verifyTrue(tc, contains(txt, 'result, KPI 7 speed part: union MET'));
verifyTrue(tc, contains(txt, '; test single set alone NOT MET (spread '));
verifyFalse(tc, contains(txt, '(descriptive)') || contains(txt, '(the verdict)') || contains(txt, 'and the verdict,'));
verifyTrue(tc, any(contains(SV.kpi_lines, 'VERDICT, approved by Adi on 30.10.2026 21:30')));
verifyEqual(tc, SV.word_union, SU.word_union); verifyEqual(tc, SV.U_union, SU.U_union);   % the numbers do not move with the mode
% inference lines on the test set alone, no union
O = struct('inference', true, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
[SI, lines] = speed_reading(R1, m1, [], cg, edges, SPR, O);
txt = strjoin(lines, newline);
verifyEqual(tc, SI.mode, 'lines'); verifyEmpty(tc, SI.union); verifyEqual(tc, SI.word_union, '');
verifyTrue(tc, contains(txt, 'Speed inference, test single set (D116 item 5; descriptive, nothing is selected on it)'));
verifyTrue(tc, contains(txt, 'recovered per band'));
verifyFalse(tc, contains(txt, 'criterion (D117 point 1)'));
verifyNumElements(tc, SI.kpi_lines, 1);
% a union without its second-test set stops
O.union = 'descriptive';
verifyError(tc, @() speed_reading(R1, m1, [], cg, edges, SPR, O), 'speed_reading:single2');
end

function test_reading_spread_not_reproduced(tc)
% A test single set whose spread is not the registered one is printed and warned about, and the
% reading goes on (a stop would lose the whole evaluation).
edges = [29 62 95 128 161]; cg = [0 1];
R1 = make_run(3, 4, [0 0 2 4], [1 1 1 1], [1 1 0 0], false);
R2 = make_run(5, 60, [0 0 0 0], [1 1 1 0], [1 1 1 0], false);
m1 = R1.recoverable & R1.threat; SPR = registered_spread(R1, edges);
O = struct('inference', false, 'union', 'descriptive', 'yes', '', 'band_table', false, 'edge161_n', 36);
verifyWarning(tc, @() speed_reading(R1, m1, R2, cg, edges, SPR + [0.01 0 0], O), 'speed_reading:point');
w = warning('off', 'speed_reading:point'); cl = onCleanup(@() warning(w)); %#ok<NASGU>
[SN, lines] = speed_reading(R1, m1, R2, cg, edges, SPR + [0.01 0 0], O);
verifyFalse(tc, SN.reproduced);
verifyTrue(tc, any(contains(lines, 'NOT REPRODUCED')));
verifyTrue(tc, startsWith(SN.word_union, 'MET'));
end

function test_edge_lines_like_for_like(tc)
% Hover 95% and 161 km/h 60% with the shadowing flights (all failed), 90% without them.
g = []; rec = []; shd = []; lo = []; hi = [];
for f = 1:20, g = [g f f]; rec = [rec 1 1 - (f <= 2)]; shd = [shd false false]; lo = [lo true true]; hi = [hi false false]; end %#ok<AGROW>
for f = 21:30, g = [g f f]; rec = [rec 1 1 - (f <= 22)]; shd = [shd false false]; lo = [lo false false]; hi = [hi true true]; end %#ok<AGROW>
for f = 31:35, g = [g f f]; rec = [rec 0 0]; shd = [shd true true]; lo = [lo false false]; hi = [hi true true]; end %#ok<AGROW>
R = struct('recovered', rec, 'geom', g);
m = true(size(rec));
L = speed_edge_lines(R, m, logical(lo), logical(hi), logical(shd));
verifyNumElements(tc, L, 4);
verifyTrue(tc, startsWith(L{2}, '  hover: 95.0% ['));
verifyTrue(tc, contains(L{2}, '(40 episodes, 20 flights)'));
verifyTrue(tc, startsWith(L{3}, '  161 km/h, the registered line (airframe shadowing included): 60.0% ['));
verifyTrue(tc, contains(L{3}, '(30 episodes, 15 flights)'));
verifyTrue(tc, contains(L{4}, 'like-for-like with hover (beside the registered line, never in its place): 90.0% ['));
verifyTrue(tc, contains(L{4}, '(20 episodes, 10 flights)'));
% an empty row says so
L = speed_edge_lines(R, m, logical(lo), false(size(hi)), logical(shd));
verifyTrue(tc, contains(L{3}, 'no episode') && contains(L{4}, 'no episode'));
end

function test_band_table_numbers(tc)
edges = [29 62 95 128 161]; ebno = [0 12];
thr   = {'antenna_fault', 'antenna_fault', 'jamming', 'jamming', 'antenna_fault', 'airframe_shadowing', 'jamming', 'antenna_fault'};
speed = [30 30 50 50 140 150 150 100];
s     = [1 2 1 2 1 2 1 2];
rec   = [1 0 1 1 0 1 1 1];
harm  = [0 1 0 0 1 1 0 0];
[L, T] = speed_band_table(rec, harm, thr, s, speed, ebno, edges);
verifyEqual(tc, T.threats, {'antenna_fault', 'jamming', 'airframe_shadowing'});
verifyTrue(tc, same(T.rec_band, [0.5 NaN 1 0; 1 NaN NaN 1; NaN NaN NaN 1]));
verifyEqual(tc, T.n_band, [2 0 1 1; 2 0 0 1; 0 0 0 1]);
verifyTrue(tc, same(T.rec_ebno, [0.5 0.5; 1 1; NaN 1]));
verifyEqual(tc, T.n_ebno, [2 2; 2 1; 0 1]);
verifyTrue(tc, same(T.pooled_band, [0.75 NaN 1 2/3]));
verifyEqual(tc, T.pooled_n, [4 0 1 3]);
verifyEqual(tc, T.lb_n, [1 0 0 2]);
verifyTrue(tc, same(T.lb_rec, [0 NaN NaN 0.5]));
verifyTrue(tc, same(T.lb_share, [0.5 NaN 0 1]));
verifyTrue(tc, same(T.deficit, [25 NaN 0 100 / 3]));
verifyTrue(tc, same(T.deficit_lb, [25 NaN 0 100 / 3]));
verifyNumElements(tc, L, 11);
verifyTrue(tc, contains(L{1}, 'reported only, nothing is selected on it'));
verifyTrue(tc, contains(L{2}, 'speed bands 29-62, 62-95, 95-128, 128-161 km/h || Eb/N0 0, 12 dB'));
verifyTrue(tc, contains(L{end}, '128-161 km/h: 2 harmed, recovered 50.0%, harmed share 100.0% | deficit 33.3 points, 33.3 on them (100.0% of it)'));
verifyTrue(tc, contains(L{end-3}, '29-62 km/h: 1 harmed, recovered 0.0%, harmed share 50.0% | deficit 25.0 points, 25.0 on them (100.0% of it)'));
% other lost-branch classes
[~, T2] = speed_band_table(rec, harm, thr, s, speed, ebno, edges, {'jamming'});
verifyEqual(tc, T2.lb_n, [0 0 0 0]);
end

%% ---------- the edge-speed split ----------
function test_edge161_geometries_prefix(tc)
% 48 geometries per Eb/N0 add 12 flights at 161 km/h after the 36 of today's pools: the first 36
% are the same flights bit for bit, and so is every other split's list (its seed block and its
% positions do not depend on the edge-speed split's size). The lists are drawn as
% build_policy_pools.m draws them.
p = base_params(4); verifyEqual(tc, p.n_rx, 4);
G36 = pool_lists(p, 36); G48 = pool_lists(p, 48);
for s = 1:numel(p.EbNo_dB)
    for sp = [1 2 3 5]
        verifyTrue(tc, isequaln(G48{s, sp}, G36{s, sp}), sprintf('Eb/N0 %d, split %d', s, sp));
    end
    for f = fieldnames(G36{s, 4})'
        verifyTrue(tc, isequaln(G48{s, 4}.(f{1})(1:36), G36{s, 4}.(f{1})), sprintf('Eb/N0 %d, field %s', s, f{1}));
    end
    g = G48{s, 4};
    verifyEqual(tc, g.speed, [zeros(1, 24), 161 * ones(1, 24)]);
    verifyEqual(tc, g.run, 1600 + (1:48));
    verifyEqual(tc, numel(unique(g.seed)), 48);
    verifyEmpty(tc, intersect(g.seed(37:48), G36{s, 4}.seed));
end
src = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, strfind(src, 'r = r0(sp) + (1:NGEO(sp));'));
verifyNotEmpty(tc, strfind(src, 'r0 = arrayfun(@(sp) sum(nG(1:sp-1) .* (BLOCK(1:sp-1) == BLOCK(sp))), 1:nSp);'));
verifyNotEmpty(tc, strfind(src, 'NGEO   = [8 6 12 36 60];'));
verifyNotEmpty(tc, strfind(src, 'NGEO(4) = SPO.edge161_n;'));
verifyNotEmpty(tc, strfind(src, 'SPO = speed_options();'));
end

function test_edge161_layout(tc)
% pool_layout.m with 48: the edge-speed split holds 24 flights at hover and 24 at 161 km/h for the
% clean link and the nominal severity, 24 at hover for the other severities, and the shadowing
% group of the nominal level flies 24 of its own; every other split's positions are unchanged.
p = base_params(4); C = decision_config(); verifyEqual(tc, p.n_rx, 4);
NCOMB = [0 0 0 0 24]; NHOVER = 24; iSpd = 4;
th = {}; sev = [];
for t = {'none', 'jamming', 'airframe_shadowing'}
    v = 1:numel(C.sev_names); if strcmp(t{1}, 'none'), v = C.nominal; end
    th = [th, repmat(t, 1, numel(v))]; sev = [sev, v]; %#ok<AGROW>
end
for t = {'jamming+path_loss', 'jamming+airframe_shadowing', 'tone_jamming+spoofing+airframe_shadowing'}
    th = [th, repmat(t, 1, numel(C.combo_sev))]; sev = [sev, C.combo_sev]; %#ok<AGROW>
end
lv = nan(1, numel(th));
for c = find(contains(th, 'airframe_shadowing')), lv(c) = threat_params(p, th{c}, sev(c), C).shadow_db; end
grp = shadow_groups(lv, p);
kind = 1 + contains(th, '+'); kind(strcmp(th, 'none')) = 0;
[g36, r36, n36, q36] = pool_layout(kind, grp, sev, C.nominal, [8 6 12 36 60], NCOMB, NHOVER, iSpd);
[g48, r48, n48, q48] = pool_layout(kind, grp, sev, C.nominal, [8 6 12 48 60], NCOMB, NHOVER, iSpd);
verifyEqual(tc, n36, [40 30 60 48 372]);
verifyEqual(tc, n48, [40 30 60 72 372]);
for c = 1:numel(th)
    for sp = [1 2 3 5]
        verifyEqual(tc, g48{c}{sp}, g36{c}{sp});
    end
end
for sp = [1 2 3 5], verifyEqual(tc, r48{sp}, r36{sp}); end
n = @(g, c) cellfun(@numel, g{c});
ij = find(strcmp(th, 'jamming')); ish = find(strcmp(th, 'airframe_shadowing'));
verifyEqual(tc, n(g36, 1), [8 6 12 36 84]); verifyEqual(tc, n(g48, 1), [8 6 12 48 84]);   % the clean link
verifyEqual(tc, g48{1}{4}, 1:48);
verifyEqual(tc, n(g48, ij(1)), [8 6 12 24 60]);                                          % other severities: hover only
verifyEqual(tc, g48{ij(1)}{4}, 1:24);
verifyEqual(tc, n(g48, ij(C.nominal)), [8 6 12 48 60]);                                  % the nominal severity: 24 + 24
verifyEqual(tc, g48{ij(C.nominal)}{4}, 1:48);
verifyEqual(tc, g36{ish(C.nominal)}{4}, 36 + (1:12));
verifyEqual(tc, g48{ish(C.nominal)}{4}, 48 + (1:24));                                    % its own flights at 161 km/h
for c = ish(ish ~= ish(C.nominal)), verifyEmpty(tc, g48{c}{4}); end
verifyEqual(tc, sort([g48{1}{4}, r48{4}]), 1:n48(4));                                    % the clean link flies every geometry
verifyEmpty(tc, intersect(r48{4}, g48{1}{4}));
verifyEqual(tc, sort([q48([q48.split] == 4).pos]), 48 + (1:24));
verifyEqual(tc, [q36([q36.split] == 4).pos], 36 + (1:12));
% the reduced chain check with one flight more at 161 km/h
[g, ~, nG] = pool_layout(kind, grp, sev, C.nominal, [2 2 2 2 2], [0 0 0 0 2], 1, iSpd);
[h, ~, nH] = pool_layout(kind, grp, sev, C.nominal, [2 2 2 3 2], [0 0 0 0 2], 1, iSpd);
verifyEqual(tc, nG, [10 10 10 3 16]); verifyEqual(tc, nH, [10 10 10 5 16]);
verifyEqual(tc, cellfun(@numel, g{ish(C.nominal)}), [2 2 2 1 2]);
verifyEqual(tc, cellfun(@numel, h{ish(C.nominal)}), [2 2 2 2 2]);
verifyEqual(tc, cellfun(@numel, h{1}), [2 2 2 3 4]);
end

function test_edge161_shadow_candidates(tc)
% The shadowing group of the nominal level still finds its flights at 161 km/h within the
% candidate limit with 24 of them, and its first 12 are the flights it finds with 12 (the
% candidates are tried in order): at every Eb/N0, every flight hides an antenna at the group's
% lowest level.
p = base_params(4); C = decision_config(); verifyEqual(tc, p.n_rx, 4);
J_MAX = 99999; BLOCK = 16;
S = pool_cells(p, C);
gi = S.grp(find(strcmp(S.th, 'airframe_shadowing') & S.sev == C.nominal, 1));
verifyGreaterThan(tc, gi, 0);
ps = p; ps.active_threat = 'airframe_shadowing'; ps.shadow_db = min(S.level(S.grp == gi));
for s = 1:numel(p.EbNo_dB)
    eb = p.EbNo_dB(s);
    keep = @(sd, v, a, kk, o, c) hides_antenna(sd, v, ps, struct('ebno', eb, 'alt_m', a, 'k_sig_db', kk, ...
        'aoa1_deg', o, 'rho', c, 'event_frame', C.event_frame, 'frames', C.event_count));
    sel = struct('seed', @(j, v) shadow_pool_seed(gi, s, BLOCK, j, v), 'j0', 0, 'jmax', J_MAX, ...
        'floor', @(a) shadow_alt_floor(a, eb, ps), 'keep', keep);
    [g12, i12] = pool_geometries(s, BLOCK, 36 + (1:12), repmat([161 161], 12, 1), p, [], 1, sel);
    [g24, i24] = pool_geometries(s, BLOCK, 48 + (1:24), repmat([161 161], 24, 1), p, [], 1, sel);
    verifyLessThan(tc, i24.j, J_MAX, sprintf('Eb/N0 %d: candidates tried', s));
    verifyGreaterThanOrEqual(tc, i24.j, i12.j);
    verifyEqual(tc, g24.seed(1:12), g12.seed, sprintf('Eb/N0 %d: the first 12 flights', s));
    verifyEqual(tc, numel(unique(g24.seed)), 24);
    verifyEqual(tc, g24.speed, 161 * ones(1, 24));
    verifyEqual(tc, g24.run, 100 * BLOCK + 48 + (1:24));
    verifyTrue(tc, all(arrayfun(@(i) keep(g24.seed(i), g24.speed(i), NaN, NaN, NaN, NaN), 1:24)));
end
end

function test_edge161_cost(tc)
% The simulation work 48 adds to C1p, from the per-cell counts as build_policy_pools.m lays the
% cells out (pool_layout.m) and the frames each flight flies (20; the shadowing groups' flights
% C.event_run), weighted by the runs and emitters of each cell (pool_cost.m): only the edge-speed
% split's work grows, and the growth is at most 3 h of the 105 h planned for profile 3's C1p.
p = base_params(4); C = decision_config(); A = policy_actions(); verifyEqual(tc, p.n_rx, 4);
S = pool_cells(p, C);
nC = numel(S.th); nS = numel(p.EbNo_dB); F_SUB = 20; NHOVER = 24; iSpd = 4; NG4 = [36 48];
unit = zeros(1, nC);                                    % work of one frame in every configuration's run
for c = 1:nC
    unit(c) = pool_cost(threat_params(p, S.th{c}, S.sev(c), C), S.th{c}, A, 1, struct('F_SUB', F_SUB));
end
verifyTrue(tc, all(unit > 0));
fr = zeros(2, nC, 5);                                   % frames per cell and split, over the Eb/N0 points
for k = 1:2
    [geo, ref] = pool_layout(S.kind, S.grp, S.sev, C.nominal, [8 6 12 NG4(k) 60], [0 0 0 0 24], NHOVER, iSpd);
    for c = 1:nC
        for sp = 1:5
            j = geo{c}{sp}; if S.kind(c) == 0, j = [j, ref{sp}]; end %#ok<AGROW>
            f = F_SUB * ones(size(j)); f(ismember(j, ref{sp})) = C.event_run;
            fr(k, c, sp) = nS * sum(f);
        end
    end
end
verifyEqual(tc, fr(2, :, [1 2 3 5]), fr(1, :, [1 2 3 5]));
verifyGreaterThan(tc, sum(fr(2, :, 4)), sum(fr(1, :, 4)));
w = sum(fr, 3) * unit';                                 % work [s] with 36 and with 48 geometries
share = (w(2) - w(1)) / w(1);
fprintf('\nedge161_n 48: +%.2f%% of C1p work, %.1f h of 90 h and %.1f h of 105 h\n', 100 * share, 0.9 * 100 * share, 1.05 * 100 * share);
verifyGreaterThan(tc, share, 0);
verifyLessThanOrEqual(tc, 105 * share, 3);
end

%% ---------- the scripts' wiring ----------
function test_wiring_build_policy_pools(tc)
% Without edge161_n nothing of build_policy_pools.m changes: the added lines sit between two lines
% the parent commit (f6f6e03) holds side by side, and NGEO(4) is the parent's 36.
check_inserts(tc, 'code/decision/build_policy_pools.m', { ...
    {'NGEO   = [8 6 12 36 60];'}, {'SPO = speed_options();', 'NGEO(4) = SPO.edge161_n;'}, {'NHOVER = 24;'}; ...
    {'BLOCK(3:5) = [18 18 19];'}, {'if SPO.edge161_n > 36, NGEO(4) = NGEO(4) + 1; end'}, {'end', 'FRX = fec_rx_config();'}});
end

function test_wiring_evaluate_policies(tc)
% Without the switches evaluate_policies.m runs the parent's lines alone: every added block sits
% between two lines the parent holds side by side and is guarded by a switch.
check_inserts(tc, 'code/decision/evaluate_policies.m', { ...
    {'if FRESH, F6 = fresh_checks('}, {'SPO = speed_options(cfg6);'}, {'K = link_env(''tables'', PP);'}; ...
    {'false, false, NE, T, RandStream(''mt19937ar'', ''Seed'', 2028))}, ''split'', TEST2);', 'end'}, ...
    {'spec2 = {};', 'if ~strcmp(SPO.union, ''off'')', 'if numel(PP.runs) < TEST2 ||', 'error(''evaluate_policies:single2''', 'end', ...
     'spec2 = policy_episodes(single_cells, nS, G(single_cells, TEST2), REPS, false, false, NE, T, RandStream(''mt19937ar'', ''Seed'', 2075));', 'end'}, ...
    {'iThreat = 1:3;'}; ...
    {'numel(POL), toc(t0)/60);', 'end'}, ...
    {'RS2 = [];', 'if ~isempty(spec2)', '[kind, ag, opt] = policy_setup(POL{iDQN}, Q, sel, fixed_best, fixed_mmse, tab, K.na);', ...
     'RS2 = policy_run_set(kind, PP, K, spec2, TEST2, ag, opt, 50000);', 'fprintf(''  set %-9s %5d episodes x 1 policy', 'end'}, ...
    {'foll_cells = single_cells(K.followable(single_cells));'}; ...
    {'''[%.1f, %.1f] (95%% bootstrap over flight geometries)''], 100 * SPR(1), 100 * SPR(2), 100 * SPR(3));'}, ...
    {'SU = [];', 'if SPO.inference || ~strcmp(SPO.union, ''off'')', 'cg = [];', ...
     '[SU, spd_lines] = speed_reading(RES{1, iDQN}, mrec, RS2, cg, bins_v, SPR, SPO);', 'rep = [rep, spd_lines];', 'end'}, ...
    {'PS = []; PD = [];'}; ...
    {'rep{end+1} = sprintf(''%-18s%s'', sprintf(''%s (%d)'', band_txt(PP.speed_out(2, :)), sum(ms & hi))'}, ...
    {'if SPO.inference', 'rep = [rep, {''''}, speed_edge_lines(RES{iS, iDQN}, ms, lo, hi, strcmp(PP.scen(Rs.scn), ''airframe_shadowing''))];', 'end'}, ...
    {'end', 'iD2 = find(strcmp({sets.name}, ''delay2''));'}; ...
    {'KP.far_geoms_fresh = F6.CT.n_geom;', 'end'}, {'if ~isempty(SU), KP.speed_union = SU; end'}, ...
    {'save(''results/policy_evaluation.mat'', ''RES'''}; ...
    {'if FRESH, save(''results/policy_evaluation.mat'', ''RWf'', ''-append''); end'}, ...
    {'if ~isempty(RS2), save(''results/policy_evaluation.mat'', ''RS2'', ''-append''); end'}, ...
    {'key = unique({''none'''}});
% single2 is flown after the registered sets and before the spread it is read beside; its episode
% spec is the single set's (REPS, no follower, no unknown threat) on the second test split's flights
src = fileread(which('evaluate_policies'));
i = [strfind(src, 'spec2 = policy_episodes('), strfind(src, 'RES{si, pk} = policy_run_set('), ...
    strfind(src, 'RS2 = policy_run_set('), strfind(src, 'SPR = spread_boot('), strfind(src, '[SU, spd_lines] = speed_reading(')];
verifyNumElements(tc, i, 5);
verifyTrue(tc, issorted(i, 'strictascending'));
end

function test_wiring_train_dqn(tc)
% The switches are read before the training, so a wrong profile.json field stops at the start;
% the band table is read after the selection and the report, on the raw agent, and nothing is
% saved with the agent from it.
check_inserts(tc, 'code/decision/train_dqn.m', { ...
    {'cfgc = [];'}, {'SPO = speed_options(cfgc);'}, {'RC = struct(''dir'', run_cache('}; ...
    {'if ~gate, warning(''train_dqn:gate'''}, ...
    {'if SPO.band_table', 'PPb = decision_settings(', 'Vb = dqn_eval_batches(sel_kind, PPb, K, val_spec, agent, struct(), 5000, SPLIT_VAL);', ...
     'sb = cell2mat(', 'cb = cell2mat(', 'ih = sub2ind(', 'hb = ~(K.restored(ih)', 'vb = PP.speed{SPLIT_VAL}', 'kb = Vb.recoverable & Vb.threat;', ...
     '[bt_lines, SB] = speed_band_table(', 'linspace(PP.speed_range(1), PP.speed_range(2), 5));', 'bt_lines{end+1} = sprintf(', ...
     'ternary(abs(dqn_recovered(Vb) - B.rec)', 'fid = fopen(''results/dqn_training.txt'', ''a'');', 'fprintf(''\n%s\n'', bt_lines{:});', ...
     'save(''results/dqn_speed_bands.mat'', ''SB'');', 'end'}, ...
    {'ES = [runs.esc];'}});
td = fileread(which('train_dqn'));
verifyNumElements(tc, strfind(td, 'SPO = speed_options(cfgc);'), 1);
verifyLessThan(tc, strfind(td, 'SPO = speed_options(cfgc);'), min(strfind(td, 'RC.id = run_cache(''key'''))));   % before the first run
i = strfind(td, 'if SPO.band_table');
verifyNumElements(tc, i, 1);
verifyLessThan(tc, i, min(strfind(td, 'agent = dqn_dense(agent);')));           % the raw agent, before the deployment form
verifyLessThan(tc, i, min(strfind(td, 'save(''data/trained_dqn.mat''')));          % nothing saved with the agent
blk = td(i:i + strfind(td(i:end), 'save(''results/dqn_speed_bands.mat'', ''SB'');') - 1);
verifyEmpty(tc, strfind(blk, 'trained_dqn'));
end

function test_wiring_measure_all_kpis(tc)
% The union reading enters the KPI 7 lines only when the file holds it, and decides the speed
% status only in the verdict mode.
check_inserts(tc, 'code/evaluation/measure_all_kpis.m', { ...
    {'''geometries; target <= 10)''], P.KP.speed_spread);', 'end'}, ...
    {'if isfield(P.KP, ''speed_union'') && ~isempty(P.KP.speed_union)', 'det = [det, P.KP.speed_union.kpi_lines(:)''];', 'end'}, ...
    {'if isfield(P.KP, ''per_speed_out'')'}; ...
    {'st7 = status(lat_ok && max(pv) - min(pv) <= 10, stale);'}, ...
    {'if isfield(P.KP, ''speed_union'') && ~isempty(P.KP.speed_union) && strcmp(P.KP.speed_union.mode, ''verdict'')', ...
     'st7 = status(lat_ok && P.KP.speed_union.met, stale);', 'end'}, ...
    {'if (lat_pending || sl.stale) && ~stale'}});
end

function test_resampling_seeds_are_their_own(tc)
% The speed readings' streams: bootstrap and permutation of the test and the union reading, and
% the edge lines' bootstrap, each their own and none one of evaluate_policies.m's boot_cluster seeds.
s = fileread(which('speed_reading'));
v = str2double(regexp(regexprep(regexp(s, 'SEEDS = struct\([^\n]*', 'match', 'once'), '[^\d ]', ''), '\s+', 'split'));
v = v(~isnan(v));
verifyEqual(tc, v, [81 82 83 84]);
e = fileread(which('speed_edge_lines'));
w = cellfun(@(x) str2double(x{1}), regexp(e, ', (9\d)\}?[;,]', 'tokens'));
verifyEqual(tc, sort(w), [91 92 93]);
ep = fileread(which('evaluate_policies'));
other = cellfun(@(x) str2double(x{1}), regexp(ep, 'boot_cluster\([^\n]*?, (\d+)\);', 'tokens'));
verifyEmpty(tc, intersect(other, [v w]));
end

%% ---------- helpers ----------
function write_json(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function p = base_params(nrx)
% The default params of this checkout (init_params.m) with nrx receive antennas as profile.json
% states them (profile 3: 4); without the argument the test folder holds no profile.json.
if nargin > 0
    f = fullfile(pwd, 'profile.json');
    write_json(f, sprintf('{"n_rx": %d}', nrx));
    cl = onCleanup(@() delete(f)); %#ok<NASGU>
end
evalc('init_params');
p = load('params.mat').params;
end

function ok = same(a, b)
% Equal up to 1e-9, NaN at the same places.
ok = isequal(size(a), size(b)) && isequal(isnan(a), isnan(b)) && all(abs(a(~isnan(a)) - b(~isnan(b))) < 1e-9);
end

function [x, band, cl, st, pg] = flat_flights(rs, ns, nper)
% ns strata of nper flights each: a band at random, unrelated to the rates, 3-6 episodes per
% flight with a continuous rate in [0, 1] from the flight's own level.
nf = ns * nper;
st_f = repelem(1:ns, nper);
band_f = randi(rs, 4, 1, nf);
ne = randi(rs, [3 6], 1, nf);
lev = rand(rs, 1, nf);
cl = repelem(1:nf, ne); st = repelem(st_f, ne); band = repelem(band_f, ne);
x = min(1, max(0, repelem(lev, ne) + 0.2 * (rand(rs, 1, numel(cl)) - 0.5)));
pg = zeros(1, numel(cl));
end

function [x, band, cl, st, pg] = banded_flights(rs, rates, ns, nper)
% ns strata of nper flights in each of numel(rates) bands, 4 episodes of 0/1 per flight with the
% band's rate (and a flight level around it); the flights of the last two bands in the middle
% stratum belong to the shadowing group 1.
nb = numel(rates);
cl = []; st = []; band = []; x = []; pg = []; id = 0;
for b = 1:nb
    for u = 1:ns
        for f = 1:nper
            id = id + 1;
            lev = min(1, max(0, rates(b) + 0.15 * (rand(rs, 1) - 0.5)));
            cl = [cl, id * ones(1, 4)]; st = [st, u * ones(1, 4)]; band = [band, b * ones(1, 4)]; %#ok<AGROW>
            x = [x, double(rand(rs, 1, 4) < lev)]; %#ok<AGROW>
            pg = [pg, double(b >= 3 && u == 2) * ones(1, 4)]; %#ok<AGROW>
        end
    end
end
end

function [q, lo, hi, p, pm] = reference_inference(x, band, cl, st, pg, nb, B, seed)
% The same inference with loops over resamples on streams of their own.
[ucl, ia] = unique(cl); nU = numel(ucl);
cband = band(ia); cst = st(ia); cpg = pg(ia);
Sx = zeros(nU, nb); Sn = zeros(nU, nb);
for k = 1:nU
    e = cl == ucl(k);
    Sx(k, cband(k)) = sum(x(e)); Sn(k, cband(k)) = sum(e);
end
m = sum(Sx, 1) ./ sum(Sn, 1);
rs = RandStream('mt19937ar', 'Seed', seed(1));
Mb = zeros(B, nb);
for r = 1:B
    idx = [];
    for u = unique(cst)
        mem = find(cst == u);
        pick = mem(randi(rs, numel(mem), numel(mem), 1));
        idx = [idx; pick(:)]; %#ok<AGROW>
    end
    Mb(r, :) = sum(Sx(idx, :), 1) ./ sum(Sn(idx, :), 1);
end
d = sort(max(Mb - m, [], 2) - min(Mb - m, [], 2));
q = d(ceil(0.95 * B));
lo = zeros(1, nb); hi = zeros(1, nb);
for b = 1:nb
    v = sort(Mb(:, b)); lo(b) = v(round(0.025 * B)); hi(b) = v(round(0.975 * B));
end
rp = RandStream('mt19937ar', 'Seed', seed(2));
obs = max(m) - min(m);
key = cst * 1000 + cpg; stat = zeros(B, 1);
for r = 1:B
    pb = cband;
    for u = unique(key)
        mem = find(key == u);
        pb(mem) = cband(mem(randperm(rp, numel(mem))));
    end
    mp = zeros(1, nb);
    for b = 1:nb, mp(b) = sum(sum(Sx(pb == b, :), 2)) / sum(sum(Sn(pb == b, :), 2)); end
    stat(r) = max(mp) - min(mp);
end
p = (1 + sum(stat >= obs - 1e-12)) / (B + 1);
pm = mean(stat);
end

function R = make_run(split, nf, klow, hi, lo, shd)
% A policy_run_set.m-like result: 4 speed bands, nf flights each over 3 Eb/N0 strata, one
% pattern of recovered per flight (lo for the first klow(b) flights of band b, hi for the
% rest). shd: the even flights of bands 3 and 4 are flown by cell 2, a shadowing cell.
cen = [45 78 111 144];
rec = []; spd = []; geom = []; s = []; scn = []; sp = [];
for b = 1:4
    for f = 1:nf
        st = mod(f - 1, 3) + 1; r = (b - 1) * nf + f;
        pat = hi; if f <= klow(b), pat = lo; end
        c = 1 + (shd && b >= 3 && mod(f, 2) == 0);
        n = numel(pat);
        rec = [rec, pat]; spd = [spd, cen(b) * ones(1, n)]; geom = [geom, (1000 * st + r) * ones(1, n)]; %#ok<AGROW>
        s = [s, st * ones(1, n)]; scn = [scn, c * ones(1, n)]; sp = [sp, split * ones(1, n)]; %#ok<AGROW>
    end
end
n = numel(rec);
R = struct('recovered', rec, 'recoverable', true(1, n), 'threat', true(1, n), 'speed', spd, 'split', sp, 'geom', geom, ...
    's', s, 'scn', scn);
end

function SPR = registered_spread(R, edges)
% The registered spread of the set as evaluate_policies.m computes it.
m = R.recoverable & R.threat; nb = numel(edges) - 1; vb = zeros(size(R.speed));
for bi = 1:nb
    vb(m & R.speed >= edges(bi) & R.speed < edges(bi + 1) + (bi == nb)) = bi;
end
SPR = spread_boot(double(R.recovered), vb, R.geom, nb, 2000, 80);
end

function S = pool_cells(p, C)
% The pool cells of build_policy_pools.m: threat, severity index, kind (0 the clean link, 1 a single
% threat, 2 a combined one), airframe-shadowing level and group.
SINGLES = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
    'antenna_fault', 'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
scen = [SINGLES, C.combos];
th = {}; sev = [];
for i = 1:numel(scen)
    t = scen{i};
    if strcmp(t, 'none'), v = C.nominal;
    elseif contains(t, '+'), v = C.combo_sev;
    else, v = 1:numel(C.sev_names);
    end
    th = [th, repmat({t}, 1, numel(v))]; sev = [sev, v]; %#ok<AGROW>
end
lv = nan(1, numel(th));
for c = find(contains(th, 'airframe_shadowing')), lv(c) = threat_params(p, th{c}, sev(c), C).shadow_db; end
kind = 1 + contains(th, '+'); kind(strcmp(th, 'none')) = 0;
S = struct('th', {th}, 'sev', sev, 'kind', kind, 'level', lv, 'grp', shadow_groups(lv, p));
end

function G = pool_lists(p, NG4)
% The shared and combined geometries of every Eb/N0 and split as build_policy_pools.m draws them
% with NGEO(4) = NG4 (the shadowing groups' own flights are selected apart).
NGEO = [8 6 12 NG4 60]; NCOMB = [0 0 0 0 24]; NHOVER = 24; BLOCK = [1 5 14 16 17];
LHS = [false false true false true]; LHS_SEED = 7100000; VOUT = [0 0; 161 161];
vrange = [p.speed_kmh_min p.speed_kmh_max];
nG = NGEO + NCOMB;
r0 = arrayfun(@(sp) sum(nG(1:sp-1) .* (BLOCK(1:sp-1) == BLOCK(sp))), 1:5);
G = cell(numel(p.EbNo_dB), 5);
for s = 1:numel(p.EbNo_dB)
    for sp = 1:5
        r = r0(sp) + (1:NGEO(sp));
        lhs = []; if LHS(sp), lhs = LHS_SEED + 100 * s + sp; end
        if sp == 4
            g = pool_geometries(s, BLOCK(sp), r, VOUT(1 + ((1:NGEO(sp))' > NHOVER), :), p);
        else
            g = pool_geometries(s, BLOCK(sp), r, vrange, p, lhs);
        end
        if NCOMB(sp) > 0
            if LHS(sp), lhs = lhs + 10; end
            gc = pool_geometries(s, BLOCK(sp), r0(sp) + NGEO(sp) + (1:NCOMB(sp)), vrange, p, lhs);
            for f = fieldnames(gc)', g.(f{1}) = [g.(f{1}), gc.(f{1})]; end
        end
        G{s, sp} = g;
    end
end
end

function check_inserts(tc, rel, blk)
% Each row of blk is {before, added, after}, lists of code-line beginnings: the parent commit
% (f6f6e03) holds the lines before and after side by side, and the file holds the added lines
% between them, once. Anything else the parent holds is untouched by the block.
d = parent_copy(tc, rel, 'f6f6e03'); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
[~, nm, ext] = fileparts(rel);
old = code_lines(fileread(fullfile(d, [nm ext])));
new = code_lines(fileread(fullfile(tc.TestData.root, strrep(rel, '/', filesep))));
for i = 1:size(blk, 1)
    pre = blk{i, 1}; add = blk{i, 2}; post = blk{i, 3};
    where = sprintf('%s after "%s"', rel, pre{end});
    verifyNumElements(tc, find_seq(old, [pre, post]), 1, ['the parent holds the anchors side by side, ' where]);
    verifyNumElements(tc, find_seq(new, [pre, add, post]), 1, ['the added lines sit between them, ' where]);
end
end

function at = find_seq(c, seq)
% Positions where consecutive code lines begin with seq{1}, seq{2}, ...
n = numel(seq); at = [];
for k = 1:numel(c) - n + 1
    if all(cellfun(@(l, s) startsWith(l, s), c(k:k + n - 1), seq)), at(end+1) = k; end %#ok<AGROW>
end
end

function c = code_lines(txt)
% The code lines of a source: trimmed, without blank and comment-only lines.
c = strtrim(regexp(txt, '\r?\n', 'split'));
c = c(~cellfun(@isempty, c));
c = c(~startsWith(c, '%'));
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
