%% MEASURE_ALL_KPIS - The proposal KPIs (section 5) from the result files (D46)
% Reads the outputs of the pipeline, never re-runs them: a missing or stale
% source is reported as such. A source older than its inputs (detector,
% decision layer) is flagged STALE.
%   KPI 1  detection: macro-F1 >= 90% above an Eb/N0 threshold (eval_detector)
%   KPI 2  unknown threats: leave-one-threat-out AUROC >= 0.8, FPR at 95% kept
%          (eval_ood_detection, Mahalanobis score)
%   KPI 3  physical validation: BER vs theory within 0.3 dB (validate_phy)
%   KPI 4  restoration: BER <= 2x clean on recoverable attacks, and the
%          survivability boundary (evaluate_policies, map_survivability_boundary)
%   KPI 5  DQN vs rule, table, fixed and oracle: recovery time, restored
%          cycles, goodput, follower jammer and unseen combinations (evaluate_policies)
%   KPI 6  false alarms on a healthy link above the Eb/N0 threshold: one-sided
%          95% Clopper-Pearson bound over >= 600 episodes, target <= 5% (evaluate_policies)
%   KPI 7  real time: decision latency median / p95 (measure_latency) and
%          robustness over 50-120 km/h (evaluate_policies, eval_detector)
%   KPI 8  minimum: a closed loop restoring at least one recoverable threat
%
% Output: results/kpi_summary.txt, results/kpi_summary.mat (KPI struct array)

close all; clc;
fprintf('=== KPI summary (proposal section 5, D46) ===\n\n');
F = struct('det', 'results/eval_detector_metrics.mat', 'unseen', 'results/unseen_snr.mat', ...
    'ood', 'results/ood_detection.mat', 'phy', 'results/phy_validation.txt', ...
    'pol', 'results/policy_evaluation.mat', 'lat', 'results/latency.mat', ...
    'surv', 'data/survivability_boundary.mat', 'dqn', 'data/trained_dqn.mat');
t_det = file_time('data/trained_detector.mat'); t_dqn = file_time(F.dqn);
KPI = struct('id', {}, 'name', {}, 'value', {}, 'target', {}, 'status', {}, 'detail', {});
rep = {'=== PROPOSAL KPI SUMMARY (section 5) ===', sprintf('Generated: %s', datestr(now)), ''};

%% KPI 1 - detection
if isfile(F.det)
    M = load(F.det, 'metrics'); m = M.metrics;
    val = m.macro_f1_above_threshold_pct;
    det = {sprintf('accuracy %.2f%%, macro-F1 %.2f%% [%.2f, %.2f] (bootstrap over sub-runs)', ...
        m.overall_accuracy_pct, m.macro_f1_pct, m.ci95.macro_f1), ...
        sprintf('macro-F1 per Eb/N0: %s', strjoin(arrayfun(@(b) sprintf('%g dB %.1f%%', b.snr_db, b.macro_f1_pct), ...
        m.snr_breakdown, 'UniformOutput', false), ' | '))};
    if isfile(F.unseen)
        U = load(F.unseen, 'summary');
        det{end+1} = sprintf('unseen Eb/N0 (1,3,5,7,9 dB): accuracy %.2f%% vs %.2f%% seen, largest gap %.2f points', ...
            U.summary.acc_unseen, U.summary.acc_seen, U.summary.max_gap);
    end
    KPI(end+1) = kpi(1, 'Detection vs SNR', sprintf('macro-F1 %.2f%% from %g dB', val, m.kpi1_threshold_db), ...
        '>= 90% above a threshold', status(val >= 90, file_time(F.det) < t_det), det);
else
    KPI(end+1) = missing(1, 'Detection vs SNR', F.det);
end

%% KPI 2 - unknown threats
if isfile(F.ood)
    O = load(F.ood, 'R', 'SC', 'RETAIN');
    j = find(strcmp(O.SC, 'maha'));
    A = vertcat(O.R.auroc); FP = vertcat(O.R.fpr95);
    val = mean(A(:, j));
    det = {sprintf('Mahalanobis AUROC per held-out threat: %s', strjoin(arrayfun(@(i) sprintf('%s %.3f', ...
        O.R(i).held_out, A(i, j)), 1:numel(O.R), 'UniformOutput', false), ', ')), ...
        sprintf('mean FPR at %.0f%% known kept: %.2f | other scores (mean AUROC): %s', 100*O.RETAIN, mean(FP(:, j)), ...
        strjoin(cellfun(@(n, a) sprintf('%s %.3f', n, a), O.SC, num2cell(mean(A, 1)), 'UniformOutput', false), ', '))};
    KPI(end+1) = kpi(2, 'Unknown threats (LOTO)', sprintf('mean AUROC %.3f', val), '>= 0.8', ...
        status(val >= 0.8, file_time(F.ood) < t_det), det);
else
    KPI(end+1) = missing(2, 'Unknown threats (LOTO)', F.ood);
end

%% KPI 3 - physical validation
if isfile(F.phy)
    txt = fileread(F.phy);
    g = regexp(txt, 'gap ([+-]\d+\.\d+) dB \(standard error (\d+\.\d+) dB\) -> (\w+)', 'tokens');
    gaps = cellfun(@(c) str2double(c{1}), g); passed = cellfun(@(c) strcmp(c{3}, 'PASS'), g);
    seeds = contains(txt, 'seeds PASS');
    KPI(end+1) = kpi(3, 'BER vs theory', sprintf('%d/%d within 0.3 dB (gaps %s dB)', sum(passed), numel(passed), ...
        strjoin(compose('%+.2f', gaps), ', ')), '<= 0.3 dB', status(all(passed) && seeds && ~isempty(passed), false), ...
        {sprintf('seeded reproducibility: %s', ternary(seeds, 'PASS', 'FAIL'))});
else
    KPI(end+1) = missing(3, 'BER vs theory', F.phy);
end

%% KPI 4-8 - decision layer
if isfile(F.pol)
    P = load(F.pol);
    stale = file_time(F.pol) < t_dqn;
    col = @(p) find(strcmp(P.POL, p));
    iD = P.iDQN; iO = col('oracle');
    sing = P.RES(1, :);
    rec_ep = sing{iO}.restored_post >= 0.5;               % recoverable: the one-step oracle restores it
    val4 = 100 * mean(sing{iD}.restored_post(rec_ep));
    det = {sprintf('single threats, test pools: DQN restored %.1f%% of cycles after onset on %d recoverable episodes (oracle %.1f%%)', ...
        val4, sum(rec_ep), 100 * mean(sing{iO}.restored_post(rec_ep))), ...
        sprintf('all single-threat episodes: DQN %.1f%%, rule + escalation %.1f%%, table %.1f%%, oracle %.1f%%', ...
        100 * mean(sing{iD}.restored_post), 100 * mean(sing{col('rule_esc')}.restored_post), ...
        100 * mean(sing{col('table')}.restored_post), 100 * mean(sing{iO}.restored_post))};
    if isfile(F.surv)
        S = load(F.surv, 'grid_data_A', 'grid_data_B');
        det{end+1} = sprintf('survivability map (threat x severity x Eb/N0 x geometry): %s', surv_txt(S));
    end
    KPI(end+1) = kpi(4, 'Restoration (<= 2x clean)', sprintf('%.1f%% of cycles on recoverable attacks', val4), ...
        '>= 80% of cycles at <= 2x clean BER', status(val4 >= 80, stale), det);

    Rall = pool_sets(P.RES(P.iThreat, :));
    d = @(k) ci_txt(Rall{iD}.ret - Rall{k}.ret);
    rec = ~isnan(Rall{iD}.t_rec);
    det = {sprintf('threat sets pooled, paired return difference DQN minus: rule + escalation %s | table %s | best fixed %s', ...
        d(col('rule_esc')), d(col('table')), d(col('fixed'))), ...
        sprintf('recovered episodes %.1f%%, median T_rec %s cycles | restored %.1f%% | goodput %.3f | oracle return %.3f', ...
        100 * mean(rec), num_txt(median(Rall{iD}.t_rec(rec))), 100 * mean(Rall{iD}.restored_post), ...
        mean(Rall{iD}.gput_post), mean(Rall{iO}.ret))};
    for si = 2:numel(P.set_names)
        R = P.RES(si, :);
        det{end+1} = sprintf('%-9s DQN %.3f | rule+esc %.3f | table %.3f | fixed %.3f | oracle %.3f (mean return)', ...
            P.set_names{si}, mean(R{iD}.ret), mean(R{col('rule_esc')}.ret), mean(R{col('table')}.ret), ...
            mean(R{col('fixed')}.ret), mean(R{iO}.ret)); %#ok<SAGROW>
    end
    dr = Rall{iD}.ret - Rall{col('rule_esc')}.ret; [~, lo] = stats_ci('t', dr);
    KPI(end+1) = kpi(5, 'DQN vs baselines', sprintf('+%.3f return vs rule + escalation', mean(dr)), ...
        'better than rule (paired 95% CI > 0)', status(lo > 0, stale), det);

    far = P.KP.far(strcmp({P.KP.far.policy}, P.LBL{iD}));
    fr = P.KP.far(strcmp({P.KP.far.policy}, 'rule + escalation'));
    KPI(end+1) = kpi(6, 'False alarms (clean link)', sprintf('%d/%d episodes, upper bound %.2f%%', far.k, far.n, ...
        100 * far.upper), '<= 5% (one-sided 95%), >= 600 episodes', status(far.upper <= 0.05 && far.n >= 600, stale), ...
        {sprintf('Eb/N0 >= %g dB, 30 cycles per episode; per-cycle rate %.4f%% | rule + escalation %d/%d, upper %.2f%%', ...
        P.KP.ebno_thr, 100 * far.per_cycle, fr.k, fr.n, 100 * fr.upper)});

    det = {};
    if isfile(F.lat)
        Lt = load(F.lat, 'LAT'); Lt = Lt.LAT;
        det{end+1} = sprintf('decision latency per cycle (%s): median %.2f ms, p95 %.2f ms (DQN chain); rule chain %.2f / %.2f ms', ...
            Lt.device, Lt.total_dqn_median_ms, Lt.total_dqn_p95_ms, Lt.total_rule_median_ms, Lt.total_rule_p95_ms);
        det{end+1} = sprintf('components (median ms): %s', strjoin(cellfun(@(n, v) sprintf('%s %.2f', n, v), Lt.names, ...
            num2cell(Lt.median_ms), 'UniformOutput', false), ', '));
        latv = sprintf('median %.2f ms, p95 %.2f ms', Lt.total_dqn_median_ms, Lt.total_dqn_p95_ms);
    else
        latv = 'latency not measured'; det{end+1} = ['missing ' F.lat];
    end
    pv = P.KP.per_speed(:, strcmp(P.KP.show, P.POL{iD}));
    det{end+1} = sprintf('DQN restored cycles per speed band (%s km/h): %s %%', ...
        strjoin(arrayfun(@(b) sprintf('%.0f-%.0f', P.KP.speed_bins(b), P.KP.speed_bins(b+1)), ...
        1:numel(P.KP.speed_bins) - 1, 'UniformOutput', false), ', '), strjoin(compose('%.1f', pv'), ', '));
    if exist('m', 'var') && isfield(m, 'speed_breakdown')
        det{end+1} = sprintf('detector accuracy per speed band: %s %%', strjoin(compose('%.1f', ...
            [m.speed_breakdown.accuracy_pct]), ', '));
    end
    KPI(end+1) = kpi(7, 'Real time + speed', latv, 'reported; restored spread <= 10 points over 50-120 km/h', ...
        status(max(pv) - min(pv) <= 10, stale), det);

    pt = P.KP.per_threat(:, strcmp(P.KP.show, P.POL{iD}));
    n_ok = sum(pt(~contains(P.KP.per_threat_scn, '+')) >= 50);
    KPI(end+1) = kpi(8, 'End-to-end closed loop', sprintf('%d single threats restored >= 50%% of cycles', n_ok), ...
        '>= 1 recoverable threat', status(n_ok >= 1, stale), ...
        {sprintf('restored per threat (DQN): %s', strjoin(cellfun(@(n, v) sprintf('%s %.0f%%', n, v), ...
        P.KP.per_threat_scn, num2cell(pt'), 'UniformOutput', false), ', '))});
    if isfile(F.dqn)
        Dq = load(F.dqn, 'seed_summary'); ss = Dq.seed_summary;
        KPI(5).detail{end+1} = sprintf('selected gamma %.2f, seed %d, validation gate %s', ss.selected_gamma, ...
            ss.selected_seed, ternary(ss.gate_pass, 'PASS', 'FAIL'));
    end
else
    for k = 4:8, KPI(end+1) = missing(k, sprintf('KPI %d', k), F.pol); end %#ok<SAGROW>
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

function R = pool_sets(RR)
R = RR(1, :);
for si = 2:size(RR, 1)
    for pk = 1:size(RR, 2)
        f = fieldnames(R{pk});
        for i = 1:numel(f), R{pk}.(f{i}) = [R{pk}.(f{i}), RR{si, pk}.(f{i})]; end
    end
end
end

function s = ci_txt(x)
[m, lo, hi] = stats_ci('t', x);
s = sprintf('%+.3f [%+.3f, %+.3f]', m, lo, hi);
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
