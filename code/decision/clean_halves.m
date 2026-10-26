function [fit, chk, h] = clean_halves(runs)
%CLEAN_HALVES  The clean validation geometries split by a hash of their id into a fit half and a
%   check half (docs/deg_fix_protocol.md): the floor(n/2) geometries of the smallest hash fit
%   the degradation quantile (clean_ber_q.m), the others decide its adoption
%   (choose_drop_threshold.m). The hash is Knuth's multiplicative hash mod 2^32 with one xor
%   shift; ties keep the smaller id. The split depends on the ids only, not on their order.
%   fit, chk  logical, the size of runs; h the hash per geometry
r = double(runs);
assert(all(r(:) >= 0 & r(:) < 2^21 & r(:) == round(r(:))), 'clean_halves: geometry ids must be integers in [0, 2^21)');
assert(numel(unique(r(:))) == numel(r), 'clean_halves: repeated geometry id');
h1 = mod(r * 2654435761, 2^32);                         % exact in double below 2^53
h = double(bitxor(uint32(h1), bitshift(uint32(h1), -15)));
[~, o] = sortrows([h(:), r(:)]);
fit = false(size(r)); fit(o(1:floor(numel(r) / 2))) = true;
chk = ~fit;
end
