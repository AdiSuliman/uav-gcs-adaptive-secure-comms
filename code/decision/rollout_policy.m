function R = rollout_policy(kind, PP, K, spec, split, agent, opt, seed)
%ROLLOUT_POLICY  Run one batch of episodes of a decision-layer policy.
%   kind   any policy_decide.m kind, or 'oracle' (knows the true scenario, onset,
%          follower state and geometry; picks the configuration with the best
%          reward of the next cycle from the measured geometry means: a one-step
%          oracle, not a bound on every metric)
%   spec   episode specification (link_env.m); split 1 train, 2 validation, 3 test,
%          4 edge speeds, 5 second test
%   seed   frame-draw seed: the same seed gives every policy the same draws
%          wherever their configurations coincide
%   R      per episode (after onset unless noted):
%          ret        mean reward per cycle (whole episode)
%          restored_post  share of cycles with BER <= 2x clean
%          plr_ok_post    share of cycles with packet loss <= 2x clean (+1 packet)
%          ok_post        share of cycles with both
%          gput_post  normalized goodput (NaN where the clean link loses > 90% of packets)
%          recovered  both BER and packet loss restored for 5 consecutive cycles
%          t_rec      cycles from onset until that run of 5 starts (NaN if never)
%          recoverable  some configuration restores this geometry (link_env.m)
%          switches, false_sw (whole episode), esc (escalations), aoa (3 x NE),
%          cfg_final, r (geometry index), cfg_trace (T x NE); at the first change:
%          fc_t, fc_cls (index into PP.classes, numel + 1 = unknown), fc_deg, fc_drop
if nargin < 7 || isempty(opt), opt = struct(); end
rs = RandStream('mt19937ar', 'Seed', seed);
opt.rs = RandStream('mt19937ar', 'Seed', seed + 1);
[E, obs] = link_env('reset', PP, K, spec, split, rs);
NE = E.NE; T = spec.T;
mem = [];
cls_list = [cellstr(string(PP.classes(:)')), {'unknown'}];
fc = struct('t', zeros(1, NE), 'cls', zeros(1, NE), 'deg', false(1, NE), 'drop', nan(1, NE));
tr = struct('r', zeros(T, NE), 'q', zeros(T, NE), 'rest', false(T, NE), 'rplr', false(T, NE), 'gput', zeros(T, NE), ...
    'ch', false(T, NE), 'fs', false(T, NE), 'post', false(T, NE), 'esc', false(T, NE), 'cfg', zeros(T, NE), ...
    'recov', false(T, NE));
for t = 1:T
    if strcmp(kind, 'oracle')
        a = oracle_action(E, K);
    else
        [a, mem, dinf] = policy_decide(kind, obs, E.cfg, mem, PP, agent, opt);
        tr.esc(t, :) = dinf.escalated;
    end
    [E, r, obs, info] = link_env('step', E, PP, K, a);
    nw = info.changed & fc.t == 0;
    if any(nw) && ~strcmp(kind, 'oracle')
        fc.t(nw) = t;
        fc.cls(nw) = cellfun(@(c) find(strcmp(cls_list, c), 1), dinf.cls(nw));
        fc.deg(nw) = dinf.degraded(nw);
        fc.drop(nw) = dinf.drop(nw);
    end
    tr.r(t, :) = r; tr.q(t, :) = info.q; tr.rest(t, :) = info.restored; tr.gput(t, :) = info.gput;
    tr.rplr(t, :) = info.restored_plr; tr.recov(t, :) = info.recoverable;
    tr.ch(t, :) = info.changed; tr.fs(t, :) = info.false_switch; tr.post(t, :) = info.post; tr.cfg(t, :) = E.cfg;
end
post = tr.post; npost = max(sum(post, 1), 1);
ok = tr.rest & tr.rplr;
R.ret = mean(tr.r, 1);
R.q_post = sum(tr.q .* post, 1) ./ npost;
R.restored_post = sum(tr.rest .* post, 1) ./ npost;
R.plr_ok_post = sum(tr.rplr .* post, 1) ./ npost;
R.ok_post = sum(ok .* post, 1) ./ npost;
g = tr.gput; g(~post) = NaN;
R.gput_post = mean(g, 1, 'omitnan');
R.switches = sum(tr.ch, 1);
R.false_sw = sum(tr.fs, 1);
R.esc = sum(tr.esc, 1);
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
last = arrayfun(@(i) find(post(:, i), 1, 'last'), 1:NE);
R.recoverable = tr.recov(sub2ind([T NE], last, 1:NE));
R.aoa = E.aoa';
R.cfg_final = E.cfg;
R.r = E.r;
R.cfg_trace = tr.cfg;
R.fc_t = fc.t; R.fc_cls = fc.cls; R.fc_deg = fc.deg; R.fc_drop = fc.drop;
end

function a = oracle_action(E, K)
% Best next-cycle reward given the truth (scenario, onset, follower, geometry).
nA = numel(K.cost);
a = E.cfg;
tn = E.t + 1;
for i = 1:E.NE
    sc = E.scn(i); if tn(i) < E.onset(i), sc = K.clean; end
    healthy = K.healthy(sc, E.s(i), E.split, E.r(i));
    fj = E.follow(i) && K.followable(E.scn(i)) && tn(i) >= E.onset(i);                % follower jammer active
    fl = fj && K.hasCh(E.cfg(i));
    comp_now  = fl && (E.t(i) - E.hop_t(i)) >= E.fdelay(i) && E.t(i) >= E.onset(i);   % decides a hop
    comp_next = fl && (tn(i) - E.hop_t(i)) >= E.fdelay(i);                            % state of the next frame
    best = -inf;
    for c = 1:nA
        hop = K.hasCh(c) && (~K.hasCh(E.cfg(i)) || comp_now);
        ceff = c;
        % a hop escapes for fdelay frames (none when the jammer follows at once, fdelay 0)
        if K.hasCh(c) && fj && ((hop && E.fdelay(i) <= 0) || (~hop && comp_next)), ceff = K.strip(c); end
        chg = c ~= E.cfg(i) || hop;
        v = K.q(sc, E.s(i), ceff, E.split, E.r(i)) - K.cost(c) - K.SW * chg - K.FA * (c ~= E.cfg(i) && healthy);
        if v > best, best = v; a(i) = c; end
    end
end
end
