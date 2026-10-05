function r = bit_reliability(zc, p)
%BIT_RELIABILITY  Magnitude of the log-likelihood ratio of every received data bit.
%   r = bit_reliability(zc, p): zc the combiner output (data symbols x frames), p.frame_length
%   bits per frame; r a column aligned with the receiver's bits, frames in order. Per
%   32-symbol block the gain g and the error power es of the decisions, as the BER estimate
%   of extract_closed_loop_frames.m, so every symbol carries the noise variance of its
%   block (jammer state information, Baldi et al. 2013, Sec. V);
%   LLR = 2 sqrt(2) Im / Re(conj(g) z) / es for the first / second bit of the Gray-mapped
%   pi/4 QPSK symbol (z = g s + n, s = (+-1 +-j) / sqrt(2), es / 2 per rail).
B = 32;
nd = p.frame_length / 2;
nf = size(zc, 2);
r = zeros(2 * nd, nf);
nb = max(1, floor(nd / B));
for f = 1:nf
    z = zc(1:nd, f);
    s = (sign0(real(z)) + 1j * sign0(imag(z))) / sqrt(2);
    for b = 1:nb
        k = (b-1)*B + 1 : b*B;
        if b == nb, k = (b-1)*B + 1 : nd; end
        g = mean(z(k) .* conj(s(k)));
        es = max(mean(abs(z(k) - g * s(k)).^2), eps);
        v = 2 * sqrt(2) * conj(g) * z(k) / es;
        r(2*k - 1, f) = abs(imag(v)); r(2*k, f) = abs(real(v));
    end
end
r = r(:);
end

function y = sign0(x)
y = sign(x); y(y == 0) = 1;
end
