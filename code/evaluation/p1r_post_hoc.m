function varargout = p1r_post_hoc(cmd, varargin)
%P1R_POST_HOC  Post-hoc rows on a saved results/policy_evaluation.mat:
%   the deployed DQN's recovery per Eb/N0 point with cluster intervals, the link-limited tags and the
%   deficit split by threat; and the A' readout, the recovery per speed band and the harmed lost-branch
%   episodes per band. Descriptive, run from a read-only copy after P1R's breakdown; the evaluation, the
%   verdicts and P1R's code are not touched, and nothing is selected on these rows.
%   p1r_post_hoc('run', pools, eval_mat, out_dir, reg_commit, docs_repo)
%       pools      a copy of the evaluation's data/policy_pools.mat (PP.ebno, scen, clean_fer, det_id)
%       eval_mat   a copy of results/policy_evaluation.mat
%       out_dir    under <repo>/results: p1r_post_hoc.{txt,mat}, written once; a failed gate writes
%                  p1r_post_hoc.gatefail.txt and stops with p1r_post_hoc:gate
%       reg_commit the commit that registers these readings (hex); docs_repo, if given, is checked for it
%                  (without it the log says the commit is unverified)
%       The gate first reproduces the saved KP.per_ebno and KP.per_speed of the deployed policy from the
%       saved episodes; the rows are read only when it passes. The label follows KP.reading: 'P1R,
%       descriptive', otherwise 'post hoc, added after the reading, descriptive'.
%   M = p1r_post_hoc('mark', clean_fer, ratio_ok)
%       M.L the link-limited points (ratio_ok x clean_fer >= 1: the packet-loss half of the restoration
%       test cannot fail there), M.tag 'L', 'J' (working point: clean_fer < 0.1) or 'M' (marginal)
%   [rows, lines] = p1r_post_hoc('ebno', R, ebno, scen, M, label, C)
%       one row per Eb/N0 point from the episodes R (s, geom, scn, recoverable, threat, recovered):
%       episodes, flights, recovered with the 95% cluster bootstrap interval, 'lower bound >= 90' iff the
%       interval's lower bound is 90 or more, and the deficit (100 - recovered) split by threat
%   [B, lines] = p1r_post_hoc('bands', Rd, Rn, bins, scen, ebno, label, C)
%       the A' readout from the deployed policy's episodes Rd and no response's Rn on the same episodes
%       (Rn.recovered is false exactly on the harmed ones): per speed band, per threat and band, per
%       threat and Eb/N0, and the harmed lost-branch episodes per band
%   mm = p1r_post_hoc('gate', E)      the mismatches of the reproduction of KP.per_ebno and KP.per_speed
switch cmd
    case 'run',   run_reading(varargin{:});
    case 'mark',  varargout{1} = mark(varargin{:});
    case 'ebno',  [varargout{1}, varargout{2}] = ebno_rows(varargin{:});
    case 'bands', [varargout{1}, varargout{2}] = band_rows(varargin{:});
    case 'gate',  varargout{1} = gate(varargin{:});
    otherwise, error('p1r_post_hoc: unknown command %s', cmd);
end
end

%% ===================== The run =====================
function run_reading(pools, eval_mat, out_dir, reg_commit, docs_repo)
root = project_root();
if nargin < 4, reg_commit = ''; end
if nargin < 5, docs_repo = ''; end
t_all = tic;
out_dir = reader_guard('out', out_dir, root);
reader_guard('input', pools, {'policy_pools.mat'});
reader_guard('input', eval_mat, {'policy_evaluation.mat'});
reg = reader_guard('registration', reg_commit, docs_repo);
fo = fullfile(out_dir, 'p1r_post_hoc.txt'); fm = fullfile(out_dir, 'p1r_post_hoc.mat');
ff = fullfile(out_dir, 'p1r_post_hoc.gatefail.txt');
reader_guard('once', {fo, fm});
for f = {pools, eval_mat}
    if ~isfile(f{1}), error('p1r_post_hoc:input', 'p1r_post_hoc: %s not found', f{1}); end
end
if ~isfolder(out_dir), mkdir(out_dir); end
code = {'p1r_post_hoc.m', 'cluster_contrast.m', 'boot_cluster.m', 'reader_guard.m'};
h_code = cellfun(@(f) reader_guard('sha', which(f)), code, 'UniformOutput', false);
h_pools = reader_guard('sha', pools); h_eval = reader_guard('sha', eval_mat);
st0 = stamps({pools, eval_mat});

Lp = load(pools, 'PP');
PP = struct('ebno', Lp.PP.ebno, 'scen', {reshape(cellstr(string(Lp.PP.scen)), [], 1)}, 'clean_fer', Lp.PP.clean_fer, ...
    'det_id', field_or(Lp.PP, 'det_id', ''));
clear Lp
E = load(eval_mat, 'ALL', 'POL', 'LBL', 'iDQN', 'KP', 'RES', 'set_names');
KP = E.KP;
C = decision_config();
cfg = struct('B', 2000, 'seed', 11800);
head = {sprintf('Registration commit %s (D110-D118); rule code sha256: %s', reg, strjoin(cellfun(@(f, h) [f ' ' h], code, h_code, ...
    'UniformOutput', false), ' | ')), sprintf('pools %s sha256 %s', pools, h_pools), ...
    sprintf('evaluation %s sha256 %s', eval_mat, h_eval)};
mm = gate(E);
if ~isequal(double(KP.ebno(:)), double(PP.ebno(:))), mm{end+1} = 'KP.ebno is not the pools'' Eb/N0 grid'; end
if isfield(KP, 'det_id') && ~isempty(PP.det_id) && ~isequal(char(string(KP.det_id)), char(string(PP.det_id)))
    mm{end+1} = 'KP.det_id is not the pools'' det_id';
end
if ~isempty(mm)
    lines = [{sprintf('GATE FAIL (%d mismatches): no row is read; no reading output was written', numel(mm))}, head, mm];
    fid = fopen(ff, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
    fprintf('%s\n', lines{:});
    error('p1r_post_hoc:gate', 'p1r_post_hoc: the gate failed: %s', ff);
end
lab = reading_label(KP);
M = mark(PP.clean_fer, C.ratio_ok);
kd = E.iDQN; kn = find(strcmp(E.POL, 'none'), 1);
body = {sprintf('=== Post-hoc rows on a saved policy_evaluation.mat (D116 items 4, 6 and 8): %s ===', lab), ...
    'GATE PASS: the saved KP.per_ebno and KP.per_speed of the deployed policy are reproduced from the saved episodes', ...
    sprintf('Generated %s | code %s | deployed policy: %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), git_head(root), E.LBL{kd}), ...
    ['Labels: ' lab '. The verdicts stay with the evaluation these episodes come from (D104 point 7); P1R''s code is not changed; ' ...
    'a "lower bound >= 90" line is the interval''s, not a commitment: only EDGE''s verdict commits (D74, D108 point 4).']};
body = [head, body];
S = struct('name', {'single set (the basis of KP.per_ebno)', 'threat sets pooled (single, follower, combined: the basis of KPI 4)'}, ...
    'Rd', {E.RES{1, kd}, E.ALL{kd}}, 'Rn', {E.RES{1, kn}, E.ALL{kn}});
OUT = struct('set', {}, 'rows', {}, 'bands', {});
for k = 1:numel(S)
    Rd = S(k).Rd; Rn = S(k).Rn;
    if ~(isequal(Rd.s, Rn.s) && isequal(Rd.geom, Rn.geom) && isequal(Rd.scn, Rn.scn))
        error('p1r_post_hoc:pairing', 'p1r_post_hoc: %s does not hold the same episodes under the deployed policy and no response', S(k).name);
    end
    [rows, l1] = ebno_rows(Rd, PP.ebno, PP.scen, M, S(k).name, cfg);
    body = [body, {''}, l1]; %#ok<AGROW>
    m = Rd.recoverable & Rd.threat;
    if ~isfield(Rd, 'speed') || ~all(isfinite(Rd.speed(m)))
        body = [body, {'', sprintf('A'' readout, %s: the saved rows carry no speed band, the table is not produced', S(k).name)}]; %#ok<AGROW>
        bands = [];
    else
        [bands, l2] = band_rows(Rd, Rn, KP.speed_bins, PP.scen, PP.ebno, S(k).name, cfg);
        body = [body, {''}, l2]; %#ok<AGROW>
    end
    OUT(end+1) = struct('set', S(k).name, 'rows', rows, 'bands', bands); %#ok<AGROW>
end
if isfield(KP, 'harmed_consistent') && ~KP.harmed_consistent
    body{end+1} = 'WARNING: the evaluation reports that harmed differs from no response''s recovery; the harmed rows are not exact';
end
if ~isequal(st0, stamps({pools, eval_mat})), error('p1r_post_hoc:inputs', 'p1r_post_hoc: an input changed during the reading'); end
body{end+1} = sprintf('Total %.1f min', toc(t_all) / 60);
fid = fopen(fo, 'w'); fprintf(fid, '%s\n', body{:}); fclose(fid);
fprintf('%s\n', body{:});
save(fm, 'M', 'OUT', 'body', 'h_pools', 'h_eval', 'pools', 'eval_mat', 'lab', 'reg', 'h_code', 'cfg');
fprintf('Saved %s and %s\n', fo, fm);
end

function lab = reading_label(KP)
if isfield(KP, 'reading') && ischar(KP.reading) && strcmp(KP.reading, 'P1R')
    lab = 'P1R, descriptive';
else
    lab = 'post hoc, added after the reading, descriptive';
end
end

function s = stamps(files)
s = cellfun(@(f) {dir(f).bytes, dir(f).datenum}, files, 'UniformOutput', false);
end

function v = field_or(S, f, d)
if isfield(S, f), v = S.(f); else, v = d; end
end

function h = git_head(root)
[st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
h = strtrim(h); if st ~= 0, h = 'unknown'; end
end

%% ===================== Mark and gate =====================
function M = mark(clean_fer, ratio_ok)
f = double(clean_fer(:)');
M = struct('clean_fer', f, 'ratio_ok', ratio_ok, 'L', ratio_ok * f >= 1, 'tag', {repmat({'M'}, 1, numel(f))});
M.tag(M.L) = {'L'};
M.tag(~M.L & f < 0.1) = {'J'};
end

function mm = gate(E)
% KP.per_ebno and KP.per_speed of the deployed policy, reproduced from the saved episodes as
% evaluate_policies.m computes them (the single set, the recoverable threat episodes).
mm = {};
need = {'RES', 'POL', 'iDQN', 'KP'};
miss = need(~isfield(E, need));
if ~isempty(miss), mm = {sprintf('the evaluation lacks %s', strjoin(miss, ', '))}; return; end
KP = E.KP;
need = {'per_ebno', 'per_speed', 'speed_bins', 'show'};
miss = need(~isfield(KP, need));
if ~isempty(miss), mm = {sprintf('KP lacks %s', strjoin(miss, ', '))}; return; end
c = find(strcmp(KP.show, E.POL{E.iDQN}), 1);
if isempty(c), mm = {'the deployed policy is not among KP.show'}; return; end
R1 = E.RES{1, 1}; Rk = E.RES{1, E.iDQN};
mrec = R1.recoverable & R1.threat;
nS = size(KP.per_ebno, 1);
pe = arrayfun(@(s) 100 * mean(Rk.recovered(mrec & R1.s == s)), 1:nS)';
if ~same(pe, KP.per_ebno(:, c)), mm{end+1} = 'KP.per_ebno of the deployed policy is not reproduced from the saved episodes'; end
b = KP.speed_bins(:)'; nb = numel(b) - 1;
pv = nan(nb, 1);
for i = 1:nb
    m = mrec & R1.speed >= b(i) & R1.speed < b(i + 1) + (i == nb);
    pv(i) = 100 * mean(Rk.recovered(m));
end
if ~same(pv, KP.per_speed(:, c)), mm{end+1} = 'KP.per_speed of the deployed policy is not reproduced from the saved episodes'; end
end

function t = same(a, b)
a = a(:); b = b(:);
t = numel(a) == numel(b) && all((abs(a - b) <= 1e-9) | (isnan(a) & isnan(b)));
end

%% ===================== Rows per Eb/N0 =====================
function [rows, lines] = ebno_rows(R, ebno, scen, M, label, C)
R = columns(R, {'s', 'geom', 'scn'}, {'recoverable', 'threat', 'recovered'});
m0 = R.recoverable & R.threat;
scen = scen(:);
thr = scen(R.scn);
names = unique(thr(m0), 'stable');
nS = numel(ebno);
rows = struct('ebno', {}, 'tag', {}, 'n', {}, 'ncl', {}, 'rate', {}, 'lo', {}, 'hi', {}, 'lb90', {}, 'fail', {}, 'defs', {});
for s = 1:nS
    m = m0 & R.s == s;
    r = struct('ebno', ebno(s), 'tag', M.tag{s}, 'n', sum(m), 'ncl', 0, 'rate', NaN, 'lo', NaN, 'hi', NaN, 'lb90', false, ...
        'fail', 0, 'defs', zeros(1, numel(names)));
    if any(m)
        [mm, lo, hi] = boot_cluster(double(R.recovered(m)), ones(sum(m), 1), R.geom(m), C.B, C.seed + s);
        r.rate = 100 * mm; r.lo = 100 * lo; r.hi = 100 * hi;
        r.ncl = numel(unique(R.geom(m)));
        r.lb90 = r.lo >= 90;
        r.fail = sum(m & ~R.recovered);
        r.defs = arrayfun(@(k) 100 * sum(m & ~R.recovered & strcmp(thr, names{k})) / sum(m), 1:numel(names));
    end
    rows(end+1) = r; %#ok<AGROW>
end
lines = {sprintf('Per Eb/N0, %s: the deployed DQN''s recovered among the recoverable threat episodes, 95%% cluster bootstrap over flights', label), ...
    ['   tags: L the clean link''s packet loss times the restoration ratio is 1 or more (the packet-loss half of restoration cannot ' ...
    'fail, the test is BER-only there), J a working point (clean packet loss < 0.1), M marginal; deficit = 100 - recovered, split by threat (points)']};
for s = 1:nS
    r = rows(s);
    if r.n == 0
        lines{end+1} = sprintf('   %5g dB  %s  no recoverable threat episode', r.ebno, r.tag); %#ok<AGROW>
        continue;
    end
    lines{end+1} = sprintf('   %5g dB  %s  episodes %4d  flights %3d  recovered %5.1f [%5.1f, %5.1f]  lower bound >= 90: %-3s  deficit %5.1f: %s', ...
        r.ebno, r.tag, r.n, r.ncl, r.rate, r.lo, r.hi, yn(r.lb90), 100 - r.rate, def_txt(r.defs, names)); %#ok<AGROW>
end
end

function s = def_txt(d, names)
[v, o] = sort(d, 'descend');
k = find(v > 0);
if isempty(k), s = 'none'; return; end
top = k(1:min(4, numel(k)));
parts = arrayfun(@(i) sprintf('%s %.1f', names{o(i)}, v(i)), top, 'UniformOutput', false);
rest = sum(v) - sum(v(top));
if rest > 1e-9, parts{end+1} = sprintf('others %.1f', rest); end
s = strjoin(parts, ', ');
end

%% ===================== A' readout =====================
function [B, lines] = band_rows(Rd, Rn, bins, scen, ebno, label, C)
Rd = columns(Rd, {'s', 'geom', 'scn', 'speed'}, {'recoverable', 'threat', 'recovered'});
Rn = columns(Rn, {'s', 'geom', 'scn'}, {'recoverable', 'threat', 'recovered'});
rec = Rd.recoverable & Rd.threat;
harmed = ~Rn.recovered;
scen = scen(:);
thr = scen(Rd.scn);
bins = bins(:)'; nb = numel(bins) - 1; nS = numel(ebno);
bi = zeros(size(Rd.speed));
for b = 1:nb, bi(Rd.speed >= bins(b) & Rd.speed < bins(b + 1) + (b == nb)) = b; end
names = unique(thr(rec), 'stable');
lost = {'antenna_fault', 'airframe_shadowing'};
bn = arrayfun(@(b) sprintf('%.0f-%.0f', bins(b), bins(b + 1)), 1:nb, 'UniformOutput', false);
B = struct('bins', bins, 'names', {names}, 'band', [], 'thr_band', nan(numel(names), nb), 'thr_band_n', zeros(numel(names), nb), ...
    'thr_ebno', nan(numel(names), nS), 'thr_ebno_n', zeros(numel(names), nS), 'lost', []);
lines = {sprintf('A'' readout, %s: the deployed DQN per speed band (km/h) and per Eb/N0, recoverable threat episodes', label)};
bd = struct('n', {}, 'ncl', {}, 'rate', {}, 'lo', {}, 'hi', {});
for b = 1:nb
    m = rec & bi == b;
    r = struct('n', sum(m), 'ncl', 0, 'rate', NaN, 'lo', NaN, 'hi', NaN);
    if any(m)
        [mm, lo, hi] = boot_cluster(double(Rd.recovered(m)), ones(sum(m), 1), Rd.geom(m), C.B, C.seed + 100 + b);
        r.rate = 100 * mm; r.lo = 100 * lo; r.hi = 100 * hi; r.ncl = numel(unique(Rd.geom(m)));
    end
    bd(end+1) = r; %#ok<AGROW>
    lines{end+1} = sprintf('   speed %-9s episodes %4d  flights %3d  recovered %5.1f [%5.1f, %5.1f]', bn{b}, r.n, r.ncl, r.rate, r.lo, r.hi); %#ok<AGROW>
end
B.band = bd;
lines{end+1} = sprintf('   per threat, recovered %% (episodes): speed bands %s || Eb/N0 %s dB', strjoin(bn, ' | '), ...
    strjoin(arrayfun(@(e) sprintf('%g', e), ebno(:)', 'UniformOutput', false), ' | '));
for k = 1:numel(names)
    mt = rec & strcmp(thr, names{k});
    cb = cell(1, nb); ce = cell(1, nS);
    for b = 1:nb
        m = mt & bi == b; B.thr_band_n(k, b) = sum(m);
        if any(m), B.thr_band(k, b) = 100 * mean(double(Rd.recovered(m))); end
        cb{b} = cell_txt(B.thr_band(k, b), B.thr_band_n(k, b));
    end
    for s = 1:nS
        m = mt & Rd.s == s; B.thr_ebno_n(k, s) = sum(m);
        if any(m), B.thr_ebno(k, s) = 100 * mean(double(Rd.recovered(m))); end
        ce{s} = cell_txt(B.thr_ebno(k, s), B.thr_ebno_n(k, s));
    end
    lines{end+1} = sprintf('   %-30s %s || %s', names{k}, strjoin(cb, ' '), strjoin(ce, ' ')); %#ok<AGROW>
end
lines{end+1} = 'Harmed lost-branch episodes per speed band (harmed: no response does not restore the geometry):';
LB = struct('thr', {}, 'band', {}, 'n', {}, 'n_h', {}, 'harm', {}, 'rec_h', {}, 'rec_u', {});
for b = 1:nb
    fb = rec & bi == b & ~Rd.recovered;
    share = NaN;
    if any(fb), share = sum(fb & harmed & ismember(thr, lost)) / sum(fb); end
    for k = 1:numel(lost)
        m = rec & bi == b & strcmp(thr, lost{k});
        e = struct('thr', lost{k}, 'band', b, 'n', sum(m), 'n_h', sum(m & harmed), 'harm', NaN, 'rec_h', NaN, 'rec_u', NaN);
        if e.n > 0, e.harm = e.n_h / e.n; end
        if e.n_h > 0, e.rec_h = mean(double(Rd.recovered(m & harmed))); end
        if e.n > e.n_h, e.rec_u = mean(double(Rd.recovered(m & ~harmed))); end
        LB(end+1) = e; %#ok<AGROW>
        lines{end+1} = sprintf('   speed %-9s %-20s episodes %4d  harmed %4d (%5.1f%%)  recovered on harmed %5.1f%%, on unharmed %5.1f%%', ...
            bn{b}, lost{k}, e.n, e.n_h, 100 * e.harm, 100 * e.rec_h, 100 * e.rec_u); %#ok<AGROW>
    end
    lines{end+1} = sprintf('   speed %-9s failures of the DQN %4d, of them harmed lost-branch episodes %5.1f%%', bn{b}, sum(fb), 100 * share); %#ok<AGROW>
end
B.lost = LB;
end

function s = cell_txt(rate, n)
if n == 0, s = sprintf('%11s', '-'); else, s = sprintf('%5.1f (%3d)', rate, n); end
end

function R = columns(R, num, lgc)
% The fields of an episode set as columns (numeric num, logical lgc).
for f = num, R.(f{1}) = double(R.(f{1})(:)); end
for f = lgc, R.(f{1}) = logical(R.(f{1})(:)); end
end

function t = yn(c)
if c, t = 'yes'; else, t = 'no'; end
end
