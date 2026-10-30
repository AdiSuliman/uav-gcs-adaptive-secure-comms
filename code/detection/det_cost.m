function c = det_cost(f)
%DET_COST  The deployed detector's cost per frame with its production unknown-threat score, on
%   the device it runs on (eval_ood_detection.m's LC and sel; ood_latency.m), for rule S7 of
%   fusion_adopt.m: the detector with the head still within the KPI 7 budget (kpi7_admit.m).
%   c = det_cost(f)  f the file (default results/ood_detection.mat)
%   c  median_ms, p95_ms (NaN when the file or its cost is missing), source
if nargin < 1 || isempty(f), f = 'results/ood_detection.mat'; end
c = struct('median_ms', NaN, 'p95_ms', NaN, 'source', [f ' missing']);
if ~isfile(f), return; end
L = load(f, 'LC', 'sel');
if ~all(isfield(L, {'LC', 'sel'})), c.source = [f ' without LC or sel']; return; end
k = find(strcmp(L.LC.cand, L.sel), 1);
if isempty(k), c.source = [f ': the production score has no cost']; return; end
c = struct('median_ms', L.LC.med(k), 'p95_ms', L.LC.p95(k), 'source', sprintf('%s, %s on %s', f, L.sel, upper(L.LC.dev{k})));
end
