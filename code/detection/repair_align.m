function R = repair_align(f, dry)
%REPAIR_ALIGN  One-off repair of an A5 dataset whose 'align' holds both the flight draw and
%   the measurement (run_dataset_sweep.m before the draw was named align_gcs): every
%   sub-run appended its draw d.align(1) for its n frames, then its measured F.align for the
%   same n frames, to the same field, so dataset.align and dataset.meas.align hold 2N values,
%   per sub-run in stored order [draw x n, measurement x n].
%   R = repair_align(f)          f: 'data/dataset.mat' (default) or 'data/dataset_fresh.mat'
%   R = repair_align(f, true)    dry run: checks the layout, writes nothing (reads the
%                                fields alone from a -v7.3 file)
%   The layout is checked in every sub-run (the first n values one constant draw; the
%   measurement's spread reported) before anything is written; then dataset.meas.align
%   holds the measurement and dataset.align_gcs the draw (N values each), dataset.align is
%   removed and dataset.meta.align_repair records the repair. The file is saved to a new
%   file first; the original is kept as <name>_before_align_repair.mat (never deleted), and
%   an existing backup stops the repair. A dataset already in the new layout is left as it
%   is (R.state 'already').
%   R: file, state ('repaired', 'already', 'checked'), n_frames, n_runs, runs_const (sub-runs
%   whose first n values are constant), runs_vary (whose last n values are not), backup
if nargin < 1 || isempty(f), f = 'data/dataset.mat'; end
if nargin < 2, dry = false; end
R = struct('file', f, 'state', '', 'n_frames', NaN, 'n_runs', NaN, 'runs_const', NaN, 'runs_vary', NaN, 'backup', '');
if ~isfile(f), error('repair_align:file', '%s not found', f); end
if dry
    get = reader(f);
    run = get('run'); A = get('meas/align');
    A2 = []; if has(f, 'align'), A2 = get('align'); end
    hasg = has(f, 'align_gcs');
else
    L = load(f, 'dataset'); ds = L.dataset; clear L
    run = ds.run; A = ds.meas.align;
    A2 = []; if isfield(ds, 'align'), A2 = ds.align; end
    hasg = isfield(ds, 'align_gcs');
end
run = run(:); A = A(:); N = numel(run);
R.n_frames = N;
if numel(A) == N && isempty(A2) && hasg
    R.state = 'already';
    fprintf('%s: already repaired (%d frames)\n', f, N);
    return
end
if numel(A) ~= 2 * N || (~isempty(A2) && ~isequal(A2(:), A))
    error('repair_align:layout', '%s: meas.align holds %d values for %d frames (and align %d); not the 2N layout', ...
        f, numel(A), N, numel(A2));
end
[draw, meas, nc, nv, nr] = split_runs(run, A);
R.n_runs = nr; R.runs_const = nc; R.runs_vary = nv;
fprintf('%s: %d frames, %d sub-runs; the first n values constant in %d (%.2f%%), the last n varying in %d (%.2f%%)\n', ...
    f, N, nr, nc, 100 * nc / nr, nv, 100 * nv / nr);
if nc ~= nr
    error('repair_align:layout', '%s: the first n values are not one draw in %d of %d sub-runs; nothing written', f, nr - nc, nr);
end
if dry
    R.state = 'checked';
    return
end
ds.meas.align = meas; ds.align_gcs = draw;
if isfield(ds, 'align'), ds = rmfield(ds, 'align'); end
ds.meta.align_repair = sprintf(['%s: meas.align and align_gcs split from the 2N field align (%d sub-runs, ' ...
    'repair_align.m)'], datestr(now), nr);
[dd, nm] = fileparts(f);
bak = fullfile(dd, [nm '_before_align_repair.mat']); tmp = fullfile(dd, [nm '_align_repair_tmp.mat']);
if isfile(bak), error('repair_align:backup', '%s exists: the dataset was repaired before or the backup is in the way', bak); end
dataset = ds; clear ds %#ok<NASGU>
save(tmp, 'dataset', '-v7.3');
clear dataset
chk = reader(tmp);
if numel(chk('meas/align')) ~= N || numel(chk('align_gcs')) ~= N || has(tmp, 'align')
    error('repair_align:write', '%s does not hold the repaired fields; the original is untouched', tmp);
end
[ok, msg] = movefile(f, bak);
if ~ok, error('repair_align:backup', 'no backup of %s: %s', f, msg); end
[ok, msg] = movefile(tmp, f);
if ~ok, error('repair_align:write', '%s not moved to %s (the original is %s): %s', tmp, f, bak, msg); end
R.state = 'repaired'; R.backup = bak;
fprintf('%s repaired; the original kept as %s\n', f, bak);
end

function [draw, meas, nc, nv, nr] = split_runs(run, A)
% Per sub-run in stored order (its frames contiguous), the n values at 2 x the frames
% before it: the first n the draw, the last n the measurement.
N = numel(run);
b = [1; find(diff(run) ~= 0) + 1]; e = [b(2:end) - 1; N];
if numel(unique(run)) ~= numel(b)
    error('repair_align:runs', 'the frames of a sub-run are not contiguous');
end
nr = numel(b); draw = nan(N, 1); meas = nan(N, 1); nc = 0; nv = 0;
for r = 1:nr
    n = e(r) - b(r) + 1; o = 2 * (b(r) - 1);
    d = A(o + (1:n)); m = A(o + n + (1:n));
    nc = nc + all(d == d(1));
    nv = nv + (n > 1 && any(m ~= m(1)));
    draw(b(r):e(r)) = d; meas(b(r):e(r)) = m;
end
end

function get = reader(f)
% Fields of the struct 'dataset' of a -v7.3 MAT file without loading it.
get = @(name) reshape(h5read(f, ['/dataset/' name]), [], 1);
end

function y = has(f, name)
% Whether the struct 'dataset' of a -v7.3 MAT file has the field name.
I = h5info(f, '/dataset');
y = any(strcmp({I.Datasets.Name}, name)) || any(strcmp(arrayfun(@(g) g.Name(find(g.Name == '/', 1, 'last') + 1:end), ...
    I.Groups, 'UniformOutput', false), name));
end
