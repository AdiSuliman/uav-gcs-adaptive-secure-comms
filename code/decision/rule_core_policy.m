function [action, reason] = rule_core_policy(threat_class, degraded, q_iot_db, q_thr_db, drop, budget, slot_on)
%RULE_CORE_POLICY  The expert rule on the revised proposal's core action set.
%   The proposal's predefined recovery actions, channel switching and transmission-rate
%   adaptation: no_action, channel_switch, rate_reduce and channel_switch+rate_reduce
%   (decision_config.m C.core_actions). Each class maps to the core configuration that
%   addresses its physics as modeled in apply_countermeasure.m, as rule_based_policy.m maps
%   it among the 36 configurations:
%     interference on our channel (jamming, reactive_jamming, spoofing, tone_jamming; a
%     degraded link read as benign_interference, or as none while the quiet slot holds
%     interference, Xu et al. 2005): channel_switch, a channel the interferer does not occupy
%     a jammer a hop does not escape (sweeping_jammer visits every channel, noise_burst
%     covers them all) and a loss of our own signal (path_loss, antenna_fault,
%     airframe_shadowing, a drop alarm with a quiet slot): rate_reduce, its processing gain
%     against noise and every interferer not spread like our signal (Eb/N0 = S/N0 x 1/R)
%     a degraded link without a known cause: channel_switch+rate_reduce, both elements
%   benign_interference and none on a healthy link, and unknown: no_action.
%   degraded, q_iot_db, q_thr_db, drop, slot_on  as rule_based_policy.m
%   budget   optional, as rule_based_policy.m (drop_db, current, current_db): a loss of our
%            signal keeps the configuration in use when its known gain covers the drop,
%            else rate_reduce, the core set's only link-budget gain
%   Outside the core set: spatial_diversity, freq_diversity, power_control, fec_interleave.
C = decision_config();
threat_class = char(threat_class);
if nargin < 2 || isempty(degraded), degraded = false; end
if nargin < 3 || isempty(q_iot_db), q_iot_db = -Inf; end
if nargin < 4 || isempty(q_thr_db) || isnan(q_thr_db), q_thr_db = C.q_alarm_db; end
if nargin < 5 || isempty(drop), drop = false; end
if nargin < 6, budget = []; end
if nargin < 7 || isempty(slot_on), slot_on = true; end
slot = q_iot_db >= q_thr_db;

switch threat_class
    case {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'}
        action = 'channel_switch';    reason = 'interferer tied to our channel: leave it';
    case {'sweeping_jammer', 'noise_burst'}
        action = 'rate_reduce';       reason = 'a hop does not escape it: processing gain';
    case 'path_loss'
        action = 'rate_reduce';       reason = 'weak signal: processing gain';
        if ~isempty(budget), [action, reason] = core_budget(budget); end
    case {'antenna_fault', 'airframe_shadowing'}
        action = 'rate_reduce';       reason = 'one branch lost: processing gain';
    case {'benign_interference', 'none'}
        action = 'no_action';         reason = 'not an attack: acting would be a false alarm';
    otherwise
        action = 'no_action';         reason = 'unknown class: no class-specific mapping';
end

if strcmp(action, 'no_action') && drop && ~slot && ~strcmp(threat_class, 'benign_interference')
    action = 'rate_reduce'; reason = 'our signal dropped over thermal noise: processing gain';
    if ~isempty(budget), [action, reason] = core_budget(budget); end
elseif strcmp(action, 'no_action') && degraded
    if strcmp(threat_class, 'benign_interference')
        action = 'channel_switch'; reason = 'interference degrades the link: leave the channel';
    elseif strcmp(threat_class, 'none') && slot && slot_on
        action = 'channel_switch'; reason = 'degraded link with interference in the quiet slot: leave the channel';
    else
        action = 'channel_switch+rate_reduce'; reason = 'link degraded without a known cause: both core actions';
    end
end
end

function [action, reason] = core_budget(b)
% Keep the configuration in use when its known gain covers the drop, else rate_reduce.
if b.current_db >= b.drop_db
    action = b.current; reason = sprintf('the configuration in use covers the %.1f dB drop', b.drop_db);
else
    action = 'rate_reduce'; reason = sprintf('our signal dropped %.1f dB: processing gain', b.drop_db);
end
end
