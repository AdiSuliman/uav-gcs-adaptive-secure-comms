function [a, mem, info] = policy_decide(kind, obs, cfg, mem, PP, agent, opt)
%POLICY_DECIDE  One decision cycle of every decision-layer policy,
%   vectorized over episodes. Used by training, evaluation and deployment.
%
%   kind   'dqn' | 'dqn_esc' | 'rule' | 'rule_esc' | 'table' | 'table_esc' |
%          'blind_esc' | 'random' | 'fixed'
%   obs    link_env observation of the frame just received (receiver measurements)
%   cfg    configuration currently requested (1 x NE); obs.cfg_link, when present,
%          the one the frame was received with
%   mem    policy memory ([] on the first cycle of an episode)
%   agent  trained agent (dqn kinds)
%   opt    fixed (action index, 'fixed'); table (1 x classes action index) and
%          table_unknown (action for 'unknown'), 'table' kinds; rs (RandStream, 'random');
%          monitor (alarm_mode, confirm, drop_db): the policy's own monitor in place of PP's
%
%   Link monitor, alarm confirmation and the agent's observation history:
%   policy_monitor.m (shared). Timing constants: decision_config.m.
%   rule      detected class, predicted MMSE gain and quiet-slot interference (alarm
%             threshold PP.q_thr) -> rule_based_policy.m
%   table     detected class -> the configuration with the best mean reward for
%             that threat on the train pools (policy_table.m); a 'none' or
%             'unknown' class on a degraded link takes table_unknown
%   rule and table commit a proposal after C.dwell consecutive cycles, not within
%   C.hold cycles of the last change reaching the link, and only on a confirmed alarm
%   (the same confirmation as the DQN shield)
%   dqn       argmax of the Q-network over the configurations allowed by the
%             shield (policy_mask.m); switching costs are part of its reward
%   *_esc     escalation: move to the next configuration not yet tried in this
%             incident (DQN: next-highest Q; rule and table: the fixed ladder C.ladder)
%             when the base policy keeps
%             - a configuration it applied while the link stays degraded for C.esc
%               cycles from the first frame received with it
%             - no_action while the alarm stays confirmed for C.esc cycles: an
%               intermittent fault can leave the windowed BER estimate near clean
%               while the threat is on
%   blind_esc the rule with escalation without the detector: every cycle reads as
%             'unknown', so the alarm comes from measured degradation only (what the
%             detection adds to an adaptive recovery)
%   random, fixed: reference policies, no monitor gating ('fixed' at no_action is
%   the link that does not respond)
%
%   info: q (Q-values, dqn kinds), cls, degraded, confirmed, escalated, ber_avg, drop
if nargin < 7, opt = struct(); end
C = decision_config();
if isfield(opt, 'monitor')
    PP.alarm_mode = opt.monitor.alarm_mode; PP.confirm = opt.monitor.confirm; PP.drop_db = opt.monitor.drop_db;
end
NE = numel(cfg); A = PP.actions; nA = numel(A);
na = find(strcmp(A, 'no_action'));
if startsWith(kind, 'blind')
    obs.probs(:) = 0; obs.unknown(:) = true; obs.maha = -Inf(size(obs.unknown));
    kind = strrep(kind, 'blind', 'rule');
end
if isempty(mem), mem = policy_monitor('init', NE, nA); end
[mem, M] = policy_monitor('update', mem, obs, PP, cfg);
base = erase(kind, '_esc');
q = [];
switch base
    case 'dqn'
        st = policy_state(mem, cfg, M.confirmed, nA);
        if isfield(agent, 'dense')
            q = q_dense(agent.dense, st);
        else
            q = double(gather(extractdata(predict(agent.qNetwork, dlarray(single(st), 'CB')))));
        end
        q(~policy_mask(cfg, M.confirmed, mem.since, nA, na)) = -inf;
        [~, a] = max(q, [], 1);
    case {'rule', 'table'}
        a = cfg;
        gain = obs.feat(:, feature_index('mmse_gain')); qi = obs.feat(:, feature_index('q_iot'));
        qt = NaN; if isfield(PP, 'q_thr') && ~isempty(PP.q_thr), qt = PP.q_thr; end
        for i = 1:NE
            if strcmp(base, 'rule')
                p = find(strcmp(A, rule_based_policy(M.cls{i}, M.degraded(i), gain(i), qi(i), qt)), 1);
            else
                p = table_action(M.cls{i}, M.degraded(i), PP, opt, na);
            end
            if p == na || p == cfg(i)
                mem.cand(i) = 0; mem.cand_n(i) = 0;
            else
                if p == mem.cand(i), mem.cand_n(i) = mem.cand_n(i) + 1; else, mem.cand(i) = p; mem.cand_n(i) = 1; end
                if mem.cand_n(i) >= C.dwell && mem.since(i) >= C.hold && M.confirmed(i)
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
    ladder = cellfun(@(x) find(strcmp(A, x)), C.ladder);
    for i = 1:NE
        mem.tried(i, cfg(i)) = true;
        if cfg(i) == na, stuck = mem.conf_n(i) >= C.esc; else, stuck = mem.deg_n(i) >= C.esc; end
        if a(i) == cfg(i) && stuck && mem.since(i) >= C.esc && ~strcmp(M.cls{i}, 'none')
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

mem = policy_monitor('change', mem, a ~= cfg);
info = struct('q', q, 'cls', {M.cls}, 'degraded', M.degraded, 'confirmed', M.confirmed, ...
    'escalated', escalated, 'ber_avg', M.ber_avg', 'drop', M.drop);
end

function p = table_action(cls, degraded, PP, opt, na)
if strcmp(cls, 'unknown')
    p = opt.table_unknown;
else
    p = opt.table(strcmp(PP.classes, cls));
end
if p == na && degraded, p = opt.table_unknown; end
end

function q = q_dense(D, st)
% Q-network as matrix products (dqn_dense.m): z-score input, ReLU hidden layers,
% linear output; single precision as predict.
x = (single(st) - D.mu) ./ D.sd;
for i = 1:numel(D.W) - 1
    x = max(D.W{i} * x + D.b{i}, 0);
end
q = double(D.W{end} * x + D.b{end});
end
