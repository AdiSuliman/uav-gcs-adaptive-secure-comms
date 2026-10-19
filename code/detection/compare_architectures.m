%% COMPARE_ARCHITECTURES - Detector architectures on the same splits
% Proposal, mitigation 6: hybrid network against spectrogram only and features only.
% Following the multimodal comparison reported by Tariq et al. (telemetry MLP,
% spectrogram CNN, fused), the production hybrid detector is compared with the
% same network seeing only one input: spectrogram only (link features held at
% zero) and link features only (spectrogram held at zero). A constant input
% leaves its branch a fixed bias, so each variant is the single-branch network
% with the same training schedule (train_hybrid_net.m), splits and seed; the spectrogram's
% time and frequency masking is off where the spectrogram is held at zero.
% Classical baselines on the same link features (the traditional classifiers of
% UAV intrusion detection, Papathanasiou et al. [2]; a random forest on spectral
% descriptors, Barajas et al.): a random forest and a kernel SVM (one-vs-one,
% random-feature Gaussian kernel on the z-scored features), each tuned by a small grid on
% the validation split, as the networks stop early there: the forest's leaf size and
% predictors per split (100 trees in the grid, 200 in the fit), the SVM's kernel scale
% around sqrt(p) (MATLAB's kernel is exp(-|x - y|^2 / s^2), so s = sqrt(p) is LIBSVM's
% default gamma = 1/p, Hsu, Chang & Lin) and its box constraint. Every variant is a
% per-frame classifier: trained and read on the frame rule's labels (frame_labels.m).
% Selection basis (validation only): each variant's per-frame validation outputs through the
% deployed temporal fusion (fuse_classes.m) with select_fusion.m's N and lambda fixed
% (data/fusion.mat), fitted and read out of fold over select_fusion's 5 folds by sub-run
% (seed 61) on the per-cycle targets (fusion_target.m), as KPI 1 reads the system's class,
% with the deployed fusion's further columns and target rule (FM.cues, FM.target_age);
% beside it the latched cause of a lost branch (latch_runs.m), its threshold chosen on the
% other folds' sub-runs as select_fusion.m chooses it, the monitor's class when the deployed
% fusion latches (FM.latch, stated in the report; the deployed FM.os_thr on the test set). The hybrid's
% validation outputs come from the epoch chosen there, so the fused test reading is the
% unbiased check. The forest and the SVM are unweighted while the networks' loss is
% inverse-frequency weighted, so accuracy follows the 'none' frames; macro-F1 is the
% comparable figure.
% Test frames: the second test set (data/splits_fresh.mat, build_fresh_test) when it exists;
% else the test split of data/splits.mat, labelled as a second reading of frames read
% before. Every test column is a reading, not a selection: the per-frame macro-F1, per
% Eb/N0 on the KPI 1 bins (kpi_ebno.m), the frames received below the grid as the share read
% right (one class, 'none', holds them), and the fused class with the fusion refitted on
% each variant's own validation outputs.
% With the deployed fusion revision the test frames are in its fit set (fusion_reading.m): the
% set's name then carries 'in-sample (fit set of the deployed fusion)'.
% Output: results/architecture_comparison.txt; results/architecture_comparison.mat (arch: the
% set, the fusion it was read with, the in-sample label, the test readings) for the report export

close all; clc;
fprintf('=== Detector architecture comparison ===\n\n');
S = load('data/splits.mat', 'splits'); sp = S.splits; clear S
classes = sp.classes; C = numel(classes);
cls_names = cellstr(string(classes(:)'));
set_name = 'test split of the dataset (a second reading of frames read before)';
if isfile('data/splits_fresh.mat')
    Sf = load('data/splits_fresh.mat', 'splits');
    assert(isequal(Sf.splits.norm, sp.norm), 'compare_architectures: the second test set has another normalization');
    sp.test = Sf.splits.test; clear Sf
    set_name = 'second test set (data/splits_fresh.mat)';
end
rd = fusion_reading('');                                % in-sample when the set is in the deployed fusion's fit set
if ~isempty(rd.sample), set_name = [set_name ', ' rd.sample]; end
fz = isfile('data/fusion.mat') && isfield(sp.val, 'pos') && isfield(sp.test, 'pos');
if fz
    FZ = load('data/fusion.mat', 'FM', 'N', 'lambda');
    os_thr = onset_shape('threshold', FZ.FM); latch_on = onset_shape('on', FZ.FM); cues = fuse_classes('cues', FZ.FM);
    sp.val.feat_names = sp.norm.feat_names; sp.test.feat_names = sp.norm.feat_names;
    yv_cyc = double(sp.val.Y(:)); yt_cyc = double(sp.test.Y(:));            % per-cycle labels (the fusion's)
    tv = fusion_target(yv_cyc, sp.val.run, sp.val.pos, FZ.N, cls_names, FZ.FM);
    tt = fusion_target(yt_cyc, sp.test.run, sp.test.pos, FZ.N, cls_names, FZ.FM);
    runs = unique(sp.val.run);                                              % select_fusion.m's folds
    rs = RandStream('mt19937ar', 'Seed', 61);
    fold_of_run = mod(randperm(rs, numel(runs)), 5) + 1;
    [~, ir] = ismember(sp.val.run, runs); fold = fold_of_run(ir)';
    tf = fold_thresholds(sp.val, yv_cyc, cls_names, runs, fold_of_run);   % the latch's threshold of every fold
    mon = ternary(latch_on, 'fused+latch (FM.latch = true)', 'fused class (FM.latch = false)');
end
sp.train = frame_labels(sp.train); sp.val = frame_labels(sp.val); sp.test = frame_labels(sp.test);
V = struct('name', {'hybrid (spectrogram + link features)', 'spectrogram only (CNN)', 'link features only (MLP)', ...
    'link features only, random forest', 'link features only, kernel SVM'}, ...
    'mask', {'', 'feat', 'spec', '', ''}, 'kind', {'net', 'net', 'net', 'rf', 'svm'});
nV = numel(V);
eb = kpi_ebno(sp.test, sp.test.Y, classes); ebs = unique(eb(~isnan(eb))); beyond = isnan(eb');
PE = nan(nV, numel(ebs)); BY = nan(nV, 1);
TT = cell(nV, 1); VA = nan(nV, 4); FT = nan(nV, 2); FV = nan(nV, C); tuned = repmat({''}, nV, 1);
yt = double(sp.test.Y(:))'; yv = double(sp.val.Y(:))';
Xtr = double(sp.train.feats); Xva = double(sp.val.feats); Xte = double(sp.test.feats); ytr = double(sp.train.Y(:));
p = size(Xtr, 2);
for v = 1:nV
    rng(42, 'twister');
    fprintf('Training: %s\n', V(v).name);
    switch V(v).kind
        case 'net'
            tr = masked(sp.train, V(v).mask); va = masked(sp.val, V(v).mask); te = masked(sp.test, V(v).mask);
            opts = struct('verbose', false);
            if strcmp(V(v).mask, 'spec'), opts.augment = false; end   % no masking of an image held at zero
            net = train_hybrid_net(tr, va, classes, opts);
            Pv = cnn_scores(net, va.X, va.feats')'; Pt = cnn_scores(net, te.X, te.feats')';
            clear tr va te net
        case 'rf'
            G = [1 5 20; round(sqrt(p)) round(sqrt(p)) round(sqrt(p))]; G = [G, [1 5 20; round(p / 3) round(p / 3) round(p / 3)]];
            f1 = zeros(1, size(G, 2));
            for g = 1:size(G, 2)
                rng(42, 'twister');
                mdl = TreeBagger(100, Xtr, ytr, 'Method', 'classification', 'MinLeafSize', G(1, g), 'NumPredictorsToSample', G(2, g));
                f1(g) = mean(per_class_f1(yv, str2double(predict(mdl, Xva))', C));
                fprintf('  random forest, leaf %2d, %2d predictors per split: validation macro-F1 %.2f%%\n', G(:, g), 100 * f1(g));
            end
            [~, g] = max(f1);
            rng(42, 'twister');
            mdl = TreeBagger(200, Xtr, ytr, 'Method', 'classification', 'MinLeafSize', G(1, g), 'NumPredictorsToSample', G(2, g));
            Pv = rf_probs(mdl, Xva, C); Pt = rf_probs(mdl, Xte, C);
            tuned{v} = sprintf('leaf %d, %d predictors per split (100-tree grid on validation; 200 trees)', G(:, g));
            clear mdl
        case 'svm'
            mu = mean(Xtr, 1); sd = max(std(Xtr, 0, 1), 1e-6);
            Ztr = (Xtr - mu) ./ sd; Zva = (Xva - mu) ./ sd; Zte = (Xte - mu) ./ sd;
            G = [sqrt(p) * [0.5 1 2 0.5 1 2]; 1 1 1 10 10 10];
            f1 = zeros(1, size(G, 2)); M = cell(1, size(G, 2));
            for g = 1:size(G, 2)
                rng(42, 'twister');
                M{g} = fitcecoc(Ztr, ytr, 'Learners', templateKernel('Learner', 'svm', 'KernelScale', G(1, g), ...
                    'BoxConstraint', G(2, g)));
                f1(g) = mean(per_class_f1(yv, predict(M{g}, Zva)', C));
                fprintf('  kernel SVM, scale %.2f, box constraint %g: validation macro-F1 %.2f%%\n', G(:, g), 100 * f1(g));
            end
            [~, g] = max(f1);
            [~, nl] = predict(M{g}, Zva); Pv = soft(nl);
            [~, nl] = predict(M{g}, Zte); Pt = soft(nl);
            tuned{v} = sprintf('kernel scale %.2f (sqrt(p) = %.2f), box constraint %g (grid on validation)', G(1, g), sqrt(p), G(2, g));
            clear M Ztr Zva Zte
    end
    [~, yp] = max(Pt, [], 2); yp = yp';
    [~, yq] = max(Pv, [], 2); yq = yq';
    f1 = per_class_f1(yt, yp, C);
    TT{v} = [100 * mean(yp == yt), 100 * mean(f1), 100 * f1];
    VA(v, 1) = 100 * mean(per_class_f1(yv, yq, C));
    for e = 1:numel(ebs), m = eb' == ebs(e); PE(v, e) = 100 * macro_present(yt(m), yp(m), C); end
    if any(beyond), BY(v) = 100 * mean(yp(beyond) == yt(beyond)); end
    if fz
        [VA(v, 2:3), FV(v, :)] = fused_oof(sp.val, Pv, FZ.N, FZ.lambda, tv, fold, cls_names, tf, cues);
        Zv = fuse_classes('windows', sp.val, Pv, FZ.N, cues); Zt = fuse_classes('windows', sp.test, Pt, FZ.N, cues);
        FMv = fuse_classes('fit', Zv, tv, C, FZ.lambda);
        pt = fuse_classes('apply', FMv, Zt); [~, kf] = max(pt, [], 2);
        [~, kl] = max(latch_runs(pt, sp.test.run, sp.test.pos, sp.test.gain_ant, cls_names, os_thr), [], 2);
        FT(v, :) = 100 * [mean(per_class_f1(tt', kf', C)), mean(per_class_f1(tt', kl', C))];
    end
end

rep = {'=== DETECTOR ARCHITECTURES ===', sprintf(['Generated: %s | same splits, schedule and seed | validation %d frames; ' ...
    'test frames %d: %s'], datestr(now), numel(yv), numel(yt), set_name), ''};
rep{end+1} = '--- Selection basis: the validation split (macro-F1 %) ---';
if fz
    rep{end+1} = sprintf(['Deployed monitor: %s (set by B2F, select_fusion.m: chosen on validation, or the measured ' ...
        'pick''s state).'], mon);
    rep{end+1} = sprintf(['%-40s %10s %14s %14s   (fusion N = %d cycles, lambda %.0e fixed; out of fold over select_fusion''s ' ...
        '5 folds by sub-run; per-cycle targets; the latch''s threshold chosen on the other folds)'], 'architecture', ...
        'per frame', 'fused (OOF)', latch_col(latch_on), FZ.N, FZ.lambda);
    for v = 1:nV
        rep{end+1} = sprintf('%-40s %9.2f%% %13.2f%% %13.2f%%', V(v).name, VA(v, 1:3)); %#ok<SAGROW>
    end
    rep{end+1} = sprintf('%-40s  %s', 'fused per class (OOF)', strjoin(cellfun(@(c) sprintf('%8.8s', c), cls_names, 'UniformOutput', false), ' '));
    for v = 1:nV
        rep{end+1} = sprintf('%-40s %s', V(v).name, sprintf('%8.1f ', FV(v, :))); %#ok<SAGROW>
    end
    rep{end+1} = sprintf(['fused+latch: the monitor''s class when the deployed fusion latches the cause of a lost branch ' ...
        '(select_fusion.m); here %s.'], ternary(latch_on, 'it latches', 'it does not: the fused class is the monitor''s'));
else
    rep{end+1} = sprintf('%-40s %10s   (no fusion or frame positions: per frame only)', 'architecture', 'per frame');
    for v = 1:nV, rep{end+1} = sprintf('%-40s %9.2f%%', V(v).name, VA(v, 1)); end %#ok<SAGROW>
end
for v = find(~cellfun(@isempty, tuned))'
    rep{end+1} = sprintf('%s: %s', V(v).name, tuned{v}); %#ok<SAGROW>
end
rep{end+1} = 'The hybrid''s validation outputs come from the epoch chosen on validation (a slight optimistic bias): the fused test reading below is the unbiased check.';
rep{end+1} = '';
rep{end+1} = sprintf('--- Readings, not selections: %s ---', set_name);
rep{end+1} = sprintf('%-40s %9s %9s  %s', 'per frame', 'accuracy', 'macro-F1', strjoin(cellfun(@(c) sprintf('%8.8s', c), ...
    cls_names, 'UniformOutput', false), ' '));
for v = 1:nV
    rep{end+1} = sprintf('%-40s %8.2f%% %8.2f%%  %s', V(v).name, TT{v}(1:2), sprintf('%7.1f%% ', TT{v}(3:end))); %#ok<SAGROW>
end
rep{end+1} = 'Accuracy follows the ''none'' frames (the forest and the SVM are unweighted, the networks inverse-frequency weighted): macro-F1 is the comparable figure.';
if fz
    rep{end+1} = sprintf('Deployed monitor: %s.', mon);
    rep{end+1} = sprintf(['%-40s %14s %14s   (the fusion refitted on each variant''s validation outputs; the latch at the ' ...
        'deployed threshold %+.2f)'], 'fused (macro-F1)', 'fused', latch_col(latch_on), os_thr);
    for v = 1:nV
        rep{end+1} = sprintf('%-40s %13.2f%% %13.2f%%', V(v).name, FT(v, :)); %#ok<SAGROW>
    end
end
rep{end+1} = sprintf('Per-frame macro-F1 per Eb/N0 [dB] %s%s', sprintf('%8g', ebs), ternary(any(beyond), sprintf(['   beyond ' ...
    'the grid: %d frames, %s, read right'], sum(beyond), strjoin(unique(cls_names(yt(beyond))), '/')), ''));
for v = 1:nV
    rep{end+1} = sprintf('%-40s%s%s', V(v).name, sprintf('%7.1f%%', PE(v, :)), ternary(any(beyond), sprintf('   %7.1f%%', BY(v)), '')); %#ok<SAGROW>
end
fid = fopen('results/architecture_comparison.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
arch = struct('test_set', set_name, 'fusion_rev', rd.fusion_rev, 'fusion_state', rd.state, 'sample', rd.sample, ...
    'names', {{V.name}}, 'test_acc_macro_f1_pct', cell2mat(cellfun(@(t) t(1:2), TT(:), 'UniformOutput', false)), ...
    'test_fused_pct', []); %#ok<NASGU>
if fz, arch.test_fused_pct = FT; end
save('results/architecture_comparison.mat', 'arch');
clear sp

function [mf, f1] = fused_oof(va, P, N, lambda, tv, fold, classes, tf, cues)
% The fused class out of fold on the validation split (select_fusion.m's folds, N and
% lambda fixed): macro-F1 % fused and with the latched cause of a lost branch (each fold
% latched at tf(fold), its threshold chosen on the other folds), and the fused per-class F1 %.
C = size(P, 2);
Z = fuse_classes('windows', va, P, N, cues);
pc = zeros(size(P)); pl = pc;
for k = 1:max(fold)
    m = fold == k;
    FM = fuse_classes('fit', Z(~m, :), tv(~m), C, lambda);
    pc(m, :) = fuse_classes('apply', FM, Z(m, :));
    pl(m, :) = latch_runs(pc(m, :), va.run(m), va.pos(m), va.gain_ant(m, :), classes, tf(k));
end
[~, kf] = max(pc, [], 2);
[~, kl] = max(pl, [], 2);
f1 = 100 * per_class_f1(tv', kf', C);
mf = [mean(f1), 100 * mean(per_class_f1(tv', kl', C))];
end

function tf = fold_thresholds(va, y, classes, runs, fold_of_run)
% The onset shape's threshold of every fold, chosen on the other folds' validation sub-runs
% of the two lost-branch classes as select_fusion.m chooses it (onset_shape.m 'events', 'choose').
iB = [find(strcmp(classes, 'antenna_fault')), find(strcmp(classes, 'airframe_shadowing'))];
heal = decision_config().heal; og = []; oy = []; orun = [];
if numel(iB) == 2
    for r = runs(:)'
        ix = find(va.run == r); [~, o] = sort(va.pos(ix)); ix = ix(o);
        b = find(ismember(iB, y(ix)), 1);
        if isempty(b), continue; end
        og(end+1) = onset_shape('events', va.gain_ant(ix, :), find(y(ix) == iB(b), 1), heal); oy(end+1) = b; orun(end+1) = r; %#ok<AGROW>
    end
end
[~, ko] = ismember(orun, runs); ko = fold_of_run(ko);
tf = arrayfun(@(k) onset_shape('choose', og(ko ~= k), oy(ko ~= k)), 1:max(fold_of_run));
end

function t = latch_col(on)
t = 'fused+latch'; if ~on, t = 'fused+latch (not deployed)'; end
end

function P = rf_probs(mdl, X, C)
% The forest's class vote fractions, columns in class order 1..C.
[~, s] = predict(mdl, X);
P = zeros(size(X, 1), C);
P(:, str2double(mdl.ClassNames)) = s;
end

function P = soft(s)
% Class probabilities of the SVM's negated losses (softmax).
s = s - max(s, [], 2);
P = exp(s) ./ sum(exp(s), 2);
end

function P = masked(P, what)
switch what
    case 'feat', P.feats = zeros(size(P.feats), 'like', P.feats);
    case 'spec', P.X = zeros(size(P.X), 'like', P.X);
end
end

function f = macro_present(yt, yp, nC)
% Macro-F1 over the classes present among the true labels.
f1 = per_class_f1(yt, yp, nC);
f = mean(f1(ismember(1:nC, yt)));
end

function f1 = per_class_f1(yt, yp, nC)
f1 = zeros(1, nC);
for c = 1:nC
    tp = sum(yp == c & yt == c); fp = sum(yp == c & yt ~= c); fn = sum(yp ~= c & yt == c);
    f1(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
