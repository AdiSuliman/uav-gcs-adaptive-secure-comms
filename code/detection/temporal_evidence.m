function [x, names] = temporal_evidence(P, G, Fw)
%TEMPORAL_EVIDENCE  Evidence of the last decision cycles for one decision: the
%   input of the temporal fusion (fuse_classes.m). One cycle carries one frame of
%   0.5 ms, too short for the fading to change, so a deep fade on one antenna looks
%   like a hidden antenna; the channel moves on between cycles, while a shadow, a
%   jammer or a fault stays. Local mean per antenna over the window: the fading
%   averages out and a persistent loss remains (Lee, local average power over 20-40
%   wavelengths; shadowing lasts seconds, Khawaja et al.).
%   Batch over E windows of n cycles:
%   P   E x C x n class probabilities of the per-frame detector
%   G   E x nr x n mean channel gain of every antenna [dB] (extract_closed_loop_frames.m)
%   Fw  E x nF x n link features of the window's frames (link_features.m order)
%   x   E x (C + 9): mean log-probability of every class (the product of the
%       per-frame likelihoods), then
%       gap_w    largest over smallest window-mean antenna gain [dB]
%       weak_w   share of the window's cycles in which the most often weakest
%                antenna is the weakest (1/nr for fading, 1 for a hidden antenna)
%       occ_w    share of cycles with interference in the quiet slot (> 3 dB over
%                thermal): continuous interference ~1, intermittent in between
%       drop_w   share of cycles in which one antenna drops: 20 dB or more below the
%                next one over the frame, or 15 dB inside the frame (a connector open
%                for part of it). An open connector (~30 dB) comes and goes, a shadow
%                stays, and fading rarely separates two antennas that far
%       off_w    mean per-cycle offset of the weakest antenna (lowest window mean)
%                from the median of the others [dB] (Willgert, US 8,548,029, eq. 5)
%       rat_w    standard deviation of that offset over |off_w|, at most 10: a loss in
%                the RF path is a steady offset (|mean| > 3 dB, ratio < 3), a pattern
%                or geometry effect a small mean with a large spread (Willgert, Table
%                1); a diversity imbalance above 5 dB that persists marks a degraded
%                antenna connection (Heath, US 10,404,368, Table 2)
%       k_w      Rician K of the weakest antenna over the window's valid cycles,
%                moment method K = sqrt(Ga^2 - Gv^2) / (Ga - sqrt(Ga^2 - Gv^2)), Ga
%                the mean power and Gv its RMS fluctuation (Aoki & Honda 2025, eq. 2)
%                [dB, -20..30]; inside airframe shadowing K falls from about 15 to
%                -16 dB (Sun et al., Part IV, p. 5), a loss in series with the antenna
%                keeps it. 0 with fewer than 3 valid cycles
%       kv_w     share of valid cycles: every antenna's gain above the noise of its
%                channel estimate (est_margin > 0 dB)
%       duty_w   mean busy share of the window's frames (duty): the occupancy of the
%                channel over the window (Cheema & Salous 2019, eq. 1)
%   names = temporal_evidence('names', C) returns the feature names.
WN = {'gap_w', 'weak_w', 'occ_w', 'drop_w', 'off_w', 'rat_w', 'k_w', 'kv_w', 'duty_w'};
if ischar(P)
    names = [arrayfun(@(c) sprintf('logp_%d', c), 1:G, 'UniformOutput', false), WN];
    x = names; return;
end
[E, nr, n] = size(G);
fi = @(name) reshape(double(Fw(:, feature_index(name), :)), E, n);
G = double(G);
lp = mean(log(max(double(P), 1e-6)), 3);
gm = 10 * log10(mean(10 .^ (G / 10), 3));
gap_w = max(gm, [], 2) - min(gm, [], 2);
[~, wk] = min(G, [], 2);                                  % E x 1 x n weakest antenna per cycle
cnt = zeros(E, nr);
for a = 1:nr, cnt(:, a) = sum(wk == a, 3); end
weak_w = max(cnt, [], 2) / n;
q = fi('q_iot'); ok = ~isnan(q);
occ_w = sum((q > 3) & ok, 2) ./ max(sum(ok, 2), 1);
gs = sort(G, 2);
dr = reshape(gs(:, min(2, nr), :) - gs(:, 1, :) >= 20, E, n);
drop_w = mean(dr | fi('branch_dip') >= 15, 2);
[off_w, rat_w, k_w, kv_w] = deal(zeros(E, 1));
[~, w] = min(gm, [], 2);                                  % weakest antenna of the window
valid = fi('est_margin') > 0;
for e = 1:E
    gw = reshape(G(e, w(e), :), 1, n);
    if nr > 1
        d = gw - median(reshape(G(e, setdiff(1:nr, w(e)), :), nr - 1, n), 1);
        off_w(e) = mean(d);
        rat_w(e) = min(std(d) / max(abs(off_w(e)), eps), 10);
    end
    kv_w(e) = mean(valid(e, :));
    if sum(valid(e, :)) >= 3, k_w(e) = k_moment(10 .^ (gw(valid(e, :)) / 10)); end
end
duty_w = mean(fi('duty'), 2, 'omitnan');
x = [lp, gap_w, weak_w, occ_w, drop_w, off_w, rat_w, k_w, kv_w, duty_w];
x(~isfinite(x)) = 0;
names = [];
end

function k = k_moment(pw)
% Moment-method Rician K [dB] from power samples (Aoki & Honda 2025, eq. 2), -20..30 dB.
Ga = mean(pw); Gv = std(pw, 1);
r = sqrt(max(Ga^2 - Gv^2, 0));
k = min(max(10 * log10(max(r / max(Ga - r, eps), 1e-2)), -20), 30);
end
