function tests = test_lect_kpis_by_ebno
%TEST_LECT_KPIS_BY_EBNO  Unit tests of the lecturer's readings by Eb/N0 (lect_kpis_by_ebno.m) and
%   of the bandwidth study's readings by link (core_bw_lect_by_link.m), on synthetic episodes;
%   no pools. Run from the repository root:
%   results = runtests('code/tests/test_lect_kpis_by_ebno.m')
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

%% ---------- profile 1 and 3: lect_kpis_by_ebno.m ----------
function test_mark_tags(tc)
% R1: link-limited where 2 x the clean packet loss >= 1, working point below 0.1, marginal
% between; 0.45 is marginal, not link-limited; 0.5 is the boundary.
M = lect_kpis_by_ebno('mark', [0.99 0.84 0.62 0.02 0.01 0], 2);
verifyEqual(tc, M.L, logical([1 1 1 0 0 0]));
verifyEqual(tc, M.tag, {'L', 'L', 'L', 'J', 'J', 'J'});
M = lect_kpis_by_ebno('mark', [0.45 0.5 0.1 0.0999], 2);
verifyEqual(tc, M.L, logical([0 1 0 0]));
verifyEqual(tc, M.tag, {'M', 'L', 'M', 'J'});
verifyEqual(tc, decision_config().ratio_ok, 2);
end

function test_full_mask_reproduces_lect_kpis(tc)
% A mask that keeps every episode gives lect_kpis.m's output exactly, and the gate passes on
% C2e's own numbers and text; a last-bit change of KP.lect, a changed line, other episodes
% under one policy or another Eb/N0 grid stop it.
[ALL, POL, LBL, scen] = ebno_world();
[L1, l1] = lect_kpis(ALL, POL, LBL, 2, scen, 5e4, 20);
[L2, l2] = lect_kpis(lect_kpis_by_ebno('subset', ALL, true(1, numel(ALL{1}.s))), POL, LBL, 2, scen, 5e4, 20);
verifyTrue(tc, isequaln(L1, L2));
verifyEqual(tc, l1, l2);
[E, PP, txt] = eval_world();
G = lect_kpis_by_ebno('gate', E, PP, txt);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
verifyEqual(tc, G.T, 30);
X = E; X.KP.lect.per(1).red_pct = X.KP.lect.per(1).red_pct + eps(X.KP.lect.per(1).red_pct);
gate_fails(tc, X, PP, txt, 'KP.lect: .per differs');
t = txt; i = find(startsWith(t, '  PRIMARY narrowband'), 1); t{i} = [t{i} ' '];
gate_fails(tc, E, PP, t, 'lect_kpis''s lines: first difference');
X = E; X.ALL{3}.s([1 7]) = X.ALL{3}.s([7 1]);
gate_fails(tc, X, PP, txt, 'ALL{3} (blind_esc) does not hold the episodes');
P2 = PP; P2.ebno = [0 3 7];
gate_fails(tc, E, P2, txt, 'Eb/N0 grid');
X = E; X.KP = rmfield(X.KP, 'lect');
gate_fails(tc, X, PP, txt, 'KP lacks lect');
end

function test_subset_keeps_pairing(tc)
% Episode i stays episode i under every policy, every per-episode field (a 3 x NE one too)
% cut alike; a field that is not one per episode stops the subset.
ALL = ebno_world();
for k = 1:numel(ALL)
    ALL{k}.id = (1:numel(ALL{k}.s)) + 100 * k;
    ALL{k}.aoa = reshape(1:3 * numel(ALL{k}.s), 3, []) + 1000 * k;
end
keep = mod(1:numel(ALL{1}.s), 3) ~= 0;
A = lect_kpis_by_ebno('subset', ALL, keep);
for k = 1:numel(A)
    verifyEqual(tc, A{k}.id, find(keep) + 100 * k);
    verifyEqual(tc, A{k}.aoa, ALL{k}.aoa(:, keep));
    verifyEqual(tc, [A{k}.s; A{k}.geom; A{k}.scn], [A{1}.s; A{1}.geom; A{1}.scn]);
    verifyEqual(tc, A{k}.per_post, ALL{k}.per_post(keep));
end
verifyError(tc, @() lect_kpis_by_ebno('subset', {struct('x', 1:3, 'y', 1)}, true(1, 3)), 'lect_kpis_by_ebno:field');
end

function test_link_limited_row_undefined(tc)
% At the L point (packet loss restored on every cycle) recovery from detection is printed as
% undefined, never as a number, and T_rec as BER-only; its detected episodes are Line A's N.
[E, PP, txt] = eval_world();
M = lect_kpis_by_ebno('mark', PP.clean_fer, 2);
G = lect_kpis_by_ebno('gate', E, PP, txt);
[S, lines] = lect_kpis_by_ebno('readings', E, PP, M, G);
und = 'undefined (restoration threshold >= 100%)';
r0 = row_of(lines, 0); r3 = row_of(lines, 3);
verifyTrue(tc, startsWith(r0{1}, '  Eb/N0 0 dB [L, link-limited] clean packet loss 0.950: 6 episodes, 6 threat, 5 recoverable threat, 4 recoverable jamming'));
cnn = r0(contains(r0, 'CNN contribution'));
verifyNotEmpty(tc, cnn);
verifyTrue(tc, all(endsWith(cnn, ['detection -> PER restored ' und])));
rec = r0(startsWith(r0, '      ') & endsWith(r0, ' BER-only'));
verifyGreaterThanOrEqual(tc, numel(rec), 6);
verifyTrue(tc, all(contains(rec, ['| ' und ' |'])));
verifyFalse(tc, any(contains(r3, und)));
verifyTrue(tc, any(contains(r0, 'normalized n/a (clean loss > 90%)')));
q = S.n_rec(strcmp({S.n_rec.set}, 'recoverable threat episodes') & strcmp({S.n_rec.policy}, 'blind_esc'));
verifyEqual(tc, [q.n q.zero q.later q.never], [5 5 0 0]);
verifyTrue(tc, any(contains(lines, 'includes N = 5 episodes at L points where t_rec_det is set by construction (5 at 0, 0 later, 0 never)')));
verifyTrue(tc, any(contains(lines, 'Line B, non-L points (headline)')));
iA = find(startsWith(lines, '=== Line A')); iB = find(startsWith(lines, '=== Line B'));
iP = find(startsWith(lines, '=== Per Eb/N0'));
verifyTrue(tc, isscalar(iA) && isscalar(iB) && isscalar(iP) && iA < iB && iB < iP);
b = lines(iB + 1:iP - 1);
v = b(contains(b, '-> MET') | contains(b, '-> NOT MET'));
verifyNotEmpty(tc, v);
verifyTrue(tc, all(endsWith(v, ' [second line, not the verdict]')));
a = lines(iA + 1:iB - 1);
verifyFalse(tc, any(contains(a, 'second line, not the verdict')));
end

function test_point_subset_clusters(tc)
% A per-Eb/N0 subset holds only the flight geometries of that point (geom = 1000 s + r), and
% the gate stops when a geometry spans two points.
ALL = ebno_world();
for s = 1:3
    A = lect_kpis_by_ebno('subset', ALL, ALL{1}.s == s);
    for k = 1:numel(A)
        verifyTrue(tc, all(floor(A{k}.geom / 1000) == s) && all(A{k}.s == s));
    end
end
[E, PP, txt] = eval_world();
for k = 1:numel(E.ALL), E.ALL{k}.geom(1) = 2001; end
gate_fails(tc, E, PP, txt, 'spans two Eb/N0 points');
end

function test_far_report_copy(tc)
% far_report and cp_upper are evaluate_policies.m's word for word; the copy reproduces KP.far
% in the gate and a changed KP.far stops it; a subset without any episode prints n = 0, and a
% point without any jamming episode prints its rows with n = 0, no error.
mine = fileread(which('lect_kpis_by_ebno'));
ev = fileread(which('evaluate_policies'));
for f = {'far_report', 'cp_upper'}
    verifyNotEmpty(tc, fn_block(mine, f{1}), f{1});
    verifyEqual(tc, fn_block(mine, f{1}), fn_block(ev, f{1}), f{1});
end
[E, PP, txt] = eval_world();
G = lect_kpis_by_ebno('gate', E, PP, txt);
verifyTrue(tc, G.pass);
verifyTrue(tc, isequaln(G.far, E.KP.far) && isequaln(G.far_diag, E.KP.far_diag));
X = E; X.KP.far(2).k = 99;
gate_fails(tc, X, PP, txt, 'KP.far: .k differs');
t = txt; i = find(startsWith(t, '  no detector + escalation') & contains(t, 'upper'), 1); t{i} = strrep(t{i}, 'upper', 'Upper');
gate_fails(tc, E, PP, t, 'far_report''s lines');
[F0, D0, l0] = lect_kpis_by_ebno('far', G.RU, E.POL, E.LBL, false(size(G.aboveU)), 30, 2, PP.ebno, E.KP.cls_list, 20);
verifyEqual(tc, [F0.n], zeros(1, numel(F0)));
verifyTrue(tc, all(contains(l0(startsWith(l0, '  ') & contains(l0, ' / ') & contains(l0, 'upper')), '   0 /    0')));
verifyEqual(tc, D0(1).n_ebno, [0 0 0]);
[ALL, POL, LBL, scen] = ebno_world();
Lk = lect_kpis(lect_kpis_by_ebno('subset', ALL, ALL{1}.scn == 4), POL, LBL, 2, scen, 5e4, 20);   % no jamming episode
l = lect_kpis_by_ebno('rows', Lk, true, 20, '');
verifyEqual(tc, [Lk.verdict.n], [0 0]);
verifyTrue(tc, any(strcmp(l, '    PER narrowband (tone_jamming): no recoverable episodes -> NOT MET (descriptive, not a verdict)')));
verifyTrue(tc, any(contains(l, 'CNN contribution (0 episodes)')));
end

function test_late_detection_counts_never(tc)
% An L episode detected two cycles before the end never holds 5 restored cycles: per_metrics.m
% gives NaN, and Line A's N counts it as never, not as 0.
[ALL, POL] = ebno_world();
R = ALL{strcmp(POL, 'rule_esc')};
verifyEqual(tc, R.t_rec_det(1), 0);
verifyTrue(tc, isnan(R.t_rec_det(2)));
[E, PP, txt] = eval_world();
M = lect_kpis_by_ebno('mark', PP.clean_fer, 2);
G = lect_kpis_by_ebno('gate', E, PP, txt);
S = lect_kpis_by_ebno('readings', E, PP, M, G);
sel = @(set) S.n_rec(strcmp({S.n_rec.set}, set) & strcmp({S.n_rec.policy}, 'rule_esc'));
q = sel('recoverable jamming episodes');
verifyEqual(tc, [q.n q.zero q.later q.never], [4 3 0 1]);
q = sel('recoverable threat episodes');
verifyEqual(tc, [q.n q.zero q.later q.never], [5 4 0 1]);
end

function test_run_order_and_once(tc)
% The single run: the mark with the pools' hash, then the gate, then Line A, Line B, the
% per-Eb/N0 rows and KPI 6 in this order; a second run is refused; a failed gate prints no
% subset; the mark is written before the evaluation is opened.
[E, PP, txt] = eval_world();
d = fullfile(tc.TestData.tmp, 'run_ebno'); mkdir(d);
fp = fullfile(d, 'policy_pools.mat'); save(fp, 'PP');
fe = fullfile(d, 'policy_evaluation.mat'); save(fe, '-struct', 'E');
ft = fullfile(d, 'policy_evaluation.txt'); write_text(ft, txt);
out = fullfile(d, 'read1'); mkdir(out);
lect_kpis_by_ebno('run', fp, fe, ft, out);
mk = read_text(fullfile(out, 'low_ebno_mark.txt'));
verifyTrue(tc, startsWith(mk{1}, '# Link-limited Eb/N0 points'));
verifyTrue(tc, any(strcmp(mk, ['pools_sha256 ' lect_kpis_by_ebno('sha', fp)])));
verifyEqual(tc, mk(end-2:end), {sprintf('0 %.17g %.17g 1 L', 0.95, 2 * 0.95), sprintf('3 %.17g %.17g 0 M', 0.3, 2 * 0.3), ...
    sprintf('6 %.17g %.17g 0 J', 0.02, 2 * 0.02)});
o = read_text(fullfile(out, 'lect_kpis_by_ebno.txt'));
verifyTrue(tc, startsWith(o{1}, 'GATE PASS'));
h = cellfun(@(p) find(startsWith(o, p)), {'=== Line A', '=== Line B', '=== Per Eb/N0', '=== KPI 6'}, 'UniformOutput', false);
verifyTrue(tc, all(cellfun(@numel, h) == 1));
verifyTrue(tc, issorted([h{:}]));
R = load(fullfile(out, 'lect_kpis_by_ebno.mat'));
verifyTrue(tc, R.G.pass && isfield(R, 'S') && ~isfield(R.G, 'RU'));
verifyError(tc, @() lect_kpis_by_ebno('run', fp, fe, ft, out), 'lect_kpis_by_ebno:once');
t = txt; i = find(startsWith(t, '  extension, the five jamming threats pooled'), 1); t{i} = [t{i} 'x'];
ft2 = fullfile(d, 'policy_evaluation_changed.txt'); write_text(ft2, t);
out2 = fullfile(d, 'read2'); mkdir(out2);
verifyError(tc, @() lect_kpis_by_ebno('run', fp, fe, ft2, out2), 'lect_kpis_by_ebno:gate');
o2 = read_text(fullfile(out2, 'lect_kpis_by_ebno.txt'));
verifyTrue(tc, startsWith(o2{1}, 'GATE FAIL'));
verifyFalse(tc, any(startsWith(o2, '=== Line')));
fb = fullfile(d, 'not_a_mat.mat'); write_text(fb, {'not a MAT-file'});
out3 = fullfile(d, 'read3'); mkdir(out3);
threw = false;
try, lect_kpis_by_ebno('run', fp, fb, ft, out3); catch, threw = true; end
verifyTrue(tc, threw);
verifyTrue(tc, isfile(fullfile(out3, 'low_ebno_mark.txt')));
verifyError(tc, @() lect_kpis_by_ebno('run', 'policy_pools.mat', fe, ft, out3), 'lect_kpis_by_ebno:input');
end

function test_sha_and_readers_match_tip(tc)
% The file hash is sha256sum's; the readers the script calls are profile 1's merged tip's
% files unchanged, and so are the files it copies from.
f = fullfile(tc.TestData.tmp, 'abc.txt'); fid = fopen(f, 'w'); fwrite(fid, 'abc'); fclose(fid);
verifyEqual(tc, lect_kpis_by_ebno('sha', f), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
root = tc.TestData.root; ref = '8b28bdfb8dfc1e4339b6be0d29a27e0552f45769';
st = system(sprintf('git -C "%s" cat-file -e %s', root, ref));
assumeEqual(tc, st, 0, 'git or the tip''s commit is not available here');
for g = {'code/evaluation/lect_kpis.m', 'code/evaluation/per_reduction.m', 'code/evaluation/boot_cluster.m', ...
        'code/evaluation/false_change_rate.m', 'code/evaluation/three_state_view.m', 'code/decision/per_metrics.m', ...
        'code/decision/decision_config.m', 'code/decision/packet_share.m', 'code/decision/core_bw_rules.m', ...
        'code/decision/evaluate_policies.m', 'code/decision/experiment_core_bw.m'}
    [~, theirs] = system(sprintf('git -C "%s" show %s:%s', root, ref, g{1}));
    verifyEqual(tc, strrep(fileread(fullfile(root, g{1})), sprintf('\r'), ''), strrep(theirs, sprintf('\r'), ''), g{1});
end
end

%% ---------- CORE_BW: core_bw_lect_by_link.m ----------
function test_core_bw_copies_match(tc)
% The readers are experiment_core_bw.m's word for word.
mine = fileread(which('core_bw_lect_by_link'));
ex = fileread(which('experiment_core_bw'));
for f = {'plr_threshold', 'read_recoverable', 'recoverable_mask', 'get_set', 'pol', 'per_lines', 'qstat'}
    verifyNotEmpty(tc, fn_block(mine, f{1}), f{1});
    verifyEqual(tc, fn_block(mine, f{1}), fn_block(ex, f{1}), f{1});
end
end

function test_core_bw_mark_and_reading(tc)
% Per episode: L when the flight's own threshold (2 x its clean loss + 1/n) >= 1; the gate
% passes on the report's numbers and stops on a changed one; Line A then Line B; N counts the
% detected L episodes, a never one apart; the scenarios holding L episodes are counted.
[T, REC, KPc, rep, PP, pay] = core_bw_world(tc);
thr = core_bw_lect_by_link('mark', PP);
verifyEqual(tc, thr, [1.3 0.7; 0.1 0.1], 'AbsTol', 1e-12);
EP = T.EPs; Lep = thr(sub2ind(size(thr), EP.s, EP.r)) >= 1;
verifyEqual(tc, Lep, EP.s == 1 & EP.r == 1);
P = struct('ebno', PP.ebno, 'runs', {PP.runs}, 'params_id', PP.params_id, 'det_id', PP.det_id);
G = core_bw_lect_by_link('gate', T, REC, KPc, rep, P, pay);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
X = KPc; X.KP.primary.per(1).red = X.KP.primary.per(1).red + eps(X.KP.primary.per(1).red);
G2 = core_bw_lect_by_link('gate', T, REC, X, rep, P, pay);
verifyFalse(tc, G2.pass); verifyTrue(tc, any(contains(G2.mismatch, 'KP.primary: .per differs')));
r2 = rep; i = find(startsWith(r2, '  PER rule_core'), 1); r2{i} = [r2{i} ' '];
G2 = core_bw_lect_by_link('gate', T, REC, KPc, r2, P, pay);
verifyFalse(tc, G2.pass); verifyTrue(tc, any(contains(G2.mismatch, 'in the report: first difference')));
Q = P; Q.det_id = 'other';
verifyFalse(tc, core_bw_lect_by_link('gate', T, REC, KPc, rep, Q, pay).pass);
[S, lines] = core_bw_lect_by_link('readings', T, G, Lep, pay);
verifyEqual(tc, [S.n_L, S.n_L_recoverable], [4 4]);
verifyEqual(tc, size(S.scen, 1), 3);
verifyEqual(tc, [sum(S.scen_anyL), sum(S.scen_allL)], [2 0]);
q = S.n_rec(strcmp({S.n_rec.policy}, 'rule_core') & strcmp({S.n_rec.type}, 'pooled'));
verifyEqual(tc, [q.n q.zero q.later q.never], [4 3 0 1]);
q = S.n_rec(strcmp({S.n_rec.policy}, 'blind_core') & strcmp({S.n_rec.type}, 'narrowband'));
verifyEqual(tc, [q.n q.zero q.later q.never], [2 2 0 0]);
iA = find(startsWith(lines, '=== Line A')); iB = find(startsWith(lines, '=== Line B'));
verifyTrue(tc, isscalar(iA) && isscalar(iB) && iA < iB);
b = lines(iB + 1:end);
verifyTrue(tc, all(endsWith(b(contains(b, '-> MET') | contains(b, '-> NOT MET')), ' [second line, not the verdict]')));
verifyTrue(tc, any(contains(lines, 'includes N = 4 L episodes where t_rec_det is set by construction (3 at 0, 0 later, 1 never)')));
end

function test_core_bw_run(tc)
% The single run of the bandwidth study's reading: the mark with the pools' hash before the
% test readings are opened, the gate, Line A then Line B; a second run is refused.
[T, REC, KPc, rep, PP] = core_bw_world(tc); %#ok<ASGLU>
d = fullfile(tc.TestData.tmp, 'run_corebw'); mkdir(d);
F = struct('pools', fullfile(d, 'pools.mat'), 'test', fullfile(d, 'test_readings.mat'), 'recov', fullfile(d, 'recoverable.txt'), ...
    'kpis', fullfile(d, 'core_bw_kpis.mat'), 'report', fullfile(d, 'core_bw_report.txt'), 'params', fullfile(d, 'params.mat'), ...
    'out', fullfile(d, 'read'));
mkdir(F.out);
save(F.pools, 'PP');
save(F.test, '-struct', 'T');
copyfile(fullfile(tc.TestData.tmp, 'core_bw_world', 'recoverable.txt'), F.recov);
KP = KPc.KP; lines = KPc.lines; save(F.kpis, 'KP', 'lines'); %#ok<NASGU>
write_text(F.report, rep);
params = struct('bits_per_frame', 1000, 'cycle_s', 0.02); save(F.params, 'params');
core_bw_lect_by_link('run', F);
mk = read_text(fullfile(F.out, 'core_bw_low_ebno_mark.txt'));
verifyTrue(tc, any(strcmp(mk, ['pools_sha256 ' lect_kpis_by_ebno('sha', F.pools)])));
t1 = 2 * mean([ones(1, 6) zeros(1, 4)]) + 1 / 10; t2 = 2 * mean([ones(1, 3) zeros(1, 7)]) + 1 / 10;
verifyEqual(tc, mk(end-3:end), {sprintf('0 1 1401 %.17g 1', t1), sprintf('0 2 1402 %.17g 0', t2), ...
    sprintf('3 1 1401 %.17g 0', 1 / 10), sprintf('3 2 1402 %.17g 0', 1 / 10)});
o = read_text(fullfile(F.out, 'core_bw_lect_by_link.txt'));
verifyTrue(tc, startsWith(o{1}, 'GATE PASS'));
verifyLessThan(tc, find(startsWith(o, '=== Line A')), find(startsWith(o, '=== Line B')));
verifyError(tc, @() core_bw_lect_by_link('run', F), 'core_bw_lect_by_link:once');
end

%% ---------- worlds ----------
function [ALL, POL, LBL, scen, PP] = ebno_world()
% Three Eb/N0 points (0 dB link-limited, 3 dB marginal, 6 dB working point), six episodes
% each: jamming (1, 2, 6; 6 not recoverable), tone_jamming (3, 4), path_loss (5). At the L point
% the packet loss is restored on every cycle, so t_rec_det follows from the detection alone
% (per_metrics.m); rule + escalation detects episode 2 two cycles before the end. Jamming threats
% (lect_kpis.m) are jamming and tone_jamming here: four recoverable per point. At the L point
% the clean link loses 95%, so the normalized goodput is not defined there.
POL = {'none', 'rule_esc', 'blind_esc', 'oracle', 'rule_core', 'blind_core'};
LBL = {'no response', 'rule + escalation', 'no detector + escalation', 'oracle', 'core: rule + escalation', ...
    'core: no detector + escalation'};
scen = {'none', 'jamming', 'tone_jamming', 'path_loss'};
PP = struct('ebno', [0 3 6], 'scen', {scen}, 'clean_fer', [0.95 0.3 0.02], 'det_id', 'det1');
T = 20; onset = 3;
s = kron(1:3, ones(1, 6)); r = repmat([1 1 2 2 3 4], 1, 3); n = numel(s);
B = struct('scn', repmat([2 2 3 3 4 2], 1, 3), 's', s, 'r', r, 'geom', 1000 * s + r, ...
    'recoverable', repmat(logical([1 1 1 1 1 0]), 1, 3), 'recoverable_core', repmat(logical([1 1 1 1 1 0]), 1, 3), ...
    'threat', true(1, n), 'aoa', zeros(3, n));
L = s == 1; nL = sum(L);
post = repmat((1:T)' >= onset, 1, nL);
ALL = cell(1, numel(POL));
for k = 1:numel(POL)
    R = B;
    switch POL{k}
        case 'none'
            per = [0.9 0.5 0.5]; dl = [0.1 0.5 0.5]; tcf = ones(1, n); rd = nan(1, n);
        case {'blind_esc', 'blind_core'}
            per = [0.6 0.3 0.3]; dl = [0.4 0.7 0.7]; tcf = 2 * ones(1, n); rd = 4 * ones(1, n);
        case 'oracle'
            per = [0.2 0 0]; dl = [0.8 1 1]; tcf = nan(1, n); rd = nan(1, n);
        otherwise
            per = [0.3 0.1 0.1]; dl = [0.7 0.9 0.9]; tcf = ones(1, n); rd = 2 * ones(1, n);
            tcf(2) = T - onset - 1;
    end
    R.per_post = per(s) + 0.01 * (R.scn == 3); R.dlv_post = dl(s);
    M = per_metrics(zeros(T, nL), post, false(T, nL), true(T, nL), ones(T, nL), tcf(L), 5);
    rd(L) = M.t_rec_det;
    R.t_conf = tcf; R.t_rec_det = rd; R.t_rec = tcf + rd;
    R.gput_post = R.dlv_post; R.gput_post(L) = NaN;
    R.recovered = isfinite(R.t_rec);
    ALL{k} = R;
end
end

function [E, PP, txt] = eval_world()
% C2e's saved variables and text on ebno_world: the threat sets pooled, the clean sets of the
% test split and of the clean pools (KPI 6 from 3 dB), KP.lect and KP.far as C2e computes them.
[ALL, POL, LBL, scen, PP] = ebno_world();
iDQN = 2; per_ms = 20; T = 30; ebno_thr = 3;
cls_list = {'none', 'jamming', 'tone_jamming', 'path_loss', 'unknown'};
[LK, ll] = lect_kpis(ALL, POL, LBL, iDQN, scen, 5e4, per_ms);
s = kron(1:3, ones(1, 4)); r = repmat(1:4, 1, 3);
cl = @(r, sw, sp) struct('s', s, 'r', r, 'geom', 1000 * s + r, 'split', sp * ones(1, 12), 'switches', sw, ...
    'fc_cls', double(sw > 0) * 2, 'fc_deg', sw > 0, 'fc_drop', 2 * (sw > 0));
RES = cell(2, numel(POL)); RW = cell(1, numel(POL)); RU = cell(1, numel(POL));
for k = 1:numel(POL)
    sw = zeros(1, 12); if strcmp(POL{k}, 'blind_esc'), sw([1 5 9 10]) = [1 2 1 1]; end
    RES{1, k} = ALL{k};
    RES{2, k} = cl(r, sw, 3);
    RW{k} = cl(r + 10, fliplr(sw), 3);
    Rw = RW{k}; Rw.split(:) = 6;
    RU{k} = cat_fields(RES{2, k}, Rw);
end
aU = [PP.ebno(RES{2, 1}.s) >= ebno_thr, PP.ebno(RW{1}.s) >= ebno_thr];
[FAR, FD, lf] = lect_kpis_by_ebno('far', RU, POL, LBL, aU, T, iDQN, PP.ebno, cls_list, per_ms);
far_src = '4 test-split + 4 data/clean_test_pools.mat geometries per Eb/N0, one episode each, Eb/N0 >= 3 dB (synthetic)';
hdr = sprintf('False alarms on the clean link, every independent clean flight: %s, %d episodes x %d cycles -> KPI 6', ...
    far_src, sum(aU), T);
KP = struct('lect', LK, 'far', FAR, 'far_diag', FD, 'far_src', far_src, 'ebno', PP.ebno, 'ebno_thr', ebno_thr, ...
    'cls_list', {cls_list}, 'det_id', 'det1', 'per_ebno', [50 60; 70 80; 90 100], 'show_lbl', {{'no resp.', 'rule+esc'}});
E = struct('ALL', {ALL}, 'POL', {POL}, 'LBL', {LBL}, 'iDQN', iDQN, 'KP', KP, 'RES', {RES}, 'RW', {RW}, ...
    'set_names', {{'single', 'clean'}});
txt = [{'=== Decision-layer evaluation on the test pools ===', 'Generated: synthetic'}, ll, ...
    {'', 'Recovered among recoverable per Eb/N0 (single set), %:', '', 'False alarms on the clean link, test pools', ''}, ...
    {hdr}, lf, {'', 'Configuration at the end of the episode, deployed policy (single set): most frequent two per threat'}];
end

function [T, REC, KPc, rep, PP, pay] = core_bw_world(tc)
% Two scenarios (a CW tone k = 1 and a 20 MHz jammer k = 2) at two Eb/N0 points, two test
% flights, two onsets: 16 episodes. The clean link of flight 1 at 0 dB loses 60% of its packets
% (threshold 2 x 0.6 + 1/10 >= 1: link-limited), flight 2 30%, none at 3 dB. Recoverable:
% both scenarios at 0 dB, the tone at 3 dB. rule_core never restores one L episode (detected
% too late).
PP = struct('ebno', [0 3], 'scen', {{'none', 'tone_jamming', 'jamming'}}, 'actions', {{'no_action', 'channel_switch'}}, ...
    'runs', {{[501 502], [1401 1402]}}, 'event_frame', {{nan(1, 2), nan(1, 2)}}, 'fec_frames', 4, 'params_id', 'p1', ...
    'det_id', 'd1');
PP.pools = cell(3, 2, 2, 2);
run = [1401 * ones(1, 10), 1402 * ones(1, 10)];
PP.pools{1, 1, 1, 2} = struct('run', run, 'fer', [ones(1, 6) zeros(1, 4) ones(1, 3) zeros(1, 7)]);
PP.pools{1, 2, 1, 2} = struct('run', run, 'fer', zeros(1, 20));
[k, s, r, e] = ndgrid(1:2, 1:2, 1:2, 1:2); n = numel(k);
EP = struct('k', k(:)', 's', s(:)', 'r', r(:)', 'rep', e(:)', 'n', n, 'T', 30);
EP.bj = 20 * (EP.k == 2); EP.narrow = EP.bj == 0; EP.slice = false(1, n); EP.occ = false(1, n);
EP.geom = 1000 * EP.s + EP.r;
L = EP.s == 1 & EP.r == 1;
ep = @(per, tcf, rd) struct('ep', 1:n, 'per_post', per, 'dlv_post', 1 - per, 't_conf', tcf, 't_rec_det', rd, ...
    'recoverable', true(1, n), 'threat', true(1, n));
rdn = nan(1, n); rdn(L) = 0;
rdb = 3 * ones(1, n); rdb(L) = 0;
rdr = 2 * ones(1, n); rdr(L) = 0; rdr(find(L, 1)) = NaN;
Rn = ep(0.8 + 0.05 * EP.narrow + 0.01 * EP.r, ones(1, n), rdn);
Rb = ep(0.5 + 0.02 * EP.r, 2 * ones(1, n), rdb);
Rr = ep(0.2 - 0.1 * EP.narrow + 0.01 * EP.r, ones(1, n), rdr);
Ro = ep(0.05 * ones(1, n), nan(1, n), nan(1, n));
RES = struct('rule', 'H1', 'set', 'primary', 'policy', {'none', 'blind_core', 'rule_core', 'oracle'}, 'R', {Rn, Rb, Rr, Ro});
X0 = struct('RULES', {{'H1', 'H3', 'H4'}}, 'B', 200, 'TARGET', 0.3, 'N_RUN', 5);
meta = struct('runs', {PP.runs}, 'params_id', 'p1', 'det_id', 'd1');
T = struct('RES', RES, 'EPs', EP, 'X', X0, 'meta', meta);
d = fullfile(tc.TestData.tmp, 'core_bw_world'); if ~isfolder(d), mkdir(d); end
f = fullfile(d, 'recoverable.txt');
write_text(f, {'# Recoverable scenarios (synthetic)', '# rule scenario_index ebno_index ...', ...
    'H1 1 1 cw_tot23 0 23.00 23.00 0 100.0 0.8500 0.7000 1 1', 'H1 2 1 bw20_tot23 20 23.00 10.00 0 100.0 0.8000 0.7000 1 1', ...
    'H1 1 2 cw_tot23 0 23.00 23.00 3 100.0 0.8500 0.1000 1 1', 'H1 2 2 bw20_tot23 20 23.00 10.00 3 50.0 0.8000 0.1000 1 0', ...
    'H3 1 1 cw_tot23 0 23.00 23.00 0 100.0 0.8500 0.7000 1 1'});
REC = core_bw_lect_by_link('read_recoverable', f);
pay = 5e4;
mask = (EP.k == 1 | EP.s == 1);
[blk, Kp] = core_bw_lect_by_link('per_lines', RES, EP, mask, X0, pay, ...
    'PRIMARY (H1, nRF24L01+ residual by offset, fixed total power, static jammer)', false);
rep = [{'=== Bandwidth study (docs/core_bw_protocol.md) ===', 'params_id p1 | det_id d1'}, blk, ...
    {'  per jammer width (recoverable scenarios, every JSR_tot and Eb/N0):'}];
KPc = struct('KP', struct('primary', Kp), 'lines', {rep});
end

%% ---------- helpers ----------
function gate_fails(tc, E, PP, txt, pat)
G = lect_kpis_by_ebno('gate', E, PP, txt);
verifyFalse(tc, G.pass, pat);
verifyTrue(tc, any(contains(G.mismatch, pat)), sprintf('"%s" not among: %s', pat, strjoin(G.mismatch, ' || ')));
end

function r = row_of(lines, ebno)
% The lines of one Eb/N0 point's row, up to the next point or section.
i = find(startsWith(lines, sprintf('  Eb/N0 %g dB [', ebno)), 1);
j = find(startsWith(lines(i + 1:end), '  Eb/N0 ') | startsWith(lines(i + 1:end), 'Recovered among') | ...
    startsWith(lines(i + 1:end), '===') | cellfun(@isempty, lines(i + 1:end)), 1);
if isempty(j), j = numel(lines) - i + 1; end
r = lines(i:i + j - 1);
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
