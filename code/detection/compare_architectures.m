%% COMPARE_ARCHITECTURES - Detector architectures on the same splits
% Proposal, mitigation 6: hybrid network against spectrogram only and features only.
% Following the multimodal comparison reported by Tariq et al. (telemetry MLP,
% spectrogram CNN, fused), the production hybrid detector is compared with the
% same network seeing only one input: spectrogram only (link features held at
% zero) and link features only (spectrogram held at zero). A constant input
% leaves its branch a fixed bias, so each variant is the single-branch network
% with the same training schedule (train_hybrid_net.m), splits and seed.
% Classical baselines on the same link features (the traditional classifiers of
% UAV intrusion detection, Papathanasiou et al. [2]; a random forest on spectral
% descriptors, Barajas et al.): a random forest (200 trees) and a kernel SVM
% (one-vs-one, random-feature Gaussian kernel), default settings, no tuning.
% Test frames: the second test set (data/splits_fresh.mat, build_fresh_test) when it exists;
% else the test split of data/splits.mat, labelled as a second reading of frames read
% before. Macro-F1 per Eb/N0 on the KPI 1 bins (kpi_ebno.m, per-frame labels), the frames
% received below the grid in their own column.
% Output: results/architecture_comparison.txt

close all; clc;
fprintf('=== Detector architecture comparison ===\n\n');
S = load('data/splits.mat', 'splits'); sp = S.splits; clear S
classes = sp.classes;
set_name = 'test split of the dataset (a second reading of frames read before)';
if isfile('data/splits_fresh.mat')
    Sf = load('data/splits_fresh.mat', 'splits');
    assert(isequal(Sf.splits.norm, sp.norm), 'compare_architectures: the second test set has another normalization');
    sp.test = Sf.splits.test; clear Sf
    set_name = 'second test set (data/splits_fresh.mat)';
end
V = struct('name', {'hybrid (spectrogram + link features)', 'spectrogram only (CNN)', 'link features only (MLP)', ...
    'link features only, random forest', 'link features only, kernel SVM'}, ...
    'mask', {'', 'feat', 'spec', '', ''}, 'kind', {'net', 'net', 'net', 'rf', 'svm'});
rep = {'=== DETECTOR ARCHITECTURES ===', ...
    sprintf('Generated: %s | same splits, schedule and seed | test frames %d: %s', datestr(now), size(sp.test.X, 4), set_name), ''};
hdr = sprintf('%-40s %9s %9s  %s', 'architecture', 'accuracy', 'macro-F1', strjoin(cellfun(@(c) sprintf('%8.8s', c), ...
    cellstr(string(classes(:)')), 'UniformOutput', false), ' '));
rep{end+1} = hdr;
eb = kpi_ebno(sp.test, sp.test.Y, classes); ebs = unique(eb(~isnan(eb)));
PE = zeros(numel(V), numel(ebs) + any(isnan(eb)));
for v = 1:numel(V)
    rng(42, 'twister');
    fprintf('Training: %s\n', V(v).name);
    yt = double(sp.test.Y(:))';
    switch V(v).kind
        case 'net'
            tr = masked(sp.train, V(v).mask); va = masked(sp.val, V(v).mask); te = masked(sp.test, V(v).mask);
            net = train_hybrid_net(tr, va, classes, struct('verbose', false));
            [~, yp] = max(cnn_scores(net, te.X, te.feats'), [], 1);
        case 'rf'
            mdl = TreeBagger(200, double(sp.train.feats), double(sp.train.Y(:)), 'Method', 'classification');
            yp = str2double(predict(mdl, double(sp.test.feats)))';
        case 'svm'
            mu = mean(double(sp.train.feats), 1); sd = max(std(double(sp.train.feats), 0, 1), 1e-6);
            mdl = fitcecoc((double(sp.train.feats) - mu) ./ sd, double(sp.train.Y(:)), 'Learners', templateKernel('Learner', 'svm'));
            yp = predict(mdl, (double(sp.test.feats) - mu) ./ sd)';
    end
    f1 = per_class_f1(yt, yp, numel(classes));
    for e = 1:numel(ebs), m = eb' == ebs(e); PE(v, e) = macro_present(yt(m), yp(m), numel(classes)); end
    if any(isnan(eb)), m = isnan(eb'); PE(v, end) = macro_present(yt(m), yp(m), numel(classes)); end
    rep{end+1} = sprintf('%-40s %8.2f%% %8.2f%%  %s', V(v).name, 100 * mean(yp == yt), 100 * mean(f1), ...
        strjoin(arrayfun(@(x) sprintf('%7.1f%%', 100 * x), f1, 'UniformOutput', false), ' ')); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Macro-F1 per Eb/N0 [dB] %s%s', sprintf('%8g', ebs), repmat(sprintf('  %s', 'beyond'), 1, any(isnan(eb))));
for v = 1:numel(V)
    rep{end+1} = sprintf('%-40s%s', V(v).name, sprintf('%7.1f%%', 100 * PE(v, :))); %#ok<SAGROW>
end
fid = fopen('results/architecture_comparison.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('\n%s\n', rep{:});
clear sp tr va te

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
