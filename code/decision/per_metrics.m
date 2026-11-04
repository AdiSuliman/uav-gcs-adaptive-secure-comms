function M = per_metrics(fer, post, gap, rplr, gpl, t_conf, n_run)
%PER_METRICS  Packet error rate, delivered payload and recovery from detection, per episode.
%   fer, post, gap, rplr, gpl  T x NE per cycle: the frame's true packet loss (CRC), after the
%          onset, coded-link gap (no coded packet decoded yet, link_env.m fec_gap), packet loss
%          restored (<= 2x clean + one loss event, link_env.m restored_plr), goodput factor of
%          the configuration the frame was received with (PP.gp)
%   t_conf 1 x NE cycles from the onset frame to the frame of the first confirmed alarm (NaN never)
%   n_run  cycles the packet loss must stay restored (the recovery window)
%   M.per_post   mean packet loss over the frames after the onset that carry a packet (gap
%                frames left out, as lost_rec in rollout_policy.m); NaN without such a frame
%   M.dlv_post   delivered payload after the onset as a share of the nominal payload rate:
%                mean of gpl x (1 - fer) over the frames after the onset, 0 in a gap frame
%   M.t_rec_det  cycles from the detection frame (onset + t_conf) to the first of n_run
%                consecutive frames with the packet loss restored, at or after it; NaN when
%                never detected or never restored
[T, NE] = size(fer);
post = logical(post); gap = logical(gap); rplr = logical(rplr);
dp = post & ~gap;
M.per_post = sum(fer .* dp, 1) ./ sum(dp, 1);
M.per_post(sum(dp, 1) == 0) = NaN;
d = gpl .* (1 - fer) .* ~gap;
M.dlv_post = sum(d .* post, 1) ./ max(sum(post, 1), 1);
M.dlv_post(sum(post, 1) == 0) = NaN;
M.t_rec_det = nan(1, NE);
for i = 1:NE
    t0 = find(post(:, i), 1);
    if isempty(t0) || ~isfinite(t_conf(i)), continue; end
    kd = t0 + t_conf(i);
    k = run_start(rplr(:, i), kd, n_run, T);
    if ~isnan(k), M.t_rec_det(i) = k - kd; end
end
end

function k = run_start(x, k0, n, T)
% First k >= k0 with x(k : k + n - 1) all true, NaN if none.
k = NaN; run = 0;
for j = k0:T
    if x(j), run = run + 1; else, run = 0; end
    if run >= n, k = j - n + 1; return; end
end
end
