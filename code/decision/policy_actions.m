function names = policy_actions()
%POLICY_ACTIONS  The configurations of the decision layer.
%   One choice per domain, applied together (the combined action a = (f, p, ...)
%   of Liu et al., 2018):
%     frequency     none | channel_switch | freq_diversity
%     space         none | spatial_diversity (adaptive MMSE combining)
%     link budget   none | rate_reduce | power_control | fec_interleave |
%                   rate_reduce+power_control | power_control+fec_interleave
%   3 x 2 x 6 = 36 configurations; 'no_action' is the configuration with no choice
%   in any domain. The names join the chosen actions with '+', in this order.
freq   = {'', 'channel_switch', 'freq_diversity'};
space  = {'', 'spatial_diversity'};
budget = {'', 'rate_reduce', 'power_control', 'fec_interleave', 'rate_reduce+power_control', ...
          'power_control+fec_interleave'};
names = {};
for b = 1:numel(budget)
    for s = 1:numel(space)
        for f = 1:numel(freq)
            parts = [freq(f), space(s), budget(b)];
            n = strjoin(parts(~cellfun(@isempty, parts)), '+');
            if isempty(n), n = 'no_action'; end
            names{end+1} = n; %#ok<AGROW>
        end
    end
end
end
