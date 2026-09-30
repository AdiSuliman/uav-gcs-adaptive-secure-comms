function k_db = channel_k(seed, range_db)
%CHANNEL_K  Rician K-factors of the channels of one seeded flight [dB].
%   k_db = channel_k(seed, range_db): [K of our signal, K of every interferer],
%   uniform in range_db. Measured air-ground K-factors run from 2-5 dB among
%   trees and -5..10 dB at low elevation in urban areas to about 12 dB (L band)
%   and 28 dB (C band) in open line of sight (Khawaja et al.), so the default
%   range [0 20] dB spans foliage and built-up ground to open terrain.
if nargin < 2 || isempty(range_db), range_db = [0 20]; end
rs = RandStream('mt19937ar', 'Seed', mod(round(seed) + 23, 2^32));
k_db = range_db(1) + (range_db(2) - range_db(1)) * rand(rs, 1, 2);
end
