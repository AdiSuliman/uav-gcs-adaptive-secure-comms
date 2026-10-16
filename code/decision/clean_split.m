function PP = clean_split(PP, CT, sp)
%CLEAN_SPLIT  The pools with split sp replaced by the independent clean-link geometries of
%   CT (build_clean_test_pools.m): the clean cell flies CT's geometries there and no other
%   cell flies the split. Every per-geometry field of the split follows CT's runs: the
%   geometry ids, the event frames (the clean geometries roll into no turn: NaN,
%   link_env.m), the speeds and the clean cell's geometries.
nS = numel(PP.ebno); nA = numel(PP.actions); n = numel(CT.runs);
ic = find(strcmp(PP.scen, 'none'), 1);
PP.pools(:, :, :, sp) = {[]};
PP.pools(ic, :, :, sp) = reshape(CT.pools(1, :, :), [1 nS nA]);
PP.runs{sp} = CT.runs;
if isfield(PP, 'event_frame') && ~isempty(PP.event_frame), PP.event_frame{sp} = nan(1, n); end
if isfield(PP, 'speed') && isfield(CT, 'speed'), PP.speed{sp} = CT.speed; end
if isfield(PP, 'cell_geo') && numel(PP.cell_geo) >= ic, PP.cell_geo{ic}{sp} = 1:n; end
end
