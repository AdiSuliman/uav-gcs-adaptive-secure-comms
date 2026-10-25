function P = spec_scores(net, X)
%SPEC_SCORES  Class probabilities of the image-only network (train_spec_net.m), in batches of
%   256 (a whole split does not fit on the GPU).
%   X  128 x 128 x 1 x N images; P  N x C, rows summing to 1
persistent useGPU
if isempty(useGPU), useGPU = canUseGPU; end
if useGPU, net = dlupdate(@gpuArray, net); end
N = size(X, 4);
B = 256;
P = [];
for i0 = 1:B:N
    idx = i0:min(i0 + B - 1, N);
    xs = dlarray(single(X(:, :, :, idx)), 'SSCB');
    if useGPU, xs = gpuArray(xs); end
    z = gather(extractdata(predict(net, xs)));
    P = [P; double(z)']; %#ok<AGROW>
end
end
