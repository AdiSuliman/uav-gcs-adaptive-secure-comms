function n = profile_forced_fields(f)
%PROFILE_FORCED_FIELDS  The forced cells a profile.json holds (f, default 'profile.json'): every
%   field whose name ends in _force (dconf_force, s1g_force, relm_force, lb_force, aprime_force,
%   deg_force, ...). They belong to the smoke form of profile 3 only; a stage refuses them
%   outside the smoke, hours into the chain (wf_force.m, train_dqn.m), so the release check
%   asserts that a real profile.json holds none.
%   n  row cell of the field names, {} without the file, a struct or a forced field
if nargin < 1 || isempty(f), f = 'profile.json'; end
n = {};
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P), return; end
k = fieldnames(P)';
n = k(endsWith(lower(k), '_force'));
end
