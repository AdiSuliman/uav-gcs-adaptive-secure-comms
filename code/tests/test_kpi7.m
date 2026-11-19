function tests = test_kpi7
%TEST_KPI7  Unit tests of KPI 7's performance changes and honest timing (docs/d126_kpi7.md):
%   every cached function equals the base commit's copy of it (git show, the branch's base)
%   bit for bit on synthetic inputs, cold and warm, and again after its inputs change (the
%   cache follows them); the timing structure of measure_latency.m and lat_cycle.m (each chain
%   a whole cycle in its own passes, one policy per cycle, the wall clock beside the sum); the
%   readers of results/latency.mat still find every field they read. No data files. Run from
%   the repository root:
%   results = runtests('code/tests/test_kpi7.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.base = 'd4623ed';                            % the branch's base: the code before the changes
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.cfg = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', tc.TestData.tmp, 'CodeGenFolder', tc.TestData.tmp);
evalc('init_params');
tc.TestData.p = load('params.mat').params;
end

function teardownOnce(tc)
Simulink.fileGenControl('setConfig', 'config', tc.TestData.cfg);
cd(tc.TestData.cwd);
end

%% ---------- the caches against the base commit ----------
function test_decision_config_once(tc)
% The constants are built once; a caller's change to its copy never reaches the next caller.
clear decision_config
C1 = decision_config(); C2 = decision_config();
verifyTrue(tc, isequaln(C1, C2));
verifyTrue(tc, isequaln(C1, with_base(tc, {'code/decision/decision_config.m'}, @() decision_config())));
C1.win = -1;
verifyNotEqual(tc, decision_config().win, -1);
end

function test_config_gain_db_power_step(tc)
% Pools without PP.pw: the power step of every configuration holding power_control, as the
% per-call form computed it; another action list replaces the kept one, and back.
p = tc.TestData.p; A = policy_actions(); A2 = fliplr(A);
PP = struct('actions', {A}, 'cfg_gain_db', config_gain_db(A, p));
PP2 = struct('actions', {A2}, 'cfg_gain_db', config_gain_db(A2, p));
ref = @(Q) Q.cfg_gain_db(strcmp(Q.actions, 'power_control')) * ...
    cellfun(@(a) any(strcmp(strsplit(a, '+'), 'power_control')), Q.actions);
seq = {PP, PP2, PP, PP};
clear config_gain_db
g = cell(size(seq)); gw = g;
for i = 1:numel(seq), [g{i}, gw{i}] = config_gain_db(seq{i}); end   % one session: kept, replaced, kept
for i = 1:numel(seq)
    verifyTrue(tc, isequal(g{i}, seq{i}.cfg_gain_db) && isequal(gw{i}, ref(seq{i})));
    [gb, gwb] = with_base(tc, {'code/decision/config_gain_db.m'}, @() config_gain_db(seq{i}));
    verifyTrue(tc, isequal(g{i}, gb) && isequal(gw{i}, gwb) && strcmp(class(gw{i}), class(gwb)));
end
PP.pw = ones(1, numel(A)); PP.pw(strcmp(A, 'power_control')) = 4;   % pools that carry the power factors
[~, gw] = config_gain_db(PP);
verifyTrue(tc, isequal(gw, 10 * log10(PP.pw)));
end

function test_feature_index_fast_path(tc)
% Every name reads the column ismember gives, as a double; a list of names a vector; an
% unknown name stops as before.
names = link_features('names');
clear feature_index
for i = 1:numel(names)
    [~, j] = ismember(names(i), names);
    verifyTrue(tc, isequal(feature_index(names{i}), j) && isa(feature_index(names{i}), 'double'));
end
verifyEqual(tc, feature_index(names([3 1])), [3 1]);
jb = with_base(tc, {'code/detection/feature_index.m'}, @() cellfun(@feature_index, names));
verifyTrue(tc, isequal(cellfun(@feature_index, names), jb));
try
    feature_index('no_such_feature'); verifyFail(tc, 'an unknown name read a column');
catch err
    verifySubstring(tc, err.message, 'unknown feature');
end
end

function test_temporal_evidence_names_and_values(tc)
% The names for each class count, the class count changing back and forth, and the window's
% evidence on synthetic windows: as the base commit's.
rels = {'code/detection/temporal_evidence.m', 'code/detection/onset_shape.m'};
nc = [11 11 3 11 0];
[P, G, Fw] = synth_window(tc, 5, 11, 3, 10, 21);
nw = [10 10 6 10];
clear temporal_evidence onset_shape
nm = arrayfun(@(c) temporal_evidence('names', c), nc, 'UniformOutput', false);   % one session
x = arrayfun(@(n) temporal_evidence(P(:, :, 1:n), G(:, :, 1:n), Fw(:, :, 1:n)), nw, 'UniformOutput', false);
for i = 1:numel(nc)
    verifyTrue(tc, isequal(nm{i}, with_base(tc, rels, @() temporal_evidence('names', nc(i)))));
end
for i = 1:numel(nw)
    n = nw(i);
    verifyTrue(tc, isequaln(x{i}, with_base(tc, rels, @() temporal_evidence(P(:, :, 1:n), G(:, :, 1:n), Fw(:, :, 1:n)))));
end
end

function test_window_cues_and_idle_names(tc)
% The kept name lists and the cues of synthetic windows (idle records, branch records) are
% the base commit's.
rels = {'code/detection/window_cues.m', 'code/link/idle_summary.m'};
clear window_cues idle_summary
verifyTrue(tc, isequal(window_cues('names'), window_cues('names'), with_base(tc, rels, @() window_cues('names'))));
verifyTrue(tc, isequal(idle_summary('names'), with_base(tc, rels, @() idle_summary('names'))));
[~, G, Fw] = synth_window(tc, 4, 11, 3, 10, 22);
rs = RandStream('mt19937ar', 'Seed', 23);
Iw = 20 * rand(rs, 4, 24, 10); Iw(:, strcmp(idle_summary('names'), 'gap_ms'), :) = 5;
Bw = randn(rs, 4, 27, 10);
x = window_cues(G, Fw, Iw, Bw);
verifyTrue(tc, isequaln(x, with_base(tc, rels, @() window_cues(G, Fw, Iw, Bw))));
end

function test_onset_shape_caches(tc)
% The fit's grid follows the window length, the class list its value and type: the
% statistic and the latch over a run read as the base commit's.
rel = {'code/detection/onset_shape.m'};
rs = RandStream('mt19937ar', 'Seed', 31);
nw = [10 10 6 20 10];
W = cell(size(nw));
for i = 1:numel(nw)
    n = nw(i); W{i} = 0.5 * randn(rs, 3, 3, n); W{i}(2, 2, ceil(n / 2):end) = W{i}(2, 2, ceil(n / 2):end) - 12;
end
G = 0.3 * randn(rs, 30, 3); G(10:end, 2) = G(10:end, 2) - 15;
P = repmat([0.1 0.4 0.5], 30, 1);
cls = {'none', 'antenna_fault', 'airframe_shadowing'};
C = {cls, cls, string(cls), categorical(cls), cls};
clear onset_shape
x = cell(size(W)); F = x; q = cell(size(C)); k = q;
for i = 1:numel(W), [x{i}, F{i}] = onset_shape(W{i}); end        % one session
for i = 1:numel(C), [q{i}, k{i}] = onset_shape('sequence', G, P, C{i}, 5, 0); end
for i = 1:numel(W)
    [xb, Fb] = with_base(tc, rel, @() onset_shape(W{i}));
    verifyTrue(tc, isequaln(x{i}, xb) && isequaln(F{i}, Fb));
end
for i = 1:numel(C)
    [qb, kb] = with_base(tc, rel, @() onset_shape('sequence', G, P, C{i}, 5, 0));
    verifyTrue(tc, isequaln(q{i}, qb) && isequaln(k{i}, kb));
end
end

function test_clean_ber_ref_table(tc)
% Every kind, inside and beyond the table, any shape of input, the kinds alternating: the
% base commit's values; the interpolant option is off by default.
mkdir('data');
clean_ref = struct('ebno', 0:3:15, 'ber', [5e-2 1.5e-2 4e-3 9e-4 2e-4 3e-5], 'ber_est', [4e-2 1.2e-2 3e-3 8e-4 2e-4 5e-5], ...
    'plr_fec', [0.3 0.1 0.03 0.01 0.003 0]);
save('data/policy_pools.mat', 'clean_ref');
cl = onCleanup(@() delete('data/policy_pools.mat')); %#ok<NASGU>
e = [-9 -1 0 1.7 4.4 15 18 25; 2 3 5 7 11 13 14 15.5];
rel = {'code/decision/clean_ber_ref.m'};
K = {'ber_est', 'plr_fec', 'ber', 'ber_est', 'plr_fec'}; X = {e, e(:), e(1, :), 6.2};
clear clean_ber_ref
verifyFalse(tc, clean_ber_ref('interpolant'));
b = cell(numel(K), numel(X));
for i = 1:numel(K), for j = 1:numel(X), b{i, j} = clean_ber_ref(X{j}, K{i}); end, end   % one session
for i = 1:numel(K)
    for j = 1:numel(X)
        verifyTrue(tc, isequaln(b{i, j}, with_base(tc, rel, @() clean_ber_ref(X{j}, K{i}))), K{i});
    end
end
old = clean_ber_ref('interpolant', true);
verifyFalse(tc, old);
verifyEqual(tc, clean_ber_ref(e, 'ber_est'), with_base(tc, rel, @() clean_ber_ref(e, 'ber_est')), 'RelTol', 1e-12);
clear clean_ber_ref
verifyFalse(tc, clean_ber_ref('interpolant'));
end

function test_mmse_predict_caches(tc)
% The groups and their index sets, the receive filter's taps and the thread count: the
% prediction (searched and not) as the base commit's, warm and cold, for another layout and
% another filter and back; the thread count restored; the tail option off by default and,
% when on, within rounding of the default.
rel = {'code/link/mmse_predict.m'};
p = tc.TestData.p;
p2 = p; p2.pilot_every = 2 * p.pilot_every;
p3 = p; p3.rolloff = p.rolloff + 0.1;
Q = {p, p, p2, p3, p};
Y = cell(size(Q)); SY = Y; G = Y; D = Y;
for i = 1:numel(Q), [Y{i}, SY{i}] = synth_rx(Q{i}, 40 + i); end
clear mmse_predict
verifyFalse(tc, mmse_predict('tail'));
n0 = maxNumCompThreads;
for i = 1:numel(Q)                                       % one session: kept, rebuilt, back
    [G{i}, D{i}] = mmse_predict(Y{i}, Q{i}, SY{i});
    verifyEqual(tc, maxNumCompThreads, n0);
end
for i = 1:numel(Q)
    [Gb, Db] = with_base(tc, rel, @() mmse_predict(Y{i}, Q{i}, SY{i}));
    verifyTrue(tc, isequaln(G{i}, Gb) && isequaln(D{i}, Db));
end
cl = onCleanup(@() maxNumCompThreads(n0)); %#ok<NASGU>
maxNumCompThreads(1);
[y, sy] = synth_rx(p, 42);
verifyTrue(tc, isequaln(mmse_predict(y, p, sy), with_base(tc, rel, @() mmse_predict(y, p, sy))));
verifyEqual(tc, maxNumCompThreads, 1);
maxNumCompThreads(n0);
[grp, sk] = mmse_predict('groups', p); GI = mmse_predict('info', p);
verifyTrue(tc, isequal(GI.grp, grp) && isequal(GI.sk, sk) && isequal(GI.kall, [grp{2:end}]));
for g = 2:numel(grp)
    verifyTrue(tc, isequal(GI.kr{g}, [grp{setdiff(max(1, g - 2):min(numel(grp), g + 2), g)}]));
end
verifyTrue(tc, isequal(GI.c, cellfun(@mean, grp(3:end))));
mmse_predict('tail', true);
G1 = mmse_predict(y, p, sy);
mmse_predict('tail', false);
G2 = mmse_predict(y, p, sy);
verifyTrue(tc, isequal(isnan(G1), isnan(G2)));
verifyEqual(tc, G1(~isnan(G2)), G2(~isnan(G2)), 'AbsTol', 1e-9);
end

function test_mmse_layout_fields(tc)
% The groups are kept on every params field frame_layout.m and groups read, so a change of
% any of them rebuilds them.
f = mmse_predict('layout_fields');
src = [fileread(which('frame_layout')), function_text(fileread(which('mmse_predict')), 'groups')];
used = unique(cellfun(@(c) c{1}, regexp(src, '\<p\.(\w+)', 'tokens'), 'UniformOutput', false));
verifyEmpty(tc, setdiff(used, f), 'a field of the layout is not in the groups'' key');
end

function test_spec_image_window(tc)
% The kept window: the image as the base commit's; the direct STFT off by default and, when
% on, within rounding of spectrogram().
rel = {'code/detection/spec_image.m'};
rs = RandStream('mt19937ar', 'Seed', 51);
IQ = arrayfun(@(L) randn(rs, L, 1) + 1j * randn(rs, L, 1), [4000 4000 5321], 'UniformOutput', false);
clear spec_image
verifyFalse(tc, spec_image('direct'));
im = cellfun(@(iq) spec_image(iq, 1e6, 0.5), IQ, 'UniformOutput', false);   % one session
for i = 1:numel(IQ)
    verifyTrue(tc, isequaln(im{i}, with_base(tc, rel, @() spec_image(IQ{i}, 1e6, 0.5))));
end
iq = IQ{end}; img = im{end};
verifyEqual(tc, spec_image('noise'), with_base(tc, rel, @() spec_image('noise')));
spec_image('direct', true);
verifyEqual(tc, spec_image(iq, 1e6, 0.5), img, 'AbsTol', 1e-9);
spec_image('direct', false);
w = hann(128);
verifyEqual(tc, stft_ref(iq, w), spectrogram(iq, w, 113, 128, 1e6, 'centered'), 'AbsTol', 1e-9 * max(abs(iq)) * 128);
end

%% ---------- timing structure ----------
function test_lat_cycle_order(tc)
% One cycle in cycle order with exactly one policy call, the chain's own, with its options;
% the detector before the predictor only in the diagnostic order; the wall clock encloses
% the components.
d = stub_folder(tc);
x = struct('iq', 1, 'M', struct('gain_ant', ones(3, 2)), 'k', 1, 'iqa', 1, 'sy', 1);
S = struct('p0', struct(), 'fs', 1, 'tw', 10, 'D', struct('net', [], 'ood', []), 'mu', 0, 'sd', 1, ...
    'PPm', struct('maha_thr', 0), 'dev', 'cpu', 'ug', false, 'gdev', [], 'det_first', false);
P = struct('kind', 'rule_esc', 'agent', [], 'opt', struct('core', true));
kpi7_stub_log('reset');
[y, t, st] = lat_cycle(x, S, P, struct('cfg', 4, 'mem', []));
lg = kpi7_stub_log();
verifyEqual(tc, lg, {'thermal_nv', 'spec_image', 'link_features', 'mmse_predict', 'detect_scores', ...
    'policy_decide rule_esc 7 core'});
verifyEqual(tc, {y.cfg, st.cfg, st.mem}, {5, 5, 'mem'});
verifyEqual(tc, size(t), [1 6]);
verifyGreaterThanOrEqual(tc, t(6), sum(t(1:5)));
S.det_first = true; kpi7_stub_log('reset');
lat_cycle(x, S, P, st);
verifyEqual(tc, kpi7_stub_log(), {'thermal_nv', 'spec_image', 'link_features', 'detect_scores', 'mmse_predict', ...
    'policy_decide rule_esc 7 core'});
verifyTrue(tc, isfolder(d));
end

function test_measure_latency_passes(tc)
% Each chain a whole cycle in its own passes (the deployed chain with no other policy before
% it); the registered total the sum of the deployed chain's components; the wall clock printed
% right after it, a side reading; the GPU handle read once per device; the receiver's
% estimators named as untimed; the monitor reads the pools' power factors.
src = code_only(fileread(which('measure_latency'))); cyc = code_only(fileread(which('lat_cycle')));
hdr = fileread(which('measure_latency'));
verifyEmpty(tc, strfind(src, 'policy_decide('));
verifyNumElements(tc, strfind(cyc, 'policy_decide('), 1);
verifyNumElements(tc, strfind(src, 'lat_cycle('), 1);
verifyNotEmpty(tc, strfind(src, 'CH = {''dep'', ''dqn'', ''rule''};'));
verifyNotEmpty(tc, strfind(src, '[~, tt, st] = lat_cycle(F{f}, S, POL.(CH{ci}), st);'));
verifyNotEmpty(tc, strfind(src, 'tot_dep = tot(T.(dsel).dep);'));
verifyNotEmpty(tc, strfind(src, 'wall_dep = T.(dsel).dep(:, 6);'));
a = strfind(src, '''total (deployed)'', LAT.total_dep_median_ms'); b = strfind(src, '''wall (deployed)'', LAT.wall_dep_median_ms');
verifyNumElements(tc, a, 1); verifyNumElements(tc, b, 1);
verifyNumElements(tc, strfind(src(a:b), 'rep{end+1}'), 1);
verifyEmpty(tc, [strfind(src, 'wait(gpuDevice)'), strfind(cyc, 'gpuDevice')]);
verifyNotEmpty(tc, strfind(src, 'if S.ug, S.gdev = gpuDevice; end'));
verifyNotEmpty(tc, strfind(cyc, 'if S.ug, wait(S.gdev); end'));
verifyNotEmpty(tc, strfind(hdr, 'extract_closed_loop_frames.m) run in the'));
verifyNotEmpty(tc, strfind(src, 'PPm.pw(a) = cm.power_factor;'));
verifyNotEmpty(tc, strfind(fileread(which('build_policy_pools')), 'pw(a) = cm.power_factor;'));
r = strfind(src, 'if exist(''LAT_SETUP_ONLY'', ''var'') && LAT_SETUP_ONLY, return; end');
verifyNumElements(tc, r, 1);
verifyGreaterThan(tc, r, strfind(src, 'nF = numel(F);'));
verifyLessThan(tc, r, strfind(src, 'ld0 = machine_load();'));
verifyNotEmpty(tc, strfind(src, 'if DET_FIRST, out_dir = fullfile(''results'', ''kpi7''); out_name = ''latency_det_first''; end'));
% the diagnostic order from the environment (run_stage.m runs the script in a function
% workspace), read after the setup-only return and cleared as read: one run only
e = strfind(src, 'DET_FIRST = strcmp(getenv(''LAT_DET_FIRST''), ''1''); setenv(''LAT_DET_FIRST'', '''');');
verifyNumElements(tc, e, 1);
verifyGreaterThan(tc, e, r);
verifyEmpty(tc, strfind(src, 'exist(''DET_FIRST'''));
verifyNotEmpty(tc, strfind(src, '''gdev'', [], ''det_first'', false);'));
end

function test_det_first_env_one_run(tc)
% The environment flag is read once and cleared: the next run is the record's order.
setenv('LAT_DET_FIRST', '1'); cl = onCleanup(@() setenv('LAT_DET_FIRST', '')); %#ok<NASGU>
src = code_only(fileread(which('measure_latency')));
ln = regexp(src, 'DET_FIRST = strcmp\(getenv[^;]*;[^;]*;', 'match', 'once');
verifyNotEmpty(tc, ln);
DET_FIRST = [];
eval(ln);
verifyTrue(tc, DET_FIRST);
verifyEmpty(tc, getenv('LAT_DET_FIRST'));
eval(ln);
verifyFalse(tc, DET_FIRST);
end

function test_latency_readers(tc)
% Every field the KPI summary, the report export and the console read from LAT is written.
src = fileread(which('measure_latency'));
k = fileread(which('measure_all_kpis'));
g = function_text(fileread(which('demo_gui')), 'plotLatency');
rd = [regexp(k, '\<Lt\.(\w+)', 'tokens'), regexp(k, '\<sc\.(\w+)', 'tokens'), regexp(g, '\<Lt\.(\w+)', 'tokens')];
rd = setdiff(unique(cellfun(@(c) c{1}, rd, 'UniformOutput', false)), {'LAT'});   % Lt = Lt.LAT
for i = 1:numel(rd)
    verifyTrue(tc, contains(src, ['''' rd{i} ''',']) || contains(src, ['LAT.' rd{i} ' =']), rd{i});
end
verifyNotEmpty(tc, strfind(fileread(which('export_report_numbers')), 'N.latency = take(''results/latency.mat'', ''LAT'');'));
end

function test_guard_compares_every_output(tc)
% The guard compares every cycle output with isequaln and writes into the checkout only.
src = fileread(which('kpi7_guard'));
verifyNotEmpty(tc, strfind(src, 'LF = {''img'', ''raw'', ''idle'', ''g'', ''probs'', ''maha'', ''cfg'', ''mem'', ''info''};'));
verifyNotEmpty(tc, strfind(src, 'RF = {''obs'', ''a'', ''mem'', ''info''};'));
verifyNotEmpty(tc, strfind(src, 'isequaln(a.(fields{j}), b.(fields{j}))'));
verifyNotEmpty(tc, strfind(src, 'out = fullfile(root, ''results'', ''kpi7'');'));
verifyNotEmpty(tc, strfind(src, sprintf('BASE = ''%s'';', tc.TestData.base)));
verifyEmpty(tc, regexp(code_only(src), 'fullfile\(tree[^)]*''results''', 'once'));
c = code_only(src);
% old against new also without PPm.pw (config_gain_db's power-step path) and with the latch on
% (onset_shape's latch path), both in the caches' verdict
verifyNotEmpty(tc, strfind(c, 'Yp0 = lat_run(L, Sp); Yl0 = lat_run(L, Sl);'));
verifyNotEmpty(tc, strfind(c, 'Y1 = lat_run(L, S); Yp1 = lat_run(L, Sp); Yl1 = lat_run(L, Sl);'));
verifyNotEmpty(tc, strfind(c, 'cL.count = c1.count + cp.count + cq.count;'));
verifyNotEmpty(tc, strfind(c, 'V.replay.old_vs_new + V.replay.latch_old_vs_new'));
verifyNotEmpty(tc, strfind(c, 'PP.fuse.latch = true;'));
% LAT's setup built by each version and compared, in the caches' verdict
verifyNumElements(tc, strfind(c, 'lat_load();'), 2);
verifyNotEmpty(tc, strfind(c, 'V.setup = cmp_setup(L0, L);'));
verifyNotEmpty(tc, strfind(c, 'V.replay.tables_equal, V.setup.verdict);'));
% the coverage of the changed functions, named when not exercised
verifyNotEmpty(tc, strfind(c, 'V.not_exercised = coverage(G, PI);'));
verifyNotEmpty(tc, strfind(c, 'NOT EXERCISED by the guard'));
% the onCleanup handle is not reused
verifyNumElements(tc, regexp(c, '^\s*cl\s*=', 'start', 'lineanchors'), 1);
end

%% ---------- helpers ----------
function varargout = with_base(tc, rels, fn)
% fn() with the base commit's copies of rels first on the path; their functions cleared
% before and after, so neither version's cache reaches the other.
d = tempname; mkdir(d);
nm = cell(1, numel(rels));
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
for i = 1:numel(rels)
    [~, nm{i}] = fileparts(rels{i});
    [st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, tc.TestData.base, rels{i}, ...
        fullfile(d, [nm{i} '.m'])));
    assumeEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', tc.TestData.base, rels{i}, out));
end
addpath(d, '-begin'); cellfun(@clear, nm);
cl = onCleanup(@() base_off(d, nm)); %#ok<NASGU>
for i = 1:numel(rels), assertEqual(tc, canon(which(nm{i})), canon(fullfile(d, [nm{i} '.m']))); end
[varargout{1:max(nargout, 1)}] = fn();
end

function base_off(d, nm)
if contains(path, d), rmpath(d); end
cellfun(@clear, nm);
if isfolder(d), rmdir(d, 's'); end
end

function [P, G, Fw] = synth_window(tc, E, nC, nr, n, seed)
% Synthetic windows: class probabilities, antenna gains with one lost branch, link features.
rs = RandStream('mt19937ar', 'Seed', seed);
P = rand(rs, E, nC, n); P = P ./ sum(P, 2);
G = 3 * randn(rs, E, nr, n); G(1, 2, 5:end) = G(1, 2, 5:end) - 20;
nF = numel(link_features('names'));
Fw = 5 * randn(rs, E, nF, n); Fw(:, feature_index('est_margin'), 1:2:end) = -1;
Fw(:, feature_index('duty'), :) = rand(rs, E, 1, n);
verifyEqual(tc, size(Fw, 2), nF);
end

function [y, sy] = synth_rx(p, seed)
% Two frames of noise and a tone on every antenna (the search runs), frame 1 the filter's
% memory only, as measure_latency.m passes them.
rs = RandStream('mt19937ar', 'Seed', seed);
L = frame_layout(p); ns = L.air * p.sps; na = p.n_rx;
t = (0:ns-1)' / (p.symbol_rate * p.sps);
y = complex(randn(rs, ns, na, 2), randn(rs, ns, na, 2)) + 3 * exp(1j * 2*pi * 37e3 * t);
sy = [NaN, 2 * p.sps; NaN, 100];
end

function S = stft_ref(x, w)
% The centered STFT of spec_image('direct') written out: frames every 15 samples, bins -63..64.
nc = fix((numel(x) - 113) / 15);
S = zeros(128, nc);
for c = 1:nc
    s = fft(x((c - 1) * 15 + (1:128)) .* w);
    S(:, c) = s([66:128, 1:65]);
end
end

function d = stub_folder(tc)
% Stubs of the cycle's components that log their calls (kpi7_stub_log), first on the path.
d = tempname; mkdir(d);
stub = @(name, body) write_text(fullfile(d, [name '.m']), body);
stub('kpi7_stub_log', ['function out = kpi7_stub_log(s)' newline 'persistent L' newline ...
    'if nargin && strcmp(s, ''reset''), L = {}; elseif nargin, L{end+1} = s; end' newline 'out = L;' newline 'end']);
stub('thermal_nv', ['function v = thermal_nv(~)' newline 'kpi7_stub_log(''thermal_nv''); v = 1;' newline 'end']);
stub('spec_image', ['function img = spec_image(~, ~, ~)' newline 'kpi7_stub_log(''spec_image''); img = zeros(128);' newline 'end']);
stub('link_features', ['function raw = link_features(~, ~, ~)' newline 'kpi7_stub_log(''link_features''); raw = zeros(1, 3);' ...
    newline 'end']);
stub('mmse_predict', ['function g = mmse_predict(~, ~, ~)' newline 'kpi7_stub_log(''mmse_predict''); g = [NaN 2];' newline 'end']);
stub('detect_scores', ['function [p, m] = detect_scores(~, ~, ~, ~, ~)' newline 'kpi7_stub_log(''detect_scores''); ' ...
    'p = [0.5; 0.5]; m = 1;' newline 'end']);
stub('policy_decide', ['function [a, mem, info] = policy_decide(kind, ~, cfg, ~, ~, ~, opt)' newline ...
    'c = ''''; if isfield(opt, ''core''), c = '' core''; end' newline ...
    'kpi7_stub_log(sprintf(''policy_decide %s %d%s'', kind, nargin, c)); a = cfg + 1; mem = ''mem''; info = struct();' ...
    newline 'end']);
addpath(d, '-begin');
nm = {'kpi7_stub_log', 'thermal_nv', 'spec_image', 'link_features', 'mmse_predict', 'detect_scores', 'policy_decide'};
cellfun(@clear, nm);
tc.addTeardown(@() base_off(d, nm));
end

function c = canon(f)
c = char(java.io.File(f).getCanonicalPath());
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s\n', s); fclose(fid);
end

function s = code_only(src)
% The source without its comments (whole-line and trailing).
L = splitlines(src);
for i = 1:numel(L)
    k = regexp(L{i}, '%(?=(?:[^'']*''[^'']*'')*[^'']*$)', 'once');
    if ~isempty(k), L{i} = L{i}(1:k - 1); end
end
s = strjoin(L, newline);
end

function t = function_text(src, name)
% The text of local function name in src, up to the next function.
a = regexp(src, ['\n\s*function[^\n]*\<' name '\('], 'once');
if isempty(a), t = ''; return; end
b = regexp(src(a + 1:end), '\n\s*function\s', 'once');
if isempty(b), t = src(a:end); else, t = src(a:a + b - 1); end
end
