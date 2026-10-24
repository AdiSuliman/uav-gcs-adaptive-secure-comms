function J = jsi_inputs(zc, p, h)
%JSI_INPUTS  Per-symbol jammer state information of the combiner output (Baldi et al. 2013,
%   Sec. V: the decoder knows the noise variance of every symbol, N0/2 + J0/(2 rho) on the
%   jammed ones), for the JSI decoder of fec_packets.m.
%   J = jsi_inputs(zc, p, h): zc the combiner output (data symbols x frames, after sync and
%   any MMSE null), p.frame_length bits per frame, h neighbours on each side averaged into a
%   symbol's variance. Per 32-symbol block the decision-directed gain g, as bit_reliability.m
%   but the median of the real and the imaginary parts of z conj(s) instead of their mean: a
%   30 dB burst on a fifth of a block moves the mean by several times |g| and every symbol's
%   residual with it, while the median holds while less than half of the block is jammed;
%   per data symbol k:
%     res    its residual |z_k - g s_k|^2 (s_k its decision)
%     res_h  the mean residual over k-h .. k+h within the frame
%     num    2 sqrt(2) |Im| and |Re| of conj(g) z_k for its first and second bit: the
%            log-likelihood ratio times the symbol's variance
%   Every field a column aligned with the receiver's bits (two per symbol), frames in order,
%   as bit_reliability.m's output.
if nargin < 3 || isempty(h), h = 0; end
B = 32;
nd = p.frame_length / 2;
nf = size(zc, 2);
num = zeros(2 * nd, nf); res = num; resh = num;
nb = max(1, floor(nd / B));
for f = 1:nf
    z = zc(1:nd, f);
    s = (sign0(real(z)) + 1j * sign0(imag(z))) / sqrt(2);
    r = zeros(nd, 1); v = complex(zeros(nd, 1));
    for b = 1:nb
        k = (b-1)*B + 1 : b*B;
        if b == nb, k = (b-1)*B + 1 : nd; end
        y = z(k) .* conj(s(k));
        g = complex(median(real(y)), median(imag(y)));
        r(k) = abs(z(k) - g * s(k)).^2;
        v(k) = 2 * sqrt(2) * conj(g) * z(k);
    end
    rh = r; if h > 0, rh = movmean(r, 2 * h + 1); end
    num(1:2:end, f) = abs(imag(v)); num(2:2:end, f) = abs(real(v));
    res(1:2:end, f) = r; res(2:2:end, f) = r;
    resh(1:2:end, f) = rh; resh(2:2:end, f) = rh;
end
J = struct('num', num(:), 'res', res(:), 'res_h', resh(:));
end

function y = sign0(x)
y = sign(x); y(y == 0) = 1;
end
