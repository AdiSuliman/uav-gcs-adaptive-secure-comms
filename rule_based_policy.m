function [action, reason] = rule_based_policy(threat_class)
%RULE_BASED_POLICY  Fixed expert mapping from detected threat class to recovery action.
%   Baseline policy for the DQN comparison (proposal: rule-based first, DQN second).
%   Each choice is the action that addresses the threat's physics as modeled in
%   apply_countermeasure.m (D28); both policies act through that same function,
%   so the comparison measures decision quality, not execution strength.
threat_class = char(threat_class);

switch threat_class
    case 'jamming'
        action = 'channel_switch';    reason = 'in-channel jammer: leave the channel';
    case 'reactive_jamming'
        action = 'channel_switch';    reason = 'jammer reacts on our channel: leave it';
    case 'sweeping_jammer'
        action = 'freq_diversity';    reason = 'sweeper visits every channel: need two at once';
    case 'spoofing'
        action = 'channel_switch';    reason = 'spoofer tied to our channel: leave it';
    case 'path_loss'
        action = 'rate_reduce';       reason = 'weak signal: largest link-budget gain';
    case 'noise_burst'
        action = 'rate_reduce';       reason = 'broadband bursts: processing gain';
    case 'antenna_fault'
        action = 'spatial_diversity'; reason = 'switch to the healthy antenna';
    case {'benign_interference', 'none'}
        action = 'no_action';         reason = 'not an attack: acting would be a false alarm';
    otherwise
        action = 'no_action';         reason = 'unknown class: no reliable mapping';
end
end