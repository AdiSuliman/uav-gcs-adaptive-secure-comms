function [a, ds] = tdl_profile(ds_ns, k_db, nt, step_ns)
%TDL_PROFILE  Diffuse tap amplitudes of the tapped delay line for an RMS delay spread.
%   [a, ds] = tdl_profile(ds_ns, k_db, nt, step_ns): amplitudes a (nt x 1, sum of squares
%   1) of the diffuse part on the taps 0, step_ns, ..., (nt-1) step_ns: an exponential
%   power profile r^n, with r set so that the composite profile, the line of sight on
%   tap 0 at K-factor k_db, has the RMS delay spread ds_ns (the second central moment of
%   the power delay profile, Rodriguez-Pineiro et al., eq. (8)). A spread the window
%   cannot hold at this K gets the flat profile, the largest it holds.
%   ds: the composite RMS delay spread reached [ns].
a = [1; zeros(nt - 1, 1)]; ds = 0;
if nt < 2 || ~(ds_ns > 0), return; end
q = 1 / (10^(k_db/10) + 1);                       % diffuse share of the power
n = (0:nt-1)';
lo = 1;
if spread(1, n, q, step_ns) > ds_ns
    lo = 0; hi = 1;
    for i = 1:60                                  % the spread grows with r
        r = (lo + hi) / 2;
        if spread(r, n, q, step_ns) < ds_ns, lo = r; else, hi = r; end
    end
end
P = lo .^ n;
a = sqrt(P / sum(P));
ds = spread(lo, n, q, step_ns);
end

function s = spread(r, n, q, step)
% Composite RMS delay spread [ns]: LoS on tap 0, the diffuse share q on r^n.
P = r .^ n; P = q * P / sum(P);
m1 = sum(P .* n) * step; m2 = sum(P .* n.^2) * step^2;
s = sqrt(max(m2 - m1^2, 0));
end
