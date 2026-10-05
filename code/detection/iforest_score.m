function s = iforest_score(P, Xf)
%IFOREST_SCORE  Anomaly score of an isolation forest, the value of isanomaly (Liu, Ting
%   & Zhou): 2^(-E[h(x)] / c(psi)), h the path length to the leaf plus the leaf's c(n).
%   All trees are walked at once, one vector step per tree level, so a single frame
%   costs a few tens of steps instead of a pass over every node of every tree.
%   P   packed forest (iforest_pack.m)
%   Xf  normalized link features, nFeat x N
%   s   1 x N, higher = more anomalous
X = double(Xf(~P.bad, :));
[d, N] = size(X);
nT = numel(P.root);
node = repmat(P.root, 1, N);
col = repmat(int32(0:N - 1) * d, nT, 1);
h = zeros(nT, N);
k = find(P.var(node) > 0);
while ~isempty(k)
    nk = node(k);
    x = X(col(k) + P.var(nk));
    lt = x < P.thr(nk); ge = x >= P.thr(nk);        % NaN goes neither way: the walk stops there, as in isanomaly
    mv = lt | ge;
    h(k(mv)) = h(k(mv)) + 1;
    node(k(lt)) = P.kids(nk(lt), 1); node(k(ge)) = P.kids(nk(ge), 2);
    k = k(mv);
    k = k(P.var(node(k)) > 0);
end
leaf = P.var(node) == 0;
h(leaf) = h(leaf) + P.cf(node(leaf));
s = pow2(-sum(h, 1) / nT / P.c);
end
