function varargout = fusion_cand(cmd, varargin)
%FUSION_CAND  Candidate fusions over the d91 pick (the base B), read out of fold by sub-run on
%   the enlarged fit set (m_head.m, fusion_recheck.m):
%     B         the window row and the pick's further columns (its cues)
%     GCC       B and the six gated coherence columns (fuse_classes 'gcc')
%     CFAR      B and the idle time against each gap's own floor (window_cues.m opt.cfar),
%               T1, T2 and m0 from the clean gaps of the training rows
%     LBH       B and the lost-branch and level head (fuse_head.m), fitted on B's
%               out-of-fold probabilities over the training folds only
%     LBH+CFAR  the head on CFAR's linear fusion; GCC+CFAR
%   Every fitted part of a reading (the linear fusion, the probabilities that feed the head,
%   the head, T1, T2, m0) is fitted on its training folds only, so a reading of a fold never
%   holds anything fitted on it. A fit depends on its training rows alone (the linear fusion
%   starts from zero, a head's stream is named by its folds), so each is made once and kept:
%   a fit is named by the folds it leaves out, E. A kept fit is written whole and then renamed
%   (commit_mat.m); one that does not read is fitted again.
%   D = fusion_cand('data', fit, Z0, XB, cues, yt, fold, C, lambda, N, classes, ck)
%       fit the fit set (run, pos, idle, level), Z0 its window rows without further columns
%       (fuse_classes 'windows'), XB the base's further columns (cues, fuse_classes 'extra'),
%       yt the targets, fold 1..K per row, ck a folder for the fits' outputs ('' none)
%   P = fusion_cand('pred', D, cand, E)   the rows of the folds E read by cand fitted on the
%       other folds (fold order of the rows kept)
%   pc = fusion_cand('oof', D, cand, ks, X)   n x C: the rows of each fold k in ks read by cand
%       fitted without the folds k and X (NaN elsewhere); X empty on the whole fit set, the
%       outer fold inside it
%   [n1, n2, n] = fusion_cand('exc', D, E, k)  clean gaps of fold k above T1 and above T2 of
%       the thresholds fitted without the folds E, and their number
%   T = fusion_cand('thr', D, tr)   T1, T2 (the smallest crest and spread exceeded by at most
%       1% of the clean gaps of the rows tr, nearest rank) and m0 (their median crest) [dB]
%   X = fusion_cand('cfar', D, T)   the idle columns of every row at T (window_cues.m's)
%   H = fusion_cand('head', D, cand, E)   the head of cand fitted without the folds E
%   M = fusion_cand('fit', D, cand)  cand fitted on every row: M.FM (the head and the gated
%       columns inside), M.cues (the further columns its readers build), M.T
%   thr = fusion_cand('kpi1_thr', yt, yp, bin, C)  the lowest Eb/N0 from which macro-F1 stays
%       >= 90% (select_fusion.m)
%   names = fusion_cand('names')   the candidates
switch cmd
    case 'data',     varargout{1} = data(varargin{:});
    case 'pred',     varargout{1} = pred(varargin{:});
    case 'oof',      varargout{1} = oof(varargin{:});
    case 'exc',      [varargout{1}, varargout{2}, varargout{3}] = exc(varargin{:});
    case 'thr',      varargout{1} = thr_rows(varargin{:});
    case 'cfar',     varargout{1} = cfar_cols(varargin{:});
    case 'head',     varargout{1} = head(varargin{:});
    case 'fit',      varargout{1} = fit_all(varargin{:});
    case 'kpi1_thr', varargout{1} = kpi1_thr(varargin{:});
    case 'names',    varargout{1} = {'LBH', 'GCC', 'CFAR', 'LBH+CFAR', 'GCC+CFAR'};
    otherwise, error('fusion_cand:cmd', 'fusion_cand: unknown command %s', cmd);
end
end

function D = data(fit, Z0, XB, cues, yt, fold, C, lambda, N, classes, ck)
n = numel(fit.run);
assert(size(Z0, 1) == n && size(XB, 1) == n && numel(yt) == n && numel(fold) == n, 'fusion_cand:rows', 'rows differ');
I = nan(n, numel(idle_summary('names')));
if isfield(fit, 'idle') && ~isempty(fit.idle), I = double(fit.idle); end
nm = idle_summary('names'); col = @(s) I(:, strcmp(nm, s));
okg = col('gap_ms') > 0 & ~isnan(col('occ'));
W = zeros(n, N);                                   % each row's window, oldest first, 0 before its run
[~, ~, rid] = unique(fit.run(:));
byrun = accumarray(rid, (1:n)', [], @(v) {v});
for r = 1:numel(byrun)
    ix = byrun{r};
    [~, o] = sort(fit.pos(ix)); ix = ix(o);
    for j = 1:numel(ix)
        w = ix(max(1, j - N + 1):j);
        W(ix(j), N - numel(w) + 1:N) = w;
    end
end
D = struct('Z0', Z0, 'XB', XB, 'cues', cues, 'yt', double(yt(:)), 'fold', double(fold(:)), 'K', max(fold), ...
    'C', C, 'lambda', lambda, 'L', fuse_head('classes', classes), 'okg', okg, 'clean', okg & isnan(double(fit.level(:))), ...
    'cr', col('max') - col('p10'), 'sp', col('p90') - col('p10'), 'W', W, 'ck', ck);
D.cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
if ~isempty(ck) && ~isfolder(ck), mkdir(ck); end
end

function X = cfar_cols(D, T)
v = D.W > 0; Wi = max(D.W, 1);
ok = v & D.okg(Wi);
cr = D.cr(Wi); cr(~v) = NaN;
sp = D.sp(Wi); sp(~v) = NaN;
nv = sum(ok, 2); has = nv > 0;
X = zeros(size(D.W, 1), 4);
X(has, 1) = sum(ok(has, :) & cr(has, :) > T(1), 2) ./ nv(has);
X(has, 2) = sum(ok(has, :) & sp(has, :) > T(2), 2) ./ nv(has);
mc = sum(cr .* ok, 2, 'omitnan') ./ max(nv, 1);
X(has, 3) = max(0, mc(has) - T(3));
X(:, 4) = ok(:, end) & cr(:, end) > T(1);
X(~isfinite(X)) = 0;
end

function T = thr_rows(D, tr)
ok = tr(:) & D.clean;
cr = sort(D.cr(ok)); sp = sort(D.sp(ok));
q = @(x) x(max(1, ceil(0.99 * numel(x))));
T = [q(cr), q(sp), median(cr)];
end

function T = thr_ex(D, E)
key = sprintf('T_m%02d', mask(E));
T = ck_get(D, key);
if isempty(T), T = thr_rows(D, ~ismember(D.fold, E)); ck_put(D, key, T); end
end

function [n1, n2, n] = exc(D, E, k)
T = thr_ex(D, E);
m = D.fold == k & D.clean;
n1 = sum(D.cr(m) > T(1)); n2 = sum(D.sp(m) > T(2)); n = sum(m);
end

function [Zv, opt] = row(D, v, E)
% The candidate's row without the gated columns: the window row, the idle columns at the
% thresholds fitted without the folds E (CFAR), the base's further columns.
opt = D.cues; Xc = zeros(size(D.Z0, 1), 0);
if contains(v, 'CFAR'), T = thr_ex(D, E); Xc = cfar_cols(D, T); opt.cfar = T; end
Zv = [D.Z0, Xc, D.XB];
end

function v = level0(cand)
v = strrep(cand, 'LBH+', ''); if strcmp(v, 'LBH'), v = 'B'; end
end

function P = l0(D, v, E)
% The linear fusion of variant v fitted without the folds E, read on the rows of E.
key = sprintf('l0_%s_m%02d', strrep(v, '+', '_'), mask(E));
P = ck_get(D, key);
if ~isempty(P), return; end
tr = ~ismember(D.fold, E);
[Zv, opt] = row(D, v, E);
FM = fit_l0(D, Zv, opt, v, tr);
P = fuse_classes('apply', FM, Zv(~tr, :));
ck_put(D, key, P);
end

function FM = fit_l0(D, Zv, opt, v, tr)
Zf = Zv;
if contains(v, 'GCC'), g = fuse_classes('gcc', D.C, opt); Zf = [Zv, fuse_classes('gcc_x', Zv, g)]; end
FM = fuse_classes('fit', Zf(tr, :), D.yt(tr), D.C, D.lambda);
if contains(v, 'GCC'), FM.gcc = g; end
end

function po = l0_oof(D, v, E)
% The level-0 probabilities that feed a head fitted without the folds E: each training fold j
% read by the linear fusion fitted without E and j.
po = nan(numel(D.fold), D.C);
for j = setdiff(1:D.K, E)
    Ej = sort([E(:)', j]);
    P = l0(D, v, Ej);
    po(D.fold == j, :) = P(D.fold(ismember(D.fold, Ej)) == j, :);
end
end

function H = head(D, cand, E)
key = sprintf('H_%s_m%02d', strrep(cand, '+', '_'), mask(E));
H = ck_get(D, key);
if ~isempty(H), return; end
v = level0(cand);
[Zv, opt] = row(D, v, E);
tr = ~ismember(D.fold, E);
po = l0_oof(D, v, E);
H = fuse_head('fit', po(tr, :), Zv(tr, :), D.yt(tr), D.L, fuse_head('cols', D.C, opt), fuse_head('seed', cand, E));
if isequal(E, 1), D.cache(key) = H; end                % kept in memory for its timing
end

function P = pred(D, cand, E)
E = sort(E(:)');
if ~contains(cand, 'LBH'), P = l0(D, cand, E); return; end
key = sprintf('hd_%s_m%02d', strrep(cand, '+', '_'), mask(E));
P = ck_get(D, key);
if ~isempty(P), return; end
H = head(D, cand, E);
v = level0(cand);
Zv = row(D, v, E);
P = fuse_head('apply', H, l0(D, v, E), Zv(ismember(D.fold, E), :));
ck_put(D, key, P);
end

function pc = oof(D, cand, ks, X)
if nargin < 4, X = []; end
pc = nan(numel(D.fold), D.C);
for k = ks(:)'
    E = sort([X(:)', k]);
    P = pred(D, cand, E);
    pc(D.fold == k, :) = P(D.fold(ismember(D.fold, E)) == k, :);
end
end

function M = fit_all(D, cand)
v = level0(cand);
[Zv, opt] = row(D, v, []);
FM = fit_l0(D, Zv, opt, v, true(numel(D.fold), 1));
if contains(cand, 'LBH')
    po = l0_oof(D, v, []);
    FM.head = fuse_head('fit', po, Zv, D.yt, D.L, fuse_head('cols', D.C, opt), fuse_head('seed', cand, []));
end
T = []; if contains(cand, 'CFAR'), T = opt.cfar; end
M = struct('FM', FM, 'cues', opt, 'T', T);
end

function thr = kpi1_thr(yt, yp, bin, C)
u = unique(bin(~isnan(bin)));
f = arrayfun(@(v) 100 * mf1(yt(bin == v), yp(bin == v), C), u);
k = find(f < 90, 1, 'last'); if isempty(k), k0 = 1; else, k0 = k + 1; end
thr = NaN; if k0 <= numel(u), thr = u(k0); end
end

function m = mf1(y, yh, C)
cm = accumarray([y(:) yh(:)], 1, [C C]);
pr = diag(cm) ./ sum(cm, 1)'; rc = diag(cm) ./ sum(cm, 2);
f = 2 * pr .* rc ./ (pr + rc); m = mean(f(sum(cm, 2) > 0), 'omitnan');
end

function m = mask(E)
m = sum(2 .^ (E(:)' - 1));
end

function x = ck_get(D, key)
x = [];
if isKey(D.cache, key), x = D.cache(key); return; end
if isempty(D.ck), return; end
f = fullfile(D.ck, [key '.mat']);
if ~isfile(f), return; end
try
    L = load(f, 'x'); x = L.x; D.cache(key) = x;
catch
    x = [];                                        % a file that does not read is fitted again
end
end

function ck_put(D, key, x)
D.cache(key) = x;
if isempty(D.ck), return; end
t = fullfile(D.ck, [key '_new.mat']);
save(t, 'x', '-v7.3');
commit_mat(t, fullfile(D.ck, [key '.mat']));       % written whole, then one rename
end
