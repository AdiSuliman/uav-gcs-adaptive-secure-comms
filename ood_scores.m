function [maha, ifs, maha_last] = ood_scores(net, M, X_spec, X_feat)
%OOD_SCORES  Feature-space unknown-threat scores (D42, D59); higher = more like
%   the known classes (same convention as MSP and energy in cnn_scores.m).
%   maha       Mahalanobis feature ensemble of fit_ood_model.m (log-odds of the
%              logistic-regression detector over the layer scores)
%   ifs        minus the isolation-forest anomaly score of the link features
%   maha_last  the last layer's score alone ('relu_merge', the D42 score)
%   X_spec 128x128x1xN images, X_feat nFeat x N normalized features.
Z = ood_layer_features(net, M.layers, X_spec, X_feat);
[maha, maha_last] = ood_ensemble(M, Z);
if nargout > 1
    [~, s] = isanomaly(M.forest, X_feat');
    ifs = -s(:)';
end
end
