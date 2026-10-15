%% EVAL_OOD_DETECTION.m - unknown-threat detection, leave-one-threat-out
% Proposal deliverable 4 (alert on a threat not seen in training) and the leave-one-threat-out KPI.
% For each threat class k the detector is retrained from scratch without k
% (train_hybrid_net.m, same schedule as production), the link features are
% re-normalized on the known classes only, and the unknown-threat models are
% refitted (fit_ood_model.m). Class k then plays the unknown threat. Scores
% (higher = more like the known classes):
%   msp, energy   maximum softmax probability and logsumexp of the logits: baselines
%   iforest       isolation forest on the link features alone (Liu, Ting & Zhou)
%   candidates of the production score (ood_score_set.m): last, ensemble, raw,
%                 last_or_raw, last_or_if, last_pre, last_l2 (Mahalanobis++, Mueller & Hein 2025)
% Every score is read as the decision cycle reads it (ood_fold_metrics.m): alone (one
% frame) and averaged over the last 2, 5 and 8 cycles of each sub-run in time order
% (ood_window.m, partial windows at its start), every window labelled by its newest frame.
% Frames of one fold (ood_loto_split.m, labels by the frame rule, frame_labels.m): the known
% classes' training frames train the network and fit the unknown-threat models; the
% validation sub-runs are split in two halves (stratified over class, level and Eb/N0,
% ood_loto_split.m): the known frames of one half stop the training
% early and fit the models' validation parts, the known windows of the other half are read
% against the held-out threat's validation windows for the selection and set the
% threshold of FPR95. The held-out threat never fits, weights or chooses anything inside
% its fold. AUROC, FPR95 (share of unknown windows accepted as known at the threshold that
% keeps 95% of the known validation windows) and Algorithm 2 are read on the second test
% set (data/splits_fresh.mat, build_fresh_test: sub-runs no decision has read); the test
% split of data/splits.mat is not read.
% Selection, on validation only: the production score and its window are the (candidate,
% window) pair with the highest mean validation AUROC over the held-out threats, among
% the candidates that fit the decision-cycle budget of KPI 7: each candidate's detector cost
% on one frame is measured first on the production detector (ood_latency.m, timed as
% measure_latency.m times it, with the machine's load logged beside the timings), and a
% candidate whose median exceeds 5 ms or p95 10 ms (half of the KPI 7 targets,
% kpi7_admit.m) is excluded and reported with its cost. The selected pair is written to
% data/trained_detector.mat (ood.score, ood.win) and the thresholds are recomputed on the
% statistic the decision cycle compares with them (ood_thresholds.m), so this stage runs
% before the frame pools (C1p). The value to quote is the nested estimate: for each
% held-out threat, the pair chosen on the validation AUROC of the OTHER threats (within
% the same budget), read on this one's test frames.
% Learning the new threat (Lee et al., Algorithm 2): once flagged and labelled, the
% held-out threat is added as a new class from K of its validation frames (never
% used in the fold) by its mean and an update of the tied covariance in the last
% hidden layer, without retraining the network; its test frames are then
% classified by the smallest Mahalanobis distance (K = 100 random frames, 5 draws,
% and all of them), and the known classes are checked for the cost.
% Output: results/ood_detection.{txt,mat}

close all; clc;
fprintf('=== Unknown-threat detection: leave-one-threat-out ===\n\n');

%% 1. Configuration and data
RETAIN   = 0.95;
N_EPOCHS = 30;                         % as train_detector.m
WIN      = [2 5 8];                    % decision cycles of the averaged score
rng(2026, 'twister');

S = load('data/splits.mat', 'splits');
sp = S.splits; clear S
sp.test = [];                          % the test split is not read here
if ~isfile('data/splits_fresh.mat')
    error('eval_ood_detection:fresh', 'data/splits_fresh.mat not found: run build_fresh_test (B3n) first');
end
Sf = load('data/splits_fresh.mat', 'splits');
assert(isequal(Sf.splits.norm, sp.norm), 'eval_ood_detection: the second test set has another normalization');
assert(isequal(Sf.splits.classes, sp.classes), 'eval_ood_detection: the second test set has other classes');
fresh = Sf.splits.test; clear Sf
all_classes = cellstr(string(sp.classes(:)'));
held_out = setdiff(all_classes, {'none'}, 'stable');
if exist('SMOKE', 'var') && SMOKE, held_out = held_out(1:2); N_EPOCHS = 3; end   % reduced chain check
D0 = load('data/trained_detector.mat', 'net', 'ood');
if ~isfield(D0.ood, 'forest_pack'), D0.ood.forest_pack = iforest_pack(D0.ood.forest); end   % a detector without the packed trees
CAND = D0.ood.candidates;
N_LAT = 200; if exist('SMOKE', 'var') && SMOKE, N_LAT = 30; end   % timed calls per candidate and device
LC = ood_latency(D0.net, D0.ood, sp.val.X, sp.val.feats', N_LAT);
fprintf('Detector cost per frame on the device with the lower p95 (median / p95 ms):\n');
for c = 1:numel(CAND)
    fprintf('  %-12s %s %7.2f / %7.2f%s\n', CAND{c}, upper(LC.dev{c}), LC.med(c), LC.p95(c), ternary(LC.ok(c), '', '  EXCLUDED'));
end
fprintf('%s\n\n', load_text(LC.load));
SC = [{'msp', 'energy', 'iforest'}, CAND];
WALL = [1 WIN];                        % window 1 = the frame alone
R = struct('held_out', {}, 'n_ood', {}, 'n_val_ood', {}, 'auroc', {}, 'fpr95', {}, 'auroc_win', {}, ...
    'auroc_val', {}, 'auroc_win_val', {}, 'fpr95_win', {}, 'id_acc', {}, 'mapped_to', {}, 'same_action', {}, 'incr', {});
K_NEW = 100; N_DRAW = 5;               % Algorithm 2: frames of the new threat, random draws

%% 2. One retraining per held-out class
t0 = tic;
for h = 1:numel(held_out)
    k = held_out{h};
    fprintf('[%d/%d] Held-out threat: %s\n', h, numel(held_out), k);
    known = setdiff(all_classes, {k}, 'stable');
    [tr, vfit, va, vk, te] = ood_loto_split(sp, fresh, k);

    net = train_hybrid_net(tr, vfit, known, struct('verbose', false, 'epochs', N_EPOCHS));
    M = fit_ood_model(net, tr, known, vfit);

    Sv = all_scores(net, M, va);
    St = all_scores(net, M, te);
    yv = cellstr(string(va.Y)); yt = cellstr(string(te.Y));
    V = struct('run', va.run, 'pos', va.pos, 'kn', ismember(yv, known) & va.sel, 'un', strcmp(yv, k));
    T = struct('run', te.run, 'pos', te.pos, 'kn', ismember(yt, known), 'un', strcmp(yt, k));
    Q = ood_fold_metrics(Sv, V, St, T, SC, WALL, RETAIN);

    [~, yi] = max(St.probs(:, T.kn), [], 1);
    id_acc = mean(strcmp(known(yi), yt(T.kn)'));
    [~, yo] = max(St.probs(:, T.un), [], 1);
    mapped = known(yo);
    [u, ~, ic] = unique(mapped); [~, im] = max(accumarray(ic(:), 1));
    true_act = rule_based_policy(k);
    same = mean(cellfun(@(c) strcmp(rule_based_policy(c), true_act), mapped));
    te_id = pick(te, T.kn, known); te_ood = pick(te, T.un, {k});
    inc = learn_new_class(net, M, te_id, te_ood, vk, K_NEW, N_DRAW);
    clear te_id te_ood
    R(end+1) = struct('held_out', k, 'n_ood', sum(T.un), 'n_val_ood', sum(V.un), 'auroc', Q.test(:, 1)', ...
        'fpr95', Q.fpr(:, 1)', 'auroc_win', Q.test(:, 2:end), 'auroc_val', Q.val(:, 1)', ...
        'auroc_win_val', Q.val(:, 2:end), 'fpr95_win', Q.fpr(:, 2:end), 'id_acc', id_acc, ...
        'mapped_to', u{im}, 'same_action', same, 'incr', inc); %#ok<SAGROW>
    ca = [SC; num2cell(Q.test(:, 1)')]; cv = [SC; num2cell(Q.val(:, 1)')];
    fprintf(['    AUROC test  %s\n    AUROC val   %s\n    known acc %.1f%% | learned from %d frames: new threat ' ...
        '%.1f%%, known %.1f%% (%.1f min)\n\n'], sprintf('%s %.3f  ', ca{:}), sprintf('%s %.3f  ', cv{:}), ...
        100*id_acc, K_NEW, 100*inc.new_k, 100*inc.known_k, toc(t0)/60);
    clear tr vfit va vk te Sv St net M
end

%% 3. Selection of the production score on validation, nested estimate on the test frames
jc = find(ismember(SC, CAND));
nP = numel(jc) * numel(WALL);
MpV = zeros(numel(R), nP); MpT = MpV; FpT = MpV; pj = zeros(1, nP); pw = pj;
c = 0;
for j = jc                                              % (candidate, window) pairs
    for w = 1:numel(WALL)
        c = c + 1; pj(c) = j; pw(c) = WALL(w);
        for i = 1:numel(R)
            av = [R(i).auroc_val(j), R(i).auroc_win_val(j, :)];
            at = [R(i).auroc(j), R(i).auroc_win(j, :)];
            ft = [R(i).fpr95(j), R(i).fpr95_win(j, :)];
            MpV(i, c) = av(w); MpT(i, c) = at(w); FpT(i, c) = ft(w);
        end
    end
end
[~, ic] = ismember(SC(pj), CAND);
[b, nb] = ood_select(MpV, LC.ok(ic));                  % pairs of the candidates within the KPI 7 budget only
sel = SC{pj(b)}; sel_win = pw(b);
NEST = struct('auroc', zeros(1, numel(R)), 'fpr95', zeros(1, numel(R)), 'auroc_val', zeros(1, numel(R)), ...
    'pick', {cell(1, numel(R))});
for i = 1:numel(R)
    NEST.auroc(i) = MpT(i, nb(i)); NEST.fpr95(i) = FpT(i, nb(i)); NEST.auroc_val(i) = MpV(i, nb(i));
    NEST.pick{i} = sprintf('%s over %d', SC{pj(nb(i))}, pw(nb(i)));
end
if ~(exist('SMOKE', 'var') && SMOKE)
    D = load('data/trained_detector.mat', 'ood'); ood = D.ood; ood.score = sel; ood.win = sel_win;
    if ~isfield(ood, 'forest_pack'), ood.forest_pack = D0.ood.forest_pack; end
    save('data/trained_detector.mat', 'ood', '-append');
    if isfile('data/ood_thresholds.mat'), delete('data/ood_thresholds.mat'); end
end
T_prod = ood_thresholds(RETAIN);

%% 4. Report
A = vertcat(R.auroc); F = vertcat(R.fpr95); Av = vertcat(R.auroc_val);
AW = cat(3, R.auroc_win); AWv = cat(3, R.auroc_win_val);   % scores x windows x held-out threats
js = find(strcmp(SC, sel));
rep = {};
rep{end+1} = '=== UNKNOWN-THREAT DETECTION: LEAVE-ONE-THREAT-OUT ===';
rep{end+1} = sprintf(['Generated: %s | detector retrained without each threat (%d epochs) | selection on the validation ' ...
    'split, reading on the second test set (data/splits_fresh.mat, %d frames); the test split of the dataset is not read'], ...
    datestr(now), N_EPOCHS, numel(fresh.Y));
rep{end+1} = sprintf(['AUROC: 0.5 = no separation, 1 = perfect. Every score read as the decision cycle reads it: windows ' ...
    'of the last cycles of each sub-run in time order, labelled by their newest frame. FPR95: unknown windows accepted ' ...
    'as known at the threshold keeping %.0f%% of the known validation windows.'], 100*RETAIN);
rep{end+1} = '';
w8 = max(8, max(cellfun(@numel, SC)) + 1);
rep{end+1} = sprintf('%-20s %5s |%s | %6s  %-20s %5s', 'held-out threat', 'n', sprintf(sprintf(' %%%ds', w8), SC{:}), ...
    'known', 'mistaken for', 'same');
rep{end+1} = sprintf('%-20s %5s |%s |', '', '', sprintf(sprintf(' %%%ds', w8), 'AUROC'));
for i = 1:numel(R)
    r = R(i);
    rep{end+1} = sprintf('%-20s %5d |%s | %5.1f%%  %-20s %4.0f%%', r.held_out, r.n_ood, ...
        sprintf(sprintf(' %%%d.3f', w8), r.auroc), 100*r.id_acc, r.mapped_to, 100*r.same_action); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %5s |%s |', 'mean AUROC (test)', '', sprintf(sprintf(' %%%d.3f', w8), mean(A, 1)));
rep{end+1} = sprintf('%-20s %5s |%s |', 'mean FPR95 (test)', '', sprintf(sprintf(' %%%d.2f', w8), mean(F, 1)));
for w = 1:numel(WIN)
    rep{end+1} = sprintf('%-20s %5s |%s |', sprintf('mean AUROC, %d cycles', WIN(w)), '', ...
        sprintf(sprintf(' %%%d.3f', w8), mean(squeeze(AW(:, w, :)), 2))); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %5s |%s |', 'mean AUROC (val)', '', sprintf(sprintf(' %%%d.3f', w8), mean(Av, 1)));
for w = 1:numel(WIN)
    rep{end+1} = sprintf('%-20s %5s |%s |', sprintf('val, %d cycles', WIN(w)), '', ...
        sprintf(sprintf(' %%%d.3f', w8), mean(squeeze(AWv(:, w, :)), 2))); %#ok<SAGROW>
end
rep{end+1} = '';
rep{end+1} = sprintf(['Detector cost per frame, one forward pass with the score (ood_latency.m: %d timed calls after ' ...
    'a warm-up, as measure_latency.m), median / p95 ms; KPI 7 budget (D80): median <= %.0f ms and p95 <= %.0f ms on ' ...
    'the device with the lower p95 (half of the %.0f / %.0f ms targets):'], LC.n, LC.budget.det_median_ms, ...
    LC.budget.det_p95_ms, LC.budget.median_ms, LC.budget.p95_ms);
for c = 1:numel(CAND)
    rep{end+1} = sprintf('  %-12s %s -> %s %s', CAND{c}, strjoin(cellfun(@(d, m, q) sprintf('%s %7.2f / %7.2f', ...
        upper(d), m, q), LC.devices, num2cell(LC.med_ms(c, :)), num2cell(LC.p95_ms(c, :)), 'UniformOutput', false), ...
        ' | '), upper(LC.dev{c}), ternary(LC.ok(c), 'within the budget', 'EXCLUDED (over the budget)')); %#ok<SAGROW>
end
rep{end+1} = sprintf(['  %s. A concurrent load can only slow the calls, so a candidate admitted here fits on an idle ' ...
    'machine too (conservative); one excluded under load may fit idle.'], load_text(LC.load));
rep{end+1} = sprintf(['Production score (highest mean validation AUROC among %s, each over 1, %s cycles): %s over %d ' ...
    'cycles, mean AUROC validation %.3f, test %.3f, FPR95 test %.2f (single frame: test AUROC %.3f, FPR95 %.2f).'], ...
    strjoin(CAND(LC.ok), ', '), strjoin(compose('%d', WIN), ', '), sel, sel_win, mean(MpV(:, b)), mean(MpT(:, b)), ...
    mean(FpT(:, b)), mean(A(:, js)), mean(F(:, js)));
if ~all(LC.ok)
    rep{end+1} = sprintf('Excluded by the KPI 7 budget (their AUROC above is reported, never selected): %s.', ...
        strjoin(CAND(~LC.ok), ', '));
end
rep{end+1} = sprintf(['Nested estimate (pair chosen on the validation AUROC of the other held-out threats, read on this ' ...
    'one''s test frames; the value to quote): mean AUROC %.3f, FPR95 %.2f; per threat %s; picks %s.'], mean(NEST.auroc), ...
    mean(NEST.fpr95), sprintf('%.3f ', NEST.auroc), strjoin(unique(NEST.pick, 'stable'), ', '));
rep{end+1} = sprintf(['Production thresholds (%.0f%% of the known validation frames kept; the unknown-threat score on ' ...
    'the statistic of the decision cycle, its mean over the last %d cycles): MSP %.3f | energy %.2f | %s %.3f ' ...
    '(per frame %.3f).'], 100*RETAIN, T_prod.win, T_prod.msp, T_prod.energy, T_prod.score, T_prod.maha, T_prod.maha_frame);
IN = [R.incr];
rep{end+1} = '';
rep{end+1} = sprintf(['Learning the new threat without retraining (Lee et al., Algorithm 2; last hidden layer, generative ' ...
    'classifier; test frames of the second test set): known-class accuracy before %.1f%% (softmax %.1f%%)'], ...
    100*mean([IN.known_before]), 100*mean([R.id_acc]));
rep{end+1} = sprintf('%-20s %22s %22s %18s', 'new threat', sprintf('%d frames: new / known', K_NEW), 'all val frames', 'frames available');
for i = 1:numel(R)
    rep{end+1} = sprintf('%-20s %13.1f%% / %5.1f%% %13.1f%% / %5.1f%% %18d', R(i).held_out, 100*IN(i).new_k, ...
        100*IN(i).known_k, 100*IN(i).new_all, 100*IN(i).known_all, IN(i).n_val); %#ok<SAGROW>
end
rep{end+1} = sprintf('%-20s %13.1f%% / %5.1f%% %13.1f%% / %5.1f%%', 'mean', 100*mean([IN.new_k]), 100*mean([IN.known_k]), ...
    100*mean([IN.new_all]), 100*mean([IN.known_all]));
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/ood_detection.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
TEST_SET = 'second test set (data/splits_fresh.mat)';
save('results/ood_detection.mat', 'R', 'SC', 'CAND', 'sel', 'sel_win', 'NEST', 'WIN', 'RETAIN', 'N_EPOCHS', 'T_prod', ...
    'K_NEW', 'LC', 'MpV', 'MpT', 'FpT', 'pj', 'pw', 'TEST_SET');
fprintf('\nSaved results/ood_detection.{txt,mat}; production score written to data/trained_detector.mat (%.1f min)\n', toc(t0)/60);
clear sp fresh


%% ===== Local functions =====
function inc = learn_new_class(net, M, te_id, te_ood, vk, K, ND)
% Lee et al., Algorithm 2: the held-out threat becomes class C+1 from its
% validation frames (mean, and the tied covariance updated as C/(C+1) old +
% 1/(C+1) new); classification by the smallest Mahalanobis distance in the last
% hidden layer. new = held-out test frames recognized, known = known test frames
% still correct.
L = M.layers(end);
fi = ood_layer_features(net, L, te_id.X, te_id.feats'); fi = fi{1};
fo = ood_layer_features(net, L, te_ood.X, te_ood.feats'); fo = fo{1};
fv = ood_layer_features(net, L, vk.X, vk.feats'); fv = fv{1};
yid = double(te_id.Y(:))';
mu = M.mu{end}; Sig = inv(M.P{end}); nC = size(mu, 2);
inc.known_before = mean(md_class(fi, mu, M.P{end}) == yid);
inc.n_val = size(fv, 2);
rs = RandStream('mt19937ar', 'Seed', 5);
r = zeros(ND, 2);
for d = 1:ND
    X = fv(:, randperm(rs, size(fv, 2), min(K, size(fv, 2))));
    [r(d, 1), r(d, 2)] = add_and_score(X, mu, Sig, nC, fo, fi, yid);
end
inc.new_k = mean(r(:, 1)); inc.known_k = mean(r(:, 2));
[inc.new_all, inc.known_all] = add_and_score(fv, mu, Sig, nC, fo, fi, yid);
end

function [a_new, a_known] = add_and_score(X, mu, Sig, nC, fo, fi, yid)
% Class C+1 from the frames X; share of new-threat and known test frames classified right.
Su = nC / (nC + 1) * Sig + 1 / (nC + 1) * cov(X', 1);
P = inv(Su); mu2 = [mu, mean(X, 2)];
a_new = mean(md_class(fo, mu2, P) == nC + 1);
a_known = mean(md_class(fi, mu2, P) == yid);
end

function y = md_class(F, mu, P)
% Class of the smallest Mahalanobis distance (Lee et al., eq. 3).
D2 = zeros(size(mu, 2), size(F, 2));
for c = 1:size(mu, 2)
    Dc = F - mu(:, c); D2(c, :) = sum(Dc .* (P * Dc), 1);
end
[~, y] = min(D2, [], 1);
end

function d = pick(P, m, cats)
% Frames m of a fold's set, Y over the categories cats.
d.X = P.X(:, :, :, m); d.feats = P.feats(m, :);
d.Y = categorical(cellstr(string(P.Y(m))), cats);
end

function S = all_scores(net, M, P)
[S.probs, ~, S.msp, S.energy] = cnn_scores(net, P.X, P.feats');
[~, T] = ood_scores(net, M, P.X, P.feats');
for f = fieldnames(T)', S.(f{1}) = T.(f{1}); end
end

function s = load_text(L)
% The machine's load logged with the timings (machine_load.m).
s = sprintf(['Timed with the machine''s load logged before / after: CPU %s / %s %%, other MATLAB processes ' ...
    '%s / %s'], num_txt(L.before.cpu_pct), num_txt(L.after.cpu_pct), num_txt(L.before.n_matlab - 1), ...
    num_txt(L.after.n_matlab - 1));
end

function s = num_txt(v)
if isnan(v), s = 'n/a'; else, s = sprintf('%g', round(v)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
