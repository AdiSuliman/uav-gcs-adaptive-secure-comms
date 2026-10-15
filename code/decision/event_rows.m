function k = event_rows(Q, runs, ev)
%EVENT_ROWS  Rows of a pool that a cell's per-flight statistics read.
%   k = event_rows(Q, runs, ev): Q a pool (pool_cell.m: run per row, the frames of a run
%   in order), runs the split's geometry ids (PP.runs{sp}), ev the run frame at which the
%   airframe enters the line of sight on each of them (PP.event_frame{sp}; NaN: none).
%   A flight that rolls into its turn (decision_config.m C.event_frame) is read from that
%   frame on, the frames its episodes take after their onset (link_env.m); every other
%   flight on all its frames. k is a logical column over the rows of Q.
k = true(numel(Q.run), 1);
if nargin < 3 || isempty(ev) || all(~isfinite(ev)), return; end
for r = find(isfinite(ev(:)'))
    i = find(Q.run == runs(r));
    k(i(1:min(ev(r) - 1, numel(i)))) = false;
end
end
