function on = fa_nothreat_on(cfg, f)
%FA_NOTHREAT_ON  Whether C2 also trains the no-threat form of the false-switch penalty
%   (train_dqn.m section 7, fa_form_train.m): CFG.fa_nothreat when cfg is a struct with that
%   field, else the field fa_nothreat of this checkout's profile.json (f, default
%   'profile.json'), else false. Its runs are scored on validation beside their grid runs and
%   never enter the selection. Only true or false is accepted.
if nargin < 1, cfg = []; end
if nargin < 2 || isempty(f), f = 'profile.json'; end
on = false; v = []; src = '';
if isstruct(cfg) && isfield(cfg, 'fa_nothreat')
    v = cfg.fa_nothreat; src = 'CFG.fa_nothreat';
elseif isfile(f)
    P = jsondecode(fileread(f));
    if isstruct(P) && isfield(P, 'fa_nothreat'), v = P.fa_nothreat; src = [f ': fa_nothreat']; end
end
if isempty(src), return; end
if ~(isscalar(v) && islogical(v)), error('fa_nothreat_on:value', '%s must be true or false', src); end
on = v;
end
