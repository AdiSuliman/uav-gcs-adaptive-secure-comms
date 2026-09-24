%% BUILD_SEQUENCE_INDEX - Phase A5-seq: window dataset.mat frames into sequences for CNN-LSTM
% Groups frames into windows of `seq_len` CONSECUTIVE frames that share the
% same (label, level, snr) triple -- i.e. frames produced by the SAME
% Simulink sim() call in run_dataset_sweep.m. Because every sim() call there
% is single-threat/single-level/single-SNR, every frame inside one call is
% homogeneously labeled -- so windows built this way are NEVER mixed-label.
% (Proposal risk #7, "transition window labeling", does not apply to this
% dataset's construction -- threats never switch mid-run.)
%
% Also saves a run_id per window (which contiguous run it came from). With
% seq_stride < seq_len, consecutive windows within a run overlap in frames
% -- run_id lets prepare_data_seq.m split by RUN (not by window) so no
% frame ever appears in both train and test.
%
% Runs on the EXISTING data/dataset.mat -- does NOT re-run any Simulink sim.
%
% Input:  data/dataset.mat            (from run_dataset_sweep.m, unchanged)
% Output: data/dataset_seq_index.mat  (frame-index windows, not spectrograms yet)
%
% Next step: extract_spectrograms_seq.m turns these index windows into
% actual [128x128x1xseq_len] spectrogram sequences (needs data/spectrograms.mat).

close all; clc;
fprintf('=== A5-seq: Build Sequence Index ===\n\n');

if ~exist('params.mat', 'file')
    error('params.mat not found. Run init_params.m first.');
end
S = load('params.mat');
p = S.params;

if ~isfield(p, 'seq_len') || ~isfield(p, 'seq_stride')
    error(['params.seq_len / params.seq_stride not found. ' ...
           'Update init_params.m with the SEQUENCE WINDOWING section and rerun it first.']);
end
seq_len    = p.seq_len;
seq_stride = p.seq_stride;

if ~exist('data/dataset.mat', 'file')
    error('data/dataset.mat not found. Run run_dataset_sweep.m first.');
end
fprintf('Loading data/dataset.mat...\n');
D = load('data/dataset.mat');
ds = D.dataset;

N = numel(ds.label);
label = ds.label(:);
level = ds.level(:);
snr   = ds.snr(:);

fprintf('  %d frames loaded | seq_len=%d, stride=%d\n', N, seq_len, seq_stride);

%% ---- Find contiguous same-(label,level,snr) run boundaries ----
same_as_prev = false(N,1);
for i = 2:N
    same_as_prev(i) = isequaln(label(i),label(i-1)) && ...
                       isequaln(level(i),level(i-1)) && ...
                       isequaln(snr(i),  snr(i-1));
end
run_id = cumsum(~same_as_prev);   % increments at every run boundary
n_runs = run_id(end);

fprintf('  %d contiguous (label,level,snr) runs found\n', n_runs);

%% ---- Slide windows (stride < seq_len => overlap) within each run ----
seq_frame_idx_c = {};
seq_label   = [];
seq_level   = [];
seq_snr     = [];
seq_run_id  = [];   % NEW: which run this window came from (for run-level split)
n_dropped_runs = 0;

for r = 1:n_runs
    run_idx = find(run_id == r);
    n_in_run = numel(run_idx);
    if n_in_run < seq_len
        n_dropped_runs = n_dropped_runs + 1;
        continue;   % run too short for even one window -- skipped, see warning below
    end
    starts = 1:seq_stride:(n_in_run - seq_len + 1);
    for st = starts
        idx_window = run_idx(st : st+seq_len-1);
        seq_frame_idx_c{end+1} = idx_window(:)';        %#ok<AGROW>
        seq_label(end+1)       = label(idx_window(1));  %#ok<AGROW>
        seq_level(end+1)       = level(idx_window(1));  %#ok<AGROW>
        seq_snr(end+1)         = snr(idx_window(1));    %#ok<AGROW>
        seq_run_id(end+1)      = r;                      %#ok<AGROW>
    end
end

seq_frame_idx = cell2mat(seq_frame_idx_c');  % [N_seq x seq_len], indices into dataset.mat arrays
seq_label     = seq_label(:);
seq_level     = seq_level(:);
seq_snr       = seq_snr(:);
seq_run_id    = seq_run_id(:);
N_seq = size(seq_frame_idx, 1);

if n_dropped_runs > 0
    fprintf('  WARNING: %d/%d runs had fewer than seq_len=%d frames and were skipped entirely.\n', ...
        n_dropped_runs, n_runs, seq_len);
    fprintf('           If this is a large fraction, lower seq_len or raise frames_per_config in run_dataset_sweep.m.\n');
end

fprintf('  Built %d sequence windows (stride=%d, non-overlap=%d) across %d runs\n', ...
    N_seq, seq_stride, seq_stride>=seq_len, n_runs - n_dropped_runs);

%% ---- Balance check per class ----
fprintf('\nSequence windows per class:\n');
for c = 1:numel(ds.class_names)
    fprintf('  %-22s %d\n', ds.class_names{c}, sum(seq_label==c));
end

%% ---- Save ----
dataset_seq_index = struct();
dataset_seq_index.frame_idx   = seq_frame_idx;   % [N_seq x seq_len]
dataset_seq_index.label       = seq_label;
dataset_seq_index.level       = seq_level;
dataset_seq_index.snr         = seq_snr;
dataset_seq_index.run_id      = seq_run_id;      % NEW: [N_seq x 1], for run-level split
dataset_seq_index.class_names = ds.class_names;
dataset_seq_index.meta.seq_len    = seq_len;
dataset_seq_index.meta.seq_stride = seq_stride;
dataset_seq_index.meta.source_N   = N;
dataset_seq_index.meta.n_runs     = n_runs;
dataset_seq_index.meta.created    = datestr(now);

save('data/dataset_seq_index.mat', 'dataset_seq_index', '-v7.3');
fprintf('\nSaved data/dataset_seq_index.mat (%d windows x %d frames, %d runs)\n', N_seq, seq_len, n_runs);
fprintf('Next: extract_spectrograms_seq.m (needs data/spectrograms.mat)\n');