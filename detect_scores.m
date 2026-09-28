function [probs, maha] = detect_scores(net, M, X_spec, X_feat, device)
%DETECT_SCORES  Class probabilities and the unknown-threat score from ONE forward
%   pass of the hybrid detector (D48, D59): the logits 'fc_out' and the hidden
%   layers of the Mahalanobis feature ensemble (fit_ood_model.m) come from the
%   same predict call. Same values as cnn_scores.m + ood_scores.m.
%   M       unknown-threat model of data/trained_detector.mat ('ood')
%   device  'auto' (GPU when available, default), 'gpu' or 'cpu'
%   probs   classes x N, maha 1 x N (higher = more like the known classes)
if nargin < 5 || isempty(device), device = 'auto'; end
switch device
    case 'auto', useGPU = canUseGPU;
    case 'gpu',  useGPU = true;
    otherwise,   useGPU = false;
end
N = size(X_spec, 4);
nL = numel(M.layers);
probs = zeros(size(M.mu{end}, 2), N); maha = zeros(1, N);
for i0 = 1:128:N
    idx = i0:min(i0 + 127, N);
    xs = dlarray(single(X_spec(:, :, :, idx)), 'SSCB'); xf = dlarray(single(X_feat(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    out = cell(1, nL + 1);
    [out{:}] = predict(net, xs, xf, 'Outputs', [{'fc_out'}, M.layers]);
    z = double(gather(extractdata(out{1})));
    ex = exp(z - max(z, [], 1));
    probs(:, idx) = ex ./ sum(ex, 1);
    Z = cell(1, nL);
    for l = 1:nL
        v = double(gather(extractdata(out{l + 1})));
        if startsWith(dims(out{l + 1}), 'SS'), v = reshape(mean(mean(v, 1), 2), size(v, 3), []); end
        Z{l} = v;
    end
    maha(idx) = ood_ensemble(M, Z);
end
end
