function [ADM, L] = aprime_admit(A, bound)
%APRIME_ADMIT  Which penalties of the no-threat form are admissible (D107 point 5,
%   d107_after_v0.md section 3.5), read on the validation episodes only.
%   [ADM, L] = aprime_admit(A, bound)
%   A      train_dqn.m section 4b's record (data/aprime_agents.mat): A.episodes (threat, harmed,
%          s, r of every validation episode) and A.runs (pen, gamma, seed; nothreat and plain,
%          the no-threat run and its paired grid run: the per-episode recovered, held,
%          recoverable and threat, and noesc, the summary without the escalation with fa_w and
%          n_w). One discount factor.
%   bound  the false-alarm bound of KPI 6 (0.05)
%   A penalty is admissible only if all of these hold; its runs are the seeds' no-threat runs,
%   deployed without the escalation:
%   (a) for every run and for the seed mean, the one-sided 95% Clopper-Pearson upper bound of the
%       false-alarm episodes on the clean validation flights is at most bound
%   (b) harmed S1 recovered (the recoverable episodes of antenna_fault and airframe_shadowing in
%       a geometry that no response does not restore), no-threat minus grid, per-episode seed means,
%       paired: the cluster bootstrap over (geometry, Eb/N0) of the mean difference, 10000
%       resamples, Holm across the penalties (holm_lower.m); its lower bound above 0
%   (b') none of antenna_fault's harmed geometries has a negative seed-mean paired difference
%   (c) seed means against the paired grid runs: no threat's held recovery over its recoverable
%       episodes falls by more than 1 point, pooled held by more than 0.5 point, held of the
%       covered S1 episodes by more than 3 points
%   ADM(k): pen, runs (their indices in A.runs), fa_k, fa_n, fa_up, fa_up_mean, a, gain, n_gain,
%   n_clusters, p, level, lb, b, geom, geom_diff, bprime, thr, thr_diff, pooled_diff, cov_diff,
%   c, admissible. L: the lines for results/dqn_training.txt.
B = 10000; SEED = 107;
S1 = {'antenna_fault', 'airframe_shadowing'};
R = A.runs; E = A.episodes;
ADM = struct([]);
L = {};
if isempty(R), return; end
if numel(unique([R.gamma])) ~= 1
    error('aprime_admit:gamma', 'aprime_admit: the runs of one discount factor only');
end
thr = E.threat(:)'; harm = logical(E.harmed(:)'); cl = 1000 * double(E.s(:)') + double(E.r(:)');
pens = unique([R.pen]); np = numel(pens);
Q = cell(1, np); P = ones(1, np);
for k = 1:np
    ix = find([R.pen] == pens(k)); Rk = R(ix);
    rec = all(per_run(Rk, 'nothreat', 'recoverable') > 0 & per_run(Rk, 'plain', 'recoverable') > 0, 2)';
    isth = all(per_run(Rk, 'nothreat', 'threat') > 0 & per_run(Rk, 'plain', 'threat') > 0, 2)';
    mT = rec & isth;                                              % the recoverable threat episodes
    Rn = per_run(Rk, 'nothreat', 'recovered'); Rp = per_run(Rk, 'plain', 'recovered');
    Hn = mean(per_run(Rk, 'nothreat', 'held'), 2)'; Hp = mean(per_run(Rk, 'plain', 'held'), 2)';
    dm = mean(Rn, 2)' - mean(Rp, 2)';                             % seed-mean paired difference per episode
    X = struct('pen', pens(k), 'runs', ix);
    % (a)
    fk = arrayfun(@(r) round(r.nothreat.noesc.fa_w * r.nothreat.noesc.n_w), Rk);
    fn = arrayfun(@(r) r.nothreat.noesc.n_w, Rk);
    X.fa_k = fk; X.fa_n = fn(1);
    X.fa_up = arrayfun(@cp_upper, fk, fn); X.fa_up_mean = cp_upper(round(mean(fk)), fn(1));
    X.a = all(fn == fn(1)) && all(X.fa_up <= bound) && X.fa_up_mean <= bound;
    % (b), the distribution here; Holm across the penalties below
    mb = mT & harm & ismember(thr, S1);
    [X.gain, Q{k}] = paired_stats('dist', dm(mb), cl(mb), B, SEED);
    X.n_gain = sum(mb); X.n_clusters = numel(unique(cl(mb)));
    if ~isempty(Q{k}), P(k) = (1 + sum(Q{k} <= 0)) / (B + 1); end
    X.p = P(k);
    % (b')
    ma = mb & strcmp(thr, 'antenna_fault');
    X.geom = []; X.geom_diff = [];
    if any(ma)
        [g, ~, gi] = unique(E.r(ma));
        X.geom = g(:)'; X.geom_diff = (accumarray(gi(:), dm(ma)') ./ accumarray(gi(:), 1))';
    end
    X.bprime = ~isempty(X.geom_diff) && all(X.geom_diff >= -1e-12);
    % (c)
    X.thr = unique(thr(mT), 'stable');
    X.thr_diff = cellfun(@(t) mean(Hn(mT & strcmp(thr, t))) - mean(Hp(mT & strcmp(thr, t))), X.thr);
    X.pooled_diff = mean(Hn(mT)) - mean(Hp(mT));
    mc = mT & ~harm & ismember(thr, S1);
    X.cov_diff = mean(Hn(mc)) - mean(Hp(mc));                     % NaN without covered S1 episodes: fails
    X.c = ~isempty(X.thr_diff) && all(X.thr_diff >= -0.01 - 1e-9) && X.pooled_diff >= -0.005 - 1e-9 ...
        && X.cov_diff >= -0.03 - 1e-9;
    X.level = NaN; X.lb = NaN; X.b = false; X.admissible = false;
    if k == 1, ADM = X; else, ADM(k) = X; end
end
[pass, level, lb] = holm_lower(P, Q);
for k = 1:np
    ADM(k).b = pass(k); ADM(k).level = level(k); ADM(k).lb = lb(k);
    ADM(k).admissible = ADM(k).a && ADM(k).b && ADM(k).bprime && ADM(k).c;
end
L{end+1} = sprintf(['Admissibility of the no-threat form (D107 point 5, validation only; a penalty is admissible only if (a), (b), ' ...
    '(b'') and (c) all hold): %d penalties, Holm across them'], np);
for k = 1:np
    X = ADM(k); wd = NaN; wn = '-';
    if ~isempty(X.thr_diff), [wd, w] = min(X.thr_diff); wn = X.thr{w}; end
    L{end+1} = sprintf('  penalty %d (%d seeds): %s', X.pen, numel(X.runs), ternary(X.admissible, 'ADMISSIBLE', 'not admissible')); %#ok<AGROW>
    L{end+1} = sprintf(['    (a) clean-flight false alarms, one-sided 95%% bound: runs %s, seed mean %.2f%% (limit %.0f%%): %s'], ...
        strjoin(arrayfun(@(u, kk) sprintf('%d/%d [%.2f%%]', kk, X.fa_n, 100 * u), X.fa_up, X.fa_k, 'UniformOutput', false), ', '), ...
        100 * X.fa_up_mean, 100 * bound, ternary(X.a, 'ok', 'FAILS')); %#ok<AGROW>
    L{end+1} = sprintf(['    (b) harmed S1 recovered, no-threat minus grid: %+.1f points over %d episodes in %d clusters, p %.4f, ' ...
        'lower bound at %.1f%% %+.2f points: %s'], 100 * X.gain, X.n_gain, X.n_clusters, X.p, 100 * X.level, 100 * X.lb, ...
        ternary(X.b, 'above 0', 'not above 0')); %#ok<AGROW>
    L{end+1} = sprintf('    (b'') antenna_fault, paired difference per harmed geometry (points): %s: %s', ...
        ternary(isempty(X.geom_diff), 'none', strjoin(arrayfun(@(g, d) sprintf('%d %+.1f', g, 100 * d), X.geom, X.geom_diff, ...
        'UniformOutput', false), ', ')), ternary(X.bprime, 'none negative', 'a geometry is negative')); %#ok<AGROW>
    L{end+1} = sprintf(['    (c) held against the grid runs: weakest change %s %+.2f (limit -1), pooled %+.2f (limit -0.5), ' ...
        'covered S1 %+.2f points (limit -3): %s'], wn, 100 * wd, 100 * X.pooled_diff, ...
        100 * X.cov_diff, ternary(X.c, 'ok', 'FAILS')); %#ok<AGROW>
end
end

function X = per_run(R, side, f)
% The per-episode reading f of side (nothreat, plain) of every run in R, one column per run.
c = arrayfun(@(r) double(r.(side).(f)(:)), R, 'UniformOutput', false);
X = [c{:}];
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
