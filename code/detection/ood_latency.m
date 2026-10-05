function L = ood_latency(net, M, X, F, nRep)
%OOD_LATENCY  Detector cost per decision cycle of every unknown-threat candidate
%   (M.candidates), timed as measure_latency.m times the detector: detect_scores.m on
%   one frame, each device in its own passes (GPU when present, then CPU), a warm-up of
%   10 calls first, GPU work synchronized before the clock is read; median and 95th
%   percentile over nRep calls, frames cycled. A candidate runs on the device with the
%   lower p95 (the device choice of measure_latency.m) and is admissible when that
%   cost fits the KPI 7 budget (kpi7_admit.m). When none fits, the cheapest is kept.
%   X  128x128x1xN images, F  nFeat x N normalized link features
%   L  cand, devices, med_ms and p95_ms (candidates x devices), dev, med, p95 (on the
%      candidate's device), ok, budget
devs = {'cpu'}; if canUseGPU, devs = {'gpu', 'cpu'}; end
nC = numel(M.candidates); N = size(X, 4); WARM = 10;
med = nan(nC, numel(devs)); q95 = med;
for d = 1:numel(devs)
    ug = strcmp(devs{d}, 'gpu');
    for c = 1:nC
        Mc = M; Mc.score = M.candidates{c};
        t = zeros(1, WARM + nRep);
        for r = 1:WARM + nRep
            i = mod(r - 1, N) + 1;
            t0 = tic; detect_scores(net, Mc, X(:, :, :, i), F(:, i), devs{d});
            if ug, wait(gpuDevice); end
            t(r) = 1000 * toc(t0);
        end
        t = sort(t(WARM + 1:end));
        med(c, d) = median(t); q95(c, d) = t(ceil(0.95 * nRep));
    end
end
[~, j] = min(q95, [], 2);
ix = sub2ind(size(med), (1:nC)', j);
[ok, B] = kpi7_admit(med(ix), q95(ix));
if ~any(ok)
    [~, c] = min(med(ix)); ok(c) = true;
    warning('ood_latency:budget', 'no candidate fits the KPI 7 budget; the cheapest (%s) is kept', M.candidates{c});
end
L = struct('cand', {M.candidates}, 'devices', {devs}, 'med_ms', med, 'p95_ms', q95, 'dev', {reshape(devs(j), 1, [])}, ...
    'med', med(ix)', 'p95', q95(ix)', 'ok', ok(:)', 'budget', B, 'n', nRep);
end
