function tests = test_ood_k2
%TEST_OOD_K2  Unit tests of D111 (the unknown-threat statistic U: ood_cue.m, unk_stat.m,
%   ood_k2_rules.m, unk_write.m, unk_guard.m, the monitor's hook, k2_1_screen.m end to end on
%   synthetic splits, ood_k2_run.m's guards) and of D116 reading 3 (k2_0_lines.m,
%   unk_options.m), on synthetic frames in a temporary folder; no pools, no network. Without
%   FM.unk, the k2_0 switch or D111's set-4 reading every output is the parent commit's bit for
%   bit. Run from the repository root:
%   results = runtests('code/tests/test_ood_k2.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- D116 reading 3 and the KPI print ----------
function test_k2_0_lines(tc)
% K2-0, descriptive and never KPI 2: bounds max(1 - FPR, s) .. min(1, 1 - FPR + s) with s 0
% for a threat whose countermeasure is no_action; the exact form per window at the deployed
% retention and at 95% (flagged, same countermeasure among the unflagged under the rule's
% mapping, their flagged-or-same-countermeasure share) and the AURC; never called coverage.
R = struct('held_out', {'antenna_fault', 'benign_interference', 'jamming'}, 'same_action', {0.85, 0.3, 0.0}, ...
    'fpr95', {[0.1 0.4], [0.1 0.25], [0.1 0.5]});
NEST = struct('fpr95', [0.4 0.25 0.5]);
L = k2_0_lines('bounds', R, NEST, 'last', {'raw', 'last'});
verifyNumElements(tc, L, 1);
for k = {'antenna_fault 85.0-100.0 (flagged 60.0, same countermeasure 85.0)', ...
        'benign_interference 75.0-75.0 (flagged 75.0, same countermeasure 0.0)', ...
        'jamming 50.0-50.0 (flagged 50.0, same countermeasure 0.0)', 'mean 70.0-75.0', 'descriptive, not KPI 2'}
    verifyNotEmpty(tc, strfind(L{1}, k{1}), k{1});
end
verifyEqual(tc, k2_0_lines('bounds', R, struct(), 'last', {'raw', 'last'}), L);
W = struct('threat', 'jamming', 'val', (1:100)' / 100, 'kn', [0.9; 0.8], 'un', [0; 0.02; 0.04; 0.5; 0.6], ...
    'y_kn', {{'none'; 'jamming'}}, 'top_kn', {{'none'; 'spoofing'}}, ...
    'top_un', {{'tone_jamming'; 'spoofing'; 'none'; 'spoofing'; 'none'}});
L = k2_0_lines('windows', W, 0.99);
verifyNumElements(tc, L, 3);
verifyNotEmpty(tc, strfind(L{1}, 'K2-0 at retention 0.99 (deployed) (descriptive, not KPI 2)'));
verifyNotEmpty(tc, strfind(L{1}, 'jamming 20.0 / 50.0 / 60.0'));
verifyNotEmpty(tc, strfind(L{2}, 'K2-0 at retention 0.95 (descriptive, not KPI 2)'));
verifyNotEmpty(tc, strfind(L{2}, 'jamming 60.0 / 50.0 / 80.0'));
verifyNotEmpty(tc, strfind(L{3}, 'jamming 0.229; mean 0.229'));
verifyNotEmpty(tc, strfind(L{3}, 'descriptive, not KPI 2'));
verifyEmpty(tc, regexp(strjoin(L, ' '), '(?<!risk-)coverage', 'once'));
end

function test_unk_options(tc)
% The k2_0 switch of profile.json: false without the file or the field, a logical value only.
d = fullfile(tc.TestData.tmp, 'opts'); mkdir(d); f = fullfile(d, 'profile.json');
verifyFalse(tc, unk_options(f).k2_0);
write_text(f, '{"other": 1}'); verifyFalse(tc, unk_options(f).k2_0);
write_text(f, '{"k2_0": false}'); verifyFalse(tc, unk_options(f).k2_0);
write_text(f, '{"k2_0": true}'); verifyTrue(tc, unk_options(f).k2_0);
write_text(f, '{"k2_0": 1}'); verifyError(tc, @() unk_options(f), 'unk_options:value');
end

function test_kpi2_print(tc)
% KPI 2's summary: without profile.json and with "k2_0": false it is the parent commit's bit
% for bit; "k2_0": true adds the K2-0 bounds.
d = fullfile(tc.TestData.tmp, 'kpi2'); mkdir(fullfile(d, 'results')); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
SC = {'msp', 'energy', 'iforest', 'last', 'raw'}; WIN = [2 5 8]; RETAIN = 0.95; sel = 'last'; sel_win = 5; %#ok<NASGU>
R = struct('held_out', {'jamming', 'tone_jamming'}, 'auroc', {[0.6 0.6 0.6 0.81 0.7], [0.6 0.6 0.6 0.83 0.7]}, ...
    'fpr95', {[0.5 0.5 0.5 0.41 0.6], [0.5 0.5 0.5 0.43 0.6]}, 'auroc_win', {0.9 * ones(5, 3), 0.9 * ones(5, 3)}, ...
    'same_action', {0.0, 0.9}); %#ok<NASGU>
pj = repelem(4:5, 4); pw = repmat([1 WIN], 1, 2); MpT = repmat(0.1 * (1:8), 2, 1); FpT = MpT / 10; MpV = MpT; %#ok<NASGU>
NEST = struct('auroc', [0.84 0.86], 'fpr95', [0.31 0.33], 'auroc_val', [0.8 0.8], 'pick', {{'last over 5', 'last over 5'}}); %#ok<NASGU>
TEST_SET = 'second test set'; %#ok<NASGU>
save('results/ood_detection.mat', 'R', 'SC', 'sel', 'sel_win', 'NEST', 'WIN', 'RETAIN', 'MpV', 'MpT', 'FpT', 'pj', 'pw', 'TEST_SET');
dp = parent_copy(tc, 'code/evaluation/measure_all_kpis.m', base_rev());
addpath(dp, '-begin'); clear measure_all_kpis
cl = onCleanup(@() fixture_off(dp, 'measure_all_kpis')); %#ok<NASGU>
verifyEqual(tc, which('measure_all_kpis'), fullfile(dp, 'measure_all_kpis.m'));
K0 = kpi2_of(run_kpis());
fixture_off(dp, 'measure_all_kpis');
verifyNotEqual(tc, which('measure_all_kpis'), fullfile(dp, 'measure_all_kpis.m'));
verifyEqual(tc, kpi2_of(run_kpis()), K0);
write_text('profile.json', '{"k2_0": false}');
verifyEqual(tc, kpi2_of(run_kpis()), K0);
write_text('profile.json', '{"k2_0": true}');
K = kpi2_of(run_kpis());
verifyEqual(tc, K.value, K0.value); verifyEqual(tc, K.status, K0.status);
verifyEqual(tc, K.detail(1:numel(K0.detail)), K0.detail);
verifyEqual(tc, K.detail{numel(K0.detail) + 1}, 'K2-0 on the second test set (results/ood_detection.mat)');
verifyNotEmpty(tc, strfind(K.detail{end}, 'jamming 69.0-69.0 (flagged 69.0, same countermeasure 0.0)'));
end

%% ---------- helpers ----------
function r = base_rev()
% The branch's parent commit (d108-edge, TIP3's lineage): the outputs every switch keeps when off.
r = 'f6f6e03';
end

function [sp, fresh] = loto_world()
% test_core.m's split of test_ood_loto_split: 12 sub-runs of 5 frames, none, jamming, spoofing.
rs = RandStream('mt19937ar', 'Seed', 12);
cls = {'none', 'jamming', 'spoofing'};
i = floor((0:59)' / 5); c = mod(i, 3) + 1;
yf = c; yf(c == 2 & mod((0:59)', 5) == 0) = 1;
lvr = 1 + mod(floor(i / 3), 2); lvr(c == 1) = NaN;
mk = @(r0) struct('X', rand(rs, 4, 4, 1, 60), 'feats', randn(rs, 60, 2), 'Y', categorical(cls(c), cls), ...
    'Y_frame', categorical(cls(yf), cls), 'run', r0 + i, 'pos', mod((0:59)', 5) + 1, 'ebno', 3 * floor(i / 6), 'level', lvr);
sp = struct('train', mk(1), 'val', mk(101), 'norm', struct('feat_mean', [1 -1], 'feat_std', [2 3]), 'classes', {cls'});
fresh = mk(201);
end

function [S, P, s0, y] = toy_split(nr, seed)
% 12 sub-runs of 16 frames in a shuffled row order, three classes (none, jamming, path_loss):
% nr antennas' gains with a 8 dB level step in the path-loss runs, link features with quiet-slot
% interference in the jamming runs, idle-time and branch records, per-frame probabilities and s0.
rs = RandStream('mt19937ar', 'Seed', seed);
nR = 12; L = 16; n = nR * L;
run = repelem((1:nR)' + 500, L); pos = repmat((1:L)', nR, 1);
o = randperm(rs, n)'; run = run(o); pos = pos(o);
y = mod(run, 3) + 1;
G = -10 + 3 * randn(rs, n, nr);
st = y == 3 & pos > 8; G(st, :) = G(st, :) - 8;
F = randn(rs, n, numel(link_features('names')));
F(:, feature_index('q_iot')) = 2 + 6 * (y == 2) + randn(rs, n, 1);
F(:, feature_index('est_margin')) = 5 + randn(rs, n, 1);
F(:, feature_index('duty')) = rand(rs, n, 1);
S = struct('run', run, 'pos', pos, 'gain_ant', G, 'feats_raw', F, ...
    'idle', rand(rs, n, numel(idle_summary('names'))) + 0.1, 'bch', rand(rs, n, 9 * nr) + 0.1);
P = rand(rs, n, 3) .^ 4 + 0.05 * (y == 1:3); P = P ./ sum(P, 2);
s0 = randn(rs, n, 1);
end

function FM = toy_fusion(S, P, y)
% A temporal fusion fitted on the toy split's windows of 12 frames, its latch off.
S.feat_names = link_features('names');
FM = fuse_classes('fit', fuse_classes('windows', S, P, 12), y, 3, 1e-3);
FM.latch = false;
end

function [U, u] = toy_model(S, X, full, s0, y, cand, N, Ns, NW)
% FM.unk of candidate cand on the toy split as ood_k2_run.m builds a fold's: the cue model on
% every window, s0 and the cue calibrated on the even sub-runs (the cue on its full windows), U
% on the odd ones as FM.unk.val; u, U of every window scored alone.
cal = mod(S.run, 2) == 0; sel = ~cal;
Sc = ood_cue('scale_fit', X);
Xs = ood_cue('scale', Sc, X);
if strcmp(cand, 'C2'), M = ood_cue('if_fit', Xs, 5); cue = 'if'; else, M = ood_cue('maha_fit', Xs, y); cue = 'maha'; end
U = struct('cand', cand, 'use0', ~strcmp(cand, 'C3'), 'cue', cue, 'scale', Sc, 'model', M, ...
    'cal0', unk_stat('cal', s0(cal)), 'cal1', [], 'val', [], 'nw', NW, 'step_n', Ns, 'N', N, 'score', 'last_or_if', 'win', 1);
U.cal1 = unk_stat('cal', unk_stat('cue', U, X(cal & full, :), true));
u = unk_stat('U', U, s0, X, full, true);
U.val = sort(u(sel));
U = unk_stat('model', U);
end

function PP = mon_pp(FM, N)
% Monitor settings of the toy split: every configuration with no known gain, the fusion FM over N.
A = policy_actions();
PP = struct('actions', {A}, 'classes', {{'none', 'jamming', 'path_loss'}}, 'sps', 4, 'bps', 2, 'maha_thr', 0, ...
    'cfg_gain_db', zeros(1, numel(A)), 'fuse', FM, 'fuse_N', N, 'unk_win', 1, 'unk_retain', 0.95);
end

function O = replay(PP, S, P, s0, forced)
% The monitor at no_action over every sub-run of S from its first frame, one episode at a
% time; per frame in S's row order M.unk_u (u), M.unk, the class, the fused probabilities and
% every M and memory. forced: the frame's own flag set (the withheld detector).
if nargin < 5, forced = false; end
A = PP.actions; na = find(strcmp(A, 'no_action')); n = numel(S.run);
O = struct('u', nan(n, 1), 'unk', false(n, 1), 'cls', {cell(n, 1)}, 'probs', nan(n, size(P, 2)), ...
    'M', {cell(n, 1)}, 'mem', {cell(n, 1)});
for r = unique(S.run)'
    ix = find(S.run == r); [~, o] = sort(S.pos(ix)); ix = ix(o);
    mem = policy_monitor('init', 1, numel(A));
    for i = ix(:)'
        ob = struct('probs', P(i, :), 'unknown', forced, 'maha', s0(i), 'feat', S.feats_raw(i, :), ...
            'gant', S.gain_ant(i, :), 'idle', S.idle(i, :), 'bch', S.bch(i, :));
        [mem, M] = policy_monitor('update', mem, ob, PP, na);
        mem = policy_monitor('change', mem, false);
        if isfield(M, 'unk_u'), O.u(i) = M.unk_u; O.unk(i) = M.unk; end
        O.cls(i) = M.cls; O.probs(i, :) = M.probs; O.M{i} = M; O.mem{i} = mem;
    end
end
end

function [PP, FMu, D] = unk_world()
% A detector, its thresholds and frame pools keyed to a fusion without FM.unk, in data/ of the
% current folder; FMu that fusion with a toy FM.unk.
ood = struct('score', 'last_or_if', 'win', 1); classes = {'none', 'jamming'}; trained_at = 7;
save('data/trained_detector.mat', 'ood', 'classes', 'trained_at');
T = struct('retain', 0.95, 'maha', -2, 'maha_val', [-3; -1], 'win', 1, 'score', 'last_or_if');
save('data/ood_thresholds.mat', 'T');
FM = struct('mu', zeros(1, 13)); N = 12; q_thr = 4.5;
save('data/fusion.mat', 'FM', 'N', 'q_thr');
FMu = FM; FMu.unk = struct('cand', 'C1', 'val', (1:100)' / 100);
Q = struct('probs', single([0.9 0.1]), 'maha', single(0), 'feat', single([1 2]), 'ber', 0, 'run', 1);
PP = struct('pools', {{Q, []}}, 'classes', {classes}, 'maha_thr', -2, 'unk_win', 1, 'fuse', FM, 'fuse_N', N, ...
    'q_thr', q_thr, 'det_id', detector_id(trained_at, ood, struct('FM', FM, 'N', N, 'q_thr', q_thr)), 'created', 'x', ...
    'maha_val', single(-(100:-1:1)' / 10), 'unk_retain', 0.95);
save('data/policy_pools.mat', 'PP', '-v7.3');
D = struct('ood', ood, 'trained_at', trained_at, 'N', N, 'q_thr', q_thr);
end

function k = guard_count(P, v, mv, extra)
% Confirmed clean episodes of guard (e)'s toy reading: 10 under either statistic, U extra more at
% retention 0.99; each statistic at its own threshold of the retention, unk_mode 'all'.
assert(strcmp(P.unk_mode, 'all') && strcmp(P.alarm_mode, 'class_drop'));
if unk_stat('on', P)
    assert(isequal(P.fuse.unk.val, v) && P.maha_thr == unk_threshold(P, P.unk_retain));
    k = 10 + extra * (P.unk_retain == 0.99);
else
    assert(P.maha_thr == unk_threshold(mv, P.unk_retain));
    k = 10;
end
end

function [G, P] = evalc_guard(PP, cnt)
% unk_guard.m with its re-key's prints held back.
[~, G, P] = evalc('unk_guard(PP, [], ''class_drop'', 4, 0, 30, 2, cnt)');
end

function k21_world(src)
% K2-1's inputs under src: data/splits.mat (train and val, five classes, 8 sub-runs of 14 frames
% per class), data/fusion.mat (N 12), data/trained_detector.mat (ood over 1 cycle) and the
% 18.10 file results/ood_detection.mat.
mkdir(fullfile(src, 'data')); mkdir(fullfile(src, 'results'));
cls = {'none', 'path_loss', 'jamming', 'antenna_fault', 'airframe_shadowing'};
fn = link_features('names');
splits = struct('train', k21_split(cls, 1000, 31), 'val', k21_split(cls, 2000, 32), 'test', [], ...
    'norm', struct('feat_mean', zeros(1, numel(fn)), 'feat_std', ones(1, numel(fn)), 'feat_names', {fn}), ...
    'classes', {cls'}); %#ok<NASGU>
save(fullfile(src, 'data', 'splits.mat'), 'splits', '-v7.3');
FM = struct('W', 1); N = 12; %#ok<NASGU>
save(fullfile(src, 'data', 'fusion.mat'), 'FM', 'N');
ood = struct('score', 'last_or_if', 'win', 1); %#ok<NASGU>
save(fullfile(src, 'data', 'trained_detector.mat'), 'ood');
SC = {'msp', 'energy', 'iforest', 'last', 'last_or_if'}; %#ok<NASGU>
R = struct('held_out', cls(2:end), 'auroc_val', {[0.5 0.5 0.5 0.6 0.64], [0.5 0.5 0.5 0.6 0.61], ...
    [0.5 0.5 0.5 0.6 0.69], [0.5 0.5 0.5 0.6 0.55]}); %#ok<NASGU>
save(fullfile(src, 'results', 'ood_detection.mat'), 'R', 'SC');
end

function P = k21_split(cls, r0, seed)
% 8 sub-runs of 14 frames per class at Eb/N0 0 and 3 dB and levels 1 and 2 (none: no level):
% path loss steps every antenna's level by 10 dB at frame 6, jamming fills the quiet slot, a
% fault drops one antenna by 15 dB, shadowing another by about 12 dB.
rs = RandStream('mt19937ar', 'Seed', seed);
L = 14; nR = 8; nC = numel(cls); n = L * nR * nC; nr = 3;
c = repelem((1:nC)', L * nR);
sr = repelem((1:nR * nC)', L);
pos = repmat((1:L)', nR * nC, 1);
k = mod(sr - 1, nR);
eb = 3 * mod(k, 2); lv = 1 + mod(floor(k / 2), 2); lv(c == 1) = NaN;
G = -10 + 2 * randn(rs, n, nr);
m = c == 2 & pos >= 6; G(m, :) = G(m, :) - 10;
m = c == 4; G(m, 1) = G(m, 1) - 15;
m = c == 5; G(m, 2) = G(m, 2) - 12 + 3 * randn(rs, sum(m), 1);
F = randn(rs, n, numel(link_features('names')));
F(:, feature_index('q_iot')) = 1 + 10 * (c == 3) + randn(rs, n, 1);
F(:, feature_index('est_margin')) = 6 + randn(rs, n, 1);
Y = categorical(cls(c), cls); Y = Y(:);
P = struct('X', zeros(2, 2, 1, n, 'single'), 'Y', Y, 'Y_frame', Y, 'feats', F, 'ebno', eb, 'run', r0 + sr, 'pos', pos, ...
    'level', lv, 'gain_ant', G, 'feats_raw', F);
end

function run_k21(src, repo, h)
% k2_1_screen.m with its inputs read from src and the registration commit h of repo.
K21_SRC = src; DOCS_REPO = repo; REG_COMMIT = h; %#ok<NASGU>
k2_1_screen;
end

function ood_run(V)
% ood_k2_run.m with the variables of V in this function's workspace.
if isfield(V, 'OOD_PHASE'), OOD_PHASE = V.OOD_PHASE; end %#ok<NASGU>
if isfield(V, 'OOD_FORCE'), OOD_FORCE = V.OOD_FORCE; end %#ok<NASGU>
if isfield(V, 'SMOKE'), SMOKE = V.SMOKE; end %#ok<NASGU>
if isfield(V, 'REG_COMMIT'), REG_COMMIT = V.REG_COMMIT; end %#ok<NASGU>
if isfield(V, 'DOCS_REPO'), DOCS_REPO = V.DOCS_REPO; end %#ok<NASGU>
ood_k2_run;
end

function [h1, h2] = docs_repo(repo)
% A docs repository with two commits: DECISIONS.md without D111 (h1), then with it (h2).
g = sprintf('git -C "%s" ', repo);
system([g 'init -q']);
f = fullfile(repo, 'docs', 'DECISIONS.md');
write_text(f, sprintf('## D110 - x\n'));
system([g 'add docs/DECISIONS.md']); system([g '-c user.name=t -c user.email=t@t commit -q -m a']);
[~, h1] = system([g 'rev-parse HEAD']); h1 = strtrim(h1);
write_text(f, sprintf('## D110 - x\n\n## D111 - y\n'));
system([g 'add docs/DECISIONS.md']); system([g '-c user.name=t -c user.email=t@t commit -q -m b']);
[~, h2] = system([g 'rev-parse HEAD']); h2 = strtrim(h2);
end

function K = run_kpis()
% measure_all_kpis.m in this function's workspace; its KPI struct array.
evalc('measure_all_kpis');
L = load('results/kpi_summary.mat', 'KPI'); K = L.KPI;
end

function k = kpi2_of(K)
k = K([K.id] == 2);
end

function y = stale3()
% Whether result_status.m reads the fourth set's reading as stale.
S = result_status(); y = S(strcmp({S.file}, 'results/eval_detector_metrics_fresh3.mat')).stale;
end

function y = mat73(f)
fid = fopen(f, 'r'); h = fread(fid, 116, '*char')'; fclose(fid);
y = contains(h, 'MATLAB 7.3');
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy
% queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, ...
    fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function fixture_off(d, fn)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
clear(fn);
if isfolder(d), rmdir(d, 's'); end
end
