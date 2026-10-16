function [a, W, drop] = drop_alarm_seq(e, mode, thr, t_stop)
%DROP_ALARM_SEQ  The monitor's drop alarm alone (policy_monitor.m) over sequences of cycles.
%   e       E x n Eb/N0 estimates less the known gain of the configuration [dB], one per
%           cycle, oldest first, from a fresh monitor
%   mode    'class_drop': the 3-cycle median at least thr dB below the reference;
%           'class_cusum': the window-limited CUSUM of the cycle's drop (drop_cusum.m,
%           bounded at 2 thr) at least thr
%   t_stop  optional ('class_cusum'): stop once the statistic has been 0 in every row for
%           10 cycles after it, its reference then the last 10 levels (the later cycles
%           stay false and 0)
%   a       E x n the drop alarm; W the CUSUM statistic (0 with 'class_drop'); drop the
%           reference less the 3-cycle median [dB]
%   The reference is the median of the last 10 cycles without an alarm (with 'class_cusum'
%   the cycles drop_ref.m keeps: those of an excursion of the statistic above 0 only once it
%   has returned to 0 without the alarm), the 3-cycle median before the first, as the monitor
%   keeps it when nothing else raises an alarm.
C = decision_config();
cus = strcmp(mode, 'class_cusum');
if nargin < 4, t_stop = Inf; end
[E, n] = size(e);
a = false(E, n); W = zeros(E, n); drop = zeros(E, n);
e3w = nan(E, 3); R = nan(E, 10); P = nan(E, 10); x = false(E, 1);
w0 = zeros(E, 1); dx = nan(E, C.cusum_win); z = 0;
for t = 1:n
    e3w = [e3w(:, 2:end), e(:, t)];
    e3 = median(e3w, 2, 'omitnan');
    ref = median(R, 2, 'omitnan'); ref(isnan(ref)) = e3(isnan(ref));
    drop(:, t) = ref - e3;
    if cus
        d = ref - e(:, t);
        w0 = drop_cusum(d, w0, dx, thr); dx = [dx(:, 2:end), d];
        W(:, t) = w0; a(:, t) = w0 >= thr;
        [R, P, x] = drop_ref(R, P, x, e(:, t), ~a(:, t), w0, a(:, t));
        if t > t_stop, z = (z + 1) * all(w0 == 0); if z >= 10, break; end, end
    else
        a(:, t) = drop(:, t) >= thr;
        q = ~a(:, t);
        R(q, :) = [R(q, 2:end), e(q, t)];
    end
end
end
