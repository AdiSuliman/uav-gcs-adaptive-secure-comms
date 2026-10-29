function s = kpi6_set(cfg, f)
%KPI6_SET  The clean flights KPI 6 (our extension) is read on in evaluate_policies.m:
%   CFG.kpi6_set when cfg is a struct with that field, else the field kpi6_set of this checkout's
%   profile.json (f, default 'profile.json').
%   'union'  without either (profile 1's chain, profile 3): every independent clean flight of
%            the test splits and of data/clean_test_pools.mat, as before
%   'fresh'  P1R (docs/p1r_protocol.md section 5): the verdict on data/clean_fresh_pools.mat
%            alone, read once (kpi6_fresh_marker.m); the union is printed beside it as a second
%            reading, descriptive
%   Any other value stops.
if nargin < 1, cfg = []; end
if nargin < 2 || isempty(f), f = 'profile.json'; end
s = 'union'; v = []; src = '';
if isstruct(cfg) && isfield(cfg, 'kpi6_set')
    v = cfg.kpi6_set; src = 'CFG.kpi6_set';
elseif isfile(f)
    P = jsondecode(fileread(f));
    if isstruct(P) && isfield(P, 'kpi6_set'), v = P.kpi6_set; src = [f ': kpi6_set']; end
end
if isempty(src), return; end
if ~((ischar(v) || isstring(v)) && any(strcmp(v, {'union', 'fresh'})))
    error('kpi6_set:value', '%s must be "union" or "fresh"', src);
end
s = char(v);
end
