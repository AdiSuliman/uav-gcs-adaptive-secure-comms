function varargout = fuse_head(cmd, varargin)
%FUSE_HEAD  The lost-branch and level head of the temporal fusion: bagged classification
%   trees (Breiman 2001) over the receiver's own branch, level-step, coherence and
%   line-of-sight columns and the linear fusion's probabilities of the four level-family
%   classes L = {none, path_loss, antenna_fault, airframe_shadowing}, stacked on the linear
%   fusion's out-of-fold probabilities (Wolpert 1992, Sec. 2: the level-1 learner on held-out
%   level-0 outputs). Only the share among the L classes moves: p_L = sum over L of p(c),
%   p(c) = p_L q(c | x) for c in L, every other class keeps the linear fusion's p(c). The
%   coherence and LOS columns mean something only once a branch has stepped, which a linear
%   fusion cannot use; a hidden antenna loses its line of sight (Sun et al., Part IV), a faulty
%   connector keeps it.
%   cols = fuse_head('cols', C, opt)   the head's columns of the fusion row (fuse_classes.m
%       'windows' with opt's further columns): window_cues.m's branch cues 1-16 (margin_mean
%       and sinr_gap_w among them), the level-step cues 17-21, the coherence and LOS columns
%       43-52, and the branch-evidence columns iso, glr without gl_phi, post and held. No idle
%       column, no antenna index or position, no truth field
%   L = fuse_head('classes', classes)  the indices of the L classes
%   X = fuse_head('inputs', H, pc, Z)  the log of the linear fusion's L probabilities and of
%       their sum (floored at 1e-6, as fuse_classes.m), then Z(:, H.cols)
%   H = fuse_head('fit', pc, Z, yt, L, cols, seed)  on the rows whose target yt is in L:
%       100 trees, MinLeafSize 20, the toolbox's default number of predictors per split; the
%       global stream seeded with seed (twister) and restored after. H holds the packed trees
%       only, never a TreeBagger, so its bytes (detector_id.m) are stable
%   H = fuse_head('pack', T, nL)       a TreeBagger fitted on labels 1..nL as flat arrays: var
%       (split column, 0 at a leaf), thr, kids (left x < thr, right x >= thr; a leaf points to
%       itself), prob (the leaf's class probabilities, label order), root (each tree's first row)
%   q = fuse_head('score', H, X)       the mean over the trees of the leaf probabilities, all
%       trees walked at once one vector step per level (iforest_score.m's method); a NaN stops
%       the walk at its node, as the toolbox does without surrogate splits
%   pc = fuse_head('apply', H, pc, Z)  the combination above
%   s = fuse_head('seed', cand, E)     the trees' stream of a head fitted without the folds E
%       (cand 'LBH' or 'LBH+CFAR'); E empty: fitted on every fold
switch cmd
    case 'cols',    varargout{1} = cols_of(varargin{:});
    case 'classes', varargout{1} = classes_of(varargin{:});
    case 'inputs',  varargout{1} = inputs(varargin{:});
    case 'fit',     varargout{1} = fit(varargin{:});
    case 'pack',    varargout{1} = pack(varargin{:});
    case 'score',   varargout{1} = score(varargin{:});
    case 'apply',   varargout{1} = apply(varargin{:});
    case 'seed',    varargout{1} = seed_of(varargin{:});
    otherwise, error('fuse_head:cmd', 'fuse_head: unknown command %s', cmd);
end
end

function c = cols_of(C, opt)
nm = fuse_classes('names', C, opt);
wn = window_cues('names');
nT = numel(temporal_evidence('names', C));
c = nT + [1:21, 43:52];
en = window_cues('extra_names', opt);
keep = ~strncmp(en, 'cf_', 3) & ~strcmp(en, 'gl_phi');
c = [c, nT + numel(wn) + C + find(keep)];
assert(sum(keep) == 18, 'fuse_head:cols', 'the head needs the 18 branch-evidence columns (iso, glr, post, held), found %d', sum(keep));
assert(numel(nm) >= max(c), 'fuse_head:cols', 'the fusion row has %d columns', numel(nm));
end

function L = classes_of(classes)
classes = cellstr(string(classes));
[ok, L] = ismember({'none', 'path_loss', 'antenna_fault', 'airframe_shadowing'}, classes);
assert(all(ok), 'fuse_head:classes', 'the head needs none, path_loss, antenna_fault and airframe_shadowing');
end

function X = inputs(H, pc, Z)
pl = pc(:, H.L);
X = [log(max(pl, 1e-6)), log(max(sum(pl, 2), 1e-6)), Z(:, H.cols)];
end

function H = fit(pc, Z, yt, L, cols, seed)
m = ismember(yt(:), L);
[~, y] = ismember(yt(m), L);
X = inputs(struct('L', L(:)', 'cols', cols(:)'), pc(m, :), Z(m, :));
s0 = rng; back = onCleanup(@() rng(s0));
rng(seed, 'twister');
T = TreeBagger(100, X, y, 'Method', 'classification', 'MinLeafSize', 20);
H = pack(T, numel(L));
H.L = L(:)'; H.cols = cols(:)';
end

function H = pack(T, nL)
tr = T.Trees; nT = numel(tr);
n = cellfun(@(t) t.NumNodes, tr);
off = [0; cumsum(n(:))];
H = struct('var', zeros(off(end), 1, 'int32'), 'thr', zeros(off(end), 1), 'kids', zeros(off(end), 2, 'int32'), ...
    'prob', zeros(off(end), nL), 'root', int32(off(1:nT) + 1));
for t = 1:nT
    c = tr{t}; m = c.NumNodes; r = off(t) + (1:m)';
    br = logical(c.IsBranchNode(:));
    ct = cellstr(c.CutType);
    if any(strcmp(ct(br), 'categorical')), error('fuse_head:categorical', 'categorical splits are not supported'); end
    [~, v] = ismember(cellstr(c.CutPredictor), cellstr(c.PredictorNames));
    v(~br) = 0;
    kids = double(c.Children); kids(~br, :) = [find(~br), find(~br)];
    th = c.CutPoint(:); th(~br) = 0;
    [ok, j] = ismember(str2double(string(c.ClassNames)), 1:nL);
    P = zeros(m, nL); P(:, j(ok)) = c.ClassProbability(:, ok);
    H.var(r) = v; H.thr(r) = th; H.kids(r, :) = kids + off(t); H.prob(r, :) = P;
end
end

function q = score(H, X)
X = double(X);
[n, d] = size(X); nL = size(H.prob, 2); nT = numel(H.root);
q = zeros(n, nL);
B = 20000;                                         % rows per block: nT x B nodes at a time
for i0 = 1:B:n
    r = i0:min(i0 + B - 1, n); m = numel(r);
    Xt = X(r, :)';
    node = repmat(H.root, 1, m);
    base = repmat(int32(0:m - 1) * d, nT, 1);
    k = find(H.var(node) > 0);
    while ~isempty(k)
        nk = node(k);
        x = Xt(base(k) + H.var(nk));
        lt = x < H.thr(nk); ge = x >= H.thr(nk);
        node(k(lt)) = H.kids(nk(lt), 1); node(k(ge)) = H.kids(nk(ge), 2);
        k = k(lt | ge);
        k = k(H.var(node(k)) > 0);
    end
    q(r, :) = reshape(mean(reshape(H.prob(node(:), :), nT, m, nL), 1), m, nL);
end
end

function pc = apply(H, pc, Z)
q = score(H, inputs(H, pc, Z));
pc(:, H.L) = sum(pc(:, H.L), 2) .* q;
end

function s = seed_of(cand, E)
b = struct('LBH', 9400, 'LBH_CFAR', 9500);
f = strrep(cand, '+', '_');
assert(isfield(b, f), 'fuse_head:seed', 'no head in %s', cand);
assert(all(ismember(E, 1:5)) && numel(unique(E)) == numel(E), 'fuse_head:seed', 'folds 1..5');
s = b.(f) + sum(2 .^ (E(:)' - 1));
end
