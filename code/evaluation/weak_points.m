function W = weak_points(y, F, grp, opt)
%WEAK_POINTS  Where a metric is lost: breakdown of a per-unit outcome by every
%   factor and by pairs of factors, with the share of the overall deficit that
%   each cell accounts for.
%   y     n x 1 outcome per unit (1/0 correct or recovered, or a continuous value)
%   F     table of n rows, one column per factor (numeric columns are binned by
%         opt.bins.<name> edges, or into 5 quantile bins)
%   grp   n x 1 cluster of each unit (sub-run or flight geometry): the bootstrap
%         resamples whole clusters, since units of one cluster are correlated
%   opt   target (the KPI target, default the overall mean), nboot (1000),
%         bins (struct of edges), pairs (k x 2 cell of factor names), min_n (30)
%   W     struct: overall, target, per factor a table of cells (value, n, 95%
%         interval, difference to the rest, deficit points), flagged low and high
%         cells, and the 2-D tables of opt.pairs
%   Deficit points of a cell: its share of the units times its shortfall below
%   the target, i.e. how many points of the overall result it pulls down; the
%   overall result if the cell alone reached the target is overall + deficit.
%   A cell is low (high) when its interval lies entirely below (above) the mean
%   of all the other units.
if nargin < 4, opt = struct(); end
nb = getf(opt, 'nboot', 1000); min_n = getf(opt, 'min_n', 30);
y = double(y(:)); n = numel(y);
[~, ~, gi] = unique(grp(:));
W.overall = mean(y, 'omitnan');
W.target = getf(opt, 'target', W.overall);
W.n = n;
rs = RandStream('mt19937ar', 'Seed', 17);
names = F.Properties.VariableNames;
L = cell(1, numel(names));
for k = 1:numel(names)
    L{k} = levels_of(F.(names{k}), names{k}, opt);
end
W.factors = struct('name', {}, 'cells', {});
W.low = {}; W.high = {};
for k = 1:numel(names)
    [lab, idx] = deal(L{k}.labels, L{k}.idx);
    T = cell_table(y, idx, lab, gi, W, nb, rs, min_n);
    W.factors(end+1) = struct('name', names{k}, 'cells', T);
    for c = 1:height(T)
        if T.low(c), W.low{end+1} = sprintf('%s = %s: %.1f (n %d, [%.1f, %.1f]) vs rest %.1f, deficit %.2f', ...
                names{k}, T.cell{c}, T.value(c), T.n(c), T.lo(c), T.hi(c), T.rest(c), T.deficit(c)); end %#ok<AGROW>
        if T.high(c), W.high{end+1} = sprintf('%s = %s: %.1f (n %d, [%.1f, %.1f]) vs rest %.1f', ...
                names{k}, T.cell{c}, T.value(c), T.n(c), T.lo(c), T.hi(c), T.rest(c)); end %#ok<AGROW>
    end
end
P = getf(opt, 'pairs', {});
W.pairs = struct('a', {}, 'b', {}, 'value', {}, 'n', {}, 'deficit', {}, 'la', {}, 'lb', {});
for q = 1:size(P, 1)
    a = find(strcmp(names, P{q, 1})); b = find(strcmp(names, P{q, 2}));
    na = numel(L{a}.labels); nbb = numel(L{b}.labels);
    V = nan(na, nbb); N = zeros(na, nbb); D = zeros(na, nbb);
    for i = 1:na
        for j = 1:nbb
            m = L{a}.idx == i & L{b}.idx == j;
            N(i, j) = sum(m);
            if N(i, j) > 0
                V(i, j) = mean(y(m), 'omitnan');
                D(i, j) = N(i, j) / n * max(W.target - V(i, j), 0);
            end
        end
    end
    W.pairs(end+1) = struct('a', names{a}, 'b', names{b}, 'value', V, 'n', N, 'deficit', D, ...
        'la', {L{a}.labels}, 'lb', {L{b}.labels});
end
end

function T = cell_table(y, idx, lab, gi, W, nb, rs, min_n)
nc = numel(lab); n = numel(y);
v = nan(nc, 1); cnt = zeros(nc, 1); lo = nan(nc, 1); hi = nan(nc, 1); rest = nan(nc, 1); de = zeros(nc, 1);
low = false(nc, 1); high = false(nc, 1);
for c = 1:nc
    m = idx == c; cnt(c) = sum(m);
    if cnt(c) == 0, continue; end
    v(c) = mean(y(m), 'omitnan'); rest(c) = mean(y(~m), 'omitnan');
    de(c) = cnt(c) / n * max(W.target - v(c), 0);
    [lo(c), hi(c)] = boot_ci(y(m), gi(m), nb, rs);
    if cnt(c) >= min_n
        low(c) = hi(c) < rest(c); high(c) = lo(c) > rest(c);
    end
end
T = table(lab(:), v, cnt, lo, hi, rest, v - rest, de, low, high, ...
    'VariableNames', {'cell', 'value', 'n', 'lo', 'hi', 'rest', 'diff', 'deficit', 'low', 'high'});
end

function [lo, hi] = boot_ci(y, g, nb, rs)
[ug, ~, k] = unique(g);
if numel(ug) < 2, lo = NaN; hi = NaN; return; end
s = accumarray(k, y, [], @(v) sum(v, 'omitnan')); c = accumarray(k, 1);
b = zeros(nb, 1);
for i = 1:nb
    j = randi(rs, numel(ug), numel(ug), 1);
    b(i) = sum(s(j)) / sum(c(j));
end
b = sort(b); lo = b(max(1, round(0.025 * nb))); hi = b(min(nb, round(0.975 * nb)));
end

function L = levels_of(x, name, opt)
% Labels and the cell index of every unit; numeric factors are binned.
if iscategorical(x) || iscellstr(x) || isstring(x)
    x = categorical(x); lab = categories(x); [~, idx] = ismember(cellstr(x), lab);
    L = struct('labels', {lab}, 'idx', idx(:)); return;
end
x = double(x(:));
u = unique(x(~isnan(x)));
if numel(u) <= 8                                          % few distinct values: one cell each
    [~, idx] = ismember(x, u);
    L = struct('labels', {cellstr(compose('%g', u))}, 'idx', idx); return;
end
if isfield(opt, 'bins') && isfield(opt.bins, name)
    e = opt.bins.(name);
else
    e = unique(quantile(x, linspace(0, 1, 6)));
end
e(1) = -inf; e(end) = inf;
idx = discretize(x, e);
lab = arrayfun(@(i) sprintf('%s-%s', num_txt(e(i)), num_txt(e(i+1))), 1:numel(e)-1, 'UniformOutput', false);
L = struct('labels', {lab}, 'idx', idx);
end

function s = num_txt(v)
if isinf(v), s = ternary(v < 0, 'min', 'max'); else, s = sprintf('%.3g', v); end
end

function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
