function img = spec_image(iq, fs, nv)
%SPEC_IMAGE  Detector input image of one received frame: centered STFT
%   (Hann 128, overlap 113, NFFT 128), magnitude in dB over the thermal floor of a bin
%   (nv, the thermal noise power per sample, thermal_nv.m, times the window's energy) on
%   a fixed scale [-25, 55] dB mapped to [0, 1], resized to 128 x 128. The receiver's
%   noise floor is fixed, so the image keeps the absolute received power: thermal noise
%   sits at 0 dB (its bins 25 dB below their mean in 0.3% of them), our signal 2 dB over
%   it at Eb/N0 0 dB and 17 dB at 15 dB, an interferer 30 dB above that (the in-band cap)
%   at 47 dB.
%   v = spec_image('noise'): the image value of a bin holding thermal noise alone, the
%   mean of its dB value: 10 log10 of an exponential power of mean 1 averages
%   -10 gamma / ln 10 = -2.51 dB (gamma, Euler's constant), at (-2.51 + 25) / 80 = 0.281.
db_lo = -25; db_hi = 55;
if ischar(iq) && strcmp(iq, 'noise')
    img = (-10 * 0.5772156649015329 / log(10) - db_lo) / (db_hi - db_lo);
    return
end
w = hann(128);
Sxx = spectrogram(iq, w, 113, 128, fs, 'centered');
P = (20*log10(abs(Sxx) + eps) - 10*log10(nv * sum(w.^2)) - db_lo) / (db_hi - db_lo);
img = imresize(min(max(P, 0), 1), [128 128]);
end
