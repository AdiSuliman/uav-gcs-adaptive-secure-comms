function b = seed_base(seed)
%SEED_BASE  First stream seed of one flight seed: 64 mod(seed, 2^26).
%   A flight seed owns the 64 stream seeds b..b+63, one per purpose (seed_stream.m),
%   so consecutive flight seeds never share a stream and the largest stream seed
%   stays below 2^32 (the mt19937ar limit). Flight seeds stay below 2^26.
b = 64 * mod(round(seed), 2^26);
end
