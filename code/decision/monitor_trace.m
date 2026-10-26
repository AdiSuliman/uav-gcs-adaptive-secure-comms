function Tr = monitor_trace(PP, K, specs, split, seed0)
%MONITOR_TRACE  The link monitor (policy_monitor.m, PP's settings) of episodes flown at
%   no_action, cycle by cycle, split into its paths. Batch b runs with the frame-draw seed
%   seed0 + b as rollout_policy.m runs it, so up to any policy's first change its episode is
%   this one: a policy changes the configuration only on a confirmed alarm (policy_mask.m),
%   so the first confirmation here bounds every policy's first change (choose_drop_threshold.m).
%   Tr.other  episodes x cycles: the alarm without the drop alarm (a hostile class but
%             path_loss, which counts only with the drop, or degradation)
%   Tr.sw     the class sweeping_jammer (the sweeper's own confirmation, PP.confirm_sweep)
%   Tr.eg     the Eb/N0 estimate less the known gain of the configuration (the drop alarm's
%             input, drop_alarm_seq.m)
%   Tr.quiet  degraded without quiet-slot interference (deg_mode 'win_q_gate': logged, no
%             alarm; false in the other modes)
%   Tr.onset, Tr.scn, Tr.s, Tr.r per episode; the padding of a batch (n_valid) is dropped.
%   The decision of cycle t reads the frame of cycle t - 1: the threat is on its frames from
%   cycle onset + 1 on.
nA = numel(PP.actions); na = find(strcmp(PP.actions, 'no_action'));
Tr = struct('other', [], 'sw', [], 'eg', [], 'quiet', [], 'onset', [], 'scn', [], 's', [], 'r', []);
for b = 1:numel(specs)
    sp = specs{b}; T = sp.T;
    [E, obs] = link_env('reset', PP, K, sp, split, RandStream('mt19937ar', 'Seed', seed0 + b));
    NE = E.NE; mem = policy_monitor('init', NE, nA);
    o = false(NE, T); w = o; qd = o; e = nan(NE, T);
    for t = 1:T
        [mem, M] = policy_monitor('update', mem, obs, PP, E.cfg);
        o(:, t) = (~ismember(M.cls, {'none', 'benign_interference', 'unknown', 'path_loss'}) | M.degraded)';
        w(:, t) = strcmp(M.cls, 'sweeping_jammer')';
        e(:, t) = mem.ebno(:, end);
        if isfield(M, 'deg_quiet'), qd(:, t) = M.deg_quiet'; end
        mem = policy_monitor('change', mem, false(1, NE));
        [E, ~, obs] = link_env('step', E, PP, K, na * ones(1, NE));
    end
    v = 1:NE; if isfield(sp, 'n_valid'), v = 1:sp.n_valid; end
    Tr.other = [Tr.other; o(v, :)]; Tr.sw = [Tr.sw; w(v, :)]; Tr.eg = [Tr.eg; e(v, :)]; Tr.quiet = [Tr.quiet; qd(v, :)];
    Tr.onset = [Tr.onset, sp.onset(v)]; Tr.scn = [Tr.scn, sp.scn(v)]; Tr.s = [Tr.s, sp.s(v)]; Tr.r = [Tr.r, E.r(v)];
end
end
