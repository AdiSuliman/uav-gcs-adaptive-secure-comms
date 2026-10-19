function [ber, fer, crcf] = closed_loop_truth(T, p)
%CLOSED_LOOP_TRUTH  Ground truth and CRC of every frame of one run (extract_closed_loop_frames.m).
%   [ber, fer, crcf] = closed_loop_truth(T, p): T the run's truth inputs, the second output of
%   extract_closed_loop_frames.m (tx_al, rx_al: aligned channel bits; iq: reference samples of
%   antenna 1, samples x frames; zc: combiner output; delay_bits; nf; erase); p the params. The
%   only place p.fec is read: with it the decoded packets (fec_packets.m), without it the
%   frames' own bits. A configuration that differs from the simulated one in p.fec alone gets
%   its truth from the same run (pool_cell.m).
nf = T.nf;
if isfield(p, 'fec') && p.fec
    Lmax = numel(T.tx_al);
    rel = bit_reliability(T.zc, p);
    rel = rel(T.delay_bits+1:T.delay_bits+Lmax);
    [ber, fer, crcf] = fec_packets(T.tx_al, T.rx_al, T.iq, p, nf, T.erase, rel);
else
    bpf = p.frame_length;
    err = double(T.tx_al ~= T.rx_al);
    ber = nan(1, nf); fer = nan(1, nf); crcf = nan(1, nf);
    for f = 1:nf
        i0 = (f-1)*bpf + 1; i1 = f*bpf;
        if i1 > numel(err), continue; end
        e = err(i0:i1);
        ber(f) = mean(e);
        fer(f) = double(any(e));
        crcf(f) = crc32_fail(T.tx_al(i0:i0 + bpf - p.crc_bits - 1), e);
    end
end
end
