function S = side_a7_action_equiv(json_file, out_dir, eval_mat)
%SIDE_A7_ACTION_EQUIV  C1: the action-equivalence matrix of the 11-class confusion matrix, a labelled side reading.
%   S = side_a7_action_equiv(json_file, out_dir, eval_mat)
%   json_file  a profile's results/report_numbers.json (key detector_fourth: classes, conf_mat, overall_accuracy_pct,
%              action_equiv_accuracy_pct; opened read-only)
%   out_dir    a new folder; side_a7_action_equiv.txt and .mat are written there
%   eval_mat   optional: the profile's results/policy_evaluation.mat, searched for the deployed policy's per-class action
%   Rows are the true class, columns the predicted one. A cell is "same" when the old rule table's countermeasure
%   (rule_based_policy.m, one argument: the class mapping, as eval_detector.m reads it) of the predicted class equals the
%   true class's, "change" when it differs. The share of the errors that change it has a two-sided 95% Clopper-Pearson
%   interval over frames (frames of one run are not independent: the interval is narrower than a run-level one).
if nargin < 3, eval_mat = ''; end
if ~isfile(json_file), error('side_a7:input', 'side_a7_action_equiv: %s not found', json_file); end
J = jsondecode(fileread(json_file));
if ~isfield(J, 'detector_fourth'), error('side_a7:field', 'side_a7_action_equiv: %s holds no detector_fourth', json_file); end
D = J.detector_fourth;
miss = setdiff({'classes', 'conf_mat'}, fieldnames(D));
if ~isempty(miss), error('side_a7:field', 'side_a7_action_equiv: detector_fourth holds no %s', strjoin(miss, ', ')); end
cls = cellstr(D.classes(:))';
cm = double(D.conf_mat);
n = numel(cls);
if ~isequal(size(cm), [n n]), error('side_a7:size', 'side_a7_action_equiv: conf_mat is %dx%d, %d classes', size(cm, 1), size(cm, 2), n); end
act = cellfun(@(c) rule_based_policy(c), cls, 'UniformOutput', false);
same = false(n);
for i = 1:n
    for j = 1:n, same(i, j) = strcmp(act{i}, act{j}); end
end
off = ~eye(n, 'logical');
tot = sum(cm(:));
n_err = sum(cm(off));
k_keep = sum(cm(off & same));
k_chg = sum(cm(off & ~same));
[lo_c, hi_c] = side_cp(k_chg, n_err);
[lo_k, hi_k] = side_cp(k_keep, n_err);
acc = 100 * trace(cm) / tot;
acc_eq = 100 * (trace(cm) + k_keep) / tot;
notes = {'rows true class, columns predicted class; "=" the old rule table gives the same countermeasure, "x" it changes', ...
    'countermeasure per class: rule_based_policy(class), the class mapping alone (eval_detector.m, act_of)', ...
    'interval: two-sided 95% Clopper-Pearson over frames (frames are not independent runs)'};
L = side_header('C1: action equivalence of the 11-class confusion matrix (old rule table)', json_file, notes);
L{end+1} = 'Class to countermeasure (rule_based_policy.m):';
for i = 1:n, L{end+1} = sprintf('  %-22s %s', cls{i}, act{i}); end %#ok<AGROW>
L{end+1} = '';
L{end+1} = 'Confusion matrix (frames), cell marked "=" same countermeasure, "x" changed (diagonal: correct):';
L{end+1} = sprintf('  %-22s %s', 'true \ predicted', strjoin(cellfun(@(c) sprintf('%10s', c(1:min(end, 10))), cls, 'UniformOutput', false), ' '));
for i = 1:n
    c = arrayfun(@(j) cell_txt(cm(i, j), i == j, same(i, j)), 1:n, 'UniformOutput', false);
    L{end+1} = sprintf('  %-22s %s', cls{i}, strjoin(c, ' ')); %#ok<AGROW>
end
L{end+1} = '';
L{end+1} = sprintf('Frames %d, correct %d (%.4f%%), errors %d', tot, trace(cm), acc, n_err);
L{end+1} = sprintf('Errors that keep the countermeasure: %d of %d = %.2f%% [%.2f, %.2f]', k_keep, n_err, 100 * k_keep / n_err, 100 * lo_k, 100 * hi_k);
L{end+1} = sprintf('Errors that change the countermeasure: %d of %d = %.2f%% [%.2f, %.2f]', k_chg, n_err, 100 * k_chg / n_err, 100 * lo_c, 100 * hi_c);
L{end+1} = sprintf('Action-equivalent accuracy recomputed: %.4f%% (class accuracy %.4f%%)', acc_eq, acc);
if isfield(D, 'action_equiv_accuracy_pct') && isfield(D, 'overall_accuracy_pct')
    L{end+1} = sprintf('Saved in detector_fourth: action-equivalent %.4f%%, class %.4f%%; differences %.2g and %.2g points', ...
        D.action_equiv_accuracy_pct, D.overall_accuracy_pct, acc_eq - D.action_equiv_accuracy_pct, acc - D.overall_accuracy_pct);
end
L{end+1} = '';
L{end+1} = 'Per true class (errors, share changing the countermeasure):';
pc = struct('class', cls, 'n', 0, 'err', 0, 'chg', 0);
for i = 1:n
    e = cm(i, :) .* off(i, :);
    pc(i).n = sum(cm(i, :)); pc(i).err = sum(e); pc(i).chg = sum(e(~same(i, :)));
    L{end+1} = sprintf('  %-22s frames %6d  errors %5d (%5.2f%%)  change %5d (%6.2f%% of its errors)', cls{i}, pc(i).n, pc(i).err, ...
        100 * pc(i).err / pc(i).n, pc(i).chg, 100 * pc(i).chg / max(pc(i).err, 1)); %#ok<AGROW>
end
L{end+1} = '';
[~, o] = sort(reshape(cm .* off, [], 1), 'descend');
nt = min(12, nnz(cm .* off));
L{end+1} = sprintf('Largest %d error cells:', nt);
top = struct('true', {}, 'pred', {}, 'n', {}, 'pct_of_true', {}, 'act_true', {}, 'act_pred', {}, 'changes', {});
for q = 1:nt
    [i, j] = ind2sub([n n], o(q));
    top(end+1) = struct('true', cls{i}, 'pred', cls{j}, 'n', cm(i, j), 'pct_of_true', 100 * cm(i, j) / sum(cm(i, :)), ...
        'act_true', act{i}, 'act_pred', act{j}, 'changes', ~same(i, j)); %#ok<AGROW>
    L{end+1} = sprintf('  %-20s -> %-20s %5d frames (%5.2f%% of the true class): %s -> %s: %s', cls{i}, cls{j}, cm(i, j), ...
        100 * cm(i, j) / sum(cm(i, :)), act{i}, act{j}, pick(same(i, j), 'same countermeasure', 'CHANGES the countermeasure')); %#ok<AGROW>
end
L{end+1} = '';
L = [L, dqn_lines(eval_mat)];
S = struct('input', json_file, 'sha256', side_sha256(json_file), 'classes', {cls}, 'actions', {act}, 'conf_mat', cm, 'same', same, ...
    'n_err', n_err, 'k_keep', k_keep, 'k_change', k_chg, 'ci_change', [lo_c hi_c], 'ci_keep', [lo_k hi_k], 'acc', acc, ...
    'acc_equiv', acc_eq, 'per_class', pc, 'top', top);
out = side_out_dir(out_dir, json_file);
side_write(out, 'side_a7_action_equiv', L, S);
fprintf('%s\n', L{:});
end

function s = cell_txt(v, isdiag, same)
if isdiag, s = sprintf('%9d ', v); elseif same, s = sprintf('%9d=', v); else, s = sprintf('%9dx', v); end
end

function s = pick(c, a, b)
if c, s = a; else, s = b; end
end

function L = dqn_lines(eval_mat)
% The deployed policy's per-class action: readable only when the saved result keeps the per-cycle configuration.
L = {'Deployed DQN, action per predicted class:'};
if isempty(eval_mat)
    L{end+1} = '  not searched (no policy_evaluation.mat given)';
    return
end
if ~isfile(eval_mat), L{end+1} = sprintf('  %s not found', eval_mat); return; end
w = whos('-file', eval_mat);
L{end+1} = sprintf('  input: %s', eval_mat);
L{end+1} = sprintf('  variables: %s', strjoin({w.name}, ', '));
W = load(eval_mat);
R = find_struct(W, 'cfg_final', 0);
if isempty(R)
    L{end+1} = '  no episode result with cfg_final found: not readable without a replay';
    return
end
f = fieldnames(R)';
L{end+1} = sprintf('  episode result fields: %s', strjoin(f, ', '));
has = @(x) any(strcmp(f, x));
L{end+1} = sprintf('  cfg_trace (per-cycle configuration) present: %d; fc_cls (detector class at the first change) present: %d; cfg_final present: %d', ...
    has('cfg_trace'), has('fc_cls'), has('cfg_final'));
if has('cfg_trace')
    L{end+1} = '  the per-cycle configuration is saved: a (class, action) count is readable from it';
else
    L{end+1} = ['  the policy acts on the link features and the history, not on the class alone, and the saved result keeps no ' ...
        'per-cycle configuration paired with the per-cycle predicted class: a per-class action of the DQN is not readable without a replay'];
end
end

function R = find_struct(x, field, depth)
% First struct (searching variables, struct arrays and cells) that has the field.
R = [];
if depth > 4, return; end
if isstruct(x)
    if isfield(x, field), R = x(1); return; end
    f = fieldnames(x);
    for k = 1:min(numel(x), 3)
        for i = 1:numel(f)
            R = find_struct(x(k).(f{i}), field, depth + 1);
            if ~isempty(R), return; end
        end
    end
elseif iscell(x)
    for k = 1:min(numel(x), 6)
        R = find_struct(x{k}, field, depth + 1);
        if ~isempty(R), return; end
    end
end
end
