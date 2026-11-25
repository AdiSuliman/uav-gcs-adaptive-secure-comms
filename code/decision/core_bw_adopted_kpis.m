function varargout = core_bw_adopted_kpis(cmd, varargin)
%CORE_BW_ADOPTED_KPIS  Goodput, recovery time, recoverable episodes and never-restored count of
%   the adopted rule-fix setting's rows in the bandwidth study (core_bw_rule_fix_reading.m
%   reported PER only), with the definitions of experiment_core_bw.m's per_lines.
%   core_bw_adopted_kpis('run', test_mat, out_dir [, tree])
%       test_mat: the rule-fix test.mat (variables x1s, P); beside it selection.json and
%       core_bw_rule_fix_reading.txt. tree (default: selection.json's tree) holds the registered
%       study: results/core_bw/{test_readings.mat, recoverable.txt, core_bw_kpis.mat,
%       core_bw_report.txt} and params.mat. Inputs are only read (SHA-256 before and after).
%       Gate first: the PER rows of the reading and of the registered report are recomputed
%       from the arrays and must be equal; only then out_dir/core_bw_adopted_kpis.{txt,mat}
%       are written. Refused when they exist.
%   G = core_bw_adopted_kpis('gate', T, U, KP, REC, rep, rdl, pay)
%       T the test.mat, U the registered test_readings.mat, KP the registered KP, REC the
%       recoverable list, rep and rdl the report's and the reading's lines (cell arrays)
%   [Rw, lines] = core_bw_adopted_kpis('rows', S, EP, mask, X, pay)
%       S: struct array (policy, R) as in test_readings.mat; mask: episodes of the recoverable
%       scenarios. Rw per policy and jamming type: n; n_rec (also flagged recoverable and threat
%       by the static run); never and never_rec (t_rec_det not finite, in n and in n_rec);
%       rec_det (median/p90 in cycles after detection over the episodes that restore, and the
%       share that never does); gput (mean bit/s, 95% interval); seg (the report's text)
%   P = core_bw_adopted_kpis('per_rows', S, EP, mask, X)   PER reduction per policy and type
switch cmd
    case 'run',      run_reading(varargin{:});
    case 'gate',     varargout{1} = gate(varargin{:});
    case 'rows',     [varargout{1}, varargout{2}] = rows(varargin{:});
    case 'per_rows', varargout{1} = per_rows(varargin{:});
    case 'per_text', varargout{1} = per_text(varargin{:});
    case 'cnn_text', varargout{1} = cnn_text(varargin{:});
    otherwise, error('core_bw_adopted_kpis:cmd', 'core_bw_adopted_kpis: unknown command %s', cmd);
end
end

%% ===================== The single run =====================
function run_reading(test_mat, out_dir, tree)
assert(ischar(test_mat) && isfile(test_mat), 'core_bw_adopted_kpis:input', '%s is not a file', test_mat);
assert(ischar(out_dir) && isfolder(out_dir), 'core_bw_adopted_kpis:input', '%s is not a folder', out_dir);
fo = fullfile(out_dir, 'core_bw_adopted_kpis.txt'); fm = fullfile(out_dir, 'core_bw_adopted_kpis.mat');
assert(~isfile(fo) && ~isfile(fm), 'core_bw_adopted_kpis:once', '%s exists: the reading runs once', fo);
d = fileparts(test_mat);
sel = fullfile(d, 'selection.json'); rd = fullfile(d, 'core_bw_rule_fix_reading.txt');
assert(isfile(sel) && isfile(rd), 'core_bw_adopted_kpis:input', 'selection.json and core_bw_rule_fix_reading.txt must lie beside %s', test_mat);
S0 = jsondecode(fileread(sel));
assert(strcmp(S0.bound, 'keep+rate'), 'core_bw_adopted_kpis:bound', 'the bound setting is %s, not keep+rate', S0.bound);
if nargin < 3, tree = S0.tree; end
I = struct('res', fullfile(tree, 'results', 'core_bw', 'test_readings.mat'), ...
    'recov', fullfile(tree, 'results', 'core_bw', 'recoverable.txt'), ...
    'kpis', fullfile(tree, 'results', 'core_bw', 'core_bw_kpis.mat'), ...
    'report', fullfile(tree, 'results', 'core_bw', 'core_bw_report.txt'), 'params', fullfile(tree, 'params.mat'));
ins = [{test_mat, sel, rd}, struct2cell(I)'];
for i = 1:numel(ins), assert(isfile(ins{i}), 'core_bw_adopted_kpis:input', '%s not found', ins{i}); end
h0 = cellfun(@(f) core_bw_rules('sha', f), ins, 'UniformOutput', false);
T = load(test_mat, 'x1s', 'P');
U = load(I.res, 'RES', 'EPs', 'X', 'meta');
K = load(I.kpis, 'KP');
REC = read_recoverable(I.recov);
p0 = load(I.params); p0 = p0.params;
pay = p0.bits_per_frame / p0.cycle_s;
G = gate(T, U, K.KP, REC, read_text(I.report), read_text(rd), pay);
if ~G.pass
    fprintf('%s\n', G.mismatch{:});
    error('core_bw_adopted_kpis:gate', 'the gate failed (%d mismatches); nothing written', numel(G.mismatch));
end
EP = U.EPs; X0 = U.X;
Soff = get_set(U.RES, X0.RULES{1}, 'primary');
[Roff, loff] = rows(Soff, EP, G.mask, X0, pay);
[Ron, lon] = rows(on_set(T.x1s), EP, G.mask, X0, pay);
lines = [{'G4 GATE PASS', sprintf('=== CORE_BW, adopted setting %s: goodput, recovery time, recoverable episodes, never restored ===', S0.bound), ...
    sprintf('rows: H1 primary set, recoverable scenarios, fixed total power (%d episodes), payload %g bit/s', nnz(G.mask), pay), ...
    'recovery time: cycles from detection to restored (median/p90 over the episodes that restore; never = share that does not)', ...
    'n_rec: episodes of the static run flagged recoverable and threat; never: episodes without restoration (of n, of n_rec)', ...
    sprintf('Gate: the reading''s PER and CNN lines (off and on) and the registered report''s primary PER, recovery and goodput rows were recomputed from the arrays and are equal (%d checks)', G.checks)}, ...
    cellfun(@(f, h) sprintf('input %s sha256 %s', f, h), ins, h0, 'UniformOutput', false), ...
    {'', '--- registered rule (setting off), the report''s primary rows ---'}, loff, ...
    {'', sprintf('--- adopted setting %s (reading''s test) ---', S0.bound)}, lon];
h1 = cellfun(@(f) core_bw_rules('sha', f), ins, 'UniformOutput', false);
assert(isequal(h0, h1), 'core_bw_adopted_kpis:inputs', 'an input changed during the reading');
write_lines(fo, lines);
save(fm, 'Roff', 'Ron', 'lines', 'G', 'ins', 'h0', 'pay');
fprintf('%s\n', lines{:});
fprintf('Saved %s, %s\n', fo, fm);
end

function S = on_set(x)
n = fieldnames(x)';
S = struct('policy', n, 'R', cellfun(@(f) x.(f), n, 'UniformOutput', false));
end

function t = read_text(f)
t = splitlines(fileread(f));
if ~isempty(t) && isempty(t{end}), t(end) = []; end
end

function write_lines(f, lines)
fid = fopen(f, 'w');
assert(fid > 0, 'core_bw_adopted_kpis:write', 'cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

%% ===================== Gate =====================
function G = gate(T, U, KP, REC, rep, rdl, pay)
mm = {}; nc = 0;
X0 = U.X; EP = U.EPs; q1 = X0.RULES{1};
Sp = get_set(U.RES, q1, 'primary');
Son = on_set(T.x1s);
mask = recoverable_mask(REC, q1, EP) & ~EP.slice & ~EP.occ;
G = struct('pass', false, 'mismatch', {{}}, 'mask', mask, 'checks', 0);
Rn = pol(Sp, 'none'); On = pol(Son, 'none');
if ~isequal(Rn.ep, 1:EP.n), mm{end+1} = 'the registered static run does not cover the episodes 1..n in order'; end
for f = fieldnames(On)'
    nc = nc + 1;
    if ~isfield(Rn, f{1}) || ~isequaln(On.(f{1}), Rn.(f{1})), mm{end+1} = sprintf('x1s.none.%s differs from the registered static run', f{1}); end %#ok<AGROW>
end
for pk = {'rule_core3', 'rule_core', 'blind_core'}
    nc = nc + 1;
    if ~isequal(pol(Son, pk{1}).ep, Rn.ep), mm{end+1} = sprintf('x1s.%s covers other episodes than the static run', pk{1}); end %#ok<AGROW>
end
if ~isempty(mm), G.mismatch = mm; return; end
% PER rows: the reading's (T.P, on) and the registered KP.primary (off), recomputed
fl = {'n', 'red', 'lo', 'hi', 'per', 'per_ref'};
Pon = per_rows(Son, EP, mask, X0); Pof = per_rows(Sp, EP, mask, X0);
for c = {{Pon, T.P, 'the reading''s test.mat P'}, {Pof, KP.primary.per, 'the registered KP.primary.per'}}
    A = c{1}{1}; B = c{1}{2};
    for i = 1:numel(A)
        j = find(strcmp({B.policy}, A(i).policy) & strcmp({B.type}, A(i).type));
        nc = nc + 1;
        if numel(j) ~= 1 || ~isequaln(cellfun(@(f) A(i).(f), fl), cellfun(@(f) B(j).(f), fl))
            mm{end+1} = sprintf('%s: PER row %s %s differs', c{1}{3}, A(i).policy, A(i).type); %#ok<AGROW>
        end
    end
end
% the reading's printed lines, off and on
for v = {{'off', Pof, Sp}, {'on', Pon, Son}}
    tag = v{1}{1};
    L = [arrayfun(@(p) per_text(tag, p), v{1}{2}, 'UniformOutput', false), cnn_text(tag, v{1}{3}, EP, mask, X0)];
    for i = 1:numel(L)
        nc = nc + 1;
        if ~any(strcmp(rdl, L{i})), mm{end+1} = sprintf('the reading has no line: %s', L{i}); end %#ok<AGROW>
    end
end
% the registered report's recovery and goodput rows and its recoverable-episode counts
Rw = rows(Sp, EP, mask, X0, pay);
for r = Rw
    nc = nc + 1;
    pre = sprintf('  %-10s %-10s onset->detection ', r.policy, r.type);
    i = find(startsWith(rep, pre));
    if numel(i) ~= 1 || ~contains(rep{i}, r.seg)
        mm{end+1} = sprintf('the report''s row %s %s does not hold "%s"', r.policy, r.type, r.seg); %#ok<AGROW>
    end
    k = KP.primary.rec.(r.policy).(r.type); g = KP.primary.gput.(r.policy).(r.type);
    if ~isequaln(k.rec_det, r.rec_det) || ~isequaln(g, r.gput), mm{end+1} = sprintf('KP.primary rec/gput %s %s differs', r.policy, r.type); end %#ok<AGROW>
    if strcmp(r.type, 'pooled') && ~strcmp(r.policy, 'none')
        nc = nc + 1;
        if ~any(contains(rep, sprintf('PER %-10s pooled, recoverable episodes only (n=%d)', r.policy, r.n_rec)))
            mm{end+1} = sprintf('the report''s recoverable-episode count of %s is not %d', r.policy, r.n_rec); %#ok<AGROW>
        end
    end
end
G = struct('pass', isempty(mm), 'mismatch', {mm}, 'mask', mask, 'checks', nc);
end

function s = per_text(tag, p)
s = sprintf('  %-4s %-10s %-10s PER %.4f vs %.4f static, reduction %5.1f%% [%5.1f, %5.1f]', tag, p.policy, p.type, ...
    p.per, p.per_ref, 100 * p.red, 100 * p.lo, 100 * p.hi);
end

function L = cnn_text(tag, S, EP, mask, X)
Rn = pol(S, 'none'); m0 = mask(Rn.ep); R3 = pol(S, 'rule_core3'); Rb = pol(S, 'blind_core');
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
L = cell(1, size(types, 1));
for t = 1:size(types, 1)
    m = m0 & types{t, 2}(Rn.ep);
    [d, lo, hi] = boot_cluster(R3.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), EP.geom(Rn.ep(m)), X.B, 6);
    L{t} = sprintf('  %-4s CNN contribution %-10s rule_core3 - blind_core: PER %+.4f [%+.4f, %+.4f]', tag, types{t, 1}, d, lo, hi);
end
end

%% ===================== Rows =====================
function P = per_rows(S, EP, mask, X)
% per_lines' PER reduction per policy and jamming type, before the verdicts.
Rn = pol(S, 'none'); m0 = mask(Rn.ep);
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
P = struct('policy', {}, 'type', {}, 'n', {}, 'red', {}, 'lo', {}, 'hi', {}, 'per', {}, 'per_ref', {});
for pk = {'rule_core3', 'rule_core', 'blind_core'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        [v, lo, hi] = per_reduction(R.per_post(m), Rn.per_post(m), EP.geom(Rn.ep(m)), X.B, 3);
        P(end+1) = struct('policy', pk{1}, 'type', types{t, 1}, 'n', nnz(m), 'red', v, 'lo', lo, 'hi', hi, ...
            'per', mean(R.per_post(m)), 'per_ref', mean(Rn.per_post(m))); %#ok<AGROW>
    end
end
end

function [Rw, lines] = rows(S, EP, mask, X, pay)
% per_lines' recovery and goodput rows (same expressions), with the counts.
Rn = pol(S, 'none'); m0 = mask(Rn.ep);
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
Rw = struct('policy', {}, 'type', {}, 'n', {}, 'n_rec', {}, 'never', {}, 'never_rec', {}, 'rec_det', {}, 'gput', {}, 'seg', {});
lines = {};
for pk = {'none', 'blind_core', 'rule_core', 'rule_core3'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        mr = m & Rn.recoverable & Rn.threat;
        b = qstat(R.t_rec_det(m));
        [g, glo, ghi] = boot_cluster(pay * R.dlv_post(m), ones(1, nnz(m)), EP.geom(Rn.ep(m)), X.B, 5);
        seg = sprintf('detection->restored (%d cycles) %s | goodput %.0f [%.0f, %.0f] bit/s', X.N_RUN, b.txt, g, glo, ghi);
        Rw(end+1) = struct('policy', pk{1}, 'type', types{t, 1}, 'n', nnz(m), 'n_rec', nnz(mr), ...
            'never', nnz(m & ~isfinite(R.t_rec_det)), 'never_rec', nnz(mr & ~isfinite(R.t_rec_det)), ...
            'rec_det', b, 'gput', [g glo ghi], 'seg', seg); %#ok<AGROW>
        lines{end+1} = sprintf('  %-10s %-10s n=%d n_rec=%d | never restored %d of %d, %d of %d | %s', pk{1}, types{t, 1}, ...
            Rw(end).n, Rw(end).n_rec, Rw(end).never, Rw(end).n, Rw(end).never_rec, Rw(end).n_rec, seg); %#ok<AGROW>
    end
end
end

%% ===================== experiment_core_bw.m's readers, byte for byte =====================

function REC = read_recoverable(f)
% The frozen list (recoverable_lines): rule, scenario and Eb/N0 indices, recoverable.
t = strtrim(splitlines(fileread(f)));
t = t(~cellfun(@isempty, t) & ~startsWith(t, '#'));
c = cellfun(@(x) strsplit(x, ' '), t, 'UniformOutput', false);
REC = struct('rule', {cellfun(@(x) x{1}, c, 'UniformOutput', false)'}, 'k', cellfun(@(x) str2double(x{2}), c)', ...
    's', cellfun(@(x) str2double(x{3}), c)', 'harm', cellfun(@(x) str2double(x{end - 1}), c)' > 0, ...
    'ok', cellfun(@(x) str2double(x{end}), c)' > 0);
end

function m = recoverable_mask(REC, rule, EP)
% Episodes of the scenarios frozen recoverable under the rule.
j = find(strcmp(REC.rule, rule) & REC.ok);
m = false(1, EP.n);
for i = j, m = m | (EP.k == REC.k(i) & EP.s == REC.s(i)); end
end

function S = get_set(RES, rule, set)
S = RES(strcmp({RES.rule}, rule) & strcmp({RES.set}, set));
end

function R = pol(S, name)
R = S(strcmp({S.policy}, name)).R;
end

function Qs = qstat(x)
% Median and p90 over the episodes where it occurs, and the share where it never does.
f = isfinite(x);
Qs = struct('median', NaN, 'p90', NaN, 'never_pct', 100 * mean(~f));
if any(f), Qs.median = median(x(f)); Qs.p90 = prctile(x(f), 90); end
Qs.txt = sprintf('%g/%g (never %.0f%%)', Qs.median, Qs.p90, Qs.never_pct);
end
