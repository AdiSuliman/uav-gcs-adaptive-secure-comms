function [m, lo, hi] = per_reduction(per_pol, per_ref, cl, B, seed)
%PER_REDUCTION  Relative reduction of the packet error rate against a reference policy.
%   [m, lo, hi] = per_reduction(per_pol, per_ref, cl, B, seed): 1 - sum(per_pol) / sum(per_ref)
%   over the same episodes (paired: episode i under both policies, common random numbers),
%   with a 95% percentile bootstrap interval that resamples whole clusters (cl, the flight
%   geometry, boot_cluster.m). Episodes with a NaN under either policy are left out.
%   A fraction: 0.3 is a 30% reduction; NaN when the reference loses no packet.
if nargin < 4 || isempty(B), B = 2000; end
if nargin < 5 || isempty(seed), seed = 1; end
ok = isfinite(per_pol) & isfinite(per_ref);
[m, lo, hi] = boot_cluster(per_ref(ok) - per_pol(ok), per_ref(ok), cl(ok), B, seed);
end
