function [c, s, r] = flight_triples(cells, rr, ss)
%FLIGHT_TRIPLES  Every (cell, Eb/N0 index, geometry) of a set of pool cells, as rows.
%   [c, s, r] = flight_triples(cells, rr, ss)
%   rr  the geometries every cell flies (one vector), or one vector per cell (a cell array:
%       link_env.m K.geo, PP.cell_geo); ss the Eb/N0 indices
%   Cells that fly the same geometries are taken together in the order of
%   ndgrid(cells, ss, geometries), the groups in the order of their first cell, so a set of
%   cells that all fly the same geometries gives ndgrid's order. 1 x n each.
if ~iscell(rr), rr = repmat({rr}, 1, numel(cells)); end
key = cellfun(@(x) mat2str(x(:)'), rr, 'UniformOutput', false);
[u, ~, j] = unique(key, 'stable');
[c, s, r] = deal(zeros(1, 0));
for k = 1:numel(u)
    cc = cells(j == k); g = rr{find(j == k, 1)};
    if isempty(g) || isempty(ss), continue; end
    [c_, s_, r_] = ndgrid(cc, ss, g);
    c = [c, c_(:)']; s = [s, s_(:)']; r = [r, r_(:)']; %#ok<AGROW>
end
end
