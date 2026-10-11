function on = threat_active(threat, act, pos, tw)
%THREAT_ACTIVE  Frames in which a threat counts as present: the labels of the dataset
%   (run_dataset_sweep.m), also used by every detector reading against them.
%   on = threat_active(threat, act): act is the share of each frame with the threat on
%   the air (extract_closed_loop_frames.m; for a combination the union over its
%   components). A WLAN frame with less than 10% of it carrying a packet, a frame with
%   less than 10% of it inside the sweeping jammer's window, an airframe-shadowing frame
%   whose attitude hides no antenna and a path-loss frame before the step's onset are clean
%   frames; every other threat counts in every frame. A combination with a gated component
%   counts by the same 10% (its union is 1 while a component that is not gated is on).
%   on = threat_active(threat, act, pos, tw): the frames of one run at positions pos; a
%   path-loss step counts from its onset (the first frame with act > 0) while its causal
%   window of tw frames (link_features.m) still holds a frame before the onset, at most
%   tw - 2 frames after it: the step is then inside the window (var_rssi, dlog_ber and plr
%   see it). A loss that has been there longer is the same link as a longer range, so its
%   frames are clean frames for the detector (the decision layer's drop alarm follows the
%   step, policy_monitor.m).
if any(ismember(strsplit(threat, '+'), {'benign_interference', 'sweeping_jammer'}))
    on = ~(act < 0.1);
else
    on = act ~= 0;
end
if nargin >= 4 && strcmp(threat, 'path_loss') && any(on)
    t0 = min(pos(on));
    on = on & pos - t0 < tw - 1;
end
end
