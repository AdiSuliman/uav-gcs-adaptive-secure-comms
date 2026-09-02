%% RUN_AWGN_SWEEP - Validate the clean link against QPSK theory
% Phase A2: Sweep Eb/No, measure BER, compare to berawgn (theory).
% This script validates the Digital Twin engine before adding Rician (A3).
% If measured BER overlaps theory -> the link engine is verified and ready.

clear; close all; clc;

%% ---- Load parameters and model ----
if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;

modelName = 'UAV_GCS_Base_Link';
if ~bdIsLoaded(modelName)
    load_system(['models/' modelName '.slx']);
end
set_param(modelName, 'SimulationMode', 'normal');

EbNo_dB = p.EbNo_dB;              % sweep points
nPts    = numel(EbNo_dB);
ber_measured = zeros(1, nPts);

fprintf('\n=== AWGN BER Sweep (QPSK) ===\n');
fprintf('%6s %12s %12s\n', 'Eb/No', 'BER(meas)', 'BER(theory)');

%% ---- Sweep loop ----
for k = 1:nPts
    % Convert Eb/No -> SNR for the AWGN block (SNR mode)
    snr_dB = EbNo_dB(k) + 10*log10(p.bits_per_symbol);  % 1 sample/symbol: no sps term
    set_param([modelName '/AWGN'], 'SNR', num2str(snr_dB));

    % Run the model
    simOut = sim(modelName, ...
        'StopTime', num2str(10 * p.num_frames * p.frame_duration), ...
        'SimulationMode', 'normal');
    % Error Rate Calc outputs a running total, one row per frame:
    % [BER, numErrors, numBits]. Take the LAST row = final cumulative result.
    ber_mat = simOut.BER_out;
    final_errors = ber_mat(end, 2);
    final_bits   = ber_mat(end, 3);
    if final_bits > 0
        ber_measured(k) = final_errors / final_bits;
    else
        ber_measured(k) = NaN;
        warning('Eb/No=%.1f dB: no bits counted (StopTime too short?)', EbNo_dB(k));
    end
    % Flag statistically unreliable points (need ~100 errors for confidence)
    if final_errors < 100 && final_errors > 0
        fprintf('  (note: only %d errors at Eb/No=%.1f — point may be noisy)\n', ...
                final_errors, EbNo_dB(k));
    end

    % Theory for this Eb/No
    ber_theory_k = berawgn(EbNo_dB(k), 'psk', p.mod_order, 'nondiff');

    fprintf('%6.1f %12.3e %12.3e\n', EbNo_dB(k), ber_measured(k), ber_theory_k);
end

%% ---- Theory curve (smooth) ----
EbNo_fine = min(EbNo_dB):0.1:max(EbNo_dB);
ber_theory = berawgn(EbNo_fine, 'psk', p.mod_order, 'nondiff');

%% ---- Plot ----
figure('Name','AWGN BER Validation','Color','w');
semilogy(EbNo_fine, ber_theory, 'b-', 'LineWidth', 2); hold on;
semilogy(EbNo_dB, ber_measured, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
grid on;
xlabel('E_b/N_0 (dB)');
ylabel('Bit Error Rate (BER)');
title('QPSK over AWGN: Simulated vs. Theory');
legend('Theory (berawgn)', 'Simulated', 'Location', 'southwest');
ylim([1e-5 1]);

%% ---- Save results ----
if ~exist('results', 'dir'); mkdir('results'); end
saveas(gcf, 'results/A2_BER_validation.png');
save('results/A2_ber_sweep.mat', 'EbNo_dB', 'ber_measured');
fprintf('\nSaved: results/A2_BER_validation.png\n');
fprintf('Done. If red circles sit on the blue curve, the engine is verified.\n');