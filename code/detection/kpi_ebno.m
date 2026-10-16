function [bin, eb, rx, bin_rx] = kpi_ebno(P, target, classes)
%KPI_EBNO  The Eb/N0 of every frame in the KPI 1 reading and its bin (eval_detector.m,
%   compare_architectures.m).
%   [bin, eb, rx, bin_rx] = kpi_ebno(P, target, classes)
%   A frame is read at the Eb/N0 our signal reaches the receiver with (rx): the configured
%   Eb/N0, less the path-loss step from its onset on. A frame judged as path_loss is read at
%   the configured Eb/N0, the link's when the step began: the step's depth is the threat's
%   severity level, as a jammer's JSR is, and every other threat is read at the link's
%   Eb/N0 too. A later frame of the same run is the clean link at the longer range
%   and is read at its own received Eb/N0.
%   P        split: ebno (configured) per frame, and ebno_rx (received) when the dataset
%            carries it; without it rx is derived from the labels: the configured Eb/N0
%            less the run's level from its first path_loss frame on (fields Y, run, pos,
%            level; the first labelled frame is the first complete frame after the onset)
%   target   class each frame is judged against (categorical, names, or indices into
%            classes)
%   classes  class names
%   bin      the highest point of the configured Eb/N0 grid at or below eb; NaN below the
%            grid (beyond range: reported beside the reading, never dropped)
%   eb       the frame's Eb/N0 in the reading; rx the received Eb/N0, bin_rx its bin
eb0 = double(P.ebno(:));
if isfield(P, 'ebno_rx') && ~isempty(P.ebno_rx)
    rx = double(P.ebno_rx(:));
else
    rx = eb0;
    if all(isfield(P, {'Y', 'run', 'pos', 'level'}))
        y = cellstr(string(P.Y(:)));
        pl = strcmp(y, 'path_loss');
        run = P.run(:); pos = P.pos(:); lv = double(P.level(:));
        for r = unique(run(pl))'
            ix = find(run == r);
            t0 = min(pos(ix(pl(ix))));
            k = ix(pos(ix) >= t0);
            rx(k) = eb0(k) - lv(k);
        end
    end
end
if isnumeric(target)
    cn = cellstr(string(classes));
    names = reshape(cn(target), [], 1);
else
    names = cellstr(string(target(:)));
end
eb = rx;
st = strcmp(names, 'path_loss');
eb(st) = eb0(st);
grid = unique(eb0);
k = discretize(eb + 1e-9, [grid; Inf]);             % a received value on a grid point stays in its bin
bin = nan(size(eb));
bin(~isnan(k)) = grid(k(~isnan(k)));
k = discretize(rx + 1e-9, [grid; Inf]);
bin_rx = nan(size(rx));
bin_rx(~isnan(k)) = grid(k(~isnan(k)));
end
