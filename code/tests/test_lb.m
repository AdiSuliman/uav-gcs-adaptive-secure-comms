function tests = test_lb
%TEST_LB  Unit tests of the link-budget completion of the DQN's action (lb_complete.m,
%   policy_monitor.m lb_track, policy_decide.m PP.lb_complete), of its stored switch
%   (decision_settings.m, policy_stamp.m), of C2's adoption step (lb_options.m, lb_adopt.m,
%   lb_selfcheck.m, train_dqn.m) and of the readers' two columns, on synthetic frames and a
%   clean-link table written in a temporary folder; no pools. Run from the repository root:
%   results = runtests('code/tests/test_lb.m')
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
end

function teardownOnce(tc)
clear('clean_ber_ref');
cd(tc.TestData.cwd);
end

%% ---------- the layer (lb_complete.m) ----------
function test_layer_threshold_in_db(tc)
% The threshold is half the smallest path-loss level, in dB, whatever the pools' drop threshold
% (a CUSUM level in dB^2 under class_cusum): 2.9 dB passes nothing, 3 dB acts.
PP = lb_world('class_cusum', 153);
na = find(strcmp(PP.actions, 'no_action'));
verifyEqual(tc, decision_config().sev.path_loss.levels(1) / 2, 3);
for dd = [0.5 4 153 1e4]
    PP.drop_db = dd;
    [m, M] = lb_state(2.9, 3, 10, false, true, true);
    [~, acted] = lb_complete(na, na, M, m, PP);
    verifyFalse(tc, acted, sprintf('2.9 dB, drop_db %g', dd));
    m.lb_dc = 3;
    [a, acted] = lb_complete(na, na, M, m, PP);
    verifyTrue(tc, acted, sprintf('3 dB, drop_db %g', dd));
    verifyEqual(tc, PP.actions{a}, 'rate_reduce');
end
end

function test_layer_guards(tc)
% Every condition is needed: a confirmed drop alarm for C.esc cycles, C.hold cycles since the
% last change, none pending, a deficit of D_min or more, a known gain of the proposal below it.
PP = lb_world('class_drop', 4); C = decision_config();
na = find(strcmp(PP.actions, 'no_action'));
[m, M] = lb_state(10, C.esc, C.hold, false, true, true);
[~, acted] = lb_complete(na, na, M, m, PP); verifyTrue(tc, acted, 'all hold');
bad = struct('drop_n', C.esc - 1, 'since', C.hold - 1, 'pend', true, 'lb_dc', 2.99, 'lb_dc2', NaN);
for f = {'drop_n', 'since', 'pend', 'lb_dc', 'lb_dc2'}
    mm = m; mm.(strrep(f{1}, 'lb_dc2', 'lb_dc')) = bad.(f{1});
    [~, acted] = lb_complete(na, na, M, mm, PP);
    verifyFalse(tc, acted, f{1});
end
for f = {'confirmed', 'drop_alarm'}
    Mx = M; Mx.(f{1}) = false;
    [~, acted] = lb_complete(na, na, Mx, m, PP);
    verifyFalse(tc, acted, f{1});
end
rp = find(strcmp(PP.actions, 'rate_reduce+power_control'));       % known gain 10 dB
m.lb_dc = 9.5; [a, acted] = lb_complete(rp, rp, M, m, PP);
verifyFalse(tc, acted); verifyEqual(tc, a, rp);                   % covers it: left alone
m.lb_dc = 12; [a, acted] = lb_complete(rp, rp, M, m, PP);
verifyFalse(tc, acted); verifyEqual(tc, a, rp);                   % the largest is the proposal already
mm = rmfield(m, 'lb_dc'); [a, acted] = lb_complete(na, na, M, mm, PP);
verifyFalse(tc, acted); verifyEqual(tc, a, na);                   % a monitor without the reading
end

function test_layer_keeps_other_factors(tc)
% The frequency and space choices of the proposal stay; its link-budget factor is the smallest
% of rate_reduce (3.5 dB), power_control (6.5) and both (10) that covers the deficit, the
% largest when none does; fec_interleave proposals are untouched.
PP = lb_world('class_drop', 4); A = PP.actions; na = find(strcmp(A, 'no_action'));
at = @(n) find(strcmp(A, n));
cases = {'channel_switch', 10, 'channel_switch+rate_reduce+power_control'; ...
    'freq_diversity+spatial_diversity', 5, 'freq_diversity+spatial_diversity+power_control'; ...
    'spatial_diversity+rate_reduce', 5, 'spatial_diversity+power_control'; ...
    'no_action', 3.2, 'rate_reduce'; 'no_action', 6.5, 'power_control'; 'no_action', 6.6, 'rate_reduce+power_control'; ...
    'channel_switch+rate_reduce', 4, 'channel_switch+power_control'; 'power_control', 8, 'rate_reduce+power_control'};
for k = 1:size(cases, 1)
    [m, M] = lb_state(cases{k, 2}, 5, 10, false, true, true);
    [a, acted] = lb_complete(at(cases{k, 1}), na, M, m, PP);
    verifyTrue(tc, acted, cases{k, 1}); verifyEqual(tc, A{a}, cases{k, 3}, cases{k, 1});
end
for n = {'fec_interleave', 'power_control+fec_interleave', 'channel_switch+fec_interleave', ...
        'spatial_diversity+rate_reduce+power_control+fec_interleave'}
    if ~any(strcmp(A, n{1})), continue; end
    [m, M] = lb_state(20, 5, 10, false, true, true);
    [a, acted] = lb_complete(at(n{1}), na, M, m, PP);
    verifyFalse(tc, acted, n{1}); verifyEqual(tc, a, at(n{1}), n{1});
end
% several episodes at once: each decided on its own deficit
mem = struct('lb_dc', [10 2 5], 'drop_n', [5 5 5], 'since', [10 10 10], 'pend', [false false false]);
M = struct('confirmed', [true true true], 'drop_alarm', [true true true]);
[a, acted] = lb_complete([na na at('channel_switch')], [na na na], M, mem, PP);
verifyEqual(tc, acted, [true false true]);
verifyEqual(tc, A(a), {'rate_reduce+power_control', 'no_action', 'channel_switch+power_control'});
end

function test_layer_parity_with_budget_match(tc)
% For every deficit from D_min to 25 dB the factor that replaces a no_action proposal is the
% smallest of the three whose known gain covers it, else the largest, and is rule_based_policy.m's
% link-budget match; the same checks are C2's (lb_selfcheck.m).
PP = lb_world('class_drop', 4); A = PP.actions; na = find(strcmp(A, 'no_action'));
names = {'rate_reduce', 'power_control', 'rate_reduce+power_control'}; gains = [3.5 6.5 10];
bud = struct('drop_db', 0, 'current', 'no_action', 'current_db', 0, 'names', {names}, 'gain_db', gains);
for D = 3:0.125:25
    [m, M] = lb_state(D, 3, 10, false, true, true);
    [a, acted] = lb_complete(na, na, M, m, PP);
    j = find(gains >= D, 1); if isempty(j), j = 3; end
    bud.drop_db = D;
    verifyTrue(tc, acted); verifyEqual(tc, A{a}, names{j}, sprintf('%g dB', D));
    verifyEqual(tc, A{a}, rule_based_policy('path_loss', false, 0, -Inf, NaN, true, bud), sprintf('%g dB', D));
end
[ok, msg] = lb_selfcheck();
verifyTrue(tc, ok, strjoin(msg, '; '));
end

function test_layer_reads_no_class_no_truth(tc)
% Static: the layer and the monitor's reading read no class, no unknown-threat score, no truth
% field of the episode, and never PP.drop_db; the layer re-checks the shield.
src = fileread(which('lb_complete'));
code = regexprep(src, '%[^\n]*', '');
bad = '\<(cls|probs|unknown|maha|sc_eff|ended|healthy|scn|truth)\>|PP\s*\.\s*drop_db|PP\s*,\s*''drop_db''';
verifyEmpty(tc, regexp(code, bad, 'match'));
verifyNotEmpty(tc, strfind(code, 'policy_mask('));
verifyNotEmpty(tc, strfind(code, 'rule_based_policy('));
trk = function_text(fileread(which('policy_monitor')), 'lb_track');
verifyNotEmpty(tc, trk);
verifyEmpty(tc, regexp(regexprep(trk, '%[^\n]*', ''), bad, 'match'));
% what lb_complete.m takes from M, mem and PP
verifyEqual(tc, fields_read(code, 'M'), {'confirmed', 'drop_alarm'});
verifyEqual(tc, fields_read(code, 'mem'), {'drop_n', 'lb_dc', 'pend', 'since'});
verifyEqual(tc, fields_read(code, 'PP'), {'actions'});
end

%% ---------- the monitor's reading (policy_monitor.m lb_track) ----------
function test_monitor_single_writer(tc)
% Past bug 1: each new monitor field has one writer, lb_track, called once per update, and no
% name collides with a field the monitor already holds.
f = {'drop_n', 'lb_ref', 'lb_rp', 'lb_rx', 'lb_e', 'lb_dc'};
d = dir(fullfile(tc.TestData.root, 'code', '**', '*.m'));
d = d(~contains({d.folder}, [filesep 'legacy']) & ~contains({d.folder}, [filesep 'tests']));
src = cell(1, numel(d));
for i = 1:numel(d), src{i} = fileread(fullfile(d(i).folder, d(i).name)); end
pm = fileread(which('policy_monitor'));
trk = function_text(pm, 'lb_track');
for k = 1:numel(f)
    w = cellfun(@(s) field_writes(s, f{k}), src);
    verifyEqual(tc, {d(w > 0).name}, {'policy_monitor.m'}, f{k});   % one file writes it
    verifyEqual(tc, sum(w), field_writes(trk, f{k}), f{k});       % in one function
    verifyGreaterThan(tc, field_writes(trk, f{k}), 0, f{k});
end
verifyNumElements(tc, strfind(pm, 'lb_track('), 2);               % its call and its header
mem0 = policy_monitor('init', 2, 36);
verifyEmpty(tc, intersect(fieldnames(mem0), [f, {'lb_complete'}]));
verifyEqual(tc, field_writes(fileread(which('lb_complete')), 'drop_n'), 0);
verifyEqual(tc, field_writes(fileread(which('policy_decide')), 'lb_dc'), 0);
end

function test_monitor_deficit_common_mode_and_branch(tc)
% The deficit is the drop of the combined gain: a common-mode step of x dB reads x dB, a single
% branch lost by 31 dB on equal branches 10 log10(N / (N - 1)): 1.76 dB on 3 antennas, 1.25 dB
% on 4; the power step of the configuration received with is taken out.
for mode = {'class_drop', 'class_cusum'}
    PP = lb_world(mode{1}, ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4));
    for nr = [3 4]
        O = lb_run(PP, 'dqn', const_agent(PP, 'channel_switch'), 24, @(t) 31 * (t > 12) * [1 zeros(1, nr - 1)]);
        verifyEqual(tc, O.dc(end), 10 * log10(nr / (nr - 1)), 'AbsTol', 0.01, sprintf('%s %d antennas', mode{1}, nr));
        verifyEqual(tc, O.dc(1:12), zeros(1, 12), 'AbsTol', 1e-9);
    end
    O = lb_run(PP, 'dqn', const_agent(PP, 'channel_switch'), 24, @(t) 6 * (t > 12) * [1 1 1]);
    verifyEqual(tc, O.dc(end), 6, 'AbsTol', 1e-9, mode{1});
end
end

function test_monitor_reference_held_while_alarm(tc)
% The reference keeps the level from before the loss while the alarm is on: the deficit of a
% persistent step does not decay over 60 cycles; without the switch no field exists.
PP = lb_world('class_drop', 4);
O = lb_run(PP, 'dqn', const_agent(PP, 'no_action'), 60, @(t) 10 * (t > 12) * [1 1 1]);
verifyEqual(tc, O.dc(20:60), 10 * ones(1, 41), 'AbsTol', 1e-9);
verifyGreaterThanOrEqual(tc, O.dn(60), 40);
PP.lb_complete = false;
O = lb_run(PP, 'dqn', const_agent(PP, 'no_action'), 20, @(t) 10 * (t > 12) * [1 1 1]);
verifyFalse(tc, O.has_fields);
% no antenna gains: nothing to read, the layer never acts
PP.lb_complete = true;
O = lb_run(PP, 'dqn', const_agent(PP, 'channel_switch'), 30, @(t) 10 * (t > 12) * [1 1 1], false);
verifyTrue(tc, all(isnan(O.dc)));
verifyFalse(tc, any(O.lb));
end

%% ---------- the decision (policy_decide.m) ----------
function test_decide_common_mode_steps(tc)
% A 10 dB common-mode step: the layer adds rate_reduce+power_control (the smallest gain that
% covers 10 dB does not exist: the largest) to the DQN's channel_switch, once the alarm has been
% confirmed for C.esc cycles and the hold has passed, never on the cycle the escalation moves;
% a 6 dB step (the smallest decision level) is answered by power_control alone; off, the DQN's
% channel_switch stays. Both drop alarms, both DQN kinds.
C = decision_config(); A = policy_actions();
for mode = {'class_drop', 'class_cusum'}
    dd = ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4);
    for kind = {'dqn', 'dqn_esc'}
        for st = [10 6]
            PP = lb_world(mode{1}, dd);
            want = ternary_t(st == 10, 'channel_switch+rate_reduce+power_control', 'channel_switch+power_control');
            ag = const_agent(PP, 'channel_switch');
            O = lb_run(PP, kind{1}, ag, 40, @(t) st * (t > 12) * [1 1 1]);
            tag = sprintf('%s %s %d dB', mode{1}, kind{1}, st);
            t1 = find(O.lb, 1);
            verifyNotEmpty(tc, t1, tag);
            verifyEqual(tc, A{O.a(t1)}, want, tag);
            verifyEqual(tc, A{O.a(t1 - 1)}, 'channel_switch', tag);          % the DQN's own choice, kept
            verifyGreaterThanOrEqual(tc, O.dn(t1), C.esc, tag);
            verifyEqual(tc, O.dc(t1), st, 'AbsTol', 1e-9, tag);
            verifyFalse(tc, O.esc(t1), tag);
            verifyTrue(tc, all(strcmp(A(O.a(t1:end)), want)), tag);          % held to the end
            PP.lb_complete = false;
            Of = lb_run(PP, kind{1}, ag, 40, @(t) st * (t > 12) * [1 1 1]);
            verifyFalse(tc, any(Of.lb), tag);
            verifyTrue(tc, all(strcmp(A(Of.a(t1:end)), 'channel_switch')), tag);   % without it the DQN keeps its pick
            verifyEqual(tc, Of.a(1:t1 - 1), O.a(1:t1 - 1), tag);                 % identical before the layer acts
        end
    end
end
end

function test_decide_single_branch_loss_not_answered(tc)
% A single branch lost by 31 dB on equal mean branches leaves D_c = 1.76 dB (3 antennas) or
% 1.25 dB (4), below D_min: the drop alarm fires on the reference antenna and is confirmed for
% many cycles, the layer stays out and the DQN's decisions are those without it.
C = decision_config();
for mode = {'class_drop', 'class_cusum'}
    dd = ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4);
    for nr = [3 4]
        PP = lb_world(mode{1}, dd); ag = const_agent(PP, 'channel_switch');
        loss = @(t) 31 * (t > 12) * [1 zeros(1, nr - 1)];
        O = lb_run(PP, 'dqn_esc', ag, 40, loss);
        PP.lb_complete = false;
        Of = lb_run(PP, 'dqn_esc', ag, 40, loss);
        tag = sprintf('%s %d antennas', mode{1}, nr);
        verifyGreaterThanOrEqual(tc, max(O.dn), 3 * C.esc, tag);             % the alarm is up and confirmed
        verifyLessThan(tc, max(O.dc), decision_config().sev.path_loss.levels(1) / 2, tag);
        verifyFalse(tc, any(O.lb), tag);
        verifyEqual(tc, O.a, Of.a, tag);
    end
end
end

function test_decide_clean_roll_in(tc)
% A clean roll-in, one branch rolling into shadow over 5 cycles (a ramp on the reference antenna,
% then on another antenna): no common-mode loss, so no layer, whatever the drop alarm does.
for ant = [1 2]
    for mode = {'class_drop', 'class_cusum'}
        dd = ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4);
        PP = lb_world(mode{1}, dd); ag = const_agent(PP, 'channel_switch');
        loss = @(t) min(15, max(0, 3 * (t - 12))) * (1:3 == ant);
        O = lb_run(PP, 'dqn_esc', ag, 40, loss);
        PP.lb_complete = false;
        Of = lb_run(PP, 'dqn_esc', ag, 40, loss);
        tag = sprintf('antenna %d, %s', ant, mode{1});
        verifyFalse(tc, any(O.lb), tag);
        verifyEqual(tc, O.a, Of.a, tag);
        verifyLessThan(tc, max(O.dc), 3, tag);
    end
end
end

function test_decide_fec_interleave_untouched(tc)
% A DQN whose proposal holds fec_interleave (the coding answer to bursts) keeps it under a
% 10 dB common-mode step, and the layer stays out.
A = policy_actions();
for n = {'power_control+fec_interleave', 'channel_switch+fec_interleave'}
    PP = lb_world('class_drop', 4); ag = const_agent(PP, n{1});
    O = lb_run(PP, 'dqn', ag, 40, @(t) 10 * (t > 12) * [1 1 1]);
    verifyFalse(tc, any(O.lb), n{1});
    verifyTrue(tc, all(strcmp(A(O.a(end - 5:end)), n{1})), n{1});
end
end

function test_decide_only_dqn_kinds(tc)
% The rule and the table kinds, and a monitor without a drop alarm, decide as without the
% switch; only the DQN kinds carry info.lb.
rs = RandStream('mt19937ar', 'Seed', 5);
for kind = {'rule_esc', 'table_esc', 'rule', 'blind_esc'}
    for mode = {'class_drop', 'class_cusum'}
        PP = lb_world(mode{1}, ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4));
        P0 = PP; P0.lb_complete = false;
        X = random_trace(PP, 4, 30, rs);
        [a1, i1] = trace_decide(PP, kind{1}, [], X);
        [a0, i0] = trace_decide(P0, kind{1}, [], X);
        verifyEqual(tc, a1, a0, [kind{1} ' ' mode{1}]);
        verifyEqual(tc, i1, i0, [kind{1} ' ' mode{1}]);
        verifyFalse(tc, any(cellfun(@(i) isfield(i, 'lb'), i1)));
    end
end
PP = lb_world('class', 4); P0 = PP; P0.lb_complete = false;           % no drop alarm in this monitor
X = random_trace(PP, 4, 30, rs); ag = random_agent(PP, rs);
[a1, ~, m1] = trace_decide(PP, 'dqn_esc', ag, X);
[a0, ~, m0] = trace_decide(P0, 'dqn_esc', ag, X);
verifyEqual(tc, a1, a0);
verifyTrue(tc, isequaln(m1, m0));
end

%% ---------- off is the parent commit's code, bit for bit ----------
function test_off_bit_identical_to_parent(tc)
% Without PP.lb_complete, and with it false, policy_monitor.m and policy_decide.m give the
% parent commit's (f6f6e03) actions, information and memory bit for bit, on random traces with
% antenna gains in every drop-alarm mode, for the DQN kinds and the rule.
d = parent_dir(tc, 'f6f6e03', {'code/decision/policy_monitor.m', 'code/decision/policy_decide.m'});
rs = RandStream('mt19937ar', 'Seed', 17);
C = struct('tag', {}, 'PP', {}, 'X', {}, 'ag', {}, 'kind', {}, 'field_absent', {}, 'field_false', {});
for mode = {'class_drop', 'class_cusum', 'class'}
    PP = lb_world(mode{1}, ternary_t(strcmp(mode{1}, 'class_cusum'), 153, 4));
    PP = rmfield(PP, 'lb_complete');
    X = random_trace(PP, 4, 40, rs); ag = random_agent(PP, rs);
    P0 = PP; P0.lb_complete = false;
    for kind = {'dqn', 'dqn_esc', 'rule_esc'}
        c = struct('tag', [mode{1} ' ' kind{1}], 'PP', PP, 'X', {X}, 'ag', ag, 'kind', kind{1}, 'field_absent', [], 'field_false', []);
        [r.a, r.i, r.m] = trace_decide(PP, kind{1}, ag, X); c.field_absent = r;
        [r.a, r.i, r.m] = trace_decide(P0, kind{1}, ag, X); c.field_false = r;
        C(end+1) = c; %#ok<AGROW>
    end
end
addpath(d, '-begin'); clear policy_monitor policy_decide
cl0 = onCleanup(@() fixture_off(d, {'policy_monitor', 'policy_decide'})); %#ok<NASGU>
verifyEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
moved = false(1, numel(C));
for k = 1:numel(C)
    [r.a, r.i, r.m] = trace_decide(C(k).PP, C(k).kind, C(k).ag, C(k).X);
    verifyTrue(tc, isequaln(C(k).field_absent, r), [C(k).tag ': field absent']);
    verifyTrue(tc, isequaln(C(k).field_false, r), [C(k).tag ': false']);
    moved(k) = numel(unique(r.a(:))) > 1;                              % the trace moves the configuration
end
fixture_off(d, {'policy_monitor', 'policy_decide'});
verifyNotEqual(tc, which('policy_decide'), fullfile(d, 'policy_decide.m'));
verifyTrue(tc, any(moved));
end

%% ---------- the stored switch ----------
function test_settings_and_stamp(tc)
% The switch reaches every reader through decision_settings.m (an absent one keeps the pools'); the
% deployed policy's stamp is the parent commit's (f6f6e03) without it and with it false, and
% changes with it on and with the smoke's forced mark.
PP = struct('x', 1);
verifyFalse(tc, isfield(decision_settings(PP, struct('alarm_mode', 'class_drop')), 'lb_complete'));
verifyTrue(tc, decision_settings(PP, struct('lb_complete', true)).lb_complete);
verifyTrue(tc, decision_settings(PP, struct('dec', struct('lb_complete', true))).lb_complete);   % data/trained_dqn.mat
verifyFalse(tc, decision_settings(struct('lb_complete', true), struct('lb_complete', false)).lb_complete);   % opt.monitor
verifyTrue(tc, decision_settings(struct('lb_complete', true), struct('alarm_mode', 'class')).lb_complete);
S = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'drop_db', 4, 'maha_thr', -2, 'rule_mmse_db', 7.5, ...
    'confirm_sweep', [2 6], 'rule_nb', {{'a', 'b'}});
Q = struct('deployed', 'dqn_esc', 'alarm_mode', 'class_drop', 'confirm', [2 2], 'drop_db', 4, 'det_id', 'x', ...
    'maha_thr', -1, 'dec', S, 'rule_sel', S);
s1 = policy_stamp(Q);
d = parent_dir(tc, 'f6f6e03', {'code/decision/policy_stamp.m'});
addpath(d, '-begin'); clear policy_stamp
cl0 = onCleanup(@() fixture_off(d, {'policy_stamp'})); %#ok<NASGU>
s0 = policy_stamp(Q);
fixture_off(d, {'policy_stamp'});
verifyEqual(tc, s1, s0);
Q.dec.lb_complete = false; verifyEqual(tc, policy_stamp(Q), s1);
Q.dec.lb_complete = true; s2 = policy_stamp(Q); verifyNotEqual(tc, s2, s1);
Q.dec.lb_forced = true; verifyNotEqual(tc, policy_stamp(Q), s2);
end

function test_options(tc)
% C2 scores the completion only with "lb_select": true in profile.json; "lb_force" is the smoke's
% forced cell; both must be true or false.
off = struct('on', false, 'force', false);
verifyEqual(tc, lb_options('none.json'), off);
f = [tempname '.json'];
write_text(f, '{"lb_select": true}'); verifyEqual(tc, lb_options(f), struct('on', true, 'force', false));
write_text(f, '{"lb_select": true, "lb_force": true}'); verifyEqual(tc, lb_options(f), struct('on', true, 'force', true));
write_text(f, '{"deg_select": true, "surv_v2": true}'); verifyEqual(tc, lb_options(f), off);
write_text(f, '{"lb_select": 1}'); verifyError(tc, @() lb_options(f), 'lb_options:value');
write_text(f, '{"lb_select": true, "lb_force": "yes"}'); verifyError(tc, @() lb_options(f), 'lb_options:value');
delete(f);
end

function test_c2_step_only_with_the_switch(tc)
% Without "lb_select" train_dqn.m runs nothing new and saves the same variables in the same
% order; the step sits after the agent pick and before the gate, runs only under the switch, and
% the stored switch has one writer.
src = fileread(which('train_dqn'));
i0 = strfind(src, 'agents{find(GAM == gamma_sel, 1)} = agent;');
i1 = strfind(src, 'LBo = lb_options();');
i2 = strfind(src, 'if LBo.on');
i3 = strfind(src, '%% 5. Gate, deployed policy and report');
verifyNumElements(tc, i0, 1); verifyNumElements(tc, i1, 1); verifyNumElements(tc, i2, 1); verifyNumElements(tc, i3, 1);
verifyTrue(tc, i0 < i1 && i1 < i2 && i2 < i3);
body = src(i2:i3);
for s = {'lb_readings(', 'lb_selfcheck()', 'lb_adopt(LBX, FA_BOUND, LBok)'}
    verifyNotEmpty(tc, strfind(body, s{1}), s{1});
    verifyEmpty(tc, strfind(src(1:i2), s{1}), s{1});
end
verifyNumElements(tc, strfind(src, 'dec.lb_complete = '), 1);
verifyNotEmpty(tc, strfind(src, 'if ~isempty(LBR), dec.lb_complete = LBon; if LBforced, dec.lb_forced = true; end, end'));
verifyNotEmpty(tc, strfind(src, ['''pools_created'', ''maha_thr'', ''dec'', ''-v7.3'');']));   % the save as before
verifyNotEmpty(tc, strfind(src, 'if ~isempty(LBR), rep = [rep, {''''}, LBlines]; end'));
% a forced completion stops outside the smoke and without the switch, before anything is computed
i4 = strfind(src, 'error(''train_dqn:lb_force''');
verifyNumElements(tc, i4, 1); verifyTrue(tc, i4 > i1 && i4 < i2);
verifyNotEmpty(tc, strfind(src, 'if LBo.force && ~(LBo.on && exist(''SMOKE'', ''var'') && SMOKE)'));
end

%% ---------- the adoption rule (lb_adopt.m) ----------
function test_adopt_rule(tc)
% Adopted only if (a) no set loses (paired difference >= -0.5 point, one-sided 95% lower bound >=
% -1 point), (b) the path-loss family gains (difference and lower bound above 0), (c) the clean
% flights' false changes stay within the 5% bound and 1 point of those without, (d) the checks pass.
% A reading that is absent fails its condition.
[on, R, lines] = lb_adopt(adopt_input(), 0.05, true);
verifyTrue(tc, on); verifyTrue(tc, R.a && R.b && R.c && R.d);
verifyEqual(tc, [R.sets.delta], 0.2 * ones(1, 4), 'AbsTol', 1e-12);
verifyEqual(tc, R.fam.delta, 0.5, 'AbsTol', 1e-12);
verifyTrue(tc, iscellstr(lines) && contains(lines{end}, 'ADOPTED'));
[on, R] = lb_adopt(adopt_input(), 0.05, false);                      % (d)
verifyFalse(tc, on); verifyFalse(tc, R.d);
for k = 1:4                                                           % (a): one set loses 20 points
    X = adopt_input(); X.sets(k).x_on = repmat([1 1 0 0 0], 1, 40);
    [on, R] = lb_adopt(X, 0.05, true);
    verifyFalse(tc, on, X.sets(k).name); verifyFalse(tc, R.a); verifyFalse(tc, R.sets(k).ok);
    verifyEqual(tc, sum([R.sets.ok]), 3);
end
X = adopt_input();                                                    % (a): a mean of zero that flights of +1 and -1 make uncertain
up = mod(X.sets(2).cl, 2) == 0;
X.sets(2).x_off = double(~up); X.sets(2).x_on = double(up);
[~, R] = lb_adopt(X, 0.05, true);
verifyEqual(tc, R.sets(2).delta, 0, 'AbsTol', 1e-12);
verifyLessThan(tc, R.sets(2).lo, -0.01); verifyFalse(tc, R.sets(2).ok);
X = adopt_input();                                                    % (b): no gain on the family
for k = 1:4, X.sets(k).x_on = X.sets(k).x_off; end
[on, R] = lb_adopt(X, 0.05, true);
verifyFalse(tc, on); verifyFalse(tc, R.b); verifyTrue(tc, R.a);
X = adopt_input();                                                    % (b): a gain on average, not by its lower bound
for k = 1:4
    f = X.sets(k).fam; up = mod(X.sets(k).cl, 7) < 4;                 % 23 flights gain, 17 lose
    X.sets(k).x_off = double(~f | ~up); X.sets(k).x_on = double(~f | up);
end
[~, R] = lb_adopt(X, 0.05, true);
verifyEqual(tc, R.fam.delta, 6 / 40, 'AbsTol', 1e-12); verifyLessThan(tc, R.fam.lo, 0); verifyFalse(tc, R.b);
for c = {[20 38 1], [20 39 0], [20 100 0], [0 0 1], [150 140 0]}    % (c): changes without, with; verdict
    X = adopt_input(); n = 1800;
    X.clean.sw_off = [ones(1, c{1}(1)), zeros(1, n - c{1}(1))];
    X.clean.sw_on = [2 * ones(1, c{1}(2)), zeros(1, n - c{1}(2))];
    [~, R] = lb_adopt(X, 0.05, true);
    verifyEqual(tc, R.c, logical(c{1}(3)), mat2str(c{1}));
end
X = adopt_input(); X.clean = struct('sw_off', [], 'sw_on', []);       % (c): not measured
[on, R] = lb_adopt(X, 0.05, true); verifyFalse(tc, on); verifyFalse(tc, R.c);
X = adopt_input(); X.sets(3) = struct('name', 'combined', 'x_off', [], 'x_on', [], 'cl', [], 'fam', false(1, 0));
[on, R] = lb_adopt(X, 0.05, true);                                    % a set not read
verifyFalse(tc, on); verifyFalse(tc, R.sets(3).ok);
X = adopt_input(); X.sets(1).cl(:) = 1;                               % one flight only: no interval
[on, R] = lb_adopt(X, 0.05, true);
verifyFalse(tc, on); verifyTrue(tc, isnan(R.sets(1).lo));
[~, R1] = lb_adopt(adopt_input(), 0.05, true); [~, R2] = lb_adopt(adopt_input(), 0.05, true);
verifyTrue(tc, isequaln(R1, R2));                                     % the same input, the same answer
end

function test_adopt_bound_is_one_sided_cluster_percentile(tc)
% The lower bound is the 5th percentile of the resampled means of whole flights: for 100 flights
% that gain 1 and 0 in turn it is near 0.5 - 1.645 x 0.5 / sqrt(100); the episodes of a flight are
% not independent draws: three copies of each flight's episodes give the bound of one episode per flight.
n = 100; up = mod(1:n, 2) == 1;
X = adopt_input();
X.sets(1) = struct('name', 'single', 'x_off', zeros(1, 3 * n), 'x_on', repelem(double(up), 3), 'cl', repelem(1:n, 3), ...
    'fam', false(1, 3 * n));
[~, R] = lb_adopt(X, 0.05, true);
verifyEqual(tc, R.sets(1).delta, 0.5, 'AbsTol', 1e-12);
verifyEqual(tc, R.sets(1).lo, 0.5 - 1.645 * 0.05, 'AbsTol', 0.02);
X.sets(1) = struct('name', 'single', 'x_off', zeros(1, n), 'x_on', double(up), 'cl', 1:n, 'fam', false(1, n));
[~, R1] = lb_adopt(X, 0.05, true);
verifyEqual(tc, R1.sets(1).lo, R.sets(1).lo, 'AbsTol', 1e-12);
end

function test_seeds_disjoint(tc)
% The step's streams are distinct from each other and from the other literal seeds of the stages
% it reads (train_dqn.m, evaluate_policies.m): the frame draws of a pair are + 100 x set + batch.
S = lb_seeds();
own = [S.specs, S.frames + 100 * (1:4), S.boot];
verifyEqual(tc, numel(unique(own)), numel(own));
verifyEqual(tc, numel(S.boot), 5);
other = [7 99 11 5000 41000 7000 2027 2028 900 30000 70000 40000];
verifyEmpty(tc, intersect(own, other));
batches = S.frames + 100 * (1:4)' + (1:60);                        % 60 batches per set stay inside their 100
verifyEmpty(tc, intersect(batches(:)', [own, other]));
src = [fileread(which('train_dqn')) fileread(which('evaluate_policies'))];
lit = cellfun(@(c) str2double(c{1}), regexp(src, '''Seed'',\s*(\d+)', 'tokens'));
verifyNotEmpty(tc, lit);
verifyEmpty(tc, intersect([own, batches(:)'], lit));
end

%% ---------- the gate reads the deployed agent ----------
function test_c2_gate_reads_the_deployed_switch(tc)
% With the completion adopted (or forced) the gate and choose_deployed read the DQN as deployed: one
% more evaluation with the switch on, inside the step, after the adoption and before the gate;
% without the switch nothing is read.
src = fileread(which('train_dqn'));
i2 = strfind(src, 'if LBo.on'); i3 = strfind(src, '%% 5. Gate, deployed policy and report');
i5 = strfind(src, 'gate = B.held >= bsel.held && B.fa_ok;');
verifyNumElements(tc, i2, 1); verifyNumElements(tc, i3, 1); verifyNumElements(tc, i5, 1);
body = src(i2:i3);
j = strfind(body, 'if LBon ');
verifyNumElements(tc, j, 1);
verifyTrue(tc, i2 + j - 1 < i3 && i3 < i5);
blk = body(j:end);
verifyNotEmpty(tc, strfind(blk, 'xl = ev(sel_kind, decision_settings(PPl, struct(''lb_complete'', true)), agent, struct());'));
verifyNotEmpty(tc, strfind(blk, '[B.rec, B.held, B.kmin, B.ret] = deal(xl.rec, xl.held, xl.kmin, xl.ret);'));
verifyNotEmpty(tc, strfind(blk, ['[B.fa_w, B.n_w, B.sw_w, B.fa_ok] = deal(xl.fa_w, xl.n_w, xl.sw_w, ' ...
    'isnan(up) || up <= FA_BOUND);']));
verifyNumElements(tc, strfind(src, 'xl = ev('), 1);
verifyLessThan(tc, strfind(body, 'LBon = true; LBforced = true;'), j);        % after the forced mark
verifyLessThan(tc, strfind(body, 'lb_adopt(LBX, FA_BOUND, LBok)'), j);        % after the adoption
% the fields it sets are the ones the gate, choose_deployed and the report read from the selected run
decl = regexp(src, 'cand = struct\(''run''.*?\{\}\);', 'match', 'once');
verifyNotEmpty(tc, decl);
for n = {'rec', 'held', 'kmin', 'ret', 'fa_w', 'n_w', 'sw_w', 'fa_ok'}
    verifyNotEmpty(tc, strfind(decl, ['''' n{1} '''']), n{1});
end
end

%% ---------- the readers' two columns (lb_columns.m, evaluate_policies.m, C2g, C2u, KPI 5) ----------
function test_columns_report(tc)
% Four sets of 10 flights of 4 episodes: without the completion 50%, with it 75% (single, combined),
% 100% (follower), 50% (unknown); rule + escalation 25%. The path-loss family is the last two episodes
% of a flight, pooled over single, combined and unknown (the follower set's flags are not read); the
% KPI line pools the threat sets single, follower and combined.
names = {'single', 'follower', 'combined', 'unknown'};
g = repelem(1:10, 4); x0 = repmat([1 1 0 0], 1, 10); xr = repmat([1 0 0 0], 1, 10); fam = repmat([false false true true], 1, 10);
x1 = {repmat([1 1 1 0], 1, 10), ones(1, 40), repmat([1 1 1 0], 1, 10), x0};
X = struct('x0', {}, 'x1', {}, 'xr', {}, 'g', {}, 'fam', {});
for k = 1:4, X(k) = struct('x0', x0, 'x1', x1{k}, 'xr', xr, 'g', g, 'fam', fam | (k == 2)); end
L = lb_columns('dqn_esc', 'on', names, X, [12 15 1800], 3);
verifyEqual(tc, {L.sets(1:4).set}, names);
verifyEqual(tc, [L.sets(1:4).n], 40 * ones(1, 4));
verifyEqual(tc, [L.sets(1:4).off], 0.5 * ones(1, 4), 'AbsTol', 1e-12);
verifyEqual(tc, [L.sets(1:4).on], [0.75 1 0.75 0.5], 'AbsTol', 1e-12);
verifyEqual(tc, [L.sets(1:4).delta], [0.25 0.5 0.25 0], 'AbsTol', 1e-12);
verifyEqual(tc, [L.sets(1:4).rule], 0.25 * ones(1, 4), 'AbsTol', 1e-12);
verifyEqual(tc, L.sets(2).ci, [0.5 0.5], 'AbsTol', 1e-12);                     % every flight gains the same
verifyTrue(tc, all(arrayfun(@(s) s.ci(1) <= s.delta + 1e-12 && s.delta - 1e-12 <= s.ci(2), L.sets(1:4))));
F = L.sets(5);                                                                  % the family: 3 sets x 20 episodes
verifyEqual(tc, F.set, 'path-loss family');
verifyEqual(tc, F.n, 60);
verifyEqual(tc, [F.off F.on F.delta F.rule], [0 1/3 1/3 0], 'AbsTol', 1e-12);
verifyNumElements(tc, L.lines, 7);                                              % heading, 4 sets, family, clean link
verifyTrue(tc, contains(L.lines{1}, 'dqn_esc') && contains(L.lines{1}, 'deployed switch is on'));
verifyTrue(tc, all(contains(L.lines(2:6), 'DQN + link-budget completion (hybrid)')));
verifyTrue(tc, contains(L.lines{6}, 'path-loss family') && contains(L.lines{6}, '60:'));
verifyTrue(tc, contains(L.lines{7}, '12/1800 without') && contains(L.lines{7}, '15/1800 with') && contains(L.lines{7}, '>= 3 dB'));
verifyNumElements(tc, L.kpi, 1);
verifyTrue(tc, startsWith(L.kpi{1}, 'beside KPI 5'));
verifyTrue(tc, contains(L.kpi{1}, '50.0%') && contains(L.kpi{1}, '83.3%') && contains(L.kpi{1}, '25.0%'));
verifyTrue(tc, endsWith(L.kpi{1}, 'deployed switch on'));
verifyTrue(tc, L.deployed); verifyEqual(tc, L.clean, [12 15 1800]);
Lo = lb_columns('dqn_g3', 'off', names, X, [12 15 1800], 3);                    % the switch deployed off: the same pair
verifyFalse(tc, Lo.deployed);
verifyTrue(tc, endsWith(Lo.kpi{1}, 'deployed switch off') && contains(Lo.lines{1}, 'deployed switch is off'));
verifyEqual(tc, [Lo.sets.delta], [L.sets.delta]);
verifyTrue(tc, isequaln(L, lb_columns('dqn_esc', 'on', names, X, [12 15 1800], 3)));   % fixed seeds
% a single flight has no interval; the report still prints
X(1).g(:) = 1;
L1 = lb_columns('dqn_esc', 'on', names, X, [0 0 10], 3);
verifyTrue(tc, all(isnan(L1.sets(1).ci)) && L1.sets(1).delta == 0.25);
verifyTrue(tc, contains(L1.lines{2}, 'NaN'));
end

function test_columns_seeds(tc)
% The columns' bootstraps are distinct from the adoption's, the step's other streams and the stages'
% literal seeds, and are not literals in lb_columns.m.
S = lb_seeds();
verifyEqual(tc, numel(S.cols), 5);
own = [S.specs, S.frames + 100 * (1:4), S.boot, S.cols];
verifyEqual(tc, numel(unique(own)), numel(own));
batches = S.frames + 100 * (1:4)' + (1:60);
verifyEmpty(tc, intersect(S.cols, [S.specs, S.boot, batches(:)']));
verifyEmpty(tc, intersect(S.cols, [7 99 11 5000 41000 7000 2027 2028 900 30000 70000 40000]));
ln = splitlines(fileread(which('lb_columns')));
b = ln(contains(ln, 'boot_cluster('));
verifyNumElements(tc, b, 2);
verifyTrue(tc, all(contains(b, 'S.cols(')));
end

function test_c2e_columns_wiring(tc)
% C2e prints the two columns only when C2 stored the switch (train_dqn.m step 4b): after the policy
% loop, before the envelope; the report and the saved file grow only then; the selected DQN runs
% without and with the completion on the main runs' frame draws; the forced mark stops outside the smoke.
src = fileread(which('evaluate_policies'));
pos = @(s) strfind(src, s);
a = pos('LBC = [];'); b = pos('if isfield(Q, ''dec'') && isstruct(Q.dec) && isfield(Q.dec, ''lb_complete'')');
c = pos('LBC = lb_flights(PP, K, Q, sets, RES, POL, sel, fixed_best, fixed_mmse, tab, ebno_thr);');
d = pos('%% 3b. Envelope predicted on the VALIDATION split'); e = pos('for si = 1:numel(sets)');
for x = {a, b, c, d}, verifyNumElements(tc, x{1}, 1); end
verifyTrue(tc, e(1) < a && a < b && b < c && c < d);
verifyNotEmpty(tc, pos('if ~isempty(LBC), rep = [rep, {''''}, LBC.lines]; end'));
verifyNotEmpty(tc, pos('if ~isempty(LBC), save(''results/policy_evaluation.mat'', ''LBC'', ''-append''); end'));
verifyNotEmpty(tc, pos(['save(''results/policy_evaluation.mat'', ''RES'', ''RW'', ''POL'', ''LBL'', ''set_names'', ''fixed_best'', ' ...
    '''tab'', ''iDQN'', ''KP'', ...']));
fl = src(strfind(src, 'function L = lb_flights('):end);
fl = fl(1:strfind(fl, 'function F6 = fresh_checks') - 1);
verifyNotEmpty(tc, strfind(fl, 'o0 = opt; o0.monitor = struct(''lb_complete'', false);'));
verifyNotEmpty(tc, strfind(fl, 'o1 = opt; o1.monitor = struct(''lb_complete'', true);'));
verifyNumElements(tc, strfind(fl, '30000 + 100 * si'), 4);                     % the main runs' draws, a pair the same
verifyNotEmpty(tc, strfind(fl, 'L = lb_columns(nm, ternary(Q.dec.lb_complete, ''on'', ''off''), names, X, cl, ebno_thr);'));
verifyNotEmpty(tc, strfind(fl, 'nm = ''dqn_esc''; if strcmp(Q.deployed, ''dqn''), nm = sprintf(''dqn_g%d'', sel); end'));
verifyNotEmpty(tc, pos('error(''evaluate_policies:lb_forced'''));
verifyNotEmpty(tc, pos('isfield(Q.dec, ''lb_forced'') && Q.dec.lb_forced && ~(exist(''SMOKE'', ''var'') && SMOKE)'));
% KPI 5 prints the line only with the columns
k = fileread(which('measure_all_kpis'));
verifyNotEmpty(tc, strfind(k, 'if isfield(P, ''LBC'') && ~isempty(P.LBC), det = [det, P.LBC.kpi]; end'));
end

function test_readers_off_is_the_parent(tc)
% Without the stored switch the readers are the parent commit's (f6f6e03): every parent line is in the
% copy, in order, but the ones named here (the cache key, the entity call and header and the options of
% the evaluations of C2g and C2u, whose opt0 is struct() without the switch); the main readers, the
% step and the layer only add lines.
for f = {'code/decision/evaluate_policies.m', 'code/evaluation/measure_all_kpis.m', 'code/decision/train_dqn.m', ...
        'code/decision/policy_monitor.m'}
    verifyEmpty(tc, parent_lines_missing(tc, 'f6f6e03', f{1}), f{1});
end
verifyEqual(tc, parent_lines_missing(tc, 'f6f6e03', 'code/decision/decision_settings.m'), ...
    {'        ''rule_mmse_db'', ''rule_slot'', ''rule_dwell'', ''esc_drop'', ''rule_nb'', ''core_nb'', ''deg_mode'', ''ber_q''}'});
verifyNumElements(tc, parent_lines_missing(tc, 'f6f6e03', 'code/decision/policy_decide.m'), 1);   % a comment line
verifyNumElements(tc, parent_lines_missing(tc, 'f6f6e03', 'code/decision/policy_stamp.m'), 1);    % a comment line
miss = parent_lines_missing(tc, 'f6f6e03', 'code/decision/experiment_combo_generalization.m');
verifyEqual(tc, miss, {'keys = cellfun(@(cn) run_cache(''key'', {CID, ''C2g'', cn, H, seed, REPS, NE, TEST, DK}), combos, ''UniformOutput'', false);', ...
    'out = run_cache(''each'', CDIR, keys, @(ci) one_combo(ci, combos, PP, K, Q, H, seed, nS, TEST, REPS, NE, DK, t0), combos);', ...
    'function r = one_combo(ci, combos, PP, K, Q, H, seed, nS, TEST, REPS, NE, DK, t0)', ...
    '% escalation and the class table on its test flights.', ...
    'Ro = dqn_eval_batches(DK, PP, K, specs, ag, struct(), 7000, TEST);', ...
    'Ri = dqn_eval_batches(DK, PP, K, specs, Q.agent, struct(), 7000, TEST);'});
miss = parent_lines_missing(tc, 'f6f6e03', 'code/decision/experiment_unknown_threat.m');
verifyEqual(tc, miss, {'keys = cellfun(@(th) run_cache(''key'', {CID, ''C2u'', th, H, seed, REPS, NE, SPL, DK}), threats, ''UniformOutput'', false);', ...
    'out = run_cache(''each'', CDIR, keys, @(ti) one_threat(ti, threats, PP, K, Q, H, seed, nS, SPL, REPS, NE, DK, t0), threats);', ...
    'function o = one_threat(ti, threats, PP, K, Q, H, seed, nS, SPL, REPS, NE, DK, t0)', ...
    '% o.res).', '[Ro, Ri, Rr] = deal([]);', ...
    '    Ro = cat_struct(Ro, mark(dqn_eval_batches(DK, PP, K, specs, ag, struct(), 7000, sp), specs, PP, sp));', ...
    '    Ri = cat_struct(Ri, mark(dqn_eval_batches(DK, PP, K, specs, Q.agent, struct(), 7000, sp), specs, PP, sp));'});
end

function test_c2g_c2u_columns_wiring(tc)
% C2g and C2u: the headline columns (dqn_out, dqn_in, the learner's own result) run with the completion
% off; the hybrid columns (_lb) with it on, on the same episodes and draws; the cache key and the option
% structs are the parent's without the stored switch; the retrained learner trains and keeps its
% checkpoint without the completion; the rule and the table never see the switch.
for f = {'experiment_combo_generalization', 'experiment_unknown_threat'}
    src = fileread(which(f{1}));
    verifyNotEmpty(tc, strfind(src, 'LBC = isfield(Q, ''dec'') && isstruct(Q.dec) && isfield(Q.dec, ''lb_complete'');'), f{1});
    verifyNotEmpty(tc, strfind(src, 'lbkey = {}; if LBC, lbkey = {''lb_columns''}; end'), f{1});
    verifyNotEmpty(tc, strfind(src, ', DK}, lbkey]), '), f{1});
    verifyNotEmpty(tc, strfind(src, 'opt0 = struct();'), f{1});
    verifyNotEmpty(tc, strfind(src, 'if LBC, opt0 = struct(''monitor'', struct(''lb_complete'', false)); end'), f{1});
    verifyNotEmpty(tc, strfind(src, 'opt1 = struct(''monitor'', struct(''lb_complete'', true));'), f{1});
    verifyNumElements(tc, strfind(src, 'PPx.lb_complete = false'), 1, f{1});
    verifyNumElements(tc, strfind(src, 'dqn_train_run('), 1, f{1});
    verifyLessThan(tc, strfind(src, 'PPx.lb_complete = false'), strfind(src, 'dqn_train_run('), f{1});
    verifyNotEmpty(tc, regexp(src, 'Ro = [^\n]*, ag, opt0,', 'once'), f{1});
    verifyNotEmpty(tc, regexp(src, 'Ri = [^\n]*, Q\.agent, opt0,', 'once'), f{1});
    verifyNotEmpty(tc, regexp(src, 'Ro1 = [^\n]*, ag, opt1,', 'once'), f{1});
    verifyNotEmpty(tc, regexp(src, 'Ri1 = [^\n]*, Q\.agent, opt1,', 'once'), f{1});
    verifyNotEmpty(tc, regexp(src, 'Rr = [^\n]*''rule_esc'', PP, K, specs, \[\], struct\(\)', 'once'), f{1});
    verifyNotEmpty(tc, strfind(src, 'DQN + LB, never trained'), f{1});
    verifyNotEmpty(tc, strfind(src, 'DQN + link-budget completion (hybrid, not learned)'), f{1});
end
end

%% ---------- helpers ----------
function X = adopt_input()
% lb_adopt.m's readings: four sets of 40 flights of 5 episodes, 3 recovered without the completion
% and the fourth with it (a gain of 20 points), the last two episodes of a flight holding a path
% loss; 1800 clean flights, 20 changed without it and 20 with it.
cl = repelem(1:40, 5); fam = repmat([false false false true true], 1, 40);
nm = {'single', 'follower', 'combined', 'unknown'};
X = struct('sets', struct('name', {}, 'x_off', {}, 'x_on', {}, 'cl', {}, 'fam', {}), 'clean', []);
for k = 1:4
    X.sets(end+1) = struct('name', nm{k}, 'x_off', repmat([1 1 1 0 0], 1, 40), 'x_on', repmat([1 1 1 1 0], 1, 40), ...
        'cl', cl, 'fam', fam);
end
X.clean = struct('sw_off', [ones(1, 20), zeros(1, 1780)], 'sw_on', [ones(1, 20), zeros(1, 1780)]);
end

function write_text(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function PP = lb_world(mode, drop_db)
% The pools' settings of the tests: two classes, known gains of 6.5 dB for power_control (the
% power step in the received field) and 3.5 dB for rate_reduce (processing gain), the
% completion on.
A = policy_actions();
g = 6.5 * contains(A, 'power_control') + 3.5 * contains(A, 'rate_reduce');
w = 6.5 * contains(A, 'power_control');
PP = struct('actions', {A}, 'classes', {{'none', 'path_loss'}}, 'sps', 4, 'bps', 2, 'maha_thr', -Inf, 'confirm', [2 2], ...
    'alarm_mode', mode, 'drop_db', drop_db, 'cfg_gain_db', g, 'pw', 10 .^ (w / 10), 'lb_complete', true);
end

function ag = const_agent(PP, name)
% A DQN whose Q-values are 1 for configuration `name` and 0 for the others, whatever the state.
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
q = zeros(nA, 1); q(strcmp(PP.actions, name)) = 1;
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{zeros(2, nS), zeros(nA, 2)}}, 'b', {{zeros(2, 1), q}}));
end

function ag = random_agent(PP, rs)
% A DQN with random weights (a state-dependent policy).
nA = numel(PP.actions); nS = policy_state_size(nA, numel(PP.classes));
ag = struct('dense', struct('mu', zeros(nS, 1), 'sd', ones(nS, 1), 'W', {{0.3 * randn(rs, 16, nS), randn(rs, nA, 16)}}, ...
    'b', {{randn(rs, 16, 1), randn(rs, nA, 1)}}));
end

function [m, M] = lb_state(dc, dn, since, pend, conf, dal)
% The monitor's reading and memory of one episode as lb_complete.m takes them.
m = struct('lb_dc', dc, 'drop_n', dn, 'since', since, 'pend', pend);
M = struct('confirmed', conf, 'drop_alarm', dal);
end

function O = lb_run(PP, kind, ag, T, loss, gant)
% policy_decide over T cycles of one episode; loss(t) the losses [dB] of the antennas (1 x nr,
% antenna 1 the reference: the estimate of Eb/N0 follows it), a change reaching the link at
% once. The frame carries the power step of the configuration it was received with. gant
% false: no antenna gains.
if nargin < 6, gant = true; end
A = PP.actions; na = find(strcmp(A, 'no_action')); nF = numel(link_features('names'));
[gk, gw] = config_gain_db(PP);
O = struct('a', zeros(1, T), 'lb', false(1, T), 'dc', nan(1, T), 'dn', zeros(1, T), 'esc', false(1, T), ...
    'has_fields', false);
a = na; m = [];
for t = 1:T
    L = loss(t);
    o = struct('probs', [1 0], 'unknown', false, 'feat', zeros(1, nF), 'cfg_link', a);
    o.feat(feature_index('log_ber')) = -6;
    o.feat(feature_index('sinr')) = 12 - L(1) + gk(a) - 10*log10(4) + 10*log10(2);
    if gant, o.gant = 2 - L + gw(a); end
    [a, m, info] = policy_decide(kind, o, a, m, PP, ag);
    O.a(t) = a; O.esc(t) = info.escalated;
    if isfield(info, 'lb'), O.lb(t) = info.lb; end
    if isfield(m, 'lb_dc'), O.dc(t) = m.lb_dc; end
    if isfield(m, 'drop_n'), O.dn(t) = m.drop_n; end
    O.has_fields = O.has_fields || isfield(m, 'lb_dc') || isfield(m, 'drop_n');
end
end

function X = random_trace(PP, NE, T, rs)
% NE episodes of T cycles: random class probabilities, BER, SINR with steps, quiet slot, CRC and
% three antennas' gains with a drop on one or all of them.
nC = numel(PP.classes); nF = numel(link_features('names'));
X = cell(1, T); step = 6 * randi(rs, [0 2], NE, 1); k0 = randi(rs, [8 20], NE, 1); on = randi(rs, [0 1], NE, 3);
for t = 1:T
    p = rand(rs, NE, nC) .^ 4; p(:, 1) = p(:, 1) + 0.7 * (rand(rs, NE, 1) < 0.8); p = p ./ sum(p, 2);
    o = struct('probs', p, 'unknown', false(NE, 1), 'feat', zeros(NE, nF));
    d = step .* (t >= k0);
    o.feat(:, feature_index('log_ber')) = -5 + 3 * rand(rs, NE, 1);
    o.feat(:, feature_index('sinr')) = 6 + randn(rs, NE, 1) - d;
    o.feat(:, feature_index('q_iot')) = 6 * rand(rs, NE, 1) - 1;
    o.feat(:, feature_index('crc_fail')) = rand(rs, NE, 1) < 0.2;
    o.gant = 1 + randn(rs, NE, 3) - d .* (1 + on) / 2;
    X{t} = o;
end
end

function [A, I, M] = trace_decide(PP, kind, ag, X)
% policy_decide over the trace X from no_action (cfg_link follows the request); the actions
% (T x NE), every cycle's information and the last memory.
NE = size(X{1}.feat, 1); T = numel(X);
na = find(strcmp(PP.actions, 'no_action'));
cfg = na * ones(1, NE); mem = [];
A = zeros(T, NE); I = cell(1, T);
opt = struct('table', na * ones(1, numel(PP.classes)), 'table_unknown', find(strcmp(PP.actions, 'freq_diversity')));
for t = 1:T
    o = X{t}; o.cfg_link = cfg;
    [cfg, mem, I{t}] = policy_decide(kind, o, cfg, mem, PP, ag, opt);
    A(t, :) = cfg;
end
M = mem;
end

function n = field_writes(src, f)
% The writes of mem.f in src: mem.f = ..., mem.f(...) = ..., or among the outputs [..., mem.f, ...] = ....
n = numel(regexp(src, ['(?<![\w.])mem\.' f '(\([^)]*\))?\s*=(?!=)'], 'match')) + ...
    numel(regexp(src, ['\[[^\]=]*(?<![\w.])mem\.' f '\>[^\]=]*\]\s*=(?!=)'], 'match'));
end

function f = fields_read(code, v)
% The sorted names of the fields of variable v that code accesses (v.name).
t = regexp(code, ['(?<![\w.])' v '\.(\w+)'], 'tokens');
f = unique(cellfun(@(c) c{1}, t, 'UniformOutput', false));
f = f(:)';
end

function t = function_text(src, name)
% The text of the local function `name` of src: its header up to the next function's.
i = regexp(src, ['\nfunction [^\n]*\<' name '\>'], 'once');
if isempty(i), t = ''; return; end
r = src(i+1:end);
j = regexp(r(2:end), '\nfunction ', 'once');
if isempty(j), t = r; else, t = r(1:j); end
end

function x = ternary_t(c, a, b)
if c, x = a; else, x = b; end
end

function d = parent_dir(tc, rev, rels)
% The files rels as commit rev holds them, together in one folder. An export without .git (the
% deploy queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
for k = 1:numel(rels)
    [~, nm, ext] = fileparts(rels{k});
    [st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rels{k}, ...
        fullfile(d, [nm ext])));
    assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rels{k}, out));
end
end

function missing = parent_lines_missing(tc, rev, rel)
% The lines of file rel as commit rev holds it that the copy in this checkout lacks, matched in order
% ({} when the copy only adds lines).
d = parent_dir(tc, rev, {rel}); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
[~, nm, ext] = fileparts(rel);
old = regexp(fileread(fullfile(d, [nm ext])), '\r?\n', 'split');
new = regexp(fileread(fullfile(tc.TestData.root, rel)), '\r?\n', 'split');
j = 1; missing = {};
for i = 1:numel(old)
    k = find(strcmp(new(j:end), old{i}), 1);
    if isempty(k), missing{end+1} = old{i}; else, j = j + k; end %#ok<AGROW>
end
end

function fixture_off(d, fns)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
for k = 1:numel(fns), clear(fns{k}); end
if isfolder(d), rmdir(d, 's'); end
end
