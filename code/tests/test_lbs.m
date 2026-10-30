function tests = test_lbs
%TEST_LBS  Tests of the link-budget completion (lb_complete.m and its hooks in policy_monitor.m,
%   policy_decide.m, decision_settings.m, rollout_policy.m, policy_stamp.m) and of the LB-S
%   reader (lbs_screen.m, lbs_inputs.m, lbs_boot.m, lbs_verdict.m) on synthetic data.
%   Run from the repository root: results = runtests('code/tests/test_lbs.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

%% ---------- the switch: off by default, bit-identical ----------
function test_off_runs_as_without_it(tc)
% Absent, false and empty are the same run, and an off run keeps none of the completion's
% memory, state or outputs.
[PP, A] = world('class_drop', 4);
ag = dense_agent(A, 'channel_switch', 2);
[dl, gl] = step_loss(45, 12, 10, 3);
R0 = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
for v = {false, []}
    P = PP; P.lb_complete = v{1};
    R1 = lb_trace(@policy_decide, 'dqn', P, ag, dl, gl, zeros(1, 3));
    verifyTrue(tc, isequaln(R0.a, R1.a));
    verifyTrue(tc, isequaln(R0.mem, R1.mem));
    verifyTrue(tc, isequaln(R0.info, R1.info));
end
verifyFalse(tc, any(isfield(R0.mem, {'drop_n', 'gc', 'gref', 'grp', 'grx'})));
verifyFalse(tc, isfield(R0.info{end}, 'lb'));
verifyFalse(tc, any(R0.acted));
verifyFalse(tc, any(strcmp(A(R0.a), 'channel_switch+rate_reduce+power_control')));
m = policy_monitor('init', 1, numel(A));
verifyFalse(tc, any(isfield(m, {'drop_n', 'gc', 'gref', 'grp', 'grx'})));       % no field collides with the monitor's
[~, M] = policy_monitor('update', m, lb_obs(PP, 1, 12, 0, [0 0 0], zeros(1, 3)), PP, 1);
verifyFalse(tc, isfield(M, 'dcomb'));
end

function test_off_matches_the_base_commit(tc)
% With the switch off the decision cycle equals the one of the commit this branch started
% from (d4623ed), compared output by output on traces with and without a drop alarm, for the
% DQN kinds and rule + escalation.
root = tc.TestData.root;
[s, ~] = system(sprintf('git -C "%s" cat-file -e d4623ed', root));
assumeTrue(tc, s == 0, 'git or the base commit is not available');
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() drop_base(tmp));
src = {'policy_decide', 'function [a, mem, info] = policy_decide(', 'function [a, mem, info] = policy_decide_base('; ...
    'policy_monitor', 'function [mem, M] = policy_monitor(', 'function [mem, M] = policy_monitor_base('};
for i = 1:2
    [s, txt] = system(sprintf('git -C "%s" show d4623ed:code/decision/%s.m', root, src{i, 1}));
    assumeTrue(tc, s == 0, 'the base file could not be read from git');
    txt = strrep(txt, src{i, 2}, src{i, 3});
    if i == 1, txt = strrep(txt, 'policy_monitor(', 'policy_monitor_base('); end
    fid = fopen(fullfile(tmp, [src{i, 1} '_base.m']), 'w'); fwrite(fid, txt); fclose(fid);
end
addpath(tmp); clear policy_decide_base policy_monitor_base
[PP, A] = world('class_drop', 4);
ag = dense_agent(A, 'channel_switch', 2);
[dl1, gl1] = step_loss(45, 12, 10, 3);
[dl2, gl2] = step_loss(30, 30, 0, 3);
for k = {'dqn', 'dqn_esc', 'rule_esc'}
    for w = 1:2
        dl = dl1; gl = gl1; if w == 2, dl = dl2; gl = gl2; end
        for sw = {'absent', 'false'}
            P = PP; if strcmp(sw{1}, 'false'), P.lb_complete = false; end
            R0 = lb_trace(@policy_decide_base, k{1}, P, ag, dl, gl, zeros(1, 3));
            R1 = lb_trace(@policy_decide, k{1}, P, ag, dl, gl, zeros(1, 3));
            msg = sprintf('%s, trace %d, switch %s', k{1}, w, sw{1});
            verifyTrue(tc, isequaln(R0.a, R1.a), msg);
            verifyTrue(tc, isequaln(R0.mem, R1.mem), msg);
            verifyTrue(tc, isequaln(R0.info, R1.info), msg);
        end
    end
end
end

function drop_base(tmp)
rmpath(tmp); clear policy_decide_base policy_monitor_base rollout_policy_base
try, rmdir(tmp, 's'); catch, end
end

function test_rollout_off_matches_the_base_commit(tc)
% rollout_policy.m with the switch off (absent or false) returns what the file of the base
% commit returns, on a toy world, for a rule kind and a DQN kind; with it on the same fields
% plus lb, which counts nothing where the pools hold no antenna gains.
root = tc.TestData.root;
[s, ~] = system(sprintf('git -C "%s" cat-file -e d4623ed', root));
assumeTrue(tc, s == 0, 'git or the base commit is not available');
[s, txt] = system(sprintf('git -C "%s" show d4623ed:code/decision/rollout_policy.m', root));
assumeTrue(tc, s == 0, 'the base file could not be read from git');
txt = strrep(txt, 'function R = rollout_policy(', 'function R = rollout_policy_base(');
verifyTrue(tc, contains(txt, 'function R = rollout_policy_base('));
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() drop_base(tmp));
fid = fopen(fullfile(tmp, 'rollout_policy_base.m'), 'w'); fwrite(fid, txt); fclose(fid);
addpath(tmp); clear rollout_policy_base
[PP, K] = toy_world();
ag = dense_agent(PP.actions, 'channel_switch', 2);
spec = struct('scn', [2 2], 's', [1 1], 'onset', [3 3], 'follow', false(1, 2), 'fdelay', [0 0], 'unk', false(1, 2), ...
    'T', 30, 'r', [1 1]);
for k = {'rule_esc', 'dqn_esc'}
    R0 = rollout_policy_base(k{1}, PP, K, spec, 1, ag, struct(), 4);
    verifyFalse(tc, isfield(R0, 'lb'));
    verifyTrue(tc, isequaln(R0, rollout_policy(k{1}, PP, K, spec, 1, ag, struct(), 4)), k{1});
    P = PP; P.lb_complete = false;
    verifyTrue(tc, isequaln(R0, rollout_policy(k{1}, P, K, spec, 1, ag, struct(), 4)), k{1});
    P.lb_complete = true;
    R1 = rollout_policy(k{1}, P, K, spec, 1, ag, struct(), 4);
    verifyEqual(tc, R1.lb, zeros(1, 2), k{1});
    verifyTrue(tc, isequaln(R0, rmfield(R1, 'lb')), k{1});
end
end

function test_rollout_counts_the_completion_only_when_it_ran(tc)
% rollout_policy.m writes R.lb once, from the decision cycle's info.lb only, and only when the
% decision cycle reported it (static; the parity run is test_rollout_off_matches_the_base_commit).
code = regexprep(fileread(which('rollout_policy')), '%[^\n]*', '');
verifyNumElements(tc, regexp(code, '\<R\.lb\>', 'match'), 1);
verifyNotEmpty(tc, strfind(code, 'if isfield(dinf, ''lb'')'));
verifyNotEmpty(tc, strfind(code, 'if ~isempty(lb_n), R.lb = lb_n; end'));
end

function test_switch_is_stored_with_the_agent(tc)
% decision_settings.m carries the switch like the other decision-time settings, and
% policy_stamp.m follows it only when it is on.
PP = struct('alarm_mode', 'class', 'confirm', [2 2], 'drop_db', 4, 'maha_thr', -1);
verifyTrue(tc, decision_settings(PP, struct('lb_complete', true)).lb_complete);
verifyTrue(tc, decision_settings(PP, struct('dec', struct('lb_complete', true))).lb_complete);
X = decision_settings(PP, struct('esc_drop', true));
verifyFalse(tc, isfield(X, 'lb_complete'));
verifyFalse(tc, lb_complete('on', X));
verifyFalse(tc, lb_complete('on', struct('lb_complete', [])));
verifyFalse(tc, lb_complete('on', struct('lb_complete', false)));
verifyTrue(tc, lb_complete('on', struct('lb_complete', true)));
mk = @(d) struct('deployed', 'dqn_esc', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', d);
s0 = policy_stamp(mk(struct('esc_drop', true)));
verifyEqual(tc, policy_stamp(mk(struct('esc_drop', true, 'lb_complete', false))), s0);
verifyEqual(tc, policy_stamp(mk(struct('esc_drop', true, 'lb_complete', []))), s0);
verifyNotEqual(tc, policy_stamp(mk(struct('esc_drop', true, 'lb_complete', true))), s0);
end

%% ---------- the completion on synthetic traces ----------
function test_common_mode_step_10db(tc)
% A 10 dB common-mode loss: the completion adds rate_reduce + power_control (the largest
% link-budget configuration, 9 dB, covers less than the deficit) and keeps the DQN's
% channel_switch; the deficit is the 10 dB.
[PP, A] = world('class_drop', 4);
ag = dense_agent(A, 'channel_switch', 2);
[dl, gl] = step_loss(45, 12, 10, 3);
PP.lb_complete = true;
R = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
k = find(R.acted, 1);
verifyNotEmpty(tc, k);
verifyEqual(tc, A{R.a(k)}, 'channel_switch+rate_reduce+power_control');
verifyTrue(tc, all(R.dn(k-2:k) >= 3));
[dc, dn] = mon_run(PP, dl, gl, zeros(1, 3));
verifyEqual(tc, dc(end), 10, 'AbsTol', 1e-9);
verifyGreaterThanOrEqual(tc, dn(end), 3);
verifyEqual(tc, dc(1:12), zeros(1, 12), 'AbsTol', 1e-9);                         % nothing before the step
PP.lb_complete = false;
R0 = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
verifyEqual(tc, unique(A(R0.a(R0.a ~= find(strcmp(A, 'no_action'))))), {'channel_switch'});   % the DQN alone
% with the escalation of the DQN kinds
PP.lb_complete = true;
R2 = lb_trace(@policy_decide, 'dqn_esc', PP, ag, dl, gl, zeros(1, 3));
k = find(R2.acted, 1);
verifyNotEmpty(tc, k);
verifyTrue(tc, contains(A{R2.a(k)}, 'channel_switch') && contains(A{R2.a(k)}, 'power_control'));
end

function test_common_mode_step_6db_and_units(tc)
% A 6 dB common-mode loss, the smallest decision level, is acted on, with the median-window
% alarm (threshold in dB) and with the CUSUM alarm, whose threshold is in dB^2 (153 here): the
% completion's own threshold is read in dB and never from the monitor's.
for md = {{'class_drop', 4}, {'class_cusum', 153}}
    [PP, A] = world(md{1}{1}, md{1}{2});
    PP.lb_complete = true;
    ag = dense_agent(A, 'channel_switch', 2);
    [dl, gl] = step_loss(45, 12, 6, 3);
    R = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
    k = find(R.acted, 1);
    verifyNotEmpty(tc, k, md{1}{1});
    verifyTrue(tc, any(strcmp(A{R.a(k)}, {'channel_switch+power_control', 'channel_switch+rate_reduce+power_control'})), md{1}{1});
    [dc, dn] = mon_run(PP, dl, gl, zeros(1, 3));
    verifyEqual(tc, dc(end), 6, 'AbsTol', 1e-9);
    verifyGreaterThanOrEqual(tc, dn(end), 3, md{1}{1});
end
code = regexprep(fileread(which('lb_complete')), '%[^\n]*', '');
verifyNumElements(tc, strfind(code, 'drop_db'), 1);                               % only the rule's budget field of that name
verifyNotEmpty(tc, strfind(code, 'struct(''drop_db'', dc(i)'));
verifyEmpty(tc, strfind(code, 'PP.drop_db'));
end

function test_single_precision_gains_keep_the_memory_double(tc)
% The pools carry the antennas' gains in single precision: the completion's window and
% reference stay double, and the deficit is the double one.
[PP, A] = world('class_drop', 4);
PP.lb_complete = true;
na = find(strcmp(A, 'no_action'));
[dl, gl] = step_loss(30, 12, 10, 3);
m1 = policy_monitor('init', 1, numel(A)); m2 = m1;
for t = 1:numel(dl)
    o = lb_obs(PP, na, 12, dl(t), gl(t, :), zeros(1, 3));
    [m1, M1] = policy_monitor('update', m1, o, PP, na); m1 = policy_monitor('change', m1, false);
    o.gant = single(o.gant);
    [m2, M2] = policy_monitor('update', m2, o, PP, na); m2 = policy_monitor('change', m2, false);
end
verifyClass(tc, M2.dcomb, 'double');
verifyClass(tc, m2.gc, 'double');
verifyClass(tc, m2.gref, 'double');
verifyEqual(tc, M2.dcomb, M1.dcomb, 'AbsTol', 1e-5);
end

function test_single_branch_loss_is_below_the_threshold(tc)
% One branch lost by 31 dB on equal branches costs 10 log10(n) - 10 log10(n - 1 + 10^-3.1)
% of the combined gain: 1.76 dB on 3 antennas, 1.25 dB on 4, below the 3 dB threshold. The
% monitor's own drop alarm (the reference antenna's level falls 6 dB) is confirmed, and the
% completion stays out.
for n = [3 4]
    [PP, A] = world('class_drop', 4);
    PP.lb_complete = true;
    ag = dense_agent(A, 'channel_switch', 2);
    T = 45; dl = [zeros(12, 1); 6 * ones(T - 12, 1)];
    gl = zeros(T, n); gl(13:end, 1) = 31;
    want = 10*log10(n) - 10*log10(n - 1 + 10^-3.1);
    [dc, dn] = mon_run(PP, dl, gl, zeros(1, n));
    verifyEqual(tc, dc(end), want, 'AbsTol', 1e-9);
    w = [1.76 1.25];
    verifyEqual(tc, round(want, 2), w(n - 2));
    verifyGreaterThanOrEqual(tc, dn(end), 3);                                      % the alarm is confirmed
    R = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, n));
    verifyFalse(tc, any(R.acted));
    verifyFalse(tc, any(contains(A(R.a), 'power_control') | contains(A(R.a), 'rate_reduce')));
end
end

function test_clean_roll_in(tc)
% A banking turn hides one antenna gradually (25 dB over 8 cycles) while the reference
% antenna's level falls 10 dB: the drop alarm is confirmed for many cycles, the combined
% deficit stays below 2 dB, and the completion never acts.
[PP, A] = world('class_drop', 4);
PP.lb_complete = true;
ag = dense_agent(A, 'channel_switch', 2);
T = 45; r = min((0:T-13)' / 8, 1);
dl = [zeros(12, 1); 10 * r]; gl = zeros(T, 3); gl(13:end, 1) = 25 * r;
R = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
[dc, dn] = mon_run(PP, dl, gl, zeros(1, 3));
verifyGreaterThanOrEqual(tc, max(dn), 3);
verifyLessThan(tc, max(dc), 2);
verifyFalse(tc, any(R.acted));
end

function test_fec_interleave_is_left_alone(tc)
% A proposal that holds fec_interleave is not completed, however large the deficit.
[PP, A] = world('class_drop', 4);
PP.lb_complete = true;
for p = {'power_control+fec_interleave', 'freq_diversity+fec_interleave', 'channel_switch+spatial_diversity+fec_interleave'}
    ag = dense_agent(A, p{1}, 2);
    [dl, gl] = step_loss(45, 12, 10, 3);
    R = lb_trace(@policy_decide, 'dqn', PP, ag, dl, gl, zeros(1, 3));
    verifyFalse(tc, any(R.acted), p{1});
    verifyTrue(tc, all(ismember(A(R.a), {'no_action', p{1}})), p{1});
    verifyGreaterThanOrEqual(tc, max(R.dn), 3, p{1});
    [a, acted] = apply_direct(PP, {p{1}}, 20);
    verifyEqual(tc, A{a}, p{1}); verifyFalse(tc, acted);
end
end

%% ---------- the rule of the completion, called directly ----------
function test_parity_with_the_rules_budget_match(tc)
% The link-budget factor the completion sets is the rule's (rule_based_policy.m, the class
% path_loss with a budget): the smallest link-budget configuration whose known gain covers
% the deficit, the largest when none does; the frequency and space factors stay.
[PP, A] = world('class_drop', 4);
g = PP.cfg_gain_db; lbi = find(ismember(A, {'power_control', 'rate_reduce', 'rate_reduce+power_control'}));
props = {'no_action', 'channel_switch', 'spatial_diversity', 'freq_diversity+spatial_diversity', 'rate_reduce', ...
    'channel_switch+rate_reduce', 'power_control'};
for dc = [3.01 3.5 5 6.5 8.5 9.5 12 22]
    for i = 1:numel(props)
        ip = find(strcmp(A, props{i}));
        [a, acted] = apply_direct(PP, props(i), dc);
        if g(ip) >= dc
            verifyEqual(tc, a, ip); verifyFalse(tc, acted); continue
        end
        bud = struct('drop_db', dc, 'current', props{i}, 'current_db', g(ip), 'names', {A(lbi)}, 'gain_db', g(lbi));
        want = rule_based_policy('path_loss', false, 0, -Inf, NaN, false, bud);
        k = find(sort(g(lbi)) >= dc, 1); if isempty(k), k = numel(lbi); end
        s = sort(g(lbi));
        own = A(lbi(g(lbi) == s(k)));
        verifyEqual(tc, want, own{1});                                   % the rule's match is the smallest covering, else the largest
        p = strsplit(props{i}, '+'); p = p(ismember(p, {'channel_switch', 'freq_diversity', 'spatial_diversity'}));
        verifyEqual(tc, A{a}, strjoin([p, {want}], '+'));
        verifyEqual(tc, acted, a ~= ip);
    end
end
end

function test_every_gate_blocks(tc)
% The completion acts only with the confirmed drop alarm held for C.esc cycles, C.hold cycles
% since the last change, no change pending, a deficit of at least 3 dB (half the smallest
% path-loss level), a proposal whose known gain is below the deficit, and the shield's consent.
C = decision_config();
[PP, A] = world('class_drop', 4);
ref = find(strcmp(A, 'channel_switch+rate_reduce+power_control'));
cs = find(strcmp(A, 'channel_switch'));
[a, acted] = apply_direct(PP, {'channel_switch'}, 10);
verifyEqual(tc, a, ref); verifyTrue(tc, acted);
blocked = {'drop_n', (C.esc - 1); 'since', (C.hold - 1); 'pend', true; 'confirmed', false};
for i = 1:size(blocked, 1)                                                              % the shield also holds the last two
    [a, acted] = apply_direct(PP, {'channel_switch'}, 10, blocked{i, :});
    verifyEqual(tc, a, cs, blocked{i, 1}); verifyFalse(tc, acted, blocked{i, 1});
end
[a, acted] = apply_direct(PP, {'channel_switch'}, 10, 'since', C.hold - 1, 'cfg', ref);  % the shield allows the target: the hold term alone blocks
verifyEqual(tc, a, cs); verifyFalse(tc, acted);
[a, acted] = apply_direct(PP, {'channel_switch'}, 10, 'since', C.hold, 'cfg', ref);
verifyEqual(tc, a, ref); verifyTrue(tc, acted);
for dc = [NaN 2.99 0 -5]
    [a, acted] = apply_direct(PP, {'channel_switch'}, dc);
    verifyEqual(tc, a, cs); verifyFalse(tc, acted);
end
[a, acted] = apply_direct(PP, {'channel_switch+rate_reduce+power_control'}, 8);          % its 9 dB cover the deficit
verifyEqual(tc, a, ref); verifyFalse(tc, acted);
[a, acted] = apply_direct(PP, {'channel_switch+rate_reduce+power_control'}, 12);         % covered by nothing: the same largest
verifyEqual(tc, a, ref); verifyFalse(tc, acted);
% episodes are independent
[a, acted] = apply_direct(PP, {'channel_switch', 'channel_switch', 'no_action', 'channel_switch'}, [10 10 5 10], ...
    'drop_n', [5 1 5 5], 'since', [10 10 10 1]);
verifyEqual(tc, acted, [true false true false]);
verifyEqual(tc, A(a), {'channel_switch+rate_reduce+power_control', 'channel_switch', 'power_control', 'channel_switch'});
end

function test_drop_counter_counts_consecutive_confirmed_alarm_cycles(tc)
% mem.drop_n counts the consecutive cycles of a confirmed drop alarm: an alarm without its
% confirmation, or a confirmation without the drop alarm, starts the count again.
A = policy_actions();
mem = policy_monitor('init', 1, numel(A));
conf = [1 1 1 0 1 1 1 0]; alarm = [1 1 0 1 1 1 1 0];
dn = zeros(1, numel(conf));
for t = 1:numel(conf)
    M = struct('confirmed', logical(conf(t)), 'drop_alarm', logical(alarm(t)));
    mem = lb_complete('track', mem, struct('gant', zeros(1, 3)), 0, true, [], M);
    dn(t) = mem.drop_n;
end
verifyEqual(tc, dn, [1 2 0 0 1 2 3 0]);
end

function test_reads_receiver_measurements_only(tc)
% No class, no truth field: the references to the monitor's outputs, the observation and the
% settings in lb_complete.m are the ones the rule lists.
src = fileread(which('lb_complete'));
code = regexprep(src, '%[^\n]*', '');
t = regexp(code, '\<(M|obs|mem|PP|C)\.(\w+)', 'tokens');
allowed = struct('M', {{'dcomb', 'confirmed', 'drop_alarm'}}, 'obs', {{'gant'}}, ...
    'mem', {{'since', 'pend', 'drop_n', 'gc', 'gref', 'grp', 'grx', 'ebno', 'ref'}}, ...
    'PP', {{'actions', 'lb_complete'}}, 'C', {{'esc', 'hold', 'sev'}});
for i = 1:numel(t)
    verifyTrue(tc, ismember(t{i}{2}, allowed.(t{i}{1})), [t{i}{1} '.' t{i}{2}]);
end
verifyGreaterThan(tc, numel(t), 10);
verifyFalse(tc, contains(code, {'.cls', 'probs', '.scn', 'truth', 'K.on', 'maha'}));
end

function test_single_writer_per_field(tc)
% Each new monitor field has one writer: code outside lb_complete.m (comments aside) never
% mentions it, and the decision function of lb_complete.m only reads memory. dcomb is written
% once, by the monitor.
root = tc.TestData.root;
f = dir(fullfile(root, 'code', '**', '*.m'));
f = f(~contains({f.folder}, [filesep 'legacy']) & ~contains({f.folder}, [filesep 'tests']) & ~strcmp({f.name}, 'lb_complete.m'));
n = 0; nd = 0;
for i = 1:numel(f)
    code = regexprep(fileread(fullfile(f(i).folder, f(i).name)), '%[^\n]*', '');
    verifyEmpty(tc, regexp(code, 'mem\.(drop_n|gc|gref|grp|grx)\>', 'once'), f(i).name);
    nd = nd + numel(regexp(code, 'M\.dcomb\s*\]?\s*=[^=]', 'match'));
    if strcmp(f(i).name, 'policy_monitor.m'), n = numel(regexp(code, 'M\.dcomb\s*\]\s*=[^=]', 'match')); end
end
verifyEqual(tc, n, 1);
verifyEqual(tc, nd, 1);
src = fileread(which('lb_complete'));
i = strfind(src, 'function [a, acted] = apply(');
verifyNumElements(tc, i, 1);
verifyEmpty(tc, regexp(src(i:end), 'mem\.\w+(\([^)]*\))?\s*=[^=]', 'once'));
end

%% ---------- the LB-S reader ----------
function test_verdict_go_rule(tc)
mk = @(pl, lo, o) struct('threat', [{'path_loss'}, arrayfun(@(k) sprintf('t%d', k), 1:numel(o), 'UniformOutput', false)], ...
    'd', num2cell([pl, o]), 'lo', num2cell([lo, zeros(1, numel(o))]));
V = lbs_verdict(mk(55, 40, [0.5 -1.9 3]), struct('d', 0.4));
verifyTrue(tc, V.go); verifyEqual(tc, V.g, [true true true]);
verifyEqual(tc, V.worst_threat, 't2'); verifyEqual(tc, V.worst, -1.9);
verifyEqual(tc, V.lines{end}, 'LB-S verdict: GO');
verifyTrue(tc, lbs_verdict(mk(20, 10, [0 0]), struct('d', 1.0)).go);                      % each threshold met exactly
verifyFalse(tc, lbs_verdict(mk(19.9, 15, [0 0]), struct('d', 0)).g(1));                    % too small a gain
verifyFalse(tc, lbs_verdict(mk(40, 9.9, [0 0]), struct('d', 0)).g(1));                     % bound below 10
verifyFalse(tc, lbs_verdict(mk(40, 20, [0 -2.1]), struct('d', 0)).g(2));                   % another threat loses more than 2
verifyTrue(tc, lbs_verdict(mk(40, 20, [0 -2.0]), struct('d', 0)).g(2));
verifyFalse(tc, lbs_verdict(mk(40, 20, [0 0]), struct('d', 1.01)).g(3));                   % clean false changes up more than 1
verifyFalse(tc, lbs_verdict(mk(40, NaN, [0 0]), struct('d', 0)).go);                       % an unmeasured bound is no go
verifyFalse(tc, lbs_verdict(mk(40, 20, [0 NaN]), struct('d', 0)).go);
verifyFalse(tc, lbs_verdict(mk(40, 20, [0 0]), struct('d', NaN)).go);
verifyEqual(tc, lbs_verdict(mk(5, 1, [0 0]), struct('d', 0)).lines{end}, 'LB-S verdict: NO-GO');
verifyError(tc, @() lbs_verdict(struct('threat', {'a', 'b'}, 'd', {1, 2}, 'lo', {1, 2}), struct('d', 0)), 'lbs_verdict:path_loss');
end

function test_boot_is_seeded_clustered_and_one_sided(tc)
rs = RandStream('mt19937ar', 'Seed', 5);
cl = repelem(1:40, 5);
d = repelem(double(rand(rs, 1, 40) < 0.7) - double(rand(rs, 1, 40) < 0.3), 5);
[m, lo, hi] = lbs_boot(d, cl, 2000, 7);
verifyEqual(tc, m, mean(d), 'AbsTol', 1e-12);
verifyLessThanOrEqual(tc, lo, m); verifyGreaterThanOrEqual(tc, hi, m);
[m2, lo2, hi2] = lbs_boot(d, cl, 2000, 7);
verifyEqual(tc, [m lo hi], [m2 lo2 hi2]);                                  % the same stream
[~, l95, h95] = boot_cluster(d, ones(size(d)), cl, 2000, 7);               % the same resamples, two-sided
verifyGreaterThanOrEqual(tc, lo, l95); verifyLessThanOrEqual(tc, hi, h95);
[m3, lo3, hi3] = lbs_boot(ones(1, 20), repelem(1:4, 5), 500, 1);
verifyEqual(tc, [m3 lo3 hi3], [1 1 1]);
[m4, lo4, hi4] = lbs_boot([1 1 1 1], [1 1 1 1], 500, 1);                   % one cluster: no interval
verifyEqual(tc, m4, 1); verifyTrue(tc, isnan(lo4) && isnan(hi4));
[m5, lo5, hi5] = lbs_boot([], [], 500, 1);
verifyTrue(tc, isnan(m5) && isnan(lo5) && isnan(hi5));
end

function test_inputs_copy_and_verify(tc)
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmdir_quiet(tmp));
src = fullfile(tmp, 'src'); dst = fullfile(tmp, 'dst'); mkdir(src);
names = {'policy_pools.mat', 'unknown_threat_agents.mat', 'trained_dqn.mat', 'clean_val_pools.mat'};
for i = 1:numel(names)
    fid = fopen(fullfile(src, names{i}), 'w'); fwrite(fid, uint8(mod((1:5000) * i, 251))); fclose(fid);
end
fid = fopen(fullfile(tmp, 'abc.txt'), 'w'); fwrite(fid, 'abc'); fclose(fid);
verifyEqual(tc, lbs_inputs('hash', fullfile(tmp, 'abc.txt')), ...
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
n0 = numel(dir(src));
c = lbs_inputs('copy', src, dst);
verifyEqual(tc, c.files, names);
verifyNumElements(tc, dir(src), n0);                                       % the source is only read
for i = 1:numel(names)
    verifyEqual(tc, c.sha256{i}, lbs_inputs('hash', fullfile(src, names{i})));
    verifyEqual(tc, c.sha256{i}, lbs_inputs('hash', fullfile(dst, names{i})));
end
m = regexp(fileread(fullfile(dst, 'lbs_inputs.sha256')), '[0-9a-f]{64}  \S+', 'match');
verifyNumElements(tc, m, 4);                                               % sha256sum -c format
v = lbs_inputs('verify', dst);
verifyEqual(tc, v.sha256, c.sha256);
verifyError(tc, @() lbs_inputs('copy', src, src), 'lbs_inputs:same');
verifyError(tc, @() lbs_inputs('copy', fullfile(tmp, 'none'), dst), 'lbs_inputs:source');
f = fullfile(dst, 'trained_dqn.mat');                                      % a changed byte is found
fid = fopen(f, 'r+'); b = fread(fid, 1, '*uint8'); fseek(fid, 0, 'bof'); fwrite(fid, uint8(bitxor(b, 255))); fclose(fid);
verifyError(tc, @() lbs_inputs('verify', dst), 'lbs_inputs:hash');
end

function test_inputs_copy_never_overwrites_a_different_file(tc)
% A file of the destination with another hash stops the copy before anything is written; the
% source's own copy already there is kept and the copy completes.
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmdir_quiet(tmp));
src = fullfile(tmp, 'src'); dst = fullfile(tmp, 'dst'); mkdir(src); mkdir(dst);
make_inputs(src);
f = fullfile(dst, 'trained_dqn.mat');
put_text(f, 'another file');
h0 = lbs_inputs('hash', f);
verifyError(tc, @() lbs_inputs('copy', src, dst), 'lbs_inputs:exists');
verifyEqual(tc, lbs_inputs('hash', f), h0);                                % untouched
verifyFalse(tc, isfile(fullfile(dst, 'policy_pools.mat')));                % nothing else was written
verifyFalse(tc, isfile(fullfile(dst, 'lbs_inputs.sha256')));
delete(f); copyfile(fullfile(src, 'trained_dqn.mat'), f);
c = lbs_inputs('copy', src, dst);
v = lbs_inputs('verify', dst);
verifyEqual(tc, v.sha256, c.sha256);
verifyEqual(tc, c.sha256{3}, lbs_inputs('hash', fullfile(src, 'trained_dqn.mat')));
end

function test_clean_reference_must_be_finite(tc)
% A folder without data/policy_pools.mat reads NaN and every cycle then reads as degraded; the
% check stops it, and stops a table with a gap.
tmp = tempname; mkdir(tmp);
cwd = pwd; cl = onCleanup(@() back(cwd, tmp));
cd(tmp);
ebno = [0 4 8 12];
verifyError(tc, @() lbs_inputs('clean_ref', ebno), 'lbs_inputs:clean_ref');           % no file
mkdir('data');
cr = struct('ebno', [0 5 10 15], 'ber', [1e-2 1e-3 1e-4 1e-5], 'ber_est', [1e-2 1e-3 1e-4 1e-5], 'plr_fec', [0.5 0.1 0.01 0.001]);
clean_ref = cr; save(fullfile('data', 'policy_pools.mat'), 'clean_ref');
r = lbs_inputs('clean_ref', ebno);
verifyTrue(tc, r.plr_fec);
verifyTrue(tc, all(r.ber > 0) && all(isfinite(r.ber_est)));
cr.ber_est(2) = NaN; clean_ref = cr; save(fullfile('data', 'policy_pools.mat'), 'clean_ref');
verifyError(tc, @() lbs_inputs('clean_ref', ebno), 'lbs_inputs:clean_ref');           % a gap in the table
cr.ber_est(2) = 1e-3; cr = rmfield(cr, 'plr_fec'); clean_ref = cr; save(fullfile('data', 'policy_pools.mat'), 'clean_ref');
r = lbs_inputs('clean_ref', ebno);
verifyFalse(tc, r.plr_fec);                                                          % absent: the monitor reads 0
end

function test_screen_refuses_to_start_unregistered_or_in_the_source(tc)
verifyError(tc, @() lbs_screen(pwd), 'lbs_screen:registration');
verifyError(tc, @() lbs_screen(pwd, 'registered_by', 'XYZ'), 'lbs_screen:registration');
verifyError(tc, @() lbs_screen(pwd, 'registered_by', 'abcdef1'), 'lbs_screen:folder');
end

function test_screen_runs_only_from_the_folder_that_holds_the_code(tc)
% It writes data/ and results/ in the current folder: from any other folder it stops before
% anything is written there.
tmp = tempname; mkdir(tmp);
cwd = pwd; cl = onCleanup(@() back(cwd, tmp));
cd(tmp);
verifyError(tc, @() lbs_screen(tc.TestData.root, 'registered_by', 'abcdef1'), 'lbs_screen:folder');
verifyEmpty(tc, setdiff({dir(tmp).name}, {'.', '..'}));
end

function test_screen_stops_unless_the_docs_repository_registers_the_hash(tc)
tmp = tempname; mkdir(tmp);
cwd = pwd; cl = onCleanup(@() back(cwd, tmp));
cd(tc.TestData.root);
src = fullfile(tmp, 'src'); mkdir(src);
verifyError(tc, @() lbs_screen(src, 'registered_by', 'abcdef1', 'docs', fullfile(tmp, 'no_docs')), 'lbs_screen:registration');
code = fileread(which('lbs_screen'));
verifyNotEmpty(tc, strfind(code, 'rule_files = {''lbs_verdict'', ''lbs_boot'', ''lb_complete'', ''lbs_screen''};'));
end

function test_registered_hash_is_resolved_in_the_docs_repository(tc)
% The registering commit must exist in the docs repository and hold the entries of the screen
% and of its run guards as headings of docs/DECISIONS.md.
[s, ~] = system('git --version');
assumeTrue(tc, s == 0, 'git is not available');
tmp = tempname; mkdir(tmp);
cl = onCleanup(@() rmdir_quiet(tmp));
docs = fullfile(tmp, 'docs_repo'); mkdir(fullfile(docs, 'docs'));
gg = @(c) system(sprintf('git -C "%s" -c user.name=lbs -c user.email=lbs@example.invalid -c commit.gpgsign=false %s', docs, c));
[s, ~] = gg('init -q');
assumeTrue(tc, s == 0, 'git init failed');
f = fullfile(docs, 'docs', 'DECISIONS.md');
h = cell(1, 3);
txt = {sprintf('# Decisions\n\n## D115 - the screen\n\n## D118 - the guards\n'), ...
    sprintf('# Decisions\n\n## D115 - the screen\n'), ...
    sprintf('# Decisions\n\n## D115 - the screen\n\nsee ## D118 - the guards, later\n')};
for i = 1:3
    put_text(f, txt{i});
    gg('add docs/DECISIONS.md'); gg('commit -q -m c');
    [~, o] = gg('rev-parse HEAD');
    h{i} = regexp(o, '[0-9a-f]{40}', 'match', 'once');
    assumeNotEmpty(tc, h{i});
end
verifyEqual(tc, lbs_inputs('registered', docs, h{1}), h{1});
verifyEqual(tc, lbs_inputs('registered', docs, h{1}(1:7)), h{1});                          % an abbreviation is resolved
verifyError(tc, @() lbs_inputs('registered', docs, h{2}), 'lbs_inputs:registration');       % no heading of the run guards
verifyError(tc, @() lbs_inputs('registered', docs, h{3}), 'lbs_inputs:registration');       % mentioned, not a heading
verifyError(tc, @() lbs_inputs('registered', docs, 'abcdef1'), 'lbs_inputs:registration');  % no such commit
verifyError(tc, @() lbs_inputs('registered', docs, 'XYZ'), 'lbs_inputs:registration');
verifyError(tc, @() lbs_inputs('registered', fullfile(tmp, 'none'), h{1}), 'lbs_inputs:registration');
end

%% ---------- helpers ----------
function make_inputs(src)
% The four input files of the screen as small files of known content.
names = {'policy_pools.mat', 'unknown_threat_agents.mat', 'trained_dqn.mat', 'clean_val_pools.mat'};
for i = 1:numel(names)
    fid = fopen(fullfile(src, names{i}), 'w'); fwrite(fid, uint8(mod((1:5000) * i, 251))); fclose(fid);
end
end

function put_text(f, txt)
fid = fopen(f, 'w'); fwrite(fid, txt); fclose(fid);
end

function [PP, K] = toy_world()
% Frame pools of one flight: the clean link, and a jammer that channel_switch and
% freq_diversity escape; no antenna gains in the pools.
A = policy_actions(); nA = numel(A); names = link_features('names');
PP = struct('actions', {A}, 'scen', {{'none', 'jamming'}}, 'ebno', [10 12], 'runs', {{101}}, 'F_SUB', 20, ...
    'classes', {{'none', 'jamming'}}, 'feat_names', {names}, 'maha_thr', 0, 'clean', [1e-6 1e-6], 'clean_fer', [0 0], ...
    'gp', ones(1, nA), 'bw', 1 + contains(A, 'freq_diversity'), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 2, nA, 1);
for sc = 1:2
    for a = 1:nA
        good = sc == 1 || contains(A{a}, 'channel_switch') || contains(A{a}, 'freq_diversity');
        F = zeros(20, numel(names)); F(:, feature_index('crc_fail')) = ~good;
        F(:, feature_index('log_ber')) = log10(max(0.1 * ~good, 1e-6));
        PP.pools(sc, :, a, 1) = {struct('ber', repmat(0.1 * ~good, 20, 1), 'fer', repmat(single(~good), 20, 1), ...
            'run', 101 * ones(20, 1), 'probs', repmat(double([sc == 1, sc == 2]), 20, 1), 'maha', ones(20, 1), 'feat', F)};
    end
end
K = link_env('tables', PP);
end

function back(cwd, tmp)
cd(cwd); clear clean_ber_ref
rmdir_quiet(tmp);
end

function rmdir_quiet(d)
try, rmdir(d, 's'); catch, end
end

function [PP, A] = world(mode, drop_db)
% The pools' settings of a toy decision world: all 36 configurations, known gains of 6 dB for
% power_control and 3 dB for rate_reduce (9 dB for both), two classes.
A = policy_actions();
g = 6 * contains(A, 'power_control') + 3 * contains(A, 'rate_reduce');
PP = struct('actions', {A}, 'classes', {{'none', 'jamming'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], ...
    'alarm_mode', mode, 'drop_db', drop_db, 'cfg_gain_db', g);
end

function ag = dense_agent(A, prefer, nC)
% A DQN whose Q-values do not depend on the state: it prefers one configuration whenever the
% shield allows it.
nA = numel(A); nS = policy_state_size(nA, nC);
q = zeros(nA, 1, 'single'); q(strcmp(A, prefer)) = 1;
ag = struct('dense', struct('W', {{zeros(1, nS, 'single'), zeros(nA, 1, 'single')}}, 'b', {{single(0), q}}, ...
    'mu', zeros(nS, 1, 'single'), 'sd', ones(nS, 1, 'single')));
end

function o = lb_obs(PP, a_link, E0, dl, gl, base)
% One cycle's observation: Eb/N0 E0 less dl as the receiver's estimate (its known gain added by
% the configuration in use), every antenna's channel gain base less gl plus the power step of the
% configuration in use.
nF = numel(link_features('names'));
o = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', a_link);
o.feat(feature_index('log_ber')) = -6;
o.feat(feature_index('sinr')) = E0 - dl + PP.cfg_gain_db(a_link) - 10*log10(PP.sps) + 10*log10(PP.bps);
o.gant = base - gl + 6 * contains(PP.actions{a_link}, 'power_control');
end

function [dl, gl] = step_loss(T, k0, L, nAnt)
% A common-mode loss of L dB after cycle k0.
dl = [zeros(k0, 1); L * ones(T - k0, 1)]; gl = repmat(dl, 1, nAnt);
end

function R = lb_trace(decide, kind, PP, ag, dl, gl, base)
% A policy over the cycles of a loss; the link runs the requested configuration at once.
A = PP.actions; na = find(strcmp(A, 'no_action'));
T = numel(dl); mem = []; a = na;
R = struct('a', zeros(1, T), 'acted', false(1, T), 'dn', zeros(1, T), 'mem', [], 'info', {cell(1, T)});
for t = 1:T
    o = lb_obs(PP, a, 12, dl(t), gl(t, :), base);
    [a, mem, d] = decide(kind, o, a, mem, PP, ag);
    R.a(t) = a; R.info{t} = d;
    R.acted(t) = isfield(d, 'lb') && any(d.lb);
    if isfield(mem, 'drop_n'), R.dn(t) = mem.drop_n; end
end
R.mem = mem;
end

function [dc, dn] = mon_run(PP, dl, gl, base)
% The monitor alone at no_action: the deficit of the combined gain and the count of confirmed
% drop-alarm cycles.
A = PP.actions; na = find(strcmp(A, 'no_action'));
T = numel(dl); mem = policy_monitor('init', 1, numel(A));
dc = nan(1, T); dn = zeros(1, T);
for t = 1:T
    o = lb_obs(PP, na, 12, dl(t), gl(t, :), base);
    [mem, M] = policy_monitor('update', mem, o, PP, na);
    dc(t) = M.dcomb; dn(t) = mem.drop_n;
    mem = policy_monitor('change', mem, false);
end
end

function [a, acted] = apply_direct(PP, props, dc, varargin)
% lb_complete('apply') on proposals (names) with the given deficit; the name-value pairs set the
% counters, the hold, the pending flags, the configuration in use and the confirmation.
A = PP.actions; na = find(strcmp(A, 'no_action')); NE = numel(props);
a = cellfun(@(p) find(strcmp(A, p)), props);
o = struct('drop_n', 5 * ones(1, NE), 'since', 10 * ones(1, NE), 'pend', false(1, NE), 'cfg', na * ones(1, NE), ...
    'confirmed', true(1, NE));
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1} .* ones(1, NE); end
M = struct('dcomb', dc .* ones(1, NE), 'confirmed', logical(o.confirmed));
mem = struct('drop_n', o.drop_n, 'since', o.since, 'pend', logical(o.pend));
[a, acted] = lb_complete('apply', a, o.cfg, M, mem, PP);
end
