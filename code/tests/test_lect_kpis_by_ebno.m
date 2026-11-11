function tests = test_lect_kpis_by_ebno
%TEST_LECT_KPIS_BY_EBNO  Unit tests of the lecturer's readings by Eb/N0 (lect_kpis_by_ebno.m) on synthetic
%   episodes; no pools. Run from the repository root:
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

%% ---------- lect_kpis_by_ebno.m ----------
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
G = lect_kpis_by_ebno('gate', X, PP, txt);
verifyTrue(tc, any(contains(G.mismatch, 'leaf.per(1).red_pct: 1 of ')) && any(contains(G.mismatch, 'max |d| ')), ...
    'the diagnostics name the leaf, the count and the size of the difference');
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
o2 = read_text(fullfile(out2, 'lect_kpis_by_ebno.gatefail.txt'));
verifyTrue(tc, startsWith(o2{1}, 'GATE FAIL'));
verifyFalse(tc, any(startsWith(o2, '=== Line')));
% a failed gate spends nothing: no reading output, the diagnostics beside, the thread count real
verifyFalse(tc, isfile(fullfile(out2, 'lect_kpis_by_ebno.txt')) || isfile(fullfile(out2, 'lect_kpis_by_ebno.mat')));
Fg = load(fullfile(out2, 'lect_kpis_by_ebno.gatefail.mat'));
verifyFalse(tc, Fg.G.pass);
verifyTrue(tc, any(startsWith(o2, sprintf('threads %d (', Fg.nthr))) && ~any(contains(o2, 'as C2e')));
verifyEqual(tc, Fg.nthr, maxNumCompThreads);
% the reading is still open: a second failure keeps the first diagnostics, the right inputs then pass once
verifyError(tc, @() lect_kpis_by_ebno('run', fp, fe, ft2, out2), 'lect_kpis_by_ebno:gate');
verifyEqual(tc, numel(dir(fullfile(out2, 'lect_kpis_by_ebno.gatefail*.txt'))), 2);
verifyEqual(tc, numel(dir(fullfile(out2, 'lect_kpis_by_ebno.gatefail*.mat'))), 2);
lect_kpis_by_ebno('run', fp, fe, ft, out2);
o3 = read_text(fullfile(out2, 'lect_kpis_by_ebno.txt'));
verifyTrue(tc, startsWith(o3{1}, 'GATE PASS'));
verifyError(tc, @() lect_kpis_by_ebno('run', fp, fe, ft, out2), 'lect_kpis_by_ebno:once');
verifyError(tc, @() lect_kpis_by_ebno('run', fp, fe, ft2, out2), 'lect_kpis_by_ebno:once');
fb = fullfile(d, 'not_a_mat.mat'); write_text(fb, {'not a MAT-file'});
out3 = fullfile(d, 'read3'); mkdir(out3);
threw = false;
try, lect_kpis_by_ebno('run', fp, fb, ft, out3); catch, threw = true; end
verifyTrue(tc, threw);
verifyTrue(tc, isfile(fullfile(out3, 'low_ebno_mark.txt')));
verifyError(tc, @() lect_kpis_by_ebno('run', 'policy_pools.mat', fe, ft, out3), 'lect_kpis_by_ebno:input');
end

function test_sha_matches_sha256sum(tc)
f = fullfile(tc.TestData.tmp, 'abc.txt'); fid = fopen(f, 'w'); fwrite(fid, 'abc'); fclose(fid);
verifyEqual(tc, lect_kpis_by_ebno('sha', f), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
end

function test_gate_repeats_the_receiver_robust_column(tc)
% C2e's call carries the receiver-robust column; the gate repeats it with the U_s stored in KP.lect, in any folder, and
% stops on a changed column or line.
Us = struct('per', 0.01, 'gput', 100, 'trec', 0.5);
[E, PP, txt] = eval_world(Us);
verifyTrue(tc, any(contains(txt, 'receiver-robust (U_s from D2c')));
verifyEqual(tc, E.KP.lect.core.cnn.rr.Us, Us);
G = lect_kpis_by_ebno('gate', E, PP, txt);
verifyTrue(tc, G.pass, strjoin(G.mismatch, newline));
X = E; X.KP.lect.core.cnn.rr.robust{1} = 'no';
gate_fails(tc, X, PP, txt, 'KP.lect');
t = txt; i = find(contains(t, 'receiver-robust (U_s from D2c'), 1); t{i} = [t{i} ' '];
gate_fails(tc, E, PP, t, 'lect_kpis''s lines: first difference');
% a call without the column is reproduced without it
[E0, PP0, txt0] = eval_world();
verifyFalse(tc, any(contains(txt0, 'receiver-robust')));
verifyTrue(tc, lect_kpis_by_ebno('gate', E0, PP0, txt0).pass);
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

function [E, PP, txt] = eval_world(Us)
% C2e's saved variables and text on ebno_world: the threat sets pooled, the clean sets of the
% test split and of the clean pools (KPI 6 from 3 dB), KP.lect and KP.far as C2e computes them.
[ALL, POL, LBL, scen, PP] = ebno_world();
iDQN = 2; per_ms = 20; T = 30; ebno_thr = 3;
opt = {}; if nargin > 0, opt = {struct('rr', Us)}; end         % C2e's call with the receiver-robust column
cls_list = {'none', 'jamming', 'tone_jamming', 'path_loss', 'unknown'};
[LK, ll] = lect_kpis(ALL, POL, LBL, iDQN, scen, 5e4, per_ms, opt{:});
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
