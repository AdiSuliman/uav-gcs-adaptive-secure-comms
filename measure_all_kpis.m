%% MEASURE_ALL_KPIS.m — aggregates all 5 proposal KPIs (section ה) into one report.
% Strategy per KPI: check for an existing, fresh result file on disk first;
% if missing, CALL the specific script that generates it (never reimplement
% that logic here).
%
% "Fresh" = the source file's timestamp is newer than MAX_STALE_DAYS --
% avoids silently reporting stale numbers from before a bug fix.
%
% FIX (2026-09-19): (a) MAX_STALE_DAYS was 3 -- inconsistent with
% measure_kpi3_recovery_time.m's 0.5 (12h), and stale enough to let
% pre-fix results count as "fresh". Now 0.5 everywhere. (b) KPI#2 and
% KPI#5 previously regex-parsed closed_loop_diagnostic_report.txt with
% patterns tuned to an older report layout ("--- Threat: X ---", "Mean
% recovery: X%") that no longer match the current sliding-window-sweep
% format ("--- X @ SNR=Y dB ---", one block per threat-SNR pair). This
% silently produced empty/"NOT MET" results. Both KPIs now read the
% results struct directly from closed_loop_diagnostic_results.mat,
% which is immune to any future report-text reformatting.
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
    eval_detector;   % script; also regenerates confusion_matrix.png / accuracy_vs_snr.png
end
M = load(metrics_path, 'metrics'); m1 = M.metrics;

report{end+1} = '--- KPI #1: Detection Accuracy (target: macro-F1 >= 90% above SNR threshold) ---';
report{end+1} = sprintf('Source: results/eval_detector_metrics.mat (generated %s)', m1.generated);
report{end+1} = sprintf('Overall accuracy: %.2f%% | Macro-F1: %.2f%% -> %s', ...
    m1.overall_accuracy_pct, m1.macro_f1_pct, ...
    string(m1.macro_f1_pct >= 90) + " (target: >=90%)");
report{end+1} = 'Accuracy vs SNR:';
for i = 1:numel(m1.snr_breakdown)
    report{end+1} = sprintf('  SNR=%2d dB: %.1f%%', m1.snr_breakdown(i).snr_db, m1.snr_breakdown(i).accuracy_pct);
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
if need_rerun
    fprintf('  No fresh %s found -- running run_closed_loop_diagnostic...\n', diag_mat_path);
    run_closed_loop_diagnostic;
end

DL = load(diag_mat_path, 'results');
cl_results = DL.results;
cl_threats = unique({cl_results.threat}, 'stable');

report{end+1} = '--- KPI #2: Link Quality Recovery vs Healthy Baseline ---';
report{end+1} = sprintf('Source: %s', diag_mat_path);
recov_by_threat = zeros(1, numel(cl_threats));
for i = 1:numel(cl_threats)
    mask = strcmp({cl_results.threat}, cl_threats{i});
    recov_by_threat(i) = mean([cl_results(mask).recovery_pct]);
    report{end+1} = sprintf('  %-20s recovery=%.1f%% (mean over SNR sweep)', cl_threats{i}, recov_by_threat(i));
end
real_mask_names = ~ismember(cl_threats, {'benign_interference','none'});
report{end+1} = sprintf('  Mean recovery (all threats, all SNR): %.1f%%', mean([cl_results.recovery_pct]));
report{end+1} = sprintf('  Mean recovery (real threats only):    %.1f%%', mean(recov_by_threat(real_mask_names)));
report{end+1} = 'NOTE: this is per-threat SNR-swept recovery, not the full survivability-boundary';
report{end+1} = 'map (proposal deliverable #7) -- that is results/survivability_boundary_mapA.txt';
report{end+1} = 'and mapB.txt (map_survivability_boundary.m), a separate, larger analysis.';
report{end+1} = '';

%% ---------- KPI #3: DQN vs Rule-Based (decision latency) ----------
fprintf('--- KPI #3: DQN vs Rule-Based ---\n');
report{end+1} = '--- KPI #3: DQN vs Rule-Based (decision latency) ---';
kpi3_path = 'results/kpi3_measurement.txt';
need_rerun = ~exist(kpi3_path, 'file');
if ~need_rerun
    d = dir(kpi3_path);
    need_rerun = (now - datenum(d.date)) > MAX_STALE_DAYS;
end
if need_rerun
    fprintf('  No fresh results/kpi3_measurement.txt found -- running measure_kpi3_recovery_time...\n');
    measure_kpi3_recovery_time;
end
kpi3_txt = fileread(kpi3_path);
report{end+1} = sprintf('Source: %s', kpi3_path);
report{end+1} = strtrim(kpi3_txt); % Insert the text generated by the KPI3 script
report{end+1} = '';

%% ---------- KPI #5: Single End-to-End Baseline (reads the .mat struct) ----------
fprintf('--- KPI #5: End-to-end baseline ---\n');
report{end+1} = '--- KPI #5: Single End-to-End Baseline (detect->decide->recover, >=1 recoverable threat) ---';
if ~isempty(recov_by_threat)
    [best_recov, best_i] = max(recov_by_threat);
    report{end+1} = sprintf('MET: %s recovers %.1f%% end-to-end, averaged over the SNR sweep (CNN detect -> DQN decide -> apply -> re-measure).', ...
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
    diagnose_far_measurement;
end
far_txt = fileread(far_path);
overall_far_match = regexp(far_txt, 'Combined FAR.*?\(([\d.]+)%\)', 'tokens', 'once');

report{end+1} = '--- KPI #4: False Alarm Rate (FAR), non-hostile classes ---';
report{end+1} = sprintf('Source: %s', far_path);
if ~isempty(overall_far_match)
    report{end+1} = sprintf('Combined FAR (none + benign_interference): %s%%', overall_far_match{1});
else
    report{end+1} = 'Could not parse combined FAR -- see full file for detail.';
end
report{end+1} = 'Full per-class breakdown: see results/far_measurement.txt';
report{end+1} = '';

%% ---------- Write summary ----------
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen('results/kpi_summary.txt', 'w');
for i = 1:numel(report), fprintf(fid, '%s\n', report{i}); end
fclose(fid);
for i = 1:numel(report), fprintf('%s\n', report{i}); end
fprintf('\nSaved results/kpi_summary.txt\n');
fprintf('\n=== KPI Aggregation Complete ===\n');