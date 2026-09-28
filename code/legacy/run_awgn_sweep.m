%% RUN_AWGN_SWEEP - Validate the clean link with RRC pulse shaping
% Phase A2: Sweep Eb/No, measure BER offline with DELAY-SCAN alignment.
% finddelay is unreliable in multirate+RRC (returns wrong delay -> ISI floor).
% Instead we scan delays and pick the BER-minimizing one (= timing recovery).

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

EbNo_dB = p.EbNo_dB;
nPts    = numel(EbNo_dB);
ber_measured = zeros(1, nPts);
maxDelay = 60;   % bits: scan range for RRC group-delay alignment

fprintf('\n=== AWGN BER Sweep (QPSK with RRC, sps=%d) ===\n', p.sps);
fprintf('%6s %12s %12s %10s\n', 'Eb/No', 'BER(meas)', 'BER(theory)', 'Delay');

%% ---- Sweep loop ----
for k = 1:nPts
    % SNR + SignalPower corrected for RRC oversampling
    snr_dB = EbNo_dB(k) + 10*log10(p.bits_per_symbol) - 10*log10(p.sps);
    set_param([modelName '/AWGN'], ...
        'SNR', num2str(snr_dB), ...
        'SignalPower', num2str(1/p.sps));

    % Run the simulation
    simOut = sim(modelName, ...
        'StopTime', num2str(10 * p.num_frames * p.frame_duration), ...
        'SimulationMode', 'normal');

    % Extract bit streams (handle 3D array [N x 1 x frames] or timeseries)
    tx_raw = simOut.get('tx_bits_out');
    rx_raw = simOut.get('rx_bits_out');
    if isa(tx_raw, 'timeseries')
        tx = double(squeeze(tx_raw.Data));
        rx = double(squeeze(rx_raw.Data));
    else
        tx = double(squeeze(tx_raw));
        rx = double(squeeze(rx_raw));
    end
    tx = tx(:);  rx = rx(:);

    % --- DELAY-SCAN alignment: pick the delay giving minimum BER ---
    bestBER = 1; bestD = 0;
    for d = 0:maxDelay
        L = min(numel(tx) - d, numel(rx) - d);
        if L < 100, continue; end
        t = tx(1:L);
        r = rx(d+1 : d+L);
        b = mean(t ~= r);
        if b < bestBER
            bestBER = b;
            bestD   = d;
        end
    end

    ber_measured(k) = bestBER;
    ber_theory_k = berawgn(EbNo_dB(k), 'psk', p.mod_order, 'nondiff');
    fprintf('%6.1f %12.3e %12.3e %10d\n', EbNo_dB(k), ber_measured(k), ber_theory_k, bestD);
end

%% ---- Plotting ----
EbNo_fine = min(EbNo_dB):0.1:max(EbNo_dB);
ber_theory = berawgn(EbNo_fine, 'psk', p.mod_order, 'nondiff');

figure('Name','AWGN BER Validation (Multirate)','Color','w');
semilogy(EbNo_fine, ber_theory, 'b-', 'LineWidth', 2); hold on;
semilogy(EbNo_dB, ber_measured, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
grid on;
xlabel('E_b/N_0 (dB)');
ylabel('Bit Error Rate (BER)');
title(sprintf('QPSK over AWGN (RRC sps=%d): Simulated vs. Theory', p.sps));
legend('Theory (berawgn)', 'Simulated', 'Location', 'southwest');
ylim([1e-5 1]);

%% ---- Save results ----
if ~exist('results', 'dir'); mkdir('results'); end
saveas(gcf, 'results/A2_BER_multirate_validation.png');
save('results/A2_ber_sweep.mat', 'EbNo_dB', 'ber_measured');
fprintf('\nValidation complete. Measured points should now sit on the theory curve.\n');