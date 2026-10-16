function [k, kf] = fused_class(probs, S, FM, N, classes)
%FUSED_CLASS  Class of every frame as the deployed monitor decides it (policy_monitor.m):
%   the temporal fusion over the last N frames of its own run (temporal_evidence.m,
%   fuse_classes.m), then the latched cause of a lost branch (onset_shape.m, latch_runs.m):
%   while it holds, a fused antenna_fault or airframe_shadowing reads that cause. Without a
%   fusion (FM empty) the frame's own output with the same latch (threshold 0). The
%   reading of KPI 1 (eval_detector.m).
%   probs    frames x classes detector probabilities
%   S        run, pos (position of the frame in its run), gain_ant (frames x antennas,
%            mean channel gain), feats_raw (frames x link features, link_features.m order)
%   FM, N    fusion model and window (data/fusion.mat, select_fusion.m)
%   classes  class names of the columns of probs
%   k        frames x 1 class index of the monitor
%   kf       frames x 1 class index of the fusion alone
pf = double(probs);
if ~isempty(FM)
    S.feat_names = link_features('names');
    pf = fuse_classes('apply', FM, fuse_classes('windows', S, pf, N));
end
[~, kf] = max(pf, [], 2);
pf = latch_runs(pf, S.run, S.pos, S.gain_ant, classes, onset_shape('threshold', FM));
[~, k] = max(pf, [], 2);
end
