function [W, th] = drop_cusum(d, W0, dw, thr)
%DROP_CUSUM  Window-limited CUSUM of a drop of our signal over the thermal floor (the
%   monitor's Eb/N0 estimate less the known gain of the configuration, policy_monitor.m).
%   Page's CUSUM recursion (Xie et al. 2021, eq. 2-3) with the unknown size of the drop
%   estimated from the drops of the last w = C.cusum_win cycles before the current one, the
%   window-limited CUSUM of Xie, Moustakides & Xie 2022 (eq. 6-7): for a Gaussian mean
%   shift the estimate is the window's mean held in the set of changes (their Remark 4).
%   Per cycle, d the cycle's drop against the monitor's reference [dB]:
%       W = min(max(0, W0 + th (d - th / 2)), 2 thr),   th = min(max(mean(dw), D(1)), D(2))
%   the log-likelihood ratio of a mean shift by th times the variance of the estimate, which
%   the threshold absorbs (W in dB^2). The set of changes D is the range of the path-loss
%   levels of the envelope (decision_config.m): a smaller drop is not a change to call, and
%   the statistic does not grow on a drop below half the smallest level (moving away lowers
%   the estimate by about 0.2 dB over 12 cycles, policy_monitor.m); the false alarms of the
%   clean link's other changes are measured on validation (choose_drop_threshold.m).
%   The bound 2 thr makes the end of the alarm (W >= thr) the same test in reverse: below
%   it, 2 thr - W is Page's recursion of the opposite log-likelihood ratio th (th / 2 - d),
%   the return to the reference, and the alarm clears once that reaches thr, the evidence
%   that raised it. Up to its first crossing of thr the statistic is the unbounded one.
%   W = drop_cusum(d)                     d E x n drops over n cycles: W E x n, from 0 and
%   W = drop_cusum(d, thr)                an empty window, unbounded or bounded at 2 thr
%   [W, th] = drop_cusum(d, W0, dw, thr)  one cycle: d, W0 E x 1, dw E x w the drops of the
%                                         w cycles before (NaN: none yet); thr optional
C = decision_config();
D = C.sev.path_loss.levels([1 end]);
if nargin <= 2
    thr = Inf; if nargin == 2, thr = W0; end
    [E, n] = size(d); W = zeros(E, n);
    w0 = zeros(E, 1); dx = nan(E, C.cusum_win);
    for t = 1:n
        W(:, t) = drop_cusum(d(:, t), w0, dx, thr);
        w0 = W(:, t); dx = [dx(:, 2:end), d(:, t)];
    end
    return
end
if nargin < 4, thr = Inf; end
th = min(max(mean(dw, 2, 'omitnan'), D(1)), D(2));
W = min(max(0, W0 + th .* (d - th / 2)), 2 * thr);
end
