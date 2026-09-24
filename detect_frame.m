function [cls, conf, probs, msp, energy] = detect_frame(net, classes, iq, raw_feats, feat_mean, feat_std, fs)
%DETECT_FRAME  CNN threat classification of one received frame.
%   Preprocessing (local function frame_features) is the same as in the C3
%   diagnostic; scoring goes through cnn_scores.m, so class, confidence and the
%   unknown-threat scores (msp, energy) come from one path.
[spec_img, norm_feats] = frame_features(iq, raw_feats, feat_mean, feat_std, fs);
[probs, ~, msp, energy] = cnn_scores(net, reshape(spec_img, 128, 128, 1, 1), norm_feats(:));
[conf, k] = max(probs);
cls = char(classes(k));
end

function [spec_img, norm_feats] = frame_features(iq, raw_feats, feat_mean, feat_std, fs)
% STFT spectrogram in dB, clipped to [-40, 20] dB, scaled to [0,1], resized to
% 128x128; the 7 scalar/temporal features [Eb/N0, BER, RSSI, PLR, var_rssi_10,
% dBER/dt, burst_ratio] normalized with the training statistics (NaN -> 0 first).
img_size = 128; win = 128; novlp = 113; nfft = 128; db_lo = -40; db_hi = 20;
Sxx = spectrogram(iq, hann(win), novlp, nfft, fs, 'centered');
Pw  = 20*log10(abs(Sxx) + eps);
Pw  = min(max((Pw - db_lo) / (db_hi - db_lo), 0), 1);
spec_img = imresize(Pw, [img_size img_size]);
raw_feats(isnan(raw_feats)) = 0;
norm_feats = (raw_feats(:)' - feat_mean) ./ feat_std;
end
