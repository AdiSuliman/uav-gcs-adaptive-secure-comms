function S = side_a7_hover_edge(edge_mat, budget_txt, out_dir)
%SIDE_A7_HOVER_EDGE  C2: the hover column of the edge map per Eb/N0, as distance, a labelled side reading.
%   S = side_a7_hover_edge(edge_mat, budget_txt, out_dir)
%   edge_mat    a profile's results/edge_map.mat (EM, FT, VAR; opened read-only)
%   budget_txt  the same profile's results/link_budget.txt (the tracked-antenna ground range per Eb/N0, 15 m row)
%   out_dir     a new folder; side_a7_hover_edge.txt and .mat are written there
%   edge_map.m pools the hover flights over every Eb/N0 from the KPI 1 threshold up (one band per threat level); no
%   verdict per single Eb/N0 is saved. Here the same verdict functions (det_layers, surv_layer, edge_verdict with the
%   saved targets and B) are replayed on the saved hover flights of each (threat, level, Eb/N0): DET, SURV, REC, PROT
%   and SYSTEM = DET, SURV, REC and the false-alarm bound. The pooled replay is compared with the saved band verdicts.
%   COMMITTED needs at least n_min flights (36): a single Eb/N0 holds fewer hover flights, so it can end only
%   UNDETERMINED or NOT COMMITTED. A pooled COMMITTED claim holds on the hover flights pooled over every Eb/N0 from the
%   threshold up, so it covers that distance range as a whole, with no claim at any single distance in it.
%   REC and PROT are read as edge_map.m reads them: per flight unless the saved targets set held_flight (held_verdict.m).
if ~isfile(edge_mat), error('side_a7:input', 'side_a7_hover_edge: %s not found', edge_mat); end
if ~isfile(budget_txt), error('side_a7:input', 'side_a7_hover_edge: %s not found', budget_txt); end
w = {whos('-file', edge_mat).name};
miss = setdiff({'EM', 'FT', 'VAR'}, w);
if ~isempty(miss), error('side_a7:field', 'side_a7_hover_edge: %s holds no variable %s', edge_mat, strjoin(miss, ', ')); end
W = load(edge_mat, 'EM', 'FT', 'VAR');
EM = W.EM; FT = W.FT; VAR = W.VAR;
BD = EM.bands(:)';
ie = find(strcmp({BD.axis}, 'edge'));
if isempty(ie), error('side_a7:field', 'side_a7_hover_edge: the edge map holds no edge-speed band'); end
[~, ih] = min([BD(ie).lo]);
bh = BD(ie(ih));
% the edge-speed split: the flight set whose speeds are exactly the edge bands' speeds
sp_all = unique(FT.sp(:))';
SPEED = NaN;
for q = sp_all
    sv = FT.speed(FT.sp == q);
    if ~isempty(sv) && all(ismember(sv(~isnan(sv)), [BD(ie).lo]))
        SPEED = q;
    end
end
if isnan(SPEED), error('side_a7:field', 'side_a7_hover_edge: no flight set at the edge speeds'); end
TGT = EM.targets; B = EM.B;
v1 = find(strcmp({VAR.kind}, 'static') & arrayfun(@(x) isequaln(x.fd, NaN), VAR) & [VAR.D] == EM.delays(1) & [VAR.pol] == 1, 1);
if isempty(v1), error('side_a7:field', 'side_a7_hover_edge: no static variant at the deployed delay'); end
FAV = double(EM.fa_bound_met);
eb = EM.ebno(:)'; nS = numel(eb); km = EM.km(:)';
txtkm = budget_km(budget_txt, 15);
dkm = max(abs(txtkm - km));
nT = numel(EM.cells);
ib = find(strcmp({BD.name}, bh.name), 1);
notes = {sprintf('hover band: %s (edge-speed split, flight set %d); deployed policy column %d of the static variants at delay %g cycles', bh.name, SPEED, v1, EM.delays(1)), ...
    sprintf('targets %s; B = %d bootstrap resamples; false-alarm bound met on validation: %d', targets_txt(TGT), B, FAV), ...
    sprintf('distance: EM.km (link_distance_km.m, tracked antenna) against %s, 15 m row: largest difference %.3f km', budget_txt, dkm), ...
    sprintf('pooled hover band: Eb/N0 >= %g dB (EM.ebno_thr), %.2f-%.2f km; a pooled COMMITTED claim holds on that range as a whole, not at each distance in it', EM.ebno_thr, min(km(eb >= EM.ebno_thr)), max(km(eb >= EM.ebno_thr))), ...
    sprintf('REC and PROT read per flight: %d (saved targets: held_flight %s)', hf_of(TGT), field_txt(TGT, 'held_flight'))};
L = side_header('C2: hover per Eb/N0 as distance (edge map)', edge_mat, notes);
L{end+1} = sprintf('Eb/N0 [dB] and distance [km]: %s', strjoin(arrayfun(@(e, k) sprintf('%g dB %.2f km', e, k), eb, km, 'UniformOutput', false), ' | '));
L{end+1} = 'Symbols: C COMMITTED, U UNDETERMINED, N NOT COMMITTED, - no hover flight. Layers D S R P = DET, SURV, REC, PROT; SYS = SYSTEM.';
L{end+1} = '';
rows = struct('label', {}, 'n', {}, 'v', {}, 'pooled', {}, 'pooled_saved', {}, 'pooled_saved_commit', {});
mism = 0; npool = 0;
for i = 1:nT
    c = EM.cells(i);
    base = FT.c == c & FT.sp == SPEED & in_band(FT, bh);
    if ~any(base), continue; end
    v = nan(5, nS); nfl = zeros(1, nS);
    for s = 1:nS
        F = take_rows(FT, base & abs(FT.eb - eb(s)) < 1e-9);
        nfl(s) = numel(unique(F.geo));
        if nfl(s) > 0, v(:, s) = layers(F, v1, TGT, B, FAV); end
    end
    F = take_rows(FT, base & FT.eb >= EM.ebno_thr - 1e-9);
    vp = layers(F, v1, TGT, B, FAV);
    saved = [EM.bt.det(i, ib).verdict; EM.bt.surv(i, ib).verdict; EM.bt.rec(i, ib).verdict; EM.bt.prot(i, ib).verdict; EM.bt.sys(i, ib)];
    npool = npool + 1; mism = mism + any(vp ~= saved);
    rows(end+1) = struct('label', EM.labels{i}, 'n', nfl, 'v', v, 'pooled', vp, 'pooled_saved', saved, ...
        'pooled_saved_commit', EM.bt.commit(i, ib)); %#ok<AGROW>
end
L{end+1} = sprintf('Replay of the pooled hover band against the saved band verdicts (DET, SURV, REC, PROT, SYSTEM): %d of %d (threat, level) rows differ', mism, npool);
L{end+1} = '';
L{end+1} = sprintf('%-28s %6s | %s | pooled [D S R P SYS] (saved SYS, saved COMMITTED)', 'threat level', 'flts', ...
    strjoin(arrayfun(@(e) sprintf('%2g dB  D S R P SYS', e), eb, 'UniformOutput', false), ' | '));
for r = rows
    c = arrayfun(@(s) col_txt(r.v(:, s)), 1:nS, 'UniformOutput', false);
    L{end+1} = sprintf('%-28s %6d | %s | %s (%s, %s)', r.label, max(r.n), strjoin(c, ' | '), sym5(r.pooled), vs(r.pooled_saved(5)), vs(r.pooled_saved_commit)); %#ok<AGROW>
end
L{end+1} = '';
names = {'DET', 'SURV', 'REC', 'PROT', 'SYSTEM'};
L{end+1} = 'Largest distance with a COMMITTED hover verdict, by layer (per Eb/N0 replay | pooled band: the range it covers as a whole):';
best = nan(5, 2);
for k = 1:5
    dk = nan; dp = nan;
    for r = rows
        for s = find(r.v(k, :) == 1), dk = max([dk km(s)]); end
        if r.pooled(k) == 1, dp = max([dp km(eb == EM.ebno_thr)]); end
    end
    best(k, :) = [dk dp];
    if isnan(dp), ptx = 'none'; else, ptx = sprintf('%.2f-%.2f km as a whole (%d rows)', min(km(eb >= EM.ebno_thr)), dp, sum(arrayfun(@(r) r.pooled(k) == 1, rows))); end
    L{end+1} = sprintf('  %-7s per Eb/N0: %s | pooled: %s', names{k}, km_txt(dk), ptx); %#ok<AGROW>
end
nfl_all = unique(cell2mat(arrayfun(@(r) r.n(r.n > 0), rows, 'UniformOutput', false)));
L{end+1} = sprintf('Hover flights per (threat, level, Eb/N0): %s (COMMITTED needs at least %d)', mat2str(nfl_all), 36);
nc = sum(arrayfun(@(r) sum(r.v(5, :) == 1), rows));
L{end+1} = sprintf('Per Eb/N0 SYSTEM COMMITTED points: %d of %d replayed (threat, level, Eb/N0) points', nc, sum(arrayfun(@(r) sum(~isnan(r.v(5, :))), rows)));
pooled_c = rows(arrayfun(@(r) r.pooled(5) == 1, rows));
if isempty(pooled_c)
    L{end+1} = 'Pooled hover SYSTEM COMMITTED rows: none';
else
    L{end+1} = sprintf('Pooled hover SYSTEM COMMITTED rows (every Eb/N0 from %g dB up): %s', EM.ebno_thr, strjoin({pooled_c.label}, ', '));
end
S = struct('input', edge_mat, 'sha256', side_sha256(edge_mat), 'ebno', eb, 'km', km, 'km_text', txtkm, 'rows', rows, ...
    'best_km', best, 'layers', {names}, 'replay_rows', npool, 'replay_mismatch', mism);
out = side_out_dir(out_dir, edge_mat);
side_write(out, 'side_a7_hover_edge', L, S);
fprintf('%s\n', L{:});
end

function v = layers(F, v1, TGT, B, FAV)
% DET, SURV, REC, PROT, SYSTEM verdicts of edge_map.m over the flights F.
det = det_layers(F, TGT, B);
sv = surv_layer(F, 'surv', TGT, B);
s = logical(F.surv);
hf = hf_of(TGT);
rec = held_verdict(F.held_k(s, v1), F.ep_n(s, v1), F.geo(s), TGT.rec, hf, B);
prot = held_verdict(F.held_k(:, v1), F.ep_n(:, v1), F.geo, TGT.prot, hf, B);
p = [det.verdict, sv.verdict, rec.verdict, prot.verdict];
sysv = [p(1:3), FAV];
if all(sysv == 1), y = 1; elseif any(sysv == -1), y = -1; else, y = 0; end
v = [p(:); y];
end

function hf = hf_of(TGT)
% Per-flight held reading unless the saved targets say otherwise (edge_map.m pol_layers).
hf = true;
if isfield(TGT, 'held_flight'), hf = logical(TGT.held_flight); end
end

function s = field_txt(T, f)
if isfield(T, f), s = mat2str(T.(f)); else, s = 'not saved'; end
end

function m = in_band(F, b)
x = F.speed;
m = x >= b.lo & (x < b.hi | (b.top & x <= b.hi));
end

function S = take_rows(S, m)
f = fieldnames(S);
for i = 1:numel(f), S.(f{i}) = S.(f{i})(m, :); end
end

function s = col_txt(v)
if all(isnan(v)), s = '-         '; else, s = sprintf('%s %s %s %s %s', sym(v(1)), sym(v(2)), sym(v(3)), sym(v(4)), sym(v(5))); s = [s '  ']; end
end

function s = sym5(v)
s = sprintf('%s %s %s %s %s', sym(v(1)), sym(v(2)), sym(v(3)), sym(v(4)), sym(v(5)));
end

function s = sym(x)
if isnan(x), s = '-'; else, t = 'NUC'; s = t(x + 2); end
end

function s = vs(x)
s = sym(x);
end

function s = km_txt(x)
if isnan(x), s = 'none'; else, s = sprintf('%.2f km', x); end
end

function s = targets_txt(T)
f = fieldnames(T);
s = strjoin(cellfun(@(k) sprintf('%s %g', k, T.(k)), f', 'UniformOutput', false), ', ');
end

function k = budget_km(f, alt)
% The tracked antenna's ground range per Eb/N0 at the altitude alt [m], from link_budget.txt.
t = splitlines(fileread(f));
h = find(contains(t, 'Ground range of profile A tracked'), 1);
if isempty(h), error('side_a7:budget', 'side_a7_hover_edge: %s has no ground-range table', f); end
for i = h + 1:numel(t)
    tok = regexp(t{i}, '^\s*(\d+) m\s+(.*)$', 'tokens', 'once');
    if ~isempty(tok) && str2double(tok{1}) == alt
        k = sscanf(tok{2}, '%f')';
        return
    end
end
error('side_a7:budget', 'side_a7_hover_edge: %s has no %d m row in the ground-range table', f, alt);
end
