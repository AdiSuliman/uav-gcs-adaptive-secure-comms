function [maha, ifs] = ood_scores(net, M, X_spec, X_feat)
%OOD_SCORES  Feature-space unknown-threat scores (D42); higher = more like the
%   known classes (same convention as MSP and energy in cnn_scores.m).
%   maha  minus the smallest Mahalanobis distance of the 'relu_merge' embedding
%         to a class mean (fit_ood_model.m)
%   ifs   minus the isolation-forest anomaly score of the link features
%   X_spec 128x128x1xN images, X_feat nFeat x N normalized features.
N = size(X_spec, 4);
maha = zeros(1, N);
useGPU = canUseGPU;
for i0 = 1:256:N
    idx = i0:min(i0 + 255, N);
    xs = dlarray(single(X_spec(:, :, :, idx)), 'SSCB'); xf = dlarray(single(X_feat(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    Z = double(gather(extractdata(predict(net, xs, xf, 'Outputs', 'relu_merge'))));
    dmin = inf(1, numel(idx));
    for c = 1:size(M.mu, 2)
        D = Z - M.mu(:, c);
        dmin = min(dmin, sum(D .* (M.P * D), 1));
    end
    maha(idx) = -dmin;
end
[~, s] = isanomaly(M.forest, X_feat');
ifs = -s(:)';
end
