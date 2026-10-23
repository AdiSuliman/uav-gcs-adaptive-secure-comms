function run_stage(varargin)
%RUN_STAGE  Run pipeline stages headless with a log file.
%   run_stage('A0', 'A5', 'A6', 'B1', 'B2', 'B3')  from the repository root (startup.m puts code/ on the path):
%   matlab -batch "run_stage('A5','A6')". Each stage is the script or function of
%   main.m; the log goes to logs/stage_<first>_<time>.txt.
%   Stages: A0 init_params | A4v validate_phy | A5 run_dataset_sweep |
%   A6 extract_spectrograms | B1 prepare_data | B2 train_detector | B2F select_fusion |
%   B3n build_fresh_test (run_dataset_sweep, extract_spectrograms and prepare_data on a
%   second test set) | B3 eval_detector (the test split, then the second test set) |
%   B3m build_fresh_test2 (the same recipe on a third test set, new seeds, then
%   eval_detector on it: the reading after the monitor's last validation choice) |
%   B3q build_fresh_test3 (the same recipe on a fourth test set, new seeds; data only, never
%   read here) | B3r read_fresh_test3 (eval_detector on the fourth test set, once, after
%   kpi1_set.m names it at the go/no-go; docs/d91_set4.md) |
%   B3a compare_architectures | B3c train_core_cnn (the proposal's three-state CNN on spectrograms
%   only, read once on the fourth test set after B3r or under docs/core_cnn_no_b3r.txt; by hand, never in the
%   takeover's chain; docs/core_cnn_protocol.md) |
%   B4 eval_unseen_snr | OOD eval_ood_detection | B4s eval_unseen_severity | C1p build_policy_pools |
%   C1c build_clean_test_pools and build_check_pools | C1d choose_drop_threshold | C2 train_dqn |
%   C2e evaluate_policies | C2g experiment_combo_generalization | C2u experiment_unknown_threat |
%   GAL threat_gallery |
%   SURV map_survivability_boundary | SURV3 experiment_survivability_options | OHP overhead_pass | GCSA gcs_antenna_analysis |
%   EDGE edge_map | LAT measure_latency |
%   KPI measure_all_kpis | DASH build_kpi_dashboard | WEAK analyze_weak_points |
%   RPT export_report_numbers
%   run_stage('smoke', ...) runs the listed stages on a reduced problem (few
%   cells, geometries and episodes) to check the chain in minutes; its outputs
%   overwrite the normal ones and are not results.
%   A stage named in the optional skip_stages of the checkout's profile.json
%   (profile_skip_stages.m) is not run: it prints its start line and its done marker with
%   the note 'skipped by profile.json', so the chain goes on past it.
smoke = strcmp(varargin{1}, 'smoke');
if smoke, varargin = varargin(2:end); end
root = setup_paths();
cd(root);
if ~isfolder('logs'), mkdir('logs'); end
logf = fullfile('logs', sprintf('stage_%s_%s.txt', varargin{1}, datestr(now, 'yyyymmdd_HHMMSS')));
diary(logf); diary on;
cleanup = onCleanup(@() diary('off'));
warning('off', 'Simulink:cgxe:LeakedJITEngine');
disk_guard('init');
map = struct('A0', 'init_params', 'A4v', 'validate_phy', 'A5', 'run_dataset_sweep', 'A6', 'extract_spectrograms', ...
    'B1', 'prepare_data', 'B2', 'train_detector', 'B2F', 'select_fusion', 'B3n', 'build_fresh_test', 'B3', 'eval_detector', ...
    'B3m', 'build_fresh_test2', 'B3q', 'build_fresh_test3', 'B3r', 'read_fresh_test3', 'B3a', 'compare_architectures', ...
    'B3c', 'train_core_cnn', 'B4', 'eval_unseen_snr', ...
    'OOD', 'eval_ood_detection', 'B4s', 'eval_unseen_severity', 'C1p', 'build_policy_pools', 'C1c', 'build_clean_test_pools', ...
    'C1d', 'choose_drop_threshold', 'C2', 'train_dqn', 'C2e', 'evaluate_policies', ...
    'C2g', 'experiment_combo_generalization', 'C2u', 'experiment_unknown_threat', 'GAL', 'threat_gallery', ...
    'SURV', 'map_survivability_boundary', 'SURV3', 'experiment_survivability_options', 'OHP', 'overhead_pass', 'GCSA', 'gcs_antenna_analysis', ...
    'EDGE', 'edge_map', 'LAT', 'measure_latency', ...
    'KPI', 'measure_all_kpis', ...
    'DASH', 'build_kpi_dashboard', 'WEAK', 'analyze_weak_points', 'RPT', 'export_report_numbers');
skip = profile_skip_stages('profile.json', fieldnames(map));
for i = 1:numel(varargin)
    st = varargin{i};
    fprintf('\n##### STAGE %s (%s) %s #####\n', st, map.(st), datestr(now));
    if ismember(st, skip)
        fprintf('##### STAGE %s done in 0.0 min (skipped by profile.json) #####\n', st);
        continue
    end
    t0 = tic;
    run_one(map.(st), smoke);
    fprintf('##### STAGE %s done in %.1f min #####\n', st, toc(t0) / 60);
end
end

function run_one(name, SMOKE)
% Scripts run in this function's workspace; CLEAN_SET selects the clean-pool set of
% C1c, which then builds the off-grid check pools; FRESH_TEST makes A5, A6 and B1 build the
% second test set, with FRESH_SET = 2 the third, with 3 the fourth; DET_TEST makes B3 read the
% test split beside it, the third test set after B3m builds it, and the fourth in B3r; SMOKE
% switches the reduced problem on. B2F deploys the fusion revision (FUSION_REV) as measured on
% the enlarged fit set (FUSION_FIT, fusion_pick.m); the smoke has no third test set, so its B2F
% runs the revision on validation. A profile's first B2F, before B3n and B3m (neither second nor
% third test set, enlarged_ready.m), fits the fusion on validation as before the revision: that
% is the fusion a no-go keeps, and the profile's B2F after B3m decides (docs/d91_deploy.md). With
% only some of the fit set's files present B2F stops (select_fusion:fit_sets).
if strcmp(name, 'build_fresh_test')
    FRESH_TEST = true; %#ok<NASGU>
    for scr = {'run_dataset_sweep', 'extract_spectrograms', 'prepare_data'}
        run(scr{1});
    end
elseif strcmp(name, 'build_fresh_test2')
    FRESH_TEST = true; FRESH_SET = 2; %#ok<NASGU>
    for scr = {'run_dataset_sweep', 'extract_spectrograms', 'prepare_data'}
        run(scr{1});
    end
    clear FRESH_TEST FRESH_SET
    DET_TEST = 'fresh2'; %#ok<NASGU>
    run('eval_detector');
elseif strcmp(name, 'build_fresh_test3')
    FRESH_TEST = true; FRESH_SET = 3; %#ok<NASGU>
    for scr = {'run_dataset_sweep', 'extract_spectrograms', 'prepare_data'}
        run(scr{1});
    end
elseif strcmp(name, 'read_fresh_test3')
    DET_TEST = 'fresh3'; %#ok<NASGU>
    run('eval_detector');
elseif strcmp(name, 'eval_detector') && isfile('data/splits_fresh.mat')
    for DET_TEST = {'split', 'fresh'}
        DET_TEST = DET_TEST{1}; %#ok<FXSET,NASGU>
        run(name);
    end
elseif strcmp(name, 'build_clean_test_pools')
    for CLEAN_SET = {'val', 'test'}
        CLEAN_SET = CLEAN_SET{1}; %#ok<FXSET,NASGU>
        run(name);
    end
    run('build_check_pools');
elseif strcmp(name, 'select_fusion')
    FUSION_REV = true; %#ok<NASGU>
    if ~SMOKE, FUSION_FIT = 'enlarged'; end %#ok<NASGU>
    [~, ~, first] = enlarged_ready();
    if ~SMOKE && first                                   % neither the second nor the third test set yet
        clear FUSION_REV FUSION_FIT
        fprintf('B2F: no enlarged fit set yet (B3n, B3m): the fusion is fitted on validation as before the revision\n');
    end
    clear first
    run(name);
elseif strcmp(name, 'validate_phy')
    if ~validate_phy(), error('run_stage:phy', 'PHY validation failed'); end
else
    run(name);
end
end
