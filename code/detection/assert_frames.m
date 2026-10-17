function assert_frames(S, n, who, skip, dim)
%ASSERT_FRAMES  Stop when a per-frame field of S does not hold one entry per frame.
%   assert_frames(S, n, who, skip, dim): every field of S but those named in skip and the
%   structs holds n entries along dim (1, the default: rows; 2: columns); a cell vector
%   counts its elements and an array of more than two dimensions its last one. who names
%   the caller in the error.
if nargin < 4, skip = {}; end
if nargin < 5, dim = 1; end
f = setdiff(fieldnames(S), skip, 'stable');
bad = {};
for i = 1:numel(f)
    x = S.(f{i});
    if isstruct(x), continue; end
    if iscell(x) && isvector(x), m = numel(x); elseif ndims(x) > 2, m = size(x, ndims(x)); else, m = size(x, dim); end
    if m ~= n, bad{end+1} = sprintf('%s (%d)', f{i}, m); end %#ok<AGROW>
end
if ~isempty(bad)
    error('assert_frames:count', '%s: %d frames, but %s', who, n, strjoin(bad, ', '));
end
end
