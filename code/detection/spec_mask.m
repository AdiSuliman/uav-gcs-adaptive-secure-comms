function X = spec_mask(X)
%SPEC_MASK  Time and frequency masking of a batch of detector images (train_hybrid_net.m):
%   one time band (<= 16 columns) and one frequency band (<= 12 rows) on a random half of
%   the batch, set to the image's thermal-noise level (spec_image('noise')): a band that
%   holds no signal, as the receiver shows it. 0 would be 25 dB below the floor, a value
%   thermal noise reaches in 0.3% of its bins.
%   X  128 x 128 x 1 x N images on spec_image.m's scale
n = size(X, 4);
v = spec_image('noise');
for i = find(rand(1, n) < 0.5)
    w = randi(16); c0 = randi(128 - w + 1); X(:, c0:c0+w-1, 1, i) = v;
    h = randi(12); r0 = randi(128 - h + 1); X(r0:r0+h-1, :, 1, i) = v;
end
end
