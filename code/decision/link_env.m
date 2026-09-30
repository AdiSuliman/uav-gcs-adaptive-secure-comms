function varargout = link_env(cmd, varargin)
%LINK_ENV  Sequential decision environment on measured frame pools.
%   Vectorized over NE parallel episodes. One step = one decision cycle = one
%   received frame of the configuration currently applied.
%
%   K = link_env('tables', PP)                     reward / restoration tables
%   [E, obs] = link_env('reset', PP, K, spec, split, rs)
%   [E, r, obs, info] = link_env('step', E, PP, K, a)
%
%   spec: scn (threat cell index into PP.scen), s (Eb/N0 index), onset, follow,
%         fdelay, unk (1 x NE each), T; optional r (1 x NE): geometry of each
%         episode, drawn at random if absent
%   split: 1 = train, 2 = validation, 3 = test pools; rs: RandStream for frame draws
%
%   One episode = one seeded geometry of the pools (fading, interferer
%   direction, threat waveform). Every configuration of the same (cell, Eb/N0,
%   split) shares the seeds of its geometries, so after a change the episode
%   continues in the SAME geometry at the same frame position: the outcome of an
%   action is the outcome in this geometry (common random numbers).
%
%   Scenario: clean link until the onset cycle, then the cell's threat. A follower
%   jammer (in-channel threats, spec.follow) re-acquires our channel fdelay cycles
%   after each hop: from then on a configuration containing channel_switch acts as
%   the same configuration without it, until the agent hops again (selects a
%   channel_switch configuration while compromised).
%
%   Reward per cycle (points / 100; weights in decision_config.m), from the true
%   mean BER m of the configuration in this geometry (training signal only):
%     q      C.q_restored when m <= C.ratio_ok x clean (the KPI), otherwise up to
%            C.q_partial, log-linear from the threshold down to 0 at the
%            unmitigated BER (at least 10x the threshold); clean = max(clean-link
%            BER, C.ber_floor), the smallest BER the pools resolve
%     cost   goodput given up, extra spectrum, transmit power, adaptive combining
%     switch per configuration change or channel hop
%     false  per change on a healthy link
%   restored: m <= C.ratio_ok x clean; restored_plr: true packet loss <= C.ratio_ok
%   x the clean link's + one packet of the geometry; healthy: unmitigated m <=
%   C.ratio_ok x clean; recoverable: some configuration restores both BER and
%   packet loss in this geometry.
%   obs: probs (NE x classes), unknown (score below threshold, or masked), feat
%   (NE x link features, receiver measurements), ber_true (analysis only)
switch cmd
    case 'tables', varargout{1} = tables(varargin{:});
    case 'reset',  [varargout{1}, varargout{2}] = reset_env(varargin{:});
    case 'step',   [varargout{1}, varargout{2}, varargout{3}, varargout{4}] = step_env(varargin{:});
    otherwise, error('link_env: unknown command %s', cmd);
end
end

%% ===================== Tables =====================
function K = tables(PP)
C = decision_config();
A = PP.actions; nA = numel(A);
K.na = find(strcmp(A, 'no_action'));
K.clean = find(strcmp(PP.scen, 'none'), 1);
K.hasCh = cellfun(@(a) contains(a, 'channel_switch'), A);
K.strip = 1:nA;
for a = find(K.hasCh)
    rest = regexprep(A{a}, '^channel_switch\+?', '');
    if isempty(rest), rest = 'no_action'; end
    K.strip(a) = find(strcmp(A, rest));
end
K.cost = C.w_goodput * (1 - PP.gp) + C.w_spectrum * (PP.bw - 1) + C.w_power * log10(PP.pw) / log10(4) ...
    + C.w_mmse * cellfun(@(a) contains(a, 'spatial_diversity'), A);
K.SW = C.w_switch; K.FA = C.w_false;
K.runs = PP.runs;                                   % geometry ids per split
K.nR = cellfun(@numel, PP.runs);
nSc = numel(PP.scen); nS = numel(PP.ebno); nSp = numel(PP.runs); nRm = max(K.nR);
K.q = nan(nSc, nS, nA, nSp, nRm); K.gput = nan(nSc, nS, nA, nSp, nRm);
K.restored = false(nSc, nS, nA, nSp, nRm); K.restored_plr = false(nSc, nS, nA, nSp, nRm);
K.healthy = false(nSc, nS, nSp, nRm); K.recoverable = false(nSc, nS, nSp, nRm);
pc = PP.clean_fer;                                  % clean-link packet loss per Eb/N0 (train split)
for sp = 1:nSp
    for sc = 1:nSc
        for s = 1:nS
            bc = max(PP.clean(s), C.ber_floor); bt = C.ratio_ok * bc;
            Pu = PP.pools{sc, s, K.na, sp};
            if isempty(Pu) || isempty(Pu.ber), continue; end
            for r = 1:K.nR(sp)
                rid = PP.runs{sp}(r);
                ku = Pu.run == rid;
                bu = mean(Pu.ber(ku));
                bw = max(bu, 10 * bt);
                K.healthy(sc, s, sp, r) = bu <= bt;
                for a = 1:nA
                    P = PP.pools{sc, s, a, sp};
                    k = P.run == rid;
                    m = mean(P.ber(k)); pl = mean(double(P.fer(k)));
                    rest = m <= bt;
                    if rest
                        q = C.q_restored;
                    else
                        q = C.q_partial * min(1, max(0, 1 - log(max(m, 1e-9) / bt) / log(bw / bt)));
                    end
                    K.q(sc, s, a, sp, r) = q;
                    K.restored(sc, s, a, sp, r) = rest;
                    K.restored_plr(sc, s, a, sp, r) = pl <= C.ratio_ok * pc(s) + 1 / max(sum(k), 1);
                    if 1 - pc(s) >= 0.1, K.gput(sc, s, a, sp, r) = PP.gp(a) * (1 - pl) / (1 - pc(s)); end
                end
                K.recoverable(sc, s, sp, r) = any(K.restored(sc, s, :, sp, r) & K.restored_plr(sc, s, :, sp, r));
            end
        end
    end
end
comp = cellfun(@(x) strsplit(x, '+'), PP.scen, 'UniformOutput', false);
K.followable = cellfun(@(c) any(ismember(c, {'jamming', 'reactive_jamming', 'spoofing'})), comp);
end

%% ===================== Reset / step =====================
function [E, obs] = reset_env(PP, K, spec, split, rs)
NE = numel(spec.scn);
E = spec; E.NE = NE; E.split = split; E.rs = rs;
E.t = zeros(1, NE);
E.cfg = K.na * ones(1, NE);
E.last_switch = -inf(1, NE);
E.hop_t = -inf(1, NE);
if ~isfield(spec, 'r') || isempty(spec.r)
    E.r = randi(rs, K.nR(split), 1, NE);             % geometry of the episode
end
E.k0 = randi(rs, PP.F_SUB, 1, NE) - 1;               % starting frame inside the geometry
E.aoa = nan(NE, 3);
for i = 1:NE
    P = PP.pools{E.scn(i), E.s(i), K.na, split};
    if isfield(P, 'aoa') && ~isempty(P.aoa)
        j = find(P.run == PP.runs{split}(E.r(i)), 1);
        E.aoa(i, 1:size(P.aoa, 2)) = P.aoa(j, :);
    end
end
[E, obs] = draw(E, PP, K);
end

function [E, r, obs, info] = step_env(E, PP, K, a)
a = a(:)';
prev = E.cfg;
comp_prev = compromised(E, K, prev);
hop = K.hasCh(a) & (~K.hasCh(prev) | comp_prev);
changed = a ~= prev;
E.hop_t(hop) = E.t(hop) + 1;
E.cfg = a;
E.last_switch(changed | hop) = E.t(changed | hop) + 1;
E.t = E.t + 1;
[E, obs, sc_eff, cfg_eff] = draw(E, PP, K);
sp = E.split * ones(1, E.NE);
idx = sub2ind(size(K.q), sc_eff, E.s, cfg_eff, sp, E.r);
ih = sub2ind(size(K.healthy), sc_eff, E.s, sp, E.r);
healthy = K.healthy(ih);
q = K.q(idx);
r = (q - K.cost(a) - K.SW * (changed | hop) - K.FA * (changed & healthy)) / 100;
info = struct('q', q, 'restored', K.restored(idx), 'restored_plr', K.restored_plr(idx), 'gput', K.gput(idx), ...
    'changed', changed | hop, 'false_switch', changed & healthy, 'healthy', healthy, ...
    'recoverable', K.recoverable(ih), 'sc_eff', sc_eff, 'cfg_eff', cfg_eff, 'post', E.t >= E.onset);
end

function c = compromised(E, K, cfg)
c = E.follow & K.followable(E.scn) & K.hasCh(cfg) & (E.t - E.hop_t) >= E.fdelay & E.t >= E.onset;
end

function [E, obs, sc_eff, cfg_eff] = draw(E, PP, K)
% Frame of the effective (cell, configuration), same geometry, frame position
% k0 + t inside the geometry (cyclic).
sc_eff = E.scn; sc_eff(E.t < E.onset) = K.clean;
cfg_eff = E.cfg;
cm = compromised(E, K, E.cfg);
cfg_eff(cm) = K.strip(E.cfg(cm));
nC = numel(PP.classes); nF = numel(PP.feat_names);
obs.probs = zeros(E.NE, nC); obs.unknown = false(E.NE, 1); obs.feat = zeros(E.NE, nF); obs.ber_true = zeros(E.NE, 1);
for i = 1:E.NE
    P = PP.pools{sc_eff(i), E.s(i), cfg_eff(i), E.split};
    rows = find(P.run == PP.runs{E.split}(E.r(i)));
    j = rows(mod(E.k0(i) + E.t(i), numel(rows)) + 1);
    obs.probs(i, :) = P.probs(j, :);
    obs.unknown(i) = P.maha(j) < PP.maha_thr;
    obs.feat(i, :) = P.feat(j, :);
    obs.ber_true(i) = P.ber(j);
end
mask = E.unk & E.t >= E.onset;
obs.probs(mask, :) = 0; obs.unknown(mask) = true;
end
