function [action, reason] = rule_based_policy(threat_class, ber, ebno)
%RULE_BASED_POLICY  Fixed expert policy: detected threat class -> recovery action.
%   Baseline for the DQN comparison (proposal: rule-based first, DQN second).
%   Each class maps to the action that addresses its physics as modeled in
%   apply_countermeasure.m (D28); both policies act through that same function.
%
%   With the link measurements (ber = observed BER, ebno = Eb/N0 in dB) the rule
%   also reacts to functional degradation, as the proposal requires of both the
%   agent and the rules (mitigation 13): a non-hostile or unknown class on a link
%   degraded beyond 2x the clean BER gets a generic action instead of no_action.
threat_class = char(threat_class);
RATIO_OK = 2;

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
        action = 'no_action';         reason = 'unknown class: no class-specific mapping';
end

if nargin >= 3 && strcmp(action, 'no_action')
    bc = clean_ber_ref(ebno);
    if isfinite(bc) && ber > RATIO_OK * bc
        if strcmp(threat_class, 'benign_interference')
            action = 'channel_switch'; reason = 'interference degrades the link: leave the channel';
        else
            action = 'freq_diversity'; reason = 'link degraded without a known cause: generic diversity';
        end
    end
end
end