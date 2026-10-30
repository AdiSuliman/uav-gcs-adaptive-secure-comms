function [mem, M] = policy_monitor(cmd, varargin)
%POLICY_MONITOR  Link monitor shared by every decision-layer policy.
%   mem = policy_monitor('init', NE, nA)
%   [mem, M] = policy_monitor('update', mem, obs, PP, cfg)
%   mem = policy_monitor('change', mem, ch)      after a decision; ch (1 x NE): the
%                                                configuration changed
%
%   cfg is the configuration requested; obs.cfg_link, when present, the one the frame
%   was received with. While they differ the request is on its way to the GCS: the
%   cycles since the change stay at 0, so the hold and the escalation wait. The first
%   frame received with the request restarts the BER and CRC windows and the count
%   of degraded cycles, and the cycles since the change count from there.
%   Receiver measurements only (link_features.m): the estimated BER of the last C.win
%   frames and the CRC packet loss of the packets they carry. A coded packet ends on a
%   frame pair (obs.pkt, the pair's key) and its codeword spans PP.fec_frames frames (Q,
%   default C.fec_frames), the pairs before it (fec_packets.m): it counts once, at the
%   second frame of its pair, when it is decoded, and only when all Q frames of its
%   codeword were received coded; without obs.pkt every frame's CRC result counts. An
%   uncoded link's packet loss is read over the last C.win frames, a coded link's over
%   the last 2 C.win, the C.win packets decoded there (as many packets as uncoded).
%   Degradation: the estimated BER above C.ratio_ok x the clean link's estimated BER
%   at the receiver's own Eb/N0 estimate (clean_ber_ref.m, floor C.deg_floor); with
%   fec_interleave in the configuration the channel BER stays high while the decoder
%   repairs the bursts, so there the CRC packet loss decides: more lost packets in the
%   window than C.ratio_ok x the clean coded link's loss over its packets plus one loss
%   event, the Q/2 packets whose codewords share a frame the decoder cannot repair (the
%   slack of restored_plr, packet_share.m).
%   Detected class: from the temporal fusion of the last PP.fuse_N cycles and the
%   current one (temporal_evidence.m, fuse_classes.m) when PP.fuse is set, otherwise
%   the frame's own detector output; 'unknown' when the unknown-threat score, averaged
%   over the last PP.unk_win cycles, is below its threshold PP.maha_thr: every class with
%   PP.unk_mode 'all' (the default), only a class that raises no alarm (none,
%   benign_interference) with 'nonhostile', so a hostile class read keeps its alarm (the mode
%   and the threshold's retention are chosen on validation, train_dqn.m).
%   Alarm, PP.alarm_mode 'class' (default): a hostile threat class, or degradation;
%   'none', 'benign_interference' (non-hostile, D9) and 'unknown' raise it only
%   through degradation. 'class_drop': as 'class', but the class path_loss
%   counts only when the signal-over-thermal estimate has dropped by at least
%   PP.drop_db from the episode's reference, and that drop raises the alarm by itself
%   (drop_alarm); the reference takes the cycles without an alarm of an excursion of that
%   drop above half the smallest path-loss level only once it has returned below it without
%   the drop alarm (drop_ref.m, as 'class_cusum' holds it): a step below the threshold is
%   never absorbed into the reference. A step of attenuation stays a lower signal over thermal noise after the
%   detector's window has passed its onset, while moving away lowers it by at most
%   8.69 v / d dB/s, about 0.2 dB between the reference and the last 3 cycles at
%   161 km/h and 0.28 km. The estimate is our signal over the thermal floor (SINR +
%   interference over thermal), so interference does not move it. Drop: reference = median
%   Eb/N0 estimate of the last 10 cycles without an alarm, minus the median of the
%   last 3 cycles. Both windows hold the estimate less the known gain of the
%   configuration the frame was received with (config_gain_db.m: the power step and the
%   processing gain), so a change of our own configuration never reads as a drop or a
%   rise of the link; the degradation test keeps the estimate as measured.
%   'class_cusum': as 'class_drop', the drop alarm raised when the window-limited CUSUM of
%   every cycle's drop against the reference (drop_cusum.m: reference less the cycle's
%   estimate, the change's size estimated over the cycles before, bounded at twice
%   PP.drop_db so the alarm clears on the same evidence in reverse) reaches PP.drop_db; the
%   reference takes the cycles without an alarm of an excursion of the statistic above 0 only
%   once it has returned to 0 without the drop alarm (drop_ref.m), so it keeps the level
%   before a change while the evidence of one builds up.
%   An alarm is CONFIRMED when at least m of the last n cycles carried
%   one (M-of-N binary integration, PP.confirm, default C.confirm), or, with PP.confirm_sweep
%   = [k n] (chosen on validation, choose_drop_threshold.m), when at least k of the last n
%   cycles read sweeping_jammer: a sweep revisits our channel once per period, up to 83.5 ms,
%   so it is on isolated cycles (k-out-of-n detection of a swept jammer, Norouzi et al. 2006).
%   The monitor also keeps the last C.hist observation vectors of policy_state.m,
%   and the window of the temporal fusion (probabilities, antenna gains, link
%   features, unknown scores, and obs.idle, the record of each cycle's idle time,
%   idle_summary.m, and obs.bch, the record of each cycle's channel estimates per antenna,
%   branch_record.m, over window_cues('branch_window') cycles: the fusion's row holds
%   window_cues.m's columns, as fuse_classes.m's), and, for a fusion with the held columns,
%   the held reference of every branch over the episode's cycles (branch_ref.m, mem.br). The window's antenna gains are kept
%   less the power step and its SINR less the whole known gain of the configuration each
%   frame was received with, so the fusion reads no level step at a change of our own
%   configuration; within one configuration the window's statistics are those of the
%   frames as measured (each is unchanged by a common shift or scale).
%   mem.since starts saturated (10): the policies never see the episode clock.
%   mem.deg_n / mem.conf_n: consecutive degraded / confirmed-alarm cycles; mem.pend:
%   a requested change not yet received. With PP.lb_complete the memory of the link-budget
%   completion (lb_complete.m): mem.drop_n, mem.gc, mem.gref, mem.grp, mem.grx.
%   M: ber_avg, plr (NE x 1), ebno_est (as measured), drop (dB, without the configurations'
%      known gains), drop_alarm, degraded, cls, alarm, confirmed (1 x NE),
%      probs (NE x classes, fused), te (NE x 9, persistence measurements of the window,
%      temporal_evidence.m), and with PP.lb_complete dcomb (1 x NE), the drop of the combined
%      channel gain of all antennas (lb_complete.m)
C = decision_config();
switch cmd
    case 'init'
        NE = varargin{1}; nA = varargin{2};
        nw = max(2 * C.win, C.fec_frames + 2);
        mem = struct('ber', nan(NE, C.win), 'crc', nan(NE, nw), 'pk', nan(NE, nw), 'tried', false(NE, nA), ...
            'since', 10 * ones(1, NE), 'cand', zeros(1, NE), 'cand_n', zeros(1, NE), 'good', zeros(1, NE), ...
            'deg_n', zeros(1, NE), 'conf_n', zeros(1, NE), 'alarm', false(NE, 8), 'ebno', nan(NE, 3), ...
            'ref', nan(NE, 10), 'hist', [], 'wp', [], 'wg', [], 'wf', [], 'wu', [], 'wn', zeros(1, NE), ...
            'unk_now', false(1, NE), 'pend', false(1, NE), 'wi', [], 'wb', [], 'cs', zeros(NE, 1), ...
            'dx', nan(NE, C.cusum_win), 'rp', nan(NE, 10), 'rx', false(NE, 1), 'sw', false(NE, 8));
        M = [];
    case 'update'
        [mem, M] = update(C, varargin{:});
    case 'change'
        mem = varargin{1}; ch = varargin{2}(:)';
        mem.since(ch) = 0; mem.pend(ch) = true;
        k = ~ch & ~mem.pend; mem.since(k) = mem.since(k) + 1;
        M = [];
    otherwise
        error('policy_monitor: unknown command %s', cmd);
end
end

function [mem, M] = update(C, mem, obs, PP, cfg)
cf = C.confirm;
if isfield(PP, 'confirm') && ~isempty(PP.confirm), cf = PP.confirm; end
fi = @(n) obs.feat(:, feature_index(n));
link = cfg(:)'; if isfield(obs, 'cfg_link'), link = obs.cfg_link(:)'; end   % the configuration this frame was received with
wait = link ~= cfg(:)';                                 % the request is still on its way
arr = mem.pend & ~wait;                                 % first frame received with the request
mem.pend = wait; mem.since(wait) = 0;
mem.ber = [mem.ber(:, 2:end), 10.^fi('log_ber')];
mem.crc = [mem.crc(:, 2:end), fi('crc_fail')];
coded = contains(PP.actions(link), 'fec_interleave');
pk = nan(size(mem.crc, 1), 1);                                   % a frame is its own packet unless coded
if isfield(obs, 'pkt') && ~isempty(obs.pkt), pk(coded) = obs.pkt(coded); end
if ~isfield(mem, 'pk'), mem.pk = nan(size(mem.crc)); end
Q = C.fec_frames; if isfield(PP, 'fec_frames') && ~isempty(PP.fec_frames), Q = PP.fec_frames; end
nw = size(mem.crc, 2);
assert(Q + 2 <= nw && 2 * C.win <= nw, 'policy_monitor: a codeword of %d frames does not fit the packet window', Q);
kx = pk - floor((Q-1:-1:1) / 2);                                % keys of the codeword's earlier frames, oldest first
mem.crc(~isnan(pk) & ~all(mem.pk(:, end-Q+2:end) == kx, 2), end) = NaN;   % not decoded here, or not all of it coded
mem.pk = [mem.pk(:, 2:end), pk];
mem.ber(arr, 1:end-1) = NaN; mem.crc(arr, 1:end-1) = NaN; mem.deg_n(arr) = 0;
[npk, lost] = packets(mem.crc(:, nw - C.win + 1:nw));
[nq, lq] = packets(mem.crc(:, nw - 2 * C.win + 1:nw));
npk(coded) = nq(coded); lost(coded) = lq(coded);
M.ber_avg = mean(mem.ber, 2, 'omitnan');
M.plr = lost ./ max(npk, 1);                                    % no packet decoded yet in the window: no loss seen
M.ebno_est = fi('sinr') + fi('iot') + 10*log10(PP.sps) - 10*log10(PP.bps);
[gk, gw] = config_gain_db(PP);
eg = M.ebno_est(:) - reshape(gk(link), [], 1);                  % without the gain of the configuration received
mem.ebno = [mem.ebno(:, 2:end), eg];
e3 = median(mem.ebno, 2, 'omitnan');
ref = median(mem.ref, 2, 'omitnan');
ref(isnan(ref)) = e3(isnan(ref));
M.drop = (ref - e3)';
bc = max(clean_ber_ref(M.ebno_est, 'ber_est'), C.deg_floor);
deg = M.ber_avg > C.ratio_ok * bc;
if any(coded)
    pc = clean_ber_ref(M.ebno_est(coded), 'plr_fec');
    pc(isnan(pc)) = 0;
    deg(coded) = lost(coded) > C.ratio_ok * pc .* npk(coded) + Q / 2;
end
M.degraded = deg(:)';
mem.good(~M.degraded) = mem.good(~M.degraded) + 1; mem.good(M.degraded) = 0;
mem.deg_n(M.degraded) = mem.deg_n(M.degraded) + 1; mem.deg_n(~M.degraded) = 0;
mem.tried(mem.good >= C.heal, :) = false;
[mem, pf, te, unk] = fusion(mem, obs, PP, gk(link), gw(link));
% Latched cause of a lost branch (onset_shape.m): read from the shape of its onset, a
% step (antenna_fault) or a ramp (airframe_shadowing), and kept while the branch stays lost;
% only while the deployed fusion latches (onset_shape('on', PP.fuse), set by B2F)
if ~isfield(mem, 'os'), mem.os = []; end
FZ = []; if isfield(PP, 'fuse'), FZ = PP.fuse; end
if isfield(obs, 'gant') && ~isempty(obs.gant) && onset_shape('on', FZ)
    [mem.os, pf] = onset_shape('latch', mem.os, obs.gant, pf, PP.classes, C.heal, onset_shape('threshold', FZ));
end
M.probs = pf; M.te = te;
[~, k] = max(pf, [], 2);
cls = PP.classes(k); cls = cls(:)';
ov = unk;                                                       % the class the unknown-threat flag overrides
if isfield(PP, 'unk_mode') && strcmp(PP.unk_mode, 'nonhostile'), ov = unk & ismember(cls, {'none', 'benign_interference'}); end
cls(ov) = {'unknown'};
M.cls = cls;
mode = 'class'; if isfield(PP, 'alarm_mode'), mode = PP.alarm_mode; end
hostile = ~ismember(M.cls, {'none', 'benign_interference', 'unknown'});
M.drop_alarm = false(1, numel(M.cls));
switch mode
    case 'degraded'
        M.alarm = M.degraded;
    case {'class_drop', 'class_cusum'}
        dd = C.drop_db; if isfield(PP, 'drop_db') && ~isempty(PP.drop_db), dd = PP.drop_db; end
        if strcmp(mode, 'class_cusum')
            if ~isfield(mem, 'cs'), mem.cs = zeros(numel(eg), 1); mem.dx = nan(numel(eg), C.cusum_win); end
            dc = ref - eg;                                              % this cycle's drop
            mem.cs = drop_cusum(dc, mem.cs, mem.dx, dd); mem.dx = [mem.dx(:, 2:end), dc];
            M.drop_alarm = mem.cs' >= dd;
        else
            M.drop_alarm = M.drop >= dd;
        end
        hostile(strcmp(M.cls, 'path_loss') & ~M.drop_alarm) = false;
        M.alarm = hostile | M.degraded | M.drop_alarm;
    otherwise
        M.alarm = hostile | M.degraded;
end
q = ~M.alarm;
ex = [];                                                        % the excursion measure of the drop reference (drop alarms only)
if any(strcmp(mode, {'class_drop', 'class_cusum'}))            % the reference before a change building up
    if ~isfield(mem, 'rp'), mem.rp = nan(size(mem.ref)); mem.rx = false(numel(eg), 1); end
    ex = mem.cs; if strcmp(mode, 'class_drop'), ex = double(M.drop(:) >= C.sev.path_loss.levels(1) / 2); end
    [mem.ref, mem.rp, mem.rx] = drop_ref(mem.ref, mem.rp, mem.rx, eg, q(:), ex, M.drop_alarm(:));
else
    mem.ref(q, :) = [mem.ref(q, 2:end), eg(q)];
end
mem.alarm = [mem.alarm(:, 2:end), M.alarm(:)];
assert(cf(2) <= size(mem.alarm, 2), 'policy_monitor: confirmation over %d cycles exceeds the alarm memory', cf(2));
M.confirmed = sum(mem.alarm(:, end-cf(2)+1:end), 2)' >= cf(1);
if ~isfield(mem, 'sw'), mem.sw = false(size(mem.alarm)); end
mem.sw = [mem.sw(:, 2:end), strcmp(M.cls(:), 'sweeping_jammer')];
cs = []; if isfield(PP, 'confirm_sweep'), cs = PP.confirm_sweep; end
if ~isempty(cs) && ~strcmp(mode, 'degraded')                    % the sweeper's own revisit window
    assert(cs(2) <= size(mem.sw, 2), 'policy_monitor: the sweeper''s confirmation over %d cycles exceeds the alarm memory', cs(2));
    M.confirmed = M.confirmed | sum(mem.sw(:, end-cs(2)+1:end), 2)' >= cs(1);
end
mem.conf_n(M.confirmed) = mem.conf_n(M.confirmed) + 1; mem.conf_n(~M.confirmed) = 0;
if lb_complete('on', PP)                                        % the memory of the link-budget completion
    [mem, M.dcomb] = lb_complete('track', mem, obs, gw(link), q(:), ex, M);
end
% Observation of this cycle for the agent's state (policy_state.m), newest first
o = policy_obs(obs, M, bc, unk);
if isempty(mem.hist), mem.hist = repmat(o, 1, 1, C.hist); end
mem.hist = cat(3, o, mem.hist(:, :, 1:end-1));
end

function o = policy_obs(obs, M, bc, unk)
% Per-cycle observation (rows) x episodes: class probabilities (fused over the
% last cycles), unknown flag, log10 estimated BER (window), degradation (log10 of
% estimate / clean estimate, clipped to [-1, 3]), packet loss (window), SINR, IoT,
% post-combining SNR, quiet-slot spatial coherence, predicted MMSE gain (obs.mmse_pred,
% mmse_predict.m, 0 dB where a frame has none), alignment, antenna
% gain gap, Eb/N0 drop (clipped), quiet-slot interference, reactive ratio, and the
% persistence measurements of the window (temporal_evidence.m: gap of the antennas'
% local means, share of cycles with the same weakest antenna, share with quiet-slot
% interference, share with one antenna 20 dB below the next, the weakest antenna's
% offset and its spread, its K-factor and the share of cycles it is valid, busy share).
fi = @(n) obs.feat(:, feature_index(n));
mp = obs_mmse_pred(obs, size(obs.feat, 1)); mp(isnan(mp)) = 0;
lb = log10(max(M.ber_avg, 1e-6));
deg = min(3, max(-1, log10(max(M.ber_avg, 1e-6) ./ bc)));
o = [M.probs'; double(unk(:)'); lb'; deg'; M.plr'; fi('sinr')'; fi('iot')'; fi('snr_post')'; ...
     fi('coh')'; mp'; fi('align')'; fi('branch_gap')'; min(20, max(-10, M.drop)); ...
     min(40, max(-5, fi('q_iot')')); min(40, max(-10, fi('q_react')')); M.te'];
end

function [mem, pf, te, unk] = fusion(mem, obs, PP, gl, gp)
% Window of the last cycles (oldest first) and the fused class probabilities. The window
% holds every frame's levels less the known gain of the configuration it was received with
% (config_gain_db.m; gl the whole gain, gp its power step, per episode): the antennas'
% channel gains less the power step, the SINR less the whole gain, so a change of our own
% configuration is never read as a step of the level.
NE = size(obs.probs, 1);
N = 1; if isfield(PP, 'fuse_N') && ~isempty(PP.fuse_N), N = PP.fuse_N; end
Nu = 1; if isfield(PP, 'unk_win') && ~isempty(PP.unk_win), Nu = PP.unk_win; end
NB = 1; if isfield(PP, 'fuse') && ~isempty(PP.fuse), NB = window_cues('branch_window'); end
W = max([N, Nu, NB]);
g = zeros(NE, 1); if isfield(obs, 'gant') && ~isempty(obs.gant), g = obs.gant - reshape(gp, [], 1); end
f = obs.feat; is = feature_index('sinr');
f(:, is) = f(:, is) - reshape(gl, [], 1);
mh = nan(NE, 1); if isfield(obs, 'maha') && ~isempty(obs.maha), mh = obs.maha(:); end
if isempty(mem.wp)
    mem.wp = repmat(obs.probs, 1, 1, W); mem.wg = repmat(g, 1, 1, W);
    mem.wf = repmat(f, 1, 1, W); mem.wu = repmat(mh, 1, W);
end
mem.wp = cat(3, mem.wp(:, :, 2:end), obs.probs); mem.wg = cat(3, mem.wg(:, :, 2:end), g);
mem.wf = cat(3, mem.wf(:, :, 2:end), f); mem.wu = [mem.wu(:, 2:end), mh];
mem.wn = min(mem.wn + 1, W);
% The record of each cycle's idle time (idle_summary.m), NaN when the frame has none
nI = numel(idle_summary('names')); id = nan(NE, nI);
if isfield(obs, 'idle') && ~isempty(obs.idle), id = double(obs.idle); end
if ~isfield(mem, 'wi') || isempty(mem.wi), mem.wi = nan(NE, nI, W); end
mem.wi = cat(3, mem.wi(:, :, 2:end), id);
% The record of each cycle's channel estimates per antenna (branch_record.m), NaN without one
nB = 9 * size(g, 2); bc = nan(NE, nB);
if isfield(obs, 'bch') && ~isempty(obs.bch), bc = double(obs.bch); nB = size(bc, 2); end
if ~isfield(mem, 'wb') || isempty(mem.wb) || size(mem.wb, 2) ~= nB, mem.wb = nan(NE, nB, W); end
mem.wb = cat(3, mem.wb(:, :, 2:end), bc);
Hx = [];                                                   % the held reference of every branch (branch_ref.m)
cu = []; if isfield(PP, 'fuse') && ~isempty(PP.fuse), cu = fuse_classes('cues', PP.fuse); end
if isfield(cu, 'held') && cu.held && size(g, 2) > 1
    if ~isfield(mem, 'br') || isempty(mem.br), mem.br = branch_ref('init', NE, size(g, 2), isfield(cu, 'phi1') && cu.phi1); end
    [mem.br, Hx] = branch_ref('step', mem.br, g);
end
nC = size(obs.probs, 2);
pf = obs.probs; te = zeros(NE, numel(temporal_evidence('names', nC)) - nC);
for n = unique(mem.wn)                                     % episodes with the same filled window length
    e = find(mem.wn == n);
    k = W - min(n, N) + 1:W;
    Z = temporal_evidence(mem.wp(e, :, k), mem.wg(e, :, k), mem.wf(e, :, k));
    te(e, :) = Z(:, nC + 1:end);
    if isfield(PP, 'fuse') && ~isempty(PP.fuse)                  % with the current frame's own evidence (fuse_classes.m)
        kb = W - min(n, NB) + 1:W;
        Zc = window_cues(mem.wg(e, :, k), mem.wf(e, :, k), mem.wi(e, :, k), mem.wb(e, :, kb));   % branch, level step, idle time, branch coherence
        h = {}; if ~isempty(Hx), h = {Hx(e, :)}; end
        Xe = window_cues('extra', mem.wg(e, :, k), mem.wf(e, :, k), mem.wi(e, :, k), cu, h{:});
        pf(e, :) = fuse_classes('apply', PP.fuse, [Z, Zc, log(max(double(mem.wp(e, :, W)), 1e-6)), Xe]);
    end
    ku = W - min(n, Nu) + 1:W;
    mem.unk_now(e) = mean(mem.wu(e, ku), 2) < PP.maha_thr;
end
unk = obs.unknown(:)';                                     % the monitor's own threshold PP.maha_thr wherever a score is read
if ~all(isnan(mh)), unk = mem.unk_now(:)' | (obs.unknown(:)' & isinf(mh(:)')); end
end

function [n, lost] = packets(crc)
% Packets in the window and the lost ones (NE x 1): every frame with a CRC result, a
% coded packet's decoding frame or an uncoded frame.
k = ~isnan(crc);
n = sum(k, 2);
lost = sum(k & crc > 0, 2);
end
