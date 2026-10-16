function export_gui_bundle(target, root)
%EXPORT_GUI_BUNDLE  Copy what the operator console needs from this checkout's trained
%   system into target/rx<n_rx> (default: profiles/ under the project root), so one
%   console switches between the antenna profiles (demo_gui.m, 'UAV antennas' menu).
%   export_gui_bundle                  into profiles/ of this checkout
%   export_gui_bundle(target)          into another folder (the launcher collects the
%                                      three profiles in the main checkout)
%   export_gui_bundle(target, root)    from the checkout at root
%   The bundle mirrors the repository layout (params.mat, profile.json, data/, results/),
%   without the multi-GB dataset files: the normalisation statistics come as
%   data/gui_norm_stats.mat. A result of another detector or deployed policy, or older
%   than its inputs (result_status.m), is not exported, and a KPI summary older than the
%   evaluation or the latency it reads neither; an optional file not exported is removed
%   from the bundle as well: the console shows no stale number.
if nargin < 2 || isempty(root), root = project_root(); end
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
c0 = cd(root); back = onCleanup(@() cd(c0)); RS = result_status(); clear back
bad = {RS([RS.stale]).file};
kp = fullfile(root, 'results', 'kpi_summary.mat');
if isfile(kp) && any(cellfun(@(f) isfile(fullfile(root, f)) && dir(fullfile(root, f)).datenum > dir(kp).datenum, ...
        {'results/policy_evaluation.mat', 'results/latency.mat', 'results/edge_map.mat'}))
    bad{end+1} = 'results/kpi_summary.mat';
end
miss = {}; stale = {};
for f = opt
    src = fullfile(root, f{1}); out = fullfile(dst, f{1});
    if ~ismember(f{1}, bad) && isfile(src), copyfile(src, out); continue; end
    if isfile(out), delete(out); end                     % no older copy stays in the bundle
    if ismember(f{1}, bad), stale{end+1} = f{1}; else, miss{end+1} = f{1}; end %#ok<AGROW>
end
fid = fopen(fullfile(dst, 'profile.json'), 'w');
fprintf(fid, '{"profile":"%d UAV antennas","n_rx":%d}\n', n, n); fclose(fid);
fprintf('GUI bundle: %d UAV antennas -> %s\n', n, dst);
if ~isempty(miss), fprintf('  not exported (not produced yet; none in the bundle): %s\n', strjoin(miss, ', ')); end
if ~isempty(stale)
    warning('export_gui_bundle:stale', 'not exported (stale, result_status.m; none in the bundle): %s', strjoin(stale, ', '));
end
end
