function out = reader_guard(cmd, varargin)
%READER_GUARD  Keeps the descriptive readers (spd_d_diag.m, combo_miss_diag.m, p1r_post_hoc.m)
%   on read-only inputs, on the splits they may read and in their own output folder.
%   PP = reader_guard('strip', PP, keep)   empties every pool of the splits not in keep, checks it
%   reader_guard('check', PP, keep)        error if a pool of a split not in keep holds data
%   reader_guard('input', f, allowed)      error unless the file name is in the cell array allowed and the file
%                                          does not lie in a live pipeline tree (uav-gcs-v7, -p3, -p2, -p1r, -bw)
%   d = reader_guard('out', d, root)       error unless d is root/results or a folder below it
%   f = reader_guard('ref', pools_file, root)
%                                          the monitor's clean reference as the pipeline reads it:
%                                          clean_ber_ref.m loads clean_ref from data/policy_pools.mat
%                                          of MATLAB's current folder, so clean_ref of pools_file
%                                          alone is saved to root/data/policy_pools.mat (refused when
%                                          that file holds anything else: a pools file is never
%                                          overwritten, and when root/data holds other .mat files
%                                          and no pools file: a pipeline tree whose pools are not
%                                          built), the current folder is set to root and the
%                                          reference is checked finite
%   reader_guard('registration', hash, docs_repo)
%                                          error unless hash is a commit id; with docs_repo, that the
%                                          commit exists there and its docs/DECISIONS.md holds D116;
%                                          without docs_repo the returned text ends in
%                                          '(unverified: no docs repo)'
%   reader_guard('once', files)            error when one of the files (a cell array) exists
%   h = reader_guard('sha', f)             SHA-256 of a file, as sha256sum prints it
%   h = reader_guard('manifest', f, name)  the sha256 of the manifest line that names the file
%   Errors carry the ids reader_guard:split, :input, :out, :ref, :registration, :once and :sha.
out = [];
switch cmd
    case 'strip'
        PP = varargin{1}; keep = varargin{2};
        if ~isfield(PP, 'pools'), error('reader_guard:split', 'reader_guard: no pools to strip'); end
        ns = size(PP.pools, 4);
        if ~all(ismember(keep, 1:ns)), error('reader_guard:split', 'reader_guard: the pools hold %d splits, not %s', ns, mat2str(keep)); end
        drop = setdiff(1:ns, keep);
        if ~isempty(drop), PP.pools(:, :, :, drop) = {[]}; end
        reader_guard('check', PP, keep);
        out = PP;
    case 'check'
        PP = varargin{1}; keep = varargin{2};
        if ~isfield(PP, 'pools'), error('reader_guard:split', 'reader_guard: no pools to check'); end
        for sp = setdiff(1:size(PP.pools, 4), keep)
            P = PP.pools(:, :, :, sp);
            if any(~cellfun(@isempty, P(:)))
                error('reader_guard:split', 'reader_guard: the pools hold data of split %d, which this reader may not read', sp);
            end
        end
    case 'input'
        f = canon(varargin{1});
        [~, n, e] = fileparts(f);
        ok = varargin{2};
        if ~ismember(lower([n e]), lower(ok))
            error('reader_guard:input', 'reader_guard: input %s refused; allowed: %s', [n e], strjoin(ok, ', '));
        end
        live = {'uav-gcs-v7', 'uav-gcs-v7-p3', 'uav-gcs-v7-p2', 'uav-gcs-v7-p1r', 'uav-gcs-v7-bw'};
        if any(ismember(lower(regexp(f, '[\\/]', 'split')), live))
            error('reader_guard:input', 'reader_guard: input %s lies in a live pipeline tree; the readers read copies', f);
        end
    case 'out'
        d = canon(varargin{1}); res = canon(fullfile(varargin{2}, 'results'));
        if ~(strcmpi(d, res) || startsWith(lower(d), lower([res filesep])))
            error('reader_guard:out', 'reader_guard: output folder %s refused; outputs go under %s', d, res);
        end
        out = d;
    case 'ref'
        src = canon(varargin{1}); root = canon(varargin{2});
        dst = canon(fullfile(root, 'data', 'policy_pools.mat'));
        if strcmpi(src, dst), error('reader_guard:ref', 'reader_guard: %s is its own reference copy', src); end
        S = load(src, 'clean_ref');
        if ~isfield(S, 'clean_ref') || ~isfield(S.clean_ref, 'ber_est')
            error('reader_guard:ref', 'reader_guard: %s holds no clean_ref with ber_est', src);
        end
        clean_ref = S.clean_ref;
        if ~isfolder(fileparts(dst)), mkdir(fileparts(dst)); end
        same = false;
        if isfile(dst)
            if ~isempty(setdiff(who('-file', dst), {'clean_ref'}))
                error('reader_guard:ref', 'reader_guard: %s holds more than a clean reference (a pools file); it is not overwritten', dst);
            end
            D = load(dst, 'clean_ref'); same = isfield(D, 'clean_ref') && isequaln(D.clean_ref, clean_ref);
        elseif ~isempty(dir(fullfile(fileparts(dst), '*.mat')))
            error('reader_guard:ref', ['reader_guard: %s holds data files and no pools file (a pipeline tree whose pools are not ' ...
                'built yet); a reference planted there would be read by the pipeline; the readers run from a reading tree'], fileparts(dst));
        end
        if ~same, save(dst, 'clean_ref'); end
        cd(root);
        clear('clean_ber_ref');
        x = clean_ref.ebno(:)'; y = log10(max(clean_ref.ber_est(:)', 1e-7));
        b = clean_ber_ref(x, 'ber_est');
        if any(~isfinite(b)) || max(abs(log10(b) - y)) > 1e-9
            error('reader_guard:ref', 'reader_guard: clean_ber_ref does not read the clean reference of %s', src);
        end
        out = dst;
    case 'registration'
        h = char(varargin{1});
        if isempty(regexp(h, '^[0-9a-f]{7,40}$', 'once'))
            error('reader_guard:registration', ['reader_guard: no registration commit (%s): a run governed by D116 starts ' ...
                'only with the hash of the commit that registers D110-D118'], h);
        end
        if numel(varargin) > 1 && ~isempty(varargin{2})
            repo = char(varargin{2});
            [st, ~] = system(sprintf('git -C "%s" cat-file -e %s', repo, h));
            if st ~= 0, error('reader_guard:registration', 'reader_guard: commit %s is not in %s', h, repo); end
            [st, txt] = system(sprintf('git -C "%s" show %s:docs/DECISIONS.md', repo, h));
            if st ~= 0 || isempty(strfind(txt, '## D116 ')) %#ok<STREMP>
                error('reader_guard:registration', 'reader_guard: docs/DECISIONS.md at %s holds no D116', h);
            end
            out = h;
        else
            out = [h ' (unverified: no docs repo)'];
        end
    case 'once'
        for f = varargin{1}(:)'
            if isfile(f{1}), error('reader_guard:once', 'reader_guard: %s exists; the reading runs once', f{1}); end
        end
    case 'sha'
        out = file_sha(varargin{1});
    case 'manifest'
        out = manifest_sha(varargin{1}, varargin{2});
    otherwise
        error('reader_guard: unknown command %s', cmd);
end
end

function p = canon(p)
% Full path with '..' resolved; a relative path is read from MATLAB's current folder.
p = char(p);
if ~java.io.File(p).isAbsolute(), p = fullfile(pwd, p); end
p = char(java.io.File(p).getCanonicalPath());
end

function h = file_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
if fid < 0, error('reader_guard:sha', 'reader_guard: cannot open %s', f); end
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^24, '*uint8');
    if isempty(b), break; end
    md.update(typecast(b, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function h = manifest_sha(f, name)
% The sha256 of the manifest line that names the file.
L = splitlines(fileread(f));
k = find(endsWith(strtrim(L), ['/' name]) | endsWith(strtrim(L), ['\' name]) | endsWith(strtrim(L), [' ' name]), 1);
if isempty(k), error('reader_guard:sha', 'reader_guard: %s has no line for %s', f, name); end
h = regexp(L{k}, '^[0-9a-fA-F]{64}', 'match', 'once');
if isempty(h), error('reader_guard:sha', 'reader_guard: no sha256 on the line for %s in %s', name, f); end
end
