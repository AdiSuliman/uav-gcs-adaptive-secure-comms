function PP = clean_split(PP, CT, sp)
%CLEAN_SPLIT  The pools with split sp replaced by the independent clean-link geometries of
%   CT (build_clean_test_pools.m): the clean cell flies CT's geometries there and no other
%   cell flies the split. Every per-geometry field of the split follows CT's runs: the
%   geometry ids, the event frames (the clean geometries roll into no turn: NaN,
%   link_env.m), the speeds, the per-flight draws (cov, alt, ksig: CT.cov, flight_cov.m),
%   the clean cell's geometries, and no reference-only geometry (ref_geo). A field CT does
%   not carry is left empty, never the replaced geometries'.
nS = numel(PP.ebno); nA = numel(PP.actions); n = numel(CT.runs);
ic = find(strcmp(PP.scen, 'none'), 1);
PP.pools(:, :, :, sp) = {[]};
PP.pools(ic, :, :, sp) = reshape(CT.pools(1, :, :), [1 nS nA]);
PP.runs{sp} = CT.runs;
if isfield(PP, 'event_frame') && ~isempty(PP.event_frame), PP.event_frame{sp} = nan(1, n); end
if isfield(PP, 'speed'), PP.speed{sp} = []; if isfield(CT, 'speed'), PP.speed{sp} = CT.speed; end, end
cv = []; if isfield(CT, 'cov'), cv = CT.cov; end
if isfield(PP, 'cov'), PP.cov{sp} = cv; end
if isfield(PP, 'alt'), PP.alt{sp} = []; if ~isempty(cv), PP.alt{sp} = cv.alt_m; end, end
if isfield(PP, 'ksig'), PP.ksig{sp} = []; if ~isempty(cv), PP.ksig{sp} = cv.k_sig; end, end
if isfield(PP, 'ref_geo'), PP.ref_geo{sp} = zeros(1, 0); end
if isfield(PP, 'cell_geo') && numel(PP.cell_geo) >= ic, PP.cell_geo{ic}{sp} = 1:n; end
end
