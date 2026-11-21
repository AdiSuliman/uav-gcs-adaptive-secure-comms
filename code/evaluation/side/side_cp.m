function [lo, hi] = side_cp(k, n)
%SIDE_CP  Two-sided 95% Clopper-Pearson interval of k successes in n trials (NaN for n = 0).
lo = NaN; hi = NaN;
if n < 1, return; end
if k <= 0, lo = 0; else, lo = betaincinv(0.025, k, n - k + 1); end
if k >= n, hi = 1; else, hi = betaincinv(0.975, k + 1, n - k); end
end
