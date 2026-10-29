function varargout = kpi_print_text(cmd, varargin)
%KPI_PRINT_TEXT  Text builders of the KPI summary, the edge map and the KPI dashboard.
%   Pure string functions: they read no file and compute no number the saved results do not
%   already hold. measure_all_kpis.m, edge_map.m and build_kpi_dashboard.m call them, so the
%   wording is tested on synthetic inputs (test_kpi_print.m). No verdict, status or KPI value
%   changes through them.
%   [s, W] = kpi_print_text('leave_out', res, what, label, unit)
%       Leave-one-out line of experiment_combo_generalization.m (res.combo) or
%       experiment_unknown_threat.m (res.threat): label the DQN that flew, the share
%       recovered weighted by episode (res.n) beside the plain average over the cases,
%       and the three lowest cases. W holds the weighted and averaged shares.
%   s = kpi_print_text('kpi1_all', m)     KPI 1: the all-frames reading and the headline, each
%       with its own interval (m: eval_detector.m metrics)
%   s = kpi_print_text('kpi1_every', m)   KPI 1, every class >= 90%: 'not reached' instead of NaN
%   s = kpi_print_text('kpi4_lower', names, point, ci)
%       KPI 4 inside the envelope counted by the 95% lower bound, beside the registered
%       count of point estimates; names, point, ci (rows [lo hi]) of the threats inside it
%   s = kpi_print_text('kpi7_spread', spread, target)
%       KPI 7 speed spread [point lo hi]: committed when the interval's upper bound is within
%       the target
%   s = kpi_print_text('edge_distance', en, inom)
%       the distance-edge line (EDGE_NUM en, nominal cells inom): threat and nominal level
%       apart from the Eb/N0 of the edge
%   s = kpi_print_text('edge_flight', V, f)
%       ' fl 86.1' for a held-recovery verdict (edge_verdict.m) whose fully held flights
%       differ from its episode share, else ''; f the number format of edge_map.m
%   s = kpi_print_text('gcsa', lines)     the GCS antenna line (results/gcs_antenna.txt)
%   c = kpi_print_text('wrap', t, w)      text t broken at spaces into lines of at most w characters
%   c = kpi_print_text('palette', n)      n distinct colors (rows), the dashboard's curves
%   L = kpi_print_text('link_limited', loss, ratio_ok)
%       Eb/N0 points where ratio_ok x the clean packet loss >= 1 (the restoration test of
%       packet loss cannot fail there)
%   L = kpi_print_text('edge_limited', Em, ebno, ratio_ok)
%       the same for the Eb/N0 points ebno, from the edge map's clean link (Em: the loaded
%       results/edge_map.mat, EM.clean.link); all false when the edge map is absent
%   t = kpi_print_text('ebno_ticks', ebno, L)   tick labels, 'L' after a link-limited point
switch cmd
    case 'leave_out',     [varargout{1}, varargout{2}] = leave_out(varargin{:});
    case 'kpi1_all',      varargout{1} = kpi1_all(varargin{:});
    case 'kpi1_every',    varargout{1} = kpi1_every(varargin{:});
    case 'kpi4_lower',    varargout{1} = kpi4_lower(varargin{:});
    case 'kpi7_spread',   varargout{1} = kpi7_spread(varargin{:});
    case 'edge_distance', varargout{1} = edge_distance(varargin{:});
    case 'edge_flight',   varargout{1} = edge_flight(varargin{:});
    case 'gcsa',          varargout{1} = gcsa(varargin{:});
    case 'wrap',          varargout{1} = wrap(varargin{:});
    case 'palette',       varargout{1} = palette(varargin{:});
    case 'link_limited',  varargout{1} = link_limited(varargin{:});
    case 'edge_limited',  varargout{1} = edge_limited(varargin{:});
    case 'ebno_ticks',    varargout{1} = ebno_ticks(varargin{:});
    otherwise, error('kpi_print_text:cmd', 'kpi_print_text: unknown command %s', cmd);
end
end

function [s, W] = leave_out(res, what, label, unit)
W = struct('k', numel(res), 'n', NaN, 'out_w', NaN, 'in_w', NaN, 'rule_w', NaN, 'out_u', NaN, 'in_u', NaN, ...
    'rule_u', NaN, 'lowest', {{}});
if isempty(res)
    s = sprintf('%s: no %s in the file', what, unit);
    return;
end
nm = 'threat'; if isfield(res, 'combo'), nm = 'combo'; end
k = numel(res); n = [res.n];
W.n = sum(n);
W.out_w = sum(n .* [res.dqn_out]) / sum(n);
W.in_w = sum(n .* [res.dqn_in]) / sum(n);
W.rule_w = sum(n .* [res.rule]) / sum(n);
W.out_u = mean([res.dqn_out]); W.in_u = mean([res.dqn_in]); W.rule_u = mean([res.rule]);
[~, ix] = sort([res.dqn_out]);
ix = ix(1:min(3, k));
W.lowest = arrayfun(@(i) sprintf('%s %s', res(i).(nm), pc(res(i).dqn_out)), ix, 'UniformOutput', false);
s = sprintf(['%s, %s: %s of the recoverable episodes, weighted by episode (%d episodes in %d %s); averaged over the %d %s: ' ...
    '%s; trained on them: %s weighted, %s averaged; rule + escalation: %s weighted, %s averaged; lowest never trained: %s'], ...
    what, label, pc(W.out_w), W.n, k, unit, k, unit, pc(W.out_u), pc(W.in_w), pc(W.in_u), pc(W.rule_w), pc(W.rule_u), ...
    strjoin(W.lowest, ', '));
end

function s = kpi1_all(m)
allf = sprintf('all frames, every Eb/N0: accuracy %.2f%%, macro-F1 %.2f%% [%.2f, %.2f] (95%% bootstrap over sub-runs)', ...
    m.overall_accuracy_pct, m.macro_f1_pct, m.ci95.macro_f1);
thr = NaN; if isfield(m, 'kpi1_threshold_db'), thr = m.kpi1_threshold_db; end
if ~isfinite(thr)
    s = [allf '; the headline: not reached, no Eb/N0 threshold chosen on validation'];
    return;
end
ci = ' (interval not saved)';
if isfield(m.ci95, 'macro_f1_above') && numel(m.ci95.macro_f1_above) == 2
    ci = sprintf(' [%.2f, %.2f]', m.ci95.macro_f1_above);
end
[mn, im] = min(m.class_f1_above_threshold_pct);
s = sprintf('%s; the headline, from %g dB (the threshold chosen on validation): macro-F1 %.2f%%%s, lowest class %.2f%% (%s)', ...
    allf, thr, m.macro_f1_above_threshold_pct, ci, mn, class_name(m, im));
end

function s = kpi1_every(m)
ec = m.every_class;
pre = 'beside KPI 1, every class F1 >= 90% (the stricter reading, its threshold chosen on validation): ';
if isfinite(ec.threshold_db)
    met = 'not met';
    if all(ec.class_f1_above_threshold_pct >= 90), met = 'met'; end
    s = sprintf('%sfrom %g dB, macro-F1 %.2f%%, lowest class %.2f%% (%s)', pre, ec.threshold_db, ...
        ec.macro_f1_above_threshold_pct, min(ec.class_f1_above_threshold_pct), met);
    return;
end
s = [pre 'not reached: no Eb/N0 threshold chosen on validation gives every class an F1 of at least 90% (not met)'];
if isfield(m, 'kpi1_threshold_db') && isfinite(m.kpi1_threshold_db) && isfield(m, 'class_f1_above_threshold_pct')
    [mn, im] = min(m.class_f1_above_threshold_pct);
    s = sprintf('%s; at the headline threshold of %g dB the lowest class is %s %.2f%%', s, m.kpi1_threshold_db, ...
        class_name(m, im), mn);
end
end

function s = kpi4_lower(names, point, ci)
s = '';
if isempty(names) || size(ci, 2) < 2, return; end
lo = ci(:, 1)'; point = point(:)';
ok = isfinite(lo);
if ~any(ok), return; end
n = numel(names);
below = find(ok & lo < 90);
tail = '';
if ~isempty(below)
    tail = sprintf('; lower bound below 90%%: %s', strjoin(arrayfun(@(i) sprintf('%s %.1f', names{i}, lo(i)), below, ...
        'UniformOutput', false), ', '));
end
if any(~ok), tail = sprintf('%s; lower bound not saved for %d', tail, sum(~ok)); end
s = sprintf(['inside the envelope, by the 95%% lower bound (the status above counts the point estimates, as registered): ' ...
    '%d of %d threats have a lower bound >= 90%% (point estimates: %d of %d)%s'], sum(lo(ok) >= 90), n, ...
    sum(point >= 90), n, tail);
end

function s = kpi7_spread(sp, target)
if ~isfinite(sp(3))
    word = 'not committed (no interval saved)';
elseif sp(3) <= target
    word = sprintf('committed (upper bound <= %g)', target);
else
    word = sprintf('not committed (upper bound > %g)', target);
end
pt = 'above the target';
if sp(1) <= target, pt = 'within the target'; end
s = sprintf(['speed spread, committed reading: point estimate %.1f points, 95%% interval upper bound %.1f, target <= %g -> %s; ' ...
    'the status above counts the point estimate (%s)'], sp(1), sp(3), target, word, pt);
end

function s = edge_distance(en, inom)
d = 1;
dist = strjoin(arrayfun(@(e, k) sprintf('%g dB %.2f km', e, k), en.ebno, en.km, 'UniformOutput', false), ' | ');
it = arrayfun(@(i) edge_item(en.cells{i}, en.edge_commit_db(d, i), en.edge_commit_km(d, i)), inom(:)', 'UniformOutput', false);
s = sprintf(['edge map, COMMITTED distance edge per (threat, nominal level), delay %d: the lowest Eb/N0 down to which the ' ...
    'points from 15 dB are COMMITTED, with its distance (profile A link budget, link_distance_km.m: %s); the dB after a ' ...
    'threat is its own nominal level, not an Eb/N0: %s'], en.delays(d), dist, strjoin(it, ', '));
end

function t = edge_item(label, e, km)
if isnan(e)
    t = sprintf('%s: no COMMITTED point', label);
else
    t = sprintf('%s: down to %g dB Eb/N0 (%.2f km)', label, e, km);
end
end

function s = edge_flight(V, f)
s = '';
if ~isfield(V, 'k') || ~isfield(V, 'n') || ~isfinite(V.k) || V.n <= 0, return; end
fs = V.k / V.n;
if abs(fs - V.value) < 1e-9, return; end
s = [' fl ' sprintf(f, 100 * fs)];
end

function s = gcsa(lines)
lines = cellstr(lines);
s = 'directional GCS antenna on the uplink (results/gcs_antenna.txt)';
pre = 'System: ';
k = find(startsWith(lines, pre), 1);
if ~isempty(k), s = [s ': ' strtrim(lines{k}(numel(pre) + 1:end))]; end
end

function c = wrap(t, w)
words = strsplit(strtrim(char(t)), ' ');
c = {};
cur = '';
for i = 1:numel(words)
    wd = words{i};
    if isempty(cur)
        cur = wd;
    elseif numel(cur) + 1 + numel(wd) <= w
        cur = [cur ' ' wd]; %#ok<AGROW>
    else
        c{end+1} = cur; %#ok<AGROW>
        cur = wd;
    end
end
c{end+1} = cur;
end

function c = palette(n)
P = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0.49 0.18 0.56; 0.47 0.67 0.19; 0.30 0.75 0.93; ...
    0.64 0.08 0.18; 0.25 0.25 0.25; 0.90 0.50 0.70; 0.55 0.35 0.15; 0.00 0.60 0.50; 0.60 0.60 0.00];
c = P(mod(0:n-1, size(P, 1)) + 1, :);
end

function L = link_limited(loss, ratio_ok)
L = ratio_ok .* loss >= 1;
end

function L = edge_limited(Em, ebno, ratio_ok)
L = false(1, numel(ebno));
if isempty(Em) || ~isfield(Em, 'EM') || ~all(isfield(Em.EM, {'ebno', 'clean'})) || ~isfield(Em.EM.clean, 'link'), return; end
loss = [Em.EM.clean.link.value];
if numel(loss) ~= numel(Em.EM.ebno), return; end
[tf, ix] = ismember(ebno, Em.EM.ebno);
L(tf) = link_limited(loss(ix(tf)), ratio_ok);
end

function t = ebno_ticks(ebno, L)
t = cell(1, numel(ebno));
for i = 1:numel(ebno)
    t{i} = sprintf('%g', ebno(i));
    if L(i), t{i} = [t{i} ' L']; end
end
end

function t = class_name(m, i)
t = '?';
if isfield(m, 'classes')
    cl = cellstr(string(m.classes));
    if i <= numel(cl), t = cl{i}; end
end
end

function t = pc(x)
if isfinite(x), t = sprintf('%.1f%%', 100 * x); else, t = 'n/a'; end
end
