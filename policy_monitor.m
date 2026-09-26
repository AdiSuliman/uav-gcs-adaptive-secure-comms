function [mem, M] = policy_monitor(cmd, varargin)
%POLICY_MONITOR  Link monitor shared by every decision-layer policy (D45).
%   mem = policy_monitor('init', NE, nA)
%   [mem, M] = policy_monitor('update', mem, obs, PP)
%
%   Per episode: BER of the last 5 frames, degradation (5-frame BER > 2x the
%   clean BER at the receiver's Eb/N0 estimate, floor 1e-3 = one error per
%   frame), detected class ('unknown' when the Mahalanobis score is below its
%   threshold) and the alarm: a threat class, 'unknown' or degradation. An alarm
%   is CONFIRMED after CONFIRM = 2 consecutive cycles (M-of-N confirmation);
%   policy_mask.m lets a policy start a new configuration only then.
%   mem.since starts saturated (10): the policies never see the episode clock.
%   M: ber_avg (NE x 1), ebno_est, degraded, cls, alarm, confirmed (1 x NE)
switch cmd
    case 'init'
        NE = varargin{1}; nA = varargin{2};
        mem = struct('ber', nan(NE, 5), 'tried', false(NE, nA), 'since', 10 * ones(1, NE), ...
            'cand', zeros(1, NE), 'cand_n', zeros(1, NE), 'good', zeros(1, NE), 'deg_n', zeros(1, NE), ...
            'alarm_n', zeros(1, NE));
        M = [];
    case 'update'
        [mem, M] = update(varargin{:});
    otherwise
        error('policy_monitor: unknown command %s', cmd);
end
end

function [mem, M] = update(mem, obs, PP)
CONFIRM = 2; HEAL = 5;
mem.ber = [mem.ber(:, 2:end), obs.ber(:)];
M.ber_avg = mean(mem.ber, 2, 'omitnan');
sinr = obs.feat(:, 1); iot = obs.feat(:, 9);
M.ebno_est = sinr + iot + 10*log10(PP.sps) - 10*log10(PP.bps);
bc = max(clean_ber_ref(M.ebno_est), 1e-3);
M.degraded = (M.ber_avg > 2 * bc)';
mem.good(~M.degraded) = mem.good(~M.degraded) + 1; mem.good(M.degraded) = 0;
mem.deg_n(M.degraded) = mem.deg_n(M.degraded) + 1; mem.deg_n(~M.degraded) = 0;
mem.tried(mem.good >= HEAL, :) = false;
[~, k] = max(obs.probs, [], 2);
cls = PP.classes(k);
cls(obs.unknown) = {'unknown'};
M.cls = cls(:)';
M.alarm = ~strcmp(M.cls, 'none') | M.degraded;
mem.alarm_n(M.alarm) = mem.alarm_n(M.alarm) + 1; mem.alarm_n(~M.alarm) = 0;
M.confirmed = mem.alarm_n >= CONFIRM;
end
