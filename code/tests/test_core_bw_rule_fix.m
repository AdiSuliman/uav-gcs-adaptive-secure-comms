function tests = test_core_bw_rule_fix
%TEST_CORE_BW_RULE_FIX  The bandwidth study's side reading of the core rule's layered answers
%   (core_bw_rule_fix_reading.m): the core projection, the guard, the test stage refused before
%   the selection, the registered conditions on synthetic readings; and, in the study's checkout
%   with docs/runs/core_bw_rule_fix_75bea00.patch (policy_decide.m knows core_blind), the core
%   rule on core-only pools: off is 75bea00's bit for bit, on answers a CW with
%   channel_switch+rate_reduce, keeps the hop and leaves the validated wideband answer alone.
%   Run from the repository root: results = runtests('code/tests/test_core_bw_rule_fix.m')
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
    'plr_fec', [0.3 0.1 0.03 0.01 0.003 0.001]); %#ok<NASGU>
save('data/policy_pools.mat', 'clean_ref');
clear('clean_ber_ref');
tc.TestData.bw = contains(fileread(which('policy_decide')), 'core_blind');   % the study's code
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
if isfolder(tc.TestData.tmp), rmdir(tc.TestData.tmp, 's'); end
end

function test_project(tc)
P = @(s) core_bw_rule_fix_reading('project', s);
verifyEqual(tc, P('keep+st+rate+fec'), 'keep+rate');
verifyEqual(tc, P('keep+st+match'), 'keep+match');
verifyEqual(tc, P('keep+st'), 'keep');
verifyEqual(tc, P('fec'), '');
verifyEqual(tc, P(''), '');
end

function test_refused_before_selection(tc)
tree = fullfile(tempname, 'no_tree');
X = core_bw_rule_fix_reading('paths', tree, 'unit_guard');
verifyError(tc, @() core_bw_rule_fix_reading('test', tree, 'unit_guard'), 'core_bw_rule_fix_reading:guard');
verifyFalse(tc, isfile(X.marker)); verifyFalse(tc, isfolder(X.dir));
verifyFalse(tc, contains(X.dir, [filesep 'core_bw' filesep]));       % never the study's own results folder
verifyNotEqual(tc, X.claim_test, X.marker);
end

function test_guard(tc)
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
X = core_bw_rule_fix_reading('paths', d, 'unit_guard');
X.dir = d; X.sel = fullfile(d, 'selection.json'); X.marker = fullfile(d, 'test_read_started.txt');
X.claim_test = fullfile(d, 'claim_test.txt');
J = core_bw_rule_fix_reading('guard', X);
verifyTrue(tc, contains(J{1}, 'no frozen selection'));
S = struct('bound', 'keep+rate', 'fingerprint', core_bw_rule_fix_reading('fingerprint', X));
write_text(X.sel, jsonencode(S));
verifyEmpty(tc, core_bw_rule_fix_reading('guard', X));
write_text(X.claim_test, 'read under another tag');
verifyTrue(tc, any(contains(core_bw_rule_fix_reading('guard', X), 'read already')));
delete(X.claim_test);
S.fingerprint.inputs{1} = 'other'; write_text(X.sel, jsonencode(S));
verifyTrue(tc, any(contains(core_bw_rule_fix_reading('guard', X), 'inputs differ')));
end

function test_adopt(tc)
[y, EP] = adopt_world();
x = y; nb = EP.narrow;
x.rule_core3.per_post(nb) = max(0, y.rule_core3.per_post(nb) - 0.2);    % the CW answered: narrowband PER falls
A = core_bw_rule_fix_reading('adopt', x, y, EP);
verifyTrue(tc, A.pass);
x2 = x; x2.rule_core3.per_post(~nb) = min(1, y.rule_core3.per_post(~nb) + 0.05);
verifyFalse(tc, core_bw_rule_fix_reading('adopt', x2, y, EP).b);
x3 = x; x3.rule_core3.false_sw(1:40) = 1;
verifyFalse(tc, core_bw_rule_fix_reading('adopt', x3, y, EP).d);
x4 = x; x4.rule_core.per_post = min(1, y.rule_core.per_post + 0.05);
verifyFalse(tc, core_bw_rule_fix_reading('adopt', x4, y, EP).e);
verifyFalse(tc, core_bw_rule_fix_reading('adopt', y, y, EP).a);          % no gain: not adopted
end

function test_core_only_pools(tc)
assumeTrue(tc, tc.TestData.bw, 'needs the study''s policy_decide.m (core-bw-p1 with the patch)');
PP = core_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
X = trace(PP, 'tone_jamming');
Ro = decide_run('rule_esc', PP, X, struct('core', true));
P1 = PP; P1.rule_fix = 'keep+rate';
Rr = decide_run('rule_esc', P1, X, struct('core', true));
verifyEqual(tc, A{Ro.a(find(Ro.a ~= na, 1))}, 'channel_switch');
verifyEqual(tc, A{Rr.a(find(Rr.a ~= na, 1))}, 'channel_switch+rate_reduce');
verifyFalse(tc, any(~contains(A(Rr.a(find(Rr.a ~= na, 1):end)), 'channel_switch')));   % the hop is kept
Xw = trace(PP, 'jamming'); Pw = P1; Pw.core_wide = 'channel_switch'; Pw.core_wide_valid = true; Pw0 = PP; Pw0.core_wide = 'channel_switch';
verifyEqual(tc, decide_run('rule_esc', Pw, Xw, struct('core', true)).a(1, 1:6), ...
    decide_run('rule_esc', Pw0, Xw, struct('core', true)).a(1, 1:6));       % the validated wideband answer stands
P2 = PP; P2.rule_fix = 'keep'; P2.core_blind = 'channel_switch+rate_reduce';
Rb = decide_run('blind_esc', P2, X, struct('core', true));
k = find(contains(A(Rb.a), 'channel_switch'), 1);
verifyTrue(tc, isempty(k) || all(contains(A(Rb.a(k:end)), 'channel_switch')));
end

function test_core_off_is_the_parent(tc)
assumeTrue(tc, tc.TestData.bw, 'needs the study''s policy_decide.m (core-bw-p1 with the patch)');
PP = core_pp(); P0 = PP; P0.rule_fix = '';
X = trace(PP, 'tone_jamming'); Xw = trace(PP, 'jamming');
kinds = {'rule_esc', 'blind_esc'};
now0 = cell(2, 2);
for k = 1:2, now0{k, 1} = decide_run(kinds{k}, PP, X, struct('core', true)); now0{k, 2} = decide_run(kinds{k}, P0, Xw, struct('core', true)); end
d = tempname; mkdir(d);
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show 75bea00:code/decision/policy_decide.m > "%s"', ...
    tc.TestData.root, fullfile(d, 'policy_decide.m')));
assertEqual(tc, st, 0, out);
addpath(d, '-begin'); clear policy_decide
cl = onCleanup(@() off(d)); %#ok<NASGU>
for k = 1:2
    verifyTrue(tc, isequaln(decide_run(kinds{k}, PP, X, struct('core', true)), now0{k, 1}), kinds{k});
    verifyTrue(tc, isequaln(decide_run(kinds{k}, PP, Xw, struct('core', true)), now0{k, 2}), kinds{k});
end
end

%% ---------- fixtures ----------
function [y, EP] = adopt_world()
rs = RandStream('mt19937ar', 'Seed', 9);
n = 800; ep = 1:n;
EP = struct('narrow', [true(1, 400), false(1, 400)], 'geom', ep);
mk = @() struct('ep', ep, 'per_post', 0.3 + 0.4 * rand(rs, 1, n), 'held', rand(rs, 1, n) < 0.7, ...
    'recovered', rand(rs, 1, n) < 0.8, 'recoverable', true(1, n), 'threat', true(1, n), 'false_sw', double(rand(rs, 1, n) < 0.01));
y = struct('rule_core3', mk(), 'rule_core', mk(), 'blind_core', mk(), 'none', mk());
end

function PP = core_pp()
C = decision_config(); A = C.core_actions;
cls = {'none', 'jamming', 'tone_jamming'};
g = 6.02 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0, 'cfg_gain_db', g, ...
    'alarm_mode', 'class_drop', 'drop_db', 4, 'confirm', [2 2], 'confirm_sweep', [2 6]);
end

function X = trace(PP, cls)
% One episode, 30 cycles: class cls with probability 1 on a degraded link, the quiet slot at 30 dB.
nF = numel(link_features('names')); nI = numel(idle_summary('names'));
p = double(strcmp(PP.classes, cls));
o = struct('probs', p, 'unknown', false, 'feat', zeros(1, nF), 'idle', nan(1, nI));
o.feat(feature_index('log_ber')) = 0; o.feat(feature_index('q_iot')) = 30;
o.feat(feature_index('sinr')) = 8 - (10*log10(PP.sps) - 10*log10(PP.bps));
X = struct('obs', {repmat({o}, 1, 30)}, 'cfg0', find(strcmp(PP.actions, 'no_action')));
end

function R = decide_run(kind, PP, X, opt)
T = numel(X.obs); cfg = X.cfg0; mem = [];
R = struct('a', zeros(1, T), 'I', {cell(1, T)});
for t = 1:T
    o = X.obs{t}; o.cfg_link = cfg;
    [a, mem, I] = policy_decide(kind, o, cfg, mem, PP, [], opt);
    R.a(t) = a; R.I{t} = I; cfg = a;
end
end

function off(d)
if contains(path, d), rmpath(d); end
clear policy_decide
if isfolder(d), rmdir(d, 's'); end
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end
