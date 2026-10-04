function [yt, rank] = fusion_target(y, run, pos, N, classes)
%FUSION_TARGET  Target of the fused decision of every frame, and its place in its run.
%   [yt, rank] = fusion_target(y, run, pos, N, classes)
%   y        class index per frame (the per-frame label of the proposal: a frame of a
%            WLAN run without a packet on the air is 'none', mitigation 3)
%   run, pos sub-run and position of every frame; N the fusion window [cycles]
%   classes  class names (y indexes them)
%   yt       the fused decision is judged on its window: a 'none' frame whose window
%            (the last N frames of its run, fuse_classes.m) holds a
%            'benign_interference' frame has the target 'benign_interference'; every
%            other frame keeps its label
%   rank     place of the frame in its run's order (1 = first); its window is full
%            from rank N on
classes = cellstr(string(classes));
ib = find(strcmp(classes, 'benign_interference'), 1); i0 = find(strcmp(classes, 'none'), 1);
y = double(y(:)); n = numel(y);
yt = y; rank = zeros(n, 1);
[~, ~, rid] = unique(run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(pos(ix)); ix = ix(o);
    rank(ix) = 1:numel(ix);
    if isempty(ib) || isempty(i0), continue; end
    isb = y(ix) == ib;
    if ~any(isb), continue; end
    for j = find(y(ix)' == i0)
        if any(isb(max(1, j - N + 1):j)), yt(ix(j)) = ib; end
    end
end
end
