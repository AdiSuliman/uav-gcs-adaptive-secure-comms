%% DIAGNOSE_REACTIVE_JAMMING — Numeric confusion matrix + reactive_jamming breakdown
% Standalone diagnostic. Loads the already-trained B3 detector and the test
% split, runs predictions on the FULL test set, and prints:
%   1. Full numeric confusion matrix (rows=true, cols=predicted)
%   2. Per-class F1
%   3. reactive_jamming's specific misclassification breakdown
%   4. The single most-confused class pair overall (for context)
%
% Does NOT retrain or modify anything. Read-only diagnostic.
%
% FIX (Sep 13): field names corrected to match prepare_data.m's actual
% splits.mat structure (splits.test.X / .Y / .feats, not .spec/.labels/.feat).
% splits.test.feats is ALREADY z-scored (prepare_data.m saves feats_norm
% directly) -- do NOT re-normalize here, that would double-normalize.

close all; clc;
fprintf('=== Diagnose: reactive_jamming vs spoofing confusion ===\n\n');

%% 1. Load trained detector + test split
D = load('data/trained_detector.mat', 'net', 'classes');
net = D.net; classes = cellstr(D.classes);
nClasses = numel(classes);

S = load('data/splits.mat', 'splits');
test_spec  = S.splits.test.X;              % [128x128x1xN]
test_feat  = S.splits.test.feats;          % [NxnFeat] -- ALREADY z-scored
test_labels = cellstr(S.splits.test.Y);    % categorical -> cellstr

N = numel(test_labels);
fprintf('Test set size: %d samples across %d classes\n\n', N, nClasses);

%% 2. Run predictions on full test set (features already normalized)
X_spec = dlarray(single(test_spec), 'SSCB');
X_feat = dlarray(single(test_feat)', 'CB');
if canUseGPU, X_spec = gpuArray(X_spec); X_feat = gpuArray(X_feat); end

pred_probs = predict(net, X_spec, X_feat);
pred_probs = extractdata(pred_probs);   % [nClasses x N]
[~, pred_idx] = max(pred_probs, [], 1);
pred_labels = classes(pred_idx);

%% 3. Build numeric confusion matrix
confmat = zeros(nClasses, nClasses);
for i = 1:N
    true_idx = find(strcmp(classes, test_labels{i}));
    p_idx = pred_idx(i);
    confmat(true_idx, p_idx) = confmat(true_idx, p_idx) + 1;
end

fprintf('%-20s', 'True \ Pred');
for c = 1:nClasses
    fprintf('%10s', classes{c}(1:min(9,end)));
end
fprintf('\n');
for r = 1:nClasses
    fprintf('%-20s', classes{r});
    for c = 1:nClasses
        fprintf('%10d', confmat(r,c));
    end
    fprintf('\n');
end

%% 4. Per-class precision/recall/F1
fprintf('\n%-20s %8s %8s %8s\n', 'Class', 'Prec', 'Recall', 'F1');
for c = 1:nClasses
    tp = confmat(c,c);
    fp = sum(confmat(:,c)) - tp;
    fn = sum(confmat(c,:)) - tp;
    prec = tp / max(tp+fp, 1);
    rec  = tp / max(tp+fn, 1);
    f1 = 2*prec*rec / max(prec+rec, eps);
    fprintf('%-20s %8.1f%% %8.1f%% %8.1f%%\n', classes{c}, 100*prec, 100*rec, 100*f1);
end

%% 5. reactive_jamming specific breakdown
rj_idx = find(strcmp(classes, 'reactive_jamming'));
if ~isempty(rj_idx)
    fprintf('\n=== reactive_jamming breakdown (%d true samples) ===\n', sum(confmat(rj_idx,:)));
    [sorted_counts, sorted_idx] = sort(confmat(rj_idx,:), 'descend');
    for k = 1:nClasses
        if sorted_counts(k) == 0, continue; end
        fprintf('  -> predicted as %-20s : %d (%.1f%%)\n', ...
            classes{sorted_idx(k)}, sorted_counts(k), 100*sorted_counts(k)/sum(confmat(rj_idx,:)));
    end
else
    fprintf('\n[WARN] reactive_jamming not found in classes list -- check class names.\n');
end

%% 6. Most-confused pair overall (excluding diagonal)
off_diag = confmat - diag(diag(confmat));
[max_val, max_idx] = max(off_diag(:));
[r_max, c_max] = ind2sub(size(off_diag), max_idx);
fprintf('\nMost-confused pair overall: true=%s -> predicted=%s (%d samples)\n', ...
    classes{r_max}, classes{c_max}, max_val);

fprintf('\n=== Diagnostic Complete ===\n');