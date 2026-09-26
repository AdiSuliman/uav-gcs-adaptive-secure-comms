%% B2 - TRAIN HYBRID DETECTOR: CNN (spectrogram) + FC (9 link features) -> softmax (D42)
% Training in train_hybrid_net.m (shared with eval_ood_detection.m). After
% training, the feature-space unknown-threat models (Mahalanobis on the embedding,
% isolation forest on the link features) are fitted on the training split.
%
% Input:  data/splits.mat
% Output: data/trained_detector.mat (net, info, classes, ood)
%         results/training_curves.png

close all; clc;
fprintf('=== B2: Train Hybrid Detector ===\n\n');
S = load('data/splits.mat');
sp = S.splits;
classes = sp.classes;
fprintf('train %d | val %d | test %d | classes %d | features %d (%s)\n', ...
    size(sp.train.X, 4), size(sp.val.X, 4), size(sp.test.X, 4), numel(classes), ...
    size(sp.train.feats, 2), strjoin(sp.norm.feat_names, ', '));
rng(42, 'twister');

[net, info] = train_hybrid_net(sp.train, sp.val, classes);
fprintf('\nBest validation accuracy %.4f at epoch %d\n', info.bestValAcc, info.bestEpoch);

fprintf('Fitting unknown-threat models (Mahalanobis, isolation forest)...\n');
ood = fit_ood_model(net, sp.train, classes);

if ~exist('data', 'dir'), mkdir('data'); end
save('data/trained_detector.mat', 'net', 'info', 'classes', 'ood', '-v7.3');
fprintf('Saved data/trained_detector.mat\n');

fig = figure('Position', [100 100 900 380], 'Color', 'w');
subplot(1, 2, 1); plot(info.trainLoss, 'b-', 'LineWidth', 1.5); grid on;
xlabel('Epoch'); ylabel('Cross-entropy'); title('Training loss');
subplot(1, 2, 2); plot(100*info.valAcc, 'r-', 'LineWidth', 1.5); hold on; grid on;
xline(info.bestEpoch, '--k', sprintf('best (ep %d)', info.bestEpoch));
xlabel('Epoch'); ylabel('Accuracy (%)'); title(sprintf('Validation accuracy (best %.1f%%)', 100*info.bestValAcc));
sgtitle('B2: Hybrid detector (9 link features, SpecAugment, cosine LR)');
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/training_curves.png'); close(fig);
fprintf('=== B2 Complete ===\n');
clear S sp   % large arrays; main.m runs the stages in one workspace
