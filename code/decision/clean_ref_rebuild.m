function R = clean_ref_rebuild(mode, opt)
%CLEAN_REF_REBUILD  The decision layer's clean-link reference per Eb/N0 from the clean
%   validation pools (data/clean_val_pools.mat, build_clean_test_pools.m: 300 independent
%   flights per Eb/N0, seed block 4) instead of the clean cell's own train flights of
%   build_policy_pools.m (8 per Eb/N0). The per-flight clean BER is heavy-tailed (bank
%   angle, attitude and polarisation loss, Rician K per flight), so a mean over 8 flights
%   depends on which flights were drawn. Both sets come from the same receiver, Eb/N0
%   definition, frames per flight and features (pool_cell.m); the flight is the
%   independent unit.
%   Fields written, each 1 x Eb/N0: clean_ref.ber and .fer (true BER and frame error at
%   no_action), .ber_est (the receiver's BER estimate: policy_monitor.m through
%   clean_ber_ref.m), .plr and .plr_fec (CRC packet loss at no_action and at
%   fec_interleave); PP.clean = ber and PP.clean_fer = fer (link_env.m's 'mean'
%   restoration reference). clean_ref also keeps the 95% flight-bootstrap interval of every
%   field (.ci), the flights per Eb/N0, the source, the leave-one-family-out change
%   (.jackknife), the heavy-tail summary (.tail) and the table it replaced (.train).
%   Only the clean validation pools are read. A test-set file, the check pools, or any set
%   other than 'val' of seed block 4 is refused.
%   mode  'check'  compute and print; write nothing (the stop window's read)
%         'write'  as 'check', then write the reference unless the verdict is 'stop';
%                  policy_pools.mat is backed up first
%         'chain'  write without a verdict (C1c, run_stage.m): a chain that builds its
%                  pools from the start takes the reference from its validation pools
%   opt   (optional) val, pp: the two files (default data/clean_val_pools.mat and
%         data/policy_pools.mat); expect: struct('ebno', 9, 'range', [3e-4 6e-3]), the
%         pre-registered range of the mean clean BER at that Eb/N0
%         (docs/clean_ref_protocol.md); B: bootstrap resamples (2000)
%   R     ref (the new clean_ref), train (the table in use before), verdict, wrote, already
%   Verdict ('check', 'write'): 'stop' when the new BER at expect.ebno lies outside
%   expect.range, or the BER rises with Eb/N0 beyond the intervals; otherwise 'confirmed'
%   when the replaced value lies outside the new interval at expect.ebno, and
%   'contradicted' when it lies inside.
%   No frame of the pools changes, so policy_pools.mat must stay older than the files
%   built from it (build_check_pools.m and build_clean_test_pools.m rebuild a file that is
%   older than the pools). Its time is set to the old time plus 2 s, or to the old time
%   when a dependent file is not newer than that. Run from the repository root.
if nargin < 1 || isempty(mode), mode = 'check'; end
if ~ischar(mode) || ~ismember(mode, {'check', 'write', 'chain'})
    error('clean_ref_rebuild:mode', 'mode must be ''check'', ''write'' or ''chain''');
end
if nargin < 2, opt = struct(); end
def = struct('val', 'data/clean_val_pools.mat', 'pp', 'data/policy_pools.mat', ...
    'expect', struct('ebno', 9, 'range', [3e-4 6e-3]), 'B', 2000);
fn = fieldnames(def);
for i = 1:numel(fn)
    if ~isfield(opt, fn{i}), opt.(fn{i}) = def.(fn{i}); end
end
BLOCK = 4;                                              % seed block of the clean validation pools (build_clean_test_pools.m)
K = {'ber', 'fer', 'ber_est', 'plr', 'plr_fec'};
LAB = {'BER', 'frame error', 'estimated BER', 'packet loss (CRC)', 'packet loss, fec_interleave'};

%% 1. Source: the clean validation pools only
CT = load_val(opt.val, BLOCK);
if ~isfile(opt.pp) || ~ismember('clean_ref', who('-file', opt.pp))
    error('clean_ref_rebuild:pools', '%s holds no clean_ref (build_policy_pools.m)', opt.pp);
end
L0 = load(opt.pp, 'clean_ref'); old = L0.clean_ref; clear L0
E = double(CT.ebno(:)'); nS = numel(E);
if ~isfield(old, 'ebno') || ~isequal(round(double(old.ebno(:)') * 1e6), round(E * 1e6))
    error('clean_ref_rebuild:grid', 'the Eb/N0 grid of %s differs from that of %s', opt.val, opt.pp);
end
if strcmp(mode, 'check')                                % the pools' identity without loading them
    id = h5_char(opt.pp, '/PP/det_id'); tag = h5_char(opt.pp, '/PP/model_tag');
    if isempty(id)
        fprintf('PP.det_id not read here; the write mode checks it\n');
    else
        P = struct('det_id', id); if ~isempty(tag), P.model_tag = tag; end
        check_det_id(P, CT, 'clean_ref_rebuild', opt.val);
    end
end
A = CT.actions; na = find(strcmp(A, 'no_action')); nf = find(strcmp(A, 'fec_interleave'));
if numel(na) ~= 1, error('clean_ref_rebuild:actions', '%s has no no_action pools', opt.val); end

%% 2. Table, flight bootstrap, family jackknife, heavy tail
ref = struct('ebno', E); ci = struct(); jk = struct();
for i = 1:numel(K), ref.(K{i}) = nan(1, nS); ci.(K{i}) = nan(2, nS); jk.(K{i}) = nan(1, nS); end
tail = struct('median', nan(1, nS), 'top_share', nan(1, nS));
nfl = zeros(1, nS); frames = [inf -inf];
jl = feature_index('log_ber');
for s = 1:nS
    Qa = CT.pools{1, s, na};
    [u, ~, ir] = unique(double(Qa.run(:)));
    nu = numel(u); nfl(s) = nu;
    fr = accumarray(ir, 1, [nu 1]); frames = [min(frames(1), min(fr)), max(frames(2), max(fr))];
    X = {double(Qa.ber(:)), double(Qa.fer(:)), 10.^double(Qa.feat(:, jl)), double(Qa.crc(:)), []};
    G = {ir, ir, ir, ir, []};
    if ~isempty(nf)
        Qf = CT.pools{1, s, nf};
        [uf, ~, irf] = unique(double(Qf.run(:)));
        if ~isequal(uf, u), error('clean_ref_rebuild:flights', 'Eb/N0 %g dB: fec_interleave flies other flights', E(s)); end
        X{5} = double(Qf.crc(:)); G{5} = irf;
    end
    Sx = zeros(nu, 5); Nx = zeros(nu, 5);
    for i = 1:5
        if isempty(G{i}), continue; end
        ok = ~isnan(X{i});
        Sx(:, i) = accumarray(G{i}(ok), X{i}(ok), [nu 1]);
        Nx(:, i) = accumarray(G{i}(ok), 1, [nu 1]);
    end
    tab = sum(Sx, 1) ./ sum(Nx, 1);                     % the frame mean, as build_policy_pools.m
    rs = RandStream('mt19937ar', 'Seed', 4000 + s);
    idx = randi(rs, nu, nu, opt.B);                     % flights drawn with replacement, nu x B
    for i = 1:5
        Si = Sx(:, i); Ni = Nx(:, i);
        ref.(K{i})(s) = tab(i);
        ci.(K{i})(:, s) = interval(sum(Si(idx), 1) ./ sum(Ni(idx), 1));
    end
    tail.median(s) = median(Sx(:, 1) ./ max(Nx(:, 1), 1));
    tail.top_share(s) = max(Sx(:, 1)) / max(sum(Sx(:, 1)), realmin);
    fam = 1 + 2 * floor((u - 100 * BLOCK - 1) / 100);   % geometry families 1, 3, 5 (clean_pool_seed.m)
    F = unique(fam);
    if numel(F) > 1
        d = zeros(numel(F), 5);
        for j = 1:numel(F)
            keep = fam ~= F(j);
            d(j, :) = abs(sum(Sx(keep, :), 1) ./ sum(Nx(keep, :), 1) - tab) ./ max(tab, realmin);
        end
        for i = 1:5, jk.(K{i})(s) = max(d(:, i)); end
    end
end
src = struct('file', opt.val, 'set', CT.set, 'block', BLOCK, 'runs', [CT.runs(1), CT.runs(end)], ...
    'n_flights', nfl, 'frames', frames, 'created', field_or(CT, 'created', ''));
done = isfield(old, 'source') && isequal(old.source.created, src.created) && isequal(old.source.runs, src.runs) ...
    && isequal(old.source.n_flights, nfl);
train = old; if isfield(old, 'train'), train = old.train; end
train = keep_fields(train, [{'ebno'}, K]);

%% 3. Report and verdict
t = sprintf('Source: %s (set %s, seed block %d, runs %d-%d, %s flights per Eb/N0, %d-%d frames per flight, built %s)\n', ...
    opt.val, src.set, BLOCK, src.runs, strjoin(arrayfun(@num2str, unique(nfl), 'UniformOutput', false), '/'), ...
    frames, src.created);
t = [t sprintf('Interval: 95%% percentile of %d flight-bootstrap resamples per Eb/N0\n', opt.B)];
t = [t row('Eb/N0 [dB]', E, '%10.1f')];
for i = 1:numel(K)
    t = [t row([LAB{i} ', validation'], ref.(K{i}), '%10.1e')]; %#ok<AGROW>
    t = [t row('  interval, low', ci.(K{i})(1, :), '%10.1e')]; %#ok<AGROW>
    t = [t row('  interval, high', ci.(K{i})(2, :), '%10.1e')]; %#ok<AGROW>
    if isfield(train, K{i}) && numel(train.(K{i})) == nS
        t = [t row('  replaced (C1p train flights)', train.(K{i}), '%10.1e')]; %#ok<AGROW>
    end
end
t = [t row('Median flight BER', tail.median, '%10.1e')];
t = [t row('Largest flight share of mean BER', tail.top_share, '%10.2f')];
t = [t row('Leave-one-family-out, BER', jk.ber, '%10.2f')];
t = [t row('Leave-one-family-out, est. BER', jk.ber_est, '%10.2f')];
verdict = 'n/a';
if ~strcmp(mode, 'chain')
    s0 = find(abs(E - opt.expect.ebno) < 1e-6, 1);
    if isempty(s0), error('clean_ref_rebuild:expect', 'Eb/N0 %g dB is not on the grid', opt.expect.ebno); end
    b0 = ref.ber(s0); c0 = ci.ber(:, s0);
    o0 = NaN; if isfield(train, 'ber') && numel(train.ber) == nS, o0 = train.ber(s0); end
    rise = any(ci.ber(1, 2:end) > ci.ber(2, 1:end-1));
    if b0 < opt.expect.range(1) || b0 > opt.expect.range(2) || rise
        verdict = 'stop';
    elseif o0 < c0(1) || o0 > c0(2)
        verdict = 'confirmed';
    else
        verdict = 'contradicted';
    end
    t = [t sprintf(['VERDICT clean_ref %s: BER at %g dB %.2e [%.2e, %.2e], pre-registered range %.0e-%.0e, ' ...
        'replaced %.2e, BER rising beyond the intervals: %d\n'], verdict, opt.expect.ebno, b0, c0, ...
        opt.expect.range, o0, rise)];
end
fprintf('\n=== Clean-link reference from the clean validation pools (%s) ===\n%s', mode, t);
new = ref; new.ci = ci; new.n_flights = nfl; new.source = src; new.jackknife = jk; new.tail = tail;
new.boot = struct('B', opt.B, 'seed', 4000 + (1:nS), 'unit', 'flight'); new.train = train;
new.created = datestr(now);
R = struct('ref', new, 'train', train, 'verdict', verdict, 'wrote', false, 'already', done);
if strcmp(mode, 'check'), return; end
if done
    fprintf('%s already holds the reference of these validation pools: nothing written\n', opt.pp);
    return
end
if strcmp(verdict, 'stop')
    error('clean_ref_rebuild:verdict', 'verdict stop: nothing written (docs/clean_ref_protocol.md)');
end

%% 4. Write
write_ref(opt.pp, opt.val, CT, new, frames, strcmp(mode, 'write'));
R.wrote = true;
if ~isfolder('results'), mkdir('results'); end
fid = fopen('results/clean_ref.txt', 'w');
fprintf(fid, 'Clean-link reference of the decision layer (clean_ref_rebuild %s, %s)\n%s', mode, new.created, t);
fprintf(fid, 'Written to %s: clean_ref (%s) and PP.clean, PP.clean_fer\n', opt.pp, strjoin(K, ', '));
fclose(fid);
fprintf('Saved results/clean_ref.txt\n');
end

function CT = load_val(f, block)
% The clean validation pools, refusing any other pool file.
[~, nm, ext] = fileparts(f);
if ~strcmp([nm ext], 'clean_val_pools.mat')
    error('clean_ref_rebuild:source', '%s: only clean_val_pools.mat (validation) is read, never test or check pools', f);
end
if ~isfile(f), error('clean_ref_rebuild:source', '%s does not exist (C1c)', f); end
v = who('-file', f);
if ismember('CK', v) || ~ismember('CT', v)
    error('clean_ref_rebuild:source', '%s holds no clean-link pools (CT)', f);
end
S = load(f, 'CT'); CT = S.CT;
if ~isfield(CT, 'set') || ~strcmp(CT.set, 'val')
    error('clean_ref_rebuild:source', '%s is not the validation set', f);
end
r = double(CT.runs(:)');
if isempty(r) || ~isequal(r, 100 * block + (1:numel(r))) || numel(r) > 300
    error('clean_ref_rebuild:source', '%s: runs outside the validation seed block %d', f, block);
end
end

function write_ref(f, fval, CT, new, frames, keep_copy)
% The new reference into the pools file; its time kept older than the files built from it.
if ~usejava('jvm'), error('clean_ref_rebuild:jvm', 'the JVM is needed to keep the time of %s', f); end
L = load(f);
if ~isfield(L, 'PP') || ~isfield(L, 'clean_ref'), error('clean_ref_rebuild:pools', '%s holds no PP and clean_ref', f); end
PP = L.PP;
check_det_id(PP, CT, 'clean_ref_rebuild', fval);
if ~isequal(CT.actions, PP.actions) || ~isequal(round(double(CT.ebno(:)') * 1e6), round(double(PP.ebno(:)') * 1e6))
    error('clean_ref_rebuild:grid', '%s and %s differ in Eb/N0 grid or configurations', fval, f);
end
if isfield(PP, 'F_SUB') && ~isempty(PP.F_SUB) && any(frames ~= PP.F_SUB)    % the table stays a frame mean
    warning('clean_ref_rebuild:frames', '%s: %d-%d frames per flight, the pools %d', fval, frames, PP.F_SUB);
end
t_old = mtime_ms(f);
if keep_copy
    bak = sprintf('%s_before_cleanref_%s.mat', f(1:end-4), char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    if isfile(bak), error('clean_ref_rebuild:backup', '%s exists', bak); end
    [ok, msg] = copyfile(f, bak);
    if ~ok || dir(bak).bytes ~= dir(f).bytes, error('clean_ref_rebuild:backup', 'no backup of %s: %s', f, msg); end
    fprintf('Backup %s\n', bak);
end
L.clean_ref = new;
L.PP.clean = reshape(new.ber, size(PP.clean));
L.PP.clean_fer = reshape(new.fer, size(PP.clean_fer));
clear PP
pool_checkpoint('commit', f, L);
clear L
t_set = set_time(f, t_old);
clear('clean_ber_ref');                                 % its cache keys on the file time
clear_workers();
C = load(f, 'clean_ref');
if ~isequaln(C.clean_ref, new), error('clean_ref_rebuild:verify', '%s: clean_ref read back differs', f); end
iso = @(t) char(datetime(t / 1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ss'));
fprintf('Written to %s: clean_ref and PP.clean, PP.clean_fer; file time %s (before: %s)\n', f, iso(t_set), iso(t_old));
end

function t = set_time(f, t_old)
% Old time + 2 s when every dependent file is newer, else the old time.
d = fileparts(abspath(f));
td = [];
for g = {'check_pools.mat', 'clean_val_pools.mat', 'clean_test_pools.mat'}
    h = fullfile(d, g{1});
    if isfile(h), td(end+1) = mtime_ms(h); end %#ok<AGROW>
end
t = t_old + 2000;
if any(td <= t), t = t_old; end
ok = java.io.File(abspath(f)).setLastModified(t);
if ~ok || abs(mtime_ms(f) - t) > 1000
    warning('clean_ref_rebuild:time', ['%s: its time could not be set back; build_check_pools.m and ' ...
        'build_clean_test_pools.m would read their files as older than the pools'], f);
end
end

function clear_workers()
% Clears clean_ber_ref's cache on the workers of an open parallel pool.
if ~exist('gcp', 'file'), return; end
pl = gcp('nocreate');
if isempty(pl), return; end
wait(parfevalOnAll(pl, @clear, 0, 'clean_ber_ref'));
end

function t = mtime_ms(f)
t = double(java.io.File(abspath(f)).lastModified());
end

function p = abspath(f)
if numel(f) > 1 && (f(2) == ':' || f(1) == '\' || f(1) == '/'), p = f; else, p = fullfile(pwd, f); end
end

function s = h5_char(f, path)
% A char field of a -v7.3 struct read without loading the struct; '' when not readable.
s = '';
try
    x = h5read(f, path);
    if isa(x, 'uint16'), s = char(x(:)'); end           % an empty char is stored as its size (uint64)
catch
end
if any(s < 32 | s > 126), s = ''; end
end

function c = interval(b)
% 95% percentile interval of bootstrap values.
b = sort(b(~isnan(b)));
if isempty(b), c = [NaN; NaN]; return; end
n = numel(b);
c = [b(max(1, floor(0.025 * n))); b(min(n, ceil(0.975 * n)))];
end

function s = row(lab, v, fmt)
s = sprintf('%-34s%s\n', lab, sprintf(fmt, v));
end

function v = field_or(S, f, d)
v = d; if isfield(S, f), v = S.(f); end
end

function T = keep_fields(S, f)
T = struct();
for i = 1:numel(f)
    if isfield(S, f{i}), T.(f{i}) = S.(f{i}); end
end
end
