function f = kpi1_file(stem)
%KPI1_FILE  The detector reading KPI 1 is read from: results/<stem>_fresh2.mat, the third test
%   set (B3m), when it exists, else results/<stem>.mat (measure_all_kpis.m's rule), so the
%   dashboard, the console and the weak points show the same test set as the KPI summary.
%   stem: 'eval_detector_metrics' or 'detector_predictions'.
f = ['results/' stem '_fresh2.mat'];
if ~isfile(f), f = ['results/' stem '.mat']; end
end
