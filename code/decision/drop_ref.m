function [R, P, x] = drop_ref(R, P, x, e, ok, W, al)
%DROP_REF  Reference cycles of the CUSUM drop alarm, one cycle (policy_monitor.m
%   'class_cusum', drop_alarm_seq.m). Page's statistic (drop_cusum.m) is the log-likelihood
%   ratio counted from the maximum-likelihood change point, the last cycle it was 0 (Xie et
%   al. 2021, eq. 3): the cycles since then are held while it is above 0. When it returns to
%   0 without having raised the alarm, they were before any change and join the reference;
%   when it raised the alarm, they are the change's and are left out. The reference so holds
%   the level before a change while its evidence builds up, and every clean cycle, low or
%   high, in the end.
%   R   E x n the reference's cycles, oldest first (NaN: none yet)
%   P   E x n the held cycles of the excursion above 0 in progress (NaN: none)
%   x   E x 1 the excursion has raised the alarm
%   e   E x 1 this cycle's levels [dB]; ok E x 1 the cycle may join (no alarm of any cause);
%   W   E x 1 the statistic after this cycle; al E x 1 its drop alarm
x = x | al;
up = W > 0;
h = up & ok;
P(h, :) = [P(h, 2:end), e(h)];
n = size(R, 2);
for i = find(~up & ~x & any(~isnan(P), 2))'
    v = [R(i, :), P(i, ~isnan(P(i, :)))]; R(i, :) = v(end - n + 1:end);
end
k = ~up & ok;
R(k, :) = [R(k, 2:end), e(k)];
P(~up, :) = NaN; x(~up) = false;
end
