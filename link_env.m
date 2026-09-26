function varargout = link_env(cmd, varargin)
%LINK_ENV  Sequential decision environment on measured frame pools (D44, D45).
%   Vectorized over NE parallel episodes. One step = one decision cycle = one
%   received frame of the configuration currently applied.
%
%   K = link_env('tables', PP)                     reward / goodput tables
%   [E, obs] = link_env('reset', PP, K, spec, split, rs)
%   [E, r, obs, info] = link_env('step', E, PP, K, a)
%
%   spec: scn, s (Eb/N0 index), onset, follow, fdelay, unk (1 x NE each), T
%   split: 1 = train pools, 2 = test pools; rs: RandStream for frame draws
%
%   One episode = one seeded sub-run of the pools (one flight geometry: fading,
%   interferer direction, threat waveform). Every configuration of the same
%   (scenario, Eb/N0, split) shares the seeds of its sub-runs, so after a change
%   the episode continues in the SAME sub-run at the same frame position: the
%   outcome of an action is the outcome in this geometry (common random numbers).
%
%   Scenario: clean link until the onset cycle, then the scenario. A follower
%   jammer (in-channel threats, spec.follow) re-acquires our channel fdelay
%   cycles after each hop: from then on a configuration containing
%   channel_switch acts as the same configuration without it, until the agent
%   hops again (selects a channel_switch configuration while compromised).
%
%   Reward per cycle (scaled by 1/100), from the mean BER m of the configuration
%   in this sub-run:
%     q      100 at <= 1.15x clean, 0 at the unmitigated BER (at least 10x clean),
%            log-linear between; clean = max(clean-link BER, K.ber_floor): below
%            1e-4 the pools (>= 41k bits per sub-run cell) cannot resolve the BER
%     cost   goodput 0.30/unit lost, spectrum 0.05/extra channel, power
%            0.10/(+6 dB), adaptive combining 2 points (processing, pilots)
%     switch 5 points per configuration change or channel hop
%     false  20 points for a change on a healthy link
%   restored: m <= 2x clean; healthy: unmitigated m <= 2x clean.
%   obs: probs (NE x 9), unknown (maha below threshold, or masked), feat (NE x 9
%   raw link features), ber (NE x 1)
switch cmd
    case 'tables', varargout{1} = tables(varargin{:});
    case 'reset',  [varargout{1}, varargout{2}] = reset_env(varargin{:});
    case 'step',   [varargout{1}, varargout{2}, varargout{3}, varargout{4}] = step_env(varargin{:});
    otherwise, error('link_env: unknown command %s', cmd);
end
end

%% ===================== Tables =====================
function K = tables(PP)
A = PP.actions; nA = numel(A);
na = find(strcmp(A, 'no_action'));
K.na = na;
K.hasCh = cellfun(@(a) contains(a, 'channel_switch'), A);
K.strip = 1:nA;
for a = find(K.hasCh)
    rest = strrep(strrep(A{a}, 'channel_switch+', ''), 'channel_switch', '');
    if isempty(rest), rest = 'no_action'; end
    K.strip(a) = find(strcmp(A, rest));
end
K.cost = 100 * (0.30 * (1 - PP.gp) + 0.05 * (PP.bw - 1) + 0.10 * log10(PP.pw) / log10(4)) ...
    + 2 * cellfun(@(a) contains(a, 'spatial_diversity'), A);
K.SW = 5; K.FA = 20;
K.ber_floor = 1e-4;
K.runs = PP.runs;                                   % sub-run ids per split
K.nR = cellfun(@numel, PP.runs);
nSc = numel(PP.scen); nS = numel(PP.ebno); nRm = max(K.nR);
K.q = nan(nSc, nS, nA, 2, nRm); K.gput = nan(nSc, nS, nA, 2, nRm);
K.restored = false(nSc, nS, nA, 2, nRm); K.healthy = false(nSc, nS, 2, nRm);
pc = zeros(1, nS);                                  % clean-link PLR per Eb/N0
for s = 1:nS, pc(s) = mean(PP.pools{1, s, na, 1}.plr); end
for sp = 1:2
    for sc = 1:nSc
        for s = 1:nS
            bc = max(PP.clean(s), K.ber_floor); bt = 1.15 * bc;
            Pu = PP.pools{sc, s, na, sp};
            if isempty(Pu) || isempty(Pu.ber), continue; end
            for r = 1:K.nR(sp)
                rid = PP.runs{sp}(r);
                bu = mean(Pu.ber(Pu.run == rid));
                bw = max(bu, 10 * bt);
                K.healthy(sc, s, sp, r) = bu <= 2 * bc;
                for a = 1:nA
                    P = PP.pools{sc, s, a, sp};
                    k = P.run == rid;
                    m = mean(P.ber(k)); pl = mean(P.plr(k));
                    K.q(sc, s, a, sp, r) = 100 * min(1, max(0, 1 - log(max(m, 1e-9) / bt) / log(bw / bt)));
                    K.gput(sc, s, a, sp, r) = PP.gp(a) * (1 - pl) / max(1 - pc(s), 1e-3);
                    K.restored(sc, s, a, sp, r) = m <= 2 * bc;
                end
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
E.r = randi(rs, K.nR(split), 1, NE);                 % sub-run (geometry) of the episode
E.k0 = randi(rs, PP.F_SUB, 1, NE) - 1;               % starting frame inside the sub-run
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
healthy = K.healthy(sub2ind(size(K.healthy), sc_eff, E.s, sp, E.r));
q = K.q(idx);
r = (q - K.cost(a) - K.SW * (changed | hop) - K.FA * (changed & healthy)) / 100;
info = struct('q', q, 'restored', K.restored(idx), 'gput', K.gput(idx), 'changed', changed | hop, ...
    'false_switch', changed & healthy, 'healthy', healthy, 'sc_eff', sc_eff, 'cfg_eff', cfg_eff, ...
    'post', E.t >= E.onset);
end

function c = compromised(E, K, cfg)
c = E.follow & K.followable(E.scn) & K.hasCh(cfg) & (E.t - E.hop_t) >= E.fdelay & E.t >= E.onset;
end

function [E, obs, sc_eff, cfg_eff] = draw(E, PP, K)
% Frame of the effective (scenario, configuration) cell, same sub-run, frame
% position k0 + t inside the sub-run (cyclic).
sc_eff = E.scn; sc_eff(E.t < E.onset) = 1;
cfg_eff = E.cfg;
cm = compromised(E, K, E.cfg);
cfg_eff(cm) = K.strip(E.cfg(cm));
obs.probs = zeros(E.NE, 9); obs.unknown = false(E.NE, 1); obs.feat = zeros(E.NE, 9); obs.ber = zeros(E.NE, 1);
for i = 1:E.NE
    P = PP.pools{sc_eff(i), E.s(i), cfg_eff(i), E.split};
    rows = find(P.run == PP.runs{E.split}(E.r(i)));
    j = rows(mod(E.k0(i) + E.t(i), numel(rows)) + 1);
    obs.probs(i, :) = P.probs(j, :);
    obs.unknown(i) = P.maha(j) < PP.maha_thr;
    obs.feat(i, :) = P.feat(j, :);
    obs.ber(i) = P.ber(j);
end
mask = E.unk & E.t >= E.onset;
obs.probs(mask, :) = 0; obs.unknown(mask) = true;
end
