function B = burst_candidates(rx)
%BURST_CANDIDATES  Candidates of the rule's answer to a noise burst, chosen on validation in
%   C2 (train_dqn.m), cheapest first: the running cost of the reward (link_env.m K.cost:
%   goodput given up, transmit power, adaptive combining), a configuration with
%   channel_switch after its twin without it (a hop).
%   B = burst_candidates(rx): rx the pools' decoder (fec_rx_of.m). On pools decoded with the
%   D78 erasure rules every candidate is uncoded: those rules erase the symbols the code needs
%   under bursts (docs/noise_burst_protocol.md), so a coded entry there rests on a known
%   bias. On pools decoded with per-symbol jammer state information the coded answers join.
%   ns, sep   the answers when the interferer is not separable and when it is (the
%             predicted MMSE gain against the nulling threshold, rule_based_policy.m)
%   core      the core rule's (rule_core_policy.m): the only core actions with an effect on
%             a broadband threat, and channel_switch beside it for an in-channel component
%   start     {ns, sep} in force before the steps; core_start the core rule's
%   reference the class mapping (rule_based_policy.m with one argument): reported, never a
%             candidate on D78 pools
if nargin < 1 || isempty(rx), rx = struct('mode', 'd78'); end
B.ns = {'power_control', 'rate_reduce', 'rate_reduce+power_control', 'channel_switch+rate_reduce+power_control'};
B.sep = {'spatial_diversity', 'spatial_diversity+power_control', 'spatial_diversity+rate_reduce+power_control'};
B.core = {'rate_reduce', 'channel_switch+rate_reduce'};
if strcmp(rx.mode, 'jsi')
    B.ns = [B.ns(1), {'power_control+fec_interleave'}, B.ns(2:end)];
    B.sep = [B.sep(1:2), {'spatial_diversity+fec_interleave'}, B.sep(3)];
end
B.start = {'rate_reduce+power_control', 'spatial_diversity+power_control'};
B.core_start = 'rate_reduce';
B.reference = {'power_control+fec_interleave', 'spatial_diversity+fec_interleave'};
B.mode = rx.mode;
end
