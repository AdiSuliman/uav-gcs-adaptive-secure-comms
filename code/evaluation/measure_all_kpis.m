%% MEASURE_ALL_KPIS - The proposal KPIs from the result files
% Reads the outputs of the pipeline, never re-runs them: a missing source is
% reported as such, and a source older than its inputs (detector, decision layer)
% is flagged STALE. Targets as worded in the proposal:
%   KPI 1  detection: macro-F1 >= 90% above an Eb/N0 threshold chosen on validation (the
%          proposal's wording); every class F1 >= 90%, the stricter reading, beside it
%          (eval_detector), unseen Eb/N0 (eval_unseen_snr); read on the third test set
%          (B3m, results/eval_detector_metrics_fresh2.mat) when it exists, the second test
%          set's reading beside it; on the fourth (B3r, _fresh3) once kpi1_set.m names it, the
%          third and second beside it
%   KPI 2  unknown threats: leave-one-threat-out mean AUROC >= KPI2_TARGET, FPR at 95%
%          of known frames kept (eval_ood_detection; the nested estimate of the
%          selected production score)
%   KPI 3  physical validation: BER vs theory within 0.3 dB (validate_phy)
%   KPI 4  restoration: BER and packet loss back to <= 2x clean on >= 90% of the
%          recoverable episodes of EVERY threat, combined threats included, over
%          five severities; survivability boundary (evaluate_policies,
%          map_survivability_boundary); beside it, the stricter reading on the harmed
%          episodes only (no response does not restore them), never in its place
%   KPI 5  DQN vs no response, rule, random, fixed and oracle: recovery, recovery
%          time, restored cycles, goodput, follower and unseen combinations;
%          paired 95% bootstrap interval of the recovery difference vs rule > 0
%   KPI 6  false alarms on a healthy link above the Eb/N0 threshold: one-sided
%          95% Clopper-Pearson bound over >= 600 independent episodes <= 5%
%   KPI 7  real time: decision latency median < 10 ms (Oli & Mahalal, low class)
%          and p95 < 20 ms (also on one CPU core); robustness over the speed
%          envelope (recovery spread <= 10 points), flights at its ends reported
%   KPI 8  minimum: a closed loop restoring at least one recoverable threat, read on the
%          harmed episodes (an episode no response restores shows no closed loop)
% Revised proposal, beside the KPIs (never in their place): the three link states (clean,
% narrowband and wideband jamming) from the saved confusion matrix of the KPI 1 reading (and of
% the third test set when KPI 1 reads another), with the recall per jamming type and a 3-state
% macro-F1, also above the KPI 1 threshold from the saved predictions (KPI 1); PER vs the static link (KPI 4);
% recovery time from detection, onset-to-detection time and goodput in bit/s (KPI 5); each for
% the full action set and for the core action set (channel switching and rate adaptation,
% rule_core and blind_core); from results/policy_evaluation.mat's KP.lect (lect_kpis.m),
% PENDING while that file predates it.
% With results/edge_map.mat (edge_map.m), the verdicts per point are added as details:
% detection and detection on harmed flights (KPI 1); the commitment at every signalling
% delay, the receiver alone, the relative criterion (SYSTEM), the distance edges and the
% overhead pass (KPI 4); the clean link (KPI 6); hover and 161 km/h (KPI 7).
% Identity and age (result_status.m): a result of another detector or deployed policy, or
% older than its inputs, is STALE (KPI 3 against params.mat, KPI 6 also when its Eb/N0
% threshold is not the current KPI 1 threshold, the edge map's details flagged); KPI 7 is
% PENDING while the latency of the current detector and deployed chain has not been
% measured (results/latency.mat absent, or of another detector or policy).
%
% Output: results/kpi_summary.txt, results/kpi_summary.mat (KPI struct array; LECT, the
% revised proposal's readings)

close all; clc;
fprintf('=== KPI summary ===\n\n');
F = struct('det', 'results/eval_detector_metrics.mat', 'unseen', 'results/unseen_snr.mat', ...
    'ood', 'results/ood_detection.mat', 'phy', 'results/phy_validation.txt', ...
    'pol', 'results/policy_evaluation.mat', 'lat', 'results/latency.mat', ...
    'surv', 'data/survivability_boundary.mat', 'dqn', 'data/trained_dqn.mat', 'arch', 'results/architecture_comparison.txt', ...
    'ant3', 'results/survivability_options.txt', 'combo', 'results/combo_generalization.mat', 'edge', 'results/edge_map.mat');
F.det = kpi1_file('eval_detector_metrics');            % the set of kpi1_set.m
KPI2_TARGET = 0.8;                                 % mean AUROC (the submitted proposal's target, kept in the update)
t_det = file_time('data/trained_detector.mat'); t_dqn = file_time(F.dqn);
if isfile('data/trained_detector.mat')             % training time (the file is updated later by the OOD stage)
    Dt = load('data/trained_detector.mat', 'trained_at');
    if isfield(Dt, 'trained_at'), t_det = Dt.trained_at; end
end
RS = result_status();
rst = @(f) RS(strcmp({RS.file}, f));                   % identity and age of a result file
KPI = struct('id', {}, 'name', {}, 'value', {}, 'target', {}, 'status', {}, 'detail', {});
LECT = struct('three', [], 'three_above', [], 'three3', [], 'three3_above', [], 'pol', []);
rep = {'=== PROPOSAL KPI SUMMARY (proposal wording) ===', sprintf('Generated: %s | %s', datestr(now), git_stamp()), ''};

%% KPI 1 - detection
if isfile(F.det)
    M = load(F.det, 'metrics'); m = M.metrics;
    val = m.macro_f1_above_threshold_pct; cl = m.class_f1_above_threshold_pct;
    det = {sprintf('accuracy %.2f%%, macro-F1 %.2f%% [%.2f, %.2f] (bootstrap over sub-runs)', ...
        m.overall_accuracy_pct, m.macro_f1_pct, m.ci95.macro_f1), ...
        sprintf('class F1 above the threshold: %s', strjoin(cellfun(@(c, v) sprintf('%s %.1f%%', c, v), m.classes(:)', ...
        num2cell(cl(:)'), 'UniformOutput', false), ', ')), ...
        sprintf('macro-F1 per Eb/N0: %s', strjoin(arrayfun(@(b) sprintf('%g dB %.1f%%', b.snr_db, b.macro_f1_pct), ...
        m.snr_breakdown, 'UniformOutput', false), ' | '))};
    if ~isempty(read_state(m)), det{end+1} = sprintf('KPI 1 reading: %s', read_state(m)); end
    if isfield(m, 'every_class')                     % the stricter reading, beside KPI 1, never hidden
        ec = m.every_class;
        det{end+1} = sprintf(['beside KPI 1, every class F1 >= 90%% (the stricter reading, its threshold chosen on ' ...
            'validation): from %g dB, macro-F1 %.2f%%, lowest class %.2f%% (%s)'], ec.threshold_db, ...
            ec.macro_f1_above_threshold_pct, min(ec.class_f1_above_threshold_pct), ...
            ternary(isfinite(ec.threshold_db) && all(ec.class_f1_above_threshold_pct >= 90), 'met', 'not met'));
    end
    if isfield(m, 'steady')                          % beside KPI 1, never in its place
        s1 = m.steady;
        det{end+1} = sprintf(['beside KPI 1, steady state (fusion window full, %d of %d frames): macro-F1 above the ' ...
            'threshold %.2f%% [%.2f, %.2f], lowest class %.2f%%, accuracy %.2f%%'], s1.n, s1.n_all, ...
            s1.macro_f1_above_threshold_pct, m.ci95.macro_f1_above_steady, min(s1.class_f1_above_threshold_pct), ...
            s1.accuracy_pct);
        det{end+1} = sprintf(['beside KPI 1, onset latency on the test sub-runs [cycles from the onset frame, ' ...
            '0 = on it; median/p90]: %s'], ...
            strjoin(arrayfun(@(o) sprintf('%s class %g/%g alarm %g/%g', o.class, o.cls_median, o.cls_p90, ...
            o.conf_median, o.conf_p90), m.onset, 'UniformOutput', false), ', '));
    end
    if isfield(m, 'branch')                          % beside KPI 1, never in its place
        det{end+1} = sprintf(['beside KPI 1, branch level (antenna fault and airframe shadowing as one branch lost): ' ...
            'macro-F1 above the threshold %.2f%%, one branch lost found in %.2f%% of its %d frames (%.2f%% above the threshold)'], ...
            m.branch.macro_f1_above_threshold_pct, m.branch.lost_recall_pct, m.branch.n_lost, m.branch.lost_recall_above_threshold_pct);
    end
    if isfield(m, 'onset_diag')                      % beside KPI 1: the latched cause per event
        how = 'latched'; if isfield(m, 'latch') && ~m.latch, how = 'read first by the monitor''s class (latch off)'; end
        for q = m.onset_diag
            det{end+1} = sprintf(['beside KPI 1, per event, %s: right cause %s in %.1f%% [%.1f, %.1f] of %d events ' ...
                '(decided in %.1f%%), median %g cycles (%g ms) from the onset'], q.class, how, q.right_pct, q.right_ci95, ...
                q.n_events, q.decided_pct, q.median_cycles, q.median_ms); %#ok<AGROW>
        end
    end
    if isfield(m, 'onset_cue')                       % beside KPI 1: the onset's shape at the start, the latched cause after it
        for q = m.onset_cue
            det{end+1} = sprintf(['beside KPI 1, %s with the onset in the fusion window: %.2f%% fused, %.2f%% with the ' ...
                'latched cause (%d frames); after it: %.2f%%, %.2f%% (%d frames)'], q.class, q.recall_fused_pct(1), ...
                q.recall_latched_pct(1), q.n(1), q.recall_fused_pct(2), q.recall_latched_pct(2), q.n(2)); %#ok<AGROW>
        end
    end
    if isfield(m, 'prevalence')                      % beside KPI 1, never in its place
        pv = m.prevalence;
        det{end+1} = sprintf(['beside KPI 1, prevalence-normalized (every class weighted equally): macro-F1 above the ' ...
            'threshold %.2f%% [%.2f, %.2f], lowest class %.2f%%; class shares of the frames above it: %s'], ...
            pv.macro_f1_above_threshold_pct, m.ci95.macro_f1_above_balanced, min(pv.class_f1_above_threshold_pct), ...
            strjoin(cellfun(@(c, v) sprintf('%s %.1f%%', c, v), pv.classes(:)', num2cell(pv.share_above_pct(:)'), ...
            'UniformOutput', false), ', '));
    end
    if isfield(m, 'beyond')                          % frames received below the grid, beside KPI 1
        b = m.beyond;
        det{end+1} = sprintf(['Eb/N0 of a frame: %s; received below the %g dB grid point (beyond range, not in the ' ...
            'per-Eb/N0 reading): %d of %d frames, read right in %.1f%%'], m.ebno_rule, b.grid_low_db, b.n, b.n_all, ...
            b.accuracy_pct);
    end
    if isfile(F.pol)
        Po = load(F.pol, 'KP');
        if isfield(Po.KP, 'onset')
            det{end+1} = sprintf(['beside KPI 1, onset latency in the closed loop (deployed policy, single set) ' ...
                '[cycles from the onset frame, 0 = on it; median/p90]: %s'], strjoin(arrayfun(@(o) sprintf('%s class %g/%g alarm %g/%g', o.threat, ...
                o.cls_median, o.cls_p90, o.conf_median, o.conf_p90), Po.KP.onset, 'UniformOutput', false), ', '));
        end
    end
    if isfile(F.unseen)
        U = load(F.unseen, 'summary');
        Ue = load(F.unseen, 'EBNO_ALL', 'EBNO_SEEN');
        det{end+1} = sprintf('unseen Eb/N0 (%s dB): accuracy %.2f%% vs %.2f%% seen, largest gap %.2f points', ...
            strjoin(compose('%g', setdiff(Ue.EBNO_ALL, Ue.EBNO_SEEN)), ','), U.summary.acc_unseen, U.summary.acc_seen, ...
            U.summary.max_gap);
    end
    if isfile(F.arch), det{end+1} = 'architecture comparison: results/architecture_comparison.txt'; end
    [LECT.three, LECT.three_above, l3] = three_states(m, kpi1_file('detector_predictions'));
    det = [det, l3];
    if ~contains(F.det, '_fresh2') && isfile('results/eval_detector_metrics_fresh2.mat')   % the third test set's beside
        M3 = load('results/eval_detector_metrics_fresh2.mat', 'metrics');
        [LECT.three3, LECT.three3_above, l3] = three_states(M3.metrics, 'results/detector_predictions_fresh2.mat');
        det = [det, l3];
    end
    if contains(F.det, '_fresh3') && isfile('results/eval_detector_metrics_fresh2.mat')
        Ms = load('results/eval_detector_metrics_fresh2.mat', 'metrics'); ms = Ms.metrics;
        det{end+1} = sprintf(['read on the %s, read once after the fusion revision''s go/no-go; the %s, %s%s: ' ...
            'macro-F1 above the threshold %.2f%%, lowest class %.2f%%, accuracy %.2f%%'], m.test_set, ms.test_set, when_fresh2(ms), smp(ms), ...
            ms.macro_f1_above_threshold_pct, min(ms.class_f1_above_threshold_pct), ms.overall_accuracy_pct);
    end
    if ~isempty(regexp(F.det, '_fresh[23]\.mat$', 'once')) && isfile('results/eval_detector_metrics.mat')
        Ms = load('results/eval_detector_metrics.mat', 'metrics'); ms = Ms.metrics;
        det{end+1} = sprintf(['read on the %s, built after the monitor''s last validation choice; the %s, first read ' ...
            'before that choice%s: macro-F1 above the threshold %.2f%%, lowest class %.2f%%, accuracy %.2f%%'], m.test_set, ms.test_set, smp(ms), ...
            ms.macro_f1_above_threshold_pct, min(ms.class_f1_above_threshold_pct), ms.overall_accuracy_pct);
    end
    if isfield(m, 'test_set') && isfile('results/eval_detector_metrics_split.mat')
        Ms = load('results/eval_detector_metrics_split.mat', 'metrics'); ms = Ms.metrics;
        det{end+1} = sprintf(['read on the %s; the test split of the dataset, also read before the last detector ' ...
            'change%s: macro-F1 above the threshold %.2f%%, lowest class %.2f%%, accuracy %.2f%%'], m.test_set, smp(ms), ...
            ms.macro_f1_above_threshold_pct, min(ms.class_f1_above_threshold_pct), ms.overall_accuracy_pct);
    end
    KPI(end+1) = kpi(1, 'Detection accuracy vs SNR', sprintf('macro-F1 %.2f%%, lowest class %.2f%%, from %g dB%s', val, min(cl), ...
        m.kpi1_threshold_db, smp(m)), 'macro-F1 >= 90% above a threshold chosen on validation', ...
        status(isfinite(m.kpi1_threshold_db) && val >= 90, file_time(F.det) < max(t_det, file_time('data/fusion.mat'))), det);
else
    KPI(end+1) = missing(1, 'Detection accuracy vs SNR', F.det);
end

%% KPI 2 - unknown threats
if isfile(F.ood)
    O = load(F.ood);
    j = find(strcmp(O.SC, O.sel));
    A = vertcat(O.R.auroc); FP = vertcat(O.R.fpr95); AW = cat(3, O.R.auroc_win);
    val = mean(O.NEST.auroc);                         % nested estimate: the selection never saw the threat it is scored on
    fn = NaN; if isfield(O.NEST, 'fpr95'), fn = mean(O.NEST.fpr95); end
    rd = 'the test split'; if isfield(O, 'TEST_SET'), rd = O.TEST_SET; end
    det = {sprintf(['production score %s (selected on validation by leave-one-threat-out, read on the %s): mean AUROC ' ...
        '%.3f, FPR at %.0f%% known kept %.2f (per frame)'], O.sel, rd, mean(A(:, j)), 100*O.RETAIN, mean(FP(:, j))), ...
        sprintf('nested estimate per held-out threat: %s', strjoin(arrayfun(@(i) sprintf('%s %.3f (%s)', O.R(i).held_out, ...
        O.NEST.auroc(i), O.NEST.pick{i}), 1:numel(O.R), 'UniformOutput', false), ', ')), ...
        sprintf('every score (mean AUROC): %s', strjoin(cellfun(@(n, a) sprintf('%s %.3f', n, a), O.SC, ...
        num2cell(mean(A, 1)), 'UniformOutput', false), ', ')), ...
        sprintf('production score averaged over %s frames of a run: %s', strjoin(compose('%d', O.WIN), ' / '), ...
        strjoin(compose('%.3f', mean(squeeze(AW(j, :, :)), 2)'), ' / '))};
    if all(isfield(O, {'pj', 'pw', 'MpT', 'FpT', 'sel_win'}))   % the statistic the decision cycle compares
        bd = find(strcmp(O.SC(O.pj), O.sel) & O.pw == O.sel_win, 1);
        det = [{sprintf(['deployed statistic: %s averaged over the last %d cycles, mean AUROC %.3f, FPR at %.0f%% known ' ...
            'kept %.2f (read on the %s); nested estimate: mean AUROC %.3f, FPR95 %.2f'], O.sel, O.sel_win, ...
            mean(O.MpT(:, bd)), 100*O.RETAIN, mean(O.FpT(:, bd)), rd, val, fn)}, det];
    end
    if isfield(O, 'LC')                               % latency-aware selection
        det{end+1} = sprintf(['candidates within the KPI 7 budget (detector median <= %.0f ms, p95 <= %.0f ms per ' ...
            'frame): %s; detector cost median / p95 ms: %s'], O.LC.budget.det_median_ms, O.LC.budget.det_p95_ms, ...
            strjoin(O.LC.cand(O.LC.ok), ', '), strjoin(arrayfun(@(c) sprintf('%s %.2f / %.2f (%s)%s', O.LC.cand{c}, ...
            O.LC.med(c), O.LC.p95(c), upper(O.LC.dev{c}), ternary(O.LC.ok(c), '', ' excluded')), ...
            1:numel(O.LC.cand), 'UniformOutput', false), ', '));
    end
    KPI(end+1) = kpi(2, 'Unknown threat (LOTO)', sprintf('mean AUROC %.3f, FPR95 %.2f (nested)', val, fn), ...
        sprintf('>= %.1f', KPI2_TARGET), ...
        status(val >= KPI2_TARGET, file_time(F.ood) < t_det), det);
else
    KPI(end+1) = missing(2, 'Unknown threat (LOTO)', F.ood);
end

%% KPI 3 - physical validation
if isfile(F.phy)
    txt = fileread(F.phy);
    g = regexp(txt, 'gap ([+-]\d+\.\d+) dB \(standard error (\d+\.\d+) dB\) -> (\w+)', 'tokens');
    gaps = cellfun(@(c) str2double(c{1}), g); passed = cellfun(@(c) strcmp(c{3}, 'PASS'), g);
    seeds = contains(txt, 'seeds PASS');
    tone = ~contains(txt, 'tone ') || contains(txt, 'tone PASS');      % tone calibration, when the report has it
    sp = rst(F.phy);
    det = {sprintf('seeded reproducibility: %s', ternary(seeds, 'PASS', 'FAIL')), ...
         sprintf('tone jammer calibration: %s', ternary(tone, 'PASS', 'FAIL'))};
    if sp.stale, det{end+1} = ['STALE: ' sp.why]; end
    KPI(end+1) = kpi(3, 'Model validation vs theory', sprintf('%d/%d within 0.3 dB (gaps %s dB)', sum(passed), numel(passed), ...
        strjoin(compose('%+.2f', gaps), ', ')), '<= 0.3 dB', status(all(passed) && seeds && tone && ~isempty(passed), sp.stale), det);
else
    KPI(end+1) = missing(3, 'Model validation vs theory', F.phy);
end

%% KPI 4-8 - decision layer
if isfile(F.pol)
    P = load(F.pol);
    sp = rst(F.pol);
    stale = file_time(F.pol) < t_dqn || sp.stale;
    col = @(p) find(strcmp(P.POL, p));
    iD = P.iDQN; iO = col('oracle'); iQ = col('dqn_esc');
    if startsWith(P.POL{iD}, 'dqn'), iQ = iD; end        % the deployed DQN, with or without the escalation
    dep = erase(P.LBL{iD}, ' (deployed)');
    ALL = P.ALL;
    pt = P.KP.per_threat(:, strcmp(P.KP.show, P.POL{iD}));
    [lo4, ilo] = min(pt);
    m4 = ALL{iD}.recoverable & ALL{iD}.threat;
    [r4, r4l, r4h] = boot_cluster(double(ALL{iD}.recovered(m4)), ones(1, sum(m4)), ALL{iD}.geom(m4), 2000, 3);
    pci = nan(numel(pt), 2); if isfield(P.KP, 'per_threat_ci'), pci = P.KP.per_threat_ci; end
    det = {sprintf('recovered among recoverable, per threat (%s, deployed; 95%% bootstrap over flight geometries): %s', dep, ...
        strjoin(cellfun(@(n, v, a, b) sprintf('%s %.1f%% [%.1f, %.1f]', n, v, a, b), P.KP.threats, num2cell(pt'), ...
        num2cell(pci(:, 1)'), num2cell(pci(:, 2)'), 'UniformOutput', false), ', ')), ...
        sprintf('all threat episodes pooled: %s %.1f%% [%.1f, %.1f] of %d recoverable episodes; recoverable share %s', ...
        dep, 100*r4, 100*r4l, 100*r4h, sum(m4), strjoin(cellfun(@(n, v) sprintf('%s %.0f%%', n, 100*v), P.KP.threats, ...
        num2cell(P.KP.recoverable_share'), 'UniformOutput', false), ', ')), ...
        sprintf('per severity %s, lowest threat: %s', strjoin(P.KP.sev_names, ' / '), strjoin(arrayfun(@(v) sprintf('%.1f%%', ...
        min(P.KP.per_threat_sev(~contains(P.KP.threats, '+'), v, strcmp(P.KP.show, P.POL{iD})))), ...
        1:numel(P.KP.sev_names), 'UniformOutput', false), ' / '))};
    if isfield(P.KP, 'shadow_note') && ~isempty(P.KP.shadow_note), det{end+1} = P.KP.shadow_note; end   % airframe shadowing: conditioned
    if isfield(P.KP, 'per_threat_h')                 % the stricter reading, beside KPI 4, never in its place
        ph = P.KP.per_threat_h(:, strcmp(P.KP.show, P.POL{iD}));
        det{end+1} = sprintf(['beside KPI 4, the stricter reading on the HARMED recoverable episodes only (no response does not ' ...
            'restore them): %d of %d threats >= 90%%, per threat (harmed episodes; 95%% bootstrap): %s'], sum(ph >= 90), ...
            sum(~isnan(ph)), strjoin(cellfun(@(n, v, k, a, b) sprintf('%s %.1f%% (%d) [%.1f, %.1f]', n, v, k, a, b), ...
            P.KP.threats, num2cell(ph'), num2cell(P.KP.n_harmed'), num2cell(P.KP.per_threat_h_ci(:, 1)'), ...
            num2cell(P.KP.per_threat_h_ci(:, 2)'), 'UniformOutput', false), ', '));
        if isfield(P.KP, 'per_threat_env_h')
            pe = P.KP.per_threat_env_h(:)';
            det{end+1} = sprintf(['beside KPI 4, inside the envelope predicted on validation on the harmed episodes: %d of ' ...
                '%d threats >= 90%%'], sum(pe(~isnan(pe)) >= 90), sum(~isnan(pe)));
        end
    end
    if isfield(P.KP, 'lect')                          % revised proposal: PER vs the static link
        LECT.pol = P.KP.lect;
        det = [det, per_lines(P.KP.lect, P.KP.lect, 'rule_esc', 'full action set')];
        if has_core(P.KP.lect)
            det = [det, per_lines(P.KP.lect, P.KP.lect.core, 'rule_core', core_tag(P.KP.lect.core))];
        else
            det{end+1} = ['beside KPI 4, PER vs the static link on the core action set (revised proposal): PENDING, ' ...
                F.pol ' predates it (rerun C2e)'];
        end
    else
        det{end+1} = ['beside KPI 4, PER vs the static link (revised proposal): PENDING, ' F.pol ' predates it (rerun C2e)'];
    end
    if isfield(P.KP, 'offset') && ~isempty(P.KP.offset)   % threats that end, reported apart
        o = P.KP.offset(strcmp({P.KP.offset.policy}, P.LBL{iD}));
        if ~isempty(o)
            det{end+1} = sprintf(['threats that end %d cycles after the onset (reported apart), %s: holding a configuration at ' ...
                'the end %s; its release to no_action median %s cycles; running cost held after the end %s points per cycle'], ...
                P.KP.offset_after, dep, strjoin(arrayfun(@(x) sprintf('%s %.0f%%', x.threat, x.held_pct), o, ...
                'UniformOutput', false), ', '), strjoin(arrayfun(@(x) sprintf('%s %g', x.threat, x.rel_median), o, ...
                'UniformOutput', false), ', '), strjoin(arrayfun(@(x) sprintf('%s %.2f', x.threat, x.cost_end), o, ...
                'UniformOutput', false), ', '));
        end
    end
    if isfile(F.surv)
        S = load(F.surv, 'grid_data_A', 'grid_data_B');
        det{end+1} = sprintf('survivability map (threat x severity x Eb/N0 x geometry): %s', surv_txt(S));
    end
    if isfile(F.ant3), det{end+1} = 'survivability options (antenna count, relay path): results/survivability_options.txt'; end
    if isfile(F.combo)
        Cg = load(F.combo, 'res');
        det{end+1} = sprintf(['combined threats never trained on (leave-one-combination-out): DQN + escalation %.1f%% of the ' ...
            'recoverable episodes (trained on them: %.1f%%, rule + escalation %.1f%%)'], 100 * mean([Cg.res.dqn_out]), ...
            100 * mean([Cg.res.dqn_in]), 100 * mean([Cg.res.rule]));
    end
    if isfield(P.KP, 'envelope')
        % inside the envelope predicted on validation; the full result stays in the details
        pe = P.KP.per_threat_env(:)'; he = ~isnan(pe);
        te = P.KP.threats(he);
        det = [{sprintf(['envelope predicted on validation (>= %d%% of >= %d recoverable episodes): %d of %d ' ...
            '(threat, level) cells inside; every level: lowest threat %s %.1f%%, %d of %d threats >= 90%%'], ...
            P.KP.env_rule(1), P.KP.env_rule(2), sum(P.KP.envelope(:)), sum(~isnan(P.KP.envelope_val(:))), ...
            P.KP.threats{ilo}, lo4, sum(pt >= 90), numel(pt))}, det];
        if any(~he)
            det = [det(1), {sprintf(['threats with no level inside the envelope, left out of the KPI 4 reading inside ' ...
                'it (their every-level rate below): %s'], strjoin(P.KP.threats(~he), ', '))}, det(2:end)];
        end
        if any(he)
            [loe, ile] = min(pe(he));
            eci = nan(numel(pe), 2); if isfield(P.KP, 'per_threat_env_ci'), eci = P.KP.per_threat_env_ci; end
            det = [det(1), {sprintf('inside the envelope, per threat: %s', strjoin(cellfun(@(n, v, a, b) ...
                sprintf('%s %.1f%% [%.1f, %.1f]', n, v, a, b), te, num2cell(pe(he)), num2cell(eci(he, 1)'), ...
                num2cell(eci(he, 2)'), 'UniformOutput', false), ', '))}, det(2:end)];
            val4 = sprintf('inside the envelope predicted on validation: lowest threat %s %.1f%%, %d of %d threats >= 90%%', ...
                te{ile}, loe, sum(pe(he) >= 90), sum(he));
        else
            val4 = 'no (threat, level) cell inside the envelope predicted on validation';
        end
        KPI(end+1) = kpi(4, 'Link restoration (<= 2x clean)', val4, ...
            '>= 90% of recoverable episodes, every threat, inside the envelope predicted on validation', ...
            status(any(he) && all(pe(he) >= 90), stale), det);
    else
        KPI(end+1) = kpi(4, 'Link restoration (<= 2x clean)', sprintf('lowest threat %s %.1f%%, %d of %d threats >= 90%%', ...
            P.KP.threats{ilo}, lo4, sum(pt >= 90), numel(pt)), '>= 90% of recoverable episodes, every threat', ...
            status(all(pt >= 90), stale), det);
    end

    k_r = col('rule_esc'); CDk = decision_config(); nq = erase(P.LBL{iQ}, ' (deployed)');
    [dr, drl, drh] = boot_cluster(double(ALL{iQ}.recovered(m4)) - double(ALL{k_r}.recovered(m4)), ones(1, sum(m4)), ...
        ALL{iQ}.geom(m4), 2000, 4);
    rec = ~isnan(ALL{iQ}.t_rec);
    det = {sprintf('recovered among recoverable, threat sets pooled: %s', strjoin(cellfun(@(p) sprintf('%s %.1f%%', ...
        P.LBL{col(p)}, 100 * mean(ALL{col(p)}.recovered(m4))), unique({'none', 'random', 'fixed', 'rule_esc', 'blind_esc', ...
        'table', 'dqn_esc', P.POL{iD}, 'oracle'}, 'stable'), 'UniformOutput', false), ' | ')), ...
        sprintf('%s: median T_rec %s cycles (%s ms at the %d ms decision period) | cycles restored %.1f%% | goodput %.3f', ...
        nq, num_txt(median(ALL{iQ}.t_rec(rec))), num_txt(median(ALL{iQ}.t_rec(rec)) * CDk.period_ms), CDk.period_ms, ...
        100 * mean(ALL{iQ}.ok_post), mean(ALL{iQ}.gput_post, 'omitnan'))};
    k_b = col('blind_esc');
    if ~isempty(k_b)
        [db, dbl, dbh] = boot_cluster(double(ALL{k_r}.recovered(m4)) - double(ALL{k_b}.recovered(m4)), ones(1, sum(m4)), ...
            ALL{k_r}.geom(m4), 2000, 5);
        det{end+1} = sprintf(['what the detection adds: rule + escalation vs the same response without the detector ' ...
            '(alarm from measured degradation only) %+.1f points [%+.1f, %+.1f]'], 100*db, 100*dbl, 100*dbh);
    end
    for si = find(ismember(P.set_names, {'follower', 'combined', 'comb'}))
        R = P.RES(si, :); mm = R{iQ}.recoverable & R{iQ}.threat;
        det{end+1} = sprintf('%-9s recovered: %s %.1f%% | rule+esc %.1f%% | table %.1f%% | fixed %.1f%% | oracle %.1f%%', ...
            P.set_names{si}, nq, 100*mean(R{iQ}.recovered(mm)), 100*mean(R{k_r}.recovered(mm)), 100*mean(R{col('table')}.recovered(mm)), ...
            100*mean(R{col('fixed')}.recovered(mm)), 100*mean(R{iO}.recovered(mm))); %#ok<SAGROW>
    end
    if isfield(P.KP, 'lect')                          % revised proposal: recovery time from detection, goodput in bit/s
        det = [det, rec_lines(P.KP.lect, P.KP.lect, 'full action set')];
        if has_core(P.KP.lect)
            det = [det, rec_lines(P.KP.lect, P.KP.lect.core, core_tag(P.KP.lect.core))];
        else
            det{end+1} = ['beside KPI 5, recovery time from detection and goodput in bit/s on the core action set ' ...
                '(revised proposal): PENDING, ' F.pol ' predates them (rerun C2e)'];
        end
    else
        det{end+1} = ['beside KPI 5, recovery time from detection and goodput in bit/s (revised proposal): PENDING, ' ...
            F.pol ' predates them (rerun C2e)'];
    end
    KPI(end+1) = kpi(5, 'DQN vs rules and baselines', sprintf('%s: %+.1f points recovery vs rule + escalation [%+.1f, %+.1f]', ...
        nq, 100*dr, 100*drl, 100*drh), 'better than rule (paired 95% bootstrap > 0)', status(drl > 0, stale), det);

    far = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{iD}));
    fr = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{k_r}));
    src = 'the test pools'' clean flights and those of data/clean_test_pools.mat';
    if isfield(P.KP, 'far_src'), src = P.KP.far_src; end
    det = {sprintf(['Eb/N0 >= %g dB, one episode per independent geometry (%s); per-cycle rate %.4f%% | rule + ' ...
        'escalation %d/%d, upper %.2f%%'], P.KP.ebno_thr, src, 100 * far.per_cycle, fr.k, fr.n, 100 * fr.upper)};
    thr_now = NaN;                                    % the current KPI 1 threshold
    if isfile(F.det), Mt = load(F.det, 'metrics'); if isfield(Mt.metrics, 'kpi1_threshold_db'), thr_now = Mt.metrics.kpi1_threshold_db; end, end
    stale6 = stale;
    if isfinite(thr_now) && ~isequal(P.KP.ebno_thr, thr_now)
        stale6 = true;
        det{end+1} = sprintf('STALE: read from %g dB, the current KPI 1 threshold is %g dB (rerun C2e)', P.KP.ebno_thr, thr_now);
    end
    KPI(end+1) = kpi(6, 'False alarms on a clean link', sprintf('%d/%d episodes, upper bound %.2f%%', far.k, far.n, ...
        100 * far.upper), '<= 5% (one-sided 95%), >= 600 episodes', status(far.upper <= 0.05 && far.n >= 600, stale6), det);

    det = {};
    sl = rst(F.lat); lat_pending = ~isfile(F.lat);
    if isfile(F.lat)
        Lt = load(F.lat, 'LAT'); Lt = Lt.LAT;
        if ~isfield(Lt, 'total_dep_median_ms')            % a latency without the deployed chain: the DQN chain
            Lt.total_dep_median_ms = Lt.total_dqn_median_ms; Lt.total_dep_p95_ms = Lt.total_dqn_p95_ms; Lt.deployed = 'dqn_esc';
        end
        det{end+1} = sprintf(['decision latency per cycle (%s): median %.2f ms, p95 %.2f ms (deployed chain, %s); DQN + ' ...
            'escalation chain %.2f / %.2f ms; rule chain %.2f / %.2f ms'], Lt.device, Lt.total_dep_median_ms, ...
            Lt.total_dep_p95_ms, Lt.deployed, Lt.total_dqn_median_ms, Lt.total_dqn_p95_ms, Lt.total_rule_median_ms, ...
            Lt.total_rule_p95_ms);
        if sl.stale, det{end+1} = ['STALE latency: ' sl.why ' (rerun LAT)']; end
        if isfield(Lt, 'load_text'), det{end+1} = Lt.load_text; end   % the machine's load at the timings
        det{end+1} = sprintf('components (median ms): %s', strjoin(cellfun(@(n, v) sprintf('%s %.2f', n, v), Lt.names, ...
            num2cell(Lt.median_ms), 'UniformOutput', false), ', '));
        if isfield(Lt, 'score')
            det{end+1} = sprintf('unknown-threat score in the detector: %s (selected within the KPI 7 budget, D80)', Lt.score);
        end
        det{end+1} = sprintf(['latency class (Oli & Mahalal 2025, detection systems: low < 10 ms, medium 10-100 ms): ' ...
            'median %s, p95 %s; measured on a desktop computer, not on UAV hardware'], ...
            lat_class(Lt.total_dep_median_ms), lat_class(Lt.total_dep_p95_ms));
        if isfield(Lt, 'single_core')
            sc = Lt.single_core;
            if ~isfield(sc, 'total_dep_median_ms'), sc.total_dep_median_ms = sc.total_dqn_median_ms; sc.total_dep_p95_ms = sc.total_dqn_p95_ms; end
            det{end+1} = sprintf('whole cycle on one CPU core: median %.2f ms, p95 %.2f ms', sc.total_dep_median_ms, sc.total_dep_p95_ms);
        end
        lat_ok = Lt.total_dep_median_ms < 10 && Lt.total_dep_p95_ms < 20;
        latv = sprintf('median %.2f ms, p95 %.2f ms', Lt.total_dep_median_ms, Lt.total_dep_p95_ms);
    else
        lat_ok = false; latv = 'latency not measured yet'; det{end+1} = ['PENDING: no ' F.lat ' (run LAT)'];
    end
    pv = P.KP.per_speed(:, strcmp(P.KP.show, P.POL{iD}));
    det{end+1} = sprintf('%s recovered per speed band (%s km/h): %s %%', dep, ...
        strjoin(arrayfun(@(b) sprintf('%.0f-%.0f', P.KP.speed_bins(b), P.KP.speed_bins(b+1)), ...
        1:numel(P.KP.speed_bins) - 1, 'UniformOutput', false), ', '), strjoin(compose('%.1f', pv'), ', '));
    if isfield(P.KP, 'speed_spread')
        det{end+1} = sprintf(['spread over the speed bands %.1f points [%.1f, %.1f] (95%% bootstrap over flight ' ...
            'geometries; target <= 10)'], P.KP.speed_spread);
    end
    if isfield(P.KP, 'per_speed_out') && ~isempty(P.KP.per_speed_out)
        po = P.KP.per_speed_out(:, strcmp(P.KP.show, P.POL{iD}));
        det{end+1} = sprintf('ends of the speed envelope (nominal severity): %s km/h %.1f%%, %s km/h %.1f%%', ...
            band_txt(P.KP.speed_out(1, :)), po(1), band_txt(P.KP.speed_out(2, :)), po(2));
    end
    if isfield(P.KP, 'per_delay') && ~isempty(P.KP.per_delay)
        pd = P.KP.per_delay(:, strcmp(P.KP.show, P.POL{iD}));
        det{end+1} = sprintf('signalling delay of a change: %d cycle %.1f%%, %d cycles %.1f%% (single set)', ...
            CDk.switch_delay, pd(1), 2 * CDk.switch_delay, pd(2));
    end
    st7 = status(lat_ok && max(pv) - min(pv) <= 10, stale);
    if (lat_pending || sl.stale) && ~stale, st7 = 'PENDING'; end   % the deployed chain not timed yet
    KPI(end+1) = kpi(7, 'Decision time and robustness', latv, 'median < 10 ms, p95 < 20 ms; spread <= 10 points over the speed envelope', ...
        st7, det);

    if isfield(P.KP, 'per_threat_h')                 % on the harmed episodes: no response restores none of them
        ph = P.KP.per_threat_h(:, strcmp(P.KP.show, P.POL{iD})); n_ok = sum(ph >= 50);
        KPI(end+1) = kpi(8, 'Performance floor (closed loop)', sprintf(['%d threats recovered on >= 50%% of the harmed ' ...
            'recoverable episodes'], n_ok), '>= 1 recoverable threat', status(n_ok >= 1, stale), ...
            {sprintf('on every recoverable episode (no response''s own restorations included): %d threats', sum(pt >= 50))});
    else
        n_ok = sum(pt >= 50);
        KPI(end+1) = kpi(8, 'Performance floor (closed loop)', sprintf('%d threats recovered on >= 50%% of recoverable episodes', n_ok), ...
            '>= 1 recoverable threat', status(n_ok >= 1, stale), {});
    end
    if isfile(F.dqn)
        Dq = load(F.dqn, 'seed_summary'); ss = Dq.seed_summary;
        KPI(5).detail{end+1} = sprintf('selected: alarm %s, gamma %.2f, training false-switch penalty %d, seed %d, validation gate %s', ...
            ss.selected_alarm, ss.selected_gamma, ss.selected_fa_pen, ss.selected_seed, ternary(ss.gate_pass, 'PASS', 'FAIL'));
        if isfield(ss, 'selected_kind')
            KPI(5).detail{end+1} = sprintf(['selected on validation by held recovery (restored to the end, the edge map''s REC): ' ...
                '%s, held %.1f%% (recovered %.1f%%) against rule + escalation with the same monitor %.1f%% (%.1f%%)'], ...
                ss.selected_kind, 100 * ss.dqn_held, 100 * ss.dqn_recovered, 100 * ss.rule_held, 100 * ss.rule_recovered);
        end
    end
else
    for k = 4:8, KPI(end+1) = missing(k, sprintf('KPI %d', k), F.pol); end %#ok<SAGROW>
end

%% Edge map: verdicts per point (edge_map.m)
if isfile(F.edge)
    En = load(F.edge, 'EDGE_NUM'); en = En.EDGE_NUM;
    se = rst(F.edge); n0 = arrayfun(@(q) numel(q.detail), KPI);
    cnt = @(x) sprintf('%d COMMITTED / %d NOT COMMITTED / %d UNDETERMINED', x);
    ly = @(name) find(strcmp(en.layers, name), 1);
    pts = @(i) sprintf('edge map, %s per (threat, level, Eb/N0): single threats %s | combined threats %s', ...
        en.layers{i}, cnt(en.counts_single(i, :)), cnt(en.counts_combined(i, :)));
    det = {pts(ly('DET')), pts(ly('DET_h'))};
    if isfield(en, 'det_split') && isfield(en.det_split, 'harmed_value')   % harm-conditioned detection, beside KPI 1
        ds = en.det_split; up = reshape(en.ebno, 1, []) >= en.ebno_thr;
        pool = @(r) sum(ds.harmed_value(r, up) .* ds.n_harmed(r, up), 'all', 'omitnan') / ...
            sum(ds.n_harmed(r, up) .* isfinite(ds.harmed_value(r, up)), 'all');
        det{end+1} = sprintf(['beside KPI 1, DET_h (detection on the flights the threat harms, no_action not restoring), ' ...
            'from %g dB, pooled over the points by their harmed flights: single threats %.1f%% (%d flights), combined ' ...
            '%.1f%% (%d)'], en.ebno_thr, 100 * pool(ds.is_single), sum(ds.n_harmed(ds.is_single, up), 'all'), ...
            100 * pool(~ds.is_single), sum(ds.n_harmed(~ds.is_single, up), 'all'));
    end
    if ~isempty(en.b4)
        det{end+1} = sprintf('edge map, detector beyond 0-15 dB (%d classes, >= 90%% same countermeasure): %s', ...
            numel(unique({en.b4.cls})), strjoin(arrayfun(@(e) sprintf('%g dB %s', e, ...
            cnt(arrayfun(@(v) sum([en.b4([en.b4.ebno] == e).verdict] == v), [1 -1 0]))), unique([en.b4.ebno]), ...
            'UniformOutput', false), ' | '));
    end
    k = find([KPI.id] == 1, 1); KPI(k).detail = [KPI(k).detail, det];
    inom = find(ismember(en.cells, en.nominal));
    det = arrayfun(@(d) sprintf(['edge map, COMMITTED (PROT, DET_h, FA, LINK, LINK_T, no band NOT COMMITTED) at a ' ...
        'signalling delay of %d cycles: single threats %s | combined threats %s; %d inside a walk region, %d not ' ...
        'attributable to the decision layer'], en.delays(d), cnt(en.commit_single(d, :)), cnt(en.commit_combined(d, :)), ...
        en.commit_inside(d), en.commit_not_attributable(d)), 1:numel(en.delays), 'UniformOutput', false);
    det{end+1} = sprintf('edge map, without signalling (the receiver alone): single threats %s | combined threats %s', ...
        cnt(en.floor_single), cnt(en.floor_combined));
    det = [det, {pts(ly('SYSTEM')), pts(ly('SYSTEM+LINK')), sprintf(['edge map, COMMITTED distance edge at the nominal ' ...
        'level, delay %d (Eb/N0 from 15 dB down to the last COMMITTED point): %s'], en.delays(1), ...
        strjoin(arrayfun(@(i) sprintf('%s %s', en.cells{i}, edge_km(en.edge_commit_db(1, i), en.edge_commit_km(1, i))), ...
        inom, 'UniformOutput', false), ', ')), ...
        sprintf('edge map, overhead pass (altitude x distance): %s', cnt(arrayfun(@(v) sum(en.ohp_verdict(:) == v), [1 -1 0])))}];
    k = find([KPI.id] == 4, 1); KPI(k).detail = [KPI(k).detail, det];
    k = find([KPI.id] == 6, 1);
    KPI(k).detail{end+1} = sprintf('edge map, clean link per Eb/N0 (%s dB), delay %d: FA <= 5%% %s | LINK <= 1.4%% %s', ...
        strjoin(compose('%g', en.ebno), '/'), en.delays(1), strjoin(arrayfun(@(v, n) sprintf('%s(%d)', vsym(v), n), ...
        en.fa_verdict(1, :), en.fa_n(1, :), 'UniformOutput', false), ' '), strjoin(arrayfun(@(v, n) sprintf('%s(%d)', ...
        vsym(v), n), en.link_verdict, en.link_n, 'UniformOutput', false), ' '));
    hv = 'hover';
    if isfield(en, 'fa_claim_verdict')
        KPI(k).detail{end+1} = sprintf(['edge map, FA as the commitment reads it (the clean flights from %g dB up, or ' ...
            'from the point up below it), delay %d: %s'], en.ebno_thr, en.delays(1), strjoin(arrayfun(@(v, n) ...
            sprintf('%s(%d)', vsym(v), n), en.fa_claim_verdict(1, :), en.fa_claim_n(1, :), 'UniformOutput', false), ' '));
        hv = en.hover_label;
    end
    k = find([KPI.id] == 7, 1);
    KPI(k).detail{end+1} = sprintf('edge map, COMMITTED at the nominal level of %d threats: %s %s | 161 km/h %s', ...
        numel(inom), hv, cnt(arrayfun(@(v) sum(en.hover == v), [1 -1 0])), cnt(arrayfun(@(v) sum(en.v161 == v), [1 -1 0])));
    if se.stale                                         % every edge-map detail of another detector or policy, flagged
        for k = 1:numel(KPI)
            for i = n0(k) + 1:numel(KPI(k).detail), KPI(k).detail{i} = ['[STALE edge map: ' se.why '] ' KPI(k).detail{i}]; end
        end
    end
end

%% Report
for k = 1:numel(KPI)
    q = KPI(k);
    rep{end+1} = sprintf('KPI %d  %-28s %-8s %s   (target: %s)', q.id, q.name, ['[' q.status ']'], q.value, q.target); %#ok<SAGROW>
    for i = 1:numel(q.detail), rep{end+1} = ['        ' q.detail{i}]; end %#ok<SAGROW>
    rep{end+1} = ''; %#ok<SAGROW>
end
fid = fopen('results/kpi_summary.txt', 'w'); fprintf(fid, '%s\n', rep{:}); fclose(fid);
fprintf('%s\n', rep{:});
save('results/kpi_summary.mat', 'KPI', 'LECT');
fprintf('Saved results/kpi_summary.{txt,mat}\n');

%% ===================== Local functions =====================
function q = kpi(id, name, value, target, st, detail)
q = struct('id', id, 'name', name, 'value', value, 'target', target, 'status', st, 'detail', {detail});
end

function q = missing(id, name, f)
q = kpi(id, name, 'not available', '-', 'MISSING', {['missing ' f]});
end

function s = status(ok, stale)
if stale, s = 'STALE'; elseif ok, s = 'MET'; else, s = 'NOT MET'; end
end

function t = file_time(f)
if isfile(f), t = dir(f).datenum; else, t = -inf; end
end

function [V, Va, lines] = three_states(m, fp)
% The three link states (three_state_view.m) from the saved reading: every Eb/N0 from its
% confusion matrix, and above the KPI 1 threshold from the saved predictions of the same
% reading (as many frames); no new test reading.
V = []; Va = []; lines = {};
if ~isfield(m, 'conf_mat') || ~isfield(m, 'classes'), return; end
V = three_state_view(m.conf_mat, m.classes);
ts = 'the test set'; if isfield(m, 'test_set'), ts = m.test_set; end
lines{1} = sprintf(['beside KPI 1, three link states (revised proposal; %s, saved confusion matrix, every Eb/N0; frames ' ...
    'of none / tone_jamming / jamming, another class read is an error): %s'], ts, three_txt(V));
if ~isfile(fp) || ~isfield(m, 'kpi1_threshold_db') || ~isfinite(m.kpi1_threshold_db), return; end
Pd = load(fp, 'pred'); pr = Pd.pred;
if numel(pr.y_true) ~= sum(m.conf_mat(:)), return; end   % predictions of another reading
ab = pr.ebno(:) >= m.kpi1_threshold_db;
[~, it] = ismember(cellstr(pr.y_true(ab)), m.classes); [~, ip] = ismember(cellstr(pr.y_pred(ab)), m.classes);
ok = it > 0 & ip > 0; nc = numel(m.classes);
Va = three_state_view(accumarray([it(ok) ip(ok)], 1, [nc nc]), m.classes);
lines{2} = sprintf('beside KPI 1, three link states from %g dB (the KPI 1 threshold, saved predictions): %s', ...
    m.kpi1_threshold_db, three_txt(Va));
end

function s = three_txt(V)
s = sprintf(['recall narrowband %.2f%%, wideband %.2f%% (>= 85%% each: %s), clean %.2f%%; 3-state macro-F1 %.2f%% ' ...
    '(>= 85%%: %s); frames %d / %d / %d'], 100 * V.recall(2), 100 * V.recall(3), ternary(all(V.recall(2:3) >= 0.85), ...
    'met', 'not met'), 100 * V.recall(1), 100 * V.macro_f1, ternary(V.macro_f1 >= 0.85, 'met', 'not met'), V.n);
end

function lines = per_lines(Lk, S, tgt, tag)
% PER vs the static link (lect_kpis.m), beside KPI 4: S the readings of one action set (Lk, or
% Lk.core), tgt its rule with the detector, tag the set's name.
lines = {};
q = S.per(strcmp({S.per.policy}, tgt));
if isempty(q), return; end
o = S.per(~strcmp({S.per.policy}, tgt));
lines{1} = sprintf(['beside KPI 4, PER vs the static link (revised proposal, %s), recoverable jamming episodes (%d), paired, ' ...
    '95%% bootstrap over flight geometries: %s %.2f%% vs %.2f%% static, reduction %.1f%% [%.1f, %.1f] -> %s (target >= %d%%; ' ...
    'interval %s it)%s'], tag, q.n, q.label, q.per_pct, q.per_ref_pct, q.red_pct, q.ci, ternary(q.met, 'MET', 'NOT MET'), ...
    Lk.target_pct, ternary(q.ci_above, 'wholly above', 'not wholly above'), strjoin(arrayfun(@(x) sprintf('; %s %.1f%% [%.1f, %.1f]', ...
    x.label, x.red_pct, x.ci), o, 'UniformOutput', false), ''));
if ~isempty(S.per_threat)
    lines{end+1} = sprintf('beside KPI 4, PER reduction per jamming threat, %s (%s): %s', tag, strjoin({S.per.label}, ' | '), ...
        strjoin(arrayfun(@(t) sprintf('%s%s %s', t.threat, ternary(isempty(t.band), '', [' (' t.band ')']), ...
        strjoin(compose('%.1f%%', t.red_pct), ' | ')), S.per_threat, 'UniformOutput', false), ', '));
end
if isfinite(S.cnn.per_red_pct)
    rt = '';
    if isfield(S.cnn, 'rec_det')
        rt = sprintf('; with vs without the detector, onset->detection %s vs %s, detection->restored %s vs %s', ...
            tq(S.cnn.det(1)), tq(S.cnn.det(2)), tq(S.cnn.rec_det(1)), tq(S.cnn.rec_det(2)));
    end
    lines{end+1} = sprintf(['beside KPI 4, CNN contribution, %s (%s vs the same escalation without the detector): ' ...
        'PER reduction %.1f%% [%.1f, %.1f], goodput %+.0f bit/s [%+.0f, %+.0f] (%d episodes)%s'], tag, q.label, ...
        S.cnn.per_red_pct, S.cnn.per_ci, S.cnn.gput_bps, S.cnn.gput_ci, S.cnn.n, rt);
end
end

function lines = rec_lines(Lk, S, tag)
% Recovery time from detection, onset-to-detection time and goodput in bit/s (lect_kpis.m), beside
% KPI 5: S the readings of one action set (Lk, or Lk.core), tag the set's name.
lines = {};
for sn = unique({S.rec.set}, 'stable')
    r = S.rec(strcmp({S.rec.set}, sn{1}));
    lines{end+1} = sprintf(['beside KPI 5, recovery time (revised proposal, %s: first confirmed alarm until the packet loss ' ...
        'stays <= 2x clean for %d cycles), %s (%d) [cycles of %g ms, median/p90]: %s'], tag, Lk.run, sn{1}, r(1).n, ...
        Lk.period_ms, strjoin(arrayfun(@(x) sprintf('%s: onset->detection %s, detection->restored %s, T_rec from onset %s', ...
        x.label, tq(x.det), tq(x.rec_det), tq(x.t_rec)), r, 'UniformOutput', false), ' | ')); %#ok<AGROW>
end
lines{end+1} = sprintf(['beside KPI 5, goodput after onset in bit/s (%s; nominal payload %.0f bit/s), threat episodes | ' ...
    'recoverable jamming episodes, normalized beside: %s'], tag, Lk.payload_bps, strjoin(arrayfun(@(g) sprintf(['%s %.0f ' ...
    '[%.0f, %.0f] (%.3f) | %.0f [%.0f, %.0f] (%.3f)'], g.label, g.bps, g.ci, g.norm, g.bps_jam, g.ci_jam, g.norm_jam), ...
    S.gput, 'UniformOutput', false), '; '));
end

function tf = has_core(Lk)
% The core action set's readings are in the policy evaluation (lect_kpis.m L.core).
tf = isfield(Lk, 'core') && ~isempty(Lk.core);
end

function s = core_tag(S)
% Name of the core action set with its configurations.
s = sprintf('core action set {%s}', strjoin(S.actions, ', '));
end

function s = tq(t)
% Median / p90 and the share never reached of a time statistic (lect_kpis.m).
if isnan(t.median), s = sprintf('- (never %.0f%%)', t.never_pct); else, s = sprintf('%g/%g (never %.0f%%)', t.median, t.p90, t.never_pct); end
end

function s = num_txt(x)
if isnan(x), s = '-'; else, s = sprintf('%.0f', x); end
end

function s = surv_txt(S)
parts = {};
for mk = {'A', 'B'}
    g = S.(['grid_data_' mk{1}]); st = [];
    for k = 1:numel(g), st = [st; g(k).status(:)]; end %#ok<AGROW>
    st = st(st > 0);
    parts{end+1} = sprintf('Map %s recoverable %.0f%% / marginal %.0f%% / non-recoverable %.0f%%', mk{1}, ...
        100 * mean(st == 1), 100 * mean(st == 2), 100 * mean(st == 3)); %#ok<AGROW>
end
s = strjoin(parts, ' | ');
end

function s = smp(m)
% ', in-sample (fit set of the deployed fusion)' for a reading of a set the deployed fusion was
% fitted on (eval_detector.m metrics.sample, fusion_reading.m), else ''.
s = ''; if isfield(m, 'sample') && ~isempty(m.sample), s = [', ' m.sample]; end
end

function s = when_fresh2(ms)
% The third test set's reading beside a KPI 1 of the fourth: the rehearsal taken after the
% deploy when it was read with the deployed revision or the kept fusion after a no-go
% (metrics.fusion_state, fusion_reading.m); else the reading taken before the go/no-go.
s = 'read before it';
if isfield(ms, 'fusion_state') && ~isempty(ms.fusion_state), s = ['the rehearsal after the deploy, read with the ' ms.fusion_state]; end
end

function s = read_state(m)
% The fusion a reading was read with, when it is the deployed revision or the kept fusion after a
% no-go (fusion_reading.m), with its sample label.
s = ''; if isfield(m, 'fusion_state') && ~isempty(m.fusion_state), s = ['read with the ' m.fusion_state smp(m)]; end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function s = band_txt(b)
% Speed band [km/h] as text, one value when the band is a single speed.
if b(1) == b(2), s = sprintf('%g', b(1)); else, s = sprintf('%g-%g', b); end
end

function s = vsym(v)
% Verdict of edge_verdict.m as a letter: C COMMITTED, N NOT COMMITTED, U UNDETERMINED.
if isnan(v), s = '-'; else, s = 'NUC'; s = s(v + 2); end
end

function s = edge_km(e, d)
if isnan(e), s = 'none'; else, s = sprintf('%g dB (%.2f km)', e, d); end
end

function s = lat_class(ms)
% Latency class of a detection system (Oli & Mahalal, IEEE Access 2025, Table 8).
if ms < 10, s = 'low (< 10 ms)'; elseif ms <= 100, s = 'medium (10-100 ms)'; else, s = 'high (> 100 ms)'; end
end

function s = git_stamp()
% Commit of the code that produced the report.
[st, h] = system('git rev-parse --short HEAD');
[~, d] = system('git status --porcelain --untracked-files=no');
if st ~= 0, s = 'commit unknown'; return; end
s = ['commit ' strtrim(h)];
if ~isempty(strtrim(d)), s = [s ' + local changes']; end
end
