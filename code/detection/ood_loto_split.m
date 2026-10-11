function [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%OOD_LOTO_SPLIT  The frames of one held-out threat k of eval_ood_detection.m.
%   [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k)
%   sp     splits of data/splits.mat (train, val, norm, classes); its test split is not read
%   fresh  the second test set (splits_fresh.mat, test), z-scored with sp.norm
%   tr     the known classes' training frames
%   vfit   the known classes' validation frames of half of the validation sub-runs (every
%          other sub-run in run order): early stopping and the unknown-threat
%          models' fit
%   va     every validation frame (every class, in its sub-run), with va.sel true on the
%          other half: the selection reads the known windows there against the held-out
%          threat's windows of every validation sub-run
%   vk     the held-out threat's validation frames (Lee et al.'s Algorithm 2)
%   te     every frame of the second test set (the reading)
%   Link features are re-normalized with the statistics of the known training frames only;
%   the held-out threat never fits, weights or chooses anything inside its fold.
%   Each set: X, feats, Y (categorical over the known classes for tr and vfit, over every
%   class otherwise), run, pos.
cls = cellstr(string(sp.classes(:)'));
known = setdiff(cls, {k}, 'stable');
raw = @(P) P.feats .* sp.norm.feat_std + sp.norm.feat_mean;
tr = subset(sp.train, ismember(cellstr(string(sp.train.Y(:))), known), known, raw(sp.train));
mu = mean(tr.feats, 1); sd = std(tr.feats, 0, 1); sd(sd < 1e-8) = 1;
tr.feats = (tr.feats - mu) ./ sd;
va = subset(sp.val, true(numel(sp.val.Y), 1), cls, (raw(sp.val) - mu) ./ sd);
runs = unique(va.run);
fit = ismember(va.run, runs(1:2:end));
yv = cellstr(string(va.Y));
va.sel = ~fit;
vfit = subset(va, fit & ismember(yv, known), known, va.feats);
vk = subset(va, strcmp(yv, k), {k}, va.feats);
te = subset(fresh, true(numel(fresh.Y), 1), cls, (raw(fresh) - mu) ./ sd);
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
