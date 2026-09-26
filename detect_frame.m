function [cls, conf, probs, msp, energy] = detect_frame(net, classes, iq, raw_feats, feat_mean, feat_std, fs)
%DETECT_FRAME  CNN threat classification of one received frame.
%   iq         antenna-1 received IQ of the frame
%   raw_feats  1 x 9 link features from link_features.m
%   Image from spec_image.m, features normalized with the training statistics;
%   scoring through cnn_scores.m, so class, confidence and the unknown-threat
%   scores (msp, energy) come from one path.
img = spec_image(iq, fs);
norm_feats = (raw_feats(:)' - feat_mean) ./ feat_std;
[probs, ~, msp, energy] = cnn_scores(net, reshape(img, 128, 128, 1, 1), norm_feats(:));
[conf, k] = max(probs);
cls = char(classes(k));
end
