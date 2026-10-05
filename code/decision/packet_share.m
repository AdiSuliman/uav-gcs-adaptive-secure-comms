function s = packet_share(action, fer, Q)
%PACKET_SHARE  Share of a run's packets that one loss event takes in that run: the slack
%   of the packet-loss criterion (one event above C.ratio_ok x the clean link's loss).
%   s = packet_share(action, fer, Q): action a configuration name, fer the run's frames in
%   order (1 when the frame's packet is lost), Q the frames of a coded packet's codeword
%   (default C.fec_frames). Without the code a frame is a packet and an event loses one:
%   1 of the n frames. With fec_interleave a packet ends on every frame pair, both frames
%   carrying its result (fec_packets.m), and a frame the decoder cannot repair lies in the
%   codewords of Q/2 consecutive packets: an event is a run of consecutive lost packets
%   (cyclic, as the run's pairs are), at most Q/2 of them; the slack is the run's longest
%   such event, at least one packet, of its floor(n/2) packets. A count of packets, the
%   same rule for every run length.
if nargin < 3 || isempty(Q), Q = decision_config().fec_frames; end
fer = double(fer(:)' > 0.5);
n = numel(fer);
if ~contains(action, 'fec_interleave')
    s = 1 / max(n, 1);
    return
end
np = floor(n / 2);
s = 1 / max(np, 1);
if np == 0, return; end
k = fer(2:2:2*np);
if all(k), s = min(Q / 2, np) / np; return; end
k = circshift(k, -find(~k, 1));                         % start after a delivered packet
e = diff([0, k, 0]);
L = max([find(e == -1) - find(e == 1), 1]);              % longest run of lost packets
s = min(L, Q / 2) / np;
end
