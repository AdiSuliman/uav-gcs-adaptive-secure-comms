%% EXTRACT_SPECTROGRAMS_SEQ - Phase B-exp: assemble sequence windows for CNN-LSTM
% Combines data/spectrograms.mat (per-frame spectrograms + 7 feats, from
% extract_spectrograms.m) with data/dataset_seq_index.mat (window frame
% indices, from build_sequence_index.m) into stacked sequence tensors.
% Does NOT recompute any spectrogram -- pure indexing/reshaping, fast.
%
% Input:  data/spectrograms.mat, data/dataset_seq_index.mat
% Output: data/spectrograms_seq.mat
%           X_seq     [128 x 128 x 1 x seq_len x N_seq] single
%           feats_seq [N_seq x seq_len x nFeat] double  (full temporal feature sequence)
%           Y_seq     [N_seq x 1] categorical

close all; clc;
fprintf('=== extract_spectrograms_seq: Assemble Sequence Tensors ===\n\n');

if ~exist('data/spectrograms.mat','file')
    error('data/spectrograms.mat not found. Run extract_spectrograms.m first.');
end
if ~exist('data/dataset_seq_index.mat','file')
    error('data/dataset_seq_index.mat not found. Run build_sequence_index.m first.');
end

fprintf('Loading data/spectrograms.mat and data/dataset_seq_index.mat...\n');
Sp = load('data/spectrograms.mat');  spec = Sp.spec;
Si = load('data/dataset_seq_index.mat'); dsi = Si.dataset_seq_index;

frame_idx  = dsi.frame_idx;      % [N_seq x seq_len], indices into spec.X(:,:,:, . )
seq_label  = dsi.label;          % [N_seq x 1]
class_names = dsi.class_names;

N_seq   = size(frame_idx, 1);
seq_len = size(frame_idx, 2);
nFeat   = size(spec.feats, 2);
img_size = spec.img_size;

fprintf('  N_seq=%d, seq_len=%d, nFeat=%d, img_size=%d\n', N_seq, seq_len, nFeat, img_size);

% Sanity: every index must be in range
max_idx = max(frame_idx(:));
if max_idx > size(spec.X,4)
    error('dataset_seq_index frame_idx (max=%d) exceeds spectrograms.mat frame count (%d). Was extract_spectrograms.m re-run with different frame ordering after build_sequence_index.m?', ...
        max_idx, size(spec.X,4));
end

%% ---- Assemble sequence tensors ----
X_seq     = zeros(img_size, img_size, 1, seq_len, N_seq, 'single');
feats_seq = zeros(N_seq, seq_len, nFeat, 'double');

fprintf('Assembling %d sequence windows...\n', N_seq);
for s = 1:N_seq
    idx = frame_idx(s, :);                       % [1 x seq_len] frame indices, in order
    X_seq(:,:,1,:,s)   = reshape(spec.X(:,:,1,idx), img_size, img_size, 1, seq_len);
    feats_seq(s, :, :) = spec.feats(idx, :);
    if mod(s,500)==0, fprintf('  %d/%d\n', s, N_seq); end
end

Y_seq = categorical(seq_label, 1:numel(class_names), class_names);

%% ---- Package + save ----
spec_seq.X_seq       = X_seq;
spec_seq.feats_seq   = feats_seq;
spec_seq.Y_seq        = Y_seq;
spec_seq.feat_names   = spec.feat_names;
spec_seq.class_names  = class_names;
spec_seq.img_size     = img_size;
spec_seq.seq_len      = seq_len;
spec_seq.meta         = dsi.meta;
spec_seq.meta.created = datestr(now);

if ~exist('data','dir'); mkdir('data'); end
save('data/spectrograms_seq.mat','spec_seq','-v7.3');
d = dir('data/spectrograms_seq.mat');

fprintf('\nDone. Saved data/spectrograms_seq.mat (%.1f MB)\n', d.bytes/1e6);
fprintf('  X_seq    : [%s]\n', strjoin(string(size(X_seq)), ' x '));
fprintf('  feats_seq: [%s]\n', strjoin(string(size(feats_seq)), ' x '));
fprintf('  Y_seq    : %d labels, %d classes\n', N_seq, numel(class_names));
fprintf('\nWindows per class:\n');
for c = 1:numel(class_names)
    fprintf('  %-22s %d\n', class_names{c}, sum(seq_label==c));
end
fprintf('\nNext: prepare_data_seq.m\n');