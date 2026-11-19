function [y, t, st] = lat_cycle(x, S, P, st)
%LAT_CYCLE  One decision cycle of KPI 7 on one received frame, as deployed: the timed cycle
%   of measure_latency.m and the cycle kpi7_guard.m compares.
%   [y, t, st] = lat_cycle(x, S, P, st)
%   x   a frame of measure_latency.m: iq, M, k, iqa, sy
%   S   the cycle's settings: p0, fs, tw (link-feature window), D (net, ood), mu, sd, PPm,
%       dev ('gpu' | 'cpu', the detector's device), ug (synchronize the GPU before the clock is
%       read), gdev (the GPU device, read once), det_first (true: the detector before the
%       predictor, a diagnostic order; the two read nothing of each other)
%   P   the chain's policy: kind, agent, opt (policy_decide.m)
%   st  the chain's state: cfg, mem (mem [] on a pass's first cycle)
%   y   the cycle's outputs: img, raw, idle, g, probs, maha, cfg, mem, info
%   t   1 x 6 seconds: spectrogram, link features, MMSE predictor, detector, policy, and the
%       wall clock of the whole cycle. The glue between the components counts in the one it
%       serves: the detector's input tensors in the detector, the observation in the policy.
w0 = tic;
t0 = tic; img = spec_image(x.iq, S.fs, thermal_nv(S.p0)); t_spec = toc(t0);
t0 = tic; raw = link_features(x.M, x.k, S.tw); iq_rec = idle_record(x.M, x.k, S.p0); t_feat = toc(t0);
if S.det_first
    t0 = tic; X = reshape(single(img), 128, 128, 1, 1); Fn = ((raw - S.mu) ./ S.sd)';
    [probs, maha] = detect_scores(S.D.net, S.D.ood, X, Fn, S.dev); if S.ug, wait(S.gdev); end; t_det = toc(t0);
    t0 = tic; g = mmse_predict(x.iqa, S.p0, x.sy); t_pred = toc(t0);
else
    t0 = tic; g = mmse_predict(x.iqa, S.p0, x.sy); t_pred = toc(t0);
    t0 = tic; X = reshape(single(img), 128, 128, 1, 1); Fn = ((raw - S.mu) ./ S.sd)';
    [probs, maha] = detect_scores(S.D.net, S.D.ood, X, Fn, S.dev); if S.ug, wait(S.gdev); end; t_det = toc(t0);
end
t0 = tic;
obs = struct('probs', probs(:)', 'unknown', maha < S.PPm.maha_thr, 'maha', maha, 'feat', raw, ...
    'gant', x.M.gain_ant(:, x.k)', 'idle', iq_rec);
if isfield(x.M, 'bch'), obs.bch = x.M.bch(:, x.k)'; end
obs.mmse_pred = g(end);
[cfg, mem, info] = policy_decide(P.kind, obs, st.cfg, st.mem, S.PPm, P.agent, P.opt);
t_pol = toc(t0);
t = [t_spec, t_feat, t_pred, t_det, t_pol, toc(w0)];
st.cfg = cfg; st.mem = mem;
y = struct('img', img, 'raw', raw, 'idle', iq_rec, 'g', g, 'probs', probs, 'maha', maha, 'cfg', cfg, ...
    'mem', mem, 'info', info);
end

function r = idle_record(M, k, p)
% The record of the idle time before frame k from that time's RSSI samples (idle_summary.m).
r = nan(1, numel(idle_summary('names')));
if isfield(M, 'idle_R') && ~isempty(M.idle_R), r = idle_summary(double(M.idle_R(:, :, k)), p); end
end
