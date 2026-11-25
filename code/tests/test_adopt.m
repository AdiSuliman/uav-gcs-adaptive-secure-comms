function tests = test_adopt
%TEST_ADOPT  The adoption of the rule's frozen setting into a finished tree's outputs
%   (adopt_options.m, adopt_reading.m): with CFG.adopt absent every policy keeps its options and
%   evaluate_policies.m is the parent's but for the hook lines; the overlay copies with dates kept,
%   links the data read-only and writes nothing under the tree; the stages refuse in their order;
%   the C2e guards, the comparisons and the write-once files on synthetic inputs. The rule's layered
%   answers ported onto this tree's decision layer: off gives the parent's answers, actions and
%   escalations bit for bit; on gives the rule-fix commit's on the same monitor. Temporary folders
%   only, no pools, no MATLAB run of a stage. Run from the repository root:
%   results = runtests('code/tests/test_adopt.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
mkdir('data');
clean_ref = struct('ebno', 0:3:15, 'ber_est', [4e-2 1.2e-2 3e-3 8e-4 2e-4 5e-5], ...
    'plr_fec', [0.3 0.1 0.03 0.01 0.003 0.001]);                 % the clean-link table clean_ber_ref.m reads
save('data/policy_pools.mat', 'clean_ref');
clear('clean_ber_ref');
tc.TestData.base = 'd4623ed';                                    % the commit this branch starts from: profile 1's HEAD
tc.TestData.tree_rev = 'd4623ed';                                % the tree's code
tc.TestData.layer = 'cc2d4f1';                                   % the rule-fix commit whose decision layer is ported
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
rm_all(tc.TestData.tmp);
end

%% ---------- adopt_options.m ----------
function test_options_off(tc)
% Absent, empty or '' is off, and off leaves every policy's options as they are.
offs = {[], struct(), struct('adopt', []), struct('adopt', struct()), struct('adopt', struct('rule_fix', '')), ...
    struct('adopt', struct('rule_fix', "")), struct('adopt', struct('rule_fix', '', 'dqn_hop', '')), struct('kpi6_set', 'union')};
for k = 1:numel(offs)
    A = adopt_options(offs{k});
    verifyFalse(tc, A.on, sprintf('case %d', k));
    verifyEqual(tc, A.rule_fix, '');
    verifyEmpty(tc, A.names);
    verifyEqual(tc, adopt_options('note', A), '');
end
A = adopt_options();
verifyFalse(tc, A.on);
opts = {struct(), struct('monitor', struct('alarm', 'class_drop 2/3')), struct('core', true), struct('fixed', 3), ...
    struct('monitor', struct('release_m', false))};
for n = policy_names()
    for o = opts
        verifyTrue(tc, isequaln(adopt_options('opt', adopt_options([]), n{1}, o{1}), o{1}), n{1});
    end
end
end

function test_options_on(tc)
A = adopt_options(struct('adopt', struct('rule_fix', 'rate+st+keep')));
verifyTrue(tc, A.on);
verifyEqual(tc, A.rule_fix, 'keep+st+rate');                      % canonical
verifyEqual(tc, A.names, {'rule_fix'});
verifyEqual(tc, adopt_options(struct('adopt', struct('rule_fix', "keep+st+rate"))).rule_fix, 'keep+st+rate');
verifyTrue(tc, contains(adopt_options('note', A), 'keep+st+rate'));
rs = struct('alarm', 'class_drop 2/3', 'drop', 4);
o = adopt_options('opt', A, 'rule_sel', struct('monitor', rs));
verifyEqual(tc, o.monitor.rule_fix, 'keep+st+rate');
verifyEqual(tc, rmfield(o.monitor, 'rule_fix'), rs);              % the rule fallback keeps its own monitor
for n = {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_core3', 'rule_esc_relm', 'rule_esc_nos1g', ...
        'rule_core_nos1gc', 'rule_esc_norelm', 'rule_esc_s1g', 'rule_core_s1gc'}
    o = adopt_options('opt', A, n{1}, struct('core', true));
    verifyEqual(tc, o.monitor, struct('rule_fix', 'keep+st+rate'), n{1});
    verifyEqual(tc, o.core, true);
end
for n = {'none', 'random', 'fixed', 'fixed_mmse', 'table', 'table_relm', 'table_norelm', 'dqn_g1', 'dqn_g3', 'dqn_esc', ...
        'dqn_g2_norelm', 'dqn_g2_relm', 'oracle'}
    for o = {struct(), struct('monitor', struct('lb_complete', true))}
        verifyTrue(tc, isequaln(adopt_options('opt', A, n{1}, o{1}), o{1}), n{1});   % the DQN and the others never
    end
end
verifyError(tc, @() adopt_options(struct('adopt', struct('rule_fx', 'keep'))), 'adopt_options:name');
verifyError(tc, @() adopt_options(struct('adopt', struct('dqn_hop', 'q'))), 'adopt_options:dqn_hop');
verifyError(tc, @() adopt_options(struct('adopt', struct('rule_fix', 'keep', 'dqn_hop', 'rule'))), 'adopt_options:dqn_hop');
verifyError(tc, @() adopt_options(struct('adopt', 'keep')), 'adopt_options:value');
verifyError(tc, @() adopt_options(struct('adopt', struct('rule_fix', 'keep+notch'))), 'rule_fix:token');
verifyEqual(tc, adopt_options('names'), {'rule_fix', 'dqn_hop'});
end

function test_rule_rows(tc)
yes = {'rule', 'rule_esc', 'blind_esc', 'rule_core', 'blind_core', 'rule_sel', 'rule_core3', 'rule_esc_relm', ...
    'rule_esc_nos1g', 'rule_core_nos1gc', 'rule_esc_norelm', 'rule_esc_s1g'};
no = {'none', 'random', 'fixed', 'fixed_mmse', 'table', 'table_relm', 'dqn_g1', 'dqn_esc', 'dqn_g2_norelm', 'oracle', ...
    'rule_x', 'core'};
verifyTrue(tc, all(cellfun(@(n) adopt_options('rule_row', n), yes)));
verifyFalse(tc, any(cellfun(@(n) adopt_options('rule_row', n), no)));
end

%% ---------- off = the parent ----------
function test_evaluate_policies_off_is_the_parent(tc)
% Line for line the parent's script but for the hook lines; each hook returns the options unchanged
% when CFG.adopt is absent (test_options_off).
[missing, added] = line_diff(tc, tc.TestData.base, 'code/decision/evaluate_policies.m');
verifyEqual(tc, missing, {});
verifyEqual(tc, added, ...
    {'cfgA = []; if exist(''CFG'', ''var''), cfgA = CFG; end', ...
    'ADP = adopt_options(cfgA);                           % adopted settings (CFG.adopt, adopt_options.m), off by default', ...
    '        opt = adopt_options(''opt'', ADP, POL{pk}, opt);', ...
    'opt = adopt_options(''opt'', ADP, POL{iDQN}, opt);', ...
    'if ADP.on, rep{end+1} = adopt_options(''note'', ADP); end', ...
    '        opt = adopt_options(''opt'', ADP, POL{pk}, opt);'});
src = strrep(fileread(fullfile(tc.TestData.root, 'code', 'decision', 'evaluate_policies.m')), char(13), '');
verifyNumElements(tc, strfind(src, 'policy_setup('), 3);          % the hook follows every policy_setup call
verifyNumElements(tc, strfind(src, 'adopt_options(''opt'''), 3);
end

function test_other_files_are_the_parent(tc)
% The tree's own code everywhere but the ported layer; rule_fix.m as the rule-fix commit holds it.
for f = {'decision/policy_stamp.m', 'decision/policy_setup.m', 'decision/policy_run_set.m', 'decision/rollout_policy.m', ...
        'decision/policy_monitor.m', 'decision/rule_core_policy.m', 'decision/config_gain_db.m', 'decision/decision_config.m', ...
        'evaluation/lect_kpis.m', 'evaluation/measure_all_kpis.m', 'evaluation/build_kpi_dashboard.m', ...
        'evaluation/export_report_numbers.m', 'gui/export_gui_bundle.m', 'evaluation/result_status.m'}
    verifyTrue(tc, same_as_rev(tc, tc.TestData.tree_rev, ['code/' f{1}]), f{1});
end
verifyTrue(tc, same_as_rev(tc, tc.TestData.layer, 'code/decision/rule_fix.m'));
for f = {'decision/rule_core_policy.m', 'decision/config_gain_db.m', 'decision/policy_actions.m'}   % what the rule reads
    verifyTrue(tc, same_rev(tc, tc.TestData.base, tc.TestData.layer, ['code/' f{1}]), f{1});
end
verifyFalse(tc, isfile(fullfile(tc.TestData.root, 'code', 'evaluation', 'lect_kpi_table.m')));   % no KPI table on this tree
end

function test_ported_layer_lines(tc)
% The port changes these lines of the parent's decision layer and no other; each new code line is
% behind fx (PP.rule_fix) or only passes it on.
[m, a] = line_diff(tc, tc.TestData.base, 'code/decision/policy_decide.m');
verifyEqual(tc, m, {'                    so, nb)), 1);', ...
    '                if ~mem.tried(i, lb(o(j))), a(i) = lb(o(j)); escalated(i) = true; continue; end', ...
    '                b = ladder(find(~mem.tried(i, ladder), 1));'});
verifyEqual(tc, a, {'%   PP.rule_fix (rule, table and their escalations, the core and blind ones included; rule_fix.m): the', ...
    '%   layered answers of the rule and the escalation that keeps what the configuration in use holds;', ...
    '%   '''' or absent leaves every answer and rung as it was; keep covers the drop alarm''s link-budget step', ...
    '%   too. The core rule''s class jamming keeps the answer PP.core_wide only when PP.core_wide_valid marks', ...
    '%   it chosen on validation. The DQN kinds are unchanged.', ...
    '%', ...
    'fx = ''''; if isfield(PP, ''rule_fix''), fx = rule_fix(''parse'', PP.rule_fix); if ~fx.on, fx = ''''; end, end   % layered answers', ...
    'cwv = ''''; if isfield(PP, ''core_wide_valid'') && isequal(PP.core_wide_valid, true) && isfield(PP, ''core_wide''), cwv = PP.core_wide; end', ...
    '                if ~isempty(fx), p = find(strcmp(A, rule_fix(''core'', A{p}, M.cls{i}, fx, qi(i), qt, M.degraded(i), so, A{cfg(i)}, cwv)), 1); end', ...
    '                    so, nb, fx)), 1);', ...
    '                if ~isempty(fx) && fx.keep                   % the hop and the null kept', ...
    '                    bj = find(strcmp(A, rule_fix(''merge'', A{cfg(i)}, A{lb(o(j))})), 1);', ...
    '                    if ~mem.tried(i, bj) && bj ~= cfg(i), a(i) = bj; escalated(i) = true; continue; end', ...
    '                elseif ~mem.tried(i, lb(o(j))), a(i) = lb(o(j)); escalated(i) = true; continue; end', ...
    '                if ~isempty(fx) && fx.keep, b = rule_fix(''rung'', A, cfg(i), ladder, mem.tried(i, :));', ...
    '                else, b = ladder(find(~mem.tried(i, ladder), 1)); end'});
[m, a] = line_diff(tc, tc.TestData.base, 'code/decision/rule_based_policy.m');
verifyEqual(tc, m, {'function [action, reason] = rule_based_policy(threat_class, degraded, mmse_gain_db, q_iot_db, q_thr_db, drop, budget, mmse_thr_db, slot_on, burst_action)'});
verifyEqual(tc, a, {'function [action, reason] = rule_based_policy(threat_class, degraded, mmse_gain_db, q_iot_db, q_thr_db, drop, budget, mmse_thr_db, slot_on, burst_action, fix)', ...
    '%   fix           the layered answers (optional; PP.rule_fix, rule_fix.m): '''' or absent keeps every', ...
    '%                 answer below', ...
    'if nargin < 11, fix = ''''; end', ...
    'a_cls = action;', ...
    'if ~isempty(fix)', ...
    '    a0 = action;', ...
    '    action = rule_fix(''answer'', action, threat_class, fix, q_iot_db, q_thr_db, degraded, slot_on, budget, strcmp(action, a_cls));', ...
    '    if ~strcmp(action, a0), reason = sprintf(''%s; layered answer %s'', reason, action); end', ...
    'end'});
[m, a] = line_diff(tc, tc.TestData.base, 'code/decision/decision_settings.m');
verifyEqual(tc, m, {'        ''rule_mmse_db'', ''rule_slot'', ''rule_dwell'', ''esc_drop'', ''rule_nb'', ''core_nb''}'});
verifyEqual(tc, a, {'%   rule        rule_fix (the layered answers, rule_fix.m; '''' or absent: off)', ...
    '        ''rule_mmse_db'', ''rule_slot'', ''rule_dwell'', ''esc_drop'', ''rule_nb'', ''core_nb'', ''rule_fix''}'});
end

%% ---------- the ported layer ----------
function test_settings_plumb(tc)
PP = struct('actions', {policy_actions()}, 'confirm', [2 2]);
verifyEqual(tc, decision_settings(PP, struct()), PP);
P1 = decision_settings(PP, struct('rule_fix', 'keep+st+rate'));
verifyEqual(tc, P1.rule_fix, 'keep+st+rate');
P2 = decision_settings(PP, struct('dec', struct('rule_fix', 'keep')));
verifyEqual(tc, P2.rule_fix, 'keep');
end

function test_rule_off_is_the_parent(tc)
% rule_based_policy.m with the option absent or '' gives the parent's answers and reasons.
[args, n] = rule_grid();
new = cell(n, 2); new2 = new;
for i = 1:n
    [a, r] = rule_based_policy(args{i}{:}); new(i, :) = {a, r};
    [a, r] = rule_based_policy(args{i}{:}, ''); new2(i, :) = {a, r};
end
verifyEqual(tc, new2, new);
d = parent_dir(tc, tc.TestData.base, {'code/decision/rule_based_policy.m'});
addpath(d, '-begin'); clear rule_based_policy
cl = onCleanup(@() fixture_off(d, {'rule_based_policy'})); %#ok<NASGU>
verifyEqual(tc, which('rule_based_policy'), fullfile(d, 'rule_based_policy.m'));
old = cell(n, 2);
for i = 1:n, [a, r] = rule_based_policy(args{i}{:}); old(i, :) = {a, r}; end
fixture_off(d, {'rule_based_policy'});
verifyEqual(tc, new, old);
end

function test_rule_port_is_the_layer(tc)
% With the option on, the port answers as the rule-fix commit's rule (no lost-branch gate there).
[args, n] = rule_grid();
fxs = {'keep', 'keep+st', 'keep+st+rate', 'keep+st+match', 'keep+st+rate+fec', 'fec'};
new = cell(n, numel(fxs)); off = cell(n, 1);
for i = 1:n
    off{i} = rule_based_policy(args{i}{:});
    for k = 1:numel(fxs), new{i, k} = rule_based_policy(args{i}{:}, fxs{k}); end
end
verifyFalse(tc, isequal(new(:, 3), off));                         % the setting moves answers
d = parent_dir(tc, tc.TestData.layer, {'code/decision/rule_based_policy.m'});
addpath(d, '-begin'); clear rule_based_policy
cl = onCleanup(@() fixture_off(d, {'rule_based_policy'})); %#ok<NASGU>
verifyEqual(tc, which('rule_based_policy'), fullfile(d, 'rule_based_policy.m'));
old = cell(n, numel(fxs));
for i = 1:n
    for k = 1:numel(fxs), old{i, k} = rule_based_policy(args{i}{:}, [], fxs{k}); end
end
fixture_off(d, {'rule_based_policy'});
verifyEqual(tc, new, old);
end

function test_decide_off_is_the_parent(tc)
% The rule, the rule with escalation, without the detector, the core rule and the table with
% escalation, under the plain settings and under the escalation on a drop alarm, the group dwell, the
% slot branch off and a noise-burst answer, with the option absent, '' and "", give the parent's
% actions and info cycle by cycle.
[~, X, V, kinds, opts] = decide_cases();
runs = runs_of(V, kinds);
Rn = cell(1, size(runs, 1)); Rf = Rn; Rs = Rn;
for r = 1:size(runs, 1)
    P = V{runs(r, 1)}; k = runs(r, 2);
    Rn{r} = decide_run(kinds{k}, P, X, opts{k});
    P.rule_fix = ''; Rf{r} = decide_run(kinds{k}, P, X, opts{k});
    P.rule_fix = ""; Rs{r} = decide_run(kinds{k}, P, X, opts{k});
end
d = parent_dir(tc, tc.TestData.base, {'code/decision/policy_decide.m', 'code/decision/rule_based_policy.m'});
addpath(d, '-begin'); clear policy_decide rule_based_policy
cl = onCleanup(@() fixture_off(d, {'policy_decide', 'rule_based_policy'})); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, size(runs, 1)); esc = moved;
for r = 1:size(runs, 1)
    k = runs(r, 2);
    Ro = decide_run(kinds{k}, V{runs(r, 1)}, X, opts{k});
    t = sprintf('%s, settings %d', kinds{k}, runs(r, 1));
    verifyTrue(tc, isequaln(Ro, Rn{r}), [t ', field absent']);
    verifyTrue(tc, isequaln(Ro, Rf{r}), [t ', field empty']);
    verifyTrue(tc, isequaln(Ro, Rs{r}), [t ', empty string']);
    moved(r) = numel(unique(Ro.a(:))) > 2;
    esc(r) = any(cellfun(@(I) any(I.escalated), Ro.I));
end
fixture_off(d, {'policy_decide', 'rule_based_policy'});
verifyTrue(tc, any(moved) && any(esc));                         % the traces move the configuration and escalate
end

function test_decide_port_is_the_layer(tc)
% With the option on, through PP or through the policy's own monitor (as the adoption applies it),
% the port's actions and escalations are the rule-fix commit's decision layer's on this tree's monitor.
[~, X, V, kinds, opts] = decide_cases();
runs = runs_of(V, kinds);
fxs = {'keep+st+rate', 'keep+st+match+fec', 'keep'};
Rp = cell(size(runs, 1), numel(fxs)); moved = false;
for r = 1:size(runs, 1)
    k = runs(r, 2);
    R0 = decide_run(kinds{k}, V{runs(r, 1)}, X, opts{k});
    for f = 1:numel(fxs)
        P = V{runs(r, 1)}; P.rule_fix = fxs{f};
        R = decide_run(kinds{k}, P, X, opts{k});
        om = opts{k}; om.monitor = struct('rule_fix', fxs{f});
        Rm = decide_run(kinds{k}, V{runs(r, 1)}, X, om);
        verifyEqual(tc, Rm.a, R.a, sprintf('%s via the monitor, %s', kinds{k}, fxs{f}));
        Rp{r, f} = struct('a', R.a, 'e', {esc_of(R)});
        moved = moved || ~isequal(R.a, R0.a);
    end
end
verifyTrue(tc, moved);                                           % the setting moves actions
d = parent_dir(tc, tc.TestData.layer, {'code/decision/policy_decide.m', 'code/decision/rule_based_policy.m'});
addpath(d, '-begin'); clear policy_decide rule_based_policy
cl = onCleanup(@() fixture_off(d, {'policy_decide', 'rule_based_policy'})); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
esc = false;
for r = 1:size(runs, 1)
    k = runs(r, 2);
    for f = 1:numel(fxs)
        P = V{runs(r, 1)}; P.rule_fix = fxs{f};
        Ro = decide_run(kinds{k}, P, X, opts{k});
        t = sprintf('%s, settings %d, %s', kinds{k}, runs(r, 1), fxs{f});
        verifyEqual(tc, Rp{r, f}.a, Ro.a, t);
        verifyEqual(tc, Rp{r, f}.e, esc_of(Ro), t);
        esc = esc || any(cellfun(@any, esc_of(Ro)));
    end
end
fixture_off(d, {'policy_decide', 'rule_based_policy'});
verifyTrue(tc, esc);                                             % the escalation ran under the option
end

%% ---------- overlay ----------
function test_overlay_builds(tc)
W = world(tc, 'dqn');
s0 = tree_state(W.tree);
M = adopt_reading('overlay', W.tag, W.tree, W.O);
X = adopt_reading('paths', W.tag, W.O);
verifyEqual(tc, M.tag, W.tag);
verifyEqual(tc, lower(M.tree), lower(canon(W.tree)));
verifyEqual(tc, M.version, 1);
verifyEqual(tc, M.adoptions(1).name, 'rule_fix');
verifyEqual(tc, M.adoptions(1).setting, 'keep+st+rate');
verifyEqual(tc, M.adoptions(1).val_sha256, adopt_reading('sha', fullfile(W.rf, 'val.mat')));
verifyEqual(tc, M.adoptions(1).test_sha256, adopt_reading('sha', fullfile(W.rf, 'test.mat')));
verifyMatches(tc, M.adoptions(1).selection_sha256, '^[0-9a-f]{64}$');
verifyEqual(tc, M.order(:)', {'overlay', 'off', 'c2e', 'gate', 'render'});
verifyEqual(tc, M.tree_head, 'unknown');                          % the synthetic tree is no git checkout
verifyEmpty(tc, M.readonly_before);
verifyMatches(tc, M.checkout_code_sha256, '^[0-9a-f]{64}$');
verifyTrue(tc, contains(fileread(X.ovt), 'read-only'));
for f = {'data/trained_dqn.mat', 'data/big.mat'}                    % the attribute is the file's, as overlay.txt states
    verifyFalse(tc, java.io.File(fullfile(W.tree, f{1})).canWrite(), f{1});
end
% the tree's registered results and inputs, hashed
F = adopt_reading('tree_files', W.tree);
verifyEqual(tc, F, sort({'results/a.txt', 'results/sub/b.txt', 'results/policy_evaluation.mat', 'results/kpi_summary.txt', ...
    'results/policy_breakdown.png', 'params.mat', 'profile.json', 'data/trained_dqn.mat', 'data/big.mat'}));
L = read_lines(X.sha);
verifyEqual(tc, L, cellfun(@(f) sprintf('%s  %s', adopt_reading('sha', fullfile(W.tree, f)), f), F, 'UniformOutput', false));
verifyEqual(tc, M.n_files, numel(F));
% copies with their dates, less what each root's stages write
for r = {'off', 'on'}
    R = X.(r{1});
    for f = {'results/a.txt', 'results/sub/b.txt', 'params.mat', 'profile.json'}
        verifyTrue(tc, isfile(fullfile(R, f{1})), [r{1} ' ' f{1}]);
        verifyEqual(tc, mtime(fullfile(R, f{1})), mtime(fullfile(W.tree, f{1})), [r{1} ' ' f{1}]);
        verifyEqual(tc, fileread(fullfile(R, f{1})), fileread(fullfile(W.tree, f{1})));
    end
    verifyFalse(tc, isfile(fullfile(R, 'results', 'kpi_summary.txt')), r{1});
    for f = {'data/trained_dqn.mat', 'data/big.mat'}                % read-only hard links
        verifyTrue(tc, java.nio.file.Files.isSameFile(jp(fullfile(R, f{1})), jp(fullfile(W.tree, f{1}))), f{1});
        verifyFalse(tc, java.io.File(fullfile(R, f{1})).canWrite(), f{1});
    end
end
verifyTrue(tc, isfile(fullfile(X.off, 'results', 'policy_evaluation.mat')));   % ADOPT0 reads the registered file
verifyTrue(tc, isfile(fullfile(X.off, 'results', 'policy_breakdown.png')));
verifyFalse(tc, isfile(fullfile(X.on, 'results', 'policy_evaluation.mat')));   % C2e writes it there
verifyFalse(tc, isfile(fullfile(X.on, 'results', 'policy_breakdown.png')));
verifyEqual(tc, mtime(fullfile(X.off, 'results', 'a.txt')), mtime(fullfile(W.tree, 'results', 'a.txt')));
verifyLessThan(tc, dir(fullfile(X.off, 'results', 'a.txt')).datenum, now - 1);     % an old date, kept
% nothing under the tree changed, and nothing new there
verifyEqual(tc, tree_state(W.tree), s0);
end

function test_overlay_refusals(tc)
W = world(tc, 'dqn');
adopt_reading('overlay', W.tag, W.tree, W.O);
s0 = tree_state(W.tree);
verifyError(tc, @() adopt_reading('overlay', W.tag, W.tree, W.O), 'adopt_reading:exists');   % built once
W2 = world(tc, 'dqn');
O2 = W2.O; O2.root = fullfile(W2.tree, 'inside');                % an overlay inside the tree
verifyError(tc, @() adopt_reading('overlay', W2.tag, W2.tree, O2), 'adopt_reading:inside');
verifyFalse(tc, isfolder(fullfile(W2.tree, 'inside')));
W3 = world(tc, 'dqn');
write_sel(W3, 'c:\some\other\tree', 'keep+st+rate');              % frozen on another tree
verifyError(tc, @() adopt_reading('overlay', W3.tag, W3.tree, W3.O), 'adopt_reading:selection');
W4 = world(tc, 'dqn');
delete(fullfile(W4.rf, 'test.mat'));
verifyError(tc, @() adopt_reading('overlay', W4.tag, W4.tree, W4.O), 'adopt_reading:sources');
W5 = world(tc, 'dqn');
delete(fullfile(W5.tree, 'results', 'policy_evaluation.mat'));
verifyError(tc, @() adopt_reading('overlay', W5.tag, W5.tree, W5.O), 'adopt_reading:tree');
for w = {W2, W3, W4, W5}
    verifyFalse(tc, isfolder(adopt_reading('paths', w{1}.tag, w{1}.O).dir));   % refused before any file
end
verifyEqual(tc, tree_state(W.tree), s0);
end

function test_stage_order(tc)
% Every stage refuses without the overlay; c2e refuses until ADOPT0 passed, then on its outputs, a
% thread count other than C2e's, a tree that moved and code that would not run from the checkout, in
% that order, before evaluate_policies.m runs.
W = world(tc, 'dqn');
for s = {'off', 'c2e', 'gate', 'render', 'release'}
    verifyError(tc, @() adopt_reading(s{1}, W.tag, W.tree, W.O), 'adopt_reading:no_overlay', s{1});
end
adopt_reading('overlay', W.tag, W.tree, W.O);
X = adopt_reading('paths', W.tag, W.O);
s0 = tree_state(W.tree);
verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:off_not_passed');
adopt_reading('write_once', X.v.off, {jsonencode(struct('stage', 'off', 'pass', false))});
verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:off_not_passed');
delete(X.v.off);
adopt_reading('write_once', X.v.off, {jsonencode(struct('stage', 'off', 'pass', true))});
pe = fullfile(X.on, 'results', 'policy_evaluation.mat'); x = 1; save(pe, 'x');
verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:exists');
delete(pe);
n0 = maxNumCompThreads;
cl = onCleanup(@() maxNumCompThreads(n0)); %#ok<NASGU>
maxNumCompThreads(1);
verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:threads');
ok8 = false;
try
    maxNumCompThreads(8); ok8 = maxNumCompThreads == 8;
catch
end
if ok8
    verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:path');   % the synthetic checkout holds no code
    verifyEqual(tc, tree_state(W.tree), s0);
    add_line(fullfile(W.tree, 'results', 'a.txt'));               % the tree moved after the overlay
    verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:tree_changed');
    try
        maxNumCompThreads(16); n16 = maxNumCompThreads;
    catch
        n16 = 8;
    end
    if n16 ~= 8                                                    % more threads than C2e's: refused too
        verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:threads');
    end
end
verifyFalse(tc, isfile(X.v.c2e));
verifyFalse(tc, isfile(pe));
verifyFalse(tc, isfolder(X.logs));                                 % refused before the log opens
end

function test_release(tc)
% The release gives back the write attribute the overlay's links took from the tree's data files
% (those read-only before stay so) and closes the overlay.
W = world(tc, 'dqn');
fileattrib(fullfile(W.tree, 'data', 'big.mat'), '-w');
M = adopt_reading('overlay', W.tag, W.tree, W.O);
X = adopt_reading('paths', W.tag, W.O);
verifyEqual(tc, reshape(cellstr(M.readonly_before), 1, []), {'data/big.mat'});
f = fullfile(W.tree, 'data', 'trained_dqn.mat');
verifyFalse(tc, java.io.File(f).canWrite());
s0 = tree_state(W.tree);
V = adopt_reading('release', W.tag, W.tree, W.O);
verifyTrue(tc, V.pass);
verifyTrue(tc, java.io.File(f).canWrite());
verifyFalse(tc, java.io.File(fullfile(W.tree, 'data', 'big.mat')).canWrite());
verifyEqual(tc, tree_state(W.tree), s0);
verifyTrue(tc, isfile(X.v.release) && isfile(X.t.release));
for s = {'off', 'c2e', 'gate', 'render', 'release'}
    verifyError(tc, @() adopt_reading(s{1}, W.tag, W.tree, W.O), 'adopt_reading:released', s{1});
end
end

function test_code_pin(tc)
% The checkout's code is pinned at the overlay: an edit after it stops every later stage (tests/
% aside); uncommitted code under git refuses the overlay.
W = world(tc, 'dqn');
write_text(fullfile(W.co, 'code', 'decision', 'a.m'), sprintf('a = 1;\r\nb = 2;\r\n'));
M = adopt_reading('overlay', W.tag, W.tree, W.O);
verifyMatches(tc, M.checkout_code_sha256, '^[0-9a-f]{64}$');
write_text(fullfile(W.co, 'code', 'tests', 'test_a.m'), 'x');
write_text(fullfile(W.co, 'code', 'decision', 'a.m'), sprintf('a = 1;\nb = 2;\n'));   % line ends converted
verifyError(tc, @() adopt_reading('c2e', W.tag, W.tree, W.O), 'adopt_reading:off_not_passed');
write_text(fullfile(W.co, 'code', 'decision', 'a.m'), 'a = 2;');
for s = {'off', 'c2e', 'gate', 'render', 'release'}
    verifyError(tc, @() adopt_reading(s{1}, W.tag, W.tree, W.O), 'adopt_reading:code', s{1});
end
[sv, ~] = system('git --version');
if sv ~= 0, return; end
W2 = world(tc, 'dqn');
write_text(fullfile(W2.co, 'code', 'decision', 'a.m'), 'a = 1;');
verifyEqual(tc, git_in(W2.co, 'init -q'), 0);
verifyEqual(tc, git_in(W2.co, 'add code'), 0);
verifyEqual(tc, git_in(W2.co, '-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m t'), 0);
write_text(fullfile(W2.co, 'code', 'decision', 'a.m'), 'a = 2;');
verifyError(tc, @() adopt_reading('overlay', W2.tag, W2.tree, W2.O), 'adopt_reading:dirty');
verifyFalse(tc, isfolder(adopt_reading('paths', W2.tag, W2.O).dir));
write_text(fullfile(W2.co, 'code', 'decision', 'a.m'), 'a = 1;');
M2 = adopt_reading('overlay', W2.tag, W2.tree, W2.O);
verifyMatches(tc, M2.checkout_head, '^[0-9a-f]{40}$');
end

function test_sources_and_gate(tc)
W = world(tc, 'dqn');
adopt_reading('overlay', W.tag, W.tree, W.O);
X = adopt_reading('paths', W.tag, W.O);
verifyError(tc, @() adopt_reading('gate', W.tag, W.tree, W.O), 'adopt_reading:c2e_not_passed');
verifyError(tc, @() adopt_reading('render', W.tag, W.tree, W.O), 'adopt_reading:gate_not_passed');
adopt_reading('write_once', X.v.c2e, {jsonencode(struct('stage', 'c2e', 'pass', true))});   % no outputs recorded
verifyError(tc, @() adopt_reading('gate', W.tag, W.tree, W.O), 'adopt_reading:c2e_outputs');
verifyFalse(tc, isfile(X.v.gate));
delete(X.v.c2e);
write_c2e(X);
verifyError(tc, @() adopt_reading('render', W.tag, W.tree, W.O), 'adopt_reading:gate_not_passed');
V = adopt_reading('gate', W.tag, W.tree, W.O);
verifyTrue(tc, V.pass);
verifyTrue(tc, isfile(X.v.gate) && isfile(X.t.gate));
G = jsondecode(fileread(X.v.gate));
verifyTrue(tc, G.pass); verifyEqual(tc, G.deployed, 'dqn');
verifyError(tc, @() adopt_reading('gate', W.tag, W.tree, W.O), 'adopt_reading:exists');   % read once
% the file ADOPT-C2e checked changed after it: the gate refuses
W3 = world(tc, 'dqn');
adopt_reading('overlay', W3.tag, W3.tree, W3.O);
X3 = adopt_reading('paths', W3.tag, W3.O);
write_c2e(X3);
x = 2; save(fullfile(X3.on, 'results', 'policy_evaluation.mat'), 'x'); %#ok<NASGU>
verifyError(tc, @() adopt_reading('gate', W3.tag, W3.tree, W3.O), 'adopt_reading:c2e_outputs');
verifyFalse(tc, isfile(X3.v.gate));
% a gate that moves the deployed policy stops the stage
W2 = world(tc, 'rule_sel');
adopt_reading('overlay', W2.tag, W2.tree, W2.O);
X2 = adopt_reading('paths', W2.tag, W2.O);
write_c2e(X2);
verifyError(tc, @() adopt_reading('gate', W2.tag, W2.tree, W2.O), 'adopt_reading:gate');
G2 = jsondecode(fileread(X2.v.gate));
verifyFalse(tc, G2.pass);
verifyError(tc, @() adopt_reading('render', W2.tag, W2.tree, W2.O), 'adopt_reading:gate_not_passed');
% the frozen reading changed after the overlay: every stage refuses
add_line(fullfile(W2.rf, 'selection.json'));
verifyError(tc, @() adopt_reading('render', W2.tag, W2.tree, W2.O), 'adopt_reading:sources');
end

function test_manifest_order(tc)
M = struct('adoptions', struct('name', 'rule_fix', 'setting', 'keep+st+rate'));
C = adopt_reading('cfg', M);
verifyEqual(tc, C.adopt, struct('rule_fix', 'keep+st+rate'));
verifyEqual(tc, adopt_options(C).rule_fix, 'keep+st+rate');
M.adoptions = struct('name', {'dqn_hop', 'rule_fix'}, 'setting', {'q', 'keep+st+rate'});
verifyError(tc, @() adopt_reading('cfg', M), 'adopt_reading:order');
M.adoptions = struct('name', {'rule_fix', 'dqn_hop'}, 'setting', {'keep+st+rate', 'q'});
verifyError(tc, @() adopt_reading('cfg', M), 'adopt_options:dqn_hop');    % the order is accepted, the layer is not here
M.adoptions = struct('name', {'rule_fix', 'other'}, 'setting', {'keep+st+rate', 'x'});
verifyError(tc, @() adopt_reading('cfg', M), 'adopt_reading:order');
M.adoptions = {struct('name', 'rule_fix', 'setting', 'keep')};    % a list of differing objects decodes to a cell
verifyEqual(tc, adopt_reading('cfg', M).adopt.rule_fix, 'keep');
end

%% ---------- C2e guards ----------
function test_guard_c2e(tc)
[N, E, T] = guard_world();
G = adopt_reading('guard_c2e', N, E, T);
verifyTrue(tc, G.pass, strjoin(arrayfun(@(r) [r.file ': ' r.why], G.rows(~[G.rows.ok]), 'UniformOutput', false), ' | '));
verifyTrue(tc, row_ok(G, 'KP.lect'));
P = N; P.RES{2, 1}.recovered(1) = ~P.RES{2, 1}.recovered(1);    % a non-rule column moved
G = adopt_reading('guard_c2e', P, E, T);
verifyFalse(tc, G.pass); verifyFalse(tc, row_ok(G, 'non-rule columns'));
P = N; P.ALL{4}.ret(1) = 99;                                     % the DQN pooled
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'non-rule columns'));
P = N; P.RW{1}.switches(2) = 7;                                  % no response on the clean pools
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'non-rule columns'));
P = N; P.LBC.sets(1).on = 0.1;                                   % the DQN columns of the completion
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'non-rule columns'));
P = N; P.LBC.lines{2} = 'clean 2/3';                               % the completion's text beside the rule's figure
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'non-rule columns'));
P = N; P.LBC.lines{1} = 'single 0.7 | rule + escalation  80.0%';
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'non-rule columns'));
P = N; P.LBC.kpi{1} = 'DQN 60.0% | rule + escalation 95.5%; deployed switch on';   % the rule's figure alone
verifyTrue(tc, adopt_reading('guard_c2e', P, E, T).pass);
P = rmfield(N, 'RS2');
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'variables'));
% KP: the deployed policy's fields whole, the rule-built ones without the rule's columns and entries
P = N; P.KP.envelope_val(1) = 1;
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.per_threat(1, 1) = 0;                                 % no response's column
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.per_threat(2, 3) = 0;                                 % the DQN's column
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.per_threat(1, 2) = 1;                                 % rule + escalation's column
verifyTrue(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.per_threat = P.KP.per_threat(:, 1:2);
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.far(3).k = 9;                                         % the DQN's clean false alarms
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.far(2).k = 99;
verifyTrue(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
P = N; P.KP.extra = 1;
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP'));
G = adopt_reading('guard_c2e', N, E, T);
verifyTrue(tc, row_ok(G, 'descriptive rule rows'));
verifyTrue(tc, contains(G.rows(strcmp({G.rows.file}, 'descriptive rule rows')).why, 'rule_esc_relm'));
P = N; P.RES{3, 3}.held(2) = ~P.RES{3, 3}.held(2);              % rule_esc on set 3 is not test.mat's
G = adopt_reading('guard_c2e', P, E, T);
verifyFalse(tc, G.pass); verifyFalse(tc, row_ok(G, 'rule columns, sets 1-5'));
P = N; P.RES{2, 5} = rmfield(P.RES{2, 5}, 't_rec');              % a kept field missing
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'rule columns, sets 1-5'));
P = N; P.RES{6, 2}.recovered(:) = true; P.RES{1, 6}.held(:) = false;   % set 6 and a descriptive row: read once, not guarded
verifyTrue(tc, adopt_reading('guard_c2e', P, E, T).pass);
P = N; P.KP.lect.per(1).red = 0.7;                                % KPI 5 not test.mat's
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP.lect'));
P = N; P.KP.lect.gput = 99;
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'KP.lect'));
T2 = T; T2.LK1 = T.LK0;                                           % nothing the setting changed: nothing checked
P = N; P.KP.lect = E.KP.lect;
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T2), 'KP.lect'));
T3 = T; T3.LK0.gput = 15;                                         % a changed value the registered KP.lect does not share
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', N, E, T3), 'KP.lect'));                         % strict
P = N; P.KP.lect.gput = 99;                                       % not compared, not strict
verifyTrue(tc, row_ok(adopt_reading('guard_c2e', P, E, T3, struct('lect_strict', false)), 'KP.lect'));
T4 = T3; T4.LK1.per(1).red = 0.4;                                 % no changed value compared: refused, not strict either
P = N; P.KP.lect.per(1).red = 0.4;
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T4, struct('lect_strict', false)), 'KP.lect'));
G = adopt_reading('guard_c2e', E, E, T);                          % the setting not applied
verifyFalse(tc, row_ok(G, 'setting applied')); verifyFalse(tc, row_ok(G, 'rule columns, sets 1-5'));
T2 = T; T2.pols = {'rule', 'rule_esc'}; T2.RONs = T.RONs(:, 1:2);  % test.mat without rule_core
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', N, E, T2), 'test.mat rows'));
P = N; P.LBL{1} = 'x';
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', P, E, T), 'LBL'));
P = N; P.RES = P.RES(:, 1:5);
verifyFalse(tc, adopt_reading('guard_c2e', P, E, T).pass);
T3 = rmfield(T, 'LK1');
verifyFalse(tc, row_ok(adopt_reading('guard_c2e', N, E, T3), 'KP.lect'));
end

%% ---------- comparisons and files ----------
function test_compare(tc)
d = tempname(tc.TestData.tmp); mkdir(d);
f = @(n) fullfile(d, n);
write_text(f('a.txt'), sprintf('=== X ===\nGenerated: 1 | commit a\nv 1\n'));
write_text(f('b.txt'), sprintf('=== X ===\nGenerated: 2 | commit b + local changes\r\nv 1\r\n'));
write_text(f('c.txt'), sprintf('=== X ===\nGenerated: 1 | commit a\nv 2\n'));
C = adopt_reading('compare', f('a.txt'), f('b.txt')); verifyTrue(tc, C.ok, C.why);
C = adopt_reading('compare', f('a.txt'), f('c.txt')); verifyFalse(tc, C.ok); verifyTrue(tc, contains(C.why, 'line 3'));
write_text(f('a.json'), jsonencode(struct('generated', '2026-11-19 10:00:00', 'v', 1, 'k', struct('detail', {{'Generated: x', 'y'}}))));
write_text(f('b.json'), jsonencode(struct('generated', '2026-11-20 11:00:00', 'v', 1, 'k', struct('detail', {{'Generated: z', 'y'}}))));
write_text(f('c.json'), jsonencode(struct('generated', '2026-11-19 10:00:00', 'v', 2, 'k', struct('detail', {{'Generated: x', 'y'}}))));
verifyTrue(tc, adopt_reading('compare', f('a.json'), f('b.json')).ok);
verifyFalse(tc, adopt_reading('compare', f('a.json'), f('c.json')).ok);
KPI = struct('id', {1, 2}, 'detail', {{'a'}, {'b'}}); LECT = struct('x', 1); %#ok<NASGU>
save(f('a.mat'), 'KPI', 'LECT'); save(f('b.mat'), 'KPI', 'LECT');
KPI(2).detail = {'c'}; save(f('c.mat'), 'KPI', 'LECT');
verifyTrue(tc, adopt_reading('compare', f('a.mat'), f('b.mat')).ok);
C = adopt_reading('compare', f('a.mat'), f('c.mat')); verifyFalse(tc, C.ok); verifyTrue(tc, contains(C.why, 'KPI(2).detail'));
im = uint8(mod(magic(100), 256)); imwrite(im, f('a.png')); imwrite(im, f('b.png'));
im1 = im; im1(3, 3) = 255 - im1(3, 3); imwrite(im1, f('c.png'));
im2 = im; im2(1:10, 1:10) = 255 - im2(1:10, 1:10); imwrite(im2, f('d.png')); imwrite(im(1:99, :), f('e.png'));
verifyTrue(tc, adopt_reading('compare', f('a.png'), f('b.png')).ok);
r = adopt_reading('compare', f('a.png'), f('c.png')); verifyTrue(tc, r.ok); verifySubstring(tc, r.why, 'rendering: 1 pixels differ');
verifyFalse(tc, adopt_reading('compare', f('a.png'), f('d.png')).ok);
verifyFalse(tc, adopt_reading('compare', f('a.png'), f('e.png')).ok);
write_text(f('a.bin'), 'abc'); write_text(f('b.bin'), 'abc'); write_text(f('c.bin'), 'abd');
verifyTrue(tc, adopt_reading('compare', f('a.bin'), f('b.bin')).ok);
verifyFalse(tc, adopt_reading('compare', f('a.bin'), f('c.bin')).ok);
verifyFalse(tc, adopt_reading('compare', f('a.txt'), f('none.txt')).ok);
fh = @(x) x + 1; save(f('h.mat'), 'fh'); copyfile(f('h.mat'), f('h2.mat'));   %#ok<NASGU> a byte copy needs no decoding
C = adopt_reading('compare', f('h.mat'), f('h2.mat')); verifyTrue(tc, C.ok, C.why); verifyEqual(tc, C.why, 'equal (bytes)');
end

function test_write_once(tc)
d = tempname(tc.TestData.tmp); f = fullfile(d, 'sub', 'v.txt');
adopt_reading('write_once', f, {'a', 'b'});
verifyEqual(tc, fileread(f), sprintf('a\nb\n'));
verifyError(tc, @() adopt_reading('write_once', f, {'c'}), 'adopt_reading:overwrite');
verifyEqual(tc, fileread(f), sprintf('a\nb\n'));
verifyFalse(tc, isfile([f '.part']));
end

function test_code_diff(tc)
d = tempname(tc.TestData.tmp); a = fullfile(d, 'co'); b = fullfile(d, 'tree');
write_text(fullfile(a, 'code', 'decision', 'same.m'), sprintf('x = 1;\r\ny = 2;\r\n'));
write_text(fullfile(b, 'code', 'decision', 'same.m'), sprintf('x = 1;\ny = 2;\n'));          % line ends aside
write_text(fullfile(a, 'code', 'decision', 'adopt_reading.m'), 'a');
write_text(fullfile(a, 'code', 'decision', 'evaluate_policies.m'), 'new');
write_text(fullfile(b, 'code', 'decision', 'evaluate_policies.m'), 'old');
write_text(fullfile(a, 'code', 'evaluation', 'measure_all_kpis.m'), 'new');
write_text(fullfile(b, 'code', 'evaluation', 'measure_all_kpis.m'), 'old');
write_text(fullfile(a, 'code', 'tests', 'test_x.m'), 'new');
write_text(fullfile(b, 'code', 'tests', 'test_x.m'), 'old');
write_text(fullfile(b, 'code', 'gui', 'gone.m'), 'old');
D = adopt_reading('code_diff', a, b);
verifyEqual(tc, sort(D.differ), sort({'decision/adopt_reading.m', 'decision/evaluate_policies.m', 'evaluation/measure_all_kpis.m', ...
    'gui/gone.m'}));
verifyEqual(tc, sort(D.bad), sort({'evaluation/measure_all_kpis.m', 'gui/gone.m'}));
end

function test_registered_constants(tc)
% The stage's file sets match the code that writes them.
src = @(f) strrep(fileread(fullfile(tc.TestData.root, 'code', f)), char(13), '');
s = src('decision/evaluate_policies.m');
for f = {'results/policy_evaluation.txt', 'results/policy_evaluation.mat', 'results/policy_evaluation.png', 'results/policy_breakdown.png'}
    verifyTrue(tc, contains(s, f{1}), f{1});
end
verifyTrue(tc, contains(src('evaluation/measure_all_kpis.m'), 'results/kpi_summary.txt'));
verifyTrue(tc, contains(src('evaluation/measure_all_kpis.m'), 'results/kpi_summary.mat'));
verifyTrue(tc, contains(src('evaluation/build_kpi_dashboard.m'), 'results/kpi_dashboard.png'));
verifyTrue(tc, contains(src('evaluation/export_report_numbers.m'), 'results/report_numbers.json'));
verifyTrue(tc, contains(s, 'RES{si, pk} = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, 30000 + 100*si);'));
a = src('decision/adopt_reading.m');
verifyFalse(tc, contains(a, 'D124') || contains(a, 'D125'));
verifyTrue(tc, contains(a, 'K.threads = 8;'));                      % C2e's thread count
end

%% ---------- helpers ----------
function [PP, X, V, kinds, opts] = decide_cases()
[PP, X] = trace_world();
V = {PP, PP};
V{2}.esc_drop = true; V{2}.rule_dwell = 'group'; V{2}.rule_slot = false;
V{2}.rule_nb = {'power_control', 'spatial_diversity+power_control'};
kinds = {'rule', 'rule_esc', 'blind_esc', 'rule_esc', 'table_esc'};
opts = {struct(), struct(), struct(), struct('core', true), table_opt(PP)};
end

function runs = runs_of(V, kinds)
[k, v] = ndgrid(1:numel(kinds), 1:numel(V));
runs = [v(:), k(:)];
end

function e = esc_of(R)
e = cellfun(@(I) I.escalated, R.I, 'UniformOutput', false);
end

function [args, n] = rule_grid()
% Every class on and off a degraded link, separable or not, with and without quiet-slot interference
% (and strong enough to need a link-budget element after a hop) and a drop alarm, the slot branch on
% and off, with and without a noise-burst answer, before and after a hop.
cls = {'none', 'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'noise_burst', 'path_loss', 'antenna_fault', ...
    'airframe_shadowing', 'benign_interference', 'sweeping_jammer', 'unknown'};
nb = {{}, {'power_control', 'spatial_diversity+power_control'}};
args = {};
for c = cls, for dg = [false true], for gn = [0 9], for qi = [-Inf 5 40], for dr = [false true]
    for so = [true false], for b = 1:2, for cur = {'no_action', 'channel_switch'}
        args{end+1} = {c{1}, dg, gn, qi, 3, dr, budget(cur{1}), 6, so, nb{b}}; %#ok<AGROW>
    end, end, end
end, end, end, end, end
n = numel(args);
end

function b = budget(cur)
A = policy_actions(); lb = ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'});
g = 4 * contains(A, 'power_control') + 6.02 * contains(A, 'rate_reduce');
b = struct('drop_db', 7, 'current', cur, 'current_db', g(strcmp(A, cur)), 'names', {A(lb)}, 'gain_db', g(lb));
end

function PP = mon_pp()
A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
g = 4 * contains(A, 'power_control') + 6.02 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'cfg_gain_db', g, ...
    'alarm_mode', 'class_drop', 'drop_db', 4, 'confirm', [2 2], 'confirm_sweep', [2 6]);
end

function [PP, X] = trace_world()
% Four episodes, 30 cycles: a jammer, a tone, an antenna fault and a link read as none whose signal
% drops 10 dB at cycle 15, each degraded, with noisy class scores.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
NE = 4; T = 30; nC = numel(PP.classes); nF = numel(link_features('names')); nI = numel(idle_summary('names'));
rs = RandStream('mt19937ar', 'Seed', 12);
main = cellfun(@(c) find(strcmp(PP.classes, c)), {'jamming', 'tone_jamming', 'antenna_fault', 'none'});
X = struct('obs', {cell(1, T)}, 'cfg0', na * ones(1, NE));
for t = 1:T
    p = 0.2 * rand(rs, NE, nC); p(sub2ind([NE nC], 1:NE, main)) = p(sub2ind([NE nC], 1:NE, main)) + 1; p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF));
    o.feat(:, feature_index('log_ber')) = -1 + 0.5 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + 2 * randn(rs, NE, 1) - 10 * [0 0 0 t >= 15]';
    o.feat(:, feature_index('q_iot')) = 2 + 30 * rand(rs, NE, 1);
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.5;
    o.idle = nan(NE, nI); o.idle(:, 1) = 0.1 * (rand(rs, NE, 1) < 0.3);
    X.obs{t} = o;
end
end

function R = decide_run(kind, PP, X, opt)
% policy_decide.m over the cycles of X, the request fed back as the next cycle's configuration.
T = numel(X.obs); cfg = X.cfg0(:)'; NE = numel(cfg); mem = [];
R = struct('a', zeros(NE, T), 'I', {cell(1, T)});
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg(:);
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, [], opt);
    R.a(:, t) = a(:); R.I{t} = I; cfg = a(:)';
end
end

function opt = table_opt(PP)
A = PP.actions; na = find(strcmp(A, 'no_action'));
tb = find(strcmp(A, 'channel_switch')) * ones(1, numel(PP.classes)); tb(1) = na;
opt = struct('table', tb, 'table_unknown', find(strcmp(A, 'power_control')));
end

function d = parent_dir(tc, rev, rels)
% The files rels as commit rev holds them, together in one folder.
d = tempname(tc.TestData.tmp); mkdir(d);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
for k = 1:numel(rels)
    [~, nm, ext] = fileparts(rels{k});
    [st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rels{k}, fullfile(d, [nm ext])));
    assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rels{k}, out));
end
end

function fixture_off(d, fns)
if contains(path, d), rmpath(d); end
for k = 1:numel(fns), clear(fns{k}); end
end
function W = world(tc, dep)
% A finished tree and a checkout with the frozen reading in a fresh temporary folder.
w = tempname(tc.TestData.tmp); mkdir(w);
W.tag = 'tt'; W.tree = fullfile(w, 'tree'); W.co = fullfile(w, 'co');
W.rf = fullfile(W.co, 'results', 'rule_fix', W.tag); W.O = struct('root', W.co);
t = W.tree;
write_text(fullfile(t, 'results', 'a.txt'), sprintf('a\n'));
write_text(fullfile(t, 'results', 'sub', 'b.txt'), sprintf('b\n'));
write_text(fullfile(t, 'results', 'kpi_summary.txt'), sprintf('k\n'));
write_text(fullfile(t, 'results', 'policy_breakdown.png'), 'p');
x = 1; save(fullfile(t, 'results', 'policy_evaluation.mat'), 'x');
params = struct('n_rx', 3); save(fullfile(t, 'params.mat'), 'params');
write_text(fullfile(t, 'profile.json'), '{"n_rx":3}');
mkdir(fullfile(t, 'data'));
deployed = 'dqn'; save(fullfile(t, 'data', 'trained_dqn.mat'), 'deployed');
big = rand(50); save(fullfile(t, 'data', 'big.mat'), 'big');
write_text(fullfile(t, 'code', 'decision', 'x.m'), 'x = 1;');
old = java.lang.System.currentTimeMillis() - 86400000 * 3;       % an old date the copies keep
for f = {'results/a.txt', 'results/sub/b.txt', 'params.mat', 'profile.json'}
    java.io.File(fullfile(t, f{1})).setLastModified(old);
end
write_sel(W, lower(canon(t)), 'keep+st+rate');
Vs = struct('gate', struct('dep', dep, 'rr', 0.5)); save(fullfile(W.rf, 'val.mat'), 'Vs');
pols = {'rule'}; RONs = cell(5, 1); save(fullfile(W.rf, 'test.mat'), 'pols', 'RONs');
end

function write_sel(W, tr, st)
S = struct('tag', W.tag, 'tree', tr, 'adopted', st, 'step1', st, 'fingerprint', struct('tree', tr, 'code', 'c'), ...
    'deployed_off', 'dqn', 'deployed_on', 'dqn');
f = fullfile(W.rf, 'selection.json');
if isfile(f), delete(f); end
write_text(f, jsonencode(S, 'PrettyPrint', true));
end

function [N, E, T] = guard_world()
% A registered file, test.mat and the adopted file that passes every guard.
POL = {'none', 'rule', 'rule_esc', 'dqn_g1', 'rule_core', 'rule_esc_relm'};
mk = @(v) struct('scn', 1:3, 's', [1 1 2], 'r', [1 2 3], 'geom', [1 2 3], 'recovered', logical([1 0 mod(round(10 * v), 2)]), ...
    'held', logical([mod(round(10 * v), 2) 1 0]), 'recoverable', true(1, 3), 'threat', true(1, 3), 'per_post', [0.1 v 0.3], ...
    'switches', [0 1 2], 'ret', [v 1 2], 't_rec', [NaN 2 3], 'gput_post', [1 2 v], 'cfg_final', [1 2 3]);
E = struct('POL', {POL}, 'LBL', {POL}, 'set_names', {{'single', 'follower', 'combined', 'unknown', 'clean', 'comb'}}, ...
    'iDQN', 4, 'iThreat', 1:3, 'fixed_best', 2, 'tab', struct('t', 1), 'top_cfg', struct('threat', 'jamming'));
E.RES = cell(6, numel(POL));
for si = 1:6, for c = 1:numel(POL), E.RES{si, c} = mk(si + c / 10); end, end
E.ALL = arrayfun(@(c) mk(20 + c), 1:numel(POL), 'UniformOutput', false);
E.RW = arrayfun(@(c) mk(30 + c), 1:numel(POL) - 1, 'UniformOutput', false);
E.RS2 = mk(40);
E.LBC = struct('policy', 'dqn_g1', 'deployed', true, 'sets', struct('set', {'single', 'family'}, 'off', {0.5, 0.4}, ...
    'on', {0.6, 0.5}, 'rule', {0.7, 0.6}), 'clean', [1 2 3], ...
    'lines', {{'single 0.6 | rule + escalation  70.0%', 'clean 1/3'}}, 'kpi', {{'DQN 60.0% | rule + escalation 70.0%; deployed switch on'}});
E.KP = struct();
E.KP.show = {'none', 'rule_esc', 'dqn_g1'};
E.KP.per_threat = [90 70 80; 91 71 81];                          % threats x KP.show
E.KP.far = struct('policy', {'none', 'rule_esc', 'dqn_g1'}, 'k', {0, 3, 2});
E.KP.envelope_val = [95 96];
E.KP.s1g_lines = {'rule 70%'};
E.KP.lect = struct('per', struct('policy', {'rule_esc', 'rule_core'}, 'red', {0.4, 0.5}), 'gput', 17.2, 'rr', 1);
T.pols = {'rule', 'rule_esc', 'rule_core'};
T.RONs = cell(5, 3);
keep = {'scn', 's', 'r', 'geom', 'recovered', 'held', 'recoverable', 'threat', 'per_post', 'switches', 'ret', 't_rec'};
N = E;
for si = 1:5
    for pk = 1:3
        R = mk(100 + si + pk);
        R.recovered = ~E.RES{si, pk}.recovered;                   % the on rows differ from the registered ones
        o = struct(); for j = 1:numel(keep), o.(keep{j}) = R.(keep{j}); end
        T.RONs{si, pk} = o;
        c = find(strcmp(POL, T.pols{pk}));
        N.RES{si, c} = R;
    end
end
N.RES{6, 2}.ret(1) = -1; N.RES{1, 6}.ret(1) = -1;                % set 6 and a descriptive row read once
N.ALL{2} = mk(55); N.RW{3} = mk(56);                            % rule rows pooled and on the clean pools
N.LBC.sets(1).rule = 0.8; N.LBC.lines{1} = 'single 0.6 | rule + escalation  80.0%';
N.LBC.kpi{1} = 'DQN 60.0% | rule + escalation 80.0%; deployed switch on';
N.KP.per_threat(:, 2) = [75; 76]; N.KP.far(2).k = 5; N.KP.s1g_lines = {'rule 75%'};
T.LK0 = struct('per', struct('policy', {'rule_esc', 'rule_core'}, 'red', {0.4, 0.5}), 'gput', 17.2);
T.LK1 = struct('per', struct('policy', {'rule_esc', 'rule_core'}, 'red', {0.6, 0.5}), 'gput', 16);
N.KP.lect.per(1).red = 0.6; N.KP.lect.gput = 16;
end

function write_c2e(X)
% A passed ADOPT-C2e verdict recording the SHA-256 of a policy_evaluation.mat in the on root.
pe = fullfile(X.on, 'results', 'policy_evaluation.mat'); x = 1; save(pe, 'x'); %#ok<NASGU>
H = struct('file', 'results/policy_evaluation.mat', 'sha256', adopt_reading('sha', pe));
adopt_reading('write_once', X.v.c2e, {jsonencode(struct('stage', 'c2e', 'pass', true, 'outputs', H))});
end

function st = git_in(d, args)
[st, ~] = system(sprintf('git --no-optional-locks -C "%s" %s', d, args));
end

function ok = row_ok(G, name)
k = find(strcmp({G.rows.file}, name), 1);
ok = ~isempty(k) && G.rows(k).ok;
end

function n = policy_names()
n = {'none', 'random', 'fixed_mmse', 'fixed', 'rule', 'rule_esc', 'blind_esc', 'table', 'dqn_g1', 'dqn_g2', 'dqn_esc', ...
    'oracle', 'rule_sel', 'rule_core', 'blind_core', 'rule_esc_norelm', 'table_norelm', 'dqn_g2_norelm', 'rule_esc_relm', ...
    'table_relm', 'rule_esc_nos1g', 'rule_esc_s1g', 'rule_core_nos1gc', 'rule_core3'};
end

function S = tree_state(t)
% Every file under t with its size, date and SHA-256.
d = dir(fullfile(t, '**', '*')); d = d(~[d.isdir]);
f = arrayfun(@(x) fullfile(x.folder, x.name), d, 'UniformOutput', false);
[f, o] = sort(f); d = d(o);
S = struct('f', {f}, 'bytes', [d.bytes], 'date', [d.datenum], 'sha', {cellfun(@(x) adopt_reading('sha', x), f, 'UniformOutput', false)});
end

function t = mtime(f)
t = char(java.nio.file.Files.getLastModifiedTime(jp(f), javaArray('java.nio.file.LinkOption', 0)).toString());
end

function p = jp(f)
p = java.io.File(f).toPath();
end

function p = canon(p)
p = char(java.io.File(p).getCanonicalPath());
end

function add_line(f)
fileattrib(f, '+w');
fid = fopen(f, 'a'); fprintf(fid, 'moved\n'); fclose(fid);
end

function L = read_lines(f)
s = strrep(fileread(f), char(13), '');
if endsWith(s, newline), s = s(1:end-1); end
L = strsplit(s, newline, 'CollapseDelimiters', false);
end

function write_text(f, s)
d = fileparts(f); if ~isfolder(d), mkdir(d); end
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function rm_all(d)
% Writable again (the overlay's links are read-only), then removed.
if ~isfolder(d), return; end
x = dir(fullfile(d, '**', '*')); x = x(~[x.isdir]);
for k = 1:numel(x), fileattrib(fullfile(x(k).folder, x(k).name), '+w'); end
rmdir(d, 's');
end

function [missing, added] = line_diff(tc, rev, rel)
% The lines of rel at rev that this checkout's copy lacks, matched in order, and the lines it adds.
old = rev_lines(tc, rev, rel);
new = regexp(strrep(fileread(fullfile(tc.TestData.root, rel)), char(13), ''), '\n', 'split');
j = 1; missing = {}; kept = false(1, numel(new));
for i = 1:numel(old)
    k = find(strcmp(new(j:end), old{i}), 1);
    if isempty(k), missing{end+1} = old{i}; else, kept(j + k - 1) = true; j = j + k; end %#ok<AGROW>
end
added = new(~kept);
end

function tf = same_as_rev(tc, rev, rel)
% This checkout's rel is, line ends aside, the file commit rev holds.
tf = isequal(rev_lines(tc, rev, rel), regexp(strrep(fileread(fullfile(tc.TestData.root, rel)), char(13), ''), '\n', 'split'));
end

function tf = same_rev(tc, r1, r2, rel)
tf = isequal(rev_lines(tc, r1, rel), rev_lines(tc, r2, rel));
end

function L = rev_lines(tc, rev, rel)
% The lines of rel as commit rev holds it (V7_GIT_REPO names the repository of an export without .git).
d = tempname(tc.TestData.tmp); mkdir(d);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
f = fullfile(d, 'f.m');
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, f));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
L = regexp(strrep(fileread(f), char(13), ''), '\n', 'split');
end
