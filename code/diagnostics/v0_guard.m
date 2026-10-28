function out = v0_guard(cmd, varargin)
%V0_GUARD  Keeps the V0 diagnostic (v0_diag.m) on the validation split and its own outputs.
%   v0_guard('split', s)          error unless s is the validation split (2)
%   PP = v0_guard('strip', PP)    empties every pool of the splits after validation (the test
%                                 splits, the speed split and the second test split) and checks it
%   v0_guard('check', PP)         error if a pool of those splits holds data
%   v0_guard('input', f)          error unless the file name is an allowed input
%                                 (policy_pools.mat, clean_val_pools.mat, trained_dqn.mat)
%   d = v0_guard('out', d, root)  error unless d is root/results or a folder below it; d as a
%                                 full path
%   f = v0_guard('ref', pools_file, root)
%                                 the monitor's clean reference as the pipeline reads it:
%                                 clean_ber_ref.m loads clean_ref from data/policy_pools.mat of
%                                 MATLAB's current folder, so clean_ref of pools_file alone is
%                                 saved to root/data/policy_pools.mat, the current folder is set
%                                 to root and the reference is checked against pools_file's;
%                                 f is the file written
%   Errors carry the ids v0_guard:test_split, v0_guard:input, v0_guard:out and v0_guard:ref.
VAL = 2;
out = [];
switch cmd
    case 'split'
        s = varargin{1};
        if ~isnumeric(s) || ~isscalar(s) || s ~= VAL
            error('v0_guard:test_split', 'v0_guard: split %s refused; V0 reads the validation split (%d) only', ...
                mat2str(s), VAL);
        end
    case 'strip'
        PP = varargin{1};
        if ~isfield(PP, 'pools'), error('v0_guard:test_split', 'v0_guard: no pools to strip'); end
        if size(PP.pools, 4) > VAL, PP.pools(:, :, :, VAL + 1:end) = {[]}; end
        v0_guard('check', PP);
        out = PP;
    case 'check'
        PP = varargin{1};
        if ~isfield(PP, 'pools'), error('v0_guard:test_split', 'v0_guard: no pools to check'); end
        if size(PP.pools, 4) > VAL
            P = PP.pools(:, :, :, VAL + 1:end);
            if any(~cellfun(@isempty, P(:)))
                error('v0_guard:test_split', 'v0_guard: the pools hold data of a split after validation');
            end
        end
    case 'input'
        [~, n, e] = fileparts(char(varargin{1}));
        ok = {'policy_pools.mat', 'clean_val_pools.mat', 'trained_dqn.mat'};
        if ~ismember(lower([n e]), ok)
            error('v0_guard:input', 'v0_guard: input %s refused; allowed: %s', [n e], strjoin(ok, ', '));
        end
    case 'out'
        d = canon(varargin{1}); res = canon(fullfile(varargin{2}, 'results'));
        if ~(strcmpi(d, res) || startsWith(lower(d), lower([res filesep])))
            error('v0_guard:out', 'v0_guard: output folder %s refused; outputs go under %s', d, res);
        end
        out = d;
    case 'ref'
        src = canon(varargin{1}); root = canon(varargin{2});
        [~, rn] = fileparts(root);
        if ismember(lower(rn), {'uav-gcs-v7', 'uav-gcs-v7-p3', 'uav-gcs-v7-p2', 'uav-gcs-logs'})
            error('v0_guard:ref', 'v0_guard: %s is a pipeline folder; the reference copy goes to the V0 worktree', root);
        end
        dst = canon(fullfile(root, 'data', 'policy_pools.mat'));
        if strcmpi(src, dst), error('v0_guard:ref', 'v0_guard: %s is its own reference copy', src); end
        S = load(src, 'clean_ref');
        if ~isfield(S, 'clean_ref') || ~isfield(S.clean_ref, 'ber_est')
            error('v0_guard:ref', 'v0_guard: %s holds no clean_ref with ber_est', src);
        end
        clean_ref = S.clean_ref;
        if ~isfolder(fileparts(dst)), mkdir(fileparts(dst)); end
        same = false;
        if isfile(dst)
            D = load(dst, 'clean_ref'); same = isfield(D, 'clean_ref') && isequaln(D.clean_ref, clean_ref);
        end
        if ~same, save(dst, 'clean_ref'); end
        cd(root);
        clear('clean_ber_ref');
        x = clean_ref.ebno(:)'; y = log10(max(clean_ref.ber_est(:)', 1e-7));
        b = clean_ber_ref(x, 'ber_est');
        if any(~isfinite(b)) || max(abs(log10(b) - y)) > 1e-9
            error('v0_guard:ref', 'v0_guard: clean_ber_ref does not read the clean reference of %s', src);
        end
        out = dst;
    otherwise
        error('v0_guard: unknown command %s', cmd);
end
end

function p = canon(p)
% Full path with '..' resolved; a relative path is read from MATLAB's current folder.
p = char(p);
if ~java.io.File(p).isAbsolute(), p = fullfile(pwd, p); end
p = char(java.io.File(p).getCanonicalPath());
end
