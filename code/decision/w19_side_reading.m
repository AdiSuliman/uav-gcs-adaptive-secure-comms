function out = w19_side_reading(a, varargin)
%W19_SIDE_READING  Descriptive side readings of the saved outputs of the single test read (profile 3).
%   L = w19_side_reading(root, tree)
%       Reads root/results/weak19/p3/test.mat (D125) and rulerows_test.mat (D127), checks the numbers
%       the read printed, and writes root/results/weak19/p3/side_reading.txt. tree: the folder holding
%       data/trained_dqn.mat (cycles per episode), default root. Nothing is re-read; no marker is written.
%   S = w19_side_reading('d125', A)             comb set, off x on: table, held, paired differences
%   S = w19_side_reading('d127', B, pay_bps)    rule rows off -> on: delivered and normalized goodput
%   S = w19_side_reading('clean', SW, T, ms)    false changes per hour off -> on, Garwood bounds
%   S = w19_side_reading('p125', A)             recomputed one-sided p of the D125 test (read's seed)
%   S = w19_side_reading('p127', B)             recomputed claims of D127 (read's seeds)
%   S = w19_side_reading('bonf', p, names, m)   Bonferroni at 0.05 / m over one-sided p-values
%   c = w19_side_reading('cells')               threat of each pool cell (PP.scen's order; scn indexes it)
%   Intervals: cluster bootstrap over flight geometries (boot_cluster.m, 2000 draws, 95% two-sided),
%   seeds from SEED_BASE, apart from the read's.
%   A paired difference is on minus off over the same episodes; non-finite pairs are dropped.
cmds = {'d125', 'd127', 'clean', 'p125', 'p127', 'bonf', 'reg', 'cells'};
if (ischar(a) || isstring(a)) && ismember(char(a), cmds)
    switch char(a)
        case 'd125', out = d125(varargin{:});
        case 'd127', out = d127(varargin{:});
        case 'clean', out = clean(varargin{:});
        case 'p125', out = p125(varargin{:});
        case 'p127', out = p127(varargin{:});
        case 'bonf', out = bonf(varargin{:});
        case 'reg', out = reg();
        case 'cells', out = cell_threats();
    end
    return
end
out = main(char(a), varargin{:});
end

%% ===================== Constants =====================
function R = reg()
R.B = 2000; R.seed = 2800;               % apart from the read's seeds (1900-1926, 1950, 2701-2724)
R.singles = {'none', 'jamming', 'noise_burst', 'reactive_jamming', 'path_loss', 'spoofing', ...
    'antenna_fault', 'benign_interference', 'sweeping_jammer', 'tone_jamming', 'airframe_shadowing'};
R.jam = {'jamming', 'noise_burst', 'reactive_jamming', 'sweeping_jammer', 'tone_jamming'};
R.rows = {'rule_esc', 'blind_esc', 'rule_core', 'blind_core'};
R.label = struct('rule_esc', 'rule + escalation', 'blind_esc', 'no detector + escalation', ...
    'rule_core', 'core rule + escalation', 'blind_core', 'core no detector + escalation');
R.bonf_m = 4;
% Values the read printed (rulerows_reading.txt), kb/s: row, subset, off, on, mandatory
R.chk = {'rule_esc', 'threat', 21.47, 18.65, true; 'rule_core', 'threat', 11.31, 8.48, true; ...
    'rule_esc', 'jam36', 25.45, 20.11, false; 'blind_esc', 'threat', 23.78, 23.83, false; ...
    'blind_esc', 'jam36', 28.98, 29.05, false; 'rule_core', 'jam36', 11.35, 7.45, false; ...
    'rule_core', 'jamcore', 12.38, 7.54, false; 'blind_core', 'threat', 9.15, 9.04, false; ...
    'blind_core', 'jam36', 8.47, 8.20, false; 'blind_core', 'jamcore', 8.32, 7.95, false};
R.chk_norm = {'rule_esc', 0.612, 0.532; 'rule_core', 0.325, 0.241};
R.chk_n = struct('threat', 32256, 'jam36', 11294, 'jamcore', 8638);
R.chk_fph = {'rule_esc', 543.3, 543.3; 'rule_core', 776.7, 790.0; 'blind_esc', 443.3, 443.3; 'blind_core', 673.3, 706.7};
R.chk_d125 = struct('gain', 12.98, 'ncl', 143);
R.chk_d127 = struct('gain', [7.29 10.71 5.78], 'ncl', [720 144 144]);
end

%% ===================== Main =====================
function L = main(root, tree)
if nargin < 2 || isempty(tree), tree = root; end
R = reg();
d = fullfile(root, 'results', 'weak19', 'p3');
A = load(fullfile(d, 'test.mat'));
B = load(fullfile(d, 'rulerows_test.mat'));
H = load(fullfile(tree, 'data', 'trained_dqn.mat'), 'H'); T = H.H.T;
C = decision_config();
pay = payload_rate(root, C);
S1 = d125(A);
S2 = d127(B, pay);
S3 = clean(B.SW, T, C.period_ms);
P1 = p125(A); P2 = p127(B);
bad = check_all(R, S1, S2, S3, P1, P2);
S4 = bonf([P1.p, P2.p], [{'dqn_hop comb (D125)'}, P2.name], R.bonf_m);
L = {'Side reading (descriptive, selects nothing; from saved outputs of the single test read)', ...
    sprintf('Sources: results/weak19/p3/test.mat (D125, dqn_hop off/on, comb set), rulerows_test.mat (D127, rule rows off and keep+st+rate on); %d cycles per episode, %g ms; nominal payload %.2f kb/s.', ...
    T, C.period_ms, pay / 1e3), ...
    sprintf(['Intervals: 95%% cluster bootstrap over flight geometries (%d draws, seeds %d+), difference = on minus off ' ...
    'over the same episodes.'], R.B, R.seed), ''};
L = [L, {'1. D125, dqn_hop comb set (recoverable threat episodes of the fresh comb set)'}, S1.lines, {''}, ...
    {'2. D127, rule rows off -> with keep+st+rate'}, S2.lines, {''}, ...
    {'3. D127, clean flights: false changes per hour, off -> on'}, S3.lines, {''}, ...
    {'4. Joint Bonferroni over the four confirmatory tests'}, S4.lines, {''}, ...
    {'Cross-checks against the numbers the read printed:'}, bad.lines];
if ~isempty(bad.fail)
    error('w19_side_reading:check', 'w19_side_reading: the read''s numbers are not reproduced: %s', strjoin(bad.fail, '; '));
end
write_lines(fullfile(d, 'side_reading.txt'), L);
fprintf('%s\n', L{:});
end

function bad = check_all(R, S1, S2, S3, P1, P2)
K = {{}, {}};
K = rec(K, abs(100 * S1.gain - R.chk_d125.gain) < 0.006 && S1.ncl == R.chk_d125.ncl, true, ...
    sprintf('D125 dqn_hop comb gain %+.2f points, %d clusters (printed +%.2f, %d)', 100 * S1.gain, S1.ncl, R.chk_d125.gain, R.chk_d125.ncl));
for k = 1:3
    K = rec(K, abs(100 * P2.gain(k) - R.chk_d127.gain(k)) < 0.006 && P2.ncl(k) == R.chk_d127.ncl(k), true, ...
        sprintf('D127 %s gain %+.2f points, %d clusters (printed +%.2f, %d)', P2.name{k}, 100 * P2.gain(k), P2.ncl(k), R.chk_d127.gain(k), R.chk_d127.ncl(k)));
end
K = rec(K, isequal(P1.stored, P1.p) && isequal(P2.stored, P2.p), true, ...
    sprintf('recomputed one-sided p equal the stored ones (%s)', strjoin(arrayfun(@(x) sprintf('%.4f', x), [P1.p, P2.p], 'UniformOutput', false), ', ')));
for f = {'threat', 'jam36', 'jamcore'}
    n = S2.n.(f{1});
    K = rec(K, n == R.chk_n.(f{1}), true, sprintf('episodes %s: %d (printed %d)', f{1}, n, R.chk_n.(f{1})));
end
for k = 1:size(R.chk, 1)
    v = S2.val.(R.chk{k, 1}).(R.chk{k, 2});
    K = rec(K, abs(v.off / 1e3 - R.chk{k, 3}) < 0.006 && abs(v.on / 1e3 - R.chk{k, 4}) < 0.006, R.chk{k, 5}, ...
        sprintf('%s, %s: delivered %.2f -> %.2f kb/s (printed %.2f -> %.2f)', R.chk{k, 1}, R.chk{k, 2}, v.off / 1e3, v.on / 1e3, R.chk{k, 3}, R.chk{k, 4}));
end
for k = 1:size(R.chk_norm, 1)
    v = S2.val.(R.chk_norm{k, 1}).threat;
    K = rec(K, abs(v.g_off - R.chk_norm{k, 2}) < 0.0006 && abs(v.g_on - R.chk_norm{k, 3}) < 0.0006, false, ...
        sprintf('%s, threat: normalized %.3f -> %.3f (printed %.3f -> %.3f)', R.chk_norm{k, 1}, v.g_off, v.g_on, R.chk_norm{k, 2}, R.chk_norm{k, 3}));
end
for k = 1:size(R.chk_fph, 1)
    v = S3.row.(R.chk_fph{k, 1});
    K = rec(K, abs(v.fph0 - R.chk_fph{k, 2}) < 0.06 && abs(v.fph1 - R.chk_fph{k, 3}) < 0.06, true, ...
        sprintf('%s false changes per hour %.1f -> %.1f (printed %.1f -> %.1f)', R.chk_fph{k, 1}, v.fph0, v.fph1, R.chk_fph{k, 2}, R.chk_fph{k, 3}));
end
bad = struct('lines', {K{1}}, 'fail', {K{2}});
end

function K = rec(K, ok, mand, txt)
K{1}{end+1} = sprintf('  %-8s %s', ternary(ok, 'ok', 'MISMATCH'), txt);
if ~ok && mand, K{2}{end+1} = txt; end
end

%% ===================== 1. D125 =====================
function S = d125(A)
R = reg();
ic = find(strcmp(A.sets, 'comb'), 1);
assert(~isempty(ic), 'w19_side_reading:sets', 'w19_side_reading: no comb set in test.mat');
c0 = A.RONs{ic, 1}; c1 = A.RONs{ic, 2};
assert(isequal(c0.geom, c1.geom) && isequal(c0.recoverable, c1.recoverable) && isequal(c0.threat, c1.threat), ...
    'w19_side_reading:pairs', 'w19_side_reading: off and on are not the same episodes');
m = logical(c0.recoverable) & logical(c0.threat); cl = c0.geom(m);
r0 = logical(c0.recovered(m)); r1 = logical(c1.recovered(m));
h0 = double(c0.held(m)); h1 = double(c1.held(m));
q0 = double(c0.per_post(m)); q1 = double(c1.per_post(m));
v0 = double(c0.dlv_post(m)); v1 = double(c1.dlv_post(m));
n = sum(m);
S = struct('n', n, 'ncl', numel(unique(cl)), 'tab', zeros(2, 2), 'lines', {{}});
L = {sprintf('  %d episodes, %d clusters (flight geometries)', n, S.ncl), ...
    '  recovered, off x on (cell: episodes; delivered payload after onset [% of nominal] and packet loss after onset [%], mean off -> on within the cell):'};
for i = 0:1
    for j = 0:1
        k = r0 == i & r1 == j;
        S.tab(i + 1, j + 1) = sum(k);
        L{end+1} = sprintf('    off %-14s on %-14s n %5d (%4.1f%%)  delivered %s  packet loss %s', ...
            ternary(i, 'recovered', 'not recovered'), ternary(j, 'recovered', 'not recovered'), sum(k), 100 * sum(k) / max(n, 1), ...
            pair_txt(100 * mean(v0(k), 'omitnan'), 100 * mean(v1(k), 'omitnan'), '%.1f'), ...
            pair_txt(100 * mean(q0(k), 'omitnan'), 100 * mean(q1(k), 'omitnan'), '%.1f')); %#ok<AGROW>
    end
end
[mr, lr, hr] = dci(double(r1) - double(r0), cl, R.seed + 1);
S.gain = mr; S.lo = lr; S.hi = hr;
L{end+1} = sprintf('  recovered   %5.1f%% -> %5.1f%%   paired difference %s points', 100 * mean(r0), 100 * mean(r1), ci_txt(mr, lr, hr, 100, '%+.2f'));
[mh, lh, hh] = dci(h1 - h0, cl, R.seed + 2);
L{end+1} = sprintf('  held        %5.1f%% -> %5.1f%%   paired difference %s points (held off -> on: %d lost, %d gained)', ...
    100 * mean(h0), 100 * mean(h1), ci_txt(mh, lh, hh, 100, '%+.2f'), sum(h0 == 1 & h1 == 0), sum(h0 == 0 & h1 == 1));
[mp, lp, hp] = dci(q1 - q0, cl, R.seed + 3);
f = isfinite(q0) & isfinite(q1);
L{end+1} = sprintf('  packet loss after onset (per_post) %5.1f%% -> %5.1f%%   paired difference %s points (%d episodes with a packet in both)', ...
    100 * mean(q0(f)), 100 * mean(q1(f)), ci_txt(mp, lp, hp, 100, '%+.2f'), sum(f));
[mv, lv, hv] = dci(v1 - v0, cl, R.seed + 4);
L{end+1} = sprintf('  delivered after onset (dlv_post)   %5.1f%% -> %5.1f%%   paired difference %s points of the nominal payload', ...
    100 * mean(v0, 'omitnan'), 100 * mean(v1, 'omitnan'), ci_txt(mv, lv, hv, 100, '%+.2f'));
S.held = struct('d', mh, 'lo', lh, 'hi', hh); S.per = struct('d', mp, 'lo', lp, 'hi', hp); S.dlv = struct('d', mv, 'lo', lv, 'hi', hv);
S.lines = L;
end

%% ===================== 2. D127 =====================
function S = d127(B, pay)
R = reg();
P = B.pols; ns = size(B.F0, 1);
x0 = struct(); x1 = struct();
for pk = 1:numel(P)
    x0.(P{pk}) = cat_sets(B.F0(:, pk)); x1.(P{pk}) = cat_sets(B.F1(:, pk));
end
z = x0.none;
jam = jam_mask(z.scn, R);
mt = logical(z.threat);
m36 = logical(z.recoverable) & mt & jam;
mcr = logical(z.recoverable_core) & mt & jam;
subs = struct('key', {'threat', 'jam36', 'jamcore'}, 'name', {'threat episodes', 'recoverable jamming episodes (36 configurations)', ...
    'recoverable jamming episodes (core action set)'}, 'm', {mt, m36, mcr});
S = struct('n', struct('threat', sum(mt), 'jam36', sum(m36), 'jamcore', sum(mcr)), 'val', struct(), 'lines', {{}});
L = {sprintf(['  Subsets as the read printed them: %d threat episodes (all three fresh sets pooled), %d recoverable jamming episodes ' ...
    '(jamming, noise_burst, reactive_jamming, sweeping_jammer, tone_jamming), %d of them recoverable by the core action set.'], ...
    sum(mt), sum(m36), sum(mcr)), ...
    '  Delivered = nominal payload x dlv_post (payload bits delivered after onset); normalized = gput_post (goodput factor of the configuration, before packet loss); difference = on minus off.'};
for r = 1:numel(R.rows)
    p = R.rows{r}; a0 = x0.(p); a1 = x1.(p);
    assert(isequal(a0.geom, z.geom) && isequal(a1.geom, z.geom), 'w19_side_reading:pairs', 'w19_side_reading: %s is not on the same episodes', p);
    L{end+1} = sprintf('  %s (%s):', p, R.label.(p)); %#ok<AGROW>
    core = startsWith(p, 'rule_core') || startsWith(p, 'blind_core');
    for k = 1:numel(subs)
        if strcmp(subs(k).key, 'jamcore') && ~core, continue; end
        mk = subs(k).m;
        cl = z.geom(mk); sd = R.seed + 100 * (10 + r) + 10 * k;
        b0 = pay * double(a0.dlv_post(mk)); b1 = pay * double(a1.dlv_post(mk));
        [o0, ~, ~] = boot_cluster(b0, ones(size(b0)), cl, R.B, sd);
        [o1, ~, ~] = boot_cluster(b1, ones(size(b1)), cl, R.B, sd);
        [dd, dl, dh] = dci(b1 - b0, cl, sd + 1);
        g0 = double(a0.gput_post(mk)); g1 = double(a1.gput_post(mk));
        [gd, gl, gh] = dci(g1 - g0, cl, sd + 2);
        S.val.(p).(subs(k).key) = struct('off', o0, 'on', o1, 'd', dd, 'lo', dl, 'hi', dh, 'g_off', mean(g0, 'omitnan'), ...
            'g_on', mean(g1, 'omitnan'), 'g_d', gd, 'g_lo', gl, 'g_hi', gh, 'n', sum(mk), 'ncl', numel(unique(cl)));
        L{end+1} = sprintf('    %-52s n %5d, %3d clusters: delivered %s kb/s; normalized %s', subs(k).name, sum(mk), numel(unique(cl)), ...
            [pair_txt(o0 / 1e3, o1 / 1e3, '%.2f') '  ' ci_txt(dd, dl, dh, 1e-3, '%+.2f')], ...
            [pair_txt(mean(g0, 'omitnan'), mean(g1, 'omitnan'), '%.3f') '  ' ci_txt(gd, gl, gh, 1, '%+.3f')]); %#ok<AGROW>
    end
end
S.lines = L;
end

function jam = jam_mask(scn, R)
jam = ismember(cell_threats(scn), R.jam);
end

function nm = name_of(scn, ~)
nm = cell_threats(scn);
end

function c = cell_threats(scn)
% The threat of each pool cell in PP.scen's order (build_policy_pools.m: one cell for none, the combined
% severities for a combination, one cell per severity for a single threat); scn indexes it.
R = reg(); C = decision_config();
c = cell(1, 0);
for t = [R.singles, C.combos]
    if strcmp(t{1}, 'none'), n = 1;
    elseif contains(t{1}, '+'), n = numel(C.combo_sev);
    else, n = numel(C.sev_names);
    end
    c = [c, repmat(t, 1, n)]; %#ok<AGROW>
end
if nargin > 0
    assert(all(scn >= 1 & scn <= numel(c)), 'w19_side_reading:cells', 'w19_side_reading: scn outside the %d pool cells', numel(c));
    c = reshape(c(scn), size(scn));
end
end

%% ===================== 3. Clean flights =====================
function S = clean(SW, T, period_ms)
% SW: per rule row 2 x n changes per clean flight (row 1 off, row 2 on).
if isstruct(SW), rows = fieldnames(SW)'; else, rows = {'row'}; SW = struct('row', SW); end
cyc_h = 3600e3 / period_ms;
S = struct('row', struct(), 'lines', {{}});
L = {sprintf(['  %d clean flights of %d cycles; rate = changes / (flights x cycles) x %.0f cycles per hour; "bound" the one-sided 95%% Garwood upper ' ...
    'bound of that rate (Poisson count; changes cluster in flights, so the bound is optimistic).'], size(SW.(rows{1}), 2), T, cyc_h)};
for r = 1:numel(rows)
    s = double(SW.(rows{r})); n = size(s, 2); cyc = T * n;
    k0 = sum(s(1, :)); k1 = sum(s(2, :));
    up = sum(max(s(2, :) - s(1, :), 0)); dn = sum(max(s(1, :) - s(2, :), 0));
    q = struct('k0', k0, 'k1', k1, 'n', n, 'fph0', k0 / cyc * cyc_h, 'fph1', k1 / cyc * cyc_h, ...
        'u0', paired_stats('garwood', k0, cyc) * cyc_h, 'u1', paired_stats('garwood', k1, cyc) * cyc_h, 'up', up, 'dn', dn, ...
        'uu', paired_stats('garwood', up, cyc) * cyc_h, 'flights0', sum(s(1, :) > 0), 'flights1', sum(s(2, :) > 0));
    S.row.(rows{r}) = q;
    L{end+1} = sprintf(['  %-11s changes %d -> %d (flights with a change %d -> %d of %d); per hour %.1f -> %.1f (change %+.1f); bound %.1f -> %.1f; ' ...
        'added on a flight %d, removed %d (bound on the added changes per hour %.1f)'], rows{r}, k0, k1, q.flights0, q.flights1, n, ...
        q.fph0, q.fph1, q.fph1 - q.fph0, q.u0, q.u1, up, dn, q.uu); %#ok<AGROW>
end
S.lines = L;
end

%% ===================== 4. Recomputed tests and Bonferroni =====================
function P = p125(A)
% The D125 test as the read ran it (weak19_reading.m fresh_lines, comb set).
W = weak19_reading('reg');
ic = find(strcmp(A.sets, 'comb'), 1);
c0 = A.RONs{ic, 1}; c1 = A.RONs{ic, 2};
m = logical(c0.recoverable) & logical(c0.threat);
Q = weak19_reading('ptest', double(c1.recovered(m)) - double(c0.recovered(m)), c0.geom(m), W.alpha, W.boot_seed + 21);
P = struct('p', Q.p, 'gain', Q.mean, 'ncl', Q.ncl, 'stored', NaN);
if isfield(A, 'verdict') && isfield(A.verdict, 'p'), P.stored = A.verdict.p(1); end
end

function P = p127(B)
% The three D127 claims as the read ran them (weak19_reading.m rr_claims), recomputed from the saved rows.
W = weak19_reading('reg'); R = reg();
pols = B.pols;
x0 = struct(); x1 = struct();
for pk = 1:numel(pols)
    x0.(pols{pk}) = cat_sets(B.F0(:, pk)); x1.(pols{pk}) = cat_sets(B.F1(:, pk));
end
z = x0.none; cl = z.geom; nm = name_of(z.scn, R);
m = logical(z.recoverable) & logical(z.threat); mc = logical(z.recoverable_core) & logical(z.threat);
c = W.rr.claims; nc = numel(c);
P = struct('name', {{c.name}}, 'p', zeros(1, nc), 'gain', zeros(1, nc), 'ncl', zeros(1, nc), 'stored', zeros(1, nc));
for k = 1:nc
    a0 = x0.(c(k).row); a1 = x1.(c(k).row);
    if isempty(c(k).threat)
        d = double(a1.recovered(m)) - double(a0.recovered(m));
        [mu, q] = paired_stats('dist', d, cl(m), W.B, c(k).seed);
        P.p(k) = mean(q <= 0); P.gain(k) = mu; P.ncl(k) = numel(unique(cl(m & isfinite(double(a1.recovered) - double(a0.recovered)))));
    else
        ok = mc & strcmp(nm, c(k).threat) & isfinite(a0.per_post) & isfinite(a1.per_post) & isfinite(z.per_post);
        Q = weak19_reading('rr_ratio', a0.per_post(ok) - a1.per_post(ok), z.per_post(ok), cl(ok), W.B, c(k).seed);
        P.p(k) = Q.p; P.gain(k) = Q.mean; P.ncl(k) = Q.ncl;
    end
    P.stored(k) = B.claims.claims(k).P.p;
end
end

function S = bonf(p, names, m)
a = 0.05 / m;
ok = p <= a; ok(isnan(p)) = false;
R = reg();
t = cell(1, numel(p));
for k = 1:numel(p), t{k} = sprintf('%s p %s', names{k}, p_txt(p(k), R.B)); end
L = {sprintf('  Joint Bonferroni over %d tests at 0.05/%d = %.4f: %s (one-sided cluster-bootstrap p, %d draws: %s)', ...
    m, m, a, ternary(all(ok), 'all pass', 'FAILS'), R.B, strjoin(t, '; '))};
S = struct('pass', all(ok), 'ok', ok, 'alpha', a, 'lines', {L});
end

function t = p_txt(p, B)
if p == 0, t = sprintf('< %.4f (no draw at or below 0)', 1 / B); else, t = sprintf('%.4f', p); end
end

%% ===================== Helpers =====================
function [m, lo, hi] = dci(d, cl, seed)
% Mean of d with the 95% cluster-bootstrap interval (boot_cluster.m).
R = reg();
d = double(d(:)'); cl = cl(:)';
[m, lo, hi] = boot_cluster(d, ones(size(d)), cl, R.B, seed);
end

function R = cat_sets(c)
R = c{1};
f = fieldnames(R);
for i = 2:numel(c)
    for j = 1:numel(f), R.(f{j}) = [R.(f{j}), c{i}.(f{j})]; end
end
end

function t = pair_txt(a, b, fmt)
t = sprintf([fmt ' -> ' fmt], a, b);
end

function t = ci_txt(d, lo, hi, sc, fmt)
t = sprintf([fmt ' [' fmt ', ' fmt ']'], sc * d, sc * lo, sc * hi);
end

function r = payload_rate(root, C)
p = load(fullfile(root, 'params.mat')).params;
cyc = C.period_ms / 1000; if isfield(p, 'cycle_s'), cyc = p.cycle_s; end
r = p.bits_per_frame / cyc;
end

function write_lines(f, L)
fid = fopen(f, 'w');
assert(fid > 0, 'w19_side_reading:write', 'w19_side_reading: cannot write %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', L{:});
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
