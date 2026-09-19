%% B3-seq — EVALUATE CNN-LSTM DETECTOR (Test Set)
% Mirrors eval_detector.m's metric computation exactly (confusion matrix,
% precision/recall/F1-macro, accuracy-vs-SNR) so results are directly
% comparable to the CNN-only baseline. Only the inference chain differs
% (four sub-networks: cnn_net -> lstm_cnn_net / feat_lstm_net -> classifier_net
% instead of a single hybrid net).

close all; clc;
fprintf('=== B3-seq: CNN-LSTM Test Evaluation ===\n\n');

%% 1. Load data and models
fprintf('Loading test data and trained CNN-LSTM model...\n');
S = load('data/splits_seq.mat');
sp = S.splits_seq;
Y_test = sp.test.Y;
seq_len = sp.seq_len;

load('data/trained_detector_lstm.mat', 'cnn_net', 'lstm_cnn_net', 'feat_lstm_net', 'classifier_net', 'classes');

%% 2. Prepare test data
% sp.test.X: [128 128 1 seq_len N] | sp.test.feats: [N seq_len nFeat]
X_test_spec = single(sp.test.X);
X_test_feat = single(permute(sp.test.feats, [3 2 1]));   % [nFeat seq_len N]
N_test = size(X_test_spec, 5);

%% 3. Inference (same chain as training: CNN per-frame -> LSTM aggregation -> merge -> classify)
fprintf('Running inference on %d test sequences...\n', N_test);

% CNN features per frame (no gradient needed)
feats_cell = cell(1, seq_len);
for t = 1:seq_len
    sz = size(X_test_spec);
    X_t = reshape(X_test_spec(:,:,:,t,:), sz(1), sz(2), sz(3), N_test);   % [128 128 1 N]
    X_t = dlarray(X_t, 'SSCB');
    if canUseGPU, X_t = gpuArray(X_t); end
    feat_t = predict(cnn_net, X_t);              % dlarray 'CB' [128 N]
    feats_cell{t} = extractdata(feat_t);          % plain [128 N]
end
cnn_feats = cat(3, feats_cell{:});                % [128 N seq_len] = (C,B,T)
cnn_feats_dl = dlarray(cnn_feats, 'CBT');
if canUseGPU, cnn_feats_dl = gpuArray(cnn_feats_dl); end

Xfeat_dl = dlarray(X_test_feat, 'CTB');
if canUseGPU, Xfeat_dl = gpuArray(Xfeat_dl); end

lstm_cnn_out  = predict(lstm_cnn_net, cnn_feats_dl);    % [64 N]
feat_lstm_out = predict(feat_lstm_net, Xfeat_dl);       % [16 N]
merged = dlarray(cat(1, extractdata(lstm_cnn_out), extractdata(feat_lstm_out)), 'CB');
if canUseGPU, merged = gpuArray(merged); end

Y_pred_prob = predict(classifier_net, merged);          % [nClasses N]
[~, max_idx] = max(extractdata(Y_pred_prob), [], 1);

Y_pred = categorical(classes(max_idx)', classes);

Y_test = Y_test(:);
Y_pred = Y_pred(:);

%% 4. Metrics & Confusion Matrix (identical computation to eval_detector.m)
fprintf('\nCalculating metrics...\n');
conf_mat = confusionmat(Y_test, Y_pred);
precision = diag(conf_mat) ./ sum(conf_mat, 1)';
recall = diag(conf_mat) ./ sum(conf_mat, 2);
f1_scores = 2 .* (precision .* recall) ./ (precision + recall);
macro_f1 = mean(f1_scores, 'omitnan');

fprintf('\n--- CNN-LSTM Test Set Metrics ---\n');
fprintf('Overall Accuracy: %.2f%%\n', 100 * sum(Y_test == Y_pred) / numel(Y_test));
fprintf('Macro-F1 Score:   %.2f%%\n\n', 100 * macro_f1);

for i = 1:numel(classes)
    fprintf('Class %18s: Acc = %5.1f%%, F1 = %5.1f%%\n', ...
        string(classes(i)), 100*recall(i), 100*f1_scores(i));
end

fig_cm = figure('Name', 'Confusion Matrix (CNN-LSTM)', 'Color', 'w', 'Position', [100 100 700 600]);
cm = confusionchart(Y_test, Y_pred);
cm.Title = 'CNN-LSTM Detector Confusion Matrix (Test Set)';
cm.RowSummary = 'row-normalized';
cm.ColumnSummary = 'column-normalized';
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig_cm, 'results/confusion_matrix_lstm.png');

%% 5. Accuracy vs SNR
% feats stored as [N seq_len nFeat], column 1 = snr. SNR is constant across
% a window (each sequence comes from one contiguous same-SNR run), so the
% first timestep's value represents the whole sequence.
norm_mean = sp.norm.feat_mean(1);
norm_std  = sp.norm.feat_std(1);
snr_real  = squeeze(sp.test.feats(:, 1, 1)) .* norm_std + norm_mean;   % -> dB

snr_vals    = round(snr_real);
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

fig_snr = figure('Name', 'Accuracy vs SNR (CNN-LSTM)', 'Color', 'w');
plot(unique_snrs, acc_vs_snr * 100, '-or', 'LineWidth', 2, ...
    'MarkerSize', 8, 'MarkerFaceColor', 'r');
grid on;
xlabel('SNR (dB)');
ylabel('Accuracy (%)');
title('CNN-LSTM Detection Accuracy vs. SNR');
xticks(unique_snrs);
saveas(fig_snr, 'results/accuracy_vs_snr_lstm.png');

fprintf('\nSNR breakdown:\n');
for i = 1:length(unique_snrs)
    fprintf('  SNR=%2d dB: %.1f%%\n', unique_snrs(i), 100*acc_vs_snr(i));
end

fprintf('\nEvaluation complete. Saved confusion_matrix_lstm.png and accuracy_vs_snr_lstm.png to results/.\n');

%% 6. Save numeric results (same structure as eval_detector.m, for direct comparison)
snr_breakdown = struct('snr_db', num2cell(unique_snrs), 'accuracy_pct', num2cell(100*acc_vs_snr));
metrics = struct( ...
    'generated', datestr(now), ...
    'architecture', 'CNN-LSTM', ...
    'overall_accuracy_pct', 100*sum(Y_test==Y_pred)/numel(Y_test), ...
    'macro_f1_pct', 100*macro_f1, ...
    'classes', {cellstr(classes)}, ...
    'per_class_recall_pct', 100*recall, ...
    'per_class_f1_pct', 100*f1_scores, ...
    'conf_mat', conf_mat, ...
    'snr_breakdown', snr_breakdown, ...
    'n_test_sequences', N_test, ...
    'seq_len', seq_len);
save('results/eval_detector_lstm_metrics.mat', 'metrics');
fprintf('Saved results/eval_detector_lstm_metrics.mat (for architecture comparison)\n');

%% 7. Direct comparison vs CNN-only baseline (if available)
if exist('results/eval_detector_metrics.mat', 'file')
    C = load('results/eval_detector_metrics.mat', 'metrics');
    cnn_metrics = C.metrics;
    fprintf('\n=== CNN vs CNN-LSTM Comparison ===\n');
    fprintf('%-22s %10s %10s %8s\n', 'Class', 'CNN', 'CNN-LSTM', 'Delta');
    for i = 1:numel(classes)
        cnn_idx = find(strcmp(cnn_metrics.classes, string(classes(i))));
        if ~isempty(cnn_idx)
            cnn_recall = cnn_metrics.per_class_recall_pct(cnn_idx);
            lstm_recall = 100*recall(i);
            fprintf('%-22s %9.1f%% %9.1f%% %+7.1f%%\n', ...
                string(classes(i)), cnn_recall, lstm_recall, lstm_recall - cnn_recall);
        end
    end
    fprintf('%-22s %9.1f%% %9.1f%% %+7.1f%%\n', 'OVERALL', ...
        cnn_metrics.overall_accuracy_pct, 100*sum(Y_test==Y_pred)/numel(Y_test), ...
        100*sum(Y_test==Y_pred)/numel(Y_test) - cnn_metrics.overall_accuracy_pct);
else
    fprintf('\n(results/eval_detector_metrics.mat not found — run eval_detector.m for side-by-side comparison)\n');
end