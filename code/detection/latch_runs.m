function [pf, cause] = latch_runs(pf, run, pos, gain_ant, classes, thr, heal)
%LATCH_RUNS  The monitor's class probabilities over whole runs (policy_monitor.m): the fused
%   probabilities with the latched cause of a lost branch (onset_shape.m 'sequence') over
%   every run's cycles in time order. A fused antenna_fault or airframe_shadowing reads the
%   cause latched from the shape of the branch's onset; every other class is unchanged.
%   Its callers run it only while the deployed fusion latches (onset_shape('on', FM)).
%   pf        frames x C fused class probabilities
%   run, pos  run id and position of every frame in its run
%   gain_ant  frames x antennas mean channel gain [dB] (extract_closed_loop_frames.m)
%   classes   class names of the columns of pf
%   thr       threshold of the onset statistic (onset_shape('threshold', FM))
%   heal      healthy cycles that close an event (default decision_config.m C.heal)
%   cause     frames x 1: 0 none or pending, 1 antenna_fault, 2 airframe_shadowing
if nargin < 7 || isempty(heal), heal = decision_config().heal; end
cause = zeros(size(pf, 1), 1);
if isempty(pf), return; end
[~, ~, rid] = unique(run(:));
byrun = accumarray(rid, (1:numel(rid))', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r}; [~, o] = sort(pos(ix)); ix = ix(o);
    [pf(ix, :), cause(ix)] = onset_shape('sequence', gain_ant(ix, :), pf(ix, :), classes, heal, thr);
end
end
