function det = dev_d91_det(src, p0)
%DEV_D91_DET  The detector of the d91 proofs, as build_policy_pools.m sets it up.
%   det = dev_d91_det(src, p0): src.detector (a trained_detector.mat) and src.splits (its
%   splits.mat: the training z-score only, split_norm.m); [] when either is missing or its
%   feature count is not that of link_features.m (the proofs then run without the detector).
det = [];
if ~isfile(src.detector) || ~isfile(src.splits)
    fprintf('detector: %s or %s missing; no detector\n', src.detector, src.splits);
    return;
end
D = load(src.detector, 'net', 'classes', 'ood');
nm = split_norm(src.splits);
if numel(nm.feat_mean) ~= numel(link_features('names'))
    fprintf('detector: %d features, link_features.m has %d; no detector\n', numel(nm.feat_mean), numel(link_features('names')));
    return;
end
det = struct('net', D.net, 'ood', D.ood, 'classes', {cellstr(string(D.classes(:)'))}, ...
    'mu', nm.feat_mean, 'sd', nm.feat_std, 'fs', p0.symbol_rate * p0.sps);
fprintf('detector: %s (%d classes, %d features, score %s)\n', src.detector, numel(det.classes), numel(det.mu), det.ood.score);
end
