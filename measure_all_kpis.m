%% MEASURE_ALL_KPIS.m — aggregates all 5 proposal KPIs (section ה) into one report.
% Strategy per KPI: check for an existing, fresh result file on disk first;
% if missing, CALL the specific script that generates it (never reimplement
% that logic here).
%
% "Fresh" = the source file's timestamp is newer than MAX_STALE_DAYS --
% avoids silently reporting stale numbers from before a bug fix.
%
% KPI #2/#5 read closed_loop_diagnostic_results.mat directly (Monte Carlo means and
% 95% CIs, D35); KPI #4 reads far_measurement.mat and applies the FAR bound.
%
% Output: results/kpi_summary.txt

close all; clc;
fprintf('=== KPI AGGREGATION: proposal section ה, all 5 KPIs ===\n\n');

MAX_STALE_DAYS = 0.5;   % 12 hours -- re-run source script if existing result is older than this

report = {};
report{end+1} = '=== PROPOSAL KPI SUMMARY (section ה) ===';
report{end+1} = sprintf('Generated: %s', datestr(now));
report{end+1} = '';

%% ---------- KPI #1: Detection accuracy as f(SNR), macro-F1>=90%, confusion matrix ----------
fprintf('--- KPI #1: Detection accuracy ---\n');
metrics_path = 'results/eval_detector_metrics.mat';
need_rerun = ~exist(metrics_path, 'file');
if ~need_rerun
    d = dir(metrics_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if need_rerun
    fprintf('  No fresh results/eval_detector_metrics.mat found -- running eval_detector...\n');
    run_isolated('eval_detector');   % also regenerates confusion_matrix.png / accuracy_vs_snr.png
end
M = load(metrics_path, 'metrics'); m1 = M.metrics;
if ~isfield(m1, 'kpi1_threshold_db')                 % metrics saved before D34
    run_isolated('eval_detector');
    M = load(metrics_path, 'metrics'); m1 = M.metrics;
end

report{end+1} = '--- KPI #1: Detection Accuracy (target: macro-F1 >= 90% above SNR threshold) ---';
report{end+1} = sprintf('Source: results/eval_detector_metrics.mat (generated %s)', m1.generated);
report{end+1} = sprintf('Overall accuracy: %.2f%% | Macro-F1: %.2f%% -> %s', ...
    m1.overall_accuracy_pct, m1.macro_f1_pct, ...
    string(m1.macro_f1_pct >= 90) + " (target: >=90%)");
report{end+1} = sprintf('KPI #1 as worded: macro-F1 >= 90%% from Eb/N0 = %g dB up; macro-F1 above that threshold %.2f%%', ...
    m1.kpi1_threshold_db, m1.macro_f1_above_threshold_pct);
report{end+1} = 'Accuracy and macro-F1 vs Eb/N0 (degradation curve):';
for i = 1:numel(m1.snr_breakdown)
    report{end+1} = sprintf('  SNR=%2d dB: accuracy %.1f%% | macro-F1 %.1f%%', m1.snr_breakdown(i).snr_db, ...
        m1.snr_breakdown(i).accuracy_pct, m1.snr_breakdown(i).macro_f1_pct);
end
report{end+1} = sprintf('Action-equivalent accuracy (confusion between classes with the same countermeasure counted as correct): %.2f%%', ...
    m1.action_equiv_accuracy_pct);
if isfield(m1, 'ci95')
    report{end+1} = sprintf('95%% bootstrap CI (%d resamples of the test set): accuracy [%.2f, %.2f] | macro-F1 [%.2f, %.2f] | macro-F1 above threshold [%.2f, %.2f]', ...
        m1.ci95.n_boot, m1.ci95.accuracy, m1.ci95.macro_f1, m1.ci95.macro_f1_above);
end
if isfile('results/unseen_snr.mat')
    U = load('results/unseen_snr.mat', 'summary');
    report{end+1} = sprintf(['Generalization to Eb/N0 never seen in training (1,3,5,7,9 dB): accuracy %.1f%% vs %.1f%% on the ' ...
        'training grid in the same run; largest gap to the interpolated curve %.1f points'], ...
        U.summary.acc_unseen, U.summary.acc_seen, U.summary.max_gap);
end
report{end+1} = 'Per-class recall/F1 (weakest classes flagged):';
for i = 1:numel(m1.classes)
    flag = '';
    if m1.per_class_recall_pct(i) < 90, flag = '  <-- below 90%'; end
    report{end+1} = sprintf('  %-20s recall=%.1f%% F1=%.1f%%%s', m1.classes{i}, ...
        m1.per_class_recall_pct(i), m1.per_class_f1_pct(i), flag);
end
report{end+1} = 'Full confusion matrix: see results/confusion_matrix.png';
report{end+1} = '';

%% ---------- KPI #2: Recovery vs baseline (reads the .mat struct, not the .txt report) ----------
fprintf('--- KPI #2: Recovery vs baseline ---\n');
diag_mat_path = 'results/closed_loop_diagnostic_results.mat';
need_rerun = ~exist(diag_mat_path, 'file');
if ~need_rerun
    d = dir(diag_mat_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if ~need_rerun
    probe = load(diag_mat_path, 'results');
    need_rerun = ~isfield(probe.results, 'plr_ok');   % saved before the D35 Monte Carlo layout
end
if need_rerun
    fprintf('  No fresh %s (with the D27 clean-link metric) found -- running run_closed_loop_diagnostic...\n', diag_mat_path);
    run_isolated('run_closed_loop_diagnostic');
end

DL = load(diag_mat_path);
cl_results = DL.results;
cl_threats = unique({cl_results.threat}, 'stable');
has_mc = isfield(DL, 'kpi_ci');

report{end+1} = '--- KPI #2: Link Quality Recovery vs Healthy (No-Attack) Baseline ---';
report{end+1} = sprintf('Source: %s', diag_mat_path);
report{end+1} = 'Definition (proposal, D27): rec = 100*(BER_before - BER_after)/(BER_before - BER_clean), capped at 100;';
report{end+1} = 'link state = BER_after/BER_clean (<= 2 restored, <= 5 marginal). Clean = none run at the same Eb/N0.';
report{end+1} = 'Packet loss (D35): frame lost when BER > 0.1; restored when PLR_after <= PLR_clean + 0.05.';
if has_mc
    report{end+1} = sprintf('Monte Carlo: %d repeats; mean [95%% CI] over the per-repeat values.', DL.N_MC);
end
real_mask   = ~ismember({cl_results.threat}, {'benign_interference','none'});
active_mask = real_mask & ~[cl_results.missed];
recov_by_threat = nan(1, numel(cl_threats));
for i = 1:numel(cl_threats)
    mask = strcmp({cl_results.threat}, cl_threats{i});
    if ismember(cl_threats{i}, {'benign_interference','none'})
        report{end+1} = sprintf('  %-20s recovery=N/A (non-hostile -- no countermeasure expected)', cl_threats{i});
        continue;
    end
    m = mask & active_mask;
    recov_by_threat(i) = mean([cl_results(m).rec_vs_clean], 'omitnan');
    r = [cl_results(mask).ratio_clean];
    ln = sprintf('  %-20s recovery=%.1f%% | %.2fx clean (mean) | restored %d/%d | missed %d', ...
        cl_threats{i}, recov_by_threat(i), mean(r, 'omitnan'), sum(r <= 2), numel(r), sum(mask & [cl_results.missed]));
    if isfield(cl_results, 'plr_ok')
        ln = sprintf('%s | PLR %.2f -> %.2f, restored %d/%d | goodput kept %.0f%%', ln, ...
            mean([cl_results(mask).plr_before]), mean([cl_results(mask).plr_after]), ...
            sum([cl_results(mask).plr_ok]), sum(mask), 100*mean([cl_results(mask).gp_kept]));
    end
    report{end+1} = ln; %#ok<SAGROW>
end
r_all = [cl_results(real_mask).ratio_clean];
nR = numel(r_all);
if has_mc
    K = DL.kpi_ci;
    report{end+1} = sprintf('  KPI #2 BER recovery (real threats):  DQN %s | rule %s | DQN-rule %s', ...
        ci_str(K.rec_dqn), ci_str(K.rec_rule), ci_str(K.rec_diff));
    report{end+1} = sprintf('  BER restored (%% of runs):            DQN %s | rule %s', ci_str(K.restored_dqn), ci_str(K.restored_rule));
    report{end+1} = sprintf('  PLR restored (%% of runs):            DQN %s | rule %s', ci_str(K.plr_restored_dqn), ci_str(K.plr_restored_rule));
    report{end+1} = sprintf('  PLR recovery vs clean (%%):           DQN %s | rule %s', ci_str(K.plr_rec_dqn), ci_str(K.plr_rec_rule));
    report{end+1} = sprintf('  Goodput kept vs no-attack (%%):       DQN %s | rule %s | no action %s', ...
        ci_str(K.gp_kept_dqn), ci_str(K.gp_kept_rule), ci_str(K.gp_kept_none));
    if ~DL.seeds_effective
        report{end+1} = '  WARNING: repeats returned identical values (seeds had no effect); the intervals are not meaningful.';
    end
else
    report{end+1} = sprintf('  KPI #2 (real threats, per-run mean):   %.1f%%', mean([cl_results(active_mask).rec_vs_clean], 'omitnan'));
end
[pw, lw, hw] = stats_ci('wilson', sum(r_all <= 2), nR);
report{end+1} = sprintf('  Link restored (<= 2x clean): %d/%d = %.1f%% [%.1f, %.1f] | marginal: %d | not restored: %d | missed detections: %d', ...
    sum(r_all <= 2), nR, 100*pw, 100*lw, 100*hw, sum(r_all > 2 & r_all <= 5), sum(r_all > 5), sum([cl_results(real_mask).missed]));
report{end+1} = sprintf('  KPI #2 (real threats, per-threat mean): %.1f%%', mean(recov_by_threat, 'omitnan'));
for mapName = {'A', 'B'}
    mf = sprintf('results/survivability_boundary_map%s.txt', mapName{1});
    if isfile(mf)
        tk = regexp(fileread(mf), 'Recoverable\s*:\s*(\d+) \(([\d.]+)%\).*?Marginal\s*:\s*(\d+) \(([\d.]+)%\).*?Non-recoverable\s*:\s*(\d+) \(([\d.]+)%\)', 'tokens', 'once');
        if ~isempty(tk)
            report{end+1} = sprintf('Survivability map %s (deliverable #7): recoverable %s%% | marginal %s%% | non-recoverable %s%%  (%s)', ...
                mapName{1}, tk{2}, tk{4}, tk{6}, mf); %#ok<SAGROW>
        end
    end
end
if isfile('results/speed_robustness.txt')
    st = fileread('results/speed_robustness.txt');
    l1 = regexp(st, 'OVERALL detection accuracy:[^\n]*', 'match', 'once');
    l2 = regexp(st, 'OVERALL KPI #2 recovery[^\n]*', 'match', 'once');
    l3 = regexp(st, 'OVERALL false alarms:[^\n]*', 'match', 'once');
    report{end+1} = 'UAV speed 50-120 km/h (results/speed_robustness.txt):';
    report{end+1} = ['  ' l1]; report{end+1} = ['  ' l2]; report{end+1} = ['  ' l3];
end
report{end+1} = '';

%% ---------- KPI #3: DQN vs Rule-Based (decision latency) ----------
fprintf('--- KPI #3: DQN vs Rule-Based ---\n');
report{end+1} = '--- KPI #3: DQN vs Rule-Based (decision latency, recovery time, link quality) ---';
kpi3_path = 'results/kpi3_measurement.txt';
need_rerun = ~exist(kpi3_path, 'file');
if ~need_rerun
    d = dir(kpi3_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if need_rerun
    fprintf('  No fresh results/kpi3_measurement.txt found -- running measure_kpi3_recovery_time...\n');
    run_isolated('measure_kpi3_recovery_time');
end
kpi3_txt = fileread(kpi3_path);
report{end+1} = sprintf('Source: %s', kpi3_path);
report{end+1} = strtrim(kpi3_txt);
if isfile('results/closed_loop_episodes.mat')
    L = load('results/closed_loop_episodes.mat', 'E', 'cfg_keys');
    if isfield(L.E, 'status')
        report{end+1} = 'Episodic loop (D31), episodes that need action, with 95% CIs:';
        for c = 1:numel(L.cfg_keys)
            m  = [L.E.needs] & strcmp({L.E.cfg}, L.cfg_keys{c});
            mt = m & ismember({L.E.status}, {'recovered', 'not recovered'});
            k  = sum(strcmp({L.E(m).status}, 'recovered'));
            [pe, le, he] = stats_ci('wilson', k, sum(mt));
            [tr, tl, th] = stats_ci('t', [L.E(mt).T_rec], [0 Inf]);
            report{end+1} = sprintf('  %-26s recovered %d/%d = %.0f%% [%.0f, %.0f] | T_recover mean %.1f [%.1f, %.1f] cycles | goodput %.2f', ...
                L.cfg_keys{c}, k, sum(mt), 100*pe, 100*le, 100*he, tr, tl, th, mean([L.E(m).goodput])); %#ok<SAGROW>
        end
    end
end
if isfile('data/trained_dqn.mat')
    V = whos('-file', 'data/trained_dqn.mat');
    if any(strcmp({V.name}, 'seed_summary'))
        Q = load('data/trained_dqn.mat', 'seed_summary');
        ss = Q.seed_summary;
        report{end+1} = sprintf('DQN training seeds (D35): %d trained, %d passed the gate; mean regret across seeds %s; selected seed %d (mean regret %.1f); cells with the same action in every seed %d/%d', ...
            numel(ss.seeds), sum(ss.gate_pass), stats_ci('fmt', ss.mean_regret, [0 Inf]), ss.selected_seed, ...
            ss.mean_regret(ss.selected), ss.cells_unanimous, ss.cells_total);
    end
end
report{end+1} = '';

%% ---------- KPI #5: Single End-to-End Baseline (reads the .mat struct) ----------
fprintf('--- KPI #5: End-to-end baseline ---\n');
report{end+1} = '--- KPI #5: Single End-to-End Baseline (detect->decide->recover, >=1 recoverable threat) ---';
if ~isempty(recov_by_threat)
    [best_recov, best_i] = max(recov_by_threat);
    report{end+1} = sprintf('MET: %s recovers %.1f%% of the attack-induced BER end-to-end (vs clean link), averaged over the SNR sweep (CNN detect -> DQN decide -> apply -> re-measure).', ...
        cl_threats{best_i}, best_recov);
else
    report{end+1} = 'NOT MET -- no recovery data found in closed_loop_diagnostic_results.mat.';
end
report{end+1} = '';

%% ---------- KPI #4: False Alarm Rate ----------
fprintf('--- KPI #4: False Alarm Rate ---\n');
far_path = 'results/far_measurement.txt';
need_rerun = ~exist(far_path, 'file');
if ~need_rerun
    d = dir(far_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if need_rerun
    fprintf('  No fresh results/far_measurement.txt found -- running diagnose_far_measurement...\n');
    run_isolated('diagnose_far_measurement');
end
F = load(strrep(far_path, '.txt', '.mat'), 'results');
fr = F.results;
FAR_BOUND = 5;                                   % % of healthy-link decisions (D35)
thr_db = m1.kpi1_threshold_db;
if isnan(thr_db), thr_db = min([fr.snr]); end
report{end+1} = '--- KPI #4: False Alarm Rate (FAR), non-hostile classes ---';
report{end+1} = sprintf('Source: %s', far_path);
report{end+1} = sprintf(['Definition (D29): an action on a non-hostile link whose BER <= 2x clean. Denominator: healthy-link trials. ' ...
    'Bound (D35): FAR <= %g%% with the 95%% upper limit below it, for Eb/N0 >= the KPI #1 threshold (%g dB).'], FAR_BOUND, thr_db);
snrs = unique([fr.snr]);
healthy = false(1, numel(fr));                   % link BER <= 2x the clean ('none') mean at that Eb/N0
for si = 1:numel(snrs)
    ms = [fr.snr] == snrs(si);
    cb = mean([fr(ms & strcmp({fr.class}, 'none')).ber_mean]);
    healthy(ms) = [fr(ms).ber_mean] / cb <= 2;
end
for si = 1:numel(snrs)
    m = healthy & [fr.snr] == snrs(si);
    k = sum([fr(m).false_alarm]);
    [pf, lf, hf] = stats_ci('wilson', k, sum(m));
    report{end+1} = sprintf('  Eb/N0 %4g dB: FAR %d/%d = %.1f%% [%.1f, %.1f]', snrs(si), k, sum(m), 100*pf, 100*lf, 100*hf); %#ok<SAGROW>
end
m = healthy & [fr.snr] >= thr_db;
k = sum([fr(m).false_alarm]);
[pf, lf, hf] = stats_ci('wilson', k, sum(m));
if 100*hf <= FAR_BOUND, verdict = 'MET'; else, verdict = 'NOT MET'; end
report{end+1} = sprintf('  Above threshold (pooled): FAR %d/%d = %.1f%%, 95%% upper limit %.1f%% (Wilson; Rule of Three %.1f%%) -> %s', ...
    k, sum(m), 100*pf, 100*hf, 300/max(sum(m),1), verdict);
report{end+1} = 'Full per-class breakdown: see results/far_measurement.txt';
report{end+1} = '';

%% ---------- Unknown-threat detection and combined threats (deliverable 4, risk 13; D32) ----------
report{end+1} = '';
report{end+1} = '--- Unknown-threat detection (deliverable 4) and combined threats (risk 13) ---';
if isfile('results/ood_detection.mat')
    O = load('results/ood_detection.mat', 'R', 'RETAIN');
    report{end+1} = sprintf('Leave-one-threat-out: mean AUROC MSP %.3f, energy %.3f; unknown frames flagged %.0f%% (MSP) at %.0f%% known kept; false flags %.1f%%', ...
        mean([O.R.auroc_msp]), mean([O.R.auroc_energy]), 100*mean([O.R.flag_msp]), 100*O.RETAIN, 100*mean([O.R.fp_msp]));
    report{end+1} = 'Per held-out threat: results/ood_detection.txt';
else
    report{end+1} = 'Leave-one-threat-out: not run (eval_ood_detection.m)';
end
if isfile('results/combined_threats.mat')
    C = load('results/combined_threats.mat');
    mcl = ~strcmp({C.Dec.link}, 'none');
    for md = 1:numel(C.modes)
        rt = arrayfun(@(d) d.ratio(md), C.Dec(mcl));
        ci = '';
        if isfield(C, 'restored_mc'), ci = sprintf(' | per repeat %s%%', stats_ci('fmt', C.restored_mc(md, :), [0 100])); end
        report{end+1} = sprintf('Combined threats, %-22s link restored in %d/%d decisions (median %.2fx clean)%s', ...
            [C.modes{md} ':'], sum(rt <= 2), numel(rt), median(rt), ci);
    end
    report{end+1} = 'Details: results/combined_threats.txt';
else
    report{end+1} = 'Combined threats: not run (eval_combined_threats.m)';
end

if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/kpi_summary.txt', 'w');
for i = 1:numel(report), fprintf(fid, '%s\n', report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end
fprintf('\nSaved results/kpi_summary.txt\n');
fprintf('\n=== KPI Aggregation Complete ===\n');

%% ===== Local functions =====
function s = ci_str(v)
if isnan(v(2)), s = sprintf('%.1f', v(1)); else, s = sprintf('%.1f [%.1f, %.1f]', v(1), v(2), v(3)); end
end

function run_isolated(script_name)
% Runs a source script in this function's own workspace, so its variables
% (e.g. its own 'report') cannot overwrite the KPI report being assembled here.
run(script_name);
end
