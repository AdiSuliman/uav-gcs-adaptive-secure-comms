function varargout = run_cache(cmd, varargin)
%RUN_CACHE  Finished long runs kept on disk, so a stage stopped at any point (a reboot, a power
%   loss, an error) and started again skips the runs it has and computes only the rest. A run is
%   keyed by everything it depends on (the code, the input files, the settings and the seed), so
%   a cached run is the run the stage would compute and the stage's results equal those of an
%   uninterrupted run. Used by train_dqn.m (every training run and the reward-sensitivity
%   retrains), experiment_combo_generalization.m and experiment_unknown_threat.m (every entity).
%   Off unless the checkout's profile.json says "run_cache": true or CFG.run_cache is true.
%
%   on = run_cache('on', CFG, f)   the switch: CFG.run_cache when CFG is a struct with that field,
%       else the field run_cache of profile.json (f, default 'profile.json'), else false
%   dirn = run_cache('dir', on, name)   'data/run_cache/<name>' when on, '' otherwise
%   id = run_cache('inputs', files)   16 hex digits of the SHA-256 of the code (every .m file
%       under code/, tests and legacy excepted, with its path), of each file in files (its bytes;
%       an absent file counts as absent), of the MATLAB release and of the number of
%       computational threads (floating-point sums may differ between thread counts)
%   key = run_cache('key', x)   16 hex digits of the SHA-256 of a MATLAB value
%   [res, hit] = run_cache('run', dirn, key, f)   res = f() unless dirn/<key>.mat holds that
%       key's result (hit true); a new result is written to a temporary file, flushed to the disk
%       and renamed once complete (pool_checkpoint.m 'commit'), so a cut-off write never looks
%       finished; an unreadable file is removed and computed again. dirn '' runs f() and keeps
%       nothing.
%   [out, failed] = run_cache('each', dirn, keys, f, names)   out{i} = f(i) for every entity i
%       through 'run'. With dirn set an entity that stops is reported, the others still run
%       (each kept as it finishes), and the call then stops naming every failed entity: started
%       again, only those are computed. With dirn '' the first error stops at once, naming its
%       entity.
switch cmd
    case 'on'
        cfg = []; f = 'profile.json';
        if numel(varargin) >= 1, cfg = varargin{1}; end
        if numel(varargin) >= 2 && ~isempty(varargin{2}), f = varargin{2}; end
        on = false;
        if isstruct(cfg) && isfield(cfg, 'run_cache')
            on = check_flag(cfg.run_cache, 'CFG.run_cache');
        elseif isfile(f)
            P = jsondecode(fileread(f));
            if isstruct(P) && isfield(P, 'run_cache'), on = check_flag(P.run_cache, [f ': run_cache']); end
        end
        varargout{1} = on;
    case 'dir'
        [on, name] = varargin{:};
        d = '';
        if on, d = fullfile('data', 'run_cache', name); end
        varargout{1} = d;
    case 'inputs'
        files = varargin{1};
        md = java.security.MessageDigest.getInstance('SHA-256');
        root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        m = dir(fullfile(root, 'code', '**', '*.m'));
        rel = cellfun(@(d, n) strrep(erase(fullfile(d, n), [root filesep]), '\', '/'), {m.folder}, {m.name}, ...
            'UniformOutput', false);
        k = ~startsWith(rel, {'code/tests/', 'code/legacy/'});
        [rel, o] = sort(rel(k)); m = m(k); m = m(o);
        for i = 1:numel(m)
            md.update(uint8(['code ' rel{i} newline]));
            update_file(md, fullfile(m(i).folder, m(i).name));
        end
        for i = 1:numel(files)
            md.update(uint8(['file ' files{i} newline]));
            if isfile(files{i}), update_file(md, files{i}); else, md.update(uint8(['absent' newline])); end
        end
        nt = -1;
        try nt = maxNumCompThreads; catch, end
        md.update(uint8(sprintf('release %s threads %d\n', version('-release'), nt)));
        h = typecast(md.digest(), 'uint8');
        varargout{1} = lower(reshape(dec2hex(h(1:8), 2)', 1, []));
    case 'key'
        varargout{1} = pool_checkpoint('key', varargin{1});
    case 'run'
        [dirn, key, f] = varargin{:};
        if isempty(dirn), varargout = {f(), false}; return; end
        if ~isfolder(dirn), mkdir(dirn); end
        fk = fullfile(dirn, [key '.mat']);
        if isfile(fk)
            try
                S = load(fk, 'key', 'res');
                assert(strcmp(S.key, key));
                varargout = {S.res, true};
                return
            catch
                delete(fk);                                     % unreadable or not this key's: computed again
            end
        end
        res = f();
        pool_checkpoint('commit', fk, struct('key', key, 'res', {res}));
        varargout = {res, false};
    case 'each'
        [dirn, keys, f, names] = varargin{:};
        n = numel(keys); out = cell(1, n); failed = {};
        for i = 1:n
            try
                out{i} = run_cache('run', dirn, keys{i}, @() f(i));
            catch err
                if isempty(dirn)
                    e2 = MException('run_cache:entity', 'entity %d (%s) stopped: %s', i, names{i}, err.message);
                    throw(addCause(e2, err));
                end
                fprintf(2, 'run_cache: entity %d (%s) stopped: %s\n', i, names{i}, err.message);
                failed{end+1} = sprintf('%s (%s)', names{i}, err.message); %#ok<AGROW>
            end
        end
        if ~isempty(failed)
            error('run_cache:failed', ['%d of %d entities stopped (the others are kept in %s; started again, only ' ...
                'these are computed): %s'], numel(failed), n, dirn, strjoin(failed, '; '));
        end
        varargout = {out, failed};
    otherwise
        error('run_cache:cmd', 'run_cache: unknown command %s', cmd);
end
end

function v = check_flag(v, what)
if ~(isscalar(v) && islogical(v)), error('run_cache:value', '%s must be true or false', what); end
end

function update_file(md, f)
% The file's bytes in 32 MB pieces (a pools file of 14 GB never sits in memory at once).
fid = fopen(f, 'r');
assert(fid > 0, 'run_cache:read', 'cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^25, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
end
