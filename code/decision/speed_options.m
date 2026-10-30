function O = speed_options(cfg, f)
%SPEED_OPTIONS  The speed readings of this checkout: the fields of CFG when cfg is a struct with them,
%   else the optional fields of its profile.json (f, default 'profile.json'). Each is off without
%   its field (profile 1's chain: every output unchanged).
%   O.inference   "speed_inference": true prints the speed inference lines beside the registered
%                 spread (per-band cluster intervals, permutation test, Hall & Miller bound;
%                 speed_reading.m) and the hover and 161 km/h lines with cluster intervals and the
%                 like-for-like value (speed_edge_lines.m) in evaluate_policies.m; false
%   O.union       "kpi7_union": 'descriptive' flies the second test split's single set for the
%                 deployed policy and prints KPI 7's speed spread on the union of the test and
%                 second-test single sets beside the test-only line, which stays the verdict;
%                 'verdict' makes the union line the verdict and needs "kpi7_union_yes", the date
%                 and time of the approval; 'off' without the field
%   O.yes         "kpi7_union_yes": the approval's date and time as text; '' without it
%   O.band_table  "speed_band_table": true prints the selected agent's recovered per speed band and
%                 Eb/N0 on validation and its harmed lost-branch episodes per band after C2
%                 (speed_band_table.m, train_dqn.m); false
%   O.edge161_n   "edge161_n": geometries per Eb/N0 of build_policy_pools.m's edge-speed split, the
%                 first 24 at hover and the rest at 161 km/h: 36 without it (12 at 161 km/h), or 48
%                 (24 at 161 km/h); any other value stops
if nargin < 1, cfg = []; end
if nargin < 2 || isempty(f), f = 'profile.json'; end
O = struct('inference', false, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
P = struct();
if isfile(f)
    P = jsondecode(fileread(f));
    if ~isstruct(P), P = struct(); end
end
names = {'speed_inference', 'kpi7_union', 'kpi7_union_yes', 'speed_band_table', 'edge161_n'};
V = struct(); src = struct();
for i = 1:numel(names)
    if isstruct(cfg) && isfield(cfg, names{i})
        V.(names{i}) = cfg.(names{i}); src.(names{i}) = ['CFG.' names{i}];
    elseif isfield(P, names{i})
        V.(names{i}) = P.(names{i}); src.(names{i}) = [f ': ' names{i}];
    end
end
if isfield(V, 'speed_inference'), O.inference = flag(V.speed_inference, src.speed_inference); end
if isfield(V, 'speed_band_table'), O.band_table = flag(V.speed_band_table, src.speed_band_table); end
if isfield(V, 'kpi7_union')
    v = V.kpi7_union;
    if ~((ischar(v) || isstring(v)) && any(strcmp(v, {'off', 'descriptive', 'verdict'})))
        error('speed_options:value', '%s must be "off", "descriptive" or "verdict"', src.kpi7_union);
    end
    O.union = char(v);
end
if isfield(V, 'kpi7_union_yes')
    v = V.kpi7_union_yes;
    if ~((ischar(v) || isstring(v)) && ~isempty(strtrim(char(v))))
        error('speed_options:yes', '%s must be the date and time of Adi''s approval, as text', src.kpi7_union_yes);
    end
    O.yes = strtrim(char(v));
end
if strcmp(O.union, 'verdict') && isempty(O.yes)
    error('speed_options:yes', ['kpi7_union "verdict" needs kpi7_union_yes, the date and time of Adi''s approval of ' ...
        'D117 point 1 (without it the union line is descriptive)']);
end
if ~strcmp(O.union, 'verdict') && ~isempty(O.yes)
    error('speed_options:yes', 'kpi7_union_yes is set, but kpi7_union is "%s", not "verdict"', O.union);
end
if isfield(V, 'edge161_n')
    v = V.edge161_n;
    if ~(isnumeric(v) && isscalar(v) && any(v == [36 48]))
        error('speed_options:value', '%s must be 36 (today''s pools) or 48 (D117 point 2)', src.edge161_n);
    end
    O.edge161_n = double(v);
end
end

function v = flag(v, what)
if ~(isscalar(v) && islogical(v)), error('speed_options:value', '%s must be true or false', what); end
end
