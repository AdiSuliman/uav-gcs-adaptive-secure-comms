function V = held_verdict(held, ep, cl, target, flight, B)
%HELD_VERDICT  Held recovery of one layer at one point (edge_map.m REC, PROT, REC_h,
%   PROT_h, the random policy's and no response's PROT, the band PROT).
%   V = held_verdict(held, ep, cl, target, flight, B)
%   held, ep  held onsets and onsets per flight; cl the flight of each
%   flight     false: the per-onset rate, read by edge_verdict.m's rate rule (the hull of
%              the bootstrap over flights and the Clopper-Pearson interval on the effective
%              sample size, between the flights and the onsets); value and interval are
%              both the share of held onsets
%              true: the flight-level reading (a flight succeeds only when every onset is
%              held); its value is still the share of held onsets
%   V          edge_verdict.m's output, target sense 'ge'
V = edge_verdict(held, ep, cl, target, 'ge', flight, B);
end
