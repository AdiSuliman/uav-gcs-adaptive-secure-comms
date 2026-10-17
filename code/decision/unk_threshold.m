function thr = unk_threshold(maha_val, retain)
%UNK_THRESHOLD  The unknown-threat threshold that keeps a share retain of the validation
%   windows above it (ood_thresholds.m): maha_val, their sorted statistic (PP.maha_val).
%   Any retention's PP.maha_thr at decision time, the pools unchanged (detector_id.m).
x = sort(maha_val(:));
thr = x(max(1, ceil((1 - retain) * numel(x))));
end
