%% B2 - TRAIN HYBRID DETECTOR: CNN (spectrogram) + FC (13 link features) -> softmax
% Training in train_hybrid_net.m (shared with eval_ood_detection.m). After
% training, the feature-space unknown-threat models (Mahalanobis on the hidden
% layers, isolation forest on the link features) are fitted (fit_ood_model.m).
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
ood = fit_ood_model(net, sp.train, classes, sp.val);
fprintf('Production score: Mahalanobis of layer %s (D60); ensemble weights for comparison (bias, %s): %s\n', ...
    ood.layers{end}, strjoin(ood.layers, ', '), mat2str(ood.w, 3));

if ~exist('data', 'dir'), mkdir('data'); end
trained_at = now;                                  % the file itself is updated later by eval_ood_detection.m (ood.score)
save('data/trained_detector.mat', 'net', 'info', 'classes', 'ood', 'trained_at', '-v7.3');
fprintf('Saved data/trained_detector.mat\n');

fig = figure('Position', [100 100 900 380], 'Color', 'w');
subplot(1, 2, 1); plot(info.trainLoss, 'b-', 'LineWidth', 1.5); grid on;
xlabel('Epoch'); ylabel('Cross-entropy'); title('Training loss');
subplot(1, 2, 2); plot(100*info.valAcc, 'r-', 'LineWidth', 1.5); hold on; grid on;
xline(info.bestEpoch, '--k', sprintf('best (ep %d)', info.bestEpoch));
xlabel('Epoch'); ylabel('Accuracy (%)'); title(sprintf('Validation accuracy (best %.1f%%)', 100*info.bestValAcc));
sgtitle(sprintf('B2: Hybrid detector (%d link features, time/frequency masking, cosine LR)', size(sp.train.feats, 2)));
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/training_curves.png'); close(fig);
fprintf('=== B2 Complete ===\n');
clear S sp   % large arrays; main.m runs the stages in one workspace
