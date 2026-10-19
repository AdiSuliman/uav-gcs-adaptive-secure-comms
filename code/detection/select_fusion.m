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
% chosen, each against the fusion without it, out of fold by sub-run at the chosen N and
% lambda, paired by bootstrap over sub-runs (fusion_adopt.m): the idle time against the radio's
% own noise (cfar: the crest and spread of every gap over its own floor, thresholds from the
% training folds' clean gaps, realized clean exceedance at most 1%; Grimaldi et al. 2019,
% Kazim et al. 2026 eq. 1.3) when macro-F1 above the KPI 1 threshold loses nothing (95% lower
% bound >= -0.1 point), every frame's gains (lower bound > 0) and the clean frames read as a
% threat do not rise (lower bound <= 0); a lost branch's evidence, each alone and all
% together (iso, the branch that steps, detection-isolation, Xie et al. 2021, Sec. III-I;
% glr, its drop against the others in linear power; held, its held reference, branch_ref.m;
% post, the K and spread cues after its step), when antenna_fault F1 and macro-F1 over every
% frame and above the threshold gain (lower bounds > 0), airframe_shadowing F1 loses nothing
% beyond its interval, neither lost-branch class loses beyond its interval at K <= 0 dB and
% the clean frames read as a threat or as a lost branch do not rise; of the branch variants
% so adopted the one with the largest gain, and with cfar both when the two rules hold for
% them together, else the single one with the larger gain. FM.cues records them
% (fuse_classes('cues', FM)) and every reader builds the same row; without FUSION_REV the
% fusion has none. With FUSION_FIT = 'enlarged' as well, the further columns are chosen and
% the fusion is fitted on the enlarged fit set (fit_sets.m: the validation split, the first
% test split and the second and third test sets, 5 folds by sub-run, a sub-run never split;
% N and lambda stay chosen on validation), and val_probs_oof holds its validation frames;
% the test sets' readings are then spent, and KPI 1 is read on a test set built after it.
% There the further columns are not chosen again: the design the measurement adopted
% (fusion_pick.m; docs/d91_fuse.md) is deployed as measured, at its N and lambda (a
% FUSION_PICK override only on the validation fit, select_fusion:pick_measured), on the
% deployed target rule (pos - onset < N, FM.target_age = N) and without cfar, and B2F stops
% (select_fusion:pick_rule) unless the adoption rule fusion_adopt('branch')
% holds for it against the fusion without it, out of fold on the same fit set and folds.
% Before any data is read, the enlarged fit set's files must exist (select_fusion:fit_sets)
% and the kept data/fusion.mat, which a no-go keeps, must be that base: the pick's N, lambda
% and latch, no further columns unless it is this pick deployed before on the enlarged fit set
% (deployed_pick and fusion_rev_id('enlarged'); select_fusion:pick_base). A failed rule, or a
% kept fusion that is not the base, writes the no-go record data/fusion_nogo.mat (fusion_nogo.m)
% before B2F stops, so B3r can read the kept fusion once on the fourth set.
% FUSION_REV without FUSION_FIT = 'enlarged' (a design chosen or fitted on validation only)
% runs only with SMOKE or FUSION_DEV = true (select_fusion:rev_fit), so a live tree never saves
% one. In the smoke only, FUSION_RULE_LOG = true prints a failed rule and saves all the same, so
% the deploy path after B2F (re-key, C1d, C2, C2e, EDGE) runs end to end on smoke data.
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
% (val_probs_oof), the measure that chose N and lambda; with a pick it is the pick's measured
% state (PK.latch), validation's choice printed beside. The per-event reading of a lost
% branch's cause (the first cycle from the onset read as antenna_fault or
% airframe_shadowing, the right one) is printed beside. The monitor's class out of fold, with
% or without the latch as chosen, sets the KPI 1 threshold of eval_detector.m. The test split
% is not used (but in the enlarged fit set).
% Output: data/fusion.mat (FM with os_thr and latch, N, lambda, cv table, out-of-fold
% probabilities (fused, and with the latch) and their targets, q_thr; with FUSION_REV also
% FM.cues, FM.target_age, the cvy, cvo tables and fusion_rev (fusion_rev_id.m); with a pick
% also deployed_pick, the design, its rule check and the latch comparison). Without
% FUSION_REV the fusion and its file are those of the selection by the own targets alone.

close all; clc;
fprintf('=== B2F: temporal fusion (validation split only) ===\n\n');
REV = exist('FUSION_REV', 'var') && isequal(FUSION_REV, true);
if REV, fprintf('The revised selection (FUSION_REV): N on the frames no candidate relabels, target age N - 1, the further columns\n\n'); end
ENL = REV && exist('FUSION_FIT', 'var') && strcmp(FUSION_FIT, 'enlarged');
PK = [];                                                 % the measured design, deployed without choosing again
if exist('FUSION_PICK', 'var') && ~isempty(FUSION_PICK), PK = FUSION_PICK; elseif ENL, PK = fusion_pick(); end
assert(isempty(PK) || REV, 'select_fusion:pick', 'FUSION_PICK needs FUSION_REV');
assert(~ENL || isequal(PK, fusion_pick()), 'select_fusion:pick_measured', ...
    'with FUSION_FIT = ''enlarged'' only the measured design (fusion_pick.m) is deployed; FUSION_PICK is for the validation fit');
SMK = exist('SMOKE', 'var') && isequal(SMOKE, true);
assert(~REV || ENL || SMK || (exist('FUSION_DEV', 'var') && isequal(FUSION_DEV, true)), 'select_fusion:rev_fit', ...
    ['FUSION_REV without FUSION_FIT = ''enlarged'' saves a design chosen or fitted on validation only: the deploy sets ' ...
    'FUSION_FIT = ''enlarged''; a smoke or dev copy sets SMOKE or FUSION_DEV = true (docs/d91_deploy.md)']);
RULE_LOG = ENL && SMK && exist('FUSION_RULE_LOG', 'var') && isequal(FUSION_RULE_LOG, true);   % smoke only: the rule is printed, not enforced
kept_base = [];                                          % the kept fusion, the rule's base (docs/d91_deploy.md)
if ENL
    [~, fs_miss] = enlarged_ready();
    assert(isempty(fs_miss), 'select_fusion:fit_sets', ...
        'the enlarged fit set needs %s (B3n, B3m first; docs/d91_deploy.md)', strjoin(fs_miss, ', '));
    assert(isfile('data/fusion.mat'), 'select_fusion:pick_base', ...
        'no kept fusion (data/fusion.mat): the rule''s base must be the fusion a no-go keeps (docs/d91_deploy.md)');
    KB = load('data/fusion.mat', 'N', 'lambda', 'FM');
    assert(all(isfield(KB, {'N', 'lambda', 'FM'})) && isstruct(KB.FM) && isfield(KB.FM, 'latch'), 'select_fusion:pick_base', ...
        'the kept data/fusion.mat names no N, lambda or latch');
    kept_base = struct('N', KB.N, 'lambda', KB.lambda, 'latch', logical(KB.FM.latch), ...
        'cues', isfield(KB.FM, 'cues') && ~isempty(KB.FM.cues));
    if kept_base.cues                                    % a revision with further columns: only this pick, deployed on the enlarged fit before
        KN = {whos('-file', 'data/fusion.mat').name}; KD = struct();
        if ismember('deployed_pick', KN), KD = load('data/fusion.mat', 'deployed_pick'); end
        if ismember('fusion_rev', KN), KD.fusion_rev = load('data/fusion.mat', 'fusion_rev').fusion_rev; end
        kept_base.cues = ~(isfield(KD, 'deployed_pick') && isfield(KD.deployed_pick, 'check') && ...
            isequal(rmfield(KD.deployed_pick, 'check'), PK) && isfield(KD, 'fusion_rev') && ...
            isequal(KD.fusion_rev, fusion_rev_id('enlarged')));
    end
    base_ok = kept_base.N == PK.N && kept_base.lambda == PK.lambda && kept_base.latch == PK.latch && ~kept_base.cues;
    if ~base_ok, fusion_nogo('write', PK, kept_base, 'base'); end   % no valid comparison: the kept fusion stays
    assert(base_ok, 'select_fusion:pick_base', ['the kept fusion (N %d, lambda %g, latch %d, further columns %d) is not the rule''s ' ...
        'base (N %d, lambda %g, latch %d, none): the rule would not compare with the fusion a no-go keeps (docs/d91_deploy.md)'], ...
        kept_base.N, kept_base.lambda, kept_base.latch, kept_base.cues, PK.N, PK.lambda, PK.latch);
    fprintf('The kept fusion is the rule''s base: N = %d cycles, lambda %.0e, latch %d, no further columns\n', ...
        kept_base.N, kept_base.lambda, kept_base.latch);
    clear KB KD KN fs_miss base_ok
end
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
if ~isempty(PK)
    fprintf('The measured design (%s): N = %d cycles, lambda %.0e, the deployed target rule; the selection above gives N = %d, lambda %.0e\n', ...
        PK.name, PK.N, PK.lambda, NS(a), LAMBDA(b));
    a = find(NS == PK.N); b = find(LAMBDA == PK.lambda);
    assert(isscalar(a) && isscalar(b), 'select_fusion:pick_grid', 'the measured N %d or lambda %g is not on the grid', PK.N, PK.lambda);
    assert(strcmp(PK.target_age, 'N'), 'select_fusion:pick_target', 'only the deployed target rule was measured');
    assert(isfield(PK, 'latch') && isscalar(PK.latch) && islogical(PK.latch), 'select_fusion:pick_latch', ...
        'the measured design names no latch state');
    TA = struct('target_age', NS(a));
end
N = NS(a); lambda = LAMBDA(b);
Z = ZN{a}; clear ZN
val_target = fusion_target(y, va.run, va.pos, N, classes, TA);
fprintf('Frames judged by their window: path-loss onsets %d, WLAN frames without a packet as benign_interference %d (of %d none frames)\n', ...
    sum(val_target ~= y & val_target == ip), sum(val_target ~= y & val_target == ib), sum(y == find(strcmp(classes, 'none'))));
pc0 = oof{a, b}; clear oof

%% 2. The fusion's further columns, each against the fusion without it (FUSION_REV)
cues = []; pick = 1; PV = {pc0}; Zf = Z; ft = val_target; vr = (1:numel(y))';
if REV
    fit = va; fit.y = y; fit.P = P; foldf = fold; pf0 = pc0; sb = 62;
    if ~isempty(PK) && ~ENL, pf0 = oof_fit(Zf, ft, foldf, C, lambda); end   % the base on the pick's own target
    if ENL                                               % the enlarged fit set (fit_sets.m)
        [fit, finfo] = fit_sets(fit, S.splits.test, D.net, classes);
        fit.feat_names = va.feat_names;
        for k = 1:numel(finfo), fprintf('Fit set: %s, %d frames, %d sub-runs\n', finfo(k).name, finfo(k).frames, finfo(k).subruns); end
        vr = find(fit.set == 1);
        Zf = fuse_classes('windows', fit, fit.P, N);
        assert(isequal(Zf(vr, :), Z), 'select_fusion: the validation rows of the fit set differ');
        ft = fusion_target(fit.y, fit.run, fit.pos, N, classes, TA);
        ru = unique(fit.run); rf = RandStream('mt19937ar', 'Seed', 9101);
        fr = mod(randperm(rf, numel(ru)), K) + 1; [~, ir] = ismember(fit.run, ru); foldf = fr(ir)';
        pf0 = oof_fit(Zf, ft, foldf, C, lambda); sb = 9102;
    end
    [bin, ~] = kpi_ebno(fit, ft, classes);
    yb = argmax(pf0); thr = kpi1_thr(ft, yb, bin, classes);
    low = false(numel(ft), 1); if isfield(fit, 'k_db'), low = double(fit.k_db(:)) <= 0; end
    B = fusion_adopt('boot', fit.run, 1000, sb);
    if ~isempty(PK)                                      % the measured design and its rule check
        cues = PK.cues;
        XP = fuse_classes('extra', fit, N, cues);
        PV = {oof_cols(Zf, ft, foldf, C, lambda, fit, N, false, {XP}, 1)}; pick = 1;
        GP = fusion_adopt('paired', ft, yb, argmax(PV{1}), bin >= thr, low, classes, B);
        fprintf(['The measured design %s against none at N = %d, lambda %.0e, out of fold over %d frames (KPI 1 threshold %g dB): ' ...
            'every frame %+.2f [%+.2f, %+.2f], above the threshold %+.2f [%+.2f, %+.2f], clean as a threat %+.2f [%+.2f, %+.2f], ' ...
            'clean as a lost branch %+.2f [%+.2f, %+.2f]; F1 antenna_fault %+.2f [%+.2f, %+.2f], airframe_shadowing %+.2f ' ...
            '[%+.2f, %+.2f]; at K <= 0 dB %+.2f [%+.2f, %+.2f], %+.2f [%+.2f, %+.2f] -> rule %s\n'], PK.name, N, lambda, numel(ft), ...
            thr, GP.all, GP.above, GP.cl, GP.lb, GP.fault, GP.shad, GP.fault_low, GP.shad_low, yn_txt(fusion_adopt('branch', GP)));
        rule_ok = fusion_adopt('branch', GP);
        if ENL && ~RULE_LOG && ~rule_ok, fusion_nogo('write', PK, GP, 'rule'); end   % the kept fusion stays; B3r may read it once
        assert(RULE_LOG || rule_ok, 'select_fusion:pick_rule', ...
            'the measured design %s fails the adoption rule on this fit set: no-go (docs/d91_fuse.md)', PK.name);
        if ~rule_ok                                      % the smoke's deploy path only: saved so the stages after it run
            fprintf('SMOKE (FUSION_RULE_LOG): the rule fails on the smoke data; saved all the same, no no-go record\n');
            GP.rule_logged_only = true;
        end
        Zf = [Zf, XP]; clear XP
    else
        OPT = {struct('iso', true), struct('glr', true), struct('held', true), struct('post', true), ...
            struct('iso', true, 'glr', true, 'held', true, 'post', true)};
        V = {'none', 'cfar', 'iso', 'glr', 'held', 'post', 'branch evidence'};
        XB = cellfun(@(o) fuse_classes('extra', fit, N, o), OPT, 'UniformOutput', false);
        PV = cell(1, numel(V)); PV{1} = pf0; TH = nan(K, 3);
        for v = 2:numel(V)
            [PV{v}, T] = oof_cols(Zf, ft, foldf, C, lambda, fit, N, v == 2, XB, v - 2);
            if v == 2, TH = T; end
        end
        G = cell(1, numel(V));
        for v = 2:numel(V), G{v} = fusion_adopt('paired', ft, yb, argmax(PV{v}), bin >= thr, low, classes, B); end
        [pick, bs] = fusion_adopt('choose', G);
        if pick == 0                                         % the idle-time columns with the adopted branch variant
            [PV{end + 1}, ~] = oof_cols(Zf, ft, foldf, C, lambda, fit, N, true, XB, bs - 2);
            V{end + 1} = ['cfar and ' V{bs}];
            G{end + 1} = fusion_adopt('paired', ft, yb, argmax(PV{end}), bin >= thr, low, classes, B);
            pick = fusion_adopt('combo', G(1:end - 1), bs, G{end});
        end
        fprintf(['Further columns at N = %d, lambda %.0e, out of fold over %d frames, against none (points, 95%% bootstrap over ' ...
            'sub-runs; KPI 1 threshold of the fusion without them %g dB):\n'], N, lambda, numel(ft), thr);
        for v = 2:numel(V)
            fprintf(['  %-26s every frame %+.2f [%+.2f, %+.2f], above the threshold %+.2f [%+.2f, %+.2f], clean as a threat %+.2f ' ...
                '[%+.2f, %+.2f], clean as a lost branch %+.2f [%+.2f, %+.2f]; F1 antenna_fault %+.2f [%+.2f, %+.2f], ' ...
                'airframe_shadowing %+.2f [%+.2f, %+.2f]; at K <= 0 dB %+.2f [%+.2f, %+.2f], %+.2f [%+.2f, %+.2f]\n'], V{v}, G{v}.all, ...
                G{v}.above, G{v}.cl, G{v}.lb, G{v}.fault, G{v}.shad, G{v}.fault_low, G{v}.shad_low);
        end
        fprintf('  cfar thresholds per training folds [dB] (crest T1, spread T2, median crest): %s\n', mat2str(TH, 3));
        fprintf('  adopted: cfar %s; branch variants %s -> the fusion''s further columns: %s\n', yn_txt(fusion_adopt('cfar', G{2})), ...
            strjoin(cellfun(@(n, d) sprintf('%s %s', n, yn_txt(fusion_adopt('branch', d))), V(3:7), G(3:7), 'UniformOutput', false), ', '), V{pick});
        if pick > 1
            cues = struct('cfar', [], 'iso', false, 'glr', false, 'held', false, 'post', false);
            if pick == 2 || pick == 8, cues.cfar = cfar_thr(fit, true(numel(ft), 1)); end
            b = 0; if pick >= 3 && pick <= 7, b = pick - 2; elseif pick == 8, b = bs - 2; end
            if b > 0, for f = fieldnames(OPT{b})', cues.(f{1}) = true; end, end
            Zf = [Zf, fuse_classes('extra', fit, N, cues)];
            if ~isempty(cues.cfar), fprintf('  clean gaps of the fit set: T1 %.2f dB, T2 %.2f dB, median crest %.2f dB\n', cues.cfar); end
        end
    end
    PV{pick} = PV{pick}(vr, :);                          % the validation frames' out-of-fold reading
end
val_probs_oof = PV{pick};
FM = fuse_classes('fit', Zf, ft, C, lambda);
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
if ~isempty(PK)                                          % the measured state, not chosen again
    fprintf('The measured design deploys latch %d, its measured state; validation out of fold would choose latch %d\n', PK.latch, FM.latch);
    FM.latch = PK.latch;
end
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
if REV
    fit_name = 'validation';
    if exist('FUSION_FIT', 'var') && strcmp(FUSION_FIT, 'enlarged'), fit_name = 'enlarged'; end
    fusion_rev = fusion_rev_id(fit_name);                % B3r reads the fourth test set only with fusion_rev_id('enlarged')
    save('data/fusion.mat', 'cvy', 'cvo', 'fusion_rev', '-append');
    if ~isempty(PK)
        deployed_pick = PK; deployed_pick.check = GP;
        deployed_pick.check.latch_val = struct('macro_f1_latched', mf_latch, 'macro_f1_fused', mf_fused);   % validation out of fold
        if ~isempty(kept_base), deployed_pick.check.kept = kept_base; end   % the fusion it replaced, the rule's base
        save('data/fusion.mat', 'deployed_pick', '-append');
    end
end
fusion_nogo('clear');                                    % an earlier no-go record no longer names the fusion on disk
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

function [pc, T] = oof_cols(Z, yt, fold, C, lambda, fit, N, cf, XB, b)
% Out-of-fold probabilities with the further columns: the idle time's (cf, thresholds from
% each training folds' clean gaps) and the branch variant b (XB{b}, 0 none).
pc = zeros(numel(yt), C); T = nan(max(fold), 3);
for k = 1:max(fold)
    tr = fold ~= k; te = fold == k;
    X = zeros(numel(yt), 0);
    if cf, T(k, :) = cfar_thr(fit, tr); X = fuse_classes('extra', fit, N, struct('cfar', T(k, :))); end
    if b > 0, X = [X, XB{b}]; end %#ok<AGROW>
    FMv = fuse_classes('fit', [Z(tr, :), X(tr, :)], yt(tr), C, lambda);
    pc(te, :) = fuse_classes('apply', FMv, [Z(te, :), X(te, :)]);
end
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
