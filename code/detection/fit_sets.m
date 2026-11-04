function [fs, info] = fit_sets(va, te, net, classes, root)
%FIT_SETS  The enlarged fit set of the fusion's further columns (select_fusion.m with
%   FUSION_REV and FUSION_FIT = 'enlarged'): the validation split, the first test split and the
%   second and third test sets, whose readings are spent; KPI 1 is then read on a test set
%   built after the fusion.
%   [fs, info] = fit_sets(va, te, net, classes)
%   va, te   the validation and test splits of data/splits.mat (va with y, the per-cycle
%            label index, and P, its probabilities, when already scored); net the detector
%            (cnn_scores.m); classes its class names
%   root     repository folder (default '.'): data/dataset.mat, splits_fresh.mat,
%            dataset_fresh.mat, splits_fresh2.mat, dataset_fresh2.mat are read by HDF5, the
%            test sets' images in blocks, never whole
%   fs       the sets one after the other, validation first: run (a key per sub-run: the set's
%            offset k * 1e7 plus its run id, so no sub-run of two sets shares one), pos,
%            gain_ant, feats_raw, idle, bch, level, ebno, ebno_rx, k_db, speed, y (the
%            per-cycle label, dataset.mat), P (the detector's probabilities), set (1-4)
%   info     per set: name, frames, sub-runs
%   The labels are the datasets' per-cycle labels (threat_active.m), in the class order of
%   the validation split's (checked).
if nargin < 5, root = '.'; end
F = {'run', 'pos', 'gain_ant', 'feats_raw', 'idle', 'bch', 'level', 'ebno', 'ebno_rx', 'k_db', 'speed'};
g = fullfile(root, 'data', 'dataset.mat');
fo = double(h5read(g, '/dataset/fold')); fo = fo(:); lab = double(h5read(g, '/dataset/label')); lab = lab(:);
assert(isequal(lab(fo == 5), double(va.y(:))), 'fit_sets: dataset.mat labels of the validation fold differ from the split''s');
if isfield(va, 'P'), P = va.P; else, P = cnn_scores(net, va.X, va.feats')'; end
fs = take(va, F, 0, 1); fs.y = double(va.y(:)); fs.P = P;
Pt = cnn_scores(net, te.X, te.feats')';
t = take(te, F, 1e7, 2); t.y = lab(fo == 6); t.P = Pt;
order(t, g, fo == 6);
fs = cat_sets(fs, t);
for k = 1:2
    f = fullfile(root, 'data', sprintf('splits_fresh%s.mat', pick(k == 2, '2', '')));
    h = fullfile(root, 'data', sprintf('dataset_fresh%s.mat', pick(k == 2, '2', '')));
    s = struct();
    for c = F
        x = h5read(f, ['/splits/test/' c{1}]);
        if isvector(x), x = x(:); end
        s.(c{1}) = x;
    end
    n = numel(s.run);
    for c = F, if size(s.(c{1}), 1) ~= n, s.(c{1}) = s.(c{1})'; end, end
    ft = h5read(f, '/splits/test/feats'); if size(ft, 1) ~= n, ft = ft'; end
    Ps = zeros(n, numel(classes));
    for i0 = 1:4096:n
        j = i0:min(i0 + 4095, n);
        Ps(j, :) = cnn_scores(net, h5read(f, '/splits/test/X', [1 1 1 i0], [128 128 1 numel(j)]), double(ft(j, :))')';
    end
    t = take(s, F, (k + 1) * 1e7, k + 2);
    yl = double(h5read(h, '/dataset/label')); t.y = yl(:); t.P = Ps;
    order(t, h, true(n, 1));
    fs = cat_sets(fs, t);
end
names = {'validation', 'first test split', 'second test set', 'third test set'};
info = struct('name', names, 'frames', num2cell(accumarray(fs.set, 1, [4 1])'), ...
    'subruns', num2cell(arrayfun(@(k) numel(unique(fs.run(fs.set == k))), 1:4)));
end

function t = take(s, F, off, k)
% The fields F of split s as stored, the run key offset, the set index.
t = struct();
for c = F
    x = s.(c{1}); if isvector(x), x = x(:); end
    t.(c{1}) = x;
end
t.run = double(t.run) + off; t.pos = double(t.pos); t.set = k * ones(numel(t.run), 1);
end

function order(t, g, m)
% The split's frames are the dataset's (fold mask m) in the same order.
r = double(h5read(g, '/dataset/run')); p = double(h5read(g, '/dataset/pos')); r = r(:); p = p(:);
assert(isequal(mod(t.run, 1e7), r(m)) && isequal(t.pos, p(m)), 'fit_sets: %s and its split differ in order', g);
end

function a = cat_sets(a, b)
for c = fieldnames(a)', a.(c{1}) = [a.(c{1}); b.(c{1})]; end
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end
