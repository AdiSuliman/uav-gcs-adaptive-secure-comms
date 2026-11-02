function core3_check(PP, where, f)
%CORE3_CHECK  Refuses to fly rule_core3 when the three-state model file is no longer the one the pools were
%   scored with (D121 item 16, P-B; D106's refusal of a model whose hash is another).
%   core3_check(PP, where, f)
%   PP.core3_id is the id (SHA-256 of the file and its window N) recorded at C1p; the file f (default
%   core3_model.m's) must give the same id, else an error 'core3_check:model' naming where. Called by
%   evaluate_policies.m only when the pools hold the scores.
if nargin < 3, f = []; end
assert(isfield(PP, 'core3_id') && ~isempty(PP.core3_id), 'core3_check:model', ...
    '%s: the pools hold no three-state model id (PP.core3_id)', where);
[M, why] = core3_model(f);
assert(~isempty(M), 'core3_check:model', '%s: rule_core3 refused, the three-state model recorded at C1p (%s) is not usable now: %s', ...
    where, PP.core3_id, why);
assert(strcmp(M.id, PP.core3_id), 'core3_check:model', ...
    '%s: rule_core3 refused, the three-state model file is another than the one the pools were scored with (now %s, C1p recorded %s)', ...
    where, M.id, PP.core3_id);
end
