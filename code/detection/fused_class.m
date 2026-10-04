function k = fused_class(probs, S, FM, N)
%FUSED_CLASS  Class of every frame as the deployed detector decides it: the temporal
%   fusion over the last N frames of its own run (temporal_evidence.m, fuse_classes.m),
%   the reading of policy_monitor.m; without a fusion (FM empty) the frame's own output.
%   probs  frames x classes detector probabilities
%   S      run, pos (position of the frame in its run), gain_ant (frames x antennas,
%          mean channel gain), feats_raw (frames x link features, link_features.m order)
%   FM, N  fusion model and window (data/fusion.mat, select_fusion.m)
%   k      frames x 1 class index
if isempty(FM)
    [~, k] = max(probs, [], 2);
    return;
end
S.feat_names = link_features('names');
[~, k] = fuse_classes('apply', FM, fuse_classes('windows', S, double(probs), N));
end
