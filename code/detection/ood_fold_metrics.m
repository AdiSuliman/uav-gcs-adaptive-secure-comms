function Q = ood_fold_metrics(Sv, V, St, T, names, wins, retain)
%OOD_FOLD_METRICS  One held-out threat of eval_ood_detection.m: every unknown-threat score
%   and window read as the decision cycle reads it, the mean over the last W cycles of
%   each sub-run in time order (ood_window.m), every window labelled by its newest frame.
%   Q = ood_fold_metrics(Sv, V, St, T, names, wins, retain)
%   Sv, St   per-frame scores, one field per name (1 x frames), on the validation and on
%            the test frames
%   V, T     run, pos (frames' sub-runs and positions) and the windows read as known (kn:
%            the newest frame of a known class) and as unknown (un: the newest frame of the
%            held-out threat), on the validation and on the test frames
%   names    scores; wins  windows [cycles] (1 = the frame alone)
%   retain   share of the known validation windows kept above the threshold
%   Q        names x windows: val, AUROC on the validation frames (the selection's input);
%            test, AUROC on the test frames; fpr, share of the test unknown windows accepted
%            as known at the threshold that keeps retain of the known validation windows;
%            thr, that threshold
nS = numel(names); nW = numel(wins);
Q = struct('names', {names}, 'wins', wins, 'val', nan(nS, nW), 'test', nan(nS, nW), 'fpr', nan(nS, nW), ...
    'thr', nan(nS, nW), 'n', [sum(V.kn) sum(V.un) sum(T.kn) sum(T.un)]);
for j = 1:nS
    for w = 1:nW
        v = ood_window(Sv.(names{j}), V.run, V.pos, wins(w));
        t = ood_window(St.(names{j}), T.run, T.pos, wins(w));
        Q.val(j, w) = auroc(v(V.kn), v(V.un));
        Q.test(j, w) = auroc(t(T.kn), t(T.un));
        Q.thr(j, w) = lowq(v(V.kn), 1 - retain);
        Q.fpr(j, w) = mean(t(T.un) >= Q.thr(j, w));
    end
end
end

function a = auroc(pos, neg)
% Probability that a known window scores above an unknown one (ties count half).
pos = pos(:); neg = neg(:);
np = numel(pos); nn = numel(neg);
if np == 0 || nn == 0, a = NaN; return; end
r = tiedrank([pos; neg]);
a = (sum(r(1:np)) - np * (np + 1) / 2) / (np * nn);
end

function q = lowq(x, frac)
x = sort(x(:));
if isempty(x), q = NaN; return; end
q = x(max(1, ceil(frac * numel(x))));
end
