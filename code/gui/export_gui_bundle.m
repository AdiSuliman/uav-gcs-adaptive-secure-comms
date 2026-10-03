function export_gui_bundle(target)
%EXPORT_GUI_BUNDLE  Copy what the operator console needs from this checkout's trained
%   system into target/rx<n_rx> (default: profiles/ under the project root), so one
%   console switches between the antenna profiles (demo_gui.m, 'UAV antennas' menu).
%   export_gui_bundle            into profiles/ of this checkout
%   export_gui_bundle(target)    into another folder (the launcher collects the three
%                                profiles in the main checkout)
%   The bundle mirrors the repository layout (params.mat, profile.json, data/, results/),
%   without the multi-GB dataset files: the normalisation statistics come as
%   data/gui_norm_stats.mat.
root = project_root();
if nargin < 1 || isempty(target), target = fullfile(root, 'profiles'); end
S = load(fullfile(root, 'params.mat')); n = S.params.n_rx;
dst = fullfile(target, sprintf('rx%d', n));
for d = {'', 'data', 'results'}
    if ~isfolder(fullfile(dst, d{1})), mkdir(fullfile(dst, d{1})); end
end
nc = fullfile(root, 'data', 'gui_norm_stats.mat'); sp = fullfile(root, 'data', 'splits.mat');
if isfile(sp) && (~isfile(nc) || dir(nc).datenum < dir(sp).datenum)
    L = load(sp, 'splits');
    feat_mean = L.splits.norm.feat_mean; feat_std = L.splits.norm.feat_std; %#ok<NASGU>
    save(nc, 'feat_mean', 'feat_std');
end
need = {'params.mat', 'data/trained_detector.mat', 'data/trained_dqn.mat', 'data/gui_norm_stats.mat', 'data/ood_thresholds.mat'};
opt = {'data/fusion.mat', 'data/drop_threshold.mat', 'data/survivability_boundary.mat', ...
    'results/eval_detector_metrics.mat', 'results/policy_evaluation.mat', 'results/latency.mat', 'results/kpi_summary.mat'};
for f = need
    src = fullfile(root, f{1});
    if ~isfile(src), error('export_gui_bundle:missing', 'missing %s: run the pipeline first', f{1}); end
    copyfile(src, fullfile(dst, f{1}));
end
miss = {};
for f = opt
    src = fullfile(root, f{1});
    if isfile(src), copyfile(src, fullfile(dst, f{1})); else, miss{end+1} = f{1}; end %#ok<AGROW>
end
fid = fopen(fullfile(dst, 'profile.json'), 'w');
fprintf(fid, '{"profile":"%d UAV antennas","n_rx":%d}\n', n, n); fclose(fid);
fprintf('GUI bundle: %d UAV antennas -> %s\n', n, dst);
if ~isempty(miss), fprintf('  not exported (not produced yet): %s\n', strjoin(miss, ', ')); end
end
