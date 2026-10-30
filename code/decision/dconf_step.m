function [D, lines] = dconf_step(form, GF, MON, MONP, cs, Tc, fit, chk, Tv, onv, thv, thn, sev1, FA, force)
%DCONF_STEP  C1d's choice, per monitor, of the drop alarm's own confirmation (PP.confirm_drop,
%   policy_monitor.m), a coordinate step after the degradation test's choice (choose_drop_threshold.m).
%   The drop alarm crossing by itself confirms: at least k of the last n cycles carried it. A
%   candidate [k n] of C.confirm_drop_cand, in its order, is read against the same monitor without
%   it, at the monitor's threshold in force (MONP), on the clean validation episodes of the check
%   half and the validation split's single threats.
%   form      'class_cusum' (the CUSUM grid is the one extended; the median window is not run)
%   GF        the form's threshold grid as it is (choose_drop_threshold.m THC), most sensitive first
%   MON, MONP the monitors and their readings (monitor, cf, pick), cs the sweeper's confirmation ([] none)
%   Tc        monitor_trace.m of the clean validation episodes; fit, chk: logical, which episodes
%             belong to the fit half and the check half of the geometries (clean_halves.m)
%   Tv        monitor_trace.m of the single threats, onv which have the threat on the air, thv their
%             threat, thn the threats, sev1 which fly the smallest path-loss level; FA the bound
%   The threshold of a candidate is re-chosen on the fit half: the most sensitive threshold of the grid
%   extended upward (GF top x C.confirm_drop_ext) whose one-sided 95% Clopper-Pearson bound of the
%   clean episodes with a confirmed alarm is within FA. It is admissible for a monitor when, on the
%   check half and the threats, against the monitor without it:
%   (a) jamming and tone_jamming: median and p90 confirmed delay and the never share do not grow;
%   (b) every other threat: the never share grows by at most 1 point, the p90 by at most 1 cycle;
%   (c) the clean episodes with a confirmed alarm are not more; (c') nor those whose first
%       confirmation comes from the drop alarm alone;
%   (d) path_loss: the median delay is at least 1 cycle shorter with a one-sided 95% upper bound of the
%       paired median difference below 0 (bootstrap of the threat flights' geometries, 2000 draws,
%       fixed seed), and the p90 not longer; (d') at the smallest level alone the median is not longer.
%   The first admissible candidate of a monitor is adopted. D(m): monitor, cand ([] none), pick, j,
%   grid (the monitor's threshold grid), ref and cands (the readings).
%   force (the smoke only, wf_force.m): a candidate [k n] deployed for every monitor instead, admissible
%   or not, at its re-chosen threshold, else the extended grid's top; D(m).forced holds it and
%   D(m).rule_pick what the rule adopted ([] none).
if nargin < 15, force = []; end
assert(strcmp(form, 'class_cusum'), 'dconf_step: the threshold grid extended is the CUSUM''s, not that of %s', form);
C = decision_config();
GX = [GF, GF(end) * C.confirm_drop_ext];
Tf = sub_trace(Tc, fit); Tk = sub_trace(Tc, chk);
nf = size(Tf.eg, 1); nk = size(Tk.eg, 1);
cl = Tv.r(:);
pl = strcmp(thn, 'path_loss'); plm = onv(:) & strcmp(thv(:), 'path_loss');
D = struct('monitor', MON(:)', 'cand', [], 'pick', NaN, 'j', NaN, 'grid', GF, 'ref', [], 'cands', [], 'forced', [], 'rule_pick', []);
lines = {sprintf(['Drop alarm''s own confirmation (coordinate step per monitor after the degradation test): candidates %s, ' ...
    'thresholds re-chosen on the fit half (%d clean episodes) from the grid extended to %g, read on the check half (%d clean ' ...
    'episodes) and %d threat episodes against the same monitor without it'], strjoin(arrayfun(@(i) sprintf('[%d %d]', ...
    C.confirm_drop_cand(i, :)), 1:size(C.confirm_drop_cand, 1), 'UniformOutput', false), ', '), nf, GX(end), nk, sum(onv))};
for m = 1:numel(MON)
    cf = MONP(m).cf; thr0 = MONP(m).pick;
    D(m).pick = thr0; D(m).j = MONP(m).j;
    ref = reading(Tk, Tv, onv, thv, thn, form, thr0, cf, cs, []);
    D(m).ref = ref;
    lines{end+1} = sprintf('  %-15s without it: threshold %6.1f, clean check episodes confirmed %d/%d (first by the drop alarm %d), path_loss delay median %s, p90 %s, never %.1f%%', ...
        MON{m}, thr0, ref.k, nk, ref.k_drop, num_txt(ref.lat.median, pl), num_txt(ref.lat.p90, pl), 100 * at(ref.lat.never, pl)); %#ok<AGROW>
    D(m).cands = struct('cd', {}, 'pick', {}, 'ok', {}, 'fail', {}, 'k', {}, 'k_drop', {}, 'lat', {}, 'ub', {});
    for ci = 1:size(C.confirm_drop_cand, 1)
        cdr = C.confirm_drop_cand(ci, :);
        kf = arrayfun(@(t) sum(any(monitor_confirm(Tf, form, t, cf, cs, cdr), 2)), GX);
        j = find(arrayfun(@(x) cp_upper(x, nf), kf) <= FA, 1);
        x = struct('cd', cdr, 'pick', NaN, 'ok', false, 'fail', {{}}, 'k', NaN, 'k_drop', NaN, 'lat', [], 'ub', NaN);
        if isempty(j)
            x.fail = {'no threshold of the extended grid holds the bound on the fit half'};
        else
            x.pick = GX(j);
            r = reading(Tk, Tv, onv, thv, thn, form, x.pick, cf, cs, cdr);
            x.k = r.k; x.k_drop = r.k_drop; x.lat = r.lat;
            x.ub = judge_ub(r, ref, plm, cl);
            x.fail = judge(r, ref, thn, pl, plm, sev1, x.ub);
            x.ok = isempty(x.fail);
            if x.ok && isempty(D(m).cand)
                D(m).cand = cdr; D(m).pick = x.pick; D(m).j = j; D(m).grid = GX;
            end
        end
        D(m).cands(end+1) = x;
        lines{end+1} = sprintf('    [%d %d]: %s', cdr, cand_txt(x, nk, pl)); %#ok<AGROW>
        if x.ok && isempty(force), break; end
    end
    if ~isempty(force)
        D(m).rule_pick = D(m).cand;
        x = D(m).cands(ismember(vertcat(D(m).cands.cd), force, 'rows'));
        D(m).cand = force; D(m).forced = force; D(m).grid = GX;
        D(m).pick = x.pick; if isnan(x.pick), D(m).pick = GX(end); end
        D(m).j = find(GX == D(m).pick, 1);
        lines{end+1} = sprintf('  Drop alarm''s own confirmation FORCED for %s (smoke only, not an adoption): [%d %d] at threshold %.1f; the rule would adopt %s', ...
            MON{m}, force, D(m).pick, ternary(isempty(D(m).rule_pick), 'none', sprintf('[%d %d]', D(m).rule_pick))); %#ok<AGROW>
    end
    lines{end+1} = sprintf('  -> %s: %s', MON{m}, ternary(isempty(D(m).cand), 'not adopted', ...
        sprintf('%s [%d %d] at threshold %.1f', ternary(isempty(D(m).forced), 'adopted', 'FORCED'), D(m).cand, D(m).pick))); %#ok<AGROW>
end
end

function r = reading(Tk, Tv, onv, thv, thn, form, thr, cf, cs, cdr)
% The check half's clean episodes with a confirmed alarm (k), those whose first confirmation the drop
% alarm alone gives (k_drop), and the threats' confirmed delays (per episode d, per threat lat).
[c, ~, cn] = monitor_confirm(Tk, form, thr, cf, cs, cdr);
[f, t1] = max(c, [], 2);
i1 = find(f);
r = struct('k', numel(i1), 'k_drop', sum(~cn(sub2ind(size(c), i1, t1(i1)))), 'd', [], 'lat', []);
cv = monitor_confirm(Tv, form, thr, cf, cs, cdr);
r.d = ep_delays(cv, Tv.onset);
r.lat = threat_delays(r.d, onv, thv, thn);
end

function fail = judge(r, ref, thn, pl, plm, sev1, ub)
% The criteria a candidate's reading r misses against the reference ref.
fail = {};
for q = 1:numel(thn)
    c = fill_inf(r.lat.median(q)); c9 = fill_inf(r.lat.p90(q)); v = fill_inf(ref.lat.median(q)); v9 = fill_inf(ref.lat.p90(q));
    if any(strcmp(thn{q}, {'jamming', 'tone_jamming'}))
        if c > v || c9 > v9 || r.lat.never(q) > ref.lat.never(q), fail{end+1} = sprintf('(a) %s grows', thn{q}); end %#ok<AGROW>
    else
        if r.lat.never(q) > ref.lat.never(q) + 0.01 || c9 > v9 + 1, fail{end+1} = sprintf('(b) %s worse', thn{q}); end %#ok<AGROW>
    end
end
if r.k > ref.k, fail{end+1} = '(c) more clean episodes confirmed'; end
if r.k_drop > ref.k_drop, fail{end+1} = '(c'') more clean episodes first confirmed by the drop alarm'; end
if ~any(pl)
    fail{end+1} = '(d) no path_loss episodes';
else
    if ~(fill_inf(ref.lat.median(pl)) - fill_inf(r.lat.median(pl)) >= 1 && ub < 0 && fill_inf(r.lat.p90(pl)) <= fill_inf(ref.lat.p90(pl)))
        fail{end+1} = '(d) path_loss median not 1 cycle shorter with the bound below 0, or p90 longer'; %#ok<AGROW>
    end
    m1 = plm(:) & sev1(:);
    if med_conf(r.d(m1)) > med_conf(ref.d(m1)), fail{end+1} = '(d'') the smallest level slower'; end %#ok<AGROW>
end
end

function ub = judge_ub(r, ref, plm, cl)
% One-sided 95% upper bound of the paired difference of the path_loss medians (candidate less
% reference) over the confirmed episodes, the geometries resampled together.
ub = NaN;
if ~any(plm), return; end
dc = r.d(plm); dr = ref.d(plm); [~, ~, j] = unique(cl(plm));
nU = max(j); B = 2000;
ix = accumarray(j, (1:numel(j))', [], @(v) {v});
rs = RandStream('mt19937ar', 'Seed', 112);
bs = nan(B, 1);
for b = 1:B
    e = vertcat(ix{randi(rs, nU, nU, 1)});
    bs(b) = median(dc(e), 'omitnan') - median(dr(e), 'omitnan');
end
bs = sort(bs(~isnan(bs)));
if ~isempty(bs), ub = bs(min(numel(bs), max(1, round(0.95 * numel(bs))))); end
end

function d = ep_delays(c, onset)
% Cycles from the onset to the first confirmed alarm per episode (NaN: never); the decision of cycle
% onset + 1 reads the threat's first frame (0).
d = nan(size(c, 1), 1);
for i = 1:size(c, 1)
    k = find(c(i, onset(i) + 1:end), 1);
    if ~isempty(k), d(i) = k - 1; end
end
end

function L = threat_delays(d, on, thr, names)
% Per threat (severities pooled, episodes with the threat on the air): median, p90 (nearest rank) and
% the never-confirmed share of the delays d.
L = struct('threat', {names}, 'n', zeros(1, numel(names)), 'median', nan(1, numel(names)), ...
    'p90', nan(1, numel(names)), 'never', zeros(1, numel(names)));
for q = 1:numel(names)
    m = on(:) & strcmp(thr(:), names{q}); x = sort(d(m & ~isnan(d)));
    L.n(q) = sum(m); L.never(q) = mean(isnan(d(m)));
    if ~isempty(x), L.median(q) = median(x); L.p90(q) = x(min(numel(x), max(1, round(0.9 * numel(x))))); end
end
end

function T = sub_trace(T, m)
% The episodes m of a monitor trace (monitor_trace.m).
for f = fieldnames(T)'
    if size(T.(f{1}), 1) > 1, T.(f{1}) = T.(f{1})(m(:), :); else, T.(f{1}) = T.(f{1})(m(:)'); end
end
end

function x = med_conf(d)
% Median of the confirmed delays (Inf: none confirmed).
x = median(d(~isnan(d)));
if isnan(x), x = Inf; end
end

function x = fill_inf(x)
x(isnan(x)) = Inf;
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion (NaN without trials).
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = cand_txt(x, nk, pl)
if isnan(x.pick)
    t = ['not admissible: ' strjoin(x.fail, '; ')]; return
end
t = sprintf('threshold %.1f, clean check episodes confirmed %d/%d (first by the drop alarm %d), path_loss delay median %s, p90 %s, never %.1f%%, bound of the median difference %.2f: %s', ...
    x.pick, x.k, nk, x.k_drop, num_txt(x.lat.median, pl), num_txt(x.lat.p90, pl), 100 * at(x.lat.never, pl), x.ub, ...
    ternary(x.ok, 'ADMISSIBLE', ['not admissible: ' strjoin(x.fail, '; ')]));
end

function t = num_txt(v, k)
v = at(v, k);
if isnan(v), t = '-'; else, t = sprintf('%g', v); end
end

function x = at(v, k)
% The entry of v selected by the logical k, NaN when there is none.
x = NaN;
if any(k), x = v(find(k, 1)); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
