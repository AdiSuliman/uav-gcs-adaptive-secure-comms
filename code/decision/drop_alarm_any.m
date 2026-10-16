function r = drop_alarm_any(e, mode, thr)
%DROP_ALARM_ANY  Whether the monitor's drop alarm alone (drop_alarm_seq.m) is raised in some
%   cycle along each row of e (E x n levels of our signal [dB], one per cycle), flown from a
%   steady cruise at e(:, 1), the monitor's windows full of it. A cycle can raise it only
%   when one of its last 3 levels is at least D below the highest of the 10 cycles before
%   that level (the reference is at most that high; D the threshold with 'class_drop'; with
%   'class_cusum' half the smallest change of drop_cusum.m, below which its statistic does
%   not grow). The cycles are run from 20 before the first such level, when the monitor's
%   windows hold the same levels as from the cruise, to 2 after the last ('class_drop'), or
%   until the statistic has been 0 in every row for 10 cycles after it ('class_cusum').
C = decision_config();
E = size(e, 1);
r = false(E, 1);
cus = strcmp(mode, 'class_cusum');
D = thr; if cus, D = C.sev.path_loss.levels(1) / 2; end
x = [repmat(e(:, 1), 1, 10), e];
hi = movmax(x, [9 0], 2);
hi = hi(:, 10:end - 1);                                 % the highest of the 10 cycles before each
can = find(any(hi - e >= D, 1));
if isempty(can), return; end
y = [repmat(e(:, 1), 1, 20), e];                       % cycle t of e is cycle t + 20 of y
if cus
    a = drop_alarm_seq(y(:, can(1):end), mode, thr, can(end) - can(1) + 21);
else
    a = drop_alarm_seq(y(:, can(1):min(end, can(end) + 22)), mode, thr);
end
r = any(a, 2);
end
