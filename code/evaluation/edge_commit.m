function X = edge_commit(L, veto)
%EDGE_COMMIT  The commitment at the Eb/N0 points of one (threat, level) (edge_map.m).
%   X = edge_commit(L, veto)
%   L      verdicts per Eb/N0 point, ascending (1 x nS each; 1 COMMITTED, 0 UNDETERMINED,
%          -1 NOT COMMITTED): prot, deth and deth_n (DET_h and its harmed flights), fa
%          (the claim's false alarms), link, linkt; optional fa_pt (the point's own false
%          alarms: NOT COMMITTED there makes FA NOT COMMITTED); fav (1 when the deployed
%          policy met the false-alarm bound on validation, else 0)
%   veto   [b, names] = veto(R): -1 and the bands' names when a band of the flights of
%          the Eb/N0 points R is NOT COMMITTED, else 1
%   A point is COMMITTED when PROT, DET_h, FA, LINK and LINK_T are, F holds, and no band
%   is NOT COMMITTED. DET_h on fewer harmed flights than N_MIN (edge_verdict.m) only must
%   not be NOT COMMITTED: a threat that seldom harms the link cannot show its detection
%   there. The bands pool the point and every point above it while the points are
%   COMMITTED before the veto from the top Eb/N0 down (the region of the distance walk);
%   a point outside that run pools its own flights; a point not COMMITTED before the veto
%   gets no band reading.
%   X.v, X.lim  verdict and the parts not COMMITTED (P PROT, H DET_h, A FA, L LINK, T
%               LINK_T, F the bound on validation, B a band); X.h DET_h and X.fa FA as
%               read; X.band the veto (NaN: not read) and X.bfail its bands
Z = edge_verdict([], [], [], 0.9, 'ge', false);
nS = numel(L.prot);
X.h = L.deth;
X.h(L.deth_n < Z.n_min & L.deth ~= -1) = 1;
X.fa = L.fa;
if isfield(L, 'fa_pt'), X.fa(L.fa_pt == -1) = -1; end
parts = [L.prot(:), X.h(:), X.fa(:), L.link(:), L.linkt(:), L.fav + zeros(nS, 1)];
pre = all(parts == 1, 2)';
s_lo = nS + 1; while s_lo > 1 && pre(s_lo - 1), s_lo = s_lo - 1; end
X.band = nan(1, nS); X.bfail = repmat({''}, 1, nS);
for s = find(pre)
    R = s; if s >= s_lo, R = s:nS; end
    [X.band(s), X.bfail{s}] = veto(R);
end
X.v = zeros(1, nS); X.lim = repmat({''}, 1, nS);
for s = 1:nS
    b = X.band(s); if isnan(b), b = 1; end
    vd = [parts(s, :), b];
    if all(vd == 1), X.v(s) = 1; elseif any(vd == -1), X.v(s) = -1; end
    X.lim{s} = 'PHALTFB'; X.lim{s} = X.lim{s}(vd ~= 1);
end
end
