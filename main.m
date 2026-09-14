%% MAIN - Master Execution & Status Pipeline
% UAV-GCS Adaptive Secure Communications System
% Orchestrates Phase A (Link+Threats+Dataset) -> B (Detection) -> C (Recovery) -> D (Report)
% Author: Adi Suliman, Bar Dvir Hassan
% Last Updated: 2026-09-13 (8-threat expansion, real DQN reward, full diary logging)
%פ שרצ
% Toggle the RUN flags below (true/false). They execute in the order listed.
% Light stages are fast; heavy stages (A5-A6, B2, C2, explore_countermeasures)
% take minutes to over an hour -- leave them false unless regenerating.
%
% COMMAND WINDOW LOGGING: every called script starts with close all/clc, which
% would normally wipe out everything printed by earlier stages. This is solved
% with MATLAB's `diary` command: it logs EVERYTHING printed to the Command
% Window into a text file, completely independent of clc (clc only clears what
% is VISIBLE on screen -- it never touches the diary log). So even though the
% screen itself still gets cleared between stages, the log file accumulates
% the full, uninterrupted transcript of the entire run. Open logs/run_*.txt
% after running to get the complete output, instead of relying on scrollback.

clear; close all; clc;

%% ========== LOGGING SETUP (diary — survives all internal clc calls) ==========
if ~exist('logs', 'dir'), mkdir('logs'); end
log_filename = sprintf('logs/run_%s.txt', datestr(now, 'yyyymmdd_HHMMSS'));
diary(log_filename);
diary on;
fprintf('=== Logging full run to: %s ===\n', log_filename);
fprintf('(This file will contain EVERYTHING printed below, even across clc calls.)\n\n');

%% ========== EXECUTION FLAGS (in execution order) ==========
RUN.init                        = false;    % A0 : regenerate params.mat
RUN.validate_A                  = false;    % A1-A3: build + validate AWGN & Rician (fast)
RUN.check_A4                    = false;    % A4 : build threat model + sanity BER (fast)
RUN.build_dataset               = false;   % A5 : run_dataset_sweep (8 threats)     (HEAVY ~8 min) >> ONE-TIME
RUN.extract_spectrograms        = false;   % A6 : extract_spectrograms              (HEAVY ~3 min) >> ONE-TIME

RUN.temporal_features           = false;   % B2.5: extract_temporal_features        (fast) >> ONE-TIME
RUN.prepare_data                = false;   % B1  : prepare_data                     (fast) >> ONE-TIME
RUN.train_detector              = false;   % B2  : train_detector (9-class CNN)     (HEAVY ~7 min GPU) >> ONE-TIME
RUN.eval_detector               = false;    % B3  : eval_detector                    (fast, safe to leave true)

RUN.train_dqn                   = false;   % C2  : train_dqn (real reward table)    (HEAVY ~5 min) >> ONE-TIME
RUN.run_closed_loop             = false;   % C3  : run_closed_loop_with_detector    (HEAVY ~4 min, 8 threats)
RUN.run_closed_loop_diagnostic  = true;   % C3d : full diagnostics + timing         (HEAVY ~4 min, 8 threats)

RUN.explore_countermeasures     = false;   % EXP : deep countermeasure sweep         (VERY HEAVY ~75 min) >> RUN RARELY
RUN.analyze_exploration_results = false;   % EXP-analysis: post-hoc diagnosis        (fast, needs EXP output first)

fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A: Link+Threats+Data | B: Detection | C: Recovery | EXP: Deep Exploration\n');
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
    fprintf('  [A5] Generating multi-JSR dataset, 8 threats (HEAVY ~8 min)...\n');
    run_dataset_sweep;
end

if RUN.extract_spectrograms
    fprintf('  [A6] Extracting spectrograms (HEAVY ~3 min)...\n');
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

%% ========== PHASE B: DETECTION (OFFLINE) ==========
fprintf('> PHASE B: Detection Network (CNN + scalar hybrid, 9 classes)\n\n');

if RUN.temporal_features
    fprintf('  [B2.5] Extracting temporal features...\n');
    extract_temporal_features;
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

%% ========== PHASE C: CLOSED-LOOP RECOVERY (ONLINE) ==========
fprintf('> PHASE C: Closed-Loop Adaptive Recovery (8 threats)\n\n');
fprintf('  [C1] Rule-based countermeasure policy...           READY (rule_based_policy.m)\n');

if RUN.train_dqn
    fprintf('  [C2] Training DQN agent (real threat-specific reward table)...\n');
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

%% ========== PHASE D: DOCUMENTATION ==========
fprintf('> PHASE D: Documentation & Defense\n\n');
fprintf('  [D1] Project report (docx)...                      [PENDING]\n');
fprintf('  [D2] Defense presentation (pptx)...                [PENDING]\n\n');

%% ========== CHECKPOINT ==========
fprintf('========================================================\n');
fprintf(' CHECKPOINT - Phase A+B+C1+C2+C3 complete (8 threats) | EXP available on demand\n');
fprintf(' Outputs in results/, data/ | models in models/ | code on GitHub\n');
fprintf(' Full run log saved to: %s\n', log_filename);
fprintf('========================================================\n\n');

diary off;
fprintf('Diary closed. Open %s for the complete unclipped run transcript.\n', log_filename);