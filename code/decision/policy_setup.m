function [kind, ag, opt] = policy_setup(name, Q, sel, fixed_best, fixed_mmse, tab, na)
%POLICY_SETUP  Policy kind, agent and options of one evaluated policy (rollout_policy.m).
%   name        policy of evaluate_policies.m: none, random, fixed_mmse, fixed, rule,
%               rule_esc, blind_esc, table, dqn_g<k> (DQN of discount factor k),
%               dqn_esc (the selected DQN with escalation), dqn (the selected DQN without
%               it, when train_dqn.m deployed it so), rule_sel (rule + escalation with the
%               monitor and settings train_dqn.m chose for it, the fallback), rule_core and
%               blind_core (rule_esc and blind_esc on the core action set, opt.core,
%               rule_core_policy.m), oracle
%               Any of them with the suffix _norelm or _nos1g is the same policy with the release on
%               evidence (release_m) or the rule's lost-branch gate (s1_gate) switched off, with _relm
%               or _s1g switched on: the descriptive row beside the deployed setting.
%   Q           data/trained_dqn.mat: agent, agents, rule_sel
%   sel         index of the selected DQN in Q.agents
%   fixed_best  configuration of the best fixed policy; fixed_mmse that of always-on MMSE
%   tab         class -> configuration table (policy_table.m)
%   na          index of no_action
SFX = {'_norelm', 'release_m', false; '_nos1g', 's1_gate', false; '_relm', 'release_m', true; '_s1g', 's1_gate', true};
sfx = 0;
for t = 1:size(SFX, 1)
    if endsWith(name, SFX{t, 1}), sfx = t; name = erase(name, SFX{t, 1}); break; end
end
kind = name; ag = Q.agent; opt = struct();
switch name
    case 'none',       kind = 'fixed'; opt.fixed = na;
    case 'fixed',      opt.fixed = fixed_best;
    case 'fixed_mmse', kind = 'fixed'; opt.fixed = fixed_mmse;
    case 'table',      opt = tab;
    case 'dqn_esc',    ag = Q.agents{sel};
    case 'rule_sel',   kind = 'rule_esc'; opt.monitor = Q.rule_sel;
    case 'rule_core',  kind = 'rule_esc'; opt.core = true;
    case 'blind_core', kind = 'blind_esc'; opt.core = true;
end
if startsWith(name, 'dqn_g'), ag = Q.agents{sscanf(name, 'dqn_g%d')}; kind = 'dqn'; end
if sfx > 0
    if ~isfield(opt, 'monitor') || ~isstruct(opt.monitor), opt.monitor = struct(); end
    opt.monitor.(SFX{sfx, 2}) = SFX{sfx, 3};
end
end
