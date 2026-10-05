function s = packet_share(action, n, Q)
%PACKET_SHARE  Share of a run's frames that one loss event takes: the slack of the
%   packet-loss criterion (one event above C.ratio_ok x the clean link's loss).
%   s = packet_share(action, n, Q): action a configuration name or a cell array of them, n
%   the frames of the run, Q the frames of a coded packet's codeword (default
%   C.fec_frames). Without the code one lost frame is one lost packet: 1 of n. With
%   fec_interleave one packet per frame pair carries its result on both frames
%   (fec_packets.m), and a frame the decoder cannot repair costs the Q/2 packets whose
%   codewords share it: Q of the 2 floor(n/2) frames that hold whole packets. s has the
%   size of action.
if nargin < 3 || isempty(Q), Q = decision_config().fec_frames; end
coded = contains(action, 'fec_interleave');
s = 1 / max(n, 1) * ones(size(coded));
s(coded) = Q / max(2 * floor(n / 2), 2);
end
