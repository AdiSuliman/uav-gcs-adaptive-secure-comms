function T = compare_weak_points(files, names)
%COMPARE_WEAK_POINTS  The weak-point cells of several profiles side by side.
%   T = compare_weak_points(files, names)
%   files  cell of results/weak_points.json paths (analyze_weak_points.m), one per profile
%   names  their labels (default P1, P2, ...)
%   T      one row per (section, factor, cell) present in any file: the value [%] and the
%          units of every profile (NaN where a profile lacks the cell) and each profile's
%          difference to the first. Without an output it is printed and saved as
%          results/weak_points_profiles.csv.
if nargin < 2 || isempty(names), names = compose('P%d', 1:numel(files)); end
names = matlab.lang.makeValidName(names);
key = {}; val = []; cnt = [];
for i = 1:numel(files)
    J = jsondecode(fileread(files{i}));
    S = sections(J, '');
    for k = 1:size(S, 1)
        W = S{k, 2};
        fn = fieldnames(W.factors);
        for f = 1:numel(fn)
            Fz = W.factors.(fn{f});
            c = cellstr(Fz.cell);
            for j = 1:numel(c)
                kk = sprintf('%s|%s|%s', S{k, 1}, fn{f}, c{j});
                r = find(strcmp(key, kk), 1);
                if isempty(r)
                    key{end+1, 1} = kk; val(end+1, :) = NaN; cnt(end+1, :) = NaN; r = numel(key); %#ok<AGROW>
                end
                val(r, i) = Fz.value(j); cnt(r, i) = Fz.n(j); %#ok<AGROW>
            end
        end
    end
    val(:, end+1:numel(files)) = NaN; cnt(:, end+1:numel(files)) = NaN; %#ok<AGROW>
end
parts = split(string(key), '|');
if size(parts, 2) == 1, parts = reshape(parts, 1, []); end
T = table(parts(:, 1), parts(:, 2), parts(:, 3), 'VariableNames', {'section', 'factor', 'cell'});
for i = 1:numel(files)
    T.(['value_' names{i}]) = val(:, i);
    T.(['n_' names{i}]) = cnt(:, i);
    if i > 1, T.(['diff_' names{i}]) = val(:, i) - val(:, 1); end
end
if nargout == 0
    disp(T);
    if ~exist('results', 'dir'), mkdir('results'); end
    writetable(T, 'results/weak_points_profiles.csv');
    fprintf('Saved results/weak_points_profiles.csv\n');
end
end

function S = sections(J, pre)
% Every breakdown (a struct with factors) in J, with its path.
S = cell(0, 2);
if isfield(J, 'factors'), S(end+1, :) = {pre, J}; return; end
fn = fieldnames(J);
for k = 1:numel(fn)
    if isstruct(J.(fn{k})) && isscalar(J.(fn{k}))
        p = fn{k}; if ~isempty(pre), p = [pre '.' fn{k}]; end
        S = [S; sections(J.(fn{k}), p)]; %#ok<AGROW>
    end
end
end
