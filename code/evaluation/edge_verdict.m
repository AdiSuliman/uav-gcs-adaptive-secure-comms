function V = edge_verdict(num, den, cl, target, sense, binary, B)
%EDGE_VERDICT  Value, 95% interval and commitment verdict of one layer at one point
%   (edge_map.m).
%   V = edge_verdict(num, den, cl, target, sense, binary)
%   V = edge_verdict(..., B)
%   num, den  per-unit numerator and denominator (an episode: recovered / 1; a flight:
%             recoverable / 1, or its correct / active frames); value = sum(num) / sum(den)
%   cl        flight of each unit: the bootstrap resamples whole flights
%   target    the layer's target; sense 'ge' (the value must reach it: DET, SURV, REC)
%             or 'le' (must stay at or below it: FA, LINK)
%   binary    true for a per-flight binary outcome: a flight succeeds only if all its
%             units do (num = den for 'ge', num = 0 for 'le')
%   B         bootstrap resamples (default 4000, fixed seed)
%   Interval, two-sided 95%: percentile bootstrap over flights (boot_cluster.m). A binary
%   outcome also gets the exact Clopper-Pearson interval of its k successful flights in
%   n: with one unit per flight the two describe the same share and the exact one is used,
%   otherwise their hull. A rate (frames) at its extreme has no bootstrap spread: for
%   'ge' the lower bound is at most the Clopper-Pearson bound of n successful flights in
%   n, for 'le' the upper bound at least that of no event in all sum(den) units (a
%   packet loss is a share of frames, not of flights).
%   Verdict: COMMITTED (1) when the interval lies on the target's side and n >= N_MIN;
%   NOT COMMITTED (-1) when it lies entirely on the other side; UNDETERMINED (0)
%   otherwise. N_MIN = 36, the smallest n whose all-success lower bound reaches 0.90
%   (0.9026; 35 gives 0.89997).
%   V: value, lo, hi, n (flights), k (successful flights, binary), verdict, n_min
N_MIN = 36;
if nargin < 7 || isempty(B), B = 4000; end
V = struct('value', NaN, 'lo', NaN, 'hi', NaN, 'n', 0, 'k', NaN, 'verdict', 0, 'n_min', N_MIN);
ok = isfinite(num) & isfinite(den) & den > 0;
num = num(ok); den = den(ok); cl = cl(ok);
if isempty(num), return; end
[V.value, lo, hi] = boot_cluster(num, den, cl, B, 74);
[~, ~, j] = unique(cl(:));
Sn = accumarray(j, num(:)); Sd = accumarray(j, den(:));
n = numel(Sn); V.n = n;
ge = strcmp(sense, 'ge');
if binary
    if ge, k = sum(Sn == Sd); else, k = sum(Sn == 0); end
    V.k = k;
    e = k; if ~ge, e = n - k; end                  % flights at the counted outcome
    [cl_, ch_] = cp_interval(e, n);
    if numel(num) == n && all(den == 1)
        lo = cl_; hi = ch_;
    else
        lo = min(lo, cl_); hi = max(hi, ch_);
    end
else
    if isnan(lo), lo = 0; hi = 1; end              % a single flight: no spread to resample
    if ge
        lo = min(lo, cp_interval(n, n));
    else
        [~, ch_] = cp_interval(0, sum(den)); hi = max(hi, ch_);
    end
end
V.lo = lo; V.hi = hi;
if ge
    if lo >= target && n >= N_MIN, V.verdict = 1; elseif hi < target, V.verdict = -1; end
else
    if hi <= target && n >= N_MIN, V.verdict = 1; elseif lo > target, V.verdict = -1; end
end
end

function [lo, hi] = cp_interval(k, n)
% Two-sided 95% Clopper-Pearson interval of k in n.
if k <= 0, lo = 0; else, lo = betaincinv(0.025, k, n - k + 1); end
if k >= n, hi = 1; else, hi = betaincinv(0.975, k + 1, n - k); end
end
