function tests = test_rule_fix
%TEST_RULE_FIX  The rule's layered answers (PP.rule_fix, rule_fix.m) and their side reading
%   (rule_fix_reading.m): off gives the parent commit's answers, actions and stamp bit for bit;
%   on gives the designed answers; the escalation keeps the hop; the DQN kinds do not move; the
%   test stage is refused before the selection is frozen; the registered selection on synthetic
%   readings. Synthetic traces in a temporary folder, no pools. Run from the repository root:
%   results = runtests('code/tests/test_rule_fix.m')
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
tc.TestData.base = '81ecc06';                                    % the commit this branch starts from
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

%% ---------- the option ----------
function test_parse(tc)
F = rule_fix('parse', '');
verifyFalse(tc, F.on);
F = rule_fix('parse', 'rate+st+keep');
verifyTrue(tc, F.on && F.keep && F.st && ~F.fec);
verifyEqual(tc, F.inch, 'rate'); verifyEqual(tc, F.name, 'keep+st+rate');
verifyEqual(tc, rule_fix('parse', 'fec+match').name, 'match+fec');
verifyError(tc, @() rule_fix('parse', 'keep+notch'), 'rule_fix:token');
verifyError(tc, @() rule_fix('parse', 'rate+match'), 'rule_fix:token');
verifyError(tc, @() rule_fix('parse', 'keep+keep'), 'rule_fix:token');
verifyEqual(tc, rule_fix('residual', 40), 10 * log10(1 + (1e4 - 1) * 10^(-2.8)), 'AbsTol', 1e-12);
verifyEqual(tc, rule_fix('acr'), 28);
end

function test_merge(tc)
verifyEqual(tc, rule_fix('merge', 'channel_switch', 'spatial_diversity+power_control'), 'channel_switch+spatial_diversity+power_control');
verifyEqual(tc, rule_fix('merge', 'channel_switch+spatial_diversity+power_control', 'freq_diversity+power_control+fec_interleave'), ...
    'freq_diversity+spatial_diversity+power_control+fec_interleave');
verifyEqual(tc, rule_fix('merge', 'channel_switch+rate_reduce', 'spatial_diversity+power_control'), ...
    'channel_switch+spatial_diversity+rate_reduce+power_control');
verifyEqual(tc, rule_fix('merge', 'power_control+fec_interleave', 'channel_switch+rate_reduce+power_control'), ...
    'channel_switch+rate_reduce+power_control');                  % rate_reduce with fec_interleave is no configuration
A = policy_actions(); C = decision_config();
for r = C.ladder, verifyEqual(tc, rule_fix('merge', 'no_action', r{1}), r{1}); end
in = true;
for i = 1:numel(A), for j = 1:numel(A), in = in && ismember(rule_fix('merge', A{i}, A{j}), A); end, end
verifyTrue(tc, in);                                              % every merge is one of the 36 (no pool rebuild)
end

function test_rung(tc)
A = policy_actions(); C = decision_config();
ix = @(n) find(strcmp(A, n));
lad = cellfun(ix, C.ladder);
tried = false(1, numel(A));
c = ix('channel_switch'); tried(c) = true;
j = rule_fix('rung', A, c, lad, tried);
verifyEqual(tc, A{j}, 'channel_switch+spatial_diversity+power_control');
tried(j) = true;
j2 = rule_fix('rung', A, j, lad, tried);
verifyEqual(tc, A{j2}, 'freq_diversity+spatial_diversity+power_control+fec_interleave');
lc = cellfun(ix, C.ladder_core); t2 = false(1, numel(A)); k = ix('channel_switch+rate_reduce'); t2(k) = true;
verifyEmpty(tc, rule_fix('rung', A, k, lc, t2));                % the core ladder never drops the hop
t3 = false(1, numel(A)); k = ix('channel_switch'); t3(k) = true;
verifyEqual(tc, A{rule_fix('rung', A, k, lc, t3)}, 'channel_switch+rate_reduce');
end

function test_rule_off_is_the_parent(tc)
% rule_based_policy.m with the option absent or '' gives the base commit's answers and reasons.
[args, n] = rule_grid();
new = cell(n, 2); new2 = new;
for i = 1:n
    [a, r] = rule_based_policy(args{i}{:}); new(i, :) = {a, r};
    [a, r] = rule_based_policy(args{i}{:}, ''); new2(i, :) = {a, r};
end
verifyEqual(tc, new2, new);
d = parent_copy(tc, 'code/decision/rule_based_policy.m', tc.TestData.base);
addpath(d, '-begin'); clear rule_based_policy
cl = onCleanup(@() fixture_off(d, 'rule_based_policy')); %#ok<NASGU>
verifyEqual(tc, which('rule_based_policy'), fullfile(d, 'rule_based_policy.m'));
old = cell(n, 2);
for i = 1:n, [a, r] = rule_based_policy(args{i}{:}); old(i, :) = {a, r}; end
fixture_off(d, 'rule_based_policy');
verifyEqual(tc, new, old);
end

function test_rule_on_answers(tc)
b = budget('no_action');
R = @(cls, dg, gn, qi, fx, varargin) rule_based_policy(cls, dg, gn, qi, 3, false, b, 6, true, {}, [], fx);
verifyEqual(tc, R('jamming', false, 0, 40, 'keep+st+rate'), 'channel_switch+rate_reduce');
verifyEqual(tc, R('jamming', false, 9, 40, 'keep+st+rate'), 'channel_switch+spatial_diversity+rate_reduce');
verifyEqual(tc, R('reactive_jamming', true, 0, -Inf, 'keep+st+rate'), 'channel_switch+rate_reduce');
verifyEqual(tc, R('spoofing', false, 0, 0, 'keep+st+rate'), 'channel_switch+rate_reduce');
verifyEqual(tc, R('tone_jamming', false, 0, 40, 'keep+st+rate'), 'channel_switch+spatial_diversity+rate_reduce');
verifyEqual(tc, R('tone_jamming', false, 0, 40, 'keep+st'), 'channel_switch+spatial_diversity');
verifyEqual(tc, R('tone_jamming', false, 0, 40, 'keep'), 'channel_switch');
verifyEqual(tc, R('jamming', false, 0, 40, 'keep+st'), 'channel_switch');
verifyEqual(tc, R('benign_interference', true, 0, 5, 'keep+st+rate'), 'channel_switch+rate_reduce');
verifyEqual(tc, R('benign_interference', false, 0, 5, 'keep+st+rate'), 'no_action');
verifyEqual(tc, R('none', true, 0, 5, 'keep+st+rate'), 'channel_switch+rate_reduce');      % interference in the quiet slot
verifyEqual(tc, rule_based_policy('none', true, 0, 5, 3, false, b, 6, false, {}, [], 'keep+st+rate'), ...
    'freq_diversity+power_control');                                                        % the slot branch off: untouched
verifyEqual(tc, R('unknown', true, 0, 5, 'keep+st+rate'), 'freq_diversity+power_control');
verifyEqual(tc, R('path_loss', false, 0, -Inf, 'keep+st+rate'), rule_based_policy('path_loss', false, 0, -Inf, 3, false, b, 6));
verifyEqual(tc, R('noise_burst', false, 0, 5, 'keep+st+rate'), 'power_control+fec_interleave');
verifyEqual(tc, R('antenna_fault', false, 0, -Inf, 'keep+st+rate'), 'power_control');      % fec not set
end

function test_rule_match(tc)
% The residual after a 28 dB hop against the known gains (power 4, rate 6.02, both 10.02 dB).
R = @(qi, cur) rule_based_policy('jamming', false, 0, qi, 3, false, budget(cur), 6, true, {}, [], 'keep+st+match');
verifyEqual(tc, R(40, 'no_action'), 'channel_switch+rate_reduce+power_control');    % 12.3 dB left: none covers it, the largest
verifyEqual(tc, R(30, 'no_action'), 'channel_switch+rate_reduce');                  % 4.1 dB left: rate_reduce
verifyEqual(tc, R(20, 'no_action'), 'channel_switch');                              % 0.6 dB left: below the slot alarm
verifyEqual(tc, R(5, 'channel_switch'), 'channel_switch+rate_reduce');              % after the hop: the slot reads the residual
verifyEqual(tc, R(2, 'channel_switch+rate_reduce+power_control'), 'channel_switch+rate_reduce+power_control');   % no regress
verifyEqual(tc, R(NaN, 'no_action'), 'channel_switch');
end

function test_lost_branch_fec(tc)
R = @(gn, hm, fx) rule_based_policy('antenna_fault', false, gn, -Inf, 3, false, [], 6, true, {}, hm, fx);
verifyEqual(tc, R(0, [], 'fec'), 'power_control+fec_interleave');
verifyEqual(tc, R(9, [], 'keep+st+rate+fec'), 'spatial_diversity+power_control+fec_interleave');
verifyEqual(tc, R(0, false, 'fec'), 'no_action');                                   % the lost-branch gate stands
verifyEqual(tc, rule_based_policy('airframe_shadowing', false, 0, -Inf, 3, false, [], 6, true, {}, [], 'fec'), ...
    'power_control+fec_interleave');
end

function test_core_answers(tc)
Cf = @(a, cls, fx, qi, cur, w) rule_fix('core', a, cls, fx, qi, 3, false, true, cur, w);
verifyEqual(tc, Cf('channel_switch', 'tone_jamming', 'keep+st+rate', 40, 'no_action', ''), 'channel_switch+rate_reduce');
verifyEqual(tc, Cf('channel_switch', 'jamming', 'keep+st+rate', 40, 'no_action', 'channel_switch'), 'channel_switch');   % chosen on validation
verifyEqual(tc, Cf('channel_switch', 'jamming', 'keep+st', 40, 'no_action', ''), 'channel_switch');
verifyEqual(tc, Cf('channel_switch', 'jamming', 'keep+st+match', 20, 'no_action', ''), 'channel_switch');
verifyEqual(tc, Cf('channel_switch', 'jamming', 'keep+st+match', 30, 'no_action', ''), 'channel_switch+rate_reduce');
verifyEqual(tc, Cf('rate_reduce', 'path_loss', 'keep+st+rate', 40, 'no_action', ''), 'rate_reduce');
verifyEqual(tc, Cf('channel_switch+rate_reduce', 'none', 'keep+st+rate', 0, 'no_action', ''), 'channel_switch+rate_reduce');
end

%% ---------- policy_decide.m ----------
function test_decide_off_is_the_parent(tc)
% The rule, the rule with escalation, without the detector, the core rule (with the three-state class
% too) and the table with escalation, under the plain settings and under the lost-branch gates, the
% escalation on a drop alarm, the group dwell, the release on evidence, the slot branch off and a
% noise-burst answer, with the option absent, '' and "", give the base commit's actions and info
% cycle by cycle.
[PP, X] = trace_world();
V = {PP, PP, PP};
V{2}.s1_gate = true; V{2}.esc_drop = true; V{2}.rule_dwell = 'group'; V{2}.release_m = true; V{2}.rule_slot = false;
V{2}.rule_nb = {'power_control', 'spatial_diversity+power_control'};
V{3}.s1_gate_core = true; V{3}.esc_drop = true; V{3}.core3_N = 3;
kinds = {'rule', 'rule_esc', 'blind_esc', 'rule_esc', 'table_esc', 'rule_esc'};
opts = {struct(), struct(), struct(), struct('core', true), table_opt(PP), struct('core', true, 'core3', true)};
runs = {};
for v = 1:numel(V)
    for k = 1:numel(kinds)
        if k == 6 && v ~= 3, continue; end
        runs(end+1, :) = {v, k}; %#ok<AGROW>
    end
end
Rn = cell(1, size(runs, 1)); Rf = Rn; Rs = Rn;
for r = 1:size(runs, 1)
    P = V{runs{r, 1}}; k = runs{r, 2};
    Rn{r} = decide_run(kinds{k}, P, X, opts{k});
    P.rule_fix = ''; Rf{r} = decide_run(kinds{k}, P, X, opts{k});
    P.rule_fix = ""; Rs{r} = decide_run(kinds{k}, P, X, opts{k});
end
d = parent_copy(tc, 'code/decision/policy_decide.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_decide
cl = onCleanup(@() fixture_off(d, 'policy_decide')); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, size(runs, 1)); esc = moved;
for r = 1:size(runs, 1)
    k = runs{r, 2};
    Ro = decide_run(kinds{k}, V{runs{r, 1}}, X, opts{k});
    t = sprintf('%s, settings %d', kinds{k}, runs{r, 1});
    verifyTrue(tc, isequaln(Ro, Rn{r}), [t ', field absent']);
    verifyTrue(tc, isequaln(Ro, Rf{r}), [t ', field empty']);
    verifyTrue(tc, isequaln(Ro, Rs{r}), [t ', empty string']);
    moved(r) = numel(unique(Ro.a(:))) > 2;
    esc(r) = any(cellfun(@(I) any(I.escalated), Ro.I));
end
fixture_off(d, 'policy_decide');
verifyTrue(tc, any(moved) && any(esc));                         % the traces move the configuration and escalate
end

function test_decide_keep_holds_the_hop(tc)
% A jammer on a degraded link: off, the escalation's first rung leaves the hop; with keep it never does.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
X = const_trace(PP, 30, 0, 8, 2, 'jamming', NaN, na);
Ro = decide_run('rule_esc', PP, X, struct());
P1 = PP; P1.rule_fix = 'keep';
Rk = decide_run('rule_esc', P1, X, struct());
verifyTrue(tc, drops_channel(Ro.a, A));                           % the defect the option answers
verifyFalse(tc, drops_channel(Rk.a, A));
verifyTrue(tc, any(contains(A(Rk.a), 'spatial_diversity')));     % and it escalated
P2 = PP; P2.rule_fix = 'keep+st+rate';
Rr = decide_run('rule_esc', P2, X, struct());
verifyEqual(tc, A{Rr.a(find(Rr.a ~= na, 1))}, 'channel_switch+rate_reduce');
verifyFalse(tc, drops_channel(Rr.a, A));
Xu = const_trace(PP, 30, 0, 8, 2, 'jamming', NaN, na);
Rb = decide_run('blind_esc', P1, Xu, struct());
verifyFalse(tc, drops_channel(Rb.a, A));
Rc0 = decide_run('rule_esc', PP, X, struct('core', true));
Rc1 = decide_run('rule_esc', P2, X, struct('core', true));
verifyEqual(tc, A{Rc0.a(find(Rc0.a ~= na, 1))}, 'channel_switch');
verifyEqual(tc, A{Rc1.a(find(Rc1.a ~= na, 1))}, 'channel_switch+rate_reduce');
verifyTrue(tc, all(ismember(Rc1.a(:), find(ismember(A, decision_config().core_actions)))));   % inside the core set
end

function test_dqn_unchanged(tc)
% The DQN kinds read no rule: with the option set their actions and info stay, and the trace makes
% the DQN's own escalation fire.
PP = mon_pp(); na = find(strcmp(PP.actions, 'no_action'));
X = const_trace(PP, 30, 0, 8, 2, 'jamming', NaN, na);
ag = dqn_stub(PP, find(strcmp(PP.actions, 'power_control')));
P1 = PP; P1.rule_fix = 'keep+st+match+fec';
for k = {'dqn', 'dqn_esc'}
    R0 = decide_run(k{1}, PP, X, struct(), ag);
    verifyTrue(tc, isequaln(R0, decide_run(k{1}, P1, X, struct(), ag)), k{1});
    if strcmp(k{1}, 'dqn_esc'), verifyTrue(tc, any(cellfun(@(I) any(I.escalated), R0.I)), 'the escalation fired'); end
end
end

function test_keep_on_the_drop_step(tc)
% The escalation on a drop alarm read as none takes the link-budget configuration that covers the
% drop: off it leaves the hop, with keep it keeps it. The table answers none with the hop (its
% unknown answer on a degraded link), so the step is the escalation's own.
PP = mon_pp(); PP.esc_drop = true; A = PP.actions;
cs = find(strcmp(A, 'channel_switch'));
op = struct('table', find(strcmp(A, 'no_action')) * ones(1, numel(PP.classes)), 'table_unknown', cs);
X = make_x(PP, 30, @(t) mk_obs(PP, ternary(t >= 8, 0, -6), ternary(t >= 8, 4, 20), 0, cs, 'none', NaN), cs);
Ro = decide_run('table_esc', PP, X, op);
P1 = PP; P1.rule_fix = 'keep';
Rk = decide_run('table_esc', P1, X, op);
hop = @(R) contains(A(R.a), {'channel_switch', 'freq_diversity'});
verifyFalse(tc, all(hop(Ro)));                                    % the defect: a pure link-budget configuration
verifyTrue(tc, all(hop(Rk)));
verifyTrue(tc, any(cellfun(@(I) any(I.escalated), Rk.I)));
end

function test_fec_scope(tc)
b = budget('no_action');
verifyFalse(tc, contains(rule_based_policy('antenna_fault', false, 0, -Inf, 3, true, b, 6, true, {}, false, 'fec'), ...
    'fec_interleave'));                                             % the gate withheld the class answer: the drop's answer, no code
verifyEqual(tc, rule_based_policy('antenna_fault', false, 0, -Inf, 3, true, b, 6, true, {}, [], 'fec'), ...
    'power_control+fec_interleave');                               % the class answer
verifyFalse(tc, contains(rule_based_policy('none', false, 0, -Inf, 3, true, budget('power_control'), 6, true, {}, [], 'fec'), ...
    'fec_interleave'));                                             % a drop alarm's answer or a kept configuration
end

function test_off_string_and_canonical_stamp(tc)
for v = {"", ''}
    verifyFalse(tc, rule_fix('parse', v{1}).on);
    verifyEqual(tc, rule_based_policy('jamming', false, 0, 40, 3, false, [], 6, true, {}, [], v{1}), 'channel_switch');
end
Q = struct('deployed', 'dqn', 'dec', struct('rule_mmse_db', 6));
Q1 = Q; Q1.dec.rule_fix = ""; Q2 = Q; Q2.dec.rule_fix = 'st+keep'; Q3 = Q; Q3.dec.rule_fix = 'keep+st';
verifyEqual(tc, policy_stamp(Q1), policy_stamp(Q));
verifyEqual(tc, policy_stamp(Q2), policy_stamp(Q3));
end

function test_core_wide_validated(tc)
% The core rule's class jamming keeps PP.core_wide only when PP.core_wide_valid marks it validated.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
X = const_trace(PP, 30, 0, 8, 2, 'jamming', NaN, na);
P = PP; P.rule_fix = 'keep+rate'; P.core_wide = 'channel_switch';
first = @(R) A{R.a(find(R.a ~= na, 1))};
verifyEqual(tc, first(decide_run('rule_esc', P, X, struct('core', true))), 'channel_switch+rate_reduce');
P.core_wide_valid = true;
verifyEqual(tc, first(decide_run('rule_esc', P, X, struct('core', true))), 'channel_switch');
end

function test_settings_and_stamp(tc)
verifyEqual(tc, decision_settings(struct(), struct('rule_fix', 'keep')).rule_fix, 'keep');
verifyFalse(tc, isfield(decision_settings(struct(), struct('rule_mmse_db', 3)), 'rule_fix'));
Q = struct('deployed', 'dqn', 'dec', struct('rule_mmse_db', 6, 'rule_slot', true));
Q1 = Q; Q1.dec.rule_fix = '';
Q2 = Q; Q2.dec.rule_fix = 'keep+st+rate';
verifyEqual(tc, policy_stamp(Q1), policy_stamp(Q));
verifyNotEqual(tc, policy_stamp(Q2), policy_stamp(Q));
d = parent_copy(tc, 'code/decision/policy_stamp.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_stamp
cl = onCleanup(@() fixture_off(d, 'policy_stamp')); %#ok<NASGU>
s0 = policy_stamp(Q);
fixture_off(d, 'policy_stamp');
verifyEqual(tc, policy_stamp(Q), s0);
end

%% ---------- rule_fix_reading.m ----------
function test_reading_refuses_test_before_selection(tc)
tree = fullfile(tempname, 'no_tree');                             % no inputs: any load would fail otherwise
X = rule_fix_reading('paths', tree, 'unit_guard');
verifyFalse(tc, isfile(X.sel));
verifyError(tc, @() rule_fix_reading('test', tree, 'unit_guard'), 'rule_fix_reading:guard');
verifyFalse(tc, isfile(X.marker));                                % refused before any write
verifyFalse(tc, isfolder(X.dir));
end

function test_reading_guard(tc)
% The test stage's refusals: no selection; another tree; the tree's test split read under any tag;
% changed code (any .m file of the checkout); changed inputs.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
X = rule_fix_reading('paths', d, 'unit_guard');
verifyTrue(tc, startsWith(X.claim_test, fullfile(tc.TestData.root, 'results', 'read_once')));
verifyEqual(tc, X.claim_test, rule_fix_reading('paths', d, 'another_tag').claim_test);   % one marker per tree
X.dir = d; X.sel = fullfile(d, 'selection.json'); X.marker = fullfile(d, 'test_read_started.txt');
X.claim_test = fullfile(d, 'claim_test.txt');
J = rule_fix_reading('guard', X);
verifyEqual(tc, numel(J), 1); verifyTrue(tc, contains(J{1}, 'no frozen selection'));
S = struct('adopted', 'keep+st+rate', 'fingerprint', rule_fix_reading('fingerprint', X));
write_text(X.sel, jsonencode(S));
verifyEmpty(tc, rule_fix_reading('guard', X));
write_text(X.claim_test, 'read under another tag');
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'read already')));
delete(X.claim_test);
S2 = S; S2.fingerprint.tree = 'c:\another\tree'; write_text(X.sel, jsonencode(S2));
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'another tree')));
S2 = S; S2.fingerprint.code = 'changed'; write_text(X.sel, jsonencode(S2));
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'code differs')));
S2 = S; S2.fingerprint.inputs{1} = 'other'; write_text(X.sel, jsonencode(S2));
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'inputs differ')));
end

function test_read_once_helpers(tc)
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'x', 'a.txt');
read_once('write', f, {'one', 'two'});
verifyEqual(tc, strtrim(fileread(f)), sprintf('one\ntwo'));
verifyFalse(tc, isfile([f '.tmp']));
read_once('save', fullfile(d, 'b.mat'), struct('z', 3));
verifyEqual(tc, load(fullfile(d, 'b.mat')).z, 3);
verifyEqual(tc, numel(read_once('code')), 64);
verifyEqual(tc, read_once('file', fullfile(d, 'none')), 'absent');
verifyEqual(tc, read_once('claim', 'rule_fix', 'test', d), read_once('claim', 'rule_fix', 'test', [d filesep]));
end

function test_reading_select(tc)
[T, base] = select_world();
S = rule_fix_reading('select', T);
verifyEqual(tc, S.pass, [false true false false]);
verifyEqual(tc, S.best, 2);
verifyTrue(tc, S.adopt{2}.a && S.adopt{2}.b && S.adopt{2}.c && S.adopt{2}.d && S.adopt{2}.e);
verifyFalse(tc, S.adopt{3}.b);                                    % a threat falls beyond its floor
verifyFalse(tc, S.adopt{4}.d);                                    % false alarms rise
T2 = T; T2.read = T.read([1 3 4]);
verifyEqual(tc, rule_fix_reading('select', T2).best, 1);          % none passes: the setting in force stays
T3 = T; T3.read(3) = T.read(2); T3.read(3).name = 'keep+st+match'; T3.read(3).sel.rec = T.read(2).sel.rec + 0.01;
verifyEqual(tc, rule_fix_reading('select', T3).best, 3);          % a tie in held: the higher recovered
T4 = T; T4.fam = {'antenna_fault'};
verifyFalse(tc, rule_fix_reading('select', T4).pass(2));          % no gain on the target threats
verifyEqual(tc, base, T.read(1).sel);
end

%% ---------- fixtures ----------
function test_c2e_draws(tc)
% The test reruns each tree's C2e draws: base + step x set from its own evaluate_policies.m.
d = tempname; mkdir(fullfile(d, 'code', 'decision')); c = onCleanup(@() rmdir(d, 's'));
f = fullfile(d, 'code', 'decision', 'evaluate_policies.m');
for v = {{'30000 + 100*si', [30000 100]}, {'20000 + 1000*si', [20000 1000]}}
    fid = fopen(f, 'w'); fprintf(fid, '        RES{si, pk} = policy_run_set(kind, PP, K, sets(si).spec, sets(si).split, ag, opt, %s);\n', v{1}{1}); fclose(fid);
    verifyEqual(tc, rule_fix_reading('draws', d), v{1}{2}, v{1}{1});
end
fid = fopen(f, 'w'); fprintf(fid, 'no run line\n'); fclose(fid);
verifyError(tc, @() rule_fix_reading('draws', d), 'rule_fix_reading:draws');
src = fileread(which('rule_fix_reading'));
verifyEqual(tc, numel(strfind(src, 'ag, opt, db + ds * si)')), 2, 'off and on read the same draws');
verifyEmpty(tc, strfind(src, 'R.test_seed'));
for tr = {{'C:\Users\Adi Suliman\uav-gcs-v7', [30000 100]}, {'C:\Users\Adi Suliman\uav-gcs-v7-p3', [20000 1000]}}
    if isfolder(tr{1}{1}), verifyEqual(tc, rule_fix_reading('draws', tr{1}{1}), tr{1}{2}, tr{1}{1}); end
end
end

function test_amend_guard(tc)
% The guard takes changed code only through the one recorded amendment, before the test.
src = fileread(which('rule_fix_reading'));
verifyNotEmpty(tc, strfind(src, '~strcmp(S.fingerprint.code, F.code) && ~amended(X, S.fingerprint.code, F.code)'));
verifyNotEmpty(tc, strfind(src, 'ok = strcmp(A.from, from) && strcmp(A.to, to);'));
verifyNotEmpty(tc, strfind(src, 'assert(~isfile(X.amend)'));
verifyNotEmpty(tc, strfind(src, 'assert(~isfile(X.claim_test) && ~isfile(X.marker)'));
end

function test_registered_rows(tc)
% The core rule's row is found with and without the lost-branch gates after its noise-burst answer
hd = ['Rule settings on validation, rule + escalation at ''class_drop 2/2'' (class_cusum 2/2), drop 180.0 dB^2, one coordinate' newline];
gr = ['  class_drop 3/3  drop 270.0 dB^2  rule + escalation: held 71.0%, recovered 77.4%, return 0.616, FA 11.1% | table: x' newline];
s = 'nulling at 3.00 dB, quiet slot off, dwell group, core rule on a noise burst rate_reduce';
for g = {'', ', lost-branch gate on, core rule''s lost-branch gate on'}
    tx = [hd '  core rule (rule_core, the same monitor and settings), noise-burst answer, core rule:' newline ...
        '  in force                 ' s g{1} ' | held 42.6%, recovered 47.2%, weakest x 1.4%, return 0.402, FA 240/1800' newline ...
        '  noise-burst answer:      ' strrep(s, 'rate_reduce', 'channel_switch+rate_reduce') g{1} ' | held 41.0%, recovered 46.0%, FA 250/1800' newline ...
        '  -> noise-burst answer, core rule: ' s g{1} newline gr];
    f = [tempname '.txt']; write_text(f, tx);
    T = rule_fix_reading('registered', f, struct('core_nb', 'rate_reduce'));
    delete(f);
    verifyEqual(tc, [T.core.held, T.core.rec, T.core.k], [42.6, 47.2, 240]);
    verifyEqual(tc, T.ref.alarm, 'class_drop 2/2');
    verifyEqual(tc, [T.grid.held], 71.0);
end
end

function [args, n] = rule_grid()
% Every class on and off a degraded link, separable or not, with and without quiet-slot interference
% and a drop alarm, the slot branch on and off, with and without a noise-burst answer, the harm
% argument empty, true and false.
cls = {'none', 'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'noise_burst', 'path_loss', 'antenna_fault', ...
    'airframe_shadowing', 'benign_interference', 'sweeping_jammer', 'unknown'};
nb = {{}, {'power_control', 'spatial_diversity+power_control'}};
hm = {[], true, false};
args = {};
for c = cls, for dg = [false true], for gn = [0 9], for qi = [-Inf 5], for dr = [false true]
    for so = [true false], for b = 1:2, for h = 1:3
        args{end+1} = {c{1}, dg, gn, qi, 3, dr, budget('channel_switch'), 6, so, nb{b}, hm{h}}; %#ok<AGROW>
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

function o = mk_obs(PP, lb, e, qi, link, cls, occ)
nF = numel(link_features('names')); nC = numel(PP.classes);
p = zeros(1, nC); p(find(strcmp(PP.classes, cls), 1)) = 1;
o = struct('probs', p, 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', link);
o.feat(feature_index('log_ber')) = lb;
o.feat(feature_index('sinr')) = e - (10*log10(PP.sps) - 10*log10(PP.bps));
o.feat(feature_index('q_iot')) = qi;
o.idle = nan(1, numel(idle_summary('names')));
if ~isnan(occ), o.idle(strcmp(idle_summary('names'), 'occ')) = occ; end
end

function X = const_trace(PP, T, lb, e, qi, cls, occ, cfg0)
X = make_x(PP, T, @(t) mk_obs(PP, lb, e, qi, cfg0, cls, occ), cfg0);
end

function X = make_x(~, T, f, cfg0)
X = struct('obs', {cell(1, T)}, 'cfg0', cfg0);
for t = 1:T, X.obs{t} = f(t); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function [PP, X] = trace_world()
% Four episodes, 30 cycles: a jammer, a tone, an antenna fault and a link read as none whose signal
% drops 10 dB at cycle 15, each degraded, with noisy class scores and three-state scores.
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
    o.probs3 = rand(rs, NE, 3); o.probs3 = o.probs3 ./ sum(o.probs3, 2);
    o.feat(:, feature_index('q_iot')) = 2 + 30 * rand(rs, NE, 1);
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.5;
    o.idle = nan(NE, nI); o.idle(:, 1) = 0.1 * (rand(rs, NE, 1) < 0.3);
    X.obs{t} = o;
end
end

function R = decide_run(kind, PP, X, opt, agent)
% policy_decide.m over the cycles of X, the request fed back as the next cycle's configuration.
if nargin < 4, opt = struct(); end
if nargin < 5, agent = []; end
T = numel(X.obs); cfg = X.cfg0(:)'; NE = numel(cfg); mem = [];
R = struct('a', zeros(NE, T), 'I', {cell(1, T)});
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg(:);
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, agent, opt);
    R.a(:, t) = a(:); R.I{t} = I; cfg = a(:)';
end
end

function y = drops_channel(a, A)
% Some request after the first one that leaves the channel holds no frequency element.
y = false;
for e = 1:size(a, 1)
    f = contains(A(a(e, :)), {'channel_switch', 'freq_diversity'});
    k = find(f, 1);
    if ~isempty(k) && any(~f(k:end)), y = true; end
end
end

function opt = table_opt(PP)
A = PP.actions; na = find(strcmp(A, 'no_action'));
tb = find(strcmp(A, 'channel_switch')) * ones(1, numel(PP.classes)); tb(1) = na;
opt = struct('table', tb, 'table_unknown', find(strcmp(A, 'power_control')));
end

function ag = dqn_stub(PP, hold)
nA = numel(PP.actions); nC = numel(PP.classes);
nS = policy_state_size(nA, nC);
q0 = zeros(nA, 1); q0(hold) = 1; q0(1:3) = [0.5 0.4 0.3];
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{zeros(nA, nS)}}, 'b', {{q0}}));
end

function [T, base] = select_world()
% 600 episodes (jamming, path_loss, antenna_fault; 200 each, one flight each) and 400 clean
% flights; the setting in force and three candidates: (2) jamming up, nothing else moves;
% (3) jamming up, path_loss down 10 points; (4) jamming up, 40 more clean flights with a change.
rs = RandStream('mt19937ar', 'Seed', 5);
n = 600; thr = [repmat({'jamming'}, 1, 200), repmat({'path_loss'}, 1, 200), repmat({'antenna_fault'}, 1, 200)];
y = struct('recovered', rand(rs, 1, n) < 0.7, 'recoverable', true(1, n), 'threat', true(1, n), 'cl', 1:n);
y.heldv = y.recovered & rand(rs, 1, n) < 0.9; y.sw = double(rand(rs, 1, 400) < 0.02);
y.rec = mean(y.recovered); y.held = mean(y.heldv); y.ret = 0.5;
up = @(x, m, k) setfield(setfield(x, 'recovered', x.recovered | m & (cumsum(m & ~x.recovered) <= k)), 'heldv', ...
    x.heldv | m & (cumsum(m & ~x.heldv) <= k)); %#ok<SFLD>
jam = strcmp(thr, 'jamming'); pl = strcmp(thr, 'path_loss');
x2 = up(y, jam, 40);
x3 = x2; d = find(pl & x3.recovered, 20); x3.recovered(d) = false; x3.heldv(d) = false;
x4 = x2; z = find(y.sw == 0, 40); x4.sw(z) = 1;
fin = @(x) setfield(setfield(setfield(x, 'rec', mean(x.recovered)), 'held', mean(x.heldv)), 'ret', 0.5); %#ok<SFLD>
base = y;
T = struct('read', struct('name', {'', 'keep+st', 'keep+st+rate', 'keep+st+match'}, 'sel', {y, fin(x2), fin(x3), fin(x4)}, ...
    'core', {y, y, y, y}), 'fam', {{'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'benign_interference'}}, 'thr', {thr});
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder (V7_GIT_REPO names the repository of an
% export without .git).
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function fixture_off(d, fn)
if contains(path, d), rmpath(d); end
clear(fn);
if isfolder(d), rmdir(d, 's'); end
end
