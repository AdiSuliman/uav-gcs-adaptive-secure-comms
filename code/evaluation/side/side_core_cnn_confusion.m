function S = side_core_cnn_confusion(pred_mat, out_dir, core_mat)
%SIDE_CORE_CNN_CONFUSION  The test-set confusion matrix of the three-state CNN (B3c) from its saved
%   per-frame predictions, with the recall of each state: a labelled side reading for the book.
%   S = side_core_cnn_confusion(pred_mat, out_dir)
%   S = side_core_cnn_confusion(pred_mat, out_dir, core_mat)
%   pred_mat  results/core_cnn_predictions.mat of the tree (cpred: state, core_window, core_frame,
%             hybrid, run, states; train_core_cnn.m, the fourth test set read once there; opened read-only)
%   out_dir   a new folder; side_core_cnn_confusion.txt and .mat are written there
%   core_mat  optional: the same tree's results/core_cnn.mat; each matrix is compared with the registered one
%   Rows the true state (clean, narrowband, wideband), columns the reader's state; a fourth column for a
%   class outside the three (the hybrid only). Per state: recall with a 95% bootstrap over the test
%   sub-runs (boot_cluster.m, 2000 draws, seed 1) and precision. Readers: the CNN windowed over N cycles
%   (official), per frame, and the hybrid's monitor class where it was read.
if nargin < 3, core_mat = ''; end
if ~isfile(pred_mat), error('side_cm:input', 'side_core_cnn_confusion: %s not found', pred_mat); end
W = load(pred_mat, 'cpred');
if ~isfield(W, 'cpred'), error('side_cm:field', 'side_core_cnn_confusion: %s holds no variable cpred', pred_mat); end
P = W.cpred;
need = {'state', 'core_window', 'core_frame', 'run'};
miss = need(~isfield(P, need));
if ~isempty(miss), error('side_cm:field', 'side_core_cnn_confusion: cpred lacks %s', strjoin(miss, ', ')); end
names = {'clean', 'narrowband jamming', 'wideband jamming'}; if isfield(P, 'states'), names = cellstr(string(P.states(:)')); end
nS = numel(names);
N = NaN; if isfield(P, 'N'), N = P.N; end
rd = {sprintf('core CNN, window N = %g (official)', N), 'core_window', 2; 'core CNN, per frame', 'core_frame', 3; ...
    'hybrid (monitor class)', 'hybrid', 1};
REG = [];
if ~isempty(core_mat)
    if ~isfile(core_mat), error('side_cm:input', 'side_core_cnn_confusion: %s not found', core_mat); end
    C = load(core_mat, 'core'); REG = C.core.metrics;
end
cmp = 'registered matrices compared: none given';
if ~isempty(core_mat), cmp = sprintf('registered matrices compared: %s (SHA-256 %s)', core_mat, side_sha256(core_mat)); end
notes = {'rows the true state, columns the reader''s state (a fourth column: a class outside the three, the hybrid only)', ...
    'recall: 95% bootstrap over the test sub-runs (2000 draws, seed 1); precision: point', cmp};
L = side_header('Three-state CNN, test-set confusion matrix (B3c)', pred_mat, notes);
y = double(P.state(:)); run = P.run(:);
rows = struct('reader', {}, 'cm', {}, 'recall', {}, 'recall_ci', {}, 'precision', {}, 'n', {}, 'registered', {});
for r = 1:size(rd, 1)
    if ~isfield(P, rd{r, 2}), continue; end
    p = double(P.(rd{r, 2})(:));
    if all(isnan(p)), L{end+1} = sprintf('%s: not read in this file', rd{r, 1}); continue; end %#ok<AGROW>
    cm = zeros(nS, nS + 1);
    for i = 1:numel(y)
        if ~isfinite(p(i)), continue; end
        c = p(i); if c < 1 || c > nS, c = nS + 1; end
        cm(y(i), c) = cm(y(i), c) + 1;
    end
    rec = nan(1, nS); ci = nan(nS, 2); pre = nan(1, nS);
    for s = 1:nS
        k = y == s & isfinite(p);
        rec(s) = cm(s, s) / sum(cm(s, :));
        [~, ci(s, 1), ci(s, 2)] = boot_cluster(double(p(k) == s), ones(sum(k), 1), run(k), 2000, 1);
        pre(s) = cm(s, s) / sum(cm(:, s));
    end
    reg = 'not compared';
    if ~isempty(REG) && numel(REG) >= rd{r, 3} && ~isempty(REG{rd{r, 3}}) && isfield(REG{rd{r, 3}}, 'cm')
        g = REG{rd{r, 3}}.cm; w = min(size(g, 2), nS + 1);
        reg = ternary(isequal(size(g, 1), nS) && isequal(g(:, 1:w), cm(:, 1:w)) && ~any(any(cm(:, w + 1:end))), ...
            'equals the registered matrix', 'DIFFERS from the registered matrix');
    end
    rows(end+1) = struct('reader', rd{r, 1}, 'cm', cm, 'recall', rec, 'recall_ci', ci, 'precision', pre, 'n', sum(cm, 2)', ...
        'registered', reg); %#ok<AGROW>
    L{end+1} = sprintf('%s (%s)', rd{r, 1}, reg); %#ok<AGROW>
    L{end+1} = sprintf('  %-20s %10s %10s %10s %10s   recall [95%%]            precision', 'true \ read', 'clean', 'narrowband', ...
        'wideband', 'other'); %#ok<AGROW>
    for s = 1:nS
        L{end+1} = sprintf('  %-20s %10d %10d %10d %10d   %6.2f%% [%6.2f, %6.2f]  %6.2f%%', names{s}, cm(s, :), 100 * rec(s), ...
            100 * ci(s, :), 100 * pre(s)); %#ok<AGROW>
    end
end
S = struct('input', pred_mat, 'sha256', side_sha256(pred_mat), 'states', {names}, 'rows', {rows});
out = side_out_dir(out_dir, [{pred_mat}, ternary(isempty(core_mat), {}, {core_mat})]);
side_write(out, 'side_core_cnn_confusion', L, S);
fprintf('%s\n', L{:});
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
