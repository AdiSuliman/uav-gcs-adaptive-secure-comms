function r = drop_alarm_any(e, mode, thr)
%DROP_ALARM_ANY  Whether the monitor's drop alarm alone (drop_alarm_seq.m) is raised in some
%   cycle along each row of e (E x n levels of our signal [dB], one per cycle), flown from a
%   steady cruise at e(:, 1), the monitor's windows full of it. Before an excursion of its
%   statistic the reference is the median of the last 10 cycles, at most the highest of them;
%   an excursion starts only when one of the last 3 levels is at least D below the highest of
%   the 10 cycles before that level (D half the smallest path-loss level: the median window's
%   excursion starts there, and the CUSUM does not grow on a smaller drop, drop_cusum.m). The
%   cycles are run from 20 before the first such level, when the monitor's windows hold the
%   same levels as from the cruise, until the excursion statistic has been 0 in every row for
%   10 cycles after the last one.
C = decision_config();
E = size(e, 1);
r = false(E, 1);
D = C.sev.path_loss.levels(1) / 2;
x = [repmat(e(:, 1), 1, 10), e];
hi = movmax(x, [9 0], 2);
hi = hi(:, 10:end - 1);                                 % the highest of the 10 cycles before each
can = find(any(hi - e >= D, 1));
if isempty(can), return; end
y = [repmat(e(:, 1), 1, 20), e];                       % cycle t of e is cycle t + 20 of y
a = drop_alarm_seq(y(:, can(1):end), mode, thr, can(end) - can(1) + 21);
r = any(a, 2);
end
