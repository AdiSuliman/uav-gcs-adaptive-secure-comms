function [mode, thr] = drop_alarm_form(VAL)
%DROP_ALARM_FORM  Form of the drop alarm chosen on validation (choose_drop_threshold.m), and
%   the threshold it is deployed at, the one it was compared at.
%   VAL(1) the 3-cycle median window ('class_drop'), VAL(2) the window-limited CUSUM
%   ('class_cusum'), each with grid (its thresholds), pick (its most sensitive threshold
%   whose false-alarm bound is admissible; NaN: none), det and delay per threshold.
%   The CUSUM when it has an admissible threshold and detects more than one point more than
%   the median window at its own (or the median window has none), or within one point with
%   a shorter mean delay; otherwise the median window. thr: the chosen form's admissible
%   threshold (the median window without one: NaN, its threshold then the train pools').
mode = 'class_drop'; thr = NaN;
j = VAL(1).pick; k = VAL(2).pick;
if ~isnan(j), thr = VAL(1).grid(j); end
if isnan(k), return; end
dm = -Inf; if ~isnan(j), dm = VAL(1).det(j); end
dc = VAL(2).det(k);
if dc > dm + 0.01 || (~isnan(j) && abs(dc - dm) <= 0.01 && VAL(2).delay(k) < VAL(1).delay(j))
    mode = 'class_cusum'; thr = VAL(2).grid(k);
end
end
