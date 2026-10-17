%% B2F - SELECT_FUSION: temporal fusion of the detector over the last decision cycles
% The per-frame detector decides on 0.5 ms of signal; the fusion
% (temporal_evidence.m, fuse_classes.m) decides on the last N cycles. It is fitted
% on the validation split, where the detector's outputs are not overconfident, and
% N and the regularization are chosen by cross-validation over the validation
% sub-runs (5 folds by sub-run). Each candidate is fitted on its own window's targets
% (fusion_target.m: a WLAN frame without a packet whose window holds packet frames has the
% target benign_interference, a frame whose window holds a path-loss onset the target
% path_loss) and, by default, chosen by the highest out-of-fold macro-F1 on those targets.
% The out-of-fold predictions and their targets are kept for the KPI 1 threshold of
% eval_detector.m. Every candidate's score on the per-cycle label of threat_active.m is
% printed beside.
% With FUSION_REV true the path-loss target ends while the window still holds a cycle before
% the onset (threat_active.m's rule, FM.target_age = N - 1); every candidate is scored on the
% frames whose target no candidate's window changes, where all of them share the per-cycle
% label: on its own targets a longer window gains by the frames it relabels, on the per-cycle
% label of every frame it loses by the same frames it was fitted to call by its window; of the
% candidates within one standard error (over the 5 folds) of the best the shortest window is
% taken (the one-standard-error rule, Hastie, Tibshirani & Friedman, The Elements of
% Statistical Learning, 2nd ed., sec. 7.10: each cycle of the window is 20 ms of memory), with
% its best regularization; and the fusion's further columns (window_cues.m 'extra') are
% chosen, each against the fusion without it
% on validation, out of fold over the same folds at the chosen N and lambda, paired by
% bootstrap over sub-runs: the idle time against the radio's own noise (cfar: the crest and
% spread of every gap over its own floor, thresholds from the training folds' clean gaps,
% realized clean exceedance at most 1%; Grimaldi et al. 2019, Kazim et al. 2026 eq. 1.3)
% when macro-F1 above the KPI 1 threshold loses nothing (95% lower bound >= -0.1 point),
% every frame's gains (lower bound > 0) and the clean frames read as a threat do not rise
% (lower bound <= 0); the branch that steps (iso: detection-isolation, Xie et al. 2021, Sec.
% III-I) when every frame's macro-F1 gains (lower bound > 0), the clean frames read as a lost
% branch do not rise and airframe-shadowing recall, overall and at K below 0 dB, does not
% fall; both when the two rules hold for both together, else the single one with the larger
% gain. FM.cues records them (fuse_classes('cues', FM)) and every reader builds the same row;
% without FUSION_REV the fusion has none.
% The quiet-slot interference alarm of the rule (rule_based_policy.m) is set here from
% the clean validation frames (the sub-runs without a threat), as an AGC jamming monitor
% sets its threshold from interference-free samples, Th = mu - 3 sigma - 2 dB for a gain
% drop (Kazim et al. 2026, eq. 1.3, p. 2); the slot's power rises instead, so
% q_thr = mu + 3 sigma + 2 dB of q_iot. The threshold of the onset's shape, which the
% monitor's latched cause of a lost branch reads (onset_shape.m: a ramp above it, airframe
% shadowing; a step at or below it, an antenna fault), is chosen on the validation sub-runs
% of the two threats: the statistic at the latch's diagnosis of each sub-run's event on the
% threat's branch, the latch run as deployed (onset_shape.m 'events', decision_config.m
% heal), the threshold that reads the two causes right in the largest mean share
% (FM.os_thr). The monitor's class out of fold with the latch (val_latch_oof): the latch over
% the out-of-fold fused probabilities of every validation sub-run, its threshold chosen on the
% other folds' sub-runs. Whether the monitor latches at all (FM.latch, onset_shape('on', FM))
% is chosen here too: the latch only where its out-of-fold macro-F1 is above the fused class's
% (val_probs_oof), the measure that chose N and lambda; the per-event reading of a lost
% branch's cause (the first cycle from the onset read as antenna_fault or
% airframe_shadowing, the right one) is printed beside. The monitor's class out of fold, with
% or without the latch as chosen, sets the KPI 1 threshold of eval_detector.m. The test split
% is not used.
% Output: data/fusion.mat (FM with os_thr and latch, N, lambda, cv table, out-of-fold
% probabilities (fused, and with the latch) and their targets, q_thr; with FUSION_REV also
% FM.cues, FM.target_age and the cvy, cvo tables). Without FUSION_REV the fusion and its file
% are those of the selection by the own targets alone.

close all; clc;
fprintf('=== B2F: temporal fusion (validation split only) ===\n\n');
REV = exist('FUSION_REV', 'var') && isequal(FUSION_REV, true);
if REV, fprintf('The revised selection (FUSION_REV): N on the frames no candidate relabels, target age N - 1, the further columns\n\n'); end
S = load('data/splits.mat'); va = S.splits.val; norm = S.splits.norm;
if ~isfield(va, 'pos')
    error('splits.mat has no frame positions (v6 dataset). Run run_dataset_sweep, extract_spectrograms, prepare_data.');
end
va.feat_names = norm.feat_names;
D = load('data/trained_detector.mat', 'net', 'classes');
C = numel(classes_of(D));
classes = classes_of(D);
P = cnn_scores(D.net, va.X, va.feats')';                 % frames x C
y = double(va.Y(:));
NS = [1 3 5 8 12];
LAMBDA = [1e-4 1e-3 1e-2];
K = 5;
runs = unique(va.run);
rs = RandStream('mt19937ar', 'Seed', 61);
fold_of_run = mod(randperm(rs, numel(runs)), K) + 1;
[~, ir] = ismember(va.run, runs);
fold = fold_of_run(ir)';
ib = find(strcmp(classes, 'benign_interference')); ip = find(strcmp(classes, 'path_loss'));

%% 1. N and lambda
cvy = zeros(numel(NS), numel(LAMBDA)); cvo = cvy; cvf = zeros(numel(NS), numel(LAMBDA), K); oof = cell(numel(NS), numel(LAMBDA));
ZN = cell(1, numel(NS)); YN = zeros(numel(y), numel(NS));
for a = 1:numel(NS)
    TAa = []; if REV, TAa = struct('target_age', NS(a) - 1); end
    YN(:, a) = fusion_target(y, va.run, va.pos, NS(a), classes, TAa);
end
cm = true(size(y)); lab = 'the per-cycle label';
if REV, cm = all(YN == y, 2); lab = 'the frames no candidate relabels'; end
for a = 1:numel(NS)
    ZN{a} = fuse_classes('windows', va, P, NS(a));
    yn = YN(:, a);
    for b = 1:numel(LAMBDA)
        pc = oof_fit(ZN{a}, yn, fold, C, LAMBDA(b));
        [~, yh] = max(pc, [], 2);
        cvy(a, b) = macro_f1(y(cm), yh(cm), C); cvo(a, b) = macro_f1(yn, yh, C);
        cvf(a, b, :) = arrayfun(@(k) macro_f1(y(cm & fold == k), yh(cm & fold == k), C), 1:K);
        oof{a, b} = pc;
        fprintf(['  N = %2d cycles, lambda %.0e: macro-F1 %.2f%% out of fold on its own window''s targets, %.2f%% on %s; ' ...
            'path-loss relabels %d, benign %d\n'], NS(a), LAMBDA(b), 100 * cvo(a, b), 100 * cvy(a, b), lab, ...
            sum(yn ~= y & yn == ip), sum(yn ~= y & yn == ib));
    end
end
if REV, fprintf('Frames no candidate''s window relabels: %d of %d\n', sum(cm), numel(y)); end
if REV
    cv = cvy;
    [mx, i] = max(cv(:)); [a1, b1] = ind2sub(size(cv), i);
    se = std(squeeze(cvf(a1, b1, :))) / sqrt(K);
    a = find(max(cv, [], 2) >= mx - se, 1);           % the shortest window within one standard error
    [~, b] = max(cv(a, :));
    fprintf(['\nBest on the frames no candidate relabels: N = %d, lambda %.0e, %.2f%% (standard error %.2f over the folds); ' ...
        'the one-standard-error rule: N = %d cycles, lambda %.0e, %.2f%%\n'], NS(a1), LAMBDA(b1), 100 * mx, 100 * se, ...
        NS(a), LAMBDA(b), 100 * cv(a, b));
    TA = struct('target_age', NS(a) - 1);
else
    cv = cvo;
    [~, i] = max(cv(:)); [a, b] = ind2sub(size(cv), i);
    TA = [];
end
N = NS(a); lambda = LAMBDA(b);
Z = ZN{a}; clear ZN
val_target = fusion_target(y, va.run, va.pos, N, classes, TA);
fprintf('Frames judged by their window: path-loss onsets %d, WLAN frames without a packet as benign_interference %d (of %d none frames)\n', ...
    sum(val_target ~= y & val_target == ip), sum(val_target ~= y & val_target == ib), sum(y == find(strcmp(classes, 'none'))));
pc0 = oof{a, b}; clear oof

%% 2. The fusion's further columns, each against the fusion without it (FUSION_REV)
cues = []; pick = 1; PV = {pc0};
if REV
    iso_x = fuse_classes('extra', va, N, struct('iso', true));
    V = {'none', 'cfar', 'iso', 'cfar and iso'}; PV = cell(1, 4); PV{1} = pc0; TH = nan(K, 3);
    for v = 2:4
        pc = zeros(numel(y), C);
        for k = 1:K
            tr = fold ~= k; te = fold == k;
            [X, TH(k, :)] = extra_cols(va, N, v, tr, iso_x);
            FMv = fuse_classes('fit', [Z(tr, :), X(tr, :)], val_target(tr), C, lambda);
            pc(te, :) = fuse_classes('apply', FMv, [Z(te, :), X(te, :)]);
        end
        PV{v} = pc;
    end
    [bin, ~] = kpi_ebno(va, val_target, classes);
    yb = argmax(pc0); thr = kpi1_thr(val_target, yb, bin, classes);
    G = struct('all', {}, 'above', {}, 'cl', {}, 'lb', {}); RC = zeros(4, 3); i0 = find(strcmp(classes, 'none'));
    iaf = find(strcmp(classes, 'antenna_fault')); ias = find(strcmp(classes, 'airframe_shadowing'));
    kdb = nan(numel(y), 1); if isfield(va, 'k_db'), kdb = double(va.k_db(:)); end
    B = run_boot(va.run, 1000, 62);
    for v = 1:4
        yh = argmax(PV{v});
        RC(v, :) = 100 * [mean(yh(val_target == i0) == iaf | yh(val_target == i0) == ias), mean(yh(val_target == ias) == ias), ...
            mean(yh(val_target == ias & kdb < 0) == ias)];
        if v > 1, G(v) = paired(val_target, yb, yh, bin >= thr, C, B, i0, [iaf ias]); end
    end
    ok_cfar = @(v) G(v).above(2) >= -0.1 && G(v).all(2) > 0 && G(v).cl(2) <= 0;
    ok_iso = @(v) G(v).all(2) > 0 && RC(v, 1) <= RC(1, 1) && RC(v, 2) >= RC(1, 2) && RC(v, 3) >= RC(1, 3);
    ad = [ok_cfar(2), ok_iso(3), ok_cfar(4) && ok_iso(4)];
    if ad(3), pick = 4; elseif ad(1) && ad(2), pick = 2 + (G(3).all(1) > G(2).all(1)); elseif ad(1), pick = 2; elseif ad(2), pick = 3;
    else, pick = 1; end
    fprintf(['Further columns at N = %d, lambda %.0e, out of fold, against none (macro-F1 points, 95%% bootstrap over sub-runs; ' ...
        'KPI 1 threshold of the fusion without them %g dB):\n'], N, lambda, thr);
    for v = 2:4
        fprintf(['  %-13s every frame %+.2f [%+.2f, %+.2f], above the threshold %+.2f [%+.2f, %+.2f], clean as a threat %+.2f ' ...
            '[%+.2f, %+.2f], clean as a lost branch %+.2f [%+.2f, %+.2f]; shadowing recall %.1f%% (K < 0 dB %.1f%%) against %.1f%% (%.1f%%)\n'], ...
            V{v}, G(v).all, G(v).above, G(v).cl, G(v).lb, RC(v, 2), RC(v, 3), RC(1, 2), RC(1, 3));
    end
    fprintf('  cfar thresholds per training folds [dB] (crest T1, spread T2, median crest): %s\n', mat2str(TH, 3));
    fprintf('  adopted: cfar %s, iso %s, both %s -> the fusion''s further columns: %s\n', yn_txt(ad(1)), yn_txt(ad(2)), yn_txt(ad(3)), V{pick});
    if ismember(pick, [2 4]), cues.cfar = cfar_thr(va, true(numel(y), 1)); end
    if ismember(pick, [3 4]), cues.iso = true; end
    if ~isempty(cues)
        if ~isfield(cues, 'cfar'), cues.cfar = []; end
        if ~isfield(cues, 'iso'), cues.iso = false; end
        Z = [Z, fuse_classes('extra', va, N, cues)];
        if ~isempty(cues.cfar), fprintf('  clean gaps of the validation split: T1 %.2f dB, T2 %.2f dB, median crest %.2f dB\n', cues.cfar); end
    end
end
val_probs_oof = PV{pick};
FM = fuse_classes('fit', Z, val_target, C, lambda);
if REV, FM.target_age = TA.target_age; FM.cues = cues; end
[~, y1] = max(P, [], 2);
yfr = y; if isfield(va, 'Y_frame'), yfr = double(va.Y_frame(:)); end   % the per-frame network's own labels
fprintf('\nThe fusion: N = %d cycles, lambda %.0e, macro-F1 %.2f%% out of fold on its targets (per frame, frame rule %.2f%%)\n', ...
    N, lambda, 100 * macro_f1(val_target, argmax(val_probs_oof), C), 100 * macro_f1(yfr, y1, C));
qi = va.feats_raw(isnan(va.level), strcmp(va.feat_names, 'q_iot'));
q_thr = mean(qi) + 3 * std(qi) + 2;
fprintf('Quiet-slot interference alarm: %.2f dB over thermal (clean frames: mean %.2f, std %.2f dB, n = %d)\n', ...
    q_thr, mean(qi), std(qi), numel(qi));
iB = [find(strcmp(classes, 'antenna_fault')), find(strcmp(classes, 'airframe_shadowing'))];
heal = decision_config().heal;
og = []; oy = []; orun = [];                            % the statistic at the latch's diagnosis, the sub-run's cause
if numel(iB) == 2
    for r = runs(:)'
        ix = find(va.run == r); [~, o] = sort(va.pos(ix)); ix = ix(o);
        bb = find(ismember(iB, y(ix)), 1);
        if isempty(bb), continue; end
        j0 = find(y(ix) == iB(bb), 1);                  % the threat's first labelled frame
        og(end+1) = onset_shape('events', va.gain_ant(ix, :), j0, heal); oy(end+1) = bb; orun(end+1) = r; %#ok<SAGROW>
    end
end
FM.os_thr = onset_shape('choose', og, oy);
k = isfinite(og);
fprintf(['Onset shape: threshold %+.2f (validation sub-runs with a latched event on the threat''s branch: antenna ' ...
    'fault %d of %d, read right %.1f%%; airframe shadowing %d of %d, %.1f%%)\n'], FM.os_thr, sum(k & oy == 1), ...
    sum(oy == 1), 100 * mean(og(k & oy == 1) <= FM.os_thr), sum(k & oy == 2), sum(oy == 2), ...
    100 * mean(og(k & oy == 2) > FM.os_thr));
val_latch_oof = val_probs_oof;                          % the monitor's class out of fold
[~, ko] = ismember(orun, runs); ko = fold_of_run(ko);
for f = 1:K
    m = fold == f;
    tf = onset_shape('choose', og(ko ~= f), oy(ko ~= f));
    val_latch_oof(m, :) = latch_runs(val_probs_oof(m, :), va.run(m), va.pos(m), va.gain_ant(m, :), classes, tf, heal);
end
[~, yl] = max(val_latch_oof, [], 2); [~, yo] = max(val_probs_oof, [], 2);
mf_latch = macro_f1(val_target, yl, C); mf_fused = macro_f1(val_target, yo, C);
FM.latch = mf_latch > mf_fused;                         % the latch only where it raises macro-F1 out of fold
fprintf('Out of fold, the monitor''s class with the latched cause of a lost branch: macro-F1 %.2f%%; the fused class %.2f%%\n', ...
    100 * mf_latch, 100 * mf_fused);
[ef, nf] = event_cause(yo, val_target, va.run, va.pos, iB); [el, ~] = event_cause(yl, val_target, va.run, va.pos, iB);
fprintf(['Per event, the first cycle from the onset read as a lost branch reads the right cause: antenna fault %.1f%% ' ...
    'fused, %.1f%% latched (%d events); airframe shadowing %.1f%%, %.1f%% (%d events)\n'], 100 * ef(1), 100 * el(1), nf(1), ...
    100 * ef(2), 100 * el(2), nf(2));
if FM.latch
    fprintf('The monitor latches the cause of a lost branch (FM.latch = true)\n');
else
    fprintf('The monitor''s class is the fused class: the latch is off (FM.latch = false)\n');
end
if ~exist('results', 'dir'), mkdir('results'); end
save('data/fusion.mat', 'FM', 'N', 'lambda', 'NS', 'LAMBDA', 'cv', 'val_probs_oof', 'val_latch_oof', 'val_target', 'q_thr');
if REV, save('data/fusion.mat', 'cvy', 'cvo', '-append'); end
fprintf('Saved data/fusion.mat\n');

function c = classes_of(D)
c = cellstr(string(D.classes(:)'));
end

function pc = oof_fit(Z, yn, fold, C, lambda)
% Out-of-fold fused probabilities over the sub-run folds.
pc = zeros(numel(yn), C);
for k = unique(fold(:))'
    tr = fold ~= k; te = fold == k;
    FMk = fuse_classes('fit', Z(tr, :), yn(tr), C, lambda);
    pc(te, :) = fuse_classes('apply', FMk, Z(te, :));
end
end

function k = argmax(p)
[~, k] = max(p, [], 2);
end

function T = cfar_thr(va, tr)
% The cfar thresholds from the clean gaps of the frames tr (the clean sub-runs, level NaN):
% T1, T2 the smallest crest and spread exceeded by at most 1% of them (nearest rank), m0 the
% median crest [dB].
I = double(va.idle); nm = idle_summary('names'); c = @(s) I(:, strcmp(nm, s));
ok = tr(:) & isnan(va.level(:)) & c('gap_ms') > 0 & ~isnan(c('occ'));
mx = c('max'); p10 = c('p10'); p90 = c('p90');
cr = sort(mx(ok) - p10(ok)); sp = sort(p90(ok) - p10(ok));
q = @(x) x(max(1, ceil(0.99 * numel(x))));
T = [q(cr), q(sp), median(cr)];
end

function [X, T] = extra_cols(va, N, v, tr, iso_x)
% The further columns of variant v (2 cfar, 3 iso, 4 both), cfar thresholds from the frames tr.
T = nan(1, 3); X = zeros(numel(va.run), 0);
if ismember(v, [2 4]), T = cfar_thr(va, tr); X = fuse_classes('extra', va, N, struct('cfar', T)); end
if ismember(v, [3 4]), X = [X, iso_x]; end
end

function thr = kpi1_thr(yt, yp, bin, classes)
% The KPI 1 threshold rule of eval_detector.m: the lowest Eb/N0 from which macro-F1 stays >= 90%.
u = unique(bin(~isnan(bin)));
f = arrayfun(@(v) 100 * mf1_cm(confusionmat(yt(bin == v), yp(bin == v), 'Order', 1:numel(classes))), u);
k = find(f < 90, 1, 'last'); if isempty(k), k0 = 1; else, k0 = k + 1; end
thr = NaN; if k0 <= numel(u), thr = u(k0); end
end

function f = mf1_cm(cm)
% Macro-F1 of a confusion matrix over the classes present among the targets (eval_detector.m).
pr = diag(cm) ./ sum(cm, 1)'; rc = diag(cm) ./ sum(cm, 2);
f1 = 2 * pr .* rc ./ (pr + rc);
f = mean(f1(sum(cm, 2) > 0), 'omitnan');
end

function B = run_boot(run, nb, seed)
% Bootstrap weights over the sub-runs: nb resamples of the sub-runs with replacement.
[u, ~, ri] = unique(run(:));
s = RandStream('mt19937ar', 'Seed', seed);
B = struct('ri', ri, 'n', numel(u), 'w', zeros(nb, numel(u)));
for b = 1:nb, B.w(b, :) = accumarray(randi(s, numel(u), numel(u), 1), 1, [numel(u) 1])'; end
end

function d = paired(yt, ya, yb, above, C, B, i0, lost)
% Paired sub-run bootstrap of b - a [points, 95%]: macro-F1 over every frame and above the
% KPI 1 threshold, the clean frames read as any threat and as a lost branch.
nr = B.n;
cmr = @(m, yh) accumarray([B.ri(m), sub2ind([C C], yt(m), yh(m))], 1, [nr C * C]);
A1 = cmr(true(size(yt)), ya); B1 = cmr(true(size(yt)), yb); A2 = cmr(above, ya); B2 = cmr(above, yb);
cl = yt == i0; cnt = @(x) accumarray(B.ri(cl), double(x(cl)), [nr 1]);
n1a = cnt(ya ~= i0); n1b = cnt(yb ~= i0); n2a = cnt(ismember(ya, lost)); n2b = cnt(ismember(yb, lost)); dn = cnt(true(size(yt)));
f = @(w, M) mf1_cm(reshape(w * M, C, C));
x = zeros(size(B.w, 1), 4);
for k = 1:size(B.w, 1)
    w = B.w(k, :);
    x(k, :) = 100 * [f(w, B1) - f(w, A1), f(w, B2) - f(w, A2), (w * (n1b - n1a)) / max(w * dn, 1), (w * (n2b - n2a)) / max(w * dn, 1)];
end
o = ones(1, nr);
pt = 100 * [f(o, B1) - f(o, A1), f(o, B2) - f(o, A2), sum(n1b - n1a) / sum(dn), sum(n2b - n2a) / sum(dn)];
ci = prctile(x, [2.5 97.5]);
d = struct('all', [pt(1) ci(:, 1)'], 'above', [pt(2) ci(:, 2)'], 'cl', [pt(3) ci(:, 3)'], 'lb', [pt(4) ci(:, 4)']);
end

function t = yn_txt(x)
if x, t = 'yes'; else, t = 'no'; end
end

function [r, n] = event_cause(k, y, run, pos, iB)
% Per lost-branch class (iB: antenna_fault, airframe_shadowing), the share of the validation
% sub-runs whose first cycle from the class's onset read as either class reads the right one
% (never read: wrong), and their number.
r = nan(1, 2); n = zeros(1, 2);
if numel(iB) < 2, return; end
ok = zeros(1, 2);
for q = unique(run(ismember(y, iB)))'
    ix = find(run == q); [~, o] = sort(pos(ix)); ix = ix(o);
    for b = 1:2
        j0 = find(y(ix) == iB(b), 1);
        if isempty(j0), continue; end
        j = find(ismember(k(ix(j0:end)), iB), 1);
        n(b) = n(b) + 1;
        if ~isempty(j), ok(b) = ok(b) + (k(ix(j0 + j - 1)) == iB(b)); end
    end
end
r = ok ./ max(n, 1);
end

function m = macro_f1(y, yh, C)
f = zeros(1, C);
for c = 1:C
    tp = sum(yh == c & y == c); fp = sum(yh == c & y ~= c); fn = sum(yh ~= c & y == c);
    f(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
m = mean(f);
end
