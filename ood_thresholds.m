function T = ood_thresholds(retain)
%OOD_THRESHOLDS  Unknown-threat thresholds for the production detector (D32).
%   Chosen on the validation split so that a fraction RETAIN (default 0.95) of
%   known-class samples stays above the threshold: a frame scoring below it is
%   treated as an unknown threat. Cached in data/ood_thresholds.mat and recomputed
%   when the detector is newer than the cache.
if nargin < 1, retain = 0.95; end
cache = 'data/ood_thresholds.mat';
if isfile(cache) && dir(cache).datenum >= dir('data/trained_detector.mat').datenum
    C = load(cache, 'T');
    if isfield(C.T, 'retain') && C.T.retain == retain, T = C.T; return; end
end
D = load('data/trained_detector.mat', 'net');
S = load('data/splits.mat', 'splits');
[~, ~, msp, en] = cnn_scores(D.net, S.splits.val.X, S.splits.val.feats');
T = struct('retain', retain, 'msp', lowq(msp, 1 - retain), 'energy', lowq(en, 1 - retain), ...
    'n_val', numel(msp));
save(cache, 'T');
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
