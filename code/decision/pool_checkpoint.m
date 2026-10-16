function out = pool_checkpoint(cmd, varargin)
%POOL_CHECKPOINT  Per-cell results of a long parallel pool build kept on disk as each cell
%   finishes, so a build stopped at any point (a power loss, an error) resumes with the cells
%   it has (build_policy_pools.m, build_clean_test_pools.m, build_check_pools.m).
%   key = pool_checkpoint('key', x)              SHA-256 of any MATLAB value (16 hex digits):
%       the identity of a cell, from everything its frames depend on
%   todo = pool_checkpoint('todo', dirn, keys)   the cells (indices into the cell array keys)
%       without a finished file dirn/cell_NNNN.mat holding the same key and a result;
%       unfinished temporary files are removed
%   pool_checkpoint('save', dirn, c, key, res)   cell c's result res with its key, written to
%       a temporary file, flushed to the disk and renamed once complete, so neither a write
%       cut off nor a power loss after the rename leaves a file that looks finished
%   res = pool_checkpoint('load', dirn, c)       cell c's result; a file that cannot be read
%       is removed and the build stops naming it (started again, it computes that cell only)
%   pool_checkpoint('commit', file, S)           the build's output, the fields of S as its
%       variables (-v7.3), written to a temporary file, flushed and renamed once complete
%   pool_checkpoint('clear', dirn)               removes the cells once the output is saved
switch cmd
    case 'key'
        md = java.security.MessageDigest.getInstance('SHA-256');
        md.update(getByteStreamFromArray(varargin{1}));
        h = typecast(md.digest(), 'uint8');
        out = lower(reshape(dec2hex(h(1:8))', 1, []));
    case 'todo'
        [dirn, keys] = varargin{:};
        if ~isfolder(dirn), mkdir(dirn); end
        t = dir(fullfile(dirn, '*.tmp.mat'));
        for i = 1:numel(t), delete(fullfile(dirn, t(i).name)); end
        done = false(1, numel(keys));
        for c = 1:numel(keys)
            f = cell_file(dirn, c);
            if ~isfile(f), continue; end
            try
                v = whos('-file', f);
                if all(ismember({'key', 'res'}, {v.name}))
                    S = load(f, 'key'); done(c) = strcmp(S.key, keys{c});
                end
            catch
                done(c) = false;                                % unreadable: computed again
            end
        end
        out = find(~done);
    case 'save'
        [dirn, c, key, res] = varargin{:};
        f = cell_file(dirn, c); tmp = fullfile(dirn, sprintf('cell_%04d.tmp.mat', c));
        save(tmp, 'key', 'res', '-v7.3');
        flush_file(tmp);
        movefile(tmp, f, 'f');
        out = f;
    case 'load'
        [dirn, c] = varargin{:};
        f = cell_file(dirn, c);
        try
            v = whos('-file', f); assert(any(strcmp({v.name}, 'res')));
            S = load(f, 'res'); out = S.res;
        catch
            if isfile(f), delete(f); end
            error('pool_checkpoint:unreadable', ['pool_checkpoint: %s cannot be read and was removed; ' ...
                'start the build again: it computes this cell only'], f);
        end
    case 'commit'
        [file, S] = varargin{:};
        [d, n] = fileparts(file); tmp = fullfile(d, [n '.tmp.mat']);
        save(tmp, '-struct', 'S', '-v7.3');
        flush_file(tmp);
        movefile(tmp, file, 'f');
        out = file;
    case 'clear'
        dirn = varargin{1}; out = dirn;
        if isfolder(dirn), rmdir(dirn, 's'); end
    otherwise
        error('pool_checkpoint: unknown command %s', cmd);
end
end

function f = cell_file(dirn, c)
f = fullfile(dirn, sprintf('cell_%04d.mat', c));
end

function flush_file(f)
% The file's data written through to the disk (FileChannel.force: FlushFileBuffers on
% Windows, fsync elsewhere) before its rename makes it look finished; without a JVM the
% operating system writes it in its own time.
d = dir(f);
if numel(d) ~= 1 || ~usejava('jvm'), return; end
try
    raf = java.io.RandomAccessFile(fullfile(d.folder, d.name), 'rw');
catch
    return
end
try
    raf.getChannel().force(true);
catch
end
raf.close();
end
