function c = surv_cell_label(status, code, nok, lim, sat, com)
%SURV_CELL_LABEL  One cell of the survivability map's text under surv_v2 (surv_report.m):
%   the status letter R, M or X (L for a recoverable cell where the clean link itself loses
%   half of its packets or more, lim), then the letters code of the configuration achieving
%   it, N when no_action already passes (nok: not degraded), or none when every configuration
%   is saturated (sat); ? when the cell is not committed (com false). '.' for no status.
if ~ismember(status, 1:3), c = '.'; return; end
c = 'RMX'; c = c(status);
if status == 1 && lim, c = 'L'; end
if sat, c = [c 'none'];
elseif nok, c = [c 'N'];
else, c = [c code];
end
if ~com, c = [c '?']; end
end
