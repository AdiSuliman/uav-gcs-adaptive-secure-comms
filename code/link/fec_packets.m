function [ber, fer, crcf, map] = fec_packets(tx_al, rx_al, iq, p, nf, ers, rel)
%FEC_PACKETS  Decoded result of every frame of a run with fec_interleave.
%   [ber, fer, crcf, map] = fec_packets(tx_al, rx_al, iq, p, nf, ers, rel)
%   tx_al, rx_al  transmitted and received channel bits, aligned per frame
%   iq            received samples of one antenna, samples x frames
%   ers           frames the receiver flags unreliable (1 x nf, logical; default none):
%                 every coded bit they carry enters the decoder as an erasure
%   rel           reliability of every received channel bit, aligned with rx_al: the
%                 magnitude of its log-likelihood ratio (extract_closed_loop_frames.m);
%                 default 1, hard decisions
%   One codeword per command packet of p.frame_length bits (1000 + 32 CRC): the packet and
%   the code's 6 tail bits through the rate-1/2 convolutional code (K = 7, generators
%   [171 133] octal), 12 coded bits punctured to 2 x 1032, interleaved and spread evenly
%   over Q = p.fec_frames frames, Q/2 frame pairs. One packet per frame pair, as one packet
%   per two uncoded frames: packet k ends on pair k (frames 2k-1, 2k) and starts on pair
%   k - Q/2 + 1, so every frame carries 2 x 1032 / Q coded bits of each of Q/2 packets
%   (Q = 4: a quarter of the packet that ends on its pair and a quarter of the next one),
%   on fixed bit positions of the frame. A lost frame then erases 1/Q of every codeword it
%   carries. The pairs of a run are cyclic: its first packets take their first frames from
%   its last pairs, as link_env.m reads a run's frames.
%   The channel's bit errors are applied to the codeword. Erased (zero metric, as for
%   punctured bits, IEEE 802.11-2007 17.3.5.5): the bits of a flagged frame, and of a
%   symbol whose received energy is more than 6 dB above the median of the codeword's
%   frames (a burst visible at the receiver); the rest enter with their reliability, the
%   sign the receiver's decision (Viterbi on soft values, 0 an erasure). Both frames of pair k carry packet k's ground truth, the BER and any error
%   of its decoded 1032 bits; its CRC check, a receiver measurement, exists only on frame
%   2k, when the packet is decoded (Q - 1 cycles later than an uncoded packet), so the
%   other frame's is NaN. A run of fewer than Q frames, or its last frame when their
%   number is odd, is NaN.
%   map  channel bit of the run (index into tx_al) that carries every coded bit of every
%        packet, coded bits in channel order x packets
ber = nan(1, nf); fer = nan(1, nf); crcf = nan(1, nf); map = zeros(0, 0);
if nargin < 6 || isempty(ers), ers = false(1, nf); end
if nargin < 7 || isempty(rel), rel = ones(size(rx_al(:))); end
rel = rel(:);
ers = logical(ers(:)');
bpf = p.frame_length;
Q = 4; if isfield(p, 'fec_frames'), Q = p.fec_frames; end
assert(mod(Q, 2) == 0 && mod(2 * bpf, Q) == 0, 'fec_packets: Q = %d frames do not split the codeword', Q);
np = floor(nf / 2);                                  % packets: one per frame pair
if np < Q / 2, return; end
e = double(tx_al(:) ~= rx_al(:));

sps = p.sps;
x = iq(:);
nsym = floor(numel(x) / sps);
Es = mean(reshape(abs(x(1:nsym*sps)).^2, sps, nsym), 1);
tm = 0; if isfield(p, 'timing_max_sym'), tm = ceil(p.timing_max_sym); end
d = p.filter_span / 2;                               % Tx filter delay in symbols
Lf = frame_layout(p);
E = nan(Lf.air, nf);                                 % symbol energies of every frame
for f = 1:nf
    k = (f-1) * Lf.air + (1:Lf.air);
    E(k <= nsym, f) = Es(k(k <= nsym));
end

trellis = poly2trellis(7, [171 133]);
rs = RandStream('mt19937ar', 'Seed', 11);
u = randi(rs, [0 1], bpf, 1);
c = convenc([u; zeros(6, 1)], trellis);
pun = round(linspace(1, numel(c), numel(c) - 2*bpf + 2));
keep = setdiff(1:numel(c), pun(2:end-1))';           % punctured evenly, ends kept
perm = randperm(rs, 2*bpf)';
tx = c(keep(perm));                                  % the codeword in channel order
L = 2 * bpf / Q; P = Q / 2;
o = repelem((1:Q)', L);                              % frame of each coded bit inside its codeword
slot = P - ceil(o / 2) + 1;                          % its slot of L bits in that frame
pos = reshape(randperm(rs, bpf)', [], P);            % bit positions of every slot of a frame
bpos = pos(sub2ind(size(pos), repmat((1:L)', Q, 1), slot));
sym = Lf.idx_data(ceil(bpos / 2)) + d;               % symbol of each coded bit in its frame
in = sym <= Lf.air;
nf2 = 2 * np;
map = zeros(2 * bpf, np);
for k = 1:np
    fr = mod(2*(k - P) + (0:Q-1), nf2) + 1;          % frames of the codeword, in order (cyclic)
    gi = (fr(o)' - 1) * bpf + bpos;
    map(:, k) = gi;
    if max(gi) > numel(e), continue; end
    ek = e(gi);
    Ek = E(:, fr);
    hot = movmax(double(Ek > 4 * median(Ek(:), 'omitnan')), [3 3 + tm], 1) > 0;   % tolerate filter delay and arrival time
    er = ers(fr(o))';
    er(in) = er(in) | hot(sub2ind(size(hot), sym(in), o(in)));
    soft = (1 - 2*double(xor(tx, ek))) .* rel(gi) .* ~er;
    sc = zeros(numel(c), 1);
    sc(keep(perm)) = soft;
    dec = vitdec(sc, trellis, 35, 'term', 'unquant');
    err = double(dec(1:bpf) ~= u);
    ber([2*k-1 2*k]) = mean(err);
    fer([2*k-1 2*k]) = double(any(err));
    crcf(2*k) = crc32_fail(u(1:bpf - p.crc_bits), err);
end
end
