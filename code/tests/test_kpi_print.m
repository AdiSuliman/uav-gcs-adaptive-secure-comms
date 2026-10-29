function tests = test_kpi_print
%TEST_KPI_PRINT  Tests of the output-only print fixes of the KPI summary (measure_all_kpis.m), the
%   report export (export_report_numbers.m), the KPI dashboard (build_kpi_dashboard.m) and the
%   edge map's held-recovery tables (edge_map.m), through kpi_print_text.m. Synthetic inputs in
%   temporary folders; no test data. A comparison against the base commit's measure_all_kpis
%   shows that no KPI value, target or status changed. Run from the repository root:
%   results = runtests('code/tests/test_kpi_print.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.base = '85484b0';                      % the commit the print fixes branch from
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- text builders ----------
function test_leave_out_weighted_and_labelled(tc)
% T9: the label of the DQN that flew, the share weighted by episode beside the plain average.
res = struct('combo', {'jamming+path_loss', 'tone_jamming+path_loss'}, 'n', {100, 300}, 'dqn_out', {0.90, 0.50}, ...
    'dqn_in', {0.96, 0.90}, 'rule', {0.40, 0.20}, 'table', {0.3, 0.3});
what = 'combined threats never trained on (leave-one-combination-out)';
[s, W] = kpi_print_text('leave_out', res, what, 'DQN + escalation', 'combinations');
verifyEqual(tc, [W.out_w, W.out_u, W.in_w, W.in_u, W.rule_w, W.rule_u, W.n, W.k], [0.6 0.7 0.915 0.93 0.25 0.3 400 2], ...
    'AbsTol', 1e-12);
for t = {[what ', DQN + escalation: 60.0% of the recoverable episodes, weighted by episode (400 episodes in 2 combinations)'], ...
        'averaged over the 2 combinations: 70.0%', 'trained on them: 91.5% weighted, 93.0% averaged', ...
        'rule + escalation: 25.0% weighted, 30.0% averaged', ...
        'lowest never trained: tone_jamming+path_loss 50.0%, jamming+path_loss 90.0%'}
    verifyTrue(tc, contains(s, t{1}), t{1});
end
s2 = kpi_print_text('leave_out', res, what, 'DQN gamma=0.50 (selected), deployed, no escalation', 'combinations');
verifyTrue(tc, contains(s2, 'DQN gamma=0.50 (selected), deployed, no escalation: 60.0%'));
verifyFalse(tc, contains(s2, 'DQN + escalation'));
s0 = kpi_print_text('leave_out', res([]), 'x', 'y', 'threats');
verifyEqual(tc, s0, 'x: no threats in the file');
end

function test_leave_out_threat_cases(tc)
% C2u: the threat field, the three lowest never-trained cases, no NaN printed.
res = struct('threat', {'jamming', 'noise_burst', 'path_loss', 'spoofing'}, 'n', {4316, 3276, 2258, 4320}, ...
    'dqn_out', {0.885, 0.301, 0.22, 0.807}, 'dqn_in', {0.872, 0.797, 0.798, 0.831}, 'rule', {0.689, 0.52, 0.815, 0.706});
[s, W] = kpi_print_text('leave_out', res, 'single threats never trained on (leave-one-threat-out, evidence only)', ...
    'DQN + escalation', 'threats');
verifyEqual(tc, W.lowest, {'path_loss 22.0%', 'noise_burst 30.1%', 'spoofing 80.7%'});
verifyEqual(tc, W.k, 4);
verifyTrue(tc, contains(s, 'weighted by episode (14170 episodes in 4 threats)'));
verifyFalse(tc, contains(s, 'NaN'));
res(2).dqn_out = NaN;
s = kpi_print_text('leave_out', res, 'x', 'y', 'threats');
verifyTrue(tc, contains(s, 'n/a'));
verifyFalse(tc, contains(s, 'NaN'));
end

function test_kpi1_lines_text(tc)
% T15: the all-frames reading and the headline each with their own interval; the stricter reading
% says 'not reached' where no threshold gives every class 90%.
m = metrics_fixture(true);
s = kpi_print_text('kpi1_all', m);
a = 'all frames, every Eb/N0: accuracy 95.01%, macro-F1 94.81% [94.35, 95.25] (95% bootstrap over sub-runs)';
b = ['the headline, from 0 dB (the threshold chosen on validation): macro-F1 94.93% [94.40, 95.30], ' ...
    'lowest class 84.46% (airframe_shadowing)'];
verifyTrue(tc, contains(s, a) && contains(s, b));
verifyLessThan(tc, strfind(s, a), strfind(s, b));
verifyTrue(tc, contains(kpi_print_text('kpi1_all', metrics_fixture(false)), 'macro-F1 94.93% (interval not saved), lowest class'));
m1 = m; m1.kpi1_threshold_db = NaN;
verifyTrue(tc, contains(kpi_print_text('kpi1_all', m1), 'the headline: not reached'));
e = kpi_print_text('kpi1_every', m);
verifyTrue(tc, contains(e, 'not reached: no Eb/N0 threshold chosen on validation gives every class an F1 of at least 90%'));
verifyTrue(tc, contains(e, 'at the headline threshold of 0 dB the lowest class is airframe_shadowing 84.46%'));
verifyFalse(tc, contains(e, 'NaN'));
m.every_class = struct('threshold_db', 9, 'macro_f1_above_threshold_pct', 96.5, 'class_f1_above_threshold_pct', [97 96.9 91]');
verifyTrue(tc, contains(kpi_print_text('kpi1_every', m), 'from 9 dB, macro-F1 96.50%, lowest class 91.00% (met)'));
m.every_class.class_f1_above_threshold_pct = [97 96.9 89]';
verifyTrue(tc, contains(kpi_print_text('kpi1_every', m), 'from 9 dB, macro-F1 96.50%, lowest class 89.00% (not met)'));
end

function test_kpi4_lower_bound_count(tc)
% T4: the count by the 95% lower bound beside the point estimates; the threats below 90 named.
names = {'a', 'b', 'c'};
s = kpi_print_text('kpi4_lower', names, [95 92 91], [91 97; 85 96; 90 93]);
verifyTrue(tc, contains(s, ['(the status above counts the point estimates, as registered): 2 of 3 threats have a lower bound ' ...
    '>= 90% (point estimates: 3 of 3); lower bound below 90%: b 85.0']));
s = kpi_print_text('kpi4_lower', names, [95 92 91], [91 97; 92 96; 90 93]);
verifyTrue(tc, endsWith(s, '3 of 3 threats have a lower bound >= 90% (point estimates: 3 of 3)'));
s = kpi_print_text('kpi4_lower', names, [95 92 91], [91 97; NaN NaN; 90 93]);
verifyTrue(tc, contains(s, '2 of 3 threats have a lower bound >= 90%') && contains(s, 'lower bound not saved for 1'));
verifyEmpty(tc, kpi_print_text('kpi4_lower', {'a'}, 95, [NaN NaN]));
verifyEmpty(tc, kpi_print_text('kpi4_lower', {}, [], zeros(0, 2)));
end

function test_kpi7_spread_committed_word(tc)
% T5: committed when the interval's upper bound is within the target.
s = kpi_print_text('kpi7_spread', [6.3 3.5 11.8], 10);
verifyTrue(tc, contains(s, 'point estimate 6.3 points, 95% interval upper bound 11.8, target <= 10 -> not committed (upper bound > 10)'));
verifyTrue(tc, contains(s, 'the status above counts the point estimate (within the target)'));
s = kpi_print_text('kpi7_spread', [6.3 3.5 9.9], 10);
verifyTrue(tc, contains(s, '-> committed (upper bound <= 10)'));
s = kpi_print_text('kpi7_spread', [12.5 10.5 14], 10);
verifyTrue(tc, contains(s, 'not committed') && contains(s, '(above the target)'));
verifyTrue(tc, contains(kpi_print_text('kpi7_spread', [6 NaN NaN], 10), 'not committed (no interval saved)'));
end

function test_edge_distance_text(tc)
% T18: the threat's nominal level is not read as an Eb/N0.
en = struct('ebno', 0:3:15, 'km', [1.57 1.11 0.79 0.56 0.40 0.28], 'delays', [1 2 7], ...
    'cells', {{'jamming 16 dB', 'path_loss 14 dB', 'spoofing nominal'}}, 'edge_commit_db', [NaN 6 NaN; 0 3 9], ...
    'edge_commit_km', [NaN 0.79 NaN; 1.57 1.11 0.56]);
s = kpi_print_text('edge_distance', en, [1 2 3]);
verifyTrue(tc, contains(s, 'jamming 16 dB: no COMMITTED point'));
verifyTrue(tc, contains(s, 'path_loss 14 dB: down to 6 dB Eb/N0 (0.79 km)'));
verifyTrue(tc, contains(s, 'spoofing nominal: no COMMITTED point'));
verifyTrue(tc, contains(s, 'the dB after a threat is its own nominal level, not an Eb/N0'));
verifyTrue(tc, contains(s, '0 dB 1.57 km | 3 dB 1.11 km | 6 dB 0.79 km | 9 dB 0.56 km | 12 dB 0.40 km | 15 dB 0.28 km'));
verifyTrue(tc, contains(s, 'delay 1'));
verifyFalse(tc, contains(s, 'jamming 16 dB none'));
s = kpi_print_text('edge_distance', en, 2);
verifyFalse(tc, contains(s, 'jamming 16 dB'));
end

function test_edge_flight_share(tc)
% T3: a held-recovery verdict with two onsets per flight prints the fully held flights beside the
% episode share; one onset per flight and a rate print nothing more. The
% verdict, value and interval are edge_verdict.m's, unchanged.
held = zeros(2, 72); held(:, 1:62) = 1; held(1, 63:72) = 1;     % 62 flights hold both onsets, 10 hold one
V = edge_verdict(held(:)', ones(1, 144), repelem(1:72, 2), 0.9, 'ge', true);
verifyEqual(tc, V.value, 134 / 144, 'AbsTol', 1e-12);
verifyEqual(tc, [V.k, V.n], [62 72]);
verifyEqual(tc, V.verdict, 0);
verifyEqual(tc, kpi_print_text('edge_flight', V, '%5.1f'), ' fl  86.1');
verifyEqual(tc, kpi_print_text('edge_flight', V, '%5.2f'), ' fl 86.11');
V1 = edge_verdict(double((1:72) <= 66), ones(1, 72), 1:72, 0.9, 'ge', true);   % one unit per flight: one share
verifyEmpty(tc, kpi_print_text('edge_flight', V1, '%5.1f'));
Vr = edge_verdict(20 * double((1:72) <= 66), 20 * ones(1, 72), 1:72, 0.9, 'ge', false);   % a rate: k is NaN
verifyTrue(tc, isnan(Vr.k));
verifyEmpty(tc, kpi_print_text('edge_flight', Vr, '%5.1f'));
verifyEmpty(tc, kpi_print_text('edge_flight', struct('value', 0.5, 'n', 3), '%5.1f'));
% the share the interval is built on: its lower bound is the exact interval's hull with the bootstrap's
lo = betaincinv(0.025, 62, 11);
verifyLessThanOrEqual(tc, V.lo, lo + 1e-9);
end

function test_text_helpers(tc)
t = 'inside the envelope predicted on validation: lowest threat antenna_fault 78.9%, 23 of 24 threats >= 90%';
c = kpi_print_text('wrap', t, 40);
verifyTrue(tc, all(cellfun(@numel, c) <= 40));
verifyEqual(tc, strjoin(c, ' '), t);
verifyEqual(tc, kpi_print_text('wrap', 'supercalifragilisticexpialidocious', 10), {'supercalifragilisticexpialidocious'});
c0 = kpi_print_text('wrap', '', 10);
verifyTrue(tc, iscell(c0) && isscalar(c0) && isempty(c0{1}));
for n = [3 8 12]
    p = kpi_print_text('palette', n);
    verifyEqual(tc, size(p), [n 3]);
    verifyEqual(tc, size(unique(p, 'rows'), 1), n);
end
loss = [0.9886 0.8120 0.3970 0.1285 0.0462 0.0236];
L = kpi_print_text('link_limited', loss, 2);
verifyEqual(tc, L, logical([1 1 0 0 0 0]));
verifyEqual(tc, kpi_print_text('link_limited', [0.5 0.4999 NaN], 2), logical([1 0 0]));
verifyEqual(tc, kpi_print_text('ebno_ticks', 0:3:15, L), {'0 L', '3 L', '6', '9', '12', '15'});
Em = struct('EM', struct('ebno', 0:3:15, 'clean', struct('link', struct('value', num2cell(loss)))));
verifyEqual(tc, kpi_print_text('edge_limited', Em, 0:3:15, 2), L);
verifyEqual(tc, kpi_print_text('edge_limited', Em, [3 15 20], 2), logical([1 0 0]));
verifyEqual(tc, kpi_print_text('edge_limited', [], 0:3:15, 2), false(1, 6));
verifyEqual(tc, kpi_print_text('edge_limited', struct('EM', struct('ebno', 0:3:9, 'clean', struct('link', struct('value', {0.9, 0.8})))), ...
    0:3:9, 2), false(1, 4));
g = kpi_print_text('gcsa', {'=== DIRECTIONAL GCS ANTENNA ===', '', 'System: 12 dBi tracked: +10.0 dB over the omni.'});
verifyEqual(tc, g, 'directional GCS antenna on the uplink (results/gcs_antenna.txt): 12 dBi tracked: +10.0 dB over the omni.');
verifyEqual(tc, kpi_print_text('gcsa', {'no system line'}), 'directional GCS antenna on the uplink (results/gcs_antenna.txt)');
verifyError(tc, @() kpi_print_text('nope'), 'kpi_print_text:cmd');
end

%% ---------- the KPI summary ----------
function test_summary_kpi1_headline_interval(tc)
% T15 in the summary: the KPI's value, target and status are the registered ones.
work_dir(tc);
metrics = metrics_fixture(true); %#ok<NASGU>
save(kpi1_file('eval_detector_metrics'), 'metrics');
evalc('measure_all_kpis');
S = load('results/kpi_summary.mat', 'KPI'); k1 = S.KPI([S.KPI.id] == 1);
verifyEqual(tc, k1.value, 'macro-F1 94.93%, lowest class 84.46%, from 0 dB');
verifyEqual(tc, k1.status, 'MET');
d = k1.detail;
verifyTrue(tc, any(startsWith(d, 'all frames, every Eb/N0: accuracy 95.01%, macro-F1 94.81% [94.35, 95.25]')));
verifyTrue(tc, any(contains(d, 'the headline, from 0 dB (the threshold chosen on validation): macro-F1 94.93% [94.40, 95.30]')));
verifyTrue(tc, any(contains(d, 'not reached: no Eb/N0 threshold chosen on validation gives every class')));
verifyFalse(tc, any(contains(d, 'NaN')));
end

function test_summary_decision_lines(tc)
% T9, T8, T4, T5 in the summary, for a deployed DQN without and with the escalation: the label of
% the DQN the leave-one-out experiments fly, C2u and the GCS antenna report in the summary, the
% lower-bound count and the committed word of the speed spread; the registered values stay.
for dep = {'dqn_g1', 'dqn_esc'}
    work_dir(tc);
    write_policy(dep{1});
    write_leave_out_files();
    evalc('measure_all_kpis');
    S = load('results/kpi_summary.mat', 'KPI'); K = S.KPI;
    d4 = K([K.id] == 4).detail; d7 = K([K.id] == 7).detail;
    lab = 'DQN + escalation';
    if strcmp(dep{1}, 'dqn_g1'), lab = 'DQN gamma=0.50 (selected), deployed, no escalation'; end
    ic = find(startsWith(d4, 'combined threats never trained on (leave-one-combination-out)'));
    verifyNumElements(tc, ic, 1);
    verifyTrue(tc, startsWith(d4{ic}, ['combined threats never trained on (leave-one-combination-out), ' lab ': 60.0% of the ' ...
        'recoverable episodes, weighted by episode (400 episodes in 2 combinations); averaged over the 2 combinations: 70.0%']));
    iu = find(startsWith(d4, 'single threats never trained on (leave-one-threat-out, evidence only)'));
    verifyNumElements(tc, iu, 1);
    verifyTrue(tc, contains(d4{iu}, [', ' lab ': ']) && contains(d4{iu}, 'lowest never trained: path_loss 22.0%, noise_burst 30.1%'));
    verifyTrue(tc, any(strcmp(d4, ['directional GCS antenna on the uplink (results/gcs_antenna.txt): 12 dBi tracked: +10.0 dB ' ...
        'over the omni on the same radio.'])));
    ip = find(startsWith(d4, 'inside the envelope, per threat:'));
    il = find(startsWith(d4, 'inside the envelope, by the 95% lower bound'));
    verifyEqual(tc, il, ip + 1);
    verifyTrue(tc, contains(d4{il}, ['1 of 3 threats have a lower bound >= 90% (point estimates: 2 of 3); lower bound below 90%: ' ...
        'tone_jamming 85.0, path_loss 80.0']));
    verifyEqual(tc, K([K.id] == 4).value, ['inside the envelope predicted on validation: lowest threat path_loss 88.0%, ' ...
        '2 of 3 threats >= 90%']);
    verifyEqual(tc, K([K.id] == 4).status, 'NOT MET');
    isp = find(startsWith(d7, 'spread over the speed bands 6.0 points [3.5, 11.8]'));
    verifyNumElements(tc, isp, 1);
    verifyTrue(tc, startsWith(d7{isp + 1}, 'speed spread, committed reading: point estimate 6.0 points, 95% interval upper bound 11.8'));
    verifyTrue(tc, contains(d7{isp + 1}, '-> not committed (upper bound > 10)'));
    verifyEqual(tc, K([K.id] == 7).status, 'PENDING');
end
end

function test_summary_output_only_against_base(tc)
% Against the base commit's measure_all_kpis on the same results: every KPI's id, name, value,
% target and status, and the revised proposal's readings (LECT), are equal; the details differ
% only in the reworked or added lines.
work_dir(tc);
metrics = metrics_fixture(true); %#ok<NASGU>
save(kpi1_file('eval_detector_metrics'), 'metrics');
write_policy('dqn_g1');
write_leave_out_files();
b = base_copy(tc, 'code/evaluation/measure_all_kpis.m', tc.TestData.base);
addpath(b, '-begin'); clear measure_all_kpis
cl = onCleanup(@() fixture_off(b, 'measure_all_kpis')); %#ok<NASGU>
verifyFalse(tc, startsWith(which('measure_all_kpis'), fullfile(tc.TestData.root, 'code')));
evalc('measure_all_kpis');
S0 = load('results/kpi_summary.mat', 'KPI', 'LECT');
fixture_off(b, 'measure_all_kpis');
verifyTrue(tc, startsWith(which('measure_all_kpis'), fullfile(tc.TestData.root, 'code')));
evalc('measure_all_kpis');
S1 = load('results/kpi_summary.mat', 'KPI', 'LECT');
verifyEqual(tc, [S1.KPI.id], [S0.KPI.id]);
for k = 1:numel(S0.KPI)
    for f = {'id', 'name', 'value', 'target', 'status'}
        verifyEqual(tc, S1.KPI(k).(f{1}), S0.KPI(k).(f{1}), sprintf('KPI %d %s', S0.KPI(k).id, f{1}));
    end
    gone = setdiff(S0.KPI(k).detail, S1.KPI(k).detail);
    new = setdiff(S1.KPI(k).detail, S0.KPI(k).detail);
    for i = 1:numel(gone)
        verifyTrue(tc, startsWith(gone{i}, {'accuracy ', 'beside KPI 1, every class F1 >= 90%', ...
            'combined threats never trained on'}), ['removed: ' gone{i}]);
    end
    for i = 1:numel(new)
        verifyTrue(tc, startsWith(new{i}, {'all frames, every Eb/N0', 'beside KPI 1, every class F1 >= 90%', ...
            'combined threats never trained on', 'single threats never trained on', 'directional GCS antenna', ...
            'inside the envelope, by the 95% lower bound', 'speed spread, committed reading'}), ['added: ' new{i}]);
    end
end
verifyTrue(tc, isequaln(S1.LECT, S0.LECT));
end

%% ---------- the report export ----------
function test_export_c2u_and_gcsa(tc)
% T8: the leave-one-threat-out policy test (not its episodes) and the GCS antenna report's lines are
% in report_numbers.json; the KPI summary is flagged old against them.
work_dir(tc);
write_policy('dqn_esc');
write_leave_out_files();
evalc('measure_all_kpis');
pause(1.1);
res = struct('threat', {'jamming', 'path_loss'}, 'n', {10, 20}, 'dqn_out', {0.9, 0.2}, 'dqn_in', {0.9, 0.8}, ...
    'rule', {0.7, 0.8}, 'ci_out', {[0.8 1], [0.1 0.3]}, 'ci_in', {[0.8 1], [0.7 0.9]});
EP = struct('x', 1); %#ok<NASGU>
save('results/unknown_threat_policy.mat', 'res', 'EP');
lastwarn('');
evalc('export_report_numbers');
[msg, id] = lastwarn;
verifyEqual(tc, id, 'export_report_numbers:stale');
verifyTrue(tc, contains(msg, 'results/unknown_threat_policy.mat'));
J = jsondecode(fileread('results/report_numbers.json'));
verifyEqual(tc, {J.unknown_policy.threat}, {'jamming', 'path_loss'});
verifyEqual(tc, [J.unknown_policy.dqn_out], [0.9 0.2], 'AbsTol', 1e-12);
verifyFalse(tc, isfield(J, 'EP'));
verifyFalse(tc, isfield(J.unknown_policy, 'out'));
verifyTrue(tc, any(startsWith(J.gcs_antenna, 'System: 12 dBi tracked')));
verifyEqual(tc, numel(J.combo), 2);
end

%% ---------- the dashboard ----------
function test_dashboard_runs_with_fixes(tc)
% T17: the dashboard draws from synthetic results; the edge map's clean link tags KPI 5's points.
work_dir(tc);
old = get(0, 'DefaultFigureVisible'); set(0, 'DefaultFigureVisible', 'off');
tc.addTeardown(@() set(0, 'DefaultFigureVisible', old));
write_ood();
write_policy('dqn_g1');
write_leave_out_files();
evalc('measure_all_kpis');
loss = [0.9886 0.8120 0.3970 0.1285 0.0462 0.0236];
EM = struct('ebno', 0:3:15, 'clean', struct('link', struct('value', num2cell(loss)))); %#ok<NASGU>
save('results/edge_map.mat', 'EM');
evalc('build_kpi_dashboard');
f = dir('results/kpi_dashboard.png');
verifyNumElements(tc, f, 1);
verifyGreaterThan(tc, f.bytes, 20000);
movefile('results/edge_map.mat', 'results/edge_map_off.mat');     % without the edge map: no tags, still drawn
movefile('results/kpi_dashboard.png', 'results/kpi_dashboard_with_tags.png');
evalc('build_kpi_dashboard');
verifyTrue(tc, isfile('results/kpi_dashboard.png'));
end

%% ---------- wiring ----------
function test_wiring_of_the_print_fixes(tc)
mk = fileread(which('measure_all_kpis'));
for t = {'kpi_print_text(''kpi1_all'', m)', 'kpi_print_text(''kpi1_every'', m)', 'kpi_print_text(''kpi4_lower'', te, pe(he), eci(he, :))', ...
        'kpi_print_text(''kpi7_spread'', P.KP.speed_spread, 10)', 'kpi_print_text(''edge_distance'', en, inom)', ...
        'kpi_print_text(''leave_out'', Cg.res', 'kpi_print_text(''leave_out'', Cu.res', 'kpi_print_text(''gcsa'', splitlines(fileread(F.gcsa)))', ...
        '''unk'', ''results/unknown_threat_policy.mat'', ''gcsa'', ''results/gcs_antenna.txt'''}
    verifyNotEmpty(tc, strfind(mk, t{1}), t{1});
end
verifyEmpty(tc, strfind(mk, 'ec = m.every_class;'));
verifyEmpty(tc, strfind(mk, 'edge_km('));
% the registered rules are as they were: KPI 4 counts the point estimates, KPI 7 the point spread
verifyNotEmpty(tc, strfind(mk, 'status(any(he) && all(pe(he) >= 90), stale), det);'));
verifyNotEmpty(tc, strfind(mk, 'st7 = status(lat_ok && max(pv) - min(pv) <= 10, stale);'));
em = fileread(which('edge_map'));
verifyNotEmpty(tc, strfind(em, 'cell_txt(PT.(LAY{f})(i, s), fmt, fl)'));
verifyNotEmpty(tc, strfind(em, 'cell_txt(PT.(q{1})(i, s), ''%5.1f'', true)'));
verifyNotEmpty(tc, strfind(em, 'kpi_print_text(''edge_flight'', V, f)'));
verifyNotEmpty(tc, strfind(em, 'fl = f == 4 || f == 5;'));
ex = fileread(which('export_report_numbers'));
verifyNotEmpty(tc, strfind(ex, 'N.unknown_policy = take(''results/unknown_threat_policy.mat'', ''res'');'));
verifyNotEmpty(tc, strfind(ex, 'N.gcs_antenna = take_lines(''results/gcs_antenna.txt'');'));
db = fileread(which('build_kpi_dashboard'));
for t = {'kpi_print_text(''palette'', size(P.KP.per_ebno, 2))', 'kpi_print_text(''ebno_ticks'', P.KP.ebno, Ll)', ...
        'kpi_print_text(''edge_limited'', Em, P.KP.ebno, decision_config().ratio_ok)', 'kpi_print_text(''wrap'', q.value, 58)', ...
        'legend(ax, hA, P.KP.show_lbl', 'legend(ax, [hb, hx]', 'legend(ax, [hb, ht], names'}
    verifyNotEmpty(tc, strfind(db, t{1}), t{1});
end
verifyEmpty(tc, strfind(db, '''r--'', ''90%'')'));
end

%% ---------- fixtures ----------
function d = work_dir(tc)
% A temporary working folder with results/ and data/, entered; left and removed at the test's end.
d = tempname; mkdir(fullfile(d, 'results')); mkdir(fullfile(d, 'data'));
tc.addTeardown(@() rmdir(d, 's'));
tc.addTeardown(@() cd(tc.TestData.cwd));
cd(d);
end

function m = metrics_fixture(with_ci)
% eval_detector.m's metrics, reduced to the fields measure_all_kpis.m reads for KPI 1; the headline
% threshold 0 dB, no Eb/N0 threshold for the stricter reading.
m = struct('overall_accuracy_pct', 95.01, 'macro_f1_pct', 94.81, 'ci95', struct('macro_f1', [94.35 95.25]), ...
    'classes', {{'none', 'jamming', 'airframe_shadowing'}}, 'class_f1_above_threshold_pct', [94.5 96.3 84.46]', ...
    'snr_breakdown', struct('snr_db', {0, 3}, 'macro_f1_pct', {92.3, 94.5}), 'macro_f1_above_threshold_pct', 94.93, ...
    'kpi1_threshold_db', 0);
if with_ci, m.ci95.macro_f1_above = [94.40 95.30]; end
m.every_class = struct('threshold_db', NaN, 'macro_f1_above_threshold_pct', NaN, 'class_f1_above_threshold_pct', nan(3, 1));
end

function write_policy(deployed)
% results/policy_evaluation.mat reduced to what measure_all_kpis.m and build_kpi_dashboard.m read
% (no identity: the file is not stale without a trained DQN). deployed: 'dqn_g1' (the DQN without
% the escalation) or 'dqn_esc'.
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_g1', 'dqn_esc', 'oracle'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', ...
    'DQN gamma=0.50 (selected)', 'DQN + escalation', 'oracle'};
iDQN = find(strcmp(POL, deployed)); LBL{iDQN} = [LBL{iDQN} ' (deployed)'];
n = 40;
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = struct('recoverable', true(1, n), 'threat', true(1, n), 'geom', repelem(1:10, 4), 'ok_post', 0.5 * ones(1, n), ...
        'gput_post', 0.5 * ones(1, n));
    R.recovered = mod(1:n, 10) < min(9, k);
    R.t_rec = nan(1, n); R.t_rec(R.recovered) = 3;
    ALL{k} = R;
end
show = {'none', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_g1', 'dqn_esc', 'oracle'};
hdr = {'no resp.', 'fixed best', 'rule+esc', 'no det.+esc', 'table', 'DQN', 'DQN+esc', 'oracle'};
nS = numel(show);
KP = struct('threats', {{'jamming', 'tone_jamming', 'path_loss'}}, 'show', {show}, 'show_lbl', {hdr}, ...
    'per_threat', repmat([96; 92; 88], 1, nS), 'recoverable_share', ones(3, 1), 'sev_names', {{'nominal'}}, ...
    'per_threat_sev', 95 * ones(3, 1, nS), ...
    'far', struct('policy', {LBL{iDQN}, LBL{4}}, 'k', {1, 11}, 'n', {700, 700}, 'upper', {0.01, 0.03}, 'per_cycle', {1e-4, 2e-4}), ...
    'ebno_thr', 3, 'ebno', 0:3:15, 'per_ebno', repmat(linspace(40, 95, 6)', 1, nS), 'per_aoa', repmat([90; 80; 70], 1, nS), ...
    'aoa_bins', [0 20 45 90], 'per_speed', [95 * ones(1, nS); 89 * ones(1, nS)], 'speed_bins', [0 80 161], ...
    'speed_spread', [6 3.5 11.8], 'envelope', true(3, 1), 'envelope_val', ones(3, 1), 'env_rule', [90 10], ...
    'per_threat_env', [96 92 88], 'per_threat_env_ci', [93 98; 85 95; 80 92]);
RES = {}; set_names = {'single'}; %#ok<NASGU>
save('results/policy_evaluation.mat', 'RES', 'POL', 'LBL', 'set_names', 'iDQN', 'KP', 'ALL');
end

function write_leave_out_files()
% C2g and C2u results (the fields of experiment_combo_generalization.m and experiment_unknown_threat.m)
% and the GCS antenna report.
res = struct('combo', {'jamming+path_loss', 'tone_jamming+path_loss'}, 'n', {100, 300}, 'dqn_out', {0.90, 0.50}, ...
    'dqn_in', {0.96, 0.90}, 'rule', {0.40, 0.20}, 'table', {0.3, 0.3}, 'ci_out', {[0.8 0.95], [0.4 0.6]}, ...
    'ci_in', {[0.9 1], [0.8 0.95]}); %#ok<NASGU>
save('results/combo_generalization.mat', 'res');
res = struct('threat', {'jamming', 'noise_burst', 'path_loss', 'spoofing'}, 'n', {4316, 3276, 2258, 4320}, ...
    'dqn_out', {0.885, 0.301, 0.22, 0.807}, 'dqn_in', {0.872, 0.797, 0.798, 0.831}, 'rule', {0.689, 0.52, 0.815, 0.706}, ...
    'ci_out', {[0.8 0.9], [0.2 0.4], [0.1 0.3], [0.7 0.9]}, 'ci_in', {[0.8 0.9], [0.7 0.8], [0.7 0.8], [0.8 0.9]}); %#ok<NASGU>
EP = struct('x', 1); %#ok<NASGU>
save('results/unknown_threat_policy.mat', 'res', 'EP');
fid = fopen('results/gcs_antenna.txt', 'w');
fprintf(fid, '%s\n', strjoin({'=== DIRECTIONAL GCS ANTENNA ON THE UPLINK (Israel / ETSI e.i.r.p. cap) ===', '', ...
    'System: 12 dBi tracked: +10.0 dB over the omni on the same radio.'}, newline));
fclose(fid);
end

function write_ood()
% The unknown-threat detection result of test_core.m's KPI 2 test (three threats' worth of fields).
SC = {'msp', 'energy', 'iforest', 'last', 'raw'}; WIN = [2 5 8]; RETAIN = 0.95; sel = 'last'; sel_win = 5;
R = struct('held_out', {'jamming', 'tone_jamming'}, 'auroc', {[0.6 0.6 0.6 0.81 0.7], [0.6 0.6 0.6 0.83 0.7]}, ...
    'fpr95', {[0.5 0.5 0.5 0.41 0.6], [0.5 0.5 0.5 0.43 0.6]}, 'auroc_win', {0.9 * ones(5, 3), 0.9 * ones(5, 3)});
pj = repelem(4:5, 4); pw = repmat([1 WIN], 1, 2);
MpT = repmat(0.1 * (1:8), 2, 1); FpT = MpT / 10; MpV = MpT; %#ok<NASGU>
NEST = struct('auroc', [0.84 0.86], 'fpr95', [0.31 0.33], 'auroc_val', [0.8 0.8], 'pick', {{'last over 5', 'last over 5'}}); %#ok<NASGU>
TEST_SET = 'second test set'; %#ok<NASGU>
save('results/ood_detection.mat', 'R', 'SC', 'sel', 'sel_win', 'NEST', 'WIN', 'RETAIN', 'MpV', 'MpT', 'FpT', 'pj', 'pw', 'TEST_SET');
end

function d = base_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy queue's)
% reads the commit from the repository named by V7_GIT_REPO. The test is filtered when the commit
% cannot be read.
d = tempname; mkdir(d);
tc.addTeardown(@() rmdir_if(d));
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, fullfile(d, [nm ext])));
assumeEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function fixture_off(d, fn)
% Removes a base-commit folder from the path (once).
if contains(path, d), rmpath(d); end
clear(fn);
end

function rmdir_if(d)
if isfolder(d), rmdir(d, 's'); end
end
