function [specs, n] = clean_wide_specs(PP, CT, ebno_thr, T, geo)
%CLEAN_WIDE_SPECS  The clean validation episodes of the false-alarm readings on validation
%   (train_dqn.m, choose_drop_threshold.m): one T-cycle episode per independent clean
%   geometry of CT (clean_world.m, split 2) and Eb/N0 from ebno_thr up, onset at cycle 3, in
%   batches of 64, the last padded cyclically; n the episodes without the padding. Batch b
%   runs with the frame-draw seed 41000 + b (rollout_policy.m, monitor_trace.m), so every
%   reader and every policy flies the same frames. geo (optional): the geometries flown
%   (indices into CT.runs), default all; C1d's choice of the degradation test flies the check
%   half (clean_halves.m).
NE = 64;
ic = find(strcmp(PP.scen, 'none'), 1);
if nargin < 5 || isempty(geo), geo = 1:CT.n_geom; end
[ss, rr] = ndgrid(find(PP.ebno >= ebno_thr), geo(:)'); ss = ss(:)'; rr = rr(:)';
n = numel(ss); nb = ceil(n / NE); pad = nb * NE - n;
k_ = mod(0:n + pad - 1, n) + 1; ss = ss(k_); rr = rr(k_);                     % cyclic padding of the last batch
specs = cell(1, nb);
for b = 1:nb
    i = (b-1)*NE + (1:NE);
    specs{b} = struct('scn', ic * ones(1, NE), 's', ss(i), 'onset', 3 * ones(1, NE), 'follow', false(1, NE), ...
        'fdelay', 2 * ones(1, NE), 'unk', false(1, NE), 'T', T, 'r', rr(i));
end
end
