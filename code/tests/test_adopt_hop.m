function tests = test_adopt_hop
%TEST_ADOPT_HOP  The stacked adoption (rule_fix, then dqn_hop; adopt_options.m, adopt_reading.m
%   hop_*): the hop layer reaches the deployed row only, and the readers' hooks leave every option
%   and run_cache key as they were when off; the stacked overlay links and copies as the first one,
%   stacks on a finished base overlay and refuses in its order; the guards on synthetic files.
%   Temporary folders only, no pools, no MATLAB run of a stage. Run from the repository root:
%   results = runtests('code/tests/test_adopt_hop.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.tree_rev = '978ee31';                                % profile 3's HEAD, the tree's code
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
rm_all(tc.TestData.tmp);
end

%% ---------- adopt_options.m ----------
function test_hop_row_only(tc)
A = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
verifyEqual(tc, A.names, {'rule_fix', 'dqn_hop'});
verifyError(tc, @() adopt_options('opt', A, 'dqn_g1', struct()), 'adopt_options:row');   % the deployed row first
A = adopt_options('deployed', A, 'dqn_g1');
o = adopt_options('opt', A, 'dqn_g1', struct());
verifyEqual(tc, o, struct('monitor', struct('dqn_hop', 'rule')));
o = adopt_options('opt', A, 'dqn_g1', struct('monitor', struct('lb_complete', true)));
verifyEqual(tc, o.monitor, struct('lb_complete', true, 'dqn_hop', 'rule'));
for n = {'dqn_g2', 'dqn_esc', 'dqn_g1_relm', 'dqn_g1_norelm', 'none', 'oracle', 'table', 'fixed'}
    verifyEqual(tc, adopt_options('opt', A, n{1}, struct('k', 1)), struct('k', 1), n{1});   % not the deployed row
end
o = adopt_options('opt', A, 'rule_esc', struct());
verifyEqual(tc, o.monitor, struct('rule_fix', 'keep+st+rate'));    % the rule rows: the rule fix alone
verifyTrue(tc, contains(adopt_options('note', A), 'dqn_g1') && contains(adopt_options('note', A), 'dqn_hop=rule') ...
    && contains(adopt_options('note', A), 'keep+st+rate'));
end

function test_dqn_call_and_key(tc)
A = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule')));
o = adopt_options('dqn', A, struct('monitor', struct('lb_complete', true)));
verifyEqual(tc, o.monitor, struct('lb_complete', true, 'dqn_hop', 'rule'));
verifyEqual(tc, adopt_options('key', A), {'dqn_hop=rule'});
verifyTrue(tc, contains(adopt_options('note', A, 'dqn'), 'hybrid'));
R = adopt_options(struct('adopt', struct('rule_fix', 'keep+st+rate')));          % the rule fix alone
verifyEqual(tc, adopt_options('dqn', R, struct('x', 1)), struct('x', 1));
verifyEqual(tc, adopt_options('key', R), {});
verifyEqual(tc, adopt_options('note', R, 'dqn'), '');
for c = {[], struct(), struct('adopt', struct('dqn_hop', '')), struct('adopt', struct('dqn_hop', ""))}
    Z = adopt_options(c{1});
    verifyFalse(tc, Z.on);
    verifyEqual(tc, adopt_options('dqn', Z, struct('monitor', struct('lb_complete', true))), ...
        struct('monitor', struct('lb_complete', true)));
    verifyEqual(tc, adopt_options('key', Z), {});
    verifyEqual(tc, adopt_options('opt', Z, 'dqn_g1', struct()), struct());
end
verifyError(tc, @() adopt_options(struct('adopt', struct('dqn_hop', struct('on', true)))), 'adopt_options:value');
end

function test_the_layer_reads_the_option(tc)
% opt.monitor reaches PP through decision_settings.m, and policy_decide.m reads PP.dqn_hop.
A = adopt_options('deployed', adopt_options(struct('adopt', struct('dqn_hop', 'rule'))), 'dqn_g1');
o = adopt_options('opt', A, 'dqn_g1', struct());
PP = decision_settings(struct('confirm', [2 3]), o.monitor);
verifyEqual(tc, PP.dqn_hop, 'rule');
pd = strrep(fileread(which('policy_decide')), char(13), '');
verifyNotEmpty(tc, strfind(pd, 'if isfield(opt, ''monitor''), PP = decision_settings(PP, opt.monitor); end'));
verifyNotEmpty(tc, strfind(pd, 'dp = dqn_fix(''parse'', ''dqn_hop'', PP.dqn_hop)'));
w = strrep(fileread(which('weak19_reading')), char(13), '');   % the test read set it the same way
verifyNotEmpty(tc, strfind(w, 'opt1 = opt0; for f = fieldnames(Sa)'', opt1.monitor.(f{1}) = Sa.(f{1}); end'));
end

%% ---------- the readers off = the parent ----------
function test_hooks_off_are_the_parent(tc)
% Each reader is the tree's file but for added lines that all name the adoption; off, each hook
% returns its input (test_dqn_call_and_key), and the run_cache keys gain nothing.
H = {'code/decision/evaluate_policies.m', 1; 'code/decision/experiment_combo_generalization.m', 5; ...
    'code/decision/experiment_unknown_threat.m', 5; 'code/evaluation/edge_map.m', 6; 'code/evaluation/measure_latency.m', 4};
for k = 1:size(H, 1)
    [missing, added] = line_diff(tc, tc.TestData.tree_rev, H{k, 1});
    if k == 1, added = added(~contains(added, 'adopt_options(''opt''') & ~contains(added, 'ADP = adopt_options(cfg6)') & ...
            ~contains(added, 'FRESH && ADP.on') & ~contains(added, 'adopt_options(''note'', ADP)')); end   % the rule fix's hooks
    verifyEqual(tc, missing, {}, H{k, 1});
    verifyNumElements(tc, added, H{k, 2}, H{k, 1});
    verifyTrue(tc, all(contains(added, 'adopt') | contains(added, 'ADP') | contains(added, 'cfge') | contains(added, 'cfgl')), H{k, 1});
end
for f = {'experiment_combo_generalization', 'experiment_unknown_threat'}
    s = strrep(fileread(which(f{1})), char(13), '');
    verifyNotEmpty(tc, strfind(s, 'lbkey = [lbkey, adopt_options(''key'', ADP)];'), f{1});   % {} off: the key is the parent's
    verifyNotEmpty(tc, regexp(s, 'opt1 = struct\(''monitor'', struct\(''lb_complete'', true\)\);\s*\n\s*if isfield\(Q, ''adopt''\), opt1 = adopt_options\(''dqn'', Q.adopt, opt1\); end', 'once'), f{1});
    verifyNumElements(tc, strfind(s, 'Q.adopt'), 2, f{1});        % the hybrid columns only
    verifyNumElements(tc, strfind(s, 'if ADP.on, Q.adopt = ADP; end'), 1, f{1});
end
e = strrep(fileread(which('edge_map')), char(13), '');
verifyNumElements(tc, strfind(e, 'if strcmp(POL{pk}, dep), opt = adopt_options(''dqn'', ADP, opt); end'), 2);
verifyNumElements(tc, strfind(e, 'opt = adopt_options(''dqn'', ADP, opt);'), 3);
l = strrep(fileread(which('measure_latency')), char(13), '');
verifyNotEmpty(tc, regexp(l, 'policy_setup\(dep, Q, sel, \[\], \[\], \[\], na\);[^\n]*\n[^\n]*\n[^\n]*\noptP = adopt_options\(''dqn'', ADP, optP\);', 'once'));
p = strrep(fileread(which('evaluate_policies')), char(13), '');
verifyNotEmpty(tc, regexp(p, 'iDQN = find\(strcmp\(POL, dep\)\);[^\n]*\nif ADP.on, ADP = adopt_options\(''deployed'', ADP, POL\{iDQN\}\); end', 'once'));
end

function test_may_differ_is_the_code_diff(tc)
% The stacked overlay's code check lists exactly what this checkout changes against the tree's code.
K = adopt_reading('hop_reg');
[st, out] = system(sprintf('git --no-optional-locks -C "%s" diff --name-only %s -- code', tc.TestData.root, tc.TestData.tree_rev));
assertEqual(tc, st, 0, out);
f = strsplit(strtrim(strrep(out, char(13), '')), newline);
f = f(endsWith(f, '.m') & ~startsWith(f, 'code/tests/'));
f = erase(f, 'code/');
verifyEqual(tc, setdiff(f, K.may_differ), cell(1, 0));
verifyEmpty(tc, setdiff(K.may_differ, [f, {'evaluation/calibration_reading.m'}]));   % no stale entry
end

function test_registered_outputs(tc)
% The stage's file sets match the code that writes them.
K = adopt_reading('hop_reg');
src = @(n) strrep(fileread(which(n)), char(13), '');
e = [src('edge_map'), src('link_budget_table')];
for f = K.edge_out
    [~, nm, x] = fileparts(f{1});
    verifyTrue(tc, contains(e, f{1}) || (startsWith(nm, 'edge_heatmap_') && contains(e, erase(nm, 'edge_heatmap_')) && ...
        contains(e, 'results/edge_heatmap_%s.png')), f{1});
    verifyTrue(tc, ismember(x, {'.txt', '.mat', '.png'}));
end
verifyNumElements(tc, K.edge_out(startsWith(K.edge_out, 'results/edge_heatmap_')), 6);
c = [src('experiment_combo_generalization'), src('experiment_unknown_threat')];
for f = K.c2gu_out, verifyTrue(tc, contains(c, f{1}), f{1}); end
verifyTrue(tc, contains(src('measure_latency'), 'out_dir = ''results''; out_name = ''latency'';'));
verifyEqual(tc, K.stages, {'overlay', 'off', 'c2e', 'gate', 'c2gu', 'edge', 'lat', 'render'});
verifyEqual(tc, K.threads, 8);
p = src('evaluate_policies');                                     % the replayed draws are C2e's
for t = {'rs = RandStream(''mt19937ar'', ''Seed'', 2027);', '20000 + 1000*si);', ...
        'RandStream(''mt19937ar'', ''Seed'', 2075));', 'RS2 = policy_run_set(kind, PP, K, spec2, TEST2, ag, opt, 50000);', ...
        'cm = policy_episodes(jam, nS, G(jam, TEST), 1, true, false, NE, T, rs, [0 0]);'}
    verifyNotEmpty(tc, strfind(p, t{1}), t{1});
end
verifyEqual(tc, K.replay, {'single', 'follower', 'combined', 'unknown', 'clean', 'comb'});
a = src('adopt_reading');
verifyFalse(tc, contains(a, 'D124') || contains(a, 'D125'));
end

%% ---------- overlay ----------
function test_overlay_stacks(tc)
W = world(tc);
s0 = tree_state(W.tree);
b0 = tree_state(W.base);
M = adopt_reading('hop_overlay', W.tag, W.tree, W.O);
X = adopt_reading('hop_paths', W.tag, W.O);
verifyEqual(tc, X.dir, fullfile(canon(W.co), 'results', 'dqn_hop', W.tag, 'adopted'));
verifyEqual(tc, M.version, 2);
verifyEqual(tc, {M.adoptions.name}, {'rule_fix', 'dqn_hop'});
verifyEqual(tc, {M.adoptions.setting}, {'keep+st+rate', 'rule'});
verifyEqual(tc, M.adoptions(2).test_sha256, adopt_reading('sha', fullfile(W.w19, 'test.mat')));
verifyEqual(tc, M.base.pe_sha256, adopt_reading('sha', fullfile(W.base, 'on', 'results', 'policy_evaluation.mat')));
verifyEqual(tc, M.order(:)', {'overlay', 'off', 'c2e', 'gate', 'c2gu', 'edge', 'lat', 'render'});
C = adopt_reading('cfg', M);
verifyEqual(tc, C.adopt, struct('rule_fix', 'keep+st+rate', 'dqn_hop', 'rule'));
% off holds every registered file; on leaves out what its stages write, the agents' file included
for f = {'results/combo_generalization.mat', 'results/edge_map.mat', 'results/latency.mat', 'results/policy_evaluation.mat', 'results/a.txt'}
    verifyTrue(tc, isfile(fullfile(X.off, f{1})), ['off ' f{1}]);
end
for f = {'results/combo_generalization.mat', 'results/edge_map.mat', 'results/latency.mat', 'results/policy_evaluation.mat', ...
        'results/link_budget.mat', 'results/unknown_threat_policy.mat'}
    verifyFalse(tc, isfile(fullfile(X.on, f{1})), ['on ' f{1}]);
end
verifyTrue(tc, isfile(fullfile(X.on, 'results', 'a.txt')));
for r = {X.off, X.on}                                             % every data file linked, the kept agents included
    for f = {'trained_dqn.mat', 'unknown_threat_agents.mat'}
        verifyTrue(tc, java.nio.file.Files.isSameFile(jp(fullfile(r{1}, 'data', f{1})), jp(fullfile(W.tree, 'data', f{1}))), f{1});
    end
end
verifyFalse(tc, java.io.File(fullfile(W.tree, 'data', 'trained_dqn.mat')).canWrite());
verifyTrue(tc, contains(fileread(X.ovt), 'read-only'));
verifyEqual(tc, tree_state(W.tree), s0);
verifyEqual(tc, tree_state(W.base), b0);                         % the base overlay is read only
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:exists');
end

function test_overlay_refusals(tc)
W = world(tc); delete(fullfile(W.base, 'render.json'));          % the base not finished
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:base');
W = world(tc); pe = fullfile(W.base, 'on', 'results', 'policy_evaluation.mat'); x = 3; save(pe, 'x'); %#ok<NASGU>
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:base');   % moved after its c2e
W = world(tc); write_hop_sel(W, struct('tree', 'c:\another\tree'));
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:selection');
W = world(tc); write_hop_sel(W, struct('adopted', struct('dqn_hop', 'rule', 'dqn_harm', 'q')));
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:selection');   % only dqn_hop here
W = world(tc); write_hop_sel(W, struct('rf', 'keep+st'));
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:selection');   % another rule-fix setting
W = world(tc); write_hop_sel(W, struct('deployed', 'rule_sel'));
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:selection');
W = world(tc); delete(fullfile(W.w19, 'test.mat'));
verifyError(tc, @() adopt_reading('hop_overlay', W.tag, W.tree, W.O), 'adopt_reading:sources');
verifyFalse(tc, isfolder(adopt_reading('hop_paths', W.tag, W.O).dir));
end

function test_stage_order(tc)
W = world(tc);
for s = {'hop_off', 'hop_c2e', 'hop_gate', 'hop_c2gu', 'hop_edge', 'hop_lat', 'hop_render', 'hop_release'}
    verifyError(tc, @() adopt_reading(s{1}, W.tag, W.tree, W.O), 'adopt_reading:no_overlay', s{1});
end
adopt_reading('hop_overlay', W.tag, W.tree, W.O);
X = adopt_reading('hop_paths', W.tag, W.O);
s0 = tree_state(W.tree);
st = {'hop_c2e', 'off'; 'hop_gate', 'c2e'; 'hop_c2gu', 'gate'; 'hop_edge', 'c2gu'; 'hop_lat', 'edge'; 'hop_render', 'lat'};
for k = 1:size(st, 1)
    verifyError(tc, @() adopt_reading(st{k, 1}, W.tag, W.tree, W.O), 'adopt_reading:order', st{k, 1});
end
n0 = maxNumCompThreads; cl = onCleanup(@() maxNumCompThreads(n0)); %#ok<NASGU>
maxNumCompThreads(1);
verifyError(tc, @() adopt_reading('hop_off', W.tag, W.tree, W.O), 'adopt_reading:threads');
adopt_reading('write_once', X.v.off, {jsonencode(struct('stage', 'off', 'pass', true))});
verifyError(tc, @() adopt_reading('hop_c2e', W.tag, W.tree, W.O), 'adopt_reading:threads');
% the hop reading moved after the overlay: every stage refuses
add_line(fullfile(W.w19, 'selection.json'));
verifyError(tc, @() adopt_reading('hop_c2e', W.tag, W.tree, W.O), 'adopt_reading:sources');
verifyFalse(tc, isfile(X.v.c2e)); verifyFalse(tc, isfolder(X.logs));
verifyEqual(tc, tree_state(W.tree), s0);
end

function test_gate(tc)
W = world(tc);
adopt_reading('hop_overlay', W.tag, W.tree, W.O);
X = adopt_reading('hop_paths', W.tag, W.O);
write_rec(X, 'c2e', 'results/policy_evaluation.mat');
V = adopt_reading('hop_gate', W.tag, W.tree, W.O);
verifyTrue(tc, V.pass, strjoin({V.rows(~[V.rows.ok]).why}, ' | '));
verifyEqual(tc, V.deployed, 'dqn');
verifyError(tc, @() adopt_reading('hop_gate', W.tag, W.tree, W.O), 'adopt_reading:exists');
n0 = maxNumCompThreads; cl = onCleanup(@() maxNumCompThreads(n0)); %#ok<NASGU>
maxNumCompThreads(1);
verifyError(tc, @() adopt_reading('hop_c2gu', W.tag, W.tree, W.O), 'adopt_reading:threads');   % past the order, at 8 threads only
% not confirmed on the fresh set: the gate stops
W2 = world(tc, false);
adopt_reading('hop_overlay', W2.tag, W2.tree, W2.O);
X2 = adopt_reading('hop_paths', W2.tag, W2.O);
write_rec(X2, 'c2e', 'results/policy_evaluation.mat');
verifyError(tc, @() adopt_reading('hop_gate', W2.tag, W2.tree, W2.O), 'adopt_reading:gate');
G = jsondecode(fileread(X2.v.gate));
verifyFalse(tc, G.pass);
verifyError(tc, @() adopt_reading('hop_c2gu', W2.tag, W2.tree, W2.O), 'adopt_reading:order');
% the c2e outputs changed after it: refused
W3 = world(tc);
adopt_reading('hop_overlay', W3.tag, W3.tree, W3.O);
X3 = adopt_reading('hop_paths', W3.tag, W3.O);
write_rec(X3, 'c2e', 'results/policy_evaluation.mat');
x = 5; save(fullfile(X3.on, 'results', 'policy_evaluation.mat'), 'x'); %#ok<NASGU>
verifyError(tc, @() adopt_reading('hop_gate', W3.tag, W3.tree, W3.O), 'adopt_reading:outputs');
% the tree's frozen copy missing
W4 = world(tc); delete(fullfile(W4.tree, 'results', 'read_once', 'weak19_selection.json'));
adopt_reading('hop_overlay', W4.tag, W4.tree, W4.O);
X4 = adopt_reading('hop_paths', W4.tag, W4.O);
write_rec(X4, 'c2e', 'results/policy_evaluation.mat');
verifyError(tc, @() adopt_reading('hop_gate', W4.tag, W4.tree, W4.O), 'adopt_reading:gate');
end

function test_confirmed(tc)
T.verdict = struct('step', {{'dqn_hop'}}, 'confirmed', true);
verifyTrue(tc, adopt_reading('confirmed', T, 'dqn_hop').ok);
T.verdict.confirmed = false;
verifyFalse(tc, adopt_reading('confirmed', T, 'dqn_hop').ok);
T.verdict = struct('step', {{'dqn_harm', 'dqn_hop'}}, 'confirmed', [false true]);
verifyTrue(tc, adopt_reading('confirmed', T, 'dqn_hop').ok);
verifyFalse(tc, adopt_reading('confirmed', T, 'lb_more').ok);
verifyFalse(tc, adopt_reading('confirmed', struct(), 'dqn_hop').ok);
end

function test_release(tc)
% The release gives back what this overlay took, and with release_base what the base overlay took.
W = world(tc);
fb = fullfile(W.tree, 'data', 'big.mat');
fileattrib(fb, '-w');                                            % read-only since the base overlay
M = adopt_reading('hop_overlay', W.tag, W.tree, W.O);
X = adopt_reading('hop_paths', W.tag, W.O);
verifyEqual(tc, sort(reshape(cellstr(M.readonly_before), 1, [])), {'data/big.mat', 'data/ro.mat'});
s0 = tree_state(W.tree);
V = adopt_reading('hop_release', W.tag, W.tree, W.O);
verifyTrue(tc, V.pass);
verifyTrue(tc, java.io.File(fullfile(W.tree, 'data', 'trained_dqn.mat')).canWrite());
verifyFalse(tc, java.io.File(fb).canWrite());                    % the base's: kept
verifyEqual(tc, tree_state(W.tree), s0);
for s = {'hop_off', 'hop_c2e', 'hop_render', 'hop_release'}
    verifyError(tc, @() adopt_reading(s{1}, W.tag, W.tree, W.O), 'adopt_reading:released', s{1});
end
W2 = world(tc);
fileattrib(fullfile(W2.tree, 'data', 'big.mat'), '-w');
adopt_reading('hop_overlay', W2.tag, W2.tree, W2.O);
add_line(fullfile(W2.w19, 'selection.json'));                    % the release checks no pin
O = W2.O; O.release_base = true;
V = adopt_reading('hop_release', W2.tag, W2.tree, O);
verifyTrue(tc, V.pass); verifyTrue(tc, V.base_released);
verifyTrue(tc, java.io.File(fullfile(W2.tree, 'data', 'big.mat')).canWrite());   % writable before the base overlay
verifyFalse(tc, java.io.File(fullfile(W2.tree, 'data', 'ro.mat')).canWrite());   % read-only before both
end

function test_run_in(tc)
% A script runs in the root with CFG in its workspace, and the folder comes back.
d = tempname(tc.TestData.tmp); mkdir(d); s = tempname(tc.TestData.tmp); mkdir(s);
write_text(fullfile(s, 'hop_probe_script.m'), sprintf(['fid = fopen(''probe.txt'', ''w''); fprintf(fid, ''%%s'', CFG.adopt.dqn_hop); fclose(fid);\n' ...
    'back = 1; c0 = 2;\n']));
addpath(s); cl = onCleanup(@() rmpath(s)); %#ok<NASGU>
c0 = pwd;
R = adopt_reading('run_in', d, 'hop_probe_script', struct('adopt', struct('dqn_hop', 'rule')), {'back', 'none_such'});
verifyEqual(tc, R.err, '');
verifyEqual(tc, R.W, struct('back', 1));                         % the variables kept that the script left
verifyEqual(tc, pwd, c0);
verifyEqual(tc, fileread(fullfile(d, 'probe.txt')), 'rule');
write_text(fullfile(s, 'hop_fail_script.m'), 'error(''probe:x'', ''stopped'');');
verifyEqual(tc, adopt_reading('run_in', d, 'hop_fail_script', struct()).err, 'stopped');
verifyEqual(tc, pwd, c0);
end

function test_failed_attempt_kept_apart(tc)
% c2gu, edge and lat: a failed attempt is kept under its own name and the stage may run again.
W = world(tc);
adopt_reading('hop_overlay', W.tag, W.tree, W.O);
X = adopt_reading('hop_paths', W.tag, W.O);
bad = struct('file', 'x', 'ok', false, 'why', 'stopped');
verifyError(tc, @() adopt_reading('verdict_try', X, 'c2gu', bad, struct()), 'adopt_reading:c2gu');
verifyFalse(tc, isfile(X.v.c2gu));
verifyNotEmpty(tc, dir(fullfile(X.dir, 'c2gu_failed_*.json')));
verifyNotEmpty(tc, dir(fullfile(X.dir, 'c2gu_failed_*.txt')));
V = adopt_reading('verdict_try', X, 'c2gu', struct('file', 'x', 'ok', true, 'why', 'read'), struct());
verifyTrue(tc, V.pass && isfile(X.v.c2gu));
end

%% ---------- guards ----------
function test_guard_hop(tc)
[N, E, D] = hop_world();
G = adopt_reading('guard_hop', N, E, D);
verifyTrue(tc, G.pass, strjoin(arrayfun(@(r) [r.file ': ' r.why], G.rows(~[G.rows.ok]), 'UniformOutput', false), ' | '));
P = N; P.RES{2, 1}.recovered(1) = ~P.RES{2, 1}.recovered(1);    % no response moved
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; P.RES{3, 3} = E.RES{3, 3};                                % a rule row not the base's
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; P.RES{6, 2} = E.RES{6, 2};                                % on every set, the sixth included
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; P.RW{2} = E.RW{2};
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; P.ALL{5}.ret(1) = 7;                                      % dqn_esc pooled
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; P.LBC.sets(1).on = 0.1;
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'other columns'));
P = N; for si = 1:6, P.RES{si, 4} = E.RES{si, 4}; end          % the deployed row as registered: not applied
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'setting applied'));
P = N; P.RES{1, 4}.held(3) = ~P.RES{1, 4}.held(3);              % the deployed row: no reference
verifyTrue(tc, adopt_reading('guard_hop', P, E, D).pass);
P = N; P.RS2.ret(1) = 5;
verifyTrue(tc, adopt_reading('guard_hop', P, E, D).pass);
P = rmfield(N, 'RS2');
verifyFalse(tc, adopt_reading('guard_hop', P, E, D).pass);
P = N; P.KP.per_threat(1, 3) = 0;                                % the deployed column of KP
verifyTrue(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'KP'));
P = N; P.KP.per_threat(1, 2) = 0;                                % rule + escalation's: the base's
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'KP'));
P = N; P.KP.far(3).k = 9;
verifyTrue(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'KP'));
P = N; P.KP.far(1).k = 9;
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'KP'));
P = N; P.KP.envelope_val(1) = 1;                                 % the deployed policy's own reading
G = adopt_reading('guard_hop', P, E, D);
verifyTrue(tc, row_ok(G, 'KP'));
verifyTrue(tc, contains(G.rows(strcmp({G.rows.file}, 'KP')).why, 'envelope_val'));
P = N; P.KP.extra = 1;
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'KP'));
P = N; P.LBL{1} = 'x';
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'LBL'));
P = N; P.top_cfg.share = 0.3;                                   % the deployed row's final configurations
G = adopt_reading('guard_hop', P, E, D);
verifyTrue(tc, G.pass);
verifyTrue(tc, contains(G.rows(strcmp({G.rows.file}, 'top_cfg')).why, 'jamming no_action 25.0% -> no_action 30.0%'));
P = N; P.top_cfg.threat = 'spoofing';
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D), 'top_cfg'));
D3 = D; D3.top_cfg.share = 0.3; P = N; P.top_cfg = D3.top_cfg;  % the base's not as registered
verifyFalse(tc, row_ok(adopt_reading('guard_hop', P, E, D3), 'top_cfg'));
D2 = D; D2.POL{1} = 'x';                                         % a base of another layout
verifyFalse(tc, row_ok(adopt_reading('guard_hop', N, E, D2), 'POL'));
end

function test_hybrid_rows(tc)
mk = @(c, v) struct('combo', c, 'n', 10, 'dqn_out', 0.5, 'dqn_in', 0.9, 'rule', 0.8, 'table', 0.7, 'ci_out', [0.4 0.6], ...
    'ci_in', [0.8 1], 'dqn_out_lb', v, 'dqn_in_lb', v + 0.1, 'ci_out_lb', [0 1], 'ci_in_lb', [0 1]);
r0 = [mk('jamming+path_loss', 0.6), mk('spoofing+noise_burst', 0.7)];
rr = {'dqn_in_lb', 'ci_in_lb'};
g = rmfield(r0, {'dqn_out', 'ci_out', 'dqn_out_lb', 'ci_out_lb'});   % C2g's reading: the deployed agent only
g(1).dqn_in_lb = 0.95;
H = adopt_reading('hybrid_rows', 'C2g', g, r0, 'combo', rr); R = H.rows; mv = H.moved;
verifyTrue(tc, all([R.ok])); verifyEqual(tc, mv, 1);
verifyTrue(tc, contains(R(3).why, 'jamming+path_loss') && ~contains(R(3).why, 'spoofing'));
verifyTrue(tc, contains(R(1).why, 'table') && ~contains(R(1).why, 'dqn_out'));
h = g; h(2).dqn_in = 0.1;                                        % a column read again without the layer moved
R = adopt_reading('hybrid_rows', 'C2g', h, r0, 'combo', rr).rows;
verifyFalse(tc, R(2).ok);
verifyFalse(tc, all([adopt_reading('hybrid_rows', 'C2g', g(1), r0, 'combo', rr).rows.ok]));
s0 = rmfield(r0, {'dqn_out_lb', 'dqn_in_lb', 'ci_out_lb', 'ci_in_lb'});   % no hybrid columns registered
verifyFalse(tc, all([adopt_reading('hybrid_rows', 'C2g', s0, s0, 'combo', rr).rows.ok]));
H = adopt_reading('hybrid_rows', 'C2u', r0, r0, 'combo', {'dqn_out_lb', 'dqn_in_lb', 'ci_out_lb', 'ci_in_lb'}); R = H.rows; mv = H.moved;
verifyTrue(tc, all([R.ok])); verifyEqual(tc, mv, 0);              % nothing moved: the stage's setting row fails
end

function test_edge_rows(tc)
% The deployed policy's variant columns may move (and must); every other column and field is the registered one.
VAR = struct('kind', {'single', 'single', 'clean'}, 'fd', {NaN, NaN, NaN}, 'D', {1, 1, 1}, 'pol', {1, 2, 1});
T = @(k) struct('c', (1:4)', 's', [1 1 2 2]', 'det_k', [1 0 1 1]', 'ep_n', k + [1 2 3; 4 5 6; 7 8 9; 1 1 1], ...
    'held_k', [1 1 1; 0 1 0; 1 0 1; 1 1 1], 'fa_k', zeros(4, 3), 'fa_n', ones(4, 3), 'sw_k', zeros(4, 3), ...
    'rec_k', ones(4, 3), 'lt_k', zeros(4, 3), 'lt_n', ones(4, 3));
E = struct('VAR', VAR, 'FT', T(0), 'CF', T(0), 'CS', T(0));
N = E; N.FT.held_k(2, 1) = 1; N.CF.fa_k(1, 3) = 1;              % the deployed policy's columns
r = adopt_reading('edge_rows', N, E);
verifyTrue(tc, all([r.ok]), strjoin({r(~[r.ok]).why}, ' | '));
verifyTrue(tc, contains(r(end).why, '2 values'));
P = N; P.FT.held_k(2, 2) = 9;                                    % another policy's column
verifyFalse(tc, all([adopt_reading('edge_rows', P, E).ok]));
P = N; P.CS.det_k(1) = 0;                                        % a policy-free field
verifyFalse(tc, all([adopt_reading('edge_rows', P, E).ok]));
P = N; P.VAR(2).pol = 3;
verifyFalse(tc, all([adopt_reading('edge_rows', P, E).ok]));
r = adopt_reading('edge_rows', E, E);                             % nothing moved
verifyFalse(tc, r(end).ok); verifyTrue(tc, all([r(1:end-1).ok]));
end

function test_replica_mirrors_the_experiments(tc)
% The c2gu reading flies the experiments' episodes, draws, options and bootstrap seeds.
a = strrep(fileread(which('adopt_reading')), char(13), '');
g = strrep(fileread(which('experiment_combo_generalization')), char(13), '');
u = strrep(fileread(which('experiment_unknown_threat')), char(13), '');
verifyNotEmpty(tc, strfind(g, 'RandStream(''mt19937ar'', ''Seed'', 300 + ci)'));
verifyNotEmpty(tc, strfind(a, 'RandStream(''mt19937ar'', ''Seed'', 300 + ci), false)'));
verifyNotEmpty(tc, strfind(u, 'RandStream(''mt19937ar'', ''Seed'', 500 + 100 * sp + ti)'));
verifyNotEmpty(tc, strfind(a, 'RandStream(''mt19937ar'', ''Seed'', 500 + 100 * sp + ti), true)'));
verifyNotEmpty(tc, strfind(g, '''unk'', false(1, NE)')); verifyNotEmpty(tc, strfind(u, '''unk'', true(1, NE)'));
for t = {'specs{b} = struct(''scn'', cc(i), ''s'', s(i), ''r'', r(i), ''onset'', randi(rs, [3 10], 1, NE), ...', ...
        '[cc, s, r] = flight_triples(c(:)'', rr, 1:nS);', 'k_ = mod(0:n + pad - 1, n) + 1; cc = cc(k_); s = s(k_); r = r(k_);', ...
        'R.threat = R.threat(1:n) & ~strcmp(PP.scen(specs{1}.scn(1)), ''none'');', ...
        'if LBC, opt0 = struct(''monitor'', struct(''lb_complete'', false)); end', 'o.agent = dqn_dense(ag);', ...
        'threats = setdiff(PP.singles, {''none''}, ''stable'');'}
    verifyTrue(tc, contains(g, t{1}) || contains(u, t{1}), t{1});
end
for k = 1:4
    verifyNotEmpty(tc, strfind(u, sprintf('2000, %d);', k))); verifyNotEmpty(tc, strfind(a, sprintf('2000, %d);', k)));
end
verifyNotEmpty(tc, strfind(a, 'if isfield(ag, ''dense''), ag = rmfield(ag, ''dense''); end'));
verifyNotEmpty(tc, strfind(fileread(which('dqn_dense')), 'agent.dense = struct('));   % the matrix form is a field beside the network
end

%% ---------- helpers ----------
function W = world(tc, conf)
% A finished tree, a finished base overlay with its frozen reading, the hop reading and a
% checkout, in a fresh temporary folder.
if nargin < 2, conf = true; end
w = tempname(tc.TestData.tmp); mkdir(w);
W.tag = 'tt'; W.tree = fullfile(w, 'tree'); W.co = fullfile(w, 'co'); W.base = fullfile(w, 'base', 'adopted');
W.rf = fullfile(w, 'base', 'rf'); W.w19 = fullfile(W.co, 'results', 'weak19', W.tag);
W.O = struct('root', W.co, 'base', W.base);
t = W.tree;
write_text(fullfile(t, 'results', 'a.txt'), sprintf('a\n'));
for f = {'combo_generalization', 'edge_map', 'latency', 'policy_evaluation', 'link_budget', 'unknown_threat_policy'}
    x = 1; save(fullfile(t, 'results', [f{1} '.mat']), 'x');
end
write_text(fullfile(t, 'results', 'kpi_summary.txt'), sprintf('k\n'));
params = struct('n_rx', 4); save(fullfile(t, 'params.mat'), 'params');
write_text(fullfile(t, 'profile.json'), '{"n_rx":4}');
mkdir(fullfile(t, 'data'));
deployed = 'dqn'; save(fullfile(t, 'data', 'trained_dqn.mat'), 'deployed');
big = rand(20); save(fullfile(t, 'data', 'big.mat'), 'big');
save(fullfile(t, 'data', 'unknown_threat_agents.mat'), 'big');
save(fullfile(t, 'data', 'ro.mat'), 'big'); fileattrib(fullfile(t, 'data', 'ro.mat'), '-w');
tr = lower(canon(t));
% the base overlay: finished, ro.mat read-only before it, big.mat writable before it
mkdir(W.rf);
write_text(fullfile(W.rf, 'selection.json'), jsonencode(struct('tag', W.tag, 'adopted', 'keep+st+rate')));
Vs = 1; save(fullfile(W.rf, 'val.mat'), 'Vs'); pols = {'rule'}; save(fullfile(W.rf, 'test.mat'), 'pols');
sh = @(f) adopt_reading('sha', f);
txt = @(f) text_sha(f);
A = struct('name', 'rule_fix', 'setting', 'keep+st+rate', 'selection_sha256', txt(fullfile(W.rf, 'selection.json')), ...
    'val_sha256', sh(fullfile(W.rf, 'val.mat')), 'test_sha256', sh(fullfile(W.rf, 'test.mat')), 'source', W.rf);
B = struct('tag', W.tag, 'tree', canon(t), 'adoptions', A, 'data_links', {{'data/big.mat', 'data/ro.mat', 'data/trained_dqn.mat', ...
    'data/unknown_threat_agents.mat'}}, 'readonly_before', {{'data/ro.mat'}});
write_text(fullfile(W.base, 'adoption.json'), jsonencode(B));
pe = fullfile(W.base, 'on', 'results', 'policy_evaluation.mat'); mkdir(fileparts(pe)); x = 2; save(pe, 'x');
write_text(fullfile(W.base, 'c2e.json'), jsonencode(struct('stage', 'c2e', 'pass', true, ...
    'outputs', struct('file', 'results/policy_evaluation.mat', 'sha256', sh(pe)))));
write_text(fullfile(W.base, 'gate.json'), jsonencode(struct('stage', 'gate', 'pass', true, 'deployed', 'dqn')));
write_text(fullfile(W.base, 'render.json'), jsonencode(struct('stage', 'render', 'pass', true)));
% the hop reading: frozen on this tree, confirmed (or not) on its fresh set; the tree's copy
write_hop_sel(W, struct('tree', tr));
verdict = struct('step', {{'dqn_hop'}}, 'confirmed', conf); save(fullfile(W.w19, 'test.mat'), 'verdict');
cp = fullfile(t, 'results', 'read_once', 'weak19_selection.json'); mkdir(fileparts(cp));
copyfile(fullfile(W.w19, 'selection.json'), cp);
end

function write_hop_sel(W, o)
tr = lower(canon(W.tree)); ad = struct('dqn_hop', 'rule'); rf = 'keep+st+rate'; dp = 'dqn';
if isfield(o, 'tree'), tr = o.tree; end
if isfield(o, 'adopted'), ad = o.adopted; end
if isfield(o, 'rf'), rf = o.rf; end
if isfield(o, 'deployed'), dp = o.deployed; end
S = struct('tag', W.tag, 'tree', tr, 'adopted', ad, 'adopted_txt', 'dqn_hop=rule', 'fingerprint', struct('tree', tr, 'code', 'c'), ...
    'deployed', dp, 'd124', struct('adopted', rf, 'file', 'x'));
f = fullfile(W.w19, 'selection.json');
if isfile(f), delete(f); end
write_text(f, jsonencode(S, 'PrettyPrint', true));
end

function write_rec(X, stage, file)
% A passed verdict of stage recording the SHA-256 of a file it wrote in the on root.
p = fullfile(X.on, file); if ~isfolder(fileparts(p)), mkdir(fileparts(p)); end
x = 1; save(p, 'x'); %#ok<NASGU>
H = struct('file', file, 'sha256', adopt_reading('sha', p));
adopt_reading('write_once', X.v.(stage), {jsonencode(struct('stage', stage, 'pass', true, 'outputs', H))});
end

function [N, E, D] = hop_world()
% The registered file E, the base overlay's D (rule rows moved) and the stacked N (D with the
% deployed row moved) that passes every guard.
POL = {'none', 'rule', 'rule_esc', 'dqn_g1', 'dqn_esc', 'rule_core'};
mk = @(v) struct('scn', 1:3, 'recovered', logical([1 0 mod(round(10 * v), 2)]), 'held', logical([mod(round(10 * v), 2) 1 0]), ...
    'per_post', [0.1 v 0.3], 'switches', [0 1 2], 'ret', [v 1 2]);
E = struct('POL', {POL}, 'LBL', {POL}, 'set_names', {{'single', 'follower', 'combined', 'unknown', 'clean', 'comb'}}, ...
    'iDQN', 4, 'iThreat', 1:3, 'fixed_best', 2, 'tab', struct('t', 1), 'top_cfg', struct('threat', 'jamming', 'action', 'no_action', 'share', 0.25));
E.LBL{4} = 'DQN gamma=0.90 (selected) (deployed)';
E.RES = cell(6, numel(POL));
for si = 1:6, for c = 1:numel(POL), E.RES{si, c} = mk(si + c / 10); end, end
E.ALL = arrayfun(@(c) mk(20 + c), 1:numel(POL), 'UniformOutput', false);
E.RW = arrayfun(@(c) mk(30 + c), 1:numel(POL), 'UniformOutput', false);
E.RS2 = mk(40);
E.LBC = struct('policy', 'dqn_g1', 'sets', struct('set', {'single'}, 'off', {0.5}, 'on', {0.6}, 'rule', {0.7}), ...
    'lines', {{'single 0.6 | rule + escalation  70.0%'}}, 'kpi', {{'DQN 60.0% | rule + escalation 70.0%; deployed switch on'}});
E.KP = struct('show', {{'none', 'rule_esc', 'dqn_g1'}}, 'per_threat', [90 70 80; 91 71 81], ...
    'far', struct('policy', {'none', 'rule_esc', 'dqn_g1'}, 'k', {0, 3, 2}), 'envelope_val', [95 96]);
D = E;
for c = [2 3 6]
    for si = 1:6, D.RES{si, c}.recovered = ~E.RES{si, c}.recovered; end
    D.ALL{c} = mk(50 + c); D.RW{c} = mk(60 + c);
end
D.LBC.sets(1).rule = 0.8; D.LBC.lines{1} = 'single 0.6 | rule + escalation  80.0%';
D.KP.per_threat(:, 2) = [75; 76]; D.KP.far(2).k = 5;
N = D;
N.RES{6, 4}.recovered(:) = true;                                 % the comb set of the deployed row
N.ALL{4} = mk(70); N.RW{4} = mk(71);
N.KP.per_threat(:, 3) = [85; 86]; N.KP.far(3).k = 1;
end

function ok = row_ok(G, name)
k = find(strcmp({G.rows.file}, name), 1);
ok = ~isempty(k) && G.rows(k).ok;
end

function h = text_sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
s = strrep(fileread(f), char(13), '');
if ~isempty(s), md.update(unicode2native(s, 'UTF-8')); end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function S = tree_state(t)
d = dir(fullfile(t, '**', '*')); d = d(~[d.isdir]);
f = arrayfun(@(x) fullfile(x.folder, x.name), d, 'UniformOutput', false);
[f, o] = sort(f); d = d(o);
S = struct('f', {f}, 'bytes', [d.bytes], 'date', [d.datenum], 'sha', {cellfun(@(x) adopt_reading('sha', x), f, 'UniformOutput', false)});
end

function p = jp(f)
p = java.io.File(f).toPath();
end

function p = canon(p)
p = char(java.io.File(p).getCanonicalPath());
end

function add_line(f)
fileattrib(f, '+w');
fid = fopen(f, 'a'); fprintf(fid, ' \n'); fclose(fid);
end

function write_text(f, s)
d = fileparts(f); if ~isfolder(d), mkdir(d); end
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function rm_all(d)
if ~isfolder(d), return; end
x = dir(fullfile(d, '**', '*')); x = x(~[x.isdir]);
for k = 1:numel(x), fileattrib(fullfile(x(k).folder, x(k).name), '+w'); end
rmdir(d, 's');
end

function [missing, added] = line_diff(tc, rev, rel)
old = rev_lines(tc, rev, rel);
new = regexp(strrep(fileread(fullfile(tc.TestData.root, rel)), char(13), ''), '\n', 'split');
j = 1; missing = {}; kept = false(1, numel(new));
for i = 1:numel(old)
    k = find(strcmp(new(j:end), old{i}), 1);
    if isempty(k), missing{end+1} = old{i}; else, kept(j + k - 1) = true; j = j + k; end %#ok<AGROW>
end
added = new(~kept);
end

function L = rev_lines(tc, rev, rel)
d = tempname(tc.TestData.tmp); mkdir(d);
f = fullfile(d, 'f.m');
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', tc.TestData.root, rev, rel, f));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
L = regexp(strrep(fileread(f), char(13), ''), '\n', 'split');
end
