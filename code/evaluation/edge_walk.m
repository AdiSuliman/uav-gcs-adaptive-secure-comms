function W = edge_walk(vd, x, i0)
%EDGE_WALK  Fixed-sequence walks of the edge map (edge_map.m): each stops at the first
%   point not COMMITTED.
%   W = edge_walk(vd, x)
%   vd, x  verdicts (1 COMMITTED, 0 UNDETERMINED, -1 NOT COMMITTED, NaN none) and their
%          values in walk order (Eb/N0 from the top down, follower re-acquisition from the
%          slowest down, K from the top band down)
%   W.edge the last value of the leading COMMITTED run (NaN when the first point is not
%          COMMITTED); W.first_not the first NOT COMMITTED value; W.nonmono a COMMITTED
%          point lies beyond a NOT COMMITTED one
%   W = edge_walk(vd, x, i0)
%          two walks from x(i0) (x ascending: levels from the nominal one down and up),
%          each step one-sided at 2.5%, so the pair keeps a 5% family error: the COMMITTED
%          run [W.lo, W.hi] around x(i0) (NaN when x(i0) is not COMMITTED), the first NOT
%          COMMITTED value on each side (W.first_lo, W.first_hi), and W.nonmono on either
if nargin < 3
    i = find(vd ~= 1, 1); if isempty(i), i = numel(vd) + 1; end
    W.edge = NaN; if i > 1, W.edge = x(i - 1); end
    j = find(vd == -1, 1);
    W.first_not = NaN; if ~isempty(j), W.first_not = x(j); end
    W.nonmono = ~isempty(j) && any(vd(j+1:end) == 1);
    return
end
U = edge_walk(vd(i0:end), x(i0:end)); D = edge_walk(vd(i0:-1:1), x(i0:-1:1));
W = struct('lo', D.edge, 'hi', U.edge, 'first_lo', D.first_not, 'first_hi', U.first_not, 'nonmono', U.nonmono || D.nonmono);
end
