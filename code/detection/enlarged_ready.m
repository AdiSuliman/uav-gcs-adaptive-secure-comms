function [ok, miss] = enlarged_ready(root)
%ENLARGED_READY  Whether the enlarged fit set of the fusion (fit_sets.m) can be built here: the
%   dataset and the second and third test sets (B3n, B3m) exist under root (default '.').
%   miss lists the missing files. B2F deploys the measured design only then; a profile's first
%   B2F, before B3n and B3m, fits the fusion on validation as before the revision
%   (run_stage.m, main.m; docs/d91_deploy.md, profile 2).
if nargin < 1, root = '.'; end
f = {'data/dataset.mat', 'data/splits_fresh.mat', 'data/dataset_fresh.mat', 'data/splits_fresh2.mat', 'data/dataset_fresh2.mat'};
miss = f(~cellfun(@(x) isfile(fullfile(root, x)), f));
ok = isempty(miss);
end
