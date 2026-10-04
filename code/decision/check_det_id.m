function check_det_id(PP, Q, who)
%CHECK_DET_ID  Stop when the agent of data/trained_dqn.mat (Q) learned on frame pools of
%   another detector than the pools PP being read (det_id, detector_id.m): its policy
%   would be measured on detector outputs it never saw.
if ~isfield(Q, 'det_id') || ~isfield(PP, 'det_id') || ~strcmp(Q.det_id, PP.det_id)
    error('check_det_id:mismatch', ['%s: the agent of data/trained_dqn.mat and these pools come from different ' ...
        'detectors (det_id); rerun C2'], who);
end
end
