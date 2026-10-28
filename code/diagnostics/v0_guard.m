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
%   Errors carry the ids v0_guard:test_split, v0_guard:input and v0_guard:out.
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
