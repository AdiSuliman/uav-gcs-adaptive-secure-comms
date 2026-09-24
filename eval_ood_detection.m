%% EVAL_OOD_DETECTION.m — unknown-threat detection, leave-one-threat-out (D32)
% Proposal deliverable 4 and risk 13: can the detector tell that a frame belongs
% to a threat it was never trained on? For each threat class k, the hybrid
% detector is retrained from scratch without k (same architecture, data split and
% schedule as train_detector.m); class k then plays the unknown threat. On the
% test split, known-class frames (in-distribution) are compared with class-k
% frames (out-of-distribution) using two scores:
%   MSP    maximum softmax probability (Hendrycks & Gimpel, ICLR 2017)
%   energy logsumexp of the logits (Liu et al., NeurIPS 2020)
% Reported per held-out class: AUROC of each score, the share of unknown frames
% flagged at a threshold that keeps 95% of known validation frames, the share of
% known test frames wrongly flagged, the known class the unknown threat is mistaken
% for, and whether that mistake still leads to the same countermeasure.
% The production detector's own thresholds come from ood_thresholds.m.
%
% Runtime: one full detector training per held-out class (~7 min each on GPU).
% Output: results/ood_detection.{txt,mat}

close all; clc;
fprintf('=== Unknown-threat detection: leave-one-threat-out (D32) ===\n\n');

%% 1. Configuration and data
RETAIN   = 0.95;
N_EPOCHS = 30;                         % as train_detector.m
rng(2026, 'twister');

S = load('data/splits.mat', 'splits');
sp = S.splits;
all_classes = cellstr(string(sp.classes(:)'));
held_out = setdiff(all_classes, {'none'}, 'stable');
T_prod = ood_thresholds(RETAIN);
fprintf('Production detector thresholds (%.0f%% of known validation frames kept): MSP %.3f | energy %.2f\n\n', ...
    100*RETAIN, T_prod.msp, T_prod.energy);

R = struct('held_out', {}, 'auroc_msp', {}, 'auroc_energy', {}, 'thr_msp', {}, 'thr_energy', {}, ...
    'flag_msp', {}, 'flag_energy', {}, 'fp_msp', {}, 'fp_energy', {}, 'id_acc', {}, ...
    'mapped_to', {}, 'mapped_share', {}, 'same_action', {}, 'same_action_unflagged', {}, 'n_ood', {});

%% 2. One retraining per held-out class
t0 = tic;
for h = 1:numel(held_out)
    k = held_out{h};
    fprintf('[%d/%d] Held-out threat: %s\n', h, numel(held_out), k);
    known = setdiff(all_classes, {k}, 'stable');

    tr = subset(sp.train, known);
    va = subset(sp.val, known);
    te_id  = subset(sp.test, known);
    te_ood = subset(sp.test, {k});

    net = train_hybrid(tr, va, known, N_EPOCHS);

    [~, ~, msp_v, en_v] = cnn_scores(net, va.X, va.feats');
    thr_msp = lowq(msp_v, 1 - RETAIN);
    thr_en  = lowq(en_v,  1 - RETAIN);

    [pi_, ~, msp_i, en_i] = cnn_scores(net, te_id.X, te_id.feats');
    [po,  ~, msp_o, en_o] = cnn_scores(net, te_ood.X, te_ood.feats');

    [~, yi] = max(pi_, [], 1);
    id_acc = mean(strcmp(known(yi), cellstr(string(te_id.Y(:)'))));

    [~, yo] = max(po, [], 1);
    mapped = known(yo);
    [u, ~, ic] = unique(mapped);
    cnt = accumarray(ic(:), 1);
    [cmax, im] = max(cnt);
    true_act = rule_based_policy(k);
    same = cellfun(@(c) strcmp(rule_based_policy(c), true_act), mapped);
    unflagged = msp_o >= thr_msp;

    R(end+1) = struct('held_out', k, 'auroc_msp', auroc(msp_i, msp_o), 'auroc_energy', auroc(en_i, en_o), ...
        'thr_msp', thr_msp, 'thr_energy', thr_en, ...
        'flag_msp', mean(msp_o < thr_msp), 'flag_energy', mean(en_o < thr_en), ...
        'fp_msp', mean(msp_i < thr_msp), 'fp_energy', mean(en_i < thr_en), 'id_acc', id_acc, ...
        'mapped_to', u{im}, 'mapped_share', cmax / numel(mapped), 'same_action', mean(same), ...
        'same_action_unflagged', mean(same(unflagged)), 'n_ood', numel(msp_o)); %#ok<SAGROW>
    fprintf('    AUROC MSP %.3f | energy %.3f | flagged %.0f%% / %.0f%% | known acc %.1f%% (%.1f min)\n\n', ...
        R(end).auroc_msp, R(end).auroc_energy, 100*R(end).flag_msp, 100*R(end).flag_energy, ...
        100*id_acc, toc(t0)/60);
end

%% 3. Report
rep = {};
rep{end+1} = '=== UNKNOWN-THREAT DETECTION: LEAVE-ONE-THREAT-OUT (proposal deliverable 4, risk 13; D32) ===';
rep{end+1} = sprintf('Generated: %s | detector retrained without each threat (%d epochs), test split', datestr(now), N_EPOCHS);
rep{end+1} = sprintf('Threshold: keeps %.0f%% of known validation frames. AUROC 0.5 = no separation, 1.0 = perfect.', 100*RETAIN);
rep{end+1} = 'flagged = share of unknown-threat frames scored below the threshold; false flag = share of known test frames below it.';
rep{end+1} = 'same action = share of unknown frames whose mistaken class still maps to the countermeasure of the true threat (rule table).';
rep{end+1} = '';
rep{end+1} = sprintf('%-20s %5s %9s %9s %10s %10s %9s %9s %8s  %-26s %7s %9s', 'held-out threat', 'n', ...
    'AUROC MSP', 'AUROC En', 'flag MSP', 'flag En', 'false MSP', 'false En', 'known', 'mistaken for', 'same', 'same|kept');
for i = 1:numel(R)
    r = R(i);
    rep{end+1} = sprintf('%-20s %5d %9.3f %9.3f %9.0f%% %9.0f%% %8.1f%% %8.1f%% %7.1f%%  %-20s %3.0f%% %6.0f%% %8.0f%%', ...
        r.held_out, r.n_ood, r.auroc_msp, r.auroc_energy, 100*r.flag_msp, 100*r.flag_energy, ...
        100*r.fp_msp, 100*r.fp_energy, 100*r.id_acc, r.mapped_to, 100*r.mapped_share, ...
        100*r.same_action, 100*r.same_action_unflagged); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf('Mean AUROC: MSP %.3f | energy %.3f. Mean flagged: MSP %.0f%% | energy %.0f%%. Mean false flags: MSP %.1f%% | energy %.1f%%.', ...
    mean([R.auroc_msp]), mean([R.auroc_energy]), 100*mean([R.flag_msp]), 100*mean([R.flag_energy]), ...
    100*mean([R.fp_msp]), 100*mean([R.fp_energy]));
rep{end+1} = sprintf('Unknown frames that are neither flagged nor mapped to the right action (harmful misses), MSP: %.0f%% on average.', ...
    100*mean(arrayfun(@(r) (1 - r.flag_msp) * (1 - nz(r.same_action_unflagged)), R)));
rep{end+1} = sprintf('Production detector thresholds (all 9 classes known): MSP %.3f, energy %.2f (data/ood_thresholds.mat).', ...
    T_prod.msp, T_prod.energy);

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/ood_detection.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/ood_detection.mat', 'R', 'RETAIN', 'N_EPOCHS', 'T_prod');
fprintf('\nSaved results/ood_detection.{txt,mat} (%.1f min)\n', toc(t0)/60);


%% ===== Local functions =====
function d = subset(part, keep)
% Frames of a split whose label is in KEEP, with the categories reduced to KEEP.
y = cellstr(string(part.Y(:)));
m = ismember(y, keep);
d.X = part.X(:, :, :, m);
d.feats = part.feats(m, :);
d.Y = categorical(y(m), keep);
end

function net = train_hybrid(tr, va, classes, numEpochs)
% Same two-branch architecture, optimizer and schedule as train_detector.m.
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

miniBatchSize = 64; lr0 = 1e-3; dropPeriod = 10; dropFactor = 0.5;
Xs = dlarray(single(tr.X), 'SSCB');
Xf = dlarray(single(tr.feats)', 'CB');
Tt = dlarray(single(double(onehotencode(tr.Y, 2)')), 'CB');
Vs = dlarray(single(va.X), 'SSCB');
Vf = dlarray(single(va.feats)', 'CB');
[~, vt] = max(double(onehotencode(va.Y, 2)'), [], 1);
useGPU = canUseGPU;
if useGPU, net = dlupdate(@gpuArray, net); Vs = gpuArray(Vs); Vf = gpuArray(Vf); end

nTrain = size(tr.X, 4);
nIter = floor(nTrain / miniBatchSize);
avgG = []; avgSq = []; it = 0; bestAcc = -1; bestNet = net;
for ep = 1:numEpochs
    perm = randperm(nTrain);
    lr = lr0 * dropFactor^floor((ep - 1) / dropPeriod);
    for b = 1:nIter
        it = it + 1;
        idx = perm((b-1)*miniBatchSize + 1 : b*miniBatchSize);
        xs = Xs(:, :, :, idx); xf = Xf(:, idx); tt = Tt(:, idx);
        if useGPU, xs = gpuArray(xs); xf = gpuArray(xf); tt = gpuArray(tt); end
        [~, grads, state] = dlfeval(@model_loss, net, xs, xf, tt);
        net.State = state;
        [net, avgG, avgSq] = adamupdate(net, grads, avgG, avgSq, it, lr);
    end
    [~, vp] = max(extractdata(predict(net, Vs, Vf)), [], 1);
    acc = mean(gather(vp) == vt);
    if acc > bestAcc, bestAcc = acc; bestNet = net; end
end
net = bestNet;
fprintf('    trained %d classes, best validation accuracy %.3f\n', nClasses, bestAcc);
end

function [loss, grads, state] = model_loss(net, xs, xf, tt)
[y, state] = forward(net, xs, xf);
loss = crossentropy(y, tt);
grads = dlgradient(loss, net.Learnables);
end

function a = auroc(pos, neg)
% Probability that a known-class frame scores above an unknown one (ties count half).
pos = pos(:); neg = neg(:);
ranks = tiedrank_local([pos; neg]);
np = numel(pos); nn = numel(neg);
a = (sum(ranks(1:np)) - np*(np + 1)/2) / (np * nn);
end

function r = tiedrank_local(x)
[xs, ord] = sort(x(:));
n = numel(xs); r = zeros(n, 1);
i = 1;
while i <= n
    j = i;
    while j < n && xs(j + 1) == xs(i), j = j + 1; end
    r(ord(i:j)) = (i + j) / 2;
    i = j + 1;
end
end

function v = nz(v)
if isnan(v), v = 0; end
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end
