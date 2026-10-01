function [net, info] = train_hybrid_net(tr, va, classes, opts)
%TRAIN_HYBRID_NET  Hybrid detector training, shared by train_detector.m and
%   eval_ood_detection.m.
%   tr, va   splits with X [128x128x1xN], feats [N x nFeat] (normalized), Y
%   classes  class names (categories of Y)
%   opts     optional: epochs (30), batch (64), lr (1e-3), l2 (1e-4),
%            augment (true), verbose (true)
%
%   Network: CNN branch (3 conv blocks, GAP, 128-d) + scalar branch (32-16) ->
%   concat -> FC 64 (layer 'relu_merge', the embedding used for Mahalanobis
%   scoring) -> dropout 0.3 -> FC nClasses ('fc_out') -> softmax.
%   Training: Adam, cosine learning-rate decay to lr/20, L2 weight decay,
%   time/frequency masking of the spectrogram (one band of each, 50% of the
%   samples); cross-entropy weighted by the inverse class frequency of the
%   training split (benign frames without a packet on the air are clean frames,
%   so the classes are not equally large); best epoch by validation macro-F1,
%   the KPI 1 metric.

if nargin < 4, opts = struct(); end
o = struct('epochs', 30, 'batch', 64, 'lr', 1e-3, 'l2', 1e-4, 'augment', true, 'verbose', true);
f = fieldnames(opts);
for i = 1:numel(f), o.(f{i}) = opts.(f{i}); end

nClasses = numel(classes); nFeat = size(tr.feats, 2);
cnn_layers = [
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
    flattenLayer('Name', 'flatten')];
fc_layers = [
    featureInputLayer(nFeat, 'Name', 'feat_input')
    fullyConnectedLayer(32, 'Name', 'fc_feat1')
    reluLayer('Name', 'relu_feat1')
    fullyConnectedLayer(16, 'Name', 'fc_feat2')
    reluLayer('Name', 'relu_feat2')];
merge_layers = [
    concatenationLayer(1, 2, 'Name', 'concat')
    fullyConnectedLayer(64, 'Name', 'fc_merge')
    reluLayer('Name', 'relu_merge')
    dropoutLayer(0.3, 'Name', 'dropout')
    fullyConnectedLayer(nClasses, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax')];
lg = layerGraph(cnn_layers);
lg = addLayers(lg, fc_layers);
lg = addLayers(lg, merge_layers);
lg = connectLayers(lg, 'flatten', 'concat/in1');
lg = connectLayers(lg, 'relu_feat2', 'concat/in2');
net = dlnetwork(lg);

useGPU = canUseGPU;
if useGPU, net = dlupdate(@gpuArray, net); end
Xtr = single(tr.X); Ftr = single(tr.feats)';
Ttr = single(double(onehotencode(tr.Y(:), 2)'));
[~, vt] = max(double(onehotencode(va.Y(:), 2)'), [], 1);
cw = sum(Ttr, 2); cw = single(sum(cw) ./ (nClasses * max(cw, 1)));   % inverse class frequency, mean 1
cw = dlarray(cw, 'CB'); if useGPU, cw = gpuArray(cw); end

nTrain = size(Xtr, 4);
nIter = floor(nTrain / o.batch);
nTot = o.epochs * nIter;
avgG = []; avgSq = []; it = 0;
bestAcc = -1; bestNet = net; bestEpoch = 0;
hist = struct('trainLoss', zeros(1, o.epochs), 'valAcc', zeros(1, o.epochs));
for ep = 1:o.epochs
    perm = randperm(nTrain);
    lsum = 0;
    for b = 1:nIter
        it = it + 1;
        lr = o.lr * (0.05 + 0.95 * 0.5 * (1 + cos(pi * (it - 1) / nTot)));
        idx = perm((b-1)*o.batch + 1 : b*o.batch);
        xs = Xtr(:, :, :, idx);
        if o.augment, xs = spec_mask(xs); end
        xs = dlarray(xs, 'SSCB'); xf = dlarray(Ftr(:, idx), 'CB'); tt = dlarray(Ttr(:, idx), 'CB');
        if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); tt = gpuArray(tt); end
        [loss, grads, state] = dlfeval(@model_loss, net, xs, xf, tt, cw);
        net.State = state;
        grads = dlupdate(@(g, w) g + o.l2 * w, grads, net.Learnables);
        [net, avgG, avgSq] = adamupdate(net, grads, avgG, avgSq, it, lr);
        lsum = lsum + double(gather(extractdata(loss)));
    end
    [~, vp] = max(cnn_scores(net, va.X, va.feats'), [], 1);   % batched: the whole split does not fit on the GPU
    acc = macro_f1(vt, vp, nClasses);
    hist.trainLoss(ep) = lsum / nIter; hist.valAcc(ep) = acc;
    if acc > bestAcc, bestAcc = acc; bestNet = net; bestEpoch = ep; end
    if o.verbose
        fprintf('  epoch %2d/%d | loss %.4f | val macro-F1 %.4f%s\n', ep, o.epochs, hist.trainLoss(ep), acc, ...
            repmat(' *', 1, bestEpoch == ep));
    end
end
net = bestNet;
info = struct('trainLoss', hist.trainLoss, 'valAcc', hist.valAcc, 'bestEpoch', bestEpoch, ...
    'bestValAcc', bestAcc, 'numEpochs', o.epochs, 'miniBatchSize', o.batch, 'nFeat', nFeat, 'opts', o);
end

function [loss, grads, state] = model_loss(net, xs, xf, tt, cw)
[y, state] = forward(net, xs, xf);
loss = -sum(cw .* tt .* log(y + 1e-8), 'all') / size(tt, 2);
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

function X = spec_mask(X)
% One time band (<= 16 columns) and one frequency band (<= 12 rows) set to the
% image floor, on a random half of the batch.
n = size(X, 4);
for i = find(rand(1, n) < 0.5)
    w = randi(16); c0 = randi(128 - w + 1); X(:, c0:c0+w-1, 1, i) = 0;
    h = randi(12); r0 = randi(128 - h + 1); X(r0:r0+h-1, :, 1, i) = 0;
end
end
