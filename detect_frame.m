function [cls, conf, probs] = detect_frame(net, classes, iq, raw_feats, feat_mean, feat_std, fs)
%DETECT_FRAME  CNN threat classification of one received frame.
%   Same preprocessing as run_closed_loop_diagnostic.m: STFT spectrogram in dB,
%   clipped to [-40, 20] dB and scaled to [0,1], resized to 128x128, plus the 7
%   scalar/temporal features [Eb/N0, BER, RSSI, PLR, var_rssi_10, dBER/dt,
%   burst_ratio] normalized with the training statistics.

persistent useGPU
if isempty(useGPU), useGPU = canUseGPU; end

img_size = 128; win = 128; novlp = 113; nfft = 128; db_lo = -40; db_hi = 20;

Sxx = spectrogram(iq, hann(win), novlp, nfft, fs, 'centered');
Pw  = 20*log10(abs(Sxx) + eps);
Pw  = min(max((Pw - db_lo) / (db_hi - db_lo), 0), 1);
spec_img = imresize(Pw, [img_size img_size]);

raw_feats(isnan(raw_feats)) = 0;
norm_feats = (raw_feats - feat_mean) ./ feat_std;
X_spec = dlarray(single(spec_img), 'SSCB');
X_feat = dlarray(single(norm_feats(:)), 'CB');
if useGPU
    X_spec = gpuArray(X_spec);
    X_feat = gpuArray(X_feat);
end

probs = gather(extractdata(predict(net, X_spec, X_feat)));
[conf, k] = max(probs);
cls = char(classes(k));
end
