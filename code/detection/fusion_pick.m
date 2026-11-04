function P = fusion_pick(ext)
%FUSION_PICK  The fusion design the d91 measurement adopted on the enlarged fit set
%   (docs/d91_fuse.md, sections 4, 5, 8 and 12), which select_fusion.m deploys with FUSION_REV
%   and FUSION_FIT = 'enlarged' without choosing again.
%   P.name        the variant: 'branch evidence, phi = 1' (phi not kept on either profile,
%                 phi = 1 passes the adoption rule on both, section 12)
%   P.cues        its further columns (window_cues.m 'extra'), no cfar; phi1: phi fixed at 1
%   P.N, P.lambda the window and regularization it was measured at
%   P.target_age  'N': the deployed target rule, pos - onset < N (fusion_target.m)
%   P.latch       false: the onset latch is off, the state it was measured in (m_all.m)
%   P.source      where the verdict is recorded
%   P.ext         only when EXT names one: the candidate over this design that m_head.m's
%                 verdict adopted ('LBH', 'GCC', 'CFAR', 'LBH+CFAR' or 'GCC+CFAR'; fusion_cand.m).
%                 B2F re-checks it against this design on its own fit set and deploys this
%                 design alone when it fails (select_fusion.m, fusion_recheck.m); EXT is then
%                 set back to '' before B3r and C1p, as the record names this design
%   P = fusion_pick(ext)  the same with ext in place of EXT (the smoke's forced cell, tests)
EXT = '';                                               % D110's verdict; '' when m_head.m adopts nothing or B2F falls back
if nargin >= 1, EXT = ext; end
P = struct('name', 'branch evidence, phi = 1', ...
    'cues', struct('cfar', [], 'iso', true, 'glr', true, 'held', true, 'post', true, 'phi1', true), ...
    'N', 12, 'lambda', 1e-3, 'target_age', 'N', 'latch', false, ...
    'source', 'docs/d91_fuse.md, sections 5 and 12 (m_p1.log, m_p3.log, m_phi_both.txt)');
if ~isempty(EXT)
    assert(ismember(EXT, fusion_cand('names')), 'fusion_pick:ext', 'unknown candidate %s', EXT);
    P.ext = struct('pick', EXT, 'source', 'docs/DECISIONS.md, the verdict of m_head.m');
end
end
