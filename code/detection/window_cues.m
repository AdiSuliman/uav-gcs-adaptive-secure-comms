function [x, names] = window_cues(G, Fw, Iw)
%WINDOW_CUES  Evidence of the last decision cycles beside temporal_evidence.m: the fusion's
%   further columns (fuse_classes.m; policy_monitor.m builds the same row per cycle).
%   Batch over E windows of n cycles, oldest first:
%   G   E x nr x n mean channel gain of every antenna [dB] (extract_closed_loop_frames.m)
%   Fw  E x nF x n link features of the window's frames (link_features.m order)
%   Iw  E x 24 x n records of the idle time before each frame (idle_summary.m), or []
%   x   E x 42, names = window_cues('names').
%
%   Branch cues (one branch lost: which cause; the receiver's per-antenna gains only):
%   the weakest antenna of the window (lowest local mean) against the others, per cycle the
%   offset d = its gain less the median of the others'.
%     k_strong, k_contrast  Rician K of the other antennas (moment method, Aoki & Honda 2025,
%                eq. 2) and the weakest's K less it [dB]: a faulty connector keeps the link's
%                K on its branch, a shadowed antenna loses its line of sight (K about -16 dB,
%                Sun et al., Part IV, Fig. 12)
%     sd_weak, sd_contrast  the weakest's spread over the cycles [dB] and less the others'
%     corr_ws    correlation of the weakest's gain with the others' mean over the cycles
%     trend      slope of d [dB per cycle]; step_max: largest change of d between two
%                cycles; off_range: largest less smallest d; off_first, off_last: d at the
%                window's ends; onset_in_win: the best split of d (a step inside the window)
%     cm_slope, cm_sd  slope and residual spread of the others' mean [dB]: the attitude's
%                pattern on the antennas that are not lost
%     margin_mean  mean est_margin; sinr_gap_w: mean sinr_gap (the weak branch's SINR)
%     gap_strong the other antennas' spread among themselves [dB]
%   A loss in the RF path is a steady branch offset; a pattern or geometry effect varies
%   (Willgert, US 8,548,029, Table 1); the imbalance indicator (Heath, US 10,404,368,
%   Table 2). The antenna's place in the array is not used: no source says which antenna
%   the airframe hides (shadow_hidden.m's far end is a stated assumption).
%   Step of our received level (path loss): on the combined level of all antennas and on
%   the monitor's estimate (sinr + iot), the best split of the window: its t statistic with
%   the pooled spread (at least 0.5 dB), its size [dB] and the cycles since it, stp_t,
%   stp_db, stp_age, stp_t_mon, stp_db_mon (a mean shift at an unknown cycle: the
%   two-sample form of the change-detection tests, Xie et al. 2021).
%   Idle time (Iw): the latest gap's i_occ, i_lvl, i_p90, i_max, i_nb (bursts),
%   i_contrast, i_ripple, i_ant_spread, i_bl_mean (complete bursts' mean length, ms), and over
%   the window's gaps w_occ and its spread, w_rate (bursts per second of idle time),
%   w_bl_mean and w_bl_cv (complete bursts' mean length and its coefficient of variation:
%   a sweep's dwell is one length, WLAN packets 0.27-3.2 ms), w_il_cv (the gaps between
%   bursts), w_start_cv (spread of the intervals between successive gaps' first bursts: a
%   sweep returns at its period), w_lvl and its spread, w_contrast, w_ripple, w_ant_spread
%   (Grimaldi et al. 2019: burst length, power, crest, envelope ripple; Rayanchu et al.
%   2011, Airshark: duty and pulse timing; Cheema & Salous 2019: duty, idle windows).
%   Windows without an idle record give 0 there (the first frame of a run).
names = {'k_strong', 'k_contrast', 'sd_weak', 'sd_contrast', 'corr_ws', 'trend', 'step_max', 'off_range', ...
    'cm_slope', 'cm_sd', 'margin_mean', 'sinr_gap_w', 'off_first', 'off_last', 'onset_in_win', 'gap_strong', ...
    'stp_t', 'stp_db', 'stp_age', 'stp_t_mon', 'stp_db_mon', ...
    'i_occ', 'i_lvl', 'i_p90', 'i_max', 'i_nb', 'i_contrast', 'i_ripple', 'i_ant_spread', 'i_bl_mean', ...
    'w_occ', 'w_occ_std', 'w_rate', 'w_bl_mean', 'w_bl_cv', 'w_il_cv', 'w_start_cv', 'w_lvl', 'w_lvl_std', ...
    'w_contrast', 'w_ripple', 'w_ant_spread'};
if ischar(G), x = names; return; end
[E, nr, n] = size(G);
G = double(G);
fi = @(name) reshape(double(Fw(:, feature_index(name), :)), E, n);
x = zeros(E, numel(names));
% ---- branch cues ----
if nr > 1
    gm = 10 * log10(mean(10 .^ (G / 10), 3));                      % E x nr local means
    [~, w] = min(gm, [], 2);
    msk = (1:nr) == w;                                             % E x nr: the weakest
    gw = reshape(sum(G .* msk, 2), E, n);
    Go = G; Go(repmat(msk, 1, 1, n)) = NaN;
    mo = reshape(median(Go, 2, 'omitnan'), E, n);                  % the others' median per cycle
    cm = reshape(mean(Go, 2, 'omitnan'), E, n);                    % the others' mean per cycle
    d = gw - mo;
    P = 10 .^ (G / 10);
    Ga = mean(P, 3); Gv = std(P, 1, 3);
    rr = sqrt(max(Ga.^2 - Gv.^2, 0));
    K = min(max(10 * log10(max(rr ./ max(Ga - rr, eps), 1e-2)), -20), 30);   % E x nr moment K
    if n < 3, K(:) = 0; end
    kw = sum(K .* msk, 2); ko = sum(K .* ~msk, 2) / (nr - 1);
    sd = std(G, 0, 3); sw = sum(sd .* msk, 2); so = sum(sd .* ~msk, 2) / (nr - 1);
    t = 1:n; tc = t - mean(t); stt = max(sum(tc.^2), eps);
    x(:, 1) = ko; x(:, 2) = kw - ko; x(:, 3) = sw; x(:, 4) = sw - so;
    if n >= 3
        a = gw - mean(gw, 2); b = cm - mean(cm, 2);
        x(:, 5) = sum(a .* b, 2) ./ max(sqrt(sum(a.^2, 2) .* sum(b.^2, 2)), eps);
        x(:, 6) = sum((d - mean(d, 2)) .* tc, 2) / stt;
        x(:, 7) = max(abs(diff(d, 1, 2)), [], 2);
        sl = sum((cm - mean(cm, 2)) .* tc, 2) / stt;
        x(:, 9) = sl; x(:, 10) = std(cm - mean(cm, 2) - sl .* tc, 0, 2);
    end
    x(:, 8) = max(d, [], 2) - min(d, [], 2);
    x(:, 13) = d(:, 1); x(:, 14) = d(:, end);
    x(:, 15) = best_split(d);
    gmo = gm; gmo(msk) = NaN;
    x(:, 16) = max(gmo, [], 2) - min(gmo, [], 2);
end
x(:, 11) = mean(fi('est_margin'), 2);
x(:, 12) = mean(fi('sinr_gap'), 2);
% ---- step of the received level ----
gc = reshape(10 * log10(sum(10 .^ (G / 10), 2)), E, n);
[x(:, 17), x(:, 18), x(:, 19)] = best_step(gc);
[x(:, 20), x(:, 21)] = best_step(fi('sinr') + fi('iot'));
% ---- idle time ----
if ~isempty(Iw)
    Iw = double(Iw);
    nm = idle_summary('names'); ci = @(s) find(strcmp(nm, s), 1);
    col = @(s) reshape(Iw(:, ci(s), :), E, n);
    ok = col('gap_ms') > 0 & ~isnan(col('occ'));
    last = ok(:, end);
    cur = {'occ', 'lvl', 'p90', 'max', 'nb', 'contrast', 'ripple', 'ant_spread'};
    for i = 1:numel(cur)
        v = col(cur{i}); x(last, 21 + i) = v(last, end);
    end
    nc = col('nc'); sb = col('sbl'); x(last, 30) = sb(last, end) ./ max(nc(last, end), 1);
    z = @(v) sum(v .* ok, 2, 'omitnan');                            % sums over the valid gaps
    nv = sum(ok, 2); has = nv > 0;
    occ = col('occ');
    m1 = z(occ) ./ max(nv, 1);
    x(has, 31) = m1(has);
    v2 = z(occ.^2) ./ max(nv, 1) - m1.^2; x(has, 32) = sqrt(max(v2(has), 0));
    snb = z(col('nb')); sgm = z(col('gap_ms'));
    x(has, 33) = snb(has) ./ max(sgm(has), eps) * 1e3;
    snc = z(nc); ssb = z(sb); ssb2 = z(col('sbl2'));
    mb = ssb ./ max(snc, 1); x(has, 34) = mb(has);
    q = snc >= 2; x(q, 35) = sqrt(max(ssb2(q) ./ snc(q) - mb(q).^2, 0)) ./ max(mb(q), eps);
    sni = z(col('nil')); ssi = z(col('sil')); ssi2 = z(col('sil2'));
    mi = ssi ./ max(sni, 1); q = sni >= 2; x(q, 36) = sqrt(max(ssi2(q) ./ sni(q) - mi(q).^2, 0)) ./ max(mi(q), eps);
    fr = col('first'); cy = col('cyc_ms');
    for e = find(has)'
        k = find(ok(e, :) & ~isnan(fr(e, :)));
        if numel(k) >= 3
            ta = (k - 1) .* cy(e, k) + fr(e, k);
            di = diff(ta); x(e, 37) = std(di) / max(mean(di), eps);
        end
    end
    lv = col('lvl'); lp = z(10 .^ (lv / 10)) ./ max(nv, 1);
    x(has, 38) = 10 * log10(lp(has));
    ml = z(lv) ./ max(nv, 1); vl = z(lv.^2) ./ max(nv, 1) - ml.^2; x(has, 39) = sqrt(max(vl(has), 0));
    mc = z(col('contrast')) ./ max(nv, 1); x(has, 40) = mc(has);
    mr = z(col('ripple')) ./ max(nv, 1); x(has, 41) = mr(has);
    ma = z(col('ant_spread')) ./ max(nv, 1); x(has, 42) = ma(has);
end
x(~isfinite(x)) = 0;
end

function [tb, db, ab] = best_step(v)
% Best split of each row (a drop: earlier mean above later): t statistic with the pooled
% spread (floored at 0.5 dB), the drop [dB], the cycles since the split.
[E, m] = size(v); tb = zeros(E, 1); db = zeros(E, 1); ab = zeros(E, 1);
if m < 2, return; end
c1 = cumsum(v, 2); c2 = cumsum(v.^2, 2); T1 = c1(:, end); T2 = c2(:, end);
for s = 2:m
    n1 = s - 1; n2 = m - n1;
    m1 = c1(:, n1) / n1; m2 = (T1 - c1(:, n1)) / n2;
    ss = (c2(:, n1) - n1 * m1.^2) + (T2 - c2(:, n1) - n2 * m2.^2);
    sp = sqrt(max(ss / max(m - 2, 1), 0.25));
    t = (m1 - m2) ./ sp / sqrt(1 / n1 + 1 / n2);
    u = t > tb;
    tb(u) = t(u); db(u) = m1(u) - m2(u); ab(u) = n2;
end
end

function b = best_split(d)
% Largest standardized split of each row, in either direction (a step inside the window).
[E, m] = size(d); b = zeros(E, 1);
if m < 4, return; end
c = cumsum(d, 2); T = c(:, end);
for s = 2:m
    n1 = s - 1; n2 = m - n1;
    b = max(b, abs(c(:, n1) / n1 - (T - c(:, n1)) / n2) * sqrt(n1 * n2 / m));
end
end
