function on = threat_active(threat, act, pos, tw, act_idle)
%THREAT_ACTIVE  Frames in which a threat counts as present: the labels of the dataset
%   (run_dataset_sweep.m), also used by every detector reading against them.
%   on = threat_active(threat, act): act is the share of each frame with the threat on the
%   air (extract_closed_loop_frames.m; for a combination the union over its components). A
%   WLAN frame with less than 10% of it carrying a packet, a frame with less than 10% of it
%   inside the sweeping jammer's window, an airframe-shadowing frame whose attitude hides no
%   antenna by 5 dB or more (shadow_frame.m), an antenna-fault frame before its connector
%   opens and a path-loss frame before the step's onset are clean frames; every other
%   threat counts in every frame. A combination with a gated component counts by the same
%   10% (its union is 1 while a component that is not gated is on).
%   on = threat_active(threat, act, pos, tw): the frames of one run at positions pos; a
%   path-loss step counts from its onset (the first frame with act > 0) while its causal
%   window of tw frames (link_features.m) still holds a frame before the onset, at most
%   tw - 2 frames after it: the step is then inside the window (var_rssi, dlog_ber and plr
%   see it). A loss that has been there longer is the same link as a longer range, so its
%   frames are clean frames for the detector (the decision layer's drop alarm follows the
%   step, policy_monitor.m).
%   on = threat_active(threat, act, pos, tw, act_idle): per decision cycle. With idle
%   sensing the receiver observes the whole cycle, the idle time before the frame
%   (idle_rssi.m) and the frame: a gated threat (the WLAN, the sweeping jammer, a
%   combination holding one) counts in a cycle while it is on the air anywhere in it,
%   act > 0 or act_idle > 0 (labels by what is on the air, proposal mitigation 3, now over
%   the decision cycle). act_idle NaN (the first frame of a run: no idle time before it)
%   leaves the frame alone. pos and tw may be empty.
if nargin < 3, pos = []; end
if nargin < 4, tw = []; end
gated = any(ismember(strsplit(threat, '+'), {'benign_interference', 'sweeping_jammer'}));
if gated && nargin >= 5 && ~isempty(act_idle)
    ai = reshape(act_idle, size(act)); ai(isnan(ai)) = 0;
    on = act > 0 | ai > 0;
elseif gated
    on = ~(act < 0.1);
else
    on = act ~= 0;
end
if ~isempty(pos) && ~isempty(tw) && strcmp(threat, 'path_loss') && any(on)
    t0 = min(pos(on));
    on = on & pos - t0 < tw - 1;
end
end
