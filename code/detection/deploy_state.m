function [st, txt] = deploy_state()
%DEPLOY_STATE  The fusion of this worktree after its deploy B2F (docs/d91_deploy.md section 5: the
%   check before a profile's C1p hold is removed or its chain resumes). Run from the repository
%   root; reads data/fusion.mat and data/fusion_nogo.mat only.
%   st   'deployed'  data/fusion.mat holds fusion_rev_id('enlarged'), FM.cues of fusion_pick.m and
%                    deployed_pick equal to fusion_pick() with its rule check and the kept base
%                    (check.kept), and the rule held
%        'nogo'      a no-go record of fusion_pick() names the fusion on disk (fusion_nogo('check'))
%        'none'      neither: the old fusion without a record, a validation-fit revision, a save
%                    cut short before its revision record, or a rule printed but not held (the
%                    smoke's FUSION_RULE_LOG); the hold stays
%   txt  one line, also printed: 'DEPLOY_STATE <st>: <details>'
fk = 'data/fusion.mat';
st = 'none'; why = 'no data/fusion.mat';
if isfile(fk)
    f = {whos('-file', fk).name};
    rev = '';
    if ismember('fusion_rev', f), r = load(fk, 'fusion_rev'); if ischar(r.fusion_rev), rev = r.fusion_rev; end, end
    why = sprintf('fusion_rev ''%s''', rev);
    P = fusion_pick();
    if strcmp(rev, fusion_rev_id('enlarged')) && all(ismember({'deployed_pick', 'FM'}, f))
        L = load(fk, 'deployed_pick', 'FM'); dp = L.deployed_pick;
        if isstruct(dp) && isfield(dp, 'check') && isstruct(dp.check) && isfield(dp.check, 'kept') && ...
                isequal(rmfield(dp, 'check'), P) && isstruct(L.FM) && isfield(L.FM, 'cues') && isequal(L.FM.cues, P.cues)
            k = dp.check.kept;
            why = sprintf('%s, deployed_pick ''%s'' with its rule check, kept base N %d, lambda %g, latch %d', ...
                why, dp.name, k.N, k.lambda, k.latch);
            if isfield(dp.check, 'rule_logged_only') && isequal(dp.check.rule_logged_only, true)
                why = [why ', but the rule failed and was only printed (FUSION_RULE_LOG)'];
            else
                st = 'deployed';
            end
        else
            why = [why ', deployed_pick, its check or FM.cues not fusion_pick.m''s'];
        end
    elseif fusion_nogo('check')
        st = 'nogo';
        N = load('data/fusion_nogo.mat', 'nogo');
        why = sprintf('%s, the no-go record (%s, %s) names the kept fusion', why, N.nogo.why, N.nogo.time);
    else
        why = [why ', no deployed_pick of fusion_pick.m and no no-go record naming this fusion'];
    end
end
txt = sprintf('DEPLOY_STATE %s: %s', st, why);
fprintf('%s\n', txt);
end
