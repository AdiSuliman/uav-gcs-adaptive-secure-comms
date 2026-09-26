function [E, info] = episode_cycle(E, k, fr, ctx)
%EPISODE_CYCLE  One decision cycle of a live episode (demo_gui.m) (D46).
%   Detector, unknown-threat score and the decision layer exactly as in the
%   evaluation: link_features.m over the episode's own history, cnn_scores.m,
%   ood_scores.m (Mahalanobis below ctx.PP.maha_thr = unknown), then
%   policy_decide.m with its shared link monitor, confirmation, shield and
%   hysteresis.
%
%   E    episode state; pass [] on the first cycle
%   k    cycle index (1-based)
%   fr   received frame: fields iq, ber, rssi, plr, sinr, env_corr, iot
%   ctx  fields: policy (a policy_decide.m kind), net, ood, feat_mean, feat_std,
%        fs, agent, PP (actions, classes, sps, bps, maha_thr), na, tw
%        (temporal window), frame_dur
%
%   info: cls (top detector class), conf, unknown, prop (configuration chosen
%   this cycle), qv (Q-values for DQN kinds, [] otherwise), switched, cfg.

if isempty(E)
    E = struct('cfg', ctx.na, 'mem', [], ...
        'ber', [], 'rssi', [], 'plr', [], 'sinr', [], 'env_corr', [], 'iot', []);
end
E.ber(k) = fr.ber; E.rssi(k) = fr.rssi; E.plr(k) = fr.plr; E.sinr(k) = fr.sinr; E.env_corr(k) = fr.env_corr; E.iot(k) = fr.iot;

%% Detection and unknown-threat score
raw = link_features(E, k, ctx.tw, ctx.frame_dur);
X = reshape(single(spec_image(fr.iq, ctx.fs)), 128, 128, 1, 1);
Xf = ((raw - ctx.feat_mean) ./ ctx.feat_std)';
probs = cnn_scores(ctx.net, X, Xf);
maha = ood_scores(ctx.net, ctx.ood, X, Xf);
[conf, ic] = max(probs);

%% Decision
obs = struct('probs', probs(:)', 'unknown', maha < ctx.PP.maha_thr, 'feat', raw, 'ber', fr.ber);
prev = E.cfg;
[a, E.mem, d] = policy_decide(ctx.policy, obs, prev, E.mem, ctx.PP, ctx.agent);
E.cfg = a;
qv = d.q; if ~isempty(qv), qv(~isfinite(qv)) = NaN; end
info = struct('cls', ctx.PP.classes{ic}, 'conf', conf, 'unknown', obs.unknown, 'prop', a, 'qv', qv, ...
    'switched', a ~= prev, 'cfg', a);
end
