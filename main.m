%% MAIN - Master Execution & Status Pipeline
% UAV-GCS Adaptive Secure Communications System
% Orchestrates Phase A (Link+Threats+Dataset) -> B (Detection) -> B-exp (CNN-LSTM)
% -> C (Recovery) -> EXP (Exploration) -> KPI (Measurement) -> D (Report)
% Author: Adi Suliman, Bar Dvir Hassan
%
% Toggle the RUN flags below (true/false). They execute in the order listed.
% Light stages are fast; heavy stages (A5-A6, B2, C2, explore_countermeasures)
% take minutes to over an hour -- leave them false unless regenerating.
%
% COMMAND WINDOW LOGGING: every called script starts with close all/clc, which
% would normally wipe out everything printed by earlier stages. This is solved
% with MATLAB's `diary` command: it logs EVERYTHING printed to the Command
% Window into a text file, independent of clc. Open logs/run_*.txt after
% running to get the complete output.
%
% BATCH MODE: set BATCH_MODE_DISABLED = true to run normally with GUI windows.
% Leave it false and launch from a Windows Command Prompt with:
%   matlab -batch "main" -nojvm -nosplash
% to run headless in the background while you work in other applications.

clear; close all; clc;

%% ========== BATCH MODE CONTROL ==========
BATCH_MODE_DISABLED = false;   % true = run with GUI windows (normal mode)
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

%% ========== EXECUTION FLAGS (in execution order) ==========
% 2026-09-19: full re-run required after the Rx_IQ tap-point fix (D18) --
% spectrograms/RSSI were computed pre-AWGN before this fix, so everything
% downstream of A6 needs regenerating. EXP/survivability are BER-only
% (quick_ber, no Rx_IQ) and are NOT affected -- left false, no rerun needed.
RUN.init                        = false;   % A0 : params.mat unchanged, no rerun needed
RUN.validate_A                  = false;   % A1-A3: unchanged, no rerun needed
RUN.check_A4                    = true;    % A4 : quick sanity check of the FIXED threat model (fast)
RUN.build_dataset               = true;    % A5 : REQUIRED -- Rx_IQ now post-AWGN (~30-40 min)
RUN.extract_spectrograms        = true;    % A6 : REQUIRED -- spectrograms from the new dataset (~5 min)

% --- Phase A-exp: sequence windowing for CNN-LSTM ---
RUN.build_sequence_index        = false;   % A5-seq : STALE (predates spoofing fix), LSTM not pursued
RUN.extract_spectrograms_seq    = false;   % A6-seq : STALE — same reason

RUN.temporal_features           = false;   % B2.5: DEPRECATED — folded into extract_spectrograms.m (A6)
RUN.prepare_data                = true;    % B1  : REQUIRED -- re-split on new spectrograms (~1 min)
RUN.train_detector              = true;    % B2  : REQUIRED -- retrain CNN on real noisy signal (~10 min)
RUN.eval_detector                = true;    % B3  : REQUIRED -- true accuracy-vs-SNR curve (~1 min)

% --- Phase B-exp: CNN-LSTM detector — NOT PURSUED FURTHER ---
RUN.prepare_data_seq            = false;
RUN.train_detector_lstm         = false;
RUN.eval_detector_lstm          = false;

RUN.train_dqn                   = true;    % C2  : REQUIRED -- RSSI in reward table now real (~10-15 min)
RUN.run_closed_loop             = true;    % C3  : REQUIRED -- Rx_IQ-based spectrogram/RSSI (~2-3 min)
RUN.run_closed_loop_diagnostic  = true;    % C3d : REQUIRED -- full SNR sweep, sliding window (~15-20 min)

RUN.explore_countermeasures     = false;   % EXP : NOT AFFECTED (quick_ber only, no Rx_IQ) -- no rerun needed
RUN.analyze_exploration_results = false;   % EXP-analysis: unaffected, existing results/exploration_diagnosis.txt still valid

% --- Phase KPI: proposal section-ה measurement ---
RUN.measure_far                 = true;    % KPI4 : REQUIRED -- diagnose_far_measurement.m uses Rx_IQ (~5 min)
RUN.measure_all_kpis            = true;    % KPI  : REQUIRED -- regenerate results/kpi_summary.txt with real numbers (fast, now fixed to read .mat directly)

fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A: Link+Threats+Data | B: Detection | C: Recovery | EXP: Exploration | KPI: Measurement\n');
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
if exist('data/dataset.mat','file')
    d = dir('data/dataset.mat');
    fprintf('         raw dataset  : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('         raw dataset  : [PENDING] -> run_dataset_sweep\n');
end
if exist('data/spectrograms.mat','file')
    d = dir('data/spectrograms.mat');
    fprintf('         spectrograms : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('         spectrograms : [PENDING] -> extract_spectrograms\n');
end
fprintf('\n');

%% ========== PHASE A-exp: SEQUENCE WINDOWING (for CNN-LSTM) ==========
fprintf('> PHASE A-exp: Sequence Windowing (CNN-LSTM data prep) -- NOT PURSUED FURTHER\n\n');

if RUN.build_sequence_index
    fprintf('  [A5-seq] Building sequence index from dataset.mat (with run_id)...\n');
    build_sequence_index;
end
if RUN.extract_spectrograms_seq
    fprintf('  [A6-seq] Assembling sequence spectrogram tensors...\n');
    extract_spectrograms_seq;
end

fprintf('  [A-exp] Sequence pipeline status (STALE -- predates spoofing fix, not regenerated):\n');
if exist('data/dataset_seq_index.mat','file')
    d = dir('data/dataset_seq_index.mat');
    fprintf('         sequence index    : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('         sequence index    : [PENDING] -> build_sequence_index\n');
end
if exist('data/spectrograms_seq.mat','file')
    d = dir('data/spectrograms_seq.mat');
    fprintf('         spectrograms_seq  : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('         spectrograms_seq  : [PENDING] -> extract_spectrograms_seq\n');
end
fprintf('\n');

%% ========== PHASE B: DETECTION (OFFLINE, CNN baseline) ==========
fprintf('> PHASE B: Detection Network (CNN + scalar hybrid, 9 classes)\n\n');

if RUN.temporal_features
    fprintf('  [B2.5] DEPRECATED flag — no script called (folded into A6 extract_spectrograms.m)\n');
end
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
if exist('data/splits.mat','file')
    d = dir('data/splits.mat');
    fprintf('      splits.mat            : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      splits.mat            : [PENDING] -> prepare_data\n');
end
if exist('data/trained_detector.mat','file')
    d = dir('data/trained_detector.mat');
    fprintf('      trained_detector.mat  : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      trained_detector.mat  : [PENDING] -> train_detector\n');
end
if exist('results/confusion_matrix.png','file')
    fprintf('      B3 evaluation results : READY -> results/confusion_matrix.png\n');
else
    fprintf('      B3 evaluation results : [PENDING] -> eval_detector\n');
end
fprintf('\n');

%% ========== PHASE B-exp: CNN-LSTM DETECTOR (comparison architecture) ==========
fprintf('> PHASE B-exp: CNN-LSTM Detector -- NOT PURSUED FURTHER\n\n');

if RUN.prepare_data_seq
    fprintf('  [B1-seq] Preparing sequence splits...\n');
    prepare_data_seq;
end
if RUN.train_detector_lstm
    fprintf('  [B2-seq] Training CNN-LSTM detector...\n');
    train_detector_lstm;
end
if RUN.eval_detector_lstm
    fprintf('  [B3-seq] Evaluating CNN-LSTM on test set...\n');
    eval_detector_lstm;
end

fprintf('  [B-exp] Pipeline status (STALE, kept for the architecture-comparison record only):\n');
if exist('data/splits_seq.mat','file')
    d = dir('data/splits_seq.mat');
    fprintf('      splits_seq.mat            : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      splits_seq.mat            : [PENDING] -> prepare_data_seq\n');
end
if exist('data/trained_detector_lstm.mat','file')
    d = dir('data/trained_detector_lstm.mat');
    fprintf('      trained_detector_lstm.mat : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      trained_detector_lstm.mat : [PENDING] -> train_detector_lstm\n');
end
if exist('results/eval_detector_lstm_metrics.mat','file')
    fprintf('      B3-seq evaluation results : READY -> results/confusion_matrix_lstm.png\n');
else
    fprintf('      B3-seq evaluation results : [PENDING] -> eval_detector_lstm\n');
end
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

fprintf('  [C] Pipeline status:\n');
if exist('data/trained_dqn.mat','file')
    d = dir('data/trained_dqn.mat');
    fprintf('      trained_dqn.mat            : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      trained_dqn.mat            : [PENDING] -> train_dqn\n');
end
if exist('results/closed_loop_results.png','file')
    fprintf('      C3 closed-loop results     : READY -> results/closed_loop_results.png\n');
else
    fprintf('      C3 closed-loop results     : [PENDING] -> run_closed_loop\n');
end
if exist('results/closed_loop_diagnostic_report.txt','file')
    fprintf('      C3-diag full report        : READY -> results/closed_loop_diagnostic_report.txt\n');
else
    fprintf('      C3-diag full report        : [PENDING] -> run_closed_loop_diagnostic\n');
end
fprintf('\n');

%% ========== PHASE EXP: DEEP COUNTERMEASURE EXPLORATION ==========
fprintf('> PHASE EXP: Deep Countermeasure Exploration (research extension)\n\n');

if RUN.explore_countermeasures
    fprintf('  [EXP] Running full countermeasure sweep (VERY HEAVY, ~75 min)...\n');
    explore_countermeasures;
end
if RUN.analyze_exploration_results
    fprintf('  [EXP-analysis] Post-hoc diagnosis (filters physically-invalid results)...\n');
    analyze_exploration_results;
end

fprintf('  [EXP] Pipeline status:\n');
if exist('data/countermeasure_exploration.mat','file')
    d = dir('data/countermeasure_exploration.mat');
    fprintf('      countermeasure_exploration.mat : READY (%s, %.0f MB)\n', d.date, d.bytes/1e6);
else
    fprintf('      countermeasure_exploration.mat : [PENDING] -> explore_countermeasures\n');
end
if exist('results/exploration_diagnosis.txt','file')
    fprintf('      exploration_diagnosis.txt      : READY -> results/exploration_diagnosis.txt\n');
else
    fprintf('      exploration_diagnosis.txt      : [PENDING] -> analyze_exploration_results\n');
end
fprintf('\n');

%% ========== PHASE KPI: PROPOSAL MEASUREMENT (section ה) ==========
fprintf('> PHASE KPI: Proposal KPI Measurement\n\n');

if RUN.measure_far
    fprintf('  [KPI4] Measuring FAR on non-hostile classes...\n');
    diagnose_far_measurement;
end
if RUN.measure_all_kpis
    fprintf('  [KPI] Aggregating all 5 proposal KPIs...\n');
    measure_all_kpis;
end

fprintf('  [KPI] Pipeline status:\n');
if exist('results/far_measurement.txt','file')
    d = dir('results/far_measurement.txt');
    fprintf('      far_measurement.txt        : READY (%s)\n', d.date);
else
    fprintf('      far_measurement.txt        : [PENDING] -> diagnose_far_measurement\n');
end
if exist('results/kpi3_measurement.txt','file')
    d = dir('results/kpi3_measurement.txt');
    fprintf('      kpi3_measurement.txt       : READY (%s)\n', d.date);
else
    fprintf('      kpi3_measurement.txt       : [PENDING] -> measure_kpi3_recovery_time\n');
end
if exist('results/kpi_summary.txt','file')
    d = dir('results/kpi_summary.txt');
    fprintf('      kpi_summary.txt            : READY (%s)\n', d.date);
else
    fprintf('      kpi_summary.txt            : [PENDING] -> measure_all_kpis\n');
end
fprintf('\n');

%% ========== PHASE D: DOCUMENTATION ==========
fprintf('> PHASE D: Documentation & Defense\n\n');
fprintf('  [D1] Project report (docx)...                      [PENDING]\n');
fprintf('  [D2] Defense presentation (pptx)...                [PENDING]\n\n');

%% ========== CHECKPOINT ==========
fprintf('========================================================\n');
fprintf(' CHECKPOINT - Post Rx_IQ fix (D18) full re-run: A5->A6->B1->B2->B3->C2->C3->C3d->KPI4->KPI\n');
fprintf(' Spectrograms/RSSI now reflect real swept AWGN noise (previously pre-AWGN, see DECISIONS.md D18)\n');
fprintf(' EXP/survivability unaffected (BER-only) -- not rerun here, still valid\n');
fprintf(' Outputs in results/, data/ | models in models/ | code on GitHub\n');
fprintf(' Full run log saved to: %s\n', log_filename);
fprintf('========================================================\n\n');

diary off;
fprintf('Diary closed. Open %s for the complete unclipped run transcript.\n', log_filename);