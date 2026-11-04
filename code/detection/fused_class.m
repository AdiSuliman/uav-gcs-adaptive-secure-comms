function [k, kf] = fused_class(probs, S, FM, N, classes)
%FUSED_CLASS  Class of every frame as the deployed monitor decides it (policy_monitor.m):
%   the temporal fusion over the last N frames of its own run (temporal_evidence.m,
%   fuse_classes.m), then the latched cause of a lost branch (onset_shape.m, latch_runs.m):
%   while it holds, a fused antenna_fault or airframe_shadowing reads that cause. With the
%   latch off (onset_shape('on', FM), chosen on validation) the monitor's class is the fused
%   class. Without a fusion (FM empty) the frame's own output with the latch (threshold 0).
%   The reading of KPI 1 (eval_detector.m). It leaves out the unknown-threat override the
%   monitor applies at decision time (policy_monitor.m: PP.maha_thr, PP.unk_mode).
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
    pf = fuse_classes('apply', FM, fuse_classes('windows', S, pf, N, fuse_classes('cues', FM)));
end
[~, kf] = max(pf, [], 2);
k = kf;
if onset_shape('on', FM)
    [~, k] = max(latch_runs(pf, S.run, S.pos, S.gain_ant, classes, onset_shape('threshold', FM)), [], 2);
end
end
