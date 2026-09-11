%% MAIN - Master Execution & Status Pipeline
% UAV-GCS Adaptive Secure Communications System
% Orchestrates Phase A (Link+Threats+Dataset) -> B (Detection) -> C (Recovery) -> D (Report)
% Author: Adi Suliman, Bar Dvir Hassan
% Last Updated: 2026-09-11 (Phase B: temporal features + hybrid detector)
%
% Toggle the RUN flags below (true/false). They execute in the order listed.
% Light stages (A0-A4) are fast; heavy stages (A5-A6, B2) take minutes — leave
% them false unless you want to regenerate.

clear; close all; clc;

%% ========== EXECUTION FLAGS (in execution order) ==========
RUN.init                 = true;    % A0 : regenerate params.mat
RUN.validate_A           = true;    % A1-A3: build + validate AWGN & Rician (fast)
RUN.check_A4             = true;    % A4 : build threat model + sanity BER (fast)
RUN.build_dataset        = false;   % A5 : run_dataset_sweep      (HEAVY ~5 min)
RUN.extract_spectrograms = false;   % A6 : extract_spectrograms   (HEAVY ~2 min)

RUN.temporal_features    = false;   % B2.5: extract_temporal_features (ONE-TIME, fast)
RUN.prepare_data         = false;   % B1  : prepare_data          (fast)
RUN.train_detector       = false;   % B2  : train_detector        (HEAVY ~5 min GPU)
RUN.eval_detector        = true;   % B3  : eval_detector         (fast)

fprintf('\n');
fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A: Link+Threats+Data | B: Detection | C: Recovery | D: Report\n');
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
    fprintf('       A1 AWGN : BER=%.3e | theory=%.3e | ratio=%.2fx\n', ...
        berA1, berTheory, berA1/berTheory);

    fprintf('  [A3] Building + validating Rician link (K=%.0fdB, fd=%.0fHz)...\n', ...
        p.rician_k, p.fd_max);
    build_rician_model;
    berA3 = quick_ber('UAV_GCS_Rician_Link');
    fprintf('       A3 Rician: BER=%.3e | degradation=%.2fx (fading penalty)\n', ...
        berA3, berA3/berTheory);
end

if RUN.check_A4
    fprintf('  [A4] Building + checking threat model (active: %s)...\n', p.active_threat);
    build_threat_model;
    berA4 = quick_ber('UAV_GCS_Threat_Link');
    fprintf('       A4 Threat: BER=%.3e under %s (JSR=%.0fdB)\n', ...
        berA4, p.active_threat, p.jsr_db);
end

if RUN.build_dataset
    fprintf('  [A5] Generating multi-JSR dataset (HEAVY ~5 min)...\n');
    run_dataset_sweep;
end

if RUN.extract_spectrograms
    fprintf('  [A6] Extracting spectrograms (HEAVY ~2 min)...\n');
    extract_spectrograms;
end

% A5-A6 dataset status (always reported)
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
fprintf('> PHASE B: Detection Network (CNN + scalar hybrid)\n\n');

if RUN.temporal_features
    fprintf('  [B2.5] Extracting temporal features (var_rssi_10, dber_dt, burst_ratio)...\n');
    extract_temporal_features;
end

if RUN.prepare_data
    fprintf('  [B1] Preparing data (stratified split 80/10/10)...\n');
    prepare_data;
end

if RUN.train_detector
    fprintf('  [B2] Training hybrid CNN+scalar detector...\n');
    train_detector;
end

if RUN.eval_detector
    fprintf('  [B3] Evaluating on test set (confusion, F1, accuracy-vs-SNR)...\n');
    eval_detector;
end

% Phase B status (always reported)
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
fprintf('> PHASE C: Closed-Loop Adaptive Recovery (Threat Response)\n\n');
fprintf('  [C1] Rule-based countermeasure policy...           [PENDING]\n');
fprintf('  [C2] DQN agent (state=metrics, reward=BER recovery)[PENDING]\n');
fprintf('  [C3] Adaptive Link Recovery (detect+decide+act)... [PENDING]\n');
fprintf('  [C4] Closed-loop sim (threat -> recover)...         [PENDING]\n');
fprintf('  [C5] Interactive dashboard (2D)...                 [PENDING]\n');
fprintf('  [C6] Regime map (GREEN/YELLOW/RED)...              [PENDING]\n\n');

%% ========== PHASE D: DOCUMENTATION ==========
fprintf('> PHASE D: Documentation & Defense\n\n');
fprintf('  [D1] Project report (docx)...                      [PENDING]\n');
fprintf('  [D2] Defense presentation (pptx)...                [PENDING]\n\n');

%% ========== CHECKPOINT ==========
fprintf('========================================================\n');
fprintf(' CHECKPOINT - Phase A+B complete | next: Phase C (closed-loop recovery)\n');
fprintf(' Outputs in results/, data/ | models in models/ | code on GitHub\n');
fprintf('========================================================\n\n');