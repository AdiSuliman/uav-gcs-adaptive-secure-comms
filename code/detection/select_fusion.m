%% B2F - SELECT_FUSION: temporal fusion of the detector over the last decision cycles
% The per-frame detector decides on 0.5 ms of signal; the fusion
% (temporal_evidence.m, fuse_classes.m) decides on the last N cycles. It is fitted
% on the validation split, where the detector's outputs are not overconfident, and
% N and the regularization are chosen by cross-validation over the validation
% sub-runs (5 folds by sub-run, highest macro-F1). The fused decision is judged on its
% window (fusion_target.m: a WLAN frame without a packet whose window holds packet
% frames has the target benign_interference; the per-frame label stays). The
% out-of-fold predictions and their targets are kept for the KPI 1 threshold of
% eval_detector.m.
% The quiet-slot interference alarm of the rule (rule_based_policy.m) is set here from
% the clean validation frames (the sub-runs without a threat), as an AGC jamming monitor
% sets its threshold from interference-free samples, Th = mu - 3 sigma - 2 dB for a gain
% drop (Kazim et al. 2026, eq. 1.3, p. 2); the slot's power rises instead, so
% q_thr = mu + 3 sigma + 2 dB of q_iot. The threshold of the onset's shape, which the
% monitor's latched cause of a lost branch reads (onset_shape.m: a ramp above it, airframe
% shadowing; a step at or below it, an antenna fault), is chosen on the validation sub-runs
% of the two threats: the statistic at the latch's diagnosis of each sub-run's event on the
% threat's branch, the latch run as deployed (onset_shape.m 'events', decision_config.m
% heal), the threshold that reads the two causes right in the largest mean share
% (FM.os_thr). The monitor's class out of fold with the latch (val_latch_oof): the latch over
% the out-of-fold fused probabilities of every validation sub-run, its threshold chosen on the
% other folds' sub-runs. Whether the monitor latches at all (FM.latch, onset_shape('on', FM))
% is chosen here too: the latch only where its out-of-fold macro-F1 is above the fused class's
% (val_probs_oof), the measure that chose N and lambda; the per-event reading of a lost
% branch's cause (the first cycle from the onset read as antenna_fault or
% airframe_shadowing, the right one) is printed beside. The monitor's class out of fold, with
% or without the latch as chosen, sets the KPI 1 threshold of eval_detector.m. The test split
% is not used.
% Output: data/fusion.mat (FM with os_thr and latch, N, lambda, cv table, out-of-fold
% probabilities (fused, and with the latch) and their targets, q_thr)

close all; clc;
fprintf('=== B2F: temporal fusion (validation split only) ===\n\n');
S = load('data/splits.mat'); va = S.splits.val; norm = S.splits.norm;
if ~isfield(va, 'pos')
    error('splits.mat has no frame positions (v6 dataset). Run run_dataset_sweep, extract_spectrograms, prepare_data.');
end
va.feat_names = norm.feat_names;
D = load('data/trained_detector.mat', 'net', 'classes');
C = numel(D.classes);
classes = cellstr(string(D.classes(:)'));
P = cnn_scores(D.net, va.X, va.feats')';                 % frames x C
y = double(va.Y(:));
NS = [1 3 5 8 12];
LAMBDA = [1e-4 1e-3 1e-2];
K = 5;
runs = unique(va.run);
rs = RandStream('mt19937ar', 'Seed', 61);
fold_of_run = mod(randperm(rs, numel(runs)), K) + 1;
[~, ir] = ismember(va.run, runs);
fold = fold_of_run(ir)';

cv = zeros(numel(NS), numel(LAMBDA)); oof = cell(numel(NS), numel(LAMBDA));
for a = 1:numel(NS)
    Z = fuse_classes('windows', va, P, NS(a));
    yn = fusion_target(y, va.run, va.pos, NS(a), classes);
    for b = 1:numel(LAMBDA)
        pc = zeros(numel(y), C);
        for k = 1:K
            tr = fold ~= k; te = fold == k;
            FM = fuse_classes('fit', Z(tr, :), yn(tr), C, LAMBDA(b));
            pc(te, :) = fuse_classes('apply', FM, Z(te, :));
        end
        [~, yh] = max(pc, [], 2);
        cv(a, b) = macro_f1(yn, yh, C);
        oof{a, b} = pc;
        fprintf('  N = %2d cycles, lambda %.0e: macro-F1 %.2f%% (out of fold)\n', NS(a), LAMBDA(b), 100 * cv(a, b));
    end
end
[~, i] = max(cv(:)); [a, b] = ind2sub(size(cv), i);
N = NS(a); lambda = LAMBDA(b);
Z = fuse_classes('windows', va, P, N);
val_target = fusion_target(y, va.run, va.pos, N, classes);
FM = fuse_classes('fit', Z, val_target, C, lambda);
[~, y1] = max(P, [], 2);
yfr = y; if isfield(va, 'Y_frame'), yfr = double(va.Y_frame(:)); end   % the per-frame network's own labels
fprintf('\nSelected N = %d cycles, lambda %.0e: macro-F1 %.2f%% out of fold (per frame, frame rule %.2f%%)\n', ...
    N, lambda, 100 * cv(a, b), 100 * macro_f1(yfr, y1, C));
fprintf('WLAN frames without a packet judged by their window as benign_interference: %d of %d none frames\n', ...
    sum(val_target ~= y), sum(y == find(strcmp(classes, 'none'))));
val_probs_oof = oof{a, b};
qi = va.feats_raw(isnan(va.level), strcmp(va.feat_names, 'q_iot'));
q_thr = mean(qi) + 3 * std(qi) + 2;
fprintf('Quiet-slot interference alarm: %.2f dB over thermal (clean frames: mean %.2f, std %.2f dB, n = %d)\n', ...
    q_thr, mean(qi), std(qi), numel(qi));
iB = [find(strcmp(classes, 'antenna_fault')), find(strcmp(classes, 'airframe_shadowing'))];
heal = decision_config().heal;
og = []; oy = []; orun = [];                            % the statistic at the latch's diagnosis, the sub-run's cause
if numel(iB) == 2
    for r = runs(:)'
        ix = find(va.run == r); [~, o] = sort(va.pos(ix)); ix = ix(o);
        b = find(ismember(iB, y(ix)), 1);
        if isempty(b), continue; end
        j0 = find(y(ix) == iB(b), 1);                   % the threat's first labelled frame
        og(end+1) = onset_shape('events', va.gain_ant(ix, :), j0, heal); oy(end+1) = b; orun(end+1) = r; %#ok<SAGROW>
    end
end
FM.os_thr = onset_shape('choose', og, oy);
k = isfinite(og);
fprintf(['Onset shape: threshold %+.2f (validation sub-runs with a latched event on the threat''s branch: antenna ' ...
    'fault %d of %d, read right %.1f%%; airframe shadowing %d of %d, %.1f%%)\n'], FM.os_thr, sum(k & oy == 1), ...
    sum(oy == 1), 100 * mean(og(k & oy == 1) <= FM.os_thr), sum(k & oy == 2), sum(oy == 2), ...
    100 * mean(og(k & oy == 2) > FM.os_thr));
val_latch_oof = val_probs_oof;                          % the monitor's class out of fold
[~, ko] = ismember(orun, runs); ko = fold_of_run(ko);
for f = 1:K
    m = fold == f;
    tf = onset_shape('choose', og(ko ~= f), oy(ko ~= f));
    val_latch_oof(m, :) = latch_runs(val_probs_oof(m, :), va.run(m), va.pos(m), va.gain_ant(m, :), classes, tf, heal);
end
[~, yl] = max(val_latch_oof, [], 2); [~, yo] = max(val_probs_oof, [], 2);
mf_latch = macro_f1(val_target, yl, C); mf_fused = macro_f1(val_target, yo, C);
FM.latch = mf_latch > mf_fused;                         % the latch only where it raises macro-F1 out of fold
fprintf('Out of fold, the monitor''s class with the latched cause of a lost branch: macro-F1 %.2f%%; the fused class %.2f%%\n', ...
    100 * mf_latch, 100 * mf_fused);
[ef, nf] = event_cause(yo, val_target, va.run, va.pos, iB); [el, ~] = event_cause(yl, val_target, va.run, va.pos, iB);
fprintf(['Per event, the first cycle from the onset read as a lost branch reads the right cause: antenna fault %.1f%% ' ...
    'fused, %.1f%% latched (%d events); airframe shadowing %.1f%%, %.1f%% (%d events)\n'], 100 * ef(1), 100 * el(1), nf(1), ...
    100 * ef(2), 100 * el(2), nf(2));
if FM.latch
    fprintf('The monitor latches the cause of a lost branch (FM.latch = true)\n');
else
    fprintf('The monitor''s class is the fused class: the latch is off (FM.latch = false)\n');
end
if ~exist('results', 'dir'), mkdir('results'); end
save('data/fusion.mat', 'FM', 'N', 'lambda', 'NS', 'LAMBDA', 'cv', 'val_probs_oof', 'val_latch_oof', 'val_target', 'q_thr');
fprintf('Saved data/fusion.mat\n');

function [r, n] = event_cause(k, y, run, pos, iB)
% Per lost-branch class (iB: antenna_fault, airframe_shadowing), the share of the validation
% sub-runs whose first cycle from the class's onset read as either class reads the right one
% (never read: wrong), and their number.
r = nan(1, 2); n = zeros(1, 2);
if numel(iB) < 2, return; end
ok = zeros(1, 2);
for q = unique(run(ismember(y, iB)))'
    ix = find(run == q); [~, o] = sort(pos(ix)); ix = ix(o);
    for b = 1:2
        j0 = find(y(ix) == iB(b), 1);
        if isempty(j0), continue; end
        j = find(ismember(k(ix(j0:end)), iB), 1);
        n(b) = n(b) + 1;
        if ~isempty(j), ok(b) = ok(b) + (k(ix(j0 + j - 1)) == iB(b)); end
    end
end
r = ok ./ max(n, 1);
end

function m = macro_f1(y, yh, C)
f = zeros(1, C);
for c = 1:C
    tp = sum(yh == c & y == c); fp = sum(yh == c & y ~= c); fn = sum(yh ~= c & y == c);
    f(c) = 2 * tp / max(2 * tp + fp + fn, 1);
end
m = mean(f);
end
