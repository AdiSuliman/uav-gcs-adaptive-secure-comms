function [f, f1] = balanced_macro_f1(yt, yp, classes)
%BALANCED_MACRO_F1  Macro-F1 at equal class priors, the prevalence-normalized reading
%   beside KPI 1 (eval_detector.m): every class present among the true labels weighs the
%   same, each frame by one over its class's frame count. With R the row-normalized
%   confusion matrix (rows: true classes), recall is R_cc and precision R_cc / sum_j R_jc,
%   Bayes' rule with the priors 1 / C, so the number of frames of one class (the clean
%   link's) does not weigh on the other classes' precision.
%   yt, yp   true and predicted classes (categorical); classes  class names (order)
%   f        macro-F1 over the present classes; f1  per class (NaN when absent)
cm = confusionmat(yt, yp, 'Order', classes);
pres = sum(cm, 2) > 0;
R = cm(pres, :) ./ sum(cm(pres, :), 2);
rc = nan(numel(classes), 1); pr = rc;
d = diag(cm) ./ max(sum(cm, 2), 1);
rc(pres) = d(pres);
pr(pres) = rc(pres) ./ sum(R(:, pres), 1)';
f1 = 2 * pr .* rc ./ (pr + rc);
f1(pres & isnan(f1)) = 0;
f = mean(f1(pres));
end
