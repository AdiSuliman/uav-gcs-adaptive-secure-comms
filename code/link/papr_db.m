function x = papr_db(p)
%PAPR_DB  Peak-to-average power ratio of our transmitted waveform [dB].
%   x = papr_db(p): the largest instantaneous power of the root-raised-cosine QPSK signal
%   (p.rolloff, p.filter_span) over its mean, 4096 seeded random symbols at 16 samples per
%   symbol. A radio's largest output is that of a CW tone, whose peak is its mean: on a
%   linear transmitter our signal's mean stays this far below it.
rs = RandStream('mt19937ar', 'Seed', 1);
s = pskmod(randi(rs, [0 3], 4096, 1), 4, pi/4);
h = rcosdesign(p.rolloff, p.filter_span, 16, 'sqrt');
y = upfirdn(s, h, 16);
y = y(numel(h):end - numel(h));                      % the filter's start-up and tail left out
a = abs(y).^2;
x = 10*log10(max(a) / mean(a));
end
