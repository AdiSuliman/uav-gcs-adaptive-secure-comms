function O = surv_options(f)
%SURV_OPTIONS  The survivability map's protocol of this checkout (map_survivability_boundary.m):
%   the optional field surv_v2 of its profile.json (f, default 'profile.json').
%   O.v2 false  no profile.json or no surv_v2 (profile 1): one flight per cell with a seed of
%               its own per level and Eb/N0, noise bursts at the fixed duty p.burst_duty
%   O.v2 true   "surv_v2": true (docs/surv_p3_protocol.md): O.NR flights per cell, the same at
%               every level and Eb/N0 (surv_flights.m), noise bursts as two entries
%               (surv_nb_entries.m), the link-limited, no_action and saturated marks, a
%               bootstrap interval and a committed verdict per cell (surv_grid.m), two gap
%               classes (surv_gap_report.m); experiment_survivability_options.m runs its section 10
%   O.NR        flights per cell: 1, or 5 (the clean link's repeats) under surv_v2
if nargin < 1 || isempty(f), f = 'profile.json'; end
O = struct('v2', false, 'NR', 1);
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P) || ~isfield(P, 'surv_v2'), return; end
v = P.surv_v2;
if ~(isscalar(v) && islogical(v)), error('surv_options:value', '%s: surv_v2 must be true or false', f); end
if v, O = struct('v2', true, 'NR', 5); end
end
