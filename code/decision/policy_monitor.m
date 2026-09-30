function [mem, M] = policy_monitor(cmd, varargin)
%POLICY_MONITOR  Link monitor shared by every decision-layer policy.
%   mem = policy_monitor('init', NE, nA)
%   [mem, M] = policy_monitor('update', mem, obs, PP, cfg)
%
%   Receiver measurements only (link_features.m): the estimated BER and the CRC
%   packet loss of the last C.win frames. Degradation: the estimated BER above
%   C.ratio_ok x the clean link's estimated BER at the receiver's own Eb/N0
%   estimate (clean_ber_ref.m, floor C.deg_floor); with fec_interleave in the
%   configuration the channel BER stays high while the decoder repairs the bursts,
%   so there the CRC packet loss decides (above C.ratio_ok x the clean coded link,
%   at least 2 of the C.win packets).
%   Detected class: 'unknown' when the unknown-threat score is below its threshold.
%   Alarm, PP.alarm_mode 'class' (default): a hostile threat class, or degradation;
%   'none', 'benign_interference' (non-hostile, D9) and 'unknown' raise it only
%   through degradation. 'class_drop': as 'class', but the class path_loss
%   counts only when the signal-over-thermal estimate has dropped by at least
%   PP.drop_db from the episode's reference. Drop: reference = median
%   Eb/N0 estimate of the last 10 cycles without an alarm, minus the median of the
%   last 3 cycles. An alarm is CONFIRMED when at least m of the last n cycles carried
%   one (M-of-N binary integration, PP.confirm, default C.confirm).
%   The monitor also keeps the last C.hist observation vectors of policy_state.m.
%   mem.since starts saturated (10): the policies never see the episode clock.
%   mem.deg_n / mem.conf_n: consecutive degraded / confirmed-alarm cycles.
%   M: ber_avg, plr (NE x 1), ebno_est, drop (dB), degraded, cls, alarm, confirmed (1 x NE)
C = decision_config();
switch cmd
    case 'init'
        NE = varargin{1}; nA = varargin{2};
        mem = struct('ber', nan(NE, C.win), 'crc', nan(NE, C.win), 'tried', false(NE, nA), ...
            'since', 10 * ones(1, NE), 'cand', zeros(1, NE), 'cand_n', zeros(1, NE), 'good', zeros(1, NE), ...
            'deg_n', zeros(1, NE), 'conf_n', zeros(1, NE), 'alarm', false(NE, 8), 'ebno', nan(NE, 3), ...
            'ref', nan(NE, 10), 'hist', []);
        M = [];
    case 'update'
        [mem, M] = update(C, varargin{:});
    otherwise
        error('policy_monitor: unknown command %s', cmd);
end
end

function [mem, M] = update(C, mem, obs, PP, cfg)
cf = C.confirm;
if isfield(PP, 'confirm') && ~isempty(PP.confirm), cf = PP.confirm; end
fi = @(n) obs.feat(:, feature_index(n));
mem.ber = [mem.ber(:, 2:end), 10.^fi('log_ber')];
mem.crc = [mem.crc(:, 2:end), fi('crc_fail')];
M.ber_avg = mean(mem.ber, 2, 'omitnan');
M.plr = mean(mem.crc, 2, 'omitnan');
M.ebno_est = fi('sinr') + fi('iot') + 10*log10(PP.sps) - 10*log10(PP.bps);
mem.ebno = [mem.ebno(:, 2:end), M.ebno_est(:)];
e3 = median(mem.ebno, 2, 'omitnan');
ref = median(mem.ref, 2, 'omitnan');
ref(isnan(ref)) = e3(isnan(ref));
M.drop = (ref - e3)';
bc = max(clean_ber_ref(M.ebno_est, 'ber_est'), C.deg_floor);
deg = M.ber_avg > C.ratio_ok * bc;
if isfield(obs, 'cfg_link'), cfg = obs.cfg_link(:)'; end        % the configuration this frame was received with
coded = contains(PP.actions(cfg), 'fec_interleave');
if any(coded)
    pc = clean_ber_ref(M.ebno_est(coded), 'plr_fec');
    pc(isnan(pc)) = 0;
    deg(coded) = M.plr(coded) > max(C.ratio_ok * pc, 1.5 / C.win);
end
M.degraded = deg(:)';
mem.good(~M.degraded) = mem.good(~M.degraded) + 1; mem.good(M.degraded) = 0;
mem.deg_n(M.degraded) = mem.deg_n(M.degraded) + 1; mem.deg_n(~M.degraded) = 0;
mem.tried(mem.good >= C.heal, :) = false;
[~, k] = max(obs.probs, [], 2);
cls = PP.classes(k);
cls(obs.unknown) = {'unknown'};
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
M.confirmed = sum(mem.alarm(:, end-cf(2)+1:end), 2)' >= cf(1);
mem.conf_n(M.confirmed) = mem.conf_n(M.confirmed) + 1; mem.conf_n(~M.confirmed) = 0;
% Observation of this cycle for the agent's state (policy_state.m), newest first
o = policy_obs(obs, M, bc);
if isempty(mem.hist), mem.hist = repmat(o, 1, 1, C.hist); end
mem.hist = cat(3, o, mem.hist(:, :, 1:end-1));
end

function o = policy_obs(obs, M, bc)
% Per-cycle observation (rows) x episodes: class probabilities, unknown flag,
% log10 estimated BER (window), degradation (log10 of estimate / clean estimate,
% clipped to [-1, 3]), packet loss (window), SINR, IoT, post-combining SNR,
% spatial coherence, predicted MMSE gain, alignment, antenna gain gap, Eb/N0
% drop (clipped).
fi = @(n) obs.feat(:, feature_index(n));
lb = log10(max(M.ber_avg, 1e-6));
deg = min(3, max(-1, log10(max(M.ber_avg, 1e-6) ./ bc)));
o = [obs.probs'; double(obs.unknown(:)'); lb'; deg'; M.plr'; fi('sinr')'; fi('iot')'; fi('snr_post')'; ...
     fi('coh')'; fi('mmse_gain')'; fi('align')'; fi('branch_gap')'; min(20, max(-10, M.drop))];
end
