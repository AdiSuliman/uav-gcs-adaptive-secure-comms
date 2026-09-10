%% VISUALIZE_SPECTROGRAMS - Phase A6: Visual validation of threat signatures
% Loads data/dataset.mat, extracts one representative IQ frame per class
% (at the highest Eb/No = cleanest), computes its spectrogram, and plots a
% 7-panel grid. Purpose: confirm the 6 threats + clean have DISTINGUISHABLE
% spectral signatures BEFORE committing to full dataset + CNN training.

clear; close all; clc;

if ~exist('data/dataset.mat', 'file')
    error('data/dataset.mat not found. Run run_dataset_sweep.m first.');
end
fprintf('Loading dataset...\n');
L = load('data/dataset.mat');
ds = L.dataset;

S = load('params.mat');
p = S.params;
fs = p.symbol_rate * p.sps;    % IQ sample rate (4 MHz)

classes = ds.class_names;
nC = numel(classes);

% Spectrogram settings (tuned for 2064-sample frames)
win     = 128;                 % Hamming window length
novlp   = 64;                  % 50% overlap
nfft    = 256;                 % FFT length

% Pick the highest Eb/No present (cleanest — threat signature most visible)
snr_target = max(ds.snr);
fprintf('Using Eb/No = %.0f dB frames (cleanest).\n', snr_target);

figure('Name','A6 - Threat Spectral Signatures','Color','w', ...
    'Position',[80 80 1500 720]);

for c = 1:nC
    % Find first frame of this class at the target SNR
    idx = find(ds.label == c & ds.snr == snr_target, 1, 'first');
    if isempty(idx)
        idx = find(ds.label == c, 1, 'first');   % fallback: any SNR
    end
    iq = ds.iq{idx};

    % Spectrogram (centered, dB)
    subplot(2, 4, c);
    [Sxx, F, T] = spectrogram(iq, hamming(win), novlp, nfft, fs, 'centered');
    imagesc(T*1e6, F/1e6, 20*log10(abs(Sxx) + eps));
    axis xy;
    colormap(gca, 'turbo');
    title(strrep(classes{c}, '_', '\_'), 'FontWeight','bold');
    xlabel('Time (\mus)');
    ylabel('Freq (MHz)');
    clim([-40 20]);   % consistent color scale across all panels
end

% Shared colorbar in the 8th (empty) slot
subplot(2, 4, 8);
axis off;
cb = colorbar('Location','west');
cb.Label.String = 'Power (dB)';
clim([-40 20]);
colormap(gca, 'turbo');
text(0.5, 0.95, 'Eb/No', 'Units','normalized', 'HorizontalAlignment','center');
text(0.5, 0.88, sprintf('%.0f dB', snr_target), 'Units','normalized', ...
    'HorizontalAlignment','center','FontWeight','bold');

sgtitle('Threat Spectral Signatures (post-attack IQ, cleanest SNR)', ...
    'FontSize', 14, 'FontWeight', 'bold');

%% Save
if ~exist('results', 'dir'); mkdir('results'); end
saveas(gcf, 'results/A6_spectrogram_signatures.png');
fprintf('\nSaved figure to results/A6_spectrogram_signatures.png\n');
fprintf('Inspect: are the 7 signatures visually distinguishable?\n');
fprintf('  - jamming/reactive: broadband "fog" filling all frequencies\n');
fprintf('  - noise_burst: broadband but time-gated (patchy)\n');
fprintf('  - spoofing: doubled QPSK structure\n');
fprintf('  - none/path_loss/antenna_fault: clean QPSK, differing power/dropouts\n');