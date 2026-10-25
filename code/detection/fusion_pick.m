function P = fusion_pick()
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
P = struct('name', 'branch evidence, phi = 1', ...
    'cues', struct('cfar', [], 'iso', true, 'glr', true, 'held', true, 'post', true, 'phi1', true), ...
    'N', 12, 'lambda', 1e-3, 'target_age', 'N', 'latch', false, ...
    'source', 'docs/d91_fuse.md, sections 5 and 12 (m_p1.log, m_p3.log, m_phi_both.txt)');
end
