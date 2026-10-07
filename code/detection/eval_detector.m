%% B3 — EVALUATE HYBRID DETECTOR (Test Set)
% Test set: the second test set of build_fresh_test.m (data/splits_fresh.mat, sub-runs never
% read before) when it exists, else the test split of data/splits.mat. With DET_TEST = 'split'
% in the calling workspace the test split is read even then, and the outputs carry the
% suffix _split. The KPI 1 threshold is chosen on the validation split in both cases.
close all; clc;fprintf('=== B3: Test Evaluation ===\n\n');

%% 1. Load data and model
has_fresh = isfile('data/splits_fresh.mat');
read_split = exist('DET_TEST', 'var') && strcmp(DET_TEST, 'split');
tag = ''; if has_fresh && read_split, tag = '_split'; end
set_name = 'test split';
fprintf('Loading test data and trained model...\n');
S = load('data/splits.mat');
sp = S.splits;
if has_fresh && ~read_split
    Sf = load('data/splits_fresh.mat');
    assert(isequal(Sf.splits.norm, sp.norm), 'eval_detector: the second test set has another normalization');
    sp.test = Sf.splits.test; clear Sf
    set_name = 'second test set';
end
sp.train = [];                                          % not read here
fprintf('Test set: %s (%d frames)\n', set_name, numel(sp.test.Y));
Y_test = sp.test.Y;

load('data/trained_detector.mat', 'net', 'classes');

%% 2. Prepare test data for dlnetwork
%% 3. Inference (batched: the whole test split does not fit on the GPU)
fprintf('Running inference on %d test samples...\n', numel(Y_test));
Y_pred_prob = cnn_scores(net, sp.test.X, sp.test.feats');
% Temporal fusion (select_fusion.m): the class of every cycle from the last N
% cycles of its own sub-run, as the system decides; the per-frame reading is kept.
% The fused decision is judged on its window (fusion_target.m): a WLAN frame without a
% packet whose window holds packet frames has the target benign_interference.
fus = [];
rk = ones(numel(Y_test), 1);
if isfile('data/fusion.mat') && isfield(sp.test, 'pos')
    fus = load('data/fusion.mat', 'FM', 'N', 'val_probs_oof', 'val_target');
    [~, i1] = max(Y_pred_prob, [], 1);
    yf = categorical(classes(i1)', classes);
    frame_acc = 100 * mean(yf(:) == sp.test.Y(:));
    frame_f1 = 100 * macro_f1_of(sp.test.Y(:), yf(:), classes);
    frame_class_f1 = 100 * class_f1_of(sp.test.Y(:), yf(:), classes);
    fprintf('Per frame (0.5 ms): accuracy %.2f%%, macro-F1 %.2f%%\n', frame_acc, frame_f1);
    sp.test.feat_names = sp.norm.feat_names;
    Z = fuse_classes('windows', sp.test, Y_pred_prob', fus.N);
    Y_pred_prob = fuse_classes('apply', fus.FM, Z)';
    fprintf('Decision over the last %d cycles (temporal fusion)\n', fus.N);
    [yt, rk] = fusion_target(double(sp.test.Y(:)), sp.test.run, sp.test.pos, fus.N, classes);
    Y_test = categorical(classes(yt)', classes);
    fprintf('WLAN frames without a packet judged by their window as benign_interference: %d\n', ...
        sum(Y_test(:) ~= sp.test.Y(:)));
end
[~, max_idx] = max(Y_pred_prob, [], 1);

Y_pred = categorical(classes(max_idx)', classes);

Y_test = Y_test(:);
Y_pred = Y_pred(:);

%% 4. Metrics & Confusion Matrix
fprintf('\nCalculating metrics...\n');
[conf_mat, cm_order] = confusionmat(Y_test, Y_pred);
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
cm_lbl = strrep(string(cm_order), '_', ' ');                       % no TeX subscripts in the labels
cm = confusionchart(conf_mat, categorical(cm_lbl, cm_lbl));          % categorical keeps the class order
cm.Title = sprintf('Hybrid Detector Confusion Matrix (%s)', set_name);
cm.RowSummary = 'row-normalized';
cm.ColumnSummary = 'column-normalized';
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig_cm, ['results/confusion_matrix' tag '.png']);

%% 5. Accuracy vs SNR (true Eb/N0 values in dB, denormalized)
% sp.test.feats is z-scored; denormalize column 1 (SNR) back to dB
% using the same train-set mean/std saved in splits.norm
if isfield(sp.test, 'ebno')
    snr_vals = sp.test.ebno(:);                          % configured Eb/N0
else
    snr_vals = round(sp.test.feats(:, 1) .* sp.norm.feat_std(1) + sp.norm.feat_mean(1));
end
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

fprintf('\nSNR breakdown:\n');
for i = 1:length(unique_snrs)
    fprintf('  SNR=%2d dB: %.1f%%\n', unique_snrs(i), 100*acc_vs_snr(i));
end


%% 5b. KPI #1 as worded in the proposal
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
% Threshold (proposal), chosen on the VALIDATION split and then read on the test
% split: the lowest Eb/N0 from which macro-F1 stays >= 90% at every higher point
% AND every class reaches F1 >= 90% over the frames at or above it.
if isempty(fus)
    [~, iv] = max(cnn_scores(net, sp.val.X, sp.val.feats'), [], 1);
else
    [~, iv] = max(fus.val_probs_oof, [], 2);                % out-of-fold fused predictions on validation
end
Y_val = sp.val.Y(:); Y_val_pred = reshape(categorical(classes(iv)', classes), [], 1);
if ~isempty(fus) && isfield(fus, 'val_target')                % the fused decision's targets (fusion_target.m)
    Y_val = reshape(categorical(classes(fus.val_target)', classes), [], 1);
end
if isfield(sp.val, 'ebno')
    snr_val = sp.val.ebno(:);
else
    snr_val = round(sp.val.feats(:, 1) .* sp.norm.feat_std(1) + sp.norm.feat_mean(1));
end
thr_db = kpi1_threshold(Y_val, Y_val_pred, snr_val, classes);
above = snr_vals >= thr_db;
f1_class_above = nan(numel(classes), 1);
if any(above), f1_class_above = 100 * class_f1_of(Y_test(above), Y_pred(above), classes); end
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
fprintf('\nKPI #1 threshold (chosen on validation): %g dB; on the %s above it macro-F1 %.2f%%, lowest class %.2f%%\n', ...
    thr_db, set_name, f1_above, min(f1_class_above));
fprintf('Action-equivalent accuracy: %.2f%% (class accuracy %.2f%%)\n', 100*mean(act_ok), 100*mean(Y_test == Y_pred));

fig_snr = figure('Name', 'Detection vs Eb/N0', 'Color', 'w', 'Position', [100 100 640 420]);
hold on; grid on;
plot(unique_snrs, f1_vs_snr, '-o', 'LineWidth', 2, 'MarkerSize', 7, 'MarkerFaceColor', 'auto', 'DisplayName', 'macro-F1');
plot(unique_snrs, 100 * acc_vs_snr, '--s', 'LineWidth', 1.4, 'MarkerSize', 6, 'DisplayName', 'accuracy');
yline(90, 'k:', 'LineWidth', 1.2, 'DisplayName', 'KPI 1 target (90%)');
if ~isnan(thr_db)
    xline(thr_db, 'r-', 'LineWidth', 1.2, 'DisplayName', sprintf('threshold %g dB (chosen on validation)', thr_db));
end
xlabel('E_b/N_0 per antenna [dB]'); ylabel('Test set [%]'); ylim([0 100]); xticks(unique_snrs);
title(['Hybrid detector, ' set_name]);
legend('Location', 'southeast');
saveas(fig_snr, ['results/accuracy_vs_snr' tag '.png']);
fprintf('Saved results/confusion_matrix%s.png and results/accuracy_vs_snr%s.png\n', tag, tag);

%% 5b2. Beside KPI 1 (which stays as above): steady state and onset latency
% Steady state: the frames whose fusion window is full (rank >= N in their sub-run); a
% sub-run of F_SUB frames starts with a window of one frame. Onset latency per class:
% cycles from the first frame of the threat in a test sub-run to the first correct fused
% class, and to the confirmed alarm (a hostile fused class, not none or
% benign_interference, on m of the last n cycles, decision_config.m confirm; the
% monitor's degradation path is not part of this detector reading). A sub-run holds no
% frame before the onset, so the window starts with the threat.
Cd = decision_config();
Nf = 1; if ~isempty(fus), Nf = fus.N; end
fullw = rk(:) >= Nf;
steady = struct('n', sum(fullw), 'n_all', numel(fullw), 'window', Nf, ...
    'accuracy_pct', 100 * mean(Y_test(fullw) == Y_pred(fullw)), ...
    'macro_f1_pct', 100 * macro_f1_of(Y_test(fullw), Y_pred(fullw), classes), ...
    'macro_f1_above_threshold_pct', 100 * macro_f1_of(Y_test(fullw & above), Y_pred(fullw & above), classes), ...
    'class_f1_above_threshold_pct', 100 * class_f1_of(Y_test(fullw & above), Y_pred(fullw & above), classes), ...
    'action_equiv_accuracy_pct', 100 * mean(act_ok(fullw)));
fprintf(['Steady state (window full, %d of %d frames): accuracy %.2f%%, macro-F1 %.2f%%, above the threshold ' ...
    '%.2f%%, action-equivalent %.2f%%\n'], steady.n, steady.n_all, steady.accuracy_pct, steady.macro_f1_pct, ...
    steady.macro_f1_above_threshold_pct, steady.action_equiv_accuracy_pct);
hostile = ~ismember(cellstr(string(Y_pred)), {'none', 'benign_interference'});
onset = struct('class', {}, 'n_runs', {}, 'cls_median', {}, 'cls_p90', {}, 'cls_never_pct', {}, ...
    'conf_median', {}, 'conf_p90', {}, 'conf_never_pct', {});
runs_t = sp.test.run(:);
for c = 2:numel(cls_names)
    rc = unique(runs_t(Y_test == cls_names{c}));
    tc_ = nan(numel(rc), 1); tf_ = nan(numel(rc), 1);
    alarm_cls = ~strcmp(cls_names{c}, 'benign_interference');
    for r = 1:numel(rc)
        ix = find(runs_t == rc(r)); [~, o] = sort(rk(ix)); ix = ix(o);
        j0 = find(Y_test(ix) == cls_names{c}, 1);
        j = find(Y_pred(ix(j0:end)) == cls_names{c}, 1);
        if ~isempty(j), tc_(r) = j - 1; end
        if alarm_cls
            cf = movsum(double(hostile(ix(j0:end))), [Cd.confirm(2) - 1, 0]) >= Cd.confirm(1);
            j = find(cf, 1); if ~isempty(j), tf_(r) = j - 1; end
        end
    end
    onset(end+1) = struct('class', cls_names{c}, 'n_runs', numel(rc), 'cls_median', median(tc_, 'omitnan'), ...
        'cls_p90', prctile_nan(tc_, 90), 'cls_never_pct', 100 * mean(isnan(tc_)), ...
        'conf_median', median(tf_, 'omitnan'), 'conf_p90', prctile_nan(tf_, 90), ...
        'conf_never_pct', 100 * alarm_cls * mean(isnan(tf_))); %#ok<SAGROW>
end
fprintf(['Onset latency [cycles of %g ms; 0 = on the onset frame itself], test sub-runs: first correct fused class median / p90 (never) | ' ...
    'confirmed alarm median / p90 (never; benign_interference raises none)\n'], Cd.period_ms);
for c = 1:numel(onset)
    fprintf('  %-20s %3d runs: %4.1f / %4.1f (%5.1f%%) | %4.1f / %4.1f (%5.1f%%)\n', onset(c).class, onset(c).n_runs, ...
        onset(c).cls_median, onset(c).cls_p90, onset(c).cls_never_pct, onset(c).conf_median, onset(c).conf_p90, ...
        onset(c).conf_never_pct);
end

%% 5c. 95% bootstrap confidence intervals
% Resamples whole test sub-runs with replacement (frames of one sub-run are
% correlated); a local stream keeps the global generator untouched.
N_BOOT = 1000;
bs = RandStream('mt19937ar', 'Seed', 7);
nT = numel(Y_test);
if isfield(sp.test, 'run'), grp = sp.test.run(:); else, grp = (1:nT)'; end
[ug, ~, gi] = unique(grp);
members = accumarray(gi, (1:nT)', [], @(v) {v});
boot = nan(N_BOOT, 4);
for b = 1:N_BOOT
    ix = vertcat(members{randi(bs, numel(ug), numel(ug), 1)});
    yb = Y_test(ix); yp = Y_pred(ix); ab = above(ix); fb = fullw(ix);
    boot(b, :) = 100 * [mean(yb == yp), macro_f1_of(yb, yp, classes), macro_f1_of(yb(ab), yp(ab), classes), ...
        macro_f1_of(yb(ab & fb), yp(ab & fb), classes)];
end
ci = prctile_cols(boot, [2.5 97.5]);
ci95 = struct('n_boot', N_BOOT, 'accuracy', ci(:, 1)', 'macro_f1', ci(:, 2)', 'macro_f1_above', ci(:, 3)', ...
    'macro_f1_above_steady', ci(:, 4)');
fprintf('95%% bootstrap CI: accuracy [%.2f, %.2f] | macro-F1 [%.2f, %.2f] | macro-F1 above threshold [%.2f, %.2f]\n', ...
    ci95.accuracy, ci95.macro_f1, ci95.macro_f1_above);

%% 6. Save numeric results for downstream KPI aggregation
snr_breakdown = struct('snr_db', num2cell(unique_snrs), 'accuracy_pct', num2cell(100*acc_vs_snr), ...
    'macro_f1_pct', num2cell(f1_vs_snr));
metrics = struct( ...
    'generated', datestr(now), 'test_set', set_name, ...
    'overall_accuracy_pct', 100*sum(Y_test==Y_pred)/numel(Y_test), ...
    'macro_f1_pct', 100*macro_f1, ...
    'classes', {cellstr(classes)}, ...
    'per_class_recall_pct', 100*recall, ...
    'per_class_f1_pct', 100*f1_scores, ...
    'conf_mat', conf_mat, ...
    'snr_breakdown', snr_breakdown, ...
    'kpi1_threshold_db', thr_db, 'macro_f1_above_threshold_pct', f1_above, ...
    'class_f1_above_threshold_pct', f1_class_above, ...
    'action_equiv_accuracy_pct', 100*mean(act_ok), 'action_equiv_per_class_pct', act_acc_class, ...
    'ci95', ci95, 'steady', steady, 'onset', onset);
if ~isempty(fus)
    metrics.fusion_cycles = fus.N;
    metrics.per_frame = struct('accuracy_pct', frame_acc, 'macro_f1_pct', frame_f1, 'class_f1_pct', frame_class_f1);
end
%% 7. Accuracy vs UAV speed (only when the dataset was generated with speed diversity)
% Every band holds about a seventh of the test sub-runs, so its mix of classes and
% severity levels differs by chance. Beside the raw accuracy, the standardized one
% weights every (class, level) stratum as in the whole test split, so the bands
% differ only by speed.
if isfield(sp.test, 'speed') && ~isempty(sp.test.speed)
    spd_test  = sp.test.speed(:);
    spd_edges = linspace(min(spd_test), max(spd_test), 8);      % 7 equal-width speed bins
    spd_edges(end) = spd_edges(end) + eps;
    spd_bin   = discretize(spd_test, spd_edges);
    speed_breakdown = struct('speed_lo_kmh', {}, 'speed_hi_kmh', {}, 'accuracy_pct', {}, 'std_accuracy_pct', {}, 'n', {});
    lv = sp.test.level(:); lv(isnan(lv)) = -1;
    [~, ~, st] = unique([double(Y_test) lv], 'rows');       % (class, level) strata
    w = accumarray(st, 1) / numel(st);                        % their share in the whole test split
    ok = double(Y_test == Y_pred);
    fprintf('\nAccuracy vs UAV speed (raw | standardized to the test mix of classes and levels):\n');
    for b = 1:numel(spd_edges)-1
        idx = (spd_bin == b);
        if ~any(idx), continue; end
        a = 100*sum(Y_test(idx) == Y_pred(idx)) / sum(idx);
        acc_s = accumarray(st(idx), ok(idx), size(w), @mean, NaN);
        has = ~isnan(acc_s);
        as = 100 * sum(w(has) .* acc_s(has)) / sum(w(has));
        speed_breakdown(end+1) = struct('speed_lo_kmh', spd_edges(b), 'speed_hi_kmh', spd_edges(b+1), ...
            'accuracy_pct', a, 'std_accuracy_pct', as, 'n', sum(idx)); %#ok<AGROW>
        fprintf('  %6.1f-%6.1f km/h: %.1f%% | %.1f%%  (n=%d)\n', spd_edges(b), spd_edges(b+1), a, as, sum(idx));
    end
    metrics.speed_breakdown = speed_breakdown;
end

save(['results/eval_detector_metrics' tag '.mat'], 'metrics');
fprintf('Saved results/eval_detector_metrics%s.mat (for KPI aggregation)\n', tag);
% Per-frame outcomes for the breakdown of weak points (analyze_weak_points.m)
pred = struct('y_true', Y_test, 'y_pred', Y_pred, 'ebno', snr_vals(:), 'level', sp.test.level(:), ...
    'speed', sp.test.speed(:), 'run', sp.test.run(:), 'rank', rk(:));
for f = {'pos', 'k_db', 'aoa'}
    if isfield(sp.test, f{1}), pred.(f{1}) = sp.test.(f{1}); end
end
save(['results/detector_predictions' tag '.mat'], 'pred');
clear S sp Y_pred_prob DET_TEST   % large arrays; main.m runs the stages in one workspace

%% Local functions
function q = prctile_nan(x, pct)
% Percentile of the finite values (nearest rank), NaN when there are none.
x = sort(x(isfinite(x)));
if isempty(x), q = NaN; else, q = x(min(numel(x), max(1, round(pct / 100 * numel(x))))); end
end

function q = prctile_cols(X, pcts)
% Percentiles of each column (nearest rank), no toolbox needed.
X = sort(X, 1);
n = size(X, 1);
q = X(min(n, max(1, round(pcts(:) / 100 * n))), :);
end

function f1 = class_f1_of(yt, yp, classes)
cm = confusionmat(yt, yp, 'Order', classes);
pr = diag(cm) ./ sum(cm, 1)';
rc = diag(cm) ./ sum(cm, 2);
f1 = 2 * pr .* rc ./ (pr + rc);
f1(isnan(f1)) = 0;
end

function thr = kpi1_threshold(yt, yp, snr, classes)
% Lowest Eb/N0 from which macro-F1 stays >= 90% at every higher point and every
% class reaches F1 >= 90% over the frames at or above it (NaN when none).
u = unique(snr);
f1 = arrayfun(@(v) 100 * macro_f1_of(yt(snr == v), yp(snr == v), classes), u);
k_thr = find(f1 < 90, 1, 'last');
if isempty(k_thr), k0 = 1; else, k0 = k_thr + 1; end
thr = NaN;
for k = k0:numel(u)
    ab = snr >= u(k);
    if all(100 * class_f1_of(yt(ab), yp(ab), classes) >= 90), thr = u(k); return; end
end
end

function f = macro_f1_of(yt, yp, classes)
cm = confusionmat(yt, yp, 'Order', classes);
pr = diag(cm) ./ sum(cm, 1)';
rc = diag(cm) ./ sum(cm, 2);
f1 = 2 * pr .* rc ./ (pr + rc);
f = mean(f1(sum(cm, 2) > 0), 'omitnan');
end
