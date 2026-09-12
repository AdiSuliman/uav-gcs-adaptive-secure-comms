%% B3 — EVALUATE HYBRID DETECTOR (Test Set)
close all; clc;fprintf('=== B3: Test Evaluation ===\n\n');

%% 1. Load data and model
fprintf('Loading test data and trained model...\n');
S = load('data/splits.mat');
sp = S.splits;
Y_test = sp.test.Y;

load('data/trained_detector.mat', 'net', 'classes');

%% 2. Prepare test data for dlnetwork
X_test_spec = dlarray(single(sp.test.X), 'SSCB');
X_test_feat = dlarray(single(sp.test.feats)', 'CB');

if canUseGPU
    X_test_spec = gpuArray(X_test_spec);
    X_test_feat = gpuArray(X_test_feat);
end

%% 3. Inference
fprintf('Running inference on %d test samples...\n', numel(Y_test));
Y_pred_prob = predict(net, X_test_spec, X_test_feat);
[~, max_idx] = max(extractdata(Y_pred_prob), [], 1);

Y_pred = categorical(classes(max_idx)', classes);

Y_test = Y_test(:);
Y_pred = Y_pred(:);

%% 4. Metrics & Confusion Matrix
fprintf('\nCalculating metrics...\n');
conf_mat = confusionmat(Y_test, Y_pred);
precision = diag(conf_mat) ./ sum(conf_mat, 1)';
recall = diag(conf_mat) ./ sum(conf_mat, 2);
f1_scores = 2 .* (precision .* recall) ./ (precision + recall);
macro_f1 = mean(f1_scores, 'omitnan');

fprintf('\n--- Test Set Metrics ---\n');
fprintf('Overall Accuracy: %.2f%%\n', 100 * sum(Y_test == Y_pred) / numel(Y_test));
fprintf('Macro-F1 Score:   %.2f%%\n\n', 100 * macro_f1);

for i = 1:numel(classes)
    fprintf('Class %18s: Acc = %5.1f%%, F1 = %5.1f%%\n', ...
        string(classes(i)), 100*recall(i), 100*f1_scores(i));
end

fig_cm = figure('Name', 'Confusion Matrix', 'Color', 'w', 'Position', [100 100 700 600]);
cm = confusionchart(Y_test, Y_pred);
cm.Title = 'Hybrid Detector Confusion Matrix (Test Set)';
cm.RowSummary = 'row-normalized';
cm.ColumnSummary = 'column-normalized';
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig_cm, 'results/confusion_matrix.png');

%% 5. Accuracy vs SNR (ערכים אמיתיים בדציבל — denormalized)
% sp.test.feats is z-scored; denormalize column 1 (SNR) back to dB
% using the same train-set mean/std saved in splits.norm
norm_mean = sp.norm.feat_mean(1);
norm_std  = sp.norm.feat_std(1);
snr_real  = sp.test.feats(:, 1) .* norm_std + norm_mean;  % → dB

snr_vals    = round(snr_real);   % snap to nominal sweep points (0,2,4,6,8,10)
unique_snrs = unique(snr_vals);
acc_vs_snr  = zeros(length(unique_snrs), 1);

for i = 1:length(unique_snrs)
    idx = (snr_vals == unique_snrs(i));
    if sum(idx) > 0
        acc_vs_snr(i) = sum(Y_test(idx) == Y_pred(idx)) / sum(idx);
    else
        acc_vs_snr(i) = NaN;
    end
end

fig_snr = figure('Name', 'Accuracy vs SNR', 'Color', 'w');
plot(unique_snrs, acc_vs_snr * 100, '-ob', 'LineWidth', 2, ...
    'MarkerSize', 8, 'MarkerFaceColor', 'b');
grid on;
xlabel('SNR (dB)');
ylabel('Accuracy (%)');
title('Detection Accuracy vs. SNR');
xticks(unique_snrs);
saveas(fig_snr, 'results/accuracy_vs_snr.png');

fprintf('\nSNR breakdown:\n');
for i = 1:length(unique_snrs)
    fprintf('  SNR=%2d dB: %.1f%%\n', unique_snrs(i), 100*acc_vs_snr(i));
end

fprintf('\nEvaluation complete. Saved confusion_matrix.png and accuracy_vs_snr.png to results/.\n');