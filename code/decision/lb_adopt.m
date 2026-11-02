function [on, R, lines] = lb_adopt(X, bound, tests_ok)
%LB_ADOPT  The adoption rule of the link-budget completion (lb_complete.m), judged on C2's
%   selected agent alone: one binary comparison, completion off against on, on the validation
%   split, nothing tuned (train_dqn.m).
%   X.sets   per validation set (single, follower, combined, unknown; at most 4): name, x_off and
%            x_on (the recovered flags, 0/1, of its recoverable threat episodes without and with the
%            completion, paired), cl (the flight of each episode, the bootstrap cluster) and fam
%            (the episodes whose threat holds a path loss: a single path_loss, a combination with
%            it, the unknown set's path_loss)
%   X.clean  sw_off, sw_on: the changes per clean validation flight without and with it
%   bound    KPI 6's false-alarm bound (0.05); tests_ok  the static and parity checks passed
%            (lb_selfcheck.m)
%   Adopted only if all hold:
%     (a) on every set, the paired difference of recovered is at least -0.5 point and its
%         one-sided 95% lower bound (the 5th percentile of 2000 resamples of whole flights) at
%         least -1.0 point;
%     (b) on the path-loss family pooled, the difference is above 0 and so is its lower bound;
%     (c) the clean flights' false changes with it stay within the one-sided 95%
%         Clopper-Pearson bound and at most 1 point above those without;
%     (d) tests_ok.
%   A reading that is absent (an empty set, no clean flights) fails its condition.
%   on: adopted; R: the readings and each condition's verdict; lines: their report lines.
S = lb_seeds(); B = 2000; tol = 1e-9;
nS = numel(X.sets);
assert(nS <= numel(S.boot) - 1, 'lb_adopt: at most %d sets', numel(S.boot) - 1);
RS = struct('set', {}, 'n', {}, 'delta', {}, 'lo', {}, 'ok', {});
df = []; cf = [];
for k = 1:nS
    s = X.sets(k); d = s.x_on(:) - s.x_off(:); f = logical(s.fam(:));
    [m, lo] = paired(d, s.cl, B, S.boot(k));
    RS(end+1) = struct('set', s.name, 'n', numel(d), 'delta', m, 'lo', lo, ...
        'ok', m >= -0.005 - tol && lo >= -0.01 - tol); %#ok<AGROW>
    cl = s.cl(:);
    df = [df; d(f)]; cf = [cf; cl(f)]; %#ok<AGROW>
end
[m, lo] = paired(df, cf, B, S.boot(end));
RF = struct('n', numel(df), 'delta', m, 'lo', lo, 'ok', m > 0 && lo > 0);
n = numel(X.clean.sw_on);
RC = struct('n', n, 'k_off', sum(X.clean.sw_off > 0), 'k_on', sum(X.clean.sw_on > 0), 'upper', NaN, 'delta', NaN, 'ok', false);
if n > 0 && numel(X.clean.sw_off) == n
    RC.upper = cp_upper(RC.k_on, n); RC.delta = (RC.k_on - RC.k_off) / n;
    RC.ok = RC.upper <= bound + tol && RC.delta <= 0.01 + tol;
end
R = struct('sets', RS, 'fam', RF, 'clean', RC, 'tests', logical(tests_ok), 'a', nS > 0 && all([RS.ok]), 'b', RF.ok, ...
    'c', RC.ok, 'd', logical(tests_ok));
on = R.a && R.b && R.c && R.d;
lines = {sprintf(['Link-budget completion on the selected agent, off against on (validation, used once more for this ' ...
    'one comparison; paired, recovered among the recoverable; lower bounds: one-sided 95%%, %d resamples of whole ' ...
    'flights):'], B)};
for k = 1:nS
    lines{end+1} = sprintf('  (a) %-9s %+6.2f points, lower bound %+6.2f (%d episodes): %s', RS(k).set, 100 * RS(k).delta, ...
        100 * RS(k).lo, RS(k).n, verdict(RS(k).ok)); %#ok<AGROW>
end
lines{end+1} = sprintf('  (b) path-loss family %+6.2f points, lower bound %+6.2f (%d episodes): %s', 100 * RF.delta, 100 * RF.lo, ...
    RF.n, verdict(RF.ok));
lines{end+1} = sprintf(['  (c) clean flights, changes: %d/%d without, %d/%d with (upper bound %.2f%% against %.0f%%, %+.2f ' ...
    'points): %s'], RC.k_off, n, RC.k_on, n, 100 * RC.upper, 100 * bound, 100 * RC.delta, verdict(RC.ok));
lines{end+1} = sprintf('  (d) static and parity checks: %s', verdict(R.d));
lines{end+1} = sprintf('  link-budget completion %s', ternary(on, 'ADOPTED (on)', 'not adopted (off, reported as a column)'));
end

function [m, lo] = paired(d, cl, B, seed)
% Mean of the paired differences d and the 5th percentile of its bootstrap that resamples whole
% clusters (boot_cluster.m's scheme); NaN where there are none, or a single cluster.
m = NaN; lo = NaN;
d = d(:); cl = cl(:); k = isfinite(d); d = d(k); cl = cl(k);
if isempty(d), return; end
[~, ~, j] = unique(cl);
Sn = accumarray(j, d); Sd = accumarray(j, ones(size(d)));
m = sum(Sn) / sum(Sd);
nU = numel(Sn);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, nU, nU, B);
q = sort(sum(Sn(idx), 1) ./ sum(Sd(idx), 1));
lo = q(max(1, round(0.05 * B)));
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = verdict(ok)
if ok, t = 'PASS'; else, t = 'FAIL'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
