function [maha, S] = ood_scores(net, M, X_spec, X_feat)
%OOD_SCORES  Unknown-threat scores of a batch; higher = more like
%   the known classes (same convention as MSP and energy in cnn_scores.m).
%   maha  the production score, candidate M.score of ood_score_set.m
%   S     every candidate of M.candidates, and the isolation forest alone (S.iforest)
%   X_spec 128x128x1xN images, X_feat nFeat x N normalized features.
Z = ood_layer_features(net, M.layers, X_spec, X_feat);
S = ood_score_set(M, Z, X_feat, [M.candidates, {'last_or_if'}]);
maha = S.(M.score);
end
