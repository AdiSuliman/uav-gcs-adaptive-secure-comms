function varargout = paired_stats(cmd, varargin)
%PAIRED_STATS  Small exact and bootstrap tests of the paired decision-layer comparisons.
%   [m, lb, ub] = paired_stats('boot', x, cl, B, seed)
%       Mean of the per-episode values x with its one-sided 95% bounds (the 5th and 95th
%       percentiles of the mean) by a cluster bootstrap: the episodes of one cluster (cl,
%       a flight geometry at an Eb/N0) are resampled together, B resamples from a fixed seed
%       (Davison & Hinkley 1997, sec. 3.8). A difference of two policies is the mean of the
%       per-episode differences. Non-finite values are dropped; fewer than two clusters give
%       NaN bounds.
%   p = paired_stats('mcnemar', b, c)
%       Exact one-sided McNemar test (McNemar 1947) of more discordant pairs of one kind
%       than the other: b the pairs that changed one way, c the other way; under no effect
%       b is binomial (b + c, 1/2) and p = P(X >= b); 1 without discordant pairs.
%   u = paired_stats('garwood', k, cyc)
%       One-sided 95% upper bound of a Poisson rate from k events in cyc exposure units
%       (Garwood 1936): the rate at which k or fewer events have probability 5%.
cmd = lower(cmd);
switch cmd
    case 'boot'
        [m, lb, ub] = boot(varargin{:});
        varargout = {m, lb, ub};
    case 'mcnemar'
        varargout = {mcnemar(varargin{:})};
    case 'garwood'
        varargout = {garwood(varargin{:})};
    otherwise
        error('paired_stats:cmd', 'paired_stats: unknown command %s', cmd);
end
end

function [m, lb, ub] = boot(x, cl, B, seed)
if nargin < 3 || isempty(B), B = 2000; end
if nargin < 4 || isempty(seed), seed = 1; end
x = double(x(:)); cl = cl(:);
ok = isfinite(x); x = x(ok); cl = cl(ok);
m = NaN; lb = NaN; ub = NaN;
if isempty(x), return; end
[~, ~, j] = unique(cl);
Sn = accumarray(j, x); Sd = accumarray(j, 1);
m = sum(Sn) / sum(Sd);
nU = numel(Sn);
if nU < 2, return; end
rs = RandStream('mt19937ar', 'Seed', seed);
idx = randi(rs, nU, nU, B);
q = sort(sum(Sn(idx), 1) ./ sum(Sd(idx), 1));
lb = q(max(1, round(0.05 * B))); ub = q(min(B, round(0.95 * B)));
end

function p = mcnemar(b, c)
n = b + c;
if n == 0 || b == 0, p = 1; return; end
p = betainc(0.5, b, n - b + 1);                          % P(X >= b), X ~ binomial(n, 1/2)
end

function u = garwood(k, cyc)
u = gammaincinv(0.95, k + 1) / cyc;
end
