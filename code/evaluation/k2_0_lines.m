function L = k2_0_lines(cmd, varargin)
%K2_0_LINES  D116 reading 3 beside KPI 2, descriptive and never KPI 2: per held-out threat the
%   flagged share (detection) and, among its unflagged windows, the share whose top known class
%   has the threat's countermeasure under the rule's mapping (rule_based_policy(c) with one
%   argument, not no_action; response), printed apart; their sum over all windows only as the
%   flagged-or-same-countermeasure share, never as coverage; at the deployed retention and at
%   95%. A second line: the area under the risk-coverage curve (Jaeger, Lueth, Klein & Bungert
%   2023, ICLR), the fold's known and held-out windows pooled, the statistic as the confidence, a
%   failure a window accepted with a countermeasure other than its true class's.
%   L = k2_0_lines('windows', W, rt)  the exact form, from per-window values: W, one element
%       per held-out threat: threat; val, the statistic on the fold's known validation windows
%       of the selection half (the threshold keeping a share r of them: unflagged at or above
%       it); kn, un, the statistic on the reading's known and held-out windows; y_kn their true
%       class, top_kn, top_un the top known class (cellstr); rt the deployed retention
%   L = k2_0_lines('bounds', R, NEST, sel, SC)  without per-window values (any
%       results/ood_detection.mat): max(1 - FPR_k, s_k) <= share <= min(1, 1 - FPR_k + s_k),
%       FPR_k the nested pick's FPR95 (NEST.fpr95; else the production score sel's per frame),
%       s_k R.same_action, over all its mapped frames (eval_ood_detection.m), 0 for a threat
%       whose countermeasure is no_action; at 95% only (the file holds no other retention)
%   L = k2_0_lines('kpi', O, u)  measure_all_kpis.m's lines: 'bounds' on its KPI 2 file O, the
%       reading set named; u true while D111's FM.unk is deployed: the bounds then describe the
%       earlier statistic s0. Neither OOD run keeps per-window values with a class read: D111's
%       set-4 reading prints AUROC and FPR95 per held-out threat only (D91's dated line)
%   L = k2_0_lines('file', f, out)  'bounds' on the file f (a read-only copy), printed and
%       written to out (profile 1's bound reader)
switch cmd
    case 'windows', L = win_lines(varargin{:});
    case 'bounds',  L = bound_lines(varargin{:});
    case 'kpi'
        O = varargin{1}; u = numel(varargin) >= 2 && varargin{2};
        rd = 'reading set not recorded'; if isfield(O, 'TEST_SET'), rd = O.TEST_SET; end
        h = sprintf('K2-0 on the %s (results/ood_detection.mat), descriptive, not KPI 2', rd);
        if u, h = [h '; the bounds describe the earlier statistic s0, not D111''s deployed U']; end
        L = [{h}, bound_lines(O.R, O.NEST, O.sel, O.SC)];
    case 'file'
        [f, out] = varargin{:};
        O = load(f, 'R', 'NEST', 'sel', 'SC', 'TEST_SET');
        rd = 'reading set not recorded'; if isfield(O, 'TEST_SET'), rd = O.TEST_SET; end
        L = [{sprintf('K2-0 bounds of %s (%s), %s, descriptive, not KPI 2', f, rd, datestr(now, 'yyyy-mm-dd HH:MM:SS'))}, ...
            bound_lines(O.R, O.NEST, O.sel, O.SC)];
        fid = fopen(out, 'w'); assert(fid > 0, 'k2_0_lines:write', 'cannot write %s', out);
        fprintf(fid, '%s\n', L{:}); fclose(fid);
        fprintf('%s\n', L{:});
    otherwise
        error('k2_0_lines:cmd', 'k2_0_lines: unknown command %s', cmd);
end
end

function L = win_lines(W, rt)
L = {};
for r = unique([rt 0.95], 'stable')
    tag = sprintf('retention %.2f', r); if r == rt, tag = [tag ' (deployed)']; end
    F = zeros(1, numel(W)); S = F; parts = cell(1, numel(W));
    for i = 1:numel(W)
        thr = lowq(W(i).val, 1 - r);
        fl = W(i).un(:) < thr;
        same = same_cm(W(i).top_un, W(i).threat);
        F(i) = mean(fl); S(i) = sum(~fl & same) / max(sum(~fl), 1);
        parts{i} = sprintf('%s %.1f / %.1f / %.1f', W(i).threat, 100 * F(i), 100 * S(i), 100 * (F(i) + (1 - F(i)) * S(i)));
    end
    L{end+1} = sprintf(['K2-0 at %s (descriptive, not KPI 2), %% per held-out threat: flagged (detection) / same ' ...
        'countermeasure among the unflagged windows, under the rule''s mapping (response) / flagged-or-same-countermeasure ' ...
        'share: %s; mean %.1f / %.1f / %.1f'], tag, strjoin(parts, ', '), 100 * mean(F), 100 * mean(S), ...
        100 * mean(F + (1 - F) .* S)); %#ok<AGROW>
end
A = arrayfun(@aurc, W);
L{end+1} = sprintf(['K2-0 risk-coverage (descriptive, not KPI 2; Jaeger et al. 2023): AURC per held-out threat, the ' ...
    'fold''s known and held-out windows pooled, a failure a window accepted with a countermeasure other than its true ' ...
    'class''s: %s; mean %.3f'], strjoin(arrayfun(@(i) sprintf('%s %.3f', W(i).threat, A(i)), 1:numel(W), ...
    'UniformOutput', false), ', '), mean(A));
end

function L = bound_lines(R, NEST, sel, SC)
n = numel(R); lo = zeros(1, n); hi = lo; parts = cell(1, n);
for i = 1:n
    if isfield(NEST, 'fpr95'), fpr = NEST.fpr95(i); else, fpr = R(i).fpr95(strcmp(SC, sel)); end
    s = R(i).same_action;
    if strcmp(rule_based_policy(R(i).held_out), 'no_action'), s = 0; end
    lo(i) = max(1 - fpr, s); hi(i) = min(1, 1 - fpr + s);
    parts{i} = sprintf('%s %.1f-%.1f (flagged %.1f, same countermeasure %.1f)', R(i).held_out, 100 * lo(i), ...
        100 * hi(i), 100 * (1 - fpr), 100 * s);
end
L = {sprintf(['K2-0 bounds (descriptive, not KPI 2; the file holds no per-window values), %% per held-out threat: ' ...
    'flagged-or-same-countermeasure share between max(1 - FPR95, s) and min(1, 1 - FPR95 + s), FPR95 of the nested pick ' ...
    'at 95%% retention, s the same-countermeasure share under the rule''s mapping over all the threat''s mapped frames, ' ...
    'not over the unflagged ones: %s; mean %.1f-%.1f'], strjoin(parts, ', '), 100 * mean(lo), 100 * mean(hi))};
end

function y = same_cm(top, k)
% Windows whose top known class has threat k's countermeasure, when that is not no_action.
cm = rule_based_policy(k);
top = cellstr(top(:));
y = false(numel(top), 1);
if strcmp(cm, 'no_action') || isempty(top), return; end
[u, ~, ic] = unique(top);
y = cellfun(@(c) strcmp(rule_based_policy(c), cm), u(:));
y = y(ic(:));
end

function a = aurc(w)
% Area under the risk-coverage curve: the mean selective risk over every acceptance cut.
conf = [w.kn(:); w.un(:)];
top = [cellstr(w.top_kn(:)); cellstr(w.top_un(:))];
tru = [cellstr(w.y_kn(:)); repmat({w.threat}, numel(w.un), 1)];
[u, ~, ic] = unique([top; tru]);
cmu = cellfun(@rule_based_policy, u(:), 'UniformOutput', false);
n = numel(conf);
fail = ~strcmp(cmu(ic(1:n)), cmu(ic(n + 1:end)));
[~, o] = sort(conf, 'descend');
a = mean(cumsum(fail(o)) ./ (1:n)');
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
