function s = kpi1_set()
%KPI1_SET  The test set KPI 1 is read on, the one switch for every reader (kpi1_file.m) and
%   for the fourth test set's single reading (eval_detector.m, stage B3r):
%   'fresh2'  the third test set (B3m), results/<stem>_fresh2.mat
%   'fresh3'  the fourth test set (B3q, docs/d91_set4.md): set only when the fusion revision
%             is adopted at its go/no-go, in the same commit that deploys it; B3r then reads
%             the set once, and no reader falls back to an earlier set
s = 'fresh2';
end
