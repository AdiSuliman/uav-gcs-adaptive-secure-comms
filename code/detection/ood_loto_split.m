function [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%OOD_LOTO_SPLIT  The frames of one held-out threat k of eval_ood_detection.m.
%   [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%   sp     splits of data/splits.mat (train, val, norm, classes); its test split is not read
%   fresh  the second test set (splits_fresh.mat, test), z-scored with sp.norm
%   tr     the known classes' training frames
%   vfit   the known classes' validation frames of one half of the validation sub-runs:
%          early stopping and the unknown-threat models' fit
%   va     every validation frame (every class, in its sub-run), with va.sel true on the
%          other half: the selection reads the known windows there against the held-out
%          threat's windows of every validation sub-run
%   vk     the held-out threat's validation frames (Lee et al.'s Algorithm 2)
%   te     every frame of the second test set (the reading)
%   Halves (half_of_runs): within each class and Eb/N0 point the validation sub-runs, in
%   level order and run order inside a level, go to the two halves in turn, starting with
%   the Eb/N0 point's parity. A class with one sub-run per (level, Eb/N0) cell is a
%   checkerboard over level and Eb/N0; a cell of several sub-runs splits inside itself; every
%   (class, Eb/N0) and (class, level) has sub-runs in both halves. A sub-run's class is its
%   per-cycle class (Y).
%   Labels: the frame rule (frame_labels.m), as the network sees the frame.
%   Link features are re-normalized with the statistics of the known training frames only;
%   the held-out threat never fits, weights or chooses anything inside its fold.
%   Each set: X, feats, Y (categorical over the known classes for tr and vfit, over every
%   class otherwise), run, pos.
cls = cellstr(string(sp.classes(:)'));
known = setdiff(cls, {k}, 'stable');
fit = half_of_runs(sp.val);
sp.train = frame_labels(sp.train); sp.val = frame_labels(sp.val); fresh = frame_labels(fresh);
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
tr = subset(sp.train, ismember(cellstr(string(sp.train.Y(:))), known), known, raw(sp.train));
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd;
va = subset(sp.val, true(numel(sp.val.Y), 1), cls, (raw(sp.val) - mu) ./ sd);
yv = cellstr(string(va.Y));
va.sel = ~fit;
vfit = subset(va, fit & ismember(yv, known), known, va.feats);
vk = subset(va, strcmp(yv, k), {k}, va.feats);
te = subset(fresh, true(numel(fresh.Y), 1), cls, (raw(fresh) - mu) ./ sd);
end

function fit = half_of_runs(P)
% True on the frames of the fit half (P: Y per cycle, run, ebno, level per frame).
[runs, i1, ir] = unique(P.run(:));
y = cellstr(string(P.Y(:)));
nR = numel(runs);
cr = repmat({'none'}, nR, 1);                           % a sub-run's class: its threat's label
for r = 1:nR
    yr = y(ir == r); yr = yr(~strcmp(yr, 'none'));
    if ~isempty(yr), [u, ~, j] = unique(yr); [~, m] = max(accumarray(j, 1)); cr{r} = u{m}; end
end
eb = P.ebno(:); eb = eb(i1);
lv = P.level(:); lv = lv(i1); lv(isnan(lv)) = -Inf;
[~, ~, ie] = unique(eb);                                % Eb/N0 index
[~, ~, ic] = unique(cr);
fitR = false(nR, 1);
for c = unique(ic)'
    for e = unique(ie(ic == c))'
        g = find(ic == c & ie == e);
        [~, o] = sortrows([lv(g), runs(g)]);
        fitR(g(o)) = mod(e + (0:numel(g) - 1)', 2) == 0;
    end
end
fit = fitR(ir);
end

function d = subset(P, m, cats, F)
% Frames m of P with the features F (rows of all frames), Y over the categories cats.
m = m(:);
y = cellstr(string(P.Y(:)));
d.X = P.X(:, :, :, m);
d.feats = F(m, :);
d.Y = categorical(y(m), cats);
d.run = P.run(m); d.run = d.run(:);
if isfield(P, 'pos') && ~isempty(P.pos), d.pos = P.pos(m); d.pos = d.pos(:); else, d.pos = []; end
end
