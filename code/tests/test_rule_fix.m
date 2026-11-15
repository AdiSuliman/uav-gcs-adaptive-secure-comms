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
% The rule, the rule with escalation, without the detector, the core rule and the table with
% escalation, with the option absent and '', give the base commit's actions and info cycle by cycle.
[PP, X] = trace_world();
P2 = PP; P2.rule_fix = '';
kinds = {'rule', 'rule_esc', 'blind_esc', 'rule_esc', 'table_esc'};
opts = {struct(), struct(), struct(), struct('core', true), table_opt(PP)};
Rn = cell(1, numel(kinds)); Rf = Rn;
for k = 1:numel(kinds), Rn{k} = decide_run(kinds{k}, PP, X, opts{k}); Rf{k} = decide_run(kinds{k}, P2, X, opts{k}); end
d = parent_copy(tc, 'code/decision/policy_decide.m', tc.TestData.base);
addpath(d, '-begin'); clear policy_decide
cl = onCleanup(@() fixture_off(d, 'policy_decide')); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, numel(kinds));
for k = 1:numel(kinds)
    Ro = decide_run(kinds{k}, PP, X, opts{k});
    verifyTrue(tc, isequaln(Ro, Rn{k}), sprintf('%s %d, field absent', kinds{k}, k));
    verifyTrue(tc, isequaln(Ro, Rf{k}), sprintf('%s %d, field empty', kinds{k}, k));
    moved(k) = numel(unique(Ro.a(:))) > 2;
end
fixture_off(d, 'policy_decide');
verifyTrue(tc, any(moved(2:3)));                                 % the escalation moves on the trace
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
[PP, X] = trace_world();
ag = dqn_stub(PP, find(strcmp(PP.actions, 'power_control')));
P1 = PP; P1.rule_fix = 'keep+st+match+fec';
for k = {'dqn', 'dqn_esc'}
    verifyTrue(tc, isequaln(decide_run(k{1}, PP, X, struct(), ag), decide_run(k{1}, P1, X, struct(), ag)), k{1});
end
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
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
X = rule_fix_reading('paths', d, 'unit_guard');
X.dir = d; X.sel = fullfile(d, 'selection.json'); X.marker = fullfile(d, 'test_read_started.txt');
J = rule_fix_reading('guard', X);
verifyEqual(tc, numel(J), 1); verifyTrue(tc, contains(J{1}, 'no frozen selection'));
S = struct('adopted', 'keep+st+rate', 'fingerprint', rule_fix_reading('fingerprint', X));
write_text(X.sel, jsonencode(S));
verifyEmpty(tc, rule_fix_reading('guard', X));
write_text(X.marker, 'started');
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'read already')));
delete(X.marker);
S.fingerprint.code{1} = 'changed';
write_text(X.sel, jsonencode(S));
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'code differs')));
S = struct('adopted', '', 'fingerprint', rule_fix_reading('fingerprint', X));
S.fingerprint.inputs{1} = 'other';
write_text(X.sel, jsonencode(S));
verifyTrue(tc, any(contains(rule_fix_reading('guard', X), 'inputs differ')));
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
function [args, n] = rule_grid()
cls = {'none', 'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'noise_burst', 'path_loss', 'antenna_fault', ...
    'airframe_shadowing', 'benign_interference', 'sweeping_jammer', 'unknown'};
args = {};
for c = cls, for dg = [false true], for gn = [0 9], for qi = [-Inf 5], for dr = [false true]
    args{end+1} = {c{1}, dg, gn, qi, 3, dr, budget('channel_switch'), 6, true, {}, []}; %#ok<AGROW>
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
X = struct('obs', {cell(1, T)}, 'cfg0', cfg0);
for t = 1:T, X.obs{t} = mk_obs(PP, lb, e, qi, cfg0, cls, occ); end
end

function [PP, X] = trace_world()
% Four episodes, 30 cycles: a jammer, a tone, the WLAN and an unexplained degradation with
% interference in the quiet slot, each on a degraded link with noisy class scores.
PP = mon_pp(); A = PP.actions; na = find(strcmp(A, 'no_action'));
NE = 4; T = 30; nC = numel(PP.classes); nF = numel(link_features('names')); nI = numel(idle_summary('names'));
rs = RandStream('mt19937ar', 'Seed', 12);
main = cellfun(@(c) find(strcmp(PP.classes, c)), {'jamming', 'tone_jamming', 'benign_interference', 'none'});
X = struct('obs', {cell(1, T)}, 'cfg0', na * ones(1, NE));
for t = 1:T
    p = 0.2 * rand(rs, NE, nC); p(sub2ind([NE nC], 1:NE, main)) = p(sub2ind([NE nC], 1:NE, main)) + 1; p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF));
    o.feat(:, feature_index('log_ber')) = -1 + 0.5 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + 2 * randn(rs, NE, 1);
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
