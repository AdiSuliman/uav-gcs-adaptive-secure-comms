function lines = speed_edge_lines(R, m, lo, hi, shd)
%SPEED_EDGE_LINES  The hover and 161 km/h readings of the deployed policy with cluster intervals, and a
%   like-for-like 161 km/h value without airframe shadowing: lines of policy_evaluation.txt beside
%   the registered line of the edge-speed set (evaluate_policies.m), which they never replace.
%   R    the deployed policy's results on the edge-speed set (policy_run_set.m: recovered, geom)
%   m    the recoverable threat episodes; lo, hi  the hover and the 161 km/h flights
%   shd  the episodes of the airframe-shadowing cell, which flies 161 km/h only: hover has none,
%        so the like-for-like value leaves it out
%   The interval is the 95% percentile bootstrap over flight geometries (boot_cluster.m, 9999
%   resamples), the episodes of one geometry resampled together.
B = 9999;
rows = {'hover', m & lo, 91; ...
        '161 km/h, the registered line (airframe shadowing included)', m & hi, 92; ...
        '161 km/h without airframe shadowing, like-for-like with hover (beside the registered line, never in its place)', ...
        m & hi & ~shd, 93};
lines = {'Speed envelope ends with cluster intervals (deployed policy, recoverable episodes, descriptive; D116 item 5):'};
for i = 1:size(rows, 1)
    k = rows{i, 2};
    if ~any(k), lines{end+1} = sprintf('  %s: no episode', rows{i, 1}); continue; end %#ok<AGROW>
    [v, a, b] = boot_cluster(double(R.recovered(k)), ones(1, sum(k)), R.geom(k), B, rows{i, 3});
    lines{end+1} = sprintf('  %s: %.1f%% [%.1f, %.1f] (%d episodes, %d flights)', rows{i, 1}, 100 * v, 100 * a, 100 * b, ...
        sum(k), numel(unique(R.geom(k)))); %#ok<AGROW>
end
end
