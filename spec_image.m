function img = spec_image(iq, fs)
%SPEC_IMAGE  Detector input image of one received frame (D42): centered STFT
%   (Hann 128, overlap 113, NFFT 128), magnitude in dB on a fixed scale
%   [-40, 40] dB mapped to [0, 1], resized to 128 x 128. The fixed scale keeps
%   absolute power differences; the 40 dB ceiling stays above the strongest
%   jammer (JSR 16 dB), so jamming no longer saturates the image.
db_lo = -40; db_hi = 40;
Sxx = spectrogram(iq, hann(128), 113, 128, fs, 'centered');
P = (20*log10(abs(Sxx) + eps) - db_lo) / (db_hi - db_lo);
img = imresize(min(max(P, 0), 1), [128 128]);
end
