%% OODS / OODR - OOD_K2_RUN: D111's OOD run on profile 3, two phases, after B3r
% OOD_PHASE = 'select' (stage OODS) or 'read' (stage OODR); built only on K2-1's go.
% select, on validation only (data/splits.mat; no test set is loaded): eval_ood_detection.m's
% leave-one-threat-out folds again (the detector retrained without each threat,
% ood_loto_split.m, train_hybrid_net.m, fit_ood_model.m, the same schedule, rng(2026) as there),
% every original (candidate, window) pair, and D111's candidates on windows labelled by their
% newest frame: C0, the registered s0 (last_or_if over 1 cycle) as it is; C1 = min-p(C0,
% cue-Maha), C2 = min-p(C0, cue-IF), C3 = cue-Maha alone (unk_stat.m: conformal p-values, s0's
% calibrated on the fold's fit half vfit, the cue score's on its full windows, where alone it is
% read; ood_cue.m's scaling and models fitted on the fold's training windows; every window's cue
% scored alone, as the monitor scores it). The rule of items 5-6 (ood_k2_rules.m 'decide') reads
% the validation AUROC, its paired bootstrap (sub-runs within each threat, 2000 draws, fixed
% seeds), each known class's flagged share at the threshold keeping 95% of the selection half's
% known windows, the static and parity checks (a replay of validation sub-runs through
% policy_monitor.m against the offline U) and D80's latency admission (kpi7_admit.m on s0's
% detector cost of the 18.10 run plus U's own).
% Its global verdict goes to docs/d111_ood_select_p3.txt with the SHA-256 of the rule code; on
% C1, C2 or C3 the production FM.unk (the cue model on every training window, s0 and the cue
% calibrated on the validation fit half, FM.unk.val U on the selection half's known windows) is
% added to data/fusion.mat (unk_write.m 'add'). Fold models and validation values go to
% results/ood_k2/.
% read: only with the select record committed and adopting C1-C3, its rule code unchanged, B3r's
% committed record of this params_id, FM.unk in data/fusion.mat and no OOD set-4 marker
% (results/ood_k2_read_started.txt), written before data/splits_fresh3.mat is loaded; a second
% reading is refused. For each held-out threat the fold's models read set 4: the candidate the rule
% picks on the other nine threats' validation ((a)-(c); C0 where none passes), the 18.10 procedure
% (the nested pick over the original pairs within the 18.10 KPI 7 admission, ood_select.m: the
% like-for-like replication of 0.763) and C0. AUROC and FPR95 per held-out threat only (D91's
% dated line of D111): no class read of set 4 is printed or kept, no Algorithm 2. KPI 2 is the
% adopted procedure's nested set-4 mean; its gain the paired set-4 difference against the 18.10
% procedure, a 95% interval from sub-runs resampled within each threat; 0.763 beside.
% Both phases: the docs commit registering D111 printed (REG_COMMIT, DOCS_REPO or profile.json);
% s0's (score, window) must be (last_or_if, 1); data/trained_detector.mat and
% data/ood_thresholds.mat are never written (their SHA-256 equal at the end); eval_ood_detection.m's
% save step is not part of this run. SMOKE: two threats, 3 epochs, 50 draws, no registration check,
% the select record in results/; OOD_FORCE (smoke only) deploys the named candidate whatever the
% verdict, marked FM.unk.forced.
% Output: select: docs/d111_ood_select_p3.txt, results/ood_k2_select.{txt,mat},
% results/ood_k2/fold_<i>.mat, FM.unk in data/fusion.mat on adoption; read:
% results/ood_k2_read_started.txt, results/ood_k2_read.{txt,mat}

close all; clc;
assert(exist('OOD_PHASE', 'var') == 1 && ischar(OOD_PHASE) && ismember(OOD_PHASE, {'select', 'read'}), 'ood_k2_run:phase', ...
    'set OOD_PHASE to ''select'' or ''read''');
SMK = exist('SMOKE', 'var') && isequal(SMOKE, true);
if ~exist('OOD_FORCE', 'var'), OOD_FORCE = ''; end
assert(isempty(OOD_FORCE) || (SMK && ismember(OOD_FORCE, {'C1', 'C2', 'C3'})), 'ood_k2_run:force', ...
    'OOD_FORCE deploys a candidate in the smoke only');
fprintf('=== D111 OOD run, phase %s ===\n\n', OOD_PHASE);
if ~exist('REG_COMMIT', 'var'), REG_COMMIT = ''; end
if ~exist('DOCS_REPO', 'var'), DOCS_REPO = ''; end
reg = ''; reg_txt = 'smoke: registration not checked';
if ~SMK, [reg, reg_txt] = ood_k2_rules('registered', DOCS_REPO, REG_COMMIT); end
[cm, tr] = ood_k2_rules('commit');
RULE = {'ood_k2_run.m', 'ood_k2_rules.m', 'ood_cue.m', 'unk_stat.m', 'unk_write.m', 'ood_loto_split.m'};
SEL_REC = 'docs/d111_ood_select_p3.txt'; if SMK, SEL_REC = 'results/d111_ood_select_smoke.txt'; end
RD_MARK = 'results/ood_k2_read_started.txt'; FOLD_DIR = 'results/ood_k2';
FROZEN = {'data/trained_detector.mat', 'data/ood_thresholds.mat'};
sha0 = cellfun(@frozen_sha, FROZEN, 'UniformOutput', false);
D0 = load('data/trained_detector.mat', 'net', 'ood', 'classes');
W0 = 1; if isfield(D0.ood, 'win') && ~isempty(D0.ood.win), W0 = D0.ood.win; end
assert(isfield(D0.ood, 'score') && strcmp(D0.ood.score, 'last_or_if') && W0 == 1, 'ood_k2_run:s0', ...
    's0 is not last_or_if over 1 cycle: D111 keeps the registered s0 frozen');
if ~isfield(D0.ood, 'forest_pack'), D0.ood.forest_pack = iforest_pack(D0.ood.forest); end
FZ = fusion_model(); N = FZ.N; Ns = ood_cue('step_n', N);
NW = max([N, W0, window_cues('branch_window'), Ns]);   % the monitor's window with FM.unk (policy_monitor.m)
pid = params_id(load('params.mat').params);
RETAIN = 0.95; N_EPOCHS = 30; WIN = [2 5 8]; WALL = [1 WIN]; NB = 2000; N_LAT = 200; N_PAR = 20;
if SMK, N_EPOCHS = 3; NB = 50; N_LAT = 20; N_PAR = 4; end
CN = {'C0', 'C1', 'C2', 'C3'};
CAND = D0.ood.candidates; SC = [{'msp', 'energy', 'iforest'}, CAND];
rep = [{sprintf('=== D111 OOD RUN, PHASE %s (profile 3) ===', upper(OOD_PHASE)), ...
    sprintf('Generated: %s | commit %s | code_tree %s | params_id %s', datestr(now), cm, tr, pid), reg_txt, ...
    sprintf('s0 = %s over %d cycle(s) (frozen); fusion window N = %d; level step over %d; cue window %d cycles', ...
    D0.ood.score, W0, N, max(N, Ns), NW)}, ood_k2_rules('sha', RULE)];
fprintf('%s\n', rep{:});
t0 = tic;

if strcmp(OOD_PHASE, 'select')
    %% S1. Data and the cue rows (no test set is read)
    assert(~isfile(SEL_REC), 'ood_k2_run:selected', '%s exists: the select phase runs once', SEL_REC);
    Lr = load('results/ood_detection.mat', 'LC', 'SC');  % the 18.10 run: its KPI 7 admission of the original candidates
    assert(isequal(Lr.SC, SC), 'ood_k2_run:candidates', 'the 18.10 run scored other candidates');
    rng(2026, 'twister');
    sp = load_val('data/splits.mat');
    C = numel(sp.classes); all_classes = cellstr(string(sp.classes(:)'));
    held_out = setdiff(all_classes, {'none'}, 'stable');
    if SMK, held_out = held_out(1:2); end
    fn = sp.norm.feat_names;
    Xtr = ood_cue('split', sp.train, fn, C, N);
    Xva = ood_cue('split', sp.val, fn, C, N);
    fva = ood_cue('fill', sp.val.run, sp.val.pos) >= NW;
    static_ok = ood_k2_rules('static', ood_cue('names', C));
    T = numel(held_out); J = numel(CN);
    A = nan(T, J); Bd = nan(NB, T, J); Fk = zeros(T, C, J); Nk = zeros(T, C);
    if ~isfolder(FOLD_DIR), mkdir(FOLD_DIR); end

    %% S2. One retraining per held-out threat, validation only
    for h = 1:T
        k = held_out{h}; known = setdiff(all_classes, {k}, 'stable');
        fprintf('[%d/%d] Held-out threat: %s\n', h, T, k);
        [tr_, vfit, va] = ood_loto_split(sp, [], k);
        net = train_hybrid_net(tr_, vfit, known, struct('verbose', false, 'epochs', N_EPOCHS));
        M = fit_ood_model(net, tr_, known, vfit);
        clear tr_ vfit
        Sv = all_scores(net, M, va);
        yv = cellstr(string(va.Y));
        V = struct('run', va.run, 'pos', va.pos, 'kn', ismember(yv, known) & va.sel & ~va.own, 'un', strcmp(yv, k));
        F = ood_loto_split('masks', sp, k);
        assert(isequal(F.kn(:), V.kn(:)) && isequal(F.un(:), V.un(:)), 'ood_k2_run:masks', 'the masks are not the fold''s windows');
        Q = ood_fold_metrics(Sv, V, Sv, V, SC, WALL, RETAIN);
        s0 = ood_window(Sv.last_or_if, va.run, va.pos, W0);
        [U, Wv] = fold_models(Xtr, Xva, F, s0, fva, N, Ns, NW, W0, 9300 + h);
        Wv = [s0, Wv];                                   % windows x C0..C3, lower = more novel
        for j = 1:J
            A(h, j) = ood_k2_rules('auroc', Wv(F.kn, j), Wv(F.un, j));
            fl = Wv(:, j) < lowq(Wv(F.kn, j), 1 - RETAIN);
            for c = 1:C
                m = F.kn & strcmp(F.yv, all_classes{c});
                Fk(h, c, j) = sum(fl & m);
                if j == 1, Nk(h, c) = sum(m); end
            end
        end
        Bd(:, h, :) = reshape(ood_k2_rules('boot_auroc', Wv, F.kn, F.un, sp.val.run, NB, 9400 + h), NB, 1, J);
        fprintf('    validation AUROC %s\n', strjoin(arrayfun(@(j) sprintf('%s %.3f', CN{j}, A(h, j)), 1:J, ...
            'UniformOutput', false), '  '));
        if h == 1, MpV = nan(T, numel(SC) * numel(WALL)); end
        MpV(h, :) = reshape(Q.val', 1, []);             % (candidate, window) pairs, candidate-major
        save(fullfile(FOLD_DIR, sprintf('fold_%d.mat', h)), 'k', 'known', 'net', 'M', 'U', 'Sv', 'V', 'Wv', 'F', '-v7.3');
        clear net M Sv va V Q U Wv F
    end
    [pw, pj] = ndgrid(WALL, 1:numel(SC)); pj = pj(:)'; pw = pw(:)';
    [~, ic] = ismember(SC(pj), CAND); okp = ic > 0; okp(okp) = Lr.LC.ok(ic(okp));
    [b18, nb18] = ood_select(MpV, okp);                % the 18.10 procedure on this run's folds

    %% S3. The production model, its parity with the monitor and its cost
    D0v = prod_scores(D0, sp.val);
    s0p = ood_window(D0v.maha, sp.val.run, sp.val.pos, W0);
    Fp = ood_loto_split('masks', sp, '');              % every class known: the fit and selection halves
    [Up, Wp] = fold_models(Xtr, Xva, Fp, s0p, fva, N, Ns, NW, W0, 9399);
    par = parity(Up, FZ, D0v, sp.val, fn, all_classes, Wp, N_PAR);
    lat = latency(Up, Xva(fva, :), s0p(fva), N_LAT, Lr.LC, CAND);
    ok = [true, static_ok & par.ok & lat.ok];
    D = ood_k2_rules('decide', A, Bd, Fk, Nk, ok, 1:T);
    verdict = CN{D.pick};

    %% S4. The select record, the report and, on adoption, FM.unk
    rs = [rep, {'', sprintf(['Validation only (selection half''s known windows against each held-out threat''s windows, ' ...
        'the newest frame''s label); C0 = s0 as stored, C1-C3 = U (unk_stat.m); %d bootstrap draws per threat'], NB), ...
        sprintf('%-20s %s', 'held-out threat', sprintf(' %8s', CN{:}))}];
    for h = 1:T
        rs{end+1} = sprintf('%-20s %s', held_out{h}, sprintf(' %8.3f', A(h, :))); %#ok<SAGROW>
    end
    rs{end+1} = sprintf('%-20s %s', 'mean', sprintf(' %8.3f', D.mean));
    rs{end+1} = sprintf(['Checks per candidate (a) mean >= C0 + 0.010 and 5th percentile of the mean paired difference > 0 ' ...
        '(lb), (b) no threat loses > 0.03, (c) no known class flagged > 2x C0 or > 10%%, (d) static %s, parity %s ' ...
        '(max |U monitor - U offline| %.2g over %d sub-runs), latency %s (U median / p95 %.3f / %.3f ms on s0''s %.2f / %.2f): %s'], ...
        tf(static_ok), tf(par.ok), par.err, par.n, tf(lat.ok), lat.med, lat.p95, lat.med0, lat.p950, ...
        strjoin(arrayfun(@(j) sprintf('%s a %s (lb %.4f) b %s c %s -> %s', CN{j}, tf(D.a(j)), D.lb(j), tf(D.b(j)), tf(D.c(j)), ...
        ternary(D.eligible(j), 'eligible', 'not eligible')), 2:J, 'UniformOutput', false), '; '));
    rs{end+1} = sprintf(['The 18.10 procedure on these folds: %s over %d cycles, validation mean %.3f (pairs within the 18.10 ' ...
        'KPI 7 admission).'], SC{pj(b18)}, pw(b18), mean(MpV(:, b18)));
    rs{end+1} = sprintf('verdict %s', verdict);
    rs{end+1} = sprintf('Global verdict (D111 items 5-6, all ten held-out threats; it decides deployment only): %s. %s', ...
        verdict, ternary(D.pick > 1, 'FM.unk is added to data/fusion.mat; the read phase may run after B3r.', ...
        'C0 stays: set 4 gets no OOD reader and KPI 2 stays 0.763.'));
    if ~isempty(fileparts(SEL_REC)) && ~isfolder(fileparts(SEL_REC)), mkdir(fileparts(SEL_REC)); end
    fid = fopen(SEL_REC, 'w'); fprintf(fid, '%s\n', rs{:}); fclose(fid);
    fid = fopen('results/ood_k2_select.txt', 'w'); fprintf(fid, '%s\n', rs{:}); fclose(fid);
    fprintf('%s\n', rs{numel(rep) + 1:end});
    fprintf('Select record %s, SHA-256 %s: commit it before the read phase\n', SEL_REC, kpi6_fresh_marker('sha', SEL_REC));
    dep = '';
    if D.pick > 1, dep = verdict; end
    if ~isempty(OOD_FORCE), dep = OOD_FORCE; fprintf('SMOKE: %s deployed by OOD_FORCE (the rule''s verdict %s)\n', dep, verdict); end
    if ~isempty(dep)
        Ud = Up{strcmp(CN(2:end), dep)};
        if ~isempty(OOD_FORCE), Ud.forced = true; end
        unk_write('add', Ud, 'data/fusion.mat');
        fprintf('FM.unk (%s) added to data/fusion.mat\n', dep);
    end
    save('results/ood_k2_select.mat', 'held_out', 'CN', 'A', 'Bd', 'Fk', 'Nk', 'ok', 'D', 'verdict', 'MpV', 'pj', 'pw', ...
        'okp', 'b18', 'nb18', 'SC', 'WALL', 'static_ok', 'par', 'lat', 'Up', 'NB', 'NW', 'N', 'Ns', 'reg', 'cm', 'tr', '-v7.3');
else
    %% R1. Guards, then the set-4 marker before any of its data
    [verdict, shas] = ood_k2_rules('select_record', SEL_REC);
    assert(ismember(verdict, {'C1', 'C2', 'C3'}), 'ood_k2_run:not_adopted', ...
        'the select verdict is %s: set 4 gets no OOD reader and KPI 2 stays 0.763', verdict);
    assert(isequal(sort(shas(:)), sort(ood_k2_rules('sha', RULE)')), 'ood_k2_run:rule_changed', ...
        'the rule code is not the one the select record names');
    assert(ood_k2_rules('b3r_recorded', pid), 'ood_k2_run:b3r', ...
        'no committed B3r record of params_id %s (docs/d91_fresh3_read_*.txt): the OOD reading comes strictly after B3r', pid);
    assert(unk_stat('on', struct('fuse', FZ.FM)), 'ood_k2_run:unk', 'data/fusion.mat holds no FM.unk');
    assert(~isfile(RD_MARK), 'ood_k2_run:read_started', '%s exists: the OOD run reads set 4 once', RD_MARK);
    assert(isfile('data/splits_fresh3.mat'), 'ood_k2_run:fresh3', 'data/splits_fresh3.mat not found');
    Sel = load('results/ood_k2_select.mat');
    fid = fopen(RD_MARK, 'w'); assert(fid > 0, 'ood_k2_run:marker', 'cannot write %s', RD_MARK);
    fprintf(fid, ['D111 OOD set-4 reading started\ntime %s\ncommit %s\ncode_tree %s\nparams_id %s\n%s\nselect record %s ' ...
        'sha256 %s\nverdict %s\n'], datestr(now, 'yyyy-mm-dd HH:MM:SS'), cm, tr, pid, reg_txt, SEL_REC, ...
        kpi6_fresh_marker('sha', SEL_REC), verdict);
    fclose(fid);

    %% R2. Set 4
    sp = load_val('data/splits.mat');
    S4 = load('data/splits_fresh3.mat', 'splits');
    assert(isequal(S4.splits.norm, sp.norm) && isequal(S4.splits.classes, sp.classes), 'ood_k2_run:fresh3', ...
        'the fourth test set has another normalization or other classes');
    fresh = S4.splits.test; clear S4
    C = numel(sp.classes);
    X4 = ood_cue('split', fresh, sp.norm.feat_names, C, N);
    f4 = ood_cue('fill', fresh.run, fresh.pos) >= NW;
    T = numel(Sel.held_out); J = numel(CN);
    [A4, FP4] = deal(nan(T, J)); [Aad, A18, FPad, FP18, pick] = deal(nan(1, T));
    Bg = nan(NB, T, 2);
    for h = 1:T
        Fd = load(fullfile(FOLD_DIR, sprintf('fold_%d.mat', h)));
        k = Fd.k; known = Fd.known;
        [~, ~, ~, ~, te] = ood_loto_split(sp, fresh, k);
        St = all_scores(Fd.net, Fd.M, te);
        yt = cellstr(string(te.Y));
        T4 = struct('run', te.run, 'pos', te.pos, 'kn', ismember(yt, known) & ~te.own, 'un', strcmp(yt, k));
        Q4 = ood_fold_metrics(Fd.Sv, Fd.V, St, T4, SC, WALL, RETAIN);
        s0t = ood_window(St.last_or_if, te.run, te.pos, W0);
        Wt = s0t;
        for j = 1:J - 1, Wt = [Wt, unk_stat('U', Fd.U{j}, s0t, X4, f4, true)]; end %#ok<AGROW>
        for j = 1:J
            A4(h, j) = ood_k2_rules('auroc', Wt(T4.kn, j), Wt(T4.un, j));
            FP4(h, j) = mean(Wt(T4.un, j) >= lowq(Fd.Wv(Fd.F.kn, j), 1 - RETAIN));
        end
        Dh = ood_k2_rules('decide', Sel.A, Sel.Bd, Sel.Fk, Sel.Nk, Sel.ok, setdiff(1:T, h));
        pick(h) = Dh.pick;
        Aad(h) = A4(h, pick(h)); FPad(h) = FP4(h, pick(h));
        p18 = Sel.nb18(h); t18 = reshape(Q4.test', 1, []); f18 = reshape(Q4.fpr', 1, []);
        A18(h) = t18(p18); FP18(h) = f18(p18);
        s18 = ood_window(St.(SC{Sel.pj(p18)}), te.run, te.pos, Sel.pw(p18));
        Bg(:, h, :) = reshape(ood_k2_rules('boot_auroc', [Wt(:, pick(h)), s18], T4.kn, T4.un, te.run, NB, 9500 + h), NB, 1, 2);
        fprintf('[%d/%d] %-20s set 4: adopted (%s) %.3f, 18.10 procedure %.3f, C0 %.3f\n', h, T, k, CN{pick(h)}, Aad(h), ...
            A18(h), A4(h, 1));
        clear Fd te St Q4 Wt yt
    end
    kpi2 = mean(Aad); gain = kpi2 - mean(A18);
    gd = mean(Bg(:, :, 1) - Bg(:, :, 2), 2); gain_ci = [prctile(gd, 2.5), prctile(gd, 97.5)];
    O18 = load('results/ood_detection.mat', 'NEST');
    v763 = mean(O18.NEST.auroc);

    %% R3. Report: AUROC and FPR95 per held-out threat only
    rr = [rep, {'', sprintf(['Fourth test set (data/splits_fresh3.mat), read once (%s). Per held-out threat, AUROC / FPR95 of the ' ...
        'adopted procedure (its pick on the other nine threats'' validation), the 18.10 procedure (nested pick over the ' ...
        'original pairs) and C0:'], RD_MARK)}];
    for h = 1:T
        rr{end+1} = sprintf('%-20s adopted %s %.3f / %.2f | 18.10 %.3f / %.2f | C0 %.3f / %.2f', Sel.held_out{h}, CN{pick(h)}, ...
            Aad(h), FPad(h), A18(h), FP18(h), A4(h, 1), FP4(h, 1)); %#ok<SAGROW>
    end
    rr{end+1} = sprintf(['KPI 2 (D111 item 8): the adopted procedure''s nested set-4 mean AUROC %.3f, FPR95 %.2f; gain against ' ...
        'the 18.10 procedure on set 4 (%.3f) %+.3f [%+.3f, %+.3f] (95%%, sub-runs resampled within each threat, %d draws); ' ...
        'C0 on set 4 %.3f; beside it 0.763 read on the second test set (data/splits_fresh.mat, the earlier statistic; this ' ...
        'run''s 18.10 file %.3f).'], kpi2, mean(FPad), mean(A18), gain, gain_ci, NB, mean(A4(:, 1)), v763);
    fid = fopen('results/ood_k2_read.txt', 'w'); fprintf(fid, '%s\n', rr{:}); fclose(fid);
    fprintf('%s\n', rr{numel(rep) + 1:end});
    TEST_SET = 'fourth test set (data/splits_fresh3.mat)';
    held_out = Sel.held_out; fpr2 = mean(FPad);
    save('results/ood_k2_read.mat', 'held_out', 'CN', 'A4', 'FP4', 'Aad', 'FPad', 'A18', 'FP18', 'pick', 'kpi2', 'fpr2', ...
        'gain', 'gain_ci', 'v763', 'TEST_SET', 'verdict', 'NB', '-v7.3');
    fid = fopen(RD_MARK, 'a'); fprintf(fid, 'OOD set-4 read %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); fclose(fid);
end
sha1 = cellfun(@frozen_sha, FROZEN, 'UniformOutput', false);
assert(isequal(sha0, sha1), 'ood_k2_run:frozen', 'data/trained_detector.mat or data/ood_thresholds.mat changed during the run');
fprintf('\n%s and %s unchanged (SHA-256); OOD run phase %s done (%.1f min)\n', FROZEN{:}, OOD_PHASE, toc(t0) / 60);


%% ===== Local functions =====
function sp = load_val(f)
% data/splits.mat without its test split: never a test set built after the dataset.
assert(~contains(f, 'splits_fresh'), 'ood_k2_run:fresh', 'the select phase never loads %s', f);
S = load(f, 'splits'); sp = S.splits;
sp.test = [];
end

function [U, Wv] = fold_models(Xtr, Xva, F, s0, full, N, Ns, NW, W0, seed)
% C1, C2, C3 of one fold (unk_stat.m 'model') and their U on every validation window: the cue
% scaling and models on the fold's training windows, s0's calibration on its fit half, the cue
% score's on the fit half's full windows, FM.unk.val U on the selection half's known windows.
Sc = ood_cue('scale_fit', Xtr(F.tr, :));
Xs = ood_cue('scale', Sc, Xtr(F.tr, :));
Mm = ood_cue('maha_fit', Xs, F.ytr(F.tr));
Mf = ood_cue('if_fit', Xs, seed);
base = struct('cand', '', 'use0', true, 'cue', '', 'scale', Sc, 'model', [], 'cal0', unk_stat('cal', s0(F.vfit)), ...
    'cal1', [], 'val', [], 'nw', NW, 'step_n', Ns, 'N', N, 'score', 'last_or_if', 'win', W0);
spec = {'C1', true, 'maha', Mm; 'C2', true, 'if', Mf; 'C3', false, 'maha', Mm};
U = cell(1, 3); Wv = nan(numel(s0), 3);
for j = 1:3
    S = base; [S.cand, S.use0, S.cue, S.model] = spec{j, :};
    S.cal1 = unk_stat('cal', unk_stat('cue', S, Xva(F.vfit & full, :), true));
    Wv(:, j) = unk_stat('U', S, s0, Xva, full, true);
    S.val = sort(Wv(F.kn, j));
    U{j} = unk_stat('model', S);
end
end

function o = par_obs(sp, fn, D0v, f)
% The monitor's observation of validation frame f (policy_monitor.m): link features in
% link_features.m's order.
[~, jf] = ismember(link_features('names'), fn);
o = struct('probs', D0v.probs(:, f)', 'unknown', false, 'maha', D0v.maha(f), 'feat', double(sp.feats_raw(f, jf)), ...
    'gant', double(sp.gain_ant(f, :)));
if isfield(sp, 'idle') && ~isempty(sp.idle), o.idle = double(sp.idle(f, :)); end
if isfield(sp, 'bch') && ~isempty(sp.bch), o.bch = double(sp.bch(f, :)); end
end

function R = parity(U, FZ, D0v, sp, fn, classes, Wp, nPar)
% D111 (d): U of the monitor on replayed validation sub-runs equals the offline U, for every
% candidate model (unk_stat.m through policy_monitor.m, PP.fuse = the deployed fusion with it).
runs = unique(sp.run, 'stable'); runs = runs(round(linspace(1, numel(runs), min(nPar, numel(runs)))));
A = policy_actions(); na = find(strcmp(A, 'no_action'));
p0 = load('params.mat').params;
err = 0;
for j = 1:numel(U)
    FM = FZ.FM; FM.unk = U{j};
    PP = struct('actions', {A}, 'classes', {classes}, 'sps', p0.sps, 'bps', p0.bits_per_symbol, 'maha_thr', 0, ...
        'fuse', FM, 'fuse_N', FZ.N, 'unk_win', U{j}.win, 'unk_retain', 0.95);
    for r = runs(:)'
        ix = find(sp.run == r); [~, o] = sort(sp.pos(ix)); ix = ix(o);
        mem = policy_monitor('init', 1, numel(A));
        for i = ix(:)'
            [mem, M] = policy_monitor('update', mem, par_obs(sp, fn, D0v, i), PP, na);
            mem = policy_monitor('change', mem, false);
            err = max(err, abs(M.unk_u - Wp(i, j)));
        end
    end
end
R = struct('ok', err == 0, 'err', err, 'n', numel(runs));
end

function L = latency(U, X, s0, n, LC, CAND)
% U's own cost per decision (one window: scaling, the cue score, the two p-values), median and
% p95 [ms] over n calls after 10 warm-up calls, added to s0's detector cost of the 18.10 run on
% its device (ood_latency.m); admitted when the sum fits kpi7_admit.m.
j0 = strcmp(CAND, 'last_or_if');
t = zeros(numel(U), 10 + n);
for j = 1:numel(U)
    for r = 1:10 + n
        i = mod(r - 1, size(X, 1)) + 1;
        c = tic; unk_stat('U', U{j}, s0(i), X(i, :), true); t(j, r) = 1000 * toc(c);
    end
end
t = sort(t(:, 11:end), 2);
L = struct('med', max(median(t, 2)), 'p95', max(t(:, ceil(0.95 * n))), 'med0', LC.med(j0), 'p950', LC.p95(j0));
L.ok = kpi7_admit(L.med0 + L.med, L.p950 + L.p95);
end

function S = all_scores(net, M, P)
[S.probs, ~, S.msp, S.energy] = cnn_scores(net, P.X, P.feats');
[~, T] = ood_scores(net, M, P.X, P.feats');
for f = fieldnames(T)', S.(f{1}) = T.(f{1}); end
end

function S = prod_scores(D0, P)
% The production detector on the validation frames: its probabilities and s0 per frame (the
% pools' P.probs and P.maha).
S.probs = cnn_scores(D0.net, P.X, P.feats');
S.maha = ood_scores(D0.net, D0.ood, P.X, P.feats');
end

function h = frozen_sha(f)
if isfile(f), h = kpi6_fresh_marker('sha', f); else, h = 'absent'; end
end

function q = lowq(x, frac)
x = sort(x(:));
q = x(max(1, ceil(frac * numel(x))));
end

function s = tf(b)
if b, s = 'pass'; else, s = 'FAIL'; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
