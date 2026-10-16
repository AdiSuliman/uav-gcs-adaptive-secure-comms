function e = received_ebno(threat, ebno, actc, pl_db)
%RECEIVED_EBNO  Received Eb/N0 of every frame [dB].
%   e = received_ebno(threat, ebno, actc, pl_db): the configured Eb/N0 ebno less the path-loss
%   step pl_db on the frames where the threat's path-loss component is on the air; actc
%   (components x frames) the on-air share of every component of threat, in its order
%   (extract_closed_loop_frames.m, act_comp). Every other frame keeps ebno.
n = size(actc, 2);
e = ebno * ones(1, n);
k = find(strcmp(strsplit(lower(threat), '+'), 'path_loss'), 1);
if ~isempty(k) && size(actc, 1) >= k
    e = e - pl_db * (actc(k, :) > 0);
end
end
