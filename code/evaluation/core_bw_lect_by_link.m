function varargout = core_bw_lect_by_link(cmd, varargin)
%CORE_BW_LECT_BY_LINK  The bandwidth study's lecturer readings where the restoration test of
%   packet loss is defined (docs/lect_ebno_protocol.md, CORE_BW). The study reads against the
%   same flight's clean link, so the mark is per episode: link-limited (L) when the flight's own
%   restoration threshold, C.ratio_ok x its clean packet loss + one loss event
%   (experiment_core_bw.m plr_threshold), is 1 or more; exact for the core configurations, none
%   of which uses fec_interleave. Reporting only: the study's verdicts and code stay as they are.
%   core_bw_lect_by_link('run', F)
%       F absolute paths: F.pools (data/core_bw/pools.mat), F.test (results/core_bw/
%       test_readings.mat), F.recov (results/core_bw/recoverable.txt), F.kpis (results/core_bw/
%       core_bw_kpis.mat), F.report (results/core_bw/core_bw_report.txt), F.params (params.mat)
%       and F.out (the reading copy's folder). The inputs are only read. In this order: the mark
%       from the pools' clean cell on the test split, written with the pools' SHA-256 to
%       F.out/core_bw_low_ebno_mark.txt before F.test is opened; the gate; only on a pass the
%       readings -> F.out/core_bw_lect_by_link.{txt,mat}. Once: refused when they exist.
%   thr = core_bw_lect_by_link('mark', PP)
%       the restoration threshold of every (Eb/N0, test geometry), as plr_threshold
%   G = core_bw_lect_by_link('gate', T, REC, KPc, report, P, pay)
%       T test_readings.mat (RES, EPs, X, meta), REC the frozen recoverable list, KPc
%       core_bw_kpis.mat (KP, lines), report its text one cell per line, P the pools' runs,
%       params_id and det_id, pay the payload rate [bit/s]. G.pass when per_lines on the primary
%       scenarios gives KP.primary and its lines of the report and of KPc.lines; exact
%   [S, lines] = core_bw_lect_by_link('readings', T, G, Lep, pay)
%       the marked episodes and scenarios, Line A (the verdict, the report's lines), Line B (the
%       non-L episodes, a second line), the comparison of their verdict words, and recovery time
%       from detection (Line B the headline, Line A with N: its detected L episodes, where
%       t_rec_det is set by construction)
%   [lines, Kp] = core_bw_lect_by_link('per_lines', S, EP, mask, X, pay, ttl, brief)
%       experiment_core_bw.m's per_lines; it and read_recoverable, recoverable_mask, get_set,
%       pol, qstat and plr_threshold are carried byte for byte
switch cmd
    case 'run',       run_reading(varargin{:});
    case 'mark',      varargout{1} = mark(varargin{:});
    case 'gate',      varargout{1} = gate(varargin{:});
    case 'readings',  [varargout{1}, varargout{2}] = readings(varargin{:});
    case 'per_lines', [varargout{1}, varargout{2}] = per_lines(varargin{:});
    case 'read_recoverable', varargout{1} = read_recoverable(varargin{:});
    otherwise, error('core_bw_lect_by_link:cmd', 'core_bw_lect_by_link: unknown command %s', cmd);
end
end

%% ===================== The single run =====================
function run_reading(F)
for f = {'pools', 'test', 'recov', 'kpis', 'report', 'params'}
    assert(isfield(F, f{1}) && is_abs(F.(f{1})) && isfile(F.(f{1})), 'core_bw_lect_by_link:input', ...
        'F.%s: not an absolute path of a file', f{1});
end
assert(isfield(F, 'out') && is_abs(F.out) && isfolder(F.out), 'core_bw_lect_by_link:input', 'F.out: not an absolute path of a folder');
fk = fullfile(F.out, 'core_bw_low_ebno_mark.txt');
fo = fullfile(F.out, 'core_bw_lect_by_link.txt'); fm = fullfile(F.out, 'core_bw_lect_by_link.mat');
assert(~isfile(fo) && ~isfile(fm), 'core_bw_lect_by_link:once', '%s exists: the reading runs once', fo);
try, maxNumCompThreads('automatic'); catch, end   % a -singleCompThread session keeps one thread; the gate decides
try, nthr = maxNumCompThreads; catch, nthr = 1; end
ins = {F.pools, F.test, F.recov, F.kpis, F.report, F.params};
st0 = stamps(ins);

% 1. The mark, from the pools alone
h_pools = lect_kpis_by_ebno('sha', F.pools);
Lp = load(F.pools, 'PP');
thr = mark(Lp.PP);
P = struct('ebno', Lp.PP.ebno, 'runs', {Lp.PP.runs}, 'params_id', Lp.PP.params_id, 'det_id', Lp.PP.det_id);
clear Lp
C = decision_config();
mk = {['# Link-limited test flights of the bandwidth study (docs/lect_ebno_protocol.md, CORE_BW): L when the ' ...
    'flight''s restoration threshold, ratio_ok x its clean packet loss + one loss event (plr_threshold), is >= 1'], ...
    ['pools ' F.pools], ['pools_sha256 ' h_pools], sprintf('ratio_ok %.17g', C.ratio_ok), ...
    'ebno_db geometry run threshold link_limited'};
for s = 1:size(thr, 1)
    for r = 1:size(thr, 2)
        mk{end+1} = sprintf('%g %d %d %.17g %d', P.ebno(s), r, P.runs{2}(r), thr(s, r), thr(s, r) >= 1); %#ok<AGROW>
    end
end
if isfile(fk)
    assert(isequal(read_lines(fk), mk), 'core_bw_lect_by_link:mark', '%s exists and is not the mark of these pools', fk);
else
    write_lines(fk, mk);
end
h_mark = lect_kpis_by_ebno('sha', fk);
fprintf('Mark written before the test readings are opened: %s (%d of %d flights L)\n', fk, nnz(thr >= 1), numel(thr));

% 2. The test readings, the gate, the readings
h = cellfun(@(f) lect_kpis_by_ebno('sha', f), ins(2:end), 'UniformOutput', false);
T = load(F.test, 'RES', 'EPs', 'X', 'meta');
REC = read_recoverable(F.recov);
KPc = load(F.kpis, 'KP', 'lines');
rep = read_lines(F.report);
p0 = load(F.params); p0 = p0.params;
pay = p0.bits_per_frame / p0.cycle_s;
head = [{'=== The bandwidth study''s lecturer readings where the restoration test is defined (docs/lect_ebno_protocol.md, CORE_BW): reporting only, the verdicts are Line A''s ===', ...
    sprintf('pools %s sha256 %s', F.pools, h_pools), sprintf('mark %s sha256 %s (written before the test readings were opened)', fk, h_mark)}, ...
    cellfun(@(f, x) sprintf('input %s sha256 %s', f, x), ins(2:end), h, 'UniformOutput', false), ...
    {sprintf('threads %d (maxNumCompThreads automatic)', nthr)}];
G = gate(T, REC, KPc, rep, P, pay);
if ~G.pass
    lines = [{sprintf('GATE FAIL (%d mismatches): no subset is read', numel(G.mismatch))}, head, G.mismatch];
    write_lines(fo, lines);
    save(fm, 'thr', 'G', 'lines', 'h_pools', 'h', 'h_mark', 'nthr', 'F');
    fprintf('%s\n', lines{:});
    error('core_bw_lect_by_link:gate', 'the gate failed: %s', fo);
end
Lep = ep_mark(thr, T.EPs);
[S, body] = readings(T, G, Lep, pay);
assert(isequal(st0, stamps(ins)), 'core_bw_lect_by_link:inputs', 'an input changed during the reading');
lines = [{'GATE PASS: per_lines reproduces the report''s KP.primary and its lines exactly'}, head, body];
write_lines(fo, lines);
save(fm, 'thr', 'Lep', 'G', 'S', 'lines', 'h_pools', 'h', 'h_mark', 'nthr', 'F');
fprintf('%s\n', lines{:});
fprintf('Saved %s, %s\n', fo, fm);
end

%% ===================== Mark =====================
function thr = mark(PP)
C = decision_config();
K = struct('clean', find(strcmp(PP.scen, 'none'), 1), 'na', find(strcmp(PP.actions, 'no_action')), 'Q', C.fec_frames);
if isfield(PP, 'fec_frames'), K.Q = PP.fec_frames; end
if isfield(PP, 'event_frame') && ~isempty(PP.event_frame)
    assert(all(isnan(PP.event_frame{2})), 'core_bw_lect_by_link:event_frame', ...
        'the test flights roll in: link_env.m''s flight reference spans their event, plr_threshold the whole flight');
end
thr = plr_threshold(PP, K, 2, C);
end

function L = ep_mark(thr, EP)
L = thr(sub2ind(size(thr), EP.s, EP.r)) >= 1;
L = reshape(L, 1, []);
end

%% ===================== Gate =====================
function G = gate(T, REC, KPc, report, P, pay)
TITLE = 'PRIMARY (H1, nRF24L01+ residual by offset, fixed total power, static jammer)';
G = struct('pass', false, 'mismatch', {{}}, 'primary', [], 'lines', {{}}, 'mask', []);
mm = {};
if ~isequal(T.meta.runs, P.runs) || ~strcmp(T.meta.params_id, P.params_id) || ~strcmp(T.meta.det_id, P.det_id)
    mm{end+1} = 'the test readings were not run on these pools (runs, params_id or det_id)';
end
if ~isfield(KPc, 'KP') || ~isfield(KPc.KP, 'primary'), mm{end+1} = 'core_bw_kpis.mat holds no KP.primary'; end
if ~isempty(mm), G.mismatch = mm; return; end
X0 = T.X; EP = T.EPs; q1 = X0.RULES{1};
mask = recoverable_mask(REC, q1, EP) & ~EP.slice & ~EP.occ;
[blk, Kp] = per_lines(get_set(T.RES, q1, 'primary'), EP, mask, X0, pay, TITLE, false);
blk = norm_lines(blk);
mm = [mm, differs(Kp, KPc.KP.primary, 'per_lines on the primary scenarios vs KP.primary')];
for src = {{report, 'the report'}, {norm_lines(KPc.lines), 'core_bw_kpis.mat lines'}}
    t = src{1}{1};
    i = find(strcmp(t, blk{2}));
    if numel(i) ~= 1
        mm{end+1} = sprintf('%s holds the primary header %d times, not once', src{1}{2}, numel(i)); %#ok<AGROW>
    else
        mm = [mm, block_diff(t, blk, i - 1, ['per_lines''s lines in ' src{1}{2}])]; %#ok<AGROW>
    end
end
G = struct('pass', isempty(mm), 'mismatch', {mm}, 'primary', Kp, 'lines', {blk}, 'mask', mask);
end

function d = differs(a, b, name)
% The fields of a and b that are not equal (isequaln), one line each.
d = {};
if isequaln(a, b), return; end
if isstruct(a) && isstruct(b) && isequal(size(a), size(b)) && isempty(setxor(fieldnames(a), fieldnames(b)))
    for f = fieldnames(a)'
        if ~isequaln({a.(f{1})}, {b.(f{1})}), d{end+1} = sprintf('%s: .%s differs', name, f{1}); end %#ok<AGROW>
    end
end
if isempty(d), d = {sprintf('%s: differs (size or fields)', name)}; end
end

function d = block_diff(txt, blk, i0, name)
d = {};
blk = reshape(blk, 1, []);
if i0 < 1 || i0 + numel(blk) - 1 > numel(txt)
    d = {sprintf('%s: %d lines do not fit the text from line %d', name, numel(blk), i0)}; return
end
k = find(~strcmp(txt(i0:i0 + numel(blk) - 1), blk), 1);
if ~isempty(k)
    d = {sprintf('%s: first difference at line %d: "%s" vs "%s"', name, i0 + k - 1, txt{i0 + k - 1}, blk{k})};
end
end

%% ===================== Readings =====================
function [S, lines] = readings(T, G, Lep, pay)
X0 = T.X; EP = T.EPs; q1 = X0.RULES{1};
Sp = get_set(T.RES, q1, 'primary');
Rn = pol(Sp, 'none'); e = Rn.ep; m0 = G.mask(e); Le = Lep(e);
ks = unique([EP.k(e(m0)); EP.s(e(m0))]', 'rows');
anyL = false(size(ks, 1), 1); allL = anyL;
for i = 1:size(ks, 1)
    j = m0 & EP.k(e) == ks(i, 1) & EP.s(e) == ks(i, 2);
    anyL(i) = any(Le(j)); allL(i) = all(Le(j));
end
lines = {'', sprintf(['Mark (per episode: the flight''s own restoration threshold >= 1): %d of the %d primary-set test ' ...
    'episodes; %d of the %d episodes of the recoverable scenarios; of these %d scenario points (scenario, Eb/N0), %d hold ' ...
    'an L episode and %d only L episodes'], sum(Le), numel(e), sum(m0 & Le), sum(m0), size(ks, 1), sum(anyL), sum(allL))};

% Line A: the verdict
lines = [lines, {'', '=== Line A, the verdict: every episode of the recoverable scenarios (the report''s lines, reproduced by the gate) ==='}, G.lines];

% Line B: the non-L episodes
[blk, KB] = per_lines(Sp, EP, G.mask & ~Lep, X0, pay, ...
    'Line B: the episodes where the restoration test is defined (non-L); second line, not the verdict', false);
lines = [lines, {'', sprintf('=== Line B, where the restoration test is defined: %d non-L episodes of the recoverable scenarios ===', ...
    sum(m0 & ~Le))}, tag_words(norm_lines(blk), ' [second line, not the verdict]')];

% Verdict words of the two lines
A = G.primary.per; W = cell(0, 3);
for a = A
    b = KB.per(strcmp({KB.per.policy}, a.policy) & strcmp({KB.per.type}, a.type));
    W(end+1, :) = {sprintf('PER %s %s%s', a.policy, a.type, ternary(a.primary, ' (primary)', '')), a.verdict, b.verdict}; %#ok<AGROW>
end
d = find(~strcmp(W(:, 2), W(:, 3)));
lines{end+1} = '';
if isempty(d)
    lines{end+1} = 'Lines A and B give the same verdict words for every reading.';
else
    lines{end+1} = sprintf('Lines A and B differ in verdict words for %d reading(s); Line A stays the verdict:', numel(d));
    for i = d'
        lines{end+1} = sprintf(['  %s: Line A %s (the verdict), Line B %s. The difference comes from the link-limited ' ...
            'flights, whose clean link loses half its packets or more, so packet loss cannot be restored from jamming ' ...
            'there.'], W{i, 1}, W{i, 2}, W{i, 3}); %#ok<AGROW>
    end
end

% Recovery time from detection: Line A with N, Line B the headline
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
lines = [lines, {'', sprintf(['Recovery time from detection (lecturer): Line A, every episode, with N, its detected L ' ...
    'episodes, where t_rec_det is set by construction; Line B, the non-L episodes, is the headline; median/p90 ' ...
    '(never %%): onset->detection | detection->restored (%d cycles)'], X0.N_RUN)}];
N = struct('policy', {}, 'type', {}, 'n', {}, 'zero', {}, 'later', {}, 'never', {});
for pk = {'none', 'blind_core', 'rule_core'}
    R = pol(Sp, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(e) & Le & isfinite(R.t_conf);
        q = struct('policy', pk{1}, 'type', types{t, 1}, 'n', nnz(m), 'zero', nnz(m & R.t_rec_det == 0), ...
            'later', nnz(m & R.t_rec_det > 0), 'never', nnz(m & ~isfinite(R.t_rec_det)));
        N(end+1) = q; %#ok<AGROW>
        a = G.primary.rec.(pk{1}).(types{t, 1}); b = KB.rec.(pk{1}).(types{t, 1});
        lines{end+1} = sprintf(['  %-10s %-10s Line A, every episode, includes N = %d L episodes where t_rec_det is set ' ...
            'by construction (%d at 0, %d later, %d never): %s | %s'], pk{1}, types{t, 1}, q.n, q.zero, q.later, q.never, ...
            a.det.txt, a.rec_det.txt); %#ok<AGROW>
        lines{end+1} = sprintf('  %-10s %-10s Line B, non-L episodes (headline): %s | %s', '', '', b.det.txt, b.rec_det.txt); %#ok<AGROW>
    end
end
S = struct('n_L', sum(Le), 'n_L_recoverable', sum(m0 & Le), 'scen', ks, 'scen_anyL', anyL, 'scen_allL', allL, ...
    'line_b', KB, 'words', {W}, 'n_rec', N);
end

function l = tag_words(l, t)
% Appends t to every line that carries a verdict word.
v = ~cellfun(@isempty, regexp(l, '-> (MET|NOT MET)', 'once'));
if any(v), l(v) = strcat(l(v), {t}); end
end

%% ===================== experiment_core_bw.m's readers, byte for byte =====================
function thr = plr_threshold(PP, K, sp, C)
% The packet-loss restoration threshold of every (Eb/N0, geometry) of split sp: C.ratio_ok x
% the same flight's clean packet loss + one loss event (packet_share.m), as link_env.m.
nS = numel(PP.ebno); nG = numel(PP.runs{sp});
thr = nan(nS, nG);
for s = 1:nS
    Pc = PP.pools{K.clean, s, K.na, sp};
    for r = 1:nG
        k = Pc.run == PP.runs{sp}(r);
        thr(s, r) = C.ratio_ok * mean(double(Pc.fer(k))) + packet_share('no_action', Pc.fer(k), K.Q);
    end
end
end

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

function [lines, Kp] = per_lines(S, EP, mask, X, pay, ttl, brief)
% PER reduction vs the static link (the primary verdict per jamming type, the pooled one its
% second line), recovery time, goodput and the CNN's contribution, pooled and per jamming type,
% on the episodes of the recoverable scenarios; brief: a sensitivity, its PER lines only.
lines = {'', sprintf('--- %s ---', ttl)};
if ~brief
    lines{end+1} = sprintf(['  PER reduction >= %g%% vs the static link per jamming type: MET (committed) when the ' ...
        '95%% lower bound clears it, MET (not committed) when only the point does, NOT MET otherwise'], 100 * X.TARGET);
end
Rn = pol(S, 'none'); m0 = mask(Rn.ep);
types = {'pooled', true(1, EP.n); 'narrowband', EP.narrow; 'wideband', ~EP.narrow};
Kp = struct('per', struct('policy', {}, 'type', {}, 'n', {}, 'red', {}, 'lo', {}, 'hi', {}, 'per', {}, 'per_ref', {}), ...
    'rec', struct(), 'gput', struct(), 'cnn', struct());
for pk = {'rule_core', 'blind_core'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        [v, lo, hi] = per_reduction(R.per_post(m), Rn.per_post(m), EP.geom(Rn.ep(m)), X.B, 3);
        Kp.per(end+1) = struct('policy', pk{1}, 'type', types{t, 1}, 'n', nnz(m), 'red', v, 'lo', lo, 'hi', hi, ...
            'per', mean(R.per_post(m)), 'per_ref', mean(Rn.per_post(m)));
    end
end
[Kp.per, blk] = core_bw_rules('per_verdicts', Kp.per, X.TARGET, ~brief);
lines = [lines, blk];
if brief, return; end
mr = m0 & Rn.recoverable & Rn.threat;                 % beside it: the per-episode reading (lect_kpis.m)
for pk = {'rule_core', 'blind_core'}
    R = pol(S, pk{1});
    [v, lo, hi] = per_reduction(R.per_post(mr), Rn.per_post(mr), EP.geom(Rn.ep(mr)), X.B, 3);
    lines{end+1} = sprintf('  PER %-10s pooled, recoverable episodes only (n=%d): reduction %5.1f%% [%5.1f, %5.1f]', ...
        pk{1}, nnz(mr), 100 * v, 100 * lo, 100 * hi); %#ok<AGROW>
end
for pk = {'none', 'blind_core', 'rule_core'}
    R = pol(S, pk{1});
    for t = 1:size(types, 1)
        m = m0 & types{t, 2}(Rn.ep);
        a = qstat(R.t_conf(m)); b = qstat(R.t_rec_det(m));
        [g, glo, ghi] = boot_cluster(pay * R.dlv_post(m), ones(1, nnz(m)), EP.geom(Rn.ep(m)), X.B, 5);
        lines{end+1} = sprintf(['  %-10s %-10s onset->detection %s | detection->restored (%d cycles) %s | goodput ' ...
            '%.0f [%.0f, %.0f] bit/s'], pk{1}, types{t, 1}, a.txt, X.N_RUN, b.txt, g, glo, ghi); %#ok<AGROW>
        Kp.rec.(pk{1}).(types{t, 1}) = struct('det', a, 'rec_det', b); Kp.gput.(pk{1}).(types{t, 1}) = [g glo ghi];
    end
end
Rr = pol(S, 'rule_core'); Rb = pol(S, 'blind_core');
for t = 1:size(types, 1)
    m = m0 & types{t, 2}(Rn.ep); cl = EP.geom(Rn.ep(m));
    [dp, dlo, dhi] = boot_cluster(Rr.per_post(m) - Rb.per_post(m), ones(1, nnz(m)), cl, X.B, 6);
    [rr, rlo, rhi] = per_reduction(Rr.per_post(m), Rb.per_post(m), cl, X.B, 7);
    [dg, glo, ghi] = boot_cluster(pay * (Rr.dlv_post(m) - Rb.dlv_post(m)), ones(1, nnz(m)), cl, X.B, 8);
    f = m & isfinite(Rr.t_rec_det) & isfinite(Rb.t_rec_det);
    [dt, tlo, thi] = boot_cluster(Rr.t_rec_det(f) - Rb.t_rec_det(f), ones(1, nnz(f)), EP.geom(Rn.ep(f)), X.B, 9);
    lines{end+1} = sprintf(['  CNN contribution %-10s rule_core - blind_core: PER %+.4f [%+.4f, %+.4f] (reduction %5.1f%% ' ...
        '[%5.1f, %5.1f]) | goodput %+.0f [%+.0f, %+.0f] bit/s | detection->restored %+.2f [%+.2f, %+.2f] cycles on the %d ' ...
        'episodes both recover in (never %.0f%% vs %.0f%%)'], types{t, 1}, dp, dlo, dhi, 100 * rr, 100 * rlo, 100 * rhi, dg, ...
        glo, ghi, dt, tlo, thi, nnz(f), 100 * mean(~isfinite(Rr.t_rec_det(m))), 100 * mean(~isfinite(Rb.t_rec_det(m)))); %#ok<AGROW>
    Kp.cnn.(types{t, 1}) = struct('per', [dp dlo dhi], 'per_red', [rr rlo rhi], 'gput', [dg glo ghi], 'trec', [dt tlo thi], ...
        'n_both', nnz(f));
end
if any(strcmp({S.policy}, 'oracle'))
    Ro = pol(S, 'oracle');
    [v, lo, hi] = per_reduction(Ro.per_post(m0), Rn.per_post(m0), EP.geom(Rn.ep(m0)), X.B, 3);
    lines{end+1} = sprintf('  oracle (one-step, a bound only): PER reduction %5.1f%% [%5.1f, %5.1f]', 100 * v, 100 * lo, 100 * hi);
end
end

function Qs = qstat(x)
% Median and p90 over the episodes where it occurs, and the share where it never does.
f = isfinite(x);
Qs = struct('median', NaN, 'p90', NaN, 'never_pct', 100 * mean(~f));
if any(f), Qs.median = median(x(f)); Qs.p90 = prctile(x(f), 90); end
Qs.txt = sprintf('%g/%g (never %.0f%%)', Qs.median, Qs.p90, Qs.never_pct);
end

%% ===================== Helpers =====================
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
assert(fid > 0, 'core_bw_lect_by_link:write', 'cannot write %s', f);
fprintf(fid, '%s\n', lines{:});
fclose(fid);
end

function y = is_abs(p)
y = ischar(p) && numel(p) > 2 && ((p(2) == ':' && any(p(3) == '\/')) || startsWith(p, '\\') || startsWith(p, '/'));
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
