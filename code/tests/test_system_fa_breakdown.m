function tests = test_system_fa_breakdown
%TEST_SYSTEM_FA_BREAKDOWN  Unit tests of the system false-alarm breakdown and the pre-onset
%   sensitivity (system_fa_breakdown.m, DECISIONS D103) on synthetic episodes; no pools. Run
%   from the repository root:
%   results = runtests('code/tests/test_system_fa_breakdown.m')
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

%% ---------- gate ----------
function test_gate_pass_and_fail(tc)
% The gate passes on C2e's own numbers, text and trained policy; a last-bit change of KP.lect,
% a changed KP.far, a changed line, another trained policy, a monitor that is not KP's, a clean
% set without fc_dal or other onsets under one policy stop it.
[E, PP, txt, Q] = eval_world();
G = system_fa_breakdown('gate', E, PP, Q, txt);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
verifyEqual(tc, G.T, 30);
verifyEqual(tc, numel(G.aboveU), 24); verifyEqual(tc, sum(G.aboveU), 16);
X = E; X.KP.lect.per(1).red_pct = X.KP.lect.per(1).red_pct + eps(X.KP.lect.per(1).red_pct);
gate_fails(tc, X, PP, Q, txt, 'KP.lect: .per differs');
G = system_fa_breakdown('gate', X, PP, Q, txt);
verifyTrue(tc, any(contains(G.mismatch, 'leaf.per(1).red_pct: 1 of ')) && any(contains(G.mismatch, 'max |d| ')), ...
    'the diagnostics name the leaf, the count and the size of the difference');
X = E; X.KP.far(2).k = 99;
gate_fails(tc, X, PP, Q, txt, 'KP.far: .k differs');
t = txt; i = find(startsWith(t, '  PRIMARY narrowband'), 1); t{i} = [t{i} ' '];
gate_fails(tc, E, PP, Q, t, 'lect_kpis''s lines: first difference');
t = txt; i = find(startsWith(t, '  rule + escalation') & contains(t, 'upper'), 1); t{i} = strrep(t{i}, 'upper', 'Upper');
gate_fails(tc, E, PP, Q, t, 'far_report''s lines');
Q2 = Q; Q2.dec.confirm_sweep = [3 6];
gate_fails(tc, E, PP, Q2, txt, 'policy_stamp of the trained policy');
X = E; X.KP.confirm = [2 2];
gate_fails(tc, X, PP, Q, txt, 'the monitor rebuilt from the trained policy');
X = E; X.RW{3} = rmfield(X.RW{3}, 'fc_dal');
gate_fails(tc, X, PP, Q, txt, 'RW{3} (rule_esc) lacks fc_dal');
X = E; X.ALL{4}.onset(1) = 5;
gate_fails(tc, X, PP, Q, txt, 'ALL{4} (blind_esc) does not hold the episodes');
X = E; X.KP = rmfield(X.KP, 'policy_stamp');
gate_fails(tc, X, PP, Q, txt, 'KP lacks policy_stamp');
P2 = PP; P2.ebno = [0 3 7];
gate_fails(tc, E, P2, Q, txt, 'Eb/N0 grid');
end

function test_monitors(tc)
% Every policy runs the trained policy's monitor, the rule fallback its own on top; without
% settings policy_monitor.m's defaults (no sweeper path).
Q = trained_world();
[mon, mm] = system_fa_breakdown('monitors', {'rule_esc', 'rule_sel'}, struct(), Q);
verifyEmpty(tc, mm);
verifyEqual(tc, {mon.alarm_mode}, {'class_drop', 'class_drop'});
verifyEqual(tc, {mon.confirm}, {[3 3], [5 5]});
verifyEqual(tc, {mon.confirm_sweep}, {[2 6], zeros(1, 0)});
[~, mm] = system_fa_breakdown('monitors', {'rule_sel'}, struct(), rmfield(Q, 'rule_sel'));
verifyTrue(tc, any(contains(mm, 'has no rule_sel')));
mon = system_fa_breakdown('monitors', {'none'}, struct(), struct());
verifyEqual(tc, mon.alarm_mode, 'class');
verifyEqual(tc, mon.confirm, decision_config().confirm);
verifyEmpty(tc, mon.confirm_sweep);
[p6, cmp] = system_fa_breakdown('policies', eval_world_pol(), 5);
verifyEqual(tc, p6, [1 3 4 7 8 5]);
verifyEqual(tc, cmp, [1 3 4 5 7 8]);
end

%% ---------- D103 3 ----------
function test_breakdown_tables(tc)
% (a) one table per Eb/N0 for the six policies, equal to far_report's rows for its two;
% (b) the path at the first change; (c) the Xu split; (d) the rates; (e) the first cycles.
[E, PP, txt, Q] = eval_world();
G = system_fa_breakdown('gate', E, PP, Q, txt);
[B, lines] = system_fa_breakdown('breakdown', E, PP, G);
verifyEqual(tc, B.policies, E.LBL([1 3 4 7 8 5]));
verifyEqual(tc, B.n_ebno, [0 8 8]);
verifyEqual(tc, B.by_ebno, [0 0 0; 0 3 3; 0 1 0; 0 0 1; 0 0 0; 0 0 1]);
verifyFalse(tc, any(contains(lines, 'random')));
r = B.path(2);
verifyEqual(tc, [r.n r.cls r.deg r.drop r.noflag r.unrec], [6 2 2 1 1 0]);
verifyEqual(tc, r.deg_by, [1 0 0 1]);
verifyEqual(tc, [r.cls_deg r.cls_drop r.deg_drop], [1 0 0]);
verifyEqual(tc, [B.path(3).deg B.path(3).deg_by], [1 0 0 1 0]);
verifyEqual(tc, [B.path(4).deg B.path(4).deg_drop], [1 1]);
verifyEqual(tc, [B.path(6).cls B.path(6).n], [1 1]);
verifyEqual(tc, [B.xu(2).healthy B.xu(2).unhealthy], [3 3]);
verifyEqual(tc, [B.xu(6).healthy B.xu(6).unhealthy], [1 0]);
verifyEqual(tc, [B.rate(2).changes B.rate(2).cycles B.rate(2).k B.rate(2).n], [7 480 6 16]);
verifyEqual(tc, B.rate(2).arl, 480 / 7, 'RelTol', 1e-12);
verifyEqual(tc, [B.first(2).n B.first(2).early], [6 3]);
verifyEqual(tc, find(B.first(2).hist), [2 3 4 7 12 20]);
verifyEqual(tc, B.win, decision_config().win);
verifyEqual(tc, [B.first(5).n B.path(5).n B.xu(5).n], [0 0 0]);   % blind_core: no false alarm
verifyTrue(tc, any(contains(lines, '-: 0 dB, below the KPI 1 threshold')));
verifyTrue(tc, any(contains(lines, 'in cycles 1..4 3 (50.0%')));
% the class path follows the monitor's mode: path_loss is hostile without the drop alarm modes
G2 = G; G2.mon(3).alarm_mode = 'class';
B2 = system_fa_breakdown('breakdown', E, PP, G2);
verifyEqual(tc, [B2.path(2).cls B2.path(2).deg], [3 1]);
G2.mon(3).alarm_mode = 'degraded';
B2 = system_fa_breakdown('breakdown', E, PP, G2);
verifyEqual(tc, [B2.path(2).cls B2.path(2).deg B2.path(2).drop B2.path(2).noflag], [0 3 1 2]);
end

function test_breakdown_one_table(tc)
% A per-Eb/N0 table that is not far_report's rows stops the reading.
[E, PP, txt, Q] = eval_world();
G = system_fa_breakdown('gate', E, PP, Q, txt);
G.far_diag(1).by_ebno(3) = G.far_diag(1).by_ebno(3) + 1;
verifyError(tc, @() system_fa_breakdown('breakdown', E, PP, G), 'system_fa_breakdown:table');
end

%% ---------- D103 4 ----------
function test_pre_onset_boundary(tc)
% The decision of cycle t reads frame t - 1: a first change at cycle 1..onset is before the
% onset, at onset + 1 it is not; no change is none.
R = struct('fc_t', [0 1 3 4 10], 'onset', [3 3 3 3 10]);
verifyEqual(tc, system_fa_breakdown('pre_onset', R), logical([0 1 1 0 1]));
end

function test_sensitivity_s0(tc)
% S0 drops an episode with a change before the onset under any compared policy, for every
% policy alike (paired); the oracle and random do not count; lect_kpis.m on S0 is lect_kpis.m
% on that subset; the shares and the composition are printed.
[E, PP, txt, Q] = eval_world();
G = system_fa_breakdown('gate', E, PP, Q, txt);
M = system_fa_breakdown('mark', PP.clean_fer, 2);
[S, lines] = system_fa_breakdown('sensitivity', E, PP, M, G);
keep = true(1, 18); keep([1 8 9 15]) = false;
verifyEqual(tc, S.S0, keep);
verifyEqual(tc, S.n_S0, 14);
A = system_fa_breakdown('subset', E.ALL, keep);
for k = 1:numel(A)
    verifyEqual(tc, [A{k}.s; A{k}.geom; A{k}.scn; A{k}.onset], [A{1}.s; A{1}.geom; A{1}.scn; A{1}.onset]);
    verifyEqual(tc, A{k}.per_post, E.ALL{k}.per_post(keep));
    verifyEqual(tc, A{k}.aoa, E.ALL{k}.aoa(:, keep));
end
LS = lect_kpis(A, E.POL, E.LBL, E.iDQN, PP.scen, 5e4, 20);
verifyTrue(tc, isequaln(S.lect_S0, LS));
q = S.pre_share(strcmp({S.pre_share.policy}, 'rule + escalation'));
verifyEqual(tc, q.pre, [2 2 1 1]);                 % 36, core, tone_jamming, jamming
verifyEqual(tc, q.n, [12 12 6 6]);
verifyEqual(tc, [q.pre_ebno; q.n_ebno], [1 1 0; 4 4 4]);
verifyTrue(tc, any(contains(lines, 'composition per Eb/N0, recoverable jamming (36), in S0 / in the full set: 0 dB [L] 3/4 | 3 dB [M] 2/4 | 6 dB [J] 3/4')));
iB = find(startsWith(lines, '(b) lect_kpis.m unchanged on S0')); iC = find(startsWith(lines, '(c) Line B'));
verifyTrue(tc, isscalar(iB) && isscalar(iC) && iB < iC);
b = lines(iB + 1:iC - 1);
v = b(contains(b, '-> MET') | contains(b, '-> NOT MET'));
verifyNotEmpty(tc, v);
verifyTrue(tc, all(endsWith(v, ' [sensitivity, not the verdict]')));
verifyTrue(tc, any(startsWith(b, 'Line A and S0')));
r0 = lines(find(startsWith(lines, '  Eb/N0 0 dB [L]'), 1):find(startsWith(lines, '  Eb/N0 3 dB [M]'), 1) - 1);
verifyTrue(tc, any(contains(r0, 'undefined (restoration threshold >= 100%)')));
verifyTrue(tc, any(startsWith(strtrim(r0), 'S0 PER')));
end

function test_sensitivity_empty_subsets(tc)
% No S0 episode, or none at one Eb/N0, prints "no episodes" and reads nothing there, no error.
[E, PP, txt, Q] = eval_world();
M = system_fa_breakdown('mark', PP.clean_fer, 2);
X = E; X.ALL{3}.fc_t(13:18) = 1;                   % rule + escalation: every 6 dB episode changes before the onset
G = system_fa_breakdown('gate', X, PP, Q, txt);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
[S, lines] = system_fa_breakdown('sensitivity', X, PP, M, G);
verifyEqual(tc, sum(S.S0(13:18)), 0);
verifyEmpty(tc, S.rows_S0{3});
i = find(startsWith(lines, '  Eb/N0 6 dB [J]'), 1);
verifyTrue(tc, endsWith(lines{i}, 'S0 0, 0'));
verifyTrue(tc, any(strcmp(lines(i + 1:end), '    S0 no episodes')));
X.ALL{3}.fc_t(:) = 1;
[S, lines] = system_fa_breakdown('sensitivity', X, PP, M, G);
verifyEqual(tc, S.n_S0, 0);
verifyEmpty(tc, S.lect_S0);
verifyTrue(tc, any(strcmp(lines, '  S0 holds no episode: no reading.')));
verifyEmpty(tc, S.line_b_S0);
end

%% ---------- D103 5 ----------
function test_carry_counts(tc)
% m-of-n 3 of 3 with the sweeper's 2 of 6: t_conf 0 is carried over, 1 is the sweeper's path
% or carried over, 2 is neither; without the sweeper path (or in the degraded mode) every
% t_conf below m - 1 is carried over.
mon = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'confirm_sweep', [2 6]);
tc0 = [0 1 2 NaN 5];
[ce, am] = system_fa_breakdown('carry_counts', tc0, mon);
verifyEqual(tc, [ce; am], logical([1 0 0 0 0; 0 1 0 0 0]));
mon.alarm_mode = 'degraded';
[ce, am] = system_fa_breakdown('carry_counts', tc0, mon);
verifyEqual(tc, [ce; am], logical([1 1 0 0 0; 0 0 0 0 0]));
mon = struct('alarm_mode', 'class', 'confirm', [5 5], 'confirm_sweep', []);
[ce, am] = system_fa_breakdown('carry_counts', tc0, mon);
verifyEqual(tc, [ce; am], logical([1 1 1 0 0; 0 0 0 0 0]));
[ce, am] = system_fa_breakdown('carry_counts', zeros(1, 0), mon);
verifyEmpty(tc, ce); verifyEmpty(tc, am);
end

function test_carried_table(tc)
[E, PP, txt, Q] = eval_world();
G = system_fa_breakdown('gate', E, PP, Q, txt);
[CO, lines] = system_fa_breakdown('carried', E, PP, G);
sel = @(p, s) CO(strcmp({CO.policy}, p) & strcmp({CO.set}, s));
q = sel('rule + escalation', 'recoverable jamming episodes (36)');
verifyEqual(tc, [q.n q.detected q.carried q.sweep_or_carried], [12 12 1 10]);
verifyEqual(tc, q.t_conf_wo.n, 11);
verifyEqual(tc, q.t_conf_wo_both.median, 16);
q = sel('rule + escalation', 'recoverable threat episodes (36)');
verifyEqual(tc, [q.n q.carried q.sweep_or_carried], [15 1 13]);
q = sel('no response', 'recoverable jamming episodes (36)');
verifyEqual(tc, [q.carried q.sweep_or_carried], [0 12]);
q = sel('no detector + escalation', 'recoverable jamming episodes (core)');
verifyEqual(tc, [q.n q.carried q.sweep_or_carried], [12 0 0]);
verifyTrue(tc, any(contains(lines, 'monitor class_drop, 3 of 3, sweeper 2 of 6')));
verifyFalse(tc, any(contains(lines, 'oracle')));
% the blind policies read every cycle as unknown: no sweeper path, t_conf 1 is carried over
verifyTrue(tc, any(startsWith(lines, '  no detector + escalation (monitor class_drop, 3 of 3, no sweeper path)')));
X = E; X.ALL{4}.t_conf(1) = 1;
CO = system_fa_breakdown('carried', X, PP, G);
q = CO(strcmp({CO.policy}, 'no detector + escalation') & strcmp({CO.set}, 'recoverable jamming episodes (36)'));
verifyEqual(tc, [q.carried q.sweep_or_carried], [1 0]);
verifyEmpty(tc, q.sweep);
end

%% ---------- the single run ----------
function test_run_order_and_once(tc)
% The gate, then D103 3, 4 and 5 in this order; a second run is refused; a failed gate prints
% none of them.
[E, PP, txt, Q] = eval_world();
d = fullfile(tc.TestData.tmp, 'run_sysfa'); mkdir(d);
fp = fullfile(d, 'policy_pools.mat'); save(fp, 'PP');
fe = fullfile(d, 'policy_evaluation.mat'); save(fe, '-struct', 'E');
ft = fullfile(d, 'policy_evaluation.txt'); write_text(ft, txt);
fq = fullfile(d, 'trained_dqn.mat'); save(fq, '-struct', 'Q');
out = fullfile(d, 'read1'); mkdir(out);
system_fa_breakdown('run', fp, fe, ft, fq, out);
o = read_text(fullfile(out, 'system_fa_breakdown.txt'));
verifyTrue(tc, startsWith(o{1}, 'GATE PASS'));
verifyTrue(tc, any(strcmp(o, sprintf('pools %s sha256 %s', fp, system_fa_breakdown('sha', fp)))));
h = cellfun(@(p) find(startsWith(o, p)), {'=== D103 3', '(a) ', '(b) ', '(c) ', '(d) ', '(e) ', '=== D103 4', ...
    '=== D103 5', '4(d)'}, 'UniformOutput', false);
verifyTrue(tc, all(cellfun(@numel, h) >= 1));
verifyTrue(tc, issorted(cellfun(@(x) x(1), h)));
R = load(fullfile(out, 'system_fa_breakdown.mat'));
verifyTrue(tc, R.G.pass && isfield(R, 'R') && ~isfield(R.G, 'RU'));
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq, out), 'system_fa_breakdown:once');
Q2 = Q; Q2.confirm = [2 2]; fq2 = fullfile(d, 'trained_dqn_other.mat'); save(fq2, '-struct', 'Q2');
out2 = fullfile(d, 'read2'); mkdir(out2);
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq2, out2), 'system_fa_breakdown:gate');
o2 = read_text(fullfile(out2, 'system_fa_breakdown.gatefail.txt'));
verifyTrue(tc, startsWith(o2{1}, 'GATE FAIL'));
verifyFalse(tc, any(startsWith(o2, '=== D103')));
% a failed gate spends nothing: no reading output, the diagnostics beside, the thread count real
verifyFalse(tc, isfile(fullfile(out2, 'system_fa_breakdown.txt')) || isfile(fullfile(out2, 'system_fa_breakdown.mat')));
Fg = load(fullfile(out2, 'system_fa_breakdown.gatefail.mat'));
verifyFalse(tc, Fg.G.pass);
verifyTrue(tc, any(startsWith(o2, sprintf('threads %d (', Fg.nthr))) && ~any(contains(o2, 'as C2e')));
verifyEqual(tc, Fg.nthr, maxNumCompThreads);
% the reading is still open: a second failure keeps the first diagnostics, the right inputs then pass once
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq2, out2), 'system_fa_breakdown:gate');
verifyEqual(tc, numel(dir(fullfile(out2, 'system_fa_breakdown.gatefail*.txt'))), 2);
verifyEqual(tc, numel(dir(fullfile(out2, 'system_fa_breakdown.gatefail*.mat'))), 2);
system_fa_breakdown('run', fp, fe, ft, fq, out2);
o3 = read_text(fullfile(out2, 'system_fa_breakdown.txt'));
verifyTrue(tc, startsWith(o3{1}, 'GATE PASS'));
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq, out2), 'system_fa_breakdown:once');
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq2, out2), 'system_fa_breakdown:once');
verifyError(tc, @() system_fa_breakdown('run', 'policy_pools.mat', fe, ft, fq, out2), 'system_fa_breakdown:input');
end

%% ---------- KPI 6's definition: KP.far_set ----------
function test_old_path_unchanged(tc)
% Without KP.far_set the gate, the readings, the text and every saved variable are those of the
% code of profile 1's D103 reading (sysfa 3c9f7ea), on a pass and on a failed gate.
root = tc.TestData.root; ref = '3c9f7ea';
[st, old] = system(sprintf('git -C "%s" show %s:code/evaluation/system_fa_breakdown.m', root, ref));
assumeEqual(tc, st, 0, 'git or the reading''s commit is not available here');
d = fullfile(tc.TestData.tmp, 'old_path'); mkdir(d);
old = regexprep(old, '^function varargout = system_fa_breakdown\(', 'function varargout = sfb_ref(', 'once');
verifyTrue(tc, startsWith(old, 'function varargout = sfb_ref(cmd, varargin)'));
fid = fopen(fullfile(d, 'sfb_ref.m'), 'w'); fwrite(fid, old); fclose(fid);
addpath(d); c = onCleanup(@() rmpath(d));
[E, PP, txt, Q] = eval_world();
verifyFalse(tc, isfield(E.KP, 'far_set'));
G0 = sfb_ref('gate', E, PP, Q, txt); G1 = system_fa_breakdown('gate', E, PP, Q, txt);
verifyTrue(tc, G1.pass, strjoin(G1.mismatch, newline));
verifyTrue(tc, isequaln(G0, G1), 'gate');
M = system_fa_breakdown('mark', PP.clean_fer, 2);
[R0, l0] = sfb_ref('readings', E, PP, M, G0); [R1, l1] = system_fa_breakdown('readings', E, PP, M, G1);
verifyTrue(tc, isequaln(R0, R1), 'readings');
verifyEqual(tc, l1, l0);
X = E; X.KP.far(2).k = 99;
verifyTrue(tc, isequaln(sfb_ref('gate', X, PP, Q, txt), system_fa_breakdown('gate', X, PP, Q, txt)), 'failed gate');
% the single run: the text byte for byte, the same saved variables
w = fullfile(d, 'run'); mkdir(w);
fp = fullfile(w, 'policy_pools.mat'); save(fp, 'PP');
fe = fullfile(w, 'policy_evaluation.mat'); save(fe, '-struct', 'E');
ft = fullfile(w, 'policy_evaluation.txt'); write_text(ft, txt);
fq = fullfile(w, 'trained_dqn.mat'); save(fq, '-struct', 'Q');
Q2 = Q; Q2.confirm = [2 2]; fq2 = fullfile(w, 'trained_dqn_other.mat'); save(fq2, '-struct', 'Q2');
o = cellfun(@(n) fullfile(w, n), {'old', 'new', 'old_fail', 'new_fail'}, 'UniformOutput', false);
for i = 1:4, mkdir(o{i}); end
sfb_ref('run', fp, fe, ft, fq, o{1});
system_fa_breakdown('run', fp, fe, ft, fq, o{2});
same_outputs(tc, o{1}, o{2}, 'system_fa_breakdown');
t = read_text(fullfile(o{2}, 'system_fa_breakdown.txt'));
verifyEqual(tc, t{1}, ['GATE PASS: lect_kpis.m reproduces KP.lect, far_report reproduces KP.far and KP.far_diag, ' ...
    'the trained policy is KP.policy_stamp, exactly']);
verifyFalse(tc, any(contains(t, 'P1R')));
verifyError(tc, @() sfb_ref('run', fp, fe, ft, fq2, o{3}), 'system_fa_breakdown:gate');
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq2, o{4}), 'system_fa_breakdown:gate');
same_outputs(tc, o{3}, o{4}, 'system_fa_breakdown.gatefail');
end

function test_gate_fresh(tc)
% With KP.far_set fresh the gate reads KPI 6 on RWf alone and P1R's labelled lecturer lines, and
% passes on P1R's C2e; the union's reader on the same outputs stops (it never misreads); a
% missing or mislabelled piece stops it.
[E, PP, txt, Q] = eval_world_fresh();
G = system_fa_breakdown('gate', E, PP, Q, txt);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
verifyEqual(tc, G.T, 30);
verifyEqual(tc, numel(G.aboveU), 12); verifyEqual(tc, sum(G.aboveU), 8);
verifyTrue(tc, isequaln(G.far, E.KP.far) && isequaln(G.far_diag, E.KP.far_diag));
verifyEqual(tc, [G.far(2).k G.far(2).n E.KP.far_union(2).k E.KP.far_union(2).n], [2 8 6 16]);
verifyTrue(tc, all(cellfun(@(R) all(R.split == 7), G.RU)));
verifyTrue(tc, all(endsWith(G.lect_lines(~cellfun(@isempty, strtrim(G.lect_lines))), ...
    ' [P1R: with the fixed monitor, second reading, descriptive]')));
X = E; X.KP = rmfield(X.KP, {'far_set', 'reading'});
gate_fails(tc, X, PP, Q, txt, 'far_report on KPI 6''s clean flights vs KP.far');
gate_fails(tc, X, PP, Q, txt, 'lect_kpis''s header 0 times');
gate_fails(tc, rmfield(E, 'RWf'), PP, Q, txt, 'the evaluation lacks RWf');
X = E; X.RWf{3}.split(2) = 6;
gate_fails(tc, X, PP, Q, txt, 'RWf{3} (rule_esc) is not split id 7');
X = E; X.RWf{4} = rmfield(X.RWf{4}, 'fc_dal');
gate_fails(tc, X, PP, Q, txt, 'RWf{4} (blind_esc) lacks fc_dal');
X = E; X.KP.far_set = 'union';
gate_fails(tc, X, PP, Q, txt, 'KP.far_set union: this reader knows');
X = E; X.KP = rmfield(X.KP, 'reading');
gate_fails(tc, X, PP, Q, txt, 'KP.far_set fresh without KP.reading P1R');
X = E; X.KP.far = X.KP.far_union; X.KP.far_diag = X.KP.far_diag_union;
gate_fails(tc, X, PP, Q, txt, 'far_report on KPI 6''s clean flights vs KP.far');
t = strrep(txt, ' [P1R: with the fixed monitor, second reading, descriptive]', '');
gate_fails(tc, E, PP, Q, t, 'lect_kpis''s header 0 times');
t = strrep(txt, '(P1R, read once)', '(P1R)');
gate_fails(tc, E, PP, Q, t, 'KPI 6''s header 0 times');
t = txt; i = find(startsWith(t, '  rule + escalation') & contains(t, 'upper'), 1, 'last'); t{i} = strrep(t{i}, 'upper', 'Upper');
gate_fails(tc, E, PP, Q, t, 'far_report''s lines');
% P1R's own code where it is here: the label and the KPI 6 header are evaluate_policies.m's
ev = fileread(which('evaluate_policies'));
if contains(ev, 'function L = p1r_label(')
    verifyEqual(tc, fn_block(fileread(which('system_fa_breakdown')), 'p1r_label'), fn_block(ev, 'p1r_label'));
    verifyTrue(tc, contains(ev, ['''False alarms on the clean link, the fresh clean test set (P1R, read once): %s, ' ...
        '%d episodes x %d cycles -> KPI 6''']));
end
end

function test_breakdown_fresh(tc)
% D103 3 on the fresh clean test set (RWf): the tables count its flights; D103 4 and 5 read the
% same episodes as without the key, labelled as P1R's second reading.
[E, PP, txt, Q] = eval_world_fresh();
G = system_fa_breakdown('gate', E, PP, Q, txt);
[B, lines] = system_fa_breakdown('breakdown', E, PP, G);
verifyEqual(tc, B.n_ebno, [0 4 4]);
verifyEqual(tc, B.by_ebno, [0 0 0; 0 1 1; 0 0 0; 0 0 0; 0 0 0; 0 1 0]);
r = B.path(2);
verifyEqual(tc, [r.n r.cls r.deg r.drop r.noflag r.unrec], [2 1 1 0 0 0]);
verifyEqual(tc, r.deg_by, [1 0 0 0]);
verifyEqual(tc, [B.path(6).n B.path(6).cls B.path(6).drop], [1 0 1]);
verifyEqual(tc, [B.xu(2).healthy B.xu(2).unhealthy], [1 1]);
verifyEqual(tc, [B.rate(2).changes B.rate(2).cycles B.rate(2).k B.rate(2).n], [3 240 2 8]);
verifyEqual(tc, [B.first(2).n B.first(2).early], [2 1]);
verifyEqual(tc, find(B.first(2).hist), [2 9]);
verifyTrue(tc, any(startsWith(lines, 'P1R: KPI 6''s flights are the fresh clean test set')));
verifyTrue(tc, any(contains(lines, 'from the fresh clean test set, as KPI 6 (P1R, every policy):')));
verifyFalse(tc, any(contains(lines, 'same union')));
[Eu, ~, tu] = eval_world();
Gu = system_fa_breakdown('gate', Eu, PP, Q, tu);
M = system_fa_breakdown('mark', PP.clean_fer, 2);
note = 'P1R: with the fixed monitor, second reading, descriptive: these episodes are test pools profile 1''s C2e has read';
[S, ls] = system_fa_breakdown('sensitivity', E, PP, M, G); [Su, lsu] = system_fa_breakdown('sensitivity', Eu, PP, M, Gu);
verifyTrue(tc, isequaln(S, Su));
verifyEqual(tc, ls{3}, note); verifyEqual(tc, ls([1:2, 4:end]), lsu);
[CO, lc] = system_fa_breakdown('carried', E, PP, G); [COu, lcu] = system_fa_breakdown('carried', Eu, PP, Gu);
verifyTrue(tc, isequaln(CO, COu));
verifyEqual(tc, lc{3}, note); verifyEqual(tc, lc([1:2, 4:end]), lcu);
end

function test_run_fresh(tc)
% The single run on P1R's outputs: RWf read from the evaluation file, the gate line and the
% header name the fresh definition, far_set saved; a P1R file without RWf fails the gate.
[E, PP, txt, Q] = eval_world_fresh();
d = fullfile(tc.TestData.tmp, 'run_fresh'); mkdir(d);
fp = fullfile(d, 'policy_pools.mat'); save(fp, 'PP');
fe = fullfile(d, 'policy_evaluation.mat'); save(fe, '-struct', 'E');
ft = fullfile(d, 'policy_evaluation.txt'); write_text(ft, txt);
fq = fullfile(d, 'trained_dqn.mat'); save(fq, '-struct', 'Q');
out = fullfile(d, 'read1'); mkdir(out);
system_fa_breakdown('run', fp, fe, ft, fq, out);
o = read_text(fullfile(out, 'system_fa_breakdown.txt'));
verifyTrue(tc, startsWith(o{1}, 'GATE PASS: ') && endsWith(o{1}, ', exactly'));
verifyTrue(tc, contains(o{1}, 'far_report on the fresh clean test set (RWf, KP.far_set fresh) reproduces KP.far'));
verifyTrue(tc, any(strcmp(o, sprintf(['P1R (KP.reading P1R, KP.far_set fresh): KPI 6''s flights are %s; D103 3 reads ' ...
    'them, D103 4 and 5 read test pools already read in profile 1''s C2e (second reading, descriptive)'], E.KP.far_src))));
h = cellfun(@(p) find(startsWith(o, p)), {'=== D103 3', 'P1R: KPI 6''s flights', '(a) ', '=== D103 4', '=== D103 5', '4(d)'}, ...
    'UniformOutput', false);
verifyTrue(tc, all(cellfun(@numel, h) >= 1));
verifyTrue(tc, issorted(cellfun(@(x) x(1), h)));
R = load(fullfile(out, 'system_fa_breakdown.mat'));
verifyEqual(tc, R.far_set, 'fresh');
verifyTrue(tc, R.G.pass && isequaln(R.G.far, E.KP.far));
verifyError(tc, @() system_fa_breakdown('run', fp, fe, ft, fq, out), 'system_fa_breakdown:once');
E2 = rmfield(E, 'RWf'); fe2 = fullfile(d, 'policy_evaluation_norwf.mat'); save(fe2, '-struct', 'E2');
out2 = fullfile(d, 'read2'); mkdir(out2);
verifyError(tc, @() system_fa_breakdown('run', fp, fe2, ft, fq, out2), 'system_fa_breakdown:gate');
o2 = read_text(fullfile(out2, 'system_fa_breakdown.gatefail.txt'));
verifyTrue(tc, startsWith(o2{1}, 'GATE FAIL') && any(contains(o2, 'the evaluation lacks RWf')));
verifyFalse(tc, isfile(fullfile(out2, 'system_fa_breakdown.txt')));
Fg = load(fullfile(out2, 'system_fa_breakdown.gatefail.mat'));
verifyEqual(tc, Fg.far_set, 'fresh');
end

%% ---------- copies and readers ----------
function test_copies_and_readers_match_tip(tc)
% far_report and cp_upper are evaluate_policies.m's, tstat lect_kpis.m's, word for word; the
% mark is D99's (lect_kpis_by_ebno.m, when on the path); the readers P1R leaves unchanged are
% profile 1's tip's (d4623ed), the six it changes are those of p1r b37e8a3, the code P1R's C2e
% runs (docs/p1r_protocol.md section 11).
mine = fileread(which('system_fa_breakdown'));
src = {'evaluate_policies', 'far_report'; 'evaluate_policies', 'cp_upper'; 'lect_kpis', 'tstat'};
for i = 1:size(src, 1)
    b = fn_block(mine, src{i, 2});
    verifyNotEmpty(tc, b, src{i, 2});
    verifyEqual(tc, b, fn_block(fileread(which(src{i, 1})), src{i, 2}), src{i, 2});
end
f = fullfile(tc.TestData.tmp, 'abc.txt'); fid = fopen(f, 'w'); fwrite(fid, 'abc'); fclose(fid);
verifyEqual(tc, system_fa_breakdown('sha', f), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
M = system_fa_breakdown('mark', [0.99 0.5 0.45 0.1 0.0999], 2);
verifyEqual(tc, M.L, logical([1 1 0 0 0]));
verifyEqual(tc, M.tag, {'L', 'L', 'M', 'M', 'J'});
if ~isempty(which('lect_kpis_by_ebno'))
    verifyEqual(tc, M, lect_kpis_by_ebno('mark', [0.99 0.5 0.45 0.1 0.0999], 2));
end
root = tc.TestData.root; tip = 'd4623ed'; p1r = 'b37e8a3';
for ref = {tip, p1r}
    st = system(sprintf('git -C "%s" cat-file -e %s', root, ref{1}));
    assumeEqual(tc, st, 0, sprintf('git or commit %s is not available here', ref{1}));
end
same = {'code/evaluation/lect_kpis.m', 'code/evaluation/per_reduction.m', 'code/evaluation/boot_cluster.m', ...
    'code/evaluation/false_change_rate.m', 'code/decision/per_metrics.m', 'code/decision/policy_run_set.m'};
changed = {'code/decision/decision_config.m', 'code/decision/decision_settings.m', 'code/decision/policy_stamp.m', ...
    'code/decision/evaluate_policies.m', 'code/decision/rollout_policy.m', 'code/decision/policy_monitor.m'};
G = [same, changed; repmat({tip}, size(same)), repmat({p1r}, size(changed))];
for g = G
    [~, theirs] = system(sprintf('git -C "%s" show %s:%s', root, g{2}, g{1}));
    verifyEqual(tc, strrep(fileread(fullfile(root, g{1})), sprintf('\r'), ''), strrep(theirs, sprintf('\r'), ''), ...
        [g{1} ' vs ' g{2}]);
end
end

%% ---------- worlds ----------
function POL = eval_world_pol()
POL = {'none', 'random', 'rule_esc', 'blind_esc', 'dqn_g1', 'oracle', 'rule_core', 'blind_core'};
end

function [ALL, POL, LBL, scen, PP] = sysfa_world()
% Three Eb/N0 points (0 dB link-limited, 3 dB marginal, 6 dB working point), six threat
% episodes each: jamming (1, 2, 6; 6 not recoverable), tone_jamming (3, 4), path_loss (5),
% onset at cycle 3. First changes: at onset + 1 for every monitored policy, but rule +
% escalation at cycles 2, 3 and 4 in episodes 1, 9 and 14 (before, at and after the onset
% boundary), the deployed DQN at 1 in 15, the core rule at 1 in 8; the oracle and random (not
% compared) change at cycle 1. t_conf: rule + escalation 0 in episode 3; the rule kinds 16 in 2.
POL = eval_world_pol();
LBL = {'no response', 'random', 'rule + escalation', 'no detector + escalation', 'DQN gamma=0.90 (selected) (deployed)', ...
    'oracle (one-step)', 'core: rule + escalation', 'core: no detector + escalation'};
scen = {'none', 'jamming', 'tone_jamming', 'path_loss'};
PP = struct('ebno', [0 3 6], 'scen', {scen}, 'clean_fer', [0.95 0.3 0.02], 'det_id', 'det1');
T = 20; onset = 3;
s = kron(1:3, ones(1, 6)); r = repmat([1 1 2 2 3 4], 1, 3); n = numel(s);
B = struct('scn', repmat([2 2 3 3 4 2], 1, 3), 's', s, 'r', r, 'geom', 1000 * s + r, ...
    'recoverable', repmat(logical([1 1 1 1 1 0]), 1, 3), 'recoverable_core', repmat(logical([1 1 1 1 1 0]), 1, 3), ...
    'threat', true(1, n), 'aoa', zeros(3, n), 'onset', onset * ones(1, n));
L = s == 1; nL = sum(L);
post = repmat((1:T)' >= onset, 1, nL);
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = B;
    sw = ones(1, n); fct = (onset + 1) * ones(1, n);
    switch POL{k}
        case 'none'
            per = [0.9 0.5 0.5]; dl = [0.1 0.5 0.5]; tcf = ones(1, n); rd = nan(1, n); sw(:) = 0; fct(:) = 0;
        case {'blind_esc', 'blind_core'}
            per = [0.6 0.3 0.3]; dl = [0.4 0.7 0.7]; tcf = 2 * ones(1, n); rd = 4 * ones(1, n);
        case 'oracle'
            per = [0.2 0 0]; dl = [0.8 1 1]; tcf = nan(1, n); rd = nan(1, n); fct(:) = 0; fct(2) = 1;
        case 'random'
            per = [0.8 0.4 0.4]; dl = [0.2 0.6 0.6]; tcf = ones(1, n); rd = nan(1, n); fct(:) = 1;
        otherwise
            per = [0.3 0.1 0.1]; dl = [0.7 0.9 0.9]; tcf = ones(1, n); rd = 2 * ones(1, n);
            tcf(2) = T - onset - 1;
    end
    switch POL{k}
        case 'rule_esc', tcf(3) = 0; fct([1 9 14]) = [2 3 4];
        case 'dqn_g1', fct(15) = 1;
        case 'rule_core', fct(8) = 1;
    end
    R.per_post = per(s) + 0.01 * (R.scn == 3); R.dlv_post = dl(s);
    M = per_metrics(zeros(T, nL), post, false(T, nL), true(T, nL), ones(T, nL), tcf(L), 5);
    rd(L) = M.t_rec_det;
    R.t_conf = tcf; R.t_rec_det = rd; R.t_rec = tcf + rd;
    R.gput_post = R.dlv_post; R.gput_post(L) = NaN;
    R.recovered = isfinite(R.t_rec);
    R.switches = sw; R.false_sw = zeros(1, n); R.fc_t = fct;
    R.fc_cls = double(sw > 0); R.fc_deg = false(1, n); R.fc_dal = false(1, n); R.fc_drop = zeros(1, n);
    ALL{k} = R;
end
end

function [SW, FS, FT, FC, FG, FL] = clean_flags(p)
% Clean flights 1..12 of the test split and 13..24 of the clean pools (4 per Eb/N0 each).
% rule + escalation: false alarms on 2 (0 dB, below the KPI 1 threshold), 5 (jamming, 2 changes,
% healthy), 6 (none, degraded), 9 (path_loss without the drop alarm, degraded, healthy), 10
% (unknown, drop alarm), 20 (none, no flag, healthy), 24 (jamming and degraded); first cycles
% 1, 2, 7, 4, 12, 3, 20. The others one each; random changes everywhere (not reported).
SW = zeros(1, 24); FS = SW; FT = SW; FC = SW; FG = false(1, 24); FL = FG;
switch p
    case 'rule_esc'
        i = [2 5 6 9 10 20 24];
        SW(i) = [1 2 1 1 1 1 1]; FT(i) = [1 2 7 4 12 3 20]; FC(i) = [1 2 1 4 6 1 2];
        FG([6 9 24]) = true; FL(10) = true; FS([5 9 20]) = [1 2 1];
    case 'blind_esc'
        SW(7) = 1; FT(7) = 1; FC(7) = 6; FG(7) = true;
    case 'dqn_g1'
        SW(21) = 1; FT(21) = 5; FC(21) = 3; FS(21) = 1;
    case 'rule_core'
        SW(11) = 1; FT(11) = 2; FC(11) = 1; FG(11) = true; FL(11) = true; FS(11) = 1;
    case 'random'
        SW(:) = 3; FT(:) = 1; FC(:) = 1;
end
end

function Q = trained_world()
% The trained policy's saved variables: the DQN deployed on class_drop 3 of 3 with the
% sweeper's 2 of 6; the rule fallback's own monitor 5 of 5 without the sweeper path.
dec = struct('alarm_mode', 'class_drop', 'confirm', [3 3], 'drop_db', 4, 'confirm_sweep', [2 6], 'maha_thr', -3);
Q = struct('agent', struct('dense', struct('W', [1 2; 3 4])), 'deployed', 'dqn', 'alarm_mode', 'class_drop', ...
    'confirm', [3 3], 'drop_db', 4, 'rule_sel', struct('alarm', 'class_drop 5/5', 'alarm_mode', 'class_drop', ...
    'confirm', [5 5], 'drop_db', 6, 'confirm_sweep', []), 'det_id', 'det1', 'maha_thr', -3, 'dec', dec);
end

function [E, PP, txt, Q] = eval_world()
% C2e's saved variables and text on sysfa_world: the threat sets pooled, the clean sets of the
% test split and of the clean pools (KPI 6 from 3 dB), KP.lect, KP.far and the policy stamp as
% C2e computes them; the deployed policy is the DQN (index 5).
[ALL, POL, LBL, scen, PP] = sysfa_world();
iDQN = 5; per_ms = 20; T = 30; ebno_thr = 3;
cls_list = {'none', 'jamming', 'tone_jamming', 'path_loss', 'benign_interference', 'unknown'};
[LK, ll] = lect_kpis(ALL, POL, LBL, iDQN, scen, 5e4, per_ms);
s12 = kron(1:3, ones(1, 4)); r12 = repmat(1:4, 1, 3);
RES = cell(2, numel(POL)); RW = cell(1, numel(POL)); RU = cell(1, numel(POL));
for k = 1:numel(POL)
    [SW, FS, FT, FC, FG, FL] = clean_flags(POL{k});
    cl = @(i, sp, ro) struct('s', s12, 'r', r12 + ro, 'geom', 1000 * s12 + r12 + ro, 'split', sp * ones(1, 12), ...
        'onset', 3 * ones(1, 12), 'switches', SW(i), 'false_sw', FS(i), 'fc_t', FT(i), 'fc_cls', FC(i), ...
        'fc_deg', FG(i), 'fc_dal', FL(i), 'fc_drop', 2 * (SW(i) > 0));
    RES{1, k} = ALL{k};
    RES{2, k} = cl(1:12, 3, 0);
    RW{k} = cl(13:24, 3, 10);
    Rw = RW{k}; Rw.split(:) = 6;
    RU{k} = cat_fields(RES{2, k}, Rw);
end
aU = [PP.ebno(RES{2, 1}.s) >= ebno_thr, PP.ebno(RW{1}.s) >= ebno_thr];
[FAR, FD, lf] = system_fa_breakdown('far', RU, POL, LBL, aU, T, iDQN, PP.ebno, cls_list, per_ms);
Q = trained_world();
far_src = '4 test-split + 4 data/clean_test_pools.mat geometries per Eb/N0, one episode each, Eb/N0 >= 3 dB (synthetic)';
hdr = sprintf('False alarms on the clean link, every independent clean flight: %s, %d episodes x %d cycles -> KPI 6', ...
    far_src, sum(aU), T);
KP = struct('lect', LK, 'far', FAR, 'far_diag', FD, 'far_src', far_src, 'ebno', PP.ebno, 'ebno_thr', ebno_thr, ...
    'cls_list', {cls_list}, 'det_id', 'det1', 'confirm', [3 3], 'alarm_mode', 'class_drop', 'policy_stamp', policy_stamp(Q));
E = struct('ALL', {ALL}, 'POL', {POL}, 'LBL', {LBL}, 'iDQN', iDQN, 'KP', KP, 'RES', {RES}, 'RW', {RW}, ...
    'set_names', {{'single', 'clean'}});
txt = [{'=== Decision-layer evaluation on the test pools ===', 'Generated: synthetic'}, ll, ...
    {'', 'False alarms on the clean link, test pools', ''}, {hdr}, lf, ...
    {'', 'Configuration at the end of the episode, deployed policy (single set): most frequent two per threat'}];
end

function [SW, FS, FT, FC, FG, FL] = fresh_flags(p)
% Fresh clean flights 1..12 (4 per Eb/N0). rule + escalation: false alarms on 3 (0 dB, below the
% KPI 1 threshold), 6 (jamming, healthy, first cycle 2) and 11 (none, degraded, 2 changes, first
% cycle 9); the deployed DQN on 8 (unknown, drop alarm, first cycle 1); random everywhere.
SW = zeros(1, 12); FS = SW; FT = SW; FC = SW; FG = false(1, 12); FL = FG;
switch p
    case 'rule_esc'
        i = [3 6 11]; SW(i) = [1 1 2]; FT(i) = [1 2 9]; FC(i) = [2 2 1]; FS(6) = 1; FG(11) = true;
    case 'dqn_g1'
        SW(8) = 1; FT(8) = 1; FC(8) = 6; FL(8) = true;
    case 'random'
        SW(:) = 3; FT(:) = 1; FC(:) = 1;
end
end

function [E, PP, txt, Q] = eval_world_fresh()
% P1R's C2e (evaluate_policies.m with kpi6_set fresh) on sysfa_world: KPI 6 on the fresh clean
% test set alone (RWf, split id 7, KPI 6 from 3 dB), the union beside it as KP.far_union and
% printed as already read, the lecturer lines with P1R's label, KP.far_set fresh, KP.reading P1R.
[E, PP, txt0, Q] = eval_world();
POL = E.POL; KP = E.KP; T = 30; per_ms = 20;
lbl = ' [P1R: with the fixed monitor, second reading, descriptive]';
s12 = kron(1:3, ones(1, 4)); r12 = repmat(1:4, 1, 3);
RWf = cell(1, numel(POL));
for k = 1:numel(POL)
    [SW, FS, FT, FC, FG, FL] = fresh_flags(POL{k});
    RWf{k} = struct('s', s12, 'r', r12 + 20, 'geom', 1000 * s12 + r12 + 20, 'split', 7 * ones(1, 12), ...
        'onset', 3 * ones(1, 12), 'switches', SW, 'false_sw', FS, 'fc_t', FT, 'fc_cls', FC, 'fc_deg', FG, ...
        'fc_dal', FL, 'fc_drop', 2 * (SW > 0));
end
aF = PP.ebno(RWf{1}.s) >= KP.ebno_thr;
[FAR, FD, lf] = system_fa_breakdown('far', RWf, POL, E.LBL, aF, T, E.iDQN, PP.ebno, KP.cls_list, per_ms);
src = ['4 data/clean_fresh_pools.mat geometries per Eb/N0 (the fresh clean test set, families 7-9, block 15), one ' ...
    'episode each, Eb/N0 >= 3 dB (synthetic)'];
KP.far_union = KP.far; KP.far_diag_union = KP.far_diag; KP.far_src_union = KP.far_src;
KP.far = FAR; KP.far_diag = FD; KP.far_src = src; KP.far_set = 'fresh'; KP.reading = 'P1R';
E.KP = KP; E.RWf = RWf;
[~, ll] = lect_kpis(E.ALL, POL, E.LBL, E.iDQN, PP.scen, 5e4, per_ms);
for i = 1:numel(ll)
    if ~isempty(ll{i}) && ~isempty(strtrim(ll{i})), ll{i} = [ll{i} lbl]; end
end
iu = find(startsWith(txt0, 'False alarms on the clean link, every independent clean flight: '));
lu = txt0(iu + 1:end - 2);
hu = strrep(txt0{iu}, ' -> KPI 6', ': already read in profile 1''s C2e, second reading, descriptive');
hf = sprintf('False alarms on the clean link, the fresh clean test set (P1R, read once): %s, %d episodes x %d cycles -> KPI 6', ...
    src, sum(aF), T);
txt = [{'=== Decision-layer evaluation on the test pools ===', 'P1R: synthetic', 'Generated: synthetic'}, ll, ...
    {'', 'False alarms on the clean link, test pools', ''}, {hu}, lu, {''}, {hf}, lf, ...
    {'', 'Configuration at the end of the episode, deployed policy (single set): most frequent two per threat'}];
end

%% ---------- helpers ----------
function same_outputs(tc, a, b, base)
% The text of two runs byte for byte and their saved variables equal (isequaln).
verifyEqual(tc, fileread(fullfile(b, [base '.txt'])), fileread(fullfile(a, [base '.txt'])));
A = load(fullfile(a, [base '.mat'])); B = load(fullfile(b, [base '.mat']));
verifyEqual(tc, sort(fieldnames(B)), sort(fieldnames(A)));
for f = fieldnames(A)'
    if isfield(B, f{1}), verifyTrue(tc, isequaln(A.(f{1}), B.(f{1})), f{1}); end
end
end

function gate_fails(tc, E, PP, Q, txt, pat)
G = system_fa_breakdown('gate', E, PP, Q, txt);
verifyFalse(tc, G.pass, pat);
verifyTrue(tc, any(contains(G.mismatch, pat)), sprintf('"%s" not among: %s', pat, strjoin(G.mismatch, ' || ')));
end

function R = cat_fields(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function b = fn_block(txt, name)
% The lines of local function name, up to the next function, without trailing empty lines
% and section headers.
L = splitlines(strrep(txt, sprintf('\r'), ''));
s = find(~cellfun(@isempty, regexp(L, ['^function .*\<' name '\('], 'once')), 1);
if isempty(s), b = {}; return; end
e = find(startsWith(L(s + 1:end), 'function '), 1);
if isempty(e), e = numel(L) - s + 1; end
b = L(s:s + e - 1);
while ~isempty(b) && (isempty(strtrim(b{end})) || startsWith(b{end}, '%%')), b(end) = []; end
end

function write_text(f, lines)
fid = fopen(f, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
end

function t = read_text(f)
t = regexp(fileread(f), '\r?\n', 'split');
if ~isempty(t) && isempty(t{end}), t(end) = []; end
end
