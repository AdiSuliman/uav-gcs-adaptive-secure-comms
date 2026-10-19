function [yt, rank] = fusion_target(y, run, pos, N, classes, FM)
%FUSION_TARGET  Target of the fused decision of every frame, and its place in its run.
%   [yt, rank] = fusion_target(y, run, pos, N, classes)
%   [yt, rank] = fusion_target(y, run, pos, N, classes, FM)   the rule fusion FM was fitted on
%   y        class index per frame (the label of the proposal, by what is on the air,
%            mitigation 3, over the decision cycle: a cycle of a WLAN run without a packet
%            on the air in its idle time or its frame is 'none'; a path-loss frame counts
%            while the step's onset lies in its link-feature window, threat_active.m)
%   run, pos sub-run and position of every frame; N the fusion window [cycles]
%   classes  class names (y indexes them)
%   yt       the fused decision is judged on its window (the last N frames of its run,
%            fuse_classes.m): a 'none' frame whose window holds a 'benign_interference'
%            frame has the target 'benign_interference', one whose window holds the
%            onset of a path-loss step (the run's first 'path_loss' frame) and a cycle
%            before it the target 'path_loss' (pos - onset < N - 1, threat_active.m's rule: a
%            window without a cycle before the step holds the same link at a longer range);
%            every other frame keeps its label. A fusion fitted before that rule (FM
%            without target_age, or no FM) is read on its own, pos - onset < N
%   rank     place of the frame in its run's order (1 = first); its window is full
%            from rank N on
classes = cellstr(string(classes));
age = N;
if nargin >= 6 && isstruct(FM) && isfield(FM, 'target_age'), age = FM.target_age; end
ib = find(strcmp(classes, 'benign_interference'), 1); i0 = find(strcmp(classes, 'none'), 1);
ip = find(strcmp(classes, 'path_loss'), 1);
y = double(y(:)); n = numel(y);
yt = y; rank = zeros(n, 1);
[~, ~, rid] = unique(run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(pos(ix)); ix = ix(o);
    rank(ix) = 1:numel(ix);
    if isempty(i0), continue; end
    pr = pos(ix); pr = pr(:);
    if ~isempty(ib) && any(y(ix) == ib)
        isb = y(ix) == ib;
        for j = find(y(ix)' == i0)
            if any(isb(max(1, j - N + 1):j)), yt(ix(j)) = ib; end
        end
    end
    if ~isempty(ip) && any(y(ix) == ip)
        t0 = pr(find(y(ix) == ip, 1));                    % onset of the step
        k = y(ix) == i0 & pr >= t0 & pr - t0 < age;
        yt(ix(k)) = ip;
    end
end
end
