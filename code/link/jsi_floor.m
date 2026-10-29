function s0 = jsi_floor(r, q)
%JSI_FLOOR  The quiet-symbol floor of a codeword from its residuals r (fec_packets.m).
%   Start: the q-quantile over -ln(1 - q), the variance of an exponential residual (complex
%   Gaussian noise). With a share f of clean symbols its lower tail reads f / sigma^2, so this
%   start sits about 1/f too high under bursts (x5 at the random jammer's duty 0.775). Then
%   eight passes of the truncated exponential's maximum likelihood: the residuals below
%   T = 3 x the current floor, where a clean symbol lies with probability 1 - e^-3 and a
%   symbol 10 dB or more above the floor seldom does, give sigma^2 from their mean,
%   m = sigma^2 - T e^(-T / sigma^2) / (1 - e^(-T / sigma^2)); never above 1.5 x the start.
%   The bound stops the passes climbing into weak bursts at high duty. It is not the start
%   itself: the block median gain of jsi_inputs.m passes through a few of the block's own
%   symbols, whose residuals sit near zero, so on a clean codeword the q-quantile reads about
%   0.75-0.8 of the thermal variance, and a floor held at the start would sit 0.8-1.3 dB low. A
%   continuous interferer puts it at its own level, where it belongs.
CAP = 1.5;
r = r(isfinite(r));
if isempty(r), s0 = eps; return; end
x = sort(r);
s0 = max(x(max(1, ceil(q * numel(x)))) / -log(1 - q), eps);
v = s0;
for it = 1:8
    T = 3 * v;
    m = mean(r(r < T));
    if ~(m > 0) || m >= 0.4999 * T, break; end
    lo = 1e-9 * T; hi = 1e3 * T;
    for b = 1:60
        mid = (lo + hi) / 2; e = exp(-T / mid);
        if mid - T * e / (1 - e) > m, hi = mid; else, lo = mid; end
    end
    v = min((lo + hi) / 2, CAP * s0);
end
s0 = max(v, eps);
end
