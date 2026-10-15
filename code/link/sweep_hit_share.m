function h = sweep_hit_share(p)
%SWEEP_HIT_SHARE  Expected share of the decision cycles the sweeping jammer counts in.
%   h = sweep_hit_share(p): with idle sensing (p.idle_rssi_hz > 0) a cycle counts while the
%   sweep's window on our channel (sweep_window_s.m) overlaps it anywhere, the idle time
%   before the frame or the frame (threat_active.m, per decision cycle): a window of g
%   seconds meets a cycle of p.cycle_s seconds at a uniform phase with probability
%   min(1, (g + cycle) / T); without it a frame counts when at least 10% of its air time
%   lies inside the window. The phase is uniform (jam_timing.m) and the period uniform in
%   p.sweep_period_s.
g = sweep_window_s(p);
T = linspace(p.sweep_period_s(1), p.sweep_period_s(end), 1001);
if isfield(p, 'idle_rssi_hz') && ~isempty(p.idle_rssi_hz) && p.idle_rssi_hz > 0
    h = mean(min(1, (diff(g) + p.cycle_s) ./ T));
else
    h = mean(min(1, (diff(g) + 0.8 * p.air_symbols / p.symbol_rate) ./ T));
end
end
