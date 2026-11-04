function O = deg_options(f)
%DEG_OPTIONS  Whether C1d chooses the degradation test on validation (choose_drop_threshold.m,
%   docs/deg_fix_protocol.md): the optional field deg_select of this checkout's profile.json (f,
%   default 'profile.json'). O.on false without the file or the field (profile 1's chain: the
%   test stays C.deg_mode 'ratio' and C1d's outputs are unchanged). O.force: the optional field
%   deg_force, a candidate deployed instead of the adopted one in the smoke only (deg_force.m,
%   docs/p1r_protocol.md); '' without it.
if nargin < 1 || isempty(f), f = 'profile.json'; end
O = struct('on', false, 'force', '');
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P), return; end
if isfield(P, 'deg_force'), O.force = deg_force('check', P.deg_force, f); end
if ~isfield(P, 'deg_select'), return; end
v = P.deg_select;
if ~(isscalar(v) && islogical(v)), error('deg_options:value', '%s: deg_select must be true or false', f); end
O.on = v;
end
