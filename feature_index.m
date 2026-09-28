function j = feature_index(name)
%FEATURE_INDEX  Column of a link feature (link_features.m) by name; a cell array
%   of names gives a vector of columns.
persistent names
if isempty(names), names = link_features('names'); end
if ischar(name), name = {name}; end
[ok, j] = ismember(name, names);
if ~all(ok), error('feature_index: unknown feature ''%s''', strjoin(name(~ok), ''', ''')); end
end
