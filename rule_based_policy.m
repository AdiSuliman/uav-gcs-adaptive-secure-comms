function [action, reason] = rule_based_policy(threat_class, ber, ebno)
%RULE_BASED_POLICY  Fixed expert policy: detected threat class -> recovery action.
%   Baseline for the DQN comparison (proposal: rule-based first, DQN second).
%   Each class maps to the action that addresses its physics as modeled in
%   apply_countermeasure.m (D28); both policies act through that same function.
%
%   With the link measurements (ber = observed BER, ebno = Eb/N0 in dB) the rule
%   also reacts to functional degradation, as the proposal requires of both the
%   agent and the rules (mitigation 13): a non-hostile or unknown class on a link
%   degraded beyond 2x the clean BER gets a generic action instead of no_action
%   (clean BER from the local function clean_ber_ref).
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

function b = clean_ber_ref(ebno)
% Measured clean-link BER at a given Eb/N0 (log-interpolated).
%   Source: data/survivability_boundary.mat (5-repeat baseline), otherwise
%   data/trained_dqn.mat. Returns NaN when neither file is available.
persistent snr ber
if isempty(snr)
    snr = []; ber = [];
    if isfile('data/survivability_boundary.mat')
        L = load('data/survivability_boundary.mat', 'SNR_points', 'ber_clean');
        snr = L.SNR_points; ber = L.ber_clean;
    elseif isfile('data/trained_dqn.mat')
        w = whos('-file', 'data/trained_dqn.mat');
        if all(ismember({'SNR_LIST', 'clean'}, {w.name}))
            L = load('data/trained_dqn.mat', 'SNR_LIST', 'clean');
            snr = L.SNR_LIST; ber = L.clean;
        end
    end
end
if isempty(snr)
    b = NaN;
    return;
end
b = 10.^interp1(snr(:), log10(max(ber(:), 1e-9)), ebno, 'linear', 'extrap');
end
