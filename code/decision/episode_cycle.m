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
%        channel gain of every antenna, optional), idle (the record of the idle time before
%        the frame, idle_summary.m, optional), mmse_pred (the predicted MMSE gain over MRC,
%        mmse_predict.m, optional), pkt (the frame pair of the run
%        its coded packet ends on, optional: policy_monitor.m), cfg_link (the
%        configuration the frame was received with, optional: by default the one in
%        use before this cycle, E.cfg, as the console draws its frames)
%   ctx  policy (a policy_decide.m kind), net, ood, feat_mean, feat_std, fs, nv (thermal
%        noise per sample, thermal_nv.m),
%        agent, PP (actions, classes, sps, bps, maha_thr, confirm, alarm_mode,
%        drop_db, cfg_gain_db), na
%        optional: core_rule (true: the rule kinds run on the core action set, rule_core),
%        core (the three-state CNN, console_core('load'): its state is read on the frames
%        of this episode, over the model's window)
%
%   info: cls (top detector class), conf, unknown, prop (configuration chosen
%   this cycle), qv (Q-values for DQN kinds, [] otherwise), switched, cfg,
%   state3 (console_core('state') of the cycle, [] without ctx.core).

if isempty(E), E = struct('cfg', ctx.na, 'mem', [], 'k', 0, 'p3', []); end
E.k = k;

%% Detection and unknown-threat score
X = reshape(single(spec_image(fr.iq, ctx.fs, ctx.nv)), 128, 128, 1, 1);
Xf = ((fr.feat - ctx.feat_mean) ./ ctx.feat_std)';
[probs, maha] = detect_scores(ctx.net, ctx.ood, X, Xf);
[conf, ic] = max(probs);

%% Three-state view of the link
st3 = [];
if isfield(ctx, 'core') && ~isempty(ctx.core)
    E.p3 = [E.p3; spec_scores(ctx.core.net, X)];
    E.p3 = E.p3(max(1, end - ctx.core.N + 1):end, :);   % the window's frames only
    st3 = console_core('read', ctx.core, E.p3);
end

%% Decision
obs = struct('probs', probs(:)', 'unknown', maha < ctx.PP.maha_thr, 'maha', maha, 'feat', fr.feat, 'ber_true', fr.ber);
if isfield(fr, 'gant'), obs.gant = fr.gant(:)'; end
if isfield(fr, 'idle'), obs.idle = fr.idle(:)'; end
if isfield(fr, 'bch'), obs.bch = fr.bch(:)'; end
if isfield(fr, 'mmse_pred'), obs.mmse_pred = fr.mmse_pred; end
if isfield(fr, 'pkt'), obs.pkt = fr.pkt; end
prev = E.cfg;
obs.cfg_link = prev; if isfield(fr, 'cfg_link'), obs.cfg_link = fr.cfg_link; end
opt = struct(); if isfield(ctx, 'core_rule') && ctx.core_rule, opt = console_core('policy_opt'); end
[a, E.mem, d] = policy_decide(ctx.policy, obs, prev, E.mem, ctx.PP, ctx.agent, opt);
E.cfg = a;
qv = d.q; if ~isempty(qv), qv(~isfinite(qv)) = NaN; end
info = struct('cls', ctx.PP.classes{ic}, 'conf', conf, 'unknown', obs.unknown, 'prop', a, 'qv', qv, ...
    'switched', a ~= prev, 'cfg', a, 'state3', st3);
end
