function side_write(out_dir, name, lines, S)
%SIDE_WRITE  Write <name>.txt (lines) and, with S, <name>.mat (the fields of S) whole: a temporary file, then a rename.
%   Refuses to replace an existing file.
tx = fullfile(out_dir, [name '.txt']);
if exist(tx, 'file'), error('side_write:exists', 'side_write: %s exists already', tx); end
tmp = [tx '.part'];
fid = fopen(tmp, 'w');
if fid < 0, error('side_write:open', 'side_write: cannot write %s', tmp); end
fprintf(fid, '%s\n', lines{:});
fclose(fid);
if nargin >= 4 && ~isempty(S)
    mt = fullfile(out_dir, [name '.mat']);
    if exist(mt, 'file'), delete(tmp); error('side_write:exists', 'side_write: %s exists already', mt); end
    tmpm = fullfile(out_dir, [name '_part.mat']);
    save(tmpm, '-struct', 'S', '-v7.3');
    movefile(tmpm, mt);
end
movefile(tmp, tx);
end
