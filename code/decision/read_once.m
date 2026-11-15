function out = read_once(cmd, varargin)
%READ_ONCE  Once-only side readings of a finished tree: code and input fingerprints, the per-tree
%   marker of a split, and atomic writes (rule_fix_reading.m, core_bw_rule_fix_reading.m).
%   h = read_once('code')              SHA-256 over every .m file under this checkout's code/
%                                      (relative path and text, line ends removed, sorted by path)
%   h = read_once('file', f)           SHA-256 of a file, 'absent' when it is missing
%   s = read_once('big', f)            size and date of a large file, 'absent' when missing
%   p = read_once('tree', tree)        the tree's canonical path (lower case on Windows)
%   f = read_once('claim', study, split, tree)   the marker of (study, split, tree):
%                                      results/read_once/<study>_<split>_<hash of the canonical
%                                      path>.txt of this checkout, whatever the reading's tag
%   read_once('write', f, lines)       text written to a temporary file, then renamed onto f
%   read_once('save', f, S)            the fields of S saved (-v7.3) the same way
switch cmd
    case 'code',  out = code_sha();
    case 'file',  out = file_sha(varargin{:});
    case 'big',   out = big_id(varargin{:});
    case 'tree',  out = canon(varargin{:});
    case 'claim', out = claim(varargin{:});
    case 'write', write_atomic(varargin{:});
    case 'save',  save_atomic(varargin{:});
    otherwise, error('read_once:cmd', 'read_once: unknown command %s', cmd);
end
end

function h = code_sha()
root = fullfile(project_root(), 'code');
d = dir(fullfile(root, '**', '*.m'));
rel = cellfun(@(p, n) strrep(erase(fullfile(p, n), [root filesep]), '\', '/'), {d.folder}, {d.name}, 'UniformOutput', false);
[rel, o] = sort(rel); d = d(o);
md = java.security.MessageDigest.getInstance('SHA-256');
for k = 1:numel(d)
    s = strrep(fileread(fullfile(d(k).folder, d(k).name)), char(13), '');
    md.update(unicode2native([rel{k} char(0) s char(0)], 'UTF-8'));
end
h = hex(md.digest());
end

function h = file_sha(f)
h = 'absent';
if ~isfile(f), return; end
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^26, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = hex(md.digest());
end

function h = big_id(f)
h = 'absent';
if isfile(f), d = dir(f); h = sprintf('%d bytes, %s', d.bytes, datestr(d.datenum, 31)); end
end

function p = canon(tree)
p = char(java.io.File(tree).getCanonicalPath());
if ispc, p = lower(p); end
end

function f = claim(study, split, tree)
assert(~isempty(regexp(study, '^[a-z0-9_]+$', 'once')) && ~isempty(regexp(split, '^[a-z0-9_]+$', 'once')), ...
    'read_once:name', 'read_once: study and split are lower-case letters, digits and _');
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(unicode2native(canon(tree), 'UTF-8'));
h = hex(md.digest());
f = fullfile(project_root(), 'results', 'read_once', sprintf('%s_%s_%s.txt', study, split, h(1:16)));
end

function write_atomic(f, lines)
d = fileparts(f); if ~isempty(d) && ~isfolder(d), mkdir(d); end
t = [f '.tmp'];
fid = fopen(t, 'w'); assert(fid > 0, 'read_once:write', 'cannot write %s', t);
fprintf(fid, '%s\n', lines{:}); fclose(fid);
[ok, msg] = movefile(t, f, 'f'); assert(ok, 'read_once:write', 'cannot rename %s: %s', t, msg);
end

function save_atomic(f, S)
d = fileparts(f); if ~isempty(d) && ~isfolder(d), mkdir(d); end
t = [f '.tmp.mat'];
save(t, '-struct', 'S', '-v7.3');
[ok, msg] = movefile(t, f, 'f'); assert(ok, 'read_once:write', 'cannot rename %s: %s', t, msg);
end

function s = hex(d)
s = lower(reshape(dec2hex(typecast(d, 'uint8'), 2)', 1, []));
end
