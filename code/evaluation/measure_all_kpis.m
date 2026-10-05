%% MEASURE_ALL_KPIS - The proposal KPIs from the result files
% Reads the outputs of the pipeline, never re-runs them: a missing source is
% reported as such, and a source older than its inputs (detector, decision layer)
% is flagged STALE. Targets as worded in the proposal:
%   KPI 1  detection: macro-F1 and every class F1 >= 90% above an Eb/N0 threshold
%          (eval_detector), unseen Eb/N0 (eval_unseen_snr)
%   KPI 2  unknown threats: leave-one-threat-out mean AUROC >= KPI2_TARGET, FPR at 95%
%          of known frames kept (eval_ood_detection; the nested estimate of the
%          selected production score)
%   KPI 3  physical validation: BER vs theory within 0.3 dB (validate_phy)
%   KPI 4  restoration: BER and packet loss back to <= 2x clean on >= 90% of the
%          recoverable episodes of EVERY threat, combined threats included, over
%          five severities; survivability boundary (evaluate_policies,
%          map_survivability_boundary)
%   KPI 5  DQN vs no response, rule, random, fixed and oracle: recovery, recovery
%          time, restored cycles, goodput, follower and unseen combinations;
%          paired 95% bootstrap interval of the recovery difference vs rule > 0
%   KPI 6  false alarms on a healthy link above the Eb/N0 threshold: one-sided
%          95% Clopper-Pearson bound over >= 600 independent episodes <= 5%
%   KPI 7  real time: decision latency median < 10 ms (Oli & Mahalal, low class)
%          and p95 < 20 ms (also on one CPU core); robustness over the speed
%          envelope (recovery spread <= 10 points), flights at its ends reported
%   KPI 8  minimum: a closed loop restoring at least one recoverable threat
% With results/edge_map.mat (edge_map.m), the verdicts per point are added as details:
% detection and detection on harmed flights (KPI 1); the commitment at every signalling
% delay, the receiver alone, the relative criterion (SYSTEM), the distance edges and the
% overhead pass (KPI 4); the clean link (KPI 6); hover and 161 km/h (KPI 7).
%
% Output: results/kpi_summary.txt, results/kpi_summary.mat (KPI struct array)

close all; clc;
fprintf('=== KPI summary ===\n\n');
F = struct('det', 'results/eval_detector_metrics.mat', 'unseen', 'results/unseen_snr.mat', ...
    'ood', 'results/ood_detection.mat', 'phy', 'results/phy_validation.txt', ...
    'pol', 'results/policy_evaluation.mat', 'lat', 'results/latency.mat', ...
    'surv', 'data/survivability_boundary.mat', 'dqn', 'data/trained_dqn.mat', 'arch', 'results/architecture_comparison.txt', ...
    'ant3', 'results/survivability_options.txt', 'combo', 'results/combo_generalization.mat', 'edge', 'results/edge_map.mat');
KPI2_TARGET = 0.8;                                 % mean AUROC (the submitted proposal's target, kept in the update)
t_det = file_time('data/trained_detector.mat'); t_dqn = file_time(F.dqn);
if isfile('data/trained_detector.mat')             % training time (the file is updated later by the OOD stage)
    Dt = load('data/trained_detector.mat', 'trained_at');
    if isfield(Dt, 'trained_at'), t_det = Dt.trained_at; end
end
KPI = struct('id', {}, 'name', {}, 'value', {}, 'target', {}, 'status', {}, 'detail', {});
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
    KPI(end+1) = kpi(1, 'Detection accuracy vs SNR', sprintf('macro-F1 %.2f%%, lowest class %.2f%%, from %g dB', val, min(cl), ...
        m.kpi1_threshold_db), 'macro-F1 and every class >= 90% above a threshold', ...
        status(isfinite(m.kpi1_threshold_db) && val >= 90 && all(cl >= 90), file_time(F.det) < t_det), det);
else
    KPI(end+1) = missing(1, 'Detection accuracy vs SNR', F.det);
end

%% KPI 2 - unknown threats
if isfile(F.ood)
    O = load(F.ood);
    j = find(strcmp(O.SC, O.sel));
    A = vertcat(O.R.auroc); FP = vertcat(O.R.fpr95); AW = cat(3, O.R.auroc_win);
    val = mean(O.NEST.auroc);                         % nested estimate: the selection never saw the threat it is scored on
    det = {sprintf('production score %s (selected by leave-one-threat-out): mean AUROC %.3f, FPR at %.0f%% known kept %.2f', ...
        O.sel, mean(A(:, j)), 100*O.RETAIN, mean(FP(:, j))), ...
        sprintf('nested estimate per held-out threat: %s', strjoin(arrayfun(@(i) sprintf('%s %.3f (%s)', O.R(i).held_out, ...
        O.NEST.auroc(i), O.NEST.pick{i}), 1:numel(O.R), 'UniformOutput', false), ', ')), ...
        sprintf('every score (mean AUROC): %s', strjoin(cellfun(@(n, a) sprintf('%s %.3f', n, a), O.SC, ...
        num2cell(mean(A, 1)), 'UniformOutput', false), ', ')), ...
        sprintf('production score averaged over %s frames of a run: %s', strjoin(compose('%d', O.WIN), ' / '), ...
        strjoin(compose('%.3f', mean(squeeze(AW(j, :, :)), 2)'), ' / '))};
    if isfield(O, 'LC')                               % latency-aware selection
        det{end+1} = sprintf(['candidates within the KPI 7 budget (detector median <= %.0f ms, p95 <= %.0f ms per ' ...
            'frame): %s; detector cost median / p95 ms: %s'], O.LC.budget.det_median_ms, O.LC.budget.det_p95_ms, ...
            strjoin(O.LC.cand(O.LC.ok), ', '), strjoin(arrayfun(@(c) sprintf('%s %.2f / %.2f (%s)%s', O.LC.cand{c}, ...
            O.LC.med(c), O.LC.p95(c), upper(O.LC.dev{c}), ternary(O.LC.ok(c), '', ' excluded')), ...
            1:numel(O.LC.cand), 'UniformOutput', false), ', '));
    end
    KPI(end+1) = kpi(2, 'Unknown threat (LOTO)', sprintf('mean AUROC %.3f (nested)', val), sprintf('>= %.1f', KPI2_TARGET), ...
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
    KPI(end+1) = kpi(3, 'Model validation vs theory', sprintf('%d/%d within 0.3 dB (gaps %s dB)', sum(passed), numel(passed), ...
        strjoin(compose('%+.2f', gaps), ', ')), '<= 0.3 dB', status(all(passed) && seeds && tone && ~isempty(passed), false), ...
        {sprintf('seeded reproducibility: %s', ternary(seeds, 'PASS', 'FAIL')), ...
         sprintf('tone jammer calibration: %s', ternary(tone, 'PASS', 'FAIL'))});
else
    KPI(end+1) = missing(3, 'Model validation vs theory', F.phy);
end

%% KPI 4-8 - decision layer
if isfile(F.pol)
    P = load(F.pol);
    stale = file_time(F.pol) < t_dqn;
    col = @(p) find(strcmp(P.POL, p));
    iD = P.iDQN; iO = col('oracle'); iQ = col('dqn_esc');
    dep = erase(P.LBL{iD}, ' (deployed)');
    ALL = P.ALL;
    pt = P.KP.per_threat(:, strcmp(P.KP.show, P.POL{iD}));
    [lo4, ilo] = min(pt);
    m4 = ALL{iD}.recoverable & ALL{iD}.threat;
    [r4, r4l, r4h] = boot_cluster(double(ALL{iD}.recovered(m4)), ones(1, sum(m4)), ALL{iD}.geom(m4), 2000, 3);
    det = {sprintf('recovered among recoverable, per threat (%s, deployed): %s', dep, strjoin(cellfun(@(n, v) sprintf('%s %.1f%%', n, v), ...
        P.KP.threats, num2cell(pt'), 'UniformOutput', false), ', ')), ...
        sprintf('all threat episodes pooled: %s %.1f%% [%.1f, %.1f] of %d recoverable episodes; recoverable share %s', ...
        dep, 100*r4, 100*r4l, 100*r4h, sum(m4), strjoin(cellfun(@(n, v) sprintf('%s %.0f%%', n, 100*v), P.KP.threats, ...
        num2cell(P.KP.recoverable_share'), 'UniformOutput', false), ', ')), ...
        sprintf('per severity %s, lowest threat: %s', strjoin(P.KP.sev_names, ' / '), strjoin(arrayfun(@(v) sprintf('%.1f%%', ...
        min(P.KP.per_threat_sev(~contains(P.KP.threats, '+'), v, strcmp(P.KP.show, P.POL{iD})))), ...
        1:numel(P.KP.sev_names), 'UniformOutput', false), ' / '))};
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
        if any(he)
            [loe, ile] = min(pe(he));
            det = [det(1), {sprintf('inside the envelope, per threat: %s', strjoin(cellfun(@(n, v) sprintf('%s %.1f%%', ...
                n, v), te, num2cell(pe(he)), 'UniformOutput', false), ', '))}, det(2:end)];
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

    k_r = col('rule_esc'); CDk = decision_config();
    [dr, drl, drh] = boot_cluster(double(ALL{iQ}.recovered(m4)) - double(ALL{k_r}.recovered(m4)), ones(1, sum(m4)), ...
        ALL{iQ}.geom(m4), 2000, 4);
    rec = ~isnan(ALL{iQ}.t_rec);
    det = {sprintf('recovered among recoverable, threat sets pooled: %s', strjoin(cellfun(@(p) sprintf('%s %.1f%%', ...
        P.LBL{col(p)}, 100 * mean(ALL{col(p)}.recovered(m4))), unique({'none', 'random', 'fixed', 'rule_esc', 'blind_esc', ...
        'table', 'dqn_esc', P.POL{iD}, 'oracle'}, 'stable'), 'UniformOutput', false), ' | ')), ...
        sprintf('DQN + escalation: median T_rec %s cycles (%s ms at the %d ms decision period) | cycles restored %.1f%% | goodput %.3f', ...
        num_txt(median(ALL{iQ}.t_rec(rec))), num_txt(median(ALL{iQ}.t_rec(rec)) * CDk.period_ms), CDk.period_ms, ...
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
        det{end+1} = sprintf('%-9s recovered: DQN + esc. %.1f%% | rule+esc %.1f%% | table %.1f%% | fixed %.1f%% | oracle %.1f%%', ...
            P.set_names{si}, 100*mean(R{iQ}.recovered(mm)), 100*mean(R{k_r}.recovered(mm)), 100*mean(R{col('table')}.recovered(mm)), ...
            100*mean(R{col('fixed')}.recovered(mm)), 100*mean(R{iO}.recovered(mm))); %#ok<SAGROW>
    end
    KPI(end+1) = kpi(5, 'DQN vs rules and baselines', sprintf('%+.1f points recovery vs rule + escalation [%+.1f, %+.1f]', ...
        100*dr, 100*drl, 100*drh), 'better than rule (paired 95% bootstrap > 0)', status(drl > 0, stale), det);

    far = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{iD}));
    fr = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{k_r}));
    KPI(end+1) = kpi(6, 'False alarms on a clean link', sprintf('%d/%d episodes, upper bound %.2f%%', far.k, far.n, ...
        100 * far.upper), '<= 5% (one-sided 95%), >= 600 episodes', status(far.upper <= 0.05 && far.n >= 600, stale), ...
        {sprintf('Eb/N0 >= %g dB, one episode per independent geometry; per-cycle rate %.4f%% | rule + escalation %d/%d, upper %.2f%%', ...
        P.KP.ebno_thr, 100 * far.per_cycle, fr.k, fr.n, 100 * fr.upper)});

    det = {};
    if isfile(F.lat)
        Lt = load(F.lat, 'LAT'); Lt = Lt.LAT;
        det{end+1} = sprintf('decision latency per cycle (%s): median %.2f ms, p95 %.2f ms (DQN + escalation chain); rule chain %.2f / %.2f ms', ...
            Lt.device, Lt.total_dqn_median_ms, Lt.total_dqn_p95_ms, Lt.total_rule_median_ms, Lt.total_rule_p95_ms);
        det{end+1} = sprintf('components (median ms): %s', strjoin(cellfun(@(n, v) sprintf('%s %.2f', n, v), Lt.names, ...
            num2cell(Lt.median_ms), 'UniformOutput', false), ', '));
        if isfield(Lt, 'score')
            det{end+1} = sprintf('unknown-threat score in the detector: %s (selected within the KPI 7 budget, D80)', Lt.score);
        end
        det{end+1} = sprintf(['latency class (Oli & Mahalal 2025, detection systems: low < 10 ms, medium 10-100 ms): ' ...
            'median %s, p95 %s; measured on a desktop computer, not on UAV hardware'], ...
            lat_class(Lt.total_dqn_median_ms), lat_class(Lt.total_dqn_p95_ms));
        if isfield(Lt, 'single_core')
            det{end+1} = sprintf('whole cycle on one CPU core: median %.2f ms, p95 %.2f ms', ...
                Lt.single_core.total_dqn_median_ms, Lt.single_core.total_dqn_p95_ms);
        end
        lat_ok = Lt.total_dqn_median_ms < 10 && Lt.total_dqn_p95_ms < 20;
        latv = sprintf('median %.2f ms, p95 %.2f ms', Lt.total_dqn_median_ms, Lt.total_dqn_p95_ms);
    else
        lat_ok = false; latv = 'latency not measured'; det{end+1} = ['missing ' F.lat];
    end
    pv = P.KP.per_speed(:, strcmp(P.KP.show, P.POL{iD}));
    det{end+1} = sprintf('%s recovered per speed band (%s km/h): %s %%', dep, ...
        strjoin(arrayfun(@(b) sprintf('%.0f-%.0f', P.KP.speed_bins(b), P.KP.speed_bins(b+1)), ...
        1:numel(P.KP.speed_bins) - 1, 'UniformOutput', false), ', '), strjoin(compose('%.1f', pv'), ', '));
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
    KPI(end+1) = kpi(7, 'Decision time and robustness', latv, 'median < 10 ms, p95 < 20 ms; spread <= 10 points over the speed envelope', ...
        status(lat_ok && max(pv) - min(pv) <= 10, stale), det);

    n_ok = sum(pt >= 50);
    KPI(end+1) = kpi(8, 'Performance floor (closed loop)', sprintf('%d threats recovered on >= 50%% of recoverable episodes', n_ok), ...
        '>= 1 recoverable threat', status(n_ok >= 1, stale), {});
    if isfile(F.dqn)
        Dq = load(F.dqn, 'seed_summary'); ss = Dq.seed_summary;
        KPI(5).detail{end+1} = sprintf('selected: alarm %s, gamma %.2f, training false-switch penalty %d, seed %d, validation gate %s', ...
            ss.selected_alarm, ss.selected_gamma, ss.selected_fa_pen, ss.selected_seed, ternary(ss.gate_pass, 'PASS', 'FAIL'));
    end
else
    for k = 4:8, KPI(end+1) = missing(k, sprintf('KPI %d', k), F.pol); end %#ok<SAGROW>
end

%% Edge map: verdicts per point (edge_map.m)
if isfile(F.edge)
    En = load(F.edge, 'EDGE_NUM'); en = En.EDGE_NUM;
    cnt = @(x) sprintf('%d COMMITTED / %d NOT COMMITTED / %d UNDETERMINED', x);
    ly = @(name) find(strcmp(en.layers, name), 1);
    pts = @(i) sprintf('edge map, %s per (threat, level, Eb/N0): single threats %s | combined threats %s', ...
        en.layers{i}, cnt(en.counts_single(i, :)), cnt(en.counts_combined(i, :)));
    det = {pts(ly('DET')), pts(ly('DET_h'))};
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
save('results/kpi_summary.mat', 'KPI');
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
