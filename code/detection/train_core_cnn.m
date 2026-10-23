%% B3c - TRAIN_CORE_CNN: the proposal's CNN on spectrograms only, three link states
% Deliverable 2 of the revised proposal as worded: a CNN on the spectrogram of the received
% signal classifies the clean link, narrowband jamming (tone_jamming) and wideband jamming
% (jamming, the barrage noise jammer). Protocol: docs/core_cnn_protocol.md, fixed before any
% run; its SHA-256 goes into the model and is checked before the reading.
% 1. Training, when data/core_cnn_model.mat is missing or older than data/splits.mat: the
%    three states' sub-runs of the training split (core_cnn_frames.m), train_spec_net.m on
%    every schedule of core_cnn_config.m, the schedule and epoch with the best validation
%    macro-F1 (a tie to the shorter); the window N of the temporal decision (the mean
%    log-probability over the last N cycles of the sub-run, core_cnn_eval 'logp') by the
%    one-standard-error rule over 5 folds of validation sub-runs. With CORE_CNN_TRAIN_ONLY
%    true in the calling workspace the stage ends there; so does a smoke run (SMOKE), whose
%    2-epoch model is marked smoke, never read and retrained by the next normal run. Once a
%    reading started or is recorded (aborted records included) the model is not retrained.
% 2. The single reading of the fourth test set (data/splits_fresh3.mat), after the hybrid's
%    own reading of it (B3r) or under a committed docs/core_cnn_no_b3r.txt that declares no
%    B3r before this reading: the protocol's guards (section 5), then the marker
%    results/core_cnn_read_started.txt before the set is loaded; the core CNN windowed and
%    per frame and, when B3r's reading exists, the hybrid's saved monitor class on the same
%    frames read as three states (three_state_view.m's mapping), with 95% intervals by test
%    sub-run. No outcome line is printed before every metric is computed.
% Inputs are the working folder's own, or the files CORE_CNN_IN names elsewhere (a struct,
% core_cnn_inputs.m), only loaded; every output goes into the working folder, which must lie
% outside the tree of every such input.
% It never writes data/trained_detector.mat, data/fusion.mat or data/ood_thresholds.mat.
% Output: data/core_cnn_model.mat, results/core_cnn_validation.txt, results/core_cnn_training.png;
% results/core_cnn_predictions.mat, results/core_cnn.mat, results/core_cnn.txt,
% results/core_cnn_confusion.png, results/core_cnn_confusion_frame.png, results/core_cnn_ebno.png,
% results/core_cnn_jsr.png

close all; clc;
fprintf('=== B3c: CNN on spectrograms, three link states ===\n\n');
CC = core_cnn_config();
nS = numel(CC.groups);
assert(isfile(CC.protocol), 'train_core_cnn:protocol', '%s not found: the protocol is fixed before any run', CC.protocol);
psha = cc_sha(CC.protocol);
if exist('CORE_CNN_IN', 'var'), IN = core_cnn_inputs(CC, CORE_CNN_IN, pwd); else, IN = core_cnn_inputs(CC); end
assert(isfile(IN.splits), 'train_core_cnn:splits', '%s not found: run B1', IN.splits);
if ~isfolder('data'), mkdir('data'); end
if ~isfolder('results'), mkdir('results'); end
SMK = exist('SMOKE', 'var') && isequal(SMOKE, true);   % reduced chain check (run_stage smoke): trains, never reads

%% 1. Training and the choices on validation
if ~isfile(CC.model) || dir(CC.model).datenum < dir(IN.splits).datenum || (~SMK && cc_smoke(CC.model))
    pid0 = ''; if isfile(IN.params), pid0 = params_id(load(IN.params).params); end
    assert(~isfile(CC.marker) && ~isfile('results/core_cnn.mat') && ~cc_recorded(pid0, true), 'train_core_cnn:read', ...
        ['the fourth test set was read with an earlier model (%s, results/core_cnn.mat or a docs/core_cnn_read_*.txt ' ...
        'record, aborted ones included): the model is not retrained'], CC.marker);
    fprintf('Loading %s (training and validation)...\n', IN.splits);
    S = load(IN.splits, 'splits'); sp = S.splits; clear S
    classes = cellstr(string(sp.classes(:)'));
    assert(isfield(sp.val, 'pos'), 'train_core_cnn:pos', 'the validation split has no frame positions: rerun A5, A6, B1');
    [mt, yt, it] = core_cnn_frames(sp.train, classes, CC.groups);
    [mv, yv, iv] = core_cnn_frames(sp.val, classes, CC.groups);
    Xt = sp.train.X(:, :, :, mt); Xv = sp.val.X(:, :, :, mv);
    va = struct('run', sp.val.run(mv), 'pos', sp.val.pos(mv));
    nrt = cc_runs(sp.train.run(mt), yt, nS); nrv = cc_runs(va.run, yv, nS);
    clear sp mt mv
    fprintf('States %s\n', strjoin(cellfun(@(n, g) sprintf('%s (%s)', n, g), CC.names, CC.groups, 'UniformOutput', false), ', '));
    fprintf('Training frames %s (sub-runs %s), left out %s\n', mat2str(accumarray(yt, 1, [nS 1])'), mat2str(nrt), mat2str(it.n_off));
    fprintf('Validation frames %s (sub-runs %s), left out %s\n', mat2str(accumarray(yv, 1, [nS 1])'), mat2str(nrv), mat2str(iv.n_off));
    ep = CC.epochs;
    if SMK, ep = 2; end
    nets = cell(1, numel(ep)); infos = cell(1, numel(ep));
    for e = 1:numel(ep)
        rng(CC.seed, 'twister');
        fprintf('\nSchedule of %d epochs\n', ep(e));
        [nets{e}, infos{e}] = train_spec_net(Xt, yt, Xv, yv, nS, struct('epochs', ep(e)));
    end
    val_best = cellfun(@(i) i.bestValF1, infos);
    [~, e] = max(val_best);                              % the first maximum: a tie to the shorter schedule
    net = nets{e}; info = infos{e}; schedules = ep; all_info = infos; clear nets Xt
    Pv = spec_scores(net, Xv); clear Xv
    [N, NT] = core_cnn_eval('choose', Pv, yv, va.run, va.pos, CC.NS, CC.K, CC.fold_seed);
    [~, yv1] = max(Pv, [], 2);
    [~, yvN] = max(core_cnn_eval('logp', Pv, va.run, va.pos, N), [], 2);
    val = struct('frame', core_cnn_eval('metrics', yv, yv1, nS), 'window', core_cnn_eval('metrics', yv, yvN, nS), ...
        'n_frames', accumarray(yv, 1, [nS 1])', 'n_runs', nrv, 'left_out', iv.n_off, 'window_table', NT);
    groups = CC.groups; names = CC.names; protocol_sha = psha; trained_at = now; smoke = SMK; %#ok<NASGU>
    tmp = 'data/core_cnn_model_new.mat';
    save(tmp, 'net', 'info', 'N', 'classes', 'groups', 'names', 'schedules', 'val_best', 'all_info', 'val', ...
        'protocol_sha', 'trained_at', 'smoke', '-v7.3');
    commit_mat(tmp, CC.model);
    fprintf('Saved %s\n', CC.model);
    vrep = {'=== THREE-STATE CNN: VALIDATION (every choice of the model) ===', ...
        sprintf('Generated: %s | validation split of %s | protocol %s sha256 %s', datestr(now), IN.splits, CC.protocol, psha), ''};
    for k = 1:numel(ep)
        vrep{end+1} = sprintf('schedule %2d epochs: best epoch %2d, validation macro-F1 per frame %.2f%%%s', ep(k), ...
            all_info{k}.bestEpoch, 100 * val_best(k), repmat('  <- kept', 1, k == e)); %#ok<SAGROW>
    end
    vrep{end+1} = sprintf('window N (mean log-probability over the last N cycles of the sub-run; %d folds by sub-run, seed %d):', CC.K, CC.fold_seed);
    for a = 1:numel(CC.NS)
        vrep{end+1} = sprintf('  N = %2d: macro-F1 %.2f%%  (folds %s)%s', CC.NS(a), 100 * NT.cv(a), ...
            sprintf('%.1f ', 100 * NT.fold(a, :)), repmat('  <- chosen', 1, CC.NS(a) == N)); %#ok<SAGROW>
    end
    vrep{end+1} = sprintf('best N = %d, standard error %.2f points over the folds; the shortest N within it: %d', NT.best, 100 * NT.se, N);
    vrep{end+1} = sprintf(['validation, per frame: macro-F1 %.2f%%, recall %s; window N = %d: macro-F1 %.2f%%, recall %s ' ...
        '(the epoch was chosen on these frames: a slight optimistic bias)'], 100 * val.frame.macro_f1, ...
        cc_pct(val.frame.recall), N, 100 * val.window.macro_f1, cc_pct(val.window.recall));
    fid = fopen('results/core_cnn_validation.txt', 'w'); fprintf(fid, '%s\n', vrep{:}); fclose(fid);
    fprintf('\n%s\n', vrep{:});
    fig = figure('Color', 'w', 'Position', [100 100 720 380]);
    hold on; grid on;
    for k = 1:numel(ep), plot(100 * all_info{k}.valF1, 'LineWidth', 1.4, 'DisplayName', sprintf('%d epochs', ep(k))); end
    xline(info.bestEpoch, '--k', sprintf('kept: epoch %d', info.bestEpoch));
    xlabel('Epoch'); ylabel('Validation macro-F1, three states (%)'); legend('Location', 'southeast');
    title('Three-state spectrogram CNN: validation per epoch');
    saveas(fig, 'results/core_cnn_training.png'); close(fig);
    clear net info all_info Pv yv yv1 yvN va val vrep fig tmp smoke pid0
end
if SMK
    fprintf('SMOKE: a reduced model is trained (marked smoke); the fourth test set is not read\n');
    clear SMK
    return
end
if exist('CORE_CNN_TRAIN_ONLY', 'var') && CORE_CNN_TRAIN_ONLY
    fprintf('CORE_CNN_TRAIN_ONLY: the model is trained; the fourth test set is not read\n');
    clear CORE_CNN_TRAIN_ONLY SMK
    return
end

%% 2. The single reading of the fourth test set (protocol, section 5)
Mo = load(CC.model, 'protocol_sha');
assert(isfield(Mo, 'protocol_sha') && strcmp(Mo.protocol_sha, psha), 'train_core_cnn:protocol_changed', ...
    '%s changed since the model was trained: the protocol is fixed before the reading', CC.protocol);
assert(~cc_smoke(CC.model), 'train_core_cnn:smoke', ...
    '%s was trained in a reduced chain check (run_stage smoke): a normal run retrains it', CC.model);
assert(strcmp(kpi1_set(), 'fresh3'), 'train_core_cnn:kpi1_set', ...
    'the fourth test set is read only once kpi1_set.m names it (docs/d91_set4.md)');
HYB = isfile(IN.hybrid_metrics) && isfile(IN.hybrid_pred);   % B3r's reading of the set exists
[NOB, nob, why] = cc_no_b3r(CC.no_b3r);
assert(HYB || (NOB && ~isfile(IN.hybrid_metrics) && ~isfile(IN.hybrid_pred)), 'train_core_cnn:hybrid', ...
    ['the hybrid''s fourth-set reading (%s, %s) comes first (run B3r), unless a committed %s declares that no B3r ' ...
    'comes before this reading and no part of B3r''s reading exists (%s)'], IN.hybrid_metrics, IN.hybrid_pred, CC.no_b3r, why);
assert(isfile(IN.test), 'train_core_cnn:fresh3', '%s not found: run B3q', IN.test);
assert(isfile(IN.params), 'train_core_cnn:params', '%s not found', IN.params);
pid = params_id(load(IN.params).params);
assert(isfile(IN.test_params) && ismember('params', {whos('-file', IN.test_params).name}) && ...
    strcmp(params_id(load(IN.test_params).params), pid), 'train_core_cnn:params', ...
    '%s is missing or names another link model than %s (params_id %s)', IN.test_params, IN.params, pid);
assert(HYB || strcmp(nob.params_id, pid), 'train_core_cnn:no_b3r', ...
    '%s names params_id %s, the link model is %s: the declaration covers another profile', CC.no_b3r, nob.params_id, pid);
assert(~isfile('results/core_cnn.mat'), 'train_core_cnn:read', 'the fourth test set was read already (results/core_cnn.mat)');
assert(~isfile(CC.marker), 'train_core_cnn:started', 'a reading of the fourth test set started already (%s)', CC.marker);
assert(~cc_recorded(pid, false), 'train_core_cnn:recorded', ...
    'docs/core_cnn_read_*.txt records a reading with params_id %s: the set is read once', pid);
if HYB, nob = []; end
cc_marker(CC.marker, pid, CC.model, CC.protocol, IN, nob);
fprintf('B3c: start marker written (%s)\n', CC.marker);
clear Mo NOB why

fprintf('Loading the fourth test set...\n');
Mo = load(CC.model, 'net', 'N', 'classes', 'schedules', 'val_best', 'info', 'val');
Sf = load(IN.test, 'splits'); te = Sf.splits.test; tcl = cellstr(string(Sf.splits.classes(:)')); clear Sf
assert(isequal(tcl, Mo.classes), 'train_core_cnn:classes', 'the fourth test set has other classes than the training split');
assert(isfield(te, 'pos'), 'train_core_cnn:pos', 'the fourth test set has no frame positions');
[mT, yT, iT] = core_cnn_frames(te, Mo.classes, CC.groups);
X = te.X(:, :, :, mT);
T = struct('run', te.run(mT), 'pos', te.pos(mT), 'level', double(te.level(mT)), 'ebno', te.ebno(mT), 'Y', te.Y(mT));
if isfield(te, 'ebno_rx'), T.ebno_rx = te.ebno_rx(mT); end
n_all = numel(te.run); key_all = [double(te.run(:)), double(te.pos(:))];
clear te
fprintf('Running inference on %d frames...\n', size(X, 4));
P = spec_scores(Mo.net, X); clear X
[~, yF] = max(P, [], 2);
[L, rk] = core_cnn_eval('logp', P, T.run, T.pos, Mo.N);
[~, yW] = max(L, [], 2); clear L

% The hybrid's monitor class on the same frames (its saved fourth-set reading), when B3r read it
yH = nan(size(yT)); rkH = nan(size(yT)); h_true_off = NaN; Nh = NaN; pr = [];
if HYB
    Hp = load(IN.hybrid_pred, 'pred'); pr = Hp.pred; clear Hp
    Hm = load(IN.hybrid_metrics, 'metrics'); hm = Hm.metrics; clear Hm
    assert(numel(pr.run) == n_all, 'train_core_cnn:hybrid_frames', 'the hybrid''s reading holds %d frames, the set %d', numel(pr.run), n_all);
    [ok, row] = ismember([double(T.run(:)), double(T.pos(:))], [double(pr.run(:)), double(pr.pos(:))], 'rows');
    assert(all(ok), 'train_core_cnn:hybrid_frames', 'frames of the set missing from the hybrid''s reading');
    assert(isequal(key_all, [double(pr.run(:)), double(pr.pos(:))]), 'train_core_cnn:hybrid_frames', ...
        'the hybrid''s reading is not in the set''s frame order');
    [~, yH] = ismember(cellstr(string(pr.y_pred(row))), CC.groups);
    yH = yH(:);
    h_true_off = sum(~strcmp(cellstr(string(pr.y_true(row))), reshape(CC.groups(yT), [], 1)));
    if isfield(hm, 'fusion_cycles'), Nh = hm.fusion_cycles; end
    rkH = pr.rank(row); rkH = rkH(:);
end

% Per-frame outcomes first (as eval_detector.m), then the metrics
cpred = struct('state', yT, 'core_window', yW, 'core_frame', yF, 'hybrid', yH, 'probs', P, 'run', T.run, 'pos', T.pos, ...
    'ebno', T.ebno, 'level', T.level, 'rank', rk, 'hybrid_rank', rkH, 'N', Mo.N, 'hybrid_N', Nh, 'states', {CC.names}); %#ok<NASGU>
save('results/core_cnn_predictions.mat', 'cpred');
clear cpred pr

%% 3. Metrics (protocol, section 6)
tg = reshape(CC.groups(yT), [], 1);
eb = kpi_ebno(T, tg, Mo.classes);                      % no path loss among the three states: the configured grid
RN = {'hybrid (monitor class)', sprintf('core CNN, window N = %d (official)', Mo.N), 'core CNN, per frame'};
YP = [yH, yW, yF]; R = size(YP, 2);
act = [HYB true true]; ar = find(act);                 % readers read; without B3r the hybrid's slot stays empty
ord = [2 3 1]; ord = ord(act(ord));                    % report order
M = cell(1, R);
for r = ar, M{r} = core_cnn_eval('metrics', yT, YP(:, r), nS); end
B = cc_boot_slots(core_cnn_eval('boot', yT, YP(:, act), T.run, eb, nS, CC.n_boot, CC.boot_seed), act);
bins = B.ebno; ME = nan(R, numel(bins));
for r = ar
    for e = 1:numel(bins), k = eb == bins(e); ME(r, e) = core_cnn_eval('metrics', yT(k), YP(k, r), nS).macro_f1; end
end
fullw = [rkH >= Nh, rk >= Mo.N, true(size(rk))];       % steady state: each reader's window full
MS = cell(1, R);
for r = ar, MS{r} = core_cnn_eval('metrics', yT(fullw(:, r)), YP(fullw(:, r), r), nS); end
lvl = cell(1, nS); RL = cell(1, nS);                    % recall per JSR level, interval by sub-run
for s = 2:nS
    lvl{s} = unique(T.level(yT == s))'; RL{s} = nan(R, numel(lvl{s}), 3);
    for j = 1:numel(lvl{s})
        k = yT == s & T.level == lvl{s}(j);
        for r = ar
            [m1, lo, hi] = boot_cluster(double(YP(k, r) == s), ones(sum(k), 1), T.run(k), 2000, 1);
            RL{s}(r, j, :) = [m1 lo hi];
        end
    end
end
D = cell(1, R);
for r = ar, D{r} = core_cnn_eval('delay', yT, YP(:, r), T.run, T.pos, 2:nS); end
VD = repmat({'no hybrid reading'}, R, 4);
for r = ar
    VD{r, 1} = core_cnn_eval('verdict', M{r}.macro_f1, B.macro_f1(r, :), CC.thr.macro_f1, '>=');
    VD{r, 2} = core_cnn_eval('verdict', M{r}.recall(2), squeeze(B.recall(r, 2, :))', CC.thr.recall, '>=');
    VD{r, 3} = core_cnn_eval('verdict', M{r}.recall(3), squeeze(B.recall(r, 3, :))', CC.thr.recall, '>=');
    VD{r, 4} = core_cnn_eval('verdict', M{r}.fa, B.fa(r, :), CC.thr.false_alarm, '<=');
end
HV = [];
if HYB, HV = three_state_view(hm.conf_mat, hm.classes); end   % the hybrid's view of all its frames of the three classes
nr = cc_runs(T.run, yT, nS);

%% 4. Report, results and figures
rep = {'=== THREE-STATE CNN ON SPECTROGRAMS (deliverable 2 of the revised proposal) ===', ...
    sprintf('Generated: %s | fourth test set (%s), read once | protocol %s sha256 %s', datestr(now), IN.test, CC.protocol, psha), ...
    sprintf('Frames: %s; sub-runs %s; left out (a label other than the sub-run''s) %s', ...
    strjoin(cellfun(@(n, c) sprintf('%s %d', n, c), CC.names, num2cell(M{2}.n), 'UniformOutput', false), ', '), ...
    mat2str(nr), mat2str(iT.n_off)), ...
    sprintf('Model: schedule of %d epochs (validation best %s), epoch %d; window N = %d cycles (validation, one-standard-error rule)', ...
    Mo.schedules(find(Mo.val_best == max(Mo.val_best), 1)), cc_pct(Mo.val_best), Mo.info.bestEpoch, Mo.N)};
if HYB
    rep{end+1} = sprintf(['Hybrid: the monitor''s class of its fourth-set reading (%s; temporal fusion over %g cycles), the same frames; ' ...
        'its label differs from the state on %d frames (the state is the truth for both)'], IN.hybrid_pred, Nh, h_true_off);
else
    rep{end+1} = sprintf(['Hybrid: no reading of this set before this one (%s, %s: %s); the comparison on the same frames ' ...
        '(protocol, section 7) is not part of this reading'], CC.no_b3r, nob.date, nob.reason);
end
rep{end+1} = '';
rep{end+1} = sprintf('--- The lecturer''s KPIs: every Eb/N0, 95%% bootstrap over the %d test sub-runs (%d resamples) ---', ...
    sum(nr), CC.n_boot);
for r = ord
    rep{end+1} = RN{r}; %#ok<SAGROW>
    rep{end+1} = sprintf('  macro-F1, three states (>= %g%%)       %s  %s', 100 * CC.thr.macro_f1, cc_ci(M{r}.macro_f1, B.macro_f1(r, :)), VD{r, 1}); %#ok<SAGROW>
    rep{end+1} = sprintf('  recall, narrowband jamming (>= %g%%)   %s  %s', 100 * CC.thr.recall, cc_ci(M{r}.recall(2), squeeze(B.recall(r, 2, :))'), VD{r, 2}); %#ok<SAGROW>
    rep{end+1} = sprintf('  recall, wideband jamming (>= %g%%)     %s  %s', 100 * CC.thr.recall, cc_ci(M{r}.recall(3), squeeze(B.recall(r, 3, :))'), VD{r, 3}); %#ok<SAGROW>
    rep{end+1} = sprintf('  false alarms, clean frames (<= %g%%)    %s  %s; read as a jamming state %s', 100 * CC.thr.false_alarm, ...
        cc_ci(M{r}.fa, B.fa(r, :)), VD{r, 4}, cc_ci(M{r}.fa_jam, B.fa_jam(r, :))); %#ok<SAGROW>
    rep{end+1} = sprintf('  recall clean %.2f%% | precision %s | F1 %s', 100 * M{r}.recall(1), cc_pct(M{r}.precision), cc_pct(M{r}.f1)); %#ok<SAGROW>
end
if HYB
    rep{end+1} = sprintf(['Paired difference of macro-F1 (same sub-runs): core windowed - hybrid %s points; core per frame - hybrid ' ...
        '%s points (analysis, not a selection)'], cc_ci(M{2}.macro_f1 - M{1}.macro_f1, B.diff(2, :)), cc_ci(M{3}.macro_f1 - M{1}.macro_f1, B.diff(3, :)));
end
rep{end+1} = '';
rep{end+1} = '--- Confusion matrices (rows the true state; columns clean, narrowband, wideband, another class) ---';
for r = ord
    rep{end+1} = RN{r}; %#ok<SAGROW>
    for s = 1:nS
        rep{end+1} = sprintf('  %-20s %s', CC.names{s}, sprintf('%8d', M{r}.cm(s, :))); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = sprintf('--- Macro-F1 per Eb/N0 [dB] %s ---', sprintf('%22g', bins));
for r = ord
    c = arrayfun(@(e) cc_ci(ME(r, e), squeeze(B.macro_f1_ebno(r, e, :))'), 1:numel(bins), 'UniformOutput', false);
    rep{end+1} = sprintf('%-34s %s', RN{r}, sprintf('%22s', c{:})); %#ok<SAGROW>
end
for s = 2:nS
    rep{end+1} = ''; %#ok<SAGROW>
    rep{end+1} = sprintf('--- Recall of %s per JSR level [dB] %s (interval by sub-run, boot_cluster) ---', CC.names{s}, sprintf('%22g', lvl{s})); %#ok<SAGROW>
    for r = ord
        c = arrayfun(@(j) cc_ci(RL{s}(r, j, 1), [RL{s}(r, j, 2), RL{s}(r, j, 3)]), 1:numel(lvl{s}), 'UniformOutput', false);
        rep{end+1} = sprintf('%-34s %s', RN{r}, sprintf('%22s', c{:})); %#ok<SAGROW>
    end
end
rep{end+1} = '';
rep{end+1} = '--- Steady state (each reader''s window full) and the detection delay ---';
for r = ord
    rep{end+1} = sprintf(['%-34s steady macro-F1 %.2f%% (%d frames); cycles from a sub-run''s first frame to the first right ' ...
        'state: narrowband median %g, p90 %g, never %.1f%%; wideband median %g, p90 %g, never %.1f%%'], RN{r}, ...
        100 * MS{r}.macro_f1, sum(MS{r}.n), D{r}.median(1), D{r}.p90(1), 100 * D{r}.never(1), D{r}.median(2), ...
        D{r}.p90(2), 100 * D{r}.never(2)); %#ok<SAGROW>
end
rep{end+1} = '';
if HYB
    rep{end+1} = sprintf(['For reference, the hybrid''s three_state_view of its whole reading (every frame labelled none, ' ...
        'tone_jamming or jamming, clean frames of other sub-runs included): macro-F1 %.2f%%, recall %s, frames %s'], ...
        100 * HV.macro_f1, cc_pct(HV.recall), mat2str(HV.n));
end
rep{end+1} = sprintf(['Validation (the choices): per frame macro-F1 %.2f%%, window N = %d %.2f%% (results/core_cnn_validation.txt)'], ...
    100 * Mo.val.frame.macro_f1, Mo.N, 100 * Mo.val.window.macro_f1);

core = struct('generated', datestr(now), 'test_set', IN.test, 'protocol_sha', psha, 'states', {CC.names}, 'groups', {CC.groups}, ...
    'readers', {RN}, 'N', Mo.N, 'hybrid_N', Nh, 'metrics', {M}, 'boot', B, 'ebno', bins, 'macro_f1_ebno', ME, ...
    'steady', {MS}, 'levels', {lvl}, 'recall_level', {RL}, 'delay', {D}, 'verdicts', {VD}, ...
    'verdict_names', {{'macro_f1', 'recall_narrowband', 'recall_wideband', 'false_alarm'}}, 'thr', CC.thr, ...
    'n_runs', nr, 'left_out', iT.n_off, 'hybrid_label_off', h_true_off, 'hybrid_view_all', HV, ...
    'hybrid', HYB, 'no_b3r', nob, 'inputs', IN, ...
    'model', struct('schedules', Mo.schedules, 'val_best', Mo.val_best, 'epoch', Mo.info.bestEpoch, 'val', Mo.val));
save('results/core_cnn.mat', 'core');
fid = fopen('results/core_cnn.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);

lbl = categorical(CC.names, CC.names);
for r = [2 3]
    fig = figure('Color', 'w', 'Position', [100 100 640 540]);
    cm = confusionchart(M{r}.cm(:, 1:nS), lbl);
    cm.Title = sprintf('Three-state CNN, %s (fourth test set)', strrep(RN{r}, 'core CNN, ', ''));
    cm.RowSummary = 'row-normalized'; cm.ColumnSummary = 'column-normalized';
    saveas(fig, ternary_str(r == 2, 'results/core_cnn_confusion.png', 'results/core_cnn_confusion_frame.png')); close(fig);
end
fig = figure('Color', 'w', 'Position', [100 100 720 420]); hold on; grid on;
for r = ord
    lo = squeeze(B.macro_f1_ebno(r, :, 1)); hi = squeeze(B.macro_f1_ebno(r, :, 2));
    errorbar(bins, 100 * ME(r, :), 100 * (ME(r, :) - lo), 100 * (hi - ME(r, :)), '-o', 'LineWidth', 1.4, 'DisplayName', RN{r});
end
yline(100 * CC.thr.macro_f1, '--k', 'KPI 85%');
xlabel('E_b/N_0 [dB]'); ylabel('Macro-F1, three states (%)'); legend('Location', 'southeast');
title('Three link states per E_b/N_0 (fourth test set, 95% intervals by sub-run)');
saveas(fig, 'results/core_cnn_ebno.png'); close(fig);
fig = figure('Color', 'w', 'Position', [100 100 980 400]);
for s = 2:nS
    subplot(1, nS - 1, s - 1); hold on; grid on;
    for r = ord
        plot(lvl{s}, 100 * RL{s}(r, :, 1), '-o', 'LineWidth', 1.4, 'DisplayName', RN{r});
    end
    yline(100 * CC.thr.recall, '--k', 'KPI 85%');
    xlabel('JSR [dB]'); ylabel('Recall (%)'); title(CC.names{s}); legend('Location', 'southeast');
end
saveas(fig, 'results/core_cnn_jsr.png'); close(fig);
fprintf('\n%s\n', rep{:});
fprintf('Saved results/core_cnn.mat, results/core_cnn.txt and the figures\n=== B3c Complete ===\n');
clear P T Mo M B MS RL D VD YP yT yW yF yH rk rkH eb tg key_all row ok fig cm lbl rep core IN HYB nob act ar ord HV hm   % main.m runs the stages in one workspace

%% Local functions
function n = cc_runs(run, y, nS)
% Sub-runs per state.
[~, i] = unique(run(:));
n = accumarray(y(i), 1, [nS 1])';
end

function s = cc_pct(v)
s = strjoin(arrayfun(@(x) sprintf('%.2f%%', 100 * x), v, 'UniformOutput', false), ' / ');
end

function s = cc_ci(p, c)
% Point and 95% interval in percent.
s = sprintf('%.2f%% [%.2f, %.2f]', 100 * p, 100 * c(1), 100 * c(2));
end

function s = ternary_str(c, a, b)
if c, s = a; else, s = b; end
end

function yes = cc_recorded(pid, aborted)
% A committed record of this reading with this link model (docs/core_cnn_read_*.txt, the
% protocol's section 5); records of aborted readings count only when aborted is true.
yes = false;
for r = dir('docs/core_cnn_read_*.txt')'
    if ~aborted && contains(r.name, '_aborted'), continue; end
    yes = yes || any(strcmp(strtrim(splitlines(fileread(fullfile(r.folder, r.name)))), ['params_id ' pid]));
end
end

function B = cc_boot_slots(Bc, act)
% The bootstrap of the readers read, in the slots of all readers (NaN for one not read); the
% paired difference to the hybrid (reader 1) only when it was read. The resamples do not depend
% on the readers (core_cnn_eval 'boot'), so the core CNN's intervals are the same either way.
B = Bc;
if all(act), return; end
R = numel(act);
for f = {'macro_f1', 'fa', 'fa_jam', 'recall', 'macro_f1_ebno'}
    v = Bc.(f{1}); sz = size(v); sz(1) = R;
    x = nan(sz); x(act, :, :) = v; B.(f{1}) = x;
end
B.diff = nan(R, 2);
end

function [ok, D, why] = cc_no_b3r(f)
% The declaration that no hybrid reading of the fourth set (B3r) comes before this one
% (protocol, section 5): the lines 'no B3r before B3c', 'date yyyy-mm-dd', 'reason <text>' and
% 'params_id <the link model's>', each once, in a file git tracks with no local change.
D = struct('file', f, 'date', '', 'reason', '', 'params_id', '', 'commit', '', 'sha256', '');
ok = false;
if ~isfile(f), why = sprintf('%s not found', f); return; end
L = strtrim(splitlines(fileread(f)));
dt = regexp(L, '^date (\d{4}-\d{2}-\d{2})$', 'tokens', 'once');
rs = regexp(L, '^reason (\S.*)$', 'tokens', 'once');
pd = regexp(L, '^params_id ([0-9a-f]{32})$', 'tokens', 'once');
dt = dt(~cellfun(@isempty, dt)); rs = rs(~cellfun(@isempty, rs)); pd = pd(~cellfun(@isempty, pd));
if sum(strcmp(L, 'no B3r before B3c')) ~= 1 || numel(dt) ~= 1 || numel(rs) ~= 1 || numel(pd) ~= 1
    why = sprintf(['%s needs the lines ''no B3r before B3c'', ''date yyyy-mm-dd'', ''reason <text>'' and ' ...
        '''params_id <32 hex>'', each once'], f);
    return
end
D.date = dt{1}{1}; D.reason = rs{1}{1}; D.params_id = pd{1}{1}; D.sha256 = cc_sha(f);
g = sprintf('git --no-optional-locks -C "%s" ', pwd);
[s1, ~] = system([g 'ls-files --error-unmatch -- "' f '"']);
[s2, o2] = system([g 'status --porcelain -- "' f '"']);
[s3, o3] = system([g 'log -1 --format=%H -- "' f '"']);
o3 = strtrim(o3);
if s1 ~= 0 || s2 ~= 0 || ~isempty(strtrim(o2)) || s3 ~= 0 || isempty(regexp(o3, '^[0-9a-f]{40}$', 'once'))
    why = sprintf('%s is not committed, or has local changes', f);
    return
end
D.commit = o3; ok = true; why = 'declared';
end

function yes = cc_smoke(f)
% The model was trained in a reduced chain check (run_stage smoke).
yes = isfile(f) && ismember('smoke', {whos('-file', f).name}) && isequal(load(f, 'smoke').smoke, true);
end

function cc_marker(f, pid, model, protocol, IN, nob)
% The reading starts: time, the code's commit and tree, local changes, untracked .m files, the
% link model's params_id, the SHA-256 of the model and of the protocol, every input's path,
% size and time, and the hybrid's reading or the declaration that none comes first (nob).
root = fileparts(fileparts(fileparts(which('train_core_cnn'))));
gcmd = sprintf('git --no-optional-locks -C "%s" ', root);
[st, o] = system([gcmd 'rev-parse HEAD HEAD:code']);
[sd, d] = system([gcmd 'status --porcelain --untracked-files=all -- code models startup.m docs/core_cnn_protocol.md docs/core_cnn_no_b3r.txt']);
[su, u] = system([gcmd 'ls-files -o --exclude-standard -- "*.m"']);
o = strsplit(strtrim(o));
cm = 'unknown'; tr = 'unknown'; um = 'unknown';
if st == 0 && numel(o) == 2, cm = o{1}; tr = o{2}; end
if st == 0 && sd ~= 0, cm = [cm ' + local changes not checked']; end
if st == 0 && sd == 0 && ~isempty(strtrim(d)), cm = [cm ' + local changes in code, models, startup.m or the protocol']; end
if su == 0, um = regexprep(strtrim(u), '\s*\n\s*', ' '); end
if isempty(um), um = 'none'; end
fid = fopen(f, 'w');
assert(fid > 0, 'train_core_cnn:marker', 'cannot write %s', f);
fprintf(fid, ['three-state CNN (B3c) reading of the fourth test set started\ntime %s\ncommit %s\ncode_tree %s\n' ...
    'params_id %s\nuntracked_m %s\n%s sha256 %s\n%s sha256 %s\n'], datestr(now, 'yyyy-mm-dd HH:MM:SS'), cm, tr, pid, um, ...
    model, cc_sha(model), protocol, cc_sha(protocol));
for k = reshape(fieldnames(IN), 1, [])
    x = dir(IN.(k{1}));
    if numel(x) == 1
        fprintf(fid, 'input %s %s bytes %d modified %s\n', k{1}, IN.(k{1}), x.bytes, datestr(x.datenum, 'yyyy-mm-dd HH:MM:SS'));
    else
        fprintf(fid, 'input %s %s none\n', k{1}, IN.(k{1}));
    end
end
if isempty(nob)
    fprintf(fid, 'hybrid_reading %s\n', IN.hybrid_pred);
else
    fprintf(fid, 'hybrid_reading none: %s commit %s sha256 %s date %s\n', nob.file, nob.commit, nob.sha256, nob.date);
end
fclose(fid);
end

function h = cc_sha(f)
% SHA-256 of a file, as sha256sum prints it.
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'train_core_cnn:sha', 'cannot read %s', f);
b = fread(fid, 2^24, '*uint8');
while ~isempty(b)
    md.update(b);
    b = fread(fid, 2^24, '*uint8');
end
fclose(fid);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
