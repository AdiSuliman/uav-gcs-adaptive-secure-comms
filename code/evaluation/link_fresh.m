function out = link_fresh(cmd, varargin)
%LINK_FRESH  The clean-link criterion LINK on P1R's fresh clean test set, read
%   once after P1R's C2e (docs/p1r_protocol.md section 11): the clean no_action packet loss
%   per Eb/N0 of data/clean_fresh_pools.mat, flight by flight as edge_map.m reads the
%   clean-link pools, with edge_verdict.m's rate rule against 5.7%; beside it, reported
%   only, the verdict at 1.4% on the same interval and the operating-point tag J (loss < 10%).
%   link_fresh('run', smoke)   in the P1R tree: reads data/clean_fresh_pools.mat, writes
%       results/link_fresh.{txt,mat} and the marker results/link_fresh_read.txt. It stops
%       before reading the pools unless C2e has read them for KPI 6 (the KPI 6 marker holds
%       "KPI 6 read" and the same file's SHA-256), and on a second reading (the marker holds
%       "LINK read"). smoke true: 400 resamples, as edge_map.m under SMOKE
%   link_fresh('check', smoke)   smoke cell A: the outputs against a recomputation from the
%       pools, the targets, the flights per Eb/N0, the labels, and a second run refused
%   F = link_fresh('flights', CT)   per-flight clean frames lost and flown at no_action
%   L = link_fresh('verdicts', F, ebno, B)   per Eb/N0 verdicts, the tag and the targets
out = [];
T = struct('link', 0.057, 'link_pre', 0.014, 'tag_j', 0.10);
FILE = 'data/clean_fresh_pools.mat'; K6 = 'results/kpi6_fresh_read_started.txt';
MK = 'results/link_fresh_read.txt';
LBL = 'D108, fresh set, first reading';
C2REF = ['C&C reliability: up to 1e-3 packet error loss rate (3GPP TR 36.777, Table 5.1-1), a service requirement ' ...
    'after the link layer; not modelled, not claimed'];
switch cmd
    case 'flights'
        out = flights_of(varargin{1});
    case 'verdicts'
        [F, ebno, B] = varargin{:};
        out = verdicts_of(F, ebno, B, T);
    case 'run'
        smoke = numel(varargin) >= 1 && varargin{1};
        out = run_reading(smoke, T, FILE, K6, MK, LBL, C2REF);
    case 'check'
        smoke = numel(varargin) >= 1 && varargin{1};
        check_outputs(smoke, T, FILE, MK, LBL);
    otherwise
        error('link_fresh:cmd', 'link_fresh: unknown command %s', cmd);
end
end

function LF = run_reading(smoke, T, FILE, K6, MK, LBL, C2REF)
if isfile(MK) && any(startsWith(lines_of(MK), 'LINK read'))
    error('link_fresh:read', '%s: LINK was read on the fresh clean test set; it is read once', MK);
end
if ~isfile(FILE), error('link_fresh:pools', 'link_fresh: %s absent', FILE); end
if ~isfile(K6) || ~any(startsWith(lines_of(K6), 'KPI 6 read'))
    error('link_fresh:order', ['link_fresh: %s holds no "KPI 6 read": LINK is read after P1R''s C2e has read the ' ...
        'fresh set for KPI 6'], K6);
end
sha = kpi6_fresh_marker('sha', FILE);
L6 = lines_of(K6);
if ~any(strcmp(L6, ['pools sha256 ' sha]))
    error('link_fresh:pools', 'link_fresh: %s is not the file C2e read for KPI 6 (%s)', FILE, K6);
end
C = load(FILE, 'CT'); CT = C.CT;
if ~(isfield(CT, 'set') && strcmp(CT.set, 'fresh') && isfield(CT, 'fams'))
    error('link_fresh:pools', 'link_fresh: %s is not the fresh clean test set (CT.set, CT.fams)', FILE);
end
did = L6(startsWith(L6, 'det_id '));
if isempty(did) || ~isfield(CT, 'det_id') || ~strcmp(did{end}, ['det_id ' CT.det_id])
    error('link_fresh:detector', 'link_fresh: the fresh pools'' det_id is not the one C2e read (%s)', K6);
end
if isfile(MK)
    append_line(MK, sprintf('restart %s', stamp()));
else
    d = fileparts(MK); if ~isempty(d) && ~isfolder(d), mkdir(d); end
    fid = fopen(MK, 'w'); assert(fid > 0, 'link_fresh:write', 'cannot write %s', MK);
    fprintf(fid, '%s\n', ['P1R: LINK reading of the fresh clean test set started (' LBL ')'], ['time ' stamp()], ...
        ['pools sha256 ' sha], ['det_id ' CT.det_id], sprintf('smoke %d', smoke));
    fclose(fid);
end
B = 4000; if smoke, B = 400; end
p0 = load('params.mat').params;
F = flights_of(CT);
LF = verdicts_of(F, CT.ebno, B, T);
LF.km = link_distance_km(CT.ebno, p0);
LF.F = F; LF.sha = sha; LF.det_id = CT.det_id; LF.fams = CT.fams; LF.block = clean_set_layout('fresh', smoke);
LF.n_geom = CT.n_geom; LF.B = B; LF.smoke = smoke; LF.label = LBL; LF.c2_reference = C2REF; LF.created = datestr(now);
r = {sprintf('=== P1R: LINK on the fresh clean test set (%s) ===', LBL)};
r{end+1} = sprintf(['Generated: %s | %s, families %d-%d of block %d, %d geometries per Eb/N0, sha256 %s (the file C2e ' ...
    'read for KPI 6, %s) | receiver as built (r1) | B = %d'], LF.created, 'data/clean_fresh_pools.mat', min(CT.fams), ...
    max(CT.fams), LF.block, CT.n_geom, sha, K6, B);
r{end+1} = sprintf(['Clean packet loss at no_action per Eb/N0, every frame of every fresh flight, read as edge_map.m reads ' ...
    'the clean-link pools (edge_verdict.m: bootstrap over flights and Clopper-Pearson on the effective sample size, ' ...
    'COMMITTED needs >= %d flights): %% [95%% interval] flights | LINK <= %g%% | registered before D108, LINK <= %g%% ' ...
    '(reported only) | tag (J: loss < %g%%, M otherwise; descriptive)'], LF.link(1).n_min, 100 * T.link, ...
    100 * T.link_pre, 100 * T.tag_j);
for s = 1:numel(CT.ebno)
    V = LF.link(s);
    r{end+1} = sprintf('  %4g dB (%5.2f km)  %6.2f [%6.2f, %6.2f] %4d | %s | %s | %s', CT.ebno(s), LF.km(s), 100 * V.value, ...
        100 * V.lo, 100 * V.hi, V.n, vsym(V.verdict), vsym(LF.link_pre(s).verdict), LF.tag{s}); %#ok<AGROW>
end
r{end+1} = [C2REF '.'];
r{end+1} = ['Profile 1''s EDGE and its LINK reading on its test pools stay as reported; this is P1R''s only LINK ' ...
    'reading, on flights no step had read for LINK.'];
if smoke, r{end+1} = 'SMOKE: a reduced chain check, not a result.'; end
fid = fopen('results/link_fresh.txt', 'w'); assert(fid > 0, 'link_fresh:write', 'cannot write results/link_fresh.txt');
fprintf(fid, '%s\n', r{:}); fclose(fid);
fprintf('%s\n', r{:});
save('results/link_fresh.mat', 'LF');
append_line(MK, sprintf('LINK read %s', stamp()));
end

function check_outputs(smoke, T, FILE, MK, LBL)
assert(isfile('results/link_fresh.mat') && isfile('results/link_fresh.txt') && isfile(MK), 'link_fresh:check', ...
    'link_fresh check: results/link_fresh.{mat,txt} or %s absent', MK);
S = load('results/link_fresh.mat', 'LF'); LF = S.LF;
C = load(FILE, 'CT'); CT = C.CT;
F = flights_of(CT);
assert(isequal(F, LF.F), 'link_fresh:check', 'link_fresh check: the flights differ from a recomputation');
R = verdicts_of(F, CT.ebno, LF.B, T);
assert(isequaln(R.link, LF.link) && isequaln(R.link_pre, LF.link_pre) && isequal(R.tag, LF.tag), 'link_fresh:check', ...
    'link_fresh check: the verdicts differ from a recomputation');
assert(isequal([LF.targets.link LF.targets.link_pre LF.targets.tag_j], [0.057 0.014 0.10]), 'link_fresh:check', ...
    'link_fresh check: targets');
assert(numel(LF.link) == numel(CT.ebno) && all([LF.link.n] == CT.n_geom), 'link_fresh:check', ...
    'link_fresh check: flights per Eb/N0');
B = 4000; if smoke, B = 400; end
assert(LF.smoke == smoke && LF.B == B, 'link_fresh:check', 'link_fresh check: smoke flag or resamples');
t = fileread('results/link_fresh.txt');
assert(contains(t, LBL) && contains(t, 'receiver as built (r1)') && contains(t, 'TR 36.777'), 'link_fresh:check', ...
    'link_fresh check: labels');
L = lines_of(MK);
assert(sum(startsWith(L, 'LINK read')) == 1 && any(strcmp(L, ['pools sha256 ' LF.sha])), 'link_fresh:check', ...
    'link_fresh check: marker');
try
    link_fresh('run', smoke); refused = false;
catch e
    refused = strcmp(e.identifier, 'link_fresh:read');
end
assert(refused, 'link_fresh:check', 'link_fresh check: a second reading was not refused');
fprintf('LINKFRESH CHECK PASS: %d Eb/N0 points, %d flights each, LINK %s, registered before D108 %s\n', numel(LF.link), ...
    CT.n_geom, strjoin(arrayfun(@(V) vsym(V.verdict), LF.link, 'UniformOutput', false), ''), ...
    strjoin(arrayfun(@(V) vsym(V.verdict), LF.link_pre, 'UniformOutput', false), ''));
end

function F = flights_of(CT)
% Per-flight frames lost and flown at no_action, as edge_map.m sums the clean-link pools.
na = find(strcmp(CT.actions, 'no_action'));
assert(isscalar(na), 'link_fresh:actions', 'link_fresh: no single no_action in CT.actions');
nS = numel(CT.ebno);
[s_, r_] = ndgrid(1:nS, 1:CT.n_geom); s_ = s_(:); r_ = r_(:); n = numel(s_);
F = struct('s', s_, 'r', r_, 'geo', 6e6 + 1000 * s_ + r_, 'link_k', zeros(n, 1), 'link_n', zeros(n, 1));
for s = 1:nS
    P = CT.pools{1, s, na};
    [~, r] = ismember(P.run, CT.runs);
    i = sub2ind([nS CT.n_geom], s + 0 * r, r);
    F.link_k = F.link_k + accumarray(i, double(P.fer), [n 1]);
    F.link_n = F.link_n + accumarray(i, 1, [n 1]);
end
end

function L = verdicts_of(F, ebno, B, T)
nS = numel(ebno);
VZ = edge_verdict([], [], [], 0.9, 'ge', false);
L = struct('ebno', ebno, 'targets', T, 'link', repmat(VZ, 1, nS), 'link_pre', repmat(VZ, 1, nS), 'tag', {repmat({'-'}, 1, nS)});
for s = 1:nS
    m = F.s == s;
    L.link(s) = edge_verdict(F.link_k(m), F.link_n(m), F.geo(m), T.link, 'le', false, B);
    L.link_pre(s) = edge_verdict(F.link_k(m), F.link_n(m), F.geo(m), T.link_pre, 'le', false, B);
    if L.link(s).n > 0 && L.link(s).value < T.tag_j, L.tag{s} = 'J'; elseif L.link(s).n > 0, L.tag{s} = 'M'; end
end
end

function L = lines_of(f)
L = strtrim(regexp(fileread(f), '\r?\n', 'split'));
L = L(~cellfun(@isempty, L));
end

function append_line(f, s)
fid = fopen(f, 'a');
assert(fid > 0, 'link_fresh:write', 'cannot write %s', f);
fprintf(fid, '%s\n', s); fclose(fid);
end

function s = stamp()
s = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end

function s = vsym(v)
s = 'U'; if v == 1, s = 'C'; elseif v == -1, s = 'N'; end
end
