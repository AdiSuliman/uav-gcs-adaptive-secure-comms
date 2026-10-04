function h = sweep_hit_share(p)
%SWEEP_HIT_SHARE  Expected share of the frames the sweeping jammer counts in.
%   h = sweep_hit_share(p): a frame counts when at least 10% of its air time lies inside the sweep's
%   window on our channel (threat_active.m, sweep_window_s.m); the frame starts at a
%   uniform phase of the sweep (jam_timing.m), whose period is uniform in p.sweep_period_s.
g = sweep_window_s(p);
T = linspace(p.sweep_period_s(1), p.sweep_period_s(end), 1001);
h = mean(min(1, (diff(g) + 0.8 * p.air_symbols / p.symbol_rate) ./ T));
end
