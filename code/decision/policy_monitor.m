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
%   over the last PP.unk_win cycles, is below its threshold.
%   Alarm, PP.alarm_mode 'class' (default): a hostile threat class, or degradation;
%   'none', 'benign_interference' (non-hostile, D9) and 'unknown' raise it only
%   through degradation. 'class_drop': as 'class', but the class path_loss
%   counts only when the signal-over-thermal estimate has dropped by at least
%   PP.drop_db from the episode's reference. Drop: reference = median
%   Eb/N0 estimate of the last 10 cycles without an alarm, minus the median of the
%   last 3 cycles. An alarm is CONFIRMED when at least m of the last n cycles carried
%   one (M-of-N binary integration, PP.confirm, default C.confirm).
%   The monitor also keeps the last C.hist observation vectors of policy_state.m,
%   and the window of the temporal fusion (probabilities, antenna gains, link
%   features, unknown scores).
%   mem.since starts saturated (10): the policies never see the episode clock.
%   mem.deg_n / mem.conf_n: consecutive degraded / confirmed-alarm cycles; mem.pend:
%   a requested change not yet received.
%   M: ber_avg, plr (NE x 1), ebno_est, drop (dB), degraded, cls, alarm, confirmed (1 x NE),
%      probs (NE x classes, fused), te (NE x 9, persistence measurements of the window,
%      temporal_evidence.m)
C = decision_config();
switch cmd
    case 'init'
        NE = varargin{1}; nA = varargin{2};
        nw = max(2 * C.win, C.fec_frames + 2);
        mem = struct('ber', nan(NE, C.win), 'crc', nan(NE, nw), 'pk', nan(NE, nw), 'tried', false(NE, nA), ...
            'since', 10 * ones(1, NE), 'cand', zeros(1, NE), 'cand_n', zeros(1, NE), 'good', zeros(1, NE), ...
            'deg_n', zeros(1, NE), 'conf_n', zeros(1, NE), 'alarm', false(NE, 8), 'ebno', nan(NE, 3), ...
            'ref', nan(NE, 10), 'hist', [], 'wp', [], 'wg', [], 'wf', [], 'wu', [], 'wn', zeros(1, NE), ...
            'unk_now', false(1, NE), 'pend', false(1, NE));
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
mem.ebno = [mem.ebno(:, 2:end), M.ebno_est(:)];
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
[mem, pf, te, unk] = fusion(mem, obs, PP);
M.probs = pf; M.te = te;
[~, k] = max(pf, [], 2);
cls = PP.classes(k);
cls(unk) = {'unknown'};
M.cls = cls(:)';
mode = 'class'; if isfield(PP, 'alarm_mode'), mode = PP.alarm_mode; end
hostile = ~ismember(M.cls, {'none', 'benign_interference', 'unknown'});
switch mode
    case 'degraded'
        M.alarm = M.degraded;
    case 'class_drop'
        dd = C.drop_db; if isfield(PP, 'drop_db') && ~isempty(PP.drop_db), dd = PP.drop_db; end
        hostile(strcmp(M.cls, 'path_loss') & M.drop < dd) = false;
        M.alarm = hostile | M.degraded;
    otherwise
        M.alarm = hostile | M.degraded;
end
q = ~M.alarm;
mem.ref(q, :) = [mem.ref(q, 2:end), M.ebno_est(q)];
mem.alarm = [mem.alarm(:, 2:end), M.alarm(:)];
assert(cf(2) <= size(mem.alarm, 2), 'policy_monitor: confirmation over %d cycles exceeds the alarm memory', cf(2));
M.confirmed = sum(mem.alarm(:, end-cf(2)+1:end), 2)' >= cf(1);
mem.conf_n(M.confirmed) = mem.conf_n(M.confirmed) + 1; mem.conf_n(~M.confirmed) = 0;
% Observation of this cycle for the agent's state (policy_state.m), newest first
o = policy_obs(obs, M, bc, unk);
if isempty(mem.hist), mem.hist = repmat(o, 1, 1, C.hist); end
mem.hist = cat(3, o, mem.hist(:, :, 1:end-1));
end

function o = policy_obs(obs, M, bc, unk)
% Per-cycle observation (rows) x episodes: class probabilities (fused over the
% last cycles), unknown flag, log10 estimated BER (window), degradation (log10 of
% estimate / clean estimate, clipped to [-1, 3]), packet loss (window), SINR, IoT,
% post-combining SNR, quiet-slot spatial coherence, predicted MMSE gain, alignment, antenna
% gain gap, Eb/N0 drop (clipped), quiet-slot interference, reactive ratio, and the
% persistence measurements of the window (temporal_evidence.m: gap of the antennas'
% local means, share of cycles with the same weakest antenna, share with quiet-slot
% interference, share with one antenna 20 dB below the next, the weakest antenna's
% offset and its spread, its K-factor and the share of cycles it is valid, busy share).
fi = @(n) obs.feat(:, feature_index(n));
lb = log10(max(M.ber_avg, 1e-6));
deg = min(3, max(-1, log10(max(M.ber_avg, 1e-6) ./ bc)));
o = [M.probs'; double(unk(:)'); lb'; deg'; M.plr'; fi('sinr')'; fi('iot')'; fi('snr_post')'; ...
     fi('coh')'; fi('mmse_gain')'; fi('align')'; fi('branch_gap')'; min(20, max(-10, M.drop)); ...
     min(40, max(-5, fi('q_iot')')); min(40, max(-10, fi('q_react')')); M.te'];
end

function [mem, pf, te, unk] = fusion(mem, obs, PP)
% Window of the last cycles (oldest first) and the fused class probabilities.
NE = size(obs.probs, 1);
N = 1; if isfield(PP, 'fuse_N') && ~isempty(PP.fuse_N), N = PP.fuse_N; end
Nu = 1; if isfield(PP, 'unk_win') && ~isempty(PP.unk_win), Nu = PP.unk_win; end
W = max([N, Nu, 1]);
g = zeros(NE, 1); if isfield(obs, 'gant') && ~isempty(obs.gant), g = obs.gant; end
mh = nan(NE, 1); if isfield(obs, 'maha') && ~isempty(obs.maha), mh = obs.maha(:); end
if isempty(mem.wp)
    mem.wp = repmat(obs.probs, 1, 1, W); mem.wg = repmat(g, 1, 1, W);
    mem.wf = repmat(obs.feat, 1, 1, W); mem.wu = repmat(mh, 1, W);
end
mem.wp = cat(3, mem.wp(:, :, 2:end), obs.probs); mem.wg = cat(3, mem.wg(:, :, 2:end), g);
mem.wf = cat(3, mem.wf(:, :, 2:end), obs.feat); mem.wu = [mem.wu(:, 2:end), mh];
mem.wn = min(mem.wn + 1, W);
nC = size(obs.probs, 2);
pf = obs.probs; te = zeros(NE, numel(temporal_evidence('names', nC)) - nC);
for n = unique(mem.wn)                                     % episodes with the same filled window length
    e = find(mem.wn == n);
    k = W - min(n, N) + 1:W;
    Z = temporal_evidence(mem.wp(e, :, k), mem.wg(e, :, k), mem.wf(e, :, k));
    te(e, :) = Z(:, nC + 1:end);
    if isfield(PP, 'fuse') && ~isempty(PP.fuse)                  % with the current frame's own evidence (fuse_classes.m)
        pf(e, :) = fuse_classes('apply', PP.fuse, [Z, log(max(double(mem.wp(e, :, W)), 1e-6))]);
    end
    ku = W - min(n, Nu) + 1:W;
    mem.unk_now(e) = mean(mem.wu(e, ku), 2) < PP.maha_thr;
end
unk = obs.unknown(:)';
if Nu > 1 && ~all(isnan(mh)), unk = mem.unk_now(:)' | (obs.unknown(:)' & isinf(mh(:)')); end
end

function [n, lost] = packets(crc)
% Packets in the window and the lost ones (NE x 1): every frame with a CRC result, a
% coded packet's decoding frame or an uncoded frame.
k = ~isnan(crc);
n = sum(k, 2);
lost = sum(k & crc > 0, 2);
end
