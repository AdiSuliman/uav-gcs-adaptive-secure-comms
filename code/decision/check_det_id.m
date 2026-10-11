function check_det_id(PP, Q, who, what)
%CHECK_DET_ID  Stop when what is read together comes from another detector or link model
%   than the pools PP being read: the agent of data/trained_dqn.mat (Q, the default what)
%   learned on frame pools of another detector (det_id, detector_id.m), so its policy would
%   be measured on detector outputs it never saw; or a pool file (what, e.g.
%   'data/clean_test_pools.mat') holds frames of another detector, or of another link
%   model (model_tag, build_policy_pools.m, when both carry one).
if nargin < 4 || isempty(what), what = 'the agent of data/trained_dqn.mat'; end
stage = 'C1c'; if contains(what, 'trained_dqn'), stage = 'C2'; end
if ~isfield(Q, 'det_id') || ~isfield(PP, 'det_id') || ~strcmp(Q.det_id, PP.det_id)
    error('check_det_id:mismatch', ['%s: %s and these pools come from different ' ...
        'detectors (det_id); rerun %s'], who, what, stage);
end
if isfield(Q, 'model_tag') && isfield(PP, 'model_tag') && ~strcmp(Q.model_tag, PP.model_tag)
    error('check_det_id:model', '%s: %s and these pools come from different link models (model_tag %s, %s); rerun %s', ...
        who, what, Q.model_tag, PP.model_tag, stage);
end
end
