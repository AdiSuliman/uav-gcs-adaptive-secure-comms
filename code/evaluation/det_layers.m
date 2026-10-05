function [det, deth, detu] = det_layers(F, TGT, B)
%DET_LAYERS  The detection layers of edge_map.m over the flights F (fields det_k, det_n:
%   detected and decided cycles per flight; geo: flight; harm: the unmitigated link is not
%   restored): DET over all of them, DET_h over the harmed ones and DET_u over the others,
%   each an edge_verdict.m against TGT.det with B bootstrap draws.
det = edge_verdict(F.det_k, F.det_n, F.geo, TGT.det, 'ge', false, B);
m = F.harm;
deth = edge_verdict(F.det_k(m), F.det_n(m), F.geo(m), TGT.det, 'ge', false, B);
if nargout > 2, detu = edge_verdict(F.det_k(~m), F.det_n(~m), F.geo(~m), TGT.det, 'ge', false, B); end
end
