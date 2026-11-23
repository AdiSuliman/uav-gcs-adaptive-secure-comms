function [runs, ebs, note] = capture_gui_plan(lv, threats, core)
%CAPTURE_GUI_PLAN  The live runs of capture_gui.m: clean at the middle and the top Eb/N0 level, then
%   narrowband, wideband, lost branch and airframe shadowing at the middle level (a threat the
%   console does not list is left out). note says whether the three-state CNN is in the bundle.
e4 = lv(find(lv == 4, 1)); if isempty(e4), e4 = lv(ceil(end / 2)); end
cleanE = unique([e4, max(lv)], 'stable');
att = {'tone_jamming', 'jamming', 'antenna_fault', 'airframe_shadowing'};
att = att(ismember(att, threats));
runs = [repmat({'none'}, 1, numel(cleanE)), att];
ebs = [cleanE, repmat(e4, 1, numel(att))];
if isempty(core)
    note = 'three-state CNN not in this bundle (data/core_cnn_model.mat): the three-state lines stay empty';
else
    note = 'three-state CNN in this bundle';
end
end
