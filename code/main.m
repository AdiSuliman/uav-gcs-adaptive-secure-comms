%% MAIN - Master Execution & Status Pipeline
% UAV-GCS Adaptive Secure Communications System
% Orchestrates the full project end to end:
%   A     Link + threats + dataset
%   B     Detection (CNN + link features, unknown-threat scores)
%   C     Decision layer (frame pools, DQN, evaluation of every policy)
%   SURV  Survivability boundary mapping (deliverable 8)
%   KPI   Latency and proposal KPIs (section 5)
%   DASH  Results dashboard (deliverable 1)
% Author: Adi Suliman, Bar Dvir Hassan
%
% HOW TO USE
% Every stage below is a RUN.<flag>. Set a flag true to run that stage.
% They execute top to bottom in dependency order. Launch headless from cmd or
% Git Bash in the project folder:  matlab -batch "main"
%
% Runtimes (Ryzen 7 7700, RTX 4070 SUPER, 6 parallel workers): A5 ~17 min, A6 ~7 min,
% B1 ~1 min, B2 ~8 min, B3a ~16 min, B4 ~25 min, OOD ~70 min, C1p ~3-4 h, C1c ~40 min,
% C2 ~3 h, C2e ~1 h, SURV ~1.5 h, SURV3 ~1 h, LAT ~2 min, KPI and DASH < 1 min.
% The same stages run headless and logged with run_stage.m, e.g.
%   matlab -batch "run_stage('C1p','C1c','C1d','C2','C2e')"
% and on a reduced problem with run_stage('smoke', ...).
%
% DEPENDENCIES (what must exist before a stage can run):
%   A5 needs A0 | A6 needs A5 | B1 needs A6 | B2 needs B1 | B3, B3a, B4, OOD need B2 | B4s needs OOD
%   C1p needs OOD (it selects the production unknown-threat score) | C1c, C1d need C1p | C2 needs C1p, C1c (validation set), C1d | C2e needs C2 (and C1c for KPI 6)
%   LAT needs C2 | SURV, SURV3 need A0 | KPI reads B3, B4, OOD, A4v, C2e, LAT, SURV | DASH needs KPI
%
% LOGGING: `diary` captures everything printed below into logs/run_*.txt,
% surviving the close all/clc that each called script starts with.

clear; close all; clc;
cd(setup_paths());                                 % repository folder: data/, results/, models/, logs/

%% ========== BATCH MODE CONTROL ==========
BATCH_MODE_DISABLED = false;   % true = force GUI windows; false = allow headless
%% =========================================

%% ========== FIGURE THEME (light for every saved figure, this session only) ==========
try
    st = settings;
    st.matlab.appearance.figure.GraphicsTheme.TemporaryValue = "light";
catch
end

if ~BATCH_MODE_DISABLED && ~usejava('desktop')
    fprintf('Running in batch mode (no GUI). All output will be logged.\n');
end

%% ========== LOGGING SETUP (diary — survives all internal clc calls) ==========
if ~exist('logs', 'dir'), mkdir('logs'); end
log_filename = sprintf('logs/run_%s.txt', datestr(now, 'yyyymmdd_HHMMSS'));
diary(log_filename);
diary on;
fprintf('=== Logging full run to: %s ===\n', log_filename);
fprintf('(This file will contain EVERYTHING printed below, even across clc calls.)\n\n');

%% ================================================================
%  EXECUTION FLAGS  (all default false — turn on what you need)
%  ================================================================
%  QUICK PRESETS - copy the block you want over the flags below:
%
%  FULL CLEAN RUN (everything from scratch, ~13 hours):
%    every flag below = true except validate_A and check_A4
%
%  DECISION LAYER + RESULTS (detector unchanged, ~10 hours):
%    build_policy_pools, build_clean_test_pools, choose_drop_threshold, train_dqn,
%    evaluate_policies, map_survivability, survivability_options, measure_latency,
%    measure_all_kpis, build_dashboard = true; rest = false
%
%  RESULTS ONLY (models and pools exist, ~1 hour):
%    evaluate_policies, measure_latency, measure_all_kpis, build_dashboard = true
%
%  DASHBOARD ONLY (< 1 min):
%    measure_all_kpis, build_dashboard = true; rest = false
%% ================================================================

warning('off', 'Simulink:cgxe:LeakedJITEngine');   % internal Simulink notice on repeated sim() of MATLAB Function blocks
disk_guard('init');                                % Simulink temporary data and the 200 GB free-disk floor

% ---- Decision-layer training; defaults of train_dqn.m when absent ----
CFG.dqn_seeds       = 3;                 % C2: training seeds per setting
CFG.dqn_gammas      = 0.5;               % C2: discount factor (selected on validation)
CFG.monitors        = {'class_drop 3/3', 'class_drop 2/2'};  % C2: alarm definition and m/n confirmation (selected on validation)
CFG.drop_steps      = 2;                 % C2: path_loss alarm threshold, 2 dB below the train-pool value (selected on validation)
CFG.fa_penalty_grid = [80 120 160];      % C2: training reward variants: false-switch penalty,
CFG.cost_scale_grid = [0.5 0.5 0.5];     %     running costs x scale,
CFG.switch_scale_grid = [1 1 1];         %     switching cost x scale

% ---- Phase A: link + threats + dataset ----

RUN.init                        = false;    % A0  : regenerate params.mat
RUN.validate_A                  = false;   % A1-A3: build+validate AWGN & Rician links (fast)
RUN.check_A4                    = false;   % A4  : build threat model + sanity BER (fast)
RUN.validate_phy                = false;    % A4v : link vs theory, MRC/MMSE, seeds; stops main on FAIL
RUN.build_dataset               = false;    % A5  : seeded sub-run dataset, 10 threats x 8 levels, receiver measurements (~40 min)
RUN.extract_spectrograms        = false;    % A6  : spectrograms + 15 link features (~12 min)


% ---- Phase B: detection (CNN baseline) ----
RUN.prepare_data                = false;    % B1  : split by sub-run 4/1/1 (~2 min)
RUN.train_detector              = false;    % B2  : train CNN+scalar hybrid, unknown-threat models (~8 min); a new detector invalidates the pools
RUN.eval_detector               = false;    % B3  : test eval + confusion/accuracy-vs-SNR + bootstrap CIs (~2 min)
RUN.compare_architectures       = false;    % B3a : hybrid vs spectrogram-only vs features-only (~16 min)
RUN.eval_unseen_snr             = false;    % B4  : detector at Eb/N0 never seen in training, midpoints of the grid (~30 min)
RUN.eval_ood_detection          = false;    % OOD : leave-one-threat-out, retrains the detector 10 times; selects the production unknown-threat score (~2.5 h)
RUN.eval_unseen_severity        = false;    % B4s : detector at severities never seen in training, between and above the levels (~10 min)


% ---- Phase C: decision layer ----
RUN.build_policy_pools          = false;    % C1p : frame pools, every cell x configuration x Eb/N0 x geometry (~3-4 h)
RUN.build_clean_test_pools      = false;    % C1c : clean link on new geometries: validation set and test set for KPI 6 (~40 min; skips when up to date)
RUN.choose_drop_threshold       = false;    % C1d : path_loss alarm threshold from the train pools (< 1 min)
RUN.train_dqn                   = false;    % C2  : Double DQN + shield, alarm x penalty x gamma x seeds, selection on validation (~3 h)
RUN.evaluate_policies           = false;    % C2e : every policy on the test pools: single, follower, combined, unknown, clean (~1 h)
RUN.combo_generalization        = false;    % C2g : combined threats never trained on, leave-one-combination-out (~50 min)
RUN.threat_gallery              = false;    % GAL : one figure per threat for the report, with the DQN's most frequent response (~5 min)

% ---- Phase SURV: survivability boundary mapping (deliverable 8) ----
RUN.map_survivability           = false;    % SURV: Map A/B per threat, severity, Eb/N0 and geometry (~1.5 h)
RUN.survivability_options       = false;    % SURV3: 2 vs 3 antennas vs relay path (~1 h)

% ---- Phase KPI: latency and proposal KPIs (section 5) ----
RUN.measure_latency             = false;    % LAT : decision latency per cycle, median / p95 (~2 min)
RUN.measure_all_kpis            = true;    % KPI : the 8 proposal KPIs from the result files

% ---- Phase DASH: results dashboard (deliverable 1) ----
RUN.build_dashboard             = true;    % DASH: 8-panel summary PNG

fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A:Link+Data  B:Detect  C:Recover  SURV:Map  KPI:Measure  DASH:Summary\n');
fprintf('========================================================\n\n');

%% ========== PHASE A: LINK + THREATS + DATASET ==========
fprintf('> PHASE A: Link Model + Threat Injection + Dataset\n\n');

if RUN.init
    fprintf('  [A0] init_params...\n');
    init_params;
end
p = load('params.mat').params;
berTheory = berawgn(0, 'psk', p.mod_order, 'nondiff');

if RUN.validate_A
    fprintf('  [A1] Building + validating AWGN link (RRC pulse shaping)...\n');
    build_link_model;
    berA1 = quick_ber('UAV_GCS_Base_Link');
    fprintf('       A1 AWGN : BER=%.3e | theory=%.3e | ratio=%.2fx\n', berA1, berTheory, berA1/berTheory);

    fprintf('  [A3] Building + validating Rician link (K=%.0fdB, fd=%.0fHz)...\n', p.rician_k, p.fd_max);
    build_rician_model;
    berA3 = quick_ber('UAV_GCS_Rician_Link');
    fprintf('       A3 Rician: BER=%.3e | degradation=%.2fx (fading penalty)\n', berA3, berA3/berTheory);
end

if RUN.check_A4
    fprintf('  [A4] Building + checking threat model (active: %s)...\n', p.active_threat);
    build_threat_model;
    berA4 = quick_ber('UAV_GCS_Threat_Link');
    fprintf('       A4 Threat: BER=%.3e under %s (JSR=%.0fdB)\n', berA4, p.active_threat, p.jsr_db);
end

if RUN.validate_phy
    fprintf('  [A4v] Validating the multi-antenna link against theory...\n');
    if ~validate_phy()
        error('main:phy', 'PHY validation failed -- see results/phy_validation.txt. Stopping before the dataset.');
    end
end

if RUN.build_dataset
    fprintf('  [A5] Generating the seeded sub-run dataset, 8 threats x 5 levels + none (HEAVY)...\n');
    run_dataset_sweep;
end

if RUN.extract_spectrograms
    fprintf('  [A6] Extracting spectrograms + 13 link features (HEAVY)...\n');
    extract_spectrograms;
end

fprintf('  [A5-A6] Dataset status:\n');
report_file('data/dataset.mat',      '         raw dataset  ', 'run_dataset_sweep');
report_file('data/spectrograms.mat', '         spectrograms ', 'extract_spectrograms');
fprintf('\n');

%% ========== PHASE B: DETECTION (OFFLINE, CNN baseline) ==========
fprintf('> PHASE B: Detection Network (CNN + scalar hybrid, 9 classes)\n\n');

if RUN.prepare_data
    fprintf('  [B1] Preparing data (split by sub-run: train 5, validation 1, test 2)...\n');
    prepare_data;
end
if RUN.train_detector
    fprintf('  [B2] Training hybrid CNN+scalar detector (9 classes)...\n');
    train_detector;
end
if RUN.eval_detector
    fprintf('  [B3] Evaluating on test set...\n');
    eval_detector;
end
if RUN.compare_architectures
    fprintf('  [B3a] Detector architectures on the same splits...\n');
    compare_architectures;
end
if RUN.eval_unseen_snr
    fprintf('  [B4] Detector generalization to unseen Eb/N0...\n');
    eval_unseen_snr;
end
if RUN.eval_ood_detection
    fprintf('  [OOD] Leave-one-threat-out unknown-threat detection; selects the production score...\n');
    eval_ood_detection;
    clear S sp tr va te_id te_ood net                  % spectrogram splits held by the script
end
if RUN.eval_unseen_severity
    fprintf('  [B4s] Detector at unseen threat severities...\n');
    eval_unseen_severity;
end

fprintf('  [B] Pipeline status:\n');
report_file('data/splits.mat',            '      splits.mat           ', 'prepare_data');
report_file('data/trained_detector.mat',  '      trained_detector.mat ', 'train_detector');
report_file('results/confusion_matrix.png','      B3 eval results      ', 'eval_detector');
report_file('results/ood_detection.txt',   '      OOD report           ', 'eval_ood_detection');
fprintf('\n');

%% ========== PHASE C: DECISION LAYER ==========
fprintf('> PHASE C: Decision layer (frame pools, DQN, evaluation)\n\n');
fprintf('  [C1] Rule-based countermeasure policy...           READY (rule_based_policy.m)\n');

if RUN.build_policy_pools
    fprintf('  [C1p] Measuring the decision-layer frame pools...\n');
    build_policy_pools;
end
if RUN.build_clean_test_pools
    fprintf('  [C1c] Measuring the clean link on new geometries: validation set, test set (KPI 6)...\n');
    CLEAN_SET = 'val';  build_clean_test_pools;
    CLEAN_SET = 'test'; build_clean_test_pools;
end
if RUN.choose_drop_threshold
    fprintf('  [C1d] Choosing the Eb/N0-drop threshold of the path_loss alarm (train pools)...\n');
    choose_drop_threshold;
end
if RUN.train_dqn
    fprintf('  [C2] Training the DQN (Double DQN, replay, target network, shield)...\n');
    train_dqn;
end
if RUN.evaluate_policies
    fprintf('  [C2e] Evaluating every policy on the test pools...\n');
    evaluate_policies;
end
if RUN.combo_generalization
    fprintf('  [C2g] Combined threats never trained on (leave-one-combination-out)...\n');
    experiment_combo_generalization;
end
if RUN.threat_gallery
    fprintf('  [GAL] Threat gallery figures...\n');
    threat_gallery;
end

fprintf('  [C] Pipeline status:\n');
report_file('data/policy_pools.mat',          '      policy_pools.mat       ', 'build_policy_pools');
report_file('data/clean_val_pools.mat',       '      clean_val_pools.mat    ', 'build_clean_test_pools');
report_file('data/clean_test_pools.mat',      '      clean_test_pools.mat   ', 'build_clean_test_pools');
report_file('results/drop_threshold.txt',     '      drop threshold (C1d)   ', 'choose_drop_threshold');
report_file('data/trained_dqn.mat',           '      trained_dqn.mat        ', 'train_dqn');
report_file('results/dqn_training.txt',       '      C2 training report     ', 'train_dqn');
report_file('results/policy_evaluation.txt',  '      C2e evaluation report  ', 'evaluate_policies');
report_file('results/combo_generalization.txt','      C2g unseen combinations', 'experiment_combo_generalization');
report_file('results/threat_gallery/overview.png','      GAL threat gallery     ', 'threat_gallery');
fprintf('\n');

%% ========== PHASE SURV: SURVIVABILITY BOUNDARY MAP (deliverable 8) ==========
fprintf('> PHASE SURV: Survivability Boundary Mapping (proposal deliverable 8)\n\n');

if RUN.map_survivability
    fprintf('  [SURV] Map A (no goodput loss) + Map B (any action), two geometries + gap analysis...\n');
    map_survivability_boundary;
end
if RUN.survivability_options
    fprintf('  [SURV3] Survivability with 3 antennas and with a relay path...\n');
    experiment_survivability_options;
end

fprintf('  [SURV] Pipeline status:\n');
report_file('data/survivability_boundary.mat',        '      survivability_boundary.mat     ', 'map_survivability_boundary');
report_file('results/survivability_boundary_mapA.txt','      Map A (no goodput loss)        ', 'map_survivability_boundary');
report_file('results/survivability_boundary_mapB.txt','      Map B (any action)             ', 'map_survivability_boundary');
fprintf('\n');

%% ========== PHASE KPI: LATENCY AND PROPOSAL KPIs (section 5) ==========
fprintf('> PHASE KPI: Latency and proposal KPIs\n\n');

if RUN.measure_latency
    fprintf('  [LAT] Decision latency per cycle...\n');
    measure_latency;
end
if RUN.measure_all_kpis
    fprintf('  [KPI] Proposal KPIs from the result files...\n');
    measure_all_kpis;
end

fprintf('  [KPI] Pipeline status:\n');
report_file('results/latency.txt',     '      latency.txt           ', 'measure_latency');
report_file('results/kpi_summary.txt', '      kpi_summary.txt       ', 'measure_all_kpis');
fprintf('\n');

%% ========== PHASE DASH: RESULTS DASHBOARD (deliverable 1) ==========
fprintf('> PHASE DASH: Results Dashboard (proposal deliverable 1)\n\n');

if RUN.build_dashboard
    fprintf('  [DASH] Building the results dashboard...\n');
    build_kpi_dashboard;
end

fprintf('  [DASH] Pipeline status:\n');
report_file('results/kpi_dashboard.png', '      kpi_dashboard.png ', 'build_kpi_dashboard');
fprintf('\n');

%% ========== PHASE D: DOCUMENTATION ==========
fprintf('> PHASE D: Documentation & Defense\n\n');
fprintf('  [D1] README.md, docs/DECISIONS.md, docs/PROJECT_LOG.md, docs/ROADMAP.md  READY (maintained by hand)\n');
fprintf('  [D2] Interim/final report (docx)...                  [PENDING]\n');
fprintf('  [D3] Defense presentation (pptx)...                  [PENDING]\n\n');

%% ========== CHECKPOINT ==========
fprintf('========================================================\n');
fprintf(' CHECKPOINT - full pipeline available from main.m\n');
fprintf(' KPIs: results/kpi_summary.txt | decision layer: results/policy_evaluation.txt\n');
fprintf(' Survivability maps: results/survivability_boundary_mapA.txt / mapB.txt (deliverable 8)\n');
fprintf(' Outputs in results/, data/ | models in models/ | code on GitHub\n');
fprintf(' Full run log saved to: %s\n', log_filename);
fprintf('========================================================\n\n');

diary off;
fprintf('Diary closed. Open %s for the complete unclipped run transcript.\n', log_filename);


%% ========== local helper ==========
function report_file(path, label, producer)
    % Prints "label : READY (date, size)" or "label : [PENDING] -> producer"
    if exist(path, 'file')
        d = dir(path);
        if d.bytes >= 1e6
            fprintf('%s: READY (%s, %.0f MB)\n', label, d.date, d.bytes/1e6);
        else
            fprintf('%s: READY (%s)\n', label, d.date);
        end
    else
        fprintf('%s: [PENDING] -> %s\n', label, producer);
    end
end