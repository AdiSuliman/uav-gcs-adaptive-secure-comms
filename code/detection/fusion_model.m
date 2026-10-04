function FZ = fusion_model()
%FUSION_MODEL  The deployed temporal fusion (data/fusion.mat, select_fusion.m): FM, N
%   and the quiet-slot interference alarm q_thr of the rule (rule_based_policy.m).
%   Without the file: no fusion (FM empty, N 1) and q_thr NaN (the rule's default).
FZ = struct('FM', [], 'N', 1, 'q_thr', NaN);
if ~isfile('data/fusion.mat'), return; end
L = load('data/fusion.mat');
FZ.FM = L.FM; FZ.N = L.N;
if isfield(L, 'q_thr'), FZ.q_thr = L.q_thr; end
end
