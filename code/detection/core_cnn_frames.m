function [m, y, info] = core_cnn_frames(S, classes, groups)
%CORE_CNN_FRAMES  The frames of the proposal's three link states in a split: the sub-runs of
%   the clean link, narrowband jamming and wideband jamming, one fixed state per sub-run
%   (proposal, mitigation 2).
%   [m, y, info] = core_cnn_frames(S, classes, groups)
%   S        split with class_run (class index of the frame's sub-run), Y_frame and Y
%   classes  the dataset's class names, in the order Y, Y_frame and class_run index
%   groups   the class of each state (default {'none', 'tone_jamming', 'jamming'})
%   m        frames of those sub-runs whose frame label and per-cycle label are both the
%            sub-run's class (frames x 1 logical)
%   y        state 1..numel(groups) of the frames m
%   info.n_sub  frames of those sub-runs per state; info.n_off those left out (another label)
if nargin < 3 || isempty(groups), groups = {'none', 'tone_jamming', 'jamming'}; end
classes = cellstr(string(classes(:)'));
for f = {'class_run', 'Y_frame', 'Y'}
    assert(isfield(S, f{1}) && ~isempty(S.(f{1})), 'core_cnn_frames:field', ...
        'core_cnn_frames: the split has no %s (rerun run_dataset_sweep, extract_spectrograms, prepare_data)', f{1});
end
assert(isequal(categories(S.Y)', classes) && isequal(categories(S.Y_frame)', classes), 'core_cnn_frames:classes', ...
    'core_cnn_frames: the split''s classes are not %s', strjoin(classes, ', '));
[ok, ic] = ismember(groups, classes);
assert(all(ok), 'core_cnn_frames:class', 'core_cnn_frames: class %s not in the dataset', strjoin(groups(~ok), ', '));
kr = double(S.class_run(:)); yf = double(S.Y_frame(:)); yc = double(S.Y(:));
st = zeros(numel(kr), 1);
for g = 1:numel(groups), st(kr == ic(g)) = g; end
in = st > 0;
lab = zeros(size(st)); lab(in) = ic(st(in));
m = in & yf == lab & yc == lab;
y = st(m);
info = struct('n_sub', accumarray(st(in), 1, [numel(groups) 1])', ...
    'n_off', accumarray(st(in & ~m), 1, [numel(groups) 1])', 'groups', {groups});
end
