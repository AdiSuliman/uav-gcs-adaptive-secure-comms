function j = feature_index(name)
%FEATURE_INDEX  Column of a link feature (link_features.m) by name; a cell array
%   of names gives a vector of columns.
persistent names map
if isempty(names)
    names = link_features('names');
    map = struct();
    for i = numel(names):-1:1                       % the first column of a name, as ismember
        if isvarname(names{i}), map.(names{i}) = i; end
    end
end
if ischar(name) && isrow(name) && isfield(map, name), j = map.(name); return; end
if ischar(name), name = {name}; end
[ok, j] = ismember(name, names);
if ~all(ok), error('feature_index: unknown feature ''%s''', strjoin(name(~ok), ''', ''')); end
end
