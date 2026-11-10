function PB = drop_path_pick(Tf, form, GF, cf, cs, bound, tau)
%DROP_PATH_PICK  D121 item 4: the drop threshold by the drop path's own false-alarm budget, for a
%   monitor whose whole-monitor rule finds no admissible threshold (choose_drop_threshold.m).
%   Tf     monitor_trace.m of the clean episodes of D103's fit half (clean_halves.m)
%   form   drop alarm form ('class_drop', 'class_cusum'); GF the grid, least sensitive last
%   cf     the monitor's confirmation [m n]; cs the sweeper's ([] none)
%   bound  the share of KPI 6's 5% (0.02; 0.014 in the 3.5% side calibration)
%   tau    the monitor's lost-branch acceptance tau_hi ([] or absent: none)
%   From GF(end) toward GF(1), stopping at the first failure, keep the last value whose clean
%   episodes first confirmed by the drop alarm have a one-sided 95% Clopper-Pearson upper bound
%   <= bound. An episode counts when the monitor without the drop alarm (threshold Inf, so with
%   tau the drop alarm is no harm evidence either) does not confirm at its first confirmed cycle
%   (D112 (c'), D121 dated reading (ii)). PB.admissible false: no value passes and the caller
%   keeps the least sensitive.
%   PB: admissible, pick, j, k (the count at pick), n (episodes of Tf), bound (its upper bound)
if nargin < 7, tau = []; end
n = size(Tf.eg, 1);
c0 = monitor_confirm(Tf, form, Inf, cf, cs, [], tau);
PB = struct('admissible', false, 'pick', NaN, 'j', NaN, 'k', NaN, 'n', n, 'bound', NaN);
for j = numel(GF):-1:1
    k = drop_first_count(Tf, form, GF(j), cf, cs, tau, c0);
    up = cp_upper(k, n);
    if ~(up <= bound), break; end
    PB = struct('admissible', true, 'pick', GF(j), 'j', j, 'k', k, 'n', n, 'bound', up);
end
end

function k = drop_first_count(T, form, thr, cf, cs, tau, c0)
% Clean episodes whose first confirmed cycle the monitor without the drop alarm (c0) does not confirm.
c = monitor_confirm(T, form, thr, cf, cs, [], tau);
[f, t1] = max(c, [], 2);
i1 = find(f);
k = sum(~c0(sub2ind(size(c), i1, t1(i1))));
end

function u = cp_upper(k, n)
% One-sided 95% Clopper-Pearson upper bound of a binomial proportion (NaN without trials).
if n == 0, u = NaN; elseif k >= n, u = 1; else, u = betaincinv(0.95, k + 1, n - k); end
end
