function R = roll_in_false_alarms(P, y_true, y_pred, cycle_s)
%ROLL_IN_FALSE_ALARMS  False alarms of the clean sub-runs while they roll into their turn,
%   beside KPI 1's clean false-alarm rate over every 'none' frame (eval_detector.m).
%   R = roll_in_false_alarms(P, y_true, y_pred, cycle_s)
%   P        split: run, pos (frame position in its run), class_run (class of the frame's
%            sub-run, 1 = none), roll_in (start [s] from the run's first frame and roll rate
%            [deg/s], 0 0 without one) and bank [deg] per frame
%   y_true   target of every frame (categorical); y_pred the class read, the monitor's
%   cycle_s  decision cycle [s]: frame pos lies (pos - 1) cycle_s into its run
%   R        roll_in: the frames of the clean sub-runs inside their roll-in, start <= t <=
%            start + bank / rate; clean: every frame whose target is none. Each with n frames,
%            n_runs sub-runs, and the shares [%] read as any class but none (any_pct), as
%            path_loss (path_loss_pct) and as airframe_shadowing (airframe_shadowing_pct);
%            the shares are NaN when n is 0
t = (double(P.pos(:)) - 1) * cycle_s;
ri = double(P.roll_in);
inside = double(P.class_run(:)) == 1 & ri(:, 2) > 0 & ri(:, 1) <= t & t <= ri(:, 1) + abs(double(P.bank(:))) ./ ri(:, 2);
R = struct('roll_in', shares(inside, y_pred(:), P.run(:)), 'clean', shares(y_true(:) == 'none', y_pred(:), P.run(:)));
end

function s = shares(m, y, run)
y = y(m);
s = struct('n', sum(m), 'n_runs', numel(unique(run(m))), 'any_pct', 100 * mean(y ~= 'none'), ...
    'path_loss_pct', 100 * mean(y == 'path_loss'), 'airframe_shadowing_pct', 100 * mean(y == 'airframe_shadowing'));
end
