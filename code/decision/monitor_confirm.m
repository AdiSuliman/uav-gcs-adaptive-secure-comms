function [c, a, cn] = monitor_confirm(Tr, mode, thr, cf, cs, cdr)
%MONITOR_CONFIRM  The monitor's confirmed alarm (policy_monitor.m) on the episodes of
%   monitor_trace.m with the drop alarm of form mode ('class_drop', 'class_cusum') at threshold
%   thr (Inf: none): the alarm is any other path or the drop alarm, whose reference never takes
%   an alarm cycle (drop_alarm_seq.m), confirmed on at least m of the last n cycles (cf = [m n]),
%   or, with cs = [k n] (PP.confirm_sweep), on at least k of the last n cycles reading
%   sweeping_jammer, or, with cdr = [k n] (PP.confirm_drop), on at least k of the last n cycles
%   carrying the drop alarm. c episodes x cycles; a the drop alarm; cn the confirmed alarm
%   without the drop alarm (the other paths and the sweeper's: what confirms with it removed).
a = false(size(Tr.eg));
if isfinite(thr), a = drop_alarm_seq(Tr.eg, mode, thr, [], Tr.other); end
cn = movsum(double(Tr.other), [cf(2) - 1, 0], 2) >= cf(1);
if nargin >= 5 && ~isempty(cs), cn = cn | movsum(double(Tr.sw), [cs(2) - 1, 0], 2) >= cs(1); end
c = movsum(double(Tr.other | a), [cf(2) - 1, 0], 2) >= cf(1);
if nargin >= 5 && ~isempty(cs), c = c | movsum(double(Tr.sw), [cs(2) - 1, 0], 2) >= cs(1); end
if nargin >= 6 && ~isempty(cdr), c = c | movsum(double(a), [cdr(2) - 1, 0], 2) >= cdr(1); end
end
