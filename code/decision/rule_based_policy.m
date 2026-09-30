function [action, reason] = rule_based_policy(threat_class, degraded, mmse_gain_db)
%RULE_BASED_POLICY  Fixed expert policy: detected threat class -> configuration.
%   Baseline for the DQN comparison (proposal: rule-based first, DQN second).
%   Each class maps to the configuration that addresses its physics as modeled in
%   apply_countermeasure.m; both policies act through that same function.
%   degraded      the link monitor's degradation flag (policy_monitor.m): a
%                 non-hostile or unknown class on a degraded link gets a generic
%                 configuration instead of no_action (proposal mitigation 15)
%   mmse_gain_db  the receiver's predicted gain of MMSE combining over MRC
%                 (link_features.m): when the interferer is spatially separable
%                 (>= C.rule_mmse_db) the rule also nulls it with the two antennas,
%                 so the rule sees the same spatial information as the agent
%   With one argument the class mapping alone is returned.
C = decision_config();
threat_class = char(threat_class);
if nargin < 2 || isempty(degraded), degraded = false; end
if nargin < 3 || isempty(mmse_gain_db), mmse_gain_db = 0; end
sep = mmse_gain_db >= C.rule_mmse_db;

switch threat_class
    case {'jamming', 'reactive_jamming', 'spoofing'}
        action = 'channel_switch';    reason = 'interferer tied to our channel: leave it';
        if sep, action = 'channel_switch+spatial_diversity'; reason = [reason ', and null it (separable)']; end
    case 'sweeping_jammer'
        action = 'freq_diversity';    reason = 'sweeper visits every channel: need two at once';
        if sep, action = 'freq_diversity+spatial_diversity'; reason = [reason ', and null it (separable)']; end
    case 'noise_burst'
        action = 'power_control+fec_interleave'; reason = 'broadband bursts: coding repairs them';
        if sep, action = 'spatial_diversity+fec_interleave'; reason = 'broadband bursts from one direction: null and code'; end
    case 'path_loss'
        action = 'rate_reduce+power_control'; reason = 'weak signal: largest link-budget gain';
    case 'antenna_fault'
        action = 'spatial_diversity'; reason = 'adaptive combining drops the faulty branch';
    case {'benign_interference', 'none'}
        action = 'no_action';         reason = 'not an attack: acting would be a false alarm';
    otherwise
        action = 'no_action';         reason = 'unknown class: no class-specific mapping';
end

if strcmp(action, 'no_action') && degraded
    if strcmp(threat_class, 'benign_interference')
        action = 'channel_switch'; reason = 'interference degrades the link: leave the channel';
    elseif sep
        action = 'spatial_diversity+power_control'; reason = 'degraded link, separable interference: null it';
    else
        action = 'freq_diversity+power_control'; reason = 'link degraded without a known cause: generic diversity';
    end
end
end
