function b = body_loss(seed, n, prm)
%BODY_LOSS  Loss of the airframe on each UAV antenna of one seeded flight [dB].
%   b = body_loss(seed, n, prm): n losses, normal with mean prm(1) and standard deviation
%   prm(2) truncated to [prm(3), prm(4)], from the flight's own 'body' stream
%   (seed_stream.m) by the inverse CDF. The drone body changes a mounted antenna's
%   co-polarized azimuth pattern by 0.016-10.96 dB, mean 3.03, SD 2.53 (Badi et al. 2019,
%   Table 1); another mounting gave a different pattern with similar statistics.
u = rand(seed_stream(seed, 'body'), 1, n);
c = @(x) 0.5 * erfc(-(x - prm(1)) / (prm(2) * sqrt(2)));
q = c(prm(3)) + u * (c(prm(4)) - c(prm(3)));
b = prm(1) - prm(2) * sqrt(2) * erfcinv(2 * q);
end
