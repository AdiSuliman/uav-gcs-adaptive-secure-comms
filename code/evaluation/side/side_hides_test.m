function S = side_hides_test(tree, out_dir)
%SIDE_HIDES_TEST  D121 item 15 on the clean test pools: the share of clean flights in a hiding geometry.
%   S = side_hides_test(tree, out_dir)
%   tree     a result tree; reads <tree>/data/clean_test_pools.mat (CT.cov, CT.ebno) and <tree>/params.mat
%   out_dir  a new folder; side_hides_test.txt and .mat are written there
%   The geometry-only share of the clean test flights that meet the hiding condition shadow_spec would
%   apply (clean_hides.m at the nominal airframe-shadowing level, no loss applied), over all Eb/N0 rows
%   and per row, with 95% intervals: a bootstrap over flights (kpi6_split.m's cluster key 1000*s + r,
%   2000 resamples, seed 6108), the same over the flight seeds (a seed shared across rows is one cluster,
%   the wider reading), and Clopper-Pearson (flights independent). KPI 6's false-alarm share on those
%   flights needs the per-episode flags of the KPI 6 pass, which no saved file holds; it is not read.
f = fullfile(tree, 'data', 'clean_test_pools.mat');
pf = fullfile(tree, 'params.mat');
for q = {f, pf}
    if ~isfile(q{1}), error('side_hides:input', 'side_hides_test: %s not found', q{1}); end
end
out = side_out_dir(out_dir, {f, pf});
notes = {['D121 item 15: clean flights never get the hidden-antenna loss; this is the share whose geometry meets the hiding condition ' ...
    '(hides_antenna.m on the flight''s own draws, airframe shadowing at the nominal level, geometry only)'], ...
    sprintf('params: %s (the tree''s own); decision_config.m, clean_hides.m and hides_antenna.m: this checkout', pf), ...
    'intervals: 95% bootstrap over flights (cluster 1000*s + r, seed 6108), over flight seeds (seed 6109), Clopper-Pearson (independent)'};
L = side_header('D121 item 15 clean test flights meeting the hiding condition', f, notes);
w = whos('-file', f);
L{end+1} = sprintf('variables in the file: %s', strjoin(arrayfun(@(x) sprintf('%s (%.1f MB)', x.name, x.bytes / 2^20), w, ...
    'UniformOutput', false), ', '));
how = '';
try
    mf = matfile(f);
    cv = mf.CT.cov; eb = mf.CT.ebno;
    how = 'CT.cov and CT.ebno by matfile field access; the pools were not loaded';
catch
    cv = []; eb = [];
end
if isempty(cv)
    W = load(f, 'CT');
    cv = W.CT.cov; eb = W.CT.ebno;
    clear W
    how = 'the variable CT was loaded whole (the file cannot be read by field), only cov and ebno kept';
end
L{end+1} = ['loaded: ' how];
need = {'seed', 'speed', 'alt_m', 'k_sig', 'aoa', 'rho'};
miss = need(~isfield(cv, need));
if ~isempty(miss)
    L{end+1} = sprintf('FIELD ABSENT in CT.cov: %s; nothing read', strjoin(miss, ', '));
    side_write(out, 'side_hides_test', L);
    fprintf('%s\n', L{:});
    error('side_hides:field', 'side_hides_test: CT.cov lacks %s', strjoin(miss, ', '));
end
eb = double(eb(:)');
P0 = load(pf); p0 = P0.params; p0.quiet_build = true;
C = decision_config();
lvl = C.sev.airframe_shadowing.levels(C.nominal);
H = clean_hides(cv, eb, p0, lvl, C.event_frame, C.event_count);
ok = isfinite(cv.seed);
[sg, rg] = ndgrid(1:size(H, 1), 1:size(H, 2));
h = double(H(ok))'; key = 1000 * sg(ok)' + rg(ok)'; sd = double(cv.seed(ok))';
n = numel(h); k = sum(h);
L{end+1} = sprintf('clean test flights with draws: %d (%d Eb/N0 rows x up to %d flights); nominal shadowing level %g dB', n, size(H, 1), ...
    size(H, 2), lvl);
[m1, lo1, hi1] = boot_cluster(h, ones(1, n), key, 2000, 6108);
[m2, lo2, hi2] = boot_cluster(h, ones(1, n), sd, 2000, 6109);
[c1, c2] = side_cp(k, n);
L{end+1} = sprintf('share meeting the hiding condition: %d/%d = %.1f%%; bootstrap over flights [%.1f, %.1f] (%d clusters); over flight seeds [%.1f, %.1f] (%d clusters); Clopper-Pearson [%.1f, %.1f]', ...
    k, n, 100 * m1, 100 * lo1, 100 * hi1, numel(unique(key)), 100 * lo2, 100 * hi2, numel(unique(sd)), 100 * c1, 100 * c2);
rows = struct('ebno', {}, 'n', {}, 'k', {}, 'cp', {});
for s = 1:size(H, 1)
    o = ok(s, :); ns = sum(o); ks = sum(H(s, o));
    [a, b] = side_cp(ks, ns);
    rows(end+1) = struct('ebno', eb(s), 'n', ns, 'k', ks, 'cp', [a b]); %#ok<AGROW>
    L{end+1} = sprintf('  Eb/N0 %g dB: %d/%d = %.1f%% [%.1f, %.1f] (Clopper-Pearson)', eb(s), ks, ns, 100 * ks / max(ns, 1), 100 * a, 100 * b); %#ok<AGROW>
end
L{end+1} = '';
L{end+1} = 'KPI 6 false-alarm share on these flights and on the rest: not read (no saved per-episode flags of the KPI 6 pass)';
L{end+1} = 'side reading, decides nothing; a clean flight in a hiding geometry is cleaner than physics, so the clean false-alarm reading is optimistic, not harsh';
S = struct('input', f, 'sha256', side_sha256(f), 'loaded', how, 'n', n, 'k', k, 'share', [m1 lo1 hi1], 'share_seed_cluster', [m2 lo2 hi2], ...
    'cp', [c1 c2], 'rows', rows, 'hides', H, 'level_db', lvl);
side_write(out, 'side_hides_test', L, S);
fprintf('%s\n', L{:});
end
