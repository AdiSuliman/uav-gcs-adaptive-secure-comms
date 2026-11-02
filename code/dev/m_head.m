function R = m_head(data_dir, out_dir, opt)
%M_HEAD  The measurement of the fusion's candidates over the d91 pick (the base B) on profile 3's
%   enlarged fit set, by the rule committed in fusion_adopt.m (docs/DECISIONS.md):
%   1. out of fold by sub-run on the whole fit set, each candidate (fusion_cand.m) against B,
%      paired bootstrap over sub-runs (1000 resamples, seed 9102); of the candidates passing
%      their rules, the one with the largest macro-F1 gain over every frame, else B;
%   2. step 1 as a whole under nested cross-validation (Varma & Simon 2006), 5 outer folds:
%      inside each, everything is refitted on its training folds (the linear fusions, the
%      probabilities that feed a head, the KPI 1 threshold, T1, T2, m0), step 1 runs on the
%      inner out-of-fold readings, and its pick read on the held-out fold;
%   3. the nested reading against B: rule S if any outer fold picked a head or the gated
%      columns, rule W if any picked the idle columns. Step 1's pick is adopted only then.
%   Read-only copies of the d91 extracts, one thread. Nothing read from a result is printed
%   before the verdict line, which comes first; a run that reaches its timebox before the
%   verdict line, the readings included, prints none and voids its fits. Before loading, the
%   inputs must be the recorded extracts (SHA-256) and no path or file of the fourth test set
%   may be in reach; after loading and before any use, no row may come from it (sub-run seeds
%   6 000 000 + run id).
%   R = m_head(data_dir, out_dir, opt)
%   data_dir  copies of sets.mat and ck_p3.mat, checked by their SHA-256 before loading
%   out_dir   the log m_head_<tag>.txt, the result m_head_<tag>.mat and the fits (ck_<tag>/, a
%             run stopped by a guard resumes from them)
%   opt.lbh      '' (default): LBH and LBH+CFAR struck from the candidates (D110 point 8b); or
%                the record of Adi's yes, 'approved by Adi on <date, time>'
%   opt.det_file the deployed detector's eval_ood_detection.m output (det_cost.m), for S7
%   opt.det_ms   [median p95] ms per frame of the deployed detector with its score, in place of
%                opt.det_file
%   opt.stop_at  the timebox (datetime); NaT none. A run is refused once it has passed
%   opt.quick    true: every 20th sub-run, a check of the code path: no reading printed or
%                saved, never a verdict
%   list = m_head('candidates', opt)        the candidates measured under opt
%   m_head('guard', data_dir, out_dir)      the checks made before loading
%   m_head('set4', S)                       the check of every row of the loaded sets S
SETS_SHA = '75b7a9cd75b37364248bf35cf9aac50eca23f91cb8ff75442e9f03ee1cbf2c6b';
CK_SHA = '0ae49158fb9cf01368d7e4aa91405c54b032f17f3c1ebcbc2a935917f2d018b8';
REG_COMMIT = 'b6628caa64e681e7f9714a30cdbbe8185079620d';   % uav-gcs-v7-docs, the registration of the rule
RULE_SHA = '96cc3549e7a85efc9e428ffb8bb1bc42d98773a0b9060b09febcf77e4cc186c7';   % fusion_adopt.m, line ends LF
if ischar(data_dir) && strcmp(data_dir, 'candidates'), R = candidates(defaults(out_dir)); return; end
if ischar(data_dir) && strcmp(data_dir, 'guard'), guard(out_dir, opt, SETS_SHA, CK_SHA); R = true; return; end
if ischar(data_dir) && strcmp(data_dir, 'set4'), set4(out_dir); R = true; return; end
if nargin < 3, opt = struct(); end
opt = defaults(opt);
assert(isnat(opt.stop_at) || datetime('now') < opt.stop_at, 'm_head:timebox', ...
    'the timebox %s has passed: B deploys unchanged (D110 point 7)', char(opt.stop_at));
maxNumCompThreads(1);
guard(data_dir, out_dir, SETS_SHA, CK_SHA);
tag = 'p3'; if opt.quick, tag = 'p3_quick'; end
if ~isfolder(out_dir), mkdir(out_dir); end
fid = fopen(fullfile(out_dir, sprintf('m_head_%s.txt', tag)), 'a'); cl = onCleanup(@() fclose(fid));
out = @(varargin) both(fid, varargin{:});
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
code = @(f) fullfile(root, 'code', f);
sh = struct('rule', file_sha(code('detection/fusion_adopt.m'), true), 'cand', file_sha(code('detection/fusion_cand.m'), true), ...
    'head', file_sha(code('detection/fuse_head.m'), true), 'fuse', file_sha(code('detection/fuse_classes.m'), true), ...
    'cues', file_sha(code('detection/window_cues.m'), true), 'me', file_sha(code('dev/m_head.m'), true), ...
    'sets', SETS_SHA, 'ck', CK_SHA, 'quick', double(opt.quick));
[gs, gh] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if gs ~= 0, gh = 'not a git checkout'; end
C = candidates(opt);
out('\n===== fusion candidates over the d91 pick, %s, %s =====\n', tag, char(datetime('now')));
out('registration commit %s; code %s; one thread (%d)\n', REG_COMMIT, strtrim(gh), maxNumCompThreads);
out('SHA-256 (LF): rule fusion_adopt.m %s, fusion_cand.m %s, fuse_head.m %s, m_head.m %s\n', sh.rule, sh.cand, sh.head, sh.me);
assert(strcmp(sh.rule, RULE_SHA), 'm_head:rule', 'fusion_adopt.m (SHA-256 %s) is not the committed rule %s', sh.rule, RULE_SHA);
det = struct('median_ms', NaN, 'p95_ms', NaN, 'source', 'none: no head measured');
if isempty(opt.lbh)
    out('LBH and LBH+CFAR struck (D110 point 8b): no yes recorded before the measurement. Candidates %s\n', strjoin(C, ', '));
else
    if ~isempty(opt.det_file), det = det_cost(opt.det_file); end
    if numel(opt.det_ms) == 2 && all(isfinite(opt.det_ms))
        det = struct('median_ms', opt.det_ms(1), 'p95_ms', opt.det_ms(2), 'source', 'opt.det_ms');
    end
    assert(isfinite(det.median_ms) && isfinite(det.p95_ms), 'm_head:det_ms', ...
        'S7 needs the detector''s cost (opt.det_file or opt.det_ms): %s', det.source);
    out('LBH in (%s). Candidates %s; the detector for S7 %.2f / %.2f ms (%s)\n', opt.lbh, strjoin(C, ', '), det.median_ms, ...
        det.p95_ms, det.source);
end
if ~isnat(opt.stop_at), out('timebox %s\n', char(opt.stop_at)); end

%% The enlarged fit set (m_all.m's), after the set-4 check of every row
L = load(fullfile(data_dir, 'sets.mat')); S = L.S; classes = cellstr(string(L.info.classes)); F = L.F; clear L
set4(S);
names = {'val', 'test', 'fresh', 'fresh2'};
FLD = {'run', 'pos', 'gain_ant', 'feats_raw', 'idle', 'bch', 'level', 'ebno', 'ebno_rx', 'k_db', 'speed', 'P', 'y'};
for k = 1:4
    s = S.(names{k}); t = struct();
    for f = FLD, x = s.(f{1}); if isvector(x), x = x(:); end, t.(f{1}) = x; end
    t.run = double(t.run) + (k - 1) * 1e7; t.pos = double(t.pos); t.set = k * ones(numel(t.run), 1);
    if k == 1, fit = t; else, for f = fieldnames(fit)', fit.(f{1}) = [fit.(f{1}); t.(f{1})]; end, end
end
clear S
keep = true(numel(fit.run), 1);
if opt.quick
    u = unique(fit.run); keep = ismember(fit.run, u(1:20:end));
    for f = fieldnames(fit)', fit.(f{1}) = fit.(f{1})(keep, :); end
end
fit.feat_names = link_features('names');
PK = fusion_pick(); N = PK.N; lam = PK.lambda; Cn = numel(classes); K = 5; n = numel(fit.run);
assert(F.N == N && F.lambda == lam, 'm_head:pick', 'the extracts'' fusion (N %d, lambda %g) is not the pick''s', F.N, F.lambda);
t0 = tic;
Z0 = fuse_classes('windows', fit, double(fit.P), N);
W = load(fullfile(data_dir, 'ck_p3.mat'), 'Z');
out('%d frames, %d sub-runs; this code rebuilds the checkpoint''s windows: %d (%.1f min)\n', n, numel(unique(fit.run)), ...
    isequal(Z0, W.Z(keep, :)), toc(t0) / 60);
clear W
XB = fuse_classes('extra', fit, N, PK.cues);
yt = fusion_target(fit.y, fit.run, fit.pos, N, classes, struct('target_age', N));
ru = unique(fit.run); rf = RandStream('mt19937ar', 'Seed', 9101);
fr = mod(randperm(rf, numel(ru)), K) + 1; [~, ir] = ismember(fit.run, ru); fold = fr(ir)';
[bin, ~] = kpi_ebno(fit, yt, classes);
low = fit.k_db <= 0; st = fit.set;
ckd = fullfile(out_dir, ['ck_' tag]);
manifest(ckd, sh);
D = fusion_cand('data', fit, Z0, XB, PK.cues, yt, fold, Cn, lam, N, classes, ckd);
out('the base''s columns and the fits'' folder ready (%.1f min)\n', toc(t0) / 60);

%% 1. Out of fold on the whole fit set
pB = fusion_cand('oof', D, 'B', 1:K, []); yB = amax(pB);
P = cell(1, numel(C));
for c = 1:numel(C)
    if stopped(opt, ckd, out), R = []; return; end
    P{c} = fusion_cand('oof', D, C{c}, 1:K, []);
    out('  step 1: %s read out of fold (%.1f min)\n', C{c}, toc(t0) / 60);
end
t = [];
if any(contains(C, 'LBH')), t = head_time(D, pB, fold, det); end

%% 2. Nested
picks = repmat({''}, 1, K); yo = yB; Gi = cell(K, numel(C)); thr_i = nan(1, K);
for k = 1:K
    if stopped(opt, ckd, out), R = []; return; end
    tr = fold ~= k; ks = setdiff(1:K, k);
    yBi = amax(fusion_cand('oof', D, 'B', ks, k)); yBi = yBi(tr);
    thr_i(k) = fusion_cand('kpi1_thr', yt(tr), yBi, bin(tr), Cn);
    Bi = fusion_adopt('boot', fit.run(tr), 1000, 9160 + k);
    for c = 1:numel(C)
        pc = amax(fusion_cand('oof', D, C{c}, ks, k));
        Gi{k, c} = fusion_adopt('paired_cls', yt(tr), yBi, pc(tr), bin(tr) >= thr_i(k), low(tr), st(tr), classes, Bi);
        if contains(C{c}, 'CFAR'), Gi{k, c}.exc = exc_pct(D, k, ks); end
    end
    j = fusion_adopt('pick', C, Gi(k, :), t);
    te = fold == k;
    if j > 0, picks{k} = C{j}; p = amax(P{j}); yo(te) = p(te); end
    out('  nested outer fold %d done (%.1f min)\n', k, toc(t0) / 60);
end
if stopped(opt, ckd, out), R = []; return; end

%% The readings, then the verdict line first
thr = fusion_cand('kpi1_thr', yt, yB, bin, Cn); above = bin >= thr;
B = fusion_adopt('boot', fit.run, 1000, 9102);
G = cell(1, numel(C)); ok = false(1, numel(C)); sc = cell(1, numel(C));
for c = 1:numel(C)
    G{c} = fusion_adopt('paired_cls', yt, yB, amax(P{c}), above, low, st, classes, B);
    if contains(C{c}, 'CFAR'), G{c}.exc = exc_pct(D, [], 1:K); end
    [ok(c), sc{c}] = fusion_adopt('cand', C{c}, G{c}, t);
end
k1 = fusion_adopt('pick', C, G, t);
Gn = fusion_adopt('paired_cls', yt, yB, yo, above, low, st, classes, B);
kc = find(contains(picks, 'CFAR'));
if ~isempty(kc), Gn.exc = exc_pct(D, [], kc); end
[okn, sn] = fusion_adopt('nested', picks, Gn, t);
if stopped(opt, ckd, out), R = []; return; end         % the readings past the timebox: no verdict
pick = ''; if k1 > 0, pick = C{k1}; end
if opt.quick
    out('\nQUICK code check on every 20th sub-run: every step ran; no reading printed or saved, no verdict (%.1f h)\n', ...
        toc(t0) / 3600);
    R = struct('quick', true, 'candidates', {C}, 'sha', sh);
    return;
end
adopt = k1 > 0 && okn;
if adopt
    out('\nVERDICT p3: adopt %s (fusion_pick.m names it; B2F re-checks it on its own fit set)\n', pick);
else
    out('\nVERDICT p3: B, the d91 pick, deploys unchanged\n');
end
out('  step 1 on the whole fit set picks %s; outer picks %s; the nested reading passes its rules: %s; LBH %s\n', ...
    pick_txt(pick), strjoin(cellfun(@pick_txt, picks, 'UniformOutput', false), ', '), yn(okn), lbh_txt(opt.lbh));
out('\nOut of fold over %d frames (%d sub-runs), against B; KPI 1 threshold of B''s reading %g dB\n', n, numel(ru), thr);
out('  B: macro-F1 every frame %.2f%%, above the threshold %.2f%%; F1 airframe_shadowing %.2f%%, benign_interference %.2f%%\n', ...
    100 * mf1(yt, yB, Cn), 100 * mf1(yt(above), yB(above), Cn), 100 * cf1(yt, yB, find(strcmp(classes, 'airframe_shadowing'))), ...
    100 * cf1(yt, yB, find(strcmp(classes, 'benign_interference'))));
if ~isempty(t)
    out('  the packed head (LBH, fitted without fold 1): single-row call median %.3f ms, p95 %.3f ms on one thread; the detector %.2f / %.2f ms\n', ...
        t.median_ms, t.p95_ms, t.det_median_ms, t.det_p95_ms);
end
for c = 1:numel(C)
    out('  %-9s %s\n            %s\n            rule %s -> %s\n', C{c}, gtxt(G{c}), ctxt(G{c}), stxt(sc{c}), yn(ok(c)));
end
for k = 1:K
    out('  nested outer fold %d (KPI 1 threshold %g dB): inner rules %s -> %s\n', k, thr_i(k), strjoin(cellfun(@(c, d) ...
        sprintf('%s %s', c, yn(fusion_adopt('cand', c, d, t))), C, Gi(k, :), 'UniformOutput', false), ', '), pick_txt(picks{k}));
    for c = 1:numel(C), out('      inner %-9s %s\n', C{c}, gtxt(Gi{k, c})); end
end
out('  NESTED reading against B: %s\n            %s\n            rules %s -> %s\n', gtxt(Gn), ctxt(Gn), stxt(sn), yn(okn));
R = struct('candidates', {C}, 'G', {G}, 'ok', ok, 'rules', {sc}, 'Gi', {Gi}, 'picks', {picks}, 'Gn', Gn, 'nested_ok', okn, ...
    'nested_rules', sn, 'pick', pick, 'adopt', adopt, 'thr', thr, 'thr_inner', thr_i, 'timing', t, 'det', det, 'sha', sh, ...
    'registration', REG_COMMIT, 'code', strtrim(gh), 'lbh', opt.lbh);
save(fullfile(out_dir, sprintf('m_head_%s.mat', tag)), 'R', 'yt', 'yB', 'yo', 'fold', '-v7.3');
out('##### m_head %s done %s (%.1f h)\n', tag, char(datetime('now')), toc(t0) / 3600);
end

function o = defaults(o)
if nargin < 1 || isempty(o), o = struct(); end
d = struct('lbh', '', 'det_file', '', 'det_ms', [NaN NaN], 'stop_at', NaT, 'quick', false);
for f = fieldnames(d)', if ~isfield(o, f{1}), o.(f{1}) = d.(f{1}); end, end
assert(isempty(o.lbh) || startsWith(o.lbh, 'approved by Adi on '), 'm_head:lbh', ...
    'opt.lbh is empty or records the yes as ''approved by Adi on <date, time>''');
end

function C = candidates(opt)
C = fusion_cand('names');
if isempty(opt.lbh), C = C(~contains(C, 'LBH')); end
end

function guard(data_dir, out_dir, sets_sha, ck_sha)
% Before loading: no path of the fourth test set, and the inputs are the recorded extracts.
for p = {data_dir, out_dir}
    assert(~contains(lower(p{1}), {'set4_out', 'fresh3'}), 'm_head:set4', '%s is a path of the fourth test set', p{1});
    assert(isempty(dir(fullfile(p{1}, '**', '*fresh3*'))), 'm_head:set4', '%s holds a file of the fourth test set', p{1});
end
assert(isempty(which('splits_fresh3.mat')), 'm_head:set4', 'splits_fresh3.mat is on the MATLAB path');
f = {fullfile(data_dir, 'sets.mat'), fullfile(data_dir, 'ck_p3.mat')};
assert(isfile(f{1}) && isfile(f{2}), 'm_head:input', 'sets.mat and ck_p3.mat are needed in %s', data_dir);
h = {file_sha(f{1}, false), file_sha(f{2}, false)};
assert(strcmp(h{1}, sets_sha) && strcmp(h{2}, ck_sha), 'm_head:input', ...
    'the inputs are not the recorded extracts (SHA-256 %s, %s)', h{1}, h{2});
end

function set4(S)
% No row of the fourth test set: its sub-runs have the seeds 6 000 000 + run id (B3q). The
% sets are the four of the enlarged fit set, each with its sub-runs' seeds.
names = fieldnames(S)';
assert(isempty(setxor(names, {'val', 'test', 'fresh', 'fresh2'})), 'm_head:set4', 'the sets are %s', strjoin(names, ', '));
for k = 1:numel(names)
    s = S.(names{k});
    assert(isfield(s, 'draws') && isfield(s.draws, 'seed') && numel(s.draws.seed) == numel(s.run), 'm_head:set4', ...
        '%s names no seed per frame', names{k});
    sd = double(s.draws.seed);
    assert(~any(sd >= 6000000 & sd < 6100000), 'm_head:set4', ...
        '%s holds flights of the fourth test set (seeds 6 000 000-6 099 999)', names{k});
end
end

function manifest(ckd, sh)
% The fits' folder belongs to one code and input state; a voided folder is never used again.
if ~isfolder(ckd), mkdir(ckd); end
assert(~isfile(fullfile(ckd, 'VOID.txt')), 'm_head:void', '%s was voided by a timebox: its fits are never used', ckd);
f = fullfile(ckd, 'manifest.mat');
if isfile(f)
    M = load(f, 'sh');
    assert(isequal(M.sh, sh), 'm_head:stale', '%s holds fits of another code or input state', ckd);
else
    save(f, 'sh');
end
end

function s = stopped(opt, ckd, out)
s = ~isnat(opt.stop_at) && datetime('now') >= opt.stop_at;
if s
    fid = fopen(fullfile(ckd, 'VOID.txt'), 'w'); fprintf(fid, 'stopped at the timebox %s\n', char(opt.stop_at)); fclose(fid);
    out('STOPPED at the timebox %s: no verdict; nothing read, the fits voided (B deploys unchanged)\n', char(opt.stop_at));
end
end

function t = head_time(D, pB, fold, det)
% The packed head's single-row call (fuse_head 'apply'), on one thread: 20 warm-up calls, then
% 2000 over rows of fold 1, median and 95th percentile.
H = fusion_cand('head', D, 'LBH', 1);
Zv = [D.Z0, D.XB];
r = find(fold == 1); r = r(round(linspace(1, numel(r), 2000)));
x = zeros(1, 2020);
for i = 1:2020
    q = r(mod(i - 1, 2000) + 1);
    t0 = tic; fuse_head('apply', H, pB(q, :), Zv(q, :)); x(i) = 1000 * toc(t0);
end
x = sort(x(21:end));
t = struct('median_ms', median(x), 'p95_ms', x(ceil(0.95 * numel(x))), 'det_median_ms', det.median_ms, 'det_p95_ms', det.p95_ms);
end

function e = exc_pct(D, X, ks)
% Clean gaps of the folds ks above T1 and above T2 fitted without them (and X), percent.
a = [0 0 0];
for k = ks(:)'
    [n1, n2, m] = fusion_cand('exc', D, sort([X(:)', k]), k); a = a + [n1 n2 m];
end
e = 100 * a(1:2) / max(a(3), 1);
end

function h = file_sha(f, lf)
% SHA-256 of a file's bytes (lf: carriage returns dropped, the committed text's line ends).
fid = fopen(f, 'r'); assert(fid > 0, 'm_head:read', 'cannot read %s', f);
md = java.security.MessageDigest.getInstance('SHA-256');
b = fread(fid, 2^24, '*uint8');
while ~isempty(b)
    if lf, b = b(b ~= 13); end
    md.update(b);
    b = fread(fid, 2^24, '*uint8');
end
fclose(fid);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function s = gtxt(d)
s = sprintf(['all %+.2f [%+.2f, %+.2f], above %+.2f [%+.2f, %+.2f], clean as threat %+.2f [%+.2f, %+.2f], as lost branch %+.2f ' ...
    '[%+.2f, %+.2f], clean as benign %+.2f [%+.2f, %+.2f]; F1 fault %+.2f [%+.2f, %+.2f], shadowing %+.2f [%+.2f, %+.2f], ' ...
    'K<=0 fault %+.2f [%+.2f, %+.2f], shadowing %+.2f [%+.2f, %+.2f]; per set shadowing %s, benign %s'], d.all, d.above, d.cl, ...
    d.lb, d.cb, d.fault, d.shad, d.fault_low, d.shad_low, mat2str(round(d.set_shad, 2)), mat2str(round(d.set_benign, 2)));
if isfield(d, 'exc'), s = [s, sprintf('; clean gaps above T1 %.2f%%, T2 %.2f%%', d.exc)]; end
end

function s = ctxt(d)
s = ['F1 per class: ', strjoin(cellfun(@(c, v) sprintf('%s %+.2f [%+.2f, %+.2f]', c, v(1), v(2), v(3)), d.classes(:)', ...
    num2cell(d.cls, 2)', 'UniformOutput', false), ', ')];
end

function s = stxt(r)
f = fieldnames(r);
s = strjoin(cellfun(@(x) sprintf('%s %s', x, yn(r.(x))), f(:)', 'UniformOutput', false), ' ');
if isempty(f), s = 'none applies'; end
end

function s = pick_txt(p)
s = p; if isempty(p), s = 'B'; end
end

function s = lbh_txt(a)
s = ['in, ' a]; if isempty(a), s = 'struck (no yes before the measurement)'; end
end

function s = yn(x)
if x, s = 'yes'; else, s = 'no'; end
end

function both(fid, varargin)
fprintf(varargin{:}); fprintf(fid, varargin{:});
end

function k = amax(p)
[~, k] = max(p, [], 2);
end

function m = mf1(y, yh, C)
cm = accumarray([y(:) yh(:)], 1, [C C]);
pr = diag(cm) ./ sum(cm, 1)'; rc = diag(cm) ./ sum(cm, 2);
f = 2 * pr .* rc ./ (pr + rc); m = mean(f(sum(cm, 2) > 0), 'omitnan');
end

function f = cf1(y, yh, c)
f = 2 * sum(y == c & yh == c) / max(sum(y == c) + sum(yh == c), 1);
end
