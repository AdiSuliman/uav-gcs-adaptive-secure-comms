function w = monitor_window_drop(e)
%MONITOR_WINDOW_DROP  Largest drop the link monitor reads on a sequence of our signal's
%   level e [dB], one value per decision cycle, after a steady cruise at e(1)
%   (policy_monitor.m 'class_drop', drop_alarm_seq.m): the median of its reference's 10
%   cycles minus the median of the last 3, the reference holding an excursion of that drop
%   above half the smallest path-loss level until it ends (drop_ref.m), no alarm raised. Up to
%   the first cycle it reaches a threshold the reading is the same with that threshold's
%   alarm, so the drop alarm is raised along e exactly when w reaches it. A step reads its
%   full depth from its second cycle on; a ramp of s dB per cycle reads 4.5 s while that
%   stays below the excursion's start, and its whole depth after it.
e = reshape(e, 1, []);
[~, ~, d] = drop_alarm_seq([repmat(e(1), 1, 10), e], 'class_drop', Inf);
w = max(0, max(d(11:end)));
end
