function R = head_cost(FM, Z, ST, nRep)
%HEAD_COST  The cost of the fusion's head on the stages that run the fusion every cycle: the
%   monitor's fusion (fuse_classes 'apply', one row per call: one episode's cycle in
%   policy_monitor.m, det_frames.m) timed with and without the head, the calls of the two arms
%   interleaved so a change of load hits both; the increase per row times each stage's rows,
%   against the stages' projected hours. One row per call is the dearest case, a batch of
%   episodes per call costs less per row.
%   R = head_cost(FM, Z, ST, nRep)
%   FM    a fusion with FM.head; Z rows of its row layout
%   ST    struct array, one per stage C1d, C2 (with its retrains), C2e, C2g, C2u and EDGE:
%         stage, rows (fusion rows over the whole stage, episodes x cycles), hours
%   nRep  timed calls per arm (default 2000) after 20 warm-up calls
%   R     with_ms, without_ms (medians), delta_ms, stage, inc_h, hours, share_pct (the increase
%         over the stages' sum, percent), ok (at most 2%)
if nargin < 4, nRep = 2000; end
need = {'C1d', 'C2', 'C2e', 'C2g', 'C2u', 'EDGE'};
assert(isstruct(ST) && all(isfield(ST, {'stage', 'rows', 'hours'})) && isempty(setxor({ST.stage}, need)), ...
    'head_cost:stages', 'ST names the stages %s once each, with rows and hours', strjoin(need, ', '));
assert(isfield(FM, 'head') && ~isempty(FM.head), 'head_cost:head', 'FM has no head');
F0 = rmfield(FM, 'head');
r = mod(0:nRep + 19, size(Z, 1)) + 1;
a = zeros(1, nRep + 20); b = a;
for i = 1:nRep + 20
    z = Z(r(i), :);
    t0 = tic; fuse_classes('apply', FM, z); a(i) = toc(t0);
    t0 = tic; fuse_classes('apply', F0, z); b(i) = toc(t0);
end
a = 1000 * a(21:end); b = 1000 * b(21:end);
dm = max(median(a) - median(b), 0);
inc = [ST.rows] * dm / 3.6e6;
tot = sum([ST.hours]);
R = struct('with_ms', median(a), 'without_ms', median(b), 'delta_ms', dm, 'stage', {{ST.stage}}, 'inc_h', inc, ...
    'hours', [ST.hours], 'share_pct', 100 * sum(inc) / tot, 'ok', sum(inc) <= 0.02 * tot);
fprintf('The head''s cost: fusion row %.3f ms with it, %.3f ms without (median, one row per call), +%.3f ms per row\n', ...
    R.with_ms, R.without_ms, dm);
fprintf('  %s\n', strjoin(arrayfun(@(s, x) sprintf('%s +%.2f h of %.1f h', s.stage, x, s.hours), ST(:)', inc, 'UniformOutput', false), ', '));
fprintf('  projected increase %.2f h of %.1f h (%.2f%%; at most 2%%) -> %s\n', sum(inc), tot, R.share_pct, ...
    ternary(R.ok, 'within', 'over: the pick alone deploys'));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
