function commit_mat(tmp, f)
%COMMIT_MAT  Replace f by the finished file tmp in one rename.
%   commit_mat(tmp, f): tmp is written through to the disk, then renamed onto f. A run cut
%   before the rename leaves f as it was, never part of a new record.
assert(isfile(tmp), 'commit_mat:tmp', '%s does not exist; %s left as it was', tmp, f);
d = dir(tmp);
if usejava('jvm')                                       % FileChannel.force: FlushFileBuffers on Windows, fsync elsewhere
    try
        raf = java.io.RandomAccessFile(fullfile(d.folder, d.name), 'rw');
        try
            raf.getChannel().force(true);
        catch
        end
        raf.close();
    catch
    end
end
[ok, msg] = movefile(tmp, f, 'f');
if ~ok, error('commit_mat:rename', '%s not renamed onto %s (left as it was): %s', tmp, f, msg); end
end
