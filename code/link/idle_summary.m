function [S, names] = idle_summary(R, p)
%IDLE_SUMMARY  What one cycle's idle time showed, per frame (the gap before it): the
%   per-cycle record the fusion's window reads (window_cues.m), so it is the same whether
%   the frames come from the dataset, a pool or the live receiver.
%   [S, names] = idle_summary(R, p): R bins x antennas x frames of idle_rssi.m; S frames x 24
%   (NaN rows where no idle time precedes the frame). The busy rule is the frame's: a bin
%   p.idle_busy_db over the floor constant (Cheema & Salous 2019, eq. 1; the frame's duty).
%   occ        busy share (Airshark's duty, Rayanchu et al. F3)
%   lvl        mean power over the antennas and bins [dB over the floor constant]
%   p10/p90/max  levels of the bins [dB] (Grimaldi et al.'s burst mean power and crest)
%   nb         busy runs (bursts); nc complete ones (inside the idle time)
%   sbl/sbl2   sum and sum of squares of the complete bursts' lengths [ms] (on-air time)
%   nil, sil, sil2  idle runs between bursts and their lengths [ms] (Wollenberg et al.:
%              packet and gap statistics; Cheema & Salous: idle windows)
%   contrast   mean busy level over mean idle level [dB]; ripple: spread of the busy
%              bins [dB] (Grimaldi et al.'s envelope ripple)
%   ant_spread, ant_weak  the antennas' busy-bin means: largest less smallest, smallest less
%              the median [dB]
%   pa1..pa4   each antenna's busy-bin mean [dB] (all bins when none is busy), NaN beyond
%              the array
%   nbusy      busy bins; first: start of the first complete burst from the cycle's start
%              [ms]; gap_ms: idle time observed [ms]; cyc_ms: the decision cycle [ms]
names = {'occ', 'lvl', 'p10', 'p90', 'max', 'nb', 'nc', 'sbl', 'sbl2', 'nil', 'sil', 'sil2', 'contrast', ...
    'ripple', 'ant_spread', 'ant_weak', 'pa1', 'pa2', 'pa3', 'pa4', 'nbusy', 'first', 'gap_ms', 'cyc_ms'};
if ischar(R), S = names; return; end
[nb, nr, nf] = size(R);
S = nan(nf, numel(names));
if nb == 0, return; end
tb = 1e3 / p.idle_rssi_hz; cy = 1e3 * p.cycle_s;
off = cy - nb * tb;                                        % the idle time ends where the frame begins
for j = 1:nf
    Rj = R(:, :, j);
    if any(isnan(Rj(:))), continue; end
    xa = 10.^(Rj / 10); x = mean(xa, 2); y = 10*log10(x);
    b = y > p.idle_busy_db;
    [bl, il, st, cb] = runs(b);
    s = zeros(1, numel(names));
    s(1) = mean(b); s(2) = 10*log10(mean(x));
    ys = sort(y); s(3) = ys(max(1, ceil(0.1 * nb))); s(4) = ys(max(1, ceil(0.9 * nb))); s(5) = ys(end);
    s(6) = numel(bl); s(7) = sum(cb);
    s(8) = sum(bl(cb)) * tb; s(9) = sum((bl(cb) * tb).^2);
    s(10) = numel(il); s(11) = sum(il) * tb; s(12) = sum((il * tb).^2);
    if any(b) && any(~b), s(13) = mean(y(b)) - mean(y(~b)); end
    if sum(b) > 1, s(14) = std(y(b)); end
    sel = b; if ~any(sel), sel = true(nb, 1); end
    pa = 10*log10(mean(xa(sel, :), 1));
    s(15) = max(pa) - min(pa); s(16) = min(pa) - median(pa);
    s(17:20) = NaN; s(16 + (1:min(nr, 4))) = pa(1:min(nr, 4));
    s(21) = sum(b);
    s(22) = NaN; if any(cb), s(22) = off + (st(find(cb, 1)) - 1) * tb; end
    s(23) = nb * tb; s(24) = cy;
    S(j, :) = s;
end
end

function [bl, il, st, cb] = runs(b)
% Busy-run lengths bl and starts st [bins], idle runs il between busy runs, and cb: the
% busy runs inside the idle time (not touching its ends).
b = b(:)'; n = numel(b);
d = diff([0 b 0]); s = find(d == 1); e = find(d == -1) - 1;
bl = e - s + 1; st = s;
cb = s > 1 & e < n;
il = [];
if numel(s) > 1, il = s(2:end) - e(1:end-1) - 1; end
end
