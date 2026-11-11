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

function parses_ok(tc, name)
% The file parses: mtree does not raise on a syntax error, it returns an ERR root.
t = mtree(fileread(which(name)));
verifyNotEqual(tc, char(t.root.kind), 'ERR', sprintf('%s does not parse', name));
end
