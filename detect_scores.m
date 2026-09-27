function [probs, maha] = detect_scores(net, M, X_spec, X_feat, device)
%DETECT_SCORES  Class probabilities and Mahalanobis unknown-threat score from
%   ONE forward pass of the hybrid detector (D48): the outputs 'fc_out'
%   (logits) and 'relu_merge' (embedding) of the same predict call. Same values
%   as cnn_scores.m + ood_scores.m, half the network evaluations.
%   M       unknown-threat model of data/trained_detector.mat ('ood')
%   device  'auto' (GPU when available, default), 'gpu' or 'cpu'
%   probs   9 x N, maha 1 x N (higher = more like the known classes)
if nargin < 5 || isempty(device), device = 'auto'; end
switch device
    case 'auto', useGPU = canUseGPU;
    case 'gpu',  useGPU = true;
    otherwise,   useGPU = false;
end
N = size(X_spec, 4);
probs = zeros(size(M.mu, 2), N); maha = zeros(1, N);
for i0 = 1:256:N
    idx = i0:min(i0 + 255, N);
    xs = dlarray(single(X_spec(:, :, :, idx)), 'SSCB'); xf = dlarray(single(X_feat(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    [z, e] = predict(net, xs, xf, 'Outputs', {'fc_out', 'relu_merge'});
    z = double(gather(extractdata(z))); Z = double(gather(extractdata(e)));
    ex = exp(z - max(z, [], 1));
    probs(1:size(z, 1), idx) = ex ./ sum(ex, 1);
    dmin = inf(1, numel(idx));
    for c = 1:size(M.mu, 2)
        D = Z - M.mu(:, c);
        dmin = min(dmin, sum(D .* (M.P * D), 1));
    end
    maha(idx) = -dmin;
end
end
