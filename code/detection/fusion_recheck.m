function R = fusion_recheck(PK, fit, Z0, XB, yt, fold, C, lambda, N, classes, B, bin, low, pB, ST, log_only)
%FUSION_RECHECK  B2F's re-check of the candidate the pick names over the d91 design
%   (fusion_pick.m P.ext; select_fusion.m): its rule, out of fold on the fit set B2F uses,
%   against the d91 design B on the same folds and bootstrap (fusion_cand.m, fusion_adopt.m
%   'cand'); for a head, its single-row cost and the detector's within the KPI 7 budget, and the
%   projected cost of the stages that run the fusion every cycle (head_cost.m). It fails: B
%   deploys alone, recorded as the fallback (not a no-go of B).
%   PK the pick; fit, Z0 (window rows), XB (B's further columns), yt, fold, C, lambda, N,
%   classes as select_fusion.m has them; B its bootstrap over sub-runs; bin, low the Eb/N0 bins
%   and the rows at K <= 0 dB; pB B's out-of-fold probabilities on these folds; ST the stages
%   (head_cost.m); log_only (the smoke) the rule printed, the candidate deployed all the same
%   R  pick, adopted, fallback, thr, d (the paired comparison), ok, rules, timing, cost, det
%      (the detector's cost and its source), and for the deploy FM, cues and pv (the
%      candidate's out-of-fold probabilities of every row)
name = PK.ext.pick; K = max(fold);
st = ones(numel(yt), 1); if isfield(fit, 'set'), st = fit.set; end
D = fusion_cand('data', fit, Z0, XB, PK.cues, yt, fold, C, lambda, N, classes, '');
pc = fusion_cand('oof', D, name, 1:K, []);
[~, yb] = max(pB, [], 2); [~, yc] = max(pc, [], 2);
thr = fusion_cand('kpi1_thr', yt, yb, bin, C);
d = fusion_adopt('paired_cls', yt, yb, yc, bin >= thr, low, st, classes, B);
if contains(name, 'CFAR')
    a = [0 0 0];
    for k = 1:K, [n1, n2, m] = fusion_cand('exc', D, k, k); a = a + [n1 n2 m]; end
    d.exc = 100 * a(1:2) / max(a(3), 1);
end
M = []; t = []; cost = []; det = struct('median_ms', NaN, 'p95_ms', NaN, 'source', '');
if contains(name, 'LBH')
    M = fusion_cand('fit', D, name);
    Zv = [Z0, XB];
    if ~isempty(M.T), Zv = [Z0, fusion_cand('cfar', D, M.T), XB]; end
    det = det_cost();
    t = head_time(M.FM.head, pc, Zv, det);
end
[ok, rules] = fusion_adopt('cand', name, d, t);
if contains(name, 'LBH') && (ok || log_only)
    r = round(linspace(1, size(Zv, 1), 2000));
    cost = head_cost(M.FM, Zv(r, :), ST);
    ok = ok && cost.ok;
end
adopted = ok || log_only;
if adopted && isempty(M), M = fusion_cand('fit', D, name); end
f = fieldnames(rules);
fprintf(['%s over the pick, out of fold against it on this fit set (KPI 1 threshold of its reading %g dB): all %+.2f [%+.2f, %+.2f], ' ...
    'above %+.2f [%+.2f, %+.2f]; F1 airframe_shadowing %+.2f [%+.2f, %+.2f], benign_interference %+.2f [%+.2f, %+.2f]; clean as a ' ...
    'threat %+.2f [%+.2f, %+.2f], as a lost branch %+.2f [%+.2f, %+.2f] -> rule %s\n'], name, thr, d.all, d.above, d.shad, ...
    d.cls(strcmp(d.classes, 'benign_interference'), :), d.cl, d.lb, strjoin(cellfun(@(x) sprintf('%s %d', x, rules.(x)), f(:)', ...
    'UniformOutput', false), ' '));
if ~isempty(t)
    fprintf('  the head: single-row call median %.3f ms, p95 %.3f ms; the detector %.2f / %.2f ms (%s)\n', t.median_ms, t.p95_ms, ...
        det.median_ms, det.p95_ms, det.source);
end
if ok
    fprintf('  deployed: %s over the pick; the pick alone is kept beside (base_fm)\n', name);
elseif log_only
    fprintf('  SMOKE (FUSION_RULE_LOG): %s fails on the smoke data; deployed all the same\n', name);
else
    fprintf('  FALLBACK: %s fails its re-check; the pick alone deploys (recorded, not a no-go)\n', name);
end
R = struct('pick', name, 'adopted', adopted, 'fallback', ~adopted, 'logged_only', log_only && ~ok, 'thr', thr, 'd', d, ...
    'ok', ok, 'rules', rules, 'timing', t, 'cost', cost, 'det', det, 'FM', [], 'cues', [], 'pv', []);
if adopted, R.FM = M.FM; R.cues = M.cues; R.pv = pc; end
end

function t = head_time(H, pc, Zv, det)
% The packed head's single-row call on one thread: 20 warm-up calls, then 2000.
n0 = maxNumCompThreads(1); back = onCleanup(@() maxNumCompThreads(n0));
r = round(linspace(1, size(Zv, 1), 2000));
x = zeros(1, 2020);
for i = 1:2020
    q = r(mod(i - 1, 2000) + 1);
    t0 = tic; fuse_head('apply', H, pc(q, :), Zv(q, :)); x(i) = 1000 * toc(t0);
end
x = sort(x(21:end));
t = struct('median_ms', median(x), 'p95_ms', x(ceil(0.95 * numel(x))), 'det_median_ms', det.median_ms, 'det_p95_ms', det.p95_ms);
end
