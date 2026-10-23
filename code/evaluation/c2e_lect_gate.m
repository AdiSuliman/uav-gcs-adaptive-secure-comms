function G = c2e_lect_gate(P, S, txtP, txtS)
%C2E_LECT_GATE  The consistency gate of the isolated C2e reading (docs/c2e_lect_protocol.md on
%   branch lect-kpi): every number profile 1's own C2e produced must come out of the isolated run
%   unchanged, so the readings added beside them come from the same episodes, draws and policies.
%   P, S   results/policy_evaluation.mat loaded as structs: profile 1's own (P) and the isolated
%          run's (S)
%   txtP, txtS  results/policy_evaluation.txt of each, one cell per line
%   Exact equality (isequaln), no tolerance. The differences allowed, fixed before profile 1's
%   C2e ran:
%     - POL and LBL: S appends rule_core and blind_core after P's policies
%     - per episode (RES, RW, ALL): S's results carry per_post, dlv_post, t_rec_det and
%       recoverable_core besides P's fields; the cells of the two appended policies
%     - KP.far, KP.far_testpools, KP.far_cleanpools: S's rows of the two appended policies
%     - the variable lect_in
%     - the text: the 'Generated:' line, and S's rows of the two appended policies
%   Anything else that differs is a mismatch. G.pass, G.mismatch (one line each), G.n_compared
%   (values compared), G.lines (the report).
EXTRA_POL = {'rule_core', 'blind_core'};
EXTRA_LBL = {'core: rule + escalation', 'core: no detector + escalation'};
EXTRA_FIELDS = {'per_post', 'dlv_post', 't_rec_det', 'recoverable_core'};
EXTRA_VARS = {'lect_in'};
FAR_FIELDS = {'far', 'far_testpools', 'far_cleanpools'};
VARS = {'RES', 'RW', 'POL', 'LBL', 'set_names', 'fixed_best', 'tab', 'iDQN', 'KP', 'iThreat', 'ALL', 'top_cfg'};
mm = {}; n = 0;

% Variables
miss = setdiff(fieldnames(P), fieldnames(S));
if ~isempty(miss), mm{end+1} = sprintf('variables missing in the isolated run: %s', jn(miss)); end
ext = setdiff(setdiff(fieldnames(S), fieldnames(P)), EXTRA_VARS);
if ~isempty(ext), mm{end+1} = sprintf('variables not allowed in the isolated run: %s', jn(ext)); end
miss = setdiff(VARS, fieldnames(P));
if ~isempty(miss)
    mm{end+1} = sprintf('profile 1''s file lacks %s', jn(miss));
    G = finish(mm, n); return
end
if ~all(isfield(S, VARS)), G = finish(mm, n); return; end

% Policies: P's, then the two appended ones
nP = numel(P.POL);
if numel(S.POL) ~= nP + 2 || ~isequal(S.POL(1:min(nP, end)), P.POL) || ~isequal(S.POL(nP+1:end), EXTRA_POL)
    mm{end+1} = sprintf('POL: profile 1 {%s}, isolated {%s}; expected profile 1''s then {%s}', strjoin(P.POL, ', '), ...
        strjoin(S.POL, ', '), strjoin(EXTRA_POL, ', '));
    G = finish(mm, n); return
end
if ~isequal(S.LBL(1:nP), P.LBL) || ~isequal(S.LBL(nP+1:end), EXTRA_LBL)
    mm{end+1} = 'LBL: the isolated labels are not profile 1''s followed by the two core labels';
end
n = n + 2;
for v = {'set_names', 'fixed_best', 'tab', 'iDQN', 'iThreat', 'top_cfg'}
    n = n + 1;
    if ~isequaln(P.(v{1}), S.(v{1})), mm{end+1} = sprintf('%s differs', v{1}); end %#ok<AGROW>
end

% Per episode
if ~isequal(size(S.RES), [size(P.RES, 1), nP + 2])
    mm{end+1} = sprintf('RES: %s cells in the isolated run, %s expected', mat2str(size(S.RES)), mat2str([size(P.RES, 1), nP + 2]));
else
    for si = 1:size(P.RES, 1)
        for pk = 1:nP
            [mm, n] = cmp_struct(P.RES{si, pk}, S.RES{si, pk}, sprintf('RES{%d,%d} (%s, %s)', si, pk, ...
                txt_of(P.set_names, si), P.POL{pk}), EXTRA_FIELDS, mm, n);
        end
    end
end
if isempty(P.RW)
    if ~isempty(S.RW), mm{end+1} = 'RW: empty in profile 1, not in the isolated run'; end
elseif numel(S.RW) ~= nP + 2
    mm{end+1} = sprintf('RW: %d cells in the isolated run, %d expected', numel(S.RW), nP + 2);
else
    for pk = 1:nP, [mm, n] = cmp_struct(P.RW{pk}, S.RW{pk}, sprintf('RW{%d} (%s)', pk, P.POL{pk}), EXTRA_FIELDS, mm, n); end
end
if numel(S.ALL) ~= nP + 2
    mm{end+1} = sprintf('ALL: %d cells in the isolated run, %d expected', numel(S.ALL), nP + 2);
else
    for pk = 1:nP, [mm, n] = cmp_struct(P.ALL{pk}, S.ALL{pk}, sprintf('ALL{%d} (%s)', pk, P.POL{pk}), EXTRA_FIELDS, mm, n); end
end

% KPI struct
fp = fieldnames(P.KP); fs = fieldnames(S.KP);
if ~isempty(setxor(fp, fs)), mm{end+1} = sprintf('KP fields differ: %s', jn(setxor(fp, fs))); end
for f = intersect(fp, fs)'
    n = n + 1;
    if ismember(f{1}, FAR_FIELDS)
        a = P.KP.(f{1}); b = S.KP.(f{1});
        if isempty(a) && isempty(b), continue; end
        if ~isstruct(a) || ~isstruct(b) || ~isfield(b, 'policy') || (~isempty(a) && ~isfield(a, 'policy'))
            mm{end+1} = sprintf('KP.%s: not a per-policy struct array in both', f{1}); continue %#ok<AGROW>
        end
        keep = ismember({b.policy}, P.LBL);
        if ~isequaln(b(keep), a), mm{end+1} = sprintf('KP.%s differs on profile 1''s policies', f{1}); end %#ok<AGROW>
        if ~isequal({b(~keep).policy}, EXTRA_LBL)
            mm{end+1} = sprintf('KP.%s: rows beside profile 1''s policies {%s}, expected {%s}', f{1}, ...
                strjoin({b(~keep).policy}, ', '), strjoin(EXTRA_LBL, ', ')); %#ok<AGROW>
        end
    elseif ~isequaln(P.KP.(f{1}), S.KP.(f{1}))
        mm{end+1} = sprintf('KP.%s differs%s', f{1}, diff_txt(P.KP.(f{1}), S.KP.(f{1}))); %#ok<AGROW>
    end
end

% Text
a = strip_lines(txtP, {}); b = strip_lines(txtS, EXTRA_LBL);
n = n + numel(a);
if ~isequal(a, b)
    k = find(~strcmp(a(1:min(end, numel(b))), b(1:min(end, numel(a)))), 1);
    if isempty(k), k = min(numel(a), numel(b)) + 1; end
    mm{end+1} = sprintf('policy_evaluation.txt: %d lines in profile 1, %d in the isolated run without the allowed ones; first difference at line %d: "%s" vs "%s"', ...
        numel(a), numel(b), k, txt_of(a, k), txt_of(b, k));
end
G = finish(mm, n);
end

function [mm, n] = cmp_struct(a, b, where, extra, mm, n)
% Every field of a equal in b; b's other fields only among extra.
if ~isstruct(a) || ~isstruct(b), mm{end+1} = sprintf('%s: not a struct in both', where); return; end
miss = setdiff(fieldnames(a), fieldnames(b));
if ~isempty(miss), mm{end+1} = sprintf('%s: fields missing in the isolated run: %s', where, jn(miss)); end
ext = setdiff(setdiff(fieldnames(b), fieldnames(a)), extra);
if ~isempty(ext), mm{end+1} = sprintf('%s: fields not allowed: %s', where, jn(ext)); end
for f = intersect(fieldnames(a), fieldnames(b))'
    n = n + numel(a.(f{1}));
    if ~isequaln(a.(f{1}), b.(f{1})), mm{end+1} = sprintf('%s.%s differs%s', where, f{1}, diff_txt(a.(f{1}), b.(f{1}))); end %#ok<AGROW>
end
end

function s = diff_txt(a, b)
% How two values differ (diagnosis only; the gate never uses it).
s = '';
if (isnumeric(a) || islogical(a)) && (isnumeric(b) || islogical(b)) && isequal(size(a), size(b))
    d = double(a(:)) - double(b(:)); k = ~(isnan(double(a(:))) & isnan(double(b(:)))) & (d ~= 0 | isnan(d));
    s = sprintf(' (%d of %d values, largest absolute difference %g)', sum(k), numel(a), max([abs(d(k)); 0]));
elseif ~isequal(size(a), size(b))
    s = sprintf(' (size %s vs %s)', mat2str(size(a)), mat2str(size(b)));
end
end

function L = strip_lines(L, lbl)
% The text without its 'Generated:' line and without the rows of the labels lbl.
L = reshape(cellstr(L), [], 1);
L = L(~startsWith(L, 'Generated: '));
for k = 1:numel(lbl)
    L = L(~startsWith(strtrim(L), [lbl{k} ' ']));
end
end

function s = jn(c)
% A list of names, one line.
s = strjoin(reshape(cellstr(c), 1, []), ', ');
end

function s = txt_of(c, k)
if k <= numel(c), s = c{k}; else, s = '<none>'; end
end

function G = finish(mm, n)
G.pass = isempty(mm);
G.mismatch = mm(:);
G.n_compared = n;
if G.pass
    G.lines = {sprintf('GATE PASS: %d values and lines of profile 1''s C2e equal in the isolated run', n)};
else
    G.lines = [{sprintf('GATE FAIL: %d mismatches (%d values and lines compared); the reading stops', numel(mm), n)}; ...
        strcat({'  '}, mm(:))];
end
end
