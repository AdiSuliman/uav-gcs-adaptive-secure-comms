function [action, reason] = rule_based_policy(threat_class, degraded, mmse_gain_db, q_iot_db, q_thr_db)
%RULE_BASED_POLICY  Fixed expert policy: detected threat class -> configuration.
%   Baseline for the DQN comparison (proposal: rule-based first, DQN second).
%   Each class maps to the configuration that addresses its physics as modeled in
%   apply_countermeasure.m; both policies act through that same function.
%   degraded      the link monitor's degradation flag (policy_monitor.m): a
%                 non-hostile or unknown class on a degraded link gets a generic
%                 configuration instead of no_action (proposal mitigation 15)
%   mmse_gain_db  the receiver's predicted gain of MMSE combining over MRC
%                 (link_features.m): when the interferer is spatially separable
%                 (>= C.rule_mmse_db) the rule also nulls it with the antennas,
%                 so the rule sees the same spatial information as the agent
%   q_iot_db      interference over thermal in this frame's quiet slot (link_features.m)
%   q_thr_db      its alarm threshold, from the clean validation frames
%                 (select_fusion.m; default C.q_alarm_db)
%   A degraded link whose class is none or benign_interference while the quiet slot
%   shows interference is interference on our channel: a low packet delivery with a
%   high signal level is jamming, not a weak link (Xu et al. 2005, pp. 8-9); the
%   slot's power plays the part of the AGC level of a jamming monitor (Kazim et al.
%   2026, eq. 1.3, p. 2; AGC gain as a detector, Ndili & Enge 1998, p. 5). The rule
%   leaves the channel there.
%   With one argument the class mapping alone is returned.
C = decision_config();
threat_class = char(threat_class);
if nargin < 2 || isempty(degraded), degraded = false; end
if nargin < 3 || isempty(mmse_gain_db), mmse_gain_db = 0; end
if nargin < 4 || isempty(q_iot_db), q_iot_db = -Inf; end
if nargin < 5 || isempty(q_thr_db) || isnan(q_thr_db), q_thr_db = C.q_alarm_db; end
sep = mmse_gain_db >= C.rule_mmse_db;
slot = q_iot_db >= q_thr_db;

switch threat_class
    case {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'}
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
    case 'airframe_shadowing'
        action = 'power_control';     reason = 'one antenna hidden by the airframe: raise the link budget';
    case {'benign_interference', 'none'}
        action = 'no_action';         reason = 'not an attack: acting would be a false alarm';
    otherwise
        action = 'no_action';         reason = 'unknown class: no class-specific mapping';
end

if strcmp(action, 'no_action') && degraded
    if strcmp(threat_class, 'benign_interference')
        action = 'channel_switch'; reason = 'interference degrades the link: leave the channel';
    elseif strcmp(threat_class, 'none') && slot
        action = 'channel_switch'; reason = 'degraded link with interference in the quiet slot: leave the channel';
        if sep, action = 'channel_switch+spatial_diversity'; reason = [reason ', and null it (separable)']; end
    elseif sep
        action = 'spatial_diversity+power_control'; reason = 'degraded link, separable interference: null it';
    else
        action = 'freq_diversity+power_control'; reason = 'link degraded without a known cause: generic diversity';
    end
end
end
