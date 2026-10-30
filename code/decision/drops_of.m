function d = drops_of(mon, MONP, drop_mode, drop_db, THC, steps, floor_db)
%DROPS_OF  C2's drop thresholds of one monitor (train_dqn.m): its own from choose_drop_threshold.m
%   (MONP; the form's alone when the file has none) and the steps around it: the median window that
%   less the steps [dB] above the moving-away floor, the CUSUM one grid step per step's sign. The CUSUM
%   grid is the monitor's own (MONP.grid) when C1d chose the drop alarm's own confirmation for it
%   (dconf_step.m), else THC.
b = drop_db; G = THC;
if ~isempty(MONP)
    k = find(strcmp({MONP.monitor}, mon), 1);
    if ~isempty(k) && isfinite(MONP(k).pick), b = MONP(k).pick; end
    if ~isempty(k) && isfield(MONP, 'grid') && ~isempty(MONP(k).grid), G = MONP(k).grid; end
end
if isempty(b), d = NaN; return; end
if strcmp(drop_mode, 'class_cusum')
    [~, j] = min(abs(G - b));
    d = unique(G(min(max(j - sign(steps), 1), numel(G))), 'stable');
else
    d = b - steps; d = d(d > floor_db);
end
if isempty(d), d = NaN; end
end
