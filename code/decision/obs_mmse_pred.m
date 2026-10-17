function g = obs_mmse_pred(obs, NE)
%OBS_MMSE_PRED  The predicted MMSE gain over MRC of a cycle's observation (NE x 1, dB):
%   obs.mmse_pred (mmse_predict.m: from the frame's known symbols), NaN where the
%   observation carries none.
g = nan(NE, 1);
if isfield(obs, 'mmse_pred') && ~isempty(obs.mmse_pred), g(:) = double(obs.mmse_pred(:)); end
end
