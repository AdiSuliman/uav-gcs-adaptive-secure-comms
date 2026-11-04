function on = unseen_gap_on(f)
%UNSEEN_GAP_ON  Whether eval_unseen_snr.m prints the unseen-minus-grid recall of the lost-branch
%   classes with its cluster interval: the optional field unseen_gap of this checkout's
%   profile.json (f, default 'profile.json'). False without the file or the field (the report
%   is then as before).
if nargin < 1 || isempty(f), f = 'profile.json'; end
on = false;
if ~isfile(f), return; end
P = jsondecode(fileread(f));
if ~isstruct(P) || ~isfield(P, 'unseen_gap'), return; end
v = P.unseen_gap;
if ~(isscalar(v) && islogical(v)), error('unseen_gap_on:value', '%s: unseen_gap must be true or false', f); end
on = v;
end
