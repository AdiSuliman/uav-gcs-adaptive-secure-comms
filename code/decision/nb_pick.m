function [best, why] = nb_pick(X, bound, rk)
%NB_PICK  The selection of the rule's noise-burst answer in C2 (train_dqn.m), over readings X
%   of candidates in cost order rk (1 the cheapest; burst_candidates.m). X: held and rec (KPI 4
%   held and recovered, pooled over the recoverable validation episodes), ret (mean return),
%   fa_w over n_w (false-alarm share of the clean validation flights; NaN: not measured),
%   nb_held over nb_n (held recovery of the recoverable episodes whose threat holds a noise
%   burst, the single threat and its combinations, severities pooled).
%   1. those whose one-sided 95% false-alarm bound is <= bound (none: the three with the
%      lowest bound), as rank_pick of train_dqn.m
%   2. within half a point of their best pooled held recovery: a misread class keeps its own
%   3. within one point of the highest nb_held; with fewer than 10 noise-burst episodes
%      (weakest_threat's minimum) this step is skipped
%   4. the highest pooled recovered, then the highest return, then the cheapest; the setting
%      in force has no preference
up = nan(1, numel(X));
for k = 1:numel(X)
    if ~isnan(X(k).fa_w), up(k) = cp_upper(round(X(k).fa_w * X(k).n_w), X(k).n_w); end
end
c = find(isnan(up) | up <= bound);
why = 'the noise-burst held recovery within the false-alarm bound and half a point of the pooled held';
if isempty(c)
    [~, o] = sort(up); c = o(1:min(3, numel(o)));
    why = 'none met the false-alarm bound: the three with the lowest bound';
end
c = near(c, [X(c).held], 0.005);
if min([X(c).nb_n]) >= 10
    c = near(c, [X(c).nb_held], 0.01);
else
    why = [why '; fewer than 10 noise-burst episodes: the pooled readings alone'];
end
c = near(c, [X(c).rec], 0);
c = near(c, [X(c).ret], 0);
[~, j] = min(rk(c)); best = c(j);
end

function c = near(c, v, tol)
% The candidates within tol of the highest reading (all of them when none is a number).
m = max(v);
if ~isnan(m), c = c(v >= m - tol); end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end
