function [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%OOD_LOTO_SPLIT  The frames of one held-out threat k of eval_ood_detection.m.
%   [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%   sp     splits of data/splits.mat (train, val, norm, classes); its test split is not read
%   fresh  the second test set (splits_fresh.mat, test), z-scored with sp.norm
%   tr     the known classes' training frames of the known classes' sub-runs
%   vfit   the known classes' validation frames of the known classes' sub-runs in one half
%          of the validation sub-runs: early stopping and the unknown-threat models' fit
%   va     every validation frame (every class, in its sub-run), with va.sel true on the
%          other half: the selection reads the known windows there against the held-out
%          threat's windows of every validation sub-run
%   vk     the held-out threat's validation frames (Lee et al.'s Algorithm 2)
%   te     every frame of the second test set (the reading); [] when fresh is [] (a run on
%          validation only, ood_k2_run.m's select phase)
%   va.own, te.own  true on the frames of the held-out threat's sub-runs: their clean
%          frames are not known windows (eval_ood_detection.m)
%   Halves (half_of_runs): within each class and Eb/N0 point the validation sub-runs, in
%   level order and run order inside a level, go to the two halves in turn, starting with
%   the Eb/N0 point's parity. A class with one sub-run per (level, Eb/N0) cell is a
%   checkerboard over level and Eb/N0; a cell of several sub-runs splits inside itself; every
%   (class, Eb/N0) and (class, level) has sub-runs in both halves.
%   A sub-run's class (run_class): its threat's per-cycle label (Y), 'none' for a sub-run
%   with no cycle of a threat.
%   Labels: the frame rule (frame_labels.m), as the network sees the frame.
%   Link features are re-normalized with the statistics of the known training frames only;
%   no frame of the held-out threat's sub-runs fits, weights or chooses anything inside its
%   fold.
%   Each set: X, feats, Y (categorical over the known classes for tr and vfit, over every
%   class otherwise), run, pos.
%   F = ood_loto_split('masks', sp, k)  the same fold as masks over sp.train and sp.val, no
%          frame copied (D111's cue rows, ood_cue.m): F.tr (train), F.vfit, F.sel, F.own,
%          F.kn and F.un (the selection's known and held-out windows, as
%          eval_ood_detection.m reads them), F.known, F.ytr and F.yv (frame-rule labels);
%          k '' holds no threat out (every class known)
if ischar(sp) && strcmp(sp, 'masks'), tr = masks(fresh, k); return; end
cls = cellstr(string(sp.classes(:)'));
known = setdiff(cls, {k}, 'stable');
fit = half_of_runs(sp.val);
otr = strcmp(run_class(sp.train), k); ova = strcmp(run_class(sp.val), k);
sp.train = frame_labels(sp.train); sp.val = frame_labels(sp.val);
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
tr = subset(sp.train, ismember(cellstr(string(sp.train.Y(:))), known) & ~otr, known, raw(sp.train));
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd;
va = subset(sp.val, true(numel(sp.val.Y), 1), cls, (raw(sp.val) - mu) ./ sd);
yv = cellstr(string(va.Y));
va.sel = ~fit; va.own = ova;
vfit = subset(va, fit & ismember(yv, known) & ~ova, known, va.feats);
vk = subset(va, strcmp(yv, k), {k}, va.feats);
te = [];
if isempty(fresh), return; end
ote = strcmp(run_class(fresh), k);
fresh = frame_labels(fresh);
te = subset(fresh, true(numel(fresh.Y), 1), cls, (raw(fresh) - mu) ./ sd);
te.own = ote;
end

function F = masks(sp, k)
% The fold of held-out threat k as masks over sp.train and sp.val (the order of the main path).
cls = cellstr(string(sp.classes(:)'));
F.known = setdiff(cls, {k}, 'stable');
fit = half_of_runs(sp.val);
otr = strcmp(run_class(sp.train), k); ova = strcmp(run_class(sp.val), k);
St = frame_labels(sp.train); Sv = frame_labels(sp.val);
F.ytr = cellstr(string(St.Y(:))); F.yv = cellstr(string(Sv.Y(:)));
F.tr = ismember(F.ytr, F.known) & ~otr;
F.vfit = fit & ismember(F.yv, F.known) & ~ova;
F.sel = ~fit; F.own = ova;
F.kn = ismember(F.yv, F.known) & F.sel & ~ova;
F.un = strcmp(F.yv, k);
end

function [cf, cr, runs, i1, ir] = run_class(P)
% The class of each frame's sub-run (cf) and of each sub-run (cr): the most frequent
% per-cycle label (P.Y) other than 'none', 'none' without one; runs, i1, ir as unique(P.run).
[runs, i1, ir] = unique(P.run(:));
y = categorical(cellstr(string(P.Y(:))));
cats = categories(y);
n = accumarray([ir, double(y)], 1, [numel(runs), numel(cats)]);
n(:, strcmp(cats, 'none')) = 0;
[nm, m] = max(n, [], 2);
cr = cats(m); cr(nm == 0) = {'none'};
cf = cr(ir);
end

function fit = half_of_runs(P)
% True on the frames of the fit half (P: Y per cycle, run, ebno, level per frame).
[~, cr, runs, i1, ir] = run_class(P);
nR = numel(runs);
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
