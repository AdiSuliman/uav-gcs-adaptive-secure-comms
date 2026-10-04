function [e, cut] = check_point_cut(e, x, vm)
%CHECK_POINT_CUT  An "up to" edge of a fixed-sequence walk (edge_map.m) against the
%   off-grid check points it spans (build_check_pools.m).
%   [e, cut] = check_point_cut(e, x, vm)
%   e    the edge: the value of x where the walk's COMMITTED run ends (NaN: none)
%   x    the walk's points in walk order (Eb/N0 from the top down, levels from the
%        lowest up)
%   vm   verdict of the check point between x(j) and x(j+1) (1 COMMITTED, 0
%        UNDETERMINED, -1 NOT COMMITTED, NaN no check point), numel(x) - 1 values
%   The run spans the check point between x(j) and x(j+1) when it reaches x(j+1); the
%   first one NOT COMMITTED in walk order stops the edge at x(j) (cut true).
cut = false;
J = find(x == e, 1);
if isempty(J), return; end
j = find(vm(1:J-1) == -1, 1);
if ~isempty(j), e = x(j); cut = true; end
end
