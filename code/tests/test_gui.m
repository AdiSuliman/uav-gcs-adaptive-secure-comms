function tests = test_gui
%TEST_GUI  Tests of the operator console's data path: the bundle exporter (clean-link reference and
%   its range, three-state model, norm statistics), console_core.m (three-state window, KPI lines),
%   console_policy.m (the deployed policy: DQN with or without escalation, rule fallback),
%   the decision cycle of the episode tab on a bundle exported from a smoke tree, headless
%   (no figure), and the console's start refusal. Run from the repository root:
%   results = runtests('code/tests/test_gui.m')
%   The tests on a smoke tree need two folders, named by environment variables, and are
%   skipped without them:
%     GUI_SMOKE_TREE  a smoke tree's folder (params.mat, data/, results/ of the deploy queue's smoke)
%     GUI_CORE_DIR    a folder with a full-run three-state model (data/core_cnn_model.mat,
%                     results/core_cnn.txt); read only, copied into the scratch root
%   GUI_BUILD_FIGURE=1 also builds the whole console on a hidden figure (test_console_builds_hidden).
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.warn = warning('off', 'MATLAB:load:variableNotFound');         % placeholder files in the exporter tests
tc.TestData.fx = []; tc.TestData.fx_err = '';
sm = getenv('GUI_SMOKE_TREE'); cm = getenv('GUI_CORE_DIR');
if ~isempty(sm) && isfolder(sm)
    try
        tc.TestData.fx = smoke_fixture(sm, cm, tc.TestData.tmp);
    catch ME
        tc.TestData.fx_err = getReport(ME);
    end
end
end

function teardownOnce(tc)
warning(tc.TestData.warn);
clean_ber_ref('reset');
cd(tc.TestData.cwd);
try, rmdir(tc.TestData.tmp, 's'); catch, end %#ok<NOCOM,CTCH>
end

%% ---------- the exporter ----------
function test_exporter_clean_reference_finite(tc)
% The bundle holds a small data/policy_pools.mat with the clean reference alone, and
% clean_ber_ref.m read from the bundle's own folder gives a finite value.
[root, tgt] = bundle_root(tc, 'ref_ok');
cr = clean_ref_table();
save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
export_quiet(tgt, root);
f = fullfile(tgt, 'rx3', 'data', 'policy_pools.mat');
verifyTrue(tc, isfile(f));
verifyEqual(tc, who('-file', f), {'clean_ref'});
c0 = cd(fullfile(tgt, 'rx3')); back = onCleanup(@() cd(c0));
clean_ber_ref('reset');
verifyTrue(tc, isfinite(clean_ber_ref(9, 'ber_est')));
verifyEqual(tc, clean_ber_ref(9, 'ber_est'), cr.clean_ref.ber_est(4), 'RelTol', 1e-9);
clear back
end

function test_exporter_refuses_reference_out_of_range(tc)
% The 9 dB value must lie in 3e-4 to 6e-3 (the pre-registered range of the rebuilt reference):
% a table below or above it is not exported, and none is left behind; values just inside the limits pass.
verifyEqual(tc, console_ref_range(), [3e-4 6e-3]);
[root, tgt] = bundle_root(tc, 'ref_range');
for b9 = [2.9e-4 6.1e-3 1e-4 1e-2]
    cr = clean_ref_table(); cr.clean_ref.ber_est(4) = b9; cr.clean_ref.ber(4) = b9;
    save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
    verifyError(tc, @() export_quiet(tgt, root), 'export_gui_bundle:clean_ref', sprintf('%g', b9));
    verifyFalse(tc, isfile(fullfile(tgt, 'rx3', 'data', 'policy_pools.mat')), sprintf('%g', b9));
end
for b9 = [3.01e-4 5.99e-3]
    cr = clean_ref_table(); cr.clean_ref.ber_est(4) = b9; cr.clean_ref.ber(4) = b9;
    save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
    export_quiet(tgt, root);
    verifyTrue(tc, isfile(fullfile(tgt, 'rx3', 'data', 'policy_pools.mat')), sprintf('%g', b9));
end
end

function test_exporter_refuses_missing_or_nan_reference(tc)
% No clean reference, or a table with a value that is not finite (clean_ber_ref.m would floor
% it silently): no export of a bundle whose link monitor would fall back to its floor on a
% clean link.
[root, tgt] = bundle_root(tc, 'ref_missing');
verifyError(tc, @() export_quiet(tgt, root), 'export_gui_bundle:clean_ref');
P = struct('PP', struct('x', 1)); save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'P');   % pools without clean_ref
verifyError(tc, @() export_quiet(tgt, root), 'export_gui_bundle:clean_ref');
cr = clean_ref_table(); cr.clean_ref.ber_est(2) = NaN;
save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
verifyError(tc, @() export_quiet(tgt, root), 'export_gui_bundle:clean_ref');
cr = clean_ref_table(); cr.clean_ref.ebno(4) = Inf;
save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
verifyError(tc, @() export_quiet(tgt, root), 'export_gui_bundle:clean_ref');
verifyFalse(tc, isfile(fullfile(tgt, 'rx3', 'data', 'policy_pools.mat')));      % none left behind
end

function test_exporter_core_files(tc)
% The three-state model and its report come along when present; a model marked smoke
% (a reduced chain check) does not, and an older copy in the bundle goes.
[root, tgt] = bundle_root(tc, 'core_files');
cr = clean_ref_table(); save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
net = 0; N = 3; names = {'clean', 'narrowband jamming', 'wideband jamming'}; groups = {'none', 'tone_jamming', 'jamming'}; %#ok<NASGU>
smoke = false; %#ok<NASGU>
save(fullfile(root, 'data', 'core_cnn_model.mat'), 'net', 'N', 'names', 'groups', 'smoke');
fid = fopen(fullfile(root, 'results', 'core_cnn.txt'), 'w'); fprintf(fid, 'report\n'); fclose(fid);
export_quiet(tgt, root);
dst = fullfile(tgt, 'rx3');
verifyTrue(tc, isfile(fullfile(dst, 'data', 'core_cnn_model.mat')));
verifyEqual(tc, strtrim(fileread(fullfile(dst, 'results', 'core_cnn.txt'))), 'report');
smoke = true; %#ok<NASGU>
save(fullfile(root, 'data', 'core_cnn_model.mat'), 'net', 'N', 'names', 'groups', 'smoke');
verifyWarning(tc, @() export_gui_bundle(tgt, root), 'export_gui_bundle:stale');
verifyFalse(tc, isfile(fullfile(dst, 'data', 'core_cnn_model.mat')));
delete(fullfile(root, 'data', 'core_cnn_model.mat')); delete(fullfile(root, 'results', 'core_cnn.txt'));
export_quiet(tgt, root);
verifyFalse(tc, isfile(fullfile(dst, 'results', 'core_cnn.txt')));
end

function test_exporter_norm_stats_without_splits(tc)
% The normalisation statistics come from split_norm.m (the top-level norm of splits.mat),
% not from loading the splits: a splits.mat holding only norm and classes is enough.
[root, tgt] = bundle_root(tc, 'norm');
cr = clean_ref_table(); save(fullfile(root, 'data', 'policy_pools.mat'), '-struct', 'cr');
delete(fullfile(root, 'data', 'gui_norm_stats.mat'));
norm = struct('feat_mean', [1 2 3], 'feat_std', [4 5 6], 'feat_names', {{'a', 'b', 'c'}}); %#ok<NASGU>
classes = {'none'; 'jamming'}; %#ok<NASGU>
save(fullfile(root, 'data', 'splits.mat'), 'norm', 'classes');
export_quiet(tgt, root);
L = load(fullfile(tgt, 'rx3', 'data', 'gui_norm_stats.mat'));
verifyEqual(tc, L.feat_mean, [1 2 3]); verifyEqual(tc, L.feat_std, [4 5 6]);
verifyFalse(tc, isfile(fullfile(root, 'data', 'gui_norm_stats.mat')), 'the checkout is only read: no cache written there');
for f = {'demo_gui', 'export_gui_bundle'}
    src = fileread(which(f{1}));
    verifyEmpty(tc, strfind(src, 'load(sp, ''splits'')'), f{1});
    verifyEmpty(tc, strfind(src, 'load(src, ''splits'')'), f{1});
    verifyNotEmpty(tc, regexp(src, 'split_norm\((sp|src)\)', 'once'), f{1});
end
end

%% ---------- console_core ----------
function test_console_core_window_and_truth(tc)
% The window is the normalised geometric mean of the last N frames' probabilities (the mean
% log-probability the stage reads); the state is its argmax; truth maps a threat to a state.
P = [0.9 0.05 0.05; 0.1 0.8 0.1; 0.2 0.7 0.1; 0.1 0.2 0.7; 0.05 0.05 0.9];
W = console_core('window', P, 3);
g = exp(mean(log(P(3:5, :)), 1)); g = g / sum(g);
verifyEqual(tc, W, g, 'AbsTol', 1e-12);
verifyEqual(tc, sum(W), 1, 'AbsTol', 1e-12);
verifyEqual(tc, console_core('window', P(1:2, :), 3), exp(mean(log(P(1:2, :)), 1)) / sum(exp(mean(log(P(1:2, :)), 1))), 'AbsTol', 1e-12);
M = struct('net', [], 'N', 3, 'names', {{'clean', 'narrowband jamming', 'wideband jamming'}}, 'groups', {{'none', 'tone_jamming', 'jamming'}});
S = console_core('read', M, P);
verifyEqual(tc, S.win, g, 'AbsTol', 1e-12); verifyEqual(tc, S.n, 3); verifyEqual(tc, S.frame, P(end, :));
[~, k] = max(g); verifyEqual(tc, S.idx, k); verifyEqual(tc, S.name, M.names{k});
verifyEqual(tc, [console_core('truth', M, 'none') console_core('truth', M, 'tone_jamming') console_core('truth', M, 'jamming') ...
    console_core('truth', M, 'noise_burst')], [1 2 3 0]);
verifyEqual(tc, console_core('policy_opt'), struct('core', true));
verifyError(tc, @() console_core('nope'), 'console_core:cmd');
end

function test_console_core_load_skips_reduced_model(tc)
d = fullfile(tc.TestData.tmp, 'load_model'); mkdir(fullfile(d, 'data'));
c0 = cd(d); back = onCleanup(@() cd(c0));
verifyEmpty(tc, console_core('load'));                                       % none in the folder
net = 0; N = 3; names = {'a', 'b', 'c'}; groups = {'none', 'tone_jamming', 'jamming'}; smoke = true; %#ok<NASGU>
save('data/core_cnn_model.mat', 'net', 'N', 'names', 'groups', 'smoke');
verifyEmpty(tc, console_core('load'));                                       % a reduced chain check
smoke = false; %#ok<NASGU>
save('data/core_cnn_model.mat', 'net', 'N', 'names', 'groups', 'smoke');
M = console_core('load');
verifyEqual(tc, M.N, 3); verifyEqual(tc, M.names, names); verifyEqual(tc, M.groups, groups);
clear back
end

function test_console_core_kpi_lines(tc)
d = fullfile(tc.TestData.tmp, 'kpi_lines'); mkdir(d);
verifyEmpty(tc, console_core('kpi_lines', d));
t = {'=== TITLE ===', '', '--- The lecturer''s KPIs: every Eb/N0 ---', 'core CNN, window N = 3 (official)', ...
    '  macro-F1, three states (>= 85%)       99.83% [99.64, 99.97]  met (committed)', '', '--- Confusion matrices ---', 'row'};
fid = fopen(fullfile(d, 'core_cnn.txt'), 'w'); fprintf(fid, '%s\n', t{:}); fclose(fid);
k = {'KPI 1  Detection', '        beside KPI 4, PER (lecturer: reduction >= 30%): NOT MET', 'KPI 2  x'};
fid = fopen(fullfile(d, 'kpi_summary.txt'), 'w'); fprintf(fid, '%s\n', k{:}); fclose(fid);
L = console_core('kpi_lines', d);
verifyEqual(tc, L, {t{3}; t{4}; t{5}; 'beside KPI 4, PER (lecturer: reduction >= 30%): NOT MET'});
end

%% ---------- the console's start ----------
function test_clean_reference_follows_the_folder(tc)
% clean_ber_ref.m reads the working folder's pools: a table cached from another folder is not
% used (the console switches bundles within one session), and 'reset' drops the cache.
a = fullfile(tc.TestData.tmp, 'ref_a'); b = fullfile(tc.TestData.tmp, 'ref_b'); mkdir(fullfile(a, 'data')); mkdir(fullfile(b, 'data'));
cr = clean_ref_table(); save(fullfile(a, 'data', 'policy_pools.mat'), '-struct', 'cr');
cr.clean_ref.ber_est = 2 * cr.clean_ref.ber_est; save(fullfile(b, 'data', 'policy_pools.mat'), '-struct', 'cr');
c0 = cd(a); back = onCleanup(@() cd(c0));
clean_ber_ref('reset');
va = clean_ber_ref(9, 'ber_est');
cd(b); vb = clean_ber_ref(9, 'ber_est');
verifyEqual(tc, vb, 2 * va, 'RelTol', 1e-9);
n = fullfile(tc.TestData.tmp, 'ref_none'); mkdir(n); cd(n);
verifyTrue(tc, isnan(clean_ber_ref(9, 'ber_est')));                       % none here: not the table of the folder before
clear back
end

%% ---------- the console's start ----------
function test_console_refuses_without_clean_reference(tc)
% No finite clean reference in the folder, also after another folder's table was read in
% this session: the console stops with the re-export message before it loads anything.
a = fullfile(tc.TestData.tmp, 'start_ok'); mkdir(fullfile(a, 'data'));
cr = clean_ref_table(); save(fullfile(a, 'data', 'policy_pools.mat'), '-struct', 'cr');
d = fullfile(tc.TestData.tmp, 'start_no_ref'); mkdir(fullfile(d, 'data'));
c0 = cd(a); back = onCleanup(@() cd(c0));
clean_ber_ref('reset'); verifyTrue(tc, isfinite(clean_ber_ref(9, 'ber_est')));
cd(d);
err = [];
try
    demo_gui();
catch ME
    err = ME;
end
verifyNotEmpty(tc, err);
if ~isempty(err)
    verifyEqual(tc, err.identifier, 'demo_gui:clean_ref');
    verifySubstring(tc, err.message, 'Re-export the bundle');
end
% a NaN away from 9 dB: clean_ber_ref floors it, so the 9 dB value is finite, but the console stops
e = fullfile(tc.TestData.tmp, 'start_nan_ref'); mkdir(fullfile(e, 'data'));
cr.clean_ref.ber_est(end) = NaN; save(fullfile(e, 'data', 'policy_pools.mat'), '-struct', 'cr');
cd(e); clean_ber_ref('reset'); verifyTrue(tc, isfinite(clean_ber_ref(9, 'ber_est')));
err = [];
try
    demo_gui();
catch ME
    err = ME;
end
verifyNotEmpty(tc, err);
if ~isempty(err), verifyEqual(tc, err.identifier, 'demo_gui:clean_ref'); end
clear back
end

function test_console_refuses_reference_out_of_range(tc)
% A finite reference whose 9 dB value is outside 3e-4 to 6e-3 stops the console's start with the
% re-export message, before any model is loaded.
for b9 = [1e-4 1e-2]
    d = fullfile(tc.TestData.tmp, sprintf('start_range_%g', b9)); mkdir(fullfile(d, 'data'));
    cr = clean_ref_table(); cr.clean_ref.ber_est(4) = b9; cr.clean_ref.ber(4) = b9;
    save(fullfile(d, 'data', 'policy_pools.mat'), '-struct', 'cr');
    c0 = cd(d); back = onCleanup(@() cd(c0));
    clean_ber_ref('reset');
    err = [];
    try
        demo_gui();
    catch ME
        err = ME;
    end
    verifyNotEmpty(tc, err);
    if ~isempty(err)
        verifyEqual(tc, err.identifier, 'demo_gui:clean_ref');
        verifySubstring(tc, err.message, 'outside');
        verifySubstring(tc, err.message, 'Re-export the bundle');
    end
    clear back
end
end

%% ---------- the deployed policy ----------
function test_policy_dqn_with_escalation(tc)
% The selected DQN with escalation: the escalation checkbox starts on, the policy_decide.m kind
% follows it, the settings are the DQN's own (PP as given).
D = console_policy('deployed', trained_stub('dqn_esc', 'dqn_esc'));
verifyEqual(tc, D.kind, 'dqn_esc'); verifyTrue(tc, D.esc); verifyFalse(tc, D.is_rule); verifyTrue(tc, D.recorded);
verifyEqual(tc, D.name, 'DQN'); verifyEmpty(tc, D.monitor);
verifyEqual(tc, [console_policy('kind', D, true) '|' console_policy('kind', D, false)], ['dqn_esc|dqn']);
PP = struct('maha_thr', 1.5, 'confirm', [2 2]);
verifyEqual(tc, console_policy('settings', D, PP, true), PP);
verifyEqual(tc, console_policy('settings', D, PP, false), PP);
end

function test_policy_dqn_without_escalation(tc)
% The no-escalation agent (the likely outcome: only it can pass the false-alarm bound): the
% checkbox starts off and says so, the Live tab runs 'dqn', not 'dqn_esc'.
D = console_policy('deployed', trained_stub('dqn', 'dqn'));
verifyEqual(tc, D.kind, 'dqn'); verifyFalse(tc, D.esc); verifyFalse(tc, D.is_rule);
verifySubstring(tc, D.text, 'without escalation');
verifyEqual(tc, console_policy('kind', D, D.esc), 'dqn');
verifyEqual(tc, console_policy('kind', D, true), 'dqn_esc');           % the operator may switch it on
ctx = console_policy('ctx', D, D.esc, struct('policy', 'dqn_esc', 'PP', struct('maha_thr', 2)));
verifyEqual(tc, ctx.policy, 'dqn'); verifyEqual(tc, ctx.PP.maha_thr, 2);
end

function test_policy_rule_fallback(tc)
% The rule fallback (deployed = rule_sel, the DQN selected as dqn_esc did not pass): the console
% runs rule + escalation on the fallback's monitor, its escalation default is on, the rule's
% settings replace PP's; in the Live tab the operator's unknown-threat threshold stays.
Q = trained_stub('rule_sel', 'dqn_esc');
D = console_policy('deployed', Q);
verifyEqual(tc, D.kind, 'rule_sel'); verifyTrue(tc, D.is_rule); verifyTrue(tc, D.esc);
verifyEqual(tc, D.name, 'deployed rule'); verifySubstring(tc, D.text, 'rule + escalation');
verifyEqual(tc, D.selected_kind, 'dqn_esc');
verifyEqual(tc, console_policy('kind', D, true), 'rule_esc');
verifyEqual(tc, console_policy('kind', D, false), 'rule');
PP = struct('maha_thr', 1.5, 'unk_retain', 0.95, 'confirm', [2 2], 'alarm_mode', 'class', 'drop_db', 4);
E = console_policy('settings', D, PP, false);                           % the episode: every setting as evaluated
verifyEqual(tc, E.confirm, [3 3]); verifyEqual(tc, E.alarm_mode, 'drop'); verifyEqual(tc, E.drop_db, 6);
verifyEqual(tc, E.maha_thr, 3.25); verifyEqual(tc, E.unk_retain, 0.9);
L = console_policy('settings', D, PP, true);                            % the Live tab: the slider's threshold stays
verifyEqual(tc, L.confirm, [3 3]); verifyEqual(tc, L.alarm_mode, 'drop');
verifyEqual(tc, L.maha_thr, 1.5); verifyEqual(tc, L.unk_retain, 0.95);
ctx = console_policy('ctx', D, true, struct('policy', 'dqn_esc', 'PP', PP));
verifyEqual(tc, ctx.policy, 'rule_esc'); verifyEqual(tc, ctx.PP.confirm, [3 3]);
end

function test_policy_older_training_and_errors(tc)
% No deployed policy recorded (an older training): the selected kind, else the DQN with
% escalation, flagged as assumed; inconsistent or incomplete records are errors, not guesses.
Q = trained_stub('dqn_esc', 'dqn'); Q = rmfield(Q, 'deployed');
D = console_policy('deployed', Q);
verifyEqual(tc, D.kind, 'dqn'); verifyFalse(tc, D.recorded);
D = console_policy('deployed', struct());
verifyEqual(tc, D.kind, 'dqn_esc'); verifyFalse(tc, D.recorded); verifyTrue(tc, D.esc);
verifyError(tc, @() console_policy('deployed', trained_stub('table', 'dqn')), 'console_policy:deployed');
verifyError(tc, @() console_policy('deployed', trained_stub('dqn', 'dqn_esc')), 'console_policy:kind');
verifyError(tc, @() console_policy('deployed', trained_stub('dqn_esc', 'oracle')), 'console_policy:kind');
Q = trained_stub('rule_sel', 'dqn'); Q = rmfield(Q, 'rule_sel');
verifyError(tc, @() console_policy('deployed', Q), 'console_policy:rule_sel');
verifyError(tc, @() console_policy('nope'), 'console_policy:cmd');
end

function test_policy_load_from_file(tc)
% The reader takes what trained_dqn.mat holds (deployed, seed_summary.selected_kind, rule_sel) and
% tolerates a file without them.
d = fullfile(tc.TestData.tmp, 'policy_files'); mkdir(d);
Q = trained_stub('rule_sel', 'dqn'); f = fullfile(d, 'rule.mat');
save(f, '-struct', 'Q');
D = console_policy('load', f);
verifyEqual(tc, D.kind, 'rule_sel'); verifyEqual(tc, D.selected_kind, 'dqn'); verifyEqual(tc, D.monitor.confirm, [3 3]);
agent = 1; f2 = fullfile(d, 'old.mat'); save(f2, 'agent');
D = console_policy('load', f2);
verifyEqual(tc, D.kind, 'dqn_esc'); verifyFalse(tc, D.recorded);
end

function test_policy_decisions_follow_the_deployed_kind(tc)
% The decision cycle as the console runs it, with a stub Q-network: the deployed no-escalation DQN
% never escalates where the DQN with escalation does on the same frames, and the rule fallback
% confirms an alarm on its own monitor (3-of-3) later than the rule on the DQN's (2-of-2).
A = policy_actions(); nA = numel(A); na = find(strcmp(A, 'no_action'));
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'confirm', [2 2], 'alarm_mode', 'class');
c0 = find(strcmp(A, rule_based_policy('jamming', true, 0)));
c1 = find(~ismember(1:nA, [na c0]), 1);
qpref = zeros(nA, 1); qpref(c0) = 10; qpref(c1) = 5;
nS = policy_state_size(nA);
agent = struct('dense', struct('W', {{zeros(nA, nS, 'single')}}, 'b', {{single(qpref)}}, ...
    'mu', zeros(nS, 1, 'single'), 'sd', ones(nS, 1, 'single')));
obs = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs.feat(feature_index('log_ber')) = -1; obs.feat(feature_index('crc_fail')) = 1;
for dk = {'dqn_esc', 'dqn'}
    D = console_policy('deployed', trained_stub(dk{1}, dk{1}));
    kind = console_policy('kind', D, D.esc);
    cfg = na; mem = []; esc = false; seen = false(1, nA);
    for k = 1:40
        obs.cfg_link = cfg;
        [cfg, mem, d] = policy_decide(kind, obs, cfg, mem, console_policy('settings', D, PP, true), agent);
        esc = esc || d.escalated; seen(cfg) = true;
    end
    verifyTrue(tc, seen(c0), dk{1});                                    % the Q-network's choice is taken
    verifyEqual(tc, esc, D.esc, ['escalation in ' dk{1}]);
    verifyEqual(tc, seen(c1), D.esc, ['second choice reached only by the escalation in ' dk{1}]);
end
R = console_policy('deployed', trained_stub('rule_sel', 'dqn_esc'));
obs2 = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs2.feat(feature_index('log_ber')) = -6;
conf = zeros(1, 2);
for q = 1:2
    P2 = PP; kind = 'rule_esc';
    if q == 2, P2 = console_policy('settings', R, PP, false); kind = console_policy('kind', R, true); end
    mem = [];
    for k = 1:6
        [~, mem, d] = policy_decide(kind, obs2, na, mem, P2, []);
        if d.confirmed, conf(q) = k; break; end
    end
end
verifyEqual(tc, conf, [2 3]);
end

function test_console_source_follows_the_deployed_policy(tc)
% demo_gui.m runs the deployed kind and never a fixed one: no policy_decide.m call with the literal
% 'dqn_esc', the checkbox starts at the deployed escalation, the start reads trained_dqn.mat
% through console_policy.m.
src = fileread(which('demo_gui'));
verifyEmpty(tc, regexp(src, 'policy_decide\(\s*''dqn', 'once'));
verifyNotEmpty(tc, regexp(src, 'console_policy\(''load''', 'once'));
verifyNotEmpty(tc, regexp(src, '''Value'', env\.dep\.esc', 'once'));
verifyNotEmpty(tc, regexp(src, 'console_ref_range\(\)', 'once'));
end

%% ---------- smoke tree: exported bundle, headless decision path ----------
function test_smoke_bundle_has_finite_reference(tc)
fx = need_fixture(tc);
c0 = cd(fx.bundle); back = onCleanup(@() cd(c0));
clean_ber_ref('reset');
verifyTrue(tc, isfinite(clean_ber_ref(9, 'ber_est')));
verifyEqual(tc, who('-file', 'data/policy_pools.mat'), {'clean_ref'});
for f = {'data/trained_detector.mat', 'data/trained_dqn.mat', 'data/gui_norm_stats.mat', 'data/ood_thresholds.mat', ...
        'data/fusion.mat', 'params.mat', 'profile.json'}
    verifyTrue(tc, isfile(f{1}), f{1});
end
if fx.core
    verifyTrue(tc, isfile('data/core_cnn_model.mat')); verifyTrue(tc, isfile('results/core_cnn.txt'));
    verifyNotEmpty(tc, console_core('kpi_lines', 'results'));
end
clear back
end

function test_headless_decision_path(tc)
% The episode tab's decision cycle on the exported smoke bundle, no figure: the detector and
% the unknown-threat score, then the DQN with escalation, the rule with escalation and the
% core rule on the same frames; the three-state CNN reads every cycle of its window.
fx = need_fixture(tc);
c0 = cd(fx.bundle); back = onCleanup(@() cd(c0));
rng(7);
env = headless_env();
C = decision_config();
nA = numel(env.action_names);
[frames, truth] = synthetic_frames(fx, env, 8, 10);
N = numel(frames);
pols = {'dqn_esc', false; 'rule_esc', false; 'rule_esc', true};
used = cell(1, 3);
for q = 1:3
    ctx = env_ctx(env, pols{q, 1}, pols{q, 2}, fx.core);
    E = [];
    for k = 1:N
        [E, info] = episode_cycle(E, k, frames{k}, ctx);
        verifyGreaterThanOrEqual(tc, info.cfg, 1); verifyLessThanOrEqual(tc, info.cfg, nA);
        verifyTrue(tc, ismember(info.cls, env.class_list));
        verifyEqual(tc, info.cfg, E.cfg);
        if pols{q, 2}
            verifyTrue(tc, ismember(env.action_names{info.cfg}, C.core_actions), 'the core rule stays in the core set');
        end
        if pols{q, 1}(1) == 'd', verifyNumElements(tc, info.qv, nA); end
        if fx.core
            s = info.state3;
            verifyNotEmpty(tc, s);
            verifyEqual(tc, sum(s.win), 1, 'AbsTol', 1e-9);
            verifyEqual(tc, s.n, min(k, env.core.N));
            verifyTrue(tc, ismember(s.name, env.core.names));
            verifyTrue(tc, all(isfinite(s.frame)));
        else
            verifyEmpty(tc, info.state3);
        end
        used{q}(end+1) = info.cfg; %#ok<AGROW>
    end
end
fprintf('HEADLESS actions used (dqn / rule / core): %s | %s | %s\n', strjoin(unique(env.action_names(used{1}), 'stable'), ','), ...
    strjoin(unique(env.action_names(used{2}), 'stable'), ','), strjoin(unique(env.action_names(used{3}), 'stable'), ','));
if fx.core
    fprintf('HEADLESS three-state reads (clean / tone / wideband noise): %s\n', headless_state_trace(env, frames, truth));
end
verifyEqual(tc, numel(truth), N);
clear back
end

function test_headless_deployed_policy_kinds(tc)
% The deployed no-escalation DQN and the rule fallback through the episode cycle on the exported
% bundle: the DQN reports its Q-values, the rule fallback none; both stay in the configuration set.
fx = need_fixture(tc);
c0 = cd(fx.bundle); back = onCleanup(@() cd(c0));
rng(5);
env = headless_env(); [frames, ~] = synthetic_frames(fx, env, 4, 6);
nA = numel(env.action_names);
R = rule_stub(env.PP);
for dk = {'dqn', 'rule_sel'}
    D = console_policy('deployed', trained_stub(dk{1}, 'dqn'));
    if D.is_rule, D.monitor = R; end
    ctx = console_policy('ctx', D, D.esc, env_ctx(env, 'dqn_esc', false, false));
    E = [];
    for k = 1:numel(frames)
        [E, info] = episode_cycle(E, k, frames{k}, ctx);
        verifyGreaterThanOrEqual(tc, info.cfg, 1); verifyLessThanOrEqual(tc, info.cfg, nA);
        if D.is_rule, verifyEmpty(tc, info.qv); else, verifyNumElements(tc, info.qv, nA); end
    end
end
clear back
end

function test_headless_without_three_state_model(tc)
% A bundle without the model: the cycle runs, the state is empty (the console shows none).
fx = need_fixture(tc);
c0 = cd(fx.bundle); back = onCleanup(@() cd(c0));
rng(11);
env = headless_env(); [frames, ~] = synthetic_frames(fx, env, 3, 3);
ctx = env_ctx(env, 'rule_esc', true, false);
E = [];
for k = 1:numel(frames)
    [E, info] = episode_cycle(E, k, frames{k}, ctx);
    verifyEmpty(tc, info.state3);
end
clear back
end

function test_console_builds_hidden(tc)
% The console builds from the exported bundle on a hidden figure: the three-state panel, the
% core-rule line and the lecturer's KPI lines are there. (The live run itself needs Simulink.)
% Opt in with GUI_BUILD_FIGURE=1: it creates a (hidden) uifigure, which a batch session on a
% machine without a display may not.
assumeEqual(tc, getenv('GUI_BUILD_FIGURE'), '1', 'set GUI_BUILD_FIGURE=1 to build the console on a hidden figure');
fx = need_fixture(tc);
c0 = cd(fx.bundle); back = onCleanup(@() cd(c0));
v0 = get(groot, 'DefaultFigureVisible'); set(groot, 'DefaultFigureVisible', 'off'); vis = onCleanup(@() set(groot, 'DefaultFigureVisible', v0));
demo_gui();
fig = findall(groot, 'Type', 'figure');
fig = fig(arrayfun(@(f) isstruct(f.UserData) && isfield(f.UserData, 'env'), fig));
cl = onCleanup(@() delete(fig));
verifyNumElements(tc, fig, 1);
env = fig.UserData.env; ui = fig.UserData.ui;
verifyEqual(tc, ~isempty(env.core), fx.core);
verifyTrue(tc, isfinite(clean_ber_ref(9, 'ber_est')));
verifyTrue(tc, all(isprop(ui.stateAx, 'YTick')) && ~isempty(ui.stateLbl.Text));
verifyTrue(tc, ismember('epStateAx', fieldnames(ui)));
verifyNotEmpty(tc, ui.epPolicyDD.ItemsData);
verifyTrue(tc, ismember('all', ui.epPolicyDD.ItemsData) && ismember('core', ui.epPolicyDD.ItemsData));
if fx.core
    verifySubstring(tc, strjoin(ui.kLect.Value, ' '), 'lecturer');
end
clear cl vis back
end

%% ---------- helpers ----------
function [root, tgt] = bundle_root(tc, name)
% A minimal checkout for the exporter: the files it must find, with placeholder content.
root = fullfile(tc.TestData.tmp, [name '_root']); tgt = fullfile(tc.TestData.tmp, [name '_target']);
mkdir(fullfile(root, 'data')); mkdir(fullfile(root, 'results'));
params = struct('n_rx', 3); save(fullfile(root, 'params.mat'), 'params');
x = 1;
for f = {'trained_detector', 'trained_dqn', 'gui_norm_stats', 'ood_thresholds'}
    save(fullfile(root, 'data', [f{1} '.mat']), 'x');
end
end

function Q = trained_stub(deployed, selected)
% What the console reads of data/trained_dqn.mat: deployed, seed_summary.selected_kind and, for the
% rule fallback, its monitor and settings (train_dqn.m rule_sel).
Q = struct('deployed', deployed, 'seed_summary', struct('selected_kind', selected), ...
    'rule_sel', struct('alarm', 'drop', 'drop', 6, 'alarm_mode', 'drop', 'confirm', [3 3], 'drop_db', 6, ...
    'maha_thr', 3.25, 'unk_retain', 0.9, 'confirm_sweep', [], 'rec', 0.5, 'held', 0.4));
end

function m = rule_stub(PP)
% A fallback monitor on the bundle's own settings, the confirmation one cycle longer.
m = struct('alarm_mode', PP.alarm_mode, 'confirm', PP.confirm + [1 1]);
if isfield(PP, 'drop_db'), m.drop_db = PP.drop_db; end
end

function cr = clean_ref_table()
v = [0.1 0.02 5e-3 1e-3 1e-4];                          % 9 dB inside the range console_ref_range.m allows
cr = struct('clean_ref', struct('ebno', [0 3 6 9 12], 'ber', v, 'ber_est', v, 'plr_fec', v));
end

function export_quiet(tgt, root)
w = warning('off', 'export_gui_bundle:stale'); c = onCleanup(@() warning(w));
export_gui_bundle(tgt, root);
clear c
end

function fx = need_fixture(tc)
fx = tc.TestData.fx;
verifyEmpty(tc, tc.TestData.fx_err, ['the bundle could not be exported from the smoke tree: ' tc.TestData.fx_err]);
assumeNotEmpty(tc, fx, 'set GUI_SMOKE_TREE (and GUI_CORE_DIR) for the tests on a smoke tree');
end

function fx = smoke_fixture(sm, cm, tmp)
% A scratch copy of what the smoke tree holds that the console needs, then the bundle
% exported from it (the clean reference as a small pools file, as the exporter reads it).
R = fullfile(tmp, 'smoke_copy'); mkdir(fullfile(R, 'data')); mkdir(fullfile(R, 'results'));
copy_if(fullfile(sm, 'params.mat'), fullfile(R, 'params.mat'));
for f = {'trained_detector', 'trained_dqn', 'ood_thresholds', 'fusion', 'drop_threshold', 'survivability_boundary', 'gui_norm_stats'}
    copy_if(fullfile(sm, 'data', [f{1} '.mat']), fullfile(R, 'data', [f{1} '.mat']));
end
for f = {'eval_detector_metrics', 'eval_detector_metrics_fresh2', 'eval_detector_metrics_fresh3', 'policy_evaluation', 'latency', ...
        'kpi_summary', 'edge_map'}
    copy_if(fullfile(sm, 'results', [f{1} '.mat']), fullfile(R, 'results', [f{1} '.mat']));
end
copy_if(fullfile(sm, 'results', 'kpi_summary.txt'), fullfile(R, 'results', 'kpi_summary.txt'));
L = load(fullfile(sm, 'data', 'policy_pools.mat'), 'clean_ref'); clean_ref = L.clean_ref; %#ok<NASGU>
save(fullfile(R, 'data', 'policy_pools.mat'), 'clean_ref');
core = ~isempty(cm) && isfile(fullfile(cm, 'data', 'core_cnn_model.mat'));
if core
    copy_if(fullfile(cm, 'data', 'core_cnn_model.mat'), fullfile(R, 'data', 'core_cnn_model.mat'));
    copy_if(fullfile(cm, 'results', 'core_cnn.txt'), fullfile(R, 'results', 'core_cnn.txt'));
end
tgt = fullfile(tmp, 'profiles');
w = warning('off', 'export_gui_bundle:stale'); c = onCleanup(@() warning(w));
export_gui_bundle(tgt, R);
clear c
p = load(fullfile(R, 'params.mat')); n = p.params.n_rx;
fx = struct('root', R, 'bundle', fullfile(tgt, sprintf('rx%d', n)), 'core', core, 'cells', pool_cells(sm));
end

function K = pool_cells(sm)
% One run of the smoke tree's clean link and of a jamming cell (no_action pools of the first
% non-empty training split): the receiver measurements the decision layer reads. The pools
% hold no IQ; the test draws it (synthetic_frames).
L = load(fullfile(sm, 'data', 'policy_pools.mat'), 'PP'); PP = L.PP;
na = find(strcmp(PP.actions, 'no_action'), 1);
j = find(strcmp(PP.scen, 'jamming')); j = j(ceil(end / 2));
K = struct('clean', one_run(PP, 1, na), 'attack', one_run(PP, j, na));
end

function c = one_run(PP, is, na)
c = [];
for s = 1:size(PP.pools, 4)
    q = PP.pools{is, 1, na, s};
    if isstruct(q) && ~isempty(q.run), c = q; break; end
end
assert(~isempty(c), 'test_gui: no pool for scenario %s', PP.scen{is});
m = c.run == c.run(1);
c = struct('ber', c.ber(m), 'feat', c.feat(m, :), 'gant', c.gant(m, :), 'idle', c.idle(m, :), 'bch', c.bch(m, :), ...
    'mmse_pred', c.mmse_pred(m));
end

function copy_if(src, dst)
if isfile(src), copyfile(src, dst); end
end

function env = headless_env()
% The console's models and decision settings (demo_gui.m's start), without the figure.
D = load('data/trained_detector.mat', 'net', 'classes', 'ood');
Q = load('data/trained_dqn.mat', 'agent', 'confirm', 'alarm_mode', 'drop_db', 'maha_thr', 'dec');
N = load('data/gui_norm_stats.mat', 'feat_mean', 'feat_std');
p0 = load('params.mat').params;
env = struct('cnn_net', D.net, 'class_list', {cellstr(D.classes(:))}, 'dqn_agent', Q.agent, ...
    'feat_mean', N.feat_mean, 'feat_std', N.feat_std, 'p0', p0, 'fs', p0.symbol_rate * p0.sps);
env.action_names = env.dqn_agent.action_names;
env.na = find(strcmp(env.action_names, 'no_action'), 1);
env.ood = D.ood;
if strcmp(D.ood.score, 'last_or_if') && ~isfield(D.ood, 'forest_pack')
    env.ood.forest_pack = iforest_pack(D.ood.forest);
end
Tood = ood_thresholds(0.95);
FZ = fusion_model();
UW = 1; if isfield(D.ood, 'win'), UW = D.ood.win; end
env.PP = struct('actions', {env.action_names}, 'classes', {env.class_list(:)'}, 'sps', p0.sps, ...
    'bps', p0.bits_per_symbol, 'maha_thr', Tood.maha, 'fuse', FZ.FM, 'fuse_N', FZ.N, 'q_thr', FZ.q_thr, ...
    'unk_win', UW, 'cfg_gain_db', config_gain_db(env.action_names, p0));
env.PP = decision_settings(env.PP, Q);
env.core = console_core('load');
end

function ctx = env_ctx(env, policy, core_rule, with_core)
ctx = struct('net', env.cnn_net, 'ood', env.ood, 'feat_mean', env.feat_mean, 'feat_std', env.feat_std, ...
    'fs', env.fs, 'nv', thermal_nv(env.p0), 'agent', env.dqn_agent, 'PP', env.PP, 'na', env.na, ...
    'policy', policy, 'core_rule', core_rule, 'core', []);
if with_core, ctx.core = env.core; end
end

function [frames, truth] = synthetic_frames(fx, env, nclean, nattack)
% A stream of frames: the receiver measurements of the pools (clean link, then the jamming
% cell) with an IQ frame drawn here (the pools hold no IQ, so these are not the link's frames):
% root-raised-cosine QPSK at Eb/N0 9 dB in thermal noise, then a tone, then wideband noise.
% truth: the state of each frame (1 clean, 2 narrowband, 3 wideband).
n = 2064;                                            % samples of a frame: 516 symbols at 4 samples/symbol
nv = thermal_nv(env.p0);
h = rcosdesign(0.25, 10, 4);
Es = nv * env.p0.bits_per_symbol * 10^0.9;           % symbol energy at Eb/N0 = 9 dB (thermal_nv.m: N0 = nv)
frames = cell(1, nclean + nattack); truth = zeros(1, nclean + nattack);
for k = 1:nclean + nattack
    a = sqrt(Es / 2) * ((2 * randi(2, 516, 1) - 3) + 1i * (2 * randi(2, 516, 1) - 3));
    x = upfirdn(a, h, 4); x = x(21:20 + n);
    iq = x + sqrt(nv / 2) * (randn(n, 1) + 1i * randn(n, 1));
    st = 1; src = fx.cells.clean; j = k;
    if k > nclean
        j = k - nclean; src = fx.cells.attack;
        if j <= nattack / 2
            st = 2; iq = iq + 30 * exp(1i * 2 * pi * 0.1 * (0:n-1)');
        else
            st = 3; iq = iq + 10 * (randn(n, 1) + 1i * randn(n, 1));
        end
    end
    j = mod(j - 1, numel(src.ber)) + 1;
    frames{k} = struct('iq', iq, 'ber', src.ber(j), 'feat', src.feat(j, :), 'gant', src.gant(j, :), 'idle', src.idle(j, :), ...
        'bch', src.bch(j, :), 'mmse_pred', src.mmse_pred(j), 'pkt', floor(k / 2));
    truth(k) = st;
end
end

function s = headless_state_trace(env, frames, truth)
% The three-state reading (window of the model) at the end of each segment of the frames.
P = zeros(numel(frames), 3);
for k = 1:numel(frames)
    X = reshape(single(spec_image(frames{k}.iq, env.fs, thermal_nv(env.p0))), 128, 128, 1, 1);
    P(k, :) = spec_scores(env.core.net, X);
end
r = cell(1, 3);
for st = 1:3
    last = find(truth == st, 1, 'last');
    r{st} = console_core('read', env.core, P(1:last, :)).name;
end
s = strjoin(r, ' / ');
end
