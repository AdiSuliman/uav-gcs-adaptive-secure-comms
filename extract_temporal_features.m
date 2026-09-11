%% B2.5 — EXTRACT TEMPORAL FEATURES (Post-hoc, no re-simulation needed)
% Adds 3 temporal features per frame, computed within each
% (threat_class, SNR) sequence group — since run_dataset_sweep.m
% generates frames in-order per group, consecutive frames ARE a
% valid time-series proxy for that threat/SNR condition.
%
% New features:
%   var_rssi_10  — rolling variance of RSSI over last 10 frames
%   dber_dt      — first difference of BER (frame-to-frame change)
%   burst_ratio  — max/mean RSSI energy ratio in a 10-frame window
%
% Input:  data/spectrograms.mat  (spec.X, spec.Y, spec.feats [N×4])
% Output: data/spectrograms.mat  (OVERWRITTEN: spec.feats now [N×7])
%         spec.feat_names updated to include the 3 new names
%
% NOTE: Backs up the original file first (spectrograms_backup.mat)

close all; clc;
fprintf('=== B2.5: Extract Temporal Features ===\n\n');

%% 1. Load + backup
fprintf('Loading spectrograms.mat...\n');
S = load('data/spectrograms.mat');
spec = S.spec;

fprintf('Backing up original to data/spectrograms_backup.mat...\n');
save('data/spectrograms_backup.mat', 'spec', '-v7.3');

X = spec.X;                  % [128 128 1 N]
Y = spec.Y;                  % [N×1] categorical
feats = spec.feats;          % [N×4] : [snr, ber, rssi, plr]
feats(isnan(feats)) = 0;

N = size(X, 4);
fprintf('  %d frames loaded\n', N);

%% 2. Determine grouping key: (class, SNR) — frames within a group
%    were generated consecutively in run_dataset_sweep's inner loop,
%    so their ORIGINAL ORDER is a valid proxy for a time sequence.
snr_col = feats(:, 1);
rssi_col = feats(:, 3);
ber_col  = feats(:, 2);

snr_rounded = round(snr_col);  % group by nominal SNR point (0,2,4,6,8,10)
classes = categories(Y);
nClasses = numel(classes);
unique_snrs = unique(snr_rounded);

fprintf('  Grouping by %d classes × %d SNR levels\n', nClasses, numel(unique_snrs));

%% 3. Compute temporal features per group (preserving original index order)
var_rssi_10 = zeros(N, 1);
dber_dt     = zeros(N, 1);
burst_ratio = zeros(N, 1);

windowSize = 10;

for c = 1:nClasses
    for s = 1:numel(unique_snrs)
        mask = (Y == classes{c}) & (snr_rounded == unique_snrs(s));
        group_idx = find(mask);   % preserves original (generation) order

        if isempty(group_idx)
            continue;
        end

        g_rssi = rssi_col(group_idx);
        g_ber  = ber_col(group_idx);
        nG = numel(group_idx);

        for i = 1:nG
            w_start = max(1, i - windowSize + 1);
            window_rssi = g_rssi(w_start:i);

            % Rolling variance of RSSI (0 if window too small)
            if numel(window_rssi) >= 2
                var_rssi_10(group_idx(i)) = var(window_rssi);
            else
                var_rssi_10(group_idx(i)) = 0;
            end

            % First difference of BER
            if i > 1
                dber_dt(group_idx(i)) = g_ber(i) - g_ber(i-1);
            else
                dber_dt(group_idx(i)) = 0;
            end

            % Burst ratio: max/mean energy proxy from RSSI window
            if numel(window_rssi) >= 2 && mean(abs(window_rssi)) > 1e-8
                burst_ratio(group_idx(i)) = max(abs(window_rssi)) / mean(abs(window_rssi));
            else
                burst_ratio(group_idx(i)) = 1;  % neutral ratio for single-sample window
            end
        end
    end
end

fprintf('  Temporal features computed.\n');
fprintf('    var_rssi_10: mean=%.3f, std=%.3f\n', mean(var_rssi_10), std(var_rssi_10));
fprintf('    dber_dt:     mean=%.4f, std=%.4f\n', mean(dber_dt), std(dber_dt));
fprintf('    burst_ratio: mean=%.3f, std=%.3f\n', mean(burst_ratio), std(burst_ratio));

%% 4. Sanity check: reactive_jamming should show higher var_rssi_10 / burst_ratio
fprintf('\n  Sanity check (mean values per class):\n');
fprintf('  %-20s %12s %12s %12s\n', 'Class', 'var_rssi_10', 'dber_dt', 'burst_ratio');
for c = 1:nClasses
    m = (Y == classes{c});
    fprintf('  %-20s %12.3f %12.4f %12.3f\n', classes{c}, ...
        mean(var_rssi_10(m)), mean(dber_dt(m)), mean(burst_ratio(m)));
end

%% 5. Merge into feats matrix [N×7] and save
feats_extended = [feats, var_rssi_10, dber_dt, burst_ratio];
spec.feats = feats_extended;
spec.feat_names = [spec.feat_names(:)', {'var_rssi_10', 'dber_dt', 'burst_ratio'}];

fprintf('\nSaving updated spectrograms.mat (feats now [%d × %d])...\n', ...
    size(feats_extended, 1), size(feats_extended, 2));
save('data/spectrograms.mat', 'spec', '-v7.3');

d = dir('data/spectrograms.mat');
fprintf('Done. spectrograms.mat saved (%.1f MB)\n', d.bytes/1e6);
fprintf('\n=== B2.5 Complete ===\n');
fprintf('NEXT: Re-run prepare_data.m (now handles 7 features) then train_detector.m\n');