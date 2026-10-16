function T = ood_thresholds(retain)
%OOD_THRESHOLDS  Unknown-threat thresholds for the production detector.
%   Chosen on the validation split so that a fraction RETAIN (default 0.95) of
%   known-class frames stays above the threshold: a frame scoring below it is
%   treated as an unknown threat. MSP and energy from cnn_scores.m, per frame. The
%   unknown-threat score (ood_scores.m, the production candidate chosen by
%   eval_ood_detection.m) on the statistic the decision cycle compares with the
%   threshold (policy_monitor.m): its mean over the last ood.win cycles of the frame's
%   sub-run, partial windows at the start (ood_window.m); T.maha_frame is the same
%   quantile of the per-frame score. T.maha_val holds the sorted validation values of
%   that statistic, so any other retention level is a quantile of it (demo_gui.m
%   slider). Cached in data/ood_thresholds.mat and recomputed when the detector is newer
%   or its score or window differ.
if nargin < 1, retain = 0.95; end
cache = 'data/ood_thresholds.mat';
D = load('data/trained_detector.mat', 'ood');
W = 1; if isfield(D.ood, 'win') && ~isempty(D.ood.win), W = D.ood.win; end
if isfile(cache) && dir(cache).datenum >= dir('data/trained_detector.mat').datenum
    C = load(cache, 'T');
    if isfield(C.T, 'retain') && C.T.retain == retain && isfield(C.T, 'maha_val') && isfield(C.T, 'win') ...
            && C.T.win == W && strcmp(C.T.score, D.ood.score)
        T = C.T; return;
    end
end
D = load('data/trained_detector.mat', 'net', 'ood');
S = load('data/splits.mat', 'splits'); va = S.splits.val; clear S
[~, ~, msp, en] = cnn_scores(D.net, va.X, va.feats');
mh = ood_scores(D.net, D.ood, va.X, va.feats');
pos = []; if isfield(va, 'pos'), pos = va.pos; end
mw = ood_window(mh, va.run, pos, W);
T = struct('retain', retain, 'msp', lowq(msp, 1 - retain), 'energy', lowq(en, 1 - retain), ...
    'maha', lowq(mw, 1 - retain), 'maha_val', sort(mw(:)), 'maha_frame', lowq(mh, 1 - retain), ...
    'win', W, 'score', D.ood.score, 'n_val', numel(msp));
save(cache, 'T');
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
