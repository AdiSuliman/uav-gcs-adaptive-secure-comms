function [a, W, drop] = drop_alarm_seq(e, mode, thr, t_stop, other)
%DROP_ALARM_SEQ  The monitor's drop alarm alone (policy_monitor.m) over sequences of cycles.
%   e       E x n Eb/N0 estimates less the known gain of the configuration [dB], one per
%           cycle, oldest first, from a fresh monitor
%   mode    'class_drop': the 3-cycle median at least thr dB below the reference;
%           'class_cusum': the window-limited CUSUM of the cycle's drop (drop_cusum.m,
%           bounded at 2 thr) at least thr
%   t_stop  optional: stop once the excursion statistic W has been 0 in every row for 10
%           cycles after it, its reference then the last 10 levels (the later cycles stay
%           false and 0)
%   other   optional E x n: the cycles another path of the monitor alarms on (a hostile
%           class, degradation), which never join the reference (policy_monitor.m)
%   a       E x n the drop alarm; W the excursion statistic: the CUSUM's, or with
%           'class_drop' 1 while the median's drop is at least half the smallest path-loss
%           level; drop the reference less the 3-cycle median [dB]
%   The reference is the median of the last 10 cycles drop_ref.m keeps: those without an
%   alarm, the cycles of an excursion of W above 0 only once it has returned to 0 without the
%   drop alarm; the 3-cycle median before the first.
C = decision_config();
cus = strcmp(mode, 'class_cusum');
if nargin < 4 || isempty(t_stop), t_stop = Inf; end
[E, n] = size(e);
if nargin < 5 || isempty(other), other = false(E, n); end
a = false(E, n); W = zeros(E, n); drop = zeros(E, n);
e3w = nan(E, 3); R = nan(E, 10); P = nan(E, 10); x = false(E, 1);
w0 = zeros(E, 1); dx = nan(E, C.cusum_win); z = 0;
D2 = C.sev.path_loss.levels(1) / 2;
for t = 1:n
    e3w = [e3w(:, 2:end), e(:, t)];
    e3 = median(e3w, 2, 'omitnan');
    ref = median(R, 2, 'omitnan'); ref(isnan(ref)) = e3(isnan(ref));
    drop(:, t) = ref - e3;
    if cus
        d = ref - e(:, t);
        w0 = drop_cusum(d, w0, dx, thr); dx = [dx(:, 2:end), d];
        W(:, t) = w0; a(:, t) = w0 >= thr;
    else
        W(:, t) = drop(:, t) >= D2; a(:, t) = drop(:, t) >= thr;
    end
    [R, P, x] = drop_ref(R, P, x, e(:, t), ~a(:, t) & ~other(:, t), W(:, t), a(:, t));
    if t > t_stop, z = (z + 1) * all(W(:, t) == 0); if z >= 10, break; end, end
end
end
