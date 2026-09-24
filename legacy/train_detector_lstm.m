%% B2-seq — TRAIN CNN-LSTM DETECTOR: CNN (per-frame) + LSTM (per-sequence) hybrid
% Architecture (custom training loop, similar to train_detector.m):
%   Step 1: For each frame in a sequence, extract CNN features:
%           [128x128x1] -> Conv/BN/ReLU/Pool x3 + GAP -> 128-d CNN features
%           (same CNN weights applied to every frame, sequence-agnostic)
%   Step 2: Sequence aggregation:
%           [128 x seq_len] per sequence -> LSTM(64) -> 64-d
%   Step 3: Merge with scalar features:
%           [nFeat x seq_len] per sequence -> LSTM(16) -> 16-d
%   Step 4: Merge CNN-LSTM + feat-LSTM + classify:
%           cat(64+16=80) -> FC(64)->ReLU->Dropout -> FC(nClasses)->softmax
%
% NOTE ON dlarray FORMATS: sequence tensors are built by concatenating
% per-timestep dlarrays with cat(3,...) and labeling the RESULT once with
% a single dlarray(...,'CBT') call. Never assign into an already-formatted
% dlarray slice (e.g. formattedArray(:,t,:)=x) -- dlarray's internal
% format-based permute mishandles that and either errors or silently
% swaps the B/T dimensions.
%
% Input:  data/splits_seq.mat
% Output: data/trained_detector_lstm.mat (cnn_net, lstm_cnn_net, feat_lstm_net, classifier_net, info, classes)
%         results/training_curves_lstm.png

close all; clc;
fprintf('=== B2-seq: Train CNN-LSTM Detector ===\n\n');

%% 1. Load splits
fprintf('Loading splits_seq...\n');
S = load('data/splits_seq.mat');
sp = S.splits_seq;
classes = sp.classes;
nClasses = numel(classes);
seq_len = sp.seq_len;
nFeat = size(sp.train.feats, 3);

fprintf('  train: %d | val: %d | test: %d | classes: %d | seq_len: %d | features: %d\n', ...
    size(sp.train.X,5), size(sp.val.X,5), size(sp.test.X,5), nClasses, seq_len, nFeat);

%% 2. Build CNN feature extractor (shared across all timesteps in a sequence)
fprintf('Building CNN feature extractor (shared weights)...\n');
cnn_layers = [
    imageInputLayer([128 128 1], 'Name', 'spec_input', 'Normalization', 'none')
    convolution2dLayer(3, 32, 'Padding', 'same', 'Name', 'conv1')
    batchNormalizationLayer('Name', 'bn1')
    reluLayer('Name', 'relu1')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')       % -> 64x64x32
    convolution2dLayer(3, 64, 'Padding', 'same', 'Name', 'conv2')
    batchNormalizationLayer('Name', 'bn2')
    reluLayer('Name', 'relu2')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')       % -> 32x32x64
    convolution2dLayer(3, 128, 'Padding', 'same', 'Name', 'conv3')
    batchNormalizationLayer('Name', 'bn3')
    reluLayer('Name', 'relu3')
    globalAveragePooling2dLayer('Name', 'gap')               % -> 1x1x128
    flattenLayer('Name', 'cnn_flat')                         % -> 128-d
];
cnn_net = dlnetwork(cnn_layers);
fprintf('  CNN: [128x128x1] -> 128-d (applied per-frame, weights shared)\n');

%% 3. Build LSTM sequence aggregators (custom training loop)
fprintf('Building LSTM aggregators and classifier...\n');
lstm_layers = [
    sequenceInputLayer(128, 'Name', 'cnn_seq_input')
    lstmLayer(64, 'OutputMode', 'last', 'Name', 'lstm_cnn')
    fullyConnectedLayer(64, 'Name', 'fc_lstm_cnn')
];
lstm_cnn_net = dlnetwork(lstm_layers);

feat_lstm_layers = [
    sequenceInputLayer(nFeat, 'Name', 'feat_seq_input')
    lstmLayer(16, 'OutputMode', 'last', 'Name', 'lstm_feat')
    fullyConnectedLayer(16, 'Name', 'fc_lstm_feat')
];
feat_lstm_net = dlnetwork(feat_lstm_layers);

%% 4. Classifier layer (separate, applied to merged features)
classifier_layers = [
    featureInputLayer(64+16, 'Name', 'merged_input')
    fullyConnectedLayer(64, 'Name', 'fc_merge')
    reluLayer('Name', 'relu_merge')
    dropoutLayer(0.3, 'Name', 'dropout')
    fullyConnectedLayer(nClasses, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax')
];
classifier_net = dlnetwork(classifier_layers);

fprintf('  CNN-LSTM branch:  128-d CNN features -> LSTM(64)\n');
fprintf('  Feat-LSTM branch: %d-d features -> LSTM(16)\n', nFeat);
fprintf('  Merged:           80-d -> FC(64)->ReLU->dropout(0.3) -> softmax(%d)\n', nClasses);
total_params = sum(cellfun(@numel, {cnn_net.Learnables.Value{:}})) + ...
               sum(cellfun(@numel, {lstm_cnn_net.Learnables.Value{:}})) + ...
               sum(cellfun(@numel, {feat_lstm_net.Learnables.Value{:}})) + ...
               sum(cellfun(@numel, {classifier_net.Learnables.Value{:}}));
fprintf('  Total params:     %d\n', total_params);

%% 5. Training setup
fprintf('\nTraining setup...\n');
numEpochs       = 30;
miniBatchSize   = 32;
initialLearnRate = 1e-3;
learnRateDropPeriod = 10;
learnRateDropFactor = 0.5;

% Convert training data (X is [128 128 1 seq_len N], feats is [N seq_len nFeat])
X_train_spec = single(sp.train.X);
X_train_feat = single(permute(sp.train.feats, [3 2 1]));   % [nFeat seq_len N_train]
T_train      = onehotencode(sp.train.Y, 2)';                % [C x N_train]

X_val_spec = single(sp.val.X);
X_val_feat = single(permute(sp.val.feats, [3 2 1]));
T_val      = onehotencode(sp.val.Y, 2)';

nTrain = size(sp.train.X, 5);
numIterPerEpoch = floor(nTrain / miniBatchSize);

fprintf('  epochs=%d | batch=%d | lr=%.0e (drop x%.1f every %d)\n', ...
    numEpochs, miniBatchSize, initialLearnRate, learnRateDropFactor, learnRateDropPeriod);
fprintf('  iterations/epoch=%d | GPU: %s\n', numIterPerEpoch, string(canUseGPU));

%% 6. Training loop
fprintf('\nTraining...\n');
avg_grad_cnn = []; avg_sqgrad_cnn = [];
avg_grad_lstm_cnn = []; avg_sqgrad_lstm_cnn = [];
avg_grad_feat_lstm = []; avg_sqgrad_feat_lstm = [];
avg_grad_classifier = []; avg_sqgrad_classifier = [];

iteration = 0;
trainLossHistory = [];
trainAccHistory  = [];
valLossHistory   = [];
valAccHistory    = [];
bestValAcc = 0;
bestCNN = []; bestLSTM_CNN = []; bestFeat_LSTM = []; bestClassifier = [];
bestEpoch  = 0;

for epoch = 1:numEpochs
    perm = randperm(nTrain);
    epochLoss = 0; epochCorrect = 0; epochCount = 0;
    lr = initialLearnRate * (learnRateDropFactor ^ floor((epoch-1)/learnRateDropPeriod));

    for iter = 1:numIterPerEpoch
        iteration = iteration + 1;
        idx = perm((iter-1)*miniBatchSize+1 : iter*miniBatchSize);

        Xspec_batch = X_train_spec(:,:,:,:,idx);      % [128 128 1 seq_len batch]
        Xfeat_batch = X_train_feat(:,:,idx);          % [nFeat seq_len batch]
        T_batch     = T_train(:,idx);                 % [C batch]

        if canUseGPU
            Xspec_batch = gpuArray(Xspec_batch);
            Xfeat_batch = gpuArray(Xfeat_batch);
            T_batch     = gpuArray(T_batch);
        end

        [loss, grad_cnn, grad_lstm_cnn, grad_feat_lstm, grad_classifier, pred] = ...
            dlfeval(@modelLoss, cnn_net, lstm_cnn_net, feat_lstm_net, classifier_net, ...
                    Xspec_batch, Xfeat_batch, T_batch, seq_len);

        [cnn_net, avg_grad_cnn, avg_sqgrad_cnn] = adamupdate( ...
            cnn_net, grad_cnn, avg_grad_cnn, avg_sqgrad_cnn, iteration, lr);
        [lstm_cnn_net, avg_grad_lstm_cnn, avg_sqgrad_lstm_cnn] = adamupdate( ...
            lstm_cnn_net, grad_lstm_cnn, avg_grad_lstm_cnn, avg_sqgrad_lstm_cnn, iteration, lr);
        [feat_lstm_net, avg_grad_feat_lstm, avg_sqgrad_feat_lstm] = adamupdate( ...
            feat_lstm_net, grad_feat_lstm, avg_grad_feat_lstm, avg_sqgrad_feat_lstm, iteration, lr);
        [classifier_net, avg_grad_classifier, avg_sqgrad_classifier] = adamupdate( ...
            classifier_net, grad_classifier, avg_grad_classifier, avg_sqgrad_classifier, iteration, lr);

        epochLoss = epochLoss + double(extractdata(loss)) * miniBatchSize;
        [~, predIdx] = max(extractdata(pred), [], 1);
        [~, trueIdx] = max(extractdata(T_batch), [], 1);
        epochCorrect = epochCorrect + sum(predIdx == trueIdx);
        epochCount = epochCount + miniBatchSize;
    end

    trainLoss = epochLoss / epochCount;
    trainAcc  = epochCorrect / epochCount;
    trainLossHistory(end+1) = trainLoss;
    trainAccHistory(end+1)  = trainAcc;

    % Validation
    val_cnn_feats = extractCNNFeatures(cnn_net, X_val_spec, seq_len, canUseGPU);  % [128 N_val seq_len] = (C,B,T)
    T_val_dl = dlarray(single(double(T_val)), 'CB');
    val_cnn_feats_dl = dlarray(val_cnn_feats, 'CBT');
    Xfeat_val_dl = dlarray(X_val_feat, 'CTB');
    if canUseGPU
        val_cnn_feats_dl = gpuArray(val_cnn_feats_dl);
        Xfeat_val_dl = gpuArray(Xfeat_val_dl);
    end
    val_lstm_cnn_out = predict(lstm_cnn_net, val_cnn_feats_dl);
    val_feat_lstm_out = predict(feat_lstm_net, Xfeat_val_dl);
    val_merged = dlarray(cat(1, extractdata(val_lstm_cnn_out), extractdata(val_feat_lstm_out)), 'CB');
    valPred = predict(classifier_net, val_merged);
    valLoss = double(extractdata(crossentropy(valPred, T_val_dl)));
    [~, vpIdx] = max(extractdata(valPred), [], 1);
    [~, vtIdx] = max(double(T_val), [], 1);
    valAcc  = mean(vpIdx == vtIdx);
    valLossHistory(end+1) = valLoss;
    valAccHistory(end+1)  = valAcc;

    if valAcc > bestValAcc
        bestValAcc = valAcc;
        bestCNN = cnn_net;
        bestLSTM_CNN = lstm_cnn_net;
        bestFeat_LSTM = feat_lstm_net;
        bestClassifier = classifier_net;
        bestEpoch = epoch;
    end

    fprintf('  Epoch %2d/%d | lr=%.0e | trainLoss=%.4f trainAcc=%.3f | valLoss=%.4f valAcc=%.3f%s\n', ...
        epoch, numEpochs, lr, trainLoss, trainAcc, valLoss, valAcc, ...
        ternary(valAcc >= bestValAcc, ' *', ''));
end

fprintf('\nBest val accuracy: %.3f at epoch %d\n', bestValAcc, bestEpoch);

%% 7. Save model + training history
cnn_net = bestCNN;
lstm_cnn_net = bestLSTM_CNN;
feat_lstm_net = bestFeat_LSTM;
classifier_net = bestClassifier;

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
info.seq_len = seq_len;

fprintf('Saving trained models...\n');
if ~exist('data', 'dir'), mkdir('data'); end
save('data/trained_detector_lstm.mat', 'cnn_net', 'lstm_cnn_net', 'feat_lstm_net', ...
     'classifier_net', 'info', 'classes', '-v7.3');
fprintf('Saved data/trained_detector_lstm.mat\n');

%% 8. Training curves plot
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
sgtitle('B2-seq: CNN-LSTM Detector Training');
if ~exist('results', 'dir'), mkdir('results'); end
saveas(fig, 'results/training_curves_lstm.png');
fprintf('Saved results/training_curves_lstm.png\n');
close(fig);
fprintf('\n=== B2-seq Complete ===\n');

%% ===== Helper: slice one frame from [128 128 1 seq_len N] and squeeze to [128 128 1 N] =====
function X_t = sliceFrame(X, t)
    sz = size(X);
    N = sz(5);
    X_t = reshape(X(:,:,:,t,:), sz(1), sz(2), sz(3), N);
end

%% ===== Helper: extract CNN features for a batch of sequences (no gradient needed) =====
function cnn_feats = extractCNNFeatures(cnn_net, X_spec, seq_len, use_gpu)
    % X_spec: [128 128 1 seq_len N]
    % Output: [128 N seq_len] plain array = (C,B,T) order for dlarray(...,'CBT')
    N = size(X_spec, 5);
    feats_cell = cell(1, seq_len);
    for t = 1:seq_len
        X_t = sliceFrame(X_spec, t);          % [128 128 1 N]
        X_t = dlarray(X_t, 'SSCB');
        if use_gpu, X_t = gpuArray(X_t); end
        feat_t = predict(cnn_net, X_t);        % dlarray 'CB' [128 N]
        feats_cell{t} = extractdata(feat_t);   % plain [128 N]
    end
    cnn_feats = cat(3, feats_cell{:});         % [128 N seq_len] = (C,B,T)
end

%% ===== Helper: forward pass + loss (gradient-tracked, built via cat not indexed assignment) =====
function [loss, grad_cnn, grad_lstm_cnn, grad_feat_lstm, grad_classifier, pred] = ...
    modelLoss(cnn_net, lstm_cnn_net, feat_lstm_net, classifier_net, Xspec, Xfeat, T, seq_len)

    % --- Extract CNN features per frame, collect as unformatted dlarrays, then cat once ---
    feats_cell = cell(1, seq_len);
    for t = 1:seq_len
        X_t = sliceFrame(Xspec, t);            % [128 128 1 batch]
        X_t = dlarray(X_t, 'SSCB');
        feat_t = predict(cnn_net, X_t);         % dlarray 'CB' [128 batch]
        feats_cell{t} = stripdims(feat_t);      % drop format, keep gradient tracking
    end
    cnn_feats_raw = cat(3, feats_cell{:});      % [128 batch seq_len], no format
    cnn_feats = dlarray(cnn_feats_raw, 'CBT');  % label once: (C,B,T)

    % --- LSTM aggregation ---
    lstm_cnn_out = predict(lstm_cnn_net, cnn_feats);         % [64 batch]
    Xfeat_dl = dlarray(Xfeat, 'CTB');                         % Xfeat is [nFeat seq_len batch] plain = (C,T,B)
    feat_lstm_out = predict(feat_lstm_net, Xfeat_dl);         % [16 batch]

    % --- Merge + classify ---
    merged = cat(1, lstm_cnn_out, feat_lstm_out);             % [80 batch]
    pred = predict(classifier_net, merged);                   % [nClasses batch]

    % --- Loss ---
    loss = crossentropy(pred, dlarray(single(double(T)), 'CB'));

    % --- Single backward pass through the whole graph ---
    [grad_cnn, grad_lstm_cnn, grad_feat_lstm, grad_classifier] = dlgradient(loss, ...
        cnn_net.Learnables, lstm_cnn_net.Learnables, feat_lstm_net.Learnables, classifier_net.Learnables);
end

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end