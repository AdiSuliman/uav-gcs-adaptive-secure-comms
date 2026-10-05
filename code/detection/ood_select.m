function [b, nb] = ood_select(Mp, ok)
%OOD_SELECT  The production (candidate, window) pair of the unknown-threat score
%   (eval_ood_detection.m): the highest mean AUROC over the held-out threats among the
%   pairs whose candidate fits the KPI 7 budget (ood_latency.m), and for the nested
%   estimate the pair chosen the same way on the other held-out threats.
%   Mp  held-out threats x pairs, AUROC
%   ok  1 x pairs, admissible
%   b   column of the selected pair; nb  1 x threats, column chosen without that threat
m = mean(Mp, 1); m(~ok) = -inf;
[~, b] = max(m);
nb = zeros(1, size(Mp, 1));
for i = 1:size(Mp, 1)
    m = mean(Mp(setdiff(1:size(Mp, 1), i), :), 1); m(~ok) = -inf;
    [~, nb(i)] = max(m);
end
end
