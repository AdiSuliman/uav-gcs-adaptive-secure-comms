function kpi1_threshold_check(thr, where)
%KPI1_THRESHOLD_CHECK  The KPI 1 threshold a stage read from results/eval_detector_metrics.mat equals
%   the one in the file KPI 1 itself is read from (kpi1_file.m), when that file exists; else an error.
%   thr: the threshold [dB] the stage uses; where: the stage's name for the message.
f = kpi1_file('eval_detector_metrics');
if ~isfile(f), return; end
M = load(f, 'metrics');
if ~isfield(M, 'metrics') || ~isstruct(M.metrics) || ~isfield(M.metrics, 'kpi1_threshold_db') || ~isfinite(M.metrics.kpi1_threshold_db)
    return;
end
if ~isequal(thr, M.metrics.kpi1_threshold_db)
    error('kpi1:threshold', ['%s: the KPI 1 threshold used is %g dB but %s holds %g dB; ' ...
        'results/eval_detector_metrics.mat is from another detector state'], where, thr, f, M.metrics.kpi1_threshold_db);
end
end
