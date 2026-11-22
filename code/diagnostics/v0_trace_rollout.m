function [R, X] = v0_trace_rollout(kind, PP, K, spec, split, agent, opt, seed)
%V0_TRACE_ROLLOUT  rollout_policy.m on the validation split with a per-cycle trace of the
%   monitor and the decision (V0 diagnostic, v0_diag.m). The same seed gives the same draws
%   and decisions as rollout_policy.m; v0_diag.m checks that on its first batch of every policy.
%   Refuses any split but validation and pools that hold a later split (v0_guard.m).
%   R (1 x NE): ret, switches, recovered, held, t_rec, recoverable, r, t0 (first cycle after the
%     onset), D (signalling delay in cycles), as rollout_policy.m
%   X (T x NE), per decision cycle t (the decision reads the frame of cycle t - 1):
%     cfg    configuration requested before the decision; a the decision
%     cls    monitor class, index into [PP.classes, 'unknown']
%     conf, deg, dal   confirmed alarm, degraded link, drop alarm
%     degn, confn      consecutive degraded / confirmed cycles (policy_monitor.m deg_n, conf_n)
%     since  cycles since the last change, as the escalation reads it (NaN on a change)
%     esc    escalated; path 1 out of no_action on a class alarm, 2 out of an applied
%            configuration that stays degraded, 3 on a drop alarm read as none
%     qgap   best configuration other than no_action minus no_action, over the shield's
%            allowed set (dqn kinds; NaN otherwise or where no_action is not allowed)
%     ok     BER and packet loss restored on the frame of cycle t; post: after the onset
v0_guard('split', split);
v0_guard('check', PP);
if nargin < 7 || isempty(opt), opt = struct(); end
rs = RandStream('mt19937ar', 'Seed', seed);
opt.rs = RandStream('mt19937ar', 'Seed', seed + 1);
[E, obs] = link_env('reset', PP, K, spec, split, rs);
NE = E.NE; T = spec.T; na = K.na;
mem = [];
cls_list = [cellstr(string(PP.classes(:)')), {'unknown'}];
z = zeros(T, NE); f = false(T, NE);
X = struct('cfg', z, 'a', z, 'cls', z, 'conf', f, 'deg', f, 'dal', f, 'degn', z, 'confn', z, 'since', nan(T, NE), ...
    'esc', f, 'path', z, 'qgap', nan(T, NE), 'ok', f, 'post', f);
tr = struct('r', z, 'ch', f, 'gap', f, 'recov', f);
for t = 1:T
    cfg0 = E.cfg;
    [a, mem, dinf] = policy_decide(kind, obs, E.cfg, mem, PP, agent, opt);
    ch = a ~= cfg0;
    X.cfg(t, :) = cfg0; X.a(t, :) = a;
    X.cls(t, :) = cellfun(@(c) find(strcmp(cls_list, c), 1), dinf.cls);
    X.conf(t, :) = dinf.confirmed; X.deg(t, :) = dinf.degraded; X.dal(t, :) = dinf.drop_alarm;
    X.degn(t, :) = mem.deg_n; X.confn(t, :) = mem.conf_n;
    sb = mem.since - double(~mem.pend);                 % undo policy_monitor('change') on the rows that kept
    sb(ch) = NaN;
    X.since(t, :) = sb;
    e = dinf.escalated; none = strcmp(dinf.cls, 'none');
    p = zeros(1, NE); p(e & none) = 3; p(e & ~none & cfg0 == na) = 1; p(e & ~none & cfg0 ~= na) = 2;
    X.esc(t, :) = e; X.path(t, :) = p;
    if ~isempty(dinf.q)
        q = dinf.q; qo = q; qo(na, :) = -inf;
        g = max(qo, [], 1) - q(na, :); g(~isfinite(g)) = NaN;
        X.qgap(t, :) = g;
    end
    [E, r, obs, info] = link_env('step', E, PP, K, a);
    X.ok(t, :) = info.restored & info.restored_plr; X.post(t, :) = info.post;
    tr.r(t, :) = r; tr.ch(t, :) = info.changed; tr.gap(t, :) = info.fec_gap; tr.recov(t, :) = info.recoverable;
end
post = X.post; ok = X.ok;
R.ret = mean(tr.r, 1);
R.switches = sum(tr.ch, 1);
R.t_rec = nan(1, NE);
for i = 1:NE
    t0 = find(post(:, i), 1);
    run = 0;
    for k = t0:T
        if ok(k, i), run = run + 1; else, run = 0; end
        if run >= 5, R.t_rec(i) = k - 4 - t0; break; end
    end
end
R.recovered = ~isnan(R.t_rec);
R.held = false(1, NE);
for i = find(R.recovered)
    k0 = find(post(:, i), 1) + R.t_rec(i);
    e = diff([0; ~ok(k0:T, i); 0]);
    nb = sum(e == 1); len = find(e == -1) - find(e == 1);
    reacq = E.follow(i) && K.followable(E.scn(i)) && ~E.comb(i);
    R.held(i) = nb == 0 || (reacq && nb == 1 && len <= 1 + E.D);
end
last = arrayfun(@(i) find(post(:, i), 1, 'last'), 1:NE);
R.recoverable = tr.recov(sub2ind([T NE], last, 1:NE));
R.r = E.r;
R.t0 = nan(1, NE);
for i = 1:NE, k = find(post(:, i), 1); if ~isempty(k), R.t0(i) = k; end, end
R.D = E.D * ones(1, NE);
end
