function t = link_target(n_rx)
%LINK_TARGET  Registered LINK target of edge_map.m for a receive antenna count.
%   t = link_target(n_rx)
%   The 802.11a criterion (PER < 10% at a 1000-byte PSDU) carried to the 1032-bit frame
%   through the simulated block fading with n_rx-branch MRC:
%     3 antennas (profile 1)   5.7%
%     4 antennas (profile 3)   5.39%
%   Any other count has no registered value and stops.
tab = [3 0.057; 4 0.0539];
i = find(tab(:, 1) == n_rx, 1);
if isempty(i)
    error('link_target:noValue', 'link_target: no LINK target registered for %s receive antennas', mat2str(n_rx));
end
t = tab(i, 2);
end
