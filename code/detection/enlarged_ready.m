function [ok, miss, first] = enlarged_ready(root)
%ENLARGED_READY  Whether the enlarged fit set of the fusion (fit_sets.m) can be built here: the
%   dataset and the second and third test sets (B3n, B3m) exist under root (default '.').
%   miss lists the missing files. first is true when neither data/splits_fresh.mat nor
%   data/splits_fresh2.mat exists: a profile's first B2F, before B3n and B3m, which fits the
%   fusion on validation as before the revision (run_stage.m, main.m; docs/d91_deploy.md,
%   profile 2). With only some of the files present B2F does not fall back: it deploys, and
%   select_fusion.m stops with select_fusion:fit_sets naming the missing ones.
if nargin < 1, root = '.'; end
f = {'data/dataset.mat', 'data/splits_fresh.mat', 'data/dataset_fresh.mat', 'data/splits_fresh2.mat', 'data/dataset_fresh2.mat'};
miss = f(~cellfun(@(x) isfile(fullfile(root, x)), f));
ok = isempty(miss);
first = all(ismember({'data/splits_fresh.mat', 'data/splits_fresh2.mat'}, miss));
end
