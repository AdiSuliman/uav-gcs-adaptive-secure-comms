function [ber, fer, crcf] = fec_packets(tx_al, rx_al, iq, p, nf)
%FEC_PACKETS  Decoded result of every frame of a run with fec_interleave.
%   [ber, fer, crcf] = fec_packets(tx_al, rx_al, iq, p, nf)
%   tx_al, rx_al  transmitted and received channel bits, aligned per frame
%   iq            received samples of one antenna, samples x frames
%   One codeword per command packet of p.frame_length bits (1000 + 32 CRC) over two
%   frames: the packet and the code's 6 tail bits through the rate-1/2 convolutional code
%   (K = 7, generators [171 133] octal), 12 coded bits punctured to the 2 x 1032 channel
%   bits of the two frames, interleaved over those two frames only. The channel's bit
%   errors of the two frames are applied to the codeword; a symbol whose received energy
%   is more than 6 dB above the median of the two frames is erased (a burst visible at
%   the receiver), the rest are hard decisions (Viterbi on +1/-1/0). Both frames carry
%   their packet's ground truth, the BER and any error of its decoded 1032 bits; its CRC
%   check, a receiver measurement, exists only from the second frame on, when the packet
%   is decoded (one cycle, 20 ms, later than an uncoded packet), so the first frame's is
%   NaN. A frame without its pair, or past the aligned bits, is NaN.
ber = nan(1, nf); fer = nan(1, nf); crcf = nan(1, nf);
bpf = p.frame_length;
e = double(tx_al(:) ~= rx_al(:));

sps = p.sps;
x = iq(:);
nsym = floor(numel(x) / sps);
Es = mean(reshape(abs(x(1:nsym*sps)).^2, sps, nsym), 1);
tm = 0; if isfield(p, 'timing_max_sym'), tm = ceil(p.timing_max_sym); end
d = p.filter_span / 2;                               % Tx filter delay in symbols
Lf = frame_layout(p);
b = (0:2*bpf-1)';
fi = floor(b / bpf);                                 % frame of each bit inside its packet
sym = fi * Lf.air + Lf.idx_data(floor((b - fi * bpf) / 2) + 1) + d;   % its symbol from the packet's start

trellis = poly2trellis(7, [171 133]);
rs = RandStream('mt19937ar', 'Seed', 11);
u = randi(rs, [0 1], bpf, 1);
c = convenc([u; zeros(6, 1)], trellis);
pun = round(linspace(1, numel(c), numel(c) - 2*bpf + 2));
keep = setdiff(1:numel(c), pun(2:end-1))';           % punctured evenly, ends kept
perm = randperm(rs, 2*bpf)';
tx = c(keep(perm));                                  % the codeword on the two frames
for k = 1:floor(nf / 2)
    f = 2*k - 1;
    if (f + 1) * bpf > numel(e), break; end
    ek = e((f-1)*bpf + (1:2*bpf));
    s0 = (f-1) * Lf.air;
    Ek = Es(s0 + 1:min(s0 + 2*Lf.air, nsym));
    hot = movmax(double(Ek > 4 * median(Ek)), [3 3 + tm]) > 0;   % tolerate filter delay and arrival time
    er = false(2*bpf, 1);
    in = sym <= numel(Ek);
    er(in) = hot(sym(in));
    soft = (1 - 2*double(xor(tx, ek))) .* ~er;
    sc = zeros(numel(c), 1);
    sc(keep(perm)) = soft;
    dec = vitdec(sc, trellis, 35, 'term', 'unquant');
    err = double(dec(1:bpf) ~= u);
    ber([f f+1]) = mean(err);
    fer([f f+1]) = double(any(err));
    crcf(f+1) = crc32_fail(u(1:bpf - p.crc_bits), err);
end
end
