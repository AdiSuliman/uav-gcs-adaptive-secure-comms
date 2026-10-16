function [W, th] = drop_cusum(d, W0, dw)
%DROP_CUSUM  Window-limited CUSUM of a drop of our signal over the thermal floor (the
%   monitor's Eb/N0 estimate less the known gain of the configuration, policy_monitor.m).
%   Page's CUSUM recursion (Xie et al. 2021, eq. 2-3) with the unknown size of the drop
%   estimated from the drops of the last w = C.cusum_win cycles before the current one, the
%   window-limited CUSUM of Xie, Moustakides & Xie 2022 (eq. 6-7): for a Gaussian mean
%   shift the estimate is the window's mean held in the set of changes (their Remark 4).
%   Per cycle, d the cycle's drop against the monitor's reference [dB]:
%       W = max(0, W0 + th (d - th / 2)),   th = min(max(mean(dw), D(1)), D(2))
%   the log-likelihood ratio of a mean shift by th times the variance of the estimate, which
%   the threshold absorbs (W in dB^2). The set of changes D is the range of the path-loss
%   levels of the envelope (decision_config.m): a smaller drop is not a change to call, and
%   the statistic does not grow on a drop below half the smallest level (moving away lowers
%   the estimate by about 0.2 dB over 12 cycles, policy_monitor.m); the false alarms of the
%   clean link's other changes are measured on validation (choose_drop_threshold.m).
%   W = drop_cusum(d)                d E x n drops over n cycles: W E x n, from 0 and an
%                                    empty window
%   [W, th] = drop_cusum(d, W0, dw)  one cycle: d, W0 E x 1, dw E x w the drops of the w
%                                    cycles before (NaN: none yet)
C = decision_config();
D = C.sev.path_loss.levels([1 end]);
if nargin == 1
    [E, n] = size(d); W = zeros(E, n);
    w0 = zeros(E, 1); dx = nan(E, C.cusum_win);
    for t = 1:n
        W(:, t) = drop_cusum(d(:, t), w0, dx);
        w0 = W(:, t); dx = [dx(:, 2:end), d(:, t)];
    end
    return
end
th = min(max(mean(dw, 2, 'omitnan'), D(1)), D(2));
W = max(0, W0 + th .* (d - th / 2));
end
