function [geo, ref, nG, parts] = pool_layout(kind, grp, sev, nominal, NGEO, NCOMB, NHOVER, iSpd)
%POOL_LAYOUT  Geometries every pool cell flies per split (build_policy_pools.m).
%   kind     per cell: 0 the clean link, 1 a single threat, 2 a combined threat
%   grp      per cell: its airframe-shadowing group (shadow_groups.m), 0 without shadowing
%   sev      per cell: severity index; nominal: the nominal one
%   NGEO, NCOMB, NHOVER, iSpd as build_policy_pools.m
%   Positions in a split: 1..NGEO the shared geometries (every cell without airframe
%   shadowing, the clean link included); then NCOMB the combined threats' own; then, per
%   shadowing group, its own flights (part 1: the single threat's, and every cell's of the
%   group in a split without the combined threats' own; part 2: its combined threats' own),
%   each as many as the shared or combined geometries they stand for. At the edge speeds a
%   shadowing group flies only the 161 km/h flights of the nominal level (NGEO - NHOVER):
%   no source measures shadowing at hover, so the hover flights are left out.
%   geo{c}{sp}  positions cell c flies in split sp (empty: not flown); the clean link's are
%               the shared and combined ones, its flights of every statistic
%   ref{sp}     the shadowing groups' positions: the clean link flies them too, only as the
%               restoration reference and lead-in of the shadowing episodes (common random
%               numbers)
%   nG(sp)      geometries of the split
%   parts       group, split, part and positions of every group's own flights, in order
nC = numel(kind); nSp = numel(NGEO); nGr = max([grp(:); 0]);
shd = grp > 0;
% parts each group needs: a single at its split (the edge speeds only at the nominal level),
% a combination in the split's shared part or its own
use = false(nGr, nSp, 2);
for c = find(shd)
    for sp = 1:nSp
        if kind(c) == 1 && (sp ~= iSpd || sev(c) == nominal)
            use(grp(c), sp, 1) = true;
        elseif kind(c) == 2 && sp ~= iSpd
            use(grp(c), sp, 1 + (NCOMB(sp) > 0)) = true;
        end
    end
end
nG = NGEO + NCOMB;
pos = cell(nGr, nSp, 2); ref = cell(1, nSp);
parts = struct('group', {}, 'split', {}, 'part', {}, 'pos', {});
for sp = 1:nSp
    for g = 1:nGr
        n = [NGEO(sp) - NHOVER * (sp == iSpd), NCOMB(sp)];
        for k = 1:2
            if ~use(g, sp, k) || n(k) == 0, continue; end
            pos{g, sp, k} = nG(sp) + (1:n(k));
            nG(sp) = nG(sp) + n(k);
            ref{sp} = [ref{sp}, pos{g, sp, k}];
            parts(end+1) = struct('group', g, 'split', sp, 'part', k, 'pos', pos{g, sp, k}); %#ok<AGROW>
        end
    end
end
geo = cell(1, nC);
for c = 1:nC
    geo{c} = cell(1, nSp);
    for sp = 1:nSp
        if kind(c) == 0
            geo{c}{sp} = 1:NGEO(sp) + NCOMB(sp);
        elseif shd(c) && kind(c) == 1
            if sp ~= iSpd || sev(c) == nominal, geo{c}{sp} = pos{grp(c), sp, 1}; end
        elseif shd(c)
            if sp ~= iSpd, geo{c}{sp} = pos{grp(c), sp, 1 + (NCOMB(sp) > 0)}; end
        elseif kind(c) == 2
            if sp == iSpd, continue; end
            if NCOMB(sp) > 0, geo{c}{sp} = NGEO(sp) + (1:NCOMB(sp)); else, geo{c}{sp} = 1:NGEO(sp); end
        elseif sp == iSpd && sev(c) ~= nominal
            geo{c}{sp} = 1:NHOVER;
        else
            geo{c}{sp} = 1:NGEO(sp);
        end
    end
end
end
