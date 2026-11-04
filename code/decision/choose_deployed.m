function [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound, dqn_rec, dqn_kind)
%CHOOSE_DEPLOYED  The decision-layer policy deployed after validation (train_dqn.m).
%   [deployed, fa_met, ir] = choose_deployed(gate, dqn_up, rule_rec, rule_up, bound, dqn_rec, dqn_kind)
%   gate      the DQN passed its gate (recovery >= rule + escalation with its own monitor,
%             false-alarm bound)
%   dqn_up    one-sided 95% false-alarm bound of the selected DQN
%   rule_rec, rule_up  recovery and false-alarm bound of rule + escalation at every
%             monitor and drop threshold of the grid (NaN bound: not measured)
%   bound     the false-alarm target (KPI 6)
%   dqn_rec   the selected DQN's recovery, on the measure of rule_rec (default Inf: not compared)
%   dqn_kind  'dqn_esc' (default) or 'dqn': the selected DQN with or without escalation
%   The rule setting ir is the best recovery among those within the bound, or among those
%   not measured when none is, else the lowest bound. The DQN when it passed its gate and
%   either no rule setting is within the bound or it recovers at least as much as rule
%   setting ir (every selection on validation: a rule the validation reads better is not set
%   aside), or when no rule setting is within the bound and the DQN's bound is the lower;
%   otherwise rule + escalation on setting ir. fa_met: the deployed policy's bound was
%   measured and is within the target (else the edge map commits no point). deployed:
%   dqn_kind or 'rule_sel'.
if nargin < 6 || isempty(dqn_rec), dqn_rec = Inf; end
if nargin < 7 || isempty(dqn_kind), dqn_kind = 'dqn_esc'; end
ok = find(rule_up <= bound);
if isempty(ok), ok = find(isnan(rule_up)); end
if isempty(ok), [~, ir] = min(rule_up); else, [~, j] = max(rule_rec(ok)); ir = ok(j); end
none_ok = rule_up(ir) > bound;
if (gate && (none_ok || dqn_rec >= rule_rec(ir))) || (none_ok && dqn_up <= rule_up(ir))
    deployed = dqn_kind; up = dqn_up;
else
    deployed = 'rule_sel'; up = rule_up(ir);
end
fa_met = up <= bound;
end
