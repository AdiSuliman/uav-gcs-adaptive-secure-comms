function d = side_out_dir(out_dir, in_files)
%SIDE_OUT_DIR  Create the new output folder of a side reading; refuse an existing one or one inside an input's folder.
%   d = side_out_dir(out_dir, in_files)   in_files: a file or a cell of files the reader reads
if ~ischar(out_dir) && ~isstring(out_dir), error('side_out_dir:arg', 'side_out_dir: out_dir must be a path'); end
out_dir = char(out_dir);
if isempty(out_dir), error('side_out_dir:arg', 'side_out_dir: out_dir is empty'); end
d = canon(out_dir);
if exist(d, 'file') || exist(d, 'dir')
    error('side_out_dir:exists', 'side_out_dir: %s exists already; a side reading never overwrites', d);
end
if ischar(in_files), in_files = {in_files}; end
for i = 1:numel(in_files)
    fd = canon(fileparts(canon(in_files{i})));
    if startsWith([lower(d) filesep], [lower(fd) filesep])
        error('side_out_dir:inside', 'side_out_dir: %s lies inside the input folder %s', d, fd);
    end
end
[ok, msg] = mkdir(d);
if ~ok, error('side_out_dir:mkdir', 'side_out_dir: cannot create %s: %s', d, msg); end
end

function p = canon(p)
p = char(java.io.File(p).getCanonicalPath());
end
