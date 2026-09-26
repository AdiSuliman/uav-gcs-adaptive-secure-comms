function [a, mem, info] = policy_decide(kind, obs, cfg, mem, PP, agent, opt)
%POLICY_DECIDE  One decision cycle of every decision-layer policy (D44, D45),
%   vectorized over episodes. Used by training, evaluation and deployment.
%
%   kind   'dqn' | 'dqn_esc' | 'rule' | 'rule_esc' | 'table' | 'table_esc' |
%          'random' | 'fixed'
%   obs    link_env observation of the frame just received
%   cfg    configuration currently applied (1 x NE)
%   mem    policy memory ([] on the first cycle of an episode)
%   agent  trained agent (dqn kinds)
%   opt    fixed (action index, 'fixed'); table (1 x 9 action index per detector
%          class) and table_unknown (action for 'unknown'), 'table' kinds; rs
%          (RandStream, 'random')
%
%   Link monitor and alarm confirmation: policy_monitor.m (shared).
%   rule      detected class -> rule_based_policy.m
%   table     detected class -> the configuration with the best mean reward for
%             that threat on the train pools (evaluate_policies.m); a 'none' or
%             'unknown' class on a degraded link takes table_unknown
%   rule and table commit a proposal after DWELL = 2 consecutive cycles and not
%   within HOLD = 3 cycles of the last change
%   dqn       argmax of the Q-network over the configurations allowed by the
%             shield (policy_mask.m); switching costs are part of its reward
%   *_esc     escalation: if the link stays degraded for ESC = 3 cycles in the
%             same configuration and the base policy keeps it, move to the next
%             configuration not yet tried in this incident (DQN: next-highest Q;
%             rule and table: fixed ladder)
%   random, fixed: reference policies, no monitor gating
%
%   info: q (Q-values, dqn kinds), cls, degraded, confirmed, escalated, ber_avg
if nargin < 7, opt = struct(); end
NE = numel(cfg); A = PP.actions; nA = numel(A);
na = find(strcmp(A, 'no_action'));
DWELL = 2; HOLD = 3; ESC = 3;
if isempty(mem), mem = policy_monitor('init', NE, nA); end
[mem, M] = policy_monitor('update', mem, obs, PP);
base = erase(kind, '_esc');
q = [];
switch base
    case 'dqn'
        st = policy_state(obs, cfg, mem.since, M.ber_avg, M.confirmed, PP);
        q = double(gather(extractdata(predict(agent.qNetwork, dlarray(single(st), 'CB')))));
        q(~policy_mask(cfg, M.confirmed, nA, na)) = -inf;
        [~, a] = max(q, [], 1);
    case {'rule', 'table'}
        a = cfg;
        for i = 1:NE
            if strcmp(base, 'rule')
                p = find(strcmp(A, rule_based_policy(M.cls{i}, M.ber_avg(i), M.ebno_est(i))), 1);
            else
                p = table_action(M.cls{i}, M.degraded(i), PP, opt, na);
            end
            if p == na || p == cfg(i)
                mem.cand(i) = 0; mem.cand_n(i) = 0;
            else
                if p == mem.cand(i), mem.cand_n(i) = mem.cand_n(i) + 1; else, mem.cand(i) = p; mem.cand_n(i) = 1; end
                if mem.cand_n(i) >= DWELL && mem.since(i) >= HOLD
                    a(i) = p; mem.cand(i) = 0; mem.cand_n(i) = 0;
                end
            end
        end
    case 'random'
        a = randi(opt.rs, nA, 1, NE);
    case 'fixed'
        a = opt.fixed * ones(1, NE);
    otherwise
        error('policy_decide: unknown policy %s', kind);
end

escalated = false(1, NE);
if endsWith(kind, '_esc')
    ladder = cellfun(@(x) find(strcmp(A, x)), {'spatial_diversity', 'spatial_diversity+power_control', ...
        'freq_diversity+fec_interleave', 'channel_switch+rate_reduce', 'spatial_diversity+rate_reduce', ...
        'rate_reduce+power_control'});
    for i = 1:NE
        mem.tried(i, cfg(i)) = true;
        if a(i) == cfg(i) && mem.deg_n(i) >= ESC && mem.since(i) >= ESC && ~strcmp(M.cls{i}, 'none')
            if ~isempty(q)
                qi = q(:, i); qi(mem.tried(i, :)) = -inf; qi(na) = -inf;
                [qm, b] = max(qi);
                if isfinite(qm), a(i) = b; escalated(i) = true; end
            else
                b = ladder(find(~mem.tried(i, ladder), 1));
                if ~isempty(b), a(i) = b; escalated(i) = true; end
            end
        end
    end
end

ch = a ~= cfg;
mem.since(ch) = 0; mem.since(~ch) = mem.since(~ch) + 1;
info = struct('q', q, 'cls', {M.cls}, 'degraded', M.degraded, 'confirmed', M.confirmed, ...
    'escalated', escalated, 'ber_avg', M.ber_avg');
end

function p = table_action(cls, degraded, PP, opt, na)
if strcmp(cls, 'unknown')
    p = opt.table_unknown;
else
    p = opt.table(strcmp(PP.classes, cls));
end
if p == na && degraded, p = opt.table_unknown; end
end
