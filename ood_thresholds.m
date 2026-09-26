function T = ood_thresholds(retain)
%OOD_THRESHOLDS  Unknown-threat thresholds for the production detector (D32, D44).
%   Chosen on the validation split so that a fraction RETAIN (default 0.95) of
%   known-class frames stays above the threshold: a frame scoring below it is
%   treated as an unknown threat. MSP and energy from cnn_scores.m, Mahalanobis
%   from ood_scores.m (the production score since D44). T.maha_val holds the
%   sorted validation Mahalanobis scores, so any other retention level is a
%   quantile of it (demo_gui.m slider). Cached in data/ood_thresholds.mat and
%   recomputed when the detector is newer.
if nargin < 1, retain = 0.95; end
cache = 'data/ood_thresholds.mat';
if isfile(cache) && dir(cache).datenum >= dir('data/trained_detector.mat').datenum
    C = load(cache, 'T');
    if isfield(C.T, 'retain') && C.T.retain == retain && isfield(C.T, 'maha_val'), T = C.T; return; end
end
D = load('data/trained_detector.mat', 'net', 'ood');
S = load('data/splits.mat', 'splits');
[~, ~, msp, en] = cnn_scores(D.net, S.splits.val.X, S.splits.val.feats');
mh = ood_scores(D.net, D.ood, S.splits.val.X, S.splits.val.feats');
T = struct('retain', retain, 'msp', lowq(msp, 1 - retain), 'energy', lowq(en, 1 - retain), ...
    'maha', lowq(mh, 1 - retain), 'maha_val', sort(mh(:)), 'n_val', numel(msp));
save(cache, 'T');
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
