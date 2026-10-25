function s = profile_skip_stages(f, known)
%PROFILE_SKIP_STAGES  Stages a profile's profile.json asks run_stage.m to skip.
%   s = profile_skip_stages(f, known): the optional field skip_stages of the JSON file f, a
%   list of stage names (e.g. {"n_rx": 3, "skip_stages": ["OHP", "GCSA"]}), as a 1 x n cell
%   of char; {} without the file, the field or names. known: the runner's stage names; a
%   name outside them is an error (a misspelt stage would otherwise run).
s = {};
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P) || ~isfield(P, 'skip_stages') || isempty(P.skip_stages), return; end
v = P.skip_stages;
if ischar(v) || isstring(v), v = cellstr(v); end
if ~iscell(v) || ~all(cellfun(@(x) ischar(x) || isstring(x), v))
    error('profile_skip_stages:type', '%s: skip_stages must be a list of stage names', f);
end
s = cellfun(@char, v(:)', 'UniformOutput', false);
bad = s(~ismember(s, known));
if ~isempty(bad)
    error('profile_skip_stages:unknown', '%s: skip_stages names %s, not a stage of run_stage.m', f, strjoin(bad, ', '));
end
end
