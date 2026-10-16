function S = frame_labels(S)
%FRAME_LABELS  A split with the frame rule's labels as Y: threat_active.m without the idle
%   time (run_dataset_sweep.m, label_frame), what the frame itself holds. The per-frame
%   network and its unknown-threat models see the frame and its link-feature window only,
%   so they train, stop early and fit on these labels; the per-cycle labels (Y) stay with
%   the fusion and every reading of the system's decision.
%   S  a split of data/splits.mat or data/splits_fresh.mat with Y_frame
if ~isfield(S, 'Y_frame') || isempty(S.Y_frame)
    error('frame_labels:missing', ['the split has no frame-rule labels (Y_frame): run run_dataset_sweep, ' ...
        'extract_spectrograms and prepare_data']);
end
S.Y = S.Y_frame;
end
