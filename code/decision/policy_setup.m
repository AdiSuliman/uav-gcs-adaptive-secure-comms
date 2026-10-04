function [kind, ag, opt] = policy_setup(name, Q, sel, fixed_best, fixed_mmse, tab, na)
%POLICY_SETUP  Policy kind, agent and options of one evaluated policy (rollout_policy.m).
%   name        policy of evaluate_policies.m: none, random, fixed_mmse, fixed, rule,
%               rule_esc, blind_esc, table, dqn_g<k> (DQN of discount factor k),
%               dqn_esc (the selected DQN with escalation), rule_sel (rule + escalation
%               on the monitor train_dqn.m chose for it, the fallback), oracle
%   Q           data/trained_dqn.mat: agent, agents, rule_sel
%   sel         index of the selected DQN in Q.agents
%   fixed_best  configuration of the best fixed policy; fixed_mmse that of always-on MMSE
%   tab         class -> configuration table (policy_table.m)
%   na          index of no_action
kind = name; ag = Q.agent; opt = struct();
switch name
    case 'none',       kind = 'fixed'; opt.fixed = na;
    case 'fixed',      opt.fixed = fixed_best;
    case 'fixed_mmse', kind = 'fixed'; opt.fixed = fixed_mmse;
    case 'table',      opt = tab;
    case 'dqn_esc',    ag = Q.agents{sel};
    case 'rule_sel',   kind = 'rule_esc'; opt.monitor = Q.rule_sel;
end
if startsWith(name, 'dqn_g'), ag = Q.agents{sscanf(name, 'dqn_g%d')}; kind = 'dqn'; end
end
