function [pass, level, lb] = holm_lower(p, Q)
%HOLM_LOWER  Holm's step-down over m one-sided lower bounds (D107 point 5, d107_after_v0.md
%   section 3.5 (b)).
%   [pass, level, lb] = holm_lower(p, Q)
%   p  the m p-values
%   Q  the m sorted bootstrap distributions of the statistic (a cell, paired_stats.m 'dist');
%      an empty one has no bound and fails
%   The tests run in the order of p (ties: the lower index first). The j-th is read at the
%   one-sided lower bound of level 1 - 0.05 / (m - j + 1), the order statistic
%   round(0.05 / (m - j + 1) * B) of Q, as paired_stats.m 'boot' reads its 5th percentile; for
%   two tests the smaller p at 97.5% and the other at 95%. A test passes when its lower bound is
%   above 0 and every test before it passed (Holm 1979).
%   pass, level, lb: one entry per test, in the order of p and Q.
m = numel(p);
pass = false(1, m); level = nan(1, m); lb = nan(1, m);
[~, ord] = sort(p(:)', 'ascend');
ok = true;
for j = 1:m
    k = ord(j); a = 0.05 / (m - j + 1);
    level(k) = 1 - a;
    q = Q{k};
    if ~isempty(q), lb(k) = q(max(1, round(a * numel(q)))); end
    ok = ok && lb(k) > 0;
    pass(k) = ok;
end
end
