function [x, names] = window_cues(G, Fw, Iw, Bw, varargin)
%WINDOW_CUES  Evidence of the last decision cycles beside temporal_evidence.m: the fusion's
%   further columns (fuse_classes.m; policy_monitor.m builds the same row per cycle).
%   Batch over E windows of n cycles, oldest first:
%   G   E x nr x n mean channel gain of every antenna [dB] (extract_closed_loop_frames.m)
%   Fw  E x nF x n link features of the window's frames (link_features.m order)
%   Iw  E x 24 x n records of the idle time before each frame (idle_summary.m), or []
%   Bw  E x 9nr x nb records of every antenna's channel estimates (branch_record.m) over the
%       last nb = window_cues('branch_window') cycles, oldest first, or [] (columns 0)
%   x   E x 52, names = window_cues('names').
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
%   Branch coherence (Bw; the cause of one lost branch from the receiver's own channel
%   estimates): a faulty connector scales everything its antenna receives, so the branch's
%   normalised correlation with the other antennas and its line-of-sight share across delay
%   are kept; a hidden antenna loses its line of sight (K about -16 dB, Sun et al., Part IV),
%   so what stays correlated with the others is its diffuse part only. Over the record's
%   cycles from the weakest antenna's step on (the best split of its offset, when it drops
%   by more than 3 dB): coh_weak, the magnitude of the weakest's cross-correlation with each
%   other antenna over the cycles, normalised by the noise-debiased powers (mean over the
%   others); coh_others, the same between the other antennas (the link's own line-of-sight
%   share); coh_ref, against the others' sum aligned by their mean cross phase;
%   coh_contrast = coh_weak - coh_others; coh_cycles, the cycles used over nb. At the
%   line-of-sight lag (the whole-symbol lag with the most power): los_weak, the weakest's
%   power there over its other lags [dB], los_others the same for the others, los_contrast,
%   los_k the Rician K of its power there over the cycles (moment method, Aoki & Honda
%   2025, eq. 2) [dB], los_coh its coherence there with the others. A common phase of the
%   frame cancels in every cross-correlation; only the antennas' gains decide which
%   antenna is weakest (its place in the array is not used).
%
%   xe = window_cues('extra', G, Fw, Iw, opt): the columns a fusion adds after its own
%   (FM.cues, select_fusion.m; fuse_classes.m puts them last), E x numel(window_cues('extra_names', opt)):
%   opt.cfar = [T1 T2 m0], the idle time against the radio's own noise: the busy rule of the
%     record is a constant over the floor, which a weak emitter never crosses, so here each
%     gap's crest max - p10 and spread p90 - p10 over its own floor p10 (Grimaldi et al.
%     2019: the threshold mu_N + 2 sigma_N on the radio's measured noise, the crest factor;
%     Kazim et al. 2026, eq. 1.3: a threshold from interference-free samples). T1, T2: the
%     clean gaps' crest and spread exceeded by at most 1% of them, m0 their median crest.
%     cf_crest_hi, cf_spread_hi: shares of the window's gaps above T1, T2; cf_crest_ex: the
%     window's mean crest less m0, at least 0; cf_crest_now: the latest gap's crest above T1.
%   opt.iso = true, the branch that steps (detection-isolation, Xie et al. 2021, Sec. III-I):
%     per antenna the best split (the two-sample step below) of its offset to the others'
%     median; iso_t the largest t, iso_db that antenna's drop, iso_margin its t less the
%     second largest, iso_agree 1 when it is the weakest by its mean as above.
names = {'k_strong', 'k_contrast', 'sd_weak', 'sd_contrast', 'corr_ws', 'trend', 'step_max', 'off_range', ...
    'cm_slope', 'cm_sd', 'margin_mean', 'sinr_gap_w', 'off_first', 'off_last', 'onset_in_win', 'gap_strong', ...
    'stp_t', 'stp_db', 'stp_age', 'stp_t_mon', 'stp_db_mon', ...
    'i_occ', 'i_lvl', 'i_p90', 'i_max', 'i_nb', 'i_contrast', 'i_ripple', 'i_ant_spread', 'i_bl_mean', ...
    'w_occ', 'w_occ_std', 'w_rate', 'w_bl_mean', 'w_bl_cv', 'w_il_cv', 'w_start_cv', 'w_lvl', 'w_lvl_std', ...
    'w_contrast', 'w_ripple', 'w_ant_spread', ...
    'coh_weak', 'coh_others', 'coh_ref', 'coh_contrast', 'coh_cycles', 'los_weak', 'los_others', 'los_contrast', 'los_k', 'los_coh'};
NB = 10;                                                           % the branch record's cycles (the link features' window)
if ischar(G)
    switch G
        case 'branch_window', x = NB;
        case 'extra_names', x = extra_names(Fw);
        case 'extra', x = extra_cues(Fw, Iw, Bw, varargin{1});
        otherwise, x = names;
    end
    return;
end
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
% ---- branch coherence ----
if nargin >= 4 && ~isempty(Bw), x(:, end - 9:end) = branch_coherence(double(Bw)); end
x(~isfinite(x)) = 0;
end

function n = extra_names(opt)
% Names of the columns window_cues('extra', ..., opt) returns.
n = {};
if isempty(opt), return; end
if isfield(opt, 'cfar') && ~isempty(opt.cfar), n = [n, {'cf_crest_hi', 'cf_spread_hi', 'cf_crest_ex', 'cf_crest_now'}]; end
if isfield(opt, 'iso') && opt.iso, n = [n, {'iso_t', 'iso_db', 'iso_margin', 'iso_agree'}]; end
end

function x = extra_cues(G, ~, Iw, opt)
% The extra columns (see the header) of E windows of n cycles.
[E, nr, n] = size(G);
x = zeros(E, numel(extra_names(opt)));
if isempty(x), return; end
k = 0;
if isfield(opt, 'cfar') && ~isempty(opt.cfar)
    if ~isempty(Iw)
        Iw = double(Iw); nm = idle_summary('names');
        col = @(s) reshape(Iw(:, find(strcmp(nm, s), 1), :), E, n);
        ok = col('gap_ms') > 0 & ~isnan(col('occ'));
        cr = col('max') - col('p10'); sp = col('p90') - col('p10');
        nv = sum(ok, 2); has = nv > 0;
        x(has, 1) = sum(ok(has, :) & cr(has, :) > opt.cfar(1), 2) ./ nv(has);
        x(has, 2) = sum(ok(has, :) & sp(has, :) > opt.cfar(2), 2) ./ nv(has);
        mc = sum(cr .* ok, 2, 'omitnan') ./ max(nv, 1);
        x(has, 3) = max(0, mc(has) - opt.cfar(3));
        x(:, 4) = ok(:, end) & cr(:, end) > opt.cfar(1);
    end
    k = 4;
end
if isfield(opt, 'iso') && opt.iso && nr > 1
    G = double(G);
    T = zeros(E, nr); Db = zeros(E, nr);
    for a = 1:nr
        o = setdiff(1:nr, a);
        d = reshape(G(:, a, :), E, n) - reshape(median(G(:, o, :), 2), E, n);
        [T(:, a), Db(:, a)] = best_step(d);
    end
    [ts, ord] = sort(T, 2, 'descend');
    i1 = sub2ind([E nr], (1:E)', ord(:, 1));
    [~, w] = min(10 * log10(mean(10 .^ (G / 10), 3)), [], 2);
    x(:, k + 1) = ts(:, 1); x(:, k + 2) = Db(i1); x(:, k + 3) = ts(:, 1) - ts(:, 2); x(:, k + 4) = ord(:, 1) == w;
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

function x = branch_coherence(B)
% The branch-coherence columns (see the header) of E windows of branch records (E x 9nr x nb).
[E, m, nb] = size(B); nr = m / 9; x = zeros(E, 10);
if nr < 2 || nb < 1, return; end
blk = @(k) (k - 1) * nr + (1:nr);
for e = 1:E
    R = reshape(B(e, :, :), m, nb).';
    R = R(all(isfinite(R(:, 1:4 * nr)), 2), :);
    nw = size(R, 1); if nw < 1, continue; end
    Gc = R(:, blk(1)); gm = 10 * log10(mean(10 .^ (Gc / 10), 1)); [~, a] = min(gm); o = setdiff(1:nr, a);
    if nw >= 3                                                     % the cycles from the weakest's step on
        d = Gc(:, a) - median(Gc(:, o), 2); sb = inf; s0 = 1;
        for s = 2:nw
            v = sum((d(1:s-1) - mean(d(1:s-1))).^2) + sum((d(s:end) - mean(d(s:end))).^2);
            if v < sb, sb = v; s0 = s; end
        end
        if mean(d(1:s0-1)) - mean(d(s0:end)) > 3, R = R(s0:end, :); nw = size(R, 1); end
    end
    h = R(:, blk(2)) + 1j * R(:, blk(3));
    [cw, co, cm] = coherences(h, R(:, blk(4)), a, o);
    x(e, 1:5) = [min(cw, 1.5), min(co, 1.5), min(cm, 1.5), min(cw, 1.5) - min(co, 1.5), nw / nb];
    k = all(isfinite(R(:, 4 * nr + 1:end)), 2); nk = sum(k);
    if nk < 1, continue; end
    p0 = R(k, blk(8)); pr = R(k, blk(9));
    lr = min(max(10 * log10(max(sum(p0, 1), eps) ./ max(sum(pr, 1), 1e-6 * max(sum(p0, 1), eps))), -20), 40);
    kl = 0; if nk >= 3, kl = k_moment(p0(:, a)); end
    cl = coherences(R(k, blk(5)) + 1j * R(k, blk(6)), R(k, blk(7)), a, o);
    x(e, 6:10) = [lr(a), mean(lr(o)), lr(a) - mean(lr(o)), kl, min(cl, 1.5)];
end
end

function [cw, co, cm] = coherences(h, nv, a, o)
% Noise-debiased normalised cross-correlations over the cycles (rows) of antenna a with the
% others o (mean), among the others (mean over their pairs), and of a with the others' sum
% aligned to the first by their mean cross phase.
pw = sum(abs(h).^2, 1); P = max(pw - sum(nv, 1), 0.05 * pw);
cx = @(i, k) abs(sum(h(:, i) .* conj(h(:, k)))) / sqrt(max(P(i) * P(k), eps));
cw = mean(arrayfun(@(k) cx(a, k), o));
co = 0; if numel(o) > 1, pr = nchoosek(o, 2); co = mean(arrayfun(@(i) cx(pr(i, 1), pr(i, 2)), 1:size(pr, 1))); end
rf = h(:, o(1)); nr0 = sum(nv(:, o(1)));
for k = o(2:end), rf = rf + h(:, k) * exp(1j * angle(sum(h(:, o(1)) .* conj(h(:, k))))); nr0 = nr0 + sum(nv(:, k)); end
prf = max(sum(abs(rf).^2) - nr0, 0.05 * sum(abs(rf).^2));
cm = abs(sum(h(:, a) .* conj(rf))) / sqrt(max(P(a) * prf, eps));
end

function k = k_moment(pw)
% Moment-method Rician K [dB] from power samples (Aoki & Honda 2025, eq. 2), -20..30 dB.
Ga = mean(pw); Gv = std(pw, 1);
r = sqrt(max(Ga^2 - Gv^2, 0));
k = min(max(10 * log10(max(r / max(Ga - r, eps), 1e-2)), -20), 30);
end
