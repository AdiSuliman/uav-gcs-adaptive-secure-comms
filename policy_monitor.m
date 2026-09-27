function [mem, M] = policy_monitor(cmd, varargin)
%POLICY_MONITOR  Link monitor shared by every decision-layer policy (D45, D48-D50).
%   mem = policy_monitor('init', NE, nA)
%   [mem, M] = policy_monitor('update', mem, obs, PP)
%
%   Per episode: BER of the last 5 frames, degradation (5-frame BER > 2x the
%   clean BER at the receiver's Eb/N0 estimate, floor 1e-3 = one error per
%   frame), detected class ('unknown' when the Mahalanobis score is below its
%   threshold) and the alarm. PP.alarm_mode 'class' (default): a hostile threat
%   class, or degradation; 'none', 'benign_interference' (non-hostile, D9) and
%   'unknown' raise it only through degradation (D33). PP.alarm_mode 'degraded':
%   degradation only; the class still chooses the response (D49).
%   PP.alarm_mode 'class_drop': as 'class', but the class path_loss counts only
%   when the signal-over-thermal estimate has dropped by at least PP.drop_db
%   (default 4 dB) from the episode's reference (D50). Attenuation is a change of
%   the link, not a level: a clean link at low Eb/N0 receives the same signal as
%   an attenuated link at a higher Eb/N0, and only the history tells them apart.
%   Drop: reference = median Eb/N0 estimate of the last 10 cycles without an
%   alarm (the current value before any such cycle), minus the median of the
%   last 3 cycles; it is also a state input of the DQN (policy_state.m).
%   An alarm is CONFIRMED when at least m of the last n cycles carried one
%   (M-of-N binary integration, PP.confirm = [m n], default [2 2]; chosen on
%   validation in train_dqn.m); policy_mask.m and the rule and table policies
%   start a new configuration only then.
%   mem.since starts saturated (10): the policies never see the episode clock.
%   M: ber_avg (NE x 1), ebno_est, drop (dB), degraded, cls, alarm, confirmed (1 x NE)
switch cmd
    case 'init'
        NE = varargin{1}; nA = varargin{2};
        mem = struct('ber', nan(NE, 5), 'tried', false(NE, nA), 'since', 10 * ones(1, NE), ...
            'cand', zeros(1, NE), 'cand_n', zeros(1, NE), 'good', zeros(1, NE), 'deg_n', zeros(1, NE), ...
            'alarm', false(NE, 8), 'ebno', nan(NE, 3), 'ref', nan(NE, 10));
        M = [];
    case 'update'
        [mem, M] = update(varargin{:});
    otherwise
        error('policy_monitor: unknown command %s', cmd);
end
end

function [mem, M] = update(mem, obs, PP)
HEAL = 5;
cf = [2 2];
if isfield(PP, 'confirm') && ~isempty(PP.confirm), cf = PP.confirm; end
mem.ber = [mem.ber(:, 2:end), obs.ber(:)];
M.ber_avg = mean(mem.ber, 2, 'omitnan');
sinr = obs.feat(:, 1); iot = obs.feat(:, 9);
M.ebno_est = sinr + iot + 10*log10(PP.sps) - 10*log10(PP.bps);
mem.ebno = [mem.ebno(:, 2:end), M.ebno_est(:)];
e3 = median(mem.ebno, 2, 'omitnan');
ref = median(mem.ref, 2, 'omitnan');
ref(isnan(ref)) = e3(isnan(ref));
M.drop = (ref - e3)';
bc = max(clean_ber_ref(M.ebno_est), 1e-3);
M.degraded = (M.ber_avg > 2 * bc)';
mem.good(~M.degraded) = mem.good(~M.degraded) + 1; mem.good(M.degraded) = 0;
mem.deg_n(M.degraded) = mem.deg_n(M.degraded) + 1; mem.deg_n(~M.degraded) = 0;
mem.tried(mem.good >= HEAL, :) = false;
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
        dd = 4; if isfield(PP, 'drop_db'), dd = PP.drop_db; end
        hostile(strcmp(M.cls, 'path_loss') & M.drop < dd) = false;
        M.alarm = hostile | M.degraded;
    otherwise
        M.alarm = hostile | M.degraded;
end
q = ~M.alarm;
mem.ref(q, :) = [mem.ref(q, 2:end), M.ebno_est(q)];
mem.alarm = [mem.alarm(:, 2:end), M.alarm(:)];
M.confirmed = sum(mem.alarm(:, end-cf(2)+1:end), 2)' >= cf(1);
end
