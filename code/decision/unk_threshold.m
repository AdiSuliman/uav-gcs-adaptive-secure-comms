function thr = unk_threshold(maha_val, retain)
%UNK_THRESHOLD  The unknown-threat threshold that keeps a share retain of the validation
%   windows above it (ood_thresholds.m): maha_val, their sorted statistic (PP.maha_val).
%   Any retention's PP.maha_thr at decision time, the pools unchanged (detector_id.m).
%   thr = unk_threshold(PP, retain)  with FM.unk in PP.fuse (D111, unk_stat.m): U's threshold
%   from FM.unk.val, U on the selection half's known windows (sorted at its fit); retain
%   default PP.unk_retain, 0.95 without it. The monitor and link_env.m compare U with it.
if isstruct(maha_val)
    PP = maha_val;
    assert(unk_stat('on', PP), 'unk_threshold:unk', 'unk_threshold: PP.fuse holds no FM.unk');
    if nargin < 2
        retain = 0.95; if isfield(PP, 'unk_retain') && ~isempty(PP.unk_retain), retain = PP.unk_retain; end
    end
    v = PP.fuse.unk.val;
    thr = v(max(1, ceil((1 - retain) * numel(v))));
    return
end
x = sort(maha_val(:));
thr = x(max(1, ceil((1 - retain) * numel(x))));
end
