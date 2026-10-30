function tests = test_speed_envelope
%TEST_SPEED_ENVELOPE  Unit tests of the speed readings on synthetic data, without pools and without
%   Simulink: speed_options.m (the profile.json switches), speed_inference.m (cluster bootstrap,
%   Hall & Miller bound, permutation test), speed_reading.m (the union reading and its criterion),
%   speed_edge_lines.m, speed_band_table.m, the edge161_n switch of build_policy_pools.m
%   (pool_layout.m, pool_geometries.m, the shadowing flights' selection at 161 km/h, the added
%   C1p work) and the insert-only wiring of build_policy_pools.m, evaluate_policies.m,
%   train_dqn.m and measure_all_kpis.m, whose outputs without the switches are those of the
%   parent commit.
%   Run from the repository root: results = runtests('code/tests/test_speed_envelope.m')
tests = functiontests(localfunctions);
end

function setupOnce(tc)
tc.TestData.root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(tc.TestData.root, 'code'));
setup_paths;
tc.TestData.cwd = pwd;
tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp); cd(tc.TestData.tmp);
end

function teardownOnce(tc)
cd(tc.TestData.cwd);
end

%% ---------- the switches ----------
function test_options_off_without_fields(tc)
% No file, no field, other fields only: every reading off and the edge-speed split at 36.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
O0 = struct('inference', false, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"profile": "profile 3", "n_rx": 4, "kpi6_set": "union"}');
verifyEqual(tc, speed_options([], f), O0);
verifyEqual(tc, speed_options(struct('dqn_seeds', 3), f), O0);
verifyEqual(tc, speed_options(), speed_options([], 'profile.json'));
end

function test_options_values(tc)
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
O0 = struct('inference', false, 'union', 'off', 'yes', '', 'band_table', false, 'edge161_n', 36);
write_json(f, '{"speed_inference": true, "speed_band_table": true, "edge161_n": 48}');
O = O0; O.inference = true; O.band_table = true; O.edge161_n = 48;
verifyEqual(tc, speed_options([], f), O);
write_json(f, '{"edge161_n": 36}'); verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"kpi7_union": "descriptive"}');
O = O0; O.union = 'descriptive'; verifyEqual(tc, speed_options([], f), O);
write_json(f, '{"kpi7_union": "off"}'); verifyEqual(tc, speed_options([], f), O0);
write_json(f, '{"kpi7_union": "verdict", "kpi7_union_yes": " 30.10.2026 21:30 "}');
O = O0; O.union = 'verdict'; O.yes = '30.10.2026 21:30'; verifyEqual(tc, speed_options([], f), O);
% CFG before the file, field by field
write_json(f, '{"speed_inference": true}');
verifyFalse(tc, speed_options(struct('speed_inference', false), f).inference);
verifyTrue(tc, speed_options(struct('speed_band_table', true), f).band_table);
verifyEqual(tc, speed_options(struct('kpi7_union', 'descriptive'), fullfile(d, 'none.json')).union, 'descriptive');
end

function test_options_errors(tc)
% A wrong value stops; the union is the verdict only with the approval's stamp.
d = tempname; mkdir(d); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
f = fullfile(d, 'profile.json');
bad = {'{"speed_inference": 1}', 'speed_options:value'; '{"speed_band_table": "yes"}', 'speed_options:value'; ...
    '{"kpi7_union": "on"}', 'speed_options:value'; '{"kpi7_union": true}', 'speed_options:value'; ...
    '{"kpi7_union": "verdict"}', 'speed_options:yes'; ...
    '{"kpi7_union": "verdict", "kpi7_union_yes": ""}', 'speed_options:yes'; ...
    '{"kpi7_union": "verdict", "kpi7_union_yes": 5}', 'speed_options:yes'; ...
    '{"kpi7_union": "descriptive", "kpi7_union_yes": "30.10.2026 21:30"}', 'speed_options:yes'; ...
    '{"kpi7_union_yes": "30.10.2026 21:30"}', 'speed_options:yes'; ...
    '{"edge161_n": 40}', 'speed_options:value'; '{"edge161_n": "48"}', 'speed_options:value'; ...
    '{"edge161_n": null}', 'speed_options:value'};
for i = 1:size(bad, 1)
    write_json(f, bad{i, 1});
    verifyError(tc, @() speed_options([], f), bad{i, 2}, bad{i, 1});
end
end

%% ---------- the statistics ----------
function test_inference_hand_example(tc)
% Three bands, two strata, seven flights; the episode of band 0 is not counted.
x    = [1 1  1 0  0 0 1  1  1 1 1 0  0 0  1];
band = [1 1  1 1  2 2 2  3  2 2 2 2  3 3  0];
cl   = [1 1  2 2  3 3 3  4  5 5 5 5  6 6  7];
st   = [1 1  1 1  1 1 1  2  2 2 2 2  2 2  1];
pg   = zeros(size(x));
S = speed_inference(x, band, cl, st, pg, 3, 400, [5 6]);
verifyEqual(tc, S.n, [4 7 3]);
verifyEqual(tc, S.nf, [2 2 2]);
verifyEqual(tc, S.m, [3/4 4/7 1/3], 'AbsTol', 1e-12);
verifyEqual(tc, S.point, 3/4 - 1/3, 'AbsTol', 1e-12);
verifyEqual(tc, S.pair, [1 3]);
verifyEqual(tc, S.nU, 6);
verifyGreaterThanOrEqual(tc, S.q, 0);
verifyEqual(tc, S.U, S.point + S.q, 'AbsTol', 1e-12);
verifyTrue(tc, all(S.lo <= S.hi));
verifyGreaterThan(tc, S.p, 0); verifyLessThanOrEqual(tc, S.p, 1);
S2 = speed_inference(x, band, cl, st, pg, 3, 400, [5 6]);
verifyTrue(tc, isequaln(S, S2), 'the same streams, the same result');
Sb = speed_inference(x, band, cl, st, pg, 3, 400, [5 6], 'boot');
verifyTrue(tc, isnan(Sb.p) && isnan(Sb.perm_mean) && Sb.q == S.q);
Sp = speed_inference(x, band, cl, st, pg, 3, 400, [5 6], 'perm');
verifyTrue(tc, isnan(Sp.q) && isnan(Sp.U) && Sp.p == S.p && Sp.perm_mean == S.perm_mean);
% a flight in two bands, strata or groups stops
verifyError(tc, @() speed_inference([1 0], [1 2], [1 1], [1 1], [0 0], 2, 50, 1), 'speed_inference:cluster');
verifyError(tc, @() speed_inference([1 0], [1 1], [1 1], [1 2], [0 0], 2, 50, 1), 'speed_inference:cluster');
verifyError(tc, @() speed_inference([1 0], [1 1], [1 1], [1 1], [0 1], 2, 50, 1), 'speed_inference:cluster');
% nothing to count
E = speed_inference([1 0], [0 0], [1 2], [1 1], [0 0], 2, 50, 1);
verifyTrue(tc, isnan(E.point) && isnan(E.p) && isnan(E.U));
end

function test_inference_identical_flights(tc)
% Flights alike inside every band and stratum: every resample is the sample, so the interval is
% the mean, q is 0 and U is the point.
[x, band, cl, st, pg] = flat_flights(RandStream('mt19937ar', 'Seed', 3), 3, 12);
x(:) = 0.75;
S = speed_inference(x, band, cl, st, pg, 4, 300, [1 2]);
verifyEqual(tc, S.q, 0); verifyEqual(tc, S.U, S.point, 'AbsTol', 1e-12);
verifyEqual(tc, S.lo, S.m, 'AbsTol', 1e-12); verifyEqual(tc, S.hi, S.m, 'AbsTol', 1e-12);
verifyEqual(tc, S.point, 0, 'AbsTol', 1e-12);
end

function test_inference_matches_reference(tc)
% The vectorized resampling against plain loops on other streams: the same band intervals, the
% same q (the Hall & Miller quantile) and the same permutation p and noise-only spread, up to
% the sampling error of 2000 resamples; groups' own flights are permuted among themselves.
rs = RandStream('mt19937ar', 'Seed', 11);
[x, band, cl, st, pg] = banded_flights(rs, [0.95 0.9 0.88 0.82], 3, 12);
B = 2000;
S = speed_inference(x, band, cl, st, pg, 4, B, [21 22]);
[q, lo, hi, p, pm] = reference_inference(x, band, cl, st, pg, 4, B, [31 32]);
verifyEqual(tc, S.q, q, 'RelTol', 0.2);
verifyEqual(tc, S.lo, lo, 'AbsTol', 0.02);
verifyEqual(tc, S.hi, hi, 'AbsTol', 0.02);
verifyEqual(tc, S.p, p, 'AbsTol', 0.05);
verifyEqual(tc, S.perm_mean, pm, 'RelTol', 0.06);
verifyLessThan(tc, S.p, 0.2);                           % the bands differ by construction
verifyGreaterThan(tc, S.perm_mean, 0);
verifyGreaterThan(tc, S.U, S.point);
end

function test_permutation_p_uniform_on_flat_set(tc)
% Bands unrelated to the rates: the permutation p is uniform (exact under exchangeability,
% Ernst 2004). 500 flat sets, 199 permutations each.
rs = RandStream('mt19937ar', 'Seed', 2024);
R = 500; P = zeros(1, R);
for i = 1:R
    [x, band, cl, st, pg] = flat_flights(rs, 3, 30);
    S = speed_inference(x, band, cl, st, pg, 4, 199, [i i + 1], 'perm');
    P(i) = S.p;
end
P = sort(P);
D = max(max(abs((1:R) / R - P), abs((0:R-1) / R - P)));   % Kolmogorov-Smirnov distance to the uniform
verifyLessThan(tc, D, 0.1);
verifyEqual(tc, mean(P), 0.5, 'AbsTol', 0.07);
verifyEqual(tc, mean(P <= 0.05), 0.05, 'AbsTol', 0.04);
verifyGreaterThanOrEqual(tc, min(P), 1 / 200);
% power: a clear band effect is found
[x, band, cl, st, pg] = banded_flights(rs, [0.98 0.9 0.8 0.7], 3, 12);
S = speed_inference(x, band, cl, st, pg, 4, 999, [7 8], 'perm');
verifyLessThan(tc, S.p, 0.01);
end

function test_permutation_stays_in_groups(tc)
% Flights of a shadowing group are permuted among themselves only. Group 1 flies band 4 alone
% at a rate far below the shared flights' (bands 1-3, equal rates): permuted within the group the
% gap to band 4 stays whatever the shared flights' bands are, so noise alone gives a spread as
% large as the observed one; permuted over all flights the gap is spread over the bands and
% noise alone gives a small spread, against which the observed one is highly significant.
rs = RandStream('mt19937ar', 'Seed', 5);
nsh = 24; nsd = 60;
band = [4 * ones(1, nsh), randi(rs, 3, 1, nsd)];
cl = 1:(nsh + nsd);
pg = [ones(1, nsh), zeros(1, nsd)];
st = [mod(0:nsh-1, 3) + 1, mod(0:nsd-1, 3) + 1];
x = [0.5 + 0.02 * rand(rs, 1, nsh), 0.9 + 0.02 * rand(rs, 1, nsd)];
Sg = speed_inference(x, band, cl, st, pg, 4, 999, [1 2], 'perm');
Su = speed_inference(x, band, cl, st, zeros(size(pg)), 4, 999, [1 2], 'perm');
verifyGreaterThan(tc, Sg.point, 0.35);
verifyGreaterThan(tc, Sg.perm_mean, 0.35);
verifyLessThan(tc, Su.perm_mean, 0.2);
verifyLessThan(tc, Su.p, 0.01);
end

%% ---------- helpers ----------
function write_json(f, s)
fid = fopen(f, 'w'); fprintf(fid, '%s', s); fclose(fid);
end

function p = base_params()
evalc('init_params');
p = load('params.mat').params;
end

function ok = same(a, b)
% Equal up to 1e-9, NaN at the same places.
ok = isequal(size(a), size(b)) && isequal(isnan(a), isnan(b)) && all(abs(a(~isnan(a)) - b(~isnan(b))) < 1e-9);
end

function [x, band, cl, st, pg] = flat_flights(rs, ns, nper)
% ns strata of nper flights each: a band at random, unrelated to the rates, 3-6 episodes per
% flight with a continuous rate in [0, 1] from the flight's own level.
nf = ns * nper;
st_f = repelem(1:ns, nper);
band_f = randi(rs, 4, 1, nf);
ne = randi(rs, [3 6], 1, nf);
lev = rand(rs, 1, nf);
cl = repelem(1:nf, ne); st = repelem(st_f, ne); band = repelem(band_f, ne);
x = min(1, max(0, repelem(lev, ne) + 0.2 * (rand(rs, 1, numel(cl)) - 0.5)));
pg = zeros(1, numel(cl));
end

function [x, band, cl, st, pg] = banded_flights(rs, rates, ns, nper)
% ns strata of nper flights in each of numel(rates) bands, 4 episodes of 0/1 per flight with the
% band's rate (and a flight level around it); the flights of the last two bands in the middle
% stratum belong to the shadowing group 1.
nb = numel(rates);
cl = []; st = []; band = []; x = []; pg = []; id = 0;
for b = 1:nb
    for u = 1:ns
        for f = 1:nper
            id = id + 1;
            lev = min(1, max(0, rates(b) + 0.15 * (rand(rs, 1) - 0.5)));
            cl = [cl, id * ones(1, 4)]; st = [st, u * ones(1, 4)]; band = [band, b * ones(1, 4)]; %#ok<AGROW>
            x = [x, double(rand(rs, 1, 4) < lev)]; %#ok<AGROW>
            pg = [pg, double(b >= 3 && u == 2) * ones(1, 4)]; %#ok<AGROW>
        end
    end
end
end

function [q, lo, hi, p, pm] = reference_inference(x, band, cl, st, pg, nb, B, seed)
% The same inference with loops over resamples on streams of their own.
[ucl, ia] = unique(cl); nU = numel(ucl);
cband = band(ia); cst = st(ia); cpg = pg(ia);
Sx = zeros(nU, nb); Sn = zeros(nU, nb);
for k = 1:nU
    e = cl == ucl(k);
    Sx(k, cband(k)) = sum(x(e)); Sn(k, cband(k)) = sum(e);
end
m = sum(Sx, 1) ./ sum(Sn, 1);
rs = RandStream('mt19937ar', 'Seed', seed(1));
Mb = zeros(B, nb);
for r = 1:B
    idx = [];
    for u = unique(cst)
        mem = find(cst == u);
        pick = mem(randi(rs, numel(mem), numel(mem), 1));
        idx = [idx; pick(:)]; %#ok<AGROW>
    end
    Mb(r, :) = sum(Sx(idx, :), 1) ./ sum(Sn(idx, :), 1);
end
d = sort(max(Mb - m, [], 2) - min(Mb - m, [], 2));
q = d(ceil(0.95 * B));
lo = zeros(1, nb); hi = zeros(1, nb);
for b = 1:nb
    v = sort(Mb(:, b)); lo(b) = v(round(0.025 * B)); hi(b) = v(round(0.975 * B));
end
rp = RandStream('mt19937ar', 'Seed', seed(2));
obs = max(m) - min(m);
key = cst * 1000 + cpg; stat = zeros(B, 1);
for r = 1:B
    pb = cband;
    for u = unique(key)
        mem = find(key == u);
        pb(mem) = cband(mem(randperm(rp, numel(mem))));
    end
    mp = zeros(1, nb);
    for b = 1:nb, mp(b) = sum(sum(Sx(pb == b, :), 2)) / sum(sum(Sn(pb == b, :), 2)); end
    stat(r) = max(mp) - min(mp);
end
p = (1 + sum(stat >= obs - 1e-12)) / (B + 1);
pm = mean(stat);
end

function R = make_run(split, nf, klow, hi, lo, shd)
% A policy_run_set.m-like result: 4 speed bands, nf flights each over 3 Eb/N0 strata, one
% pattern of recovered per flight (lo for the first klow(b) flights of band b, hi for the
% rest). shd: the even flights of bands 3 and 4 are flown by cell 2, a shadowing cell.
cen = [45 78 111 144];
rec = []; spd = []; geom = []; s = []; scn = []; sp = [];
for b = 1:4
    for f = 1:nf
        st = mod(f - 1, 3) + 1; r = (b - 1) * nf + f;
        pat = hi; if f <= klow(b), pat = lo; end
        c = 1 + (shd && b >= 3 && mod(f, 2) == 0);
        n = numel(pat);
        rec = [rec, pat]; spd = [spd, cen(b) * ones(1, n)]; geom = [geom, (1000 * st + r) * ones(1, n)]; %#ok<AGROW>
        s = [s, st * ones(1, n)]; scn = [scn, c * ones(1, n)]; sp = [sp, split * ones(1, n)]; %#ok<AGROW>
    end
end
n = numel(rec);
R = struct('recovered', rec, 'recoverable', true(1, n), 'threat', true(1, n), 'speed', spd, 'split', sp, 'geom', geom, ...
    's', s, 'scn', scn);
end

function SPR = registered_spread(R, edges)
% The registered spread of the set as evaluate_policies.m computes it.
m = R.recoverable & R.threat; nb = numel(edges) - 1; vb = zeros(size(R.speed));
for bi = 1:nb
    vb(m & R.speed >= edges(bi) & R.speed < edges(bi + 1) + (bi == nb)) = bi;
end
SPR = spread_boot(double(R.recovered), vb, R.geom, nb, 2000, 80);
end

function S = pool_cells(p, C)
% The pool cells of build_policy_pools.m: threat, severity index, kind (0 the clean link, 1 a single
% threat, 2 a combined one), airframe-shadowing level and group.
SINGLES = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
    'antenna_fault', 'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
scen = [SINGLES, C.combos];
th = {}; sev = [];
for i = 1:numel(scen)
    t = scen{i};
    if strcmp(t, 'none'), v = C.nominal;
    elseif contains(t, '+'), v = C.combo_sev;
    else, v = 1:numel(C.sev_names);
    end
    th = [th, repmat({t}, 1, numel(v))]; sev = [sev, v]; %#ok<AGROW>
end
lv = nan(1, numel(th));
for c = find(contains(th, 'airframe_shadowing')), lv(c) = threat_params(p, th{c}, sev(c), C).shadow_db; end
kind = 1 + contains(th, '+'); kind(strcmp(th, 'none')) = 0;
S = struct('th', {th}, 'sev', sev, 'kind', kind, 'level', lv, 'grp', shadow_groups(lv, p));
end

function G = pool_lists(p, NG4)
% The shared and combined geometries of every Eb/N0 and split as build_policy_pools.m draws them
% with NGEO(4) = NG4 (the shadowing groups' own flights are selected apart).
NGEO = [8 6 12 NG4 60]; NCOMB = [0 0 0 0 24]; NHOVER = 24; BLOCK = [1 5 14 16 17];
LHS = [false false true false true]; LHS_SEED = 7100000; VOUT = [0 0; 161 161];
vrange = [p.speed_kmh_min p.speed_kmh_max];
nG = NGEO + NCOMB;
r0 = arrayfun(@(sp) sum(nG(1:sp-1) .* (BLOCK(1:sp-1) == BLOCK(sp))), 1:5);
G = cell(numel(p.EbNo_dB), 5);
for s = 1:numel(p.EbNo_dB)
    for sp = 1:5
        r = r0(sp) + (1:NGEO(sp));
        lhs = []; if LHS(sp), lhs = LHS_SEED + 100 * s + sp; end
        if sp == 4
            g = pool_geometries(s, BLOCK(sp), r, VOUT(1 + ((1:NGEO(sp))' > NHOVER), :), p);
        else
            g = pool_geometries(s, BLOCK(sp), r, vrange, p, lhs);
        end
        if NCOMB(sp) > 0
            if LHS(sp), lhs = lhs + 10; end
            gc = pool_geometries(s, BLOCK(sp), r0(sp) + NGEO(sp) + (1:NCOMB(sp)), vrange, p, lhs);
            for f = fieldnames(gc)', g.(f{1}) = [g.(f{1}), gc.(f{1})]; end
        end
        G{s, sp} = g;
    end
end
end

function check_inserts(tc, rel, blk)
% Each row of blk is {before, added, after}, lists of code-line beginnings: the parent commit
% (f6f6e03) holds the lines before and after side by side, and the file holds the added lines
% between them, once. Anything else the parent holds is untouched by the block.
d = parent_copy(tc, rel, 'f6f6e03'); cl = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
[~, nm, ext] = fileparts(rel);
old = code_lines(fileread(fullfile(d, [nm ext])));
new = code_lines(fileread(fullfile(tc.TestData.root, strrep(rel, '/', filesep))));
for i = 1:size(blk, 1)
    pre = blk{i, 1}; add = blk{i, 2}; post = blk{i, 3};
    where = sprintf('%s after "%s"', rel, pre{end});
    verifyNumElements(tc, find_seq(old, [pre, post]), 1, ['the parent holds the anchors side by side, ' where]);
    verifyNumElements(tc, find_seq(new, [pre, add, post]), 1, ['the added lines sit between them, ' where]);
end
end

function at = find_seq(c, seq)
% Positions where consecutive code lines begin with seq{1}, seq{2}, ...
n = numel(seq); at = [];
for k = 1:numel(c) - n + 1
    if all(cellfun(@(l, s) startsWith(l, s), c(k:k + n - 1), seq)), at(end+1) = k; end %#ok<AGROW>
end
end

function c = code_lines(txt)
% The code lines of a source: trimmed, without blank and comment-only lines.
c = strtrim(regexp(txt, '\r?\n', 'split'));
c = c(~cellfun(@isempty, c));
c = c(~startsWith(c, '%'));
end

function d = parent_copy(tc, rel, rev)
% The file rel as commit rev holds it, alone in a folder. An export without .git (the deploy
% queue's) reads the commit from the repository named by V7_GIT_REPO.
d = tempname; mkdir(d);
[~, nm, ext] = fileparts(rel);
repo = tc.TestData.root;
[sg, ~] = system(sprintf('git --no-optional-locks -C "%s" rev-parse --git-dir', repo));
if sg ~= 0 && ~isempty(getenv('V7_GIT_REPO')), repo = getenv('V7_GIT_REPO'); end
[st, out] = system(sprintf('git --no-optional-locks -C "%s" show %s:%s > "%s"', repo, rev, rel, ...
    fullfile(d, [nm ext])));
assertEqual(tc, st, 0, sprintf('git show %s:%s failed: %s', rev, rel, out));
end
