%% B2 — TRAIN HYBRID DETECTOR: CNN (spectrogram) + FC (scalars) → softmax(7)
% Two-branch architecture (scalar branch now handles 7 features after B2.5):
%   Branch 1 (CNN):  [128×128×1] → Conv→BN→ReLU→Pool ×3 → GAP → Flatten → 128-d
%   Branch 2 (FC):   [nFeat] → FC(32)→ReLU → FC(16)→ReLU → 16-d
%   Merge:           cat(128+16=144) → FC(64)→ReLU→Dropout → FC(7)→softmax
%
% Input:  data/splits.mat
% Output: data/trained_detector.mat (net, info, classes)
%         results/training_curves.png

close all; clc;
fprintf('=== B2: Train Hybrid Detector (with temporal features) ===\n\n');

%% 1. Load splits
fprintf('Loading splits...\n');
S = load('data/splits.mat');
sp = S.splits;
classes = sp.classes;
nClasses = numel(classes);
nFeat = size(sp.train.feats, 2);

fprintf('  train: %d | val: %d | test: %d | classes: %d | features: %d\n', ...
    size(sp.train.X,4), size(sp.val.X,4), size(sp.test.X,4), nClasses, nFeat);

%% 2. Build hybrid network (dlnetwork with two inputs)
fprintf('Building hybrid network...\n');
% --- CNN branch (spectrogram input) ---
cnn_layers = [
    imageInputLayer([128 128 1], 'Name', 'spec_input', 'Normalization', 'none')
    convolution2dLayer(3, 32, 'Padding', 'same', 'Name', 'conv1')
    batchNormalizationLayer('Name', 'bn1')
    reluLayer('Name', 'relu1')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')       % → 64×64×32
    convolution2dLayer(3, 64, 'Padding', 'same', 'Name', 'conv2')
    batchNormalizationLayer('Name', 'bn2')
    reluLayer('Name', 'relu2')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')       % → 32×32×64
    convolution2dLayer(3, 128, 'Padding', 'same', 'Name', 'conv3')
    batchNormalizationLayer('Name', 'bn3')
    reluLayer('Name', 'relu3')
    globalAveragePooling2dLayer('Name', 'gap')               % → 1×1×128
    flattenLayer('Name', 'flatten')                          % → 128-d (CB)
];
% --- Scalar branch (nFeat features input — 7 with temporal features) ---
fc_layers = [
    featureInputLayer(nFeat, 'Name', 'feat_input')
    fullyConnectedLayer(32, 'Name', 'fc_feat1')
    reluLayer('Name', 'relu_feat1')
    fullyConnectedLayer(16, 'Name', 'fc_feat2')
    reluLayer('Name', 'relu_feat2')
];
% --- Merge + classifier ---
merge_layers = [
    concatenationLayer(1, 2, 'Name', 'concat')               % 128+16=144
    fullyConnectedLayer(64, 'Name', 'fc_merge')
    reluLayer('Name', 'relu_merge')
    dropoutLayer(0.3, 'Name', 'dropout')
    fullyConnectedLayer(nClasses, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax')
];
% Assemble into layerGraph
lgraph = layerGraph(cnn_layers);
lgraph = addLayers(lgraph, fc_layers);
lgraph = addLayers(lgraph, merge_layers);
% Connect branches to concat
lgraph = connectLayers(lgraph, 'flatten',    'concat/in1');
lgraph = connectLayers(lgraph, 'relu_feat2', 'concat/in2');
% Convert to dlnetwork
net = dlnetwork(lgraph);

fprintf('  CNN branch:    spec [128×128×1] → 128-d\n');
fprintf('  Scalar branch: feats [%d] → 16-d\n', nFeat);
fprintf('  Merged:        144-d → FC(64) → dropout(0.3) → softmax(%d)\n', nClasses);
fprintf('  Total params:  %d\n', sum(cellfun(@numel, {net.Learnables.Value{:}})));

%% 3. Training setup
fprintf('\nTraining setup...\n');
numEpochs       = 30;
miniBatchSize   = 64;
initialLearnRate = 1e-3;
learnRateDropPeriod = 10;
learnRateDropFactor = 0.5;

% Prepare data as dlarray
X_train_spec = dlarray(single(sp.train.X), 'SSCB');
X_train_feat = dlarray(single(sp.train.feats)', 'CB');  % [nFeat × N]
T_train      = onehotencode(sp.train.Y, 2)';             % [C × N]
T_train_dl   = dlarray(single(double(T_train)), 'CB');

X_val_spec = dlarray(single(sp.val.X), 'SSCB');
X_val_feat = dlarray(single(sp.val.feats)', 'CB');
T_val      = onehotencode(sp.val.Y, 2)';
T_val_dl   = dlarray(single(double(T_val)), 'CB');

nTrain = size(sp.train.X, 4);
numIterPerEpoch = floor(nTrain / miniBatchSize);

fprintf('  epochs=%d | batch=%d | lr=%.0e (drop ×%.1f every %d)\n', ...
    numEpochs, miniBatchSize, initialLearnRate, learnRateDropFactor, learnRateDropPeriod);
fprintf('  iterations/epoch=%d | GPU: %s\n', numIterPerEpoch, ...
    string(canUseGPU));

if canUseGPU
    net = dlupdate(@gpuArray, net);
end

%% 4. Training loop
fprintf('\nTraining...\n');
averageGrad = []; averageSqGrad = [];
iteration = 0;
trainLossHistory = [];
trainAccHistory  = [];
valLossHistory   = [];
valAccHistory    = [];
bestValAcc = 0;
bestNet    = [];

for epoch = 1:numEpochs
    perm = randperm(nTrain);
    epochLoss = 0; epochCorrect = 0; epochCount = 0;
    lr = initialLearnRate * (learnRateDropFactor ^ floor((epoch-1)/learnRateDropPeriod));

    for iter = 1:numIterPerEpoch
        iteration = iteration + 1;
        idx = perm((iter-1)*miniBatchSize+1 : iter*miniBatchSize);

        Xspec = X_train_spec(:,:,:,idx);
        Xfeat = X_train_feat(:,idx);
        T     = T_train_dl(:,idx);

        if canUseGPU
            Xspec = gpuArray(Xspec);
            Xfeat = gpuArray(Xfeat);
            T     = gpuArray(T);
        end

        [loss, gradients, state, pred] = dlfeval(@modelLoss, net, Xspec, Xfeat, T);
        net.State = state;

        [net, averageGrad, averageSqGrad] = adamupdate( ...
            net, gradients, averageGrad, averageSqGrad, iteration, lr);

        epochLoss = epochLoss + double(extractdata(loss)) * miniBatchSize;
        [~, predIdx] = max(extractdata(pred), [], 1);
        [~, trueIdx] = max(extractdata(T), [], 1);
        epochCorrect = epochCorrect + sum(predIdx == trueIdx);
        epochCount = epochCount + miniBatchSize;
    end

    trainLoss = epochLoss / epochCount;
    trainAcc  = epochCorrect / epochCount;
    trainLossHistory(end+1) = trainLoss;
    trainAccHistory(end+1)  = trainAcc;

    if canUseGPU
        valSpec = gpuArray(X_val_spec);
        valFeat = gpuArray(X_val_feat);
    else
        valSpec = X_val_spec;
        valFeat = X_val_feat;
    end
    valPred = predict(net, valSpec, valFeat);
    valLoss = double(extractdata(crossentropy(valPred, T_val_dl)));
    [~, vpIdx] = max(extractdata(valPred), [], 1);
    [~, vtIdx] = max(double(T_val), [], 1);
    valAcc  = mean(vpIdx == vtIdx);
    valLossHistory(end+1) = valLoss;
    valAccHistory(end+1)  = valAcc;

    if valAcc > bestValAcc
        bestValAcc = valAcc;
        bestNet = net;
        bestEpoch = epoch;
    end

    fprintf('  Epoch %2d/%d | lr=%.0e | trainLoss=%.4f trainAcc=%.3f | valLoss=%.4f valAcc=%.3f%s\n', ...
        epoch, numEpochs, lr, trainLoss, trainAcc, valLoss, valAcc, ...
        ternary(valAcc >= bestValAcc, ' *', ''));
end

fprintf('\nBest val accuracy: %.3f at epoch %d\n', bestValAcc, bestEpoch);

%% 5. Save model + training history
net = bestNet;
info = struct();
info.trainLoss = trainLossHistory;
info.trainAcc  = trainAccHistory;
info.valLoss   = valLossHistory;
info.valAcc    = valAccHistory;
info.bestEpoch = bestEpoch;
info.bestValAcc = bestValAcc;
info.numEpochs = numEpochs;
info.miniBatchSize = miniBatchSize;
info.nFeat = nFeat;

fprintf('Saving trained model...\n');
if ~exist('data', 'dir'), mkdir('data'); end
save('data/trained_detector.mat', 'net', 'info', 'classes', '-v7.3');
fprintf('Saved data/trained_detector.mat\n');

%% 6. Training curves plot
fig = figure('Position', [100 100 900 400]);
subplot(1,2,1);
plot(1:numEpochs, trainLossHistory, 'b-', 'LineWidth', 1.5); hold on;
plot(1:numEpochs, valLossHistory, 'r-', 'LineWidth', 1.5);
xline(bestEpoch, '--k', sprintf('best (ep %d)', bestEpoch));
xlabel('Epoch'); ylabel('Cross-Entropy Loss');
title('Loss'); legend('Train', 'Val', 'Location', 'northeast');
grid on;
subplot(1,2,2);
plot(1:numEpochs, 100*trainAccHistory, 'b-', 'LineWidth', 1.5); hold on;
plot(1:numEpochs, 100*valAccHistory, 'r-', 'LineWidth', 1.5);
xline(bestEpoch, '--k', sprintf('best (ep %d)', bestEpoch));
xlabel('Epoch'); ylabel('Accuracy (%)');
title(sprintf('Accuracy (best val: %.1f%%)', 100*bestValAcc));
legend('Train', 'Val', 'Location', 'southeast');
grid on;
sgtitle('B2: Hybrid Detector Training (7 features, temporal)');
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/training_curves.png');
fprintf('Saved results/training_curves.png\n');
close(fig);
fprintf('\n=== B2 Complete ===\n');

%% ===== Helper functions =====
function [loss, gradients, state, pred] = modelLoss(net, Xspec, Xfeat, T)
    [pred, state] = forward(net, Xspec, Xfeat);
    loss = crossentropy(pred, T);
    gradients = dlgradient(loss, net.Learnables);
end

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end