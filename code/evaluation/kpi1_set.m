function s = kpi1_set()
%KPI1_SET  The test set KPI 1 is read on, the one switch for every reader (kpi1_file.m) and
%   for the fourth test set's single reading (eval_detector.m, stage B3r):
%   'fresh2'  the third test set (B3m), results/<stem>_fresh2.mat
%   'fresh3'  the fourth test set (B3q, docs/d91_set4.md), set by the commit that deploys the
%             fusion revision (docs/d91_deploy.md); B3r reads the set once, with the deployed
%             revision or, after a no-go on the profile, with the kept fusion (fusion_nogo.m),
%             and no reader falls back to an earlier set
s = 'fresh3';
end
