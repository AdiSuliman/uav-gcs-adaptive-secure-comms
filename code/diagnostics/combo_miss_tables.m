function varargout = combo_miss_tables(cmd, varargin)
%COMBO_MISS_TABLES  R5, the combined-threat diagnostic: which class the monitor
%   reads on the threat-active frames of a combined threat, and which mechanism carries the frames DET
%   misses, from the per-frame facts alone, so it runs on synthetic frames. Descriptive: no number of
%   any profile changes and no threshold is chosen from it.
%   ct = combo_miss_tables('categories', cls, mp)
%       the category of every frame from the monitor's class index cls (0: not read):
%       1 a jammer component (a class DET counts for a non-level component), 2 the pair's level
%       component (path_loss or antenna_fault) read as its own class, 3 another level-family class,
%       4 none, 5 any other class. mp: J (1 x classes, the classes DET counts for the jammer
%       components), Lc (index of the pair's level-component class, 0 for a pair without one), fam
%       (1 x classes, the level family: path_loss, antenna_fault, airframe_shadowing), none_idx
%   [name, k] = combo_miss_tables('mechanism', mcnt, mp)
%       the category with the most missed frames (ties to the lowest category) and its name:
%       (a) path_loss read as a class but counted only with the drop alarm (det_frames.m), (b) another
%       level-family class outvoting the jammer, or the monitor reading none or another class
%   T = combo_miss_tables('tables', F, M, C)
%       F   per frame (columns): pair (index into M.pairs), s (Eb/N0 index), flight (cluster id: the
%           geometry at its Eb/N0, shared by the severities), age (cycles since the threat's first frame
%           read, det_frames.m), cls, dr (the drop alarm fired), hit (DET counts the frame, drop alarm
%           included), harmed (the flight's unmitigated link is not restored), on (the threat is on the air)
%       M   pairs, classes, pm (per pair: J, Lc, fam, none_idx, drop_used, pl_idx), fuse_N, ebno, det_h_read
%       C   B (bootstrap resamples), seed
%   lines = combo_miss_tables('lines', T, M, C)
switch cmd
    case 'categories', varargout{1} = categories(varargin{:});
    case 'mechanism',  [varargout{1}, varargout{2}] = mechanism(varargin{:});
    case 'tables',     varargout{1} = tables(varargin{:});
    case 'lines',      varargout{1} = table_lines(varargin{:});
    otherwise, error('combo_miss_tables: unknown command %s', cmd);
end
end

%% ===================== Categories and mechanism =====================
function ct = categories(cls, mp)
cls = cls(:);
ct = zeros(size(cls));
ok = cls >= 1;
c = cls(ok);
fam = mp.fam(:); J = mp.J(:);
v = 5 * ones(size(c));
v(fam(c)) = 3;
if mp.Lc > 0, v(c == mp.Lc) = 2; end
v(J(c)) = 1;
v(c == mp.none_idx) = 4;
ct(ok) = v;
end

function [name, k] = mechanism(mcnt, mp)
mcnt = mcnt(:)';
k = 0; name = 'no missed frame';
if sum(mcnt) == 0, return; end
[~, k] = max(mcnt);
switch k
    case 2
        if mp.drop_used
            name = '(a) the class path_loss is read but counts only with the drop alarm (the scoring)';
        else
            name = 'the pair''s level component is read as its own class and not counted';
        end
    case 3
        name = '(b) a level-family class other than the pair''s component outvotes the jammer';
    case 4
        name = 'the monitor reads none (neither (a) nor (b))';
    case 5
        name = 'the monitor reads another class (neither (a) nor (b))';
    otherwise
        name = 'a jammer component is read and the frame is still missed (check the extraction)';
end
end

%% ===================== Tables =====================
function T = tables(F, M, C)
for f = {'pair', 's', 'flight', 'age', 'cls'}, F.(f{1}) = double(F.(f{1})(:)); end
for f = {'dr', 'hit', 'harmed', 'on'}, F.(f{1}) = logical(F.(f{1})(:)); end
np = numel(M.pairs);
edge = [3, max(4, M.fuse_N)];
T = struct('pairs', {M.pairs}, 'edge', edge, 'p', []);
P = struct('pair', {}, 'n_on', {}, 'n_flights', {}, 'det', {}, 'det_h', {}, 'det_u', {}, 'n_h', {}, 'cnt', {}, 'mcnt', {}, ...
    'pl_class', {}, 'drop', {}, 'both', {}, 'det_cf', {}, 'mech', {}, 'mech_k', {}, 'age', {}, 'ebno', {});
for p = 1:np
    mp = M.pm(p);
    m = F.pair == p & F.on;
    cls = F.cls(m); hit = F.hit(m); dr = F.dr(m); hm = F.harmed(m); s = F.s(m); fl = F.flight(m); age = F.age(m);
    ct = categories(cls, mp);
    miss = ~hit;
    P(p).pair = M.pairs{p};
    P(p).n_on = sum(m); P(p).n_flights = numel(unique(fl));
    P(p).det = ci(hit, true(size(hit)), fl, C.B, C.seed + 10 * p + 1);
    P(p).det_h = ci(hit, hm, fl, C.B, C.seed + 10 * p + 2);
    P(p).det_u = ci(hit, ~hm, fl, C.B, C.seed + 10 * p + 3);
    P(p).n_h = sum(hm);
    P(p).cnt = counts(ct, true(size(ct)));
    P(p).mcnt = counts(ct, miss);
    has_pl = mp.pl_idx > 0;
    P(p).pl_class = NaN; P(p).drop = NaN; P(p).both = NaN; P(p).det_cf = NaN;
    if has_pl && any(m)
        isp = cls == mp.pl_idx;
        P(p).pl_class = mean(double(isp)); P(p).drop = mean(double(dr)); P(p).both = mean(double(isp & dr));
        P(p).det_cf = mean(double(hit | isp));
    end
    [P(p).mech, P(p).mech_k] = mechanism(P(p).mcnt, mp);
    band = 1 + (age >= edge(1)) + (age >= edge(2));
    P(p).age = repmat(slice(hit, ct, false(size(hit))), 1, 3);
    for b = 1:3, P(p).age(b) = slice(hit, ct, band == b); end
    nS = numel(M.ebno);
    P(p).ebno = repmat(slice(hit, ct, false(size(hit))), 1, nS);
    for e = 1:nS, P(p).ebno(e) = slice(hit, ct, s == e); end
end
T.p = P;
end

function r = ci(x, m, fl, B, seed)
r = struct('n', sum(m), 'rate', NaN, 'lo', NaN, 'hi', NaN, 'ncl', 0);
if ~any(m), return; end
[r.rate, r.lo, r.hi] = boot_cluster(double(x(m)), ones(sum(m), 1), fl(m), B, seed);
r.ncl = numel(unique(fl(m)));
end

function c = counts(ct, m)
c = arrayfun(@(k) sum(ct(m) == k), 1:5);
end

function t = slice(hit, ct, m)
t = struct('n', sum(m), 'det', NaN, 'n_miss', sum(m & ~hit), 'mcnt', counts(ct(m), ~hit(m)));
if t.n > 0, t.det = mean(double(hit(m))); end
end

%% ===================== Lines =====================
function L = table_lines(T, M, C)
L = {};
L{end+1} = sprintf(['As read: the combined threats'' DET_h is %.1f%% (profile 1, edge_map.m on the test pools). This reading explains ' ...
    'it on the validation pools at no_action; the number stands, nothing is re-scored.'], M.det_h_read);
L{end+1} = ['Categories of the monitor''s class on the threat-active frames: 1 a jammer component, 2 the pair''s level component ' ...
    'read as its own class, 3 another level-family class (path_loss, antenna_fault, airframe_shadowing), 4 none, 5 any other class. ' ...
    'DET counts a frame by the registered definition (det_frames.m): the class of a jammer component, an antenna_fault class for an ' ...
    'antenna_fault component, and path_loss only through the drop alarm.'];
L{end+1} = sprintf('Onset age bands (cycles since the threat''s first frame read): 0-%d, %d-%d, %d and later (the fusion window holds %d).', ...
    T.edge(1) - 1, T.edge(1), T.edge(2) - 1, T.edge(2), M.fuse_N);
L{end+1} = sprintf('Intervals: 95%% bootstrap over flights (%d resamples, boot_cluster.m).', C.B);
for p = 1:numel(T.p)
    P = T.p(p);
    L{end+1} = ''; %#ok<AGROW>
    L{end+1} = sprintf('--- %s: %d threat-active frames of %d flights, %d of them on harmed flights', P.pair, P.n_on, P.n_flights, P.n_h); %#ok<AGROW>
    L{end+1} = sprintf('   DET %s | DET_h (harmed flights) %s | DET_u (unharmed) %s', ci_txt(P.det), ci_txt(P.det_h), ci_txt(P.det_u)); %#ok<AGROW>
    L{end+1} = sprintf('   class of the threat-active frames, share %%: %s', cat_txt(P.cnt, P.n_on)); %#ok<AGROW>
    L{end+1} = sprintf('   class of the missed frames (%d), share %%: %s', sum(P.mcnt), cat_txt(P.mcnt, sum(P.mcnt))); %#ok<AGROW>
    if ~isnan(P.pl_class)
        L{end+1} = sprintf(['   path_loss: read as the class on %.1f%% of the frames, drop alarm on %.1f%%, both %.1f%%; DET if the class ' ...
            'counted without the drop alarm (not the registered definition) %.1f%%'], 100 * P.pl_class, 100 * P.drop, ...
            100 * P.both, 100 * P.det_cf); %#ok<AGROW>
    end
    L{end+1} = sprintf('   largest share of the missed frames: %s', P.mech); %#ok<AGROW>
    ab = {sprintf('0-%d', T.edge(1) - 1), sprintf('%d-%d', T.edge(1), T.edge(2) - 1), sprintf('%d+', T.edge(2))};
    for b = 1:3
        L{end+1} = sprintf('   onset age %-7s frames %5d  DET %5.1f%%  missed %4d by category: %s', ab{b}, P.age(b).n, ...
            100 * P.age(b).det, P.age(b).n_miss, cat_txt(P.age(b).mcnt, P.age(b).n_miss)); %#ok<AGROW>
    end
    for e = 1:numel(P.ebno)
        L{end+1} = sprintf('   Eb/N0 %5g dB   frames %5d  DET %5.1f%%  missed %4d by category: %s', M.ebno(e), P.ebno(e).n, ...
            100 * P.ebno(e).det, P.ebno(e).n_miss, cat_txt(P.ebno(e).mcnt, P.ebno(e).n_miss)); %#ok<AGROW>
    end
end
end

function s = ci_txt(r)
if r.n == 0, s = '-'; return; end
s = sprintf('%5.1f%% [%5.1f, %5.1f] (%d frames, %d flights)', 100 * r.rate, 100 * r.lo, 100 * r.hi, r.n, r.ncl);
end

function s = cat_txt(c, n)
if n == 0, s = '-'; return; end
nm = {'jammer', 'level comp.', 'other level', 'none', 'other'};
s = strjoin(arrayfun(@(k) sprintf('%s %.1f', nm{k}, 100 * c(k) / n), 1:5, 'UniformOutput', false), ' | ');
end
