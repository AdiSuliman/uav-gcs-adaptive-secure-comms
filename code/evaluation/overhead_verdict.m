function [v, lt, ll] = overhead_verdict(drops, read, lvs, commit, nr)
%OVERHEAD_VERDICT  Commitment of the pass over the GCS at one altitude, distance and speed
%   band (edge_map.m, overhead_pass.m).
%   drops   the pass's drop with the tracked and with the tracker-lost bound [dB], 1 x 2
%   read    whether the drop the link monitor reads along the pass reaches the deployed
%           drop threshold, for each bound (1 x 2 logical)
%   lvs     the path-loss levels, ascending; commit the deployed policy's path_loss
%           commitment at each (edge_verdict.m: 1, -1, 0); nr the no-response PROT verdict
%           at each
%   A bound reads the commitment at the smallest level at or above its drop when the drop
%   is read; when it is not, the policy sees no drop and the link is as without a
%   response: COMMITTED when the no-response PROT is there, UNDETERMINED otherwise. NaN
%   beyond the top level (not measured).
%   v   COMMITTED (1) when both bounds are, NOT COMMITTED (-1) when the tracked bound is,
%       UNDETERMINED (0) otherwise (also NaN bounds); lt, ll the levels read (NaN beyond)
[vt, lt] = bound(drops(1), read(1), lvs, commit, nr);
[vl, ll] = bound(drops(2), read(2), lvs, commit, nr);
if vt == 1 && vl == 1, v = 1; elseif vt == -1, v = -1; else, v = 0; end
end

function [v, lv] = bound(drop, read, lvs, commit, nr)
k = find(lvs >= drop, 1);
if isempty(k), v = NaN; lv = NaN; return; end
lv = lvs(k); v = commit(k);
if ~read, v = double(nr(k) == 1); end
end
