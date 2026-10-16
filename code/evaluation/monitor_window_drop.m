function w = monitor_window_drop(e)
%MONITOR_WINDOW_DROP  Largest drop the link monitor reads on a sequence of our signal's
%   level e [dB], one value per decision cycle, after a steady cruise at e(1)
%   (policy_monitor.m): the median of the 10 cycles before the current one minus the median
%   of the last 3, its reference never frozen (no alarm before the largest drop is read).
%   A step reads its full depth from its second cycle on; a ramp of s dB per cycle reads
%   4.5 s.
e = [repmat(e(1), 1, 10), reshape(e, 1, [])];
r = movmedian(e, [9 0], 'Endpoints', 'shrink');      % the 10 cycles up to each one
m3 = movmedian(e, [2 0], 'Endpoints', 'shrink');
w = max(0, max(r(10:end-1) - m3(11:end)));
end
