function run_stage(varargin)
%RUN_STAGE  Run pipeline stages headless with a log file (D59).
%   run_stage('A0', 'A5', 'A6', 'B1', 'B2', 'B3')  from the repository root (startup.m puts code/ on the path):
%   matlab -batch "run_stage('A5','A6')". Each stage is the script or function of
%   main.m; the log goes to logs/stage_<first>_<time>.txt.
%   Stages: A0 init_params | A4v validate_phy | A5 run_dataset_sweep |
%   A6 extract_spectrograms | B1 prepare_data | B2 train_detector | B3 eval_detector |
%   B3a compare_architectures |
%   B4 eval_unseen_snr | OOD eval_ood_detection | C1p build_policy_pools |
%   C1c build_clean_test_pools | C1d choose_drop_threshold | C2 train_dqn |
%   C2e evaluate_policies | C2g experiment_combo_generalization | SURV map_survivability_boundary | SURV3 experiment_survivability_options |
%   LAT measure_latency |
%   KPI measure_all_kpis | DASH build_kpi_dashboard
%   run_stage('smoke', ...) runs the listed stages on a reduced problem (few
%   cells, geometries and episodes) to check the chain in minutes; its outputs
%   overwrite the normal ones and are not results.
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
    'B1', 'prepare_data', 'B2', 'train_detector', 'B3', 'eval_detector', 'B3a', 'compare_architectures', ...
    'B4', 'eval_unseen_snr', ...
    'OOD', 'eval_ood_detection', 'C1p', 'build_policy_pools', 'C1c', 'build_clean_test_pools', ...
    'C1d', 'choose_drop_threshold', 'C2', 'train_dqn', 'C2e', 'evaluate_policies', ...
    'C2g', 'experiment_combo_generalization', ...
    'SURV', 'map_survivability_boundary', 'SURV3', 'experiment_survivability_options', 'LAT', 'measure_latency', ...
    'KPI', 'measure_all_kpis', ...
    'DASH', 'build_kpi_dashboard');
for i = 1:numel(varargin)
    st = varargin{i};
    fprintf('\n##### STAGE %s (%s) %s #####\n', st, map.(st), datestr(now));
    t0 = tic;
    run_one(map.(st), smoke);
    fprintf('##### STAGE %s done in %.1f min #####\n', st, toc(t0) / 60);
end
end

function run_one(name, SMOKE) %#ok<INUSD>
% Scripts run in this function's workspace; CLEAN_SET selects the clean-pool set of
% C1c; SMOKE switches the reduced problem on.
if strcmp(name, 'build_clean_test_pools')
    for CLEAN_SET = {'val', 'test'}
        CLEAN_SET = CLEAN_SET{1}; %#ok<FXSET,NASGU>
        run(name);
    end
elseif strcmp(name, 'validate_phy')
    if ~validate_phy(), error('run_stage:phy', 'PHY validation failed'); end
else
    run(name);
end
end
