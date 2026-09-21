%% MAIN - Master Execution & Status Pipeline
% UAV-GCS Adaptive Secure Communications System
% Orchestrates the full project end to end:
%   A     Link + Threats + Dataset
%   B     Detection (CNN + scalar hybrid)
%   C     Closed-loop adaptive recovery (DQN)
%   EXP   Deep countermeasure exploration
%   SURV  Survivability boundary mapping (deliverable #7)
%   KPI   Proposal KPI measurement (section 5 / ה)
%   DASH  Results dashboard (deliverable #1)
% Author: Adi Suliman, Bar Dvir Hassan
%
% HOW TO USE
% Every stage below is a RUN.<flag>. Set a flag true to run that stage.
% They execute top to bottom in dependency order, so to run the whole project
% from scratch, set the flags in the "FULL CLEAN RUN" preset to true.
% All flags default to FALSE (everything is already generated) -- turn on only
% what you need to regenerate.
%
% Runtimes (RTX 4070): A5 ~30-40min, A6 ~5min, B2 ~10min, C2 ~10-15min,
% C3-diag ~15-20min, EXP ~75-86min (VERY HEAVY), everything else < 5min.
%
% DEPENDENCIES (what must exist before a stage can run):
%   A6 needs A5 | B1 needs A6 | B2 needs B1 | B3 needs B2
%   C2 needs B2 | C3 needs C2 | C3-diag needs C2
%   SURV needs EXP | KPI needs B3+C3-diag+FAR | DASH needs B3+C3-diag+FAR+SURV
%
% LOGGING: `diary` captures everything printed below into logs/run_*.txt,
% surviving the close all/clc that each called script starts with.
%
% BATCH MODE: leave BATCH_MODE_DISABLED = false and launch headless from a
% Windows Command Prompt to keep working while it runs:
%   matlab -batch "main" -nosplash
% (drop -nojvm if a stage needs Java/Stateflow; it stays headless either way)

clear; close all; clc;

%% ========== BATCH MODE CONTROL ==========
BATCH_MODE_DISABLED = false;   % true = force GUI windows; false = allow headless
%% =========================================

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
%  QUICK PRESETS — copy the block you want over the flags below:
%
%  FULL CLEAN RUN (everything from scratch, ~3 hours incl. EXP):
%    all A/B/C/EXP/SURV/KPI/DASH flags = true
%
%  RESULTS-ONLY REFRESH (models already trained, ~25 min):
%    run_closed_loop_diagnostic, measure_far, measure_kpi3,
%    measure_all_kpis, build_dashboard = true; rest = false
%
%  SPEED-DIVERSE RETRAIN (after switching to the 50-120 km/h envelope):
%    init, build_dataset, extract_spectrograms, prepare_data, train_detector,
%    eval_detector, run_closed_loop_diagnostic, eval_speed_robustness,
%    measure_far, measure_kpi3, measure_all_kpis, build_dashboard = true;
%    everything else (train_dqn, EXP, SURV, validate/check A) = false
%
%  DASHBOARD-ONLY (all results exist, < 1 min):
%    build_dashboard = true; rest = false
%% ================================================================

% ---- Phase A: link + threats + dataset ----
RUN.init                        = true;   % A0  : regenerate params.mat
RUN.validate_A                  = true;   % A1-A3: build+validate AWGN & Rician links (fast)
RUN.check_A4                    = true;   % A4  : bבכuild threat model + sanity BER (fast)
RUN.build_dataset               = true;   % A5  : full dataset sweep (HEAVY ~30-40min)
RUN.extract_spectrograms        = true;   % A6  : spectrograms + 7 features (~5min)


% ---- Phase B: detection (CNN baseline) ----
RUN.prepare_data                = true;   % B1  : stratified 80/10/10 split (~1min)
RUN.train_detector              = true;   % B2  : train CNN+scalar hybrid (~10min)
RUN.eval_detector               = true;   % B3  : test eval + confusion/accuracy-vs-SNR (~1min)


% ---- Phase C: closed-loop recovery ----
RUN.train_dqn                   = true;   % C2  : train DQN (one-hot state) (~10-15min)בי ינ

RUN.run_closed_loop_diagnostic  = true;   % C3d : full SNR sweep + timing + Q-values (~15-20min)
RUN.eval_speed_robustness       = true;   % C3s : detection/decision/recovery vs UAV speed 50-120 km/h (~30-60min)

% ---- Phase EXP: deep countermeasure exploration ----
RUN.explore_countermeasures     = true;   % EXP : full sweep (VERY HEAVY ~75-86min)
RUN.analyze_exploration_results = true;   % EXP-analysis: legitimacy filter + diagnosis (fast)

% ---- Phase SURV: survivability boundary mapping (deliverable #7) ----
RUN.map_survivability           = true;   % SURV: Map A + Map B + gap analysis (~5min, needs EXP data)

% ---- Phase KPI: proposal measurement (section 5 / ה) ----
RUN.measure_far                 = true;   % KPI4 : FAR on non-hostile classes, SNR-swept (~5min)
RUN.measure_kpi3                 = true;   % KPI3 : DQN vs rule decision latency (fast, needs C3-diag)
RUN.measure_all_kpis            = true;   % KPI  : aggregate all 5 into kpi_summary.txt (fast)

% ---- Phase DASH: results dashboard (deliverable #1) ----
RUN.build_dashboard             = true;   % DASH : 7-panel summary PNG (fast, needs B3+C3d+FAR+SURV)

fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A:Link+Data  B:Detect  C:Recover  EXP:Explore  SURV:Map  KPI:Measure  DASH:Summary\n');
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

if RUN.build_dataset
    fprintf('  [A5] Generating multi-JSR dataset, 9 threats/classes incl. none (HEAVY, frames_per_config=100)...\n');
    run_dataset_sweep;
end

if RUN.extract_spectrograms
    fprintf('  [A6] Extracting spectrograms + 7 features (HEAVY)...\n');
    extract_spectrograms;
end

fprintf('  [A5-A6] Dataset status:\n');
report_file('data/dataset.mat',      '         raw dataset  ', 'run_dataset_sweep');
report_file('data/spectrograms.mat', '         spectrograms ', 'extract_spectrograms');
fprintf('\n');

%% ========== PHASE B: DETECTION (OFFLINE, CNN baseline) ==========
fprintf('> PHASE B: Detection Network (CNN + scalar hybrid, 9 classes)\n\n');

if RUN.prepare_data
    fprintf('  [B1] Preparing data (stratified split 80/10/10)...\n');
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

fprintf('  [B] Pipeline status:\n');
report_file('data/splits.mat',            '      splits.mat           ', 'prepare_data');
report_file('data/trained_detector.mat',  '      trained_detector.mat ', 'train_detector');
report_file('results/confusion_matrix.png','      B3 eval results      ', 'eval_detector');
fprintf('\n');

%% ========== PHASE C: CLOSED-LOOP RECOVERY (ONLINE) ==========
fprintf('> PHASE C: Closed-Loop Adaptive Recovery (9 threats/classes)\n\n');
fprintf('  [C1] Rule-based countermeasure policy...           READY (rule_based_policy.m)\n');

if RUN.train_dqn
    fprintf('  [C2] Training DQN agent (one-hot state, real threat-specific reward table)...\n');
    train_dqn;
end
if RUN.run_closed_loop
    fprintf('  [C3] Running closed-loop with CNN detector + DQN...\n');
    run_closed_loop_with_detector;
end
if RUN.run_closed_loop_diagnostic
    fprintf('  [C3-diag] Running full diagnostic closed-loop (timing, Q-values, rule comparison)...\n');
    run_closed_loop_diagnostic;
end

if RUN.eval_speed_robustness
    fprintf('  [C3-speed] Closed-loop robustness vs UAV speed (Doppler sweep, 50-120 km/h)...\n');
    eval_speed_robustness;
end

fprintf('  [C] Pipeline status:\n');
report_file('data/trained_dqn.mat',                     '      trained_dqn.mat        ', 'train_dqn');
report_file('results/closed_loop_results.png',          '      C3 closed-loop results ', 'run_closed_loop');
report_file('results/closed_loop_diagnostic_report.txt','      C3-diag full report    ', 'run_closed_loop_diagnostic');
report_file('results/speed_robustness.txt',             '      C3-speed robustness    ', 'eval_speed_robustness');
fprintf('\n');

%% ========== PHASE EXP: DEEP COUNTERMEASURE EXPLORATION ==========
fprintf('> PHASE EXP: Deep Countermeasure Exploration (research extension)\n\n');

if RUN.explore_countermeasures
    fprintf('  [EXP] Running full countermeasure sweep (VERY HEAVY, ~75-86 min)...\n');
    explore_countermeasures;
end
if RUN.analyze_exploration_results
    fprintf('  [EXP-analysis] Post-hoc diagnosis (filters physically-invalid results)...\n');
    analyze_exploration_results;
end

fprintf('  [EXP] Pipeline status:\n');
report_file('data/countermeasure_exploration.mat', '      countermeasure_exploration.mat ', 'explore_countermeasures');
report_file('results/exploration_diagnosis.txt',   '      exploration_diagnosis.txt      ', 'analyze_exploration_results');
fprintf('\n');

%% ========== PHASE SURV: SURVIVABILITY BOUNDARY MAP (deliverable #7) ==========
fprintf('> PHASE SURV: Survivability Boundary Mapping (proposal deliverable #7)\n\n');

if RUN.map_survivability
    fprintf('  [SURV] Mapping Map A (neutralization) + Map B (survivability) + gap analysis...\n');
    map_survivability_boundary;
end

fprintf('  [SURV] Pipeline status:\n');
report_file('data/survivability_boundary.mat',        '      survivability_boundary.mat     ', 'map_survivability_boundary');
report_file('results/survivability_boundary_mapA.txt','      Map A (neutralization)         ', 'map_survivability_boundary');
report_file('results/survivability_boundary_mapB.txt','      Map B (link survivability)     ', 'map_survivability_boundary');
fprintf('\n');

%% ========== PHASE KPI: PROPOSAL MEASUREMENT (section 5 / ה) ==========
fprintf('> PHASE KPI: Proposal KPI Measurement\n\n');

if RUN.measure_far
    fprintf('  [KPI4] Measuring FAR on non-hostile classes (SNR-swept)...\n');
    diagnose_far_measurement;
end
if RUN.measure_kpi3
    fprintf('  [KPI3] Measuring DQN vs rule-based decision latency...\n');
    measure_kpi3_recovery_time;
end
if RUN.measure_all_kpis
    fprintf('  [KPI] Aggregating all 5 proposal KPIs...\n');
    measure_all_kpis;
end

fprintf('  [KPI] Pipeline status:\n');
report_file('results/far_measurement.txt',  '      far_measurement.txt   ', 'diagnose_far_measurement');
report_file('results/kpi3_measurement.txt', '      kpi3_measurement.txt  ', 'measure_kpi3_recovery_time');
report_file('results/kpi_summary.txt',      '      kpi_summary.txt       ', 'measure_all_kpis');
fprintf('\n');

%% ========== PHASE DASH: RESULTS DASHBOARD (deliverable #1) ==========
fprintf('> PHASE DASH: Results Dashboard (proposal deliverable #1)\n\n');

if RUN.build_dashboard
    fprintf('  [DASH] Building 7-panel results dashboard...\n');
    build_kpi_dashboard;
end

fprintf('  [DASH] Pipeline status:\n');
report_file('results/kpi_dashboard.png', '      kpi_dashboard.png ', 'build_kpi_dashboard');
fprintf('\n');

%% ========== PHASE D: DOCUMENTATION ==========
fprintf('> PHASE D: Documentation & Defense\n\n');
fprintf('  [D1] README.md / PROJECT_LOG.md / docs/DECISIONS.md  READY (maintained by hand)\n');
fprintf('  [D2] Interim/final report (docx)...                  [PENDING]\n');
fprintf('  [D3] Defense presentation (pptx)...                  [PENDING]\n\n');

%% ========== CHECKPOINT ==========
fprintf('========================================================\n');
fprintf(' CHECKPOINT - full pipeline available from main.m\n');
fprintf(' Current verified results: CNN 96.99%% | closed-loop 100%% | recovery 74.6%% | FAR 0%% | latency 2.67ms\n');
fprintf(' Survivability Map A 84.6%% / Map B 87.9%% recoverable (deliverable #7)\n');
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