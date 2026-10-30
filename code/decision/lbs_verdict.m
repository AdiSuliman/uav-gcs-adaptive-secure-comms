function V = lbs_verdict(rows, clean)
%LBS_VERDICT  The go rule of the LB-S screen (lbs_screen.m), in points.
%   V = lbs_verdict(rows, clean)
%   rows   one struct per threat the kept agents were left out of, never-trained agent, link-budget
%          completion on against off on the same episodes: threat, d (change of the recovered
%          share), lo (its one-sided 95% lower bound)
%   clean  the deployed agent on the clean validation flights: d (change of the share of
%          episodes with a change of configuration)
%   Go only if all three hold:
%     1  path_loss improves by at least 20 points, with a lower bound of at least 10;
%     2  no other threat loses more than 2 points;
%     3  clean false changes rise by at most 1.0 point.
%   V: go, g (the three tests), worst (the other threat that changes least, worst_threat),
%   lines (the text of the report).
GAIN = 20; LOWER = 10; LOSS = 2; RISE = 1.0;
TOL = 1e-9;                                             % floating-point slack on the thresholds
ip = strcmp({rows.threat}, 'path_loss');
if sum(ip) ~= 1, error('lbs_verdict:path_loss', 'lbs_verdict: the rows must hold path_loss exactly once'); end
r = rows(ip); o = rows(~ip);
g = false(1, 3);
g(1) = r.d >= GAIN - TOL && r.lo >= LOWER - TOL;
g(2) = ~isempty(o) && all([o.d] >= -LOSS - TOL);
g(3) = clean.d <= RISE + TOL;
V = struct('go', all(g), 'g', g, 'worst', NaN, 'worst_threat', '', 'lines', {{}});
if ~isempty(o)
    [V.worst, k] = min([o.d]);
    V.worst_threat = o(k).threat;
end
yn = @(x) ternary(x, 'yes', 'no');
V.lines = { ...
    sprintf('1  never-trained path_loss: %+.1f points [one-sided 95%% lower bound %+.1f]; at least +%g with a bound of at least +%g: %s', ...
        r.d, r.lo, GAIN, LOWER, yn(g(1))), ...
    sprintf('2  other threats, the lowest change %+.1f points (%s); none below -%g: %s', V.worst, V.worst_threat, LOSS, yn(g(2))), ...
    sprintf('3  clean false changes %+.2f points; at most +%g: %s', clean.d, RISE, yn(g(3))), ...
    sprintf('LB-S verdict: %s', ternary(V.go, 'GO', 'NO-GO'))};
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
