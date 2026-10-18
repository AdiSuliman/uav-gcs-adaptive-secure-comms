function P = fusion_pick()
%FUSION_PICK  The fusion design the d91 measurement adopted on the enlarged fit set
%   (docs/d91_fuse.md, sections 4, 5 and 8), which select_fusion.m deploys with FUSION_REV and
%   FUSION_FIT = 'enlarged' without choosing again.
%   P.name        the variant ('branch evidence' or 'branch evidence, phi = 1')
%   P.cues        its further columns (window_cues.m 'extra'), no cfar
%   P.N, P.lambda the window and regularization it was measured at
%   P.target_age  'N': the deployed target rule, pos - onset < N (fusion_target.m)
%   P.latch       false: the onset latch is off, the state it was measured in (m_all.m)
%   P.source      where the verdict is recorded
P = struct('name', 'branch evidence', 'cues', struct('cfar', [], 'iso', true, 'glr', true, 'held', true, 'post', true), ...
    'N', 12, 'lambda', 1e-3, 'target_age', 'N', 'latch', false, 'source', 'docs/d91_fuse.md, section 5 (m_p1.log, m_p3.log)');
end
