function [m, lo, hi] = stats_ci(kind, a, b)
%STATS_CI  95% confidence intervals used by the Monte Carlo reporting (D35).
%
%   [m, lo, hi] = stats_ci('t', x, lim)
%       Mean of the finite values of x with a Student-t 95% interval.
%       One value gives lo = hi = NaN (no spread to estimate). Optional
%       lim = [lower upper] clips the interval to the metric's range
%       (e.g. [0 100] for a percentage).
%
%   [p, lo, hi] = stats_ci('wilson', k, n)
%       Proportion k/n with the Wilson score 95% interval. Stays inside [0,1]
%       and is defined for k = 0 and k = n, unlike the normal approximation.
%
%   txt = stats_ci('fmt', x, lim)
%       Short text 'mean [lo, hi]' for reports (t interval, optional clip).

switch lower(kind)
    case 't'
        x = a(isfinite(a));
        n = numel(x);
        m = NaN; lo = NaN; hi = NaN;
        if n == 0, return; end
        m = mean(x);
        if n < 2, return; end
        h = t975(n - 1) * std(x) / sqrt(n);
        lo = m - h; hi = m + h;
        if nargin > 2 && ~isempty(b)
            lo = max(lo, b(1)); hi = min(hi, b(2));
        end

    case 'wilson'
        k = a; n = b;
        m = NaN; lo = NaN; hi = NaN;
        if n <= 0, return; end
        z = 1.959964;
        p = k / n;
        d = 1 + z^2 / n;
        c = (p + z^2 / (2*n)) / d;
        h = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d;
        m = p; lo = max(0, c - h); hi = min(1, c + h);

    case 'fmt'
        if nargin < 3, b = []; end
        [mm, l, h] = stats_ci('t', a, b);
        if isnan(l)
            m = sprintf('%.1f', mm);
        else
            m = sprintf('%.1f [%.1f, %.1f]', mm, l, h);
        end

    otherwise
        error('stats_ci: unknown kind "%s"', kind);
end
end

function t = t975(df)
% Two-sided 95% Student-t quantile; tabulated so no toolbox is needed.
T = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 2.262 2.228 ...
     2.201 2.179 2.160 2.145 2.131 2.120 2.110 2.101 2.093 2.086 ...
     2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 2.045 2.042];
if df <= numel(T), t = T(df); else, t = 1.960 + 2.4 / df; end
end
