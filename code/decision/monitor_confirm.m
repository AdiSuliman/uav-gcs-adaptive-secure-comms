function [c, a, cn, ot] = monitor_confirm(Tr, mode, thr, cf, cs, cdr, tau)
%MONITOR_CONFIRM  The monitor's confirmed alarm (policy_monitor.m) on the episodes of
%   monitor_trace.m with the drop alarm of form mode ('class_drop', 'class_cusum') at threshold
%   thr (Inf: none): the alarm is any other path or the drop alarm, whose reference never takes
%   an alarm cycle (drop_alarm_seq.m), confirmed on at least m of the last n cycles (cf = [m n]),
%   or, with cs = [k n] (PP.confirm_sweep), on at least k of the last n cycles reading
%   sweeping_jammer, or, with cdr = [k n] (PP.confirm_drop), on at least k of the last n cycles
%   carrying the drop alarm. c episodes x cycles; a the drop alarm; cn the confirmed alarm
%   without the drop alarm (the other paths and the sweeper's: what confirms with it removed).
%   With tau (PP.lb_accept.tau_hi; needs Tr.lb, Tr.plb, Tr.dg of PP.record_lb) a cycle whose class is
%   a lost-branch class alarms on its class only with p_LB >= tau or harm evidence (degraded, degraded
%   without RF evidence or the drop alarm) in the last n cycles, as policy_monitor.m; ot the other paths
%   after it (Tr.other without tau).
if nargin >= 7 && ~isempty(tau), Tr.other = lb_other(Tr, mode, thr, cf, tau); end
ot = Tr.other;
a = false(size(Tr.eg));
if isfinite(thr), a = drop_alarm_seq(Tr.eg, mode, thr, [], Tr.other); end
cn = movsum(double(Tr.other), [cf(2) - 1, 0], 2) >= cf(1);
if nargin >= 5 && ~isempty(cs), cn = cn | movsum(double(Tr.sw), [cs(2) - 1, 0], 2) >= cs(1); end
c = movsum(double(Tr.other | a), [cf(2) - 1, 0], 2) >= cf(1);
if nargin >= 5 && ~isempty(cs), c = c | movsum(double(Tr.sw), [cs(2) - 1, 0], 2) >= cs(1); end
if nargin >= 6 && ~isempty(cdr), c = c | movsum(double(a), [cdr(2) - 1, 0], 2) >= cdr(1); end
end

function o = lb_other(Tr, mode, thr, cf, tau)
% The other paths with the lost-branch acceptance: a withheld cycle keeps its degradation alone. The
% drop alarm's reference takes the withheld cycles and the harm evidence holds the drop alarm, so both
% are solved together; cycle t depends only on the cycles before it, so each pass fixes at least one
% more cycle and the loop ends on the monitor's own sequence.
q = isfield(Tr, 'quiet') && isequal(size(Tr.quiet), size(Tr.other));
hb = Tr.dg; if q, hb = hb | Tr.quiet; end
o = Tr.other;
for it = 1:size(o, 2) + 1
    a = false(size(Tr.eg)); if isfinite(thr), a = drop_alarm_seq(Tr.eg, mode, thr, [], o); end
    h = movsum(double(hb | a), [cf(2) - 1, 0], 2) > 0;
    w = Tr.lb & ~(Tr.plb >= tau | h);
    on = Tr.other; on(w) = Tr.dg(w);
    if isequal(on, o), return; end
    o = on;
end
end
