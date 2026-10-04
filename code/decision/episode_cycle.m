function [E, info] = episode_cycle(E, k, fr, ctx)
%EPISODE_CYCLE  One decision cycle of a live episode (demo_gui.m).
%   Detector, unknown-threat score and decision layer as in the evaluation:
%   detect_scores.m on the frame's spectrogram and link features (score below
%   ctx.PP.maha_thr = unknown), then policy_decide.m with its link monitor,
%   confirmation, shield and hysteresis.
%
%   E    episode state; pass [] on the first cycle
%   k    cycle index (1-based)
%   fr   received frame: iq, ber (true BER, display only), feat (link_features.m
%        of the frame within its own run, as in the frame pools), gant (mean
%        channel gain of every antenna, optional), pkt (its coded packet, two
%        frames of the run, optional: policy_monitor.m)
%   ctx  policy (a policy_decide.m kind), net, ood, feat_mean, feat_std, fs,
%        agent, PP (actions, classes, sps, bps, maha_thr, confirm, alarm_mode,
%        drop_db), na
%
%   info: cls (top detector class), conf, unknown, prop (configuration chosen
%   this cycle), qv (Q-values for DQN kinds, [] otherwise), switched, cfg.

if isempty(E), E = struct('cfg', ctx.na, 'mem', [], 'k', 0); end
E.k = k;

%% Detection and unknown-threat score
X = reshape(single(spec_image(fr.iq, ctx.fs)), 128, 128, 1, 1);
Xf = ((fr.feat - ctx.feat_mean) ./ ctx.feat_std)';
[probs, maha] = detect_scores(ctx.net, ctx.ood, X, Xf);
[conf, ic] = max(probs);

%% Decision
obs = struct('probs', probs(:)', 'unknown', maha < ctx.PP.maha_thr, 'maha', maha, 'feat', fr.feat, 'ber_true', fr.ber);
if isfield(fr, 'gant'), obs.gant = fr.gant(:)'; end
if isfield(fr, 'pkt'), obs.pkt = fr.pkt; end
prev = E.cfg;
[a, E.mem, d] = policy_decide(ctx.policy, obs, prev, E.mem, ctx.PP, ctx.agent);
E.cfg = a;
qv = d.q; if ~isempty(qv), qv(~isfinite(qv)) = NaN; end
info = struct('cls', ctx.PP.classes{ic}, 'conf', conf, 'unknown', obs.unknown, 'prop', a, 'qv', qv, ...
    'switched', a ~= prev, 'cfg', a);
end
