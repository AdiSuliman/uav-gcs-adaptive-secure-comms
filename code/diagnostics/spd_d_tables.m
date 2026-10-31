function varargout = spd_d_tables(cmd, varargin)
%SPD_D_TABLES  The tables and the routing table of SPD-D, from per-episode
%   facts alone, so they run on synthetic episodes. Descriptive: nothing here selects a run, a seed
%   or a threshold; the routing is advisory.
%   C = spd_d_tables('config', speed_range)
%       speed bands: four equal bands of the speed range (KPI 7's, evaluate_policies.m); bank bands
%       0-20, 20-40 and 40 deg and above (edge_map.m); hi_speed 112 km/h; a contrast counts from 3
%       points; a restoring set is small at 3 configurations or fewer; a branch needs a share of 50%;
%       cov_registered false: the coverage branch's second clause (a share of T5's failures) has no
%       registered share, so the branch is printed and never raised
%   [sb, bb] = spd_d_tables('bands', speed, bank, C)    band of every flight (0: not finite)
%   [sc, bud] = spd_d_tables('families', names)         configurations with a spatial/channel part
%                                                       (channel_switch, freq_diversity,
%                                                       spatial_diversity) and with a link-budget part
%                                                       (rate_reduce, power_control, fec_interleave)
%   [nR, r_sc, r_only] = spd_d_tables('restoring', ok, sc, bud)
%       ok  configurations x episodes, true where the configuration restores BER and packet loss
%       (link_env.m tables); nR the size of the restoring set R, r_sc R holds a spatial/channel
%       configuration, r_only R is not empty and holds link-budget configurations alone
%   T = spd_d_tables('tables', E, CL, C)
%       E   per episode (single threats on the air and recoverable are the rows with rec true):
%           thr (cellstr), split, geom (cluster: the flight, unique over the splits), s, speed [km/h],
%           bank [deg], rec, harmed (no response does not restore it), recovered (the DQN), nR, r_sc,
%           r_only, cfg_end (configuration index the DQN ends on), shadow_fl (a shadowing group flight),
%           na (index of no_action), actions (names), sc_cfg (per configuration: spatial/channel part)
%       CL  clean-link flights at working Eb/N0 points: speed, bank, fer, geom
%   lines = spd_d_tables('lines', T, C)
%       T1 recovered per speed band x bank band; T2 the speed contrasts inside bank 0-20 and 20-40 deg
%       and the bank contrast from hi_speed up; T3 size and families of R; T4 harmed share and recovered
%       per speed band for the lost-branch classes and benign_interference; T5 where the DQN ends on its
%       failures from hi_speed up; then the routing table
switch cmd
    case 'config',    varargout{1} = config(varargin{:});
    case 'bands',     [varargout{1}, varargout{2}] = bands(varargin{:});
    case 'families',  [varargout{1}, varargout{2}] = families(varargin{:});
    case 'restoring', [varargout{1}, varargout{2}, varargout{3}] = restoring(varargin{:});
    case 'tables',    varargout{1} = tables(varargin{:});
    case 'lines',     varargout{1} = table_lines(varargin{:});
    otherwise, error('spd_d_tables: unknown command %s', cmd);
end
end

%% ===================== Configuration, bands, families =====================
function C = config(speed_range)
C = struct('speed_edges', linspace(speed_range(1), speed_range(2), 5), 'bank_edges', [0 20 40 58], ...
    'hi_speed', 112, 'contrast', 3, 'nr_small', 3, 'share', 0.5, 'lost', {{'antenna_fault', 'airframe_shadowing'}}, ...
    'benign', 'benign_interference', 'cov_registered', false, 'B', 2000, 'seed', 11600);
end

function [sb, bb] = bands(speed, bank, C)
sb = band_of(speed, C.speed_edges); bb = band_of(bank, C.bank_edges);
end

function b = band_of(x, e)
% Band 1..numel(e) - 1 of every value (the last band has no upper edge); 0 where not finite.
x = x(:); b = ones(size(x));
for k = 2:numel(e) - 1, b = b + (x >= e(k)); end
b(~isfinite(x)) = 0;
end

function [sc, bud] = families(names)
names = cellstr(string(names(:)'));
sc = contains(names, 'channel_switch') | contains(names, 'freq_diversity') | contains(names, 'spatial_diversity');
bud = contains(names, 'rate_reduce') | contains(names, 'power_control') | contains(names, 'fec_interleave');
sc = sc(:); bud = bud(:);
end

function [nR, r_sc, r_only] = restoring(ok, sc, bud)
ok = logical(ok); sc = logical(sc(:)); bud = logical(bud(:));
nR = sum(ok, 1);
r_sc = any(ok & sc, 1);
only = bud & ~sc;
r_only = nR > 0 & ~any(ok & ~only, 1);
end

%% ===================== Tables =====================
function T = tables(E, CL, C)
for f = {'split', 'geom', 's', 'speed', 'bank', 'nR', 'cfg_end'}, E.(f{1}) = double(E.(f{1})(:)); end
for f = {'rec', 'harmed', 'recovered', 'r_sc', 'r_only', 'shadow_fl'}, E.(f{1}) = logical(E.(f{1})(:)); end
E.thr = E.thr(:); E.sc_cfg = logical(E.sc_cfg(:));
[sb, bb] = bands(E.speed, E.bank, C);
nsb = numel(C.speed_edges) - 1; nbb = numel(C.bank_edges) - 1;
lost = ismember(E.thr, C.lost);
G = struct('name', {}, 'key', {}, 'm', {});
G(end+1) = struct('name', 'all single threats', 'key', 'all', 'm', E.rec);
G(end+1) = struct('name', 'other single threats (not antenna_fault or airframe_shadowing; shadowing flights left out)', ...
    'key', 'other', 'm', E.rec & ~lost & ~E.shadow_fl);
G(end+1) = struct('name', 'antenna_fault + airframe_shadowing', 'key', 'lost', 'm', E.rec & lost);
G(end+1) = struct('name', C.benign, 'key', 'benign', 'm', E.rec & strcmp(E.thr, C.benign));
T = struct('G', G, 'nsb', nsb, 'nbb', nbb, 'n_episodes', numel(E.rec), 'n_rec', sum(E.rec));

% T1: recovered per speed band x bank band, per group; and per split for all threats
T.t1 = cell(1, numel(G));
for gi = 1:numel(G)
    c = repmat(rate_ci(E.recovered, false(size(E.rec)), E.geom, C.B, 1), nsb, nbb);
    for i = 1:nsb
        for j = 1:nbb
            c(i, j) = rate_ci(E.recovered, G(gi).m & sb == i & bb == j, E.geom, C.B, C.seed + 1000 + 100 * gi + 10 * i + j);
        end
    end
    T.t1{gi} = c;
end
T.t1s = struct('split', {}, 'n', {}, 'rate', {});
for sp = [1 2]
    nn = zeros(nsb, nbb); rr = nan(nsb, nbb);
    for i = 1:nsb
        for j = 1:nbb
            mm = G(1).m & E.split == sp & sb == i & bb == j;
            nn(i, j) = sum(mm);
            if nn(i, j) > 0, rr(i, j) = mean(double(E.recovered(mm))); end
        end
    end
    T.t1s(end+1) = struct('split', sp, 'n', nn, 'rate', rr);
end

% T2: contrasts, the lower speed bands minus the top band inside a bank band, and the bank below 40 deg minus
% 40 deg and above from hi_speed up; for all threats and for the other single threats
T.t2 = struct('name', {}, 'grp', {}, 'd', {}, 'lo', {}, 'hi', {}, 'n', {}, 'point3', {}, 'meets3', {});
for gi = [1 2]
    for j = 1:2
        a = G(gi).m & bb == j & sb >= 1 & sb < nsb; b = G(gi).m & bb == j & sb == nsb;
        nm = sprintf('speed, lower bands minus top band, bank %g-%g deg', C.bank_edges(j), C.bank_edges(j + 1));
        T.t2(end+1) = contrast_entry(nm, G(gi).key, E, a, b, C, C.seed + 2000 + 100 * gi + j);
    end
    a = G(gi).m & E.speed >= C.hi_speed & bb >= 1 & bb < nbb; b = G(gi).m & E.speed >= C.hi_speed & bb == nbb;
    nm = sprintf('bank, below %g deg minus %g deg and above, speed >= %g km/h', C.bank_edges(nbb), C.bank_edges(nbb), C.hi_speed);
    T.t2(end+1) = contrast_entry(nm, G(gi).key, E, a, b, C, C.seed + 2000 + 100 * gi + 3);
end

% T3: the restoring set R by speed band x bank band, policy free; all recoverable episodes and the harmed ones
T.t3 = {restoring_grid(E, E.rec, sb, bb, C), restoring_grid(E, E.rec & E.harmed, sb, bb, C)};

% T4: harmed share and recovered per speed band, lost-branch classes and benign_interference
names = [C.lost(:); {C.benign}];
T.t4 = struct('name', {}, 'n', {}, 'harm', {}, 'rec', {}, 'rec_h', {}, 'rec_u', {}, 'n_h', {});
for k = 1:numel(names)
    nn = zeros(1, nsb); hs = nan(1, nsb); rh = nan(1, nsb); ru = nan(1, nsb); nh = zeros(1, nsb);
    rc = repmat(rate_ci(E.recovered, false(size(E.rec)), E.geom, C.B, 1), 1, nsb);
    for i = 1:nsb
        m = E.rec & strcmp(E.thr, names{k}) & sb == i;
        nn(i) = sum(m); nh(i) = sum(m & E.harmed);
        if nn(i) > 0, hs(i) = mean(double(E.harmed(m))); end
        if nh(i) > 0, rh(i) = mean(double(E.recovered(m & E.harmed))); end
        if nn(i) > nh(i), ru(i) = mean(double(E.recovered(m & ~E.harmed))); end
        rc(i) = rate_ci(E.recovered, m, E.geom, C.B, C.seed + 4000 + 100 * k + i);
    end
    T.t4(end+1) = struct('name', names{k}, 'n', nn, 'harm', hs, 'rec', rc, 'rec_h', rh, 'rec_u', ru, 'n_h', nh);
end

% T5: where the DQN ends on its failures from hi_speed up
ce = E.cfg_end; ce(~isfinite(ce) | ce < 1) = E.na;
endsc = E.sc_cfg(ce);
T.t5 = struct('name', {}, 'n', {}, 'end_na', {}, 'end_sc', {}, 'end_bud', {}, 'top', {}, 'r_only', {}, 'r_small', {});
for gi = 1:numel(G)
    f = G(gi).m & ~E.recovered & E.speed >= C.hi_speed;
    n = sum(f); cf = ce(f);
    isna = cf == E.na; issc = endsc(f);
    T.t5(end+1) = struct('name', G(gi).name, 'n', n, 'end_na', sum(isna), 'end_sc', sum(issc & ~isna), ...
        'end_bud', sum(~issc & ~isna), 'top', top_names(E.actions(cf), 5), ...
        'r_only', rate_of(E.r_only(f)), 'r_small', rate_of(E.nR(f) <= C.nr_small));
end

% Routing
T.cl = struct('d', NaN, 'lo', NaN, 'hi', NaN, 'n', [0 0 0 0]);
if ~isempty(CL) && isfield(CL, 'fer') && ~isempty(CL.fer)
    [csb, cbb] = bands(CL.speed, CL.bank, C);
    a = csb == nsb & cbb == 1; b = csb >= 1 & csb < nsb & cbb == 1;
    [d, lo, hi, n] = cluster_contrast(CL.fer, a, b, CL.geom, C.B, C.seed + 9000);
    T.cl = struct('d', d, 'lo', lo, 'hi', hi, 'n', n);
end
T.route = route(E, G, sb, endsc, T, C);
end

function r = rate_ci(x, m, cl, B, seed)
% Rate of the episodes of mask m with a cluster bootstrap interval (boot_cluster.m).
r = struct('n', sum(m), 'rate', NaN, 'lo', NaN, 'hi', NaN, 'ncl', 0);
if ~any(m), return; end
[r.rate, r.lo, r.hi] = boot_cluster(double(x(m)), ones(sum(m), 1), cl(m), B, seed);
r.ncl = numel(unique(cl(m)));
end

function c = contrast_entry(name, grp, E, a, b, C, seed)
[d, lo, hi, n] = cluster_contrast(double(E.recovered), a, b, E.geom, C.B, seed);
c = struct('name', name, 'grp', grp, 'd', d, 'lo', lo, 'hi', hi, 'n', n, ...
    'point3', d >= C.contrast / 100, 'meets3', d >= C.contrast / 100 && lo > 0);
end

function t = restoring_grid(E, m, sb, bb, C)
nsb = numel(C.speed_edges) - 1; nbb = numel(C.bank_edges) - 1;
t = struct('n', zeros(nsb, nbb), 'mean_nR', nan(nsb, nbb), 'small', nan(nsb, nbb), 'only', nan(nsb, nbb), 'sc', nan(nsb, nbb));
for i = 1:nsb
    for j = 1:nbb
        mm = m & sb == i & bb == j;
        t.n(i, j) = sum(mm);
        if t.n(i, j) == 0, continue; end
        t.mean_nR(i, j) = mean(E.nR(mm));
        t.small(i, j) = mean(double(E.nR(mm) <= C.nr_small));
        t.only(i, j) = mean(double(E.r_only(mm)));
        t.sc(i, j) = mean(double(E.r_sc(mm)));
    end
end
end

function r = rate_of(x)
if isempty(x), r = NaN; else, r = mean(double(x)); end
end

function s = top_names(names, k)
if isempty(names), s = '-'; return; end
[u, ~, j] = unique(names(:));
c = accumarray(j, 1);
[c, o] = sort(c, 'descend'); u = u(o);
k = min(k, numel(u));
s = strjoin(arrayfun(@(i) sprintf('%s %d', u{i}, c(i)), 1:k, 'UniformOutput', false), ', ');
end

%% ===================== Routing =====================
function R = route(E, G, sb, endsc, T, C)
nsb = numel(C.speed_edges) - 1;
m4 = G(1).m & sb == nsb; f4 = m4 & ~E.recovered;
lost = ismember(E.thr, C.lost);
R = struct('n_top', sum(m4), 'n_fail', sum(f4), 'deficit', NaN, 'defined', sum(f4) > 0);
R.policy = struct('share', NaN, 'met', false);
R.coverage = struct('small', NaN, 'only_sc', NaN, 'nested', NaN, 'n_small', 0, 'n_t5', 0, 'read', false, ...
    'registered', C.cov_registered, 'met', false);
R.bank_only = struct('speed_meets', false, 'bank_point3', false, 'met', false);
R.doppler = struct('d', NaN, 'lo', NaN, 'hi', NaN, 'point3', false, 'fer_d', T.cl.d, 'fer_lo', T.cl.lo, 'fer_up', T.cl.d > 0, 'met', false);
if R.n_top > 0, R.deficit = 1 - mean(double(E.recovered(m4))); end
% bank only: no speed contrast of 3 points with an interval excluding 0 inside bank < 40 deg, and the bank contrast 3 points
ia = find(strcmp({T.t2.grp}, 'all')); io = find(strcmp({T.t2.grp}, 'other'));
R.bank_only.speed_meets = any([T.t2(ia(1:2)).meets3]);
R.bank_only.bank_point3 = T.t2(ia(3)).point3;
R.bank_only.met = ~R.bank_only.speed_meets && R.bank_only.bank_point3;
% Doppler: the top band 3 points lower inside bank 0-20 deg on the other single threats, the clean link's FER rising with speed
R.doppler.d = T.t2(io(1)).d; R.doppler.lo = T.t2(io(1)).lo; R.doppler.hi = T.t2(io(1)).hi; R.doppler.point3 = T.t2(io(1)).point3;
R.doppler.met = R.doppler.point3 && R.doppler.fer_up;
if R.defined
    R.policy.share = sum(f4 & E.harmed & lost) / sum(f4);
    R.policy.met = R.policy.share >= C.share;
    % coverage: |R| <= 3 on a share of the top-band failures, and on a share of T5's failures (hi_speed up) R holds
    % power/rate/FEC alone while the DQN ends on a spatial/channel configuration; nested: that second share among the
    % top-band failures with |R| <= 3, read beside it; the branch is raised only when the reading is registered
    sm = f4 & E.nR <= C.nr_small;
    f5 = G(1).m & ~E.recovered & E.speed >= C.hi_speed;
    R.coverage.n_small = sum(sm);
    R.coverage.small = sum(sm) / sum(f4);
    R.coverage.n_t5 = sum(f5);
    if any(f5), R.coverage.only_sc = sum(f5 & E.r_only & endsc) / sum(f5); end
    if any(sm), R.coverage.nested = sum(sm & E.r_only & endsc) / sum(sm); end
    R.coverage.read = R.coverage.small >= C.share && isfinite(R.coverage.only_sc) && R.coverage.only_sc >= C.share;
    R.coverage.met = R.coverage.read && C.cov_registered;
end
% the policy branch first, then the others in the order of the registered table
order = {'policy', 'bank_only', 'doppler', 'coverage'};
R.met = order(cellfun(@(k) R.(k).met, order));
if isempty(R.met), R.first = 'none'; else, R.first = R.met{1}; end
end

%% ===================== Lines =====================
function L = table_lines(T, C)
L = {};
nsb = T.nsb; nbb = T.nbb;
L{end+1} = sprintf(['Single-threat episodes on the air: %d (recoverable %d). Speed bands %s km/h; bank bands %s deg; ' ...
    'recovered = the deployed DQN restores BER and packet loss for 5 cycles (KPI 4), among the recoverable episodes.'], ...
    T.n_episodes, T.n_rec, strjoin(arrayfun(@(i) speed_name(C, i), 1:nsb, 'UniformOutput', false), ', '), ...
    strjoin(arrayfun(@(j) bank_name(C, j), 1:nbb, 'UniformOutput', false), ', '));
L{end+1} = '';
for gi = 1:numel(T.G)
    L{end+1} = sprintf('T1 %s: DQN recovered %% [95%% cluster interval] episodes/flights', T.G(gi).name); %#ok<AGROW>
    L{end+1} = sprintf('   %-12s %s', 'speed km/h', strjoin(arrayfun(@(j) sprintf('%-30s', ['bank ' bank_name(C, j) ' deg']), ...
        1:nbb, 'UniformOutput', false), ' ')); %#ok<AGROW>
    for i = 1:nsb
        L{end+1} = sprintf('   %-12s %s', speed_name(C, i), strjoin(arrayfun(@(j) sprintf('%-30s', fmt_ci(T.t1{gi}(i, j))), ...
            1:nbb, 'UniformOutput', false), ' ')); %#ok<AGROW>
    end
end
for k = 1:numel(T.t1s)
    sp = T.t1s(k).split;
    tag = 'train split (in sample for the DQN)'; if sp == 2, tag = 'validation split (used for selection)'; end
    L{end+1} = sprintf('T1 all single threats, %s: recovered %% (episodes)', tag); %#ok<AGROW>
    for i = 1:nsb
        L{end+1} = sprintf('   %-12s %s', speed_name(C, i), strjoin(arrayfun(@(j) ...
            sprintf('%-14s', cell_txt(T.t1s(k).rate(i, j), T.t1s(k).n(i, j))), 1:nbb, 'UniformOutput', false), ' ')); %#ok<AGROW>
    end
end
L{end+1} = '';
L{end+1} = sprintf(['T2 contrasts in points of recovered, 95%% cluster interval; a contrast counts when it is %g points or more ' ...
    'with an interval above 0'], C.contrast);
for k = 1:numel(T.t2)
    c = T.t2(k);
    L{end+1} = sprintf('   [%-5s] %-62s %+6.1f [%+6.1f,%+6.1f]  episodes %d / %d, flights %d / %d  3 points: %s, with the interval: %s', ...
        c.grp, c.name, 100 * c.d, 100 * c.lo, 100 * c.hi, c.n(1), c.n(2), c.n(3), c.n(4), yn(c.point3), yn(c.meets3)); %#ok<AGROW>
end
L{end+1} = '';
blk = {'all recoverable episodes', 'harmed recoverable episodes (no_action is not in R)'};
for b = 1:2
    L{end+1} = sprintf('T3 the restoring set R (configurations restoring BER and packet loss), %s', blk{b}); %#ok<AGROW>
    for i = 1:nsb
        for j = 1:nbb
            t = T.t3{b};
            L{end+1} = sprintf('   speed %-10s bank %-8s n %4d  mean |R| %5.1f  |R| <= %d %5.1f%%  R power/rate/FEC only %5.1f%%  R has a spatial/channel part %5.1f%%', ...
                speed_name(C, i), bank_name(C, j), t.n(i, j), t.mean_nR(i, j), C.nr_small, 100 * t.small(i, j), ...
                100 * t.only(i, j), 100 * t.sc(i, j)); %#ok<AGROW>
        end
    end
end
L{end+1} = '';
L{end+1} = 'T4 per speed band: episodes, harmed share, recovered [95% cluster interval] episodes/flights, recovered on harmed, on unharmed episodes';
for k = 1:numel(T.t4)
    t = T.t4(k);
    L{end+1} = sprintf('   %s', t.name); %#ok<AGROW>
    for i = 1:nsb
        L{end+1} = sprintf('     speed %-10s n %4d  harmed %5.1f%% (%d)  recovered %-30s  on harmed %5.1f%%  on unharmed %5.1f%%', ...
            speed_name(C, i), t.n(i), 100 * t.harm(i), t.n_h(i), fmt_ci(t.rec(i)), 100 * t.rec_h(i), 100 * t.rec_u(i)); %#ok<AGROW>
    end
end
L{end+1} = '';
L{end+1} = sprintf('T5 failures of the DQN from %g km/h up: the configuration it ends on, and R of those episodes', C.hi_speed);
for k = 1:numel(T.t5)
    t = T.t5(k);
    L{end+1} = sprintf('   %-60s failures %3d | ends on no_action %d, spatial/channel %d, power/rate/FEC alone %d | most frequent: %s | R power/rate/FEC only %5.1f%%, |R| <= %d %5.1f%%', ...
        t.name, t.n, t.end_na, t.end_sc, t.end_bud, t.top, 100 * t.r_only, C.nr_small, 100 * t.r_small); %#ok<AGROW>
end
L{end+1} = '';
R = T.route;
L{end+1} = 'Routing table (fixed in D116 item 7; advisory: validation was used for selection, the profile has 3 antennas, so it is indicative for profile 3):';
L{end+1} = sprintf('   top speed band %s km/h: %d recoverable episodes, deficit %5.1f%%, %d failures', speed_name(C, nsb), R.n_top, 100 * R.deficit, R.n_fail);
L{end+1} = sprintf('   policy      : %5.1f%% of the top-band failures are harmed lost-branch episodes (needs %g%%) -> %s', ...
    100 * R.policy.share, 100 * C.share, met_txt(R.policy.met));
L{end+1} = sprintf('   bank only   : a speed contrast of %g points with an interval above 0 inside bank < %g deg: %s; the bank contrast at >= %g km/h is %g points or more: %s -> %s', ...
    C.contrast, C.bank_edges(nbb), yn(R.bank_only.speed_meets), C.hi_speed, C.contrast, yn(R.bank_only.bank_point3), met_txt(R.bank_only.met));
L{end+1} = sprintf(['   Doppler     : other single threats, lower bands minus top band inside bank 0-20 deg %+5.1f points [%+5.1f,%+5.1f] ' ...
    '(%g points: %s); clean-link FER of the top band minus the lower bands there %+8.5f [lower bound %+8.5f] (rising: %s) -> %s'], ...
    100 * R.doppler.d, 100 * R.doppler.lo, 100 * R.doppler.hi, C.contrast, yn(R.doppler.point3), R.doppler.fer_d, ...
    R.doppler.fer_lo, yn(R.doppler.fer_up), met_txt(R.doppler.met));
cov_head = '   coverage    : '; cov_res = met_txt(R.coverage.met);
if ~R.coverage.registered
    cov_head = '   coverage (reading not registered): ';
    if R.coverage.read, cov_res = 'met by the reading, not raised'; end
end
L{end+1} = sprintf(['%s|R| <= %d on %5.1f%% of the top-band failures (needs %g%%); of the %d failures from %g km/h up (T5), ' ...
    'R holds power/rate/FEC alone and the DQN ends on a spatial/channel configuration in %5.1f%% (needs %g%%); among the %d top-band ' ...
    'failures with |R| <= %d the same share is %5.1f%% (read beside, not used) -> %s'], ...
    cov_head, C.nr_small, 100 * R.coverage.small, 100 * C.share, R.coverage.n_t5, C.hi_speed, 100 * R.coverage.only_sc, 100 * C.share, ...
    R.coverage.n_small, C.nr_small, 100 * R.coverage.nested, cov_res);
if R.defined
    if isempty(R.met), mt = 'none of the four branches is met'; else, mt = strjoin(R.met, ', '); end
    L{end+1} = sprintf('   routing: first %s; branches met: %s', R.first, mt);
    if R.coverage.read && ~R.coverage.registered
        L{end+1} = ['   coverage is met by the reading but not raised: D116 item 7 registers no share for its second clause, so ' ...
            'it does not switch C-LHS (D117 point 3)'];
    end
else
    L{end+1} = '   routing: the DQN has no failure in the top band, no branch applies';
end
end

function s = fmt_ci(r)
if r.n == 0, s = '-'; return; end
s = sprintf('%5.1f [%5.1f,%5.1f] %3d/%2d', 100 * r.rate, 100 * r.lo, 100 * r.hi, r.n, r.ncl);
end

function s = cell_txt(rate, n)
if n == 0, s = '-'; else, s = sprintf('%5.1f (%d)', 100 * rate, n); end
end

function s = speed_name(C, i)
s = sprintf('%.0f-%.0f', C.speed_edges(i), C.speed_edges(i + 1));
end

function s = bank_name(C, j)
if j == numel(C.bank_edges) - 1, s = sprintf('%g+', C.bank_edges(j)); else, s = sprintf('%g-%g', C.bank_edges(j), C.bank_edges(j + 1)); end
end

function s = yn(c)
if c, s = 'yes'; else, s = 'no'; end
end

function s = met_txt(c)
if c, s = 'MET'; else, s = 'not met'; end
end
