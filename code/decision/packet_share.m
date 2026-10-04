function s = packet_share(action, n)
%PACKET_SHARE  Share of a run's frames that one lost packet takes: the slack of the
%   packet-loss criterion (one packet above C.ratio_ok x the clean link's loss).
%   s = packet_share(action, n): action a configuration name or a cell array of them, n
%   the frames of the run. With fec_interleave a packet spans two frames, both carrying
%   its result (fec_packets.m): 2 of the 2 floor(n/2) frames that hold whole packets;
%   otherwise 1 of n. s has the size of action.
coded = contains(action, 'fec_interleave');
s = 1 / max(n, 1) * ones(size(coded));
s(coded) = 2 / max(2 * floor(n / 2), 2);
end
