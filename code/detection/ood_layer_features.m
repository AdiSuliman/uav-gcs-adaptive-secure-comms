function Z = ood_layer_features(net, layers, X_spec, X_feat, device)
%OOD_LAYER_FEATURES  Hidden features of the hybrid detector for the Mahalanobis
%   ensemble (fit_ood_model.m): one cell per layer, features x N; convolutional
%   outputs are average-pooled over time and frequency (Lee et al., NeurIPS 2018).
%   device  'auto' (GPU when available, default) or 'cpu'
if nargin < 5 || isempty(device), device = 'auto'; end
useGPU = strcmp(device, 'auto') && canUseGPU;
Z = cell(1, numel(layers));
for i0 = 1:128:size(X_spec, 4)
    idx = i0:min(i0 + 127, size(X_spec, 4));
    xs = dlarray(single(X_spec(:, :, :, idx)), 'SSCB'); xf = dlarray(single(X_feat(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    out = cell(1, numel(layers));
    [out{:}] = predict(net, xs, xf, 'Outputs', layers);
    for l = 1:numel(layers)
        Z{l} = [Z{l}, pooled(out{l})];
    end
end
end

function v = pooled(a)
% SSCB -> C x B by averaging over the spatial dimensions; CB stays as it is.
isSpatial = startsWith(dims(a), 'SS');
v = double(gather(extractdata(a)));
if isSpatial
    v = mean(mean(v, 1), 2);
    v = reshape(v, size(v, 3), []);
end
end
