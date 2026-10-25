function [action, reason] = rule_based_policy(threat_class, degraded, mmse_gain_db, q_iot_db, q_thr_db, drop, budget, mmse_thr_db, slot_on, burst_action)
%RULE_BASED_POLICY  Fixed expert policy: detected threat class -> configuration.
%   Baseline for the DQN comparison (proposal: rule-based first, DQN second).
%   Each class maps to the configuration that addresses its physics as modeled in
%   apply_countermeasure.m; both policies act through that same function.
%   degraded      the link monitor's degradation flag (policy_monitor.m): a
%                 non-hostile or unknown class on a degraded link gets a generic
%                 configuration instead of no_action (proposal mitigation 15)
%   mmse_gain_db  the receiver's predicted gain of MMSE combining over MRC from the
%                 frame's known symbols (mmse_predict.m, obs.mmse_pred): when the
%                 interferer is spatially separable (>= mmse_thr_db) the rule also nulls
%                 it with the antennas, so the rule sees the same spatial information as
%                 the agent; NaN reads as not separable
%   q_iot_db      interference over thermal in this frame's quiet slot (link_features.m)
%   q_thr_db      its alarm threshold, from the clean validation frames
%                 (select_fusion.m; default C.q_alarm_db)
%   drop          the monitor's drop alarm: our signal over thermal noise fell by the
%                 drop threshold from its reference before (policy_monitor.m)
%   budget        the link budget of the cycle (optional): drop_db, the monitor's drop
%                 without the known gains of the configurations (policy_monitor.m);
%                 current, the configuration in use, and current_db its known gain;
%                 names and gain_db, the link-budget configurations and their known
%                 gains (config_gain_db.m)
%   mmse_thr_db   the nulling threshold (optional; PP.rule_mmse_db, default C.rule_mmse_db)
%   slot_on       the quiet-slot branch of a degraded link read as none below (optional;
%                 PP.rule_slot, default true; chosen on validation, train_dqn.m); the slot
%                 still keeps a drop alarm from the link-budget answer
%   burst_action  the answer to the class noise_burst (optional; PP.rule_nb, chosen on
%                 validation, train_dqn.m): {not separable, separable}, two of the 36
%                 configurations; empty keeps the class mapping below
%   A lost branch (an antenna fault or airframe shadowing) leaves white noise on the
%   antennas, where adaptive combining (MVDR) is maximum-ratio combining (Winters, Salz &
%   Gitlin 1994) and only pays its estimation loss (Besson 2021, eq. 20-21): both take
%   power_control, and spatial_diversity beside it only where the receiver's predicted
%   MMSE gain says an interferer is separable.
%   On a degraded link whose class is benign_interference the rule leaves the channel.
%   A degraded link whose class is none while the quiet slot shows interference is
%   interference on our channel: a low packet delivery with a high signal level is
%   jamming, not a weak link (Xu et al. 2005, pp. 8-9); the slot's power plays the part
%   of the AGC level of a jamming monitor (Kazim et al. 2026, eq. 1.3, p. 2; AGC gain as
%   a detector, Ndili & Enge 1998, p. 5). The rule leaves the channel there too, and
%   nulls the interferer when it is separable.
%   A drop alarm whose class has no mapping (none, unknown) is a loss on our signal's side,
%   attenuation and not interference (the slot is quiet). The answer to a loss of our
%   signal, that drop alarm and the class path_loss, is a link-budget match when the
%   budget is given: the received power falls by the drop, and the known gain of a
%   configuration raises Eb/N0 by that gain (Friis; Eb/N0 = S/N0 x 1/R), so the rule takes
%   the link-budget configuration with the smallest gain that covers the drop (the
%   largest when none does), and keeps the configuration in use when its own gain already
%   covers it. Without the budget: power_control, rate_reduce+power_control when the link
%   is also degraded, and rate_reduce+power_control for the class path_loss.
%   With one argument the class mapping alone is returned.
C = decision_config();
threat_class = char(threat_class);
if nargin < 2 || isempty(degraded), degraded = false; end
if nargin < 3 || isempty(mmse_gain_db), mmse_gain_db = 0; end
if nargin < 4 || isempty(q_iot_db), q_iot_db = -Inf; end
if nargin < 5 || isempty(q_thr_db) || isnan(q_thr_db), q_thr_db = C.q_alarm_db; end
if nargin < 6 || isempty(drop), drop = false; end
if nargin < 7, budget = []; end
if nargin < 8 || isempty(mmse_thr_db), mmse_thr_db = C.rule_mmse_db; end
if nargin < 9 || isempty(slot_on), slot_on = true; end
if nargin < 10, burst_action = {}; end
if ~isempty(burst_action), check_burst(burst_action); end
sep = mmse_gain_db >= mmse_thr_db;
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
        if ~isempty(burst_action)
            action = burst_action{1 + sep};
            reason = sprintf('broadband bursts%s: %s, chosen on validation', ternary(sep, ' from one direction', ''), action);
        end
    case 'path_loss'
        action = 'rate_reduce+power_control'; reason = 'weak signal: largest link-budget gain';
        if ~isempty(budget), [action, reason] = budget_match(budget); end
    case {'antenna_fault', 'airframe_shadowing'}
        action = 'power_control';     reason = 'one branch lost: raise the link budget';
        if sep, action = 'spatial_diversity+power_control'; reason = [reason ', and null the separable interferer']; end
    case {'benign_interference', 'none'}
        action = 'no_action';         reason = 'not an attack: acting would be a false alarm';
    otherwise
        action = 'no_action';         reason = 'unknown class: no class-specific mapping';
end

if strcmp(action, 'no_action') && drop && ~slot && ~strcmp(threat_class, 'benign_interference')
    action = 'power_control'; reason = 'our signal dropped over thermal noise: raise the link budget';
    if degraded, action = 'rate_reduce+power_control'; reason = 'our signal dropped and the link degraded: largest link-budget gain'; end
    if ~isempty(budget), [action, reason] = budget_match(budget); end
elseif strcmp(action, 'no_action') && degraded
    if strcmp(threat_class, 'benign_interference')
        action = 'channel_switch'; reason = 'interference degrades the link: leave the channel';
    elseif strcmp(threat_class, 'none') && slot && slot_on
        action = 'channel_switch'; reason = 'degraded link with interference in the quiet slot: leave the channel';
        if sep, action = 'channel_switch+spatial_diversity'; reason = [reason ', and null it (separable)']; end
    elseif sep
        action = 'spatial_diversity+power_control'; reason = 'degraded link, separable interference: null it';
    else
        action = 'freq_diversity+power_control'; reason = 'link degraded without a known cause: generic diversity';
    end
end
end

function [action, reason] = budget_match(b)
% Link-budget match of a drop: keep the configuration in use when its known gain covers
% the drop, else the link-budget configuration with the smallest gain that does, the
% largest when none does.
if b.current_db >= b.drop_db
    action = b.current; reason = sprintf('the configuration in use covers the %.1f dB drop', b.drop_db);
    return
end
[g, o] = sort(b.gain_db);
k = find(g >= b.drop_db, 1);
if isempty(k), k = numel(g); end
action = b.names{o(k)};
reason = sprintf('our signal dropped %.1f dB: the smallest link-budget gain that covers it (%.1f dB)', b.drop_db, g(k));
end

function check_burst(b)
% Two configurations of the 36, neither no_action.
persistent A
if isempty(A), A = setdiff(policy_actions(), {'no_action'}); end
if ~iscellstr(b) || numel(b) ~= 2 || ~all(ismember(b, A))
    error('rule_based_policy:burst', 'rule_based_policy: the noise-burst answer must be two configurations of the 36 other than no_action');
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
