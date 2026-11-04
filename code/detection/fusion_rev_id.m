function id = fusion_rev_id(fit, P)
%FUSION_REV_ID  The id select_fusion.m stores in data/fusion.mat (fusion_rev) for the revised
%   selection (FUSION_REV), fitted on validation ('validation') or on the enlarged fit set
%   ('enlarged', FUSION_FIT, fit_sets.m). B3r reads the fourth test set only with
%   fusion_rev_id('enlarged'), the revision its go/no-go adopts (docs/d91_set4.md). When the pick
%   names a candidate over the d91 design (fusion_pick.m P.ext), the id carries it.
%   id = fusion_rev_id(fit, P)  the id of pick P (default fusion_pick())
assert(ismember(fit, {'validation', 'enlarged'}), 'fusion_rev_id:fit', 'unknown fit set %s', fit);
id = ['d91_branch_evidence_' fit];
if nargin < 2, P = fusion_pick(); end
if isfield(P, 'ext'), id = [id '_' lower(strrep(P.ext.pick, '+', '_'))]; end
end
