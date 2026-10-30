function tests = test_head
%TEST_HEAD  Unit tests of the fusion's candidates over the d91 pick (D110: fuse_head.m,
%   fusion_cand.m, fusion_adopt.m's rules S and W, fusion_recheck.m, head_cost.m, det_cost.m, the
%   switches in fuse_classes.m, fusion_pick.m, fusion_rev_id.m, select_fusion.m, eval_detector.m)
%   and of m_head.m's guards, and of R1 (D116: eval_unseen_snr.m behind unseen_gap,
%   boot_cluster.m's two groups), on synthetic rows in a temporary folder; no data files. Every
%   switch off reads as the parent commit (the branch's base) bit for bit. Run from the
%   repository root:
%   results = runtests('code/tests/test_head.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
addpath(fullfile(tc.TestData.root, 'code', 'dev'));
tc.TestData.base = 'f6f6e03';                            % the branch's base (d108-edge, TIP3's lineage)
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
tc.TestData.X = synth(7);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- the head ----------
function test_head_pack_equals_treebagger(tc)
% The packed trees read exactly as TreeBagger.predict, one row or many; no object is kept.
rs = RandStream('mt19937ar', 'Seed', 11);
X = randn(rs, 400, 6); y = 1 + (X(:, 1) > 0) + 2 * (X(:, 2) > 0.5);
s0 = rng; rng(5, 'twister'); T = TreeBagger(30, X, y, 'Method', 'classification', 'MinLeafSize', 5); rng(s0);
H = fuse_head('pack', T, 4);
[~, sc] = predict(T, X);
cn = str2double(T.ClassNames);
q = fuse_head('score', H, X);
verifyEqual(tc, q(:, cn), sc, 'AbsTol', 1e-12);
for i = 1:20, verifyEqual(tc, fuse_head('score', H, X(i, :)), q(i, :), 'AbsTol', 1e-15); end
verifyEqual(tc, sum(q, 2), ones(400, 1), 'AbsTol', 1e-12);
for f = fieldnames(H)', verifyTrue(tc, isnumeric(H.(f{1})), f{1}); end
end

function test_head_fit_seeded(tc)
% A head is a function of its rows and its stream; the global stream is restored after it.
X = tc.TestData.X; Z = [X.Z0, X.XB]; m = X.fold ~= 1;
pc = softmax_rows(Z(:, 1:X.C));
cols = fuse_head('cols', X.C, X.PK.cues); L = fuse_head('classes', X.classes);
rng(123, 'twister'); s0 = rng;
H1 = fuse_head('fit', pc(m, :), Z(m, :), X.yt(m), L, cols, 9401);
verifyEqual(tc, rng, s0);
H2 = fuse_head('fit', pc(m, :), Z(m, :), X.yt(m), L, cols, 9401);
verifyEqual(tc, H1, H2);
H3 = fuse_head('fit', pc(m, :), Z(m, :), X.yt(m), L, cols, 9402);
verifyFalse(tc, isequal(H1, H3));
verifyEqual(tc, H1.L, L); verifyEqual(tc, H1.cols, cols);
end

function test_head_apply_moves_only_the_level_family(tc)
% p(c) = p_L q(c | x) for the four level-family classes; every other class keeps its p(c).
X = tc.TestData.X; Z = [X.Z0, X.XB];
pc = softmax_rows(Z(:, 1:X.C));
L = fuse_head('classes', X.classes);
H = fuse_head('fit', pc, Z, X.yt, L, fuse_head('cols', X.C, X.PK.cues), 9400);
p2 = fuse_head('apply', H, pc, Z);
o = setdiff(1:X.C, L);
verifyTrue(tc, isequal(p2(:, o), pc(:, o)));
verifyEqual(tc, sum(p2(:, L), 2), sum(pc(:, L), 2), 'AbsTol', 1e-12);
verifyEqual(tc, sum(p2, 2), ones(size(pc, 1), 1), 'AbsTol', 1e-12);
verifyEqual(tc, fuse_head('inputs', H, pc(1, :), Z(1, :)), [log(max(pc(1, L), 1e-6)), log(max(sum(pc(1, L)), 1e-6)), Z(1, H.cols)]);
end

function test_head_cols(tc)
% The head reads the branch, level-step, coherence and LOS cues and the 18 branch-evidence
% columns: no idle column, no cfar column, no gl_phi; the same names with the cfar columns in.
X = tc.TestData.X;
c = fuse_head('cols', X.C, X.PK.cues);
n = fuse_classes('names', X.C, X.PK.cues);
verifyNumElements(tc, c, 49);
nm = n(c);
verifyFalse(tc, any(startsWith(nm, {'i_', 'w_', 'cf_', 'logp_', 'now_'}) | strcmp(nm, 'gl_phi')));
verifyTrue(tc, all(ismember({'margin_mean', 'sinr_gap_w', 'stp_t', 'stp_db_mon', 'coh_contrast', 'los_k', 'iso_t', ...
    'gl_db', 'ps_k_contrast', 'br_w'}, nm)));
o = X.PK.cues; o.cfar = [1 2 3];
c2 = fuse_head('cols', X.C, o); n2 = fuse_classes('names', X.C, o);
verifyEqual(tc, n2(c2), nm);
verifyEqual(tc, fuse_head('seed', 'LBH', []), 9400); verifyEqual(tc, fuse_head('seed', 'LBH+CFAR', 1:5), 9531);
verifyEqual(tc, fuse_head('seed', 'LBH', [1 3]), 9405);
verifyError(tc, @() fuse_head('seed', 'GCC', 1), 'fuse_head:seed');
end

function test_head_single_row_cost(tc)
% S7's measure: a head of M3's settings (100 trees, MinLeafSize 20) on noisy rows of the head's
% width, its single-row call on one thread: p95 at most 1.0 ms.
rs = RandStream('mt19937ar', 'Seed', 12);
n = 6000; C = 4;
Z = randn(rs, n, 49);
y = 1 + mod(floor(2 * Z(:, 1) + Z(:, 2) .* Z(:, 3) + randn(rs, n, 1)), C);
pc = softmax_rows(randn(rs, n, C));
H = fuse_head('fit', pc, Z, y, 1:C, 1:49, 9400);
n0 = maxNumCompThreads(1); back = onCleanup(@() maxNumCompThreads(n0));
x = zeros(1, 2020);
for i = 1:2020
    q = mod(i - 1, n) + 1;
    t0 = tic; fuse_head('apply', H, pc(q, :), Z(q, :)); x(i) = 1000 * toc(t0);
end
x = sort(x(21:end));
verifyLessThanOrEqual(tc, x(ceil(0.95 * numel(x))), 1.0);
end

%% ---------- fuse_classes ----------
function test_fuse_classes_off_parent(tc)
% Without FM.gcc and FM.head the rows, the fit and the fusion read as the parent commit's, bit
% for bit.
X = tc.TestData.X; S = X.fit;
P = softmax_rows(randn(RandStream('mt19937ar', 'Seed', 4), numel(S.run), X.C));
Zc = fuse_classes('windows', S, P, X.N, X.PK.cues);
Xc = fuse_classes('extra', S, X.N, X.PK.cues);
Fc = fuse_classes('fit', Zc, X.yt, X.C, 1e-3);
[pc, kc] = fuse_classes('apply', Fc, Zc);
d = parent_copy(tc, 'code/detection/fuse_classes.m', tc.TestData.base);
addpath(d, '-begin'); clear fuse_classes
c0 = onCleanup(@() fixture_off(d, 'fuse_classes')); %#ok<NASGU>
verifyEqual(tc, which('fuse_classes'), fullfile(d, 'fuse_classes.m'));
Zp = fuse_classes('windows', S, P, X.N, X.PK.cues);
Xp = fuse_classes('extra', S, X.N, X.PK.cues);
Fp = fuse_classes('fit', Zp, X.yt, X.C, 1e-3);
[pp, kp] = fuse_classes('apply', Fp, Zp);
fixture_off(d, 'fuse_classes');
verifyTrue(tc, isequaln(Zc, Zp)); verifyTrue(tc, isequaln(Xc, Xp)); verifyTrue(tc, isequaln(Fc, Fp));
verifyTrue(tc, isequaln(pc, pp)); verifyTrue(tc, isequaln(kc, kp));
verifyEqual(tc, fieldnames(Fc)', {'W', 'mu', 'sd', 'C', 'lambda'});
end

function test_fuse_classes_gcc(tc)
% The gated columns: the six coherence columns times 1[gl_db >= 3 dB], appended by apply.
X = tc.TestData.X; Z = [X.Z0, X.XB];
g = fuse_classes('gcc', X.C, X.PK.cues);
n = fuse_classes('names', X.C, X.PK.cues);
verifyEqual(tc, n(g.cols), {'coh_contrast', 'los_contrast', 'los_k', 'coh_weak', 'k_contrast', 'ps_k_contrast'});
verifyEqual(tc, n{g.gate}, 'gl_db');
G = fuse_classes('gcc_x', Z, g);
verifyEqual(tc, G, double(Z(:, g.gate) >= 3) .* Z(:, g.cols));
verifyTrue(tc, any(Z(:, g.gate) >= 3) && any(Z(:, g.gate) < 3));
FM = fuse_classes('fit', [Z, G], X.yt, X.C, 1e-3);
Fg = FM; Fg.gcc = g;
verifyTrue(tc, isequal(fuse_classes('apply', Fg, Z), fuse_classes('apply', FM, [Z, G])));
verifyError(tc, @() fuse_classes('gcc', X.C, struct('iso', true)), 'fuse_classes:gcc');
end

function test_fuse_classes_head_inside_apply(tc)
% With FM.head the fusion's own probabilities go through the head (fuse_head 'apply').
X = tc.TestData.X; Z = [X.Z0, X.XB];
FM = fuse_classes('fit', Z, X.yt, X.C, 1e-3);
p0 = fuse_classes('apply', FM, Z);
H = fuse_head('fit', p0, Z, X.yt, fuse_head('classes', X.classes), fuse_head('cols', X.C, X.PK.cues), 9400);
Fh = FM; Fh.head = H;
[p1, k1] = fuse_classes('apply', Fh, Z);
verifyTrue(tc, isequal(p1, fuse_head('apply', H, p0, Z)));
[~, k0] = max(p1, [], 2); verifyTrue(tc, isequal(k1, k0));
end

%% ---------- the rules ----------
function test_rule_s(tc)
% Rule S: each condition alone fails it.
d = pass_d();
t = struct('median_ms', 0.3, 'p95_ms', 0.6, 'det_median_ms', 2.9, 'det_p95_ms', 4.4);
[ok, s] = fusion_adopt('head', d, t); verifyTrue(tc, ok); verifyEqual(tc, fieldnames(s)', {'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7'});
verifyTrue(tc, fusion_adopt('head', d, []));
is = find(strcmp(d.classes, 'airframe_shadowing')); ia = find(strcmp(d.classes, 'antenna_fault'));
bad = {@(e) setf(e, 'shad', [0.9 0.2 1.5]), @(e) setf(e, 'shad', [1.5 0 2]), @(e) setf(e, 'all', [0.3 0 0.5]), ...
    @(e) setf(e, 'above', [0.3 -0.1 0.5]), @(e) setcls(e, ia, [-0.6 -1 0.2]), @(e) setcls(e, ia, [-0.2 -1 -0.01]), ...
    @(e) setf(e, 'fault_low', [-1.2 -3 1]), @(e) setf(e, 'shad_low', [-0.5 -2 -0.1]), @(e) setf(e, 'cl', [0.06 -0.1 0.2]), ...
    @(e) setf(e, 'lb', [0 0.01 0.1]), @(e) setf(e, 'set_shad', [1 1 -0.1 1])};
for i = 1:numel(bad), verifyFalse(tc, fusion_adopt('head', bad{i}(d), t), sprintf('case %d', i)); end
e = d; e.cls(is, :) = [-3 -4 -2]; verifyTrue(tc, fusion_adopt('head', e, t));   % S3 is every other class
for tt = {setf(t, 'p95_ms', 1.01), setf(t, 'det_median_ms', 4.8), setf(t, 'det_p95_ms', 9.5), setf(t, 'det_p95_ms', NaN)}
    verifyFalse(tc, fusion_adopt('head', d, tt{1}));
end
end

function test_rule_w(tc)
% Rule W for the idle columns; the d91 rule for a comparison without per-class F1 is unchanged.
d = pass_d(); d.exc = [0.9 1.0];
[ok, s] = fusion_adopt('cfar', d); verifyTrue(tc, ok); verifyEqual(tc, fieldnames(s)', {'W1', 'W2', 'W3', 'W4', 'W5'});
ib = find(strcmp(d.classes, 'benign_interference')); is = find(strcmp(d.classes, 'airframe_shadowing'));
bad = {@(e) setcls(e, ib, [0.4 0.1 0.8]), @(e) setcls(e, ib, [0.6 0 1]), @(e) setf(e, 'above', [0 -0.11 0.2]), ...
    @(e) setf(e, 'all', [0.2 0 0.4]), @(e) setcls(e, is, [-0.6 -1 0.1]), @(e) setf(e, 'cl', [0 0.01 0.1]), ...
    @(e) setf(e, 'cb', [0 0.01 0.1]), @(e) setf(e, 'exc', [1.01 0.5]), @(e) rmfield(e, 'exc'), @(e) setf(e, 'set_benign', [0 -0.01 1 1])};
for i = 1:numel(bad), verifyFalse(tc, fusion_adopt('cfar', bad{i}(d)), sprintf('case %d', i)); end
z = [0 -1 1];
c = struct('all', [0.2 0.05 0.4], 'above', [0 -0.05 0.1], 'cl', z);
verifyTrue(tc, fusion_adopt('cfar', c));
c.above = [0 -0.2 0.1]; verifyFalse(tc, fusion_adopt('cfar', c));
end

function test_rule_cand_pick_nested(tc)
% The rules per candidate, step 1's pick and the nested reading's rule.
d = pass_d(); d.exc = [0.5 0.5];
t = struct('median_ms', 0.3, 'p95_ms', 0.6, 'det_median_ms', 2.9, 'det_p95_ms', 4.4);
tb = setf(t, 'p95_ms', 2);
verifyTrue(tc, fusion_adopt('cand', 'GCC', d, tb));                    % no head: S7 does not apply
verifyFalse(tc, fusion_adopt('cand', 'LBH', d, tb));
verifyFalse(tc, fusion_adopt('cand', 'LBH+CFAR', d, tb));
e = rmfield(d, 'exc');
verifyTrue(tc, fusion_adopt('cand', 'LBH', e, t)); verifyFalse(tc, fusion_adopt('cand', 'GCC+CFAR', e, t));
ib = find(strcmp(d.classes, 'benign_interference'));
w = d; w.shad = [0.2 -0.1 0.5]; verifyTrue(tc, fusion_adopt('cand', 'CFAR', w)); verifyFalse(tc, fusion_adopt('cand', 'GCC', w));
verifyError(tc, @() fusion_adopt('cand', 'XYZ', d), 'fusion_adopt:cand');
names = {'LBH', 'GCC', 'CFAR'};
G = {d, setf(d, 'all', [0.9 0.5 1.2]), setf(d, 'all', [2 1 3])}; G{3}.cls(ib, :) = [0.1 -0.1 0.3];   % CFAR fails W1
[k, ok] = fusion_adopt('pick', names, G, t); verifyEqual(tc, k, 2); verifyEqual(tc, ok, [true true false]);
verifyEqual(tc, fusion_adopt('pick', names, {w, w, G{3}}, t), 0);
verifyFalse(tc, fusion_adopt('nested', {'', '', '', '', ''}, d, t));    % B everywhere: nothing passes
verifyTrue(tc, fusion_adopt('nested', {'GCC', '', 'GCC', '', ''}, d, t));
verifyFalse(tc, fusion_adopt('nested', {'GCC', '', 'CFAR', '', ''}, e, t));   % W needs the exceedance
verifyFalse(tc, fusion_adopt('nested', {'LBH', '', '', '', ''}, d, tb));
verifyTrue(tc, fusion_adopt('nested', {'', 'CFAR', '', '', ''}, w, t));
end

function test_paired_cls(tc)
% The per-class F1, the clean frames read as benign and the per-set shadowing and benign gains
% read their own sums; the fields of 'paired' are unchanged.
cls = {'none', 'antenna_fault', 'airframe_shadowing', 'benign_interference'};
yt = [1 1 1 2 2 3 3 4 4 1 3 4]'; ya = [1 4 1 2 1 3 1 4 1 1 3 4]'; yb = [1 1 4 2 2 3 3 4 4 1 1 4]';
run = [1 1 2 2 3 3 4 4 5 5 6 6]'; st = [1 1 1 2 2 2 3 3 3 4 4 4]';
B = fusion_adopt('boot', run, 40, 5);
ab = true(12, 1); lo = false(12, 1); lo(1:4) = true;
d0 = fusion_adopt('paired', yt, ya, yb, ab, lo, cls, B);
d = fusion_adopt('paired_cls', yt, ya, yb, ab, lo, st, cls, B);
for f = fieldnames(d0)', verifyEqual(tc, d.(f{1}), d0.(f{1}), f{1}); end
f1 = @(y, c, m) 2 * sum(y(m) == c & yt(m) == c) / max(sum(y(m) == c) + sum(yt(m) == c), eps);
al = true(12, 1);
for c = 1:4, verifyEqual(tc, d.cls(c, 1), 100 * (f1(yb, c, al) - f1(ya, c, al)), 'AbsTol', 1e-9); end
verifyEqual(tc, d.cls(3, :), d.shad, 'AbsTol', 1e-9);
verifyEqual(tc, d.cb(1), 100 * (sum(yb == 4 & yt == 1) - sum(ya == 4 & yt == 1)) / sum(yt == 1), 'AbsTol', 1e-9);
for k = 1:4
    m = st == k;
    verifyEqual(tc, d.set_shad(k), 100 * (f1(yb, 3, m) - f1(ya, 3, m)), 'AbsTol', 1e-9);
    verifyEqual(tc, d.set_benign(k), 100 * (f1(yb, 4, m) - f1(ya, 4, m)), 'AbsTol', 1e-9);
end
verifyTrue(tc, all(d.cls(:, 2) <= d.cls(:, 3)));
end

function test_fusion_adopt_off_parent(tc)
% The commands of before ('boot', 'paired', 'cfar' on a comparison without per-class F1,
% 'branch', 'choose', 'combo') read as the parent commit's, bit for bit.
rs = RandStream('mt19937ar', 'Seed', 21);
cls = {'none', 'jamming', 'antenna_fault', 'benign_interference', 'airframe_shadowing'};
n = 400; run = repelem((1:40)', 10); yt = randi(rs, 5, n, 1);
ya = yt; f = rand(rs, n, 1) < 0.3; ya(f) = randi(rs, 5, sum(f), 1);
yb = yt; g = rand(rs, n, 1) < 0.25; yb(g) = randi(rs, 5, sum(g), 1);
yc = yt; h = rand(rs, n, 1) < 0.2; yc(h) = randi(rs, 5, sum(h), 1);
above = rand(rs, n, 1) < 0.7; low = repelem(rand(rs, 40, 1) < 0.3, 10);
run_all = @() adopt_calls(run, yt, ya, yb, yc, above, low, cls);
a = run_all();
d = parent_copy(tc, 'code/detection/fusion_adopt.m', tc.TestData.base);
addpath(d, '-begin'); clear fusion_adopt
c0 = onCleanup(@() fixture_off(d, 'fusion_adopt')); %#ok<NASGU>
verifyEqual(tc, which('fusion_adopt'), fullfile(d, 'fusion_adopt.m'));
b = run_all();
fixture_off(d, 'fusion_adopt');
verifyTrue(tc, isequaln(a, b));
end

%% ---------- the candidates ----------
function test_cfar_columns_fast(tc)
% fusion_cand's idle columns equal window_cues.m's (fuse_classes 'extra'); its thresholds the
% nearest-rank 99% of the clean gaps of the rows given.
X = tc.TestData.X; D = data_of(X, X.yt, '');
tr = X.fold ~= 2;
T = fusion_cand('thr', D, tr);
nm = idle_summary('names'); I = X.fit.idle; col = @(s) I(:, strcmp(nm, s));
ok = tr & isnan(X.fit.level) & col('gap_ms') > 0 & ~isnan(col('occ'));
c = sort(I(ok, strcmp(nm, 'max')) - I(ok, strcmp(nm, 'p10'))); s = sort(I(ok, strcmp(nm, 'p90')) - I(ok, strcmp(nm, 'p10')));
verifyEqual(tc, T, [c(ceil(0.99 * numel(c))), s(ceil(0.99 * numel(s))), median(c)]);
verifyEqual(tc, fusion_cand('cfar', D, T), fuse_classes('extra', X.fit, X.N, struct('cfar', T)), 'AbsTol', 1e-12);
[n1, n2, n] = fusion_cand('exc', D, 2, 2);
m = X.fold == 2 & isnan(X.fit.level) & col('gap_ms') > 0 & ~isnan(col('occ'));
verifyEqual(tc, [n1 n2 n], [sum(col('max') - col('p10') > T(1) & m), sum(col('p90') - col('p10') > T(2) & m), sum(m)]);
end

function test_candidates_match_direct_fits(tc)
% A reading is the fit on the other folds: B's equals select_fusion.m's out-of-fold columns;
% the head's level-0 inputs come from fits without the read fold.
X = tc.TestData.X; D = data_of(X, X.yt, '');
Z = [X.Z0, X.XB]; te = X.fold == 1; tr = ~te;
FM = fuse_classes('fit', Z(tr, :), X.yt(tr), X.C, 1e-3);
P = fusion_cand('pred', D, 'B', 1);
verifyTrue(tc, isequal(P, fuse_classes('apply', FM, Z(te, :))));
po = nan(size(Z, 1), X.C);
for j = 2:5
    m = ~ismember(X.fold, [1 j]);
    po(X.fold == j, :) = fuse_classes('apply', fuse_classes('fit', Z(m, :), X.yt(m), X.C, 1e-3), Z(X.fold == j, :));
end
L = fuse_head('classes', X.classes);
H = fuse_head('fit', po(tr, :), Z(tr, :), X.yt(tr), L, fuse_head('cols', X.C, X.PK.cues), fuse_head('seed', 'LBH', 1));
verifyTrue(tc, isequal(fusion_cand('pred', D, 'LBH', 1), fuse_head('apply', H, fuse_classes('apply', FM, Z(te, :)), Z(te, :))));
verifyTrue(tc, isequal(fusion_cand('head', D, 'LBH', 1), H));
pc = fusion_cand('oof', D, 'B', [1 3], []);
verifyTrue(tc, isequal(pc(te, :), P)); verifyTrue(tc, all(isnan(pc(X.fold == 2, :)), 'all'));
q = fusion_cand('oof', D, 'B', 2, 1);                    % inside outer fold 1: fold 2 read by the fit without folds 1 and 2
m = ~ismember(X.fold, [1 2]);
verifyTrue(tc, isequal(q(X.fold == 2, :), fuse_classes('apply', fuse_classes('fit', Z(m, :), X.yt(m), X.C, 1e-3), Z(X.fold == 2, :))));
end

function test_candidates_no_leak(tc)
% Nothing fitted on a read fold: its targets changed, its reading of every candidate is the
% same, on the whole fit set and inside an outer fold.
X = tc.TestData.X;
y2 = X.yt; m1 = X.fold == 1; y2(m1) = 1;
y3 = X.yt; m12 = ismember(X.fold, [1 2]); y3(m12) = 2;
D = data_of(X, X.yt, ''); D2 = data_of(X, y2, ''); D3 = data_of(X, y3, '');
for c = [{'B'}, fusion_cand('names')]
    p = fusion_cand('oof', D, c{1}, 1, []); p2 = fusion_cand('oof', D2, c{1}, 1, []);
    verifyTrue(tc, isequal(p(m1, :), p2(m1, :)), c{1});
    q = fusion_cand('oof', D, c{1}, 2, 1); q3 = fusion_cand('oof', D3, c{1}, 2, 1);
    verifyTrue(tc, isequal(q(X.fold == 2, :), q3(X.fold == 2, :)), c{1});
end
X4 = X; I = X4.fit.idle; nm = idle_summary('names');
I(m1, strcmp(nm, 'max')) = I(m1, strcmp(nm, 'max')) + 50; X4.fit.idle = I;
verifyEqual(tc, fusion_cand('thr', data_of(X4, X.yt, ''), ~m1), fusion_cand('thr', D, ~m1));
end

function test_candidates_checkpoint(tc)
% The fits' outputs are kept in the folder given and read back the same.
X = tc.TestData.X; ck = fullfile(tc.TestData.tmp, 'ck_cand');
D = data_of(X, X.yt, ck);
p = fusion_cand('pred', D, 'CFAR', [2 4]);
verifyTrue(tc, isfile(fullfile(ck, 'l0_CFAR_m10.mat')) && isfile(fullfile(ck, 'T_m10.mat')));
D2 = data_of(X, X.yt, ck);
verifyTrue(tc, isequal(fusion_cand('pred', D2, 'CFAR', [4 2]), p));
M = fusion_cand('fit', D, 'LBH+CFAR');
verifyTrue(tc, isfield(M.FM, 'head') && ~isfield(M.FM, 'gcc') && numel(M.T) == 3 && isequal(M.cues.cfar, M.T));
M = fusion_cand('fit', D, 'GCC');
verifyTrue(tc, isfield(M.FM, 'gcc') && ~isfield(M.FM, 'head') && isempty(M.cues.cfar));
end

function test_recheck_and_cost(tc)
% B2F's re-check: the rule against B on the same folds; a failed rule deploys B (the
% fallback); in the smoke the candidate deploys all the same with its cost printed.
X = tc.TestData.X; D = data_of(X, X.yt, '');
pB = fusion_cand('oof', D, 'B', 1:5, []);
B = fusion_adopt('boot', X.fit.run, 50, 1);
low = X.fit.k_db <= 0;
[~, R] = evalc('fusion_recheck(fusion_pick(''GCC''), X.fit, X.Z0, X.XB, X.yt, X.fold, X.C, 1e-3, X.N, X.classes, B, X.fit.ebno, low, pB, [], false)');
verifyEqual(tc, R.pick, 'GCC'); verifyEqual(tc, R.adopted, R.ok); verifyEqual(tc, R.fallback, ~R.ok);
verifyEqual(tc, size(R.d.cls), [X.C 3]);
verifyEqual(tc, isempty(R.FM), ~R.adopted);
ST = stages(1);
[txt, R] = evalc('fusion_recheck(fusion_pick(''LBH''), X.fit, X.Z0, X.XB, X.yt, X.fold, X.C, 1e-3, X.N, X.classes, B, X.fit.ebno, low, pB, ST, true)');
verifyTrue(tc, R.adopted && isfield(R.FM, 'head') && ~R.rules.S7);   % no detector cost here: S7 fails, the smoke deploys
verifyEqual(tc, R.det.source, 'results/ood_detection.mat missing');
verifyTrue(tc, R.cost.ok && R.timing.p95_ms > 0);
verifySubstring(tc, txt, 'SMOKE (FUSION_RULE_LOG)');
verifyEqual(tc, size(R.pv), [numel(X.yt) X.C]);
[~, C1] = evalc('head_cost(R.FM, [X.Z0(1:50, :), X.XB(1:50, :)], stages(1e15), 50)');
verifyTrue(tc, C1.delta_ms > 0); verifyFalse(tc, C1.ok);
verifyError(tc, @() head_cost(R.FM, [X.Z0, X.XB], ST(1:5), 5), 'head_cost:stages');
verifyError(tc, @() head_cost(rmfield(R.FM, 'head'), [X.Z0, X.XB], ST, 5), 'head_cost:head');
end

function test_det_cost(tc)
% The detector's cost for S7: the production score's on its device; NaN without it.
d = fullfile(tc.TestData.tmp, 'dc'); mkdir(d); f = fullfile(d, 'ood_detection.mat');
c = det_cost(f); verifyTrue(tc, isnan(c.median_ms) && isnan(c.p95_ms)); verifySubstring(tc, c.source, 'missing');
LC = struct('cand', {{'maha', 'energy'}}, 'med', [1.2 2.5], 'p95', [2.0 4.1], 'dev', {{'cpu', 'gpu'}}); sel = 'energy';
save(f, 'LC', 'sel');
c = det_cost(f); verifyEqual(tc, [c.median_ms c.p95_ms], [2.5 4.1]); verifySubstring(tc, c.source, 'energy on GPU');
sel = 'knn'; save(f, 'LC', 'sel'); %#ok<NASGU>
c = det_cost(f); verifyTrue(tc, isnan(c.median_ms) && isnan(c.p95_ms));
end

%% ---------- the switches ----------
function test_pick_and_rev_id(tc)
% Off: the d91 pick and its revision id as the parent commit's. On: the candidate named, the id
% carries it; B2F's code builds the record and the id as registered.
P = fusion_pick('');
verifyFalse(tc, isfield(P, 'ext'));
verifyEqual(tc, fieldnames(P)', {'name', 'cues', 'N', 'lambda', 'target_age', 'latch', 'source'});
verifyEqual(tc, fusion_rev_id('enlarged', P), 'd91_branch_evidence_enlarged');
verifyEqual(tc, fusion_rev_id('validation', struct()), 'd91_branch_evidence_validation');
verifyEqual(tc, fusion_rev_id('enlarged'), fusion_rev_id('enlarged', fusion_pick()));
d = parent_copy(tc, 'code/detection/fusion_pick.m', tc.TestData.base);
dp = load_parent_pick(d);
verifyTrue(tc, isequal(dp, P));
Q = fusion_pick('LBH+CFAR');
verifyEqual(tc, Q.ext.pick, 'LBH+CFAR'); verifyTrue(tc, isequal(rmfield(Q, 'ext'), P));
verifyEqual(tc, fusion_rev_id('enlarged', Q), 'd91_branch_evidence_enlarged_lbh_cfar');
verifyError(tc, @() fusion_pick('XYZ'), 'fusion_pick:ext');
ed = fileread(which('eval_detector'));
for t = {'isequal(rmfield(Fp.deployed_pick, ''check''), fusion_pick())', 'strcmp(Fz.fusion_rev, fusion_rev_id(''enlarged''))', ...
        'd91 alone, descriptive, never the KPI 1 value', 'if ismember(''base_fm'', {whos(''-file'', ''data/fusion.mat'').name})', ...
        'if ~isempty(base_alone), metrics.base_alone = base_alone; end', '''%.2f%%; F1 above it %s\n''']
    verifyNotEmpty(tc, strfind(ed, t{1}), t{1});
end
sf = fileread(which('select_fusion'));
sf = sf(strfind(sf, 'close all; clc;'):end);              % the script's body, after its header
k = cellfun(@(t) min([strfind(sf, t), Inf]), {'''select_fusion:pick_measured''', 'FUSION_EXT_FORCE', '''select_fusion:head_stages''', ...
    'S = load(''data/splits.mat'');', 'RX = fusion_recheck(', 'Zf = [Zf, XP]; clear XP', 'base_fm = FM;', ...
    'PKr = struct(); if ~isempty(PK), PKr = PK; end', 'fusion_rev = fusion_rev_id(fit_name, PKr);', ...
    'deployed_pick.check.ext = rmfield(RX, {''FM'', ''pv''});', 'save(fz_tmp, ''base_fm'', ''-append'');'});
verifyTrue(tc, all(isfinite(k)) && issorted(k));
verifyNotEmpty(tc, strfind(sf, 'if RULE_LOG && exist(''FUSION_EXT_FORCE'', ''var'')'));   % the smoke only
verifyNotEmpty(tc, strfind(sf, 'if isfield(PK, ''ext'')'));                              % the re-check only with a candidate
verifyNotEmpty(tc, strfind(sf, 'if ~isempty(PK) && isfield(PK, ''ext'')'));              % base_fm only with a candidate
end

function test_b3r_guards_accept_the_pick(tc)
% With fusion_pick.m naming a candidate, the record B2F builds (adopted or fallen back) passes
% B3r's fresh3_pick and fresh3_fusion_rev in their form, which is the parent commit's; so does
% select_fusion's pick_measured.
src = fileread(which('fusion_pick'));
verifyNumElements(tc, strfind(src, 'EXT = '''';'), 1);
d = tempname; mkdir(d);
c0 = onCleanup(@() fixture_off(d, 'fusion_pick')); %#ok<NASGU>
fid = fopen(fullfile(d, 'fusion_pick.m'), 'w'); fwrite(fid, strrep(src, 'EXT = '''';', 'EXT = ''GCC'';')); fclose(fid);
addpath(d, '-begin'); clear fusion_pick
verifyEqual(tc, fusion_pick().ext.pick, 'GCC');
PK = fusion_pick();
for adopted = [true false]
    dp = PK; dp.check = struct('all', [0 0 0]); dp.check.ext = struct('pick', 'GCC', 'adopted', adopted, 'fallback', ~adopted);
    fz = fusion_rev_id('enlarged', PK);                    % select_fusion.m: fusion_rev_id(fit_name, PKr)
    verifyTrue(tc, isequal(rmfield(dp, 'check'), fusion_pick()));          % fresh3_pick
    verifyTrue(tc, ischar(fz) && strcmp(fz, fusion_rev_id('enlarged')));    % fresh3_fusion_rev
    verifyTrue(tc, isequal(PK, fusion_pick()));                             % select_fusion:pick_measured
end
verifyEqual(tc, fusion_rev_id('enlarged'), 'd91_branch_evidence_enlarged_gcc');
fixture_off(d, 'fusion_pick');
p = parent_copy(tc, 'code/detection/eval_detector.m', tc.TestData.base);
a = strrep(fileread(fullfile(p, 'eval_detector.m')), sprintf('\r'), '');
b = strrep(fileread(which('eval_detector')), sprintf('\r'), '');
g = @(s) s(min(strfind(s, 'if fusion_nogo(''check'')')):min(strfind(s, 'Dt = load(''data/trained_detector.mat'', ''trained_at'');')));
verifyEqual(tc, g(b), g(a));
q = parent_copy(tc, 'code/detection/select_fusion.m', tc.TestData.base);
a = strrep(fileread(fullfile(q, 'select_fusion.m')), sprintf('\r'), '');
b = strrep(fileread(which('select_fusion')), sprintf('\r'), '');
g = @(s) s(min(strfind(s, 'assert(~ENL || isequal(PK, fusion_pick())')):min(strfind(s, 'SMK = exist(''SMOKE''')));
verifyEqual(tc, g(b), g(a));
end

function test_detector_id_head(tc)
% A head changes the detector's identity; the same head refitted keeps it.
X = tc.TestData.X; Z = [X.Z0, X.XB];
FM = fuse_classes('fit', Z, X.yt, X.C, 1e-3);
FZ = struct('FM', FM, 'N', X.N, 'q_thr', 5.5); ood = struct('score', 'last', 'win', 1);
id0 = detector_id(1, ood, FZ);
L = fuse_head('classes', X.classes); cols = fuse_head('cols', X.C, X.PK.cues);
pc = fuse_classes('apply', FM, Z);
F1 = FZ; F1.FM.head = fuse_head('fit', pc, Z, X.yt, L, cols, 9400);
F2 = FZ; F2.FM.head = fuse_head('fit', pc, Z, X.yt, L, cols, 9400);
verifyNotEqual(tc, detector_id(1, ood, F1), id0);
verifyEqual(tc, detector_id(1, ood, F2), detector_id(1, ood, F1));
F3 = FZ; F3.FM.gcc = fuse_classes('gcc', X.C, X.PK.cues);
verifyNotEqual(tc, detector_id(1, ood, F3), id0);
end

function test_boot_cluster_groups(tc)
% Without groups the interval is the parent commit's, bit for bit; with two groups, the second's
% ratio less the first's, clusters resampled within each.
rs = RandStream('mt19937ar', 'Seed', 3);
num = randi(rs, 20, 1, 60); den = 20 * ones(1, 60); cl = 1:60; g = double((1:60) > 25);
[m, lo, hi, v] = boot_cluster(num, den, cl, 500, 4);
[m1, lo1, hi1, v1] = boot_cluster(num, den, cl, 500, 4, []);
d = parent_copy(tc, 'code/evaluation/boot_cluster.m', tc.TestData.base);
addpath(d, '-begin'); clear boot_cluster
c0 = onCleanup(@() fixture_off(d, 'boot_cluster')); %#ok<NASGU>
verifyEqual(tc, which('boot_cluster'), fullfile(d, 'boot_cluster.m'));
[m0, lo0, hi0, v0] = boot_cluster(num, den, cl, 500, 4);
fixture_off(d, 'boot_cluster');
verifyTrue(tc, isequaln([m lo hi v], [m0 lo0 hi0 v0]));
verifyTrue(tc, isequaln([m1 lo1 hi1 v1], [m lo hi v]));
[dd, dl, dh] = boot_cluster(num, den, cl, 500, 4, g);
verifyEqual(tc, dd, sum(num(g == 1)) / sum(den(g == 1)) - sum(num(g == 0)) / sum(den(g == 0)), 'AbsTol', 1e-12);
verifyTrue(tc, dl <= dd && dd <= dh);
[d2, dl2] = boot_cluster(num, den, cl, 500, 4, g); verifyEqual(tc, [d2 dl2], [dd dl]);
verifyError(tc, @() boot_cluster(num, den, cl, 500, 4, mod(1:60, 3)), 'boot_cluster:groups');
end

function test_unseen_gap_switch(tc)
% The unseen-minus-grid lines print only with "unseen_gap": true in profile.json; no verdict words.
d = fullfile(tc.TestData.tmp, 'ug'); mkdir(d); c0 = cd(d); back = onCleanup(@() cd(c0));
verifyFalse(tc, unseen_gap_on());
w = @(s) writelines(s, 'profile.json');
w('{"profile": "p3"}'); verifyFalse(tc, unseen_gap_on());
w('{"unseen_gap": true}'); verifyTrue(tc, unseen_gap_on());
w('{"unseen_gap": false}'); verifyFalse(tc, unseen_gap_on());
w('{"unseen_gap": 1}'); verifyError(tc, @() unseen_gap_on(), 'unseen_gap_on:value');
src = fileread(which('eval_unseen_snr'));
i0 = strfind(src, 'if unseen_gap_on()'); verifyNumElements(tc, i0, 1);
seg = src(i0:min(numel(src), i0 + 1400));
verifyNotEmpty(tc, strfind(seg, 'boot_cluster([b.correct], [b.n], 1:numel(b), 2000, 4251, double(un))'));
verifyNotEmpty(tc, strfind(seg, '{''antenna_fault'', ''airframe_shadowing''}'));
verifyEmpty(tc, regexp(seg, 'ANSWERED|OPEN|UNDETERMINED|COMMITTED|MET', 'once'));
verifyNotEmpty(tc, strfind(src, 'if ~isempty(gap_lb), save(''results/unseen_snr.mat'', ''gap_lb'', ''-append''); end'));
end

%% ---------- the measurement ----------
function test_m_head_guard_and_candidates(tc)
% LBH and LBH+CFAR are struck without the recorded yes; the inputs are checked before any load:
% no path or file of the fourth test set, the recorded extracts only; no row of the fourth set;
% a passed timebox refuses the run; the verdict line comes before any reading.
verifyEqual(tc, m_head('candidates', struct()), {'GCC', 'CFAR', 'GCC+CFAR'});
verifyEqual(tc, m_head('candidates', struct('lbh', 'approved by Adi on 31.10.2026 09:00')), fusion_cand('names'));
verifyError(tc, @() m_head('candidates', struct('lbh', 'yes')), 'm_head:lbh');
d = fullfile(tc.TestData.tmp, 'mh'); mkdir(d); o = fullfile(tc.TestData.tmp, 'mh_out');
verifyError(tc, @() m_head(d, o, struct('stop_at', datetime('now') - hours(1))), 'm_head:timebox');
verifyFalse(tc, isfolder(o));
verifyError(tc, @() m_head('guard', d, o), 'm_head:input');
x = 1; save(fullfile(d, 'sets.mat'), 'x'); save(fullfile(d, 'ck_p3.mat'), 'x');
verifyError(tc, @() m_head('guard', d, o), 'm_head:input');                 % not the recorded extracts
save(fullfile(d, 'splits_fresh3.mat'), 'x');
verifyError(tc, @() m_head('guard', d, o), 'm_head:set4');
verifyError(tc, @() m_head('guard', fullfile(tc.TestData.tmp, 'set4_out'), o), 'm_head:set4');
mk = @(sd) struct('run', (1:3)', 'draws', struct('seed', sd(:)));
S = struct('val', mk(3000001:3000003), 'test', mk(3000004:3000006), 'fresh', mk(3500001:3500003), 'fresh2', mk(6500001:6500003));
verifyTrue(tc, m_head('set4', S));
S4 = S; S4.fresh.draws.seed(2) = 6000002; verifyError(tc, @() m_head('set4', S4), 'm_head:set4');
S5 = S; S5.fresh3 = S.val; verifyError(tc, @() m_head('set4', S5), 'm_head:set4');
S6 = S; S6.test = rmfield(S6.test, 'draws'); verifyError(tc, @() m_head('set4', S6), 'm_head:set4');
src = fileread(which('m_head'));
r = regexp(src, 'RULE_SHA = ''([0-9a-f]*)'';', 'tokens', 'once');
verifyEqual(tc, r{1}, lf_sha(fullfile(tc.TestData.root, 'code', 'detection', 'fusion_adopt.m')));   % the committed rule
for t = {'maxNumCompThreads(1);', 'guard(data_dir, out_dir, SETS_SHA, CK_SHA);', 'sd >= 6000000 & sd < 6100000', ...
        'RandStream(''mt19937ar'', ''Seed'', 9101)', 'fusion_adopt(''boot'', fit.run, 1000, 9102)', ...
        'fusion_adopt(''boot'', fit.run(tr), 1000, 9160 + k)', 'REG_COMMIT = ''b6628caa64e681e7f9714a30cdbbe8185079620d'';'}
    verifyNotEmpty(tc, strfind(src, t{1}), t{1});
end
g = strfind(src, 'guard(data_dir, out_dir, SETS_SHA, CK_SHA);'); l = strfind(src, 'L = load(fullfile(data_dir, ''sets.mat''));');
s4 = strfind(src, 'set4(S);'); z = strfind(src, 'Z0 = fuse_classes(''windows''');
verifyTrue(tc, isscalar(g) && isscalar(l) && isscalar(s4) && g < l && l < s4 && s4 < z);
v = min(strfind(src, 'VERDICT p3')); qk = strfind(src, 'R = struct(''quick'', true');
p = [strfind(src, 'out(''\nOut of fold over'), strfind(src, 'gtxt(G{c})'), strfind(src, 'NESTED reading against B'), ...
    strfind(src, 'save(fullfile(out_dir, sprintf(''m_head_%s.mat'', tag))')];
verifyTrue(tc, isscalar(qk) && qk < v && v < min(p) && v > max(strfind(src, 'nested outer fold %d done')));
end

%% ---------- helpers ----------
function X = synth(seed)
% Synthetic rows of the fusion's layout: 60 sub-runs of 10 cycles, one class each.
rs = RandStream('mt19937ar', 'Seed', seed);
classes = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
C = numel(classes); PK = fusion_pick(''); N = 4;
nT = numel(temporal_evidence('names', C)); nZ = nT + numel(window_cues('names')) + C;
en = window_cues('extra_names', PK.cues); nX = numel(en);
R = 60; Lr = 10; n = R * Lr;
run = repelem((1:R)', Lr); pos = repmat((1:Lr)', R, 1);
cyc = [1 5 7 11 8 2];
cr = cyc(mod((1:R)' - 1, numel(cyc)) + 1);
y = cr(run); y = y(:);
Z0 = randn(rs, n, nZ); XB = randn(rs, n, nX);
for c = unique(cyc)
    m = y == c;
    Z0(m, nT + mod(3 * c, 52) + 1) = Z0(m, nT + mod(3 * c, 52) + 1) + 2;
    XB(m, mod(c, nX) + 1) = XB(m, mod(c, nX) + 1) + 1.5;
end
ig = strcmp(en, 'gl_db'); XB(:, ig) = 5 * (rand(rs, n, 1) < 0.4 + 0.4 * ismember(y, [7 11]));
nm = idle_summary('names'); I = nan(n, numel(nm)); col = @(s) find(strcmp(nm, s));
I(:, col('gap_ms')) = 1 + rand(rs, n, 1); I(rand(rs, n, 1) < 0.1, col('gap_ms')) = 0;
I(:, col('occ')) = rand(rs, n, 1);
I(:, col('p10')) = -100 + rand(rs, n, 1);
I(:, col('max')) = I(:, col('p10')) + 3 * rand(rs, n, 1) + 6 * (y == 8);
I(:, col('p90')) = I(:, col('p10')) + 2 * rand(rs, n, 1) + 3 * (y == 8);
level = nan(n, 1); level(y ~= 1) = 1;
eb = [0 3 6]; ebr = eb(mod((1:R)', 3) + 1); kd = 8 * randn(rs, R, 1);
fit = struct('run', run, 'pos', pos, 'gain_ant', randn(rs, n, 4), 'feats_raw', randn(rs, n, numel(link_features('names'))), ...
    'feat_names', {link_features('names')}, 'idle', I, 'level', level, 'set', mod(run, 4) + 1, 'k_db', kd(run), ...
    'ebno', ebr(run)', 'ebno_rx', ebr(run)');
fit.ebno = fit.ebno(:); fit.ebno_rx = fit.ebno_rx(:);
X = struct('fit', fit, 'Z0', Z0, 'XB', XB, 'yt', y, 'fold', mod(run, 5) + 1, 'classes', {classes}, 'C', C, 'N', N, 'PK', PK);
end

function D = data_of(X, yt, ck)
D = fusion_cand('data', X.fit, X.Z0, X.XB, X.PK.cues, yt, X.fold, X.C, 1e-3, X.N, X.classes, ck);
end

function a = adopt_calls(run, yt, ya, yb, yc, above, low, cls)
% The commands of fusion_adopt.m before D110 on one set of readings.
B = fusion_adopt('boot', run, 200, 7);
d1 = fusion_adopt('paired', yt, ya, yb, above, low, cls, B);
d2 = fusion_adopt('paired', yt, ya, yc, above, low, cls, B);
d3 = fusion_adopt('paired', yt, yb, yc, above, low, cls, B);
G = {[], d1, d2, d3};
[pk, bs] = fusion_adopt('choose', G);
if isempty(bs), bs = 3; end
a = {B, d1, d2, d3, fusion_adopt('cfar', d1), fusion_adopt('cfar', d2), fusion_adopt('branch', d1), fusion_adopt('branch', d3), ...
    pk, bs, fusion_adopt('combo', G, bs, d2), fusion_adopt('combo', G, bs, d3)};
end

function P = load_parent_pick(d)
% The parent commit's fusion_pick() (no argument), read from its own copy.
addpath(d, '-begin'); clear fusion_pick
c0 = onCleanup(@() fixture_off(d, 'fusion_pick')); %#ok<NASGU>
P = fusion_pick();
end

function d = pass_d()
% A comparison that passes rules S and W.
cls = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', 'antenna_fault', ...
    'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
z = [0 -0.2 0.2];
d = struct('all', [0.4 0.1 0.7], 'above', [0.4 0.1 0.7], 'cl', [-0.1 -0.3 0.1], 'lb', [-0.1 -0.3 0.1], 'fault', z, ...
    'shad', [2 1 3], 'fault_low', [0 -1 1], 'shad_low', [0.5 -1 2], 'cls', repmat(z, numel(cls), 1), 'cb', [0 -0.1 0.1], ...
    'classes', {cls}, 'set_shad', [1 2 1 3], 'set_benign', [1 1 1 1]);
d.cls(11, :) = d.shad; d.cls(8, :) = [1 0.5 1.5];
end

function e = setf(e, f, v)
e.(f) = v;
end

function e = setcls(e, c, v)
e.cls(c, :) = v;
end

function ST = stages(rows)
s = {'C1d', 'C2', 'C2e', 'C2g', 'C2u', 'EDGE'};
ST = struct('stage', s, 'rows', num2cell(rows * ones(1, 6)), 'hours', num2cell([6 50 2 10 10 15]));
end

function P = softmax_rows(A)
A = A - max(A, [], 2); P = exp(A); P = P ./ sum(P, 2);
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy
% queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, ...
    fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end

function fixture_off(d, fn)
% Removes a parent-commit folder from the path and the disk (once).
if contains(path, d), rmpath(d); end
clear(fn);
if isfolder(d), rmdir(d, 's'); end
end

function h = lf_sha(f)
fid = fopen(f, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
b = b(b ~= 13);
md = java.security.MessageDigest.getInstance('SHA-256'); md.update(b);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
