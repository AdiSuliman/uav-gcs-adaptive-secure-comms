function [a, ceff, ta] = oracle_action(E, K)
%ORACLE_ACTION  The one-step oracle of rollout_policy.m: per episode the configuration
%   with the best reward of the frame on which the choice reaches the link (after the
%   signalling delay), given the truth (scenario, onset, follower, geometry) and the hop
%   rule of link_env.m: a hop when channel_switch follows a configuration without it, or
%   is kept after a failed frame, and none while one is on its way; with spec.cover (the
%   bandwidth study, link_env.m) channel_switch on a channel the static jammer covers acts as
%   the configuration without it (spec.cover_rel: hops counted from the onset), and on an
%   escaped one with spec.acr reads the reward of that hop's layer (K.acr_tabs).
%   [a, ceff, ta] = oracle_action(E, K)
%   E, K   link_env.m state (before the step) and tables
%   a      the configuration chosen (1 x NE)
%   ceff   the configuration the link runs it as on frame ta (a follower or comb jammer
%          strips channel_switch or freq_diversity): link_env.m's cfg_eff of that frame
%   ta     the frame the choice runs on (E.t + 1 + E.D)
nA = numel(K.cost);
a = E.cfg; ceff = a;
ta = E.t + 1 + E.D;
pend = any(E.hopq, 1);
cov = isfield(E, 'cover') && ~isempty(E.cover);
lay = cov && isfield(E, 'acr') && ~isempty(E.acr);
rel = false(1, E.NE);                                  % the jammer takes the channel in use at the onset
if cov && isfield(E, 'cover_rel') && ~isempty(E.cover_rel), rel = logical(E.cover_rel(:)'); end
for i = 1:E.NE
    sc = E.scn(i); if ta(i) < E.onset(i), sc = K.clean; end
    healthy = K.healthy(sc, E.s(i), E.split, E.r(i));
    on = K.followable(E.scn(i)) && ta(i) >= E.onset(i);
    hl = E.hop_live(i);                                % channel in use when the choice arrives
    k = find(E.hopq(:, i), 1);
    if ~isempty(k), hl = E.t(i) + k; end               % after the hop on its way
    best = -inf;
    for c = 1:nA
        hop = K.hasCh(c) && (~K.hasCh(E.cfg(i)) || E.crc(i)) && ~pend(i);
        h = hl; if hop, h = ta(i); end
        ce = c; lv = 1; fo = on && E.follow(i) && K.hasCh(c) && ta(i) - h >= E.fdelay(i);
        if fo, ce = K.strip(c); end
        if on && E.comb(i) && K.hasFd(c), ce = K.strip_fd(c); end
        if on && cov && K.hasCh(c)                     % the hops that have reached the link by frame ta
            nh = E.nhop(i) + nnz(E.hopq(:, i)) + hop;
            if rel(i), nh = nh - E.nh_on(i) - (E.t(i) < E.onset(i) && ~isempty(k) && E.t(i) + k < E.onset(i)); end
            if nh == 0 || E.cover(i, min(nh, size(E.cover, 2))), ce = K.strip(c);
            elseif lay && ~fo, lv = E.acr(i, min(nh, size(E.acr, 2)));
            end
        end
        chg = c ~= E.cfg(i) || hop;
        if lv > 1, qv = K.acr_tabs{lv - 1}.q(sc, E.s(i), ce, E.split, E.r(i)); else, qv = K.q(sc, E.s(i), ce, E.split, E.r(i)); end
        v = qv - K.cost(c) - K.SW * chg - K.FA * (c ~= E.cfg(i) && healthy);
        if v > best, best = v; a(i) = c; ceff(i) = ce; end
    end
end
end
