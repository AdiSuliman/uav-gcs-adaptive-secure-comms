function [E, info] = episode_cycle(E, k, fr, ctx)
%EPISODE_CYCLE  One decision cycle of the episodic closed loop (D31, D37).
%   Shared by run_closed_loop_episodes.m and the continuous-episode view of
%   demo_gui.m, so both apply the same detection, policy and hysteresis.
%
%   E    episode state; pass [] on the first cycle
%   k    cycle index (1-based)
%   fr   received frame: fields iq, ber, rssi, plr, sinr, env_corr, iot
%   ctx  fields: ebno, policy ('dqn' | 'rule'), dwell, hold, net, classes,
%        feat_mean, feat_std, fs, agent, actions, na, tw (temporal window),
%        frame_dur
%
%   The detector classifies the frame with causal temporal features over the
%   episode's own history. The policy proposes an action; no_action or the
%   current configuration keeps things as they are. A new configuration is
%   committed after DWELL consecutive proposals and not within HOLD cycles of
%   the previous switch.
%
%   info: cls, conf, prop (proposed action index), qv (DQN Q-values, [] for
%   the rule), switched (a new configuration was committed this cycle), cfg.

if isempty(E)
    E = struct('cfg', ctx.na, 'last_switch', -inf, 'cand', 0, 'cand_n', 0, ...
        'ber', [], 'rssi', [], 'plr', [], 'sinr', [], 'env_corr', [], 'iot', []);
end
E.ber(k) = fr.ber; E.rssi(k) = fr.rssi; E.plr(k) = fr.plr; E.sinr(k) = fr.sinr; E.env_corr(k) = fr.env_corr; E.iot(k) = fr.iot;

%% Detection
raw = link_features(E, k, ctx.tw, ctx.frame_dur);
[cls, conf] = detect_frame(ctx.net, ctx.classes, fr.iq, raw, ctx.feat_mean, ctx.feat_std, ctx.fs);

%% Policy
qv = [];
if strcmp(ctx.policy, 'dqn')
    st = build_dqn_state(cls, fr.ber, fr.rssi, ctx.ebno, fr.plr);
    qv = gather(extractdata(predict(ctx.agent.qNetwork, dlarray(single(st), 'CB'))));
    [~, prop] = max(qv);
else
    prop = find(strcmp(ctx.actions, rule_based_policy(cls, fr.ber, ctx.ebno)), 1);
end

%% Dwell / hysteresis
switched = false;
if prop == ctx.na || prop == E.cfg
    E.cand = 0; E.cand_n = 0;
else
    if prop == E.cand, E.cand_n = E.cand_n + 1; else, E.cand = prop; E.cand_n = 1; end
    if E.cand_n >= ctx.dwell && (k - E.last_switch) >= ctx.hold
        E.cfg = prop; E.last_switch = k; E.cand = 0; E.cand_n = 0;
        switched = true;
    end
end

info = struct('cls', cls, 'conf', conf, 'prop', prop, 'qv', qv, 'switched', switched, 'cfg', E.cfg);
end
