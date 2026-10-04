function F = false_change_rate(sw, T, cl, period_ms)
%FALSE_CHANGE_RATE  Configuration changes on the clean link per decision cycle, per hour
%   of flight and the mean time between two of them.
%   F = false_change_rate(sw, T, cl, period_ms)
%   sw         changes in each clean episode (every one a false alarm); T cycles per
%              episode; cl flight of each episode (the bootstrap resamples whole
%              flights); period_ms decision period (decision_config.m)
%   F.k changes in F.cycles cycles; F.rate per cycle and F.hi its two-sided 95% upper
%   bound: the bootstrap over flights (boot_cluster.m), at least the Clopper-Pearson
%   bound of k events in all the cycles; F.per_hour and F.per_hour_hi; F.mtbf_s, the
%   mean time between false changes [s], and F.mtbf_lo_s at the bound.
sw = double(sw(:)'); cl = cl(:)';
F = struct('k', sum(sw), 'cycles', T * numel(sw), 'rate', NaN, 'hi', NaN, 'per_hour', NaN, 'per_hour_hi', NaN, ...
    'mtbf_s', NaN, 'mtbf_lo_s', NaN);
if isempty(sw), return; end
[F.rate, ~, hi] = boot_cluster(sw, T * ones(size(sw)), cl, 4000, 75);
if F.k >= F.cycles, cp = 1; else, cp = betaincinv(0.975, F.k + 1, F.cycles - F.k); end
F.hi = max([hi, cp], [], 'omitnan');
cyc_h = 3600e3 / period_ms;                              % decision cycles per hour
F.per_hour = F.rate * cyc_h; F.per_hour_hi = F.hi * cyc_h;
F.mtbf_s = period_ms / 1e3 / F.rate; F.mtbf_lo_s = period_ms / 1e3 / F.hi;
end
