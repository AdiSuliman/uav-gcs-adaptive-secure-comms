function [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound)
%CHOOSE_DEPLOYED  The decision-layer policy deployed after validation (train_dqn.m).
%   [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound)
%   gate      the DQN passed its gate (recovery >= rule + escalation, false-alarm bound)
%   dqn_up    one-sided 95% false-alarm bound of the selected DQN
%   rule_rec, rule_up  recovery and false-alarm bound of rule + escalation at every
%             monitor and drop threshold of the grid (NaN bound: not measured, taken
%             as met)
%   bound     the false-alarm target (KPI 6)
%   The DQN with escalation when it passed its gate; otherwise rule + escalation on the
%   setting ir with the best recovery among those within the bound; when none is, the
%   policy with the lowest bound. fa_met: the deployed policy met the bound (else the
%   edge map commits no point). deployed: 'dqn_esc' or 'rule_sel'.
ok = find(rule_up <= bound | isnan(rule_up));
if isempty(ok), [~, ir] = min(rule_up); else, [~, j] = max(rule_rec(ok)); ir = ok(j); end
if gate
    deployed = 'dqn_esc'; fa_met = true;
elseif ~isempty(ok)
    deployed = 'rule_sel'; fa_met = true;
elseif dqn_up <= rule_up(ir)
    deployed = 'dqn_esc'; fa_met = dqn_up <= bound;
else
    deployed = 'rule_sel'; fa_met = false;
end
end
