function f = kpi1_file(stem)
%KPI1_FILE  The detector reading KPI 1 is read from, on the set of kpi1_set.m: with 'fresh2',
%   results/<stem>_fresh2.mat, the third test set (B3m), when it exists, else
%   results/<stem>.mat (measure_all_kpis.m's rule); with 'fresh3', results/<stem>_fresh3.mat,
%   the fourth test set (B3q), also when it is missing (it then shows as missing). So the
%   dashboard, the console and the weak points show the same test set as the KPI summary.
%   stem: 'eval_detector_metrics' or 'detector_predictions'.
ks = kpi1_set();
assert(any(strcmp(ks, {'fresh2', 'fresh3'})), 'kpi1_file: unknown KPI 1 set ''%s'' (kpi1_set.m)', ks);
f = ['results/' stem '_' ks '.mat'];
if ~isfile(f) && strcmp(ks, 'fresh2'), f = ['results/' stem '.mat']; end
end
