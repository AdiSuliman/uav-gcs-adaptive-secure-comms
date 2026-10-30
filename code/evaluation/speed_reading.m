function [SU, lines] = speed_reading(R1, m1, R2, cellgrp, edges, SPR, O)
%SPEED_READING  KPI 7's speed part of the deployed policy: the inference lines beside the registered
%   spread and the reading on the union of the test and second-test single sets under a pinned
%   criterion. Lines for policy_evaluation.txt and the struct SU that evaluate_policies.m saves as
%   KP.speed_union and measure_all_kpis.m reads.
%   [SU, lines] = speed_reading(R1, m1, R2, cellgrp, edges, SPR, O)
%   R1, m1   the deployed policy's results on the test single set (policy_run_set.m) and its
%            recoverable threat episodes
%   R2       the same on the second test split's single set, [] without it
%   cellgrp  the airframe-shadowing group of every pool cell (PP.shadow.cell_group), [] without
%   edges    the speed bands' edges [km/h] (evaluate_policies.m bins_v)
%   SPR      the registered spread of the test single set, [value lo hi] (spread_boot.m)
%   O        speed_options.m: O.inference prints the test single set's inference lines; O.union
%            'descriptive' or 'verdict' reads the union (R2 needed)
%   The estimand is the registered one: the largest minus the smallest band mean of the deployed
%   policy's recovered among the recoverable threat episodes. The union has 72 flights per Eb/N0
%   instead of 12 and removes the range bias of the spread (Tippett 1925); it changes the
%   reading, not the system.
%   Criterion (U: speed_inference.m, Hall & Miller 2010): MET (committed) iff U <= 10 points;
%   MET (not committed) iff the point <= 10 < U; NOT MET iff the point > 10. The test single set
%   alone under the registered rule (the point <= 10 is MET, with its spread_boot.m interval) is
%   printed beside it as the continuity line with profile 1, and the result line names both
%   verdicts. The union is the KPI 7 verdict only with O.union 'verdict'; 'descriptive' leaves
%   the verdict to the test-only line.
%   SU: mode ('lines', 'descriptive', 'verdict'), yes, target [points], test and union
%   (speed_inference.m structs, fractions), word_test, word_union, point_test, point_union,
%   U_union [points], met (the verdict line's), kpi_lines (what measure_all_kpis.m shows),
%   reproduced (the test single set's spread equals the registered one: a printed line and a
%   warning say so when it does not, the reading goes on)
TARGET = 0.10;                                          % KPI 7: spread <= 10 points
B = 9999;
SEEDS = struct('test', [81 82], 'union', [83 84]);      % bootstrap and permutation streams
nb = numel(edges) - 1;
[x1, b1, c1, s1, g1] = episode_vectors(R1, m1, edges, cellgrp);
T = speed_inference(x1, b1, c1, s1, g1, nb, B, SEEDS.test);
same = abs(T.point - SPR(1)) <= 1e-12;
met_t = T.point <= TARGET;
word_t = ternary(met_t, 'MET', 'NOT MET');
SU = struct('mode', ternary(strcmp(O.union, 'off'), 'lines', O.union), 'yes', O.yes, 'target', 100 * TARGET, 'test', T, ...
    'union', [], 'word_test', word_t, 'word_union', '', 'point_test', 100 * T.point, 'point_union', NaN, 'U_union', NaN, ...
    'met', met_t, 'kpi_lines', {{}}, 'reproduced', same);
lines = {};
if ~same
    warning('speed_reading:point', 'the spread of the test single set (%.6f) is not the registered one (%.6f)', T.point, SPR(1));
    lines = {'', sprintf(['  NOT REPRODUCED: the spread of the test single set read here (%.6f) differs from the registered one ' ...
        '(%.6f, spread_boot.m)'], T.point, SPR(1))};
end
if O.inference
    lines = [lines, {'', sprintf(['Speed inference, test single set (D116 item 5; descriptive, nothing is selected on it): deployed ' ...
        'policy, %d recoverable threat episodes of %d flights'], sum(T.n), T.nU)}, infer_lines(T, edges)];
    SU.kpi_lines = {sprintf(['speed inference on the test single set (descriptive): permutation test p = %.4f (noise alone gives ' ...
        '%.1f points), Hall & Miller upper bound U %.1f points'], T.p, 100 * T.perm_mean, 100 * T.U)};
end
if strcmp(O.union, 'off'), return; end
if isempty(R2), error('speed_reading:single2', 'kpi7_union %s: the second test split''s single set was not flown', O.union); end
m2 = R2.recoverable & R2.threat;
[x2, b2, c2, s2, g2] = episode_vectors(R2, m2, edges, cellgrp);
U = speed_inference([x1 x2], [b1 b2], [c1 c2], [s1 s2], [g1 g2], nb, B, SEEDS.union);
if U.point > TARGET, wu = 'NOT MET';
elseif U.U <= TARGET, wu = 'MET (committed)';
else, wu = 'MET (not committed)'; end
differ = (U.point <= TARGET) ~= met_t;
verdict = strcmp(O.union, 'verdict');
if verdict
    tag = sprintf('VERDICT LINE, approved by Adi on %s', O.yes);
else
    tag = 'DESCRIPTIVE ONLY, Adi''s approval of D117 point 1 is not recorded: the verdict stays the test-only line';
end
SU.union = U; SU.word_union = wu; SU.point_union = 100 * U.point; SU.U_union = 100 * U.U;
if verdict, SU.met = U.point <= TARGET; end
lines = [lines, {'', sprintf(['KPI 7 speed part on the union of the test and second-test single sets (D117 point 1; %s): deployed ' ...
    'policy, %d recoverable threat episodes of %d flights'], tag, sum(U.n), U.nU), ...
    ['  our KPI 7 (decision time and robustness), not the lecturer''s; this changes the reading, not the system, and is not ' ...
    'counted as a fix of the speed weak result']}, infer_lines(U, edges)];
lines{end+1} = sprintf(['  criterion (D117 point 1): MET (committed) iff U <= %g points; MET (not committed) iff the point <= %g < U; ' ...
    'NOT MET iff the point > %g -> %s'], 100 * TARGET, 100 * TARGET, 100 * TARGET, wu);
lines{end+1} = sprintf(['  continuity line with profile 1, the test single set alone under the registered rule (the point <= %g is ' ...
    'MET): spread %.1f points [%.1f, %.1f] (95%% bootstrap over flight geometries, spread_boot.m) -> %s'], 100 * TARGET, ...
    100 * SPR(1), 100 * SPR(2), 100 * SPR(3), word_t);
lines{end+1} = sprintf('  result, KPI 7 speed part: union %s (spread %.1f points, U %.1f); test single set alone %s (spread %.1f points)%s', ...
    wu, 100 * U.point, 100 * U.U, word_t, 100 * T.point, ternary(differ, '; THE TWO READINGS DIFFER', ''));
SU.kpi_lines = [SU.kpi_lines, {sprintf(['speed part on the union of the test and second-test single sets (D117 point 1, %s): spread ' ...
    '%.1f points, Hall & Miller upper bound U %.1f points -> %s; permutation test p = %.4f (noise alone gives %.1f points)'], ...
    ternary(verdict, ['VERDICT, approved by Adi on ' O.yes], 'DESCRIPTIVE'), 100 * U.point, 100 * U.U, wu, U.p, ...
    100 * U.perm_mean), sprintf(['speed part on the test single set alone, the registered rule: spread %.1f points [%.1f, %.1f] ' ...
    '-> %s%s'], 100 * SPR(1), 100 * SPR(2), 100 * SPR(3), word_t, ternary(differ, ' (THE TWO READINGS DIFFER)', ''))}];
end

function [x, band, cl, st, pg] = episode_vectors(R, m, edges, cellgrp)
% Rate, band, flight, Eb/N0 stratum and shadowing group of the episodes m. The flight is the
% geometry within its split, so the two splits' flights stay apart.
nb = numel(edges) - 1;
x = double(R.recovered(m)); v = R.speed(m);
band = zeros(1, sum(m));
for bi = 1:nb
    band(v >= edges(bi) & v < edges(bi + 1) + (bi == nb)) = bi;
end
cl = 10000 * R.split(m) + R.geom(m);
st = R.s(m);
pg = zeros(1, sum(m));
if ~isempty(cellgrp), pg = cellgrp(R.scn(m)); end
end

function L = infer_lines(S, edges)
% Per-band intervals, the permutation test and the Hall & Miller bound written out.
nb = numel(edges) - 1;
pb = arrayfun(@(b) sprintf('%.0f-%.0f km/h %.1f [%.1f, %.1f] (%d episodes, %d flights)', edges(b), edges(b + 1), ...
    100 * S.m(b), 100 * S.lo(b), 100 * S.hi(b), S.n(b), S.nf(b)), 1:nb, 'UniformOutput', false);
L = cell(1, 3);
L{1} = sprintf(['  recovered per band, %% [95%% cluster-bootstrap interval, flights resampled within Eb/N0 strata, %d resamples, ' ...
    'seed %d]: %s'], S.B, S.seed(1), strjoin(pb, ' | '));
L{2} = sprintf(['  spread over the bands %.1f points; permutation test of association (whole flights'' bands permuted within Eb/N0 ' ...
    'strata and within each airframe-shadowing group''s own flights, %d permutations, seed %d, statistic max - min): p = %.4f; ' ...
    'noise alone gives %.1f points on average'], 100 * S.point, S.B, S.seed(2), S.p, 100 * S.perm_mean);
L{3} = sprintf(['  conservative upper bound on the spread (Hall & Miller 2010, joint-centred cluster bootstrap, one-sided 95%%): ' ...
    'U = max over a ~= b of (m_a - m_b) + q = %.1f + %.1f = %.1f points; q is the 95%% quantile over %d replicates of max over ' ...
    'a ~= b of [(m*_a - m*_b) - (m_a - m_b)], m the band means and m* their replicates (seed %d)'], 100 * S.point, 100 * S.q, ...
    100 * S.U, S.B, S.seed(1));
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
