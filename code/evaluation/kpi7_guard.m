function V = kpi7_guard(tree, opt)
%KPI7_GUARD  Bit-identity guard of KPI 7's performance changes (docs/d126_kpi7.md).
%   V = kpi7_guard(tree)       tree: a finished tree, read only (its data/, params.mat)
%   V = kpi7_guard(tree, opt)  opt.base: the commit before the changes (default BASE below);
%                              opt.sets: replay sets (default single, combined, clean);
%                              opt.max_batches: replay batches per set (default all)
%   Run from this checkout, with its code on the path (startup.m), never the tree's.
%   The code before the changes is every function file changed since opt.base (git diff,
%   the drivers measure_latency.m, lat_cycle.m and this file excepted), each taken by git show
%   into its own temporary folder and put first on the path; the current code is the
%   checkout's. Both run over:
%   - the 84 frames of measure_latency.m (its setup and frames, LAT_SETUP_ONLY), every chain
%     (deployed, DQN, rule + escalation) through lat_cycle.m, the detector on the CPU;
%     compared per cycle with isequaln: img, raw, idle, g, probs, maha, cfg, mem, info. The
%     old code runs twice: a field that differs between those two runs is not deterministic
%     and its comparison is inconclusive, not a rejection.
%   - a replay of the deployed policy on the tree's test pools (link_env.m, the test split,
%     the episode sets of evaluate_policies.m, one pass each, its batch seeds); compared per
%     cycle: obs, a, mem, info, and link_env's tables.
%   Verdicts: the default changes (caches) ACCEPTED only when every compared output is
%   identical; otherwise REJECTED, and each changed file is tried alone to name the ones that
%   differ. Each guarded option (spec_image 'direct', mmse_predict 'tail', clean_ber_ref
%   'interpolant') ACCEPTED alone on the same terms; the detector before the predictor (the
%   diagnostic order) and PPm.pw in LAT's monitor settings are reported (identical, or the
%   decisions identical).
%   The tree is never written: Simulink's cache and code folders go to a temporary folder,
%   the unknown-threat threshold cache must be current (ood_thresholds.m would rewrite it), and
%   the tree's files are listed before and after (a change there is named in the verdict; a
%   stage running on the tree at the same time also shows there).
%   Output: results/kpi7/guard_verdict.{txt,mat} in this checkout.
BASE = 'd4623ed';
if nargin < 2, opt = struct(); end
o = struct('base', BASE, 'sets', {{'single', 'combined', 'clean'}}, 'max_batches', Inf);
for f = fieldnames(opt)', o.(f{1}) = opt.(f{1}); end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tree = canon(tree);
assert(~strcmpi(tree, canon(root)), 'kpi7_guard: the tree is this checkout');
assert(startsWith(canon(which('policy_monitor')), canon(fullfile(root, 'code')), 'IgnoreCase', true), ...
    'kpi7_guard: run with this checkout''s code on the path (cd %s; startup), not another tree''s', root);
assert(isfile(fullfile(tree, 'data', 'policy_pools.mat')), 'kpi7_guard: no data/policy_pools.mat in %s', tree);
V = struct('generated', datestr(now), 'tree', tree, 'checkout', root, 'base', o.base, 'head', git1(root, 'rev-parse HEAD'), ...
    'dirty', ~isempty(git1(root, 'status --porcelain -- code')), 'tree_head', git1(tree, 'rev-parse HEAD'));

tmp = tempname; mkdir(tmp);
G = old_copies(root, o.base, tmp);
V.files = G.rel;
cwd0 = pwd; cfg0 = Simulink.fileGenControl('getConfig');
cl = onCleanup(@() restore(cwd0, cfg0, G, tmp)); %#ok<NASGU>
Simulink.fileGenControl('set', 'CacheFolder', tmp, 'CodeGenFolder', tmp, 'createDir', true);
cd(tree);
ood_cache_current();
snap0 = listing(tree);

%% 1. The 84 frames of measure_latency.m
fprintf('kpi7_guard: setup and frames (measure_latency.m, current code)\n');
set_code(G, true(1, numel(G.rel)));
L = lat_load();
S = L.S; S.dev = 'cpu'; S.ug = false; S.gdev = []; S.det_first = false;
LF = {'img', 'raw', 'idle', 'g', 'probs', 'maha', 'cfg', 'mem', 'info'};
set_code(G, false(1, numel(G.rel)));
Y0 = lat_run(L, S); Y0b = lat_run(L, S);
set_code(G, true(1, numel(G.rel)));
Y1 = lat_run(L, S);
nd = cmp_lat(Y0, Y0b, L.CH, LF);                     % not deterministic between two old runs
c1 = cmp_lat(Y0, Y1, L.CH, LF);
V.lat = struct('n_frames', numel(L.F), 'chains', {L.CH}, 'fields', {LF}, 'old_vs_old', nd, 'old_vs_new', c1);
OPT = {'spec_image', 'direct'; 'mmse_predict', 'tail'; 'clean_ber_ref', 'interpolant'};
for i = 1:size(OPT, 1)
    set_code(G, true(1, numel(G.rel)));
    feval(OPT{i, 1}, OPT{i, 2}, true);
    V.opt_lat(i) = cmp_lat(Y0, lat_run(L, S), L.CH, LF);
end
set_code(G, true(1, numel(G.rel)));
Sd = S; Sd.det_first = true;
V.det_first = cmp_lat(Y1, lat_run(L, Sd), L.CH, LF);
Sp = S; Sp.PPm = rmfield(S.PPm, 'pw');
V.pw = cmp_lat(lat_run(L, Sp), Y1, L.CH, LF);
clear Y0b

%% 2. Replay of the deployed policy on the tree's test pools
fprintf('kpi7_guard: replay on the test pools\n');
Lp = load('data/policy_pools.mat', 'PP'); PP = Lp.PP; clear Lp
Qr = load('data/trained_dqn.mat', 'agent', 'agents', 'gammas', 'H', 'seed_summary', 'confirm', 'alarm_mode', 'drop_db', ...
    'deployed', 'rule_sel', 'det_id', 'maha_thr', 'dec');
check_det_id(PP, Qr, 'kpi7_guard');
PP = decision_settings(PP, Qr);
set_code(G, false(1, numel(G.rel))); K0 = link_env('tables', PP);
set_code(G, true(1, numel(G.rel))); K1 = link_env('tables', PP);
dep = 'dqn_esc'; if isfield(Qr, 'deployed') && ~isempty(Qr.deployed), dep = Qr.deployed; end
sel = 1; if all(isfield(Qr, {'gammas', 'seed_summary'})), sel = find(Qr.gammas == Qr.seed_summary.selected_gamma, 1); end
[kind, ag, op] = policy_setup(dep, Qr, sel, [], [], [], K1.na);
specs = replay_specs(PP, K1, Qr.H.T, o.sets, o.max_batches);
RF = {'obs', 'a', 'mem', 'info'};
z = zeros(1, numel(RF));
V.replay = struct('deployed', dep, 'sets', {o.sets}, 'batches', numel(specs), 'cycles', 0, 'fields', {RF}, ...
    'tables_equal', isequaln(K0, K1), 'old_vs_old', z, 'old_vs_new', z, 'interpolant', z, 'first_bad', 0);
for b = 1:numel(specs)
    seed = 7000 + b;
    set_code(G, false(1, numel(G.rel))); R0 = replay_batch(PP, K0, specs{b}, kind, ag, op, seed);
    if b == 1, V.replay.old_vs_old = cmp_rep(R0, replay_batch(PP, K0, specs{b}, kind, ag, op, seed), RF); end
    set_code(G, true(1, numel(G.rel))); d = cmp_rep(R0, replay_batch(PP, K1, specs{b}, kind, ag, op, seed), RF);
    V.replay.old_vs_new = V.replay.old_vs_new + d;
    if any(d) && V.replay.first_bad == 0, V.replay.first_bad = b; end
    set_code(G, true(1, numel(G.rel))); clean_ber_ref('interpolant', true);
    V.replay.interpolant = V.replay.interpolant + cmp_rep(R0, replay_batch(PP, K1, specs{b}, kind, ag, op, seed), RF);
    V.replay.cycles = V.replay.cycles + specs{b}.T * numel(specs{b}.scn);
    if mod(b, 10) == 0, fprintf('  %d / %d batches\n', b, numel(specs)); end
end

%% 3. Verdicts
V.caches = verdict(c1, nd, V.replay.old_vs_new, V.replay.old_vs_old, V.replay.tables_equal);
V.attribution = {};
if ~strcmp(V.caches, 'ACCEPTED')                       % each changed file alone on the current code
    for i = 1:numel(G.rel)
        u = false(1, numel(G.rel)); u(i) = true;
        set_code(G, u); bad = any(cmp_lat(Y0, lat_run(L, S), L.CH, LF).count);
        if V.replay.first_bad > 0
            b = V.replay.first_bad; seed = 7000 + b;
            set_code(G, false(1, numel(G.rel))); R0 = replay_batch(PP, K0, specs{b}, kind, ag, op, seed);
            set_code(G, u); bad = bad || any(cmp_rep(R0, replay_batch(PP, K0, specs{b}, kind, ag, op, seed), RF));
        end
        if bad, V.attribution{end+1} = G.rel{i}; end
    end
end
V.options = struct('name', {'spec_image direct', 'mmse_predict tail', 'clean_ber_ref interpolant'}, 'verdict', '');
for i = 1:size(OPT, 1)
    rp = z; rpo = z; tq = true;
    if i == 3, rp = V.replay.interpolant; rpo = V.replay.old_vs_old; end
    V.options(i).verdict = verdict(V.opt_lat(i), nd, rp, rpo, tq);
end
V.det_first_verdict = ternary(~any(V.det_first.count), 'IDENTICAL (the two read nothing of each other)', 'DIFFERS');
dec = strcmp(LF, 'cfg');
V.pw_verdict = ternary(~any(V.pw.count), 'IDENTICAL', ternary(~any(V.pw.count(dec)), ...
    'DECISIONS IDENTICAL, other outputs differ in the last bits', 'DECISIONS DIFFER'));
snap1 = listing(tree);
V.tree_changed = setxor(snap0, snap1);
write_verdict(V, root);
end

%% ---------- code versions ----------
function G = old_copies(root, base, tmp)
% Every function file under code/ changed since base (the drivers excepted), with base's copy
% in a folder of its own.
skip = {'code/evaluation/measure_latency.m', 'code/evaluation/lat_cycle.m', 'code/evaluation/kpi7_guard.m'};
rel = strsplit(git1(root, sprintf('diff --name-only %s -- code', base)), newline);
rel = rel(endsWith(rel, '.m') & ~startsWith(rel, 'code/tests/') & ~ismember(rel, skip));
G = struct('rel', {{}}, 'name', {{}}, 'dir', {{}}, 'cur', {{}});
for i = 1:numel(rel)
    [s, ~] = system(sprintf('git --no-optional-locks -C "%s" cat-file -e %s:%s', root, base, rel{i}));
    if s ~= 0, continue; end                          % a file new since base: the same in both
    [~, nm] = fileparts(rel{i});
    d = fullfile(tmp, 'old', nm); mkdir(d);
    [s, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', root, base, rel{i}, fullfile(d, [nm '.m'])));
    assert(s == 0, 'kpi7_guard: git show %s:%s failed: %s', base, rel{i}, out);
    G.rel{end+1} = rel{i}; G.name{end+1} = nm; G.dir{end+1} = d; G.cur{end+1} = fullfile(root, rel{i});
end
assert(~isempty(G.rel), 'kpi7_guard: no function file changed since %s', base);
fprintf('kpi7_guard: %d files changed since %s: %s\n', numel(G.rel), base, strjoin(G.rel, ', '));
end

function set_code(G, use_new)
% Base's copy first on the path where use_new(i) is false, the checkout's file otherwise;
% every function cleared, so no cache of the other version survives.
P = [pathsep path pathsep];
for i = 1:numel(G.rel)
    on = contains(P, [pathsep G.dir{i} pathsep], 'IgnoreCase', ispc);
    if ~use_new(i) && ~on, addpath(G.dir{i}, '-begin'); end
    if use_new(i) && on, rmpath(G.dir{i}); end
end
clear functions %#ok<CLFUNC>
for i = 1:numel(G.rel)
    want = G.cur{i}; if ~use_new(i), want = fullfile(G.dir{i}, [G.name{i} '.m']); end
    assert(strcmpi(canon(which(G.name{i})), canon(want)), 'kpi7_guard: %s resolves to %s, not %s', G.name{i}, ...
        which(G.name{i}), want);
end
end

function restore(cwd0, cfg0, G, tmp)
% Back to the checkout's code, the folder and Simulink's folders of the caller.
P = [pathsep path pathsep];
for i = 1:numel(G.dir)
    if contains(P, [pathsep G.dir{i} pathsep], 'IgnoreCase', ispc), rmpath(G.dir{i}); end
end
clear functions %#ok<CLFUNC>
cd(cwd0);
Simulink.fileGenControl('setConfig', 'config', cfg0);
if isfolder(tmp), rmdir(tmp, 's'); end
end

%% ---------- the frames of measure_latency.m ----------
function L = lat_load()
% measure_latency.m's setup and frames, in this workspace.
LAT_SETUP_ONLY = true; DET_FIRST = false; %#ok<NASGU>
measure_latency;
L = struct();
for v = {'S', 'POL', 'CH', 'F', 'na'}
    L.(v{1}) = eval(v{1});
end
end

function Y = lat_run(L, S)
% Every chain over the frames, in its own pass from a fresh memory (Y.(chain){frame}).
Y = struct();
for ci = 1:numel(L.CH)
    st = struct('cfg', L.na, 'mem', []);
    out = cell(1, numel(L.F));
    for f = 1:numel(L.F)
        [out{f}, ~, st] = lat_cycle(L.F{f}, S, L.POL.(L.CH{ci}), st);
    end
    Y.(L.CH{ci}) = out;
end
end

function R = cmp_lat(Ya, Yb, CH, fields)
% Per field, the cycles (all chains) whose outputs differ (isequaln); the first of them.
R = struct('count', zeros(1, numel(fields)), 'cycles', 0, 'first', '');
for ci = 1:numel(CH)
    for f = 1:numel(Ya.(CH{ci}))
        a = Ya.(CH{ci}){f}; b = Yb.(CH{ci}){f}; R.cycles = R.cycles + 1;
        for j = 1:numel(fields)
            if ~isequaln(a.(fields{j}), b.(fields{j}))
                R.count(j) = R.count(j) + 1;
                if isempty(R.first), R.first = sprintf('%s chain, frame %d, %s', CH{ci}, f, fields{j}); end
            end
        end
    end
end
end

%% ---------- replay ----------
function specs = replay_specs(PP, K, T, sets, nmax)
% The test-split episode batches of evaluate_policies.m's sets, one pass each.
TEST = 3; NE = 64; nS = numel(PP.ebno);
single_cells = find(ismember(PP.scen, PP.singles) & ~strcmp(PP.scen, 'none'));
combo_cells = find(ismember(PP.scen, PP.combos));
rs = RandStream('mt19937ar', 'Seed', 2027);
specs = {};
for s = sets
    switch s{1}
        case 'single', c = single_cells; u = false;
        case 'combined', c = combo_cells; u = false;
        case 'clean', c = K.clean; u = false;
        case 'unknown', c = single_cells; u = true;
        otherwise, error('kpi7_guard: unknown set %s', s{1});
    end
    b = policy_episodes(c, nS, K.geo(c, TEST), 1, false, u, NE, T, rs);
    if numel(b) > nmax, b = b(unique(round(linspace(1, numel(b), nmax)))); end
    specs = [specs, b]; %#ok<AGROW>
end
end

function R = replay_batch(PP, K, spec, kind, ag, op, seed)
% One batch as rollout_policy.m runs it: every cycle's observation, action, memory and info.
rs = RandStream('mt19937ar', 'Seed', seed);
op.rs = RandStream('mt19937ar', 'Seed', seed + 1);
[E, obs] = link_env('reset', PP, K, spec, 3, rs);
mem = []; R = cell(1, spec.T);
for t = 1:spec.T
    [a, mem, in] = policy_decide(kind, obs, E.cfg, mem, PP, ag, op);
    R{t} = struct('obs', obs, 'a', a, 'mem', mem, 'info', in);
    [E, ~, obs] = link_env('step', E, PP, K, a);
end
end

function n = cmp_rep(Ra, Rb, fields)
% Per field, the cycles whose outputs differ (isequaln).
n = zeros(1, numel(fields));
for t = 1:numel(Ra)
    for j = 1:numel(fields), n(j) = n(j) + ~isequaln(Ra{t}.(fields{j}), Rb{t}.(fields{j})); end
end
end

%% ---------- verdicts ----------
function v = verdict(c, nd, rp, rpo, tables_equal)
% ACCEPTED: every output identical; INCONCLUSIVE: only fields that differ between two old runs
% too; REJECTED otherwise.
bad = c.count > 0; nond = nd.count > 0;
rbad = rp > 0; rnond = rpo > 0;
if ~any(bad) && ~any(rbad) && tables_equal, v = 'ACCEPTED';
elseif all(nond(bad)) && all(rnond(rbad)) && tables_equal, v = 'INCONCLUSIVE (only fields that differ between two runs of the old code)';
else, v = 'REJECTED';
end
end

function ood_cache_current()
% ood_thresholds.m reads its cache without writing only when it is current.
c = 'data/ood_thresholds.mat'; d = 'data/trained_detector.mat';
ok = isfile(c) && dir(c).datenum >= dir(d).datenum;
if ok
    C = load(c, 'T'); Dd = load(d, 'ood'); W = 1;
    if isfield(Dd.ood, 'win') && ~isempty(Dd.ood.win), W = Dd.ood.win; end
    ok = isfield(C.T, 'retain') && C.T.retain == 0.95 && isfield(C.T, 'maha_val') && isfield(C.T, 'win') ...
        && C.T.win == W && strcmp(C.T.score, Dd.ood.score);
end
assert(ok, 'kpi7_guard: data/ood_thresholds.mat is not current, so ood_thresholds.m would write the tree');
end

function s = listing(tree)
% Every file of the tree (git's own folder excepted) with its size and time.
d = dir(fullfile(tree, '**', '*'));
d = d(~[d.isdir] & ~contains({d.folder}, [filesep '.git']));
s = strcat({d.folder}', filesep, {d.name}', '|', arrayfun(@(x) sprintf('%d|%.10f', x.bytes, x.datenum), d, ...
    'UniformOutput', false));
end

function c = canon(f)
c = char(java.io.File(f).getCanonicalPath());
end

function s = git1(dir0, args)
[st, s] = system(sprintf('git --no-optional-locks -C "%s" %s', dir0, args));
if st ~= 0, s = ''; end
s = strtrim(s);
end

function c = ternary(t, a, b)
if t, c = a; else, c = b; end
end

function write_verdict(V, root)
out = fullfile(root, 'results', 'kpi7'); if ~isfolder(out), mkdir(out); end
r = {};
r{end+1} = '=== KPI 7 GUARD: bit identity of the performance changes (docs/d126_kpi7.md) ===';
r{end+1} = sprintf('Generated %s | checkout %s at %s%s | base %s | tree %s at %s', V.generated, V.checkout, V.head, ...
    ternary(V.dirty, ' (uncommitted changes in code/)', ''), V.base, V.tree, V.tree_head);
r{end+1} = sprintf('Changed files (base copy vs checkout): %s', strjoin(V.files, ', '));
r{end+1} = sprintf('LAT frames: %d frames x %d chains (%s), detector on the CPU; fields %s', V.lat.n_frames, ...
    numel(V.lat.chains), strjoin(V.lat.chains, ', '), strjoin(V.lat.fields, ', '));
r{end+1} = ['  old vs old (determinism): ' counts(V.lat.old_vs_old.count, V.lat.fields)];
r{end+1} = ['  old vs new:               ' counts(V.lat.old_vs_new.count, V.lat.fields) first(V.lat.old_vs_new)];
r{end+1} = sprintf('Replay: deployed %s, sets %s, %d batches, %d episode-cycles, link_env tables %s; fields %s', ...
    V.replay.deployed, strjoin(V.replay.sets, ', '), V.replay.batches, V.replay.cycles, ...
    ternary(V.replay.tables_equal, 'identical', 'DIFFER'), strjoin(V.replay.fields, ', '));
r{end+1} = ['  old vs old (first batch): ' counts(V.replay.old_vs_old, V.replay.fields)];
r{end+1} = ['  old vs new:               ' counts(V.replay.old_vs_new, V.replay.fields)];
r{end+1} = sprintf('CACHES (default changes): %s', V.caches);
if ~isempty(V.attribution), r{end+1} = sprintf('  files that differ alone: %s', strjoin(V.attribution, ', ')); end
for i = 1:numel(V.options)
    r{end+1} = sprintf('OPTION %s: %s | LAT %s%s', V.options(i).name, V.options(i).verdict, ...
        counts(V.opt_lat(i).count, V.lat.fields), first(V.opt_lat(i))); %#ok<AGROW>
end
r{end+1} = sprintf('  clean_ber_ref interpolant on the replay: %s', counts(V.replay.interpolant, V.replay.fields));
r{end+1} = sprintf('DETECTOR BEFORE PREDICTOR (diagnostic order): %s | %s', V.det_first_verdict, ...
    counts(V.det_first.count, V.lat.fields));
r{end+1} = sprintf('PPm.pw in LAT (the pools'' power factors) vs without: %s | %s%s', V.pw_verdict, ...
    counts(V.pw.count, V.lat.fields), first(V.pw));
if isempty(V.tree_changed)
    r{end+1} = 'Tree: no file changed during the guard.';
else
    r{end+1} = sprintf('Tree: %d file entries changed during the guard (this guard or another process): %s', ...
        numel(V.tree_changed), strjoin(V.tree_changed(1:min(end, 20)), '; '));
end
fid = fopen(fullfile(out, 'guard_verdict.txt'), 'w'); fprintf(fid, '%s\n', r{:}); fclose(fid);
save(fullfile(out, 'guard_verdict.mat'), 'V');
fprintf('%s\n', r{:});
fprintf('Saved %s\n', fullfile(out, 'guard_verdict.{txt,mat}'));
end

function s = counts(n, fields)
s = strjoin(cellfun(@(f, k) sprintf('%s %d', f, k), fields, num2cell(n), 'UniformOutput', false), ', ');
end

function s = first(R)
s = ''; if ~isempty(R.first), s = sprintf(' (first: %s)', R.first); end
end
