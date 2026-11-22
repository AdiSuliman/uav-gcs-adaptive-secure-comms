function S = side_d107_cells(agents_mat, out_dir)
%SIDE_D107_CELLS  D107's harmed geometries by (Eb/N0 index, r) cell, a labelled side reading.
%   S = side_d107_cells(agents_mat, out_dir)
%   agents_mat  data/aprime_agents.mat (variable aprime; opened read-only)
%   out_dir     a new folder; side_d107_cells.txt and .mat are written there
%   Per penalty, from the same per-episode readings aprime_admit.m uses (the seed-mean paired
%   difference, no-threat run minus grid run, on the recoverable threat episodes): the harmed
%   antenna_fault episodes grouped by geometry r (the registered grouping, 6) and by the 36
%   (Eb/N0 index s, r) cells, the count of harmed geometries and of harmed cells, the mean paired
%   difference of each, and the stricter reading of (b'): no cell below zero. The registered
%   (b) statistic is repeated with cluster key 1000*s + r (10000 resamples, seed 107, one-sided
%   p) and compared with the saved admission when the file holds it. Holm across penalties is
%   not repeated: this reading admits nothing.
if ~isfile(agents_mat), error('side_d107:input', 'side_d107_cells: %s not found', agents_mat); end
out = side_out_dir(out_dir, agents_mat);
B = 10000; SEED = 107; TOL = 1e-12;
S1 = {'antenna_fault', 'airframe_shadowing'};
notes = {['D107 point 5 side reading (clarification of 2.11.2026): the count of harmed geometries and the grouping by (Eb/N0 index, r), ' ...
    '36 cells, beside the registered (b'') that groups by r'], ...
    ['harmed = no response does not restore the geometry (aprime.episodes.harmed); episodes = the recoverable threat episodes of ' ...
    'the penalty''s runs; paired difference = seed-mean recovered of the no-threat run minus that of its grid run'], ...
    sprintf('stricter reading of (b''): a cell counts as negative when its mean difference is below -%g, and one negative cell fails; (b) uses %d resamples, seed %d', TOL, B, SEED)};
L = side_header('D107 harmed geometries by (Eb/N0 index, r) cells', agents_mat, notes);
Wm = load(agents_mat, 'aprime');
if ~isfield(Wm, 'aprime'), error('side_d107:field', 'side_d107_cells: %s holds no variable aprime', agents_mat); end
A = Wm.aprime;
if ~isfield(A, 'episodes') || ~isfield(A, 'runs'), error('side_d107:field', 'side_d107_cells: aprime has no episodes or runs'); end
E = A.episodes; R = A.runs;
if numel(unique([R.gamma])) ~= 1, error('side_d107:gamma', 'side_d107_cells: the runs are not of one discount factor'); end
thr = E.threat(:)'; harm = logical(E.harmed(:)'); sv = double(E.s(:)'); rv = double(E.r(:)'); cl = 1000 * sv + rv;
L{end+1} = sprintf('validation episodes: %d; harmed %d; Eb/N0 indices %s; geometries r %s', numel(thr), sum(harm), ...
    mat2str(unique(sv)), mat2str(unique(rv)));
pens = unique([R.pen]); np = numel(pens);
Q = cell(1, np); P = ones(1, np); X = cell(1, np);
for k = 1:np
    Rk = R([R.pen] == pens(k));
    rec = all(per_run(Rk, 'nothreat', 'recoverable') > 0 & per_run(Rk, 'plain', 'recoverable') > 0, 2)';
    isth = all(per_run(Rk, 'nothreat', 'threat') > 0 & per_run(Rk, 'plain', 'threat') > 0, 2)';
    mT = rec & isth;
    dm = mean(per_run(Rk, 'nothreat', 'recovered'), 2)' - mean(per_run(Rk, 'plain', 'recovered'), 2)';
    q = struct('pen', pens(k), 'nruns', numel(Rk));
    mb = mT & harm & ismember(thr, S1);
    [q.gain, Qk] = paired_stats('dist', dm(mb), cl(mb), B, SEED);
    Q{k} = Qk;
    if ~isempty(Qk), P(k) = (1 + sum(Qk <= 0)) / (B + 1); end
    q.p = P(k); q.n_gain = sum(mb); q.n_clusters = numel(unique(cl(mb)));
    for t = 1:numel(S1)
        m = mT & harm & strcmp(thr, S1{t});
        g = zeros(1, 0); gd = zeros(0, 1); gn = zeros(0, 1); c = zeros(1, 0); cd = zeros(0, 1); cn = zeros(0, 1);
        if any(m)
            [g, ~, gi] = unique(rv(m));
            gn = accumarray(gi(:), 1); gd = accumarray(gi(:), dm(m)') ./ gn;
            [c, ~, ci] = unique(cl(m));
            cn = accumarray(ci(:), 1); cd = accumarray(ci(:), dm(m)') ./ cn;
        end
        q.thr(t) = struct('threat', S1{t}, 'n', sum(m), 'geom', g(:)', 'geom_diff', gd(:)', 'geom_n', gn(:)', ...
            'cell_key', c(:)', 'cell_s', floor(c(:)' / 1000), 'cell_r', mod(c(:)', 1000), 'cell_diff', cd(:)', 'cell_n', cn(:)', ...
            'n_geom', numel(g), 'n_cells', numel(c), 'n_geom_neg', sum(gd < -TOL), 'n_cells_neg', sum(cd < -TOL), ...
            'bprime_geom', ~isempty(gd) && all(gd >= -TOL), 'bprime_cells', ~isempty(cd) && all(cd >= -TOL));
    end
    X{k} = q;
end
[pass, level, lb] = holm_lower(P, Q);
for k = 1:np
    q = X{k};
    L{end+1} = sprintf('penalty %d (%d runs, one discount factor):', q.pen, q.nruns); %#ok<AGROW>
    L{end+1} = sprintf('  (b) harmed S1 recovered, no-threat minus grid: %+.1f points over %d episodes in %d clusters (key 1000*s+r), one-sided p %.4f', ...
        100 * q.gain, q.n_gain, q.n_clusters, q.p); %#ok<AGROW>
    if isfield(A, 'admit') && numel(A.admit) >= k && isfield(A.admit, 'gain')
        a = A.admit(k);
        L{end+1} = sprintf('      saved admission: gain %+.1f points, %d episodes, %d clusters, p %.4f -> %s', 100 * a.gain, a.n_gain, ...
            a.n_clusters, a.p, ternary(abs(a.gain - q.gain) < 1e-12 && a.n_gain == q.n_gain && a.n_clusters == q.n_clusters && ...
            abs(a.p - q.p) < 1e-12, 'reproduced', 'NOT REPRODUCED')); %#ok<AGROW>
    else
        L{end+1} = '      the file holds no saved admission to compare with'; %#ok<AGROW>
    end
    for t = 1:numel(q.thr)
        h = q.thr(t);
        L{end+1} = sprintf('  %s: %d harmed recoverable episodes; harmed geometries r (registered grouping): %d of 6 [%s]; harmed (s, r) cells: %d of 36; negative: %d geometries, %d cells', ...
            h.threat, h.n, h.n_geom, num2str(h.geom), h.n_cells, h.n_geom_neg, h.n_cells_neg); %#ok<AGROW>
        L{end+1} = sprintf('    by r, paired difference in points (n): %s -> (b'') on geometries: %s', ...
            list(h.geom_diff, h.geom_n, h.geom), ternary(h.bprime_geom, 'none negative', 'a geometry is negative')); %#ok<AGROW>
        L{end+1} = sprintf('    by (s, r), paired difference in points (n): %s -> stricter on cells: %s', ...
            list(h.cell_diff, h.cell_n, arrayfun(@(a, b) a * 10 + b, h.cell_s, h.cell_r)), ...
            ternary(h.bprime_cells, 'none negative', 'a cell is negative')); %#ok<AGROW>
        L{end+1} = '    grid, rows Eb/N0 index s, columns r (difference in points, n in brackets; . = not harmed):'; %#ok<AGROW>
        L = [L, grid_lines(h, unique(sv), unique(rv))]; %#ok<AGROW>
    end
end
L{end+1} = '';
L{end+1} = 'a side reading: it admits nothing and moves no verdict; the registered (b'') groups by r';
S = struct('input', agents_mat, 'sha256', side_sha256(agents_mat), 'B', B, 'seed', SEED, 'tol', TOL, 'per_penalty', {X}, ...
    'holm_pass_not_used', pass, 'holm_level', level, 'holm_lb', lb);
side_write(out, 'side_d107_cells', L, S);
fprintf('%s\n', L{:});
end

function X = per_run(R, side, f)
c = arrayfun(@(r) double(r.(side).(f)(:)), R, 'UniformOutput', false);
X = [c{:}];
end

function s = list(d, n, key)
if isempty(d), s = 'none'; return; end
s = strjoin(arrayfun(@(i) sprintf('%d %+.1f (%d)', key(i), 100 * d(i), n(i)), 1:numel(d), 'UniformOutput', false), ', ');
end

function G = grid_lines(h, sl, rl)
G = cell(1, numel(sl));
for i = 1:numel(sl)
    c = cell(1, numel(rl));
    for j = 1:numel(rl)
        f = find(h.cell_s == sl(i) & h.cell_r == rl(j), 1);
        if isempty(f), c{j} = sprintf('%12s', '.'); else, c{j} = sprintf('%+7.1f (%2d)', 100 * h.cell_diff(f), h.cell_n(f)); end
    end
    G{i} = sprintf('      s %d | %s', sl(i), strjoin(c, ' '));
end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
