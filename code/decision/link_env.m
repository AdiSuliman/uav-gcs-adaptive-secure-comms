function varargout = link_env(cmd, varargin)
%LINK_ENV  Sequential decision environment on measured frame pools.
%   Vectorized over NE parallel episodes. One step = one decision cycle = one
%   received frame of the configuration currently applied.
%
%   K = link_env('tables', PP)                     reward / restoration tables
%   K = link_env('tables', PP, 'flight')           the same flight's clean link as the reference
%   [E, obs] = link_env('reset', PP, K, spec, split, rs)
%   [E, r, obs, info] = link_env('step', E, PP, K, a)
%
%   spec: scn (threat cell index into PP.scen), s (Eb/N0 index), onset, follow,
%         fdelay, unk (1 x NE each), T; optional r (1 x NE): geometry of each
%         episode (index into PP.runs{split}, one the cell flies: PP.cell_geo), drawn
%         at random among the cell's (K.geo) if absent; optional delay: signalling delay of a configuration
%         change in cycles (default C.switch_delay); optional comb (1 x NE): the
%         jammer is on every channel we can use (frequency diversity escapes it no
%         more than a hop); optional offset (1 x NE, default Inf): the cycle the threat ends,
%         from which the episode flies the clean link of the same geometry at the same frame
%         positions (a threat that ends; no follower after it); optional cover (NE x H
%         logical): the static jammer covers the channel the k-th hop that reaches the link
%         moves to (the bandwidth study, experiment_core_bw.m; the home channel before the
%         first hop is covered): while the threat is on, a configuration containing
%         channel_switch on a covered channel acts as the same configuration without it, as
%         after a follower's re-acquisition; optional acr (NE x H): on an escaped hop the
%         channel_switch configurations take their frames from the pools (1) or from the
%         residual's layer PP.acr_pools{v - 1} (v > 1, the same configurations at another
%         rejection; PP.alt is the pools' altitudes, never a layer), and the recoverable rule
%         reads that hop's layer; optional cover_rel
%         (1 x NE logical, default false): the jammer takes the channel in use at the onset
%         (a jammer tuned to our channel), so the k-th hop after the onset reads column k of
%         cover and acr and a hop before the onset escapes nothing
%   split: 1 = train, 2 = validation, 3 = test, 4 = edge-speed pools, 5 = second
%         test; rs: RandStream for frame draws
%
%   A configuration chosen in one cycle is requested from the GCS and runs on the
%   link from the frame after the next delay cycles: E.cfg is the configuration
%   requested (what the policy knows), E.cfg_link the one the link runs.
%
%   One episode = one seeded geometry of the pools (fading, interferer
%   direction, threat waveform). Every configuration of the same (cell, Eb/N0,
%   split) shares the seeds of its geometries, so after a change the episode
%   continues in the SAME geometry at the same frame position: the outcome of an
%   action is the outcome in this geometry (common random numbers). On a geometry whose
%   UAV rolls into its turn (PP.event_frame: the airframe enters the line of sight just
%   before that frame of its run, build_policy_pools.m) the onset cycle reads that frame, so
%   the frames after the onset follow the shadowing's ramp and those before it are the same
%   flight's clean link before the event; beyond the run's end the episode cycles over its
%   last 10 frames; the per-flight tables read such a run from that frame on (event_rows.m).
%   Every other geometry starts at a random frame (an antenna fault, path loss and every
%   additive threat are on from their run's first frame: a step at the onset).
%
%   Scenario: clean link until the onset cycle, then the cell's threat (until spec.offset). A follower
%   jammer (in-channel threats, spec.follow) re-acquires our channel fdelay cycles
%   after a hop reaches the link: from then on a configuration containing
%   channel_switch acts as the same configuration without it. A hop is requested
%   when a channel_switch configuration follows one without it, or is kept while the
%   frame just received failed its CRC (what the UAV sees of the channel in use, frame
%   by frame); it travels with the request through the signalling delay and costs a
%   switch, the link stays on the old channel until it arrives, and no hop is
%   requested while one is on its way.
%   A comb jammer (spec.comb) also takes frequency diversity's second carrier from
%   the onset: such a configuration acts as the same one without it, at its cost.
%
%   Reward per cycle (points / 100; weights in decision_config.m), from the true
%   mean BER m and packet loss of the configuration in this geometry (training signal only):
%     q      C.q_restored when m <= C.ratio_ok x clean and the packet loss is restored
%            (restored_plr below; both, as KPI 4), otherwise up to C.q_partial,
%            log-linear from the threshold down to 0 at the
%            unmitigated BER (at least 10x the threshold); clean = max(clean-link
%            BER, C.ber_floor), the smallest BER the pools resolve: the clean link's
%            mean at the same Eb/N0 (PP.clean: the 300 clean validation flights per
%            Eb/N0, clean_ref_rebuild.m; training and KPI 4), or with
%            'flight' the same flight's clean link (the clean cell flies every
%            geometry; edge_map.m), its packet loss likewise
%     cost   goodput given up, extra spectrum, transmit power, adaptive combining
%     switch per configuration change or channel hop
%     false  per change on a healthy link, but a release to no_action after the threat
%            ended (spec.offset), which is no false alarm
%   restored: m <= C.ratio_ok x clean; restored_plr: true packet loss <= C.ratio_ok
%   x the clean link's + one loss event of the geometry (one packet; with fec_interleave
%   the geometry's longest run of consecutive lost packets, at most the PP.fec_frames / 2
%   that share a frame, packet_share.m); after the link turns to fec_interleave
%   (a coded configuration reaches the link after an uncoded one) its first coded packet
%   is decoded on the PP.fec_frames-th coded frame: the PP.fec_frames - 1 frames before
%   deliver no packet and count as neither restored nor restored_plr (info.fec_gap);
%   healthy: no_action restores both, its m <= C.ratio_ok x clean and its packet loss
%   restored (KPI 4's test); recoverable: some configuration restores both BER and
%   packet loss in this geometry (under a comb jammer, one without channel_switch
%   and freq_diversity; with spec.cover, one with channel_switch only when a hop that can
%   reach the link after the onset, floor((T - onset - 1) / (delay + 1)) of them counted
%   from the hops before it, or from the first with spec.cover_rel, escapes and, with
%   spec.acr, it restores both at that hop's layer); recoverable_core: the
%   same over the core action set's configurations alone (C.core_actions); on: the cell's threat is on the air in some frame of this
%   geometry (pool_cell.m act; airframe shadowing only where the flight's attitude lets
%   the airframe hide an antenna, shadow_hidden.m), so an episode whose threat never is
%   counts as no threat episode (policy_run_set.m, dqn_eval_batches.m).
%   obs: probs (NE x classes), maha (unknown-threat score), unknown (score below
%   threshold, or masked), feat (NE x link features, receiver measurements), gant
%   (NE x antennas, mean channel gain of every antenna), mmse_pred (NE x 1, the predicted
%   MMSE gain over MRC [dB], mmse_predict.m; NaN from pools without it), cfg_link (configuration
%   the frame was received with), pkt (the frame's coded packet: the one that ends on
%   frames 2k-1 and 2k of the geometry, the receiver's framing; its codeword spans the
%   PP.fec_frames frames up to them, cyclic over the geometry's frames as the frame
%   positions are, fec_packets.m), ber_true and fer_true (the frame's BER and packet
%   error, analysis only); probs3 (NE x 3, the three-state CNN's probabilities, pool_cell.m),
%   only when the pools hold them, NaN where the frame's pool has none
%   info: per episode q, restored, restored_plr, fec_gap, gput, changed (a change or a hop),
%   false_switch, healthy, recoverable, recoverable_core, sc_eff, cfg_eff, post, hop (requested this
%   cycle), hop_in (a hop reached the link on this frame), compromised, ended (the frame is
%   after the threat's end), released (a change to no_action decided after the end)
switch cmd
    case 'tables', varargout{1} = tables(varargin{:});
    case 'reset',  [varargout{1}, varargout{2}] = reset_env(varargin{:});
    case 'step',   [varargout{1}, varargout{2}, varargout{3}, varargout{4}] = step_env(varargin{:});
    otherwise, error('link_env: unknown command %s', cmd);
end
end

%% ===================== Tables =====================
function K = tables(PP, ref)
if nargin < 2 || isempty(ref), ref = 'mean'; end
C = decision_config();
A = PP.actions; nA = numel(A);
K.na = find(strcmp(A, 'no_action'));
K.clean = find(strcmp(PP.scen, 'none'), 1);
K.hasCh = cellfun(@(a) contains(a, 'channel_switch'), A);
K.hasFd = cellfun(@(a) contains(a, 'freq_diversity'), A);
K.hasFec = cellfun(@(a) contains(a, 'fec_interleave'), A);
K.strip = 1:nA; K.strip_fd = 1:nA;
for a = find(K.hasCh | K.hasFd)
    rest = regexprep(A{a}, '^(channel_switch|freq_diversity)\+?', '');
    if isempty(rest), rest = 'no_action'; end
    if K.hasCh(a), K.strip(a) = find(strcmp(A, rest)); else, K.strip_fd(a) = find(strcmp(A, rest)); end
end
K.cost = C.w_goodput * (1 - PP.gp) + C.w_spectrum * (PP.bw - 1) + C.w_power * log10(PP.pw) / log10(4) ...
    + C.w_mmse * cellfun(@(a) contains(a, 'spatial_diversity'), A);
K.SW = C.w_switch; K.FA = C.w_false;
K.ref = ref;
Q = C.fec_frames; if isfield(PP, 'fec_frames'), Q = PP.fec_frames; end   % frames of a coded packet's codeword
K.Q = Q;
K.runs = PP.runs;                                   % geometry ids per split
K.nR = cellfun(@numel, PP.runs);
nSc = numel(PP.scen); nS = numel(PP.ebno); nSp = numel(PP.runs); nRm = max(K.nR);
K.ev = arrayfun(@(sp) nan(1, K.nR(sp)), 1:nSp, 'UniformOutput', false);   % frame of the event of a rolling-in flight
if isfield(PP, 'event_frame') && ~isempty(PP.event_frame), K.ev = PP.event_frame; end
for sp = 1:max(nSp, numel(K.ev))                    % one event frame per geometry of every split
    if sp > nSp || sp > numel(K.ev) || numel(K.ev{sp}) ~= K.nR(sp)
        error('link_env:event_frame', ['link_env: split %d of PP.event_frame does not match PP.runs (its runs ' ...
            'replaced without their event frames)'], sp);
    end
end
K.geo = cell(nSc, nSp);                             % the geometries every cell flies (PP.cell_geo; the clean link's
for sc = 1:nSc                                      % own, without the shadowing reference), every one without it
    for sp = 1:nSp
        K.geo{sc, sp} = 1:K.nR(sp);
        if isfield(PP, 'cell_geo') && numel(PP.cell_geo) >= sc && numel(PP.cell_geo{sc}) >= sp
            K.geo{sc, sp} = PP.cell_geo{sc}{sp};
        end
    end
end
K.q = nan(nSc, nS, nA, nSp, nRm); K.gput = nan(nSc, nS, nA, nSp, nRm);
K.restored = false(nSc, nS, nA, nSp, nRm); K.restored_plr = false(nSc, nS, nA, nSp, nRm);
K.healthy = false(nSc, nS, nSp, nRm); K.recoverable = false(nSc, nS, nSp, nRm); K.recoverable_comb = K.recoverable;
K.rec_noch = K.recoverable; K.rec_ch = K.recoverable;   % some configuration without / with channel_switch restores
K.rec_core = K.recoverable; K.rec_core_comb = K.recoverable;   % the same over the core action set
K.rec_core_noch = K.recoverable; K.rec_core_ch = K.recoverable;
K.on = false(nSc, nS, nSp, nRm);
stay = ~K.hasCh & ~K.hasFd;                         % configurations a comb jammer leaves as they are
core = ismember(A, C.core_actions);                 % the core action set (decision_config.m)
for sp = 1:nSp
    [BC, PC] = clean_reference(PP, K, sp, ref, C);   % clean BER (floored) and packet loss, Eb/N0 x geometry
    for sc = 1:nSc
        for s = 1:nS
            Pu = PP.pools{sc, s, K.na, sp};
            if isempty(Pu) || isempty(Pu.ber), continue; end
            for r = 1:K.nR(sp)
                rid = PP.runs{sp}(r);
                ku = span(Pu.run == rid, K.ev{sp}(r));
                if ~any(ku), continue; end              % a geometry the cell does not fly
                bt = C.ratio_ok * BC(s, r); pr = PC(s, r);
                bu = mean(Pu.ber(ku));
                bw = max(bu, 10 * bt);
                K.healthy(sc, s, sp, r) = bu <= bt && ...
                    mean(double(Pu.fer(ku))) <= C.ratio_ok * pr + packet_share(A{K.na}, Pu.fer(ku), Q);
                K.on(sc, s, sp, r) = sc ~= K.clean && (~isfield(Pu, 'act') || isempty(Pu.act) || any(Pu.act(ku) > 0) || ...
                    (isfield(Pu, 'act_idle') && ~isempty(Pu.act_idle) && any(Pu.act_idle(ku) > 0)));   % on the air in a frame or an idle time
                for a = 1:nA
                    P = PP.pools{sc, s, a, sp};
                    k = span(P.run == rid, K.ev{sp}(r));
                    m = mean(P.ber(k)); pl = mean(double(P.fer(k)));
                    rest = m <= bt;
                    rp = pl <= C.ratio_ok * pr + packet_share(A{a}, P.fer(k), Q);
                    if rest && rp
                        q = C.q_restored;
                    else
                        q = C.q_partial * min(1, max(0, 1 - log(max(m, 1e-9) / bt) / log(bw / bt)));
                    end
                    K.q(sc, s, a, sp, r) = q;
                    K.restored(sc, s, a, sp, r) = rest;
                    K.restored_plr(sc, s, a, sp, r) = rp;
                    if 1 - pr >= 0.1, K.gput(sc, s, a, sp, r) = PP.gp(a) * (1 - pl) / (1 - pr); end
                end
                ok = K.restored(sc, s, :, sp, r) & K.restored_plr(sc, s, :, sp, r);
                K.recoverable(sc, s, sp, r) = any(ok);
                K.recoverable_comb(sc, s, sp, r) = any(ok(stay));
                K.rec_noch(sc, s, sp, r) = any(ok(~K.hasCh)); K.rec_ch(sc, s, sp, r) = any(ok(K.hasCh));
                K.rec_core(sc, s, sp, r) = any(ok(core)); K.rec_core_comb(sc, s, sp, r) = any(ok(core & stay));
                K.rec_core_noch(sc, s, sp, r) = any(ok(core & ~K.hasCh)); K.rec_core_ch(sc, s, sp, r) = any(ok(core & K.hasCh));
            end
        end
    end
end
comp = cellfun(@(x) strsplit(x, '+'), PP.scen, 'UniformOutput', false);
K.followable = cellfun(@(c) any(ismember(c, {'jamming', 'reactive_jamming', 'spoofing', 'tone_jamming'})), comp);
K.acr_tabs = {};                                    % PP.acr_pools: pools of the residual's layers (spec.acr)
if isfield(PP, 'acr_pools') && ~isempty(PP.acr_pools)
    for v = 1:numel(PP.acr_pools)
        Pv = rmfield(PP, 'acr_pools'); Pv.pools = PP.acr_pools{v};
        Kv = tables(Pv, ref);
        K.acr_tabs{v} = struct('q', Kv.q, 'restored', Kv.restored, 'restored_plr', Kv.restored_plr, 'gput', Kv.gput, ...
            'rec_ch', Kv.rec_ch, 'rec_core_ch', Kv.rec_core_ch);
    end
end
end

function [BC, PC] = clean_reference(PP, K, sp, ref, C)
% Restoration reference of every (Eb/N0, geometry) of split sp: the clean link's BER,
% at least C.ber_floor, and its packet loss; 'mean' the table per Eb/N0 (PP.clean,
% PP.clean_fer: the clean validation flights, clean_ref_rebuild.m),
% 'flight' the clean cell on the same geometry (the mean where it does not fly it).
nS = numel(PP.ebno);
BC = repmat(max(PP.clean(:), C.ber_floor), 1, K.nR(sp)); PC = repmat(PP.clean_fer(:), 1, K.nR(sp));
if ~strcmp(ref, 'flight'), return; end
for s = 1:nS
    P = PP.pools{K.clean, s, K.na, sp};
    if isempty(P) || isempty(P.ber), continue; end
    for r = 1:K.nR(sp)
        k = span(P.run == PP.runs{sp}(r), K.ev{sp}(r));
        if any(k), BC(s, r) = max(mean(P.ber(k)), C.ber_floor); PC(s, r) = mean(double(P.fer(k))); end
    end
end
end

%% ===================== Reset / step =====================
function [E, obs] = reset_env(PP, K, spec, split, rs)
NE = numel(spec.scn);
E = spec; E.NE = NE; E.split = split; E.rs = rs;
E.t = zeros(1, NE);
E.cfg = K.na * ones(1, NE);
E.cfg_link = E.cfg;
if isfield(spec, 'delay') && ~isempty(spec.delay), E.D = spec.delay; else, E.D = decision_config().switch_delay; end
E.queue = K.na * ones(E.D, NE);                     % requests on their way to the GCS
E.hopq = false(E.D, NE);                            % the requests that carry a hop
E.last_switch = -inf(1, NE);
E.hop_live = -inf(1, NE);                           % frame from which the channel in use was taken
E.crc = false(1, NE);                               % CRC of the frame just received failed
E.fec_t = -inf(1, NE);                              % frame from which the link runs coded
E.nhop = zeros(1, NE); E.nh_on = E.nhop;            % hops that reached the link, and of them before the onset
if ~isfield(spec, 'cover'), E.cover = []; end
if ~isfield(spec, 'acr'), E.acr = []; end
if ~isfield(spec, 'cover_rel') || isempty(spec.cover_rel), E.cover_rel = false(1, NE); end
if ~isfield(spec, 'comb') || isempty(spec.comb), E.comb = false(1, NE); end
if ~isfield(spec, 'offset') || isempty(spec.offset), E.offset = inf(1, NE); end
if ~isfield(spec, 'r') || isempty(spec.r)            % geometry of the episode, one its cell flies
    G = K.geo(E.scn, split);
    if all(cellfun(@(g) isequal(g, G{1}), G))
        E.r = G{1}(randi(rs, numel(G{1}), 1, NE));
    else
        E.r = cellfun(@(g) g(randi(rs, numel(g))), G(:)');
    end
end
E.k0 = randi(rs, PP.F_SUB, 1, NE) - 1;               % starting frame inside the geometry
assert(mod(PP.F_SUB, 2) == 0, 'link_env: %d frames per geometry do not hold whole frame pairs (coded packets)', PP.F_SUB);
ev = K.ev{split}(E.r);                              % a rolling-in flight: the onset reads its event's frame
E.ev = isfinite(ev);
E.k0(E.ev) = ev(E.ev) - 1 - E.onset(E.ev);
E.aoa = nan(NE, 3);
for i = 1:NE
    P = PP.pools{E.scn(i), E.s(i), K.na, split};
    if isfield(P, 'aoa') && ~isempty(P.aoa)
        j = find(P.run == PP.runs{split}(E.r(i)), 1);
        if isempty(j), error('link_env: %s does not fly geometry %d of split %d', PP.scen{E.scn(i)}, E.r(i), split); end
        E.aoa(i, 1:size(P.aoa, 2)) = P.aoa(j, :);
    end
end
[E, obs] = draw(E, PP, K);
end

function [E, r, obs, info] = step_env(E, PP, K, a)
a = a(:)';
prev = E.cfg; prev_link = E.cfg_link;
if ~isfield(E, 'offset'), E.offset = inf(1, E.NE); end
if ~isfield(E, 'nhop'), E.nhop = zeros(1, E.NE); E.nh_on = E.nhop; E.cover = []; E.acr = []; end
rel = a ~= prev & a == K.na & E.t >= E.offset;      % decided on a frame after the threat's end
pend = any(E.hopq, 1);                              % a hop on its way to the GCS
hop = K.hasCh(a) & (~K.hasCh(prev) | E.crc) & ~pend;
changed = a ~= prev;
E.cfg = a;
if E.D > 0
    E.cfg_link = E.queue(1, :); arr = E.hopq(1, :);
    E.queue = [E.queue(2:end, :); a]; E.hopq = [E.hopq(2:end, :); hop];
else
    E.cfg_link = a; arr = hop;
end
E.last_switch(changed | hop) = E.t(changed | hop) + 1;
E.t = E.t + 1;
turn = K.hasFec(E.cfg_link) & ~K.hasFec(prev_link);  % the link runs coded from this frame
E.fec_t(turn) = E.t(turn);
gap = K.hasFec(E.cfg_link) & E.t - E.fec_t < K.Q - 1;   % no coded packet decoded yet
E.hop_live(arr) = E.t(arr);                         % the new channel is in use from this frame
E.nhop = E.nhop + arr;
pre = E.t < E.onset; E.nh_on(pre) = E.nhop(pre);
[E, obs, sc_eff, cfg_eff, cm, lay] = draw(E, PP, K);
sp = E.split * ones(1, E.NE);
idx = sub2ind(size(K.q), sc_eff, E.s, cfg_eff, sp, E.r);
ih = sub2ind(size(K.healthy), sc_eff, E.s, sp, E.r);
healthy = K.healthy(ih);
q = K.q(idx); rst = K.restored(idx); rpl = K.restored_plr(idx); gpt = K.gput(idx);
nL = 0; if isfield(K, 'acr_tabs'), nL = numel(K.acr_tabs); end
for v = 1:nL                                        % an escaped hop at another rejection
    j = lay == v; if ~any(j), continue; end
    q(j) = K.acr_tabs{v}.q(idx(j)); rst(j) = K.acr_tabs{v}.restored(idx(j));
    rpl(j) = K.acr_tabs{v}.restored_plr(idx(j)); gpt(j) = K.acr_tabs{v}.gput(idx(j));
end
r = (q - K.cost(E.cfg_link) - K.SW * (changed | hop) - K.FA * (changed & healthy & ~rel)) / 100;
rec = K.recoverable(ih); rec(E.comb) = K.recoverable_comb(ih(E.comb));
rcr = rec;
if isfield(K, 'rec_core'), rcr = K.rec_core(ih); rcr(E.comb) = K.rec_core_comb(ih(E.comb)); end
if ~isempty(E.cover)                                % a channel_switch configuration only through an escaped hop
    j = ~E.comb;
    rec(j) = K.rec_noch(ih(j)) | reach_escape(E, j, K, ih(j), 'rec_ch');
    if isfield(K, 'rec_core'), rcr(j) = K.rec_core_noch(ih(j)) | reach_escape(E, j, K, ih(j), 'rec_core_ch'); else, rcr = rec; end
end
info = struct('q', q, 'restored', rst & ~gap, 'restored_plr', rpl & ~gap, ...
    'fec_gap', gap, 'gput', gpt, ...
    'changed', changed | hop, 'false_switch', changed & healthy & ~rel, 'healthy', healthy, ...
    'recoverable', rec, 'recoverable_core', rcr, 'sc_eff', sc_eff, 'cfg_eff', cfg_eff, 'post', E.t >= E.onset, ...
    'hop', hop, 'hop_in', arr, 'compromised', cm, 'ended', E.t >= E.offset, 'released', rel);
end

function [c, cf, lay] = compromised(E, K, cfg)
% c: a follower has re-acquired the channel in use, or the static jammer covers it
% (spec.cover); cf: a comb jammer holds the second carrier of frequency diversity; lay: the
% residual's layer of an escaped hop (spec.acr; 0 the pools).
on = K.followable(E.scn) & E.t >= E.onset & E.t < E.offset;
c = on & E.follow & K.hasCh(cfg) & (E.t - E.hop_live) >= E.fdelay;
cf = on & E.comb & K.hasFd(cfg);
lay = zeros(1, E.NE);
if isfield(E, 'cover') && ~isempty(E.cover)
    [cv, k] = on_channel(E);
    c = c | (on & K.hasCh(cfg) & cv);
    if isfield(E, 'acr') && ~isempty(E.acr)
        j = on & K.hasCh(cfg) & ~c & k > 0;
        lay(j) = E.acr(sub2ind(size(E.acr), find(j), k(j))) - 1;
    end
end
end

function [cv, k] = on_channel(E)
% The jammer covers the channel in use: the home channel before the first hop, else the
% channel of the k-th hop that reached the link (spec.cover_rel: the k-th after the onset,
% the channel in use at the onset covered).
k = E.nhop - E.nh_on .* rel_cover(E); cv = true(1, E.NE); h = k > 0;
if any(k > size(E.cover, 2))
    error('link_env:cover', 'link_env: hop %d reached the link, spec.cover holds %d', max(k), size(E.cover, 2));
end
cv(h) = E.cover(sub2ind(size(E.cover), find(h), k(h)));
end

function e = reach_escape(E, j, K, ih, fld)
% Some hop that can reach the link after the onset escapes the jammer and a channel_switch
% configuration restores the geometry there, K.(fld) at ih (episodes j): with spec.acr at that
% hop's layer (K.acr_tabs), else the pools'.
H = size(E.cover, 2); ii = find(j); rel = rel_cover(E);
lay = isfield(E, 'acr') && ~isempty(E.acr);
e = false(1, numel(ii));
for m = 1:numel(ii)
    i = ii(m);
    n = floor((E.T - E.onset(i) - 1) / (E.D + 1));
    w = E.nh_on(i) * ~rel(i) + (1:n); w = w(w <= H);
    w = w(~E.cover(i, w));
    if isempty(w), continue; end
    if ~lay, e(m) = K.(fld)(ih(m)); continue; end
    for v = unique(E.acr(i, w))
        if v == 1, ok = K.(fld)(ih(m)); else, ok = K.acr_tabs{v - 1}.(fld)(ih(m)); end
        if ok, e(m) = true; break; end
    end
end
end

function rel = rel_cover(E)
% Episodes whose jammer takes the channel in use at the onset (spec.cover_rel).
rel = false(1, E.NE);
if isfield(E, 'cover_rel') && ~isempty(E.cover_rel), rel = logical(E.cover_rel(:)'); end
end

function [E, obs, sc_eff, cfg_eff, cm, lay] = draw(E, PP, K)
% Frame of the effective (cell, configuration), same geometry, frame position
% k0 + t inside the geometry (cyclic; a rolling-in flight beyond its run's end cycles over
% its last 10 frames); lay > 0 takes it from the residual's layer PP.acr_pools{lay}.
sc_eff = E.scn; sc_eff(E.t < E.onset | E.t >= E.offset) = K.clean;
cfg_eff = E.cfg_link;
[cm, cf, lay] = compromised(E, K, E.cfg_link);
cfg_eff(cm) = K.strip(E.cfg_link(cm));
cfg_eff(cf) = K.strip_fd(E.cfg_link(cf));
cm = cm | cf;
nC = numel(PP.classes); nF = numel(PP.feat_names);
icrc = feature_index('crc_fail');
obs.probs = zeros(E.NE, nC); obs.unknown = false(E.NE, 1); obs.feat = zeros(E.NE, nF); obs.ber_true = zeros(E.NE, 1);
obs.fer_true = zeros(E.NE, 1);
obs.maha = zeros(E.NE, 1); obs.gant = [];
obs.idle = nan(E.NE, numel(idle_summary('names')));     % the idle time before the frame (pools without it: none)
obs.bch = [];                                           % every antenna's channel estimates (branch_record.m)
obs.mmse_pred = nan(E.NE, 1);                           % the predicted MMSE gain over MRC (pools without it: none)
for i = 1:E.NE
    if lay(i) > 0, P = PP.acr_pools{lay(i)}{sc_eff(i), E.s(i), cfg_eff(i), E.split};
    else, P = PP.pools{sc_eff(i), E.s(i), cfg_eff(i), E.split}; end
    rows = find(P.run == PP.runs{E.split}(E.r(i)));
    q = E.k0(i) + E.t(i); n = numel(rows);
    if isfield(E, 'ev') && E.ev(i) && q >= n, q = n - 10 + mod(q - n, 10); end
    j = rows(mod(q, n) + 1);
    obs.probs(i, :) = P.probs(j, :);
    if isfield(P, 'probs3')
        if ~isfield(obs, 'probs3'), obs.probs3 = nan(E.NE, size(P.probs3, 2)); end
        obs.probs3(i, :) = P.probs3(j, :);
    end
    obs.unknown(i) = P.maha(j) < PP.maha_thr;
    obs.maha(i) = P.maha(j);
    obs.feat(i, :) = P.feat(j, :);
    E.crc(i) = P.feat(j, icrc) > 0.5;
    if isfield(P, 'gant') && ~isempty(P.gant)
        if isempty(obs.gant), obs.gant = zeros(E.NE, size(P.gant, 2)); end
        obs.gant(i, :) = P.gant(j, :);
    end
    if isfield(P, 'idle') && ~isempty(P.idle), obs.idle(i, :) = P.idle(j, :); end
    if isfield(P, 'bch') && ~isempty(P.bch)
        if isempty(obs.bch), obs.bch = nan(E.NE, size(P.bch, 2)); end
        obs.bch(i, :) = P.bch(j, :);
    end
    if isfield(P, 'mmse_pred') && ~isempty(P.mmse_pred), obs.mmse_pred(i) = P.mmse_pred(j); end
    obs.ber_true(i) = P.ber(j);
    obs.fer_true(i) = P.fer(j);
end
mask = E.unk & E.t >= E.onset;
obs.probs(mask, :) = 0; obs.unknown(mask) = true; obs.maha(mask) = -Inf;
obs.cfg_link = E.cfg_link(:);
obs.pkt = floor((E.k0(:) + E.t(:)) / 2);           % frame position k0 + t: pairs of the geometry's frames (F_SUB even, so the pairs wrap with the frames)
end

function k = span(k, e)
% The rows k of one run from its event's frame e on for a rolling-in flight (event_rows.m).
if isfinite(e)
    i = find(k);
    k(i(1:min(e - 1, numel(i)))) = false;
end
end
