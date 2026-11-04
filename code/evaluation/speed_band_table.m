function [lines, T] = speed_band_table(rec, harmed, thr, s, speed, ebno, edges, lb)
%SPEED_BAND_TABLE  The selected agent's recovered per speed band and per Eb/N0, and its harmed
%   lost-branch episodes per band, on the recoverable threat episodes of the validation flights
%   (train_dqn.m, "speed_band_table"). Reported only: nothing is selected on it, and the validation
%   flights have already served the selection, so it is indicative.
%   [lines, T] = speed_band_table(rec, harmed, thr, s, speed, ebno, edges, lb)
%   rec     recovered per episode (1 x n logical or 0/1)
%   harmed  no response does not restore the episode's geometry (link_env.m K.restored at no_action)
%   thr     the episode's threat (1 x n cell of names, severities pooled)
%   s       Eb/N0 index into ebno; speed  the geometry's speed [km/h]
%   edges   speed band edges [km/h]; lb  the lost-branch classes (default antenna_fault, airframe_shadowing)
%   lines   the text; T  the numbers: edges, ebno, threats, rec_band and n_band (threat x band),
%           rec_ebno and n_ebno (threat x Eb/N0), lb_n, lb_rec, lb_share (per band), deficit and
%           deficit_lb (per band, points of all the band's episodes), pooled_band and pooled_n
if nargin < 8 || isempty(lb), lb = {'antenna_fault', 'airframe_shadowing'}; end
rec = double(rec(:)'); harmed = logical(harmed(:)'); s = s(:)'; speed = speed(:)'; thr = thr(:)';
nb = numel(edges) - 1; ne = numel(ebno);
vb = zeros(size(speed));
for bi = 1:nb
    vb(speed >= edges(bi) & speed < edges(bi + 1) + (bi == nb)) = bi;
end
th = unique(thr, 'stable');
T = struct('edges', edges, 'ebno', ebno, 'threats', {th}, 'rec_band', nan(numel(th), nb), 'n_band', zeros(numel(th), nb), ...
    'rec_ebno', nan(numel(th), ne), 'n_ebno', zeros(numel(th), ne), 'lb', {lb}, 'lb_n', zeros(1, nb), 'lb_rec', nan(1, nb), ...
    'lb_share', nan(1, nb), 'deficit', nan(1, nb), 'deficit_lb', nan(1, nb), 'pooled_band', nan(1, nb), 'pooled_n', zeros(1, nb));
bt = strjoin(arrayfun(@(b) sprintf('%.0f-%.0f', edges(b), edges(b + 1)), 1:nb, 'UniformOutput', false), ', ');
et = strjoin(arrayfun(@(e) sprintf('%g', e), ebno, 'UniformOutput', false), ', ');
lines = {['A'' per speed band (D116 item 6): the selected agent on the validation flights, recoverable threat episodes; ' ...
    'reported only, nothing is selected on it']};
lines{end+1} = sprintf('  recovered %% (episodes) per threat; speed bands %s km/h || Eb/N0 %s dB', bt, et);
for ti = 1:numel(th)
    mt = strcmp(thr, th{ti});
    for b = 1:nb, [T.rec_band(ti, b), T.n_band(ti, b)] = rate(rec, mt & vb == b); end
    for e = 1:ne, [T.rec_ebno(ti, e), T.n_ebno(ti, e)] = rate(rec, mt & s == e); end
    lines{end+1} = sprintf('   %-42s %s || %s', th{ti}, row_txt(T.rec_band(ti, :), T.n_band(ti, :)), ...
        row_txt(T.rec_ebno(ti, :), T.n_ebno(ti, :))); %#ok<AGROW>
end
pe = nan(1, ne); pn = zeros(1, ne);
for b = 1:nb, [T.pooled_band(b), T.pooled_n(b)] = rate(rec, vb == b); end
for e = 1:ne, [pe(e), pn(e)] = rate(rec, s == e); end
lines{end+1} = sprintf('   %-42s %s || %s', 'pooled', row_txt(T.pooled_band, T.pooled_n), row_txt(pe, pn));
hl = harmed & ismember(thr, lb);
lines{end+1} = sprintf(['  harmed lost-branch episodes (%s; no response does not restore them) per speed band: episodes, recovered %%, ' ...
    'harmed share of the lost-branch episodes; the band''s deficit (points of all its episodes) and the part of it on them'], ...
    strjoin(lb, ', '));
for b = 1:nb
    inb = vb == b; k = hl & inb;
    T.lb_n(b) = sum(k);
    [T.lb_rec(b), ~] = rate(rec, k);
    nl = sum(inb & ismember(thr, lb));
    if nl > 0, T.lb_share(b) = sum(k) / nl; end
    if any(inb)
        T.deficit(b) = 100 * sum(inb & ~rec) / sum(inb);
        T.deficit_lb(b) = 100 * sum(k & ~rec) / sum(inb);
    end
    lines{end+1} = sprintf('   %.0f-%.0f km/h: %d harmed, recovered %s, harmed share %s | deficit %s points, %s on them (%s of it)', ...
        edges(b), edges(b + 1), T.lb_n(b), pct(T.lb_rec(b)), pct(T.lb_share(b)), num(T.deficit(b)), num(T.deficit_lb(b)), ...
        pct(T.deficit_lb(b) / T.deficit(b))); %#ok<AGROW>
end
end

function [r, n] = rate(rec, k)
n = sum(k); r = NaN;
if n > 0, r = mean(rec(k)); end
end

function t = row_txt(r, n)
% Recovered % and the episode count per column.
c = arrayfun(@(i) cell_txt(r(i), n(i)), 1:numel(r), 'UniformOutput', false);
t = strjoin(c, ' ');
end

function t = cell_txt(r, n)
if n == 0, t = '    -   (0)'; else, t = sprintf('%5.1f(%d)', 100 * r, n); end
end

function t = pct(x)
if isnan(x) || isinf(x), t = '-'; else, t = sprintf('%.1f%%', 100 * x); end
end

function t = num(x)
if isnan(x), t = '-'; else, t = sprintf('%.1f', x); end
end
