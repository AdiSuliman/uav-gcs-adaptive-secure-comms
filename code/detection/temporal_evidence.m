function [x, names] = temporal_evidence(P, G, Qi, Dp)
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
%   Qi  E x n interference over thermal in the quiet slot [dB]
%   Dp  E x n deepest drop of one antenna's channel gain inside the frame [dB]
%       (branch_dip of extract_closed_loop_frames.m); optional
%   x   E x (C + 4): mean log-probability of every class (the product of the
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
%   names = temporal_evidence('names', C) returns the feature names.
if ischar(P)
    names = [compose('logp_%d', 1:G), {'gap_w', 'weak_w', 'occ_w', 'drop_w'}];
    x = []; return;
end
[E, nr, n] = size(G);
lp = mean(log(max(double(P), 1e-6)), 3);
gm = 10 * log10(mean(10 .^ (double(G) / 10), 3));
gap_w = max(gm, [], 2) - min(gm, [], 2);
[~, wk] = min(G, [], 2);                                  % E x 1 x n weakest antenna per cycle
cnt = zeros(E, nr);
for a = 1:nr, cnt(:, a) = sum(wk == a, 3); end
weak_w = max(cnt, [], 2) / n;
q = double(Qi); ok = ~isnan(q);
occ_w = sum((q > 3) & ok, 2) ./ max(sum(ok, 2), 1);
gs = sort(double(G), 2);
dr = squeeze(gs(:, min(2, nr), :) - gs(:, 1, :) >= 20);
if nargin >= 4 && ~isempty(Dp), dr = dr | reshape(double(Dp) >= 15, size(dr)); end
drop_w = mean(reshape(dr, E, n), 2);
x = [lp, gap_w, weak_w, occ_w, drop_w];
x(~isfinite(x)) = 0;
names = [];
end
