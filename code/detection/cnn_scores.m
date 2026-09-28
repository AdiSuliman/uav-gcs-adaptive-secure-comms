function [probs, logits, msp, energy] = cnn_scores(net, X_spec, X_feat)
%CNN_SCORES  Batch outputs of the hybrid detector, including unknown-threat scores.
%   X_spec: 128x128x1xN spectrogram images, X_feat: nFeat x N normalized features.
%   logits  pre-softmax outputs of layer 'fc_out' (train_detector.m)
%   probs   softmax(logits), identical to the network's own softmax output
%   msp     maximum softmax probability (Hendrycks & Gimpel, ICLR 2017)
%   energy  logsumexp of the logits (Liu et al., NeurIPS 2020)
%   For msp and energy, higher means more like the known classes.
persistent useGPU
if isempty(useGPU), useGPU = canUseGPU; end
N = size(X_spec, 4);
B = 256;
logits = [];
for i0 = 1:B:N
    idx = i0:min(i0 + B - 1, N);
    xs = dlarray(single(X_spec(:, :, :, idx)), 'SSCB');
    xf = dlarray(single(X_feat(:, idx)), 'CB');
    if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); end
    z = gather(extractdata(predict(net, xs, xf, 'Outputs', 'fc_out')));
    logits = [logits, double(z)]; %#ok<AGROW>
end
m = max(logits, [], 1);
e = exp(logits - m);
probs  = e ./ sum(e, 1);
msp    = max(probs, [], 1);
energy = m + log(sum(e, 1));
end
