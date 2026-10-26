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
%   data/gui_norm_stats.mat, and the clean-link reference of the decision layer as a small
%   data/policy_pools.mat holding clean_ref alone (clean_ber_ref.m reads nothing else): the
%   export stops when the pools hold none, its table has a missing or non-finite value, or
%   the bundle's reference is not finite, because the link monitor would fall back to its
%   floor and alarm on a clean link. The three-state
%   CNN (data/core_cnn_model.mat, not a reduced chain check) and its report
%   (results/core_cnn.txt) come along when present. A result of another detector or deployed
%   policy, or older than its inputs (result_status.m), is not exported, and a KPI summary
%   older than the evaluation or the latency it reads neither; an optional file not exported
%   is removed from the bundle as well: the console shows no stale number.
if nargin < 2 || isempty(root), root = project_root(); end
if nargin < 1 || isempty(target), target = fullfile(root, 'profiles'); end
S = load(fullfile(root, 'params.mat')); n = S.params.n_rx;
dst = fullfile(target, sprintf('rx%d', n));
for d = {'', 'data', 'results'}
    if ~isfolder(fullfile(dst, d{1})), mkdir(fullfile(dst, d{1})); end
end
nc = fullfile(root, 'data', 'gui_norm_stats.mat'); sp = fullfile(root, 'data', 'splits.mat');
if isfile(sp) && (~isfile(nc) || dir(nc).datenum < dir(sp).datenum)
    nm = split_norm(sp);
    feat_mean = nm.feat_mean; feat_std = nm.feat_std; %#ok<NASGU>
    save(nc, 'feat_mean', 'feat_std');
end
need = {'params.mat', 'data/trained_detector.mat', 'data/trained_dqn.mat', 'data/gui_norm_stats.mat', 'data/ood_thresholds.mat'};
opt = {'data/fusion.mat', 'data/drop_threshold.mat', 'data/survivability_boundary.mat', ...
    'results/eval_detector_metrics.mat', 'results/eval_detector_metrics_fresh2.mat', 'results/eval_detector_metrics_fresh3.mat', ...
    'results/policy_evaluation.mat', ...
    'results/latency.mat', 'results/kpi_summary.mat', 'results/kpi_summary.txt', ...
    'data/core_cnn_model.mat', 'results/core_cnn.txt'};
for f = need
    src = fullfile(root, f{1});
    if ~isfile(src), error('export_gui_bundle:missing', 'missing %s: run the pipeline first', f{1}); end
    copyfile(src, fullfile(dst, f{1}));
end
export_clean_ref(root, dst);
c0 = cd(root); back = onCleanup(@() cd(c0)); RS = result_status(); clear back
bad = {RS([RS.stale]).file};
kp = fullfile(root, 'results', 'kpi_summary.mat');
if isfile(kp) && any(cellfun(@(f) isfile(fullfile(root, f)) && dir(fullfile(root, f)).datenum > dir(kp).datenum, ...
        {'results/policy_evaluation.mat', 'results/latency.mat', 'results/edge_map.mat'}))
    bad{end+1} = 'results/kpi_summary.mat';
end
if ismember('results/kpi_summary.mat', bad), bad{end+1} = 'results/kpi_summary.txt'; end
cm = fullfile(root, 'data', 'core_cnn_model.mat');
if isfile(cm) && ismember('smoke', who('-file', cm)) && isequal(load(cm, 'smoke').smoke, true)
    bad{end+1} = 'data/core_cnn_model.mat';              % a reduced chain check is no model to show
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

function export_clean_ref(root, dst)
% The clean-link reference of the pools into the bundle, then read back through clean_ber_ref.m
% from the bundle's own folder: a bundle whose reference is not finite is not left behind.
pp = fullfile(root, 'data', 'policy_pools.mat');
if ~isfile(pp) || ~ismember('clean_ref', who('-file', pp))
    error('export_gui_bundle:clean_ref', ['%s holds no clean_ref (build_policy_pools.m, clean_ref_rebuild.m): ' ...
        'the console cannot judge a link without the clean reference'], pp);
end
L = load(pp, 'clean_ref'); clean_ref = L.clean_ref;
ok = all(isfield(clean_ref, {'ebno', 'ber_est'})) && numel(clean_ref.ebno) >= 2;
for f = {'ebno', 'ber', 'ber_est', 'plr_fec'}               % clean_ber_ref.m floors a NaN in the table, so it is checked here
    if ok && isfield(clean_ref, f{1}), ok = all(isfinite(clean_ref.(f{1})(:))); end
end
if ~ok
    error('export_gui_bundle:clean_ref', 'the clean_ref in %s lacks ebno or ber_est, or holds a value that is not finite: not exported', pp);
end
out = fullfile(dst, 'data', 'policy_pools.mat');
save(out, 'clean_ref');
c0 = cd(dst); back = onCleanup(@() cd(c0));
clean_ber_ref('reset');
b = clean_ber_ref(9, 'ber_est');
clean_ber_ref('reset');
clear back
if ~isfinite(b)
    delete(out);
    error('export_gui_bundle:clean_ref', 'the clean reference in %s is not finite at 9 dB: not exported', pp);
end
end
