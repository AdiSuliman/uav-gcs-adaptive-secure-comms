function [nm, classes] = split_norm(file)
%SPLIT_NORM  The training z-score (feat_mean, feat_std, feat_names) and the classes of the
%   detector's dataset split, read without the splits themselves: the top-level variables
%   norm and classes of data/splits.mat (prepare_data.m), or the struct splits of a file
%   that has none (read whole).
if nargin < 1, file = 'data/splits.mat'; end
v = who('-file', file);
if all(ismember({'norm', 'classes'}, v))
    S = load(file, 'norm', 'classes'); nm = S.norm; classes = S.classes;
else
    S = load(file, 'splits'); nm = S.splits.norm; classes = S.splits.classes;
end
end
