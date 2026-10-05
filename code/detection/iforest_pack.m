function P = iforest_pack(F)
%IFOREST_PACK  The trees of a trained isolation forest (iforest) as flat arrays for
%   iforest_score.m: one row per node of every tree, numerical splits only.
%   F   IsolationForest of the Statistics and Machine Learning Toolbox
%   P   var (split variable, 0 = leaf), thr (split value), kids (left and right
%       child rows), cf (path-length correction c(n) of a leaf with n training
%       observations, Liu, Ting & Zhou 2012), root (first row of every tree),
%       bad (constant predictors dropped at training), c (c of the sub-sample size)
S = toStruct(F);                                   % the toolbox's own export of the trees (code generation)
nT = numel(S.Trees);
n = cellfun(@(t) max(t.NumNodes, 1), S.Trees);
off = [0; cumsum(n(:))];
P = struct('var', zeros(off(end), 1, 'int32'), 'thr', zeros(off(end), 1), 'kids', ones(off(end), 2, 'int32'), ...
    'cf', zeros(off(end), 1), 'root', int32(off(1:nT) + 1), 'bad', logical(S.IsBadVariable(:)'), ...
    'c', cfac(double(S.NumObservationsPerLearner)));
for t = 1:nT
    T = S.Trees{t}; m = T.NumNodes;
    if m == 0, continue; end                       % an empty tree adds depth 0 (one leaf, c(0) = 0)
    if any(T.CatSplitLogicalIndices(1:m)), error('iforest_pack:categorical', 'categorical splits are not supported'); end
    r = off(t) + (1:m)';
    cs = T.ContSplitLogicalIndices(1:m);
    th = zeros(m, 1); th(cs) = T.ContSplit(T.ContSplitIndices(cs));
    kids = T.Children(1:m, :); leaf = T.SplitVariable(1:m) == 0;
    kids(leaf, :) = [find(leaf), find(leaf)];       % a leaf points to itself
    P.var(r) = T.SplitVariable(1:m); P.thr(r) = th;
    P.kids(r, :) = kids + off(t);
    P.cf(r(leaf)) = cfac(double(T.NumObservations(leaf)));
end
end

function c = cfac(n)
% Average path length of an unsuccessful search in a binary tree of n points, c(0) = 0.
c = 2 * psi(max(n, 1)) - 2 * psi(1) - 2 * (1 - 1 ./ max(n, 1));
c(n == 0) = 0;
end
