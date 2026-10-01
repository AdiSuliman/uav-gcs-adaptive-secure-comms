function Zp = pre_features(net, M, X, F, ep)
%PRE_FEATURES  Last-hidden-layer features after the input pre-processing of Lee et al.
%   (NeurIPS 2018): every input takes a small step that lowers its Mahalanobis distance
%   to the closest known class, x - eps sign(grad d(x)); known inputs move closer than
%   unknown ones, which separates them more.
%   ep   [image step (image in [0,1]), feature step (z-score units)]; default M.eps_pre
%   Zp   features of M.layers{end} (dims x N) of the pre-processed inputs
if nargin < 5 || isempty(ep), ep = M.eps_pre; end
useGPU = canUseGPU;
lay = M.layers{end};
MU = dlarray(single(M.mu{end})); P = dlarray(single(M.P{end}));
if useGPU, MU = gpuArray(MU); P = gpuArray(P); end
N = size(X, 4);
Zp = zeros(size(M.mu{end}, 1), N);
for i0 = 1:128:N
    idx = i0:min(i0 + 127, N);
    xs = dlarray(single(X(:, :, :, idx)), 'SSCB'); xf = dlarray(single(F(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    if any(ep > 0)
        [gs, gf] = dlfeval(@dist_grad, net, xs, xf, MU, P, lay);
        xs = min(max(xs - ep(1) * sign(gs), 0), 1);
        xf = xf - ep(2) * sign(gf);
    end
    z = predict(net, xs, xf, 'Outputs', lay);
    v = double(gather(extractdata(z)));
    if startsWith(dims(z), 'SS'), v = reshape(mean(mean(v, 1), 2), size(v, 3), []); end
    Zp(:, idx) = v;
end
end

function [gs, gf] = dist_grad(net, xs, xf, MU, P, lay)
% Gradient of the smallest class Mahalanobis distance (summed over the batch).
z = stripdims(predict(net, xs, xf, 'Outputs', lay));
if ndims(z) > 2, z = reshape(mean(mean(z, 1), 2), size(z, 3), []); end
nC = size(MU, 2);
D = [];
for c = 1:nC
    d = z - MU(:, c);
    D = [D; sum(d .* (P * d), 1)]; %#ok<AGROW>
end
loss = sum(min(D, [], 1));
[gs, gf] = dlgradient(loss, xs, xf);
end
