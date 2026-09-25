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

%% 5b. KPI #1 as worded in the proposal (D34)
% Macro-F1 per Eb/N0, and the threshold: the lowest Eb/N0 from which macro-F1
% stays >= 90% at every higher point. Action-equivalent accuracy counts a
% confusion as harmless when both classes map to the same countermeasure in the
% rule table (e.g. jamming <-> reactive_jamming -> channel_switch).
cls_names = cellstr(string(classes(:)'));
f1_vs_snr = nan(numel(unique_snrs), 1);
for i = 1:numel(unique_snrs)
    idx = (snr_vals == unique_snrs(i));
    f1_vs_snr(i) = 100 * macro_f1_of(Y_test(idx), Y_pred(idx), classes);
end
ok = f1_vs_snr >= 90;
k_thr = find(~ok, 1, 'last');
if isempty(k_thr), thr_db = unique_snrs(1); elseif k_thr < numel(ok), thr_db = unique_snrs(k_thr + 1); else, thr_db = NaN; end
above = snr_vals >= thr_db;
f1_above = 100 * macro_f1_of(Y_test(above), Y_pred(above), classes);

act_of = containers.Map(cls_names, cellfun(@(c) rule_based_policy(c), cls_names, 'UniformOutput', false));
act_true = cellfun(@(c) act_of(c), cellstr(string(Y_test)), 'UniformOutput', false);
act_pred = cellfun(@(c) act_of(c), cellstr(string(Y_pred)), 'UniformOutput', false);
act_ok = strcmp(act_true, act_pred);
act_acc_class = nan(numel(cls_names), 1);
for c = 1:numel(cls_names)
    m = strcmp(cellstr(string(Y_test)), cls_names{c});
    act_acc_class(c) = 100 * mean(act_ok(m));
end
fprintf('\nMacro-F1 per Eb/N0:');
fprintf(' %g dB %.1f%% |', [unique_snrs(:)'; f1_vs_snr(:)']);
fprintf('\nKPI #1 threshold: macro-F1 >= 90%% from %g dB up; macro-F1 above it %.2f%%\n', thr_db, f1_above);
fprintf('Action-equivalent accuracy: %.2f%% (class accuracy %.2f%%)\n', 100*mean(act_ok), 100*mean(Y_test == Y_pred));

%% 6. Save numeric results for downstream KPI aggregation (does not affect anything above)
snr_breakdown = struct('snr_db', num2cell(unique_snrs), 'accuracy_pct', num2cell(100*acc_vs_snr), ...
    'macro_f1_pct', num2cell(f1_vs_snr));
metrics = struct( ...
    'generated', datestr(now), ...
    'overall_accuracy_pct', 100*sum(Y_test==Y_pred)/numel(Y_test), ...
    'macro_f1_pct', 100*macro_f1, ...
    'classes', {cellstr(classes)}, ...
    'per_class_recall_pct', 100*recall, ...
    'per_class_f1_pct', 100*f1_scores, ...
    'conf_mat', conf_mat, ...
    'snr_breakdown', snr_breakdown, ...
    'kpi1_threshold_db', thr_db, 'macro_f1_above_threshold_pct', f1_above, ...
    'action_equiv_accuracy_pct', 100*mean(act_ok), 'action_equiv_per_class_pct', act_acc_class);
%% 7. Accuracy vs UAV speed (only when the dataset was generated with speed diversity)
if isfield(sp.test, 'speed') && ~isempty(sp.test.speed)
    spd_test  = sp.test.speed(:);
    spd_edges = linspace(min(spd_test), max(spd_test), 8);      % 7 equal-width speed bins
    spd_edges(end) = spd_edges(end) + eps;
    spd_bin   = discretize(spd_test, spd_edges);
    speed_breakdown = struct('speed_lo_kmh', {}, 'speed_hi_kmh', {}, 'accuracy_pct', {}, 'n', {});
    fprintf('\nAccuracy vs UAV speed:\n');
    for b = 1:numel(spd_edges)-1
        idx = (spd_bin == b);
        if ~any(idx), continue; end
        a = 100*sum(Y_test(idx) == Y_pred(idx)) / sum(idx);
        speed_breakdown(end+1) = struct('speed_lo_kmh', spd_edges(b), 'speed_hi_kmh', spd_edges(b+1), ...
            'accuracy_pct', a, 'n', sum(idx)); %#ok<AGROW>
        fprintf('  %6.1f-%6.1f km/h: %.1f%%  (n=%d)\n', spd_edges(b), spd_edges(b+1), a, sum(idx));
    end
    metrics.speed_breakdown = speed_breakdown;
end

save('results/eval_detector_metrics.mat', 'metrics');
fprintf('Saved results/eval_detector_metrics.mat (for KPI aggregation)\n');

%% Local function
function f = macro_f1_of(yt, yp, classes)
cm = confusionmat(yt, yp, 'Order', classes);
pr = diag(cm) ./ sum(cm, 1)';
rc = diag(cm) ./ sum(cm, 2);
f1 = 2 * pr .* rc ./ (pr + rc);
f = mean(f1(sum(cm, 2) > 0), 'omitnan');
end
