function [S, lines] = kpi6_split(flag, geom, cov, names, B, seed)
%KPI6_SPLIT  The clean false-change episodes over the clean episodes in bins of the flight's
%   estimated link K, speed and bank, and of the hiding geometry (D121 items 12 and 15;
%   descriptive, printed beside KPI 6's registered reading, never in its place; it moves no
%   verdict, threshold or choice).
%   flag   P x N logical, row p: the clean episode had a false change under policy (or monitor) p
%   geom   1 x N flight geometry of each episode (the bootstrap cluster, boot_cluster.m)
%   cov    per-episode covariates: lk (the flight's median estimated link K from the receiver,
%          dB, NaN without one), speed [km/h], speed_bins (band edges, D116's), bank [deg], hide
%          (logical: the geometry meets the hiding condition shadow_spec would apply, or [])
%   Bins, fixed here: K < 0, 0 to < 10, >= 10 dB; speed per cov.speed_bins; bank 0 to < 20,
%   20 to < 40, >= 40 deg (D116 item 7); hiding geometry yes / no.
%   S.var(v): name, labels, and per policy p: k, n, pct, ci (95% bootstrap over geometries),
%   ncl (clusters); S.hide_share and its interval where cov.hide is given.
if nargin < 5 || isempty(B), B = 2000; end
if nargin < 6 || isempty(seed), seed = 6101; end
P = size(flag, 1);
vars = {};
vars(end+1, :) = {'estimated link K', {'< 0 dB', '0 to < 10 dB', '>= 10 dB'}, binof(cov.lk, [0 10])};
vars(end+1, :) = {'speed', arrayfun(@(b) sprintf('%.0f-%.0f km/h', cov.speed_bins(b), cov.speed_bins(b+1)), ...
    1:numel(cov.speed_bins) - 1, 'UniformOutput', false), binof(cov.speed, cov.speed_bins(2:end-1))};
vars(end+1, :) = {'bank', {'0 to < 20 deg', '20 to < 40 deg', '>= 40 deg'}, binof(abs(cov.bank), [20 40])};
if isfield(cov, 'hide') && ~isempty(cov.hide)
    vars(end+1, :) = {'hiding geometry', {'meets the hiding condition', 'does not'}, 2 - double(logical(cov.hide(:)'))};
end
S = struct('var', struct('name', {}, 'labels', {}, 'k', {}, 'n', {}, 'pct', {}, 'ci', {}, 'ncl', {}), 'hide_share', [NaN NaN NaN]);
lines = {'', ['KPI 6 split, clean false-change episodes over clean episodes with a 95% bootstrap over flight geometries and the ' ...
    'cluster count (descriptive, beside the registered reading; D121 items 12 and 15):']};
for v = 1:size(vars, 1)
    bin = vars{v, 3}; nl = numel(vars{v, 2});
    x = struct('name', vars{v, 1}, 'labels', {vars{v, 2}}, 'k', zeros(P, nl), 'n', zeros(P, nl), 'pct', nan(P, nl), ...
        'ci', nan(P, nl, 2), 'ncl', zeros(P, nl));
    for p = 1:P
        txt = cell(1, nl);
        for b = 1:nl
            m = bin == b;
            x.n(p, b) = sum(m); x.k(p, b) = sum(flag(p, m)); x.ncl(p, b) = numel(unique(geom(m)));
            if any(m)
                [q, lo, hi] = boot_cluster(double(flag(p, m)), ones(1, sum(m)), geom(m), B, seed + 100 * v + 10 * p + b);
                x.pct(p, b) = 100 * q; x.ci(p, b, :) = 100 * [lo hi];
            end
            txt{b} = sprintf('%s %d/%d = %s%% [%s, %s] (%d geometries)', vars{v, 2}{b}, x.k(p, b), x.n(p, b), ...
                ntxt(x.pct(p, b)), ntxt(x.ci(p, b, 1)), ntxt(x.ci(p, b, 2)), x.ncl(p, b));
        end
        lines{end+1} = sprintf('  %s, %s: %s', names{p}, x.name, strjoin(txt, ' | ')); %#ok<AGROW>
    end
    S.var(end+1) = x;
end
if isfield(cov, 'hide') && ~isempty(cov.hide)
    h = double(logical(cov.hide(:)'));
    [q, lo, hi] = boot_cluster(h, ones(size(h)), geom, B, seed + 7);
    S.hide_share = 100 * [q lo hi];
    lines{end+1} = sprintf(['  share of the clean flights in a geometry that meets the hiding condition shadow_spec would apply ' ...
        '(geometry only, no loss applied): %s%% [%s, %s]; a clean flight there is cleaner than physics, so the clean false-alarm ' ...
        'reading is optimistic, not harsh'], ntxt(S.hide_share(1)), ntxt(S.hide_share(2)), ntxt(S.hide_share(3)));
end
end

function b = binof(x, edges)
% Bin index of x by the ascending edges (the edges belong to the upper bin); 0 where x is not finite.
x = x(:)'; b = 1 + sum(x >= edges(:), 1); b(~isfinite(x)) = 0;
end

function s = ntxt(x)
if isnan(x), s = '-'; else, s = sprintf('%.1f', x); end
end
