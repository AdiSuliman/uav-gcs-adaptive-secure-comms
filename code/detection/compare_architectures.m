%% COMPARE_ARCHITECTURES - Detector architectures on the same splits
% Approved proposal, risk 5 mitigation: "compare several model architectures".
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
% Output: results/architecture_comparison.txt

close all; clc;
fprintf('=== Detector architecture comparison (D59) ===\n\n');
S = load('data/splits.mat', 'splits'); sp = S.splits; clear S
classes = sp.classes;
V = struct('name', {'hybrid (spectrogram + link features)', 'spectrogram only (CNN)', 'link features only (MLP)', ...
    'link features only, random forest', 'link features only, kernel SVM'}, ...
    'mask', {'', 'feat', 'spec', '', ''}, 'kind', {'net', 'net', 'net', 'rf', 'svm'});
rep = {'=== DETECTOR ARCHITECTURES, TEST SPLIT (D59) ===', ...
    sprintf('Generated: %s | same splits, schedule and seed; test frames %d', datestr(now), size(sp.test.X, 4)), ''};
hdr = sprintf('%-40s %9s %9s  %s', 'architecture', 'accuracy', 'macro-F1', strjoin(cellfun(@(c) sprintf('%8.8s', c), ...
    cellstr(string(classes(:)')), 'UniformOutput', false), ' '));
rep{end+1} = hdr;
eb = sp.test.ebno(:); ebs = unique(eb);
PE = zeros(numel(V), numel(ebs));
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
    for e = 1:numel(ebs), m = eb' == ebs(e); PE(v, e) = mean(per_class_f1(yt(m), yp(m), numel(classes))); end
    rep{end+1} = sprintf('%-40s %8.2f%% %8.2f%%  %s', V(v).name, 100 * mean(yp == yt), 100 * mean(f1), ...
        strjoin(arrayfun(@(x) sprintf('%7.1f%%', 100 * x), f1, 'UniformOutput', false), ' ')); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Macro-F1 per Eb/N0 [dB] %s', sprintf('%8g', ebs));
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

function f1 = per_class_f1(yt, yp, nC)
f1 = zeros(1, nC);
for c = 1:nC
    tp = sum(yp == c & yt == c); fp = sum(yp == c & yt ~= c); fn = sum(yp ~= c & yt == c);
    f1(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
end
