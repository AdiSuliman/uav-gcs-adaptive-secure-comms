function names = policy_actions()
%POLICY_ACTIONS  The 17 configurations of the decision layer: no_action, six
%   single countermeasures, every {channel_switch, freq_diversity,
%   spatial_diversity} x {rate_reduce, power_control, fec_interleave} pair (D39),
%   and the link-budget pair rate_reduce + power_control against signal-side
%   attenuation, where avoidance does nothing (D45).
singles = {'no_action', 'channel_switch', 'rate_reduce', 'freq_diversity', 'spatial_diversity', ...
           'power_control', 'fec_interleave'};
avoid  = {'channel_switch', 'freq_diversity', 'spatial_diversity'};
robust = {'rate_reduce', 'power_control', 'fec_interleave'};
pairs = {};
for i = 1:numel(avoid)
    for j = 1:numel(robust), pairs{end+1} = [avoid{i} '+' robust{j}]; end %#ok<AGROW>
end
names = [singles, pairs, {'rate_reduce+power_control'}];
end
