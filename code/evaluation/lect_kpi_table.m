function [T, lines] = lect_kpi_table(res_dir)
%LECT_KPI_TABLE  The lecturer's KPI table and three figures from the saved results (a pure reader).
%   [T, lines] = lect_kpi_table(res_dir)
%   res_dir  the results folder (default 'results'). Only saved outputs are read, nothing is
%   recomputed and no test-set data is opened:
%     policy_evaluation.mat   KP.lect (lect_kpis.m) and KP.far (system false alarms)
%     core_cnn.mat, core_cnn.txt   the three-state CNN's single reading (train_core_cnn.m, B3c)
%     phy_validation.txt      the BER model against theory
%     low_ebno_mark.txt, lect_kpis_by_ebno.mat   the link-limited mark and Line B (D99)
%     core_bw/core_bw_kpis.mat   CORE_BW's controlled-bandwidth reading (headline of KPI 5 and 8, D106)
%   Verdict words and intervals are copied from the saved structs (lect_kpis.m, train_core_cnn.m,
%   the phy report, experiment_core_bw.m); the one word not in a saved struct, the system
%   false-alarm word, follows the one-sided 95% bound (D103): 'MET (bound <= 5%)' when the bound
%   is at most 5%, 'point estimate only' when only the point is, 'NOT MET' otherwise. A missing
%   input gives rows that read 'pending (...)'.
%   Writes in res_dir:
%     lect_kpi_table.txt, lect_kpi_table.csv   the table in the proposal's numbering
%     lect_kpi_per.png        PER after onset and PER reduction vs the static link, 95% intervals
%     lect_kpi_recovery.png   recovery time from detection (Line A, and Line B when D99 is read)
%     lect_kpi_goodput.png    goodput after onset in bit/s with 95% intervals
%   Proposal numbering (D92, D105): 1 BER model vs theory, 2 macro-F1 >= 85%, 3 false alarms
%   <= 5% in clean states, 4 recall >= 85% per jamming type, 5 PER reduction >= 30% vs the static
%   link, 6 recovery time, 7 goodput, 8 the CNN's contribution.
%   Each row names the network that produced it and the policy pair. KPI 2-4 come from the
%   three-state CNN (B3c). KPI 5-8 of C2e are read with the hybrid detector's classes on the core
%   action set (rule_core against none and blind_core, D105). CORE_BW puts the three-state CNN in
%   the loop (rule_core3, D106): its rows are the headline of KPI 5 and 8 against the
%   validation-tuned blind_core, rule_core there is labelled 'hybrid, secondary', and
%   rule_core3 - rule_core is descriptive, with no verdict word. Without rule_core3 in the file
%   (the fallback of D106 point 9) rule_core carries the CORE_BW rows as D105 registered them.
%   The system false alarms (KP.far) are not proposal KPI 3: they are listed apart as 'extension:
%   system FA (project KPI 6, D103)'. T.rows is the struct array behind the csv, T.files the
%   files written, T.pending the rows that read 'pending'; lines is the text file's content.
if nargin < 1 || isempty(res_dir), res_dir = 'results'; end
res_dir = char(res_dir);
if ~isfolder(res_dir), error('lect_kpi_table:folder', 'lect_kpi_table: %s is not a folder', res_dir); end
[~, fa] = fileattrib(res_dir); res_abs = fa.Name;
pth = @(f) fullfile(res_abs, f);
F = struct('pol', 'policy_evaluation.mat', 'phy', 'phy_validation.txt', 'cnn', 'core_cnn.mat', 'cnn_txt', 'core_cnn.txt', ...
    'mark', 'low_ebno_mark.txt', 'd99', 'lect_kpis_by_ebno.mat', 'bw', fullfile('core_bw', 'core_bw_kpis.mat'));

%% Inputs (read only)
P = read_policy(pth(F.pol));
Cn = read_mat(pth(F.cnn), 'core');
D = read_mat(pth(F.d99), {'M', 'S'});
Bw = read_mat(pth(F.bw), 'KP');
mk = read_mark(pth(F.mark), D, P);
lect = P.ok && isfield(P.KP, 'lect') && isstruct(P.KP.lect) && ~isempty(P.KP.lect);
lineB = D.ok && isfield(D.S, 'line_b') && isstruct(D.S.line_b);

%% Rows
rows = {};
rows = [rows, phy_rows(pth(F.phy), F.phy)];
rows = [rows, cnn_rows(Cn, F.cnn)];
rows = [rows, far_rows(P, F.pol)];
if lect
    L = P.KP.lect;
    if ~isfield(L, 'core') || isempty(L.core)
        for k = 5:8
            rows{end+1} = row('kpi', k, 'reading', 'core action set readings (rule_core, blind_core)', 'network', 'HYB_LOOP', ...
                'verdict', sprintf('pending (%s: KP.lect.core is empty, rule_core and blind_core did not run)', F.pol), ...
                'role', 'pending', 'source', F.pol); %#ok<AGROW>
        end
    end
    rows = [rows, lect_rows(L, ctx_of(L, 'core', 'A', F.pol))];
    if lineB, rows = [rows, lect_rows(D.S.line_b, ctx_of(L, 'core', 'B', F.d99))]; end
    rows = [rows, lect_rows(L, ctx_of(L, 'core36', 'A', F.pol))];
    rows = [rows, lect_rows(L, ctx_of(L, 'full', 'A', F.pol))];
    if lineB, rows = [rows, lect_rows(D.S.line_b, ctx_of(L, 'full', 'B', F.d99))]; end
else
    why = pend_why(P, F.pol, 'KP.lect (lect_kpis.m)');
    for k = 5:8
        rows{end+1} = row('kpi', k, 'reading', 'all readings of KPI 5-8 (lect_kpis.m)', 'network', 'HYB_LOOP', 'verdict', why, ...
            'role', 'pending', 'source', F.pol); %#ok<AGROW>
    end
end
if lect && ~lineB
    rows{end+1} = row('kpi', 6, 'reading', 'detection -> PER restored, non-link-limited points (D99 Line B, the headline)', ...
        'network', 'HYB_LOOP', 'line', 'B', 'verdict', pend_why(D, F.d99, 'line_b (D99 reading)'), 'role', 'pending', 'source', F.d99); %#ok<AGROW>
end
rows = [rows, bw_rows(Bw, F.bw)];
rows = [rows{:}];
rk = arrayfun(@(r) role_rank(r.role), rows);
[~, ix] = sortrows([[rows.kpi]', rk(:)]);
rows = rows(ix);

%% Files
nm = {'', 'BER model vs theory', 'Macro-F1, three link states', 'False alarm rate in clean states', ...
    'Recall per jamming type', 'PER reduction vs the static link', 'Recovery time from detection', 'Goodput', ...
    'CNN contribution vs the conventional adaptive link', 'extension: system FA (project KPI 6, D103)'};
lines = text_lines(rows, nm, res_abs, P, F, mk, Cn, lect);
T = struct('rows', {rows}, 'files', {{}}, 'pending', {find(strncmp({rows.verdict}, 'pending', 7))});
f_txt = pth('lect_kpi_table.txt'); f_csv = pth('lect_kpi_table.csv');
write_lines(f_txt, lines);
write_csv(f_csv, rows, nm, Cn);
T.files = {f_txt, f_csv};
if lect
    L = P.KP.lect;
    LB = []; if lineB, LB = D.S.line_b; end
    T.files{end+1} = fig_per(L, pth('lect_kpi_per.png'));
    T.files{end+1} = fig_rec(L, LB, pth('lect_kpi_recovery.png'));
    T.files{end+1} = fig_gput(L, pth('lect_kpi_goodput.png'));
end
fprintf('%s\n', lines{:});
fprintf('Saved %s\n', strjoin(T.files, ', '));
end

%% ===================== Inputs =====================
function P = read_policy(f)
P = struct('ok', false, 'why', 'missing', 'KP', [], 'POL', {{}}, 'LBL', {{}}, 'iDQN', NaN);
if ~isfile(f), return; end
try
    v = who('-file', f);
    want = intersect({'KP', 'POL', 'LBL', 'iDQN'}, v);
    S = load(f, want{:});
    if ~isfield(S, 'KP'), P.why = 'no KP in the file'; return; end
    P.KP = S.KP; P.ok = true; P.why = '';
    if isfield(S, 'POL'), P.POL = S.POL; end
    if isfield(S, 'LBL'), P.LBL = S.LBL; end
    if isfield(S, 'iDQN'), P.iDQN = S.iDQN; end
catch err
    P.why = ['unreadable: ' err.message];
end
end

function M = read_mat(f, names)
% The variables names of a mat file. One name that holds a struct: its fields; several names:
% one field each. M.ok false with M.why when the file is missing, unreadable or lacks a name.
M = struct('ok', false, 'why', 'missing');
if ~isfile(f), return; end
names = cellstr(names);
try
    have = who('-file', f);
    miss = setdiff(names, have);
    if ~isempty(miss), M.why = sprintf('no %s in the file', strjoin(miss, ', ')); return; end
    S = load(f, names{:});
    if isscalar(names) && isstruct(S.(names{1})), M = S.(names{1}); else, M = S; end
    M.ok = true; M.why = '';
catch err
    M = struct('ok', false, 'why', ['unreadable: ' err.message]);
end
end

function mk = read_mark(f, D, P)
% The link-limited mark of D99, written before policy_evaluation.mat was opened.
mk = struct('ok', false, 'ebno', [], 'tag', {{}}, 'clean_fer', [], 'src', '');
if isfile(f)
    t = splitlines(fileread(f));
    t = strtrim(t(~cellfun(@isempty, strtrim(t)) & ~startsWith(strtrim(t), '#')));
    for i = 1:numel(t)
        c = strsplit(t{i}, ' ');
        if numel(c) == 5 && all(~isnan(str2double(c(1:4))))
            mk.ebno(end+1) = str2double(c{1}); mk.clean_fer(end+1) = str2double(c{2}); mk.tag{end+1} = c{5}; %#ok<AGROW>
        end
    end
    mk.ok = ~isempty(mk.ebno); mk.src = 'low_ebno_mark.txt';
elseif D.ok && isfield(D, 'M') && isfield(D.M, 'tag') && P.ok && isfield(P.KP, 'ebno') && numel(P.KP.ebno) == numel(D.M.tag)
    mk.ebno = P.KP.ebno(:)'; mk.tag = D.M.tag(:)'; mk.clean_fer = D.M.clean_fer(:)'; mk.ok = true;
    mk.src = 'lect_kpis_by_ebno.mat';
end
end

function s = pend_why(S, f, what)
if isfield(S, 'ok') && ~S.ok
    s = sprintf('pending (%s: %s)', f, S.why);
else
    s = sprintf('pending (%s has no %s)', f, what);
end
end

%% ===================== Rows =====================
function r = row(varargin)
r = struct('kpi', NaN, 'reading', '', 'network', '', 'policy', '', 'versus', '', 'pair_set', '', 'action_set', '', ...
    'line', '-', 'episodes', '', 'n', NaN, 'value', NaN, 'lo', NaN, 'hi', NaN, 'unit', '', 'p90', NaN, 'never_pct', NaN, ...
    'verdict', '', 'role', '', 'source', '', 'note', '');
for i = 1:2:numel(varargin), r.(varargin{i}) = varargin{i+1}; end
end

function k = role_rank(role)
switch role
    case {'headline', 'verdict', 'pending'}, k = 1;
    case {'measured', 'system'}, k = 2;
    case 'beside', k = 3;
    case 'second_line', k = 4;
    case {'secondary', 'extension'}, k = 5;
    case 'descriptive', k = 6;
    otherwise, k = 7;
end
end

function s = net_text(k)
switch k
    case 'CNN3', s = 'three-state CNN on spectrograms (B3c, core_cnn.mat)';
    case 'HYB_FRAMES', s = 'hybrid detector, 11 classes (monitor class), on the same frames as B3c';
    case 'HYB_LOOP', s = ['hybrid detector, 11 classes (trained_detector.mat, temporally fused) driving the rule; ' ...
            'not the three-state CNN (D105)'];
    case 'CNN3_LOOP', s = ['three-state CNN (B3c model, mean log-probability over N = 3 cycles) driving the same rule in the loop; ' ...
            'rule_core3, CORE_BW only (D106)'];
    case 'LINK', s = 'link metrics only (no detector: every cycle reads unknown), same decision layer';
    case 'NONE', s = 'none (static link, no response)';
    case 'PHY', s = 'physical-layer BER model (no network)';
    otherwise, s = k;
end
end

function s = pair_text(kind)
switch kind
    case 'core', s = 'core pair (D105): rule_core, blind_core, static none';
    case 'core3', s = 'core3 pair, CORE_BW (D106): rule_core3, blind_core (validation-tuned), static none';
    case 'full', s = 'extension pair (D105): rule_esc, blind_esc, static none';
    otherwise, s = '';
end
end

function R = phy_rows(f, name)
R = {};
if ~isfile(f)
    R = {row('kpi', 1, 'reading', 'BER against theory', 'network', 'PHY', 'verdict', sprintf('pending (%s: missing)', name), ...
        'role', 'pending', 'source', name)};
    return;
end
t = splitlines(fileread(f));
cur = ''; ok = 0; n = 0;
for i = 1:numel(t)
    m = regexp(t{i}, '^(V\d+)\s+(.*?)\s+BER\s', 'tokens', 'once');
    if ~isempty(m), cur = strtrim([m{1} ' ' m{2}]); end
    g = regexp(t{i}, 'gap\s*([+-]?\d+\.?\d*)\s*dB\s*\(standard error\s*([\d.]+)\s*dB\)\s*->\s*(PASS|FAIL)', 'tokens', 'once');
    if ~isempty(g) && ~isempty(cur)
        n = n + 1; ok = ok + strcmp(g{3}, 'PASS');
        R{end+1} = row('kpi', 1, 'reading', ['gap to theory, ' cur], 'network', 'PHY', 'value', str2double(g{1}), 'unit', 'dB', ...
            'verdict', g{3}, 'role', 'measured', 'source', name, 'note', sprintf('standard error %s dB', g{2})); %#ok<AGROW>
        cur = '';
    end
end
if n == 0
    R = {row('kpi', 1, 'reading', 'BER against theory', 'network', 'PHY', 'verdict', sprintf('pending (%s: no gap lines)', name), ...
        'role', 'pending', 'source', name)};
    return;
end
w = 'FAIL'; if ok == n, w = 'PASS'; end
R = [{row('kpi', 1, 'reading', 'BER model against theory, validation cases with a gap line', 'network', 'PHY', 'n', n, ...
    'value', ok, 'unit', 'cases passed', 'verdict', sprintf('%s (%d/%d)', w, ok, n), 'role', 'verdict', 'source', name)}, R];
end

function R = cnn_rows(C, name)
R = {};
if ~C.ok
    for k = 2:4
        R{end+1} = row('kpi', k, 'reading', 'three link states, three-state CNN', 'network', 'CNN3', 'verdict', ...
            sprintf('pending (%s: %s)', name, C.why), 'role', 'pending', 'source', name); %#ok<AGROW>
    end
    return;
end
thr = struct('macro_f1', 0.85, 'recall', 0.85, 'false_alarm', 0.05);
if isfield(C, 'thr') && isstruct(C.thr), thr = C.thr; end
eps_txt = sprintf('fourth test set (%s), read once; every Eb/N0', C.test_set);
net = {'HYB_FRAMES', 'CNN3', 'CNN3'};
how = {'hybrid monitor class', sprintf('windowed, N = %d cycles (official)', C.N), 'per frame'};
role = {'secondary', 'verdict', 'extension'};
for r = [2 3 1]
    M = C.metrics{r};
    if isempty(M)
        for k = 2:4
            R{end+1} = row('kpi', k, 'reading', ['three link states, ' how{r}], 'network', net{r}, 'verdict', ...
                'pending (no hybrid reading of this set before it, docs/core_cnn_no_b3r.txt)', 'role', 'pending', ...
                'source', name); %#ok<AGROW>
        end
        continue;
    end
    B = C.boot; V = C.verdicts;
    base = {'network', net{r}, 'policy', how{r}, 'episodes', eps_txt, 'role', role{r}, 'source', name, 'unit', '%'};
    R{end+1} = row(base{:}, 'kpi', 2, 'reading', 'macro-F1, clean / narrowband / wideband', 'value', 100 * M.macro_f1, ...
        'lo', 100 * B.macro_f1(r, 1), 'hi', 100 * B.macro_f1(r, 2), 'verdict', V{r, 1}, 'n', sum(M.n), ...
        'note', sprintf('target >= %g%%; frames %s', 100 * thr.macro_f1, mat2str(M.n))); %#ok<AGROW>
    R{end+1} = row(base{:}, 'kpi', 3, 'reading', 'false alarms, clean frames read as another state', 'value', 100 * M.fa, ...
        'lo', 100 * B.fa(r, 1), 'hi', 100 * B.fa(r, 2), 'verdict', V{r, 4}, 'n', M.n(1), ...
        'note', sprintf('target <= %g%%; read as a jamming state %s%% [%s, %s]', 100 * thr.false_alarm, ...
        nf('%.2f', 100 * M.fa_jam), nf('%.2f', 100 * B.fa_jam(r, 1)), nf('%.2f', 100 * B.fa_jam(r, 2)))); %#ok<AGROW>
    for s = 2:3
        R{end+1} = row(base{:}, 'kpi', 4, 'reading', sprintf('recall, %s', C.states{s}), 'value', 100 * M.recall(s), ...
            'lo', 100 * B.recall(r, s, 1), 'hi', 100 * B.recall(r, s, 2), 'verdict', V{r, s}, 'n', M.n(s), ...
            'note', sprintf('target >= %g%%', 100 * thr.recall)); %#ok<AGROW>
    end
end
end

function R = far_rows(P, name)
% System false alarms (KP.far): episodes with a change on the clean flights of the project's KPI 6,
% one-sided 95% Clopper-Pearson bound. An extension label of its own (D103), never proposal KPI 3.
% The word follows the bound: at most 5% -> met; only the point estimate at most 5% -> 'point
% estimate only'; otherwise not met.
R = {};
if ~P.ok || ~isfield(P.KP, 'far') || isempty(P.KP.far) || isempty(P.POL) || isempty(P.LBL)
    R = {row('kpi', kpi_fa(), 'reading', 'system false alarms on clean flights (KP.far)', 'network', 'HYB_LOOP', 'verdict', ...
        pend_why(P, name, 'KP.far'), 'role', 'pending', 'source', name)};
    return;
end
keys = {'rule_core', 'blind_core', 'none', 'rule_esc', 'blind_esc'};
if isfinite(P.iDQN) && ~isempty(P.POL) && P.iDQN <= numel(P.POL), keys{end+1} = P.POL{P.iDQN}; end
keys = unique(keys, 'stable');
for k = 1:numel(keys)
    j = find(strcmp(P.POL, keys{k}), 1);
    if isempty(j), continue; end
    q = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{j}));
    if isempty(q), continue; end
    q = q(1);
    w = 'NOT MET';
    if q.upper <= 0.05, w = 'MET (bound <= 5%)'; elseif q.p <= 0.05, w = 'point estimate only'; end
    ph = '';
    if isfield(q, 'rate') && isstruct(q.rate) && isfield(q.rate, 'per_hour')
        ph = sprintf('; %s false changes per hour', nf('%.0f', q.rate.per_hour));
    end
    if q.n < 600                                     % measure_all_kpis.m: the project's KPI 6 also needs 600 episodes
        ph = sprintf('%s; fewer than 600 episodes, so the project''s own KPI 6 (kpi_summary) does not pass on these counts', ph);
    end
    net = pol_net(keys{k});
    R{end+1} = row('kpi', kpi_fa(), 'reading', 'system false alarms: episodes with a change on clean flights', 'network', net, ...
        'policy', keys{k}, 'pair_set', pair_text(pair_kind(keys{k})), 'action_set', action_text(keys{k}), ...
        'episodes', 'independent clean flights of KPI 6 above the KPI 1 Eb/N0 threshold', 'n', q.n, 'value', 100 * q.p, ...
        'hi', 100 * q.upper, 'unit', '%', 'verdict', w, 'role', 'extension', 'source', name, ...
        'note', sprintf('%d/%d episodes; hi = one-sided 95%% Clopper-Pearson upper bound; target <= 5%%; the word follows the bound%s%s', ...
        q.k, q.n, ph, sec_note(keys{k}))); %#ok<AGROW>
end
end

function R = bw_rows(Bw, name)
% CORE_BW's reading: the headline of KPI 5 and 8 (equal tuning budget, D105/D106) and its PER verdicts.
% With rule_core3 in the saved struct (D106) it carries the headline against the validation-tuned
% blind_core, rule_core is 'hybrid, secondary' and rule_core3 - rule_core is descriptive. Without it
% (D106 point 9, the fallback) rule_core carries them as D105 registered.
if ~Bw.ok || ~isfield(Bw, 'primary')
    R = {row('kpi', 8, 'reading', 'CNN contribution, rule_core3 against the validation-tuned blind_core (CORE_BW)', ...
        'network', 'CNN3_LOOP', 'policy', 'rule_core3', 'versus', 'blind_core', 'pair_set', pair_text('core3'), ...
        'verdict', 'pending (CORE_BW)', 'role', 'pending', 'source', name, ...
        'note', 'CORE_BW runs after profile 1; C2e rows carry the hybrid label')};
    return;
end
K = Bw.primary; R = {};
src = [name ' (KP.primary)'];
c3 = isfield(K, 'per') && isstruct(K.per) && ~isempty(K.per) && any(strcmp({K.per.policy}, 'rule_core3'));
if c3
    hp = 'rule_core3'; hnet = 'CNN3_LOOP'; hpair = pair_text('core3');
else
    hp = 'rule_core'; hnet = 'HYB_LOOP'; hpair = 'core pair, CORE_BW (D105 headline), equal tuning budget';
end
sec = ' (hybrid, secondary)';
if isfield(K, 'cnn') && isstruct(K.cnn)
    R = [R, bw_contrib(K.cnn, hp, 'blind_core', hnet, hpair, 'headline', '', 'analysis, no target', src)];
end
if c3
    if isfield(K, 'cnn_hybrid') && isstruct(K.cnn_hybrid)
        R = [R, bw_contrib(K.cnn_hybrid, 'rule_core', 'blind_core', 'HYB_LOOP', 'core pair, CORE_BW, hybrid detector', ...
            'secondary', sec, 'analysis, no target', src)];
    end
    if isfield(K, 'cnn_3vs') && isstruct(K.cnn_3vs)
        R = [R, bw_contrib(K.cnn_3vs, 'rule_core3', 'rule_core', 'CNN3_LOOP', ...
            'rule_core3 against rule_core: one decision layer, only the class source differs', 'descriptive', '', ...
            'descriptive, no verdict word', src)];
    end
end
if isfield(K, 'per') && isstruct(K.per) && isfield(K.per, 'verdict')
    pols = {'rule_core'};
    if c3, pols = {'rule_core3', 'rule_core'}; end
    for i = 1:numel(pols)
        pl = pols{i};
        isHyb = c3 && strcmp(pl, 'rule_core');
        net = hnet; pr = hpair; tag = '';
        if isHyb, net = 'HYB_LOOP'; pr = 'core pair, CORE_BW, hybrid detector'; tag = sec; end
        for q = K.per(strcmp({K.per.policy}, pl))
            if strcmp(q.type, 'pooled') && ~c3, continue; end     % D105's rows: the two jamming types only
            role = 'beside';
            if strcmp(q.type, 'pooled'), role = 'second_line'; end
            if isHyb, role = 'secondary'; end
            R{end+1} = row('kpi', 5, 'reading', sprintf('PER reduction vs the static link, %s (CORE_BW controlled cells)%s', q.type, tag), ...
                'network', net, 'policy', pl, 'versus', 'none', 'pair_set', pr, ...
                'line', 'A', 'episodes', 'CORE_BW recoverable scenarios', 'n', q.n, 'value', 100 * q.red, 'lo', 100 * q.lo, ...
                'hi', 100 * q.hi, 'unit', '%', 'verdict', q.verdict, 'role', role, 'source', src, ...
                'note', 'controlled-bandwidth reading; neither it nor C2e replaces the other (D105, D106)'); %#ok<AGROW>
        end
    end
end
if isempty(R), R = {row('kpi', 8, 'reading', 'CORE_BW reading', 'network', 'HYB_LOOP', 'verdict', ...
        sprintf('pending (%s has no KP.primary.cnn)', name), 'role', 'pending', 'source', name)}; end
end

function R = bw_contrib(C, pol, vs, net, pair, role, tag, word, src)
% KPI 8 rows of one CORE_BW contribution struct (pooled, narrowband, wideband): PER reduction of pol
% against vs, the goodput difference and the detection -> restored difference, with 95% intervals.
R = {};
for t = {'pooled', 'narrowband', 'wideband'}
    if ~isfield(C, t{1}), continue; end
    c = C.(t{1});
    b = {'kpi', 8, 'network', net, 'policy', pol, 'versus', vs, 'pair_set', pair, 'line', 'A', ...
        'episodes', sprintf('CORE_BW recoverable scenarios, %s', t{1}), 'role', role, 'source', src};
    R{end+1} = row(b{:}, 'reading', sprintf('PER reduction of %s against %s, %s%s', pol, vs, t{1}, tag), 'value', 100 * c.per_red(1), ...
        'lo', 100 * c.per_red(2), 'hi', 100 * c.per_red(3), 'unit', '%', 'verdict', word); %#ok<AGROW>
    R{end+1} = row(b{:}, 'reading', sprintf('goodput difference %s - %s, %s%s', pol, vs, t{1}, tag), 'value', c.gput(1), ...
        'lo', c.gput(2), 'hi', c.gput(3), 'unit', 'bit/s', 'verdict', word); %#ok<AGROW>
    R{end+1} = row(b{:}, 'reading', sprintf('detection -> restored difference %s - %s, %s%s', pol, vs, t{1}, tag), ...
        'value', c.trec(1), 'lo', c.trec(2), 'hi', c.trec(3), 'unit', 'cycles', 'n', c.n_both, 'verdict', word); %#ok<AGROW>
end
end

function c = ctx_of(L, kind, line, src)
% The reading context of one lect_kpis.m output block.
c = struct('kind', kind, 'line', line, 'src', [src ' (KP.lect' ternary(strcmp(src, 'lect_kpis_by_ebno.mat'), ' on Line B', '') ')'], ...
    'period_ms', L.period_ms, 'target', L.target_pct, 'payload', L.payload_bps, 'actions', '');
if isfield(L, 'core') && ~isempty(L.core), c.actions = strjoin(L.core.actions, ', '); end
end

function R = lect_rows(L, c)
% KPI 5-8 rows of one lect_kpis.m output L (or its Line B twin): the core block, the core block on the
% 36-configuration mask, or the full action set.
R = {};
switch c.kind
    case 'core'
        if ~isfield(L, 'core') || isempty(L.core), return; end
        S = L.core; tgt = 'rule_core'; conv = 'blind_core';
        aset = sprintf('core {%s}', c.actions); rec = 'some core configuration restores the geometry';
    case 'core36'
        if ~isfield(L, 'core') || isempty(L.core) || ~isfield(L.core, 'all36'), return; end
        S = L.core.all36; tgt = 'rule_core'; conv = 'blind_core';
        aset = sprintf('core {%s}', c.actions); rec = 'some of the 36 configurations restores the geometry';
    otherwise
        S = L; tgt = 'rule_esc'; conv = 'blind_esc';
        aset = '36 configurations'; rec = 'some of the 36 configurations restores the geometry';
end
if strcmp(c.line, 'B'), rec = [rec '; non-link-limited Eb/N0 points only']; end
c.tgt = tgt; c.conv = conv; c.aset = aset; c.rec = rec;
c.pair = pair_text(ternary(strncmp(c.kind, 'core', 4), 'core', 'full'));
switch [c.kind c.line]
    case 'coreA', r5 = 'verdict'; r6 = 'measured'; r7 = 'measured'; r8 = 'secondary';
    case 'coreB', r5 = 'second_line'; r6 = 'headline'; r7 = 'measured'; r8 = 'second_line';
    otherwise, r5 = 'extension'; r6 = 'extension'; r7 = 'extension'; r8 = 'extension';
end
if strcmp(c.kind, 'core36'), c.pair = [c.pair '; 36-configuration mask, second line']; end
R = [R, per_rows(S, c, r5)];
R = [R, rec_rows(S, c, r6)];
if strcmp(c.line, 'A'), R = [R, gput_rows(S, c, r7)]; end
R = [R, cnn_contrib_rows(S, c, r8)];
end

function R = per_rows(S, c, role)
R = {};
b = {'kpi', 5, 'pair_set', c.pair, 'action_set', c.aset, 'line', c.line, 'unit', '%', 'source', c.src};
for v = S.verdict
    R{end+1} = row(b{:}, 'reading', sprintf('PER reduction vs the static link, %s (%s)', v.scenario, v.threat), ...
        'network', pol_net(v.policy), 'policy', v.policy, 'versus', 'none', 'episodes', ['recoverable jamming episodes: ' c.rec], 'n', v.n, ...
        'value', v.red_pct, 'lo', v.ci(1), 'hi', v.ci(2), 'verdict', v.verdict, 'role', pol_role_of(v.policy, role), ...
        'note', sprintf('static PER %s; target >= %g%%%s', pct_txt(v.per_ref_pct), c.target, role_note(c, v.policy))); %#ok<AGROW>
end
for t = S.per_threat
    if isempty(t.band), continue; end
    for j = 1:numel(S.per)
        p = S.per(j).policy;
        if any(strcmp({S.verdict.policy}, p)), continue; end
        R{end+1} = row(b{:}, 'reading', sprintf('PER reduction vs the static link, %s (%s)', t.band, t.threat), 'network', pol_net(p), 'policy', p, ...
            'versus', 'none', 'episodes', ['recoverable jamming episodes: ' c.rec], 'n', t.n, 'value', t.red_pct(j), ...
            'lo', t.ci(j, 1), 'hi', t.ci(j, 2), 'verdict', '-', 'role', pol_role_of(p, role_ext(role)), ...
            'note', sprintf('static PER %s; no verdict word in lect_kpis.m for this policy%s', pct_txt(t.per_ref_pct), role_note(c, p))); %#ok<AGROW>
    end
end
for q = S.per
    w = '-'; if strcmp(q.policy, c.tgt), w = q.verdict; end
    R{end+1} = row(b{:}, 'reading', 'PER reduction vs the static link, five jamming threats pooled', 'network', pol_net(q.policy), 'policy', q.policy, ...
        'versus', 'none', 'episodes', ['recoverable jamming episodes: ' c.rec], 'n', q.n, 'value', q.red_pct, 'lo', q.ci(1), ...
        'hi', q.ci(2), 'verdict', w, 'role', pol_role_of(q.policy, role_pooled(role)), ...
        'note', sprintf('pooled over the five jamming threats (extension); PER %s vs %s static%s', pct_txt(q.per_pct), pct_txt(q.per_ref_pct), role_note(c, q.policy))); %#ok<AGROW>
end
end

function R = rec_rows(S, c, role)
R = {};
if ~isfield(S, 'rec') || isempty(S.rec), return; end
pm = c.period_ms;
lineA = '';
if strcmp(c.line, 'A'), lineA = ' Line A pools the link-limited points, where detection -> restored is set by construction (D99).'; end
nm = {'det', 'onset -> detection (t_conf)'; 'rec_det', 'detection -> PER restored (t_rec_det)'; ...
    't_rec', 'restored from onset (T_rec, BER and packet loss)'};
for q = S.rec
    [net, ~] = pol_role(q.policy, 'x');
    for i = 1:3
        s = q.(nm{i, 1});
        R{end+1} = row('kpi', 6, 'reading', [nm{i, 2} ', ' strrep(q.set, 'recoverable ', '')], 'network', net, 'policy', q.policy, 'pair_set', c.pair, ...
            'action_set', c.aset, 'line', c.line, 'episodes', [q.set ': ' c.rec], 'n', q.n, 'value', s.median * pm, ...
            'p90', s.p90 * pm, 'never_pct', s.never_pct, 'unit', 'ms', 'verdict', '-', ...
            'role', pol_role_of(q.policy, role), 'source', c.src, ...
            'note', sprintf('median %s / p90 %s cycles of %g ms; no target%s%s', nf('%g', s.median), nf('%g', s.p90), pm, role_note(c, q.policy), ...
            ternary(i == 2, lineA, ''))); %#ok<AGROW>
    end
end
end

function R = gput_rows(S, c, role)
R = {};
if ~isfield(S, 'gput') || isempty(S.gput), return; end
for q = S.gput
    [net, ~] = pol_role(q.policy, 'x');
    b = {'kpi', 7, 'network', net, 'policy', q.policy, 'pair_set', c.pair, 'action_set', c.aset, 'line', c.line, ...
        'unit', 'bit/s', 'verdict', '-', 'role', pol_role_of(q.policy, role), 'source', c.src};
    R{end+1} = row(b{:}, 'reading', 'goodput after onset, threat episodes', 'episodes', 'all threat episodes', 'value', q.bps, ...
        'lo', q.ci(1), 'hi', q.ci(2), 'note', sprintf('normalized %s; no target; nominal payload %g bit/s%s', nf('%.3f', q.norm), ...
        c.payload, role_note(c, q.policy))); %#ok<AGROW>
    R{end+1} = row(b{:}, 'reading', 'goodput after onset, recoverable jamming episodes', 'episodes', ['recoverable jamming episodes: ' c.rec], ...
        'value', q.bps_jam, 'lo', q.ci_jam(1), 'hi', q.ci_jam(2), 'note', sprintf('normalized %s; no target%s', nf('%.3f', q.norm_jam), ...
        role_note(c, q.policy))); %#ok<AGROW>
end
end

function R = cnn_contrib_rows(S, c, role)
R = {};
if ~isfield(S, 'cnn') || ~isstruct(S.cnn) || ~isfield(S.cnn, 'n'), return; end
k = S.cnn; pm = c.period_ms;
b = {'kpi', 8, 'network', 'HYB_LOOP', 'policy', c.tgt, 'versus', c.conv, 'pair_set', c.pair, 'action_set', c.aset, ...
    'line', c.line, 'episodes', ['recoverable jamming episodes: ' c.rec], 'n', k.n, 'role', role, 'source', c.src};
sec = '';
if strcmp(c.tgt, 'rule_core')
    sec = ' Secondary, weakened baseline: blind_core has a fixed first response (channel_switch+rate_reduce), no validation choice; the headline is CORE_BW''s rule_core3 against the validation-tuned blind_core (D106).';
end
if k.n == 0
    R{end+1} = row(b{:}, 'reading', 'CNN contribution', 'verdict', 'no recoverable jamming episodes', 'note', strtrim(sec));
    return;
end
R{end+1} = row(b{:}, 'reading', 'PER reduction of the rule with the detector against the same without it', 'value', k.per_red_pct, ...
    'lo', k.per_ci(1), 'hi', k.per_ci(2), 'unit', '%', 'verdict', 'analysis, no target', 'note', strtrim(sec));
R{end+1} = row(b{:}, 'reading', 'goodput difference, with minus without the detector', 'value', k.gput_bps, 'lo', k.gput_ci(1), ...
    'hi', k.gput_ci(2), 'unit', 'bit/s', 'verdict', 'analysis, no target', 'note', strtrim(sec));
nm = {'onset -> detection', 'det'; 'detection -> PER restored', 'rec_det'};
for i = 1:2
    for w = 1:2
        s = k.(nm{i, 2})(w);
        t = {'with the detector', 'without the detector'};
        R{end+1} = row(b{:}, 'reading', sprintf('%s, %s', nm{i, 1}, t{w}), 'value', s.median * pm, 'p90', s.p90 * pm, ...
            'never_pct', s.never_pct, 'unit', 'ms', 'verdict', 'analysis, no target', ...
            'note', strtrim(sprintf('median %s / p90 %s cycles of %g ms.%s', nf('%g', s.median), nf('%g', s.p90), pm, sec))); %#ok<AGROW>
    end
end
end

function [net, role] = pol_role(p, base)
% The network behind a policy and its role (blind_core rows are secondary, D105).
net = pol_net(p);
role = pol_role_of(p, base);
end

function net = pol_net(p)
if strcmp(p, 'none'), net = 'NONE';
elseif startsWith(p, 'blind'), net = 'LINK';
else, net = 'HYB_LOOP'; end
end

function role = pol_role_of(p, base)
role = base;
if strcmp(p, 'blind_core'), role = 'secondary'; end
end

function r = role_ext(role)
% Rows of a policy the verdict word does not cover stay extension rows next to a verdict block.
r = role;
if strcmp(role, 'verdict') || strcmp(role, 'measured'), r = 'extension'; end
end

function r = role_pooled(role)
r = role;
if strcmp(role, 'verdict'), r = 'extension'; end
end

function s = role_note(~, p)
s = '';
if strcmp(p, 'blind_core')
    s = ' Secondary, weakened baseline (fixed first response channel_switch+rate_reduce, no validation choice; D105).';
end
end

function s = sec_note(p)
s = '';
if strcmp(p, 'blind_core'), s = role_note([], p); end
end

function k = pair_kind(p)
if endsWith(p, '_core'), k = 'core'; elseif endsWith(p, '_esc'), k = 'full'; else, k = ''; end
end

function s = action_text(p)
if endsWith(p, '_core'), s = 'core action set'; elseif endsWith(p, '_esc'), s = '36 configurations'; else, s = ''; end
end

%% ===================== Text and csv =====================
function lines = text_lines(rows, nm, res_abs, P, F, mk, Cn, lect)
lines = {'=== LECTURER KPI TABLE (proposal numbering KPI 1-8) ===', ...
    sprintf('Generated: %s | results folder %s', datestr(now), res_abs), ''};
lines{end+1} = 'Sources read (saved outputs only; nothing recomputed, no test-set data opened):';
for f = {F.pol, F.phy, F.cnn, F.cnn_txt, F.mark, F.d99, F.bw}
    p = fullfile(res_abs, f{1});
    if isfile(p), lines{end+1} = sprintf('  %-30s present (%s)', f{1}, datestr(dir(p).datenum)); %#ok<AGROW>
    else, lines{end+1} = sprintf('  %-30s absent', f{1}); end %#ok<AGROW>
end
if P.ok && isfield(P.KP, 'det_id') && isfield(P.KP, 'policy_stamp')
    lines{end+1} = sprintf('  policy_evaluation.mat: det_id %s, policy_stamp %s', tostr(P.KP.det_id), tostr(P.KP.policy_stamp));
end
lines = [lines, {'', 'Networks:'}];
for k = {'CNN3', 'CNN3_LOOP', 'HYB_FRAMES', 'HYB_LOOP', 'LINK', 'NONE', 'PHY'}
    lines{end+1} = sprintf('  %-10s %s', k{1}, net_text(k{1})); %#ok<AGROW>
end
lines = [lines, {'', ['Which network produced which KPI (D105, D106): KPI 2-4 detection from the three-state CNN (B3c). KPI 5-8 of C2e from the ' ...
    'hybrid detector''s classes on the core action set (rule_core against none and blind_core); those rows are the hybrid''s. ' ...
    'CORE_BW alone puts the three-state CNN in the decision loop (rule_core3): its rows are the headline of KPI 5 and 8 against the ' ...
    'validation-tuned blind_core, rule_core there is labelled hybrid, secondary, and rule_core3 - rule_core is descriptive, with no ' ...
    'verdict word. C2e''s and CORE_BW''s verdicts are side by side; neither replaces the other. Extension rows (36 configurations, ' ...
    'pooled threats, the 36-mask) are never in the verdict''s place; blind_core rows are a secondary, weakened baseline. The system ' ...
    'false alarms of the whole policy are listed apart as an extension (project KPI 6, D103), never as proposal KPI 3.'], ''}];
if mk.ok
    L = strcmp(mk.tag, 'L'); M = strcmp(mk.tag, 'M'); J = strcmp(mk.tag, 'J');
    lines{end+1} = sprintf(['Link-limited points (D99, mark %s, written before policy_evaluation.mat was opened): link-limited (L) %s | ' ...
        'marginal (M) %s | working point (J) %s. Line A pools all points.'], mk.src, pts(mk.ebno(L)), pts(mk.ebno(M)), pts(mk.ebno(J)));
else
    lines{end+1} = 'Link-limited points (D99): pending (no mark file low_ebno_mark.txt, no lect_kpis_by_ebno.mat). Line A pools all points.';
end
lines{end+1} = '';
for k = [1:8 kpi_fa()]
    ix = find([rows.kpi] == k);
    if isempty(ix), continue; end
    if k == kpi_fa()
        lines{end+1} = sprintf('EXTENSION, not a proposal KPI: %s   (target: %s)', nm{k + 1}, target_of(k, Cn)); %#ok<AGROW>
    else
        lines{end+1} = sprintf('KPI %d  %s   (target: %s)', k, nm{k + 1}, target_of(k, Cn)); %#ok<AGROW>
    end
    for i = ix, lines{end+1} = row_text(rows(i)); end %#ok<AGROW>
    lines{end+1} = ''; %#ok<AGROW>
end
if ~lect
    lines{end+1} = 'Figures: not written (no KP.lect in policy_evaluation.mat).';
else
    lines{end+1} = ['Figures: lect_kpi_per.png (PER after onset as point values; PER reduction with 95% intervals), ' ...
        'lect_kpi_recovery.png, lect_kpi_goodput.png (95% intervals).'];
end
f = fullfile(res_abs, F.cnn_txt);
if isfile(f)
    t = splitlines(fileread(f));
    a = find(startsWith(t, '--- The lecturer''s KPIs'), 1); z = find(startsWith(t, '--- Confusion matrices'), 1);
    if ~isempty(a) && ~isempty(z) && z > a
        lines = [lines, {'', 'core_cnn.txt, the lecturer''s KPI block (copied):'}, strcat({'  '}, t(a:z-1))'];
    end
end
end

function s = target_of(k, C)
thr = struct('macro_f1', 0.85, 'recall', 0.85, 'false_alarm', 0.05);
if C.ok && isfield(C, 'thr') && isstruct(C.thr), thr = C.thr; end
switch k
    case 1, s = 'the BER model agrees with theory';
    case 2, s = sprintf('>= %g%% on an independent test set', 100 * thr.macro_f1);
    case 3, s = sprintf('<= %g%% in clean states', 100 * thr.false_alarm);
    case 4, s = sprintf('>= %g%% per jamming type', 100 * thr.recall);
    case 5, s = '>= 30% lower than the static link in recoverable scenarios';
    case 6, s = 'measured, no target: from detection until the PER stays below a threshold for a fixed window';
    case 7, s = 'measured, no target';
    case kpi_fa(), s = 'one-sided 95% upper bound <= 5% on independent clean flights (the project''s KPI 6; word: bound <= 5% or point estimate only)';
    otherwise, s = 'analysis metric, not a promise';
end
end

function s = row_text(r)
v = '-';
if isfinite(r.value), v = sprintf('%.4g', r.value); end
if isfinite(r.lo) && isfinite(r.hi), v = sprintf('%s [%.4g, %.4g]', v, r.lo, r.hi);
elseif isfinite(r.hi), v = sprintf('%s (upper bound %.4g)', v, r.hi); end
u = r.unit;
if ~isempty(u) && ~strcmp(u, 'cases passed'), v = [v ' ' u]; elseif ~isempty(u), v = [v ' ' u]; end
x = {};
if isfinite(r.p90), x{end+1} = sprintf('p90 %.4g %s', r.p90, u); end
if isfinite(r.never_pct), x{end+1} = sprintf('never %.1f%%', r.never_pct); end
if isfinite(r.n), x{end+1} = sprintf('n %g', r.n); end
if ~isempty(x), v = [v ' (' strjoin(x, ', ') ')']; end
pol = r.policy; if ~isempty(r.versus), pol = sprintf('%s vs %s', pol, r.versus); end
if ~isempty(pol), pol = [pol ' | ']; end
w = ''; if ~isempty(r.verdict), w = [' -> ' r.verdict]; end
s = sprintf('  [%s] %s%s | line %s | %s: %s%s | %s%s', r.role, pol, r.network, r.line, r.reading, v, w, r.source, ...
    ternary(isempty(r.note), '', [' | ' r.note]));
end

function s = pts(x)
if isempty(x), s = '-'; else, s = strjoin(arrayfun(@(e) sprintf('%g dB', e), x, 'UniformOutput', false), ', '); end
end

function s = pct_txt(x)
if isfinite(x), s = sprintf('%.2f%%', x); else, s = 'n/a'; end
end

function s = tostr(x)
if ischar(x) || isstring(x), s = char(x);
elseif isnumeric(x), s = mat2str(x);
else, s = '?'; end
end

function write_csv(f, rows, nm, Cn)
cols = {'kpi', 'kpi_name', 'target', 'reading', 'network', 'policy', 'versus', 'pair_set', 'action_set', 'line', 'episodes', ...
    'n', 'value', 'lo', 'hi', 'unit', 'p90', 'never_pct', 'verdict', 'role', 'source', 'note'};
fid = fopen(f, 'w');
assert(fid > 0, 'lect_kpi_table:write', 'lect_kpi_table: cannot write %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', strjoin(cols, ','));
for r = rows
    v = cell(1, numel(cols));
    for i = 1:numel(cols)
        switch cols{i}
            case 'kpi_name', v{i} = q(nm{r.kpi + 1});
            case 'target', v{i} = q(target_of(r.kpi, Cn));
            case 'network', v{i} = q(net_text(r.network));
            case {'kpi', 'n', 'value', 'lo', 'hi', 'p90', 'never_pct'}
                x = r.(cols{i}); if isfinite(x), v{i} = sprintf('%.10g', x); else, v{i} = ''; end
            otherwise, v{i} = q(r.(cols{i}));
        end
    end
    fprintf(fid, '%s\n', strjoin(v, ','));
end
end

function s = q(t)
s = ['"' strrep(char(t), '"', '""') '"'];
end

function write_lines(f, lines)
fid = fopen(f, 'w');
assert(fid > 0, 'lect_kpi_table:write', 'lect_kpi_table: cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function k = kpi_fa()
% The row number of the system false-alarm extension (after the proposal's KPI 1-8).
k = 9;
end

function s = nf(fmt, x)
% A number as text; n/a when it is not finite (never a printed NaN).
if isfinite(x), s = sprintf(fmt, x); else, s = 'n/a'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

%% ===================== Figures =====================
function f = fig_per(L, f)
S = L; ser = {L, 'full'};
if isfield(L, 'core') && ~isempty(L.core), S = L.core; ser = {S, 'core'; L, 'full'}; end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [60 60 1150 440]);
c = onCleanup(@() close(fig));
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
% Panel A: PER after onset, five jamming threats pooled (point values)
ax = nexttile(tl);
keys = {}; val = [];
keys{end+1} = 'none'; val(end+1) = ser{1, 1}.per(1).per_ref_pct;
for i = 1:size(ser, 1)
    for q = ser{i, 1}.per
        if ~any(strcmp(keys, q.policy)), keys{end+1} = q.policy; val(end+1) = q.per_pct; end %#ok<AGROW>
    end
end
hb = bar(ax, val, 'FaceColor', 'flat');
for i = 1:numel(keys), hb.CData(i, :) = pcolor(keys{i}); end
set(ax, 'XTick', 1:numel(keys), 'XTickLabel', keys, 'TickLabelInterpreter', 'none'); grid(ax, 'on');
ylabel(ax, 'PER after onset [%]');
title(ax, 'PER after onset, five jamming threats pooled (point values)', 'FontSize', 10); ylim(ax, [0 1.15 * max(100, max(val))]);
for i = 1:numel(val), text(ax, i, val(i), nf('%.1f', val(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom'); end
% Panel B: reduction vs the static link, 95% intervals
ax = nexttile(tl);
grp = {'narrowband', 'wideband', 'pooled'};
names = {}; Y = zeros(3, 0); LO = Y; HI = Y; cols = zeros(0, 3);
for i = 1:size(ser, 1)
    Si = ser{i, 1};
    for j = 1:numel(Si.per)
        y = nan(3, 1); lo = y; hi = y;
        for g = 1:2
            t = Si.per_threat(strcmp({Si.per_threat.band}, grp{g}));
            if ~isempty(t), y(g) = t.red_pct(j); lo(g) = t.ci(j, 1); hi(g) = t.ci(j, 2); end
        end
        y(3) = Si.per(j).red_pct; lo(3) = Si.per(j).ci(1); hi(3) = Si.per(j).ci(2);
        names{end+1} = Si.per(j).policy; Y(:, end+1) = y; LO(:, end+1) = lo; HI(:, end+1) = hi; cols(end+1, :) = pcolor(Si.per(j).policy); %#ok<AGROW>
    end
end
hb = bar(ax, Y, 'grouped'); hold(ax, 'on');
for j = 1:numel(hb)
    hb(j).FaceColor = cols(j, :);
    errorbar(ax, hb(j).XEndPoints, Y(:, j), Y(:, j) - LO(:, j), HI(:, j) - Y(:, j), 'k', 'LineStyle', 'none', 'CapSize', 6);
end
yline(ax, L.target_pct, '--k', sprintf('target %g%%', L.target_pct), 'LabelHorizontalAlignment', 'left');
set(ax, 'XTick', 1:3, 'XTickLabel', {'narrowband (tone jamming)', 'wideband (jamming)', 'five threats pooled'}); grid(ax, 'on');
ylabel(ax, 'PER reduction vs the static link [%]');
legend(ax, hb, names, 'Interpreter', 'none', 'Location', 'southoutside', 'Orientation', 'horizontal');
title(ax, 'PER reduction, 95% bootstrap over flight geometries', 'FontSize', 10);
title(tl, 'KPI 5: PER by configuration (core pair rule_core / blind_core; rule_esc / blind_esc extension)', 'Interpreter', 'none');
exportgraphics(fig, f, 'Resolution', 150);
end

function f = fig_rec(L, LB, f)
S = L; if isfield(L, 'core') && ~isempty(L.core), S = L.core; end
Sb = []; if ~isempty(LB), Sb = LB; if isfield(LB, 'core') && ~isempty(LB.core), Sb = LB.core; end, end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [60 60 1150 440]);
c = onCleanup(@() close(fig));
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
rec_panel(nexttile(tl), S, L.period_ms, 'Line A (all Eb/N0 points; detection -> restored set by construction at link-limited points)');
if isempty(Sb)
    ax = nexttile(tl); axis(ax, 'off');
    text(ax, 0.5, 0.5, 'Line B (D99 headline): pending, lect_kpis_by_ebno.mat not found', 'HorizontalAlignment', 'center', 'Interpreter', 'none');
else
    rec_panel(nexttile(tl), Sb, L.period_ms, 'Line B (non-link-limited points), the headline (D99)');
end
title(tl, 'KPI 6: recovery time, recoverable jamming episodes (median, whisker to p90; never = share never reached)', 'Interpreter', 'none');
exportgraphics(fig, f, 'Resolution', 150);
end

function rec_panel(ax, S, pm, ttl)
q = S.rec(strcmp({S.rec.set}, 'recoverable jamming episodes'));
if isempty(q), axis(ax, 'off'); text(ax, 0.5, 0.5, 'no recoverable jamming episodes', 'HorizontalAlignment', 'center'); return; end
nmeas = {'det', 'rec_det'};
Y = nan(numel(q), 2); U = Y; NV = Y;
for i = 1:numel(q)
    for k = 1:2
        s = q(i).(nmeas{k}); Y(i, k) = s.median * pm; U(i, k) = (s.p90 - s.median) * pm; NV(i, k) = s.never_pct;
    end
end
hb = bar(ax, Y, 'grouped'); hold(ax, 'on');
cols = [pcolor('rule_core'); pcolor('none')];
for k = 1:2
    hb(k).FaceColor = cols(k, :);
    errorbar(ax, hb(k).XEndPoints, Y(:, k), zeros(numel(q), 1), U(:, k), 'k', 'LineStyle', 'none', 'CapSize', 6);
    for i = 1:numel(q)
        txt = ['never ' nf('%.0f', NV(i, k)) '%'];
        if isfinite(Y(i, k)), y = Y(i, k) + max(U(i, k), 0); else, y = 0; end
        text(ax, hb(k).XEndPoints(i), y, txt, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
    end
end
set(ax, 'XTick', 1:numel(q), 'XTickLabel', {q.policy}, 'TickLabelInterpreter', 'none'); grid(ax, 'on');
ylabel(ax, 'time [ms]');
legend(ax, hb, {'onset -> detection', 'detection -> PER restored'}, 'Location', 'northwest');
title(ax, ttl, 'FontSize', 8, 'Interpreter', 'none'); ylim(ax, [0 1.15 * max(1, max(Y(:) + max(U(:), 0), [], 'omitnan'))]);
end

function f = fig_gput(L, f)
cs = {}; if isfield(L, 'core') && ~isempty(L.core), cs = {L.core.gput}; end
G = [cs, {L.gput}];
keys = {}; rowsg = struct('bps', {}, 'ci', {}, 'bps_jam', {}, 'ci_jam', {});
for i = 1:numel(G)
    for q = G{i}
        if strcmp(q.policy, 'oracle') || any(strcmp(keys, q.policy)), continue; end
        keys{end+1} = q.policy; rowsg(end+1) = struct('bps', q.bps, 'ci', q.ci, 'bps_jam', q.bps_jam, 'ci_jam', q.ci_jam); %#ok<AGROW>
    end
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [60 60 1000 440]);
c = onCleanup(@() close(fig));
ax = axes(fig);
if isempty(keys)
    axis(ax, 'off'); text(ax, 0.5, 0.5, 'no goodput readings', 'HorizontalAlignment', 'center');
    exportgraphics(fig, f, 'Resolution', 150);
    return;
end
Y = [[rowsg.bps]', [rowsg.bps_jam]'] / 1e3;
LO = [cellfun(@(x) x(1), {rowsg.ci})', cellfun(@(x) x(1), {rowsg.ci_jam})'] / 1e3;
HI = [cellfun(@(x) x(2), {rowsg.ci})', cellfun(@(x) x(2), {rowsg.ci_jam})'] / 1e3;
hb = bar(ax, Y, 'grouped'); hold(ax, 'on');
cl = [0.55 0.55 0.55; 0 0.45 0.74];
for k = 1:2
    hb(k).FaceColor = cl(k, :);
    errorbar(ax, hb(k).XEndPoints, Y(:, k), Y(:, k) - LO(:, k), HI(:, k) - Y(:, k), 'k', 'LineStyle', 'none', 'CapSize', 6);
end
set(ax, 'XTick', 1:numel(keys), 'XTickLabel', keys, 'TickLabelInterpreter', 'none'); grid(ax, 'on');
ylabel(ax, 'goodput after onset [kb/s]');
legend(ax, hb, {'all threat episodes', 'recoverable jamming episodes'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
title(ax, sprintf('KPI 7: goodput by configuration, 95%% bootstrap over flight geometries (nominal payload %.0f kb/s)', L.payload_bps / 1e3));
exportgraphics(fig, f, 'Resolution', 150);
end

function c = pcolor(p)
switch p
    case 'none', c = [0.55 0.55 0.55];
    case 'rule_core', c = [0 0.45 0.74];
    case 'blind_core', c = [0.85 0.33 0.1];
    case 'rule_esc', c = [0.4 0.7 0.9];
    case 'blind_esc', c = [0.95 0.6 0.4];
    otherwise, c = [0.3 0.65 0.35];
end
end
