function m = ood_window(s, run, pos, W)
%OOD_WINDOW  The unknown-threat statistic of the decision cycle (policy_monitor.m): the
%   score averaged over the last W cycles of the frame's own sub-run, the frame the newest
%   of its window; the first frames of a sub-run average over the cycles it has (a partial
%   window, as the monitor's window fills).
%   m = ood_window(s, run, pos, W)
%   s     per-frame score (higher = more like the known classes)
%   run   sub-run of every frame
%   pos   position of every frame in its sub-run (time order); empty: the order given
%   W     window [cycles] (ood.win); 1 = the frame alone
%   m     column, one value per frame
s = double(s(:)); n = numel(s); m = nan(n, 1);
if n == 0, return; end
if isempty(pos), pos = (1:n)'; end
pos = pos(:);
[~, ~, rid] = unique(run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(pos(ix)); ix = ix(o);
    m(ix) = movmean(s(ix), [W - 1, 0]);
end
end
