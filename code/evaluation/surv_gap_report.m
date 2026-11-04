function [report, M] = surv_gap_report(GA, GB, SNR_points)
%SURV_GAP_REPORT  The gap analysis of the survivability map under surv_v2
%   (map_survivability_boundary.m): the cells where a configuration with a goodput cost does
%   better than every goodput-free one, in two classes. GA, GB: Map A and Map B (surv_grid.m).
%   class 1  Map A non-recoverable, Map B recoverable or marginal: survival bought with
%            throughput (the one-flight map's gap cells)
%   class 2  Map A marginal, Map B recoverable: full recovery bought with throughput
%   A ratio of zero (no bit error in the cell) reads "0 err". M(t).g1, M(t).g2: the classes'
%   cells of entry t.
report = {};
report{end+1} = '=== SURVIVABILITY GAP ANALYSIS ===';
report{end+1} = 'Cells where a configuration with a goodput cost (Map B) does better than every goodput-free one (Map A):';
report{end+1} = '  class 1: Map A non-recoverable, Map B recoverable or marginal (survival bought with throughput)';
report{end+1} = '  class 2: Map A marginal, Map B recoverable (full recovery bought with throughput)';
report{end+1} = 'the goodput trade-off named in the proposal. L: the Map B cell is link-limited; ?: a cell not committed.';
report{end+1} = '';
M = struct('g1', {}, 'g2', {});
n = [0 0];
for t = 1:numel(GA)
    gA = GA(t); gB = GB(t);
    M(t).g1 = gA.status == 3 & (gB.status == 1 | gB.status == 2);
    M(t).g2 = gA.status == 2 & gB.status == 1;
    k = [nnz(M(t).g1), nnz(M(t).g2)]; n = n + k;
    if ~any(k), continue; end
    report{end+1} = sprintf('%s: %d class 1, %d class 2', gA.threat, k(1), k(2)); %#ok<AGROW>
    for c = 1:2
        [li_idx, s_idx] = find(M(t).(sprintf('g%d', c)));
        for i = 1:numel(li_idx)
            li = li_idx(i); s = s_idx(i);
            m = '';
            if gB.link_limited(li, s), m = [m ' L']; end
            if ~gA.committed(li, s) || ~gB.committed(li, s), m = [m ' ?']; end
            report{end+1} = sprintf('  class %d level=%g, Eb/N0=%gdB: Map A %s (%s) | Map B %s (%s)%s', c, gA.levels(li), ...
                SNR_points(s), rtxt(gA.ratio(li, s)), gA.best_action{li, s}, rtxt(gB.ratio(li, s)), gB.best_action{li, s}, m); %#ok<AGROW>
        end
    end
end
report{end+1} = '';
report{end+1} = sprintf('Total gap cells: %d class 1, %d class 2', n(1), n(2));
end

function s = rtxt(r)
if r == 0, s = '0 err'; else, s = sprintf('%.2fx', r); end
end
