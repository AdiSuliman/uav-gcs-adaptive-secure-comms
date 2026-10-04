function on = threat_active(threat, act)
%THREAT_ACTIVE  Frames in which a threat counts as present: the labels of the dataset
%   (run_dataset_sweep.m), also used by every detector reading against them.
%   on = threat_active(threat, act): act is the share of each frame with the threat on
%   the air (extract_closed_loop_frames.m). A WLAN frame with less than 10% of it carrying
%   a packet, and an antenna-fault frame with the contact closed throughout, are clean
%   frames; every other threat counts in every frame.
switch threat
    case 'benign_interference', on = ~(act < 0.1);
    case 'antenna_fault',       on = act ~= 0;
    otherwise,                  on = true(size(act));
end
end
