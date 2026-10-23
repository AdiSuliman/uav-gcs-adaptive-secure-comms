function tests = test_c2e_lect
%TEST_C2E_LECT  Unit tests of the isolated reading of profile 1's C2e (c2e_lect.m): the gate,
%   the reading, the port onto profile 1's code (its numbers unchanged), and the revised
%   proposal's readers, the latter word for word as on branch lect-kpi. Run from the
%   repository root: results = runtests('code/tests/test_c2e_lect.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- the gate ----------
function test_gate_pass(tc)
% The isolated run's file passes when it holds profile 1's numbers and only the differences
% fixed in advance: the two core policies appended, the four per-episode fields, lect_in and
% the text's 'Generated:' line and core rows.
[P, S, tP, tS] = gate_world();
G = c2e_lect_gate(P, S, tP, tS);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
verifyEmpty(tc, G.mismatch);
verifyGreaterThan(tc, G.n_compared, 50);
verifyTrue(tc, startsWith(G.lines{1}, 'GATE PASS'));
S2 = rmfield(S, 'lect_in');                                 % lect_in is allowed, never required
verifyTrue(tc, c2e_lect_gate(P, S2, tP, tS).pass);
P.RW = {}; S.RW = {};                                       % no clean pools in either
verifyTrue(tc, c2e_lect_gate(P, S, tP, tS).pass);
end

function test_gate_mismatch(tc)
% Every other difference stops the reading, a last-bit one included, and is named.
[P, S, tP, tS] = gate_world();
chk = @(S1, t1, pat) verify_fail(tc, c2e_lect_gate(P, S1, tP, t1), pat);
X = S; X.RES{1, 2}.ret(3) = X.RES{1, 2}.ret(3) + eps(X.RES{1, 2}.ret(3));
chk(X, tS, 'RES{1,2} (single, rule_esc).ret differs (1 of 4 values');
X = S; X.ALL{3}.recovered(1) = ~X.ALL{3}.recovered(1); chk(X, tS, 'ALL{3} (blind_esc).recovered differs');
X = S; X.RW{1}.switches(2) = 1; chk(X, tS, 'RW{1} (none).switches differs');
X = S; X.RES{2, 1}.extra = 1; chk(X, tS, 'fields not allowed: extra');
X = S; X.RES{2, 1} = rmfield(X.RES{2, 1}, 'ret'); chk(X, tS, 'fields missing in the isolated run: ret');
X = S; X.KP.far(2).k = 99; chk(X, tS, 'KP.far differs on profile 1''s policies');
X = S; X.KP.far(end) = []; chk(X, tS, 'KP.far: rows beside profile 1''s policies');
X = S; X.KP.per_threat(1) = NaN; chk(X, tS, 'KP.per_threat differs');
X = S; X.KP.newfield = 1; chk(X, tS, 'KP fields differ: newfield');
X = S; X.fixed_best = 2; chk(X, tS, 'fixed_best differs');
X = S; X.POL([2 3]) = X.POL([3 2]); chk(X, tS, 'POL: profile 1');
X = S; X.LBL{end} = 'core: other'; chk(X, tS, 'LBL:');
X = S; X.other = 1; chk(X, tS, 'variables not allowed in the isolated run: other');
X = S; X.RES(:, end) = []; chk(X, tS, 'RES:');
t = tS; t{4} = [t{4} ' ']; chk(S, t, 'first difference at line 3');
t = tS; t(end + 1) = {'core: rule + escalation  1 2 3'}; verifyTrue(tc, c2e_lect_gate(P, S, tP, t).pass);  % a core row only
t = tS; t(end + 1) = {'rule + escalation  1 2 3'}; chk(S, t, 'policy_evaluation.txt');
X = S; X.KP.far(1).rate.hi = NaN; Y = P; Y.KP.far(1).rate.hi = NaN;
verifyTrue(tc, c2e_lect_gate(Y, X, tP, tS).pass);           % NaN equals NaN
end

function test_gate_text(tc)
% The text is compared line by line without the 'Generated:' line and the core rows.
[P, S, tP, tS] = gate_world();
tS{2} = 'Generated: 01-Jan-2027 00:00:00 | other';
verifyTrue(tc, c2e_lect_gate(P, S, tP, tS).pass);
verifyEqual(tc, sum(startsWith(strtrim(tS), 'core: ')), 4);
G = c2e_lect_gate(P, S, tP, tS(1:end-1));
verifyFalse(tc, G.pass);
verifyTrue(tc, any(contains(G.mismatch, 'lines in profile 1')));
end

function verify_fail(tc, G, pat)
verifyFalse(tc, G.pass, pat);
verifyTrue(tc, any(contains(G.mismatch, pat)), sprintf('expected "%s" among: %s', pat, strjoin(G.mismatch, ' | ')));
verifyTrue(tc, startsWith(G.lines{1}, 'GATE FAIL'));
end

function [P, S, tP, tS] = gate_world()
% Profile 1's file (P, its text tP) and an isolated run that adds only what is allowed (S, tS).
POL = {'none', 'rule_esc', 'blind_esc'}; LBL = {'no response', 'rule + escalation', 'no detector + escalation'};
ep = @(k) struct('ret', [0.1 0.2 0.3 0.4] + k, 'recovered', logical([1 0 1 k > 1]), 'switches', [0 0 1 2], ...
    'recoverable', true(1, 4), 'scn', [2 2 3 3], 'aoa', nan(3, 4));
RES = cell(2, 3); for si = 1:2, for pk = 1:3, RES{si, pk} = ep(pk + si); end, end
RW = arrayfun(@(k) ep(k), 1:3, 'UniformOutput', false);
ALL = arrayfun(@(k) ep(10 * k), 1:3, 'UniformOutput', false);
far = struct('policy', LBL, 'k', {0, 3, 4}, 'n', 600, 'p', {0, 0.005, 1 / 150}, 'upper', 0.01, ...
    'per_cycle', 0, 'rate', struct('hi', 0.1));
KP = struct('per_threat', [90; 80], 'far', far, 'far_testpools', far, 'far_cleanpools', struct([]), ...
    'det_id', 'abc', 'policy_stamp', 'def', 'onset', struct('threat', {'jamming'}, 'n', 3));
KP.far = far; KP.far_testpools = far;
P = struct('RES', {RES}, 'RW', {RW}, 'POL', {POL}, 'LBL', {LBL}, 'set_names', {{'single', 'clean'}}, 'fixed_best', 5, ...
    'tab', struct('names', {{'a', 'b'}}), 'iDQN', 2, 'KP', KP, 'iThreat', 1, 'ALL', {ALL}, ...
    'top_cfg', struct('threat', 'jamming', 'action', 'channel_switch', 'share', 0.5));
S = P;
S.POL = [POL, {'rule_core', 'blind_core'}]; S.LBL = [LBL, {'core: rule + escalation', 'core: no detector + escalation'}];
S.RES = [cellfun(@with_new, RES, 'UniformOutput', false), {with_new(ep(7)), with_new(ep(8)); with_new(ep(7)), with_new(ep(8))}];
S.RW = [cellfun(@with_new, RW, 'UniformOutput', false), {with_new(ep(7)), with_new(ep(8))}];
S.ALL = [cellfun(@with_new, ALL, 'UniformOutput', false), {with_new(ep(7)), with_new(ep(8))}];
fc = struct('policy', {'core: rule + escalation', 'core: no detector + escalation'}, 'k', {5, 6}, 'n', 600, ...
    'p', 0.01, 'upper', 0.02, 'per_cycle', 0, 'rate', struct('hi', 0.1));
S.KP.far = [far, fc]; S.KP.far_testpools = [far, fc];
S.lect_in = struct('scen', {{'none', 'jamming'}});
tP = {'=== DECISION-LAYER EVALUATION, TEST POOLS ===', 'Generated: 01-Nov-2026 10:00:00 | 30-cycle episodes', ...
    'policy                                  recovered', 'no response                              0.0 [0.0, 0.0]', ...
    'rule + escalation                        90.0 [88.0, 92.0]', 'no detector + escalation                 80.0 [78.0, 82.0]', ...
    '  no response                                 0 /  600 =   0.00%', '  rule + escalation                           3 /  600 =   0.50%'};
tS = [tP(1:6), {'core: rule + escalation                  85.0 [83.0, 87.0]', ...
    'core: no detector + escalation           75.0 [73.0, 77.0]'}, tP(7:8), ...
    {'  core: rule + escalation                     5 /  600 =   0.83%', '  core: no detector + escalation              6 /  600 =   1.00%'}];
tS{2} = 'Generated: 02-Nov-2026 11:00:00 | 30-cycle episodes';
end

function R = with_new(R)
% An episode result with the fields the isolated run adds.
R.per_post = [0.1 0.2 0.3 0.4]; R.dlv_post = ones(1, 4); R.t_rec_det = [1 NaN 2 3]; R.recoverable_core = true(1, 4);
end

%% ---------- the port onto profile 1's code ----------
function test_port_matches_profile1_code(tc)
% The files this branch changed in profile 1's code (208602b) give every policy the same
% episodes, frame by frame, as profile 1's own versions: their results agree in every field
% profile 1's code gives, and the tables in every field they hold; the new ones are only added.
root = tc.TestData.root;
st = system(sprintf('git -C "%s" cat-file -e 208602b^{commit}', root));
assumeEqual(tc, st, 0, 'git or profile 1''s commit 208602b is not available here');
old = fullfile(tc.TestData.tmp, 'p1code'); if ~isfolder(old), mkdir(old); end
for f = {'code/decision/link_env.m', 'code/decision/rollout_policy.m', 'code/decision/policy_decide.m', ...
        'code/decision/policy_setup.m', 'code/decision/decision_config.m'}
    [~, nm, ext] = fileparts(f{1});
    st = system(sprintf('git -C "%s" show 208602b:%s > "%s"', root, f{1}, fullfile(old, [nm ext])));
    verifyEqual(tc, st, 0);
end
fn = {'link_env', 'rollout_policy', 'policy_decide', 'policy_setup', 'decision_config'};
here = pwd; c = onCleanup(@() cd(here));
specs = {struct('scn', [2 2 1 2], 's', [1 2 1 1], 'onset', [3 5 3 4], 'follow', [false true false true], ...
    'fdelay', [0 2 0 3], 'unk', [false false false true], 'T', 25, 'r', [1 1 1 1]), ...
    struct('scn', [2 2], 's', [1 2], 'onset', [3 4], 'follow', [true false], 'fdelay', [1 0], 'unk', [false false], ...
    'T', 25, 'r', [1 1], 'comb', [true false])};
kinds = {'fixed', 'rule', 'rule_esc', 'blind_esc', 'oracle', 'random'};
for hop = [false true]
    out = cell(1, 2);
    for v = 1:2
        if v == 1, cd(old); else, cd(here); end
        clear(fn{:}); rehash;
        verifyEqual(tc, isfield(decision_config(), 'core_actions'), v == 2);   % the version in use
        [PP, K] = toy_world(true, hop);
        R = {};
        for b = 1:numel(specs)
            for k = 1:numel(kinds)
                opt = struct(); if strcmp(kinds{k}, 'fixed'), opt.fixed = K.na; end
                R{end+1} = rollout_policy(kinds{k}, PP, K, specs{b}, 1, [], opt, 10 * b + k); %#ok<AGROW>
            end
        end
        out{v} = struct('K', K, 'R', {R});
    end
    cd(here); clear(fn{:}); rehash;
    verifyEqual(tc, setdiff(fieldnames(out{2}.K), fieldnames(out{1}.K)), {'rec_core'; 'rec_core_comb'});
    for f = fieldnames(out{1}.K)'
        verifyTrue(tc, isequaln(out{1}.K.(f{1}), out{2}.K.(f{1})), sprintf('K.%s', f{1}));
    end
    for j = 1:numel(out{1}.R)
        Ro = out{1}.R{j}; Rn = out{2}.R{j};
        verifyEqual(tc, sort(setdiff(fieldnames(Rn), fieldnames(Ro))), sort({'per_post'; 'dlv_post'; 't_rec_det'; 'recoverable_core'}));
        for f = fieldnames(Ro)'
            verifyTrue(tc, isequaln(Ro.(f{1}), Rn.(f{1})), sprintf('rollout %d, %s', j, f{1}));
        end
    end
end
end

function test_link_env_core_recoverable(tc)
% recoverable_core: some configuration of the core action set restores the geometry, under a
% comb jammer one without channel_switch and freq_diversity; never without recoverable.
[PP, K] = toy_world(true);                                   % channel_switch escapes: core
verifyEqual(tc, K.rec_core, K.recoverable);
verifyTrue(tc, all(K.rec_core_comb(:) <= K.recoverable_comb(:)));
[PPf, Kf] = toy_fd_world();                                  % freq_diversity alone escapes
verifyTrue(tc, all(Kf.recoverable(2, :, 1, 1)));
verifyFalse(tc, any(Kf.rec_core(2, :, 1, 1)));
verifyTrue(tc, all(Kf.rec_core(:) <= Kf.recoverable(:)));
spec = struct('scn', [2 2], 's', [1 1], 'onset', [3 3], 'follow', false(1, 2), 'fdelay', [0 0], 'unk', false(1, 2), ...
    'T', 20, 'r', [1 1], 'comb', [false true]);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', K.na), 4);
verifyEqual(tc, [R.recoverable; R.recoverable_core], [true false; true false]);
R = rollout_policy('fixed', PPf, Kf, spec, 1, [], struct('fixed', Kf.na), 4);
verifyEqual(tc, [R.recoverable; R.recoverable_core], [true false; false false]);
end

function test_rollout_per_fields(tc)
% rollout_policy.m gives every episode its PER, delivered payload and recovery time from the
% detection: the static link under a jammer loses every packet, a configuration the jammer
% cannot reach loses none and delivers its goodput factor; detection time plus the recovery
% from it is T_rec where BER and packet loss restore together.
[PP, K] = toy_world(true);
fd = find(strcmp(PP.actions, 'freq_diversity'));
spec = struct('scn', [2 2], 's', [1 1], 'onset', [3 3], 'follow', false(1, 2), 'fdelay', [0 0], 'unk', false(1, 2), ...
    'T', 20, 'r', [1 1]);
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', K.na), 4);
verifyEqual(tc, [R.per_post, R.dlv_post], [1 1 0 0]);
verifyTrue(tc, all(isnan(R.t_rec_det)));
R = rollout_policy('fixed', PP, K, spec, 1, [], struct('fixed', fd), 4);
verifyEqual(tc, [R.per_post, R.dlv_post], [0 0 1 1]);
PP.gp(fd) = 0.5; K2 = link_env('tables', PP);
R = rollout_policy('fixed', PP, K2, spec, 1, [], struct('fixed', fd), 4);
verifyEqual(tc, R.dlv_post, [0.5 0.5]);
R = rollout_policy('rule_esc', PP, K, spec, 1, [], struct(), 8);
d = isfinite(R.t_rec_det);
verifyTrue(tc, any(d));
verifyEqual(tc, R.t_conf(d) + R.t_rec_det(d), R.t_rec(d));
end

function test_evaluate_policies_source(tc)
% evaluate_policies.m appends the two core policies after every other one and saves lect_in;
% the revised proposal's readings come only after the gate (c2e_lect.m), never inside C2e.
src = fileread(which('evaluate_policies'));
verifyNotEmpty(tc, strfind(src, 'POL = [POL, {''rule_core'', ''blind_core''}];'));
verifyNotEmpty(tc, strfind(src, '''iThreat'', ''ALL'', ''top_cfg'', ''lect_in'');'));
verifyEmpty(tc, strfind(src, 'lect_kpis('));
i1 = strfind(src, 'POL = [POL, {''rule_core'''); i0 = strfind(src, 'POL = [POL(1:end-1), {''rule_sel''}');
verifyGreaterThan(tc, i1, i0);
[kind, ~, opt] = policy_setup('rule_core', struct('agent', []), 1, 1, 1, [], 1);
verifyEqual(tc, {kind, opt.core}, {'rule_esc', true});
[kind, ~, opt] = policy_setup('blind_core', struct('agent', []), 1, 1, 1, [], 1);
verifyEqual(tc, {kind, opt.core}, {'blind_esc', true});
end

%% ---------- the reading ----------
function test_c2e_lect_guard(tc)
% The steps run only in an isolated copy: its marker and its own code on the path.
d = fullfile(tc.TestData.tmp, 'notiso'); mkdir(d); here = pwd; c = onCleanup(@() cd(here)); cd(d);
verifyError(tc, @() c2e_lect('gate'), 'c2e_lect:isolation');
fid = fopen('C2E_LECT_ISOLATED', 'w'); fprintf(fid, 'test\n'); fclose(fid);
verifyError(tc, @() c2e_lect('gate'), 'c2e_lect:isolation');     % this branch's code is elsewhere
verifyError(tc, @() c2e_lect('other'), 'c2e_lect:step');
end

function test_c2e_lect_read(tc)
% The reading on a gated file: the KPI summary's PER, recovery and goodput lines for the full
% and the core action sets, lect_kpis.m's section, the three link states and the clean frames'
% false alarms of the KPI 1 reading, the false alarms of every system configuration.
d = fullfile(tc.TestData.tmp, 'iso'); mkdir(fullfile(d, 'results')); here = pwd; c = onCleanup(@() cd(here)); cd(d);
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle', 'rule_core', 'blind_core'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', ...
    'oracle', 'core: rule + escalation', 'core: no detector + escalation'};
[ALL, scen] = lect_world(POL); iDQN = 4; %#ok<NASGU>
kf = {'no response', 'rule + escalation', 'no detector + escalation', 'core: rule + escalation', 'core: no detector + escalation'};
far = struct('policy', kf, 'k', {0, 20, 30, 40, 10}, 'n', 600, 'p', {0, 20 / 600, 0.05, 40 / 600, 10 / 600}, ...
    'upper', {0.005, 0.049, 0.068, 0.088, 0.03});
KP = struct('far_src', 'test flights'); KP.far = far; %#ok<STRNU>
lect_in = struct('scen', {scen}, 'period_ms', 20, 'payload_bps', 5e4, 'det_id', 'abc'); %#ok<NASGU>
save('results/policy_evaluation.mat', 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'lect_in');
cls = {'none', 'jamming', 'tone_jamming', 'path_loss', 'benign_interference'};
cm = [90 2 1 4 3; 5 85 5 5 0; 2 3 90 5 0; 0 0 0 100 0; 0 0 0 0 100];
[i, j] = find(cm > 0); yt = {}; yp = {};
for k = 1:numel(i), yt = [yt, repmat(cls(i(k)), 1, cm(i(k), j(k)))]; yp = [yp, repmat(cls(j(k)), 1, cm(i(k), j(k)))]; end %#ok<AGROW>
metrics = struct('conf_mat', cm, 'classes', {cls}, 'kpi1_threshold_db', 5, 'test_set', 'third test set'); %#ok<NASGU>
pred = struct('y_true', categorical(yt(:), cls), 'y_pred', categorical(yp(:), cls), 'ebno', 10 * ones(numel(yt), 1)); %#ok<NASGU>
save('results/eval_detector_metrics_fresh2.mat', 'metrics'); save('results/detector_predictions_fresh2.mat', 'pred');
G = struct('pass', true, 'lines', {{'GATE PASS: 10 values and lines of profile 1''s C2e equal in the isolated run'}}, ...
    'det_id', 'abc', 'policy_stamp', 'def');
evalc('c2e_lect_read(G)');
t = splitlines(string(fileread('results/c2e_lect.txt')));
verifyEqual(tc, t(3), "GATE PASS: 10 values and lines of profile 1's C2e equal in the isolated run");
verifyTrue(tc, any(startsWith(t, 'beside KPI 4, PER vs the static link (revised proposal, full action set), PRIMARY per jamming scenario')));
verifyTrue(tc, any(startsWith(t, ['beside KPI 4, PER vs the static link (revised proposal, core action set {no_action, ' ...
    'channel_switch, rate_reduce, channel_switch+rate_reduce}, recoverable by a core configuration), PRIMARY'])));
verifyTrue(tc, any(contains(t, 'second line: recoverable by any of the 36 configurations')));
verifyTrue(tc, any(startsWith(t, 'beside KPI 5, recovery time (revised proposal, full action set')));
verifyTrue(tc, any(startsWith(t, 'beside KPI 5, goodput after onset in bit/s (full action set; nominal payload 50000 bit/s)')));
verifyTrue(tc, any(t == "Full action set (the 36 configurations):"));
verifyTrue(tc, any(startsWith(t, 'beside KPI 1, three link states (revised proposal; third test set')));
verifyTrue(tc, any(startsWith(t, 'beside KPI 1, three link states from 5 dB')));
verifyTrue(tc, any(t == "beside KPI 1, clean frames read as a jamming state 3.00%, as a class that raises an alarm 7.00% (100 frames, every Eb/N0; <= 5%: not met)"));
verifyTrue(tc, any(startsWith(t, 'beside KPI 1, from 5 dB (the KPI 1 threshold): clean frames read as a jamming state 3.00%')));
fl = t(startsWith(t, '  ') & contains(t, 'episodes with a change'));
verifyEqual(tc, numel(fl), 5);
w = @(k) extractBefore(fl(k), ' (lecturer');
verifyTrue(tc, startsWith(strtrim(fl(1)), 'no response') && endsWith(w(1), '-> MET (committed)'));
verifyTrue(tc, startsWith(strtrim(fl(2)), 'no detector + escalation') && endsWith(w(2), '-> MET (not committed)'));
verifyTrue(tc, startsWith(strtrim(fl(3)), 'rule + escalation') && endsWith(w(3), '-> MET (committed)'));
verifyTrue(tc, startsWith(strtrim(fl(4)), 'core: no detector + escalation') && endsWith(w(4), '-> MET (committed)'));
verifyTrue(tc, startsWith(strtrim(fl(5)), 'core: rule + escalation') && endsWith(w(5), '-> NOT MET'));
L = load('results/c2e_lect.mat', 'LECT'); X = L.LECT;
verifyEqual(tc, X.three.recall, [0.9 0.9 0.85], 'AbsTol', 1e-12);
verifyEqual(tc, [X.clean_fa.jam, X.clean_fa.alarm, X.clean_fa.above.alarm], [0.03 0.07 0.07], 'AbsTol', 1e-12);
verifyEqual(tc, {X.far.policy}, {'none', 'blind_esc', 'rule_esc', 'blind_core', 'rule_core'});
verifyEqual(tc, X.kpi1_file, 'results/eval_detector_metrics_fresh2.mat');
verifyEqual(tc, X.pol.verdict(1).scenario, 'narrowband');
verifyError(tc, @() c2e_lect('read'), 'c2e_lect:isolation');   % outside a prepared copy
end

function test_lect_lines_match_lect_kpi(tc)
% lect_lines.m's local functions are measure_all_kpis.m's of lect-kpi word for word, and the
% readers this branch took from lect-kpi are its files unchanged.
root = tc.TestData.root; ref = 'e84a5fd';
st = system(sprintf('git -C "%s" cat-file -e %s^{commit}', root, ref));
assumeEqual(tc, st, 0, 'git or lect-kpi''s commit is not available here');
[~, mak] = system(sprintf('git -C "%s" show %s:code/evaluation/measure_all_kpis.m', root, ref));
mine = fileread(which('lect_lines'));
for f = {'three_states', 'three_txt', 'per_lines', 'rec_lines', 'has_core', 'core_tag', 'tq', 'ternary'}
    verifyEqual(tc, fn_block(mine, f{1}), fn_block(mak, f{1}), f{1});
end
for f = {'code/evaluation/lect_kpis.m', 'code/evaluation/per_reduction.m', 'code/evaluation/three_state_view.m', ...
        'code/decision/per_metrics.m', 'code/decision/rule_core_policy.m'}
    [~, theirs] = system(sprintf('git -C "%s" show %s:%s', root, ref, f{1}));
    verifyEqual(tc, strrep(fileread(fullfile(root, f{1})), sprintf('\r'), ''), strrep(theirs, sprintf('\r'), ''), f{1});
end
end

function b = fn_block(txt, name)
% The lines of local function name, up to the next function, without trailing empty lines.
L = splitlines(strrep(txt, sprintf('\r'), ''));
s = find(~cellfun(@isempty, regexp(L, ['^function .*\<' name '\('], 'once')), 1);
if isempty(s), b = {}; return; end
e = find(startsWith(L(s + 1:end), 'function '), 1);
if isempty(e), e = numel(L) - s + 1; end
b = L(s:s + e - 1);
while ~isempty(b) && isempty(strtrim(b{end})), b(end) = []; end
end

%% ---------- worlds ----------
function [PP, K] = toy_world(crc_fails, hop_only)
% Frame pools of one flight: the clean link, and a jammer that only channel_switch and
% freq_diversity escape (hop_only: channel_switch alone); crc_fails false lets the jammed
% frames pass their CRC (test_core.m's).
if nargin < 2, hop_only = false; end
[PP, K] = toy_pools(@(a) contains(a, 'channel_switch') || (~hop_only && contains(a, 'freq_diversity')), crc_fails);
end

function [PP, K] = toy_fd_world()
% The same flight with a jammer only freq_diversity escapes, outside the core action set.
[PP, K] = toy_pools(@(a) contains(a, 'freq_diversity'), true);
end

function [PP, K] = toy_pools(escapes, crc_fails)
A = policy_actions(); nA = numel(A); names = link_features('names');
PP = struct('actions', {A}, 'scen', {{'none', 'jamming'}}, 'ebno', [10 12], 'runs', {{101}}, 'F_SUB', 20, ...
    'classes', {{'none', 'jamming'}}, 'feat_names', {names}, 'maha_thr', 0, 'clean', [1e-6 1e-6], 'clean_fer', [0 0], ...
    'gp', ones(1, nA), 'bw', 1 + contains(A, 'freq_diversity'), 'pw', ones(1, nA), 'sps', 4, 'bps', 2);
PP.pools = cell(2, 2, nA, 1);
for sc = 1:2
    for a = 1:nA
        good = sc == 1 || escapes(A{a});
        F = zeros(20, numel(names)); F(:, feature_index('crc_fail')) = ~good && crc_fails;
        F(:, feature_index('log_ber')) = log10(max(0.1 * ~good, 1e-6));
        PP.pools(sc, :, a, 1) = {struct('ber', repmat(0.1 * ~good, 20, 1), 'fer', repmat(single(~good), 20, 1), ...
            'run', 101 * ones(20, 1), 'probs', repmat(double([sc == 1, sc == 2]), 20, 1), 'maha', ones(20, 1), 'feat', F)};
    end
end
K = link_env('tables', PP);
end

%% ---------- the revised proposal's readers (test_core.m of lect-kpi, word for word) ----------
function v = ternary_(c, a, b)
if c, v = a; else, v = b; end
end

function test_per_metrics_traces(tc)
% PER after onset over the frames that carry a packet (a coded link's gap left out), the
% delivered payload (goodput factor x (1 - packet loss), none in the gap) and the recovery
% time from the detection frame until the packet loss stays restored for the whole window.
T = 12; NE = 4; post = repmat((1:T)' >= 3, 1, NE);
fer = zeros(T, NE); gap = false(T, NE); gpl = ones(T, NE);
fer(3:6, 1) = 1;
fer(3:4, 2) = 1; gap(5:7, 2) = true; gpl(5:T, 2) = 0.5;
fer(3:T, 3) = 1;
rplr = fer == 0 & ~gap;
M = per_metrics(fer, post, gap, rplr, gpl, [1 NaN 0 2], 5);
verifyEqual(tc, M.per_post, [0.4, 2/7, 1, 0], 'AbsTol', 1e-12);
verifyEqual(tc, M.dlv_post, [0.6, 0.25, 0, 1], 'AbsTol', 1e-12);
verifyEqual(tc, M.t_rec_det, [3 NaN NaN 0]);
M = per_metrics(fer, post, gap, rplr, gpl, [1 NaN 0 2], 7);      % episode 1 stays restored 6 cycles only
verifyEqual(tc, M.t_rec_det, [NaN NaN NaN 0]);
M = per_metrics(fer, false(T, NE), gap, rplr, gpl, [1 1 1 1], 5);
verifyTrue(tc, all(isnan([M.per_post, M.dlv_post, M.t_rec_det])));
end


function test_per_reduction(tc)
% PER reduction vs the static link: 1 - sum(PER policy) / sum(PER static) over the same
% episodes (paired), the episodes of one flight geometry resampled together; an episode with
% a NaN under either policy is left out; a reference that loses no packet gives NaN.
ref = [0.5 0.5 0.4 0.4 0.2 NaN]; pol = [0.1 0.1 0.2 0.2 0.1 0];
cl = [1 1 2 2 3 4];
[m, lo, hi] = per_reduction(pol, ref, cl, 500, 3);
verifyEqual(tc, m, 1 - 0.7 / 2, 'AbsTol', 1e-12);
verifyLessThanOrEqual(tc, lo, m); verifyGreaterThanOrEqual(tc, hi, m);
verifyEqual(tc, per_reduction(ref(1:4), ref(1:4), cl(1:4), 100, 1), 0, 'AbsTol', 1e-12);
verifyTrue(tc, isnan(per_reduction([0 0], [0 0], [1 2], 100, 1)));
end

function test_lect_kpis_readings(tc)
% The revised proposal's readings (lect_kpis.m) on the recoverable jamming episodes: the PER
% reduction of rule + escalation and of the escalation without the detector vs the static
% link, per jamming threat, the CNN's share; recovery from detection, the onset-to-detection
% time and T_rec (median, p90, never); goodput in bit/s.
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', 'oracle'};
[ALL, scen] = lect_world(POL);
[L, lines] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20);
verifyEqual(tc, {L.per.policy}, {'rule_esc', 'blind_esc'});
verifyEqual(tc, [L.per.n], [4 4]);
verifyEqual(tc, [L.per.red_pct], 100 * [1 - 0.6 / 1.8, 1 - 1.4 / 1.8], 'AbsTol', 1e-9);
verifyEqual(tc, [L.per.met], [true false]);
verifyEqual(tc, L.per(1).per_ref_pct, 45, 'AbsTol', 1e-9);
verifyEqual(tc, {L.per_threat.threat}, {'jamming', 'tone_jamming'});
verifyEqual(tc, {L.per_threat.band}, {'wideband', 'narrowband'});
verifyEqual(tc, [L.per_threat(1).red_pct(1), L.per_threat(2).red_pct(1)], [80 50], 'AbsTol', 1e-9);
verifyEqual(tc, L.cnn.per_red_pct, 100 * (1 - 0.6 / 1.4), 'AbsTol', 1e-9);
verifyEqual(tc, L.cnn.gput_bps, 1e4, 'AbsTol', 1e-6);
sel = @(s, p) L.rec(strcmp({L.rec.set}, s) & strcmp({L.rec.policy}, p));
verifyEqual(tc, unique({L.rec.policy}, 'stable'), {'none', 'blind_esc', 'rule_esc', 'dqn_esc'});
r = sel('recoverable threat episodes', 'rule_esc');
verifyEqual(tc, [r.n, r.det.median, r.det.p90, r.rec_det.median, r.rec_det.p90, r.rec_det.never_pct], [6 1 2 3 5 0]);
verifyEqual(tc, r.det.never_pct, 100 / 6, 'AbsTol', 1e-9);
verifyEqual(tc, [r.t_rec.median, r.t_rec.p90], [4 6]);
r = sel('recoverable jamming episodes', 'rule_esc');
verifyEqual(tc, [r.n, r.det.median, r.det.p90, r.det.never_pct, r.rec_det.median, r.rec_det.p90], [4 1 2 25 3 4]);
r = sel('recoverable threat episodes', 'none');
verifyTrue(tc, isnan(r.rec_det.median)); verifyEqual(tc, r.rec_det.never_pct, 100);
g = L.gput(strcmp({L.gput.policy}, 'rule_esc'));
verifyEqual(tc, [g.bps, g.bps_jam], [5e4 * 5.5 / 7, 42500], 'AbsTol', 1e-6);
verifyTrue(tc, any(strcmp({L.gput.policy}, 'oracle')));
verifyTrue(tc, any(contains(lines, '-> MET')));
verifyEqual(tc, {L.verdict.scenario}, {'narrowband', 'wideband'});
verifyEqual(tc, {L.verdict.threat}, {'tone_jamming', 'jamming'});
verifyEqual(tc, [L.verdict.red_pct], [50 80], 'AbsTol', 1e-9);
verifyEqual(tc, {L.verdict.verdict}, {'MET (not committed)', 'MET (not committed)'});   % one geometry each: no interval
verifyEqual(tc, {L.per.verdict}, {'MET (committed)', 'NOT MET'});
verifyEqual(tc, L.recoverable, 'all36');
L2 = lect_kpis(ALL, POL, LBL, 7, scen, 5e4, 20);                   % a deployed DQN is read too
verifyEqual(tc, {L2.per.policy}, {'rule_esc', 'blind_esc', 'dqn_esc'});
end

function test_lect_kpis_verdict(tc)
% The primary PER verdict per lecturer scenario (lect_kpis.m L.verdict): narrowband =
% tone_jamming, wideband = jamming, rule + escalation's reduction vs the static link; MET
% (committed) when the 95% lower bound clears 30%, MET (not committed) when only the point
% does, NOT MET otherwise or without episodes; the five threats pooled are the extension.
POL = {'none', 'rule_esc', 'blind_esc'}; LBL = {'no response', 'rule + escalation', 'no detector + escalation'};
scen = {'none', 'jamming', 'tone_jamming'};
B = struct('scn', [3 3 3 3 2 2 2 2], 'recoverable', true(1, 8), 'recoverable_core', true(1, 8), ...
    'threat', true(1, 8), 'geom', 1:8, 'ok_post', 0.5 * ones(1, 8), 't_conf', ones(1, 8), 't_rec_det', ones(1, 8), ...
    't_rec', 2 * ones(1, 8), 'dlv_post', 0.5 * ones(1, 8), 'gput_post', 0.5 * ones(1, 8));
ALL = {B, B, B};
for k = 1:3, ALL{k}.per_post = 0.5 * ones(1, 8); end
ALL{2}.per_post = [0 0.5 0.5 0 0.1 0.1 0.1 0.1];        % tone 50%, two of four geometries; jamming 80% on every one
[L, lines] = lect_kpis(ALL, POL, LBL, 2, scen, 5e4, 20);
v = L.verdict;
verifyEqual(tc, {v.scenario}, {'narrowband', 'wideband'});
verifyEqual(tc, [v.n], [4 4]);
verifyEqual(tc, [v.red_pct], [50 80], 'AbsTol', 1e-9);
verifyLessThan(tc, v(1).ci(1), 30);
verifyGreaterThanOrEqual(tc, v(2).ci(1), 30);
verifyEqual(tc, {v.verdict}, {'MET (not committed)', 'MET (committed)'});
verifyEqual(tc, [v.met; v.committed], [true true; false true]);
verifyEqual(tc, {v.policy}, {'rule_esc', 'rule_esc'});
verifyTrue(tc, any(startsWith(lines, '  PRIMARY narrowband (tone_jamming), 4 recoverable episodes, static PER 50.00%: rule + escalation reduction 50.0% [') & ...
    endsWith(lines, '-> MET (not committed)')));
verifyTrue(tc, any(startsWith(lines, '  PRIMARY wideband (jamming), 4 recoverable episodes') & endsWith(lines, '-> MET (committed)')));
i = find(startsWith(lines, '  extension, the five jamming threats pooled (8 recoverable episodes; jamming, noise_burst'));
verifyNumElements(tc, i, 1);
verifyGreaterThan(tc, i, find(startsWith(lines, '  PRIMARY wideband'), 1));
verifyEqual(tc, L.per(1).red_pct, 65, 'AbsTol', 1e-9);
verifyEqual(tc, L.per(1).verdict, ternary_(L.per(1).ci(1) >= 30, 'MET (committed)', 'MET (not committed)'));
ALL{2}.per_post(5:8) = 0.4;                                % jamming 20%
ALL = cellfun(@(R) setfield(R, 'threat', [false(1, 4), true(1, 4)]), ALL, 'UniformOutput', false); %#ok<SFLD>
[L, lines] = lect_kpis(ALL, POL, LBL, 2, scen, 5e4, 20);
verifyEqual(tc, [L.verdict.n], [0 4]);
verifyEqual(tc, {L.verdict.verdict}, {'NOT MET', 'NOT MET'});
verifyTrue(tc, any(strcmp(lines, '  PRIMARY narrowband (tone_jamming): no recoverable episodes -> NOT MET')));
verifyTrue(tc, any(startsWith(lines, '  PRIMARY wideband (jamming), 4 recoverable episodes') & endsWith(lines, 'reduction 20.0% [20.0, 20.0] -> NOT MET')));
end

function [ALL, scen] = lect_world(POL)
% Eight episodes of every policy in POL: jamming (1, 2, 7), tone_jamming (3, 4, 8), path_loss
% (5, 6); episode 7 not recoverable, episode 8 without its threat on the air; episode 2
% recoverable only by a configuration outside the core action set.
% The policies without the detector share one set of readings, every other policy another.
scen = {'none', 'jamming', 'tone_jamming', 'path_loss'};
B = struct('scn', [2 2 3 3 4 4 2 3], 'recoverable', logical([1 1 1 1 1 1 0 1]), ...
    'recoverable_core', logical([1 0 1 1 1 1 0 1]), ...
    'threat', logical([1 1 1 1 1 1 1 0]), 'geom', [1 1 2 2 3 3 4 5], 'ok_post', 0.5 * ones(1, 8));
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
        otherwise
            R.per_post = [0.1 0.1 0.2 0.2 0 0 0.9 0.2]; R.dlv_post = [0.9 0.9 0.8 0.8 1 1 0.1 0.8];
            R.t_conf = [1 2 NaN 0 1 1 NaN NaN]; R.t_rec_det = [3 4 NaN 2 0 5 NaN NaN]; R.t_rec = [4 6 NaN 2 1 6 NaN NaN];
            if strcmp(POL{k}, 'oracle'), R.t_conf(:) = NaN; R.t_rec_det(:) = NaN; end
    end
    R.gput_post = R.dlv_post; R.recovered = isfinite(R.t_rec);
    ALL{k} = R;
end
end

function test_three_state_view(tc)
% The detector's confusion matrix as the three link states: the rows of none, tone_jamming
% and jamming only; a frame read as another class is an error of its state (column other),
% precision over the three states' frames.
classes = {'none', 'jamming', 'path_loss', 'tone_jamming', 'spoofing'};
cm = [90 2 3 1 4; 5 80 5 10 0; 10 10 70 5 5; 2 3 0 85 10; 1 1 1 1 96];
V = three_state_view(cm, classes);
verifyEqual(tc, V.cm, [90 1 2 7; 2 85 3 10; 5 10 80 5]);
verifyEqual(tc, V.recall, [0.9 0.85 0.8], 'AbsTol', 1e-12);
p = [90 / 97, 85 / 96, 80 / 85];
verifyEqual(tc, V.precision, p, 'AbsTol', 1e-12);
f1 = 2 * p .* V.recall ./ (p + V.recall);
verifyEqual(tc, V.macro_f1, mean(f1), 'AbsTol', 1e-12);
verifyEqual(tc, V.n, [100 100 100]);
verifyError(tc, @() three_state_view(eye(3), {'none', 'jamming', 'path_loss'}), 'three_state_view:class');
end

function test_rule_core_policy(tc)
% The rule on the core set: interference on our channel leaves it, a jammer a hop does not
% escape and a loss of our signal take the processing gain, a degraded link without a known
% cause both; benign and clean classes on a healthy link do nothing; every answer is core.
C = decision_config();
for c = {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'}
    verifyEqual(tc, rule_core_policy(c{1}), 'channel_switch');
end
for c = {'sweeping_jammer', 'noise_burst', 'path_loss', 'antenna_fault', 'airframe_shadowing'}
    verifyEqual(tc, rule_core_policy(c{1}), 'rate_reduce');
end
verifyEqual(tc, rule_core_policy('none'), 'no_action');
verifyEqual(tc, rule_core_policy('benign_interference'), 'no_action');
verifyEqual(tc, rule_core_policy('unknown'), 'no_action');
verifyEqual(tc, rule_core_policy('benign_interference', true), 'channel_switch');
verifyEqual(tc, rule_core_policy('none', true), 'channel_switch+rate_reduce');
verifyEqual(tc, rule_core_policy('unknown', true), 'channel_switch+rate_reduce');
verifyEqual(tc, rule_core_policy('none', true, 10, 5), 'channel_switch');                   % interference in the quiet slot
verifyEqual(tc, rule_core_policy('none', true, 10, 5, false, [], false), 'channel_switch+rate_reduce');   % slot branch off
verifyEqual(tc, rule_core_policy('none', true, 4, 5), 'channel_switch+rate_reduce');
verifyEqual(tc, rule_core_policy('none', true, C.q_alarm_db), 'channel_switch');             % default alarm
verifyEqual(tc, rule_core_policy('none', false, -Inf, 3, true), 'rate_reduce');              % drop alarm, quiet slot
verifyEqual(tc, rule_core_policy('unknown', true, -Inf, 3, true), 'rate_reduce');
verifyEqual(tc, rule_core_policy('none', false, 10, 3, true), 'no_action');                  % interference: no drop answer
verifyEqual(tc, rule_core_policy('benign_interference', false, -Inf, 3, true), 'no_action');
B = @(d, cur, g) struct('drop_db', d, 'current', cur, 'current_db', g);
verifyEqual(tc, rule_core_policy('path_loss', false, -Inf, 3, false, B(5, 'no_action', 0)), 'rate_reduce');
verifyEqual(tc, rule_core_policy('path_loss', false, -Inf, 3, false, B(5, 'channel_switch+rate_reduce', 6)), ...
    'channel_switch+rate_reduce');                                                           % its gain covers the drop
verifyEqual(tc, rule_core_policy('path_loss', false, -Inf, 3, false, B(-0.5, 'no_action', 0)), 'no_action');
verifyEqual(tc, rule_core_policy('none', false, -Inf, 3, true, B(8, 'rate_reduce', 6)), 'rate_reduce');
cls = {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming', 'sweeping_jammer', 'noise_burst', 'path_loss', ...
    'antenna_fault', 'airframe_shadowing', 'benign_interference', 'none', 'unknown'};
for c = cls
    for deg = [false true]
        for q = [-Inf 10]
            for dr = [false true]
                verifyTrue(tc, ismember(rule_core_policy(c{1}, deg, q, 5, dr), C.core_actions));
                verifyTrue(tc, ismember(rule_core_policy(c{1}, deg, q, 5, dr, B(3, 'no_action', 0)), C.core_actions));
            end
        end
    end
end
end

function test_core_decide_escalation(tc)
% Through the decision cycle the core rule applies channel_switch to a jammer it names, and
% when the link stays degraded escalates along the core ladder, never outside the core set;
% the full rule escalates along its own ladder. The option is the rule's only.
C = decision_config(); A = policy_actions();
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
PP = struct('actions', {A}, 'classes', {cls}, 'sps', 4, 'bps', 2, 'maha_thr', 0);
na = find(strcmp(A, 'no_action'));
obs = struct('probs', double(strcmp(cls, 'jamming')), 'unknown', false, 'feat', zeros(1, numel(link_features('names'))));
obs.feat(feature_index('log_ber')) = -1; obs.feat(feature_index('crc_fail')) = 1;
runs = {struct('core', true), struct()};
first = {{'channel_switch', 'channel_switch+rate_reduce'}, {'channel_switch', C.ladder{1}}};
for k = 1:2
    mem = []; cfg = na; ch = {}; esc = [];
    for t = 1:30
        o = obs; o.cfg_link = cfg;
        [a, mem, d] = policy_decide('rule_esc', o, cfg, mem, PP, [], runs{k});
        if a ~= cfg, ch{end+1} = A{a}; esc(end+1) = d.escalated; end %#ok<AGROW>
        cfg = a;
    end
    verifyGreaterThanOrEqual(tc, numel(ch), 2);
    verifyEqual(tc, ch(1:2), first{k});
    verifyEqual(tc, double(esc(1:2)), [0 1]);
    if k == 1, verifyTrue(tc, all(ismember(ch, C.core_actions))); end
end
% without the detector: every cycle reads unknown, the alarm from the degradation; the core
% answer to a degraded link without a known cause holds both core elements
mem = []; cfg = na; ch = {};
for t = 1:30
    o = obs; o.cfg_link = cfg;
    [a, mem] = policy_decide('blind_esc', o, cfg, mem, PP, [], struct('core', true));
    if a ~= cfg, ch{end+1} = A{a}; end %#ok<AGROW>
    cfg = a;
end
verifyNotEmpty(tc, ch);
verifyEqual(tc, ch{1}, 'channel_switch+rate_reduce');
verifyTrue(tc, all(ismember(ch, C.core_actions)));
verifyError(tc, @() policy_decide('table_esc', obs, na, [], PP, [], struct('core', true, 'table', na * ones(1, numel(cls)), ...
    'table_unknown', na)), 'policy_decide:core');
verifyError(tc, @() policy_decide('dqn', obs, na, [], PP, [], struct('core', true)), 'policy_decide:core');
end

function test_lect_kpis_core(tc)
% lect_kpis.m reads the core action set beside the full one: the PER reduction of the core
% rule with and without the detector vs the same static link, per jamming threat, the CNN's
% share in PER, goodput and recovery time, recovery and goodput; the full set's readings
% and lines are those it gives without the core policies.
POL = {'none', 'random', 'fixed', 'rule_esc', 'blind_esc', 'table', 'dqn_esc', 'oracle'};
LBL = {'no response', 'random', 'fixed', 'rule + escalation', 'no detector + escalation', 'table', 'DQN + escalation', 'oracle'};
[ALL, scen] = lect_world(POL);
[L0, lines0] = lect_kpis(ALL, POL, LBL, 4, scen, 5e4, 20);
verifyEmpty(tc, L0.core);
POLc = [POL, {'rule_core', 'blind_core'}];
LBLc = [LBL, {'core: rule + escalation', 'core: no detector + escalation'}];
[ALLc, scen] = lect_world(POLc);
[L, lines] = lect_kpis(ALLc, POLc, LBLc, 4, scen, 5e4, 20);
for f = {'verdict', 'per', 'per_threat', 'cnn', 'rec', 'gput'}
    verifyEqual(tc, L.(f{1}), L0.(f{1}));
end
verifyEqual(tc, lines(1:numel(lines0)), lines0);
verifyEqual(tc, lines0{3}, 'Full action set (the 36 configurations):');
% Primary: the episodes a core configuration recovers (episode 2 out: jamming 1, tone 3 and 4)
Cc = L.core;
verifyEqual(tc, Cc.actions, decision_config().core_actions);
verifyEqual(tc, Cc.recoverable, 'core');
verifyEqual(tc, {Cc.per.policy}, {'rule_core', 'blind_core'});
verifyEqual(tc, [Cc.per.n], [3 3]);
verifyEqual(tc, [Cc.per.red_pct], 100 * [1 - 0.5 / 1.3, 1 - 1.1 / 1.3], 'AbsTol', 1e-9);
verifyEqual(tc, {Cc.per.verdict}, {'MET (committed)', 'NOT MET'});
verifyEqual(tc, {Cc.per_threat.threat}, {'jamming', 'tone_jamming'});
verifyEqual(tc, [Cc.per_threat.n], [1 2]);
verifyEqual(tc, {Cc.verdict.threat}, {'tone_jamming', 'jamming'});
verifyEqual(tc, [Cc.verdict.n], [2 1]);
verifyEqual(tc, [Cc.verdict.red_pct], [50 80], 'AbsTol', 1e-9);
verifyEqual(tc, {Cc.verdict.policy}, {'rule_core', 'rule_core'});
verifyEqual(tc, Cc.cnn.per_red_pct, 100 * (1 - 0.5 / 1.1), 'AbsTol', 1e-9);
verifyEqual(tc, Cc.cnn.gput_bps, 1e4, 'AbsTol', 1e-6);
verifyEqual(tc, [Cc.cnn.det.median; Cc.cnn.det.p90; Cc.cnn.det.never_pct], [0.5 2; 1 3; 100 / 3 0], 'AbsTol', 1e-9);
verifyEqual(tc, [Cc.cnn.rec_det.median; Cc.cnn.rec_det.p90; Cc.cnn.rec_det.never_pct], [2.5 5; 3 5; 0 200 / 3], 'AbsTol', 1e-9);
sel = @(S, s, p) S.rec(strcmp({S.rec.set}, s) & strcmp({S.rec.policy}, p));
r = sel(Cc, 'recoverable threat episodes', 'rule_core');
verifyEqual(tc, [r.n, r.det.median, r.det.p90, r.det.never_pct, r.rec_det.median, r.rec_det.p90, r.t_rec.median, r.t_rec.p90], ...
    [5 1 1 20 2.5 5 3 6]);
verifyEqual(tc, sel(Cc, 'recoverable jamming episodes', 'rule_core').n, 3);
verifyEqual(tc, unique({Cc.rec.policy}, 'stable'), {'none', 'blind_core', 'rule_core'});
verifyEqual(tc, {Cc.gput.policy}, {'none', 'blind_core', 'rule_core'});
g = Cc.gput(strcmp({Cc.gput.policy}, 'rule_core'));
verifyEqual(tc, [g.bps, g.bps_jam], [5e4 * 5.5 / 7, 5e4 * 2.5 / 3], 'AbsTol', 1e-6);
% Conservative: the episodes any of the 36 recovers
C36 = Cc.all36;
verifyEqual(tc, C36.recoverable, 'all36');
verifyEqual(tc, [C36.per.n], [4 4]);
verifyEqual(tc, [C36.per.red_pct], 100 * [1 - 0.6 / 1.8, 1 - 1.4 / 1.8], 'AbsTol', 1e-9);
verifyEqual(tc, [C36.per.met], [true false]);
verifyEqual(tc, {C36.per_threat.threat}, {'jamming', 'tone_jamming'});
verifyEqual(tc, [C36.verdict.n], [2 2]);
verifyEqual(tc, C36.cnn.per_red_pct, 100 * (1 - 0.6 / 1.4), 'AbsTol', 1e-9);
verifyEqual(tc, C36.cnn.gput_bps, 1e4, 'AbsTol', 1e-6);
verifyEqual(tc, [C36.cnn.det.median; C36.cnn.det.p90; C36.cnn.det.never_pct], [1 2.5; 2 3; 25 0]);
verifyEqual(tc, [C36.cnn.rec_det.median; C36.cnn.rec_det.p90; C36.cnn.rec_det.never_pct], [3 5.5; 4 6; 0 50]);
verifyEqual(tc, [L.cnn.det.median], [1 2.5]);                                        % the full set's alike
g = C36.gput(strcmp({C36.gput.policy}, 'rule_core'));
verifyEqual(tc, [g.bps, g.bps_jam], [5e4 * 5.5 / 7, 42500], 'AbsTol', 1e-6);
r = sel(C36, 'recoverable threat episodes', 'rule_core');
verifyEqual(tc, [r.n, r.det.median, r.rec_det.median, r.t_rec.median], [6 1 3 4]);
lc = lines(numel(lines0) + 1:end);
verifyTrue(tc, startsWith(lc{1}, 'Core action set {no_action, channel_switch, rate_reduce, channel_switch+rate_reduce}'));
verifyTrue(tc, endsWith(lc{1}, 'primary: the episodes a core configuration recovers (5 recoverable threat episodes, 3 jamming):'));
verifyTrue(tc, any(contains(lc, 'core: rule + escalation') & contains(lc, '-> MET')));
verifyTrue(tc, any(startsWith(lc, 'Core action set: Recovery time (lecturer)')));
verifyTrue(tc, any(startsWith(lc, 'Core action set: Goodput after onset in bit/s')));
verifyTrue(tc, any(startsWith(lc, ['Core action set: PER after onset vs the static link (no response), paired by episode, ' ...
    '95% bootstrap over flight geometries; recoverable episodes: some configuration of the core action set restores the geometry.'])));
verifyTrue(tc, any(contains(lc, 'CNN contribution (core rule + escalation vs the same core escalation without the detector')));
i = find(startsWith(lc, 'Core action set, second line: the episodes any of the 36 configurations recovers (6 recoverable threat episodes, 4 jamming'));
verifyNumElements(tc, i, 1);
verifyTrue(tc, any(startsWith(lc(i:end), 'Core action set (recoverable by the 36): PER after onset')));
verifyTrue(tc, any(startsWith(lc(i:end), 'Core action set (recoverable by the 36): Recovery time (lecturer)')));
verifyTrue(tc, any(startsWith(lc(i:end), 'Core action set (recoverable by the 36): Goodput after onset in bit/s')));
A = ALLc; A{1} = rmfield(A{1}, 'recoverable_core');                                   % the flags are required
verifyError(tc, @() lect_kpis(A, POLc, LBLc, 4, scen, 5e4, 20), 'lect_kpis:core_flags');
end
