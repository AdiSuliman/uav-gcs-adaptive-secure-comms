function varargout = clt_step(op, varargin)
%CLT_STEP  C1d's calibrated lost-branch acceptance per monitor (PP.lb_accept, policy_monitor.m): a cycle
%   whose class is antenna_fault or airframe_shadowing counts as hostile only with p_LB, the fused posterior
%   of the two, at or above tau_hi, or with harm evidence in the last n cycles of the confirmation
%   (monitor_confirm.m). Run after the degradation test and the monitors' thresholds, before the drop
%   threshold's re-choice and the drop alarm's own confirmation (choose_drop_threshold.m).
%   [L, lines] = clt_step('choose', form, MON, MONP, cs, Tc, fit, chk, Tv, onv, thv, thn, Kv, sp, force)
%     Tc, Tv    monitor_trace.m with PP.record_lb of the clean validation episodes and of the validation
%               split's single threats; fit, chk which episodes of Tc belong to the fit and the check half
%               (clean_halves.m); onv, thv, thn as dconf_step.m; Kv, sp the tables (link_env.m) and split of Tv:
%               a threat episode is harmed when no response does not restore its geometry (BER and packet loss)
%     MON, MONP the monitors and their readings (cf, pick); cs the sweeper's confirmation ([] none)
%     Grid: Inf (harm only) and the 99th, 95th, 90th, 75th and 50th percentiles of p_LB over the fit half's
%     clean cycles whose class is a lost-branch class. Per monitor, from Inf down the grid on the check
%     half: a value passes when the clean episodes whose first confirmation needs the lost-branch class
%     path have a one-sided 95% Clopper-Pearson bound <= 1.5%; the scan stops at the first failure and
%     tau_hi is the last passing value (Inf, the miss printed, when Inf fails). Guards at tau_hi on the
%     threats against the same monitor without it: antenna_fault and airframe_shadowing on the harmed
%     episodes, the never share grows by at most 5 points and the p90 confirmed delay by at most 3
%     cycles; every other threat, the confirmed alarm is the same in every cycle from the onset on.
%     Adopted only if the guards hold.
%     force (the smoke only, wf_force.m): tau_hi deployed for every monitor whatever the guards say;
%     L(m).forced holds it and L(m).rule_accept what the rule adopted ([] none).
%     L(m): monitor, grid, k (lost-branch-first count per grid value, NaN not read), n, tau, miss,
%     guard_ok, fail, accept ([] or struct('tau_hi', tau)), budget, forced, rule_accept.
%   [B, line] = clt_step('budget', T, form, thr, cf, cs, tau, label, cdr)
%     The clean episodes of T with a confirmed alarm and those whose first confirmation needs each path,
%     with their bounds against the shares of KPI 6's 5%: lost-branch class 1.5%, drop alarm 2.0%,
%     degradation and the other classes 1.5%; "union bound met" only if all three hold. The drop alarm's
%     count reads the monitor without it (threshold Inf: with tau it is no harm evidence either). cdr the drop
%     alarm's own confirmation ([] or absent: none). The lines of 'choose' read the monitor before the
%     drop threshold's re-choice; choose_drop_threshold.m prints the monitor as deployed.
switch op
    case 'choose'
        [varargout{1:2}] = choose(varargin{:});
    case 'budget'
        [varargout{1:2}] = budget(varargin{:});
    otherwise
        error('clt_step:op', 'clt_step: unknown operation %s', op);
end
end

function [L, lines] = choose(form, MON, MONP, cs, Tc, fit, chk, Tv, onv, thv, thn, Kv, sp, force)
SH = 0.015; NEV = 0.05; P90 = 3;
LBC = {'antenna_fault', 'airframe_shadowing'};
Tf = sub_trace(Tc, fit); Tk = sub_trace(Tc, chk); nk = size(Tk.eg, 1);
x = Tf.plb(Tf.lb);
G = Inf;
if ~isempty(x), G = [Inf, prctile(x(:)', [99 95 90 75 50])]; end
gn = {'Inf (harm only)', 'q99', 'q95', 'q90', 'q75', 'q50'};
lines = {sprintf(['Calibrated lost-branch acceptance per monitor: grid of p_LB from %d fit-half clean cycles whose class is a ' ...
    'lost-branch class (%s); scanned from Inf on the check half (%d clean episodes), a value passes at a one-sided 95%% ' ...
    'bound <= %.1f%% of the episodes first confirmed by the lost-branch class path'], numel(x), ...
    strjoin(arrayfun(@(i) sprintf('%s %.4g', gn{i}, G(i)), 1:numel(G), 'UniformOutput', false), ', '), nk, 100 * SH)};
if isempty(x), lines{end+1} = '  no fit-half clean cycle reads a lost-branch class: the grid is Inf alone'; end
onv = onv(:)'; thv = thv(:)';
ih = sub2ind(size(Kv.restored), Tv.scn, Tv.s, Kv.na + 0 * Tv.s, sp + 0 * Tv.s, Tv.r);
hv = ~(Kv.restored(ih) & Kv.restored_plr(ih)); hv = hv(:)';
lbt = ismember(thv, LBC);
L = struct('monitor', MON(:)', 'grid', G, 'k', [], 'n', nk, 'tau', Inf, 'miss', false, 'guard_ok', false, 'fail', {{}}, ...
    'accept', [], 'budget', [], 'forced', [], 'rule_accept', []);
for m = 1:numel(MON)
    cf = MONP(m).cf; thr = MONP(m).pick;
    k = nan(1, numel(G)); jp = 0;
    for j = 1:numel(G)
        B = budget(Tk, form, thr, cf, cs, G(j), '');
        k(j) = B.lb;
        if cp_upper(k(j), nk) > SH, break; end
        jp = j;
    end
    L(m).k = k; L(m).miss = jp == 0; L(m).tau = G(max(jp, 1));
    tau = L(m).tau;
    lines{end+1} = sprintf('  %-15s threshold %6.1f: lost-branch-first clean episodes per grid value %s -> tau_hi %s%s', MON{m}, thr, ...
        strjoin(arrayfun(@(j) sprintf('%s %d (bound %.2f%%)', gn{j}, k(j), 100 * cp_upper(k(j), nk)), find(~isnan(k)), ...
        'UniformOutput', false), ', '), tau_txt(tau), ternary(L(m).miss, sprintf(' (MISS: Inf already exceeds %.1f%%)', 100 * SH), '')); %#ok<AGROW>
    c0 = monitor_confirm(Tv, form, thr, cf, cs);
    c1 = monitor_confirm(Tv, form, thr, cf, cs, [], tau);
    d0 = ep_delays(c0, Tv.onset); d1 = ep_delays(c1, Tv.onset);
    fail = {};
    for q = LBC(ismember(LBC, thn))
        h = onv & strcmp(thv, q{1}) & hv;
        [n0, p0] = never_p90(d0(h)); [n1, p1] = never_p90(d1(h));
        ok = n1 <= n0 + NEV + 1e-12 && fill_inf(p1) <= fill_inf(p0) + P90;
        if ~ok, fail{end+1} = sprintf('%s harmed slower', q{1}); end %#ok<AGROW>
        u = onv & strcmp(thv, q{1}) & ~hv;
        lines{end+1} = sprintf(['    %-20s harmed %4d: never %.1f%% -> %.1f%%, p90 %s -> %s cycles%s | unharmed %4d: confirmed ' ...
            '%.1f%% -> %.1f%% (the cost on unharmed lost-branch alarms)'], q{1}, sum(h), 100 * n0, 100 * n1, num_txt(p0), ...
            num_txt(p1), ternary(ok, '', ' (GUARD FAILS)'), sum(u), 100 * mean(~isnan(d0(u))), 100 * mean(~isnan(d1(u)))); %#ok<AGROW>
    end
    o = find(onv & ~lbt);
    nd = sum(arrayfun(@(i) ~isequal(c0(i, Tv.onset(i) + 1:end), c1(i, Tv.onset(i) + 1:end)), o));
    na = sum(any(c0(o, :) ~= c1(o, :), 2));
    if nd > 0, fail{end+1} = sprintf('%d episodes of another threat change their confirmed alarm', nd); end %#ok<AGROW>
    lines{end+1} = sprintf(['    every other threat: %d of %d episodes with another confirmed-alarm series from the onset%s ' ...
        '(%d before it included)'], nd, numel(o), ternary(nd > 0, ' (GUARD FAILS)', ''), na); %#ok<AGROW>
    L(m).fail = fail; L(m).guard_ok = isempty(fail);
    if L(m).guard_ok, L(m).accept = struct('tau_hi', tau); end
    [B0, b0] = budget(Tk, form, thr, cf, cs, [], 'without it, before the re-choice');
    [B1, b1] = budget(Tk, form, thr, cf, cs, tau, sprintf('at tau_hi %s, before the re-choice', tau_txt(tau)));
    L(m).budget = struct('ref', B0, 'cand', B1);
    lines = [lines, {['    ' b0], ['    ' b1]}]; %#ok<AGROW>
    if ~isempty(force) && force
        L(m).rule_accept = L(m).accept; L(m).forced = tau; L(m).accept = struct('tau_hi', tau);
        lines{end+1} = sprintf(['  Lost-branch acceptance FORCED for %s (smoke only, not an adoption): tau_hi %s; the rule would ' ...
            '%s'], MON{m}, tau_txt(tau), ternary(isempty(L(m).rule_accept), 'not adopt it', 'adopt it')); %#ok<AGROW>
    end
    lines{end+1} = sprintf('  -> %s: %s', MON{m}, ternary(isempty(L(m).accept), ['not adopted (' strjoin(fail, '; ') ')'], ...
        sprintf('%s at tau_hi %s', ternary(isempty(L(m).forced), 'adopted', 'FORCED'), tau_txt(tau)))); %#ok<AGROW>
end
end

function [B, line] = budget(T, form, thr, cf, cs, tau, label, cdr)
% First confirmation per path: without that path the monitor does not confirm at that cycle.
% cdr: the drop alarm's own confirmation (PP.confirm_drop), [] or absent: none.
if nargin < 8, cdr = []; end
[c, a, ~, ot] = monitor_confirm(T, form, thr, cf, cs, cdr, tau);
cn = monitor_confirm(T, form, Inf, cf, cs, [], tau);  % without the drop alarm, nor its harm evidence
acc = T.lb & ot;                                     % cycles that alarm on a lost-branch class
o1 = ot; o1(acc) = T.dg(acc);
c1 = movsum(double(o1 | a), [cf(2) - 1, 0], 2) >= cf(1);
if ~isempty(cs), c1 = c1 | movsum(double(T.sw), [cs(2) - 1, 0], 2) >= cs(1); end
c2 = movsum(double(acc | a), [cf(2) - 1, 0], 2) >= cf(1);
if ~isempty(cdr)                                      % the drop alarm's own confirmation stays in both
    cd = movsum(double(a), [cdr(2) - 1, 0], 2) >= cdr(1);
    c1 = c1 | cd; c2 = c2 | cd;
end
[f, t1] = max(c, [], 2); i1 = find(f); ix = sub2ind(size(c), i1, t1(i1));
n = size(c, 1);
B = struct('n', n, 'k', numel(i1), 'lb', sum(~c1(ix)), 'drop', sum(~cn(ix)), 'rest', sum(~c2(ix)));
sh = [0.015 0.02 0.015]; v = [B.lb B.drop B.rest];
up = arrayfun(@(x) cp_upper(x, n), v);
B.met = all(up <= sh);
line = sprintf(['%s: clean episodes confirmed %d/%d; first by the lost-branch class %d (bound %.2f%%, share 1.5%%), the drop ' ...
    'alarm %d (bound %.2f%%, share 2.0%%), degradation and the other classes %d (bound %.2f%%, share 1.5%%): union bound %s'], ...
    label, B.k, n, v(1), 100 * up(1), v(2), 100 * up(2), v(3), 100 * up(3), ternary(B.met, 'met', 'NOT met'));
end

function [nv, p9] = never_p90(d)
% The never-confirmed share and the p90 (nearest rank) of the confirmed delays d.
nv = mean(isnan(d)); if isempty(d), nv = 0; end
x = sort(d(~isnan(d))); p9 = NaN;
if ~isempty(x), p9 = x(min(numel(x), max(1, round(0.9 * numel(x))))); end
end

function d = ep_delays(c, onset)
% Cycles from the onset to the first confirmed alarm per episode (NaN: never); the decision of cycle
% onset + 1 reads the threat's first frame (0).
d = nan(1, size(c, 1));
for i = 1:size(c, 1)
    k = find(c(i, onset(i) + 1:end), 1);
    if ~isempty(k), d(i) = k - 1; end
end
end

function T = sub_trace(T, m)
% The episodes m of a monitor trace (monitor_trace.m).
for f = fieldnames(T)'
    if size(T.(f{1}), 1) > 1, T.(f{1}) = T.(f{1})(m(:), :); else, T.(f{1}) = T.(f{1})(m(:)'); end
end
end

function x = fill_inf(x)
x(isnan(x)) = Inf;
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion (NaN without trials).
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end

function t = tau_txt(tau)
if isinf(tau), t = 'Inf (harm only)'; else, t = sprintf('%.4g', tau); end
end

function t = num_txt(v)
if isnan(v), t = '-'; else, t = sprintf('%g', v); end
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
