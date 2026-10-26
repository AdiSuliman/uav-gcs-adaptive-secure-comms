function [pick, adm, best, fail] = deg_adopt(R, R0, fa_bound, lect)
%DEG_ADOPT  The adoption rule of the degradation test (docs/deg_fix_protocol.md, section 3; the
%   form of the sweeper's rule, choose_drop_threshold.m).
%   R    candidates in the adoption order (F1, F2 per alpha, F3 per alpha), each with lat (1 x
%        monitors, choose_drop_threshold.m's delays: threat, median, p90, never) and bound (1 x
%        monitors, the clean check half's one-sided 95% bound at the monitor's own threshold)
%   R0   'ratio' under the same monitors and episodes (lat; optional monitor, their names)
%   fa_bound  KPI 6's bound (0.05); lect  the lecturer's threats (default jamming, tone_jamming)
%   A candidate is admissible when, under every monitor against 'ratio': (a) for the lecturer's
%   threats the median and p90 delay and the never share do not grow; (b) for every other threat
%   the never share grows by at most 1 point and the p90 by at most 1 cycle (never confirmed:
%   an infinite delay). pick: the first admissible candidate whose lowest bound over the
%   monitors is at most fa_bound; else the admissible one with the lowest bound (the first on a
%   tie); 0 when none is admissible ('ratio' stays). adm per candidate, best its lowest bound,
%   fail the threats that broke (a) or (b).
if nargin < 4 || isempty(lect), lect = {'jamming', 'tone_jamming'}; end
tol = 1e-9;
nc = numel(R); adm = false(1, nc); best = inf(1, nc); fail = repmat({''}, 1, nc);
for c = 1:nc
    f = {};
    for m = 1:numel(R0.lat)
        a = R(c).lat(m); r = R0.lat(m);
        mn = sprintf('monitor %d', m); if isfield(R0, 'monitor'), mn = R0.monitor{m}; end
        for q = 1:numel(r.threat)
            i = find(strcmp(a.threat, r.threat{q}), 1);
            if isempty(i), f{end+1} = sprintf('%s %s not read', mn, r.threat{q}); continue; end %#ok<AGROW>
            if ismember(r.threat{q}, lect)
                bad = inf_nan(a.median(i)) > inf_nan(r.median(q)) || inf_nan(a.p90(i)) > inf_nan(r.p90(q)) || ...
                    a.never(i) > r.never(q) + tol;
            else
                bad = a.never(i) > r.never(q) + 0.01 + tol || inf_nan(a.p90(i)) > inf_nan(r.p90(q)) + 1;
            end
            if bad, f{end+1} = sprintf('%s %s', mn, r.threat{q}); end %#ok<AGROW>
        end
    end
    adm(c) = isempty(f); fail{c} = strjoin(f, ', ');
    best(c) = min(R(c).bound);
end
pick = find(adm & best <= fa_bound, 1);
if isempty(pick)
    b = best; b(~adm) = Inf;
    [v, pick] = min(b);
    if ~isfinite(v), pick = 0; end
end
end

function x = inf_nan(x)
% A delay never read (NaN: no episode confirmed) is an infinite one.
x(isnan(x)) = Inf;
end
