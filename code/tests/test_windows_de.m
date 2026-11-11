function tests = test_windows_de
%TEST_WINDOWS_DE  The lost-branch log print of C2e (lb_log_lines.m), the shared-settings note, P-B's record and
%   sentence, the receiver-robust column of KPI 8 in lect_kpis.m, the per-policy false-alarm breakdown
%   and the C2 validation reader. Run from the repository root: results = runtests('code/tests').
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
end

%% ---------- the lost-branch log (lb_log_lines.m, evaluate_policies.m) ----------
function test_lb_log_counts_cycles_and_episodes_by_harm(tc)
R = struct('threat', logical([1 1 1 1 1 0]), 'lb_na', [3 0 2 0 0 7], 's1_withheld', [1 1 0 0 4 0], 's1_blocked', [0 0 0 2 0 0]);
Rb = struct('threat', R.threat);                                  % a policy without the counts
HA = logical([1 1 0 0 0 0]);
L = lb_log_lines({R, Rb}, {'a', 'b'}, {'policy a', 'policy b'}, HA);
verifyEqual(tc, numel(L), 4);                                    % heading and three lines for policy a
verifyNotEmpty(tc, strfind(L{1}, 'Lost-branch log'));
verifyEqual(tc, L{2}, ['  policy a: lost-branch class not accepted (class alarm withheld), 3 cycles in 1 of 2 harmed episodes | ' ...
    '2 cycles in 1 of 3 unharmed episodes']);                    % the clean episode (7 cycles) is not counted
verifyEqual(tc, L{3}, ['  policy a: class answer withheld by the lost-branch gate, 2 cycles in 2 of 2 harmed episodes | ' ...
    '4 cycles in 1 of 3 unharmed episodes']);
verifyEqual(tc, L{4}, ['  policy a: escalation blocked by the lost-branch gate, 0 cycles in 0 of 2 harmed episodes | ' ...
    '2 cycles in 1 of 3 unharmed episodes']);
end

function test_lb_log_prints_nothing_without_the_fields(tc)
R = struct('threat', logical([1 1 0]), 'recovered', [1 0 0]);
verifyEmpty(tc, lb_log_lines({R, R}, {'a', 'b'}, {'A', 'B'}, logical([1 0 0])));
end

function test_lb_log_wiring_static_and_parse(tc)
e = strrep(fileread(which('evaluate_policies')), char(13), '');
verifyNumElements(tc, strfind(e, 'LBX = lb_log_lines(ALL, POL, LBL, HA);'), 1);
verifyNotEmpty(tc, strfind(e, 'if ~isempty(LBX), rep = [rep, {''''}, LBX]; end'));
verifyLessThan(tc, strfind(e, 'HA = harmed(ALL{1}, K);'), strfind(e, 'LBX = lb_log_lines('));
parses_ok(tc, 'lb_log_lines'); parses_ok(tc, 'evaluate_policies');
end

%% ---------- the shared-settings note (evaluate_policies.m) ----------
function test_shared_settings_note_names_rule_core3_only_when_it_runs(tc)
e = strrep(fileread(which('evaluate_policies')), char(13), '');
verifyEmpty(tc, strfind(e, 'never with the gate'));
verifyNumElements(tc, strfind(e, 'rule_core and rule_core3 run with those'), 0);
a = ['%s with those shared settings and without that gate (the '' ...' newline];
verifyNumElements(tc, strfind(e, a), 1);
verifyNumElements(tc, strfind(e, 'ternary(c3_on, ''rule_core and rule_core3 run'', ''rule_core runs'')'), 1);
% the note comes after c3_on is set, and the core option's own gate line follows it unchanged
verifyLessThan(tc, strfind(e, 'c3_on = isfield(PP, ''core3_id'')'), strfind(e, 'ternary(c3_on, ''rule_core and rule_core3 run'''));
verifyLessThan(tc, strfind(e, 'ternary(c3_on, ''rule_core and rule_core3 run'''), strfind(e, '% the core rule''s lost-branch gate step ran at C2'));
end

%% ---------- P-B's record and its 'not run' sentence ----------
function test_pb_not_run_sentence_is_unconditional(tc)
e = strrep(fileread(which('evaluate_policies')), char(13), '');
i0 = strfind(e, 'if c3_on                                                          % P-B');
i1 = strfind(e, 'rep = [rep, MNOTE];');
verifyNumElements(tc, i0, 1); verifyNumElements(tc, i1, 1); verifyLessThan(tc, i0, i1);
b = e(i0:i1 - 1);
verifyNumElements(tc, strfind(b, 'elseif isfield(PP, ''core3_not_run'')'), 1);
verifyNotEmpty(tc, regexp(b, '
else
    MNOTE\{end\+1\} = \[''rule_core3 was not run in profile 3; CORE_BW \(profile 1\) is the three-state CNN''''s in-loop evidence'' \.\.\.', 'once'));
verifyEmpty(tc, strfind(b, 'elseif WF.core3'));          % no longer gated on the switch
% the same sentence as build_policy_pools.m's
bp = fileread(which('build_policy_pools'));
verifyNotEmpty(tc, strfind(bp, 'rule_core3 was not run in profile 3; CORE_BW (profile 1) is the three-state CNN'));
end

function test_pb_check_record_exists(tc)
f = fullfile(tc.TestData.root, 'docs', 'p_b_check.txt');
verifyTrue(tc, isfile(f));
t = fileread(f);
verifyNotEmpty(tc, strfind(t, 'Condition (a)'));
verifyNotEmpty(tc, strfind(t, 'FALSE'));
verifyNotEmpty(tc, strfind(t, 'rule_core3 was not run in profile 3'));
end

%% ---------- KPI 8's receiver-robust side column (lect_kpis.m) ----------
function [ALL, POL, LBL, scen] = rr_world()
% Eight episodes of every policy: jamming (1, 2, 7), tone_jamming (3, 4, 8), path_loss (5, 6); episode 7 not recoverable,
% episode 8 without its threat on the air, episode 2 recoverable only outside the core action set. On the core jamming
% episodes 1, 3 and 4 rule_core3 reads 0.1 below blind_core in PER and rule_core 0.2 below.
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle', 'rule_core', 'blind_core', 'rule_core3'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', 'oracle', ...
    'core: rule + escalation', 'core: no detector + escalation', 'core: rule + escalation, three-state CNN (profile 3, P-B)'};
scen = {'none', 'jamming', 'tone_jamming', 'path_loss'};
B = struct('scn', [2 2 3 3 4 4 2 3], 'recoverable', logical([1 1 1 1 1 1 0 1]), ...
    'recoverable_core', logical([1 0 1 1 1 1 0 1]), 'threat', logical([1 1 1 1 1 1 1 0]), ...
    'geom', [1 1 2 2 3 3 4 5], 'ok_post', 0.5 * ones(1, 8));
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = B;
    switch POL{k}
        case 'none'
            R.per_post = [0.5 0.5 0.4 0.4 0.6 0.6 0.9 0.2]; R.dlv_post = [0.5 0.5 0.6 0.6 0.4 0.4 0.1 0.8];
            R.t_conf = [1 1 1 1 1 1 NaN NaN]; R.t_rec_det = nan(1, 8); R.t_rec = nan(1, 8);
        case {'blind_esc', 'blind_core'}
            R.per_post = [0.3 0.3 0.4 0.4 0.3 0.3 0.9 0.2]; R.dlv_post = [0.7 0.7 0.6 0.6 0.7 0.7 0.1 0.8];
            R.t_conf = [2 3 3 2 2 2 NaN NaN]; R.t_rec_det = [5 6 NaN NaN 4 4 NaN NaN]; R.t_rec = [7 9 NaN NaN 6 6 NaN NaN];
        case 'rule_core3'
            R.per_post = [0.2 0.2 0.3 0.3 0 0 0.9 0.2]; R.dlv_post = [0.8 0.8 0.7 0.7 1 1 0.1 0.8];
            R.t_conf = [1 2 5 4 1 1 NaN NaN]; R.t_rec_det = [3 4 6 2 0 5 NaN NaN]; R.t_rec = [4 6 11 6 1 6 NaN NaN];
        otherwise
            R.per_post = [0.1 0.1 0.2 0.2 0 0 0.9 0.2]; R.dlv_post = [0.9 0.9 0.8 0.8 1 1 0.1 0.8];
            R.t_conf = [1 2 NaN 0 1 1 NaN NaN]; R.t_rec_det = [3 4 NaN 2 0 5 NaN NaN]; R.t_rec = [4 6 NaN 2 1 6 NaN NaN];
            if strcmp(POL{k}, 'oracle'), R.t_conf(:) = NaN; R.t_rec_det(:) = NaN; end
    end
    R.gput_post = R.dlv_post; R.recovered = isfinite(R.t_rec);
    ALL{k} = R;
end
end

function back = rr_cwd(tc)
% A fresh working folder with an empty results folder, entered until the returned cleanup runs.
d = tempname; mkdir(fullfile(d, 'results'));
c0 = cd(d); back = onCleanup(@() cd(c0));
tc.addTeardown(@() rmdir(d, 's'));
end

function test_rr_column_off_is_the_parent(tc)
[ALL, POL, LBL, scen] = rr_world();
[L0, l0] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20);
[L1, l1] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20, struct());
[L2, l2] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20, struct('rr', false));
verifyTrue(tc, isequaln(L0, L1) && isequaln(L0, L2));
verifyEqual(tc, l0, l1); verifyEqual(tc, l0, l2);
verifyFalse(tc, any(contains(l0, 'receiver-robust')));
verifyFalse(tc, isfield(L0.core.cnn, 'rr') || isfield(L0.core.cnn3, 'rr'));
end

function test_rr_column_without_the_d2c_file_is_not_available(tc)
back = rr_cwd(tc); %#ok<NASGU>
[ALL, POL, LBL, scen] = rr_world();
[L0, l0] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20);
[L, lines] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20, struct('rr', true));
isrr = contains(lines, 'receiver-robust (U_s from D2c');
verifyEqual(tc, sum(isrr), 2);                                   % the core pair and the three-state pair, primary mask only
verifyEqual(tc, lines(~isrr), l0);                                % every other line is the registered one
for c = {L.core.cnn, L.core.cnn3}
    verifyEqual(tc, c{1}.rr.robust, {'n/a', 'n/a', 'n/a'});
    verifyTrue(tc, all(isnan([c{1}.rr.Us.per c{1}.rr.Us.gput c{1}.rr.Us.trec])));
end
for l = lines(isrr)
    verifyNotEmpty(tc, strfind(l{1}, 'U_s not available (results/d2c_us.mat absent or empty): no verdict'));
    verifyNotEmpty(tc, strfind(l{1}, '(U_s not available) n/a'));
    verifyEmpty(tc, strfind(l{1}, ' yes'));
end
% the registered readings and the other pairs carry nothing of it
verifyFalse(tc, isfield(L.cnn, 'rr') || isfield(L.core.all36.cnn, 'rr') || isfield(L.core.all36.cnn3, 'rr'));
for f = {'verdict', 'per', 'per_threat', 'cnn', 'rec', 'gput'}
    verifyTrue(tc, isequaln(L.(f{1}), L0.(f{1})), f{1});
end
verifyTrue(tc, isequaln(rmfield(L.core.cnn, 'rr'), L0.core.cnn));
verifyTrue(tc, isequaln(rmfield(L.core.cnn3, 'rr'), L0.core.cnn3));
verifyTrue(tc, isequaln(L.core.all36, L0.core.all36));
end

function test_rr_column_with_the_d2c_file_gives_yes_no_and_na(tc)
back = rr_cwd(tc); %#ok<NASGU>
Us = struct('per', 0.01, 'gput', 100, 'trec', 0.5); save(fullfile('results', 'd2c_us.mat'), 'Us');
[ALL, POL, LBL, scen] = rr_world();
[L, lines] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20, struct('rr', true));
% episodes 1, 3, 4 (geometries 1, 2, 2): rule_core3 less blind_core is -0.1 in PER and +5000 bit/s in each;
% only episode 1 has a detection-to-restored time in both rows, a single geometry: no interval, so n/a
r = L.core.cnn3.rr;
verifyEqual(tc, r.per, [-0.1 -0.1 -0.1], 'AbsTol', 1e-9);
verifyEqual(tc, r.gput, [5000 5000 5000], 'AbsTol', 1e-6);
verifyEqual(tc, r.n_both, 1);
verifyEqual(tc, r.robust, {'yes', 'yes', 'n/a'});
verifyEqual(tc, [r.Us.per r.Us.gput r.Us.trec], [0.01 100 0.5]);
verifyEqual(tc, L.core.cnn.rr.robust, {'yes', 'yes', 'n/a'});    % rule_core less blind_core: -0.2 and +10000 bit/s
l = lines(contains(lines, 'receiver-robust (U_s from D2c') & contains(lines, 'rule_core3 (profile 3)'));
verifyNumElements(tc, l, 1);
verifyNotEmpty(tc, strfind(l{1}, 'PER difference -0.1000 [-0.1000, -0.1000] (U_s 0.01) yes'));
verifyNotEmpty(tc, strfind(l{1}, 'goodput +5000 [+5000, +5000] bit/s (U_s 100) yes'));
verifyEmpty(tc, strfind(l{1}, 'not available'));
Us.per = 0.5; save(fullfile('results', 'd2c_us.mat'), 'Us');    % an interval inside U_s is "no"
L = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20, struct('rr', true));
verifyEqual(tc, L.core.cnn3.rr.robust, {'no', 'yes', 'n/a'});
end

function test_rr_column_wiring_static_and_parse(tc)
e = strrep(fileread(which('evaluate_policies')), char(13), '');
verifyNumElements(tc, strfind(e, '[LK, lines] = lect_kpis(ALL, POL, LBL, iDQN, PP.scen, payload_bps, C.period_ms, struct(''rr'', true));'), 1);
src = strrep(fileread(which('lect_kpis')), char(13), '');
verifyNumElements(tc, regexp(src, 'rr_us\(\)', 'match'), 1);
verifyNumElements(tc, regexp(src, 'rr_column\(', 'match'), 3);
verifyNotEmpty(tc, strfind(src, 'the registered pair above stands'));
parses_ok(tc, 'lect_kpis'); parses_ok(tc, 'evaluate_policies');
end

function parses_ok(tc, name)
% The file parses: mtree does not raise on a syntax error, it returns an ERR root.
t = mtree(fileread(which(name)));
verifyNotEqual(tc, char(t.root.kind), 'ERR', sprintf('%s does not parse', name));
end
