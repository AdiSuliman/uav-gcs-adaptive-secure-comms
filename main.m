%% MAIN - Master Execution Script
% UAV-GCS Adaptive Secure Communications System
% Sequential execution: Phase A (Link+Threats) → B (Detection) → C (Closed-Loop) → D (Report)
% Author: Adi Suliman, Bar Dvir Hassan
% Last Updated: 2026-09-05

clear all; close all; clc;

fprintf('\n');
fprintf('========================================================\n');
fprintf('  UAV-GCS ADAPTIVE SECURE COMMS - MASTER PIPELINE\n');
fprintf('  A: Link+Threats | B: Detection | C: Closed-Loop | D: Report\n');
fprintf('========================================================\n\n');

%% ========== PHASE A: LINK MODEL + THREAT INJECTION ==========
fprintf('> PHASE A: Link Model + Threat Injection (Dataset Generation)\n\n');

% A0-A3: Initialize parameters and build baseline Rician model
fprintf('  [A0-A3] Initializing parameters and building Rician baseline...\n');
init_params;                            % Generate params.mat
p_check = load('params.mat').params;    % load params for reporting in main
build_rician_model;                     % Build Rician baseline (1.43x degradation)
fprintf('  Baseline ready: Rician K=10dB, fd=160Hz\n\n');

% A4: Threat injection (Jamming first; more threats added incrementally)
fprintf('  [A4] Threat injection (active: %s)...\n', p_check.active_threat);
build_threat_model;                     % Build UAV_GCS_Threat_Link.slx
out_threat = sim('UAV_GCS_Threat_Link');
ber_threat = out_threat.get('BER_out');
ber_t = ber_threat(end, :);
fprintf('  Threat model ran: BER=%.4e (%d/%d bits) under %s, JSR=%.0f dB\n\n', ...
    ber_t(1), ber_t(2), ber_t(3), p_check.active_threat, p_check.jsr_db);

% A5-A6: Dataset generation with metrics logging
fprintf('  [A5-A6] Dataset generation with link metrics (RSSI, BER, SNR, PLR)...\n');
fprintf('       [PENDING] run_dataset_sweep.m\n\n');

%% ========== PHASE B: DETECTION NETWORK (OFFLINE) ==========
fprintf('> PHASE B: Detection Network Training (Offline)\n\n');
fprintf('  [B1] Loading and preprocessing dataset...       [PENDING]\n');
fprintf('  [B2] Training CNN/LSTM detection network...      [PENDING]\n');
fprintf('  [B3] Evaluating: accuracy-vs-SNR, confusion, F1... [PENDING]\n\n');

%% ========== PHASE C: CLOSED-LOOP ADAPTIVE RECOVERY ==========
fprintf('> PHASE C: Closed-Loop Adaptive Recovery (Online)\n\n');
fprintf('  [C1] Rule-based decision policy...               [PENDING]\n');
fprintf('  [C2] Deep Q-Network (DQN) agent...               [PENDING]\n');
fprintf('  [C3] Adaptive link recovery module...            [PENDING]\n');
fprintf('  [C4] Closed-loop: Detect -> Decide -> Recover... [PENDING]\n');
fprintf('  [C5] Interactive dashboard...                    [PENDING]\n');
fprintf('  [C6] Regime map (recoverable vs unrecoverable)... [PENDING]\n\n');

%% ========== PHASE D: DOCUMENTATION & DEFENSE ==========
fprintf('> PHASE D: Documentation & Defense Preparation\n\n');
fprintf('  [D1] Generating project report (docx)...         [PENDING]\n');
fprintf('  [D2] Preparing defense presentation (pptx)...    [PENDING]\n\n');

%% ========== COMPLETION ==========
fprintf('========================================================\n');
fprintf(' EXECUTION CHECKPOINT - current stage: A4 (threat injection)\n');
fprintf(' Outputs in results/ | models in models/ | code on GitHub\n');
fprintf('========================================================\n\n');