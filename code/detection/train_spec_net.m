function [net, info] = train_spec_net(X, y, Xv, yv, C, opts)
%TRAIN_SPEC_NET  CNN on the detector image alone (train_core_cnn.m): the hybrid's CNN branch
%   (train_hybrid_net.m) with a head of its own, on the same schedule.
%   X, Xv  128 x 128 x 1 x N images (spec_image.m), training and validation
%   y, yv  class index 1..C of every image
%   opts   optional: epochs (30), batch (64), lr (1e-3), l2 (1e-4), augment (true), verbose (true)
%
%   Network: 3 conv blocks (3x3, 32/64/128 filters, batch norm, ReLU, 2x2 max pooling after
%   the first two), global average pooling, FC 64 + ReLU, dropout 0.3, FC C, softmax: the
%   hybrid without its link-feature branch (compare_architectures.m's spectrogram-only
%   variant feeds that branch zeros, a constant bias).
%   Training: Adam, cosine learning-rate decay to lr/20, L2 weight decay, time and frequency
%   masking (spec_mask.m), cross-entropy weighted by the inverse class frequency of the
%   training images (mean 1); the epoch with the best validation macro-F1 is kept.
%   info: trainLoss and valF1 per epoch, bestEpoch, bestValF1, numEpochs, classWeights, opts
if nargin < 6, opts = struct(); end
o = struct('epochs', 30, 'batch', 64, 'lr', 1e-3, 'l2', 1e-4, 'augment', true, 'verbose', true);
f = fieldnames(opts);
for i = 1:numel(f), o.(f{i}) = opts.(f{i}); end
y = double(y(:)); yv = double(yv(:));
assert(size(X, 4) == numel(y) && size(Xv, 4) == numel(yv), 'train_spec_net:size', 'train_spec_net: images and labels differ in number');
assert(all(ismember(y, 1:C)) && all(ismember(yv, 1:C)), 'train_spec_net:labels', 'train_spec_net: labels outside 1..%d', C);

layers = [
    imageInputLayer([128 128 1], 'Name', 'spec_input', 'Normalization', 'none')
    convolution2dLayer(3, 32, 'Padding', 'same', 'Name', 'conv1')
    batchNormalizationLayer('Name', 'bn1')
    reluLayer('Name', 'relu1')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')
    convolution2dLayer(3, 64, 'Padding', 'same', 'Name', 'conv2')
    batchNormalizationLayer('Name', 'bn2')
    reluLayer('Name', 'relu2')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')
    convolution2dLayer(3, 128, 'Padding', 'same', 'Name', 'conv3')
    batchNormalizationLayer('Name', 'bn3')
    reluLayer('Name', 'relu3')
    globalAveragePooling2dLayer('Name', 'gap')
    flattenLayer('Name', 'flatten')
    fullyConnectedLayer(64, 'Name', 'fc_merge')
    reluLayer('Name', 'relu_merge')
    dropoutLayer(0.3, 'Name', 'dropout')
    fullyConnectedLayer(C, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax')];
net = dlnetwork(layers);

useGPU = canUseGPU;
if useGPU, net = dlupdate(@gpuArray, net); end
X = single(X);
T = single(full(sparse(y, (1:numel(y))', 1, C, numel(y))));
cw = sum(T, 2); cw = single(sum(cw) ./ (C * max(cw, 1)));       % inverse class frequency, mean 1
cwd = dlarray(cw, 'CB'); if useGPU, cwd = gpuArray(cwd); end

nTrain = numel(y);
bs = min(o.batch, nTrain);
nIter = floor(nTrain / bs);
nTot = o.epochs * nIter;
avgG = []; avgSq = []; it = 0;
best = -1; bestNet = net; bestEpoch = 0;
hist = struct('trainLoss', zeros(1, o.epochs), 'valF1', zeros(1, o.epochs));
for ep = 1:o.epochs
    perm = randperm(nTrain);
    lsum = 0;
    for b = 1:nIter
        it = it + 1;
        lr = o.lr * (0.05 + 0.95 * 0.5 * (1 + cos(pi * (it - 1) / nTot)));
        idx = perm((b - 1) * bs + 1 : b * bs);
        xs = X(:, :, :, idx);
        if o.augment, xs = spec_mask(xs); end
        xs = dlarray(xs, 'SSCB'); tt = dlarray(T(:, idx), 'CB');
        if useGPU, xs = gpuArray(xs); tt = gpuArray(tt); end
        [loss, grads, state] = dlfeval(@model_loss, net, xs, tt, cwd);
        net.State = state;
        grads = dlupdate(@(g, w) g + o.l2 * w, grads, net.Learnables);
        [net, avgG, avgSq] = adamupdate(net, grads, avgG, avgSq, it, lr);
        lsum = lsum + double(gather(extractdata(loss)));
    end
    [~, vp] = max(spec_scores(net, Xv), [], 2);
    f1 = macro_f1(yv, vp, C);
    hist.trainLoss(ep) = lsum / nIter; hist.valF1(ep) = f1;
    if f1 > best, best = f1; bestNet = net; bestEpoch = ep; end
    if o.verbose
        fprintf('  epoch %2d/%d | loss %.4f | val macro-F1 %.4f%s\n', ep, o.epochs, hist.trainLoss(ep), f1, ...
            repmat(' *', 1, bestEpoch == ep));
    end
end
net = dlupdate(@gather, bestNet);                       % saved and read without a GPU too
info = struct('trainLoss', hist.trainLoss, 'valF1', hist.valF1, 'bestEpoch', bestEpoch, 'bestValF1', best, ...
    'numEpochs', o.epochs, 'classWeights', double(cw(:)'), 'opts', o);
end

function [loss, grads, state] = model_loss(net, xs, tt, cw)
[p, state] = forward(net, xs);
loss = -sum(cw .* tt .* log(p + 1e-8), 'all') / size(tt, 2);
grads = dlgradient(loss, net.Learnables);
end

function m = macro_f1(y, yh, C)
f = zeros(1, C);
for c = 1:C
    tp = sum(yh == c & y == c); fp = sum(yh == c & y ~= c); fn = sum(yh ~= c & y == c);
    f(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
m = mean(f);
end
