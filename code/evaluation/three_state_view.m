function V = three_state_view(cm, classes, groups, names)
%THREE_STATE_VIEW  The detector's confusion matrix read as the proposal's three link states.
%   V = three_state_view(cm, classes): cm (classes x classes, rows the true class, columns the
%   detector's class, eval_detector.m metrics.conf_mat), classes its class names. The rows
%   are only the frames of the three states' classes: clean (none), narrowband jamming
%   (tone_jamming) and wideband jamming (jamming, the barrage noise jammer); a frame read as
%   any other class is an error of its state ('other' column), never a hit.
%   groups, names  optional: the classes of each state and the states' names.
%   V.cm      3 x 4 frames: rows the true state, columns the three states and 'other'
%   V.recall, V.precision, V.f1  per state (precision over the three states' frames);
%   V.macro_f1 their mean; V.n frames per state. Fractions.
if nargin < 3 || isempty(groups), groups = {{'none'}, {'tone_jamming'}, {'jamming'}}; end
if nargin < 4 || isempty(names), names = {'clean', 'narrowband jamming', 'wideband jamming'}; end
classes = cellstr(string(classes(:)'));
nG = numel(groups);
g = zeros(1, numel(classes));                         % state of every class, 0 none of them
for k = 1:nG
    [hit, j] = ismember(groups{k}, classes);
    if ~all(hit)
        error('three_state_view:class', 'three_state_view: class %s not among the detector''s classes', ...
            strjoin(groups{k}(~hit), ', '));
    end
    g(j) = k;
end
V.names = names; V.groups = groups;
V.cm = zeros(nG, nG + 1);
for a = 1:nG
    r = sum(cm(g == a, :), 1);
    for b = 1:nG, V.cm(a, b) = sum(r(g == b)); end
    V.cm(a, nG + 1) = sum(r(g == 0));
end
V.n = sum(V.cm, 2)';
tp = diag(V.cm(:, 1:nG))';
V.recall = tp ./ V.n;
V.precision = tp ./ sum(V.cm(:, 1:nG), 1);
V.f1 = 2 * V.precision .* V.recall ./ (V.precision + V.recall);
V.f1(tp == 0 & V.n > 0) = 0;
V.macro_f1 = mean(V.f1, 'omitnan');
end
