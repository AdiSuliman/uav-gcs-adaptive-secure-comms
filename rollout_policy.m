function R = rollout_policy(kind, PP, K, spec, split, agent, opt, seed)
%ROLLOUT_POLICY  Run one batch of episodes of a decision-layer policy (D44, D45).
%   kind   any policy_decide.m kind, or 'oracle' (knows the true scenario, onset,
%          follower state and sub-run geometry; picks the configuration with the
%          best reward of the next cycle from the measured sub-run means: a
%          one-step oracle, not a bound on every metric)
%   spec   episode specification (link_env.m); split 1 = train, 2 = test pools
%   seed   frame-draw seed: the same seed gives every policy the same draws
%          wherever their configurations coincide
%   R      per episode: ret (mean reward per cycle), q_post, restored_post,
%          gput_post (normalized goodput after onset), switches, false_sw,
%          t_rec (cycles from onset until restored for 5 consecutive cycles),
%          esc (escalations), aoa (NE x 3, interferer directions of the
%          episode's sub-run); cfg_trace (T x NE)
if nargin < 7 || isempty(opt), opt = struct(); end
rs = RandStream('mt19937ar', 'Seed', seed);
opt.rs = RandStream('mt19937ar', 'Seed', seed + 1);
[E, obs] = link_env('reset', PP, K, spec, split, rs);
NE = E.NE; T = spec.T;
mem = [];
tr = struct('r', zeros(T, NE), 'q', zeros(T, NE), 'rest', false(T, NE), 'gput', zeros(T, NE), ...
    'ch', false(T, NE), 'fs', false(T, NE), 'post', false(T, NE), 'esc', false(T, NE), 'cfg', zeros(T, NE));
for t = 1:T
    if strcmp(kind, 'oracle')
        a = oracle_action(E, K);
    else
        [a, mem, dinf] = policy_decide(kind, obs, E.cfg, mem, PP, agent, opt);
        tr.esc(t, :) = dinf.escalated;
    end
    [E, r, obs, info] = link_env('step', E, PP, K, a);
    tr.r(t, :) = r; tr.q(t, :) = info.q; tr.rest(t, :) = info.restored; tr.gput(t, :) = info.gput;
    tr.ch(t, :) = info.changed; tr.fs(t, :) = info.false_switch; tr.post(t, :) = info.post; tr.cfg(t, :) = E.cfg;
end
R.ret = mean(tr.r, 1);
post = tr.post;
R.q_post = sum(tr.q .* post, 1) ./ max(sum(post, 1), 1);
R.restored_post = sum(tr.rest .* post, 1) ./ max(sum(post, 1), 1);
R.gput_post = sum(tr.gput .* post, 1) ./ max(sum(post, 1), 1);
R.switches = sum(tr.ch, 1);
R.false_sw = sum(tr.fs, 1);
R.esc = sum(tr.esc, 1);
R.t_rec = nan(1, NE);
for i = 1:NE
    t0 = find(post(:, i), 1);
    ok = tr.rest(t0:end, i);
    run = 0;
    for k = 1:numel(ok)
        if ok(k), run = run + 1; else, run = 0; end
        if run >= 5, R.t_rec(i) = k - 5; break; end
    end
end
R.aoa = E.aoa';
R.cfg_trace = tr.cfg;
end

function a = oracle_action(E, K)
% Best next-cycle reward given the truth (scenario, onset, follower, sub-run).
nA = numel(K.cost);
a = E.cfg;
tn = E.t + 1;
for i = 1:E.NE
    sc = E.scn(i); if tn(i) < E.onset(i), sc = 1; end
    healthy = K.healthy(sc, E.s(i), E.split, E.r(i));
    fl = E.follow(i) && K.followable(E.scn(i)) && K.hasCh(E.cfg(i));
    comp_now  = fl && (E.t(i) - E.hop_t(i)) >= E.fdelay(i) && E.t(i) >= E.onset(i);   % decides a hop
    comp_next = fl && (tn(i) - E.hop_t(i)) >= E.fdelay(i) && tn(i) >= E.onset(i);     % state of the next frame
    best = -inf;
    for c = 1:nA
        hop = K.hasCh(c) && (~K.hasCh(E.cfg(i)) || comp_now);
        ceff = c;
        if K.hasCh(c) && ~hop && comp_next, ceff = K.strip(c); end
        chg = c ~= E.cfg(i) || hop;
        v = K.q(sc, E.s(i), ceff, E.split, E.r(i)) - K.cost(c) - K.SW * chg - K.FA * (c ~= E.cfg(i) && healthy);
        if v > best, best = v; a(i) = c; end
    end
end
end
