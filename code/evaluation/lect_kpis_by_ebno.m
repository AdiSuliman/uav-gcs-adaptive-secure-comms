function varargout = lect_kpis_by_ebno(cmd, varargin)
%LECT_KPIS_BY_EBNO  The lecturer's readings of C2e where the restoration test of packet loss is
%   defined: the pooled verdict line, the line without the link-limited Eb/N0 points and one row
%   per Eb/N0 (docs/lect_ebno_protocol.md). Reporting only: lect_kpis.m runs unchanged on
%   subsets of the saved episodes; no verdict, threshold or KPI definition changes.
%   lect_kpis_by_ebno('run', pools, eval_mat, eval_txt, out_dir)
%       pools     the post-M data/policy_pools.mat C2e read (PP.ebno, scen, clean_fer, det_id)
%       eval_mat, eval_txt  C2e's results/policy_evaluation.mat and .txt
%       out_dir   the reading copy's results folder
%       Absolute paths; the inputs are only read. In this order: the mark from the pools alone,
%       written with the pools' SHA-256 to out_dir/low_ebno_mark.txt before eval_mat is opened;
%       the gate; only on a pass the readings -> out_dir/lect_kpis_by_ebno.{txt,mat}. Once: refused
%       when they exist. A failed gate writes out_dir/lect_kpis_by_ebno.gatefail.{txt,mat} (the
%       diagnostics) and stops with lect_kpis_by_ebno:gate; it creates no reading output, so the
%       reading stays open. The header names the thread count the session really has.
%   M = lect_kpis_by_ebno('mark', clean_fer, ratio_ok)
%       M.L the link-limited points, ratio_ok x clean_fer >= 1 (the packet-loss test of
%       restoration cannot fail there); M.tag 'L', 'J' (working point: clean_fer < 0.1, the
%       IEEE 802.11a-1999 sensitivity criterion) or 'M' (marginal)
%   A = lect_kpis_by_ebno('subset', ALL, keep)
%       every policy's episodes keep, in order (episode i stays paired across the policies)
%   G = lect_kpis_by_ebno('gate', E, PP, txt)
%       E the variables of eval_mat, txt eval_txt one cell per line. G.pass when lect_kpis.m on
%       every episode gives KP.lect and its lines of txt, and far_report on KPI 6's clean flights
%       gives KP.far, KP.far_diag and their lines; exact (isequaln), no tolerance. G.mismatch
%   [S, lines] = lect_kpis_by_ebno('readings', E, PP, M, G)
%       Line A (the verdict, C2e's lines), Line B (non-L points, a second line), the comparison
%       of their verdict words, recovery time from detection (Line B the headline, Line A with
%       N: its detected episodes at L points, where t_rec_det is set by construction), the
%       per-Eb/N0 rows (descriptive), the KPI 4/5 table with the mark, KPI 6's non-L line and
%       per-Eb/N0 rows (descriptive)
%   lines = lect_kpis_by_ebno('rows', L, isL, period_ms, pre)
%       one Eb/N0 point's lines from lect_kpis.m's output L (isL: the point is link-limited)
%   [FAR, FD, lines] = lect_kpis_by_ebno('far', RR, POL, LBL, above, T, iDQN, ebno, cls_list, period_ms)
%       evaluate_policies.m's far_report, byte for byte
%   h = lect_kpis_by_ebno('sha', f)    SHA-256 of a file, as sha256sum prints it
switch cmd
    case 'run',      run_reading(varargin{:});
    case 'mark',     varargout{1} = mark(varargin{:});
    case 'subset',   varargout{1} = subset(varargin{:});
    case 'gate',     varargout{1} = gate(varargin{:});
    case 'readings', [varargout{1}, varargout{2}] = readings(varargin{:});
    case 'rows',     varargout{1} = row_lines(varargin{:});
    case 'far',      [varargout{1}, varargout{2}, varargout{3}] = far_report(varargin{:});
    case 'sha',      varargout{1} = file_sha(varargin{:});
    otherwise, error('lect_kpis_by_ebno:cmd', 'lect_kpis_by_ebno: unknown command %s', cmd);
end
end

%% ===================== The single run =====================
function run_reading(pools, eval_mat, eval_txt, out_dir)
for f = {pools, eval_mat, eval_txt}
    assert(is_abs(f{1}) && isfile(f{1}), 'lect_kpis_by_ebno:input', '%s: not an absolute path of a file', f{1});
end
assert(is_abs(out_dir) && isfolder(out_dir), 'lect_kpis_by_ebno:input', '%s: not an absolute path of a folder', out_dir);
fk = fullfile(out_dir, 'low_ebno_mark.txt');
fo = fullfile(out_dir, 'lect_kpis_by_ebno.txt'); fm = fullfile(out_dir, 'lect_kpis_by_ebno.mat');
ff = fullfile(out_dir, 'lect_kpis_by_ebno.gatefail.txt'); fg = fullfile(out_dir, 'lect_kpis_by_ebno.gatefail.mat');
assert(~isfile(fo) && ~isfile(fm), 'lect_kpis_by_ebno:once', '%s exists: the reading runs once', fo);
[nthr, thr_how] = thread_info();
st0 = stamps({pools, eval_mat, eval_txt});

% 1. The mark, from the pools alone
h_pools = file_sha(pools);
Lp = load(pools, 'PP');
PP = struct('ebno', Lp.PP.ebno, 'scen', {Lp.PP.scen}, 'clean_fer', Lp.PP.clean_fer, 'det_id', field_or(Lp.PP, 'det_id', ''));
clear Lp
C = decision_config();
M = mark(PP.clean_fer, C.ratio_ok);
mk = mark_lines(M, PP.ebno, pools, h_pools);
if isfile(fk)
    assert(isequal(read_lines(fk), mk), 'lect_kpis_by_ebno:mark', '%s exists and is not the mark of these pools', fk);
else
    write_lines(fk, mk);
end
h_mark = file_sha(fk);
fprintf('Mark written before the evaluation is opened: %s (%s)\n', fk, strjoin(M.tag, ' '));

% 2. C2e's results, the gate, the readings
h_mat = file_sha(eval_mat); h_txt = file_sha(eval_txt);
E = load(eval_mat, 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'RW', 'set_names');
txt = read_lines(eval_txt);
head = {'=== The lecturer''s readings by Eb/N0 (docs/lect_ebno_protocol.md): reporting only, the verdicts are Line A''s ===', ...
    sprintf('pools %s sha256 %s', pools, h_pools), sprintf('evaluation %s sha256 %s', eval_mat, h_mat), ...
    sprintf('text %s sha256 %s', eval_txt, h_txt), sprintf('mark %s sha256 %s (written before the evaluation was opened)', fk, h_mark), ...
    sprintf('threads %d (%s)', nthr, thr_how)};
G = gate(E, PP, txt);
if ~G.pass
    lines = [{sprintf('GATE FAIL (%d mismatches): no subset is read; no reading output was written, the reading stays open', ...
        numel(G.mismatch))}, head, G.mismatch];
    keep_old(ff); keep_old(fg);
    write_lines(ff, lines);
    G = rmfield(G, 'RU');
    save(fg, 'M', 'G', 'lines', 'h_pools', 'h_mat', 'h_txt', 'h_mark', 'nthr', 'thr_how', 'pools', 'eval_mat', 'eval_txt');
    fprintf('%s\n', lines{:});
    error('lect_kpis_by_ebno:gate', 'the gate failed: %s', ff);
end
[S, body] = readings(E, PP, M, G);
assert(isequal(st0, stamps({pools, eval_mat, eval_txt})), 'lect_kpis_by_ebno:inputs', 'an input changed during the reading');
lines = [{'GATE PASS: lect_kpis.m reproduces KP.lect and far_report reproduces KP.far exactly'}, head, body];
write_lines(fo, lines);
G = rmfield(G, 'RU');
save(fm, 'M', 'G', 'S', 'lines', 'h_pools', 'h_mat', 'h_txt', 'h_mark', 'nthr', 'thr_how', 'pools', 'eval_mat', 'eval_txt');
fprintf('%s\n', lines{:});
fprintf('Saved %s, %s\n', fo, fm);
end

function lines = mark_lines(M, ebno, pools, h)
lines = {['# Link-limited Eb/N0 points (docs/lect_ebno_protocol.md R1): L when ratio_ok x clean_fer >= 1; ' ...
    'J when clean_fer < 0.1, M otherwise'], ['pools ' pools], ['pools_sha256 ' h], sprintf('ratio_ok %.17g', M.ratio_ok), ...
    'ebno_db clean_fer ratio_ok_x_clean_fer link_limited tag'};
for k = 1:numel(M.L)
    lines{end+1} = sprintf('%g %.17g %.17g %d %s', ebno(k), M.clean_fer(k), M.ratio_ok * M.clean_fer(k), M.L(k), M.tag{k}); %#ok<AGROW>
end
end

%% ===================== Mark and subsets =====================
function M = mark(clean_fer, ratio_ok)
f = double(clean_fer(:)');
M = struct('clean_fer', f, 'ratio_ok', ratio_ok, 'L', ratio_ok * f >= 1, 'tag', {repmat({'M'}, 1, numel(f))});
M.tag(M.L) = {'L'};
M.tag(~M.L & f < 0.1) = {'J'};
end

function A = subset(ALL, keep)
keep = logical(keep(:)');
A = ALL;
for k = 1:numel(ALL)
    f = fieldnames(ALL{k});
    for j = 1:numel(f)
        x = ALL{k}.(f{j});
        assert(size(x, 2) == numel(keep), 'lect_kpis_by_ebno:field', ...
            'ALL{%d}.%s has %d columns, not one per episode (%d)', k, f{j}, size(x, 2), numel(keep));
        A{k}.(f{j}) = x(:, keep);
    end
end
end

%% ===================== Gate =====================
function G = gate(E, PP, txt)
G = struct('pass', false, 'mismatch', {{}}, 'lect', [], 'lect_lines', {{}}, 'far', [], 'far_diag', [], ...
    'far_lines', {{}}, 'T', NaN, 'RU', {{}}, 'aboveU', []);
txt = norm_lines(txt);
need = {'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'RW', 'set_names'};
miss = need(~isfield(E, need));
if ~isempty(miss), G.mismatch = {sprintf('the evaluation lacks %s', strjoin(miss, ', '))}; return; end
KP = E.KP;
need = {'lect', 'far', 'far_diag', 'far_src', 'ebno', 'ebno_thr', 'cls_list'};
miss = need(~isfield(KP, need));
if ~isempty(miss), G.mismatch = {sprintf('KP lacks %s', strjoin(miss, ', '))}; return; end
mm = {};
if ~isequal(double(KP.ebno), double(PP.ebno)), mm{end+1} = 'KP.ebno is not the pools'' Eb/N0 grid'; end
if isfield(KP, 'det_id') && ~isequal(KP.det_id, PP.det_id)
    mm{end+1} = sprintf('KP.det_id %s is not the pools'' %s', char(string(KP.det_id)), char(string(PP.det_id)));
end
mm = [mm, pairing(E.ALL, E.POL)];
if ~isempty(mm), G.mismatch = mm; return; end

% lect_kpis.m on every episode: KP.lect and its lines
[Lf, lf] = lect_kpis(E.ALL, E.POL, E.LBL, E.iDQN, PP.scen, KP.lect.payload_bps, KP.lect.period_ms);
lf = norm_lines(lf);
mm = [mm, differs(Lf, KP.lect, 'lect_kpis on every episode vs KP.lect')];
i = find(strcmp(txt, lf{2}));
if numel(i) ~= 1
    mm{end+1} = sprintf('the text holds lect_kpis''s header %d times, not once', numel(i));
else
    mm = [mm, block_diff(txt, lf, i - 1, 'lect_kpis''s lines')];
end

% far_report on KPI 6's clean flights: KP.far, KP.far_diag and their lines
[RU, aU, m2] = union_ru(E, PP, KP); mm = [mm, m2];
T = 0; n = [KP.far.n]; j = find(n > 0, 1);
if ~isempty(j), T = KP.far(j).rate.cycles / n(j); end
if T ~= round(T), mm{end+1} = sprintf('KP.far gives %g cycles per episode', T); end
if isempty(m2)
    [Ff, FDf, lfar] = far_report(RU, E.POL, E.LBL, aU, T, E.iDQN, PP.ebno, KP.cls_list, KP.lect.period_ms);
    mm = [mm, differs(Ff, KP.far, 'far_report on KPI 6''s clean flights vs KP.far'), ...
        differs(FDf, KP.far_diag, 'far_report on KPI 6''s clean flights vs KP.far_diag')];
    hdr = sprintf('False alarms on the clean link, every independent clean flight: %s, %d episodes x %d cycles -> KPI 6', ...
        KP.far_src, sum(aU), T);
    i = find(strcmp(txt, hdr));
    if numel(i) ~= 1
        mm{end+1} = sprintf('the text holds KPI 6''s header %d times, not once: %s', numel(i), hdr);
    else
        mm = [mm, block_diff(txt, norm_lines(lfar), i + 1, 'far_report''s lines')];
    end
    G.far = Ff; G.far_diag = FDf; G.far_lines = norm_lines(lfar);
end
G.pass = isempty(mm); G.mismatch = mm;
G.lect = Lf; G.lect_lines = lf; G.T = T; G.RU = RU; G.aboveU = aU;
end

function mm = pairing(ALL, POL)
% The same episodes under every policy, each flight geometry inside one Eb/N0 point.
mm = {};
R1 = ALL{1};
if ~all(isfield(R1, {'s', 'geom', 'scn'})), mm = {'ALL{1} lacks s, geom or scn'}; return; end
for k = 2:numel(ALL)
    R = ALL{k};
    if ~all(isfield(R, {'s', 'geom', 'scn'})) || ~isequal(R.s, R1.s) || ~isequal(R.geom, R1.geom) || ~isequal(R.scn, R1.scn)
        mm{end+1} = sprintf('ALL{%d} (%s) does not hold the episodes of ALL{1} (s, geom, scn)', k, POL{k}); %#ok<AGROW>
    end
end
if any(floor(R1.geom / 1000) ~= R1.s), mm{end+1} = 'a flight geometry (1000 s + r) spans two Eb/N0 points'; end
end

function [RU, aU, mm] = union_ru(E, PP, KP)
% KPI 6's clean flights as evaluate_policies.m joins them: the test split's clean set, the
% second test split's and the clean pools' (split id 6), from the KPI 1 threshold up.
RU = {}; aU = []; mm = {};
iC = find(strcmp(E.set_names, 'clean')); iC2 = find(strcmp(E.set_names, 'clean2'));
if numel(iC) ~= 1, mm = {'set_names holds no single clean set'}; return; end
ebno_thr = KP.ebno_thr;
RU = E.RES(iC, :); aU = PP.ebno(RU{1}.s) >= ebno_thr;
if ~isempty(iC2)
    for pk = 1:numel(E.POL), RU{pk} = cat_struct(RU{pk}, E.RES{iC2, pk}); end
    aU = [aU, PP.ebno(E.RES{iC2, 1}.s) >= ebno_thr];
end
if ~isempty(E.RW)
    for pk = 1:numel(E.POL)
        Rw = E.RW{pk}; Rw.split(:) = 6;
        RU{pk} = cat_struct(RU{pk}, Rw);
    end
    aU = [aU, PP.ebno(E.RW{1}.s) >= ebno_thr];
end
aU = reshape(aU, 1, []);
end

function d = differs(a, b, name)
% The fields of a and b that are not equal (isequaln), one line each, then the leaves that differ.
d = {};
if isequaln(a, b), return; end
if isstruct(a) && isstruct(b) && isequal(size(a), size(b)) && isempty(setxor(fieldnames(a), fieldnames(b)))
    for f = fieldnames(a)'
        if ~isequaln({a.(f{1})}, {b.(f{1})}), d{end+1} = sprintf('%s: .%s differs', name, f{1}); end %#ok<AGROW>
    end
end
if isempty(d), d = {sprintf('%s: differs (size or fields)', name)}; end
try
    d = [d, leaf_diff(a, b, '    leaf', 12)];
catch ME                                            % the diagnostics never replace the gate's own answer
    d{end+1} = sprintf('    leaf: the diagnostics failed: %s', ME.message);
end
end

function d = leaf_diff(a, b, p, maxn)
% Where a and b differ, down to the numbers: the count, the largest absolute difference and the
% first pair at full precision (diagnostics only; the gate stays exact).
d = {};
if isequaln(a, b) || maxn <= 0, return; end
if ~strcmp(class(a), class(b)), d = {sprintf('%s: class %s vs %s', p, class(a), class(b))}; return; end
if ~isequal(size(a), size(b)), d = {sprintf('%s: size [%s] vs [%s]', p, num2str(size(a)), num2str(size(b)))}; return; end
if isstruct(a)
    fa = fieldnames(a);
    if ~isempty(setxor(fa, fieldnames(b))), d = {sprintf('%s: fields differ', p)}; return; end
    for i = 1:numel(a)
        for k = 1:numel(fa)
            q = [p '.' fa{k}];
            if numel(a) > 1, q = sprintf('%s(%d).%s', p, i, fa{k}); end
            d = [d, leaf_diff(a(i).(fa{k}), b(i).(fa{k}), q, maxn - numel(d))]; %#ok<AGROW>
            if numel(d) >= maxn, return; end
        end
    end
elseif iscell(a)
    for i = 1:numel(a)
        d = [d, leaf_diff(a{i}, b{i}, sprintf('%s{%d}', p, i), maxn - numel(d))]; %#ok<AGROW>
        if numel(d) >= maxn, return; end
    end
elseif isnumeric(a) || islogical(a)
    ne = ~(a == b | (isnan(a) & isnan(b)));
    i = find(ne, 1);
    d = {sprintf('%s: %d of %d elements differ, max |d| %.3g, first at %d: %.17g vs %.17g', p, nnz(ne), numel(a), ...
        max(abs(double(a(ne)) - double(b(ne)))), i, double(a(i)), double(b(i)))};
else
    d = {sprintf('%s: differs (%s)', p, class(a))};
end
end

function d = block_diff(txt, blk, i0, name)
% blk against the text from line i0 on.
d = {};
blk = reshape(blk, 1, []);
if i0 < 1 || i0 + numel(blk) - 1 > numel(txt)
    d = {sprintf('%s: %d lines do not fit the text from line %d', name, numel(blk), i0)}; return
end
k = find(~strcmp(txt(i0:i0 + numel(blk) - 1), blk), 1);
if ~isempty(k)
    d = {sprintf('%s: first difference at line %d of the text: "%s" vs "%s"', name, i0 + k - 1, txt{i0 + k - 1}, blk{k})};
end
end

%% ===================== Readings =====================
function [S, lines] = readings(E, PP, M, G)
ALL = E.ALL; POL = E.POL; LBL = E.LBL; iDQN = E.iDQN; KP = E.KP; LA = G.lect;
pay = LA.payload_bps; per_ms = LA.period_ms; nS = numel(PP.ebno);
s = ALL{1}.s; Lep = M.L(s);
pts = @(k) point_list(PP.ebno, k);
kp = @(keep) lect_kpis(subset(ALL, keep), POL, LBL, iDQN, PP.scen, pay, per_ms);
lines = {'', sprintf('Mark (R1, from the pools before the evaluation was opened): %s', strjoin(arrayfun(@(k) ...
    sprintf('%g dB %s (clean loss %.3f)', PP.ebno(k), M.tag{k}, M.clean_fer(k)), 1:nS, 'UniformOutput', false), ', ')), ...
    sprintf(['  L link-limited: %g x the clean packet loss >= 1, so the packet-loss test of restoration cannot fail ' ...
    'there; J working point: clean loss < 0.1 (IEEE 802.11a-1999 sensitivity, PER < 10%%); M marginal'], M.ratio_ok)};

% Line A: the verdict
lines = [lines, {'', sprintf(['=== Line A, the verdict: all %d Eb/N0 points, lect_kpis.m on every episode (C2e''s ' ...
    'lines, reproduced by the gate) ==='], nS)}, G.lect_lines, gput_note(LA, ALL, POL, PP, M)];

% Line B: where the restoration test is defined
[LB, lb] = kp(~Lep);
lines = [lines, {'', sprintf(['=== Line B, where the restoration test is defined: the non-L points (%s), %d of %d ' ...
    'episodes; second line, not the verdict ==='], pts(find(~M.L)), sum(~Lep), numel(Lep))}, ...
    tag_words(norm_lines(lb), ' [second line, not the verdict]')];
[l, W] = compare_words(LA, LB, pts(find(M.L))); lines = [lines, {''}, l];

% Recovery time from detection: Line A with N, Line B the headline
[l, N] = rec_summary(LA, LB, ALL, POL, PP.scen, LA.jam, Lep, 'recoverable', LA.run, per_ms, '');
lines = [lines, {''}, l];
Nc = []; Nc36 = [];
if ~isempty(LA.core) && ~isempty(LB.core)
    [l, Nc] = rec_summary(LA.core, LB.core, ALL, POL, PP.scen, LA.jam, Lep, 'recoverable_core', LA.run, per_ms, ...
        'Core action set: ');
    lines = [lines, l];
    [l, Nc36] = rec_summary(LA.core.all36, LB.core.all36, ALL, POL, PP.scen, LA.jam, Lep, 'recoverable', LA.run, ...
        per_ms, 'Core action set (recoverable by the 36): ');
    lines = [lines, l];
end

% Per Eb/N0
lines = [lines, {'', ['=== Per Eb/N0: lect_kpis.m on the episodes of each point; descriptive, not a verdict; at L ' ...
    'points recovery from detection is undefined and T_rec is a BER-only test ===']}];
RS = cell(1, nS);
for k = 1:nS
    keep = s == k;
    A = subset(ALL, keep); R1 = A{1};
    Lk = lect_kpis(A, POL, LBL, iDQN, PP.scen, pay, per_ms); RS{k} = Lk;
    mr = R1.recoverable & R1.threat;
    mj = mr & ismember(reshape(PP.scen(R1.scn), 1, []), LA.jam);
    cnt = sprintf('%d episodes, %d threat, %d recoverable threat, %d recoverable jamming', sum(keep), sum(R1.threat), ...
        sum(mr), sum(mj));
    if isfield(R1, 'recoverable_core'), cnt = [cnt sprintf(', %d recoverable by the core set', sum(R1.recoverable_core & R1.threat))]; end %#ok<AGROW>
    lines{end+1} = sprintf('  Eb/N0 %g dB [%s, %s] clean packet loss %.3f: %s', PP.ebno(k), M.tag{k}, tag_name(M.tag{k}), ...
        M.clean_fer(k), cnt); %#ok<AGROW>
    lines = [lines, row_lines(Lk, M.L(k), per_ms, '')]; %#ok<AGROW>
    if ~isempty(Lk.core)
        lines = [lines, row_lines(Lk.core, M.L(k), per_ms, 'core: '), ...
            row_lines(Lk.core.all36, M.L(k), per_ms, 'core (recoverable by the 36): ')]; %#ok<AGROW>
    end
end

% KPI 4/5 per Eb/N0 (single set) with the mark
if isfield(KP, 'per_ebno') && isfield(KP, 'show_lbl') && size(KP.per_ebno, 1) == nS
    lines = [lines, {'', 'Recovered among recoverable per Eb/N0 (single set, as C2e), %, with the mark; at L points a BER-only test:', ...
        sprintf('%-12s%-12s%s', 'Eb/N0 [dB]', 'mark', sprintf('%11s', KP.show_lbl{:}))}];
    for k = 1:nS
        lines{end+1} = sprintf('%-12g%-12s%s', PP.ebno(k), [M.tag{k} ternary(M.L(k), ' BER-only', '')], ...
            sprintf('%11.1f', KP.per_ebno(k, :))); %#ok<AGROW>
    end
end

% KPI 6: the verdict unchanged, the non-L line and the per-Eb/N0 rows
sU = G.RU{1}.s; aU = G.aboveU; mU = aU & ~M.L(sU);
lines = [lines, {'', sprintf(['=== KPI 6, system false alarms on every independent clean flight from the KPI 1 ' ...
    'threshold (%g dB) ==='], KP.ebno_thr), 'Line A, the verdict (C2e''s lines, reproduced by the gate):'}, G.far_lines];
[FN, ~, l] = far_report(G.RU, POL, LBL, mU, G.T, iDQN, PP.ebno, KP.cls_list, per_ms);
lines = [lines, {sprintf('Non-L points (%s), %d episodes; descriptive, not a verdict:', pts(find(~M.L)), sum(mU))}, l];
FR = cell(1, nS);
for k = 1:nS
    m = aU & sU == k;
    [FR{k}, ~, l] = far_report(G.RU, POL, LBL, m, G.T, iDQN, PP.ebno, KP.cls_list, per_ms);
    lines = [lines, {sprintf('Eb/N0 %g dB [%s] clean packet loss %.3f, %d episodes%s; descriptive, not a verdict:', ...
        PP.ebno(k), M.tag{k}, M.clean_fer(k), sum(m), ternary(PP.ebno(k) < KP.ebno_thr, ...
        ' (below the KPI 1 threshold: not in KPI 6)', ''))}, l]; %#ok<AGROW>
end
S = struct('mark', M, 'line_b', LB, 'rows', {RS}, 'words', {W}, 'n_rec', N, 'n_rec_core', Nc, 'n_rec_core36', Nc36, ...
    'far_nonL', FN, 'far_rows', {FR});
end

function lines = gput_note(LA, ALL, POL, PP, M)
% Normalized goodput is not defined where the clean link loses more than 90% (link_env.m).
R = ALL{find(strcmp(POL, 'none'), 1)}; R1 = ALL{1};
mt = R1.threat;
mj = R1.recoverable & R1.threat & ismember(reshape(PP.scen(R1.scn), 1, []), LA.jam);
nn = isnan(R.gput_post);
lines = {sprintf(['  Normalized goodput is not defined where the clean link loses more than 90%% of its packets ' ...
    '(link_env.m; here %s): Line A''s normalized means leave out those %d of %d threat episodes (%d of %d recoverable ' ...
    'jamming) of the static link (mean ''omitnan''); goodput in bit/s keeps them.'], ...
    point_list(PP.ebno, find(1 - M.clean_fer < 0.1)), sum(nn & mt), sum(mt), sum(nn & mj), sum(mj))};
end

function [lines, N] = rec_summary(LA, LB, ALL, POL, scen, jam, Lep, recf, n_run, per_ms, pre)
% Recovery time from detection per set and policy of lect_kpis.m: Line A with N, the detected
% episodes at L points (t_rec_det there 0, later only by a coded link's first frames, or never
% when fewer than n_run cycles follow the detection), then Line B, the headline.
col = @(p) find(strcmp(POL, p), 1);
R1 = ALL{1};
mr = R1.(recf) & R1.threat;
mj = mr & ismember(reshape(scen(R1.scn), 1, []), jam);
sets = {mr, mj}; sn = {'recoverable threat episodes', 'recoverable jamming episodes'};
lines = {sprintf(['%sRecovery time from detection (lecturer): Line A, all points, with N, its detected episodes at L ' ...
    'points, where t_rec_det is set by construction; Line B, the non-L points, is the headline; median / p90 ' ...
    '[cycles of %g ms] (never %%): onset -> detection | detection -> PER restored (%d cycles) | T_rec from onset'], ...
    pre, per_ms, n_run)};
N = struct('set', {}, 'policy', {}, 'n', {}, 'zero', {}, 'later', {}, 'never', {});
for si = 1:2
    lines{end+1} = sprintf('  %s (Line A %d, Line B %d):', sn{si}, sum(sets{si}), sum(sets{si} & ~Lep)); %#ok<AGROW>
    for a = LA.rec(strcmp({LA.rec.set}, sn{si}))
        R = ALL{col(a.policy)};
        d = sets{si} & Lep & isfinite(R.t_conf);
        q = struct('set', sn{si}, 'policy', a.policy, 'n', sum(d), 'zero', sum(d & R.t_rec_det == 0), ...
            'later', sum(d & R.t_rec_det > 0), 'never', sum(d & ~isfinite(R.t_rec_det)));
        N(end+1) = q; %#ok<AGROW>
        lines{end+1} = sprintf(['    %-44s Line A, all points, includes N = %d episodes at L points where t_rec_det ' ...
            'is set by construction (%d at 0, %d later, %d never): %s | %s | %s'], a.label, q.n, q.zero, q.later, q.never, ...
            tt(a.det, per_ms), tt(a.rec_det, per_ms), tt(a.t_rec, per_ms)); %#ok<AGROW>
        b = LB.rec(strcmp({LB.rec.set}, sn{si}) & strcmp({LB.rec.policy}, a.policy));
        if isempty(b)
            lines{end+1} = sprintf('    %-44s Line B, non-L points (headline): -', ''); %#ok<AGROW>
        else
            lines{end+1} = sprintf('    %-44s Line B, non-L points (headline): %s | %s | %s', '', tt(b.det, per_ms), ...
                tt(b.rec_det, per_ms), tt(b.t_rec, per_ms)); %#ok<AGROW>
        end
    end
end
end

function lines = row_lines(S, isL, per_ms, pre)
% One Eb/N0 point's readings from lect_kpis.m's output S; verdict words labelled descriptive;
% at an L point recovery from detection undefined and T_rec tagged BER-only.
w = ' (descriptive, not a verdict)';
und = 'undefined (restoration threshold >= 100%)';
lines = {};
for v = S.verdict
    if v.n == 0
        lines{end+1} = sprintf('    %sPER %s (%s): no recoverable episodes -> %s%s', pre, v.scenario, v.threat, v.verdict, w); %#ok<AGROW>
    else
        lines{end+1} = sprintf('    %sPER %s (%s), %d recoverable episodes, static PER %.2f%%: %s reduction %.1f%% [%.1f, %.1f] -> %s%s', ...
            pre, v.scenario, v.threat, v.n, v.per_ref_pct, v.label, v.red_pct, v.ci, v.verdict, w); %#ok<AGROW>
    end
end
for q = S.per
    lines{end+1} = sprintf('    %sPER five jamming threats pooled, %-40s %d episodes: %6.2f%% vs %6.2f%% static, reduction %6.1f%% [%.1f, %.1f]%s', ...
        pre, q.label, q.n, q.per_pct, q.per_ref_pct, q.red_pct, q.ci, ternary(any(strcmp(q.policy, {'rule_esc', 'rule_core'})), ...
        [' -> ' q.verdict w], '')); %#ok<AGROW>
end
for q = S.per_threat
    lines{end+1} = sprintf('    %sPER %s, %d episodes, static PER %.2f%%: reduction %s', pre, q.threat, q.n, q.per_ref_pct, ...
        strjoin(arrayfun(@(j) sprintf('%s %.1f [%.1f, %.1f]', S.per(j).label, q.red_pct(j), q.ci(j, 1), q.ci(j, 2)), ...
        1:numel(S.per), 'UniformOutput', false), ' | ')); %#ok<AGROW>
end
c = S.cnn;
rd = und;
if ~isL, rd = sprintf('%s vs %s', tt(c.rec_det(1), per_ms), tt(c.rec_det(2), per_ms)); end
lines{end+1} = sprintf(['    %sCNN contribution (%d episodes): PER reduction %.1f%% [%.1f, %.1f], goodput %+.0f bit/s ' ...
    '[%+.0f, %+.0f]; with vs without the detector: onset -> detection %s vs %s, detection -> PER restored %s'], pre, ...
    c.n, c.per_red_pct, c.per_ci, c.gput_bps, c.gput_ci, tt(c.det(1), per_ms), tt(c.det(2), per_ms), rd);
sn = unique({S.rec.set}, 'stable');
for i = 1:numel(sn)
    lines{end+1} = sprintf('    %s%s: onset -> detection | detection -> PER restored | T_rec from onset%s', pre, sn{i}, ...
        ternary(isL, ' (BER-only)', '')); %#ok<AGROW>
    for q = S.rec(strcmp({S.rec.set}, sn{i}))
        r = und;
        if ~isL, r = tt(q.rec_det, per_ms); end
        lines{end+1} = sprintf('      %-44s %d: %s | %s | %s%s', q.label, q.n, tt(q.det, per_ms), r, tt(q.t_rec, per_ms), ...
            ternary(isL, ' BER-only', '')); %#ok<AGROW>
    end
end
for q = S.gput
    lines{end+1} = sprintf('    %sgoodput %-44s threat %s [%s, %s], normalized %s | recoverable jamming %s [%s, %s], normalized %s', ...
        pre, q.label, bps(q.bps), bps(q.ci(1)), bps(q.ci(2)), nrm(q.norm), bps(q.bps_jam), bps(q.ci_jam(1)), ...
        bps(q.ci_jam(2)), nrm(q.norm_jam)); %#ok<AGROW>
end
end

function [lines, W] = compare_words(LA, LB, lpts)
% The verdict words of Lines A and B per reading; where they differ, both are named.
W = [words(LA, LB, '')];
if ~isempty(LA.core) && ~isempty(LB.core)
    W = [W; words(LA.core, LB.core, 'core action set: '); ...
        words(LA.core.all36, LB.core.all36, 'core action set, recoverable by the 36: ')];
end
d = find(~strcmp(W(:, 2), W(:, 3)));
if isempty(d)
    lines = {'Lines A and B give the same verdict words for every reading.'};
else
    lines = {sprintf('Lines A and B differ in verdict words for %d reading(s); Line A stays the verdict:', numel(d))};
    for i = d'
        lines{end+1} = sprintf(['  %s: Line A %s (the verdict), Line B %s. The difference comes from the link-limited ' ...
            'points (%s), where the clean link itself loses half its packets or more, so packet loss cannot be ' ...
            'restored from jamming there.'], W{i, 1}, W{i, 2}, W{i, 3}, lpts); %#ok<AGROW>
    end
end
end

function W = words(A, B, pre)
W = cell(0, 3);
for v = A.verdict
    j = find(strcmp({B.verdict.scenario}, v.scenario), 1); wb = '-';
    if ~isempty(j), wb = B.verdict(j).verdict; end
    W(end+1, :) = {sprintf('%sPER %s (%s), %s', pre, v.scenario, v.threat, v.label), v.verdict, wb}; %#ok<AGROW>
end
for q = A.per(ismember({A.per.policy}, {'rule_esc', 'rule_core'}))
    j = find(strcmp({B.per.policy}, q.policy), 1); wb = '-';
    if ~isempty(j), wb = B.per(j).verdict; end
    W(end+1, :) = {sprintf('%sPER five jamming threats pooled, %s', pre, q.label), q.verdict, wb}; %#ok<AGROW>
end
end

function l = tag_words(l, t)
% Appends t to every line that carries a verdict word.
v = ~cellfun(@isempty, regexp(l, '-> (MET|NOT MET)', 'once'));
if any(v), l(v) = strcat(l(v), {t}); end
end

%% ===================== evaluate_policies.m's far_report, byte for byte =====================
function [FAR, FD, lines] = far_report(RR, POL, LBL, above, T, iDQN, ebno, cls_list, period_ms)
% False-alarm counts per policy (episodes with >= 1 change, Clopper-Pearson
% bound; false changes per cycle and per hour, false_change_rate.m), and for the
% deployed policy and rule + escalation the false-alarm episodes per Eb/N0 and the
% trigger at the first change.
lines = {};
FAR = struct('policy', {}, 'k', {}, 'n', {}, 'p', {}, 'upper', {}, 'per_cycle', {}, 'rate', {});
for pk = 1:numel(POL)
    if any(strcmp(POL{pk}, {'oracle', 'random'})), continue; end
    R = RR{pk}; kf = sum(R.switches(above) > 0); n = sum(above);
    F = false_change_rate(R.switches(above), T, R.geom(above) + 1e6 * R.split(above), period_ms);
    FAR(end+1) = struct('policy', LBL{pk}, 'k', kf, 'n', n, 'p', kf / n, 'upper', cp_upper(kf, n), ...
        'per_cycle', F.rate, 'rate', F); %#ok<AGROW>
    lines{end+1} = sprintf(['  %-40s %4d / %4d = %6.2f%%   upper %6.2f%%   per cycle %.4f%% (<= %.4f%%), %.0f per hour ' ...
        '(<= %.0f), one every %.3g s'], LBL{pk}, kf, n, 100 * kf / n, 100 * FAR(end).upper, 100 * F.rate, 100 * F.hi, ...
        F.per_hour, F.per_hour_hi, F.mtbf_s); %#ok<AGROW>
end
nS = numel(ebno);
FD = struct('policy', {}, 'by_ebno', {}, 'n_ebno', {}, 'cls', {}, 'deg', {}, 'drop', {});
for pk = unique([iDQN, find(strcmp(POL, 'rule_esc'))], 'stable')
    R = RR{pk}; fe = above & R.switches > 0;
    byE = arrayfun(@(s) sum(fe & R.s == s), 1:nS); nE = arrayfun(@(s) sum(above & R.s == s), 1:nS);
    lines{end+1} = sprintf('  %s, false-alarm episodes per Eb/N0: %s', LBL{pk}, strjoin(arrayfun(@(s) ...
        sprintf('%g dB %d/%d', ebno(s), byE(s), nE(s)), 1:nS, 'UniformOutput', false), ' | ')); %#ok<AGROW>
    c = R.fc_cls(fe); d = R.fc_deg(fe); dr = R.fc_drop(fe); u = unique(c(c > 0));
    txt = strjoin(arrayfun(@(k) sprintf('%s %d (degraded %d, median Eb/N0 drop %.1f dB)', cls_list{k}, ...
        sum(c == k), sum(c == k & d), median(dr(c == k), 'omitnan')), u, 'UniformOutput', false), ', ');
    if isempty(txt), txt = '-'; end
    lines{end+1} = sprintf('    detector class at the first change: %s', txt); %#ok<AGROW>
    FD(end+1) = struct('policy', LBL{pk}, 'by_ebno', byE, 'n_ebno', nE, 'cls', c, 'deg', d, 'drop', dr); %#ok<AGROW>
end
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion.
if k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

%% ===================== Helpers =====================
function [nthr, how] = thread_info()
% The thread count this session really has; maxNumCompThreads('automatic') is refused under
% -singleCompThread (the gated wrapper's), which keeps one.
how = 'maxNumCompThreads set to automatic';
try, maxNumCompThreads('automatic'); catch, how = 'not changeable in this session: -singleCompThread'; end
try, nthr = maxNumCompThreads; catch, nthr = NaN; how = [how '; the count is not readable']; end
end

function keep_old(f)
% A diagnostics file of an earlier failed attempt stays, under its own time.
if ~isfile(f), return; end
d = dir(f); [p, n, e] = fileparts(f);
movefile(f, fullfile(p, [n '_' datestr(d.datenum, 'yyyymmdd_HHMMSS') e]));
end

function R = cat_struct(R, Rb)
f = fieldnames(R);
for i = 1:numel(f), R.(f{i}) = [R.(f{i}), Rb.(f{i})]; end
end

function s = tt(q, period_ms)
% Median / p90 of a recovery time as lect_kpis.m prints it.
if isnan(q.median), s = sprintf('- (never %.1f%%)', q.never_pct); return; end
s = sprintf('%g / %g (%g / %g ms, never %.1f%%)', q.median, q.p90, q.median * period_ms, q.p90 * period_ms, q.never_pct);
end

function s = bps(x)
if ~isfinite(x), s = 'n/a'; elseif abs(x) >= 1e3, s = sprintf('%.2f kb/s', x / 1e3); else, s = sprintf('%.0f b/s', x); end
end

function s = nrm(x)
% Normalized goodput: n/a where the clean link loses more than 90%; above 1 it is real.
if isnan(x), s = 'n/a (clean loss > 90%)';
elseif x > 1, s = sprintf('%.3f (above 1: the clean link loses more here)', x);
else, s = sprintf('%.3f', x); end
end

function s = point_list(ebno, k)
if isempty(k), s = 'none'; return; end
s = strjoin(arrayfun(@(i) sprintf('%g dB', ebno(i)), k(:)', 'UniformOutput', false), ', ');
end

function s = tag_name(t)
switch t
    case 'L', s = 'link-limited';
    case 'J', s = 'working point';
    otherwise, s = 'marginal';
end
end

function h = file_sha(f)
% SHA-256 of a file, as sha256sum prints it, read in pieces of 64 MB.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'lect_kpis_by_ebno:sha', 'cannot read %s', f);
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^26, '*uint8');
    if isempty(b), break; end
    md.update(b);
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function st = stamps(files)
% Size and time of each file.
st = cell(size(files));
for i = 1:numel(files)
    d = dir(files{i}); st{i} = [d.bytes, d.datenum];
end
end

function t = read_lines(f)
t = norm_lines(regexp(fileread(f), '\r?\n', 'split'));
if ~isempty(t) && isempty(t{end}), t(end) = []; end
end

function l = norm_lines(l)
l = reshape(l, 1, []);
l(cellfun(@isempty, l)) = {''};
end

function write_lines(f, lines)
fid = fopen(f, 'w');
assert(fid > 0, 'lect_kpis_by_ebno:write', 'cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function y = is_abs(p)
y = ischar(p) && numel(p) > 2 && ((p(2) == ':' && any(p(3) == '\/')) || startsWith(p, '\\') || startsWith(p, '/'));
end

function v = field_or(S, f, d)
if isfield(S, f), v = S.(f); else, v = d; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
