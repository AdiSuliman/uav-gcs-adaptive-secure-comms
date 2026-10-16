function out = pool_checkpoint(cmd, varargin)
%POOL_CHECKPOINT  Per-cell results of a long parallel pool build kept on disk as each cell
%   finishes, so a build stopped at any point (a power loss, an error) resumes with the cells
%   it has (build_policy_pools.m, build_clean_test_pools.m, build_check_pools.m).
%   key = pool_checkpoint('key', x)              SHA-256 of any MATLAB value (16 hex digits):
%       the identity of a cell, from everything its frames depend on
%   todo = pool_checkpoint('todo', dirn, keys)   the cells (indices into the cell array keys)
%       without a finished file dirn/cell_NNNN.mat of the same key; unfinished temporary
%       files are removed
%   pool_checkpoint('save', dirn, c, key, res)   cell c's result res with its key, written to
%       a temporary file and renamed once complete, so a write cut off never looks finished
%   res = pool_checkpoint('load', dirn, c)       cell c's result
%   pool_checkpoint('commit', file, S)           the build's output, the fields of S as its
%       variables (-v7.3), written to a temporary file and renamed once complete
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
                S = load(f, 'key'); done(c) = strcmp(S.key, keys{c});
            catch
                done(c) = false;                                % unreadable: computed again
            end
        end
        out = find(~done);
    case 'save'
        [dirn, c, key, res] = varargin{:};
        f = cell_file(dirn, c); tmp = fullfile(dirn, sprintf('cell_%04d.tmp.mat', c));
        save(tmp, 'key', 'res', '-v7.3');
        movefile(tmp, f, 'f');
        out = f;
    case 'load'
        [dirn, c] = varargin{:};
        S = load(cell_file(dirn, c), 'res'); out = S.res;
    case 'commit'
        [file, S] = varargin{:};
        [d, n] = fileparts(file); tmp = fullfile(d, [n '.tmp.mat']);
        save(tmp, '-struct', 'S', '-v7.3');
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
