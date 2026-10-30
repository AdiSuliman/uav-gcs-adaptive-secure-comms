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
%          monitor (alarm_mode, confirm, drop_db and any other decision-time setting,
%          decision_settings.m): the policy's own settings in place of PP's; core (rule,
%          rule_esc, blind_esc): the core action set C.core_actions, the rule from
%          rule_core_policy.m, the escalation over C.ladder_core and the link-budget match
%          over rate_reduce alone; PP.core_wide, when set, the core rule's action for the
%          class jamming (rule_core_policy.m wide_action); PP.core_nb, when set, its action for
%          the class noise_burst (burst_action)
%
%   Link monitor, alarm confirmation and the agent's observation history:
%   policy_monitor.m (shared). Timing constants: decision_config.m.
%   rule      detected class, predicted MMSE gain (obs.mmse_pred, mmse_predict.m: from the
%             frame's known symbols; nulling threshold PP.rule_mmse_db, default
%             C.rule_mmse_db), quiet-slot interference (alarm
%             threshold PP.q_thr; that branch on or off, PP.rule_slot), the monitor's drop
%             alarm and the link budget (its drop without the configurations' known gains,
%             the configuration in use and the gains of power_control, rate_reduce and
%             both, config_gain_db.m) -> rule_based_policy.m; PP.rule_nb, when set, the answer
%             to the class noise_burst chosen on validation (burst_action, train_dqn.m)
%   table     detected class -> the configuration with the best mean reward for
%             that threat on the train pools (policy_table.m); a 'none' or
%             'unknown' class on a degraded link takes table_unknown
%   rule and table commit a proposal after C.dwell consecutive cycles (PP.rule_dwell 'run',
%   the default), not within C.hold cycles of the last change reaching the link, and only
%   on a confirmed alarm (the same confirmation as the DQN shield). With PP.rule_dwell
%   'group' (chosen on validation, train_dqn.m) a proposal commits when its group, the
%   threat-specific elements it holds (channel_switch, freq_diversity, fec_interleave,
%   spatial_diversity; link-budget configurations one group), was proposed in at least
%   C.dwell of the last C.dwell_n cycles (M-of-N integration, Barajas et al.; an
%   intermittent threat alternates its cycles' proposals), unless the configuration in use
%   already holds its elements and at least its known gain (no regress to a weaker one) or
%   the escalation tried it in this incident. The tried check is the group dwell's: with
%   'run' the class answer can commit again after an escalation left it, and train_dqn.m
%   picks between the two dwells on validation (rule + escalation), which every rule kind,
%   the core and blind ones included, then runs (decision_settings.m)
%   dqn       argmax of the Q-network over the configurations allowed by the
%             shield (policy_mask.m); switching costs are part of its reward. With
%             PP.lb_complete (stored with the agent, decision_settings.m; default off) the
%             argmax is completed by the link budget, before the escalation (lb_complete.m):
%             a confirmed loss of our own signal that the proposal's known gain does not cover
%             gets the link-budget configuration that does, the proposal's frequency and
%             space choice kept (info.lb marks the episodes it changed)
%   *_esc     escalation: move to the next configuration not yet tried in this
%             incident (DQN: next-highest Q; rule and table: the fixed ladder C.ladder)
%             when the base policy keeps
%             - a configuration it applied while the link stays degraded for C.esc
%               cycles from the first frame received with it
%             - no_action while the alarm stays confirmed for C.esc cycles: a threat
%               the detector names can leave the windowed BER estimate near clean (a
%               jammer between our packets, a lost branch the other antennas cover)
%               while it is on
%             and only on a confirmed alarm, as every change of the rule and the table
%             and the DQN's shield, and never while the class reads none. With
%             PP.esc_drop (chosen on validation) a confirmed drop alarm read as none
%             escalates too: out of no_action, or out of a configuration whose known gain
%             no longer covers the drop; its first step is the link-budget configuration
%             with the smallest known gain covering the drop (rule_based_policy.m's budget
%             match), if not tried yet
%   blind_esc the rule with escalation without the detector: every cycle reads as
%             'unknown' whatever PP.unk_mode (the fused class from the receiver cues and
%             the lost-branch latch included), so the alarm comes from measured
%             degradation only (what the detection adds to an adaptive recovery)
%   random, fixed: reference policies, no monitor gating ('fixed' at no_action is
%   the link that does not respond)
%
%   info: q (Q-values, dqn kinds), cls, degraded, confirmed, escalated, ber_avg, drop, drop_alarm;
%   deg_quiet with the monitor's deg_mode 'win_q_gate'
if nargin < 7, opt = struct(); end
C = decision_config();
if isfield(opt, 'monitor'), PP = decision_settings(PP, opt.monitor); end
NE = numel(cfg); A = PP.actions; nA = numel(A);
na = find(strcmp(A, 'no_action'));
if startsWith(kind, 'blind')
    obs.probs(:) = 0; obs.unknown(:) = true; obs.maha = -Inf(size(obs.unknown));
    PP.unk_mode = 'all';                              % no class survives, fused or latched
    kind = strrep(kind, 'blind', 'rule');
end
if isempty(mem), mem = policy_monitor('init', NE, nA); end
[mem, M] = policy_monitor('update', mem, obs, PP, cfg);
base = erase(kind, '_esc');
core = isfield(opt, 'core') && opt.core;
if core && ~strcmp(base, 'rule')
    error('policy_decide:core', 'policy_decide: the core action set is a rule option, not of %s', kind);
end
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
        gain = obs_mmse_pred(obs, NE); qi = obs.feat(:, feature_index('q_iot'));
        qt = NaN; if isfield(PP, 'q_thr') && ~isempty(PP.q_thr), qt = PP.q_thr; end
        mt = C.rule_mmse_db; if isfield(PP, 'rule_mmse_db') && ~isempty(PP.rule_mmse_db), mt = PP.rule_mmse_db; end
        so = true; if isfield(PP, 'rule_slot') && ~isempty(PP.rule_slot), so = PP.rule_slot; end
        cw = ''; if isfield(PP, 'core_wide') && ~isempty(PP.core_wide), cw = PP.core_wide; end
        cn = ''; if isfield(PP, 'core_nb') && ~isempty(PP.core_nb), cn = PP.core_nb; end
        nb = {}; if isfield(PP, 'rule_nb') && ~isempty(PP.rule_nb), nb = PP.rule_nb; end
        grp = isfield(PP, 'rule_dwell') && strcmp(PP.rule_dwell, 'group');
        if grp && (~isfield(mem, 'ph') || size(mem.ph, 1) ~= NE), mem.ph = zeros(NE, C.dwell_n); end
        gk = config_gain_db(PP); [gm, gid] = action_groups(A);
        lb = find(ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'}));   % link-budget configurations
        if core, lb = find(strcmp(A, 'rate_reduce')); end
        bud = struct('drop_db', 0, 'current', '', 'current_db', 0, 'names', {A(lb)}, 'gain_db', gk(lb));
        for i = 1:NE
            if core
                bud.drop_db = M.drop(i); bud.current = A{cfg(i)}; bud.current_db = gk(cfg(i));
                p = find(strcmp(A, rule_core_policy(M.cls{i}, M.degraded(i), qi(i), qt, M.drop_alarm(i), bud, so, cw, cn)), 1);
            elseif strcmp(base, 'rule')
                bud.drop_db = M.drop(i); bud.current = A{cfg(i)}; bud.current_db = gk(cfg(i));
                p = find(strcmp(A, rule_based_policy(M.cls{i}, M.degraded(i), gain(i), qi(i), qt, M.drop_alarm(i), bud, mt, ...
                    so, nb)), 1);
            else
                p = table_action(M.cls{i}, M.degraded(i), PP, opt, na);
            end
            if grp                                       % m of the last n proposals of one group
                mem.ph(i, :) = [mem.ph(i, 2:end), gid(p)];
                held = bitand(gm(p), gm(cfg(i))) == gm(p) && gk(cfg(i)) >= gk(p);   % the configuration in use covers it
                if p ~= na && p ~= cfg(i) && ~held && ~mem.tried(i, p) && sum(mem.ph(i, :) == gid(p)) >= C.dwell ...
                        && mem.since(i) >= C.hold && M.confirmed(i)
                    a(i) = p; mem.ph(i, :) = 0;
                end
            elseif p == na || p == cfg(i)
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

lbc = false(1, NE);
lbon = strcmp(base, 'dqn') && isfield(PP, 'lb_complete') && ~isempty(PP.lb_complete) && PP.lb_complete;
if lbon, [a, lbc] = lb_complete(a, cfg, M, mem, PP); end   % after the argmax, before the escalation

escalated = false(1, NE);
if endsWith(kind, '_esc')
    ladder = cellfun(@(x) find(strcmp(A, x)), C.ladder);
    ed = isfield(PP, 'esc_drop') && ~isempty(PP.esc_drop) && PP.esc_drop;
    gk = config_gain_db(PP);
    lb = find(ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'}));
    if core, ladder = cellfun(@(x) find(strcmp(A, x)), C.ladder_core); lb = find(strcmp(A, 'rate_reduce')); end
    for i = 1:NE
        mem.tried(i, cfg(i)) = true;
        if cfg(i) == na, stuck = mem.conf_n(i) >= C.esc; else, stuck = mem.deg_n(i) >= C.esc; end
        none = strcmp(M.cls{i}, 'none');
        byd = ed && none && M.drop_alarm(i) && (cfg(i) == na || gk(cfg(i)) < M.drop(i));   % a drop the configuration does not cover
        if a(i) == cfg(i) && stuck && mem.since(i) >= C.esc && M.confirmed(i) && (~none || byd)
            if byd                                       % the link-budget match first
                [g, o] = sort(gk(lb)); j = find(g >= M.drop(i), 1); if isempty(j), j = numel(g); end
                if ~mem.tried(i, lb(o(j))), a(i) = lb(o(j)); escalated(i) = true; continue; end
            end
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
    'escalated', escalated, 'ber_avg', M.ber_avg', 'drop', M.drop, 'drop_alarm', M.drop_alarm);
if isfield(M, 'deg_quiet'), info.deg_quiet = M.deg_quiet; end   % degraded, no RF evidence (deg_mode 'win_q_gate')
if lbon, info.lb = lbc; end                                      % changed by the link-budget completion
end

function [gm, gid] = action_groups(A)
% Per configuration, its threat-specific elements as a bit mask (channel_switch,
% freq_diversity, fec_interleave, spatial_diversity) and its proposal group (the mask; a
% link-budget configuration 16; no_action 0).
el = {'channel_switch', 'freq_diversity', 'fec_interleave', 'spatial_diversity'};
gm = zeros(1, numel(A));
for a = 1:numel(A)
    p = strsplit(A{a}, '+');
    gm(a) = sum(2 .^ (find(ismember(el, p)) - 1));
end
gid = gm; gid(gm == 0) = 16; gid(strcmp(A, 'no_action')) = 0;
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
