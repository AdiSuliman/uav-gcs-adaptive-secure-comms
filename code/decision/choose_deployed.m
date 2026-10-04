function [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound)
%CHOOSE_DEPLOYED  The decision-layer policy deployed after validation (train_dqn.m).
%   [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound)
%   gate      the DQN passed its gate (recovery >= rule + escalation, false-alarm bound)
%   dqn_up    one-sided 95% false-alarm bound of the selected DQN
%   rule_rec, rule_up  recovery and false-alarm bound of rule + escalation at every
%             monitor and drop threshold of the grid (NaN bound: not measured)
%   bound     the false-alarm target (KPI 6)
%   The DQN with escalation when it passed its gate; otherwise rule + escalation on the
%   setting ir with the best recovery among those within the bound, or among those not
%   measured when none is; when neither, the policy with the lowest bound. fa_met: the
%   deployed policy's bound was measured and is within the target (else the edge map
%   commits no point). deployed: 'dqn_esc' or 'rule_sel'.
ok = find(rule_up <= bound);
if isempty(ok), ok = find(isnan(rule_up)); end
if isempty(ok), [~, ir] = min(rule_up); else, [~, j] = max(rule_rec(ok)); ir = ok(j); end
if gate || (rule_up(ir) > bound && dqn_up <= rule_up(ir))
    deployed = 'dqn_esc'; up = dqn_up;
else
    deployed = 'rule_sel'; up = rule_up(ir);
end
fa_met = up <= bound;
end
