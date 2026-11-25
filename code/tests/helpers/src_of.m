function txt = src_of(name)
%SRC_OF  Source text of the named function or script, as read from disk.
%   Equal to fileread(which(name)); line endings are left as stored. Source-reading
%   tests call this instead of fileread so that the layout of the files behind a name
%   can change in one place.
p = which(name);
assert(~isempty(p), 'src_of: %s is not on the path', name);
txt = fileread(p);
end
